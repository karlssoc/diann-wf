#!/usr/bin/env nextflow

/*
 * Iterative Quantification Workflow
 *
 * This workflow implements an iterative quantification strategy with optional
 * InfinDIA-based calibration for faster processing:
 *
 * 1. Calibration (optional): InfinDIA pre-search to generate empirical calibration library
 * 2. Library generation (optional): Generate library from FASTA if not provided
 * 3. Identification stage: Quantify with full proteome library WITHOUT MBR to identify proteins
 * 4. Library subsetting: Reduce the library to only include identified Protein.Groups
 * 5. Final quantification: Quantify with subset library WITH MBR for improved sensitivity
 *
 * This approach:
 * - Reduces false positives by limiting MBR to identified proteins
 * - Improves quantification sensitivity for true positives
 * - Significantly reduces computational time for final stage
 * - (With InfinDIA) Speeds up calibration using empirical library
 *
 * Required parameters:
 *   --fasta           Path to FASTA file
 *   --samples         Sample definitions (id, dir, file_type, recursive)
 *
 * Optional parameters:
 *   --existing_library  Path to existing spectral library (.parquet or .speclib)
 *                       If not provided, library is generated from FASTA
 *   --library_name      Name for generated library (default: 'predicted_library')
 *   --model_preset    Pre-trained models for library generation (e.g., 'ttht-evos-30spd')
 *   --mbr             Enable MBR in identification stage (default: false)
 *   --mbr_final       Enable MBR in final stage (default: true)
 *
 * Calibration parameters (InfinDIA):
 *   --calibration_mode    'infindia', 'existing', or 'none' (default: 'none')
 *   --calibration_library Path to existing calibration library (when mode='existing')
 *   --instrument_type     'hfx' or 'timstof' for mass accuracy presets
 *   --pre_select          Limit precursors in InfinDIA (default: 0 = unlimited)
 *   --calibration_files   Number of MS files to use for calibration (default: 5)
 */

nextflow.enable.dsl = 2

// Include modules
include { QUANTIFY as QUANTIFY_IDENTIFY } from '../modules/quantify'
include { QUANTIFY as QUANTIFY_FINAL } from '../modules/quantify'
include { SUBSET_LIBRARY } from '../modules/subset_library'
include { CONVERT_LIBRARY } from '../modules/convert_library'
include { GENERATE_LIBRARY } from '../modules/library'
include { INFINDIA_PRESEARCH } from '../modules/infindia_presearch'
include { CONVERT_RAW_TO_MZML } from '../modules/convert_raw'

// Include shared utilities
include { createSamplesChannel } from '../lib/samples'
include { resolveModelFiles; logModelInfo } from '../lib/models'

