// =============================================================================
// JenkinsFileKingdoms.groovy
//
// DEDICATED orchestrator for the Empirical_kingdoms collection (kingdom x
// datatype empirical supermatrices). Separate from JenkinsFileOrchestrator.groovy
// so that the generic pipeline is completely unaffected.
//
// Register in Jenkins as a NEW job, suggested name: iqtree_kingdoms_orchestrator
//
// What differs from JenkinsFileOrchestrator.groovy
// -----------------------------------------------
//  1. NATIVE KINGDOM ADDRESSING. DATASET_PATH is built directly as
//        <parent_dataset_path>/<kingdom>/<data_type>/<model>
//     from the optional 17th CSV column `kingdom`. No {placeholder} machinery,
//     and no change to the generic orchestrator.
//  2. PRE-FLIGHT VALIDATION (new stage). Before any PBS job is submitted, every
//     unique DATASET_PATH is checked on the cluster for (a) existence and
//     (b) EXACTLY ONE alignment file. This is essential because
//     scripts/test/iqtree/lib_dataset.sh resolves the alignment by extension
//     (resolve_empirical_alignment step 3) - two alignments in one directory
//     makes the choice order-dependent and silently wrong.
//  3. GUARD RAILS for known OpenACC limitations:
//       - rows with execution_type OPENACC* may NOT pass -p/-q/-Q/-S
//         (partitioned analysis crashes the OpenACC build)
//       - data_type outside {AA,DNA,Codon} is rejected
//       - tree_mode other than 'none' is warned about (empirical data ships
//         no fixed tree, so a full ML search is the only valid mode)
//  4. Stage names are grouped by kingdom for a readable Jenkins view.
//  5. A run summary is printed before dispatch.
//
// Everything downstream is UNCHANGED: it triggers the same
// iqtree_cuda_test_pipeline job with the same parameter set.
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
            defaultValue: 'Empirical_kingdoms/pipeline_config.yaml',
            description:  'Relative path to the YAML config file inside the config repo'
        )
        string(
            name:         'CONFIG_CSV_PATH',
            defaultValue: 'Empirical_kingdoms/test_matrix.csv',
            description:  'Relative path to the test-matrix CSV inside the config repo'
        )
        string(
            name:         'WORKDIR',
            defaultValue: '',
            description:  'Working directory on the cluster (e.g. /scratch/dx61/workdir). ' +
                          'Scripts are copied here and child builds use it as their workdir.'
        )
        string(
            name:         'OUTPUT_DIR',
            defaultValue: '',
            description:  'Root directory for run outputs (e.g. /scratch/dx61/sa0557/results/run42). ' +
                          'Results are written under <OUTPUT_DIR>/<kingdom>/<data_type>/<model>/, ' +
                          'mirroring the dataset hierarchy under general.parent_dataset_path. ' +
                          'Leave empty to keep the legacy behaviour of writing beside the alignment, ' +
                          'inside the dataset tree.'
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
            name:         'SKIP_PREFLIGHT',
            defaultValue: false,
            description:  'Skip the cluster pre-flight dataset check. Only use if the datasets are known-good ' +
                          'and you need to dispatch immediately; a bad path otherwise wastes PBS queue time.'
        )
        booleanParam(
            name:         'PROFILE',
            defaultValue: false,
            description:  'Enable profiling in child builds.'
        )
        booleanParam(
            name:         'RESERVE_FULL_NODE',
            defaultValue: false,
            description:  'Reserve the whole CPU node but pass -nt (node CPUs - 1) to iqtree (leave 1 core idle for OS). Only effective for rows with iqtree_omp=true and either cpu_nodes=104+normalsr (-nt 103) or cpu_nodes=48 on the normal queue (-nt 47).'
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

        // ── 4. Pre-flight: validate every dataset path ON THE CLUSTER ─────────
        // Cheap insurance. lib_dataset.sh resolves the alignment by extension, so a
        // directory holding two alignments silently picks one at random, and a missing
        // directory only fails after the PBS job has queued and started. One ssh here
        // catches both before anything is submitted.
        stage('Pre-flight Dataset Check') {
            when { expression { return !params.SKIP_PREFLIGHT } }
            steps {
                script {
                    def cfg      = readYaml file: "config_repo/${params.CONFIG_YAML_PATH?.trim()}"
                    def nciAlias = cfg.general?.nci_alias ?: ''
                    def parent   = cfg.general?.parent_dataset_path ?: ''
                    if (!nciAlias || !parent) {
                        error('YAML must define general.nci_alias and general.parent_dataset_path')
                    }

                    // Collect the unique <kingdom>/<data_type>/<model> triples from the CSV.
                    def csvText = readFile("config_repo/${params.CONFIG_CSV_PATH?.trim()}")
                    def seen = [] as Set
                    csvText.split('\n').drop(1).each { line ->
                        if (!line?.trim()) return
                        def f = line.split(',')
                        if (f.size() < 17) return
                        def dt = f[0].trim(), mdl = f[5].trim(), kg = f[16].trim()
                        if (dt && mdl && kg) seen << "${kg}/${dt}/${mdl}"
                    }
                    if (!seen) {
                        error('Pre-flight: no valid rows found — check the CSV has the 17-column kingdom format.')
                    }
                    echo "Pre-flight: checking ${seen.size()} unique dataset paths under ${parent}"

                    // One remote pass. The checker is written to a file and shipped over,
                    // which avoids nested shell/Groovy quoting entirely.
                    writeFile file: 'preflight_paths.txt', text: seen.join('\n') + '\n'
                    writeFile file: 'preflight_check.sh', text: '''#!/bin/bash
# Verify each <kingdom>/<data_type>/<model> path holds EXACTLY ONE alignment.
# Extension list mirrors DATASET_ALN_EXTS in scripts/test/iqtree/lib_dataset.sh.
PARENT="$1"
BAD=0
EXTS='\\.(fasta|fas|fa|phy|phylip|nex|nexus|aln)$'
while read -r p; do
  [ -z "$p" ] && continue
  d="$PARENT/$p"
  if [ ! -d "$d" ]; then
    printf "  MISSING    %s\\n" "$p"; BAD=1; continue
  fi
  n=$(ls "$d" 2>/dev/null | grep -cE "$EXTS")
  if [ "$n" -eq 0 ]; then
    printf "  NO_ALIGN   %s\\n" "$p"; BAD=1
  elif [ "$n" -gt 1 ]; then
    printf "  AMBIGUOUS  %s (%s alignments - resolution is order-dependent)\\n" "$p" "$n"; BAD=1
  else
    printf "  OK         %-44s -> %s\\n" "$p" "$(ls "$d" | grep -E "$EXTS")"
  fi
done
exit $BAD
'''
                    sh "scp -q preflight_check.sh preflight_paths.txt ${nciAlias}:/tmp/"
                    def rc = sh(returnStatus: true,
                                script: "ssh ${nciAlias} 'bash /tmp/preflight_check.sh \"${parent}\" < /tmp/preflight_paths.txt'")
                    if (rc != 0) {
                        error('Pre-flight FAILED — one or more dataset paths are missing, empty, or ambiguous ' +
                              '(see the list above). Fix the staging or the CSV before dispatching; ' +
                              'set SKIP_PREFLIGHT=true only to bypass deliberately.')
                    }
                    echo 'Pre-flight OK — every dataset path resolves to exactly one alignment.'
                }
            }
        }

        // ── 5. Read YAML + CSV → launch parallel child builds ─────────────────
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
                        def execType   = parts[3].trim()   // VANILA | CUDA | IQTREE_GPU | OPENACC | OPENACC_PROFILE
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
                        def kingdom        = parts.size() > 16 ? parts[16].trim() : ''      // REQUIRED here: Animalia|Fungi|Plantae|Protista

                        // Per-row GPU arch derivation
                        def gpuArch    = gpuArchMap[gpuType] ?: ''

                        // Constructed values — dataset path uses the YAML pattern
                        // ── Native kingdom addressing ────────────────────
                        // <parent>/<kingdom>/<data_type>/<model>
                        // No {placeholder} substitution: this orchestrator serves
                        // exactly one collection shape, so the path is explicit.
                        if (!kingdom) {
                            error("Row ${idx + 2}: the 'kingdom' column (17th) is required by " +
                                  "JenkinsFileKingdoms. Use JenkinsFileOrchestrator for other collections.")
                        }
                        def datasetPath = "${parentDatasetPath}/${kingdom}/${dataType}/${model}"

                        // ── Guard rails ──────────────────────────────────
                        if (!(dataType in ['AA', 'DNA', 'Codon'])) {
                            error("Row ${idx + 2}: data_type='${dataType}' is not one of AA|DNA|Codon. " +
                                  "Note the simulated branch of test_script_iqtree.sh matches ONLY 'AA' or 'DNA' " +
                                  "and would silently skip anything else.")
                        }
                        if (execType.startsWith('OPENACC') && (iqtreeArgs =~ /(^|\s)-[pqQS](\s|$)/)) {
                            error("Row ${idx + 2}: execution_type=${execType} with a partition flag in " +
                                  "iqtree_args ('${iqtreeArgs}'). The OpenACC build CRASHES on partitioned " +
                                  "analysis (-p/-q/-Q/-S). Remove it, or run the row as VANILA.")
                        }
                        if (treeMode != 'none') {
                            echo "WARNING row ${idx + 2}: tree_mode='${treeMode}' but empirical alignments ship " +
                                 "no fixed tree; lib_dataset.sh will fall back to a full ML search."
                        }

                        def fullIqtreeArgs = iqtreeArgs
                        // OMP rows use OMP_{cpuNodes} as the exec label; all others use execType
                        def execLabel      = iqtreeOmp.toBoolean() ? "OMP_${cpuNodes}" : execType
                        def taxaSuffix     = taxa ? "_taxa${taxa}" : ''
                        def uniqueNameSuffix = uniqueName ? "_${uniqueName}" : ''
                        def runAlias         = "${runAliasPrefix}_${dataType}_${model}_${execLabel}${taxaSuffix}_run1_tree_1_${alignLen}_iqtree3${uniqueNameSuffix}"
                        def stageName      = "${kingdom} | ${dataType} | ${model} | ${execLabel}" +
                                             (gpuType != 'none' ? " | ${gpuType}" : '') +
                                             (taxa ? " | ${taxa}tx" : '')

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
                        // Output relocation. Both are loop-invariant, but capture them
                        // alongside the rest so the closure has no free variables.
                        def cOutputDir       = params.OUTPUT_DIR ?: ''
                        def cDatasetRoot     = parentDatasetPath ?: ''

                        parallelStages[stageName] = {
                            echo "▶ ${stageName}"
                            echo "  DATASET_PATH : ${cDatasetPath}"
                            echo "  OUTPUT       : ${cOutputDir ? cOutputDir + '/' + cDatasetPath.replace(cDatasetRoot + '/', '') : '(beside the alignment)'}"
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
                                    booleanParam(name: 'IQTREE_GPU',            value: cExecType == 'IQTREE_GPU'),
                                    booleanParam(name: 'IQTREE_GPU_SHARED',     value: cExecType == 'IQTREE_GPU_SHARED'),
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
                                    booleanParam(name: 'INTEL_VANILA_CLX',      value: cExecType == 'INTEL_VANILA_CLX'),
                                    string(name: 'IQTREE_ARGS',  value: cFullArgs),
                                    string(name: 'DATASET_PATH', value: cDatasetPath),
                                    // Output relocation: DATASET_ROOT is the collection root, so the
                                    // child can strip it off DATASET_PATH and rebuild the same
                                    // <kingdom>/<data_type>/<model> path beneath OUTPUT_DIR.
                                    string(name: 'OUTPUT_DIR',   value: cOutputDir),
                                    string(name: 'DATASET_ROOT', value: cDatasetRoot),
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

                    // ── Run summary before dispatch ──────────────────
                    echo "=" * 66
                    echo "Empirical_kingdoms dispatch: ${parallelStages.size()} rows"
                    def byKingdom = [:]
                    parallelStages.keySet().each { k ->
                        def kg = k.split(/\s*\|\s*/)[0]
                        byKingdom[kg] = (byKingdom[kg] ?: 0) + 1
                    }
                    byKingdom.sort().each { kg, n -> echo String.format("  %-12s %3d rows", kg, n) }
                    echo "=" * 66

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
