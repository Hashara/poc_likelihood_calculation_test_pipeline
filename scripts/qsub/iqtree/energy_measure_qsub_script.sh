#!/bin/bash

# this script for submitting energy measurement jobs to a cluster using qsub

IQTREE=$1 # boolean for whether to build IQTREE
V100_GPU=$2
A100_GPU=$3
WD=$4
DATASET_DIR=$5
UNIQUE_NAME=$6
AA=$7
DNA=$8
length=$9
factor=${10}
repeat=${11}

IQTREE_OPENMP=${12}
IQTREE_THREADS=${13}

PROJECT_NAME=${14}
TYPE=${15}
H200=${16}
IQTREE_ARGS=${17}

data_types=()
if [ "$AA" == true ]; then
    data_types+=("AA")
fi
if [ "$DNA" == true ]; then
    data_types+=("DNA")
fi

base_walltime="00:05:00"
if [ "$V100_GPU" == true ] || [ "$A100_GPU" == true ] || [ "$H200" == true ]; then
  base_walltime="01:20:00"
else
  base_walltime="01:10:00"
fi

# Convert HH:MM:SS to total seconds
IFS=: read -r h m s <<< "$base_walltime"
total_seconds=$((10#$h * 3600 + 10#$m * 60 + 10#$s))

# Multiply by factor
scaled_seconds=$((total_seconds * factor))

# Convert back to HH:MM:SS
printf -v wall_time "%02d:%02d:%02d" \
  $((scaled_seconds / 3600)) \
  $(((scaled_seconds % 3600) / 60)) \
  $((scaled_seconds % 60))

for r in $(seq 1 $repeat); do
    local_unique_name="${UNIQUE_NAME}_run${r}"
  for data_type in "${data_types[@]}"; do

      if [ "$TYPE" == "OPENACC" ] || [ "$TYPE" == "OPENACC_PROFILE" ] || [ "$TYPE" == "CUDA" ]; then
          # GPU backends need GPU queue
          if [ "$V100_GPU" == true ]; then
            memory=$((factor * 1 * 48))
              qsub -P${PROJECT_NAME} -lwalltime=$wall_time,ncpus=12,ngpus=1,mem="${memory}GB",jobfs=10GB,wd -qgpuvolta -N energy_v100_${TYPE} \
                    -vARG1="$DATASET_DIR",ARG2="$local_unique_name",ARG3="$WD",ARG4="$data_type",ARG5="$length",ARG6="$TYPE",ARG7="$IQTREE_ARGS" "$WD"/energy_measure/iqtree/test_script_iqtree.sh
          fi

          if [ "$A100_GPU" == true ]; then
            memory=$(echo "$factor * 0.5 * 64" | bc)
             qsub -P${PROJECT_NAME} -lwalltime=$wall_time,ncpus=16,ngpus=1,mem="64GB",jobfs=10GB,wd -qdgxa100 -N energy_a100_${TYPE} \
                    -vARG1="$DATASET_DIR",ARG2="$local_unique_name",ARG3="$WD",ARG4="$data_type",ARG5="$length",ARG6="$TYPE",ARG7="$IQTREE_ARGS" "$WD"/energy_measure/iqtree/test_script_iqtree.sh
          fi

          if [ "$H200" == true ]; then
            memory=$((factor * 1 * 48))
             qsub -P${PROJECT_NAME} -lwalltime=$wall_time,ncpus=12,ngpus=1,mem="${memory}GB",jobfs=10GB,wd -qgpuhopper -N energy_h200_${TYPE} \
                    -vARG1="$DATASET_DIR",ARG2="$local_unique_name",ARG3="$WD",ARG4="$data_type",ARG5="$length",ARG6="$TYPE",ARG7="$IQTREE_ARGS" "$WD"/energy_measure/iqtree/test_script_iqtree.sh
          fi

      elif [ "$TYPE" == "VANILA" ]; then
          # VANILA is CPU-only, use normal queue
          memory=$((factor * 1 * 20))
         qsub -P${PROJECT_NAME} -lwalltime=$wall_time,ncpus=1,mem="${memory}GB",jobfs=10GB,wd -qnormal -N energy_iqtree_${TYPE} \
                -vARG1="$DATASET_DIR",ARG2="$local_unique_name",ARG3="$WD",ARG4="$data_type",ARG5="$length",ARG6="$TYPE",ARG7="$IQTREE_ARGS" "$WD"/energy_measure/iqtree/test_script_iqtree.sh
      fi

      if [ "$IQTREE_OPENMP" == true ]; then
          memory=$((factor * IQTREE_THREADS * 4))
          omp_wall_time="1:00:00"
         qsub -P${PROJECT_NAME} -lwalltime=$omp_wall_time,ncpus=$IQTREE_THREADS,mem="${memory}GB",jobfs=10GB,wd -qnormal -N energy_iqtree_omp_${TYPE} \
                -vARG1="$DATASET_DIR",ARG2="$local_unique_name",ARG3="$WD",ARG4="$data_type",ARG5="$length",ARG6="$IQTREE_THREADS",ARG7="$TYPE",ARG8="$IQTREE_ARGS" "$WD"/energy_measure/iqtree/test_script_iqtree_omp.sh
      fi
  done
done
