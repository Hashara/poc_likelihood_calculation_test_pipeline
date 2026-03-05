#!/bin/bash

DATASET_DIR=$ARG1
UNIQUE_NAME=$ARG2
WD=$ARG3
AA_or_DNA=$ARG4

length=$ARG5

executable_type=("iqtree")

TYPE=$ARG6
REV=$ARG7
VERBOSE=$ARG8

executable_path=""
if [ "$TYPE" == "VANILA" ]; then
  executable_path="$WD/builds/build-vanila/iqtree3"
elif [ "$TYPE" == "CUDA" ]; then
  executable_path="$WD/builds/build-nvhpc-cuda/iqtree3"
elif [ "$TYPE" == "OPENACC" ]; then
  executable_path="$WD/builds/build-nvhpc-openacc/iqtree3"
fi

kernel_rev=""
if [[ "$REV" == "true" ]]; then
    kernel_rev="--kernel-nonrev"
fi

verbose=""
if [[ "$VERBOSE" == "true" ]]; then
  verbose="-vvv"
fi

iter=1
module load nvhpc-profilers/22.11

for i in $(seq 1 $iter); do
  TAXA_DIR="${DATASET_DIR}/tree_${i}"
  echo "Processing folder: $TAXA_DIR"
  taxa_size=$(basename "$TAXA_DIR")

  echo "Current directory: $(pwd)"

  cd "$TAXA_DIR" || { echo "Failed to change directory to $TAXA_DIR"; exit 1; }

    echo "Current directory: $(pwd)"

        echo "Running profiling for length: $length taxa: $taxa_size"

        #loop through each executable type
        for type in "${executable_type[@]}"; do
            echo "Using executable: $executable_path"

            if [ -f "$executable_path" ]; then
                echo "Running nsys + ncu profiling for tree: $i length: $length with $type ($TYPE)"
                if [ "$AA_or_DNA" = "AA" ]; then
                    echo "Using amino acid data"
                    nsys profile --trace=cuda,openacc,nvtx --gpu-metrics-device=all --cuda-memory-usage=true --stats=true -o profile_report_${UNIQUE_NAME}_tree${i}_aa $executable_path -s alignment_${length}.phy -te tree_${i}.full.treefile --prefix output_${UNIQUE_NAME}_${taxa_size}_${length}_aa_${type} -m Poisson -blfix $kernel_rev $verbose
                    ncu --set full -f -o ncu_report_${UNIQUE_NAME}_tree${i}_aa $executable_path -s alignment_${length}.phy -te tree_${i}.full.treefile --prefix outputncu_${UNIQUE_NAME}_${taxa_size}_${length}_aa_${type} -m Poisson -blfix $kernel_rev $verbose

                elif [ "$AA_or_DNA" = "DNA" ]; then
                    echo "Using DNA data"
                    nsys profile --trace=cuda,openacc,nvtx --gpu-metrics-device=all --cuda-memory-usage=true --stats=true -o profile_report_${UNIQUE_NAME}_tree${i}_dna $executable_path -s alignment_${length}.phy -te tree_${i}.full.treefile --prefix output_${UNIQUE_NAME}_${taxa_size}_${length}_${type} -m JC -blfix $kernel_rev $verbose
                    ncu --set full -f -o ncu_report_${UNIQUE_NAME}_tree${i}_dna $executable_path -s alignment_${length}.phy -te tree_${i}.full.treefile --prefix outputncu_${UNIQUE_NAME}_${taxa_size}_${length}_${type} -m JC -blfix $kernel_rev $verbose

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
