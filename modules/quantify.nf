// DIANN Quantification Module
// Quantifies MS data using a spectral library

process QUANTIFY {
    label 'diann_quantify'
    publishDir "${params.outdir}/${sample_id}", mode: 'copy', overwrite: true

    tag "$sample_id"

    input:
    tuple val(sample_id), path(ms_dir), val(file_type)
    path library
    path fasta

    output:
    tuple val(sample_id), path("report.parquet"), emit: report
    tuple val(sample_id), path("out-lib.parquet"), emit: out_lib
    tuple val(sample_id), path("*.tsv"), emit: matrices, optional: true
    path "diann.log", emit: log

    script:
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
    diann \\
        --fasta ${fasta} \\
        --dir ${ms_dir} \\
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
