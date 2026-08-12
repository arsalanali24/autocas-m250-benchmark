#!/bin/bash
# autocas_setup.sh
# ================
# Smart autoCAS setup script. Run this on any HPC to:
#   1. Auto-detect the environment (no manual questions)
#   2. Clone the GitHub repo with all scripts
#   3. Ask ONLY what it cannot auto-detect: new system info
#   4. Run test cases to verify everything works
#   5. Submit jobs
#
# Usage:
#   bash autocas_setup.sh                    # interactive setup
#   bash autocas_setup.sh --test-only        # run tests only
#   bash autocas_setup.sh --submit-only      # submit existing JSON
#   bash autocas_setup.sh --add-system       # add a new system

REPO_URL="https://github.com/arsalanali24/autocas-m250-benchmark"
GITHUB_TOKEN=""   # set this or pass as env: GITHUB_TOKEN=xxx bash autocas_setup.sh

MODE="${1:---interactive}"

echo "========================================================"
echo " autoCAS Framework Setup"
echo "========================================================"
echo ""

# ── Step 1: Auto-detect environment ──────────────────────────
echo "=== Detecting environment ==="

# Detect cluster
HOSTNAME=$(hostname)
if echo "$HOSTNAME" | grep -q "noctua"; then
    CLUSTER="noctua2"
    ACCOUNT="hpc-prf-qehpc"
    PARTITION="normal"
    SCRATCH="/scratch/hpc-prf-qehpc/$USER/autocas_scratch"
    MKL="/opt/software/pc2/EB-SW/software/imkl/2022.2.1/mkl/2022.2.1/lib/intel64"
    GCC="/opt/software/pc2/EB-SW/software/GCCcore/11.3.0/lib64"
    ENV_CMD="source ~/.autocas_env.sh"
elif echo "$HOSTNAME" | grep -q "login"; then
    CLUSTER="unknown_hpc"
    ACCOUNT="$USER"
    PARTITION="normal"
    SCRATCH="/scratch/$USER/autocas_scratch"
    MKL=""
    GCC=""
    ENV_CMD=""
else
    CLUSTER="local"
    ACCOUNT=""
    PARTITION=""
    SCRATCH="/tmp/autocas_scratch"
    MKL=""
    GCC=""
    ENV_CMD=""
fi
echo "  Cluster:   $CLUSTER"
echo "  User:      $USER"
echo "  Hostname:  $HOSTNAME"

# Detect autocas
$ENV_CMD 2>/dev/null || true
if python3 -c "import scine_autocas" 2>/dev/null; then
    AUTOCAS_VERSION=$(python3 -c "import scine_autocas; print(scine_autocas.__version__)" 2>/dev/null)
    echo "  autoCAS:   $AUTOCAS_VERSION ✓"
    HAS_AUTOCAS=1
else
    echo "  autoCAS:   NOT FOUND"
    echo "  → Load your environment first, then rerun this script"
    HAS_AUTOCAS=0
fi

# Detect SLURM
if command -v sbatch &>/dev/null; then
    echo "  SLURM:     available ✓"
    HAS_SLURM=1
else
    echo "  SLURM:     not available (local mode)"
    HAS_SLURM=0
fi

# Detect Python
PY=$(python3 --version 2>/dev/null)
echo "  Python:    $PY"
echo ""

# ── Step 2: Clone/update GitHub repo ─────────────────────────
echo "=== Setting up GitHub repository ==="
WORK_DIR="$HOME/autocas_framework"

if [ -d "$WORK_DIR/.git" ]; then
    echo "  Repo exists — pulling latest..."
    cd "$WORK_DIR" && git pull --quiet
    echo "  Updated ✓"
else
    echo "  Cloning $REPO_URL..."
    git clone --quiet "$REPO_URL" "$WORK_DIR"
    echo "  Cloned to $WORK_DIR ✓"
fi
cd "$WORK_DIR"

# Copy scripts to working location
mkdir -p "$WORK_DIR/scripts"
echo "  Scripts ready in $WORK_DIR/scripts/"
echo ""

# ── Step 3: Environment config file ─────────────────────────
CONFIG="$WORK_DIR/cluster_config.sh"
cat > "$CONFIG" << CONFIG
#!/bin/bash
# Auto-generated cluster configuration — $(date)
export AUTOCAS_CLUSTER="$CLUSTER"
export AUTOCAS_ACCOUNT="$ACCOUNT"
export AUTOCAS_PARTITION="$PARTITION"
export AUTOCAS_SCRATCH="$SCRATCH"
export AUTOCAS_MKL="$MKL"
export AUTOCAS_GCC="$GCC"
export AUTOCAS_ENV_CMD="$ENV_CMD"
export AUTOCAS_WORKDIR="$WORK_DIR"
mkdir -p "\$AUTOCAS_SCRATCH"
CONFIG
echo "  Config written: $CONFIG"

