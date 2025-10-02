#!/bin/bash

# this script for submitting jobs to a cluster using qsub

IQTREE=$1 # boolean for whether to build IQTREE
OPENACC_V100=$2
OPENACC_A100=$3
WD=$4
DATASET_DIR=$5
UNIQUE_NAME=$6
AA=$7
DNA=$8

data_types=()
if [ "$AA" = true ]; then
    data_types+=("AA")
fi
if [ "$DNA" = true ]; then
    data_types+=("DNA")
fi

for data_type in "${data_types[@]}"; do
    if [ "$OPENACC_V100" = true ]; then

        qsub -Pdx61 -lwalltime=00:05:00,ncpus=16,ngpus=1,mem=64GB,jobfs=10GB,wd -qgpuvolta -N test_v100 \
              -vARG1="$DATASET_DIR",ARG2="$UNIQUE_NAME",ARG3="$WD",ARG4="$data_type",ARG5="V100" "$WD"/test/test_script_poc.sh
    fi

    if [ "$OPENACC_A100" = true ]; then

       qsub -Pdx61 -lwalltime=00:05:00,ncpus=16,ngpus=1,mem=64GB,jobfs=10GB,wd -qdgxa100 -N test_a100 \
              -vARG1="$DATASET_DIR",ARG2="$UNIQUE_NAME",ARG3="$WD",ARG4="$data_type",ARG5="A100" "$WD"/test/test_script_poc.sh

    fi

    if [ "$IQTREE" = true ]; then
       qsub -Pdx61 -lwalltime=00:05:00,ncpus=16,ngpus=1,mem=64GB,jobfs=10GB,wd -N test_iqtree \
              -vARG1="$DATASET_DIR",ARG2="$UNIQUE_NAME",ARG3="$WD",ARG4="$data_type" "$WD"/test/test_script_iqtree.sh
    fi
done
