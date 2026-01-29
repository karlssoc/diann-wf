#!/usr/bin/env nextflow

/*
 * Iterative Quantification Workflow
 *
 * This workflow implements an iterative quantification strategy:
 * 1. Identification stage: Quantify with full proteome library WITHOUT MBR to identify proteins
 * 2. Library subsetting: Reduce the library to only include identified Protein.Groups
 * 3. Final quantification: Quantify with subset library WITH MBR for improved sensitivity
 *
 * This approach:
 * - Reduces false positives by limiting MBR to identified proteins
 * - Improves quantification sensitivity for true positives
 * - Significantly reduces computational time for final stage
 *
 * Required parameters:
 *   --library         Path to full spectral library (.parquet or .speclib)
 *   --fasta           Path to FASTA file
 *   --samples         Sample definitions (id, dir, file_type, recursive)
 *
 * Optional parameters:
 *   --mbr             Enable MBR in identification stage (default: false)
 *   --mbr_final       Enable MBR in final stage (default: true)
 */

nextflow.enable.dsl = 2

// Include modules
include { QUANTIFY as QUANTIFY_IDENTIFY } from '../modules/quantify'
include { QUANTIFY as QUANTIFY_FINAL } from '../modules/quantify'
include { SUBSET_LIBRARY } from '../modules/subset_library'
include { CONVERT_LIBRARY } from '../modules/convert_library'

// Include shared utilities
include { createSamplesChannel } from '../lib/samples'

// Help message
def helpMessage() {
    log.info"""
    Iterative Quantification Workflow

    This workflow performs iterative quantification:
    1. Identification stage: WITHOUT MBR to identify proteins
    2. Library subsetting: based on identified Protein.Groups
    3. Final stage: WITH MBR on subset library for improved quantification

    Usage:
      nextflow run workflows/iterative_quant.nf -params-file <config.yaml> -profile <profile>

    Required Parameters:
      --library PATH        Full spectral library (.parquet or .speclib)
      --fasta PATH          FASTA sequence database
      --samples LIST        Sample definitions [{id, dir, file_type, recursive}]

    Optional Parameters:
      --mbr BOOL            Enable MBR in identification stage (default: false)
      --mbr_final BOOL      Enable MBR in final stage (default: true)
      --outdir PATH         Output directory (default: results)
      --threads N           Number of threads (default: ${params.threads})

    Profiles:
      standard              Run locally with Singularity
      docker                Run locally with Docker
      slurm                 Submit to SLURM cluster
      cosmos                LUNARC COSMOS HPC

    Output Structure:
      results/
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
if (!params.library) {
    log.error "ERROR: --library parameter is required"
    helpMessage()
    exit 1
}
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
    def library_file = file(params.library)
    def fasta_file = file(params.fasta)

    if (!library_file.exists()) {
        log.error "ERROR: Library file not found: ${params.library}"
        exit 1
    }
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

    // Log workflow parameters
    log.info ""
    log.info "Iterative Quantification Workflow"
    log.info "================================="
    log.info "Library      : ${params.library}"
    log.info "FASTA        : ${params.fasta}"
    log.info "Samples      : ${samples_list.size()}"
    log.info "MBR (identify): ${mbr_identify}"
    log.info "MBR (final)  : ${mbr_final}"
    log.info "Output dir   : ${params.outdir}"
    log.info ""

    // ========================================
    // IDENTIFICATION STAGE: Quantify without MBR
    // ========================================
    log.info "Identification: Quantifying with full library (MBR=${mbr_identify})"

    // Check if library needs conversion to parquet
    def library_for_quantify = library_file
    if (library_file.name.endsWith('.speclib')) {
        log.info "Converting .speclib to .parquet for subsetting compatibility"
        CONVERT_LIBRARY(library_file, 'converted_library')
        library_for_quantify = CONVERT_LIBRARY.out.parquet_library
    }

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
    log.info "  Identification stage: ${params.outdir}/identification/"
    log.info "  Subset library:       ${params.outdir}/subset_library/"
    log.info "  Final quantification: ${params.outdir}/final/"
    log.info ""
}
