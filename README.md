# autoCAS M=250 Benchmark — Transition Metal Complexes

Benchmark of autoCAS LargeCAS workflow at bond dimension M=250 on 50
transition metal complexes covering high, medium, and low spin states.

## Dataset

| Category | Systems | Spin (2S) |
|---|---|---|
| High spin  | 15 | 3–4 |
| Medium spin | 20 | 2 |
| Low spin   | 15 | 0–1 |

## Contents

```
data/
  high_spin_15.json      — 15 high spin systems (CASSCF reference + geometry)
  medium_spin_20.json    — 20 medium spin systems
  low_spin_15.json       — 15 low spin systems

results/
  results_high_spin.json    — autoCAS M=250 active spaces (high spin)
  results_medium_spin.json  — autoCAS M=250 active spaces (medium spin)
  results_low_spin.json     — autoCAS M=250 active spaces (low spin)

entropy_plots/
  *_threshold.pdf    — entropy threshold plots (active space selection)
  *_entanglement.pdf — orbital entanglement diagrams

scripts/
  run_autocas_m250.py        — main runner script
  submit_autocas_m250.sh     — SLURM submission script
  collect_m250_results.py    — result collector
  autocas_benchmark_results.py — 16 Noctua2 benchmark results

report/
  autocas_benchmark_report.tex — LaTeX report (2 pages)
```

## Method

- Software: SCINE autoCAS + QCMaquis 4.0.0
- Bond dimension: M=250 (init M=128)
- DMRG sweeps: 10 (init 5)
- Basis: def2-SVP (ECP for 4d/5d)
- Post-CAS: NEVPT2
- Cluster: Noctua2, PC2 Paderborn

## Key Findings

1. Metal–ligand covalency (not spin state) dominates active space size
2. 4d/5d + Br ligands: CAS 12–21 orbitals (larger than d-only reference)
3. Low spin systems show sharp entropy plateaus → reliable selection
4. High spin + mixed ligands show gradual plateaus → ambiguous boundary

## Reference

autoCAS: Stein & Reiher, J. Chem. Theory Comput. 2016, 12, 1760.
QCMaquis: Keller et al., J. Chem. Phys. 2015, 143, 244118.
