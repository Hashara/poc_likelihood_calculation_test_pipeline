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
elif [ "$TYPE" == "IQTREE_GPU" ]; then
  executable_path=$(resolve_openacc_binary "build-nvhpc-iqtree-gpu")
elif [ "$TYPE" == "IQTREE_GPU_SHARED" ]; then
  executable_path="${IQTREE_GPU_SHARED_BIN:-/scratch/dx61/as1708/shared-jolt/iqtree3-gpu-latest}"  # shared external JOLT build (override via IQTREE_GPU_SHARED_BIN)
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
elif [ "$TYPE" == "INTEL_VANILA" ]; then
  executable_path="$WD/builds/build-intel-vanila/iqtree3"
elif [ "$TYPE" == "INTEL_VANILA_CLX" ]; then
  executable_path="$WD/builds/build-intel-vanila-clx/iqtree3"
fi
echo "GPU_TYPE='$GPU_TYPE' TYPE='$TYPE' -> executable_path='$executable_path'"

# Shared dataset-layout helpers (simulated tree_<i>/ vs empirical single-file).
source "$WD/test/iqtree/lib_dataset.sh"

# Run one iqtree invocation from the current working directory.
#   run_iqtree_cmd <align_file> <tree_args> <prefix>
run_iqtree_cmd() {
    local aln=$1 targs=$2 prefix=$3
    echo "Running: $executable_path -s $aln $targs --prefix $prefix ${IQTREE_ARGS}"
    $executable_path -s "$aln" $targs --prefix "$prefix" ${IQTREE_ARGS}
}

if dataset_is_simulated "$DATASET_DIR"; then
  # ── Simulated layout: iterate tree_1..NUM_TREES ───────────────────────────
  echo "Dataset layout: simulated — iterating tree_1..$NUM_TREES under $DATASET_DIR"
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
                      run_iqtree_cmd "alignment_${length}.phy" "$tree_args" "output_${UNIQUE_NAME}_${taxa_size}_${length}_aa_${type}"

                  elif [ "$AA_or_DNA" = "DNA" ]; then
                      echo "Using DNA data"
                      run_iqtree_cmd "alignment_${length}.phy" "$tree_args" "output_${UNIQUE_NAME}_${taxa_size}_${length}_${type}"

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
else
  # ── Empirical layout: single alignment file, run once (NUM_TREES ignored) ──
  echo "Dataset layout: empirical — single alignment for $DATASET_DIR (NUM_TREES ignored)"

  if [ ! -f "$executable_path" ]; then
    echo "Executable not found: $executable_path"
    exit 1
  fi

  ALIGN=$(resolve_empirical_alignment "$DATASET_DIR") || {
    echo "No alignment file found for dataset '$DATASET_DIR' (tried the path as a file, with extensions: ${DATASET_ALN_EXTS[*]}, and as a directory)"
    exit 1
  }
  aln_dir=$(dirname "$ALIGN")
  aln_file=$(basename "$ALIGN")
  echo "Empirical alignment: $ALIGN"

  cd "$aln_dir" || { echo "Failed to change directory to $aln_dir"; exit 1; }

  tree_args=$(empirical_tree_args "$TREE_MODE" "$aln_file")
  echo "Tree mode: $TREE_MODE → tree_args: ${tree_args:-<full search>}"

  if [ "$AA_or_DNA" = "AA" ]; then
    echo "Using amino acid data"
    run_iqtree_cmd "$aln_file" "$tree_args" "output_${UNIQUE_NAME}_${length}_aa_iqtree"
  else
    echo "Using DNA data"
    run_iqtree_cmd "$aln_file" "$tree_args" "output_${UNIQUE_NAME}_${length}_iqtree"
  fi

  if [ $? -ne 0 ]; then
    echo "run failed for empirical alignment $ALIGN"
    exit 1
  fi

  echo "--------------------------------------"
fi
