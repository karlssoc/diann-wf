// DIANN Ultrafast Presearch Module
// Runs DIA-NN in ultrafast mode on a sample for calibration ref library generation.
//
// Used by QUANTIFY_FASTA_SUBSET* workflows when ref_n_proteins is set.
// Outputs report.parquet, which is passed to SUBSET_FASTA (top_n) to identify
// the most commonly detected proteins for building a small calibration speclib.
//
// Design notes:
// - Ultrafast flags are hardcoded (not from params.ultrafast); this process is
//   always ultrafast regardless of the global ultrafast setting.
// - publishDir is hardcoded to outdir/ref_presearch/<sample_id>/. The subdir
//   field in the input tuple is carried for channel compatibility but not used.
// - No MBR, no matrices, no ref_library — this is a fast protein discovery step.
// - Time allocation is 50% of normal (ultrafast mode ~2x faster).
// - Mass accuracy logic is identical to QUANTIFY for consistent calibration.

process PRESEARCH_ULTRAFAST {
    label 'diann_quantify'

    publishDir "${params.outdir}/ref_presearch/${sample_id}",
        mode: 'copy',
        overwrite: true

    tag "ref_presearch/${sample_id}"

    // Ultrafast mode is ~50% of normal time
    time {
        def base_hours = params.time_base_hours ?: 2
        def minutes_per_file = params.time_per_file_minutes ?: 15
        def total_minutes = ((base_hours * 60) + (file_count.toInteger() * minutes_per_file)) * 0.5
        def hours = Math.ceil(total_minutes / 60.0) as Integer
        return "${hours}h"
    }

    input:
    tuple val(sample_id), path(ms_dir), val(file_type), val(subdir), val(recursive), val(file_count)
    path library
    path fasta

    output:
    tuple val(sample_id), path("report.parquet"), emit: report
    path "diann.log", emit: log

    script:
    // DIA-NN binary path (auto-computed from version if not explicitly set)
    def diann_cmd = params.diann_binary ?: "/usr/bin/diann-${params.diann_version}/diann-linux"

    // Directory parameter: use --dir-all for recursive, --dir for non-recursive
    def dir_param = recursive ? "--dir-all" : "--dir"

    // Mass accuracy parameters — identical logic to QUANTIFY for consistent calibration
    def mass_acc_params = ""
    if (params.mass_acc != null && params.mass_acc_ms1 != null) {
        mass_acc_params = "--mass-acc ${params.mass_acc} --mass-acc-ms1 ${params.mass_acc_ms1}"
    } else if (params.mass_acc != null) {
        mass_acc_params = "--mass-acc ${params.mass_acc}"
    } else if (params.mass_acc_ms1 != null) {
        mass_acc_params = "--mass-acc-ms1 ${params.mass_acc_ms1}"
    } else if (file_type == 'd') {
        mass_acc_params = "--mass-acc 15 --mass-acc-ms1 15"
    } else if (file_type == 'raw') {
        mass_acc_params = "--mass-acc 15 --mass-acc-ms1 5"
    }

    // Auto-reannotate when using parquet libraries (proteotypic annotations lost in speclib conversion)
    def reannotate = library.name.endsWith('.parquet') ? '--reannotate' : ''

    """
    mkdir -p temp_diann

    ${diann_cmd} \\
        --fasta ${fasta} \\
        ${dir_param} ${ms_dir} \\
        --lib ${library} \\
        --threads ${task.cpus} \\
        --verbose 1 \\
        --temp temp_diann \\
        --out report.parquet \\
        ${reannotate} \\
        ${mass_acc_params} \\
        --min-corr 2.0 \\
        --time-corr-only \\
        --extracted-ms1 \\
        --min-cal 500 \\
        --min-class 1000 \\
        --pre-filter \\
        --rt-window-mul 1.7 \\
        --rt-window-factor 100 \\
        2>&1 | tee diann.log
    """
}
