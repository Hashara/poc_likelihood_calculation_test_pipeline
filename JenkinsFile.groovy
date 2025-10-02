pipeline {
    agent any

    parameters {
        booleanParam(name: 'DNA', defaultValue: true, description: 'Include DNA analysis')
        booleanParam(name: 'AA', defaultValue: true, description: 'Include AA analysis')

        string(name: 'WORKDIR', defaultValue: '/path/to/workdir', description: 'Working directory')

        string(name: 'NCI_ALIAS', defaultValue: 'nci_gadi', description: 'ssh alias, if you do not have one, create one')

        string(name: "POC_GIT_BRANCH", defaultValue: "main", description: "Branch of the POC repo to use")


        // dataset path
        string(name: 'DATASET_PATH', defaultValue: '/path/to/dataset', description: 'Path to the dataset')

        booleanParam(name: 'BUILD', defaultValue: false, description: 'Build if not present')

        booleanParam(name: 'IQTREE', defaultValue: true, description: 'Run IQ-TREE')
        booleanParam(name: 'OpenACC_V100', defaultValue: false, description: 'Use OpenACC for V100 GPUs')
        booleanParam(name: 'OpenACC_A100', defaultValue: false, description: 'Use OpenACC for A100 GPUs')

        string(name: 'RUN_ALIASES', defaultValue: 'run', description: 'Unique name for this run')
    }

    environment {
        DATASET_PATH = "${params.DATASET_PATH}"
        RUN_ALIASES = "${params.RUN_ALIASES}"

        WORKDIR = "${params.WORKDIR}"

        NCI_ALIAS = "${params.NCI_ALIAS}"
        POC_GIT_BRANCH = "${params.POC_GIT_BRANCH}"

        BUILD = "${params.BUILD}"
        DNA = "${params.DNA}"
        AA = "${params.AA}"
        IQTREE = "${params.IQTREE}"
        OpenACC_V100 = "${params.OpenACC_V100}"
        OpenACC_A100 = "${params.OpenACC_A100}"
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
                    sh ${WORKDIR}/scripts/build/build.sh ${IQTREE} ${OpenACC_V100} ${OpenACC_A100} ${WORKDIR} ${POC_GIT_BRANCH}
    
                    """
                }
            }
        }
        stage('run tests'){
            steps{
                script{
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
                    sh ${WORKDIR}/scripts/qsub/qsub_script.sh ${IQTREE} ${OpenACC_V100} ${OpenACC_A100} ${WORKDIR} ${DATASET_PATH} ${RUN_ALIASES} ${AA} ${DNA}
    
                    """
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