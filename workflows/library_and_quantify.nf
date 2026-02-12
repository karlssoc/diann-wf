#!/usr/bin/env nextflow

/*
========================================================================================
    DIANN Workflow: Library Generation + Quantification
========================================================================================
    Simple two-step workflow:
    1. Generate spectral library from FASTA
    2. Quantify all samples using that library

    Use case: You only have a FASTA file and MS data - need both library and quantification
    in one go without multiple rounds or tuning.
----------------------------------------------------------------------------------------
*/

nextflow.enable.dsl = 2

// Include modules
include { GENERATE_LIBRARY } from '../modules/library'
include { QUANTIFY } from '../modules/quantify'

// Include shared utilities
include { parseSamples; createSamplesChannel } from '../lib/samples'
include { resolveModelFiles; logModelInfo } from '../lib/models'

/*
========================================================================================
    WORKFLOW
========================================================================================
*/

workflow LIBRARY_AND_QUANTIFY {
    // Validate required parameters (inside workflow block so they only run when this entry is selected)
    if (!params.fasta) {
        error "ERROR: Missing required parameter --fasta"
    }
    if (!params.samples) {
        error "ERROR: Missing required parameter --samples"
    }

    // Parse samples using shared utility
    def samples_list = parseSamples(params.samples)

    // Set defaults
    def library_name = params.library_name ?: 'library'
    def library_subdir = params.library_subdir ?: 'library'

    // Create file objects
    def fasta_file = file(params.fasta)
    if (!fasta_file.exists()) {
        error "ERROR: FASTA file not found: ${params.fasta}"
    }

    // Resolve model files using shared utility
    def models = resolveModelFiles(params, projectDir)

    // Optional reference library for batch correction in quantification
    def ref_library_file = params.ref_library ? file(params.ref_library) : file('NO_FILE')

    /*
    ========================================================================================
        STEP 1: Generate Library from FASTA
    ========================================================================================
    */

    GENERATE_LIBRARY(
        fasta_file,
        library_name,
        library_subdir,
        params.library ?: [:],
        models.tokens,
        models.rt_model,
        models.im_model,
        models.fr_model,
        file('NO_FILE')  // No fasta filter
    )

    /*
    ========================================================================================
        STEP 2: Quantify Samples with Generated Library
    ========================================================================================
    */

    // Prepare samples channel using shared utility
    def subdir = params.quantify_subdir ?: ''
    def samples_ch = createSamplesChannel(samples_list, subdir)

    // Convert library output to value channel for multi-sample broadcasting
    def generated_library = GENERATE_LIBRARY.out.library.first()

    // Quantify all samples with the generated library (MBR enabled by default)
    def mbr = params.mbr_final != null ? params.mbr_final : true
    QUANTIFY(
        samples_ch,
        generated_library,
        fasta_file,
        ref_library_file,
        mbr,
        params.qvalue ?: 0
    )

    // Emit outputs for potential use in combined workflows
    emit:
    library = GENERATE_LIBRARY.out.library
    library_log = GENERATE_LIBRARY.out.log
    quantify_reports = QUANTIFY.out.report
    quantify_out_libs = QUANTIFY.out.out_lib
    quantify_matrices = QUANTIFY.out.matrices
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
    Library generated:  ${params.outdir}/${params.library_subdir ?: 'library'}/${params.library_name ?: 'library'}.predicted.speclib
    Samples quantified: ${sample_count}
    Results directory:  ${params.outdir}
    ========================================================================================
    """
}
