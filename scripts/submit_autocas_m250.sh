#!/bin/bash
# submit_autocas_m250.sh
# ======================
# Submits one SLURM job per system (50 total: 15 high + 20 medium + 15 low).
# Results go to separate directories per spin category.
#
# Prerequisites (all in same directory as this script):
#   run_autocas_m250.py
#   high_spin_15.json
#   medium_spin_20.json
#   low_spin_15.json
#   patches/  (patched_pyscf_interface.py, patched_large_spaces.py, patched_qcmaquis_alias.py)
#
# Usage:
#   bash submit_autocas_m250.sh

SCRIPTS="$(cd "$(dirname "$0")" && pwd)"
SCRATCH="/scratch/hpc-prf-qehpc/hpcmual/autocas_scratch"
LOG_DIR="$SCRATCH/m250_logs"
mkdir -p "$LOG_DIR"

# ── System lists (from JSON files) ────────────────────────────────────────
HIGH_SPIN=(
    CSD_RuCl4O2_trans_spin4
    CSD_MoCl3O3_fac_spin3
    CSD_VCl6_3m_dist_spin4
    CSD_MnCl4O2_trans_spin3
    CSD_FeCl4N2_cis_spin4
    Rh_Br6_chg-3_spin4_oct_d2p356
    Pd_Br6_chg-2_spin4_oct_d2p337
    Ru_Br4_chg-2_spin4_tet_d2p375
    Mo_Br4_chg0_spin4_tet_d2p451
    Ir_Br6_chg-3_spin4_oct_d2p384
    Pt_Br6_chg-2_spin4_oct_d2p328
    Ti_Br6_chg0_spin4_oct_d2p259
    V_Br4_chg-2_spin3_tet_d2p318
    Mn_Br4_chg-1_spin4
    Fe_Br6_chg-1_spin3
)

MEDIUM_SPIN=(
    CSD_RhCl2N2_1m_sqpl_spin2
    CSD_PdBr4_2m_sqpl_spin2
    CSD_RuCl4O2_trans_spin2
    CSD_MoOCl6_2m_capoct_spin2
    CSD_IrBr6_3m_oct_spin2
    Rh_Br4_chg-1_spin2_tet_d2p356
    Pd_Br4_chg-2_spin2_sq_pl_d2p337
    Ru_Br4_chg-2_spin2_tet_d2p375
    Mo_Br4_chg0_spin2_tet_d2p451
    Ir_Br6_chg-3_spin2_oct_d2p384
    Pt_Br4_chg-2_spin2_sq_pl_d2p328
    Ti_Br4_chg-2_spin2_tet_d2p635
    V_Br6_chg-3_spin2_oct_d2p318
    Mn_Br4_chg-1_spin2
    Fe_Br6_chg-2_spin2
    Cr_Br4_chg-2_spin2
    Ni_Br6_chg-4_spin2
    Cu_Br6_chg-3_spin2
    Co_Br4_chg-1_spin2
    Rh_Br4_chg-1_spin2_tet_d2p48
)

LOW_SPIN=(
    CSD_RhBr6_3m_oct_spin0
    CSD_PdBr4_2m_sqpl_spin0
    CSD_RuCl4O2_trans_spin0
    CSD_MoCl3O3_fac_spin1
    CSD_IrBr6_3m_oct_spin0
    Rh_Br4_chg-1_spin0_tet_d2p356
    Pd_Br4_chg-2_spin0_sq_pl_d2p337
    Ru_Br4_chg-2_spin0_tet_d2p375
    Mo_Br4_chg0_spin0_tet_d2p451
    Ir_Br6_chg-3_spin0_oct_d2p384
    Pt_Br4_chg-2_spin0_sq_pl_d2p328
    Ti_Br4_chg-3_spin1_tet_d2p259
    V_Br6_chg-2_spin1_oct_d2p318
    Zn_Br4_chg-2_spin0_tet_d2p289
    Mn_Br4_chg-1_spin0
)

