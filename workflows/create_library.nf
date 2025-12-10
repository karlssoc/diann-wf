#!/usr/bin/env nextflow

/*
 * DIANN Library Creation Workflow
 *
 * Creates a spectral library from a FASTA file, optionally using tuned prediction models.
 *
 * Required parameters:
 *   --fasta           Path to FASTA file
 *   --library_name    Name for the output library
 *
 * Optional parameters for tuned models:
 *   --tokens          Path to tokens file (out-lib.dict.txt)
 *   --rt_model        Path to RT model (out-lib.tuned_rt.pt)
 *   --im_model        Path to IM model (out-lib.tuned_im.pt)
 *   --fr_model        Path to FR model (out-lib.tuned_fr.pt)
 *
 * Example usage:
 *   # Create library with default models
 *   nextflow run workflows/create_library.nf -params-file configs/library_creation.yaml -profile slurm
 *
 *   # Create library with tuned models
 *   nextflow run workflows/create_library.nf \\
 *     --fasta mydata.fasta \\
 *     --library_name mylib_tuned \\
 *     --tokens tuning/out-lib.dict.txt \\
 *     --rt_model tuning/out-lib.tuned_rt.pt \\
 *     --im_model tuning/out-lib.tuned_im.pt \\
 *     -profile slurm
 */

nextflow.enable.dsl = 2

// Include modules
include { GENERATE_LIBRARY } from '../modules/library'

// Help message
def helpMessage() {
    log.info"""
    DIANN Library Creation Workflow

    Usage:
      nextflow run workflows/create_library.nf -params-file <config.yaml> -profile <profile>

    Required Parameters:
      --fasta PATH          FASTA file
      --library_name NAME   Name for output library

    Optional Parameters (Tuned Models):
      --tokens PATH         Tokens file (out-lib.dict.txt)
      --rt_model PATH       RT model (out-lib.tuned_rt.pt)
      --im_model PATH       IM model (out-lib.tuned_im.pt)
      --fr_model PATH       FR model (out-lib.tuned_fr.pt) [requires DIANN 2.3.1+]

    Library Parameters (with defaults):
      --library.min_fr_mz 200
      --library.max_fr_mz 1800
      --library.min_pep_len 7
      --library.max_pep_len 30
      --library.min_pr_mz 350
      --library.max_pr_mz 1650
      --library.min_pr_charge 2
      --library.max_pr_charge 3
      --library.cut 'K*,R*'
      --library.missed_cleavages 1
      --library.met_excision true
      --library.unimod4 true

    Examples:
      # Create library with default models
      nextflow run workflows/create_library.nf \\
        --fasta mydata.fasta \\
        --library_name mylib \\
        -profile slurm

      # Create library with tuned models
      nextflow run workflows/create_library.nf \\
        --fasta mydata.fasta \\
        --library_name mylib_tuned \\
        --tokens results/tuning/out-lib.dict.txt \\
        --rt_model results/tuning/out-lib.tuned_rt.pt \\
        --im_model results/tuning/out-lib.tuned_im.pt \\
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

if (!params.library_name) {
    log.error "ERROR: --library_name parameter is required"
    helpMessage()
    exit 1
}

// Main workflow
workflow {
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

    // Validate tuned model files if provided
    if (params.tokens && !tokens_file.exists()) {
        log.error "ERROR: Tokens file not found: ${params.tokens}"
        exit 1
    }
    if (params.rt_model && !rt_model_file.exists()) {
        log.error "ERROR: RT model file not found: ${params.rt_model}"
        exit 1
    }
    if (params.im_model && !im_model_file.exists()) {
        log.error "ERROR: IM model file not found: ${params.im_model}"
        exit 1
    }
    if (params.fr_model && !fr_model_file.exists()) {
        log.error "ERROR: FR model file not found: ${params.fr_model}"
        exit 1
    }

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
    if (using_tuned) {
        log.info "  Tokens     : ${params.tokens}"
        log.info "  RT model   : ${params.rt_model ?: 'not provided'}"
        log.info "  IM model   : ${params.im_model ?: 'not provided'}"
        log.info "  FR model   : ${params.fr_model ?: 'not provided'}"
    }
    log.info ""

    // Generate library
    GENERATE_LIBRARY(
        fasta_file,
        params.library_name,
        tokens_file,
        rt_model_file,
        im_model_file,
        fr_model_file
    )
}

workflow.onComplete {
    log.info ""
    log.info "Workflow completed at: ${workflow.complete}"
    log.info "Execution status: ${workflow.success ? 'Success' : 'Failed'}"
    log.info "Duration: ${workflow.duration}"
    log.info "Library: ${params.outdir}/library/${params.library_name}.predicted.speclib"
    log.info ""
}
