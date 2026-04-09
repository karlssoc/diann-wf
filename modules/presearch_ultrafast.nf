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
// - File limiting: params.ref_presearch_files (default 5) controls how many
//   individual files from the batch directory are searched. Files are found by
//   scanning for common DIA-NN formats (.raw, .dia, .mzML, .wiff, .d/) and
//   passed via --f flags. This avoids searching entire large batch directories.
//   Set to 0 to use --dir and process all files (original behaviour).
// - publishDir is hardcoded to outdir/ref_presearch/<sample_id>/. The subdir
//   field in the input tuple is carried for channel compatibility but not used.
// - No MBR, no matrices, no ref_library — this is a fast protein discovery step.
// - Time allocation uses ref_presearch_files instead of file_count when limiting.
// - Mass accuracy logic is identical to QUANTIFY for consistent calibration.

process PRESEARCH_ULTRAFAST {
    label 'diann_quantify'

    publishDir "${params.outdir}/ref_presearch/${sample_id}",
        mode: 'copy',
        overwrite: true

    tag "ref_presearch/${sample_id}"

    // Time based on number of files actually searched (limited by ref_presearch_files)
    time {
        def max_files = params.ref_presearch_files != null ? params.ref_presearch_files : 5
        def effective_files = (max_files > 0) ? Math.min(max_files, file_count.toInteger()) : file_count.toInteger()
        def base_hours = params.time_base_hours ?: 2
        def minutes_per_file = params.time_per_file_minutes ?: 15
        def total_minutes = ((base_hours * 60) + (effective_files * minutes_per_file)) * 0.5
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

    // File limiting: use --f flags for N individual files, or --dir for all
    def max_files = params.ref_presearch_files != null ? params.ref_presearch_files : 5

    // Directory parameter (fallback when max_files = 0)
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

    # Build file list for presearch
    # Enumerate all common DIA-NN-compatible formats (file_type is a mass-accuracy hint,
    # not necessarily the actual extension — scan for all formats to be robust).
    # Bruker .d are directories; all others are files.
    MAX_FILES=${max_files}

    if [ "\${MAX_FILES}" -gt 0 ]; then
        FILE_LISTING=\$(
            {
                find -L ${ms_dir} -maxdepth 1 -type f \\
                    \\( -iname "*.raw" -o -iname "*.dia" -o -iname "*.mzML" -o -iname "*.mzml" -o -iname "*.wiff" \\)
                find -L ${ms_dir} -maxdepth 1 -type d -name "*.d"
            } | sort | head -\${MAX_FILES}
        )

        if [ -z "\${FILE_LISTING}" ]; then
            echo "WARNING: No compatible files found in ${ms_dir}; falling back to --dir"
            DIR_OR_F="${dir_param} ${ms_dir}"
        else
            FILE_COUNT=\$(echo "\${FILE_LISTING}" | wc -l)
            echo "Presearch: using \${FILE_COUNT} files from ${ms_dir}"
            echo "\${FILE_LISTING}"
            # Build --f flags for each file/directory
            F_ARGS=""
            while IFS= read -r F; do
                F_ARGS="\${F_ARGS} --f \${F}"
            done <<< "\${FILE_LISTING}"
            DIR_OR_F="\${F_ARGS}"
        fi
    else
        echo "Presearch: using all files in ${ms_dir} (ref_presearch_files=0)"
        DIR_OR_F="${dir_param} ${ms_dir}"
    fi

    ${diann_cmd} \\
        --fasta ${fasta} \\
        \${DIR_OR_F} \\
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
