#!/usr/bin/env python3
"""
run_autocas_m250.py  — autoCAS M=250 benchmark runner
======================================================
Self-contained. Reads high_spin_15.json / medium_spin_20.json / low_spin_15.json
and runs autoCAS LargeCasWorkflow at M=250 on every system.

Usage:
    source ~/.autocas_env.sh
    python3 -u run_autocas_m250.py <system_id>

Example:
    python3 -u run_autocas_m250.py CSD_RhBr6_3m_oct_spin0
    python3 -u run_autocas_m250.py Ru_Br4_chg-2_spin4_tet_d2p375
"""

import sys, os, json, re, math, time, runpy
from pathlib import Path

# ── Paths ──────────────────────────────────────────────────────────────────
SCRIPTS_DIR = Path(__file__).parent
JSON_DIR    = SCRIPTS_DIR   # JSONs must be in same dir as this script
RESULTS_DIR = SCRIPTS_DIR / "autocas_m250_results"

# JSON file for each spin category
SPIN_FILES = {
    'high':   JSON_DIR / "high_spin_15.json",
    'medium': JSON_DIR / "medium_spin_20.json",
    'low':    JSON_DIR / "low_spin_15.json",
}

# ── Geometry ───────────────────────────────────────────────────────────────
def _tet(d):
    c = d/math.sqrt(3)
    return [(c,c,c),(-c,-c,c),(-c,c,-c),(c,-c,-c)]
def _oct(d):
    return [(d,0,0),(-d,0,0),(0,d,0),(0,-d,0),(0,0,d),(0,0,-d)]
def _sqpl(d):
    return [(d,0,0),(-d,0,0),(0,d,0),(0,-d,0)]
def _sq5(d):
    return [(d,0,0),(-d,0,0),(0,d,0),(0,-d,0),(0,0,d)]

BUILDERS = {
    'octahedral':           _oct,
    'distorted_octahedral': _oct,
    'capped_octahedral':    _oct,
    'tetrahedral':          _tet,
    'square_planar':        _sqpl,
    'square_pyramidal':     _sq5,
}

# Primary atom for ligand strings
LIG_ATOM = {
    'O':'O','Cl':'Cl','Br':'Br','F':'F','N':'N','S':'S',
    'H':'H','C':'C','P':'P',
    'Cl2F4':'Cl','Cl3N1':'Cl','Cl4O2':'Cl',
    'CN':'C','NH3':'N','H2O':'O','PH3':'P',
}

# Default M-L distances (Å) when JSON has M_L_bond_distance_A = None
DIST_DEFAULTS = {
    ('Ru','O'):2.00, ('Ru','Cl'):2.35, ('Ru','Br'):2.50,
    ('Mo','O'):1.95, ('Mo','Cl'):2.40, ('Mo','Br'):2.55,
    ('V', 'Cl'):2.34,('V', 'Br'):2.50,
    ('Mn','Cl'):2.48,('Mn','O'):2.10, ('Mn','Br'):2.63,
    ('Fe','Cl'):2.38,('Fe','F'):2.00, ('Fe','Br'):2.50,('Fe','N'):2.18,
    ('Rh','Cl'):2.35,('Rh','N'):2.10, ('Rh','Br'):2.48,
    ('Pd','Br'):2.42,('Pd','Cl'):2.30,
    ('Ir','Br'):2.50,('Ir','Cl'):2.37,
    ('Pt','Br'):2.45,('Pt','Cl'):2.31,
    ('Ti','Br'):2.50,('Ti','Cl'):2.35,
    ('Ni','Br'):2.53,('Ni','Cl'):2.40,
    ('Cu','Br'):2.50,('Cu','Cl'):2.35,
    ('Co','Br'):2.57,('Co','Cl'):2.44,
    ('Cr','Br'):2.45,('Cr','Cl'):2.34,
    ('Zn','Br'):2.39,('Zn','Cl'):2.26,
}

