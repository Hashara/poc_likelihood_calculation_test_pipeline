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
factor=${10}
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

data_types=()
if [ "$AA" == true ]; then
    data_types+=("AA")
fi
if [ "$DNA" == true ]; then
    data_types+=("DNA")
fi

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
      if [ "$V100_GPU" == true ]; then
        memory=$((factor * 1 * 48))
          qsub -P${PROJECT_NAME} -lwalltime=$wall_time,ncpus=12,ngpus=1,mem="${memory}GB",jobfs=10GB,wd -qgpuvolta -N test_v100 \
                -vARG1="$DATASET_DIR",ARG2="$local_unique_name",ARG3="$WD",ARG4="$data_type",ARG5="$length",ARG6="$TYPE",ARG7="$IQTREE_ARGS",ARG8="$NUM_TREES",ARG9="$TREE_MODE" "$WD"/test/iqtree/test_script_iqtree.sh

#
#      if [ "$A100_GPU" == true ]; then
#        memory=$(echo "$factor * 0.5 * 64" | bc)
#         qsub -P${PROJECT_NAME} -lwalltime=$wall_time,ncpus=16,ngpus=1,mem="64GB",jobfs=10GB,wd -qdgxa100 -N test_a100 \
#                -vARG1="$DATASET_DIR",ARG2="$local_unique_name",ARG3="$WD",ARG4="$data_type",ARG5="A100",ARG6="$length",ARG7="$TYPE" "$WD"/test/test_script_poc.sh
#      fi
#
#      if [ "$H200" == true ]; then
#        if [ "$ALL_NODE" == true ]; then
#              memory=$((factor * 4 * 48))
#              qsub -P${PROJECT_NAME} -lwalltime=$wall_time,ncpus=48,ngpus=4,mem="${memory}GB",jobfs=10GB,wd -qgpuhopper -N test_h200_all \
#                                    -vARG1="$DATASET_DIR",ARG2="$local_unique_name",ARG3="$WD",ARG4="$data_type",ARG5="H200",ARG6="$length",ARG7="$TYPE" "$WD"/test/h200/run_test_per_gpu.sh
#          else
#                memory=$((factor * 1 * 48))
#                qsub -P${PROJECT_NAME} -lwalltime=$wall_time,ncpus=12,ngpus=1,mem="${memory}GB",jobfs=10GB,wd -qgpuhopper -N test_h200 \
#                          -vARG1="$DATASET_DIR",ARG2="$local_unique_name",ARG3="$WD",ARG4="$data_type",ARG5="H200",ARG6="$length",ARG7="$TYPE" "$WD"/test/test_script_poc.sh
#          fi
#      fi
      elif [ "$IQTREE" == true ]; then
          memory=$((factor * 1 * 20))
         qsub -P${PROJECT_NAME} -lwalltime=$wall_time,ncpus=1,mem="${memory}GB",jobfs=10GB,wd -qnormal -N test_iqtree \
                -vARG1="$DATASET_DIR",ARG2="$local_unique_name",ARG3="$WD",ARG4="$data_type",ARG5="$length",ARG6="$TYPE",ARG7="$IQTREE_ARGS",ARG8="$NUM_TREES",ARG9="$TREE_MODE" "$WD"/test/iqtree/test_script_iqtree.sh
      fi

      if [ "$IQTREE_OPENMP" == true ]; then
          memory=$((factor * IQTREE_THREADS * 4))
          wall_time="1:00:00"
          # Strip _${TYPE} suffix appended by child pipeline, then substitute
          # run1 → run${r} so repetitions produce distinct output names
          omp_unique_base="${UNIQUE_NAME%_${TYPE}}"
          omp_unique="${omp_unique_base/run1/run${r}}"
         qsub -P${PROJECT_NAME} -lwalltime=$wall_time,ncpus=$IQTREE_THREADS,mem="${memory}GB",jobfs=10GB,wd -qnormal -N test_iqtree_omp \
                -vARG1="$DATASET_DIR",ARG2="$omp_unique",ARG3="$WD",ARG4="$data_type",ARG5="$length",ARG6="$IQTREE_THREADS",ARG7="$IQTREE_AUTO",ARG8="$IQTREE_ARGS",ARG9="$NUM_TREES",ARG10="$TREE_MODE" "$WD"/test/iqtree/test_script_iqtree_omp.sh
      fi
  done
done
