#!/bin/bash

DATASET_DIR=$ARG1
UNIQUE_NAME=$ARG2
WD=$ARG3
AA_or_DNA=$ARG4


length=$ARG5
IQTREE_THREADS=$ARG6
IQTREE_AUTO=$ARG7
IQTREE_ARGS=$ARG8
TREE_MODE=${ARG9:-te}
TYPE=${ARG10:-VANILA}
# -nt value passed by qsub; falls back to ncpus when not supplied (legacy callers).
# Whole-node reservation reserves all node cores but leaves 1 idle for the OS:
# normalsr ncpus=104 → -nt=103, normal ncpus=48 → -nt=47.
NT_THREADS=${ARG11:-$IQTREE_THREADS}

if [ "$IQTREE_AUTO" == "true" ]; then
    NT_THREADS="AUTO"
    echo "Auto operation for IQ-TREE threads enabled."
fi

executable_type=("iqtree")

lengths=(100 1000 10000 100000 1000000)

# Build tree args based on TREE_MODE (lenbased uses tree.full.treefile)
tree_file="tree.full.treefile"
case "$TREE_MODE" in
  te)   tree_args="-te $tree_file" ;;
  t)    tree_args="-t $tree_file" ;;
  none) tree_args="" ;;
esac
echo "Tree mode: $TREE_MODE → tree_args: $tree_args"

# Shared dataset-layout helpers (simulated alignment_<length>/ vs empirical single-file).
source "$WD/test/iqtree/lib_dataset.sh"

if dataset_dir_has_glob "$DATASET_DIR" "alignment_*"; then
for length in "${lengths[@]}"; do
  TAXA_DIR="${DATASET_DIR}/alignment_${length}"
  echo "Processing folder: $TAXA_DIR"
  taxa_size=$(basename "$TAXA_DIR")

  echo "Current directory: $(pwd)"

  cd "$TAXA_DIR" || { echo "Failed to change directory to $TAXA_DIR"; exit 1; }


    echo "Current directory: $(pwd)"

#    for length in "${lengths[@]}"; do
        echo "Running likelihood for length: $length taxa: $taxa_size"

        #loop through each executable type
        for type in "${executable_type[@]}"; do
            if [ "$TYPE" == "CLANG_VANILA" ]; then
                executable_path="$WD/builds/build-clang-vanila/iqtree3"
            elif [ "$TYPE" == "INTEL_VANILA" ]; then
                executable_path="$WD/builds/build-intel-vanila/iqtree3"
            elif [ "$TYPE" == "INTEL_VANILA_CLX" ]; then
                executable_path="$WD/builds/build-intel-vanila-clx/iqtree3"
            else
                executable_path="$WD/builds/build-vanila/iqtree3"
            fi
            echo "Using executable: $executable_path"

            if [ -f "$executable_path" ]; then
                echo "Running test for length: $length with $type"
                if [ "$AA_or_DNA" = "AA" ]; then
                    echo "Using amino acid data"
                    $executable_path -s alignment_${length}.phy $tree_args --prefix output_${UNIQUE_NAME}_${taxa_size}_${length}_aa_${type} ${IQTREE_ARGS} -nt $NT_THREADS

                elif [ "$AA_or_DNA" = "DNA" ]; then
                    echo "Using DNA data"
                    $executable_path -s alignment_${length}.phy $tree_args --prefix output_${UNIQUE_NAME}_${taxa_size}_${length}_${type} ${IQTREE_ARGS} -nt $NT_THREADS

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
  # ── Empirical layout: single alignment file, run once (lengths array ignored) ──
  echo "Dataset layout: empirical — single alignment for $DATASET_DIR (lengths ignored)"

  if [ "$TYPE" == "CLANG_VANILA" ]; then
      executable_path="$WD/builds/build-clang-vanila/iqtree3"
  elif [ "$TYPE" == "INTEL_VANILA" ]; then
      executable_path="$WD/builds/build-intel-vanila/iqtree3"
  elif [ "$TYPE" == "INTEL_VANILA_CLX" ]; then
      executable_path="$WD/builds/build-intel-vanila-clx/iqtree3"
  else
      executable_path="$WD/builds/build-vanila/iqtree3"
  fi
  echo "Using executable: $executable_path"

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

  if [ "$AA_or_DNA" = "AA" ]; then
      echo "Using amino acid data"
      $executable_path -s "$aln_file" $tree_args --prefix output_${UNIQUE_NAME}_${length}_aa_iqtree ${IQTREE_ARGS} -nt $NT_THREADS
  else
      echo "Using DNA data"
      $executable_path -s "$aln_file" $tree_args --prefix output_${UNIQUE_NAME}_${length}_iqtree ${IQTREE_ARGS} -nt $NT_THREADS
  fi

  if [ $? -ne 0 ]; then
      echo "run failed for empirical alignment $ALIGN"
      exit 1
  fi

  echo "--------------------------------------"
fi