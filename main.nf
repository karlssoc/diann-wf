#!/usr/bin/env nextflow

/*
 * DIANN Workflow - Main Entry Point
 *
 * This file provides named workflow entry points for the different DIANN workflows.
 * Use the -entry flag to select which workflow to run.
 *
 * Available workflows:
 *   - ITERATIVE_QUANT:     Iterative quantification (library gen -> identify -> subset -> final)
 *   - LIBRARY_AND_QUANTIFY: Generate library + quantify samples in one go
 *   - create_library:       Create a spectral library from FASTA
 *   - quantify_only:        Quantify samples using an existing library
 *
 * Examples:
 *   nextflow run karlssoc/diann-wf -entry ITERATIVE_QUANT -params-file config.yaml -profile slurm
 *   nextflow run karlssoc/diann-wf -entry LIBRARY_AND_QUANTIFY -params-file config.yaml -profile slurm
 *   nextflow run karlssoc/diann-wf -entry create_library -params-file configs/library.yaml -profile slurm
 *   nextflow run karlssoc/diann-wf -entry quantify_only -params-file configs/quantify.yaml -profile slurm
 */

nextflow.enable.dsl = 2

// Import modules
include { GENERATE_LIBRARY } from './modules/library'
include { QUANTIFY } from './modules/quantify'

// Import workflows
include { ITERATIVE_QUANT } from './workflows/iterative_quant'
include { LIBRARY_AND_QUANTIFY } from './workflows/library_and_quantify'

// Import shared utilities
include { parseSamples; createSamplesChannel } from './lib/samples'
include { resolveModelFiles; logModelInfo } from './lib/models'

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
    def fasta_file = file(params.fasta)
    if (!fasta_file.exists()) {
        log.error "ERROR: FASTA file not found: ${params.fasta}"
        exit 1
    }

    // Resolve model files using shared utility (supports --model_preset and explicit paths)
    def models = resolveModelFiles(params, projectDir)

    // Log workflow info
    log.info ""
    log.info "DIANN Library Creation Workflow"
    log.info "================================"
    log.info "FASTA        : ${params.fasta}"
    log.info "Library name : ${params.library_name}"
    log.info "DIANN version: ${params.diann_version}"
    log.info "Threads      : ${params.threads}"
    log.info "Output dir   : ${params.outdir}"
    logModelInfo(models, params)
    log.info ""

    def subdir = params.subdir ?: 'library'

    // Generate library
    GENERATE_LIBRARY(
        fasta_file,
        params.library_name,
        subdir,
        models.tokens,
        models.rt_model,
        models.im_model,
        models.fr_model,
        file('NO_FILE')  // No fasta filter
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

    // Parse samples using shared utility
    def samples_list = parseSamples(params.samples)

    // Create channel from samples with file counting
    def subdir = params.subdir ?: ''
    def samples_ch = createSamplesChannel(samples_list, subdir)

    // Check library and fasta files
    def library_file = file(params.library)
    def fasta_file = file(params.fasta)

    if (!library_file.exists()) {
        log.error "ERROR: Library file not found: ${params.library}"
        exit 1
    }
    if (!fasta_file.exists()) {
        log.error "ERROR: FASTA file not found: ${params.fasta}"
        exit 1
    }

    // Handle optional reference library for batch correction
    def ref_library_file = params.ref_library ? file(params.ref_library) : file('NO_FILE')
    if (params.ref_library && !ref_library_file.exists()) {
        log.error "ERROR: Reference library file not found: ${params.ref_library}"
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
    if (params.ref_library) {
        log.info "Ref library  : ${params.ref_library}"
    }
    log.info ""

    // Run quantification (MBR enabled by default)
    def mbr = params.mbr != null ? params.mbr : true
    QUANTIFY(
        samples_ch,
        library_file,
        fasta_file,
        ref_library_file,
        mbr,
        params.qvalue ?: 0
    )
}

// Default workflow (no entry specified)
workflow {
    log.error """
    ERROR: No workflow specified.

    Please use the -entry flag to select a workflow:
      -entry ITERATIVE_QUANT      : Iterative quantification (recommended)
      -entry LIBRARY_AND_QUANTIFY : Generate library + quantify samples
      -entry create_library       : Create spectral library from FASTA
      -entry quantify_only        : Quantify samples using existing library

    Example:
      nextflow run karlssoc/diann-wf -entry ITERATIVE_QUANT -params-file config.yaml -profile slurm
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
