#!/usr/bin/env nextflow

/*
 * DIANN Library Conversion Workflow
 *
 * Converts a spectral library from .speclib format to .parquet format.
 * This is useful for downstream tools that prefer parquet, or for
 * more efficient storage and access patterns.
 *
 * Required parameters:
 *   --library         Path to spectral library (.speclib or .predicted.speclib)
 *
 * Example usage:
 *   nextflow run workflows/convert_library.nf -params-file configs/library/convert.yaml -profile docker
 */

nextflow.enable.dsl = 2

// Include modules
include { CONVERT_LIBRARY } from '../modules/convert_library'

// Help message
def helpMessage() {
    log.info"""
    DIANN Library Conversion Workflow

    Usage:
      nextflow run workflows/convert_library.nf -params-file <config.yaml> -profile <profile>

    Required Parameters:
      --library PATH        Spectral library file (.speclib or .predicted.speclib)

    Optional Parameters:
      --diann_version VER   DIANN version (default: ${params.diann_version})
      --threads N           Number of threads (default: ${params.threads})
      --outdir PATH         Output directory (default: ${params.outdir})
      --subdir PATH         Output subdirectory (default: '')

    Profiles:
      standard              Run locally with Singularity
      docker                Run locally with Docker
      slurm                 Submit to SLURM cluster

    Examples:
      nextflow run workflows/convert_library.nf \\
        --library libs/mylib.predicted.speclib \\
        --outdir results \\
        -profile docker
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

// Main workflow
workflow {
    // Check library file
    library_file = file(params.library)

    if (!library_file.exists()) {
        log.error "ERROR: Library file not found: ${params.library}"
        exit 1
    }

    // Optional subdirectory for output organization
    def subdir = params.subdir ?: ''

    // Log workflow info
    log.info ""
    log.info "DIANN Library Conversion Workflow"
    log.info "================================="
    log.info "Library      : ${params.library}"
    log.info "DIANN version: ${params.diann_version}"
    log.info "Threads      : ${params.threads}"
    log.info "Output dir   : ${params.outdir}"
    log.info ""

    // Run conversion
    CONVERT_LIBRARY(
        library_file,
        subdir
    )
}

workflow.onComplete {
    log.info ""
    log.info "Workflow completed at: ${workflow.complete}"
    log.info "Execution status: ${workflow.success ? 'Success' : 'Failed'}"
    log.info "Duration: ${workflow.duration}"
    log.info "Results: ${params.outdir}"
    log.info ""
}
