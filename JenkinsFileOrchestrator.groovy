// =============================================================================
// JenkinsFileOrchestrator.groovy
//
// Reads a YAML + CSV from a config repo and invokes iqtree_cuda_test_pipeline
// in parallel for every row in the CSV.
//
// Parameters (4 inputs only)
// ──────────────────────────
//   CONFIG_REPO_URL    Git URL of the config repository
//   CONFIG_REPO_BRANCH Branch of the config repository  (default: main)
//   CONFIG_YAML_PATH   Relative path to pipeline_config.yaml inside the repo
//   CONFIG_CSV_PATH    Relative path to test_matrix.csv  inside the repo
//
// YAML  → common params: cluster, GPU, repetitions, dataset base path, tree type
// CSV   → per-test params: data_type, alignment_length, execution_type, iqtree_args, model
//
// Per-row runtime construction
// ────────────────────────────
//   DATASET_PATH = general.parent_dataset_path / data_type / general.tree_type / model
//   IQTREE_ARGS  = "-m <model> <csv_iqtree_args>"
//   RUN_ALIASES  = "<run_aliases>_<data_type>_<model>_<execution_type>_<row_index>"
// =============================================================================

pipeline {
    agent any

    parameters {
        string(
            name:         'CONFIG_REPO_URL',
            defaultValue: '',
            description:  'Git URL of the config repo (e.g. https://github.com/org/iqtree-pipeline-config.git)'
        )
        string(
            name:         'CONFIG_REPO_BRANCH',
            defaultValue: 'master',
            description:  'Branch of the config repo to check out'
        )
        string(
            name:         'CONFIG_YAML_PATH',
            defaultValue: '100taxa_10000sites/pipeline_config.yaml',
            description:  'Relative path to the YAML config file inside the config repo'
        )
        string(
            name:         'CONFIG_CSV_PATH',
            defaultValue: '100taxa_10000sites/test_matrix.csv',
            description:  'Relative path to the test-matrix CSV inside the config repo'
        )
    }

    stages {

        // ── 1. Validate ───────────────────────────────────────────────────────
        stage('Validate') {
            steps {
                script {
                    if (!params.CONFIG_REPO_URL?.trim()) {
                        error('CONFIG_REPO_URL is required — provide the Git URL of the config repository.')
                    }
                    echo "Config repo : ${params.CONFIG_REPO_URL} @ ${params.CONFIG_REPO_BRANCH}"
                    echo "YAML        : ${params.CONFIG_YAML_PATH}"
                    echo "CSV         : ${params.CONFIG_CSV_PATH}"
                }
            }
        }

        // ── 2. Checkout config repo ───────────────────────────────────────────
        stage('Checkout Config Repo') {
            steps {
                // Checks out into ./config_repo/ so the pipeline workspace
                // (scripts/, groovy files) is not overwritten.
                dir('config_repo') {
                    git url: params.CONFIG_REPO_URL,
                        branch: params.CONFIG_REPO_BRANCH
                }
            }
        }

        // ── 3. Copy scripts to cluster ────────────────────────────────────────
        stage('Copy Scripts') {
            steps {
                script {
                    def cfg      = readYaml file: "config_repo/${params.CONFIG_YAML_PATH}"
                    def nciAlias = cfg.general?.nci_alias ?: ''
                    def workdir  = cfg.general?.workdir   ?: ''

                    if (!nciAlias || !workdir) {
                        error('YAML must define general.nci_alias and general.workdir')
                    }

                    sh "scp -r scripts/* ${nciAlias}:${workdir}"
                }
            }
        }

        // ── 4. Read YAML + CSV → launch parallel child builds ─────────────────
        stage('Run Tests in Parallel') {
            steps {
                script {

                    // ── Load YAML ────────────────────────────────────────────
                    def cfg = readYaml file: "config_repo/${params.CONFIG_YAML_PATH}"

                    // Required
                    def workdir           = cfg.general?.workdir             ?: ''
                    def projectName       = cfg.general?.project_name        ?: ''
                    def nciAlias          = cfg.general?.nci_alias           ?: ''
                    def parentDatasetPath = cfg.general?.parent_dataset_path ?: ''
                    def runAliasPrefix    = cfg.general?.run_aliases         ?: 'run'

                    if (!workdir || !projectName || !nciAlias || !parentDatasetPath) {
                        error('YAML must define: general.workdir, general.project_name, ' +
                              'general.nci_alias, general.parent_dataset_path')
                    }

                    // Optional with defaults
                    def repetitions = (cfg.execution?.repetitions ?: 1).toString()
                    def failFast    =  cfg.execution?.fail_fast   ?: false
                    def gpuType     =  cfg.gpu?.gpu_type          ?: 'none'
                    def allNode     =  cfg.gpu?.all_node          ?: false

                    // Derive GPU_ARCH from gpu_type
                    // V100 → cc70 | A100 → cc80 | H200 → cc90 | none → '' (multi-arch default)
                    def gpuArchMap = [V100: 'cc70', A100: 'cc80', H200: 'cc90']
                    def gpuArch    = gpuArchMap[gpuType] ?: ''

                    echo "=== YAML ========================="
                    echo "  workdir            : ${workdir}"
                    echo "  project_name       : ${projectName}"
                    echo "  nci_alias          : ${nciAlias}"
                    echo "  parent_dataset_path: ${parentDatasetPath}"
                    echo "  repetitions        : ${repetitions}"
                    echo "  fail_fast          : ${failFast}"
                    echo "  gpu_type           : ${gpuType}"
                    echo "  gpu_arch           : ${gpuArch ?: '(multi-arch default)'}"
                    echo "  all_node           : ${allNode}"
                    echo "=================================="

                    // ── Load CSV ─────────────────────────────────────────────
                    def csvText  = readFile("config_repo/${params.CONFIG_CSV_PATH}")
                    def lines    = csvText.trim().split('\n') as List

                    // Drop header row
                    lines.remove(0)

                    // Drop blank lines
                    lines = lines.findAll { it?.trim() }

                    if (lines.isEmpty()) {
                        error("CSV has no data rows: ${params.CONFIG_CSV_PATH}")
                    }

                    echo "Loaded ${lines.size()} test row(s) — launching in parallel"

                    // ── Build parallel stage map ─────────────────────────────
                    def parallelStages = [failFast: failFast]

                    lines.eachWithIndex { line, idx ->

                        // Split with limit 6: iqtree_args may contain spaces
                        def parts = line.split(',', 6)
                        if (parts.size() < 6) {
                            echo "WARNING: skipping malformed row ${idx + 2}: '${line}'"
                            return
                        }

                        def dataType   = parts[0].trim()   // DNA | AA
                        def alignLen   = parts[1].trim()   // e.g. 100000
                        def treeType   = parts[2].trim()   // rooted | unrooted
                        def execType   = parts[3].trim()   // VANILA | CUDA | OPENACC | OPENACC_PROFILE
                        def iqtreeArgs = parts[4].trim()   // e.g. -blfix
                        def model      = parts[5].trim()   // e.g. GTR | Poisson

                        // Constructed values
                        def datasetPath    = "${parentDatasetPath}/${dataType}/${treeType}/${model}"
                        def fullIqtreeArgs = "-m ${model} ${iqtreeArgs}"
                        def runAlias       = "${runAliasPrefix}_${dataType}_${model}_${execType}_${idx + 1}"
                        def stageName      = "Row ${idx + 1} | ${dataType} | ${model} | ${execType}"

                        // Capture loop variables for the closure
                        def cDataType    = dataType
                        def cAlignLen    = alignLen
                        def cExecType    = execType
                        def cDatasetPath = datasetPath
                        def cFullArgs    = fullIqtreeArgs
                        def cRunAlias    = runAlias

                        parallelStages[stageName] = {
                            echo "▶ ${stageName}"
                            echo "  DATASET_PATH : ${cDatasetPath}"
                            echo "  IQTREE_ARGS  : ${cFullArgs}"
                            echo "  RUN_ALIASES  : ${cRunAlias}"

                            build job: 'iqtree_cuda_test_pipeline',
                                parameters: [
                                    // ── From YAML (common) ──────────────────
                                    string(name: 'WORKDIR',      value: workdir),
                                    string(name: 'PROJECT_NAME', value: projectName),
                                    string(name: 'NCI_ALIAS',    value: nciAlias),
                                    string(name: 'REPETITIONS',  value: repetitions),
                                    booleanParam(name: 'V100',     value: gpuType == 'V100'),
                                    booleanParam(name: 'A100',     value: gpuType == 'A100'),
                                    booleanParam(name: 'H200',     value: gpuType == 'H200'),
                                    booleanParam(name: 'ALL_NODE', value: allNode),

                                    // ── From CSV (per row) ──────────────────
                                    booleanParam(name: 'DNA',    value: cDataType == 'DNA'),
                                    booleanParam(name: 'AA',     value: cDataType == 'AA'),
                                    string(name: 'LENGTH',       value: cAlignLen),
                                    booleanParam(name: 'VANILA',          value: cExecType == 'VANILA'),
                                    booleanParam(name: 'CUDA',            value: cExecType == 'CUDA'),
                                    booleanParam(name: 'OPENACC',         value: cExecType == 'OPENACC'),
                                    booleanParam(name: 'OPENACC_PROFILE', value: cExecType == 'OPENACC_PROFILE'),
                                    string(name: 'IQTREE_ARGS',  value: cFullArgs),
                                    string(name: 'DATASET_PATH', value: cDatasetPath),
                                    string(name: 'RUN_ALIASES',  value: cRunAlias),

                                    // ── Fixed defaults ──────────────────────
                                    booleanParam(name: 'QSUB',          value: true),
                                    booleanParam(name: 'IQTREE',        value: true),
                                    booleanParam(name: 'BUILD',         value: false),
                                    booleanParam(name: 'LEN_BASED',     value: false),
                                    booleanParam(name: 'SPECIFIC_TREE', value: false),
                                    booleanParam(name: 'IQTREE_OPENMP', value: false),
                                    booleanParam(name: 'CLONE_IQTREE',  value: false),
                                    booleanParam(name: 'PROFILE',        value: false),
                                    booleanParam(name: 'ENERGY_PROFILE', value: false),
                                    string(name: 'IQTREE_THREADS',      value: '1'),
                                    string(name: 'AUTO',                 value: 'true'),
                                    string(name: 'FACTOR',               value: '1'),
                                    string(name: 'GPU_ARCH',             value: gpuArch),
                                    string(name: 'IQ_TREE_GIT_BRANCH',  value: 'main'),
                                ],
                                wait:      true,
                                propagate: true
                        }
                    }

                    parallel parallelStages
                }
            }
        }
    }

    post {
        success {
            echo 'All test rows completed successfully!'
        }
        failure {
            echo 'One or more test rows failed — check the child builds for details.'
        }
    }
}
