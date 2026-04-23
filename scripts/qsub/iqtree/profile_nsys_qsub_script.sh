#!/bin/bash

# Submit Nsys profiling job to cluster via qsub
# Nsys has minimal overhead (~5-10%) — suitable for full runs

IQTREE=$1
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

PROJECT_NAME=${12}
TYPE=${13}
H200=${14}
IQTREE_ARGS=${15}
wall_time_factor=${16:-1}
TREE_MODE=${17:-te}

data_types=()
if [ "$AA" == true ]; then
    data_types+=("AA")
fi
if [ "$DNA" == true ]; then
    data_types+=("DNA")
fi

# wall_time_factor=1 → 10 minutes (600 seconds)
# Nsys adds ~10% overhead, so same walltime as normal runs
scaled_seconds=$((wall_time_factor * 600))
printf -v wall_time "%02d:%02d:%02d" \
  $((scaled_seconds / 3600)) \
  $(((scaled_seconds % 3600) / 60)) \
  $((scaled_seconds % 60))

for r in $(seq 1 $repeat); do
    local_unique_name="${UNIQUE_NAME}_run${r}"
  for data_type in "${data_types[@]}"; do

      if [ "$TYPE" == "OPENACC" ] || [ "$TYPE" == "OPENACC_PROFILE" ] || [ "$TYPE" == "OPENACC_DEBUG" ] || [ "$TYPE" == "OPENACC_DEBUG_PROFILE" ] || [ "$TYPE" == "CUDA" ]; then
          if [ "$V100_GPU" == true ]; then
            memory=$((mem_factor * 1 * 48))
              export ARG1="$DATASET_DIR" ARG2="$local_unique_name" ARG3="$WD" ARG4="$data_type" ARG5="$length" ARG6="$TYPE" ARG7="$IQTREE_ARGS" ARG8="$TREE_MODE"
              echo "[qsub] Nsys V100: walltime=$wall_time mem=${memory}GB data=$data_type len=$length"
              qsub -P${PROJECT_NAME} -lwalltime=$wall_time,ncpus=12,ngpus=1,mem="${memory}GB",jobfs=200GB,wd -qgpuvolta -N nsys_v100_${data_type}_${length} \
                    -v ARG1,ARG2,ARG3,ARG4,ARG5,ARG6,ARG7,ARG8 "$WD"/profile/iqtree/test_script_iqtree_nsys.sh
          fi

          if [ "$A100_GPU" == true ]; then
            memory=$(echo "$mem_factor * 0.5 * 64" | bc)
              export ARG1="$DATASET_DIR" ARG2="$local_unique_name" ARG3="$WD" ARG4="$data_type" ARG5="$length" ARG6="$TYPE" ARG7="$IQTREE_ARGS" ARG8="$TREE_MODE"
              echo "[qsub] Nsys A100: walltime=$wall_time mem=${memory}GB data=$data_type len=$length"
             qsub -P${PROJECT_NAME} -lwalltime=$wall_time,ncpus=16,ngpus=1,mem="64GB",jobfs=200GB,wd -qdgxa100 -N nsys_a100_${data_type}_${length} \
                    -v ARG1,ARG2,ARG3,ARG4,ARG5,ARG6,ARG7,ARG8 "$WD"/profile/iqtree/test_script_iqtree_nsys.sh
          fi

          if [ "$H200" == true ]; then
            memory=$((mem_factor * 1 * 48))
              export ARG1="$DATASET_DIR" ARG2="$local_unique_name" ARG3="$WD" ARG4="$data_type" ARG5="$length" ARG6="$TYPE" ARG7="$IQTREE_ARGS" ARG8="$TREE_MODE"
              echo "[qsub] Nsys H200: walltime=$wall_time mem=${memory}GB data=$data_type len=$length"
             qsub -P${PROJECT_NAME} -lwalltime=$wall_time,ncpus=12,ngpus=1,mem="${memory}GB",jobfs=200GB,wd -qgpuhopper -N nsys_h200_${data_type}_${length} \
                    -v ARG1,ARG2,ARG3,ARG4,ARG5,ARG6,ARG7,ARG8 "$WD"/profile/iqtree/test_script_iqtree_nsys.sh
          fi
      fi
  done
done
