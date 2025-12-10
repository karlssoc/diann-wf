// DIANN Library Generation Module
// Creates a spectral library from FASTA file

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
    path tokens, stageAs: 'tokens.txt'
    path rt_model, stageAs: 'rt_model.pt'
    path im_model, stageAs: 'im_model.pt'
    path fr_model, stageAs: 'fr_model.pt'

    output:
    path "${library_name}.predicted.speclib", emit: library
    path "${library_name}.tsv", emit: tsv, optional: true
    path "library_generation.log", emit: log

    script:
    // Tuned model parameters (only add if files exist)
    def use_tuned = tokens.name != 'NO_FILE'
    def tokens_param = use_tuned ? "--tokens tokens.txt" : ""
    def rt_param = (use_tuned && rt_model.name != 'NO_FILE') ? "--rt-model rt_model.pt" : ""
    def im_param = (use_tuned && im_model.name != 'NO_FILE') ? "--im-model im_model.pt" : ""
    def fr_param = (use_tuned && fr_model.name != 'NO_FILE') ? "--fr-model fr_model.pt" : ""

    // Library generation parameters
    def min_fr_mz = params.library?.min_fr_mz ?: 200
    def max_fr_mz = params.library?.max_fr_mz ?: 1800
    def min_pep_len = params.library?.min_pep_len ?: 7
    def max_pep_len = params.library?.max_pep_len ?: 30
    def min_pr_mz = params.library?.min_pr_mz ?: 350
    def max_pr_mz = params.library?.max_pr_mz ?: 1650
    def min_pr_charge = params.library?.min_pr_charge ?: 2
    def max_pr_charge = params.library?.max_pr_charge ?: 3
    def cut = params.library?.cut ?: 'K*,R*'
    def missed_cleavages = params.library?.missed_cleavages ?: 1

    def met_excision = params.library?.met_excision ? "--met-excision" : ""
    def unimod4 = params.library?.unimod4 ? "--unimod4" : ""

    """
    diann \\
        --fasta ${fasta} \\
        --gen-spec-lib \\
        --threads ${params.threads} \\
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
        ${tokens_param} \\
        ${rt_param} \\
        ${im_param} \\
        ${fr_param} \\
        2>&1 | tee library_generation.log
    """
}
