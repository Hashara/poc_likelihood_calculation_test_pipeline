#!/bin/bash

# this script for submitting jobs to a cluster using qsub

IQTREE=$1 # boolean for whether to build IQTREE
V100_GPU=$2
A100_GPU=$3
WD=$4
DATASET_DIR=$5
UNIQUE_NAME=$6
AA=$7
DNA=$8
length=$9
mem_factor=${10}
repeat=${11}

IQTREE_OPENMP=${12}
IQTREE_THREADS=${13}
IQTREE_AUTO=${14}

PROJECT_NAME=${15}

TYPE=${16}
H200=${17}
ALL_NODE=${18}
IQTREE_ARGS=${19}
NUM_TREES=${20:-10}
wall_time_factor=${21:-1}
TREE_MODE=${22:-te}
NORMALSR=${23:-false}
# ${24} is ENV_VARS (passed through by Jenkins but consumed by profile_*_qsub_script.sh, not here)
RESERVE_FULL_NODE=${25:-false}
# Codon rows. Added as a TRAILING positional with a false default so every existing
# 25-argument caller keeps working untouched.
CODON=${26:-false}

# Determine CPU queue name and per-CPU memory ratio
# normal: 190 GB / 48 CPUs = ~3.96 GB/CPU → 4 GB
# normalsr: 500 GB / 104 CPUs = ~4.81 GB/CPU → 5 GB
if [ "$NORMALSR" == true ]; then
    CPU_QUEUE="normalsr"
    MEM_PER_CPU=5
else
    CPU_QUEUE="normal"
    MEM_PER_CPU=4
fi

# ---------------------------------------------------------------------------------
# Which data types to submit.
#
# THE BUG THIS FIXES. This array used to be built from $AA and $DNA only. The
# kingdoms orchestrator validates data_type against AA|DNA|Codon but passes only the
# DNA and AA booleans downstream, so a Codon row arrived with BOTH false, the array
# came out empty, the submission loop below iterated zero times, no qsub was ever
# issued -- and the script still exited 0, so Jenkins reported the stage GREEN. Four
# Codon rows of the 2026-08-25 dryrun_all sweep vanished exactly this way: no job, no
# output directory, no log, no error.
# ---------------------------------------------------------------------------------
data_types=()
if [ "$AA" == true ]; then
    data_types+=("AA")
fi
if [ "$DNA" == true ]; then
    data_types+=("DNA")
fi
if [ "$CODON" == true ]; then
    data_types+=("Codon")
fi

