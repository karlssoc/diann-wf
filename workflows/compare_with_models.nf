#!/usr/bin/env nextflow

/*
 * DIANN Library Comparison with Pre-trained Models
 *
 * This workflow compares quantification results using default vs pre-trained model libraries:
 *   1. Generate library with default models
 *   2. Generate library with pre-trained models (from preset or explicit paths)
 *   3. Quantify samples with both libraries (side-by-side comparison)
 *
 * Unlike compare_libraries.nf, this workflow SKIPS the tuning step and uses
 * existing .pt model files directly.
 *
 * Required parameters:
 *   --fasta              Path to FASTA file
 *   --samples            Sample definitions
 *   --model_preset OR explicit model paths (--tokens, --rt_model, etc.)
 *
 * Output organization:
 *   results/
 *     ├── default_library/     # Library generated with default models
 *     ├── tuned_library/       # Library generated with pre-trained models
 *     ├── quant/default/       # Quantification results using default library
 *     └── quant/tuned/         # Quantification results using tuned library
 *
 * Example usage:
 *   # Using model preset
 *   nextflow run workflows/compare_with_models.nf \
 *     --model_preset ttht-evos-30spd \
 *     --fasta mydata.fasta \
 *     --samples '[{"id":"exp01","dir":"input/exp01","file_type":"raw"}]' \
 *     -profile slurm
 *
 *   # Using explicit paths
 *   nextflow run workflows/compare_with_models.nf \
 *     --tokens path/to/dict.txt \
 *     --rt_model path/to/tuned_rt.pt \
 *     --fasta mydata.fasta \
 *     --samples '[{"id":"exp01","dir":"input/exp01","file_type":"raw"}]' \
 *     -profile slurm
 */

nextflow.enable.dsl = 2

// Include modules with aliases to allow multiple invocations
include { GENERATE_LIBRARY as GENERATE_LIBRARY_DEFAULT } from '../modules/library'
include { GENERATE_LIBRARY as GENERATE_LIBRARY_TUNED } from '../modules/library'
include { QUANTIFY as QUANTIFY_DEFAULT } from '../modules/quantify'
include { QUANTIFY as QUANTIFY_TUNED } from '../modules/quantify'

// Include shared utilities
include { parseSamples; createSamplesChannel } from '../lib/samples'

