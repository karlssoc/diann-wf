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

    Optional Parameters (Pre-Trained Models):
      --model_preset NAME   Use pre-trained models from models/ directory
                            Example: 'ttht-evos-30spd'
      --tokens PATH         Tokens file (out-lib.dict.txt) [overrides preset]
      --rt_model PATH       RT model (out-lib.tuned_rt.pt) [overrides preset]
      --im_model PATH       IM model (out-lib.tuned_im.pt) [overrides preset]
      --fr_model PATH       FR model (out-lib.tuned_fr.pt) [overrides preset, requires DIANN 2.3.1+]

      Note: Explicit file paths take priority over model_preset

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

      # Create library with pre-trained model preset
      nextflow run workflows/create_library.nf \\
        --fasta mydata.fasta \\
        --library_name mylib_preset \\
        --model_preset ttht-evos-30spd \\
        -profile slurm

      # Create library with explicit model files (overrides preset)
      nextflow run workflows/create_library.nf \\
        --fasta mydata.fasta \\
        --library_name mylib_custom \\
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

    // Resolve model files from preset or explicit paths
    // Priority: Explicit paths > Model preset > NO_FILE (default)
    def tokens_file = file('NO_FILE')
    def rt_model_file = file('NO_FILE')
    def im_model_file = file('NO_FILE')
    def fr_model_file = file('NO_FILE')

    // Tokens file
    if (params.tokens) {
        tokens_file = file(params.tokens)
    } else if (params.model_preset) {
        def tokens_path = "${projectDir}/models/${params.model_preset}/dict.txt"
        if (file(tokens_path).exists()) {
            tokens_file = file(tokens_path)
            log.info "Using model preset: ${params.model_preset}"
        } else {
            log.warn "Model preset '${params.model_preset}' tokens not found at ${tokens_path}"
        }
    }

    // RT model
    if (params.rt_model) {
        rt_model_file = file(params.rt_model)
    } else if (params.model_preset) {
        def rt_path = "${projectDir}/models/${params.model_preset}/tuned_rt.pt"
        if (file(rt_path).exists()) {
            rt_model_file = file(rt_path)
        }
    }

    // IM model
    if (params.im_model) {
        im_model_file = file(params.im_model)
    } else if (params.model_preset) {
        def im_path = "${projectDir}/models/${params.model_preset}/tuned_im.pt"
        if (file(im_path).exists()) {
            im_model_file = file(im_path)
        }
    }

    // FR model
    if (params.fr_model) {
        fr_model_file = file(params.fr_model)
    } else if (params.model_preset) {
        def fr_path = "${projectDir}/models/${params.model_preset}/tuned_fr.pt"
        if (file(fr_path).exists()) {
            fr_model_file = file(fr_path)
        }
    }

    // Validate explicit paths exist
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
    def using_models = (tokens_file.name != 'NO_FILE')
    log.info ""
    log.info "DIANN Library Creation Workflow"
    log.info "================================"
    log.info "FASTA        : ${params.fasta}"
    log.info "Library name : ${params.library_name}"
    log.info "DIANN version: ${params.diann_version}"
    log.info "Threads      : ${params.threads}"
    log.info "Output dir   : ${params.outdir}"
    log.info "Using models : ${using_models}"
    if (using_models) {
        if (params.model_preset) {
            log.info "  Preset     : ${params.model_preset}"
        }
        log.info "  Tokens     : ${tokens_file.name != 'NO_FILE' ? (params.tokens ?: 'from preset') : 'not provided'}"
        log.info "  RT model   : ${rt_model_file.name != 'NO_FILE' ? (params.rt_model ?: 'from preset') : 'not provided'}"
        log.info "  IM model   : ${im_model_file.name != 'NO_FILE' ? (params.im_model ?: 'from preset') : 'not provided'}"
        log.info "  FR model   : ${fr_model_file.name != 'NO_FILE' ? (params.fr_model ?: 'from preset') : 'not provided'}"
    }
    log.info ""

    // Optional: params.subdir can be used to organize outputs into subdirectories
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

workflow.onComplete {
    def subdir = params.subdir ?: 'library'
    log.info ""
    log.info "Workflow completed at: ${workflow.complete}"
    log.info "Execution status: ${workflow.success ? 'Success' : 'Failed'}"
    log.info "Duration: ${workflow.duration}"
    log.info "Library: ${params.outdir}/${subdir}/${params.library_name}.predicted.speclib"
    log.info ""
}
