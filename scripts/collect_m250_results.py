#!/usr/bin/env python3
"""
collect_m250_results.py
=======================
Collects autoCAS M=250 results from log files and writes THREE clean
output JSON files — one per spin category — ready for:
  - Energy convergence testing
  - QICAS benchmark comparison
  - Active space analysis

Output files:
  results_high_spin.json
  results_medium_spin.json
  results_low_spin.json

Usage:
    python3 collect_m250_results.py
    python3 collect_m250_results.py --log_dir /scratch/.../m250_logs
"""

import json, re, glob, argparse
from pathlib import Path

SCRIPTS_DIR = Path(__file__).parent
LOG_DIR_DEFAULT = Path("/scratch/hpc-prf-qehpc/hpcmual/autocas_scratch/m250_logs")
RESULTS_DIR = SCRIPTS_DIR / "autocas_m250_results"

# ── Reference data from JSONs ──────────────────────────────────────────────
def load_reference():
    ref = {}
    for spin_cat, fname in [
        ('high',   'high_spin_15.json'),
        ('medium', 'medium_spin_20.json'),
        ('low',    'low_spin_15.json'),
    ]:
        fpath = SCRIPTS_DIR / fname
        if not fpath.exists():
            continue
        with open(fpath) as f:
            data = json.load(f)
        for s in data['systems']:
            ref[s['system_id']] = {
                'spin_category':    spin_cat,
                'metal':            s['metal'],
                'ligand':           s['ligand'],
                'total_charge':     s['total_charge'],
                'spin_2S':          s['spin_2S'],
                'multiplicity':     s['multiplicity'],
                'geometry':         s['geometry'],
                'metal_row':        s.get('metal_row', '?'),
                'is_csd':           s['is_csd_geometry'],
                # CASSCF reference
                'ref_n_active_e':   s['n_active_electrons'],
                'ref_n_active_orb': s['n_active_orbitals'],
                'ref_E_HF_Eh':      s['E_HF_Eh'],
                'ref_E_CASSCF_Eh':  s['E_CASSCF_Eh'],
                'ref_NOONs':        s.get('natural_orbital_occupations', []),
                'autocas_hint':     s.get('autocas_run_hint', ''),
            }
    return ref

# ── Parse one log file ─────────────────────────────────────────────────────
def parse_log(log_path):
    """Extract final_occupation, final_energy, runtime from a log file."""
    txt = Path(log_path).read_text(errors='replace')

    result = {
        'log_file':    str(log_path),
        'status':      'unknown',
        'occupation':  None,
        'orbital_idx': None,
        'energy_Ha':   None,
        'runtime_s':   None,
        'error_msg':   None,
    }

    # Final occupation
    m = re.search(r'final_occupation:\s*\n\s*(\[[\d,\s]+\])', txt)
    if m:
        result['occupation'] = eval(m.group(1))

    # Final orbital indices
    m = re.search(r'final_orbital_indices:\s*\n\s*(\[[\d,\s]+\])', txt)
    if m:
        result['orbital_idx'] = eval(m.group(1))

    # Final energy
    m = re.search(r'final_energy:\s*\n\s*(\[[-\d.,\s]+\])', txt)
    if m:
        result['energy_Ha'] = eval(m.group(1))[0]

    # Runtime
    m = re.search(r'completed in ([\d.]+)s', txt)
    if m:
        result['runtime_s'] = float(m.group(1))

    # Error
    m = re.search(r'\[error\] .+', txt)
    if m:
        result['error_msg'] = m.group(0)[8:120]

    # Status
    if result['occupation'] is not None:
        occ = result['occupation']
        ne  = sum(occ)
        no  = len(occ)
        result['autocas_ne'] = round(ne)
        result['autocas_no'] = no
        # Parity check
        spin_ref = None  # will be set after merging with ref
        result['status'] = 'done'
    elif result['error_msg']:
        result['status'] = 'failed'
    elif 'Finished:' in txt:
        result['status'] = 'done_no_result'
    else:
        result['status'] = 'running'

    return result

