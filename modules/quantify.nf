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

    // Dynamic time allocation based on file count
    // Formula: base_hours + (file_count * minutes_per_file)
    // Configurable via params.time_base_hours and params.time_per_file_minutes
    // Default: 2h + (file_count * 10 min) - generous buffer for file variability
    time {
        def base_hours = params.time_base_hours ?: 2
        def minutes_per_file = params.time_per_file_minutes ?: 10
        def total_minutes = (base_hours * 60) + (file_count.toInteger() * minutes_per_file)
        def hours = Math.ceil(total_minutes / 60.0) as Integer
        return "${hours}h"
    }

    input:
    tuple val(sample_id), path(ms_dir), val(file_type), val(subdir), val(recursive), val(file_count)
    path library
    path fasta

    output:
    tuple val(sample_id), path("report.parquet"), emit: report
    tuple val(sample_id), path("out-lib.parquet"), emit: out_lib
    tuple val(sample_id), path("*.tsv"), emit: matrices, optional: true
    path "diann.log", emit: log

    script:
    // Use absolute path to DIANN binary (container ENTRYPOINT interferes with PATH)
    def diann_cmd = "/usr/bin/diann-${params.diann_version}/diann-linux"

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
    ${diann_cmd} \\
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
