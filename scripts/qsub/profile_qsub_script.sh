#!/bin/bash

# this script for submitting jobs to a cluster using qsub

IQTREE=$1 # boolean for whether to build IQTREE
OPENACC_V100=$2
OPENACC_A100=$3
WD=$4
DATASET_DIR=$5
UNIQUE_NAME=$6
AA=$7
DNA=$8
length=$9
mem_factor=${10}
repeat=${11}
PROJECT_NAME=${12}
wall_time_factor=${13:-1}

data_types=()
if [ "$AA" = true ]; then
    data_types+=("AA")
fi
if [ "$DNA" = true ]; then
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
      if [ "$OPENACC_V100" = true ]; then
        memory=$((mem_factor * 1 * 48))
          qsub -P${PROJECT_NAME} -lwalltime=$wall_time,ncpus=12,ngpus=1,mem="${memory}GB",jobfs=30GB,wd -qgpuvolta -N test_v100 \
                -vARG1="$DATASET_DIR",ARG2="$local_unique_name",ARG3="$WD",ARG4="$data_type",ARG5="V100",ARG6="$length" "$WD"/profile/test_script_poc.sh
      fi

      if [ "$OPENACC_A100" = true ]; then
        memory=$(echo "$mem_factor * 0.5 * 64" | bc)
         qsub -P${PROJECT_NAME} -lwalltime=$wall_time,ncpus=16,ngpus=1,mem="64GB",jobfs=30GB,wd -qdgxa100 -N test_a100 \
                -vARG1="$DATASET_DIR",ARG2="$local_unique_name",ARG3="$WD",ARG4="$data_type",ARG5="A100",ARG6="$length" "$WD"/profile/test_script_poc.sh
      fi

      if [ "$IQTREE" = true ]; then
          memory=$((mem_factor * 1 * 20))
         qsub -P${PROJECT_NAME} -lwalltime=$wall_time,ncpus=1,mem="${memory}GB",jobfs=30GB,wd -qnormal -N test_iqtree \
                -vARG1="$DATASET_DIR",ARG2="$local_unique_name",ARG3="$WD",ARG4="$data_type",ARG5="$length" "$WD"/test/test_script_iqtree.sh
      fi
  done
done
