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

## CRITICAL: JSON FILE STRUCTURE

All three JSON files use this EXACT structure — always use `data['systems']`, never `data` directly:

```python
# CORRECT way to read/write JSON files
import json
with open('medium_spin_20.json') as f:
    data = json.load(f)

systems = data['systems']        # ← always data['systems'], NOT data itself
ids = [s['system_id'] for s in systems]

# Add new system
systems.append(new_entry)
data['systems'] = systems
with open('medium_spin_20.json', 'w') as f:
    json.dump(data, f, indent=2)
```

**WRONG** (will crash with TypeError):
```python
ids = [s['system_id'] for s in data]    # ← WRONG, data is a dict not a list
data.append(new_entry)                   # ← WRONG
```

### Minimum required fields for a new system entry:

```json
{
  "system_id":           "Ni_Br6_chg-2_spin2_oct_d2p240",
  "metal":               "Ni",
  "ligand":              "Br",
  "total_charge":        -2,
  "spin_2S":             2,
  "multiplicity":        3,
  "M_L_bond_distance_A": 2.40
}
```

Everything else (geometry, coordination_number, metal_row, n_ligands) is
auto-parsed from `system_id` by `_parse_name()` in `run_autocas_m250.py`.
Do NOT add wrong values for these — leave them out entirely.

### Full optional fields (only add if you have them):
```json
{
  "n_active_electrons":  10,
  "n_active_orbitals":   5,
  "E_HF_Eh":            -4018.34,
  "E_CASSCF_Eh":        -4019.12,
  "geometry":           "octahedral",
  "coordination_number": 6,
  "metal_row":          "3d",
  "is_csd_geometry":    false,
  "autocas_run_hint":   "AutoCAS; mult=3 (2S=2); DMRG m=128→250."
}
```

---

## KEY FILES (all in ~/activeml/scripts/)

| Script | Purpose |
|---|---|
| `run_autocas_m250.py` | Main runner — one system per call |
| `submit_autocas_m250.sh` | Submit all 50 SLURM jobs |
| `collect_m250_results.py` | Collect results → 3 JSON files |
| `check_m250_progress.sh` | Check running jobs |
| `plot_entropy.py` | Plot entropy vs orbital |
| `autocas_setup.sh` | Smart setup for new systems |
| `high_spin_15.json` | 15 HS input systems |
| `medium_spin_20.json` | 20 MS input systems |
| `low_spin_15.json` | 15 LS input systems |

---

## HOW TO ADD AND RUN A NEW SYSTEM

```bash
# Step 1: Add to JSON (use this exact pattern)
python3 - << 'EOF'
import json
path = "/pc2/users/h/hpcmual/activeml/scripts/medium_spin_20.json"
with open(path) as f:
    data = json.load(f)
systems = data['systems']
new_entry = {
    "system_id":           "Ni_Br6_chg-2_spin2_oct_d2p240",
    "metal":               "Ni",
    "ligand":              "Br",
    "total_charge":        -2,
    "spin_2S":             2,
    "multiplicity":        3,
    "M_L_bond_distance_A": 2.40
}
ids = [s['system_id'] for s in systems]
if new_entry['system_id'] not in ids:
    systems.append(new_entry)
    data['systems'] = systems
    with open(path, 'w') as f:
        json.dump(data, f, indent=2)
    print(f"Added. Total: {len(systems)}")
else:
    print("Already exists")
EOF

# Step 2: Test interactively
source ~/.autocas_env.sh
find ~/activeml/scripts -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true
python3 -u ~/activeml/scripts/run_autocas_m250.py Ni_Br6_chg-2_spin2_oct_d2p240 2>&1 | head -30

# Expected output: [xyz] [yaml] [patches] All 3 patches applied [run]
# If you see these 4 lines → submit SLURM job

# Step 3: Submit SLURM job
sbatch << 'SLURM'
#!/bin/bash
#SBATCH --job-name=m250_NiBr6
#SBATCH --partition=normal
#SBATCH --account=hpc-prf-qehpc
#SBATCH --nodes=1 --ntasks=1 --cpus-per-task=8
#SBATCH --mem-per-cpu=8G --time=08:00:00
#SBATCH --output=/scratch/hpc-prf-qehpc/hpcmual/autocas_scratch/m250_logs/medium_Ni_Br6_%j.log

set -uo pipefail
source ~/.autocas_env.sh || true; set -e
find ~/activeml/scripts -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true
MKL="/opt/software/pc2/EB-SW/software/imkl/2022.2.1/mkl/2022.2.1/lib/intel64"
GCC="/opt/software/pc2/EB-SW/software/GCCcore/11.3.0/lib64"
export LD_PRELOAD="${GCC}/libgomp.so.1:${MKL}/libmkl_gnu_thread.so.2:${MKL}/libmkl_core.so.2"
export OMP_NUM_THREADS=$SLURM_CPUS_PER_TASK
export SCRATCH="/scratch/hpc-prf-qehpc/hpcmual/autocas_scratch"
cd ~/activeml/scripts && python3 -u run_autocas_m250.py Ni_Br6_chg-2_spin2_oct_d2p240
echo "Finished: $(date)"
SLURM
```

