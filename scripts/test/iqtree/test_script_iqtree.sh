#!/bin/bash

DATASET_DIR=$ARG1
UNIQUE_NAME=$ARG2
WD=$ARG3
AA_or_DNA=$ARG4


length=$ARG5

executable_type=("iqtree")

TYPE=$ARG6
IQTREE_ARGS=$ARG7
NUM_TREES=${ARG8:-10}
TREE_MODE=${ARG9:-te}
GPU_TYPE=${ARG10:-}  # v100|a100|h200 (lowercase) — picks per-arch build dir; empty = multi-arch fallback

# Resolve OpenACC binary: prefer per-arch dir (build-nvhpc-openacc-${GPU_TYPE}/),
# fall back to multi-arch dir (build-nvhpc-openacc/) when per-arch missing or
# GPU_TYPE not set (CPU/legacy callers).
resolve_openacc_binary() {
    local base=$1
    local per_arch="$WD/builds/${base}-${GPU_TYPE}/iqtree3"
    local multi="$WD/builds/${base}/iqtree3"
    if [ -n "$GPU_TYPE" ] && [ -f "$per_arch" ]; then
        echo "$per_arch"
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
elif [ "$TYPE" == "CLANG_VANILA" ]; then
  executable_path="$WD/builds/build-clang-vanila/iqtree3"
fi
echo "GPU_TYPE='$GPU_TYPE' TYPE='$TYPE' -> executable_path='$executable_path'"

echo "Number of trees: $NUM_TREES"

for i in $(seq 1 $NUM_TREES); do
  TAXA_DIR="${DATASET_DIR}/tree_${i}"
  echo "Processing folder: $TAXA_DIR"
  taxa_size=$(basename "$TAXA_DIR")

  echo "Current directory: $(pwd)"

  cd "$TAXA_DIR" || { echo "Failed to change directory to $TAXA_DIR"; exit 1; }

    # Build tree args based on TREE_MODE
    tree_file="tree_${i}.full.treefile"
    case "$TREE_MODE" in
      te)   tree_args="-te $tree_file" ;;
      t)    tree_args="-t $tree_file" ;;
      none) tree_args="" ;;
    esac

    echo "Current directory: $(pwd)"
    echo "Tree mode: $TREE_MODE → tree_args: $tree_args"

#    for length in "${lengths[@]}"; do
        echo "Running likelihood for length: $length taxa: $taxa_size"

        #loop through each executable type
        for type in "${executable_type[@]}"; do

            echo "Using executable: $executable_path"

            if [ -f "$executable_path" ]; then
                echo "Running test for length: $length with $type"
                if [ "$AA_or_DNA" = "AA" ]; then
                    echo "Using amino acid data"
                    $executable_path -s alignment_${length}.phy $tree_args --prefix output_${UNIQUE_NAME}_${taxa_size}_${length}_aa_${type} ${IQTREE_ARGS}

                elif [ "$AA_or_DNA" = "DNA" ]; then
                    echo "Using DNA data"
                    $executable_path -s alignment_${length}.phy $tree_args --prefix output_${UNIQUE_NAME}_${taxa_size}_${length}_${type} ${IQTREE_ARGS}

                fi

                if [ $? -ne 0 ]; then
                    echo "run failed for length: $length with $type for $taxa_size taxa"
                    exit 1
                fi
            else
                echo "Executable not found: $executable_path"
            fi

#        done

    done



  cd - || { echo "Failed to return to previous directory"; exit 1; }

  echo "--------------------------------------"

done