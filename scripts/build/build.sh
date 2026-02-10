#!/bin/bash

IQTREE=$1 # boolean for whether to build IQTREE
GPU_V100=$2
GPU_A100=$3
WD=$4
POC_GIT_BRANCH=$5
PROJECT_NAME=$6
TYPE=$7
GPU_H200=$8

cd $WD || { echo "Failed to change directory to $WD"; exit 1; }
mkdir -p build
cd build || { echo "Failed to change directory to build"; exit 1; }

if [ "$IQTREE" = true ]; then

  echo "cloning IQTREE"

  git clone --recursive https://github.com/iqtree/iqtree3.git

  # Build IQTREE
  mkdir -p "iqtree3_build"
  cd "iqtree3_build" || { echo "Failed to change directory to iqtree3_build"; exit 1; }
  module load openmpi/4.1.5 boost/1.84.0 eigen/3.3.7 llvm/17.0.1

  export OMPI_CC=clang
  export OMPI_CXX=clang++


  export CC=clang
  export CXX=clang++


  export LDFLAGS="-L/apps/llvm/17.0.1/lib"
  export CPPFLAGS="-I/apps/llvm/17.0.1/lib/clang/17/include"


  ############


  cmake -DCMAKE_CXX_FLAGS="$LDFLAGS $CPPFLAGS" -DEIGEN3_INCLUDE_DIR=/apps/eigen/3.3.7/include/eigen3 -DUSE_CMAPLE=OFF ../iqtree3 || { echo "CMake configuration failed for IQTREE"; exit 1; }
  make -j

  cd $WD/build || { echo "Failed to change directory to $WD/build"; exit 1; }

fi

##############################
if [ "$GPU_V100" == true ] || [ "$GPU_A100" == true ] || [ "$GPU_H200" == true ]; then
    echo "Cloning poc repository"
    git clone --branch $POC_GIT_BRANCH --single-branch https://github.com/Hashara/poc-gpu-likelihood-calculation.git
fi

if [ "$GPU_V100" == true ]; then

    if  [ "$TYPE" == "OpenACC" ]; then
      echo "Building OpenACC V100 version"
      mkdir -p "openacc_v100"
      cd "openacc_v100" || { echo "Failed to change directory to openacc_v100"; exit 1; }


      module load nvhpc-compilers/24.7

      export OMPI_CC=nvc
      export OMPI_CXX=nvc++

      export CC=nvc
      export CXX=nvc++
      export CUDACXX=nvcc

      export LDFLAGS="-L/apps/nvidia-hpc-sdk/24.7/Linux_x86_64/24.7/compilers/lib"
      export CPPFLAGS="-I/apps/nvidia-hpc-sdk/24.7/Linux_x86_64/24.7/compilers/include"

      cmake -DCMAKE_CXX_FLAGS="$LDFLAGS $CPPFLAGS" -DUSE_OPENACC=ON ../poc-gpu-likelihood-calculation
      make VERBOSE=1 -j

  elif [ "$TYPE" == "cuBLAS" ]; then

      echo "Building cuBLAS V100 version"
      mkdir -p "cublas_v100"
      cd "cublas_v100" || { echo "Failed to change directory to cublas_v100"; exit 1; }

      module load nvhpc-compilers/24.7 cuda/12.5.1

      export OMPI_CC=nvc
      export OMPI_CXX=nvc++

      export CC=nvc
      export CXX=nvc++
      export CUDACXX=nvcc

      export LDFLAGS="-L/apps/nvidia-hpc-sdk/24.7/Linux_x86_64/24.7/compilers/lib"
      export CPPFLAGS="-I/apps/nvidia-hpc-sdk/24.7/Linux_x86_64/24.7/compilers/include"

      cmake -DCMAKE_CXX_FLAGS="$LDFLAGS $CPPFLAGS" -DUSE_CUDA=ON -DUSE_CUBLAS=ON ../poc-gpu-likelihood-calculation
      make VERBOSE=1 -j

  else
      echo "Unknown TYPE specified for GPU_V100 build: $TYPE"
      exit 1
  fi

#    cd ..
#    mkdir -p "openacc_transpose_v100"
#    cd "openacc_transpose_v100" || { echo "Failed to change directory to openacc_transpose_v100"; exit 1; }
#    # for transposed rate matrix version
#    cmake -DCMAKE_CXX_FLAGS="$LDFLAGS $CPPFLAGS" -DUSE_OPENACC=ON -DTRANSPOSED_RATE_MATRIX=ON ../poc-gpu-likelihood-calculation
#    make VERBOSE=1 -j

fi

if [ "$GPU_A100" == true ]; then
  if [ "$TYPE" == "OpenACC" ]; then

    echo "Building OpenACC A100 version"

    qsub -P${PROJECT_NAME} -lwalltime=00:05:00,ncpus=16,ngpus=1,mem=64GB,jobfs=10GB,wd -qdgxa100 -N build_a100 -vARG1="$WD/build",ARG2="$WD/build/poc-gpu-likelihood-calculation" $WD/build/build_a100.sh

  elif [ "$TYPE" == "cuBLAS" ]; then

    echo "Building cuBLAS A100 version"

    qsub -P${PROJECT_NAME} -lwalltime=00:05:00,ncpus=16,ngpus=1,mem=64GB,jobfs=10GB,wd -qdgxa100 -N build_cublas_a100 -vARG1="$WD/build",ARG2="$WD/build/poc-gpu-likelihood-calculation" $WD/build/cublas_build.sh

  else
      echo "Unknown TYPE specified for GPU_A100 build: $TYPE"
      exit 1
  fi


fi

if [ "$GPU_H200" == true ]; then
    if [ "$TYPE" == "OpenACC" ]; then

      echo "Building OpenACC V100 version"

      qsub -P${PROJECT_NAME} -lwalltime=00:05:00,ncpus=12,ngpus=1,mem=48GB,jobfs=10GB,wd -qgpuhopper -N build_h200 -vARG1="$WD/build",ARG2="$WD/build/poc-gpu-likelihood-calculation" $WD/build/build_h200.sh

    elif [ "$TYPE" == "cuBLAS" ]; then

      echo "Building cuBLAS V100 version"

      qsub -P${PROJECT_NAME} -lwalltime=00:05:00,ncpus=12,ngpus=1,mem=48GB,jobfs=10GB,wd -qgpuhopper -N build_cublas_h200 -vARG1="$WD/build",ARG2="$WD/build/poc-gpu-likelihood-calculation" $WD/build/cublas_build_h200.sh

    else
        echo "Unknown TYPE specified for GPU_A100 build: $TYPE"
        exit 1
    fi
fi