submit_job() {
    local SYS="$1"
    local SPIN_CAT="$2"   # high / medium / low
    local WALLTIME="$3"
    local MEM="$4"

JOBSCRIPT=$(cat << SLURM
#!/bin/bash
#SBATCH --job-name=m250_${SYS:0:12}
#SBATCH --partition=normal
#SBATCH --account=hpc-prf-qehpc
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=8
#SBATCH --mem-per-cpu=${MEM}
#SBATCH --time=${WALLTIME}
#SBATCH --output=${LOG_DIR}/${SPIN_CAT}_${SYS}_%j.log
#SBATCH --error=${LOG_DIR}/${SPIN_CAT}_${SYS}_%j.err

set -uo pipefail
source ~/.autocas_env.sh || true
set -e

# Clear Python cache
find "${SCRIPTS}" -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true
find "${SCRIPTS}" -name "*.pyc" -delete 2>/dev/null || true

MKL22="/opt/software/pc2/EB-SW/software/imkl/2022.2.1/mkl/2022.2.1/lib/intel64"
GCC11="/opt/software/pc2/EB-SW/software/GCCcore/11.3.0/lib64"
export LD_PRELOAD="\${GCC11}/libgomp.so.1:\${MKL22}/libmkl_gnu_thread.so.2:\${MKL22}/libmkl_core.so.2"
export LD_LIBRARY_PATH="\${MKL22}:\${LD_LIBRARY_PATH:-}"
export OMP_NUM_THREADS=\$SLURM_CPUS_PER_TASK
export SCRATCH="${SCRATCH}"

echo "=== autoCAS M=250: ${SYS} [${SPIN_CAT}-spin] ==="
echo "Job: \$SLURM_JOB_ID  Node: \$(hostname)  Start: \$(date)"
echo ""

cd "${SCRIPTS}"
python3 -u run_autocas_m250.py ${SYS}

echo ""
echo "Finished: \$(date)"
SLURM
)
    JOBID=$(echo "$JOBSCRIPT" | sbatch --parsable 2>&1)
    echo "  [$SPIN_CAT] ${SYS}: job ${JOBID##*$'\n'}"
}

# ── Determine wall times by metal row ─────────────────────────────────────
get_walltime() {
    local SYS="$1"
    # 5d metals (Ir, Pt) need longest time
    if [[ "$SYS" == Ir_* ]] || [[ "$SYS" == Pt_* ]] || \
       [[ "$SYS" == CSD_Ir* ]] || [[ "$SYS" == CSD_Pt* ]]; then
        echo "12:00:00"
    # 4d metals
    elif [[ "$SYS" == Mo_* ]] || [[ "$SYS" == Ru_* ]] || \
         [[ "$SYS" == Rh_* ]] || [[ "$SYS" == Pd_* ]] || \
         [[ "$SYS" == CSD_Mo* ]] || [[ "$SYS" == CSD_Ru* ]] || \
         [[ "$SYS" == CSD_Rh* ]] || [[ "$SYS" == CSD_Pd* ]]; then
        echo "10:00:00"
    else
        echo "08:00:00"
    fi
}

get_mem() {
    local SYS="$1"
    if [[ "$SYS" == Ir_* ]] || [[ "$SYS" == Pt_* ]] || \
       [[ "$SYS" == CSD_Ir* ]] || [[ "$SYS" == CSD_Pt* ]]; then
        echo "12G"
    elif [[ "$SYS" == Mo_* ]] || [[ "$SYS" == Ru_* ]] || \
         [[ "$SYS" == Rh_* ]] || [[ "$SYS" == Pd_* ]] || \
         [[ "$SYS" == CSD_Mo* ]] || [[ "$SYS" == CSD_Ru* ]] || \
         [[ "$SYS" == CSD_Rh* ]] || [[ "$SYS" == CSD_Pd* ]]; then
        echo "10G"
    else
        echo "8G"
    fi
}

# ── Submit ─────────────────────────────────────────────────────────────────
source ~/.autocas_env.sh 2>/dev/null || true

echo "========================================"
echo " autoCAS M=250 — 50 systems"
echo " HIGH:   15 jobs"
echo " MEDIUM: 20 jobs"
echo " LOW:    15 jobs"
echo "========================================"
echo ""

echo "--- HIGH SPIN (15) ---"
for SYS in "${HIGH_SPIN[@]}"; do
    submit_job "$SYS" "high" "$(get_walltime $SYS)" "$(get_mem $SYS)"
done

echo ""
echo "--- MEDIUM SPIN (20) ---"
for SYS in "${MEDIUM_SPIN[@]}"; do
    submit_job "$SYS" "medium" "$(get_walltime $SYS)" "$(get_mem $SYS)"
done

echo ""
echo "--- LOW SPIN (15) ---"
for SYS in "${LOW_SPIN[@]}"; do
    submit_job "$SYS" "low" "$(get_walltime $SYS)" "$(get_mem $SYS)"
done

echo ""
echo "All 50 jobs submitted."
echo "Logs: $LOG_DIR/"
echo ""
echo "Monitor: squeue -u \$USER"
echo "Results: bash check_m250_results.sh"
