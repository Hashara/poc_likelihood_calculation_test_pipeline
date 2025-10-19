#!/bin/bash

WD=$ARG1
code_dir=$ARG2

mkdir -p "$WD/openacc_a100"
cd "$WD/openacc_a100" || { echo "Failed to change directory to openacc_a100"; exit 1; }

module load nvhpc-compilers/24.7

export OMPI_CC=nvc
export OMPI_CXX=nvc++

export CC=nvc
export CXX=nvc++
export CUDACXX=nvcc

export LDFLAGS="-L/apps/nvidia-hpc-sdk/24.7/Linux_x86_64/24.7/compilers/lib"
export CPPFLAGS="-I/apps/nvidia-hpc-sdk/24.7/Linux_x86_64/24.7/compilers/include"

cmake -DCMAKE_CXX_FLAGS="$LDFLAGS $CPPFLAGS" -DUSE_OPENACC=ON $code_dir
make VERBOSE=1 -j

cd ..
#mkdir -p "$WD/openacc_transpose_a100"
#cd "$WD/openacc_transpose_a100" || { echo "Failed to change directory to openacc_transpose_a100"; exit 1; }
## for transposed rate matrix version
#cmake -DCMAKE_CXX_FLAGS="$LDFLAGS $CPPFLAGS" -DUSE_OPENACC=ON -DTRANSPOSED_RATE_MATRIX=ON -DTARGET_A100=ON $code_dir
#make VERBOSE=1 -j