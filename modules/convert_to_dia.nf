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

    publishDir "${params.outdir}/dia_converted/${sample_id}",
        mode: 'copy',
        overwrite: true

    tag "${sample_id}/${ms_file.name}"

    input:
    tuple val(sample_id), path(ms_file)    // Sample ID and MS file

    output:
    tuple val(sample_id), path("*.dia"), emit: dia_file

    script:
    def diann_cmd = params.diann_binary
    def base_name = ms_file.name.replaceAll(/(?i)\.(raw|d|mzML|wiff)$/, '')

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
