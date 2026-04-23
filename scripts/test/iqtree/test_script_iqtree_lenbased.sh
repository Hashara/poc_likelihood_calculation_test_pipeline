#!/bin/bash

DATASET_DIR=$ARG1
UNIQUE_NAME=$ARG2
WD=$ARG3
AA_or_DNA=$ARG4


length=$ARG5
TYPE=$ARG6
IQTREE_ARGS=$ARG7
TREE_MODE=${ARG8:-te}

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

if [ "$TYPE" == "VANILA" ]; then
  executable_path="$WD/builds/build-vanila/iqtree3"
elif [ "$TYPE" == "CUDA" ]; then
  executable_path="$WD/builds/build-nvhpc-cuda/iqtree3"
elif [ "$TYPE" == "OPENACC_PROFILE" ]; then
  executable_path="$WD/builds/build-nvhpc-prof-openacc/iqtree3"
elif [ "$TYPE" == "OPENACC" ]; then
  executable_path="$WD/builds/build-nvhpc-openacc/iqtree3"
elif [ "$TYPE" == "OPENACC_DEBUG" ]; then
  executable_path="$WD/builds/build-nvhpc-debug-openacc/iqtree3"
elif [ "$TYPE" == "OPENACC_DEBUG_PROFILE" ]; then
  executable_path="$WD/builds/build-nvhpc-debug-prof-openacc/iqtree3"
fi


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