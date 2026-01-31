// DIA-NN Format Conversion Module
// Converts RAW/.d files to .dia format for faster subsequent processing
//
// Benefits:
//   - RAW/.d files read only once (during conversion)
//   - .dia files load much faster in all subsequent stages
//   - Eliminates need for mzML conversion in presearch
//   - Significant speedup for iterative workflows
//
// Supports: Thermo RAW, Bruker .d, mzML, WIFF

process CONVERT_TO_DIA {
    label 'diann_convert'

    publishDir "${params.outdir}/dia_converted",
        mode: 'copy',
        overwrite: true

    tag "${ms_file.name}"

    input:
    path ms_file    // Single MS file (RAW, .d folder, mzML, etc.)

    output:
    path "*.dia", emit: dia_file

    script:
    def diann_cmd = params.diann_binary
    def base_name = ms_file.name.replaceAll(/\.(raw|d|mzML|wiff)$/i, '')

    """
    echo "=== Converting to .dia format ==="
    echo "Input: ${ms_file}"
    echo ""

    ${diann_cmd} \\
        --f ${ms_file} \\
        --convert \\
        --threads ${task.cpus} \\
        --verbose 1

    # DIA-NN outputs filename.raw.dia or filename.d.dia, rename to filename.dia
    if [ -f "${ms_file}.dia" ]; then
        mv "${ms_file}.dia" "${base_name}.dia"
    fi

    echo ""
    echo "=== Conversion Complete ==="
    ls -lh *.dia
    """
}
