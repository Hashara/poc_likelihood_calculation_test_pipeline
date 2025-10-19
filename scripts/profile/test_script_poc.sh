#!/bin/bash

# this script for running 10 different trees with 1M sites each with 100 taxa
DATASET_DIR=$ARG1
UNIQUE_NAME=$ARG2
WD=$ARG3
AA_or_DNA=$ARG4
A_or_V100=$ARG5

length=$ARG6

executable_type=()
if [ "$A_or_V100" = "A100" ]; then
    echo "Using A100 build"
#    executable_type=("openacc_a100" "openacc_transpose_a100")
    executable_type=("openacc_a100_profile")

else
    echo "Using V100 build"
#    executable_type=("openacc_v100" "openacc_transpose_v100")
    executable_type=("openacc_v100_profile")
fi


iter=10
module load nvhpc-profilers/22.11

for i in $(seq 1 $iter); do
    TAXA_DIR="${DATASET_DIR}/tree_${i}"
    echo "Processing folder: $TAXA_DIR"
    taxa_size=$(basename "$TAXA_DIR")

    echo "Current directory: $(pwd)"

    cd "$TAXA_DIR" || { echo "Failed to change directory to $TAXA_DIR"; exit 1; }

        echo "Current directory: $(pwd)"

#        for length in "${lengths[@]}"; do
            echo "Running likelihood for length: $length taxa: $taxa_size"

            #loop through each executable type
            for type in "${executable_type[@]}"; do
                executable_path="$WD/build/$type/gpulcal"
                echo "Using executable: $executable_path"

                if [ -f "$executable_path" ]; then
                    echo "Running test for length: $length with $type"
                    if [ "$AA_or_DNA" = "AA" ]; then
                        echo "Using amino acid data"
                        nsys profile --trace=cuda,openacc,nvtx --stats=true -o profile_report $executable_path -s alignment_${length}.phy -te tree_${i}.full.treefile --seqtype AA -prefix output_${UNIQUE_NAME}_${taxa_size}_${length}_aa_${type}.txt
                    elif [ "$AA_or_DNA" = "DNA" ]; then
                        echo "Using DNA data"
                        nsys profile --trace=cuda,openacc,nvtx --stats=true -o profile_report $executable_path -s alignment_${length}.phy -te tree_${i}.full.treefile -prefix output_${UNIQUE_NAME}_${taxa_size}_${length}_dna_${type}.txt
                    fi

                    if [ $? -ne 0 ]; then
                        echo "run failed for length: $length with $type for $taxa_size taxa"
                        exit 1
                    fi
                else
                    echo "Executable not found: $executable_path"
                fi

            done

#        done


    cd - || { echo "Failed to return to previous directory"; exit 1; }

    echo "--------------------------------------"

done