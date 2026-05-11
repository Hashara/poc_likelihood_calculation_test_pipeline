#!/bin/bash

# NCU-only profiling for IQ-TREE GPU runs
# Captures detailed kernel metrics: occupancy, memory throughput, SM utilization
# WARNING: NCU slows execution ~10-50x. Use short runs or --launch-count to limit.
#
# Recommended datasets:
#   AA 10K sites + -te tree  (~223s normal → ~1-3h with NCU)
#   DNA 10K sites + -te tree (~62s normal → ~20-60min with NCU)
#
# For targeted profiling, use --kernel-name regex to profile specific kernels only.

DATASET_DIR=$ARG1
UNIQUE_NAME=$ARG2
WD=$ARG3
AA_or_DNA=$ARG4

length=$ARG5

TYPE=$ARG6
IQTREE_ARGS=$ARG7
TREE_MODE=${ARG8:-te}

# NCU options — configurable via environment variables
NCU_SET=${NCU_SET:-full}                          # metrics set: full, detailed, basic
NCU_LAUNCH_COUNT=${NCU_LAUNCH_COUNT:-0}           # 0 = profile ALL launches (slow!)
NCU_KERNEL_FILTER=${NCU_KERNEL_FILTER:-""}        # regex filter, e.g. "batchedInternal|derivKernel"
[ "$NCU_KERNEL_FILTER" = "null" ] && NCU_KERNEL_FILTER=""
NCU_SKIP_COUNT=${NCU_SKIP_COUNT:-0}               # skip first N kernel launches (warmup)

GPU_TYPE=${ARG9:-}  # v100|a100|h200 (lowercase) — picks per-arch build dir; empty = multi-arch fallback

# Resolve OpenACC/GPU binary: when GPU_TYPE is set, REQUIRE the per-arch dir
# (build-nvhpc-openacc-${GPU_TYPE}/); fail loudly if missing rather than silently
# falling back to multi-arch (which masks "build not done" errors). When GPU_TYPE
# is unset (legacy/CPU callers), use the multi-arch dir.
resolve_openacc_binary() {
    local base=$1
    local per_arch="$WD/builds/${base}-${GPU_TYPE}/iqtree3"
    local multi="$WD/builds/${base}/iqtree3"
    if [ -n "$GPU_TYPE" ]; then
        if [ -f "$per_arch" ]; then
            echo "$per_arch"
        else
            echo "ERROR: per-arch binary missing for GPU_TYPE='$GPU_TYPE': $per_arch" >&2
            echo "       (no fallback to multi-arch dir when GPU_TYPE is set; build the per-arch binary first)" >&2
            echo "$per_arch"  # return per-arch path so caller's '[ ! -f ]' check reports the right path
        fi
    else
        echo "$multi"
    fi
}

executable_path=""
if [ "$TYPE" == "VANILA" ]; then
  executable_path="$WD/builds/build-vanila/iqtree3"
elif [ "$TYPE" == "CUDA" ]; then
  executable_path="$WD/builds/build-nvhpc-cuda/iqtree3"
elif [ "$TYPE" == "OPENACC_PROFILE" ]; then
  executable_path=$(resolve_openacc_binary "build-nvhpc-prof-openacc")
elif [ "$TYPE" == "OPENACC" ]; then
  executable_path=$(resolve_openacc_binary "build-nvhpc-openacc")
elif [ "$TYPE" == "OPENACC_DEBUG" ]; then
  executable_path=$(resolve_openacc_binary "build-nvhpc-debug-openacc")
elif [ "$TYPE" == "OPENACC_DEBUG_PROFILE" ]; then
  executable_path=$(resolve_openacc_binary "build-nvhpc-debug-prof-openacc")
elif [ "$TYPE" == "OPENMP_GPU" ]; then
  executable_path=$(resolve_openacc_binary "build-nvhpc-openmp-gpu")
elif [ "$TYPE" == "OPENMP_GPU_PROFILE" ]; then
  executable_path=$(resolve_openacc_binary "build-nvhpc-prof-openmp-gpu")
elif [ "$TYPE" == "OPENMP_GPU_DEBUG" ]; then
  executable_path=$(resolve_openacc_binary "build-nvhpc-debug-openmp-gpu")
elif [ "$TYPE" == "OPENMP_GPU_DEBUG_PROFILE" ]; then
  executable_path=$(resolve_openacc_binary "build-nvhpc-debug-prof-openmp-gpu")
elif [ "$TYPE" == "CLANG_VANILA" ]; then
  executable_path="$WD/builds/build-clang-vanila/iqtree3"
fi
echo "GPU_TYPE='$GPU_TYPE' TYPE='$TYPE' -> executable_path='$executable_path'"

iter=1
module load nvhpc-profilers/22.11

for i in $(seq 1 $iter); do
  TAXA_DIR="${DATASET_DIR}/tree_${i}"
  echo "Processing folder: $TAXA_DIR"
  taxa_size=$(basename "$TAXA_DIR")

  cd "$TAXA_DIR" || { echo "Failed to change directory to $TAXA_DIR"; exit 1; }

    # Build tree args based on TREE_MODE
    tree_file="tree_${i}.full.treefile"
    case "$TREE_MODE" in
      te)   tree_args="-te $tree_file" ;;
      t)    tree_args="-t $tree_file" ;;
      none) tree_args="" ;;
    esac

    if [ ! -f "$executable_path" ]; then
        echo "Executable not found: $executable_path"
        exit 1
    fi

    echo "Running NCU profiling for tree: $i length: $length ($AA_or_DNA, $TYPE)"
    echo "  NCU_SET=$NCU_SET NCU_LAUNCH_COUNT=$NCU_LAUNCH_COUNT"
    echo "  NCU_KERNEL_FILTER='$NCU_KERNEL_FILTER' NCU_SKIP_COUNT=$NCU_SKIP_COUNT"

    # Build NCU command with optional filters
    NCU_CMD="ncu --set $NCU_SET --target-processes all -f"

    if [ "$NCU_LAUNCH_COUNT" -gt 0 ]; then
        NCU_CMD="$NCU_CMD --launch-count $NCU_LAUNCH_COUNT"
    fi

    if [ -n "$NCU_KERNEL_FILTER" ]; then
        NCU_CMD="$NCU_CMD --kernel-name '$NCU_KERNEL_FILTER'"
    fi

    if [ "$NCU_SKIP_COUNT" -gt 0 ]; then
        NCU_CMD="$NCU_CMD --launch-skip $NCU_SKIP_COUNT"
    fi

    if [ "$AA_or_DNA" = "AA" ]; then
        eval $NCU_CMD \
            -o ncu_report_${UNIQUE_NAME}_tree${i}_aa \
            $executable_path -s alignment_${length}.phy $tree_args \
            --prefix outputncu_${UNIQUE_NAME}_${taxa_size}_${length}_aa \
            ${IQTREE_ARGS}
    elif [ "$AA_or_DNA" = "DNA" ]; then
        eval $NCU_CMD \
            -o ncu_report_${UNIQUE_NAME}_tree${i}_dna \
            $executable_path -s alignment_${length}.phy $tree_args \
            --prefix outputncu_${UNIQUE_NAME}_${taxa_size}_${length}_dna \
            ${IQTREE_ARGS}
    fi

    if [ $? -ne 0 ]; then
        echo "NCU run failed for length: $length ($AA_or_DNA)"
        exit 1
    fi

  cd - || { echo "Failed to return to previous directory"; exit 1; }
  echo "--------------------------------------"
done
