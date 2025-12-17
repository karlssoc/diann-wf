#!/usr/bin/env nextflow

/*
========================================================================================
    DIANN Workflow: Repredict Library
========================================================================================
    Generates a new spectral library using DIA-NN predictor based on peptides
    from an existing library.

    Use case: You have an existing spectral library (e.g., from a search) and want
    to generate a new predicted library with updated/tuned models while keeping
    the same peptide identifications.
----------------------------------------------------------------------------------------
*/

nextflow.enable.dsl = 2

// Include modules
include { REPREDICT_LIBRARY } from '../modules/repredict_library'

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
    if (!params.input_library) {
        error "ERROR: Missing required parameter --input_library (existing spectral library)"
    }

    // Set defaults
    def library_name = params.library_name ?: 'repredicted_lib'
    def subdir = params.subdir ?: 'library'

    // Create file objects
    def fasta_file = file(params.fasta)
    def input_lib_file = file(params.input_library)

    // Check input files exist
    if (!fasta_file.exists()) {
        error "ERROR: FASTA file not found: ${params.fasta}"
    }
    if (!input_lib_file.exists()) {
        error "ERROR: Input library file not found: ${params.input_library}"
    }

    // Handle optional tuned model files
    def tokens_file = params.tokens ? file(params.tokens) : file('NO_FILE')
    def rt_model_file = params.rt_model ? file(params.rt_model) : file('NO_FILE')
    def im_model_file = params.im_model ? file(params.im_model) : file('NO_FILE')
    def fr_model_file = params.fr_model ? file(params.fr_model) : file('NO_FILE')

    // Run library reprediction
    REPREDICT_LIBRARY(
        fasta_file,
        input_lib_file,
        library_name,
        subdir,
        tokens_file,
        rt_model_file,
        im_model_file,
        fr_model_file
    )

    // Emit outputs for use in combined workflows
    emit:
    library = REPREDICT_LIBRARY.out.library
    log = REPREDICT_LIBRARY.out.log
}

/*
========================================================================================
    WORKFLOW INTROSPECTION
========================================================================================
*/

workflow.onComplete {
    println """
    ========================================================================================
    Workflow completed!
    ========================================================================================
    Repredicted library: ${params.outdir}/${params.subdir ?: 'library'}/${params.library_name ?: 'repredicted_lib'}.predicted.speclib
    Log file:            ${params.outdir}/${params.subdir ?: 'library'}/library_reprediction.log
    ========================================================================================
    """
}
