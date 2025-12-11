#!/usr/bin/env nextflow

/*
 * DIANN Workflow - Main Entry Point
 *
 * This file provides named workflow entry points for the different DIANN workflows.
 * Use the -entry flag to select which workflow to run.
 *
 * Available workflows:
 *   - create_library: Create a spectral library from FASTA
 *   - quantify:       Quantify samples using an existing library
 *   - full_pipeline:  Run the complete DIANN pipeline
 *
 * Examples:
 *   nextflow run karlssoc/diann-wf -entry create_library -params-file configs/library.yaml -profile slurm
 *   nextflow run karlssoc/diann-wf -entry quantify -params-file configs/quant.yaml -profile slurm
 */

nextflow.enable.dsl = 2

// Import workflows
include { GENERATE_LIBRARY } from './modules/library'

// Create Library Workflow
workflow create_library {
    // Validate required parameters
    if (!params.fasta) {
        log.error "ERROR: --fasta parameter is required"
        exit 1
    }
    if (!params.library_name) {
        log.error "ERROR: --library_name parameter is required"
        exit 1
    }

    // Check FASTA file
    fasta_file = file(params.fasta)
    if (!fasta_file.exists()) {
        log.error "ERROR: FASTA file not found: ${params.fasta}"
        exit 1
    }

    // Handle tuned model files (use placeholder if not provided)
    tokens_file = params.tokens ? file(params.tokens) : file('NO_FILE')
    rt_model_file = params.rt_model ? file(params.rt_model) : file('NO_FILE')
    im_model_file = params.im_model ? file(params.im_model) : file('NO_FILE')
    fr_model_file = params.fr_model ? file(params.fr_model) : file('NO_FILE')

    // Log workflow info
    def using_tuned = params.tokens != null
    log.info ""
    log.info "DIANN Library Creation Workflow"
    log.info "================================"
    log.info "FASTA        : ${params.fasta}"
    log.info "Library name : ${params.library_name}"
    log.info "DIANN version: ${params.diann_version}"
    log.info "Threads      : ${params.threads}"
    log.info "Output dir   : ${params.outdir}"
    log.info "Using tuned  : ${using_tuned}"
    log.info ""

    def subdir = params.subdir ?: 'library'

    // Generate library
    GENERATE_LIBRARY(
        fasta_file,
        params.library_name,
        subdir,
        tokens_file,
        rt_model_file,
        im_model_file,
        fr_model_file
    )
}

// Default workflow (points to the manifest main script)
workflow {
    log.error """
    ERROR: No workflow specified.

    Please use the -entry flag to select a workflow:
      -entry create_library  : Create spectral library from FASTA
      -entry quantify        : Quantify samples (TBD)
      -entry full_pipeline   : Run complete pipeline (TBD)

    Example:
      nextflow run karlssoc/diann-wf -entry create_library -params-file configs/library.yaml -profile slurm
    """
    exit 1
}

workflow.onComplete {
    def subdir = params.subdir ?: 'library'
    log.info ""
    log.info "Workflow completed at: ${workflow.complete}"
    log.info "Execution status: ${workflow.success ? 'Success' : 'Failed'}"
    log.info "Duration: ${workflow.duration}"
    if (params.library_name) {
        log.info "Library: ${params.outdir}/${subdir}/${params.library_name}.predicted.speclib"
    }
    log.info ""
}
