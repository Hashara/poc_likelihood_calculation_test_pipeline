#!/bin/bash

# Submit NCU profiling job to cluster via qsub
# NCU has HIGH overhead (~10-50x slowdown) — use short runs or kernel filters!
#
# Recommended configurations:
#   1. Full kernel profile (short dataset):
#      length=1000, TREE_MODE=te, wall_time_factor=10 (~1.5h walltime)
#
#   2. Targeted kernel profile (any dataset):
#      NCU_KERNEL_FILTER="batchedInternal|derivKernel" NCU_LAUNCH_COUNT=50
#      wall_time_factor=5
#
#   3. Steady-state profile (skip warmup):
#      NCU_SKIP_COUNT=100 NCU_LAUNCH_COUNT=20

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
wall_time_factor=${16:-10}
TREE_MODE=${17:-te}

# NCU-specific options (pass via environment or override here)
export NCU_SET=${NCU_SET:-full}
export NCU_LAUNCH_COUNT=${NCU_LAUNCH_COUNT:-0}
export NCU_KERNEL_FILTER=${NCU_KERNEL_FILTER:-""}
export NCU_SKIP_COUNT=${NCU_SKIP_COUNT:-0}

data_types=()
if [ "$AA" == true ]; then
    data_types+=("AA")
fi
if [ "$DNA" == true ]; then
    data_types+=("DNA")
fi

# NCU is 10-50x slower — scale walltime accordingly
# wall_time_factor=10 → 100 minutes (6000 seconds)
scaled_seconds=$((wall_time_factor * 600))
printf -v wall_time "%02d:%02d:%02d" \
  $((scaled_seconds / 3600)) \
  $(((scaled_seconds % 3600) / 60)) \
  $((scaled_seconds % 60))

for r in $(seq 1 $repeat); do
    local_unique_name="${UNIQUE_NAME}_run${r}"
  for data_type in "${data_types[@]}"; do

      if [ "$TYPE" == "VANILA" ] || [ "$TYPE" == "CLANG_VANILA" ]; then
          # CPU-only backends — use normal queue
          memory=$((mem_factor * 1 * 20))
          export ARG1="$DATASET_DIR" ARG2="$local_unique_name" ARG3="$WD" ARG4="$data_type" ARG5="$length" ARG6="$TYPE" ARG7="$IQTREE_ARGS" ARG8="$TREE_MODE"
          echo "[qsub] NCU CPU: walltime=$wall_time mem=${memory}GB data=$data_type len=$length"
          echo "  NCU_SET=$NCU_SET NCU_LAUNCH_COUNT=$NCU_LAUNCH_COUNT NCU_KERNEL_FILTER='$NCU_KERNEL_FILTER'"
          qsub -P${PROJECT_NAME} -lwalltime=$wall_time,ncpus=1,mem="${memory}GB",jobfs=200GB,wd -qnormal -N ncu_cpu_${data_type}_${length} \
                -v ARG1,ARG2,ARG3,ARG4,ARG5,ARG6,ARG7,ARG8,NCU_SET,NCU_LAUNCH_COUNT,NCU_KERNEL_FILTER,NCU_SKIP_COUNT \
                "$WD"/profile/iqtree/test_script_iqtree_ncu.sh
      elif [ "$TYPE" == "OPENACC" ] || [ "$TYPE" == "OPENACC_PROFILE" ] || [ "$TYPE" == "OPENACC_DEBUG" ] || [ "$TYPE" == "OPENACC_DEBUG_PROFILE" ] || [ "$TYPE" == "CUDA" ]; then
          if [ "$V100_GPU" == true ]; then
            memory=$((mem_factor * 1 * 48))
              export ARG1="$DATASET_DIR" ARG2="$local_unique_name" ARG3="$WD" ARG4="$data_type" ARG5="$length" ARG6="$TYPE" ARG7="$IQTREE_ARGS" ARG8="$TREE_MODE"
              echo "[qsub] NCU V100: walltime=$wall_time mem=${memory}GB data=$data_type len=$length"
              echo "  NCU_SET=$NCU_SET NCU_LAUNCH_COUNT=$NCU_LAUNCH_COUNT NCU_KERNEL_FILTER='$NCU_KERNEL_FILTER'"
              qsub -P${PROJECT_NAME} -lwalltime=$wall_time,ncpus=12,ngpus=1,mem="${memory}GB",jobfs=200GB,wd -qgpuvolta -N ncu_v100_${data_type}_${length} \
                    -v ARG1,ARG2,ARG3,ARG4,ARG5,ARG6,ARG7,ARG8,NCU_SET,NCU_LAUNCH_COUNT,NCU_KERNEL_FILTER,NCU_SKIP_COUNT \
                    "$WD"/profile/iqtree/test_script_iqtree_ncu.sh
          fi

          if [ "$A100_GPU" == true ]; then
            memory=$(echo "$mem_factor * 0.5 * 64" | bc)
              export ARG1="$DATASET_DIR" ARG2="$local_unique_name" ARG3="$WD" ARG4="$data_type" ARG5="$length" ARG6="$TYPE" ARG7="$IQTREE_ARGS" ARG8="$TREE_MODE"
              echo "[qsub] NCU A100: walltime=$wall_time mem=${memory}GB data=$data_type len=$length"
              echo "  NCU_SET=$NCU_SET NCU_LAUNCH_COUNT=$NCU_LAUNCH_COUNT NCU_KERNEL_FILTER='$NCU_KERNEL_FILTER'"
             qsub -P${PROJECT_NAME} -lwalltime=$wall_time,ncpus=16,ngpus=1,mem="64GB",jobfs=200GB,wd -qdgxa100 -N ncu_a100_${data_type}_${length} \
                    -v ARG1,ARG2,ARG3,ARG4,ARG5,ARG6,ARG7,ARG8,NCU_SET,NCU_LAUNCH_COUNT,NCU_KERNEL_FILTER,NCU_SKIP_COUNT \
                    "$WD"/profile/iqtree/test_script_iqtree_ncu.sh
          fi

          if [ "$H200" == true ]; then
            memory=$((mem_factor * 1 * 48))
              export ARG1="$DATASET_DIR" ARG2="$local_unique_name" ARG3="$WD" ARG4="$data_type" ARG5="$length" ARG6="$TYPE" ARG7="$IQTREE_ARGS" ARG8="$TREE_MODE"
              echo "[qsub] NCU H200: walltime=$wall_time mem=${memory}GB data=$data_type len=$length"
              echo "  NCU_SET=$NCU_SET NCU_LAUNCH_COUNT=$NCU_LAUNCH_COUNT NCU_KERNEL_FILTER='$NCU_KERNEL_FILTER'"
             qsub -P${PROJECT_NAME} -lwalltime=$wall_time,ncpus=12,ngpus=1,mem="${memory}GB",jobfs=200GB,wd -qgpuhopper -N ncu_h200_${data_type}_${length} \
                    -v ARG1,ARG2,ARG3,ARG4,ARG5,ARG6,ARG7,ARG8,NCU_SET,NCU_LAUNCH_COUNT,NCU_KERNEL_FILTER,NCU_SKIP_COUNT \
                    "$WD"/profile/iqtree/test_script_iqtree_ncu.sh
          fi
      fi
  done
done
