// DIA-NN InfinDIA Pre-search Module
// Performs library-free search to identify peptides for calibration
//
// This module performs a library-free DIA analysis on a subset of MS files
// to identify peptides. The report output is used to subset the predicted
// spectral library, creating a calibration library with matching RT/IM
// predictions. This approach avoids RT/IM mismatch warnings that occur
// when using the empirical library directly.
//
// Uses --direct-quant to disable QuantUMS for faster execution during
// presearch (calibration library doesn't require QuantUMS precision).
//
// Outputs:
//   - calibration_report.parquet: Used to subset predicted library
//   - calibration_lib.parquet: Empirical library (for reference only)

process INFINDIA_PRESEARCH {
    label 'diann_library'

    publishDir "${params.outdir}${subdir ? '/' + subdir : ''}",
        mode: 'copy',
        overwrite: true

    tag "${subdir ? subdir + '/' : ''}calibration (${ms_files instanceof List ? ms_files.size() : 1} files)"

    input:
    path ms_files                    // MS data files (can be list of files)
    path fasta                       // FASTA database
    val subdir                       // Output subdirectory
    val instrument_type              // 'hfx' or 'timstof' for mass accuracy presets
    val pre_select                   // Max precursors to select (0 = unlimited)

    output:
    path "calibration_lib.parquet", emit: calibration_library
    path "calibration_lib.parquet.skyline.speclib", emit: skyline_lib, optional: true
    path "calibration_presearch.log", emit: log
    path "calibration_report.parquet", emit: report  // Required for library subsetting
    path "calibration_report.stats.tsv", emit: stats, optional: true
    path "calibration_report.log.txt", emit: report_log, optional: true

    script:
    def diann_cmd = params.diann_binary

    // Mass accuracy presets based on instrument type
    // HFX (Orbitrap): MS1 5 ppm, MS2 15 ppm
    // timsTOF: 15 ppm for both
    // --mass-acc-cal 20 fixes calibration mass accuracy (default 100 ppm auto-adjusted)
    // Using 20 ppm as safe starting point for calibration phase
    def mass_acc_params = ""
    if (instrument_type == 'hfx' || instrument_type == 'orbitrap') {
        mass_acc_params = "--mass-acc 15 --mass-acc-ms1 5 --mass-acc-cal 20"
    } else if (instrument_type == 'timstof' || instrument_type == 'd') {
        mass_acc_params = "--mass-acc 15 --mass-acc-ms1 15 --mass-acc-cal 20"
    }
    // If no instrument type specified, let DIA-NN auto-calibrate

    // Pre-select parameter (limit precursors for faster runs)
    def pre_select_param = ""
    if (pre_select && pre_select > 0) {
        pre_select_param = "--pre-select ${pre_select} --pre-select-force"
    }

    // Library generation parameters from config (use defaults if not specified)
    def min_pep_len = params.library?.min_pep_len ?: 7
    def max_pep_len = params.library?.max_pep_len ?: 30
    def min_pr_mz = params.library?.min_pr_mz ?: 300
    def max_pr_mz = params.library?.max_pr_mz ?: 1800
    def min_pr_charge = params.library?.min_pr_charge ?: 2
    def max_pr_charge = params.library?.max_pr_charge ?: 3
    def min_fr_mz = params.library?.min_fr_mz ?: 200
    def max_fr_mz = params.library?.max_fr_mz ?: 1800
    def cut = params.library?.cut ?: 'K*,R*,!*P'
    def missed_cleavages = params.library?.missed_cleavages ?: 1

    // Build --f parameters for each input file
    // ms_files can be a single file or a list of files
    def files_list = ms_files instanceof List ? ms_files : [ms_files]
    def input_params = files_list.collect { f -> "--f ${f}" }.join(' ')

    """
    mkdir -p temp_diann

    echo "=== InfinDIA Pre-search ==="
    echo "Input files: ${files_list.size()}"
    echo "Instrument: ${instrument_type ?: 'auto'}"
    echo "Pre-select: ${pre_select > 0 ? pre_select : 'unlimited'}"
    echo ""

    ${diann_cmd} \\
        ${input_params} \\
        --fasta ${fasta} \\
        --lib \\
        --threads ${task.cpus} \\
        --verbose 1 \\
        --temp temp_diann \\
        --out calibration_report.parquet \\
        --out-lib calibration_lib.parquet \\
        --gen-spec-lib \\
        --pre-search \\
        --pre-filter \\
        --reanalyse \\
        --rt-profiling \\
        ${pre_select_param} \\
        ${mass_acc_params} \\
        --met-excision \\
        --min-pep-len ${min_pep_len} \\
        --max-pep-len ${max_pep_len} \\
        --min-pr-mz ${min_pr_mz} \\
        --max-pr-mz ${max_pr_mz} \\
        --min-pr-charge ${min_pr_charge} \\
        --max-pr-charge ${max_pr_charge} \\
        --min-fr-mz ${min_fr_mz} \\
        --max-fr-mz ${max_fr_mz} \\
        --cut ${cut} \\
        --missed-cleavages ${missed_cleavages} \\
        --unimod4 \\
        --pg-level 1 \\
        --direct-quant \\
        2>&1 | tee calibration_presearch.log

    echo ""
    echo "=== InfinDIA Pre-search Complete ==="
    echo "Calibration library: calibration_lib.parquet"
    if [ -f calibration_report.stats.tsv ]; then
        echo "Precursors identified:"
        cat calibration_report.stats.tsv
    fi
    """
}