---

## CHANGING BOND DIMENSION (e.g. M=50 for quick test)

The bond dimension is set in `make_yaml()` inside `run_autocas_m250.py`.
To run at M=50 instead of M=250, either:

1. Pass it via environment variable (if supported), or
2. Edit the YAML values directly in `make_yaml()`:
   - `dmrg_bond_dimension: 50`
   - `init_dmrg_bond_dimension: 50`
   - `dmrg_sweeps: 5`
   - `init_dmrg_sweeps: 3`

Or write a wrapper that patches the YAML after generation.

---

## SLURM MEMORY/TIME BY METAL ROW

| Metal row | Metals | mem-per-cpu | time |
|---|---|---|---|
| 3d | Ti,V,Cr,Mn,Fe,Co,Ni,Cu,Zn | 8G | 08:00:00 |
| 4d | Mo,Ru,Rh,Pd | 10G | 10:00:00 |
| 5d | Ir,Pt | 12G | 12:00:00 |

---

## KNOWN ISSUES (already solved — do not re-solve)

| Problem | Fix |
|---|---|
| `KeyError: 'geometry'` in build_xyz | build_xyz uses `_parse_name()` not dict keys |
| `KeyError: 'metal'` | Always include `metal` and `ligand` in JSON entry |
| `TypeError: string indices must be integers` | Use `data['systems']` not `data` |
| `NameError: _parse_name not defined` | It's defined at line ~81 in run_autocas_m250.py |
| SCF not converging | `scf_level_shift: 0.3, scf_max_cycle: 300, scf_init_guess: atom` |
| Parity failure (ne-2S odd) | `scf_level_shift: 0.1, scf_init_guess: atom` |
| `__pycache__` stale | Clear before every run |
| Mixed ligand geometry wrong | fac/trans/cis auto-detected from name |

---

## CHECK RESULT AFTER JOB FINISHES

```bash
log=$(ls /scratch/hpc-prf-qehpc/hpcmual/autocas_scratch/m250_logs/medium_SYSNAME_*.log | sort | tail -1)
grep -A 1 "final_occupation:\|final_energy:" "$log"
# Parity check:
python3 -c "
occ=[2,2,2,2]; ne=sum(occ); spin=2
print(f'CAS({ne},{len(occ)}) parity: {\"OK\" if (ne-spin)%2==0 else \"FAIL\"}')"
```

---

## CURRENT BENCHMARK STATUS

| Category | Total | Done | Parity OK |
|---|---|---|---|
| High spin  | 15 | 12 | 7  |
| Medium spin | 20 | 16 | 13 |
| Low spin   | 15 | 14 | 14 |
| **Total** | **50** | **42** | **34** |

## QICAS vs autoCAS KEY FINDINGS

- Low spin: QICAS 100% accurate (|ΔCASCI|=0 for all 11 LS systems)
- High spin: QICAS poor (mean |ΔCASCI|=95 mHa, 14-orb window too small)
- Active space size ∝ metal-ligand covalency, NOT spin state
- 4d/5d + Br → always large CAS (12-21 orb) regardless of spin
- Sharp entropy plateau → reliable CAS; gradual → ambiguous

---

## GITHUB TOKEN (for uploads)

```
YOUR_GITHUB_TOKEN_HERE
```
Upload script: `bash ~/activeml/scripts/upload_to_github.sh <token>`

---

*Updated: 2026-08-12 | Cluster: Noctua2 | autoCAS 3.0.0 | M=250*
