import groovy.yaml.YamlSlurper

/**
 * JenkinsFileConfig  –  YAML-driven configuration loader for IQ-TREE pipelines.
 *
 * Usage inside a Jenkinsfile / pipeline script:
 *
 *   def cfg = new JenkinsFileConfig('config/pipeline_config.yaml')
 *   // access any value
 *   cfg.get('general.workdir')
 *   cfg.get('backends.cuda')
 *
 *   // override with Jenkins params (params win over YAML defaults)
 *   cfg.mergeParams(params)
 *
 *   // generate the 100-taxa CSV test matrix
 *   cfg.generateTestCsv('scripts/test/iqtree/100taxa_1000000sites_tests.csv')
 */
class JenkinsFileConfig implements Serializable {

    private Map config

    // ---------------------------------------------------------------
    // Construction
    // ---------------------------------------------------------------

    /**
     * Load configuration from a YAML file.
     * @param yamlPath  path relative to the workspace (or absolute)
     */
    JenkinsFileConfig(String yamlPath) {
        def yamlContent = new File(yamlPath).text
        this.config = new YamlSlurper().parseText(yamlContent) as Map
    }

    /**
     * Build from a raw map (useful for tests).
     */
    JenkinsFileConfig(Map raw) {
        this.config = raw
    }

    // ---------------------------------------------------------------
    // Accessors
    // ---------------------------------------------------------------

    /**
     * Retrieve a value using a dot-separated key path.
     *   cfg.get('general.workdir')            => '/path/to/workdir'
     *   cfg.get('backends.cuda')              => true
     *   cfg.get('missing.key', 'fallback')    => 'fallback'
     */
    def get(String dotPath, def defaultValue = null) {
        def keys = dotPath.tokenize('.')
        def current = config
        for (key in keys) {
            if (current instanceof Map && current.containsKey(key)) {
                current = current[key]
            } else {
                return defaultValue
            }
        }
        return current
    }

    /**
     * Return the full config map (read-only copy).
     */
    Map getAll() {
        return Collections.unmodifiableMap(config)
    }

    // ---------------------------------------------------------------
    // Convenience getters for top-level sections
    // ---------------------------------------------------------------

    Map getGeneral()    { return config.general    ?: [:] }
    Map getData()       { return config.data       ?: [:] }
    Map getBackends()   { return config.backends   ?: [:] }
    Map getGpu()        { return config.gpu        ?: [:] }
    Map getExecution()  { return config.execution  ?: [:] }
    Map getProfiling()  { return config.profiling  ?: [:] }
    Map getDatasets()   { return config.datasets   ?: [:] }

    // ---------------------------------------------------------------
    // Parameter merging  (Jenkins params override YAML defaults)
    // ---------------------------------------------------------------

    /**
     * Merge Jenkins pipeline parameters into the loaded configuration.
     * Jenkins params use UPPER_CASE names; this method maps them to the
     * corresponding YAML keys so that user overrides always win.
     */
    void mergeParams(def params) {
        // Mapping: JENKINS_PARAM -> yaml.dot.path
        def mapping = [
            'WORKDIR'           : 'general.workdir',
            'PROJECT_NAME'      : 'general.project_name',
            'NCI_ALIAS'         : 'general.nci_alias',
            'RUN_ALIASES'       : 'general.run_aliases',

            'CLONE_IQTREE'      : 'iqtree_source.clone',
            'IQ_TREE_GIT_BRANCH': 'iqtree_source.git_branch',

            'DNA'               : 'data.dna',
            'AA'                : 'data.aa',
            'LENGTH'            : 'data.length',
            'DATASET_PATH'      : 'data.dataset_path',
            'LEN_BASED'         : 'data.len_based',
            'SPECIFIC_TREE'     : 'data.specific_tree',

            'VANILA'            : 'backends.vanila',
            'CUDA'              : 'backends.cuda',
            'OPENACC'           : 'backends.openacc',
            'OPENACC_PROFILE'   : 'backends.openacc_profile',

            'GPU_ARCH'          : 'gpu.gpu_arch',
            'V100'              : 'gpu.v100',
            'A100'              : 'gpu.a100',
            'H200'              : 'gpu.h200',
            'ALL_NODE'          : 'gpu.all_node',

            'BUILD'             : 'execution.build',
            'QSUB'              : 'execution.qsub',
            'IQTREE'            : 'execution.iqtree',
            'IQTREE_OPENMP'     : 'execution.iqtree_openmp',
            'IQTREE_THREADS'    : 'execution.iqtree_threads',
            'AUTO'              : 'execution.auto_threads',
            'IQTREE_ARGS'       : 'execution.iqtree_args',
            'FACTOR'            : 'execution.factor',
            'REPETITIONS'       : 'execution.repetitions',

            'PROFILE'           : 'profiling.profile',
            'ENERGY_PROFILE'    : 'profiling.energy_profile',
        ]

        mapping.each { paramName, dotPath ->
            if (params.containsKey(paramName) && params[paramName] != null) {
                set(dotPath, params[paramName])
            }
        }
    }