def build_xyz(s):
    """Build XYZ string from system dict.
    Handles mixed-ligand systems by parsing csd_struct_name.
    """
    metal    = s['metal']
    lig_str  = s['ligand']
    lig_atom = LIG_ATOM.get(lig_str, lig_str[0] if lig_str else 'Cl')
    geom     = s['geometry']
    dist     = s.get('M_L_bond_distance_A')
    coord    = s.get('coordination_number') or \
               {'octahedral':6,'distorted_octahedral':6,'capped_octahedral':6,
                'tetrahedral':4,'square_planar':4,'square_pyramidal':5}.get(geom, 6)
    coord    = int(coord)

    # Detect mixed-ligand systems from csd_struct_name or system_id
    # e.g. MoCl3O3_fac -> 3 Cl + 3 O in fac arrangement
    #      RuCl4O2_trans -> 4 Cl + 2 O in trans arrangement
    #      MnCl4O2_trans -> 4 Cl + 2 O in trans arrangement
    #      FeCl4N2_cis   -> 4 Cl + 2 N in cis arrangement
    #      MoOCl6        -> 1 O + 6 Cl (capped oct)
    struct = s.get('csd_struct_name', '') or s.get('system_id', '')
    mixed_atoms = []  # list of (atom, x, y, z)

    # Parse patterns like Cl3O3, Cl4O2, Cl4N2, OCl6
    m_mixed = re.findall(r'([A-Z][a-z]?)([0-9]+)', struct.split('_')[0] if '_' in struct else struct)
    if len(m_mixed) >= 2 and m_mixed[0][0] != metal:
        # Mixed ligand: build positions explicitly
        # Position pools for different isomers
        # fac: A-ligands on one face (+x,+y,+z), B-ligands on opposite (-x,-y,-z)
        # trans: major ligand equatorial, minor axial (trans pair)
        # mer/default: sequential oct positions
        is_fac   = 'fac'   in struct.lower()
        is_trans = 'trans' in struct.lower()
        is_cis   = 'cis'   in struct.lower()

        # All oct unit positions
        oct_pos = [(1,0,0),(-1,0,0),(0,1,0),(0,-1,0),(0,0,1),(0,0,-1)]
        # fac faces: all mutually 90 degrees
        fac_face1 = [(1,0,0),(0,1,0),(0,0,1)]    # one face
        fac_face2 = [(-1,0,0),(0,-1,0),(0,0,-1)] # opposite face

        # Build position pool based on isomer and stoichiometry
        counts = [int(c) for sym,c in m_mixed if sym != metal]
        if is_fac and len(counts) == 2 and counts[0] == 3 and counts[1] == 3:
            pos_pool = fac_face1 + fac_face2
        elif is_trans and len(counts) == 2 and counts[1] == 2:
            # trans: minor ligand (2) goes axial (0,0,+z),(0,0,-z)
            pos_pool = [(1,0,0),(-1,0,0),(0,1,0),(0,-1,0),(0,0,1),(0,0,-1)]
        else:
            pos_pool = oct_pos

        idx = 0
        for lig_sym, count in m_mixed:
            if lig_sym == metal:
                continue
            dist_lig = DIST_DEFAULTS.get((metal, lig_sym),
                       DIST_DEFAULTS.get((metal, lig_atom), 2.30))
            if dist and lig_sym == lig_atom:
                dist_lig = float(dist)
            for _ in range(int(count)):
                if idx < len(pos_pool):
                    ux,uy,uz = pos_pool[idx]
                    mixed_atoms.append((lig_sym, ux*dist_lig, uy*dist_lig, uz*dist_lig))
                    idx += 1

    if mixed_atoms:
        lines = [str(1 + len(mixed_atoms)), s['system_id'],
                 f"{metal}  0.000000  0.000000  0.000000"]
        for atm, x, y, z in mixed_atoms:
            lines.append(f"{atm}  {x:.6f}  {y:.6f}  {z:.6f}")
        return "\n".join(lines) + "\n"

    # Single ligand type (standard case)
    if dist is None:
        dist = DIST_DEFAULTS.get((metal, lig_atom),
               DIST_DEFAULTS.get((metal, lig_str), 2.30))

    builder  = BUILDERS.get(geom, _oct)
    lig_pos  = builder(float(dist))[:coord]

    lines = [str(1 + len(lig_pos)), s['system_id'],
             f"{metal}  0.000000  0.000000  0.000000"]
    for x, y, z in lig_pos:
        lines.append(f"{lig_atom}  {x:.6f}  {y:.6f}  {z:.6f}")
    return "\n".join(lines) + "\n"

# ── Load all systems ───────────────────────────────────────────────────────
def load_all_systems():
    all_sys = {}
    for spin_cat, fpath in SPIN_FILES.items():
        if not fpath.exists():
            print(f"[warn] {fpath} not found — skipping {spin_cat}")
            continue
        with open(fpath) as f:
            data = json.load(f)
        for s in data['systems']:
            s['_spin_category'] = spin_cat
            all_sys[s['system_id']] = s
    return all_sys

