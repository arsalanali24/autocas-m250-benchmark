# autoCAS Project Context — Load This First

Upload this file at the start of every new chat.
AI assistant: read this completely before responding.

---

## WHO I AM

Researcher running autoCAS M=250 DMRG active space calculations
on transition metal complexes on the Noctua2 HPC cluster (PC2 Paderborn).

## WHAT WE ARE DOING

Benchmarking autoCAS LargeCAS workflow (M=250) on 50 TM complexes
split into three spin categories (high/medium/low) and comparing
against QICAS active space selection using ΔCASCI as quality metric.

**GitHub repo:** `https://github.com/arsalanali24/autocas-m250-benchmark`
**Clone command:** `git clone https://github.com/arsalanali24/autocas-m250-benchmark`

---

## CLUSTER FACTS (do not ask these)

| Item | Value |
|---|---|
| Cluster | Noctua2, PC2 Paderborn |
| Login | `hpcmual@fe.noctua2.pc2.uni-paderborn.de` |
| User | `hpcmual` |
| Home | `/pc2/users/h/hpcmual/` |
| Scripts | `~/activeml/scripts/` |
| Results | `~/activeml/scripts/autocas_m250_results/{high,medium,low}/` |
| Logs | `/scratch/hpc-prf-qehpc/hpcmual/autocas_scratch/m250_logs/` |
| Env | `source ~/.autocas_env.sh` |
| Python | 3.10.4 |
| autoCAS | scine_autocas 3.0.0 |
| QCMaquis | 4.0.0-intel-2022a-python-3.10 |
| SLURM account | `hpc-prf-qehpc` |
| SLURM partition | `normal` |

---

## KEY FILES

```
~/activeml/scripts/
  run_autocas_m250.py          ← MAIN RUNNER (self-contained, no imports)
  submit_autocas_m250.sh       ← SLURM submission for all 50 systems
  collect_m250_results.py      ← collect results → 3 JSON files
  check_m250_progress.sh       ← progress checker
  extract_entropy_profiles.sh  ← copy PDFs from project dirs
  plot_entropy.py              ← entropy vs orbital plots
  autocas_setup.sh             ← smart setup for new systems
  high_spin_15.json            ← 15 HS input systems
  medium_spin_20.json          ← 20 MS input systems
  low_spin_15.json             ← 15 LS input systems
  results_high_spin.json       ← autoCAS M=250 results (HS)
  results_medium_spin.json     ← autoCAS M=250 results (MS)
  results_low_spin.json        ← autoCAS M=250 results (LS)
  patched_pyscf_interface.py   ← patch 1: UHF spin consistency
  patched_large_spaces.py      ← patch 2: LargeCAS partition
  patched_qcmaquis_alias.py    ← patch 3: QCMaquis alias
```

---

## GEOMETRY BUILDER (critical — do not rewrite)

`run_autocas_m250.py` is SELF-CONTAINED. It:
- Parses metal/ligand/n_ligands/geometry from the system NAME
- Never reads these from JSON (some JSONs have wrong values!)
- Builds XYZ as a plain Python string (NO mol.build() call)
- Uses `Defaults:` YAML format with `scine_autocas run -y yaml -x xyz -l -u`

**Do NOT** rewrite geometry_utils.py or add mol.build() calls.

---

## SLURM JOB STRUCTURE

```bash
#SBATCH --cpus-per-task=8
#SBATCH --mem-per-cpu=8G   # 3d; use 10G for 4d, 12G for 5d
#SBATCH --time=08:00:00    # 3d; use 10h for 4d, 12h for 5d

source ~/.autocas_env.sh
find ~/activeml/scripts -name __pycache__ -exec rm -rf {} +  # ALWAYS clear cache
export LD_PRELOAD="${GCC11}/libgomp.so.1:${MKL22}/libmkl_gnu_thread.so.2:..."
cd ~/activeml/scripts && python3 -u run_autocas_m250.py SYSTEM_NAME
```

---

## KNOWN ISSUES (already solved — do not re-solve)

| Problem | Root cause | Fix (already in scripts) |
|---|---|---|
| `geometry_utils.py` empty | Not in zip | Geometry inlined in runner |
| `mol.build()` errors | PySCF basis/ECP | No mol.build() in v3 |
| Wrong ligand/n_ligands | Bad JSON values | Parse from name only |
| `tuple * float` error | `atom_coord()` returns tuple | XYZ as plain string |
| `__pycache__` stale | Old .pyc loaded | Clear cache in every job |
| MnCl6 SCF fail | Degeneracy | `level_shift=0.3, init_guess=atom` |
| Parity failure | UHF symmetry break | `level_shift=0.1, init_guess=atom` |
| Mixed ligand wrong geometry | Sequential oct positions | fac/trans/cis detection |
| `qcmaquis_result_file.h5` is dir | Wrong path | Use `final/qcmaquis_result_file.h5` |
| Entropy not in HDF5 `results/` | In `spectrum/results/` | Use `Hdf5Converter` + `OrbitalRDMBuilder` |

---

## ADDING NEW SYSTEMS

```bash
# Interactive setup with auto-detection:
bash ~/activeml/scripts/autocas_setup.sh --add-system

# Or manually add to JSON then submit:
# 1. Edit high_spin_15.json / medium_spin_20.json / low_spin_15.json
# 2. python3 run_autocas_m250.py <system_id>   ← test first!
# 3. bash submit_autocas_m250.sh
```

JSON entry minimum required fields:
```json
{
  "system_id": "Fe_Cl6_chg-2_spin4_oct_d2p238",
  "total_charge": -2,
  "spin_2S": 4,
  "multiplicity": 5,
  "M_L_bond_distance_A": 2.38
}
```
Everything else (metal, ligand, geometry, n_ligands, metal_row) is parsed from `system_id`.

---

## CURRENT BENCHMARK STATUS

| Category | Total | Done | Parity OK | Failed/Pending |
|---|---|---|---|---|
| High spin  | 15 | 12 | 7  | 3 (Pt,Rh,Fe CIS) |
| Medium spin | 20 | 16 | 13 | 4 (Co,Cr,Fe,Rh_d48) |
| Low spin   | 15 | 14 | 14 | 1 (MnCl6 SCF) |
| **Total** | **50** | **42** | **34** | **8** |

---

## WORKFLOW FOR NEW CHAT

**If continuing existing work:**
```bash
# Check status
bash ~/activeml/scripts/check_m250_progress.sh
# Collect results
python3 ~/activeml/scripts/collect_m250_results.py
```

**If adding new systems:**
```bash
bash ~/activeml/scripts/autocas_setup.sh --add-system
```

**If uploading to GitHub:**
```bash
bash ~/activeml/scripts/upload_to_github.sh <TOKEN>
```

**If plotting entropy:**
```bash
python3 ~/activeml/scripts/plot_entropy.py --all
```

---

## PHYSICAL FINDINGS (do not re-derive)

1. **Active space size ∝ metal-ligand covalency** (not spin state)
2. **4d/5d + Br** → always large CAS (12-21 orb) regardless of spin
3. **3d + Cl/F** → small CAS (4-8 orb), spin matters here
4. **QICAS 100% accurate for low spin** (|ΔCASCI|=0 for all 11 LS systems)
5. **QICAS fails for high spin** (mean |ΔCASCI|=95 mHa, 14-orb window too small)
6. **Sharp entropy plateau** → reliable CAS (small CAS systems)
7. **Gradual entropy plateau** → ambiguous CAS (large CAS, 4d+Br)

---

*Generated: 2026-07-18 | Cluster: Noctua2 | autoCAS 3.0.0 | M=250*