# Fallback for callers that do not pass ${26} yet. The kingdoms collection is laid out
# <root>/<kingdom>/<data_type>/<dataset>, so the data type is the parent directory of
# DATASET_DIR. Only the three known values are accepted; anything else is ignored and
# falls through to the hard error below, so a differently-shaped collection (the
# simulated layout ends in taxa_N/len_M) cannot inject a bogus value here.
if [ ${#data_types[@]} -eq 0 ]; then
    derived_type=$(basename "$(dirname "$DATASET_DIR")")
    case "$derived_type" in
        AA|DNA|Codon)
            data_types+=("$derived_type")
            echo "[qsub] no data-type flag set; derived '$derived_type' from DATASET_DIR"
            ;;
    esac
fi

# Hard stop. An empty array must never again mean "submit nothing and report success".
if [ ${#data_types[@]} -eq 0 ]; then
    echo "[qsub] ERROR: no data type selected (AA=$AA DNA=$DNA CODON=$CODON) and none could" >&2
    echo "[qsub]        be derived from DATASET_DIR='$DATASET_DIR'." >&2
    echo "[qsub]        No job would be submitted, so failing loudly instead of exiting 0." >&2
    exit 1
fi
echo "[qsub] data types to submit: ${data_types[*]}"

# wall_time_factor=1 → 10 minutes (600 seconds)
scaled_seconds=$((wall_time_factor * 600))

# Convert to HH:MM:SS
printf -v wall_time "%02d:%02d:%02d" \
  $((scaled_seconds / 3600)) \
  $(((scaled_seconds % 3600) / 60)) \
  $((scaled_seconds % 60))

for r in $(seq 1 $repeat); do
    local_unique_name="${UNIQUE_NAME}_run${r}"
  for data_type in "${data_types[@]}"; do
      # GPU branches are mutually exclusive — orchestrator sets exactly one of V100/A100/H200
      # per row from the CSV gpu_type column. ARG10=GPU_TYPE (lowercase) tells the test
      # script which per-arch build dir to pick (build-nvhpc-openacc-{v100,a100,h200}/).
      if [ "$V100_GPU" == true ]; then
        memory=$((mem_factor * 1 * 48))
          export ARG1="$DATASET_DIR" ARG2="$local_unique_name" ARG3="$WD" ARG4="$data_type" ARG5="$length" ARG6="$TYPE" ARG7="$IQTREE_ARGS" ARG8="$NUM_TREES" ARG9="$TREE_MODE" ARG10="v100" OUTPUT_DIR="${OUTPUT_DIR:-}" DATASET_ROOT="${DATASET_ROOT:-}"
          echo "[qsub] V100: walltime=$wall_time mem=${memory}GB ARG1=$ARG1 ARG2=$ARG2 ARG3=$ARG3 ARG4=$ARG4 ARG5=$ARG5 ARG6=$ARG6 ARG7='$ARG7' ARG8=$ARG8 ARG9=$ARG9 ARG10=$ARG10"
          qsub -P${PROJECT_NAME} -lwalltime=$wall_time,ncpus=12,ngpus=1,mem="${memory}GB",jobfs=10GB,wd -qgpuvolta -N test_v100 \
                -v ARG1,ARG2,ARG3,ARG4,ARG5,ARG6,ARG7,ARG8,ARG9,ARG10,OUTPUT_DIR,DATASET_ROOT "$WD"/test/iqtree/test_script_iqtree.sh

      elif [ "$A100_GPU" == true ]; then
          memory=$((mem_factor * 1 * 64))
          export ARG1="$DATASET_DIR" ARG2="$local_unique_name" ARG3="$WD" ARG4="$data_type" ARG5="$length" ARG6="$TYPE" ARG7="$IQTREE_ARGS" ARG8="$NUM_TREES" ARG9="$TREE_MODE" ARG10="a100" OUTPUT_DIR="${OUTPUT_DIR:-}" DATASET_ROOT="${DATASET_ROOT:-}"
          echo "[qsub] A100: walltime=$wall_time mem=${memory}GB ARG1=$ARG1 ARG2=$ARG2 ARG3=$ARG3 ARG4=$ARG4 ARG5=$ARG5 ARG6=$ARG6 ARG7='$ARG7' ARG8=$ARG8 ARG9=$ARG9 ARG10=$ARG10"
          qsub -P${PROJECT_NAME} -lwalltime=$wall_time,ncpus=16,ngpus=1,mem="${memory}GB",jobfs=10GB,wd -qdgxa100 -N test_a100 \
                -v ARG1,ARG2,ARG3,ARG4,ARG5,ARG6,ARG7,ARG8,ARG9,ARG10,OUTPUT_DIR,DATASET_ROOT "$WD"/test/iqtree/test_script_iqtree.sh

      elif [ "$H200" == true ]; then
          memory=$((mem_factor * 1 * 48))
          export ARG1="$DATASET_DIR" ARG2="$local_unique_name" ARG3="$WD" ARG4="$data_type" ARG5="$length" ARG6="$TYPE" ARG7="$IQTREE_ARGS" ARG8="$NUM_TREES" ARG9="$TREE_MODE" ARG10="h200" OUTPUT_DIR="${OUTPUT_DIR:-}" DATASET_ROOT="${DATASET_ROOT:-}"
          echo "[qsub] H200: walltime=$wall_time mem=${memory}GB ARG1=$ARG1 ARG2=$ARG2 ARG3=$ARG3 ARG4=$ARG4 ARG5=$ARG5 ARG6=$ARG6 ARG7='$ARG7' ARG8=$ARG8 ARG9=$ARG9 ARG10=$ARG10"
          qsub -P${PROJECT_NAME} -lwalltime=$wall_time,ncpus=12,ngpus=1,mem="${memory}GB",jobfs=10GB,wd -qgpuhopper -N test_h200 \
                -v ARG1,ARG2,ARG3,ARG4,ARG5,ARG6,ARG7,ARG8,ARG9,ARG10,OUTPUT_DIR,DATASET_ROOT "$WD"/test/iqtree/test_script_iqtree.sh

      elif [ "$IQTREE" == true ]; then
          memory=$((mem_factor * 1 * 20))
          export ARG1="$DATASET_DIR" ARG2="$local_unique_name" ARG3="$WD" ARG4="$data_type" ARG5="$length" ARG6="$TYPE" ARG7="$IQTREE_ARGS" ARG8="$NUM_TREES" ARG9="$TREE_MODE" ARG10="" OUTPUT_DIR="${OUTPUT_DIR:-}" DATASET_ROOT="${DATASET_ROOT:-}"
          echo "[qsub] CPU: walltime=$wall_time mem=${memory}GB ARG1=$ARG1 ARG2=$ARG2 ARG3=$ARG3 ARG4=$ARG4 ARG5=$ARG5 ARG6=$ARG6 ARG7='$ARG7' ARG8=$ARG8 ARG9=$ARG9"
         qsub -P${PROJECT_NAME} -lwalltime=$wall_time,ncpus=1,mem="${memory}GB",jobfs=10GB,wd -q${CPU_QUEUE} -N test_iqtree \
                -v ARG1,ARG2,ARG3,ARG4,ARG5,ARG6,ARG7,ARG8,ARG9,ARG10,OUTPUT_DIR,DATASET_ROOT "$WD"/test/iqtree/test_script_iqtree.sh
      fi

      if [ "$IQTREE_OPENMP" == true ]; then
          memory=$((mem_factor * IQTREE_THREADS * MEM_PER_CPU))
          # Cap memory at the full-node budget: normalsr 104 threads → 500 GB, normal 48 threads → 190 GB
          if [ "$NORMALSR" == true ] && [ "$IQTREE_THREADS" == "104" ]; then
              memory=500
          elif [ "$NORMALSR" == false ] && [ "$IQTREE_THREADS" == "48" ]; then
              memory=190
          fi
          # Whole-node reservation (opt-in): keep ncpus at the full node count but pass
          # -nt = ncpus-1 to iqtree so one core is left idle for the OS.
          # normalsr full node = 104 → -nt 103; normal full node = 48 → -nt 47.
          if [ "$RESERVE_FULL_NODE" == true ] && [ "$NORMALSR" == true ] && [ "$IQTREE_THREADS" == "104" ]; then
              iqtree_nt=103
          elif [ "$RESERVE_FULL_NODE" == true ] && [ "$NORMALSR" == false ] && [ "$IQTREE_THREADS" == "48" ]; then
              iqtree_nt=47
          else
              iqtree_nt=$IQTREE_THREADS
          fi
          # Strip _${TYPE} suffix appended by child pipeline, then substitute
          # run1 → run${r} so repetitions produce distinct output names
          omp_unique_base="${UNIQUE_NAME%_${TYPE}}"
          omp_unique="${omp_unique_base/run1/run${r}}"
          export ARG1="$DATASET_DIR" ARG2="$omp_unique" ARG3="$WD" ARG4="$data_type" ARG5="$length" ARG6="$IQTREE_THREADS" ARG7="$IQTREE_AUTO" ARG8="$IQTREE_ARGS" ARG9="$NUM_TREES" ARG10="$TREE_MODE" ARG11="$TYPE" ARG12="$iqtree_nt" OUTPUT_DIR="${OUTPUT_DIR:-}" DATASET_ROOT="${DATASET_ROOT:-}"
          echo "[qsub] OMP: walltime=$wall_time mem=${memory}GB ncpus=$IQTREE_THREADS nt=$iqtree_nt ARG1=$ARG1 ARG2=$ARG2 ARG3=$ARG3 ARG4=$ARG4 ARG5=$ARG5 ARG6=$ARG6 ARG7=$ARG7 ARG8='$ARG8' ARG9=$ARG9 ARG10=$ARG10 ARG11=$ARG11 ARG12=$ARG12"
         qsub -P${PROJECT_NAME} -lwalltime=$wall_time,ncpus=$IQTREE_THREADS,mem="${memory}GB",jobfs=10GB,wd -q${CPU_QUEUE} -N test_iqtree_omp \
                -v ARG1,ARG2,ARG3,ARG4,ARG5,ARG6,ARG7,ARG8,ARG9,ARG10,ARG11,ARG12,OUTPUT_DIR,DATASET_ROOT "$WD"/test/iqtree/test_script_iqtree_omp.sh
      fi
  done
done