// Help message
def helpMessage() {
    log.info"""
    DIANN Library Comparison with Pre-trained Models

    This workflow compares quantification using default vs pre-trained models.
    Unlike compare_libraries.nf, this SKIPS tuning and uses existing .pt files.

    Usage:
      nextflow run workflows/compare_with_models.nf -params-file <config.yaml> -profile <profile>

    Required Parameters:
      --fasta PATH              FASTA file
      --samples LIST            Sample definitions

    Model Parameters (one of these approaches required):
      --model_preset NAME       Use preset from models/ directory (e.g., 'ttht-evos-30spd')

      OR explicit paths:
      --tokens PATH             Path to tokens/dict.txt file
      --rt_model PATH           Path to RT model .pt file
      --im_model PATH           Path to IM model .pt file (optional)
      --fr_model PATH           Path to FR model .pt file (optional)

    Optional Parameters:
      --diann_version VER       DIANN version (default: ${params.diann_version})
      --threads N               Number of threads (default: ${params.threads})
      --outdir PATH             Output directory (default: ${params.outdir})
      --library_name STR        Base name for libraries (default: 'library')

    Examples:
      # Using model preset
      nextflow run workflows/compare_with_models.nf \\
        --model_preset ttht-evos-30spd \\
        --fasta 'mydata.fasta' \\
        --samples '[{"id":"exp01","dir":"input/exp01","file_type":"raw"}]' \\
        -profile slurm

      # Using explicit model paths
      nextflow run workflows/compare_with_models.nf \\
        --tokens 'models/custom/dict.txt' \\
        --rt_model 'models/custom/tuned_rt.pt' \\
        --fasta 'mydata.fasta' \\
        --samples '[{"id":"exp01","dir":"input/exp01","file_type":"raw"}]' \\
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

if (!params.samples) {
    log.error "ERROR: --samples parameter is required"
    helpMessage()
    exit 1
}

// Validate that at least one model source is provided
if (!params.model_preset && !params.tokens && !params.rt_model) {
    log.error "ERROR: Either --model_preset or explicit model paths (--tokens, --rt_model, etc.) are required"
    helpMessage()
    exit 1
}

// Main workflow
workflow {
    // Parse samples using shared utility
    def samples_list = parseSamples(params.samples)

    // Check FASTA file
    fasta_file = file(params.fasta)
    if (!fasta_file.exists()) {
        log.error "ERROR: FASTA file not found: ${params.fasta}"
        exit 1
    }

    // Handle optional reference library for batch correction
    ref_library_file = params.ref_library ? file(params.ref_library) : file('NO_FILE')
    if (params.ref_library && !ref_library_file.exists()) {
        log.error "ERROR: Reference library file not found: ${params.ref_library}"
        exit 1
    }

    // Resolve model files from preset or explicit paths
    // Priority: explicit paths > model preset > NO_FILE (defaults)
    def tokens_file = file('NO_FILE')
    def rt_model_file = file('NO_FILE')
    def im_model_file = file('NO_FILE')
    def fr_model_file = file('NO_FILE')
    def model_source = "none"

    // Check explicit paths first (highest priority)
    if (params.tokens) {
        tokens_file = file(params.tokens)
        if (!tokens_file.exists()) {
            log.error "ERROR: Tokens file not found: ${params.tokens}"
            exit 1
        }
        model_source = "explicit paths"
    }
    if (params.rt_model) {
        rt_model_file = file(params.rt_model)
        if (!rt_model_file.exists()) {
            log.error "ERROR: RT model file not found: ${params.rt_model}"
            exit 1
        }
        model_source = "explicit paths"
    }
    if (params.im_model) {
        im_model_file = file(params.im_model)
        if (!im_model_file.exists()) {
            log.error "ERROR: IM model file not found: ${params.im_model}"
            exit 1
        }
    }
    if (params.fr_model) {
        fr_model_file = file(params.fr_model)
        if (!fr_model_file.exists()) {
            log.error "ERROR: FR model file not found: ${params.fr_model}"
            exit 1
        }
    }

    // If no explicit paths, try model preset
    if (model_source == "none" && params.model_preset) {
        def preset_dir = "${projectDir}/models/${params.model_preset}"

        // Check tokens
        def tokens_path = "${preset_dir}/dict.txt"
        if (file(tokens_path).exists()) {
            tokens_file = file(tokens_path)
        } else {
            log.error "ERROR: Tokens file not found in preset: ${tokens_path}"
            exit 1
        }

        // Check RT model
        def rt_path = "${preset_dir}/tuned_rt.pt"
        if (file(rt_path).exists()) {
            rt_model_file = file(rt_path)
        } else {
            log.warn "RT model not found in preset: ${rt_path} (will use default)"
        }

        // Check IM model
        def im_path = "${preset_dir}/tuned_im.pt"
        if (file(im_path).exists()) {
            im_model_file = file(im_path)
        } else {
            log.info "IM model not found in preset: ${im_path} (will use default)"
        }

        // Check FR model
        def fr_path = "${preset_dir}/tuned_fr.pt"
        if (file(fr_path).exists()) {
            fr_model_file = file(fr_path)
        } else {
            log.info "FR model not found in preset: ${fr_path} (will use default)"
        }

        model_source = "preset '${params.model_preset}'"
    }

    // Log workflow info
    log.info ""
    log.info "DIANN Library Comparison with Pre-trained Models"
    log.info "================================================="
    log.info "FASTA        : ${params.fasta}"
    log.info "Model source : ${model_source}"
    if (params.model_preset) {
        log.info "Model preset : ${params.model_preset}"
    }
    log.info "Tokens       : ${tokens_file.getName() != 'NO_FILE' ? tokens_file : '(default)'}"
    log.info "RT model     : ${rt_model_file.getName() != 'NO_FILE' ? rt_model_file : '(default)'}"
    log.info "IM model     : ${im_model_file.getName() != 'NO_FILE' ? im_model_file : '(default)'}"
    log.info "FR model     : ${fr_model_file.getName() != 'NO_FILE' ? fr_model_file : '(default)'}"
    log.info "DIANN version: ${params.diann_version}"
    log.info "Threads      : ${params.threads}"
    log.info "Output dir   : ${params.outdir}"
    log.info "Samples      : ${samples_list.size()}"
    if (params.ref_library) {
        log.info "Ref library  : ${params.ref_library}"
    }
    log.info ""

    // Step 1: Generate library with default models
    log.info "Step 1: Generating library with default models"
    def library_name_default = "${params.library_name ?: 'library'}_default"
    GENERATE_LIBRARY_DEFAULT(
        fasta_file,
        library_name_default,
        'default_library',
        file('NO_FILE'),  // no tokens
        file('NO_FILE'),  // no rt model
        file('NO_FILE'),  // no im model
        file('NO_FILE')   // no fr model
    )
    def default_library = GENERATE_LIBRARY_DEFAULT.out.library

    // Step 2: Generate library with pre-trained models (NO TUNING STEP)
    log.info "Step 2: Generating library with pre-trained models"
    def library_name_tuned = "${params.library_name ?: 'library'}_tuned"
    GENERATE_LIBRARY_TUNED(
        fasta_file,
        library_name_tuned,
        'tuned_library',
        tokens_file,
        rt_model_file,
        im_model_file,
        fr_model_file
    )
    def tuned_library = GENERATE_LIBRARY_TUNED.out.library

    // Step 3: Quantify with default library
    log.info "Step 3: Quantifying samples with default library"
    def samples_ch_default = createSamplesChannel(samples_list, 'quant/default')

    QUANTIFY_DEFAULT(
        samples_ch_default,
        default_library,
        fasta_file,
        ref_library_file
    )

    // Step 4: Quantify with tuned library
    log.info "Step 4: Quantifying samples with tuned library"
    def samples_ch_tuned = createSamplesChannel(samples_list, 'quant/tuned')

    // Use .first() to ensure library is a value channel that broadcasts to all samples
    QUANTIFY_TUNED(
        samples_ch_tuned,
        tuned_library.first(),
        fasta_file,
        ref_library_file
    )
}

workflow.onComplete {
    log.info ""
    log.info "Library Comparison Workflow completed at: ${workflow.complete}"
    log.info "Execution status: ${workflow.success ? 'Success' : 'Failed'}"
    log.info "Duration: ${workflow.duration}"
    log.info ""
    log.info "Results organized by library type:"
    log.info "  Default library quantification: ${params.outdir}/quant/default/"
    log.info "  Tuned library quantification:   ${params.outdir}/quant/tuned/"
    log.info "  Default library:                ${params.outdir}/default_library/"
    log.info "  Tuned library:                  ${params.outdir}/tuned_library/"
    log.info ""
}
