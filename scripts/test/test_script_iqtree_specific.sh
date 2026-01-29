#!/bin/bash

DATASET_DIR=$ARG1
UNIQUE_NAME=$ARG2
WD=$ARG3
AA_or_DNA=$ARG4


length=$ARG5

executable_type=("iqtree")

iter=1

for i in $(seq 1 $iter); do
  TAXA_DIR="${DATASET_DIR}/tree_${i}"
  echo "Processing folder: $TAXA_DIR"
  taxa_size=$(basename "$TAXA_DIR")

  echo "Current directory: $(pwd)"

  cd "$TAXA_DIR" || { echo "Failed to change directory to $TAXA_DIR"; exit 1; }


    echo "Current directory: $(pwd)"

#    for length in "${lengths[@]}"; do
        echo "Running likelihood for length: $length taxa: $taxa_size"

        #loop through each executable type
        for type in "${executable_type[@]}"; do
            executable_path="$WD/build/iqtree_build/iqtree3"
            echo "Using executable: $executable_path"

            if [ -f "$executable_path" ]; then
                echo "Running test for length: $length with $type"
                if [ "$AA_or_DNA" = "AA" ]; then
                    echo "Using amino acid data"
                    $executable_path -s alignment_${length}.phy -te tree_${i}.full.treefile --prefix output_${UNIQUE_NAME}_${taxa_size}_${length}_aa_${type} -m Poisson  -blfix --kernel-nonrev

                elif [ "$AA_or_DNA" = "DNA" ]; then
                    echo "Using DNA data"
                    $executable_path -s alignment_${length}.phy -te tree_${i}.full.treefile --prefix output_${UNIQUE_NAME}_${taxa_size}_${length}_${type} -m JC  -blfix --kernel-nonrev

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