#!/usr/bin/env nextflow

/*
========================================================================================
    DIANN Workflow: Compare Library Tuning
========================================================================================
    Three-step workflow to evaluate impact of model tuning:
    1. Generate library from FASTA + quantify samples (default models)
    2. Tune models using out-lib from one of the samples
    3. Generate library from FASTA + quantify samples (tuned models)

    Use case: Evaluate whether model tuning improves results for your specific dataset
    without needing an external library.
----------------------------------------------------------------------------------------
*/

nextflow.enable.dsl = 2

// Include modules
include { GENERATE_LIBRARY as GENERATE_LIBRARY_DEFAULT } from '../modules/library'
include { GENERATE_LIBRARY as GENERATE_LIBRARY_TUNED } from '../modules/library'
include { QUANTIFY as QUANTIFY_DEFAULT } from '../modules/quantify'
include { QUANTIFY as QUANTIFY_TUNED } from '../modules/quantify'
include { TUNE_MODELS } from '../modules/tune'

// Include shared utilities
include { parseSamples; createSamplesChannel } from '../lib/samples'

// Default parameters for this workflow
params.library_name_default = 'library_default'
params.library_name_tuned = 'library_tuned'

/*
========================================================================================
    WORKFLOW
========================================================================================
*/

workflow {
    // Validate required parameters
    if (!params.fasta) {
        error "ERROR: Missing required parameter --fasta"
    }
    if (!params.samples) {
        error "ERROR: Missing required parameter --samples"
    }

    // Parse samples using shared utility
    def samples_list = parseSamples(params.samples)

    // Determine which sample to use for tuning (default: first sample)
    def tune_sample = params.tune_sample ?: samples_list[0].id
    log.info "Using sample '${tune_sample}' for model tuning"

    // Set defaults
    def library_name_default = params.library_name_default ?: 'library_default'
    def library_name_tuned = params.library_name_tuned ?: 'library_tuned'

    // Create file objects
    def fasta_file = file(params.fasta)
    if (!fasta_file.exists()) {
        error "ERROR: FASTA file not found: ${params.fasta}"
    }

    // Optional reference library for batch correction
    def ref_library_file = params.ref_library ? file(params.ref_library) : file('NO_FILE')

    /*
    ========================================================================================
        STEP 1: Generate Default Library + Quantify
    ========================================================================================
    */

    // Generate library with default models
    GENERATE_LIBRARY_DEFAULT(
        fasta_file,
        library_name_default,
        'default/library',
        file('NO_FILE'),  // No tokens
        file('NO_FILE'),  // No RT model
        file('NO_FILE'),  // No IM model
        file('NO_FILE')   // No FR model
    )

    // Prepare samples channel for default quantification using shared utility
    def samples_ch_default = createSamplesChannel(samples_list, 'default/quantify')

    // Quantify with default library
    QUANTIFY_DEFAULT(
        samples_ch_default,
        GENERATE_LIBRARY_DEFAULT.out.library.first(),
        fasta_file,
        ref_library_file
    )

    /*
    ========================================================================================
        STEP 2: Tune Models
    ========================================================================================
    */

    // Extract out-lib from the tune_sample
    def tune_library = QUANTIFY_DEFAULT.out.out_lib
        .filter { sample_id, out_lib -> sample_id == tune_sample }
        .map { sample_id, out_lib -> out_lib }

    // Run model tuning
    TUNE_MODELS(
        tune_library,
        tune_sample,
        'tuning'
    )

    /*
    ========================================================================================
        STEP 3: Generate Tuned Library + Quantify
    ========================================================================================
    */

    // Generate library with tuned models
    GENERATE_LIBRARY_TUNED(
        fasta_file,
        library_name_tuned,
        'tuned/library',
        TUNE_MODELS.out.tokens,
        TUNE_MODELS.out.rt_model,
        TUNE_MODELS.out.im_model,
        TUNE_MODELS.out.fr_model
    )

    // Prepare samples channel for tuned quantification using shared utility
    def samples_ch_tuned = createSamplesChannel(samples_list, 'tuned/quantify')

    // Quantify with tuned library
    QUANTIFY_TUNED(
        samples_ch_tuned,
        GENERATE_LIBRARY_TUNED.out.library.first(),
        fasta_file,
        ref_library_file
    )

    emit:
    default_library = GENERATE_LIBRARY_DEFAULT.out.library
    tuned_library = GENERATE_LIBRARY_TUNED.out.library
    tuned_tokens = TUNE_MODELS.out.tokens
    tuned_rt_model = TUNE_MODELS.out.rt_model
    tuned_im_model = TUNE_MODELS.out.im_model
    tuned_fr_model = TUNE_MODELS.out.fr_model
    default_reports = QUANTIFY_DEFAULT.out.report
    tuned_reports = QUANTIFY_TUNED.out.report
}

/*
========================================================================================
    WORKFLOW INTROSPECTION
========================================================================================
*/

workflow.onComplete {
    def sample_count = params.samples instanceof List ? params.samples.size() : 0

    println """
    ========================================================================================
    Workflow completed!
    ========================================================================================
    Default library:  ${params.outdir}/default/library/${params.library_name_default}.predicted.speclib
    Tuned library:    ${params.outdir}/tuned/library/${params.library_name_tuned}.predicted.speclib
    Tuned models:     ${params.outdir}/tuning/

    Default results:  ${params.outdir}/default/quantify/
    Tuned results:    ${params.outdir}/tuned/quantify/

    Samples quantified: ${sample_count}
    ========================================================================================
    Compare results in default/ vs tuned/ directories to evaluate tuning impact
    ========================================================================================
    """
}
