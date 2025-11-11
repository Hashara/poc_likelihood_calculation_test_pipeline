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
factor=${10}
repeat=${11}

IQTREE_OPENMP=${12}
IQTREE_THREADS=${13}

data_types=()
if [ "$AA" = true ]; then
    data_types+=("AA")
fi
if [ "$DNA" = true ]; then
    data_types+=("DNA")
fi

base_walltime="00:05:00"
if [ "$OPENACC_V100" = true ] || [ "$OPENACC_V100" = true ]; then
  base_walltime="00:05:00"
else
  base_walltime="00:10:00"
fi

# Convert HH:MM:SS to total seconds
IFS=: read -r h m s <<< "$base_walltime"
total_seconds=$((10#$h * 3600 + 10#$m * 60 + 10#$s))

# Multiply by factor
scaled_seconds=$((total_seconds * factor))

# Convert back to HH:MM:SS
printf -v wall_time "%02d:%02d:%02d" \
  $((scaled_seconds / 3600)) \
  $(((scaled_seconds % 3600) / 60)) \
  $((scaled_seconds % 60))

for r in $(seq 1 $repeat); do
    local_unique_name="${UNIQUE_NAME}_run${r}"
  for data_type in "${data_types[@]}"; do
      if [ "$OPENACC_V100" = true ]; then
        memory=$((factor * 1 * 48))
          qsub -Pdx61 -lwalltime=$wall_time,ncpus=12,ngpus=1,mem="${memory}GB",jobfs=10GB,wd -qgpuvolta -N test_v100 \
                -vARG1="$DATASET_DIR",ARG2="$local_unique_name",ARG3="$WD",ARG4="$data_type",ARG5="V100",ARG6="$length" "$WD"/test/test_script_poc.sh
      fi

      if [ "$OPENACC_A100" = true ]; then
        memory=$(echo "$factor * 0.5 * 64" | bc)
         qsub -Pdx61 -lwalltime=$wall_time,ncpus=16,ngpus=1,mem="64GB",jobfs=10GB,wd -qdgxa100 -N test_a100 \
                -vARG1="$DATASET_DIR",ARG2="$local_unique_name",ARG3="$WD",ARG4="$data_type",ARG5="A100",ARG6="$length" "$WD"/test/test_script_poc.sh
      fi

      if [ "$IQTREE" = true ]; then
          memory=$((factor * 1 * 20))
         qsub -Pdx61 -lwalltime=$wall_time,ncpus=1,mem="${memory}GB",jobfs=10GB,wd -qnormal -N test_iqtree \
                -vARG1="$DATASET_DIR",ARG2="$local_unique_name",ARG3="$WD",ARG4="$data_type",ARG5="$length" "$WD"/test/test_script_iqtree.sh
      fi

      if [ "$IQTREE_OPENMP" = true ]; then
          memory=$((factor * IQTREE_THREADS * 20))
         qsub -Pdx61 -lwalltime=$wall_time,ncpus=$IQTREE_THREADS,mem="${memory}GB",jobfs=10GB,wd -qnormal -N test_iqtree_omp \
                -vARG1="$DATASET_DIR",ARG2="$local_unique_name",ARG3="$WD",ARG4="$data_type",ARG5="$length",ARG6="$IQTREE_THREADS" "$WD"/test/test_script_iqtree_omp.sh
      fi
  done
done
