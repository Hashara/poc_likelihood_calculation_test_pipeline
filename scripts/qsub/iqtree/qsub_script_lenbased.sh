#!/bin/bash

# this script for submitting jobs to a cluster using qsub

IQTREE=$1 # boolean for whether to build IQTREE
V100_GPU=$2
A100_GPU=$3
WD=$4
DATASET_DIR=$5
UNIQUE_NAME=$6
AA=$7
DNA=$8
length=$9
mem_factor=${10}
repeat=${11}

IQTREE_OPENMP=${12}
IQTREE_THREADS=${13}
IQTREE_AUTO=${14}
PROJECT_NAME=${15}
H200=${16}
TYPE=${17}
IQTREE_ARGS=${18}
NUM_TREES=${19:-10}
wall_time_factor=${20:-1}
TREE_MODE=${21:-te}

data_types=()
if [ "$AA" = true ]; then
    data_types+=("AA")
fi
if [ "$DNA" = true ]; then
    data_types+=("DNA")
fi

# wall_time_factor=1 → 10 minutes (600 seconds)
scaled_seconds=$((wall_time_factor * 600))

# Convert to HH:MM:SS
printf -v wall_time "%02d:%02d:%02d" \
  $((scaled_seconds / 3600)) \
  $(((scaled_seconds % 3600) / 60)) \
  $((scaled_seconds % 60))

for r in $(seq 1 $repeat); do
    local_unique_name="${UNIQUE_NAME}_run${r}"
  for data_type in "${data_types[@]}"; do

      if [ "$IQTREE" == true ]; then
          # GPU branches mutually exclusive — orchestrator sets one of V100/A100/H200 per row.
          # ARG9=GPU_TYPE (lowercase) routes to per-arch build dir in the test script.
          if [ "$V100_GPU" == true ]; then
            memory=$((mem_factor * 1 * 48))
            export ARG1="$DATASET_DIR" ARG2="$local_unique_name" ARG3="$WD" ARG4="$data_type" ARG5="$length" ARG6="$TYPE" ARG7="$IQTREE_ARGS" ARG8="$TREE_MODE" ARG9="v100"
            echo "[qsub] lenbased V100: walltime=$wall_time mem=${memory}GB ARG1=$ARG1 ARG2=$ARG2 ARG3=$ARG3 ARG4=$ARG4 ARG5=$ARG5 ARG6=$ARG6 ARG7='$ARG7' ARG8=$ARG8 ARG9=$ARG9"
            qsub -P${PROJECT_NAME} -lwalltime=$wall_time,ncpus=12,ngpus=1,mem="${memory}GB",jobfs=10GB,wd -qgpuvolta -N test_iqtree_v100 \
                -v ARG1,ARG2,ARG3,ARG4,ARG5,ARG6,ARG7,ARG8,ARG9 "$WD"/test/iqtree/test_script_iqtree_lenbased.sh

          elif [ "$A100_GPU" == true ]; then
            memory=$((mem_factor * 1 * 64))
            export ARG1="$DATASET_DIR" ARG2="$local_unique_name" ARG3="$WD" ARG4="$data_type" ARG5="$length" ARG6="$TYPE" ARG7="$IQTREE_ARGS" ARG8="$TREE_MODE" ARG9="a100"
            echo "[qsub] lenbased A100: walltime=$wall_time mem=${memory}GB ARG1=$ARG1 ARG2=$ARG2 ARG3=$ARG3 ARG4=$ARG4 ARG5=$ARG5 ARG6=$ARG6 ARG7='$ARG7' ARG8=$ARG8 ARG9=$ARG9"
            qsub -P${PROJECT_NAME} -lwalltime=$wall_time,ncpus=16,ngpus=1,mem="${memory}GB",jobfs=10GB,wd -qdgxa100 -N test_iqtree_a100 \
                -v ARG1,ARG2,ARG3,ARG4,ARG5,ARG6,ARG7,ARG8,ARG9 "$WD"/test/iqtree/test_script_iqtree_lenbased.sh

          elif [ "$H200" == true ]; then
            memory=$((mem_factor * 1 * 48))
            export ARG1="$DATASET_DIR" ARG2="$local_unique_name" ARG3="$WD" ARG4="$data_type" ARG5="$length" ARG6="$TYPE" ARG7="$IQTREE_ARGS" ARG8="$TREE_MODE" ARG9="h200"
            echo "[qsub] lenbased H200: walltime=$wall_time mem=${memory}GB ARG1=$ARG1 ARG2=$ARG2 ARG3=$ARG3 ARG4=$ARG4 ARG5=$ARG5 ARG6=$ARG6 ARG7='$ARG7' ARG8=$ARG8 ARG9=$ARG9"
            qsub -P${PROJECT_NAME} -lwalltime=$wall_time,ncpus=12,ngpus=1,mem="${memory}GB",jobfs=10GB,wd -qgpuhopper -N test_iqtree_h200 \
                -v ARG1,ARG2,ARG3,ARG4,ARG5,ARG6,ARG7,ARG8,ARG9 "$WD"/test/iqtree/test_script_iqtree_lenbased.sh

          else
              memory=$((mem_factor * 1 * 20))
              export ARG1="$DATASET_DIR" ARG2="$local_unique_name" ARG3="$WD" ARG4="$data_type" ARG5="$length" ARG6="$TYPE" ARG7="$IQTREE_ARGS" ARG8="$TREE_MODE" ARG9=""
              echo "[qsub] lenbased CPU: walltime=$wall_time mem=${memory}GB ARG1=$ARG1 ARG2=$ARG2 ARG3=$ARG3 ARG4=$ARG4 ARG5=$ARG5 ARG6=$ARG6 ARG7='$ARG7' ARG8=$ARG8"
              qsub -P${PROJECT_NAME} -lwalltime=$wall_time,ncpus=1,mem="${memory}GB",jobfs=10GB,wd -qnormal -N test_iqtree \
                -v ARG1,ARG2,ARG3,ARG4,ARG5,ARG6,ARG7,ARG8,ARG9 "$WD"/test/iqtree/test_script_iqtree_lenbased.sh
          fi
      fi

      if [ "$IQTREE_OPENMP" == true ]; then
          memory=$((mem_factor * IQTREE_THREADS * 4))
          export ARG1="$DATASET_DIR" ARG2="$local_unique_name" ARG3="$WD" ARG4="$data_type" ARG5="$length" ARG6="$IQTREE_THREADS" ARG7="$IQTREE_AUTO" ARG8="$IQTREE_ARGS" ARG9="$TREE_MODE"
          echo "[qsub] lenbased OMP: walltime=$wall_time mem=${memory}GB ARG1=$ARG1 ARG2=$ARG2 ARG3=$ARG3 ARG4=$ARG4 ARG5=$ARG5 ARG6=$ARG6 ARG7=$ARG7 ARG8='$ARG8' ARG9=$ARG9"
         qsub -P${PROJECT_NAME} -lwalltime=$wall_time,ncpus=$IQTREE_THREADS,mem="${memory}GB",jobfs=10GB,wd -qnormal -N test_iqtree_omp \
                -v ARG1,ARG2,ARG3,ARG4,ARG5,ARG6,ARG7,ARG8,ARG9 "$WD"/test/iqtree/test_script_iqtree_lenbased_omp.sh
      fi
  done
done
