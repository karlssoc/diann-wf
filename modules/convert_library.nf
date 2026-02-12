// DIANN Library Conversion Module
// Converts spectral library from .speclib to .parquet format
//
// Optional FASTA support: When FASTA is provided with digest parameters,
// DIA-NN can correctly annotate proteotypic peptides (unique to single protein).
// Without FASTA, proteotypicity cannot be determined and may cause warnings
// like "N precursors were wrongly annotated in the library as proteotypic".

process CONVERT_LIBRARY {
    label 'diann_convert'

    publishDir "${params.outdir}${subdir ? '/' + subdir : ''}",
        mode: 'copy',
        overwrite: true

    tag "${subdir ? subdir + '/' : ''}${library.baseName}"

    input:
    path library
    val subdir
    path fasta, stageAs: 'reference.fasta'  // Optional: use file('NO_FILE') if not needed
    val cut                                  // Digest specificity, e.g., 'K*,R*' (empty string if no fasta)
    val missed_cleavages                     // Number of missed cleavages (0 if no fasta)

    output:
    path "${library.baseName}.parquet", emit: parquet_library
    path "convert_library.log", emit: log

    script:
    def diann_cmd = params.diann_binary ?: "/usr/bin/diann-${params.diann_version}/diann-linux"
    def out_name = "${library.baseName}.parquet"

    // Build FASTA parameters if FASTA is provided
    def use_fasta = fasta.name != 'NO_FILE'
    def fasta_params = use_fasta ? "--fasta reference.fasta --cut '${cut}' --missed-cleavages ${missed_cleavages}" : ""

    """
    echo "Converting library to parquet format"
    echo "FASTA annotation: ${use_fasta ? 'enabled' : 'disabled'}"

    ${diann_cmd} \\
        --lib ${library} \\
        --gen-spec-lib \\
        --out-lib ${out_name} \\
        ${fasta_params} \\
        --threads ${task.cpus} \\
        2>&1 | tee convert_library.log
    """
}
