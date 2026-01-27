// DIANN Library Conversion Module
// Converts spectral library from .speclib to .parquet format

process CONVERT_LIBRARY {
    label 'diann_convert'

    publishDir "${params.outdir}${subdir ? '/' + subdir : ''}",
        mode: 'copy',
        overwrite: true

    tag "${subdir ? subdir + '/' : ''}${library.baseName}"

    input:
    path library
    val subdir

    output:
    path "${library.baseName}.parquet", emit: parquet_library
    path "convert_library.log", emit: log

    script:
    def diann_cmd = params.diann_binary
    def out_name = "${library.baseName}.parquet"

    """
    ${diann_cmd} \\
        --lib ${library} \\
        --gen-spec-lib \\
        --out-lib ${out_name} \\
        --threads ${task.cpus} \\
        2>&1 | tee convert_library.log
    """
}
