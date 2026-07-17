#!/bin/bash
# check_m250_progress.sh
# Quick status check during the run.
# Usage: bash check_m250_progress.sh

LOG_DIR="/scratch/hpc-prf-qehpc/hpcmual/autocas_scratch/m250_logs"
SCRIPTS="$(cd "$(dirname "$0")" && pwd)"

echo "========================================"
echo " M=250 PROGRESS — $(date '+%Y-%m-%d %H:%M')"
echo "========================================"
echo ""

# Queue
RUNNING=$(squeue -u $USER --noheader 2>/dev/null | grep -c "m250_")
echo "Queue: $RUNNING M=250 jobs running"
squeue -u $USER --noheader 2>/dev/null | grep "m250_" | \
    awk '{printf "  %-20s ST=%-2s TIME=%-8s NODE=%s\n",$3,$5,$6,$8}'
echo ""

# Results per spin category
for CAT in high medium low; do
    case $CAT in
        high)   SYSTEMS=(CSD_RuCl4O2_trans_spin4 CSD_MoCl3O3_fac_spin3 CSD_VCl6_3m_dist_spin4 CSD_MnCl4O2_trans_spin3 CSD_FeCl4N2_cis_spin4 Rh_Br6_chg-3_spin4_oct_d2p356 Pd_Br6_chg-2_spin4_oct_d2p337 Ru_Br4_chg-2_spin4_tet_d2p375 Mo_Br4_chg0_spin4_tet_d2p451 Ir_Br6_chg-3_spin4_oct_d2p384 Pt_Br6_chg-2_spin4_oct_d2p328 Ti_Br6_chg0_spin4_oct_d2p259 V_Br4_chg-2_spin3_tet_d2p318 Mn_Br4_chg-1_spin4 Fe_Br6_chg-1_spin3) ;;
        medium) SYSTEMS=(CSD_RhCl2N2_1m_sqpl_spin2 CSD_PdBr4_2m_sqpl_spin2 CSD_RuCl4O2_trans_spin2 CSD_MoOCl6_2m_capoct_spin2 CSD_IrBr6_3m_oct_spin2 Rh_Br4_chg-1_spin2_tet_d2p356 Pd_Br4_chg-2_spin2_sq_pl_d2p337 Ru_Br4_chg-2_spin2_tet_d2p375 Mo_Br4_chg0_spin2_tet_d2p451 Ir_Br6_chg-3_spin2_oct_d2p384 Pt_Br4_chg-2_spin2_sq_pl_d2p328 Ti_Br4_chg-2_spin2_tet_d2p635 V_Br6_chg-3_spin2_oct_d2p318 Mn_Br4_chg-1_spin2 Fe_Br6_chg-2_spin2 Cr_Br4_chg-2_spin2 Ni_Br6_chg-4_spin2 Cu_Br6_chg-3_spin2 Co_Br4_chg-1_spin2 Rh_Br4_chg-1_spin2_tet_d2p48) ;;
        low)    SYSTEMS=(CSD_RhBr6_3m_oct_spin0 CSD_PdBr4_2m_sqpl_spin0 CSD_RuCl4O2_trans_spin0 CSD_MoCl3O3_fac_spin1 CSD_IrBr6_3m_oct_spin0 Rh_Br4_chg-1_spin0_tet_d2p356 Pd_Br4_chg-2_spin0_sq_pl_d2p337 Ru_Br4_chg-2_spin0_tet_d2p375 Mo_Br4_chg0_spin0_tet_d2p451 Ir_Br6_chg-3_spin0_oct_d2p384 Pt_Br4_chg-2_spin0_sq_pl_d2p328 Ti_Br4_chg-3_spin1_tet_d2p259 V_Br6_chg-2_spin1_oct_d2p318 Zn_Br4_chg-2_spin0_tet_d2p289 Mn_Br4_chg-1_spin0) ;;
    esac

    echo "--- ${CAT^^} SPIN (${#SYSTEMS[@]}) ---"
    NDONE=0; NFAIL=0; NRUN=0
    for SYS in "${SYSTEMS[@]}"; do
        log=$(ls "$LOG_DIR/${CAT}_${SYS}_"*.log 2>/dev/null | sort | tail -1)
        [ -z "$log" ] && log=$(ls "$LOG_DIR/${SYS}_"*.log 2>/dev/null | sort | tail -1)

        if [ -z "$log" ]; then
            printf "  %-44s  QUEUED\n" "$SYS"
        else
            occ=$(awk '/^  final_occupation:/{f=1;next} f{print;exit}' "$log" 2>/dev/null)
            err=$(grep "^\[error\]" "$log" 2>/dev/null | tail -1 | cut -c1-60)
            fin=$(grep "^Finished:" "$log" 2>/dev/null)
            sweeps=$(grep -c "[Ss]weep" "$log" 2>/dev/null || echo 0)
            scf=$(grep -c "converged SCF" "$log" 2>/dev/null || echo 0)

            if [ -n "$occ" ]; then
                result=$(python3 -c "occ=$occ; print(f'CAS({sum(occ):.0f},{len(occ)})')" 2>/dev/null)
                printf "  %-44s  DONE  %s\n" "$SYS" "$result"
                ((NDONE++))
            elif [ -n "$err" ]; then
                printf "  %-44s  FAIL  %s\n" "$SYS" "${err:8:50}"
                ((NFAIL++))
            elif [ -z "$fin" ]; then
                printf "  %-44s  RUN   SCF=%s DMRG_sweeps=%s\n" "$SYS" "$scf" "$sweeps"
                ((NRUN++))
            else
                printf "  %-44s  DONE? (no occupation yet)\n" "$SYS"
                ((NDONE++))
            fi
        fi
    done
    echo "  → Done=$NDONE  Running=$NRUN  Failed=$NFAIL"
    echo ""
done

echo "To collect final results:"
echo "  python3 $SCRIPTS/collect_m250_results.py"
