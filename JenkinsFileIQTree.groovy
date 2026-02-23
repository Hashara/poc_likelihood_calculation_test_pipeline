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

        string(name: "IQ_TREE_GIT_BRANCH", defaultValue: "main", description: "Branch of the IQ-TREE repo to use")
        booleanParam(name: 'CLONE_IQTREE', defaultValue: false, description: 'Clone IQ-TREE?')

        booleanParam(name: 'QSUB', defaultValue: true, description: 'QSUB?')
        booleanParam(name: 'VANILLA', defaultValue: false, description: 'Vanilla?')
        booleanParam(name: 'CUDA', defaultValue: true, description: 'CUDA integration?')


        // dataset path
        string(name: 'DATASET_PATH', defaultValue: '/path/to/dataset', description: 'Path to the dataset')

        booleanParam(name: 'BUILD', defaultValue: false, description: 'Build if not present')

        booleanParam(name: 'IQTREE', defaultValue: true, description: 'Run IQ-TREE')
        booleanParam(name: 'IQTREE_OPENMP', defaultValue: false, description: 'Use OpenMP version of IQ-TREE')
        string(name: 'IQTREE_THREADS', defaultValue: '1', description: 'Number of threads for IQ-TREE')
        string(name: 'AUTO', defaultValue: 'true', description: 'IQ-TREE auto number of threads')
        booleanParam(name: 'V100', defaultValue: false, description: 'Use V100 GPUs')
        booleanParam(name: 'A100', defaultValue: false, description: 'Use A100 GPUs')
        booleanParam(name: 'H200', defaultValue: false, description: 'Use H200 GPUs' )
        booleanParam(name: 'ALL_NODE', defaultValue: false, description: 'Use whole node and execute parallely')
        string(name: 'FACTOR',defaultValue: "1", description: "memory/time multipler")

        string(name: 'REPETITIONS', defaultValue: '1', description: 'Number of repetitions of each analysis')
//        booleanParam(name: 'PROFILE', defaultValue: false, description: 'Profile runs with nsight')
//        booleanParam(name: 'ENERGY_PROFILE', defaultValue: false, description: 'Profile energy consumption with forge')
        string(name: 'RUN_ALIASES', defaultValue: 'run', description: 'Unique name for this run')

    }

    environment {
        DATASET_PATH = "${params.DATASET_PATH}"
        RUN_ALIASES = "${params.RUN_ALIASES}"

        WORKDIR = "${params.WORKDIR}"
        PROJECT_NAME = "${params.PROJECT_NAME}"

        NCI_ALIAS = "${params.NCI_ALIAS}"
        IQ_TREE_GIT_BRANCH = "${params.IQ_TREE_GIT_BRANCH}"

        VANILA="${params.VANILA}"
        CUDA="${params.CUDA}"


        BUILD = "${params.BUILD}"
        DNA = "${params.DNA}"
        AA = "${params.AA}"
        IQTREE = "${params.IQTREE}"

        IQTREE_OPENMP = "${params.IQTREE_OPENMP}"
        IQTREE_THREADS = "${params.IQTREE_THREADS}"
        AUTO = "${params.AUTO}"

        V100 = "${params.V100}"
        A100 = "${params.A100}"
        H200 = "${params.H200}"
        ALL_NODE = "${params.ALL_NODE}"
        LENGTH="${params.LENGTH}"
        FACTOR="${params.FACTOR}"
        REPETITIONS = "${params.REPETITIONS}"
//        PROFILE = "${params.PROFILE}"
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
                    IQ_TREE_GIT_BRANCH=$ARG5*/

                    build job: 'iqtree_cuda-pipeline',
                        parameters: [
                                string(name: 'BRANCH', value: params.IQ_TREE_GIT_BRANCH),
                                booleanParam(name: 'CLONE_IQTREE', value: params.CLONE_IQTREE),
                                string(name: 'NCI_ALIAS', value: 'nci_gadi'),
                                string(name: 'WORKING_DIR', value: params.WORKDIR),
                                booleanParam(name: 'QSUB', value: params.QSUB),
                                booleanParam(name: 'VANILLA', value: params.VANILLA),
                                booleanParam(name: 'CUDA', value: params.CUDA)
                        ],wait:true
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

        stage('run tests'){
            when {
                expression { return params.PROFILE == false && params.ENERGY_PROFILE == false  }
            }
            steps{
                script{
//                    if (params.LEN_BASED) {
//                        // args of the run script
//                        /*IQTREE=$1 # boolean for whether to build IQTREE
//                            OPENACC_V100=$2
//                            OPENACC_A100=$3
//                            WD=$4
//                            DATASET_DIR=$5
//                            UNIQUE_NAME=$6
//                            AA=$7
//                            DNA=$8*/
//                        echo "Running ...."
//                        sh """
//                        ssh ${NCI_ALIAS} << EOF
//                        cd ${WORKDIR}
//                        echo "Running..."
//                        sh ${WORKDIR}/qsub/qsub_script_lenbased.sh ${IQTREE} ${V100} ${A100} ${WORKDIR} ${DATASET_PATH} ${RUN_ALIASES} ${AA} ${DNA} ${LENGTH} ${FACTOR} ${REPETITIONS} ${IQTREE_OPENMP} ${IQTREE_THREADS} ${AUTO} ${PROJECT_NAME} ${H200}
//
//                        """
//                    }
//                    else if (params.SPECIFIC_TREE) {
//                        echo "Running ...."
//                        sh """
//                        ssh ${NCI_ALIAS} << EOF
//                        cd ${WORKDIR}
//                        echo "Running..."
//                        sh ${WORKDIR}/qsub/qsub_script_specific.sh ${IQTREE} ${V100} ${A100} ${WORKDIR} ${DATASET_PATH} ${RUN_ALIASES} ${AA} ${DNA} ${LENGTH} ${FACTOR} ${REPETITIONS} ${IQTREE_OPENMP} ${IQTREE_THREADS} ${AUTO} ${PROJECT_NAME} ${TYPE} ${H200}
//
//                        """
//                    }
//                    else {
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
                        sh ${WORKDIR}/qsub/iqtree/qsub_script.sh ${IQTREE} ${V100} ${A100} ${WORKDIR} ${DATASET_PATH} ${RUN_ALIASES} ${AA} ${DNA} ${LENGTH} ${FACTOR} ${REPETITIONS} ${IQTREE_OPENMP} ${IQTREE_THREADS} ${AUTO} ${PROJECT_NAME} ${TYPE} ${H200} ${ALL_NODE}
        
                        """
//                    }

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