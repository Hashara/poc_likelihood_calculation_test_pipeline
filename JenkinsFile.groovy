pipeline {
    agent any

    parameters {
        booleanParam(name: 'DNA', defaultValue: true, description: 'Include DNA analysis')
        booleanParam(name: 'AA', defaultValue: true, description: 'Include AA analysis')

        string(name: 'WORKDIR', defaultValue: '/path/to/workdir', description: 'Working directory')
        string(name: 'PROJECT_NAME', defaultValue: 'dx61', description: 'Project name')
        string(name: 'LENGTH', defaultValue: '1000000', description: 'alignment length')
        booleanParam(name: 'LEN_BASED', defaultValue: false, description: 'Use length based datasets')
        booleanParam(name: 'SPECIFIC_TREE', defaultValue: false, description: 'Use a specific tree folder for testing')

        string(name: 'NCI_ALIAS', defaultValue: 'nci_gadi', description: 'ssh alias, if you do not have one, create one')

        string(name: "POC_GIT_BRANCH", defaultValue: "main", description: "Branch of the POC repo to use")

        string(name: 'TYPE', defaultValue: 'OpenACC', description: 'Type of execution: OpenACC, cuBLAS, CPU')

        // dataset path
        string(name: 'DATASET_PATH', defaultValue: '/path/to/dataset', description: 'Path to the dataset')

        booleanParam(name: 'BUILD', defaultValue: false, description: 'Build if not present')

        booleanParam(name: 'IQTREE', defaultValue: true, description: 'Run IQ-TREE')
        booleanParam(name: 'IQTREE_OPENMP', defaultValue: false, description: 'Use OpenMP version of IQ-TREE')
        string(name: 'IQTREE_THREADS', defaultValue: '1', description: 'Number of threads for IQ-TREE')
        string(name: 'AUTO', defaultValue: 'true', description: 'IQ-TREE auto number of threads')
        booleanParam(name: 'OpenACC_V100', defaultValue: false, description: 'Use OpenACC for V100 GPUs')
        booleanParam(name: 'OpenACC_A100', defaultValue: false, description: 'Use OpenACC for A100 GPUs')
        string(name: 'FACTOR',defaultValue: "1", description: "memory/time multipler")

        string(name: 'REPETITIONS', defaultValue: '1', description: 'Number of repetitions of each analysis')
        booleanParam(name: 'PROFILE', defaultValue: false, description: 'Profile runs with nsight')
        booleanParam(name: 'ENERGY_PROFILE', defaultValue: false, description: 'Profile energy consumption with forge')
        string(name: 'RUN_ALIASES', defaultValue: 'run', description: 'Unique name for this run')

    }

    environment {
        DATASET_PATH = "${params.DATASET_PATH}"
        RUN_ALIASES = "${params.RUN_ALIASES}"

        WORKDIR = "${params.WORKDIR}"
        PROJECT_NAME = "${params.PROJECT_NAME}"

        NCI_ALIAS = "${params.NCI_ALIAS}"
        POC_GIT_BRANCH = "${params.POC_GIT_BRANCH}"

        TYPE = "${params.TYPE}"

        BUILD = "${params.BUILD}"
        DNA = "${params.DNA}"
        AA = "${params.AA}"
        IQTREE = "${params.IQTREE}"

        IQTREE_OPENMP = "${params.IQTREE_OPENMP}"
        IQTREE_THREADS = "${params.IQTREE_THREADS}"
        AUTO = "${params.AUTO}"

        OpenACC_V100 = "${params.OpenACC_V100}"
        OpenACC_A100 = "${params.OpenACC_A100}"
        LENGTH="${params.LENGTH}"
        FACTOR="${params.FACTOR}"
        REPETITIONS = "${params.REPETITIONS}"
        PROFILE = "${params.PROFILE}"
        ENERGY_PROFILE = "${params.ENERGY_PROFILE}"
        LEN_BASED = "${params.LEN_BASED}"
    }

    stages{
        stage('Copy scripts'){
            steps{
                script{
                    sh "pwd"
                    sh "scp -r scripts/* ${NCI_ALIAS}:${WORKDIR}"
                }
            }
        }
        stage('Build'){
            when {
                expression { return params.BUILD == true }
            }
            steps{
                script{
                    // args of the build script
                    /*IQTREE=$ARG1 # boolean for whether to build IQTREE
                    OPENACC_V100=$ARG2
                    OPENACC_A100=$ARG3
                    WD=$ARG4
                    POC_GIT_BRANCH=$ARG5*/

                    sh """
                    ssh ${NCI_ALIAS} << EOF
                    cd ${WORKDIR}
                    echo "Building..."
                    sh ${WORKDIR}/build/build.sh ${IQTREE} ${OpenACC_V100} ${OpenACC_A100} ${WORKDIR} ${POC_GIT_BRANCH} ${PROJECT_NAME} ${TYPE}
    
                    """
                }
            }
        }
        stage('Profile builds'){
            when {
                expression { return params.BUILD == true && params.PROFILE == true }
            }
            steps{
                script{
                    sh """
                    ssh ${NCI_ALIAS} << EOF
                    cd ${WORKDIR}
                    echo "Profiling builds..."
                    sh ${WORKDIR}/build/profile_build.sh ${IQTREE} ${OpenACC_V100} ${OpenACC_A100} ${WORKDIR} ${POC_GIT_BRANCH} ${PROJECT_NAME}
    
                    """
                }
            }
        }
        stage('Energy profile build'){
            when {
                expression { return params.BUILD == true && params.ENERGY_PROFILE == true }
            }
            steps{
                script{
                    sh """
                    ssh ${NCI_ALIAS} << EOF
                    cd ${WORKDIR}
                    echo "Energy profiling builds..."
                    sh ${WORKDIR}/build/energy_build.sh ${IQTREE} ${OpenACC_V100} ${OpenACC_A100} ${WORKDIR} ${POC_GIT_BRANCH} ${PROJECT_NAME}
    
                    """
                }
            }
        }
        stage("Pause of check builds"){
            when {
                expression { return params.BUILD == true }
            }
            steps{
                script{
                    input message: 'Have you checked the build logs and are happy to proceed?', ok: 'Yes, proceed'
                }
            }
        }
        stage('Profiling'){
            when {
                expression { return params.PROFILE == true }
            }
            steps{
                script{
                    sh """
                    ssh ${NCI_ALIAS} << EOF
                    cd ${WORKDIR}
                    echo "Profiling..."
                    sh ${WORKDIR}/qsub/profile_qsub_script.sh ${IQTREE} ${OpenACC_V100} ${OpenACC_A100} ${WORKDIR} ${DATASET_PATH} ${RUN_ALIASES} ${AA} ${DNA} ${LENGTH} ${FACTOR} ${REPETITIONS} ${PROJECT_NAME}
    
                    """
                }
            }
        }
        stage('Energy profiling'){
            when {
                expression { return params.ENERGY_PROFILE == true }
            }
            steps{
                script{
                    sh """
                    ssh ${NCI_ALIAS} << EOF
                    cd ${WORKDIR}
                    echo "Energy profiling..."
                    sh ${WORKDIR}/qsub/energy_measure_qsub_script.sh ${IQTREE} ${OpenACC_V100} ${OpenACC_A100} ${WORKDIR} ${DATASET_PATH} ${RUN_ALIASES} ${AA} ${DNA} ${LENGTH} ${FACTOR} ${REPETITIONS} ${IQTREE_OPENMP} ${IQTREE_THREADS} ${PROJECT_NAME}
    
                    """
                }
            }
        }
        stage('run tests'){
            when {
                expression { return params.PROFILE == false && params.ENERGY_PROFILE == false  }
            }
            steps{
                script{
                    if (params.LEN_BASED) {
                        // args of the run script
                        /*IQTREE=$1 # boolean for whether to build IQTREE
                            OPENACC_V100=$2
                            OPENACC_A100=$3
                            WD=$4
                            DATASET_DIR=$5
                            UNIQUE_NAME=$6
                            AA=$7
                            DNA=$8*/
                        echo "Running ...."
                        sh """
                        ssh ${NCI_ALIAS} << EOF
                        cd ${WORKDIR}
                        echo "Running..."
                        sh ${WORKDIR}/qsub/qsub_script_lenbased.sh ${IQTREE} ${OpenACC_V100} ${OpenACC_A100} ${WORKDIR} ${DATASET_PATH} ${RUN_ALIASES} ${AA} ${DNA} ${LENGTH} ${FACTOR} ${REPETITIONS} ${IQTREE_OPENMP} ${IQTREE_THREADS} ${AUTO} ${PROJECT_NAME}
        
                        """
                    } else if (params.SPECIFIC_TREE) {
                        echo "Running ...."
                        sh """
                        ssh ${NCI_ALIAS} << EOF
                        cd ${WORKDIR}
                        echo "Running..."
                        sh ${WORKDIR}/qsub/qsub_script_specific.sh ${IQTREE} ${OpenACC_V100} ${OpenACC_A100} ${WORKDIR} ${DATASET_PATH} ${RUN_ALIASES} ${AA} ${DNA} ${LENGTH} ${FACTOR} ${REPETITIONS} ${IQTREE_OPENMP} ${IQTREE_THREADS} ${AUTO} ${PROJECT_NAME} ${TYPE}
        
                        """
                    }
                    else {
                        // args of the run script
                        /*IQTREE=$1 # boolean for whether to build IQTREE
                            OPENACC_V100=$2
                            OPENACC_A100=$3
                            WD=$4
                            DATASET_DIR=$5
                            UNIQUE_NAME=$6
                            AA=$7
                            DNA=$8*/
                            echo "Running ...."
                            sh """
                        ssh ${NCI_ALIAS} << EOF
                        cd ${WORKDIR}
                        echo "Running..."
                        sh ${WORKDIR}/qsub/qsub_script.sh ${IQTREE} ${OpenACC_V100} ${OpenACC_A100} ${WORKDIR} ${DATASET_PATH} ${RUN_ALIASES} ${AA} ${DNA} ${LENGTH} ${FACTOR} ${REPETITIONS} ${IQTREE_OPENMP} ${IQTREE_THREADS} ${AUTO} ${PROJECT_NAME} ${TYPE}
        
                        """
                    }

                }
            }
        }
    }
    post {
        success {
            echo 'Pipeline completed successfully!'
        }
        failure {
            echo 'Pipeline failed.'
        }
    }
}