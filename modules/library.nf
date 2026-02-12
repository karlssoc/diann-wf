// DIANN Library Generation Module
// Creates a spectral library from FASTA file
//
// Supports optional --fasta-filter for faster generation when only a subset
// of peptides is needed (e.g., from InfinDIA presearch)

process GENERATE_LIBRARY {
    label 'diann_library'

    // Dynamic publishDir: supports optional subdirectory organization
    // If subdir is provided: outdir/subdir/
    // If subdir is empty:    outdir/
    publishDir "${params.outdir}${subdir ? '/' + subdir : ''}",
        mode: 'copy',
        overwrite: true

    tag "${subdir ? subdir + '/' : ''}${library_name}"

    input:
    path fasta
    val library_name
    val subdir
    val search_params   // Map of search space overrides (e.g., params.library ?: [:])
    path tokens, stageAs: 'tokens.txt'
    path rt_model, stageAs: 'rt_model.pt'
    path im_model, stageAs: 'im_model.pt'
    path fr_model, stageAs: 'fr_model.pt'
    path fasta_filter, stageAs: 'fasta_filter.txt'  // Optional: stripped sequences to filter

    output:
    path "${library_name}.predicted.speclib", emit: library
    path "${library_name}.tsv", emit: tsv, optional: true
    path "library_generation.log", emit: log
    path "*.log.txt", emit: diann_log, optional: true

    script:
    // DIA-NN binary path (auto-computed from version if not explicitly set)
    def diann_cmd = params.diann_binary ?: "/usr/bin/diann-${params.diann_version}/diann-linux"

    // Check if using tuned models based on tokens file (must convert to string for bash)
    def use_tuned = (tokens.getName() != 'NO_FILE') ? 'true' : 'false'

    // Check if using fasta filter
    def use_filter = (fasta_filter.getName() != 'NO_FILE') ? 'true' : 'false'

    // Library generation parameters (from search_params map, with defaults)
    def min_fr_mz = search_params.min_fr_mz ?: 200
    def max_fr_mz = search_params.max_fr_mz ?: 1800
    def min_pep_len = search_params.min_pep_len ?: 7
    def max_pep_len = search_params.max_pep_len ?: 30
    def min_pr_mz = search_params.min_pr_mz ?: 350
    def max_pr_mz = search_params.max_pr_mz ?: 1650
    def min_pr_charge = search_params.min_pr_charge ?: 2
    def max_pr_charge = search_params.max_pr_charge ?: 3
    def cut = search_params.cut ?: 'K*,R*,!*P'
    def missed_cleavages = search_params.missed_cleavages ?: 1

    def met_excision = (search_params.met_excision != null ? search_params.met_excision : true) ? "--met-excision" : ""
    def unimod4 = (search_params.unimod4 != null ? search_params.unimod4 : true) ? "--unimod4" : ""

    """
    # Build model parameters - check for NO_FILE placeholders and empty files
    TOKENS_PARAM=""
    RT_PARAM=""
    IM_PARAM=""
    FR_PARAM=""
    FILTER_PARAM=""

    if [ "${use_tuned}" = "true" ] && [ -s "tokens.txt" ]; then
        TOKENS_PARAM="--tokens tokens.txt"
        echo "Using tuned tokens file"
    fi

    if [ "${use_tuned}" = "true" ] && [ -s "rt_model.pt" ]; then
        RT_PARAM="--rt-model rt_model.pt"
        echo "Using tuned RT model"
    fi

    if [ "${use_tuned}" = "true" ] && [ -s "im_model.pt" ]; then
        IM_PARAM="--im-model im_model.pt"
        echo "Using tuned IM model"
    fi

    if [ "${use_tuned}" = "true" ] && [ -s "fr_model.pt" ]; then
        FR_PARAM="--fr-model fr_model.pt"
        echo "Using tuned FR model"
    fi

    if [ "${use_filter}" = "true" ] && [ -s "fasta_filter.txt" ]; then
        FILTER_PARAM="--fasta-filter fasta_filter.txt"
        FILTER_COUNT=\$(wc -l < fasta_filter.txt)
        echo "Using FASTA filter with \$FILTER_COUNT sequences"
    fi

    # Run library generation
    ${diann_cmd} \\
        --fasta ${fasta} \\
        --gen-spec-lib \\
        --threads ${task.cpus} \\
        --verbose 1 \\
        --out-lib ${library_name} \\
        --predictor \\
        --fasta-search \\
        --min-fr-mz ${min_fr_mz} \\
        --max-fr-mz ${max_fr_mz} \\
        --min-pep-len ${min_pep_len} \\
        --max-pep-len ${max_pep_len} \\
        --min-pr-mz ${min_pr_mz} \\
        --max-pr-mz ${max_pr_mz} \\
        --min-pr-charge ${min_pr_charge} \\
        --max-pr-charge ${max_pr_charge} \\
        --cut '${cut}' \\
        --missed-cleavages ${missed_cleavages} \\
        ${met_excision} \\
        ${unimod4} \\
        \$TOKENS_PARAM \\
        \$RT_PARAM \\
        \$IM_PARAM \\
        \$FR_PARAM \\
        \$FILTER_PARAM \\
        2>&1 | tee library_generation.log
    """
}