# ── autoCAS YAML (M=250, Defaults: format) ────────────────────────────────
def make_yaml(s, work_dir):
    charge    = s['total_charge']
    spin_mult = s['multiplicity']
    # Infer metal_row from metal symbol if not set in JSON
    _4d_metals = {'Mo','Tc','Ru','Rh','Pd','Ag','Cd'}
    _5d_metals = {'Hf','Ta','W','Re','Os','Ir','Pt','Au','Hg'}
    metal_sym  = s.get('metal','')
    _row       = s.get('metal_row') or ('4d' if metal_sym in _4d_metals else ('5d' if metal_sym in _5d_metals else '3d'))
    is_4d5d    = _row in ('4d', '5d')
    metal_row = s.get('metal_row', '3d')

    # ECP for 4d/5d metals
    ecp_metals_4d = {'Mo','Tc','Ru','Rh','Pd','Ag','Cd'}
    ecp_metals_5d = {'Hf','Ta','W','Re','Os','Ir','Pt','Au','Hg'}
    metal = s['metal']
    use_ecp = metal in ecp_metals_4d or metal in ecp_metals_5d

    return f"""\
Defaults:
  AutoCAS:
    large_cas: true
    large_cas_average_entanglement: false
    large_cas_max_orbitals: 30
    large_cas_seed: 42
    plateau_values: 10
    single_reference_threshold: 0.14
    threshold_step: 0.01
    weak_correlation_threshold: 0.02
  Interface:
    basis_set: def2-svp
    cas_method: dmrgci
    dmrg_bond_dimension: 250
    dmrg_solver: QCMaquis
    dmrg_sweeps: 10
    dump: true
    fiedler: true
    init_cas_method: dmrgci
    init_dmrg_bond_dimension: 128
    init_dmrg_sweeps: 5
    init_fiedler: true
    interface: pyscf
    n_excited_states: 0
    post_cas_method: nevpt2
    uhf: true
    scf_max_cycle: 300
    scf_init_guess: atom
    scf_level_shift: 0.2
  Molecule:
    charge: {charge}
    double_d_shell: {'false' if is_4d5d else 'true'}
    ecp_electrons: 0
    spin_multiplicity: {spin_mult}
    unit: ang
"""

# ── Patches ────────────────────────────────────────────────────────────────
def load_patches():
    sys.path.insert(0, str(SCRIPTS_DIR))
    try:
        from patched_pyscf_interface import PatchedPyscfInterface
        import scine_autocas.io.actions.run as run_module
        run_module.PyscfInterface = PatchedPyscfInterface
        from patched_large_spaces import apply_patch as p2; p2()
        from patched_qcmaquis_alias import apply_patch as p3; p3()
        print("[patches] All 3 patches applied")
    except Exception as e:
        print(f"[patches] WARNING: {e}")

# ── Main runner ────────────────────────────────────────────────────────────
def run_system(sys_id, s):
    spin_cat = s['_spin_category']
    work_dir = RESULTS_DIR / spin_cat / sys_id
    work_dir.mkdir(parents=True, exist_ok=True)

    # XYZ
    xyz_str  = build_xyz(s)
    xyz_path = work_dir / f"{sys_id}.xyz"
    xyz_path.write_text(xyz_str)
    print(f"[xyz] {xyz_path}")
    print(f"[xyz] content:\n{xyz_str}")

    # YAML
    yaml_str  = make_yaml(s, work_dir)
    yaml_path = work_dir / f"{sys_id}.yaml"
    yaml_path.write_text(yaml_str)
    print(f"[yaml] {yaml_path}")
    print(f"[info] charge={s['total_charge']}  mult={s['multiplicity']}  "
          f"metal_row={s.get('metal_row','?')}  spin_cat={spin_cat}")
    print(f"[ref]  CASSCF ref: CAS({s['n_active_electrons']},{s['n_active_orbitals']})")
    print(f"[hint] {s.get('autocas_run_hint','')}")

    load_patches()

    old_argv = sys.argv.copy()
    old_cwd  = os.getcwd()
    os.chdir(work_dir)
    sys.argv = ["scine_autocas","run","-y",str(yaml_path),"-x",str(xyz_path),"-l","-u"]
    print(f"[run] {sys.argv}")

    t0 = time.time()
    try:
        runpy.run_module("scine_autocas", run_name="__main__")
        elapsed = time.time() - t0
        print(f"[done] {sys_id} in {elapsed:.1f}s ({elapsed/3600:.2f}h)")
        return True
    except SystemExit as e:
        elapsed = time.time() - t0
        print(f"[done] SystemExit({e.code}) after {elapsed:.1f}s")
        return True
    except Exception as e:
        print(f"[error] {sys_id}: {type(e).__name__}: {e}")
        import traceback; traceback.print_exc()
        return False
    finally:
        sys.argv = old_argv
        os.chdir(old_cwd)

def main():
    if len(sys.argv) < 2:
        print("Usage: python3 run_autocas_m250.py <system_id>")
        print()
        all_sys = load_all_systems()
        print(f"Available systems ({len(all_sys)}):")
        for cat in ('high','medium','low'):
            ids = [k for k,v in all_sys.items() if v['_spin_category']==cat]
            print(f"\n  {cat.upper()} SPIN ({len(ids)}):")
            for sid in ids:
                print(f"    {sid}")
        sys.exit(1)

    sys_id  = sys.argv[1]
    all_sys = load_all_systems()

    if sys_id not in all_sys:
        print(f"ERROR: '{sys_id}' not found.")
        print("Run without arguments to see available systems.")
        sys.exit(1)

    s = all_sys[sys_id]
    print(f"=== autoCAS M=250: {sys_id} ===")
    success = run_system(sys_id, s)
    sys.exit(0 if success else 1)

if __name__ == "__main__":
    main()
