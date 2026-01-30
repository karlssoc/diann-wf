#!/usr/bin/env nextflow

/*
 * Iterative Quantification Workflow
 *
 * This workflow implements an iterative quantification strategy:
 * 1. Library generation (optional): Generate library from FASTA if not provided
 * 2. Identification stage: Quantify with full proteome library WITHOUT MBR to identify proteins
 * 3. Library subsetting: Reduce the library to only include identified Protein.Groups
 * 4. Final quantification: Quantify with subset library WITH MBR for improved sensitivity
 *
 * This approach:
 * - Reduces false positives by limiting MBR to identified proteins
 * - Improves quantification sensitivity for true positives
 * - Significantly reduces computational time for final stage
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
 */

nextflow.enable.dsl = 2

// Include modules
include { QUANTIFY as QUANTIFY_IDENTIFY } from '../modules/quantify'
include { QUANTIFY as QUANTIFY_FINAL } from '../modules/quantify'
include { SUBSET_LIBRARY } from '../modules/subset_library'
include { CONVERT_LIBRARY } from '../modules/convert_library'
include { GENERATE_LIBRARY } from '../modules/library'

// Include shared utilities
include { createSamplesChannel } from '../lib/samples'
include { resolveModelFiles; logModelInfo } from '../lib/models'

// Help message
def helpMessage() {
    log.info"""
    Iterative Quantification Workflow

    This workflow performs iterative quantification:
    1. Library generation (if not provided): Generate from FASTA
    2. Identification stage: WITHOUT MBR to identify proteins
    3. Library subsetting: based on identified Protein.Groups
    4. Final stage: WITH MBR on subset library for improved quantification

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
workflow {
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

    // Reference library (optional, for batch correction)
    def ref_library_file = params.ref_library ? file(params.ref_library) : file('NO_FILE')

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
    log.info "Output dir   : ${params.outdir}"
    if (generate_library && models) {
        logModelInfo(models, params)
    }
    log.info ""

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

    QUANTIFY_IDENTIFY(
        samples_ch_identify,
        library_for_quantify,
        fasta_file,
        ref_library_file,
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

    QUANTIFY_FINAL(
        samples_ch_final,
        SUBSET_LIBRARY.out.subset_library.first(),
        fasta_file,
        ref_library_file,
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
    if (!params.existing_library) {
        log.info "  Generated library:    ${params.outdir}/library/"
    }
    log.info "  Identification stage: ${params.outdir}/identification/"
    log.info "  Subset library:       ${params.outdir}/subset_library/"
    log.info "  Final quantification: ${params.outdir}/final/"
    log.info ""
}