# ── Main ───────────────────────────────────────────────────────────────────
def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--log_dir', default=str(LOG_DIR_DEFAULT))
    args = parser.parse_args()
    log_dir = Path(args.log_dir)

    ref = load_reference()
    print(f"Reference systems loaded: {len(ref)}")
    print(f"Log directory: {log_dir}")
    print()

    # Collect results per spin category
    output = {'high': [], 'medium': [], 'low': []}

    for sys_id, r in ref.items():
        spin_cat = r['spin_category']

        # Find latest log for this system
        patterns = [
            log_dir / f"{spin_cat}_{sys_id}_*.log",
            log_dir / f"{sys_id}_*.log",
        ]
        logs = []
        for pat in patterns:
            logs.extend(glob.glob(str(pat)))
        logs = sorted(logs)

        entry = {
            'system_id':   sys_id,
            **r,
        }

        if not logs:
            entry['autocas_status'] = 'no_log'
            entry['autocas_ne']     = None
            entry['autocas_no']     = None
            entry['autocas_occ']    = None
            entry['autocas_orb_idx']= None
            entry['autocas_E_Ha']   = None
            entry['autocas_runtime_s'] = None
            entry['parity_ok']      = None
            entry['error_msg']      = None
        else:
            log = logs[-1]
            res = parse_log(log)
            entry['autocas_status']    = res['status']
            entry['autocas_occ']       = res['occupation']
            entry['autocas_orb_idx']   = res['orbital_idx']
            entry['autocas_E_Ha']      = res['energy_Ha']
            entry['autocas_ne']        = res.get('autocas_ne')
            entry['autocas_no']        = res.get('autocas_no')
            entry['autocas_runtime_s'] = res.get('runtime_s')
            entry['error_msg']         = res.get('error_msg')

            # Parity check
            if entry['autocas_ne'] is not None:
                spin_2s = r['spin_2S']
                entry['parity_ok'] = (entry['autocas_ne'] - spin_2s) % 2 == 0
            else:
                entry['parity_ok'] = None

        output[spin_cat].append(entry)

    # ── Write output files ────────────────────────────────────────────────
    out_files = {
        'high':   SCRIPTS_DIR / 'results_high_spin.json',
        'medium': SCRIPTS_DIR / 'results_medium_spin.json',
        'low':    SCRIPTS_DIR / 'results_low_spin.json',
    }

    for spin_cat, entries in output.items():
        # Sort by system_id
        entries.sort(key=lambda x: x['system_id'])

        # Summary stats
        done   = sum(1 for e in entries if e['autocas_status'] == 'done')
        failed = sum(1 for e in entries if e['autocas_status'] == 'failed')
        nolog  = sum(1 for e in entries if e['autocas_status'] == 'no_log')
        ok     = sum(1 for e in entries if e.get('parity_ok') is True)

        out_data = {
            'meta': {
                'spin_category':   spin_cat,
                'n_systems':       len(entries),
                'n_done':          done,
                'n_parity_ok':     ok,
                'n_failed':        failed,
                'n_no_log':        nolog,
                'method':          'autoCAS M=250, LargeCas, def2-svp, UHF+NEVPT2',
                'dmrg_bond_dim':   250,
                'dmrg_sweeps':     10,
                'init_bond_dim':   128,
                'init_sweeps':     5,
            },
            'systems': entries,
        }

        fpath = out_files[spin_cat]
        with open(fpath, 'w') as f:
            json.dump(out_data, f, indent=2)

        print(f"{'='*60}")
        print(f"  {spin_cat.upper()} SPIN → {fpath.name}")
        print(f"  Total: {len(entries)}  Done: {done}  "
              f"Parity OK: {ok}  Failed: {failed}  No log: {nolog}")
        print()

        # Print table
        print(f"  {'System':<44} {'CAS':>12} {'Ref':>10} {'Parity':>7} {'E(Ha)':>16}")
        print(f"  {'-'*44} {'-'*12} {'-'*10} {'-'*7} {'-'*16}")
        for e in entries:
            ne = e.get('autocas_ne')
            no = e.get('autocas_no')
            re_ne = e['ref_n_active_e']
            re_no = e['ref_n_active_orb']
            par   = '✓' if e.get('parity_ok') else ('✗' if e.get('parity_ok') is False else '?')
            status = e['autocas_status']
            cas_str = f"CAS({ne},{no})" if ne is not None else status
            e_str   = f"{e['autocas_E_Ha']:.6f}" if e.get('autocas_E_Ha') else "—"
            print(f"  {e['system_id']:<44} {cas_str:>12} "
                  f"CAS({re_ne},{re_no}){'':<2} {par:>7} {e_str:>16}")
        print()

    print("Output files written:")
    for f in out_files.values():
        print(f"  {f}")

if __name__ == "__main__":
    main()
