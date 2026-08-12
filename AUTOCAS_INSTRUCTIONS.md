# autoCAS HPC Framework — Quick Start Guide

Upload this file at the start of any new chat to immediately continue autoCAS work.

---

## CLUSTER SETUP (Noctua2)

```
Login:    hpcmual@fe.noctua2.pc2.uni-paderborn.de
Scripts:  ~/activeml/scripts/
Results:  ~/activeml/scripts/autocas_m250_results/{high,medium,low}/
Scratch:  /scratch/hpc-prf-qehpc/hpcmual/autocas_scratch/m250_logs/
Env:      source ~/.autocas_env.sh
Account:  hpc-prf-qehpc
GitHub:   https://github.com/arsalanali24/autocas-m250-benchmark
```

## ENVIRONMENT

```bash
source ~/.autocas_env.sh   # loads QCMaquis/4.0.0-intel-2022a-python-3.10
# Python 3.10.4, scine_autocas 3.0.0, h5py available
```

## BOND DIMENSIONS USED

| Spin state | M (bond dim) | Init M | Sweeps | Init sweeps |
|---|---|---|---|---|
| High spin  | 250 | 128 | 10 | 5 |
| Medium spin | 250 | 128 | 10 | 5 |
| Low spin   | 250 | 128 | 10 | 5 |

## KEY SCRIPTS (all in ~/activeml/scripts/)

| Script | Purpose |
|---|---|
| `run_autocas_m250.py` | Main runner — one system per call |
| `submit_autocas_m250.sh` | Submit all 50 SLURM jobs |
| `collect_m250_results.py` | Collect results → 3 JSON files |
| `check_m250_progress.sh` | Check running jobs |
| `extract_entropy_profiles.sh` | Copy entanglement/threshold PDFs |

## JSON INPUT FORMAT

Each system in `high_spin_15.json` / `medium_spin_20.json` / `low_spin_15.json`:

```json
{
  "system_id": "Mo_Br4_chg0_spin4_tet_d2p451",
  "metal": "Mo",
  "ligand": "Br",
  "n_ligands": 4,
  "total_charge": 0,
  "spin_2S": 4,
  "multiplicity": 5,
  "geometry": "tetrahedral",
  "coordination_number": 4,
  "M_L_bond_distance_A": 2.451,
  "metal_row": "4d",
  "is_csd_geometry": false,
  "n_active_electrons": 10,
  "n_active_orbitals": 6,
  "E_HF_Eh": -10343.544031,
  "E_CASSCF_Eh": -10344.230362,
  "autocas_run_hint": "AutoCAS CAS(10,6); mult=5 (2S=4); DMRG m=128→512."
}
```

## GEOMETRY BUILDER (inlined in run_autocas_m250.py)

Parses geometry from system name — NO external files needed:
- `CSD_FeCl4_2m_tet_spin4` → Fe, Cl×4, tetrahedral, d=2.19 Å
- `Mo_Br4_chg0_spin4_tet_d2p451` → Mo, Br×4, tetrahedral, d=2.451 Å
- Handles: oct, tet, sqpl/sq_pl, sq5, jt geometries
- Handles mixed ligands: MoCl3O3_fac, RuCl4O2_trans, FeCl4N2_cis

## PATCHES APPLIED

All in `~/activeml/scripts/patches/`:
- `patched_pyscf_interface.py` — UHF spin consistency
- `patched_large_spaces.py` — LargeCAS partition fix
- `patched_qcmaquis_alias.py` — QCMaquis solver alias

## SLURM SETTINGS

```
Partition: normal
Account:   hpc-prf-qehpc
Nodes:     1, CPUs: 8
Memory:    8G/core (3d), 10G/core (4d), 12G/core (5d)
Wall time: 8h (3d), 10h (4d), 12h (5d)
LD_PRELOAD: MKL22 + GCC11 libraries
```

## KNOWN ISSUES & FIXES

| Issue | Fix |
|---|---|
| SCF not converging | `scf_level_shift: 0.3`, `scf_max_cycle: 300`, `scf_init_guess: atom` |
| Parity failure (ne-2S odd) | `scf_level_shift: 0.1`, `scf_init_guess: atom` |
| Mixed ligand geometry wrong | Uses `is_fac`/`is_trans`/`is_cis` detection from name |
| __pycache__ stale | `find ~/activeml/scripts -name __pycache__ -exec rm -rf {} +` |
| 4d/5d needs ECP | Auto-detected from metal symbol, def2-SVP includes ECP |

## COMPLETED BENCHMARK STATUS

| Category | Total | Done | Parity OK |
|---|---|---|---|
| High spin  | 15 | 12 | 7 |
| Medium spin | 20 | 16 | 13 |
| Low spin   | 15 | 14 | 14 |
| **Total** | **50** | **42** | **34** |

## QICAS COMPARISON

| Spin | Systems | Within chem.acc. (<1.6 mHa) |
|---|---|---|
| Low  | 11 | 11/11 = 100% |
| Med  | 15 | 5/15 = 33% |
| High | 9  | 2/9 = 22%  |

## ENTROPY DATA LOCATION

- **autoCAS s_i**: `entropy_data/entropy_{high,medium,low}_spin.json` on GitHub
  - Extracted via `Hdf5Converter` + `OrbitalRDMBuilder` from `dmrg_0/qcmaquis_result_file.h5`
  - `spectrum/results/Nup|Ndown|Nupdown/mean/value` → 1-RDM → entropy
- **QICAS s_i**: `data/{high,medium,low}_spin_*.json` → `orbitals[i]['s_i']`

---

## ADDING NEW SYSTEMS — CHECKLIST

1. Add system to the appropriate JSON file (high/medium/low)
2. Run: `python3 run_autocas_m250.py <system_id>` interactively to test
3. Submit: edit `submit_autocas_m250.sh` arrays and run
4. Collect: `python3 collect_m250_results.py`
5. Upload to GitHub: `bash upload_to_github.sh <token>`
