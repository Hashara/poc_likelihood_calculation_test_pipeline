#!/bin/bash

DATASET_DIR=$ARG1
UNIQUE_NAME=$ARG2
WD=$ARG3
AA_or_DNA=$ARG4


length=$ARG5
IQTREE_THREADS=$ARG6
AUTO=$ARG7
IQTREE_ARGS=$ARG8
NUM_TREES=${ARG9:-10}
TREE_MODE=${ARG10:-te}
TYPE=${ARG11:-VANILA}
# -nt value passed by qsub; falls back to ncpus when not supplied (legacy callers).
# Whole-node reservation reserves all node cores but leaves 1 idle for the OS:
# normalsr ncpus=104 → -nt=103, normal ncpus=48 → -nt=47.
NT_THREADS=${ARG12:-$IQTREE_THREADS}

if [ "$AUTO" == "true" ]; then
    NT_THREADS="AUTO"
    echo "Auto opertation for IQ-TREE threads enabled."
fi


executable_type=("iqtree3")

if [ "$TYPE" == "CLANG_VANILA" ]; then
    executable_path="$WD/builds/build-clang-vanila/iqtree3"
elif [ "$TYPE" == "INTEL_VANILA" ]; then
    executable_path="$WD/builds/build-intel-vanila/iqtree3"
elif [ "$TYPE" == "INTEL_VANILA_CLX" ]; then
    executable_path="$WD/builds/build-intel-vanila-clx/iqtree3"
else
    executable_path="$WD/builds/build-vanila/iqtree3"
fi
echo "TYPE='$TYPE' -> executable_path='$executable_path'"

# Shared dataset-layout helpers (simulated tree_<i>/ vs empirical single-file).
source "$WD/test/iqtree/lib_dataset.sh"

# Run one iqtree invocation (OMP) from the current working directory.
#   run_iqtree_omp_cmd <align_file> <tree_args> <prefix>
run_iqtree_omp_cmd() {
    local aln=$1 targs=$2 prefix=$3
    echo "Running: $executable_path -s $aln $targs --prefix $prefix ${IQTREE_ARGS} -nt $NT_THREADS"
    $executable_path -s "$aln" $targs --prefix "$prefix" ${IQTREE_ARGS} -nt $NT_THREADS
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
                  omp_prefix="${UNIQUE_NAME/tree_1/tree_${i}}"
                  if [ "$AA_or_DNA" = "AA" ]; then
                      echo "Using amino acid data"
                      run_iqtree_omp_cmd "alignment_${length}.phy" "$tree_args" "output_${omp_prefix}_aa"

                  elif [ "$AA_or_DNA" = "DNA" ]; then
                      echo "Using DNA data"
                      run_iqtree_omp_cmd "alignment_${length}.phy" "$tree_args" "output_${omp_prefix}"

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

  # No per-tree iteration here — use the unique name as-is for the prefix.
  omp_prefix="$UNIQUE_NAME"
  if [ "$AA_or_DNA" = "AA" ]; then
    echo "Using amino acid data"
    run_iqtree_omp_cmd "$aln_file" "$tree_args" "output_${omp_prefix}_${length}_aa"
  else
    echo "Using DNA data"
    run_iqtree_omp_cmd "$aln_file" "$tree_args" "output_${omp_prefix}_${length}"
  fi

  if [ $? -ne 0 ]; then
    echo "run failed for empirical alignment $ALIGN"
    exit 1
  fi

  echo "--------------------------------------"
fi
