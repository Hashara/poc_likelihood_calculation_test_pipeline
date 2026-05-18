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
// YAML  → common params: cluster, execution settings, all_node flag, dataset base path, num_trees (workdir now a param)
// RUN_ALIASES param → prefix for per-row run alias (was previously in YAML as general.run_aliases)
// CSV   → per-test params: data_type, alignment_length, tree_type, execution_type, iqtree_args, model, gpu_type, iqtree_omp, cpu_nodes, auto, factor, taxa (optional), wall_time_factor (optional), tree_mode (optional: te|t|none), unique_name (optional: appended to RUN_ALIASES), normalsr (optional: true|false, default false). NOTE: INTEL_VANILA binary is built for Sapphire Rapids — set normalsr=true for those rows or the job will likely SIGILL on the normal queue (Cascade Lake).
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
        booleanParam(
            name:         'RESERVE_FULL_NODE',
            defaultValue: false,
            description:  'Reserve the whole 104-CPU normalsr node but pass -nt 103 to iqtree (leave 1 core idle for OS). Only effective for rows with iqtree_omp=true, cpu_nodes=104, and normalsr enabled.'
        )
        booleanParam(
            name:         'ENERGY_PROFILE',
            defaultValue: false,
            description:  'Enable energy profiling (Linaro Forge perf-report) in child builds.'
        )
        booleanParam(
            name:         'PROFILE_NSYS',
            defaultValue: false,
            description:  'Run nsys timeline profiling (~5-10% overhead, suitable for full runs).'
        )
        booleanParam(
            name:         'PROFILE_NCU',
            defaultValue: false,
            description:  'Run ncu kernel-detail profiling (~10-50x overhead, use NCU_LAUNCH_COUNT to limit).'
        )
        string(
            name:         'NCU_LAUNCH_COUNT',
            defaultValue: '0',
            description:  'NCU: max kernel launches to profile (0 = all, 20-50 recommended).'
        )
        string(
            name:         'NCU_KERNEL_FILTER',
            defaultValue: '',
            description:  'NCU: kernel name regex filter (e.g. batchedInternal|reductionKernel).'
        )
        string(
            name:         'NCU_SKIP_COUNT',
            defaultValue: '0',
            description:  'NCU: skip first N kernel launches before profiling begins.'
        )
        string(
            name:         'NSYS_DELAY',
            defaultValue: '0',
            description:  'Nsys: delay capture start by N seconds (skip init/ModelFinder for tree-search-only profiles).'
        )
        string(
            name:         'NSYS_DURATION',
            defaultValue: '0',
            description:  'Nsys: bound capture to N seconds (0 = unbounded; cap long runs).'
        )
        string(
            name:         'NSYS_SAMPLE',
            defaultValue: 'none',
            description:  'Nsys: CPU sampling mode (none|process-tree|system-wide). Default none — GPU-bound workloads do not need CPU stacks.'
        )
        string(
            name:         'ENV_VARS',
            defaultValue: '',
            description:  'Extra comma-separated KEY=VALUE env vars forwarded to child iqtree runs (e.g. OMP_TARGET_OFFLOAD=MANDATORY). Composes with NSYS_*/NCU_* knobs above.'
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
                    def cfg      = readYaml file: "config_repo/${params.CONFIG_YAML_PATH?.trim()}"
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
                    def yamlPath = params.CONFIG_YAML_PATH?.trim()
                    def csvPath  = params.CONFIG_CSV_PATH?.trim()
                    def cfg = readYaml file: "config_repo/${yamlPath}"

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

                    // Number of tree folders (tree_1..tree_N) — common to all rows
                    def numTrees = (cfg.general?.num_trees ?: 10).toString()

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
                    echo "  num_trees          : ${numTrees}"
                    echo "=================================="

                    // ── Load CSV ─────────────────────────────────────────────
                    def csvText  = readFile("config_repo/${csvPath}")
                    def lines    = csvText.trim().split('\n') as List

                    // Drop header row
                    lines.remove(0)

                    // Drop blank lines
                    lines = lines.findAll { it?.trim() }

                    if (lines.isEmpty()) {
                        error("CSV has no data rows: ${csvPath}")
                    }

                    echo "Loaded ${lines.size()} test row(s) — launching in parallel"

                    // ── Build parallel stage map ─────────────────────────────
                    def parallelStages = [failFast: failFast]

                    lines.eachWithIndex { line, idx ->

                        // Split by comma, respecting double-quoted fields
                        // (e.g. iqtree_args may contain commas: "-m GTR{1.0,2.0}")
                        def parts = []
                        def current = new StringBuilder()
                        boolean inQuotes = false
                        for (int ci = 0; ci < line.length(); ci++) {
                            char ch = line.charAt(ci)
                            if (ch == '"' as char) {
                                inQuotes = !inQuotes
                            } else if (ch == ',' as char && !inQuotes) {
                                parts << current.toString()
                                current = new StringBuilder()
                            } else {
                                current.append(ch)
                            }
                        }
                        parts << current.toString()  // last field
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
                        def memFactor  = parts[10].trim()  // integer, memory multiplier
                        def taxa           = parts.size() > 11 ? parts[11].trim() : ''   // optional, e.g. 100
                        def wallTimeFactor = parts.size() > 12 ? parts[12].trim() : '1'  // optional, default 1 (1=10min)
                        def treeMode       = parts.size() > 13 ? parts[13].trim() : 'te' // optional, default te (te|t|none)
                        def uniqueName     = parts.size() > 14 ? parts[14].trim() : ''   // optional, appended to run alias
                        def normalsr       = parts.size() > 15 ? parts[15].trim() : 'false' // optional, true|false (normalsr queue)

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
                        def uniqueNameSuffix = uniqueName ? "_${uniqueName}" : ''
                        def runAlias         = "${runAliasPrefix}_${dataType}_${model}_${execLabel}${taxaSuffix}_run1_tree_1_${alignLen}_iqtree3${uniqueNameSuffix}"
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
                        def cMemFactor       = memFactor
                        def cWallTimeFactor  = wallTimeFactor
                        def cTreeMode        = treeMode
                        def cUniqueName      = uniqueName
                        def cNormalsr        = normalsr

                        parallelStages[stageName] = {
                            echo "▶ ${stageName}"
                            echo "  DATASET_PATH : ${cDatasetPath}"
                            echo "  IQTREE_ARGS  : ${cFullArgs}"
                            echo "  RUN_ALIASES  : ${cRunAlias}"
                            if (cUniqueName) echo "  UNIQUE_NAME  : ${cUniqueName}"
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
                                    booleanParam(name: 'VANILA',                value: cExecType == 'VANILA'),
                                    booleanParam(name: 'CUDA',                  value: cExecType == 'CUDA'),
                                    booleanParam(name: 'OPENACC',               value: cExecType == 'OPENACC'),
                                    booleanParam(name: 'OPENACC_PROFILE',       value: cExecType == 'OPENACC_PROFILE'),
                                    booleanParam(name: 'OPENACC_DEBUG',         value: cExecType == 'OPENACC_DEBUG'),
                                    booleanParam(name: 'OPENACC_DEBUG_PROFILE', value: cExecType == 'OPENACC_DEBUG_PROFILE'),
                                    booleanParam(name: 'OPENMP_GPU',              value: cExecType == 'OPENMP_GPU'),
                                    booleanParam(name: 'OPENMP_GPU_PROFILE',      value: cExecType == 'OPENMP_GPU_PROFILE'),
                                    booleanParam(name: 'OPENMP_GPU_DEBUG',        value: cExecType == 'OPENMP_GPU_DEBUG'),
                                    booleanParam(name: 'OPENMP_GPU_DEBUG_PROFILE', value: cExecType == 'OPENMP_GPU_DEBUG_PROFILE'),
                                    booleanParam(name: 'CLANG_VANILA',          value: cExecType == 'CLANG_VANILA'),
                                    booleanParam(name: 'INTEL_VANILA',          value: cExecType == 'INTEL_VANILA'),
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
                                    booleanParam(name: 'PROFILE_NSYS',  value: params.PROFILE_NSYS),
                                    booleanParam(name: 'PROFILE_NCU',   value: params.PROFILE_NCU),
                                    string(name: 'NCU_LAUNCH_COUNT',    value: params.NCU_LAUNCH_COUNT),
                                    string(name: 'NCU_KERNEL_FILTER',   value: params.NCU_KERNEL_FILTER),
                                    string(name: 'NCU_SKIP_COUNT',      value: params.NCU_SKIP_COUNT),
                                    // Compose NSYS_* knobs + user ENV_VARS into the single ENV_VARS
                                    // string the child build passes to profile_{nsys,ncu}_qsub_script.sh.
                                    // Non-default values only — keeps the qsub -v list minimal.
                                    string(name: 'ENV_VARS', value: ([
                                        params.NSYS_DELAY            != '0'      ? "NSYS_DELAY=${params.NSYS_DELAY}"                       : null,
                                        params.NSYS_DURATION         != '0'      ? "NSYS_DURATION=${params.NSYS_DURATION}"                 : null,
                                        params.NSYS_SAMPLE           != 'none'   ? "NSYS_SAMPLE=${params.NSYS_SAMPLE}"                     : null,
                                        params.ENV_VARS?.trim()                  ? params.ENV_VARS.trim()                                  : null,
                                    ] - null).join(',')),
                                    booleanParam(name: 'ENERGY_PROFILE', value: params.ENERGY_PROFILE),
                                    string(name: 'IQTREE_THREADS',      value: cCpuNodes),
                                    string(name: 'AUTO',                 value: cAuto),
                                    string(name: 'MEM_FACTOR',            value: cMemFactor),
                                    string(name: 'WALL_TIME_FACTOR',     value: cWallTimeFactor),
                                    string(name: 'TREE_MODE',            value: cTreeMode),
                                    string(name: 'GPU_ARCH',             value: cGpuArch),
                                    // NORMALSR is taken from the CSV as-is. Caller is responsible for setting
                                    // normalsr=true on INTEL_VANILA rows (Sapphire Rapids binary).
                                    booleanParam(name: 'NORMALSR',       value: cNormalsr.toBoolean()),
                                    booleanParam(name: 'RESERVE_FULL_NODE', value: params.RESERVE_FULL_NODE),
                                    string(name: 'NUM_TREES',            value: numTrees),
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
