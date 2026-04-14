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
        booleanParam(name: 'VANILA', defaultValue: false, description: 'VANILA?')
        booleanParam(name: 'CUDA', defaultValue: true, description: 'CUDA integration?')
        booleanParam(name: 'OPENACC', defaultValue: true, description: 'OPENACC integration?')
        booleanParam(name: 'OPENACC_PROFILE', defaultValue: false, description: 'OpenACC with profiling instrumentation?')
        string(name: 'GPU_ARCH', defaultValue: '', description: 'GPU architecture for OpenACC build (e.g. cc70 for V100, cc80 for A100, cc90 for H100). Empty = multi-arch default (cc70,cc80,cc90)')


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

        string(name: 'IQTREE_ARGS', defaultValue: '-m Poisson -blfix --kernel-nonrev -vvv', description: 'Additional IQ-TREE arguments (e.g. -m Poisson -blfix --kernel-nonrev -vvv)')
        string(name: 'MEM_FACTOR',defaultValue: "1", description: "memory multiplier (1 = base memory per GPU type)")
        string(name: 'WALL_TIME_FACTOR', defaultValue: "1", description: "wall time multiplier (1 = 10 minutes)")

        string(name: 'REPETITIONS', defaultValue: '1', description: 'Number of repetitions of each analysis')
        booleanParam(name: 'PROFILE', defaultValue: false, description: 'Profile runs with nsight (legacy: both nsys + ncu together)')
        booleanParam(name: 'PROFILE_NSYS', defaultValue: false, description: 'Nsys timeline profiling only (~5-10% overhead, suitable for full runs)')
        booleanParam(name: 'PROFILE_NCU', defaultValue: false, description: 'NCU kernel metrics only (~10-50x overhead, use short datasets or kernel filters)')
        string(name: 'NCU_LAUNCH_COUNT', defaultValue: '0', description: 'NCU: max kernel launches to profile (0 = all, 20-50 recommended)')
        string(name: 'NCU_KERNEL_FILTER', defaultValue: '', description: 'NCU: kernel name regex filter (e.g. batchedInternal|derivKernel)')
        booleanParam(name: 'ENERGY_PROFILE', defaultValue: false, description: 'Profile energy consumption with forge')
        string(name: 'RUN_ALIASES', defaultValue: 'run', description: 'Unique name for this run')
        string(name: 'NUM_TREES', defaultValue: '10', description: 'Number of tree folders (tree_1..tree_N) to iterate over in the dataset')
        string(name: 'TREE_MODE', defaultValue: 'te', description: 'Tree arg mode: te (-te TREEFILE), t (-t TREEFILE), none (no tree args)')

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
        OPENACC="${params.OPENACC}"
        OPENACC_PROFILE="${params.OPENACC_PROFILE}"
        GPU_ARCH="${params.GPU_ARCH}"


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

        IQTREE_ARGS = "${params.IQTREE_ARGS}"

        LENGTH="${params.LENGTH}"
        MEM_FACTOR="${params.MEM_FACTOR}"
        WALL_TIME_FACTOR="${params.WALL_TIME_FACTOR}"
        REPETITIONS = "${params.REPETITIONS}"
        PROFILE = "${params.PROFILE}"
        PROFILE_NSYS = "${params.PROFILE_NSYS}"
        PROFILE_NCU = "${params.PROFILE_NCU}"
        NCU_LAUNCH_COUNT = "${params.NCU_LAUNCH_COUNT}"
        NCU_KERNEL_FILTER = "${params.NCU_KERNEL_FILTER}"
        ENERGY_PROFILE = "${params.ENERGY_PROFILE}"
        LEN_BASED = "${params.LEN_BASED}"
        NUM_TREES = "${params.NUM_TREES}"
        TREE_MODE = "${params.TREE_MODE}"
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

                    build job: 'iqtree-cuda-pipeline',
                        parameters: [
                                string(name: 'BRANCH', value: params.IQ_TREE_GIT_BRANCH),
                                booleanParam(name: 'CLONE_IQTREE', value: params.CLONE_IQTREE),
                                string(name: 'NCI_ALIAS', value: 'nci_gadi'),
                                string(name: 'WORKING_DIR', value: params.WORKDIR),
                                booleanParam(name: 'QSUB', value: params.QSUB),
                                booleanParam(name: 'VANILA', value: params.VANILA),
                                booleanParam(name: 'CUDA', value: params.CUDA),
                                booleanParam(name: 'OPENACC', value: params.OPENACC),
                                booleanParam(name: 'OPENACC_PROFILE', value: params.OPENACC_PROFILE),
                                string(name: 'GPU_ARCH', value: params.GPU_ARCH)
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

        stage('Profiling'){
            when {
                expression { return params.PROFILE == true }
            }
            steps{
                script{
                    def backends = []

                    if (params.VANILA) backends << "VANILA"
                    if (params.CUDA)    backends << "CUDA"
                    if (params.OPENACC) backends << "OPENACC"
                    if (params.OPENACC_PROFILE) backends << "OPENACC_PROFILE"

                    if (backends.isEmpty()) {
                        error("No backend selected for profiling. Enable at least one of VANILA, CUDA, OPENACC, OPENACC_PROFILE")
                    }

                    echo "Profiling backends: ${backends}"

                    for (backend in backends) {

                        echo "Profiling backend: ${backend}"

                        sh """
                        ssh ${NCI_ALIAS} << EOF
                        cd ${WORKDIR}
                        echo "Profiling ${backend}..."
                        sh ${WORKDIR}/qsub/iqtree/profile_qsub_script.sh \
                            ${IQTREE} ${V100} ${A100} ${WORKDIR} \
                            ${DATASET_PATH} ${RUN_ALIASES}_profile_${backend} \
                            ${AA} ${DNA} ${LENGTH} ${MEM_FACTOR} ${REPETITIONS} \
                            ${PROJECT_NAME} ${backend} ${H200} \
                            "${IQTREE_ARGS}" ${WALL_TIME_FACTOR} ${TREE_MODE}

                        """
                    }
                }
            }
        }

        stage('Nsys Profiling'){
            when {
                expression { return params.PROFILE_NSYS == true }
            }
            steps{
                script{
                    def backends = []

                    if (params.VANILA) backends << "VANILA"
                    if (params.CUDA)    backends << "CUDA"
                    if (params.OPENACC) backends << "OPENACC"
                    if (params.OPENACC_PROFILE) backends << "OPENACC_PROFILE"

                    if (backends.isEmpty()) {
                        error("No backend selected for Nsys profiling. Enable at least one of VANILA, CUDA, OPENACC, OPENACC_PROFILE")
                    }

                    echo "Nsys profiling backends: ${backends}"

                    for (backend in backends) {

                        echo "Nsys profiling backend: ${backend}"

                        sh """
                        ssh ${NCI_ALIAS} << EOF
                        cd ${WORKDIR}
                        echo "Nsys profiling ${backend}..."
                        sh ${WORKDIR}/qsub/iqtree/profile_nsys_qsub_script.sh \
                            ${IQTREE} ${V100} ${A100} ${WORKDIR} \
                            ${DATASET_PATH} ${RUN_ALIASES}_nsys_${backend} \
                            ${AA} ${DNA} ${LENGTH} ${MEM_FACTOR} ${REPETITIONS} \
                            ${PROJECT_NAME} ${backend} ${H200} \
                            "${IQTREE_ARGS}" ${WALL_TIME_FACTOR} ${TREE_MODE}

                        """
                    }
                }
            }
        }

        stage('NCU Profiling'){
            when {
                expression { return params.PROFILE_NCU == true }
            }
            steps{
                script{
                    def backends = []

                    if (params.VANILA) backends << "VANILA"
                    if (params.CUDA)    backends << "CUDA"
                    if (params.OPENACC) backends << "OPENACC"
                    if (params.OPENACC_PROFILE) backends << "OPENACC_PROFILE"

                    if (backends.isEmpty()) {
                        error("No backend selected for NCU profiling. Enable at least one of VANILA, CUDA, OPENACC, OPENACC_PROFILE")
                    }

                    echo "NCU profiling backends: ${backends}"

                    for (backend in backends) {

                        echo "NCU profiling backend: ${backend}"

                        sh """
                        ssh ${NCI_ALIAS} << EOF
                        cd ${WORKDIR}
                        export NCU_LAUNCH_COUNT=${NCU_LAUNCH_COUNT}
                        export NCU_KERNEL_FILTER="${NCU_KERNEL_FILTER}"
                        echo "NCU profiling ${backend} (launch_count=${NCU_LAUNCH_COUNT}, filter='${NCU_KERNEL_FILTER}')..."
                        sh ${WORKDIR}/qsub/iqtree/profile_ncu_qsub_script.sh \
                            ${IQTREE} ${V100} ${A100} ${WORKDIR} \
                            ${DATASET_PATH} ${RUN_ALIASES}_ncu_${backend} \
                            ${AA} ${DNA} ${LENGTH} ${MEM_FACTOR} ${REPETITIONS} \
                            ${PROJECT_NAME} ${backend} ${H200} \
                            "${IQTREE_ARGS}" ${WALL_TIME_FACTOR} ${TREE_MODE}

                        """
                    }
                }
            }
        }

        stage('Energy profiling'){
            when {
                expression { return params.ENERGY_PROFILE == true }
            }
            steps{
                script{
                    def backends = []

                    if (params.VANILA) backends << "VANILA"
                    if (params.OPENACC) backends << "OPENACC"
                    if (params.OPENACC_PROFILE) backends << "OPENACC_PROFILE"

                    if (backends.isEmpty()) {
                        error("No backend selected for energy profiling. Enable at least one of VANILA, OPENACC, OPENACC_PROFILE")
                    }

                    echo "Energy profiling backends: ${backends}"

                    for (backend in backends) {

                        echo "Energy profiling backend: ${backend}"

                        sh """
                        ssh ${NCI_ALIAS} << EOF
                        cd ${WORKDIR}
                        echo "Energy profiling ${backend}..."
                        sh ${WORKDIR}/qsub/iqtree/energy_measure_qsub_script.sh \
                            ${IQTREE} ${V100} ${A100} ${WORKDIR} \
                            ${DATASET_PATH} ${RUN_ALIASES}_energy_${backend} \
                            ${AA} ${DNA} ${LENGTH} ${MEM_FACTOR} ${REPETITIONS} \
                            ${IQTREE_OPENMP} ${IQTREE_THREADS} \
                            ${PROJECT_NAME} ${backend} ${H200} \
                            "${IQTREE_ARGS}" ${WALL_TIME_FACTOR} ${TREE_MODE}

                        """
                    }
                }
            }
        }

        stage('run tests'){
            when {
                expression { return params.PROFILE == false && params.PROFILE_NSYS == false && params.PROFILE_NCU == false && params.ENERGY_PROFILE == false }
            }
            steps{
                script{
                    def backends = []

                    if (params.VANILA) backends << "VANILA"
                    if (params.CUDA)    backends << "CUDA"
                    if (params.OPENACC) backends << "OPENACC"
                    if (params.OPENACC_PROFILE) backends << "OPENACC_PROFILE"

                    if (backends.isEmpty()) {
                        error("No backend selected. Enable at least one of VANILA, CUDA, OPENACC, OPENACC_PROFILE")
                    }

                    echo "Selected backends: ${backends}"
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
                        for (backend in backends) {

                            echo "Running backend: ${backend}"
                            echo "Running ...."
                            sh """
                            ssh ${NCI_ALIAS} << EOF
                            cd ${WORKDIR}
                            echo "Running..."
                            sh ${WORKDIR}/qsub/iqtree/qsub_script_lenbased.sh \
                            ${IQTREE} ${V100} ${A100} ${WORKDIR} ${DATASET_PATH} \
                            ${RUN_ALIASES} ${AA} ${DNA} ${LENGTH} ${MEM_FACTOR} ${REPETITIONS} \
                            ${IQTREE_OPENMP} ${IQTREE_THREADS} ${AUTO} ${PROJECT_NAME} ${H200} \
                            ${backend} "${IQTREE_ARGS}" ${NUM_TREES} ${WALL_TIME_FACTOR} ${TREE_MODE}

                            """
                        }
                    }
                    else{
                        for (backend in backends) {

                            echo "Running backend: ${backend}"

                            sh """
                        ssh ${NCI_ALIAS} << EOF
                        cd ${WORKDIR}
                        echo "Running ${backend}..."
                        sh ${WORKDIR}/qsub/iqtree/qsub_script.sh \
                            ${IQTREE} ${V100} ${A100} ${WORKDIR} \
                            ${DATASET_PATH} ${RUN_ALIASES}_${backend} \
                            ${AA} ${DNA} ${LENGTH} ${MEM_FACTOR} ${REPETITIONS} \
                            ${IQTREE_OPENMP} ${IQTREE_THREADS} ${AUTO} \
                            ${PROJECT_NAME} ${backend} ${H200} ${ALL_NODE} \
                            "${IQTREE_ARGS}" ${NUM_TREES} ${WALL_TIME_FACTOR} ${TREE_MODE}

                        """
                        }
                    }
//                    def backends = []
//
//                    if (params.VANILA) backends << "VANILA"
//                    if (params.CUDA)    backends << "CUDA"
//                    if (params.OPENACC) backends << "OPENACC"
//
//                    if (backends.isEmpty()) {
//                        error("No backend selected. Enable at least one of VANILA, CUDA, OPENACC")
//                    }
//
//                    echo "Selected backends: ${backends}"
//
//                    for (backend in backends) {
//
//                        echo "Running backend: ${backend}"
//
//                        sh """
//                        ssh ${NCI_ALIAS} << EOF
//                        cd ${WORKDIR}
//                        echo "Running ${backend}..."
//                        sh ${WORKDIR}/qsub/iqtree/qsub_script.sh \
//                            ${IQTREE} ${V100} ${A100} ${WORKDIR} \
//                            ${DATASET_PATH} ${RUN_ALIASES}_${backend} \
//                            ${AA} ${DNA} ${LENGTH} ${MEM_FACTOR} ${REPETITIONS} \
//                            ${IQTREE_OPENMP} ${IQTREE_THREADS} ${AUTO} \
//                            ${PROJECT_NAME} ${backend} ${H200} ${ALL_NODE} \
//                            ${REV} ${VERBOSE}
//
//                        """
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