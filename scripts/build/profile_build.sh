#!/bin/bash

IQTREE=$1 # boolean for whether to build IQTREE
OPENACC_V100=$2
OPENACC_A100=$3
WD=$4
POC_GIT_BRANCH=$5
suffix="_profile"
PROJECT_NAME=$6

cd $WD || { echo "Failed to change directory to $WD"; exit 1; }
mkdir -p build
cd build || { echo "Failed to change directory to build"; exit 1; }

##############################
if [ "$OPENACC_V100" == true ] || [ "$OPENACC_A100" == true ]; then
    echo "Cloning poc repository"
    git clone --branch $POC_GIT_BRANCH --single-branch https://github.com/Hashara/poc-gpu-likelihood-calculation.git
fi

if [ "$OPENACC_V100" = true ]; then
    echo "Building OpenACC V100 version"
    mkdir -p "openacc_v100${suffix}"
    cd "openacc_v100${suffix}" || { echo "Failed to change directory to openacc_v100"; exit 1; }

    module load nvhpc-compilers/24.7

    export OMPI_CC=nvc
    export OMPI_CXX=nvc++

    export CC=nvc
    export CXX=nvc++
    export CUDACXX=nvcc

    export LDFLAGS="-L/apps/nvidia-hpc-sdk/24.7/Linux_x86_64/24.7/compilers/lib"
    export CPPFLAGS="-I/apps/nvidia-hpc-sdk/24.7/Linux_x86_64/24.7/compilers/include"

    cmake -DCMAKE_CXX_FLAGS="$LDFLAGS $CPPFLAGS" -DUSE_OPENACC=ON -DPROFILE=ON ../poc-gpu-likelihood-calculation
    make VERBOSE=1 -j

    cd ..
#   mkdir -p "openacc_transpose_v100${suffix}"
#    cd "openacc_transpose_v100$suffix" || { echo "Failed to change directory to openacc_transpose_v100"; exit 1; }
#    # for transposed rate matrix version
#    cmake -DCMAKE_CXX_FLAGS="$LDFLAGS $CPPFLAGS" -DUSE_OPENACC=ON -DTRANSPOSED_RATE_MATRIX=ON -DPROFILE=ON ../poc-gpu-likelihood-calculation
#    make VERBO SE=1 -j

fi

if [ "$OPENACC_A100" = true ]; then
    echo "Building OpenACC A100 version"

    qsub -P${PROJECT_NAME} -lwalltime=00:05:00,ncpus=16,ngpus=1,mem=64GB,jobfs=10GB,wd -qdgxa100 -N build_a100 -vARG1="$WD/build",ARG2="$WD/build/poc-gpu-likelihood-calculation" $WD/build/profile_build_a100.sh



fi