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
NORMALSR=${18:-false}
# ARG19: comma-separated KEY=VALUE env vars from Jenkins (e.g.
# NCU_KERNEL_FILTER=batchedTipTip_Rev|batchedTipInternal_Rev,NCU_LAUNCH_COUNT=50,NCU_SKIP_COUNT=200).
# Mirrors the ENV_VARS plumbing in scripts/qsub/qsub_script.sh:40-50. Empty = none.
# Parsed BEFORE the NCU_* defaults below so caller-provided values win without
# the defaults overwriting them.
ENV_VARS=${19:-}

ENV_VAR_NAMES=""
if [ -n "$ENV_VARS" ]; then
    echo "profile_ncu_qsub_script: extra env vars: $ENV_VARS"
    IFS=',' read -ra _pairs <<< "$ENV_VARS"
    for _kv in "${_pairs[@]}"; do
        _k="${_kv%%=*}"
        _v="${_kv#*=}"
        [ -z "$_k" ] && continue
        export "$_k"="$_v"
        ENV_VAR_NAMES="${ENV_VAR_NAMES},${_k}"
    done
    unset _pairs _kv _k _v
fi

# Determine CPU queue name and per-CPU memory ratio
# normal: 190 GB / 48 CPUs = ~3.96 GB/CPU → 4 GB
# normalsr: 500 GB / 104 CPUs = ~4.81 GB/CPU → 5 GB
if [ "$NORMALSR" == true ]; then
    CPU_QUEUE="normalsr"
else
    CPU_QUEUE="normal"
fi

# NCU-specific options (pass via environment or override here).
# Already-set values from ENV_VARS above are preserved via ${VAR:-default}.
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
          qsub -P${PROJECT_NAME} -lwalltime=$wall_time,ncpus=1,mem="${memory}GB",jobfs=200GB,wd -q${CPU_QUEUE} -N ncu_cpu_${data_type}_${length} \
                -v "ARG1,ARG2,ARG3,ARG4,ARG5,ARG6,ARG7,ARG8,NCU_SET,NCU_LAUNCH_COUNT,NCU_KERNEL_FILTER,NCU_SKIP_COUNT${ENV_VAR_NAMES}" \
                "$WD"/profile/iqtree/test_script_iqtree_ncu.sh
      elif [ "$TYPE" == "OPENACC" ] || [ "$TYPE" == "OPENACC_PROFILE" ] || [ "$TYPE" == "OPENACC_DEBUG" ] || [ "$TYPE" == "OPENACC_DEBUG_PROFILE" ] || [ "$TYPE" == "OPENMP_GPU" ] || [ "$TYPE" == "OPENMP_GPU_PROFILE" ] || [ "$TYPE" == "OPENMP_GPU_DEBUG" ] || [ "$TYPE" == "OPENMP_GPU_DEBUG_PROFILE" ] || [ "$TYPE" == "CUDA" ]; then
          if [ "$V100_GPU" == true ]; then
            memory=100
              export ARG1="$DATASET_DIR" ARG2="$local_unique_name" ARG3="$WD" ARG4="$data_type" ARG5="$length" ARG6="$TYPE" ARG7="$IQTREE_ARGS" ARG8="$TREE_MODE" ARG9="v100"
              echo "[qsub] NCU V100: walltime=$wall_time mem=${memory}GB data=$data_type len=$length"
              echo "  NCU_SET=$NCU_SET NCU_LAUNCH_COUNT=$NCU_LAUNCH_COUNT NCU_KERNEL_FILTER='$NCU_KERNEL_FILTER'"
              qsub -P${PROJECT_NAME} -lwalltime=$wall_time,ncpus=12,ngpus=1,mem="${memory}GB",jobfs=200GB,wd -qgpuvolta -N ncu_v100_${data_type}_${length} \
                    -v "ARG1,ARG2,ARG3,ARG4,ARG5,ARG6,ARG7,ARG8,ARG9,NCU_SET,NCU_LAUNCH_COUNT,NCU_KERNEL_FILTER,NCU_SKIP_COUNT${ENV_VAR_NAMES}" \
                    "$WD"/profile/iqtree/test_script_iqtree_ncu.sh
          fi

          if [ "$A100_GPU" == true ]; then
            memory=$(echo "$mem_factor * 0.5 * 64" | bc)
              export ARG1="$DATASET_DIR" ARG2="$local_unique_name" ARG3="$WD" ARG4="$data_type" ARG5="$length" ARG6="$TYPE" ARG7="$IQTREE_ARGS" ARG8="$TREE_MODE" ARG9="a100"
              echo "[qsub] NCU A100: walltime=$wall_time mem=${memory}GB data=$data_type len=$length"
              echo "  NCU_SET=$NCU_SET NCU_LAUNCH_COUNT=$NCU_LAUNCH_COUNT NCU_KERNEL_FILTER='$NCU_KERNEL_FILTER'"
             qsub -P${PROJECT_NAME} -lwalltime=$wall_time,ncpus=16,ngpus=1,mem="64GB",jobfs=200GB,wd -qdgxa100 -N ncu_a100_${data_type}_${length} \
                    -v "ARG1,ARG2,ARG3,ARG4,ARG5,ARG6,ARG7,ARG8,ARG9,NCU_SET,NCU_LAUNCH_COUNT,NCU_KERNEL_FILTER,NCU_SKIP_COUNT${ENV_VAR_NAMES}" \
                    "$WD"/profile/iqtree/test_script_iqtree_ncu.sh
          fi

          if [ "$H200" == true ]; then
            memory=$((mem_factor * 1 * 48))
              export ARG1="$DATASET_DIR" ARG2="$local_unique_name" ARG3="$WD" ARG4="$data_type" ARG5="$length" ARG6="$TYPE" ARG7="$IQTREE_ARGS" ARG8="$TREE_MODE" ARG9="h200"
              echo "[qsub] NCU H200: walltime=$wall_time mem=${memory}GB data=$data_type len=$length"
              echo "  NCU_SET=$NCU_SET NCU_LAUNCH_COUNT=$NCU_LAUNCH_COUNT NCU_KERNEL_FILTER='$NCU_KERNEL_FILTER'"
             qsub -P${PROJECT_NAME} -lwalltime=$wall_time,ncpus=12,ngpus=1,mem="${memory}GB",jobfs=200GB,wd -qgpuhopper -N ncu_h200_${data_type}_${length} \
                    -v "ARG1,ARG2,ARG3,ARG4,ARG5,ARG6,ARG7,ARG8,ARG9,NCU_SET,NCU_LAUNCH_COUNT,NCU_KERNEL_FILTER,NCU_SKIP_COUNT${ENV_VAR_NAMES}" \
                    "$WD"/profile/iqtree/test_script_iqtree_ncu.sh
          fi
      fi
  done
done
