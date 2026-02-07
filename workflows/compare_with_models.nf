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
include { resolveModelFiles; logModelInfo } from '../lib/models'

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

    // Resolve model files using shared utility (supports --model_preset and explicit paths)
    def models = resolveModelFiles(params, projectDir)

    // Log workflow info
    log.info ""
    log.info "DIANN Library Comparison with Pre-trained Models"
    log.info "================================================="
    log.info "FASTA        : ${params.fasta}"
    log.info "DIANN version: ${params.diann_version}"
    log.info "Threads      : ${params.threads}"
    log.info "Output dir   : ${params.outdir}"
    log.info "Samples      : ${samples_list.size()}"
    logModelInfo(models, params)
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
        params.library ?: [:],
        file('NO_FILE'),  // no tokens
        file('NO_FILE'),  // no rt model
        file('NO_FILE'),  // no im model
        file('NO_FILE'),  // no fr model
        file('NO_FILE')   // no fasta filter
    )
    def default_library = GENERATE_LIBRARY_DEFAULT.out.library

    // Step 2: Generate library with pre-trained models (NO TUNING STEP)
    log.info "Step 2: Generating library with pre-trained models"
    def library_name_tuned = "${params.library_name ?: 'library'}_tuned"
    GENERATE_LIBRARY_TUNED(
        fasta_file,
        library_name_tuned,
        'tuned_library',
        params.library ?: [:],
        models.tokens,
        models.rt_model,
        models.im_model,
        models.fr_model,
        file('NO_FILE')   // no fasta filter
    )
    def tuned_library = GENERATE_LIBRARY_TUNED.out.library

    // Step 3: Quantify with default library
    log.info "Step 3: Quantifying samples with default library"
    def samples_ch_default = createSamplesChannel(samples_list, 'quant/default')
    def mbr = params.mbr != null ? params.mbr : true

    QUANTIFY_DEFAULT(
        samples_ch_default,
        default_library.first(),  // Broadcast library to all samples
        fasta_file,
        ref_library_file,
        mbr,
        params.qvalue ?: 0
    )

    // Step 4: Quantify with tuned library
    log.info "Step 4: Quantifying samples with tuned library"
    def samples_ch_tuned = createSamplesChannel(samples_list, 'quant/tuned')

    // Use .first() to ensure library is a value channel that broadcasts to all samples
    QUANTIFY_TUNED(
        samples_ch_tuned,
        tuned_library.first(),
        fasta_file,
        ref_library_file,
        mbr,
        params.qvalue ?: 0
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
