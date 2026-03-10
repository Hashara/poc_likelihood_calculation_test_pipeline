// =============================================================================
// JenkinsFileOrchestrator.groovy
//
// Reads a YAML + CSV from a config repo and invokes iqtree_cuda_test_pipeline
// in parallel for every row in the CSV.
//
// Parameters (5 inputs)
// ─────────────────────
//   CONFIG_REPO_URL    Git URL of the config repository
//   CONFIG_REPO_BRANCH Branch of the config repository  (default: master)
//   CONFIG_YAML_PATH   Relative path to pipeline_config.yaml inside the repo
//   CONFIG_CSV_PATH    Relative path to test_matrix.csv  inside the repo
//   REPETITIONS        Override execution.repetitions from YAML (leave blank = use YAML)
//
// YAML  → common params: cluster, execution settings, all_node flag, dataset base path
// CSV   → per-test params: data_type, alignment_length, tree_type, execution_type, iqtree_args, model, gpu_type, iqtree_omp, cpu_nodes, auto
//
// Per-row runtime construction
// ────────────────────────────
//   DATASET_PATH = general.parent_dataset_path / data_type / tree_type / model
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
        string(
            name:         'REPETITIONS',
            defaultValue: '',
            description:  'Number of times each test row is repeated on the cluster. ' +
                          'Overrides execution.repetitions in the YAML when set. Leave blank to use YAML value.'
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
                    // REPETITIONS param overrides YAML when provided; YAML is used otherwise
                    def yamlRepetitions = (cfg.execution?.repetitions ?: 1).toString()
                    def repetitions     = params.REPETITIONS?.trim() ?: yamlRepetitions
                    def failFast        =  cfg.execution?.fail_fast   ?: false
                    def allNode         =  cfg.gpu?.all_node          ?: false

                    // GPU_ARCH is derived per-row from the csv gpu_type column
                    // V100 → cc70 | A100 → cc80 | H200 → cc90 | none → '' (multi-arch default)
                    def gpuArchMap = [V100: 'cc70', A100: 'cc80', H200: 'cc90']

                    echo "=== YAML ========================="
                    echo "  workdir            : ${workdir}"
                    echo "  project_name       : ${projectName}"
                    echo "  nci_alias          : ${nciAlias}"
                    echo "  parent_dataset_path: ${parentDatasetPath}"
                    echo "  repetitions        : ${repetitions} ${params.REPETITIONS?.trim() ? '(param override)' : '(from YAML)'}"
                    echo "  fail_fast          : ${failFast}"
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

                        // Split with limit 10: iqtree_args (col 5) may contain spaces;
                        // remaining cols must not contain spaces
                        def parts = line.split(',', 10)
                        if (parts.size() < 10) {
                            echo "WARNING: skipping malformed row ${idx + 2}: '${line}'"
                            return
                        }

                        def dataType   = parts[0].trim()   // DNA | AA
                        def alignLen   = parts[1].trim()   // e.g. 100000
                        def treeType   = parts[2].trim()   // rooted | unrooted
                        def execType   = parts[3].trim()   // VANILA | CUDA | OPENACC | OPENACC_PROFILE
                        def iqtreeArgs = parts[4].trim()   // e.g. -blfix
                        def model      = parts[5].trim()   // e.g. GTR | Poisson
                        def gpuType    = parts[6].trim()   // none | V100 | A100 | H200
                        def iqtreeOmp  = parts[7].trim()   // true | false
                        def cpuNodes   = parts[8].trim()   // integer, e.g. 4
                        def auto       = parts[9].trim()   // true | false

                        // Per-row GPU arch derivation
                        def gpuArch    = gpuArchMap[gpuType] ?: ''

                        // Constructed values
                        def datasetPath    = "${parentDatasetPath}/${dataType}/${treeType}/${model}"
                        def fullIqtreeArgs = "-m ${model} ${iqtreeArgs}"
                        def runAlias       = "${runAliasPrefix}_${dataType}_${model}_${execType}_${idx + 1}"
                        def stageName      = "Row ${idx + 1} | ${dataType} | ${model} | ${execType} | ${gpuType}"

                        // Capture loop variables for the closure
                        def cDataType    = dataType
                        def cAlignLen    = alignLen
                        def cExecType    = execType
                        def cDatasetPath = datasetPath
                        def cFullArgs    = fullIqtreeArgs
                        def cRunAlias    = runAlias
                        def cGpuType     = gpuType
                        def cGpuArch     = gpuArch
                        def cIqtreeOmp   = iqtreeOmp
                        def cCpuNodes    = cpuNodes
                        def cAuto        = auto

                        parallelStages[stageName] = {
                            echo "▶ ${stageName}"
                            echo "  DATASET_PATH : ${cDatasetPath}"
                            echo "  IQTREE_ARGS  : ${cFullArgs}"
                            echo "  RUN_ALIASES  : ${cRunAlias}"
                            echo "  GPU_TYPE     : ${cGpuType}"
                            echo "  GPU_ARCH     : ${cGpuArch ?: '(multi-arch default)'}"
                            echo "  IQTREE_OMP   : ${cIqtreeOmp}"
                            echo "  CPU_NODES    : ${cCpuNodes}"

                            build job: 'iqtree_cuda_test_pipeline',
                                parameters: [
                                    // ── From YAML (common) ──────────────────
                                    string(name: 'WORKDIR',      value: workdir),
                                    string(name: 'PROJECT_NAME', value: projectName),
                                    string(name: 'NCI_ALIAS',    value: nciAlias),
                                    string(name: 'REPETITIONS',  value: repetitions),
                                    booleanParam(name: 'V100',     value: cGpuType == 'V100'),
                                    booleanParam(name: 'A100',     value: cGpuType == 'A100'),
                                    booleanParam(name: 'H200',     value: cGpuType == 'H200'),
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
                                    // When iqtree_omp=true the child runs OMP only — suppress IQTREE
                                    booleanParam(name: 'IQTREE',        value: !cIqtreeOmp.toBoolean()),
                                    booleanParam(name: 'BUILD',         value: false),
                                    booleanParam(name: 'LEN_BASED',     value: false),
                                    booleanParam(name: 'SPECIFIC_TREE', value: false),
                                    booleanParam(name: 'IQTREE_OPENMP', value: cIqtreeOmp.toBoolean()),
                                    booleanParam(name: 'CLONE_IQTREE',  value: false),
                                    booleanParam(name: 'PROFILE',        value: false),
                                    booleanParam(name: 'ENERGY_PROFILE', value: false),
                                    string(name: 'IQTREE_THREADS',      value: cCpuNodes),
                                    string(name: 'AUTO',                 value: cAuto),
                                    string(name: 'FACTOR',               value: '1'),
                                    string(name: 'GPU_ARCH',             value: cGpuArch),
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
