#!/bin/bash
# =============================================================================
# qsub_script_100taxa.sh
#
# Submits 100taxa_1000000sites CSV-driven IQ-TREE tests to the NCI cluster.
# This script mirrors qsub_script.sh but uses the CSV test matrix and the
# test_script_iqtree_100taxa.sh runner.
#
# Positional arguments:
#   $1   IQTREE           - boolean, whether IQ-TREE should run
#   $2   V100_GPU         - boolean, use V100 queue
#   $3   A100_GPU         - boolean, use A100 queue
#   $4   WD               - working directory on cluster
#   $5   DATASET_BASE     - base path to 100taxa_1000000sites data
#   $6   UNIQUE_NAME      - unique run identifier
#   $7   AA               - boolean, include AA
#   $8   DNA              - boolean, include DNA
#   $9   factor           - walltime / memory multiplier
#   $10  repeat           - number of repetitions
#   $11  PROJECT_NAME     - NCI project code
#   $12  TYPE             - backend: VANILA | CUDA | OPENACC | OPENACC_PROFILE
#   $13  H200             - boolean, use H200 queue
#   $14  ALL_NODE         - boolean, use whole node
#   $15  IQTREE_ARGS      - extra IQ-TREE arguments (quoted)
# =============================================================================

set -uo pipefail

IQTREE=$1
V100_GPU=$2
A100_GPU=$3
WD=$4
DATASET_BASE=$5
UNIQUE_NAME=$6
AA=$7
DNA=$8
factor=$9
repeat=${10}

PROJECT_NAME=${11}
TYPE=${12}
H200=${13}
ALL_NODE=${14}
IQTREE_ARGS=${15:-}

CSV_FILE="$WD/test/iqtree/100taxa_1000000sites_tests.csv"

# ---------------------------------------------------------------------------
# Determine data-type filter for the test script
# ---------------------------------------------------------------------------
data_types=()
if [ "$AA" == true ] && [ "$DNA" == true ]; then
    data_types+=("ALL")
elif [ "$AA" == true ]; then
    data_types+=("AA")
elif [ "$DNA" == true ]; then
    data_types+=("DNA")
fi

# ---------------------------------------------------------------------------
# Wall-time calculation
# ---------------------------------------------------------------------------
base_walltime="00:30:00"       # 100-taxa with many models needs more time
if [ "$V100_GPU" == true ] || [ "$A100_GPU" == true ] || [ "$H200" == true ]; then
    base_walltime="00:20:00"
fi

IFS=: read -r h m s <<< "$base_walltime"
total_seconds=$((10#$h * 3600 + 10#$m * 60 + 10#$s))
scaled_seconds=$((total_seconds * factor))

printf -v wall_time "%02d:%02d:%02d" \
    $((scaled_seconds / 3600)) \
    $(((scaled_seconds % 3600) / 60)) \
    $((scaled_seconds % 60))

# ---------------------------------------------------------------------------
# Submit jobs
# ---------------------------------------------------------------------------
for r in $(seq 1 $repeat); do
    local_unique_name="${UNIQUE_NAME}_run${r}"

    for data_type_filter in "${data_types[@]}"; do

        if [ "$V100_GPU" == true ]; then
            memory=$((factor * 1 * 48))
            qsub -P${PROJECT_NAME} \
                -lwalltime=$wall_time,ncpus=12,ngpus=1,mem="${memory}GB",jobfs=10GB,wd \
                -qgpuvolta \
                -N "test_100taxa_v100_${TYPE}" \
                -vARG1="$DATASET_BASE",ARG2="$local_unique_name",ARG3="$WD",ARG4="$data_type_filter",ARG5="$TYPE",ARG6="$CSV_FILE",ARG7="$IQTREE_ARGS" \
                "$WD"/test/iqtree/test_script_iqtree_100taxa.sh

        elif [ "$A100_GPU" == true ]; then
            memory=$((factor * 1 * 64))
            qsub -P${PROJECT_NAME} \
                -lwalltime=$wall_time,ncpus=16,ngpus=1,mem="${memory}GB",jobfs=10GB,wd \
                -qdgxa100 \
                -N "test_100taxa_a100_${TYPE}" \
                -vARG1="$DATASET_BASE",ARG2="$local_unique_name",ARG3="$WD",ARG4="$data_type_filter",ARG5="$TYPE",ARG6="$CSV_FILE",ARG7="$IQTREE_ARGS" \
                "$WD"/test/iqtree/test_script_iqtree_100taxa.sh

        elif [ "$H200" == true ]; then
            if [ "$ALL_NODE" == true ]; then
                memory=$((factor * 4 * 48))
                qsub -P${PROJECT_NAME} \
                    -lwalltime=$wall_time,ncpus=48,ngpus=4,mem="${memory}GB",jobfs=10GB,wd \
                    -qgpuhopper \
                    -N "test_100taxa_h200_all_${TYPE}" \
                    -vARG1="$DATASET_BASE",ARG2="$local_unique_name",ARG3="$WD",ARG4="$data_type_filter",ARG5="$TYPE",ARG6="$CSV_FILE",ARG7="$IQTREE_ARGS" \
                    "$WD"/test/iqtree/test_script_iqtree_100taxa.sh
            else
                memory=$((factor * 1 * 48))
                qsub -P${PROJECT_NAME} \
                    -lwalltime=$wall_time,ncpus=12,ngpus=1,mem="${memory}GB",jobfs=10GB,wd \
                    -qgpuhopper \
                    -N "test_100taxa_h200_${TYPE}" \
                    -vARG1="$DATASET_BASE",ARG2="$local_unique_name",ARG3="$WD",ARG4="$data_type_filter",ARG5="$TYPE",ARG6="$CSV_FILE",ARG7="$IQTREE_ARGS" \
                    "$WD"/test/iqtree/test_script_iqtree_100taxa.sh
            fi

        elif [ "$IQTREE" == true ]; then
            # CPU-only (VANILA backend, no GPU)
            memory=$((factor * 1 * 20))
            qsub -P${PROJECT_NAME} \
                -lwalltime=$wall_time,ncpus=1,mem="${memory}GB",jobfs=10GB,wd \
                -qnormal \
                -N "test_100taxa_cpu_${TYPE}" \
                -vARG1="$DATASET_BASE",ARG2="$local_unique_name",ARG3="$WD",ARG4="$data_type_filter",ARG5="$TYPE",ARG6="$CSV_FILE",ARG7="$IQTREE_ARGS" \
                "$WD"/test/iqtree/test_script_iqtree_100taxa.sh
        fi

    done
done
