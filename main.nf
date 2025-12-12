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

// Import modules
include { GENERATE_LIBRARY } from './modules/library'
include { QUANTIFY } from './modules/quantify'

// Check for non-native execution (ARM Mac with Docker/Podman)
def checkPlatformWarning() {
    def osArch = System.getProperty("os.arch")
    def isDocker = workflow.containerEngine == 'docker'
    def isPodman = workflow.containerEngine == 'podman'

    if ((isDocker || isPodman) && osArch.contains("aarch64")) {
        log.warn ""
        log.warn "=" * 80
        log.warn "WARNING: Running x86-64 container on ARM architecture via emulation"
        log.warn ""
        log.warn "Rosetta 2 emulation can introduce differences in:"
        log.warn "  - Floating-point precision"
        log.warn "  - CPU instruction handling"
        log.warn "  - Numeric calculations"
        log.warn ""
        log.warn "This may result in DIFFERENT SCIENTIFIC RESULTS compared to native execution,"
        log.warn "including lower identification rates and altered quantification values."
        log.warn ""
        log.warn "For production/publication work, use native x86-64 hardware or Singularity"
        log.warn "on an HPC cluster with SLURM."
        log.warn "=" * 80
        log.warn ""
    }
}

// Create Library Workflow
workflow create_library {
    // Check for platform warnings
    checkPlatformWarning()

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

// Quantify Workflow
workflow quantify_only {
    // Check for platform warnings
    checkPlatformWarning()

    // Validate required parameters
    if (!params.library) {
        log.error "ERROR: --library parameter is required"
        exit 1
    }
    if (!params.fasta) {
        log.error "ERROR: --fasta parameter is required"
        exit 1
    }
    if (!params.samples) {
        log.error "ERROR: --samples parameter is required"
        exit 1
    }

    // Parse samples
    def samples_list
    if (params.samples instanceof List) {
        samples_list = params.samples
    } else if (params.samples instanceof String && params.samples.startsWith('[')) {
        samples_list = new groovy.json.JsonSlurper().parseText(params.samples)
    } else if (params.samples instanceof String) {
        def samples_file = file(params.samples)
        if (!samples_file.exists()) {
            log.error "ERROR: Samples file not found: ${params.samples}"
            exit 1
        }
        if (samples_file.name.endsWith('.yaml') || samples_file.name.endsWith('.yml')) {
            samples_list = new org.yaml.snakeyaml.Yaml().load(samples_file.text).samples
        } else {
            samples_list = new groovy.json.JsonSlurper().parseText(samples_file.text)
        }
    }

    // Create channel from samples
    def subdir = params.subdir ?: ''
    samples_ch = Channel.fromList(samples_list)
        .map { sample ->
            def sample_id = sample.id
            def sample_dir = file(sample.dir)
            def file_type = sample.file_type ?: 'raw'
            def recursive = sample.recursive ?: false

            if (!sample_dir.exists()) {
                log.error "ERROR: Sample directory not found: ${sample.dir}"
                exit 1
            }

            // Count MS files in directory for dynamic time allocation
            def file_extensions = ['*.mzML', '*.raw', '*.d', '*.wiff']
            def file_count = 0
            file_extensions.each { ext ->
                if (recursive) {
                    file_count += sample_dir.listFiles().findAll {
                        it.isDirectory() || it.name.matches(ext.replace('*', '.*'))
                    }.size()
                } else {
                    file_count += sample_dir.listFiles().findAll {
                        it.name.matches(ext.replace('*', '.*'))
                    }.size()
                }
            }

            // Log file count for user awareness
            log.info "Sample ${sample_id}: Found ${file_count} MS files"

            tuple(sample_id, sample_dir, file_type, subdir, recursive, file_count)
        }

    // Check library and fasta files
    library_file = file(params.library)
    fasta_file = file(params.fasta)

    if (!library_file.exists()) {
        log.error "ERROR: Library file not found: ${params.library}"
        exit 1
    }
    if (!fasta_file.exists()) {
        log.error "ERROR: FASTA file not found: ${params.fasta}"
        exit 1
    }

    // Log workflow info
    log.info ""
    log.info "DIANN Quantification Workflow"
    log.info "=============================="
    log.info "Library      : ${params.library}"
    log.info "FASTA        : ${params.fasta}"
    log.info "DIANN version: ${params.diann_version}"
    log.info "Threads      : ${params.threads}"
    log.info "Output dir   : ${params.outdir}"
    log.info "Samples      : ${samples_list.size()}"
    log.info ""

    // Run quantification
    QUANTIFY(
        samples_ch,
        library_file,
        fasta_file
    )
}

// Default workflow (points to the manifest main script)
workflow {
    log.error """
    ERROR: No workflow specified.

    Please use the -entry flag to select a workflow:
      -entry create_library  : Create spectral library from FASTA
      -entry quantify_only   : Quantify samples using existing library
      -entry full_pipeline   : Run complete pipeline (TBD)

    Example:
      nextflow run karlssoc/diann-wf -entry create_library -params-file configs/library.yaml -profile slurm
      nextflow run karlssoc/diann-wf -entry quantify_only -params-file configs/quant.yaml -profile slurm
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