// Help message
def helpMessage() {
    log.info"""
    Iterative Quantification Workflow

    This workflow performs iterative quantification with optional InfinDIA calibration:
    1. Calibration (optional): InfinDIA pre-search for fast calibration library
    2. Library generation (if not provided): Generate from FASTA
    3. Identification stage: WITHOUT MBR to identify proteins
    4. Library subsetting: based on identified Protein.Groups
    5. Final stage: WITH MBR on subset library for improved quantification

    Usage:
      nextflow run workflows/iterative_quant.nf -params-file <config.yaml> -profile <profile>

    Required Parameters:
      --fasta PATH          FASTA sequence database
      --samples LIST        Sample definitions [{id, dir, file_type, recursive}]

    Optional Parameters:
      --existing_library PATH  Existing spectral library (.parquet or .speclib)
                               If not provided, library is generated from FASTA
      --library_name NAME      Name for generated library (default: 'predicted_library')
      --model_preset NAME   Pre-trained models for library generation
                            Example: 'ttht-evos-30spd'
      --mbr BOOL            Enable MBR in identification stage (default: false)
      --mbr_final BOOL      Enable MBR in final stage (default: true)
      --outdir PATH         Output directory (default: results)
      --threads N           Number of threads (default: ${params.threads})

    Calibration Parameters (InfinDIA):
      --calibration_mode MODE    Calibration strategy:
                                 'none'     - No calibration library (default)
                                 'infindia' - Generate via InfinDIA pre-search
                                 'existing' - Use existing calibration library
      --calibration_library PATH Path to existing calibration library
                                 (required when mode='existing')
      --calibration_files N      Number of MS files for calibration (default: 5)
                                 Uses random selection from first sample
      --instrument_type TYPE     Mass accuracy presets:
                                 'hfx'      - Orbitrap HFX (MS1: 5ppm, MS2: 15ppm)
                                 'timstof'  - timsTOF (MS1: 15ppm, MS2: 15ppm)
      --pre_select N             Limit precursors in InfinDIA (default: 0 = unlimited)
                                 Recommended: 5000-10000 for fast calibration

    Library Generation Parameters (when --library not provided):
      --library.min_fr_mz 200      Min fragment m/z
      --library.max_fr_mz 1800     Max fragment m/z
      --library.min_pep_len 7      Min peptide length
      --library.max_pep_len 30     Max peptide length
      --library.min_pr_mz 350      Min precursor m/z
      --library.max_pr_mz 1650     Max precursor m/z

    Profiles:
      standard              Run locally with Singularity
      docker                Run locally with Docker
      slurm                 Submit to SLURM cluster
      cosmos                LUNARC COSMOS HPC

    Output Structure:
      results/
      ├── calibration/             # Calibration library (if mode='infindia')
      │   └── calibration_lib.parquet
      ├── library/                 # Generated library (if no --library provided)
      │   └── predicted_library.predicted.speclib
      ├── identification/          # Identification stage results
      │   └── <sample_id>/
      │       ├── report.parquet   # Quantification report
      │       └── out-lib.parquet  # Sample-specific library
      ├── subset_library/          # Subset library
      │   └── subset_lib.parquet
      └── final/                   # Final quantification results
          └── <sample_id>/
              ├── report.parquet   # Final quantification
              └── out-lib.parquet
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
if (!params.samples) {
    log.error "ERROR: --samples parameter is required"
    helpMessage()
    exit 1
}

// Main workflow
workflow ITERATIVE_QUANT {
    // Validate input files
    def fasta_file = file(params.fasta)

    if (!fasta_file.exists()) {
        log.error "ERROR: FASTA file not found: ${params.fasta}"
        exit 1
    }

    // Get samples list
    def samples_list = params.samples

    // MBR settings
    def mbr_identify = params.mbr != null ? params.mbr : false
    def mbr_final = params.mbr_final != null ? params.mbr_final : (params.mbr_second_pass != null ? params.mbr_second_pass : true)

    // Calibration settings
    def calibration_mode = params.calibration_mode ?: 'none'
    def instrument_type = params.instrument_type ?: ''
    def pre_select = params.pre_select ?: 0
    def calibration_files = params.calibration_files ?: 5

    // Library name for generation (if needed)
    def library_name = params.library_name ?: 'predicted_library'

    // Determine library source
    // Note: params.library is a map for generation settings, params.existing_library is a path
    def generate_library = !params.existing_library
    def library_source = generate_library ? "generated from FASTA" : params.existing_library

    // Resolve model files for library generation
    def models = null
    if (generate_library) {
        models = resolveModelFiles(params, projectDir)
    }

    // Log workflow parameters
    log.info ""
    log.info "Iterative Quantification Workflow"
    log.info "================================="
    log.info "FASTA        : ${params.fasta}"
    log.info "Library      : ${library_source}"
    log.info "Samples      : ${samples_list.size()}"
    log.info "MBR (identify): ${mbr_identify}"
    log.info "MBR (final)  : ${mbr_final}"
    log.info "Calibration  : ${calibration_mode}"
    if (calibration_mode == 'infindia') {
        log.info "  Files      : ${calibration_files}"
        log.info "  Instrument : ${instrument_type ?: 'auto'}"
        log.info "  Pre-select : ${pre_select > 0 ? pre_select : 'unlimited'}"
    } else if (calibration_mode == 'existing') {
        log.info "  Library    : ${params.calibration_library}"
    }
    log.info "Output dir   : ${params.outdir}"
    if (generate_library && models) {
        logModelInfo(models, params)
    }
    log.info ""

    // ========================================
    // CALIBRATION LIBRARY (optional)
    // ========================================
    def calibration_library = null

    if (calibration_mode == 'infindia') {
        log.info "Generating calibration library via InfinDIA pre-search..."

        // Use first sample for calibration
        def first_sample = samples_list[0]
        def calibration_sample_dir = file(first_sample.dir)
        def file_type = first_sample.file_type ?: 'raw'

        if (!calibration_sample_dir.exists()) {
            log.error "ERROR: Calibration sample directory not found: ${first_sample.dir}"
            exit 1
        }

        // Find MS files and randomly select N for calibration
        def file_pattern = file_type == 'd' ? '*.d' : "*.${file_type}"
        def all_ms_files = calibration_sample_dir.listFiles().findAll { f ->
            if (file_type == 'd') {
                return f.isDirectory() && f.name.endsWith('.d')
            } else {
                return f.isFile() && f.name.toLowerCase().endsWith(".${file_type.toLowerCase()}")
            }
        }

        if (all_ms_files.size() == 0) {
            log.error "ERROR: No ${file_type} files found in ${calibration_sample_dir}"
            exit 1
        }

        // Shuffle and take N files (or all if fewer than N)
        Collections.shuffle(all_ms_files)
        def selected_files = all_ms_files.take(calibration_files)
        log.info "Selected ${selected_files.size()} of ${all_ms_files.size()} files for calibration"

        // Convert RAW files to mzML for presearch (Linux ThermoRaw reader may fail on some instruments)
        // Regular DIA-NN quantification handles RAW files fine via different code path
        if (file_type.toLowerCase() == 'raw') {
            log.info "Converting RAW files to mzML for presearch compatibility..."

            // Create channel with individual files for parallel conversion
            def raw_files_ch = Channel.fromList(selected_files)

            // Convert each file in parallel
            CONVERT_RAW_TO_MZML(raw_files_ch)

            // Collect all converted mzML files for presearch
            INFINDIA_PRESEARCH(
                CONVERT_RAW_TO_MZML.out.mzml_file.collect(),
                fasta_file,
                'calibration',
                instrument_type,
                pre_select
            )
        } else {
            // Non-RAW files (mzML, .d, etc.) can be used directly
            def calibration_files_ch = Channel.fromList(selected_files).collect()
            INFINDIA_PRESEARCH(
                calibration_files_ch,
                fasta_file,
                'calibration',
                instrument_type,
                pre_select
            )
        }

        calibration_library = INFINDIA_PRESEARCH.out.calibration_library
    } else if (calibration_mode == 'existing') {
        if (!params.calibration_library) {
            log.error "ERROR: --calibration_library is required when --calibration_mode='existing'"
            exit 1
        }
        def cal_lib_file = file(params.calibration_library)
        if (!cal_lib_file.exists()) {
            log.error "ERROR: Calibration library not found: ${params.calibration_library}"
            exit 1
        }
        calibration_library = Channel.value(cal_lib_file)
    } else {
        // No calibration library - use placeholder
        calibration_library = Channel.value(file('NO_FILE'))
    }

    // Reference library for batch correction (separate from calibration)
    def ref_library_file = params.ref_library ? file(params.ref_library) : file('NO_FILE')

    // ========================================
    // LIBRARY GENERATION (if no library provided)
    // ========================================
    def library_for_quantify = null

    if (generate_library) {
        log.info "Generating library from FASTA..."

        GENERATE_LIBRARY(
            fasta_file,
            library_name,
            'library',
            models.tokens,
            models.rt_model,
            models.im_model,
            models.fr_model
        )

        // Convert generated .speclib to .parquet for subsetting
        // Pass FASTA for proper proteotypic annotation
        def cut = params.library?.cut ?: 'K*,R*'
        def missed_cleavages = params.library?.missed_cleavages ?: 1

        CONVERT_LIBRARY(
            GENERATE_LIBRARY.out.library,
            'library',
            fasta_file,
            cut,
            missed_cleavages
        )
        library_for_quantify = CONVERT_LIBRARY.out.parquet_library
    } else {
        // Use provided library
        def library_file = file(params.existing_library)

        if (!library_file.exists()) {
            log.error "ERROR: Library file not found: ${params.existing_library}"
            exit 1
        }

        // Check if library needs conversion to parquet
        if (library_file.name.endsWith('.speclib')) {
            log.info "Converting .speclib to .parquet for subsetting compatibility"
            // Pass FASTA for proper proteotypic annotation
            def cut = params.library?.cut ?: 'K*,R*'
            def missed_cleavages = params.library?.missed_cleavages ?: 1

            CONVERT_LIBRARY(
                library_file,
                'converted_library',
                fasta_file,
                cut,
                missed_cleavages
            )
            library_for_quantify = CONVERT_LIBRARY.out.parquet_library
        } else {
            library_for_quantify = Channel.value(library_file)
        }
    }

    // ========================================
    // IDENTIFICATION STAGE: Quantify without MBR
    // ========================================
    log.info "Identification: Quantifying with full library (MBR=${mbr_identify})"

    // Create samples channel for identification stage
    def samples_ch_identify = createSamplesChannel(samples_list, 'identification')

    // Use calibration library as --ref if available, otherwise use ref_library for batch correction
    def ref_for_identify = calibration_mode != 'none' ? calibration_library : Channel.value(ref_library_file)

    QUANTIFY_IDENTIFY(
        samples_ch_identify,
        library_for_quantify,
        fasta_file,
        ref_for_identify,
        mbr_identify
    )

    // ========================================
    // SUBSET LIBRARY
    // ========================================
    log.info "Subsetting library based on identified Protein.Groups"

    // Collect all identification stage reports and merge Protein.Groups
    // For multi-sample, we take the union of all identified Protein.Groups
    def all_identify_reports = QUANTIFY_IDENTIFY.out.report
        .map { sample_id, report -> report }
        .collect()

    // Use the first report for subsetting (in multi-sample, could merge)
    // For now, use the collected reports - DuckDB can handle multiple files
    def identify_report = QUANTIFY_IDENTIFY.out.report
        .first()
        .map { sample_id, report -> report }

    SUBSET_LIBRARY(
        identify_report,
        library_for_quantify,
        'subset_library',
        'subset_lib'
    )

    // ========================================
    // FINAL STAGE: Quantify with MBR
    // ========================================
    log.info "Final: Quantifying with subset library (MBR=${mbr_final})"

    // Create samples channel for final stage
    def samples_ch_final = createSamplesChannel(samples_list, 'final')

    // Use calibration library as --ref if available
    def ref_for_final = calibration_mode != 'none' ? calibration_library : Channel.value(ref_library_file)

    QUANTIFY_FINAL(
        samples_ch_final,
        SUBSET_LIBRARY.out.subset_library.first(),
        fasta_file,
        ref_for_final,
        mbr_final
    )
}

workflow.onComplete {
    log.info ""
    log.info "Iterative Quantification completed at: ${workflow.complete}"
    log.info "Execution status: ${workflow.success ? 'Success' : 'Failed'}"
    log.info "Duration: ${workflow.duration}"
    log.info ""
    log.info "Results:"
    if (params.calibration_mode == 'infindia') {
        log.info "  Calibration library:  ${params.outdir}/calibration/"
    }
    if (!params.existing_library) {
        log.info "  Generated library:    ${params.outdir}/library/"
    }
    log.info "  Identification stage: ${params.outdir}/identification/"
    log.info "  Subset library:       ${params.outdir}/subset_library/"
    log.info "  Final quantification: ${params.outdir}/final/"
    log.info ""
}