    // ---------------------------------------------------------------
    // CSV generation for the 100-taxa dataset
    // ---------------------------------------------------------------

    /**
     * Build the full test-matrix CSV for the 100taxa_1000000sites dataset.
     *
     * Columns:
     *   data_type, tree_type, model, tree_number, taxa, sites,
     *   alignment_file, tree_file, dataset_dir, iqtree_model_flag
     *
     * @param outputPath  file path for the generated CSV
     * @return            the File object written
     */
    File generateTestCsv(String outputPath) {
        def ds = get('datasets.100taxa_1000000sites')
        if (!ds) {
            throw new IllegalStateException(
                "No 'datasets.100taxa_1000000sites' section found in config")
        }

        def basePath      = ds.base_path
        def taxa           = ds.taxa
        def sites          = ds.sites
        def treesPerModel  = ds.trees_per_model

        def rows = []

        // DNA combinations
        def dnaModels     = ds.dna?.models     ?: []
        def dnaTreeTypes  = ds.dna?.tree_types ?: []

        for (model in dnaModels) {
            for (treeType in dnaTreeTypes) {
                for (int t = 1; t <= treesPerModel; t++) {
                    def datasetDir   = "${basePath}/DNA/${treeType}/${model}/tree_${t}"
                    def alignFile    = "alignment_${sites}.phy"
                    def treeFile     = "tree_${t}.treefile"
                    def modelFlag    = "-m ${model}"

                    rows << [
                        'DNA', treeType, model, t, taxa, sites,
                        alignFile, treeFile, datasetDir, modelFlag
                    ].join(',')
                }
            }
        }

        // AA combinations
        def aaModels     = ds.aa?.models     ?: []
        def aaTreeTypes  = ds.aa?.tree_types ?: []

        for (model in aaModels) {
            for (treeType in aaTreeTypes) {
                for (int t = 1; t <= treesPerModel; t++) {
                    def datasetDir   = "${basePath}/AA/${treeType}/${model}/tree_${t}"
                    def alignFile    = "alignment_${sites}.phy"
                    def treeFile     = "tree_${t}.treefile"
                    def modelFlag    = "-m ${model}"

                    rows << [
                        'AA', treeType, model, t, taxa, sites,
                        alignFile, treeFile, datasetDir, modelFlag
                    ].join(',')
                }
            }
        }

        def header = 'data_type,tree_type,model,tree_number,taxa,sites,alignment_file,tree_file,dataset_dir,iqtree_model_flag'
        def csvContent = header + '\n' + rows.join('\n') + '\n'

        def outFile = new File(outputPath)
        outFile.parentFile?.mkdirs()
        outFile.text = csvContent
        return outFile
    }

    // ---------------------------------------------------------------
    // Build the list of active backends
    // ---------------------------------------------------------------

    /**
     * Return the list of enabled backend names.
     */
    List<String> getActiveBackends() {
        def backends = []
        if (get('backends.vanila'))          backends << 'VANILA'
        if (get('backends.cuda'))            backends << 'CUDA'
        if (get('backends.openacc'))         backends << 'OPENACC'
        if (get('backends.openacc_profile')) backends << 'OPENACC_PROFILE'
        return backends
    }

    /**
     * Return the list of enabled data types.
     */
    List<String> getActiveDataTypes() {
        def types = []
        if (get('data.dna')) types << 'DNA'
        if (get('data.aa'))  types << 'AA'
        return types
    }

    // ---------------------------------------------------------------
    // Internal helpers
    // ---------------------------------------------------------------

    private void set(String dotPath, def value) {
        def keys = dotPath.tokenize('.')
        def current = config
        for (int i = 0; i < keys.size() - 1; i++) {
            if (!current.containsKey(keys[i])) {
                current[keys[i]] = [:]
            }
            current = current[keys[i]]
        }
        current[keys[-1]] = value
    }
}

return JenkinsFileConfig
