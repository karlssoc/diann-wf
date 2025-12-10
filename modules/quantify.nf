// DIANN Quantification Module
// Quantifies MS data using a spectral library

process QUANTIFY {
    label 'diann_quantify'

    // Dynamic publishDir: supports optional subdirectory organization
    // If subdir is provided: outdir/subdir/sample_id/
    // If subdir is empty:    outdir/sample_id/
    publishDir "${params.outdir}${subdir ? '/' + subdir : ''}/${sample_id}",
        mode: 'copy',
        overwrite: true

    tag "${subdir ? subdir + '/' : ''}${sample_id}"

    input:
    tuple val(sample_id), path(ms_dir), val(file_type), val(subdir), val(recursive)
    path library
    path fasta

    output:
    tuple val(sample_id), path("report.parquet"), emit: report
    tuple val(sample_id), path("out-lib.parquet"), emit: out_lib
    tuple val(sample_id), path("*.tsv"), emit: matrices, optional: true
    path "diann.log", emit: log

    script:
    // Construct version-specific DIANN binary path
    def diann_binary = "/usr/bin/diann-${params.diann_version}/diann-linux"

    // Directory parameter: use --dir-all for recursive, --dir for non-recursive
    def dir_param = recursive ? "--dir-all" : "--dir"

    // File-type specific parameters
    def mass_acc_params = ""
    if (file_type == 'd') {
        mass_acc_params = "--mass-acc 15 --mass-acc-ms1 15"
    }

    // Get additional quantification parameters if specified
    def individual_mass_acc = params.individual_mass_acc != null ?
        "--individual-mass-acc" : ""
    def smart_profiling = params.smart_profiling != null ?
        "--smart-profiling" : ""
    def mass_acc_cal = params.mass_acc_cal != null ?
        "--mass-acc-cal ${params.mass_acc_cal}" : ""
    def pg_level = params.pg_level != null ?
        "--pg-level ${params.pg_level}" : ""
    def matrices = params.matrices != null ?
        "--matrices" : ""

    """
    ${diann_binary} \\
        --fasta ${fasta} \\
        ${dir_param} ${ms_dir} \\
        --lib ${library} \\
        --threads ${params.threads} \\
        --verbose 1 \\
        --out report.parquet \\
        --out-lib out-lib.parquet \\
        --reanalyse \\
        ${pg_level} \\
        ${mass_acc_params} \\
        ${mass_acc_cal} \\
        ${smart_profiling} \\
        ${individual_mass_acc} \\
        ${matrices} \\
        2>&1 | tee diann.log
    """
}