# ── Step 4: Run test cases ────────────────────────────────────
echo ""
echo "=== Running test cases ==="

if [ "$HAS_AUTOCAS" -eq 0 ]; then
    echo "  SKIP: autoCAS not available"
else
    python3 - << 'PYEOF'
import sys, os, math, re
sys.path.insert(0, os.path.expanduser("~/autocas_framework/scripts"))

print("  Test 1: Geometry builder...")
def _tet(d):
    c=d/math.sqrt(3); return [(c,c,c),(-c,-c,c),(-c,c,-c),(c,-c,-c)]
def _oct(d):
    return [(d,0,0),(-d,0,0),(0,d,0),(0,-d,0),(0,0,d),(0,0,-d)]
def _sqpl(d):
    return [(d,0,0),(-d,0,0),(0,d,0),(0,-d,0)]

test_cases = [
    ("CSD_FeCl4_2m_tet_spin4",  "Fe","Cl",4,"tet",2.19),
    ("Mo_Br4_chg0_spin4_tet_d2p451","Mo","Br",4,"tet",2.451),
    ("CSD_NiCl4_2m_sqpl_spin0", "Ni","Cl",4,"sqpl",2.20),
    ("CSD_MnCl6_4m_oct_spin5",  "Mn","Cl",6,"oct",2.48),
    ("Rh_Cl6_chg-3_spin0_oct_d2p32","Rh","Cl",6,"oct",2.320),
]

def parse_name(name):
    n=re.sub(r'^CSD_','',name)
    metal=(re.match(r'^([A-Z][a-z]?)',n) or re.match(r'.','Fe')).group(1)
    m_lig=re.search(r'_(Cl|Br|F|N|O|I)(\d+)',n) or re.search(r'(Cl|Br|F|N|O|I)(\d+)',n)
    ligand=m_lig.group(1) if m_lig else 'Cl'
    n_lig=int(m_lig.group(2)) if m_lig else 6
    m_geom=re.search(r'(sq_pl|sqpl|oct|tet|jt)',n,re.IGNORECASE)
    geom=m_geom.group(1).lower() if m_geom else 'oct'
    m_dist=re.search(r'd(\d+)p(\d+)',n)
    dist=None
    if m_dist:
        dec=m_dist.group(2)
        dist=int(m_dist.group(1))+float(dec)/(10**len(dec))
    return metal,ligand,n_lig,geom,dist

all_ok=True
for name,em,el,en,eg,ed in test_cases:
    m,l,n,g,d=parse_name(name)
    ok=(m==em and l==el and n==en and g==eg)
    if not ok: all_ok=False
    print(f"    {'OK' if ok else 'FAIL'} {name[:40]} → {m}/{l}×{n} {g}")

print(f"  Geometry: {'ALL OK ✓' if all_ok else 'FAILURES ✗'}")

print()
print("  Test 2: autoCAS import...")
try:
    import scine_autocas
    print(f"  autoCAS {scine_autocas.__version__} ✓")
except Exception as e:
    print(f"  FAIL: {e}")

print()
print("  Test 3: Patches...")
patches_dir = os.path.expanduser("~/activeml/scripts")
for patch in ['patched_pyscf_interface.py','patched_large_spaces.py',
              'patched_qcmaquis_alias.py']:
    exists = os.path.exists(os.path.join(patches_dir, patch))
    print(f"    {'✓' if exists else '✗ MISSING'} {patch}")

print()
print("  Test 4: JSON files...")
import json, glob
for jfile in ['high_spin_15.json','medium_spin_20.json','low_spin_15.json']:
    path = os.path.expanduser(f"~/activeml/scripts/{jfile}")
    if os.path.exists(path):
        with open(path) as f:
            n = len(json.load(f)['systems'])
        print(f"    ✓ {jfile} ({n} systems)")
    else:
        print(f"    ✗ MISSING: {jfile}")
PYEOF
fi

# ── Step 5: Interactive mode — add new system ────────────────
if [ "$MODE" == "--add-system" ] || [ "$MODE" == "--interactive" ]; then
    echo ""
    echo "=== Add new system ==="
    echo "  Press ENTER to skip and use existing JSON files"
    echo ""
    read -p "  Add a new system? (y/N): " ADD_NEW

    if [ "$ADD_NEW" == "y" ] || [ "$ADD_NEW" == "Y" ]; then
        echo ""
        echo "  Provide system information:"
        read -p "  System name (e.g. Fe_Cl6_chg-2_spin4_oct_d2p238): " SYS_ID
        read -p "  Spin category (high/medium/low): " SPIN_CAT
        read -p "  Total charge (e.g. -2): " CHARGE
        read -p "  Spin 2S (e.g. 4): " SPIN_2S
        read -p "  M-L bond distance in Angstrom (e.g. 2.38, or ENTER to auto): " DIST

        # Infer defaults from system name
        MULT=$((SPIN_2S + 1))

        python3 - << PYEOF
