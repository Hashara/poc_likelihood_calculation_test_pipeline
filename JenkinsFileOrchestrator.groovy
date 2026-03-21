// =============================================================================
// JenkinsFileOrchestrator.groovy
//
// Reads a YAML + CSV from a config repo and invokes iqtree_cuda_test_pipeline
// in parallel for every row in the CSV.
//
// Parameters (8 inputs)
// ─────────────────────
//   CONFIG_REPO_URL    Git URL of the config repository
//   CONFIG_REPO_BRANCH Branch of the config repository  (default: master)
//   CONFIG_YAML_PATH   Relative path to pipeline_config.yaml inside the repo
//   CONFIG_CSV_PATH    Relative path to test_matrix.csv  inside the repo
//   WORKDIR            Working directory on the cluster (e.g. /scratch/dx61/workdir)
//   REPETITIONS        Override execution.repetitions from YAML (leave blank = use YAML)
//   RUN_ALIASES        Prefix for per-row run alias identifier (default: run)
//   PROFILE            Enable profiling in child builds (default: false)
//
// YAML  → common params: cluster, execution settings, all_node flag, dataset base path (workdir now a param)
// RUN_ALIASES param → prefix for per-row run alias (was previously in YAML as general.run_aliases)
// CSV   → per-test params: data_type, alignment_length, tree_type, execution_type, iqtree_args, model, gpu_type, iqtree_omp, cpu_nodes, auto, factor, taxa (optional)
//
// Per-row runtime construction
// ────────────────────────────
//   DATASET_PATH = general.parent_dataset_path / <dataset_path_pattern>
//                  default pattern: {data_type}/{tree_type}/{model}
//                  complex pattern: {data_type}/{model}/taxa_{taxa}/len_{alignment_length}
//   IQTREE_ARGS  = <csv_iqtree_args>  (model is NOT auto-prepended; use iqtree_args column if needed)
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
            name:         'WORKDIR',
            defaultValue: '',
            description:  'Working directory on the cluster (e.g. /scratch/dx61/workdir). ' +
                          'Scripts are copied here and child builds use it as their workdir.'
        )
        string(
            name:         'REPETITIONS',
            defaultValue: '',
            description:  'Number of times each test row is repeated on the cluster. ' +
                          'Overrides execution.repetitions in the YAML when set. Leave blank to use YAML value.'
        )
        string(
            name:         'RUN_ALIASES',
            defaultValue: 'run',
            description:  'Prefix for the run alias identifier (e.g. "run", "D1"). ' +
                          'Used to construct per-row RUN_ALIASES passed to child builds.'
        )
        booleanParam(
            name:         'PROFILE',
            defaultValue: false,
            description:  'Enable profiling in child builds.'
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
                    if (!params.WORKDIR?.trim()) {
                        error('WORKDIR is required — provide the working directory on the cluster.')
                    }
                    echo "Config repo : ${params.CONFIG_REPO_URL} @ ${params.CONFIG_REPO_BRANCH}"
                    echo "YAML        : ${params.CONFIG_YAML_PATH}"
                    echo "CSV         : ${params.CONFIG_CSV_PATH}"
                    echo "WORKDIR     : ${params.WORKDIR}"
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
                    def workdir  = params.WORKDIR?.trim() ?: ''

                    if (!nciAlias || !workdir) {
                        error('YAML must define general.nci_alias and WORKDIR parameter must be set')
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
                    def workdir           = params.WORKDIR?.trim()           ?: ''
                    def projectName       = cfg.general?.project_name        ?: ''
                    def nciAlias          = cfg.general?.nci_alias           ?: ''
                    def parentDatasetPath = cfg.general?.parent_dataset_path ?: ''
                    def runAliasPrefix    = params.RUN_ALIASES?.trim() ?: 'run'

                    // Dataset path pattern — controls how DATASET_PATH is built per row
                    // Default: legacy format  {data_type}/{tree_type}/{model}
                    // Complex: e.g.           {data_type}/{model}/taxa_{taxa}/len_{alignment_length}
                    def datasetPathPattern = cfg.general?.dataset_path_pattern ?: '{data_type}/{tree_type}/{model}'

                    if (!workdir || !projectName || !nciAlias || !parentDatasetPath) {
                        error('WORKDIR parameter must be set. YAML must define: ' +
                              'general.project_name, general.nci_alias, general.parent_dataset_path')
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
                    echo "  dataset_path_pattern: ${datasetPathPattern}"
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

                        // Split by comma — minimum 11 columns required,
                        // optional 12th column (taxa) for complex dataset layouts
                        def parts = line.split(',')
                        if (parts.size() < 11) {
                            echo "WARNING: skipping malformed row ${idx + 2}: '${line}'"
                            return
                        }

                        def dataType   = parts[0].trim()   // DNA | AA
                        def alignLen   = parts[1].trim()   // e.g. 100000
                        def treeType   = parts[2].trim()   // rooted | unrooted | none
                        def execType   = parts[3].trim()   // VANILA | CUDA | OPENACC | OPENACC_PROFILE
                        def iqtreeArgs = parts[4].trim()   // e.g. -blfix
                        def model      = parts[5].trim()   // e.g. GTR | GTR+I+G4 | LG+R4
                        def gpuType    = parts[6].trim()   // none | V100 | A100 | H200
                        def iqtreeOmp  = parts[7].trim()   // true | false
                        def cpuNodes   = parts[8].trim()   // integer, e.g. 4
                        def auto       = parts[9].trim()   // true | false
                        def factor     = parts[10].trim()  // integer, memory/time multiplier
                        def taxa       = parts.size() > 11 ? parts[11].trim() : ''  // optional, e.g. 100

                        // Per-row GPU arch derivation
                        def gpuArch    = gpuArchMap[gpuType] ?: ''

                        // Constructed values — dataset path uses the YAML pattern
                        def datasetPath = "${parentDatasetPath}/" + datasetPathPattern
                            .replace('{data_type}', dataType)
                            .replace('{tree_type}', treeType)
                            .replace('{model}', model)
                            .replace('{taxa}', taxa)
                            .replace('{alignment_length}', alignLen)

                        def fullIqtreeArgs = iqtreeArgs
                        // OMP rows use OMP_{cpuNodes} as the exec label; all others use execType
                        def execLabel      = iqtreeOmp.toBoolean() ? "OMP_${cpuNodes}" : execType
                        def taxaSuffix     = taxa ? "_taxa${taxa}" : ''
                        def runAlias       = "${runAliasPrefix}_${dataType}_${model}_${execLabel}${taxaSuffix}_run1_tree_1_${alignLen}_iqtree3"
                        def stageName      = "Row ${idx + 1} | ${dataType} | ${model} | ${execLabel} | ${gpuType}" +
                                             (taxa ? " | taxa_${taxa}" : '')

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
                        def cFactor      = factor

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
                                    booleanParam(name: 'PROFILE',        value: params.PROFILE),
                                    booleanParam(name: 'ENERGY_PROFILE', value: false),
                                    string(name: 'IQTREE_THREADS',      value: cCpuNodes),
                                    string(name: 'AUTO',                 value: cAuto),
                                    string(name: 'FACTOR',               value: cFactor),
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
