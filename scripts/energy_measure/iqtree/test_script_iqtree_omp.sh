#!/bin/bash

DATASET_DIR=$ARG1
UNIQUE_NAME=$ARG2
WD=$ARG3
AA_or_DNA=$ARG4

length=$ARG5
IQTREE_THREADS=$ARG6

TYPE=$ARG7
IQTREE_ARGS=$ARG8
TREE_MODE=${ARG9:-te}
# -nt value passed by qsub; falls back to ncpus when not supplied (legacy callers).
# Whole-node normalsr reservation uses ncpus=104, -nt=103 (1 core reserved for OS).
NT_THREADS=${ARG10:-$IQTREE_THREADS}

executable_type=("iqtree")

executable_path=""
if [ "$TYPE" == "VANILA" ]; then
  executable_path="$WD/builds/build-vanila/iqtree3"
elif [ "$TYPE" == "CUDA" ]; then
  executable_path="$WD/builds/build-nvhpc-cuda/iqtree3"
elif [ "$TYPE" == "IQTREE_GPU" ]; then
  executable_path="$WD/builds/build-nvhpc-iqtree-gpu/iqtree3"
elif [ "$TYPE" == "IQTREE_GPU_SHARED" ]; then
  executable_path="${IQTREE_GPU_SHARED_BIN:-/scratch/dx61/as1708/shared-jolt/iqtree3-gpu-latest}"  # shared external JOLT build (override via IQTREE_GPU_SHARED_BIN)
elif [ "$TYPE" == "OPENACC_PROFILE" ]; then
  executable_path="$WD/builds/build-nvhpc-prof-openacc/iqtree3"
elif [ "$TYPE" == "OPENACC" ]; then
  executable_path="$WD/builds/build-nvhpc-openacc/iqtree3"
elif [ "$TYPE" == "OPENMP_GPU" ]; then
  executable_path="$WD/builds/build-nvhpc-openmp-gpu/iqtree3"
elif [ "$TYPE" == "OPENMP_GPU_PROFILE" ]; then
  executable_path="$WD/builds/build-nvhpc-prof-openmp-gpu/iqtree3"
elif [ "$TYPE" == "OPENMP_GPU_DEBUG" ]; then
  executable_path="$WD/builds/build-nvhpc-debug-openmp-gpu/iqtree3"
elif [ "$TYPE" == "OPENMP_GPU_DEBUG_PROFILE" ]; then
  executable_path="$WD/builds/build-nvhpc-debug-prof-openmp-gpu/iqtree3"
elif [ "$TYPE" == "CLANG_VANILA" ]; then
  executable_path="$WD/builds/build-clang-vanila/iqtree3"
elif [ "$TYPE" == "INTEL_VANILA" ]; then
  executable_path="$WD/builds/build-intel-vanila/iqtree3"
elif [ "$TYPE" == "INTEL_VANILA_CLX" ]; then
  executable_path="$WD/builds/build-intel-vanila-clx/iqtree3"
fi

# Shared dataset-layout helpers (simulated tree_<i>/ vs empirical single-file).
source "$WD/test/iqtree/lib_dataset.sh"

iter=10
module load linaro-forge/24.0.2

if dataset_dir_has_glob "$DATASET_DIR" "tree_*"; then
  for i in $(seq 1 $iter); do
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

          echo "Running likelihood for length: $length taxa: $taxa_size"

          #loop through each executable type
          for type in "${executable_type[@]}"; do
              echo "Using executable: $executable_path"

              if [ -f "$executable_path" ]; then
                  echo "Running energy measurement for tree: $i length: $length with $type ($TYPE) ncpus: $IQTREE_THREADS -nt: $NT_THREADS"
                  if [ "$AA_or_DNA" = "AA" ]; then
                      echo "Using amino acid data"
                      perf-report --no-mpi --output=perf_report_${UNIQUE_NAME}_tree${i}_aa $executable_path -s alignment_${length}.phy $tree_args --prefix output_${UNIQUE_NAME}_${taxa_size}_${length}_aa_${type} ${IQTREE_ARGS} -nt $NT_THREADS

                  elif [ "$AA_or_DNA" = "DNA" ]; then
                      echo "Using DNA data"
                      perf-report --no-mpi --output=perf_report_${UNIQUE_NAME}_tree${i}_dna $executable_path -s alignment_${length}.phy $tree_args --prefix output_${UNIQUE_NAME}_${taxa_size}_${length}_${type} ${IQTREE_ARGS} -nt $NT_THREADS

                  fi

                  if [ $? -ne 0 ]; then
                      echo "run failed for length: $length with $type for $taxa_size taxa"
                      exit 1
                  fi
              else
                  echo "Executable not found: $executable_path"
              fi

      done

    cd - || { echo "Failed to return to previous directory"; exit 1; }

    echo "--------------------------------------"

  done
else
  # ── Empirical layout: single alignment file, run once (iter ignored) ──
  echo "Dataset layout: empirical — single alignment for $DATASET_DIR (iter ignored)"

  if [ ! -f "$executable_path" ]; then
    echo "Executable not found: $executable_path"
    exit 1
  fi

  ALIGN=$(resolve_empirical_alignment "$DATASET_DIR") || {
    echo "No alignment file found for dataset '$DATASET_DIR'"
    exit 1
  }
  aln_dir=$(dirname "$ALIGN")
  aln_file=$(basename "$ALIGN")
  echo "Empirical alignment: $ALIGN"

  cd "$aln_dir" || { echo "Failed to change directory to $aln_dir"; exit 1; }

  tree_args=$(empirical_tree_args "$TREE_MODE" "$aln_file")
  echo "Tree mode: $TREE_MODE → tree_args: ${tree_args:-<full search>}"

  echo "Using executable: $executable_path"
  echo "Running energy measurement for empirical alignment $aln_file length: $length ($TYPE) ncpus: $IQTREE_THREADS -nt: $NT_THREADS"
  if [ "$AA_or_DNA" = "AA" ]; then
      echo "Using amino acid data"
      perf-report --no-mpi --output=perf_report_${UNIQUE_NAME}_${length}_aa $executable_path -s "$aln_file" $tree_args --prefix output_${UNIQUE_NAME}_${length}_aa_iqtree ${IQTREE_ARGS} -nt $NT_THREADS
  else
      echo "Using DNA data"
      perf-report --no-mpi --output=perf_report_${UNIQUE_NAME}_${length}_dna $executable_path -s "$aln_file" $tree_args --prefix output_${UNIQUE_NAME}_${length}_iqtree ${IQTREE_ARGS} -nt $NT_THREADS
  fi

  if [ $? -ne 0 ]; then
      echo "run failed for empirical alignment $ALIGN"
      exit 1
  fi

  echo "--------------------------------------"
fi
