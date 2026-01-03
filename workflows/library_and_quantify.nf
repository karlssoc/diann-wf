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

    // Parse samples
    def samples_list = params.samples instanceof List ? params.samples : []
    if (samples_list.isEmpty()) {
        error "ERROR: No samples defined. Provide --samples parameter or samples in config file."
    }

    // Set defaults
    def library_name = params.library_name ?: 'library'
    def library_subdir = params.library_subdir ?: 'library'

    // Create file objects
    def fasta_file = file(params.fasta)
    if (!fasta_file.exists()) {
        error "ERROR: FASTA file not found: ${params.fasta}"
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
        tokens_file,
        rt_model_file,
        im_model_file,
        fr_model_file
    )

    /*
    ========================================================================================
        STEP 2: Quantify Samples with Generated Library
    ========================================================================================
    */

    // Prepare samples channel
    // Count MS files for dynamic time allocation
    def samples_ch = Channel.fromList(samples_list)
        .map { sample ->
            def sample_id = sample.id
            def sample_dir = file(sample.dir)
            def file_type = sample.file_type ?: 'raw'
            def subdir = params.quantify_subdir ?: ''  // Optional subdirectory for quantify outputs
            def recursive = sample.recursive ?: false

            // Check if sample directory exists
            if (!sample_dir.exists()) {
                error "ERROR: Sample directory not found: ${sample.dir} for sample ${sample_id}"
            }

            // Count MS files for time estimation
            def file_count = 0
            if (recursive) {
                // Recursive search for MS files
                if (file_type == 'd') {
                    file_count = sample_dir.listFiles().findAll { it.isDirectory() && it.name.endsWith('.d') }.size()
                } else if (file_type == 'raw') {
                    file_count = sample_dir.listFiles().findAll { it.name.endsWith('.raw') }.size()
                } else if (file_type == 'mzML') {
                    file_count = sample_dir.listFiles().findAll { it.name.endsWith('.mzML') }.size()
                }
            } else {
                // Non-recursive: count files in directory
                if (file_type == 'd') {
                    file_count = sample_dir.list().findAll { it.endsWith('.d') }.size()
                } else if (file_type == 'raw') {
                    file_count = sample_dir.list().findAll { it.endsWith('.raw') }.size()
                } else if (file_type == 'mzML') {
                    file_count = sample_dir.list().findAll { it.endsWith('.mzML') }.size()
                }
            }

            if (file_count == 0) {
                log.warn "WARNING: No ${file_type} files found in ${sample.dir} for sample ${sample_id}"
                file_count = 1  // Avoid division by zero, will fail at runtime anyway
            }

            tuple(sample_id, sample_dir, file_type, subdir, recursive, file_count)
        }

    // Quantify all samples with the generated library
    QUANTIFY(
        samples_ch,
        GENERATE_LIBRARY.out.library.first(),  // Broadcast library to all samples
        fasta_file,
        ref_library_file
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