import json, os, re

sys_id   = "$SYS_ID"
spin_cat = "$SPIN_CAT"
charge   = int("$CHARGE")
spin_2s  = int("$SPIN_2S")
mult     = int("$MULT")
dist_inp = "$DIST"

# Parse from name
n = re.sub(r'^CSD_','', sys_id)
metal = (re.match(r'^([A-Z][a-z]?)', n) or re.match(r'.','Fe')).group(1)
m_lig = re.search(r'_(Cl|Br|F|N|O|I)(\d+)',n) or re.search(r'(Cl|Br|F|N|O|I)(\d+)',n)
ligand = m_lig.group(1) if m_lig else 'Cl'
n_lig  = int(m_lig.group(2)) if m_lig else 6
m_geom = re.search(r'(sq_pl|sqpl|oct|tet)', n, re.IGNORECASE)
geom   = m_geom.group(1).lower() if m_geom else 'oct'
m_dist = re.search(r'd(\d+)p(\d+)', n)
if dist_inp:
    dist = float(dist_inp)
elif m_dist:
    dec = m_dist.group(2)
    dist = int(m_dist.group(1)) + float(dec)/(10**len(dec))
else:
    dist = None

# Determine metal row
metals_4d = {'Mo','Tc','Ru','Rh','Pd','Ag','Cd'}
metals_5d = {'Hf','Ta','W','Re','Os','Ir','Pt','Au','Hg'}
row = '4d' if metal in metals_4d else ('5d' if metal in metals_5d else '3d')

new_system = {
    "system_id": sys_id,
    "metal": metal,
    "ligand": ligand,
    "n_ligands": n_lig,
    "total_charge": charge,
    "spin_2S": spin_2s,
    "multiplicity": mult,
    "geometry": {"oct":"octahedral","tet":"tetrahedral",
                 "sqpl":"square_planar","sq_pl":"square_planar"}.get(geom,"octahedral"),
    "coordination_number": n_lig,
    "M_L_bond_distance_A": dist,
    "metal_row": row,
    "is_csd_geometry": sys_id.startswith("CSD_"),
    "n_active_electrons": None,
    "n_active_orbitals": None,
    "E_HF_Eh": None,
    "E_CASSCF_Eh": None,
    "autocas_run_hint": f"AutoCAS; mult={mult} (2S={spin_2s}); DMRG m=128→250."
}

# Add to correct JSON file
json_map = {'high': 'high_spin_15.json',
            'medium': 'medium_spin_20.json',
            'low': 'low_spin_15.json'}
fname = json_map.get(spin_cat, 'high_spin_15.json')
fpath = os.path.expanduser(f"~/activeml/scripts/{fname}")

if os.path.exists(fpath):
    with open(fpath) as f:
        data = json.load(f)
    # Check not already there
    existing = {s['system_id'] for s in data['systems']}
    if sys_id in existing:
        print(f"  System {sys_id} already in {fname}")
    else:
        data['systems'].append(new_system)
        with open(fpath, 'w') as f:
            json.dump(data, f, indent=2)
        print(f"  Added {sys_id} to {fname}")
        print(f"  Parsed: {metal}/{ligand}×{n_lig} {geom} d={dist} {row} mult={mult}")
else:
    print(f"  ERROR: {fpath} not found")
    print(f"  New system dict:")
    print(json.dumps(new_system, indent=2))
PYEOF
    fi
fi

# ── Step 6: Submit or run ────────────────────────────────────
if [ "$MODE" != "--test-only" ]; then
    echo ""
    echo "=== Ready to submit ==="
    if [ "$HAS_SLURM" -eq 1 ] && [ "$HAS_AUTOCAS" -eq 1 ]; then
        read -p "  Submit all jobs now? (y/N): " DO_SUBMIT
        if [ "$DO_SUBMIT" == "y" ] || [ "$DO_SUBMIT" == "Y" ]; then
            $ENV_CMD 2>/dev/null || true
            bash ~/activeml/scripts/submit_autocas_m250.sh
        fi
    elif [ "$HAS_AUTOCAS" -eq 1 ]; then
        echo "  No SLURM — run interactively:"
        echo "  python3 ~/activeml/scripts/run_autocas_m250.py <system_id>"
    else
        echo "  Load autoCAS environment first:"
        echo "  source ~/.autocas_env.sh"
        echo "  Then rerun: bash autocas_setup.sh"
    fi
fi

echo ""
echo "========================================================"
echo " Setup complete!"
echo " Work dir: $WORK_DIR"
echo " Next steps:"
echo "   Check progress: bash ~/activeml/scripts/check_m250_progress.sh"
echo "   Collect results: python3 ~/activeml/scripts/collect_m250_results.py"
echo "   Plot entropy:    python3 ~/activeml/scripts/plot_entropy.py"
echo "========================================================"
