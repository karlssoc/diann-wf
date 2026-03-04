#!/usr/bin/env nextflow

/*
 * DIANN Workflow - Main Entry Point
 *
 * Use: nextflow run karlssoc/diann-wf -entry <WORKFLOW> -params-file config.yaml -profile <PROFILE>
 *
 * Production workflows (FASTA + MS data -> quantified proteins):
 *   QUANTIFY_FASTA_SUBSET    Presearch N files -> subset FASTA -> new speclib -> quantify all (recommended)
 *   PRESEARCH_AND_QUANTIFY   Presearch N largest files -> subset library -> quantify all
 *   LIBRARY_AND_QUANTIFY     Generate library + quantify samples (no search space reduction)
 *
 * Standalone modules (single step):
 *   create_library           Create spectral library from FASTA
 *   quantify_only            Quantify samples using an existing library
 *   convert_library          Convert .speclib to .parquet format
 *   tune_models              Tune prediction models from an existing library
 *
 * Development:
 *   ITERATIVE_QUANT          Iterative quantification (all files for identification)
 */

nextflow.enable.dsl = 2

// Import modules
include { GENERATE_LIBRARY } from './modules/library'
include { QUANTIFY } from './modules/quantify'
include { CONVERT_LIBRARY } from './modules/convert_library'
include { TUNE_MODELS } from './modules/tune'

// Import workflows
include { ITERATIVE_QUANT } from './workflows/iterative_quant'
include { LIBRARY_AND_QUANTIFY } from './workflows/library_and_quantify'
include { PRESEARCH_AND_QUANTIFY } from './workflows/presearch_and_quantify'
include { QUANTIFY_FASTA_SUBSET } from './workflows/quantify_fasta_subset'

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
        params.library ?: [:],
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

    // MBR: quantify_only is a single-pass workflow, so mbr_final controls --reanalyse
    // (params.mbr is for identification stages in multi-pass workflows, default false)
    def mbr = params.mbr_final != null ? params.mbr_final : true
    log.info "MBR          : ${mbr}"
    log.info ""
    QUANTIFY(
        samples_ch,
        library_file,
        fasta_file,
        ref_library_file,
        mbr,
        params.qvalue ?: 0
    )
}

// Convert Library Workflow
workflow convert_library {
    checkPlatformWarning()

    if (!params.library) {
        log.error "ERROR: --library parameter is required (path to .speclib or .predicted.speclib)"
        exit 1
    }

    def library_file = file(params.library)
    if (!library_file.exists()) {
        log.error "ERROR: Library file not found: ${params.library}"
        exit 1
    }

    def subdir = params.subdir ?: ''
    def fasta_file = params.fasta ? file(params.fasta) : file('NO_FILE')
    def cut = params.cut ?: 'K*,R*,!*P'
    def missed_cleavages = params.missed_cleavages ?: 1

    if (params.fasta && !fasta_file.exists()) {
        log.error "ERROR: FASTA file not found: ${params.fasta}"
        exit 1
    }

    log.info ""
    log.info "DIANN Library Conversion"
    log.info "========================"
    log.info "Library      : ${params.library}"
    log.info "FASTA        : ${params.fasta ?: 'not provided (proteotypic annotation disabled)'}"
    if (params.fasta) {
        log.info "Digest       : cut=${cut}, missed_cleavages=${missed_cleavages}"
    }
    log.info "Output dir   : ${params.outdir}"
    log.info ""

    CONVERT_LIBRARY(
        library_file,
        subdir,
        fasta_file,
        cut,
        missed_cleavages
    )
}

// Tune Models Workflow
workflow tune_models {
    checkPlatformWarning()

    if (!params.tune_library) {
        log.error "ERROR: --tune_library parameter is required (path to spectral library for tuning)"
        exit 1
    }

    def tune_lib_file = file(params.tune_library)
    if (!tune_lib_file.exists()) {
        log.error "ERROR: Tune library not found: ${params.tune_library}"
        exit 1
    }

    def subdir = params.subdir ?: 'tuning'

    log.info ""
    log.info "DIANN Model Tuning"
    log.info "==================="
    log.info "Library      : ${params.tune_library}"
    log.info "Tune RT      : ${params.tuning?.tune_rt ?: false}"
    log.info "Tune IM      : ${params.tuning?.tune_im ?: false}"
    log.info "Tune FR      : ${params.tuning?.tune_fr ?: false}"
    log.info "Output dir   : ${params.outdir}"
    log.info ""

    def tune_lib_ch = Channel.fromPath(params.tune_library, checkIfExists: true)

    TUNE_MODELS(
        tune_lib_ch,
        params.library_name ?: 'tuned',
        subdir
    )
}

// Default workflow (no entry specified)
workflow {
    log.error """
    ERROR: No workflow specified.

    Usage: nextflow run karlssoc/diann-wf -entry <WORKFLOW> -params-file config.yaml -profile <PROFILE>

    Production workflows:
      -entry QUANTIFY_FASTA_SUBSET  : Presearch N files -> subset FASTA -> new speclib -> quantify all (recommended)
      -entry PRESEARCH_AND_QUANTIFY : Presearch N files -> subset library -> quantify all
      -entry LIBRARY_AND_QUANTIFY   : Generate library + quantify samples

    Standalone modules:
      -entry create_library         : Create spectral library from FASTA
      -entry quantify_only          : Quantify with existing library
      -entry convert_library        : Convert .speclib to .parquet
      -entry tune_models            : Tune prediction models

    Development:
      -entry ITERATIVE_QUANT        : Iterative quantification

    Example:
      nextflow run karlssoc/diann-wf -entry PRESEARCH_AND_QUANTIFY -params-file config.yaml -profile slurm
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
