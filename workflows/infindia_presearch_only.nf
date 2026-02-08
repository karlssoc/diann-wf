#!/usr/bin/env nextflow

/*
 * InfinDIA Pre-search Workflow
 *
 * Performs a library-free DIA analysis to identify peptides for calibration.
 * The output report can be used to subset a predicted spectral library.
 *
 * Supports optional .dia conversion for .d (Bruker) and .raw (Thermo) files
 * that DIA-NN presearch cannot read directly.
 *
 * Required parameters:
 *   --fasta           Path to FASTA file
 *   --ms_files        List of MS data file paths (.dia, .mzML, .d, .raw)
 *
 * Optional parameters:
 *   --convert_to_dia   Convert input files to .dia before presearch (default: false)
 *   --instrument_type  'hfx' (Orbitrap) or 'timstof' (default: auto-calibrate)
 *   --pre_select       Max precursors to select, 0 = unlimited (default: 5000)
 *   --mbr              Match-between-runs (default: true)
 *
 * Example usage:
 *   nextflow run workflows/infindia_presearch_only.nf \
 *     -params-file configs/presearch/standard.yaml \
 *     -profile standard
 */

nextflow.enable.dsl = 2

// Include modules
include { INFINDIA_PRESEARCH } from '../modules/infindia_presearch'
include { CONVERT_TO_DIA } from '../modules/convert_to_dia'

// Help message
def helpMessage() {
    log.info"""
    InfinDIA Pre-search Workflow

    Usage:
      nextflow run workflows/infindia_presearch_only.nf -params-file <config.yaml> -profile <profile>

    Required Parameters:
      --fasta PATH            FASTA database file
      --ms_files LIST         List of MS data file paths (.dia, .mzML, .d, .raw)

    Optional Parameters:
      --convert_to_dia BOOL   Convert .d/.raw files to .dia first (default: false)
      --instrument_type STR   'hfx' (Orbitrap) or 'timstof' (default: auto)
      --pre_select INT        Max precursors to select, 0 = unlimited (default: 5000)
      --mbr BOOL              Match-between-runs (default: true)

    Library Generation Parameters (with defaults):
      --library.min_pep_len 7
      --library.max_pep_len 30
      --library.min_pr_mz 350
      --library.max_pr_mz 1650
      --library.min_pr_charge 2
      --library.max_pr_charge 3
      --library.min_fr_mz 200
      --library.max_fr_mz 1800
      --library.cut 'K*,R*,!*P'
      --library.missed_cleavages 1

    Examples:
      # Run with .dia files (no conversion needed)
      nextflow run workflows/infindia_presearch_only.nf \\
        -params-file configs/presearch/standard.yaml \\
        -profile standard

      # Run with .d files (requires conversion)
      nextflow run workflows/infindia_presearch_only.nf \\
        -params-file configs/presearch/standard.yaml \\
        --convert_to_dia true \\
        -profile slurm
    """.stripIndent()
}

// Show help message if requested
if (params.help) {
    helpMessage()
    exit 0
}

// Validate required parameters
if (!params.fasta) {
    log.error "ERROR: --fasta parameter is required"
    helpMessage()
    exit 1
}

if (!params.ms_files) {
    log.error "ERROR: --ms_files parameter is required (list of MS data file paths)"
    helpMessage()
    exit 1
}

// Main workflow
workflow {
    // Validate FASTA file
    def fasta_file = file(params.fasta)
    if (!fasta_file.exists()) {
        log.error "ERROR: FASTA file not found: ${params.fasta}"
        exit 1
    }

    // Collect and validate MS files
    def ms_file_list = params.ms_files instanceof List ? params.ms_files : [params.ms_files]
    def ms_files = []
    ms_file_list.each { f ->
        def ms_file = file(f)
        if (!ms_file.exists()) {
            log.error "ERROR: MS file not found: ${f}"
            exit 1
        }
        ms_files << ms_file
    }

    // Resolve parameters with defaults
    def instrument_type = params.instrument_type ?: ''
    def pre_select = params.pre_select ?: 5000
    def convert_to_dia = params.convert_to_dia ?: false

    // Log workflow info
    log.info """
    ============================================
    InfinDIA Pre-search Workflow
    ============================================
    FASTA          : ${params.fasta}
    MS files       : ${ms_files.size()} file(s)
    Convert to .dia: ${convert_to_dia}
    Instrument     : ${instrument_type ?: 'auto'}
    Pre-select     : ${pre_select > 0 ? pre_select : 'unlimited'}
    MBR            : ${params.mbr ?: true}
    DIANN version  : ${params.diann_version}
    Threads        : ${params.threads}
    Output dir     : ${params.outdir}
    Profile        : ${workflow.profile}
    ============================================
    """.stripIndent()

    // Prepare MS files channel
    if (convert_to_dia) {
        // Convert .d/.raw files to .dia format first
        // Use 'presearch' as sample_id for all files
        def raw_files_ch = Channel.fromList(ms_files)
            .map { f -> tuple('presearch', f) }

        CONVERT_TO_DIA(raw_files_ch)

        // Collect all converted .dia files
        ms_files_ch = CONVERT_TO_DIA.out.dia_file
            .map { sample_id, dia -> dia }
            .collect()
    } else {
        // Use files directly
        ms_files_ch = Channel.fromList(ms_files).collect()
    }

    // Run pre-search
    INFINDIA_PRESEARCH(
        ms_files_ch,
        fasta_file,
        'presearch',
        instrument_type,
        pre_select
    )
}

workflow.onComplete {
    log.info """
    ============================================
    Workflow completed: ${workflow.success ? 'SUCCESS' : 'FAILED'}
    Duration          : ${workflow.duration}
    Output            : ${params.outdir}/presearch/
    ============================================
    """.stripIndent()
}

workflow.onError {
    log.info """
    ============================================
    Workflow execution stopped with error
    Error message: ${workflow.errorMessage}
    ============================================
    """.stripIndent()
}
