#!/usr/bin/env nextflow

/*
 * DIANN Library Comparison Workflow
 *
 * This workflow compares quantification results using default vs tuned libraries:
 *   1. Generate library with default models
 *   2. Tune models using provided external library
 *   3. Generate library with tuned models
 *   4. Quantify samples with both libraries (side-by-side comparison)
 *
 * Required parameters:
 *   --tune_library       Path to external library for model tuning
 *   --fasta              Path to FASTA file
 *   --samples            Sample definitions
 *
 * Output organization:
 *   results/
 *     ├── default_library/     # Library generated with default models
 *     ├── tuned_library/       # Library generated with tuned models
 *     ├── tuning/              # Tuned model files
 *     ├── default/             # Quantification results using default library
 *     └── tuned/               # Quantification results using tuned library
 *
 * Example usage:
 *   nextflow run workflows/compare_libraries.nf \
 *     -params-file configs/compare_libraries.yaml \
 *     -profile slurm
 */

nextflow.enable.dsl = 2

// Include modules with aliases to allow multiple invocations
include { GENERATE_LIBRARY as GENERATE_LIBRARY_DEFAULT } from '../modules/library'
include { GENERATE_LIBRARY as GENERATE_LIBRARY_TUNED } from '../modules/library'
include { TUNE_MODELS } from '../modules/tune'
include { QUANTIFY as QUANTIFY_DEFAULT } from '../modules/quantify'
include { QUANTIFY as QUANTIFY_TUNED } from '../modules/quantify'

// Include shared utilities
include { parseSamples; createSamplesChannel } from '../lib/samples'

// Help message
def helpMessage() {
    log.info"""
    DIANN Library Comparison Workflow

    Usage:
      nextflow run workflows/compare_libraries.nf -params-file <config.yaml> -profile <profile>

    Required Parameters:
      --tune_library PATH       External library for model tuning
      --fasta PATH              FASTA file
      --samples LIST            Sample definitions

    Optional Parameters:
      --diann_version VER       DIANN version (default: ${params.diann_version})
      --threads N               Number of threads (default: ${params.threads})
      --outdir PATH             Output directory (default: ${params.outdir})
      --library_name STR        Base name for libraries (default: 'library')

    Tuning Configuration:
      --tuning.tune_rt BOOL     Tune RT models (default: true)
      --tuning.tune_im BOOL     Tune IM models (default: true)
      --tuning.tune_fr BOOL     Tune FR models (default: true, requires DIANN 2.3.1+)

    Examples:
      # Compare default vs tuned library quantification
      nextflow run workflows/compare_libraries.nf \\
        --tune_library 'results/previous_run/sample1/out-lib.parquet' \\
        --fasta 'mydata.fasta' \\
        --samples '[{"id":"exp01","dir":"input/exp01","file_type":"raw"}]' \\
        -profile slurm

      # Using config file
      nextflow run workflows/compare_libraries.nf \\
        -params-file configs/compare_libraries.yaml \\
        -profile slurm
    """.stripIndent()
}

// Show help message if requested
if (params.help) {
    helpMessage()
    exit 0
}

// Validate required parameters
if (!params.tune_library) {
    log.error "ERROR: --tune_library parameter is required"
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
    // Parse samples using shared utility
    def samples_list = parseSamples(params.samples)

    // Check files
    fasta_file = file(params.fasta)
    if (!fasta_file.exists()) {
        log.error "ERROR: FASTA file not found: ${params.fasta}"
        exit 1
    }

    tune_library_file = file(params.tune_library)
    if (!tune_library_file.exists()) {
        log.error "ERROR: Tune library file not found: ${params.tune_library}"
        exit 1
    }

    // Handle optional reference library for batch correction
    ref_library_file = params.ref_library ? file(params.ref_library) : file('NO_FILE')
    if (params.ref_library && !ref_library_file.exists()) {
        log.error "ERROR: Reference library file not found: ${params.ref_library}"
        exit 1
    }

    // Log workflow info
    log.info ""
    log.info "DIANN Library Comparison Workflow"
    log.info "=================================="
    log.info "Tune library : ${params.tune_library}"
    log.info "FASTA        : ${params.fasta}"
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

    // Step 2: Tune models using external library
    log.info "Step 2: Tuning models using external library"
    def tune_lib = Channel.fromPath(params.tune_library)
    TUNE_MODELS(
        tune_lib,
        "tuned_models",
        'tuning'
    )

    // Step 3: Generate library with tuned models
    log.info "Step 3: Generating library with tuned models"
    def library_name_tuned = "${params.library_name ?: 'library'}_tuned"
    GENERATE_LIBRARY_TUNED(
        fasta_file,
        library_name_tuned,
        'tuned_library',
        TUNE_MODELS.out.tokens,
        TUNE_MODELS.out.rt_model,
        TUNE_MODELS.out.im_model,
        TUNE_MODELS.out.fr_model
    )
    def tuned_library = GENERATE_LIBRARY_TUNED.out.library

    // Step 4: Quantify with default library
    log.info "Step 4: Quantifying samples with default library"
    def samples_ch_default = createSamplesChannel(samples_list, 'quant/default')

    QUANTIFY_DEFAULT(
        samples_ch_default,
        default_library,
        fasta_file,
        ref_library_file
    )

    // Step 5: Quantify with tuned library
    log.info "Step 5: Quantifying samples with tuned library"
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
    log.info "  Tuned models:                   ${params.outdir}/tuning/"
    log.info ""
}
