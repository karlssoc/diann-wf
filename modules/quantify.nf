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
    // Default: 2h + (file_count * 15 min)
    // Based on: 2.3M precursor library, 81 .dia files, 96 threads → 7.3 min/file mean
    //   Scaled to 60 threads: 11.6 min/file mean, 14.3 min/file max → 15 min buffer
    // Ultrafast mode: reduces time by ~50% due to simplified algorithms
    time {
        def base_hours = params.time_base_hours ?: 2
        def minutes_per_file = params.time_per_file_minutes ?: 15
        def total_minutes = (base_hours * 60) + (file_count.toInteger() * minutes_per_file)

        // Ultrafast mode is significantly faster - reduce time estimate by 50%
        if (params.ultrafast) {
            total_minutes = total_minutes * 0.5
        }

        def hours = Math.ceil(total_minutes / 60.0) as Integer
        return "${hours}h"
    }

    input:
    tuple val(sample_id), path(ms_dir), val(file_type), val(subdir), val(recursive), val(file_count)
    path library
    path fasta
    path ref_library
    val mbr      // Match-between-runs: true enables --reanalyse, false disables it
    val qvalue   // Precursor q-value threshold (0 = DIA-NN default 0.01)

    output:
    // Main report and library
    tuple val(sample_id), path("report.parquet"), emit: report
    tuple val(sample_id), path("out-lib.parquet"), emit: out_lib, optional: true
    tuple val(sample_id), path("out-lib.parquet.skyline.speclib"), emit: skyline_lib, optional: true
    // Matrices (--matrices flag)
    tuple val(sample_id), path("report.*_matrix.tsv"), emit: matrices, optional: true
    tuple val(sample_id), path("report-first-pass.*_matrix.tsv"), emit: first_pass_matrices, optional: true
    // Stats and protein descriptions
    tuple val(sample_id), path("report.stats.tsv"), emit: stats, optional: true
    tuple val(sample_id), path("report-first-pass.stats.tsv"), emit: first_pass_stats, optional: true
    tuple val(sample_id), path("report.protein_description.tsv"), emit: protein_description, optional: true
    // First-pass report (MBR mode)
    tuple val(sample_id), path("report-first-pass.parquet"), emit: first_pass_report, optional: true
    // Manifests and logs
    tuple val(sample_id), path("report-first-pass.manifest.txt"), emit: first_pass_manifest, optional: true
    tuple val(sample_id), path("report.manifest.txt"), emit: manifest, optional: true
    path "report.log.txt", emit: report_log, optional: true
    path "diann.log", emit: log

    script:
    // Use centralized DIA-NN binary path (container ENTRYPOINT interferes with PATH)
    def diann_cmd = params.diann_binary

    // Directory parameter: use --dir-all for recursive, --dir for non-recursive
    def dir_param = recursive ? "--dir-all" : "--dir"

    // File-type specific parameters
    def mass_acc_params = ""
    if (file_type == 'd') {
        mass_acc_params = "--mass-acc 15 --mass-acc-ms1 15"
    }

    // Get additional quantification parameters if specified
    // Boolean flags use truthy check (not != null) to respect false defaults in nextflow.config
    def individual_mass_acc = params.individual_mass_acc ?
        "--individual-mass-acc" : ""
    def smart_profiling = params.smart_profiling ?
        "--smart-profiling" : ""
    def mass_acc_cal = params.mass_acc_cal != null ?
        "--mass-acc-cal ${params.mass_acc_cal}" : ""
    def pg_level = params.pg_level != null ?
        "--pg-level ${params.pg_level}" : ""
    def matrices = params.matrices ?
        "--matrices" : ""

    // Batch correction parameters (for multi-batch data from same instrument)
    def individual_windows = params.individual_windows ?
        "--individual-windows" : ""
    def ref_lib = ref_library.name != 'NO_FILE' ?
        "--ref ${ref_library}" : ""

    // Q-value threshold (0 = use DIA-NN default of 0.01)
    def qvalue_param = qvalue ? "--qvalue ${qvalue}" : ""

    // Auto-reannotate when using parquet libraries (proteotypic annotations lost in speclib conversion)
    def reannotate = library.name.endsWith('.parquet') ? '--reannotate' : ''

    // Ultrafast mode parameters (trades sensitivity for speed)
    // These parameters enable aggressive filtering and simplified algorithms
    def ultrafast_params = ""
    if (params.ultrafast) {
        ultrafast_params = """--min-corr 2.0 \\
        --time-corr-only \\
        --extracted-ms1 \\
        --min-cal 500 \\
        --min-class 1000 \\
        --pre-filter \\
        --rt-window-mul 1.7 \\
        --rt-window-factor 100"""
    }

    """
    # Create temporary directory for DIA-NN temp files (prevents interference in parallel jobs)
    mkdir -p temp_diann

    ${diann_cmd} \\
        --fasta ${fasta} \\
        ${dir_param} ${ms_dir} \\
        --lib ${library} \\
        --threads ${task.cpus} \\
        --verbose 1 \\
        --temp temp_diann \\
        --out report.parquet \\
        --out-lib out-lib.parquet \\
        ${mbr ? '--reanalyse' : ''} \\
        ${qvalue_param} \\
        ${reannotate} \\
        ${pg_level} \\
        ${mass_acc_params} \\
        ${mass_acc_cal} \\
        ${smart_profiling} \\
        ${individual_mass_acc} \\
        ${individual_windows} \\
        ${ref_lib} \\
        ${matrices} \\
        ${ultrafast_params} \\
        2>&1 | tee diann.log
    """
}
