// DIANN Library Reprediction Module
// Generates a new spectral library using DIA-NN predictor based on peptides from an existing library

process REPREDICT_LIBRARY {
    label 'diann_library'

    // Dynamic publishDir: supports optional subdirectory organization
    publishDir "${params.outdir}${subdir ? '/' + subdir : ''}",
        mode: 'copy',
        overwrite: true

    tag "${subdir ? subdir + '/' : ''}${library_name}"

    input:
    path fasta
    path input_library
    val library_name
    val subdir
    path tokens, stageAs: 'tokens.txt'
    path rt_model, stageAs: 'rt_model.pt'
    path im_model, stageAs: 'im_model.pt'
    path fr_model, stageAs: 'fr_model.pt'

    output:
    path "${library_name}.predicted.speclib", emit: library
    path "${library_name}.tsv", emit: tsv, optional: true
    path "${library_name}.parquet", emit: parquet, optional: true
    path "library_reprediction.log", emit: log

    script:
    // Use absolute path to DIANN binary
    def diann_cmd = "/usr/bin/diann-${params.diann_version}/diann-linux"

    // Check if using tuned models
    def use_tuned = (tokens.getName() != 'NO_FILE') ? 'true' : 'false'

    """
    # Build model parameters
    TOKENS_PARAM=""
    RT_PARAM=""
    IM_PARAM=""
    FR_PARAM=""

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

    # Generate new spectral library based on peptides from existing library
    ${diann_cmd} \\
        --fasta ${fasta} \\
        --lib ${input_library} \\
        --gen-spec-lib \\
        --predictor \\
        --threads ${task.cpus} \\
        --verbose 1 \\
        --out-lib ${library_name} \\
        --pg-level 1 \\
        \$TOKENS_PARAM \\
        \$RT_PARAM \\
        \$IM_PARAM \\
        \$FR_PARAM \\
        2>&1 | tee library_reprediction.log
    """
}
