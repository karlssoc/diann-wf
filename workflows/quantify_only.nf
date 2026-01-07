#!/usr/bin/env nextflow

/*
 * DIANN Quantification-Only Workflow
 *
 * This workflow performs quantification of MS data using an existing spectral library.
 * This is the most common use case - when you already have a library and just need
 * to quantify new samples.
 *
 * Required parameters:
 *   --library         Path to spectral library (.speclib or .predicted.speclib)
 *   --fasta           Path to FASTA file
 *   --samples         Path to YAML/JSON file with sample definitions, or inline JSON
 *
 * Example usage:
 *   nextflow run workflows/quantify_only.nf -params-file configs/simple_quant.yaml -profile slurm
 */

nextflow.enable.dsl = 2

// Include modules
include { QUANTIFY } from '../modules/quantify'

// Include shared utilities
include { parseSamples; createSamplesChannel } from '../lib/samples'

// Help message
def helpMessage() {
    log.info"""
    DIANN Quantification-Only Workflow

    Usage:
      nextflow run workflows/quantify_only.nf -params-file <config.yaml> -profile <profile>

    Required Parameters:
      --library PATH        Spectral library file
      --fasta PATH          FASTA file
      --samples LIST        Sample definitions (YAML file or inline list)

    Optional Parameters:
      --diann_version VER   DIANN version (default: ${params.diann_version})
      --threads N           Number of threads (default: ${params.threads})
      --outdir PATH         Output directory (default: ${params.outdir})

    Profiles:
      standard              Run locally
      slurm                 Submit to SLURM cluster
      test                  Test run with minimal resources

    Sample Definition Format (YAML):
      samples:
        - id: 'sample1'
          dir: 'input/sample1'
          file_type: 'd'           # Options: 'd', 'raw', 'mzML'
          recursive: false         # Optional: use --dir-all for recursive (default: false)
        - id: 'sample2'
          dir: 'input/sample2'
          file_type: 'raw'
          recursive: true          # Use --dir-all to process subfolders recursively

    Examples:
      # Using config file
      nextflow run workflows/quantify_only.nf -params-file configs/simple_quant.yaml -profile slurm

      # Using command line
      nextflow run workflows/quantify_only.nf \\
        --library libs/mylib.predicted.speclib \\
        --fasta mydata.fasta \\
        --samples '[{"id":"exp01","dir":"input/exp01","file_type":"d"}]' \\
        --outdir results/exp01 \\
        -profile slurm
    """.stripIndent()
}

// Show help message if requested
if (params.help) {
    helpMessage()
    exit 0
}

// Validate required parameters
if (!params.library) {
    log.error "ERROR: --library parameter is required"
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
    // Samples can be provided as:
    // 1. YAML/JSON file path
    // 2. Inline JSON string
    // 3. Already parsed list from params file
    def samples_list = parseSamples(params.samples)

    // Create channel from samples with file counting
    // Optional: params.subdir can be used to organize outputs into subdirectories
    def subdir = params.subdir ?: ''
    samples_ch = createSamplesChannel(samples_list, subdir)

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

    // Handle optional reference library for batch correction
    ref_library_file = params.ref_library ? file(params.ref_library) : file('NO_FILE')
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
    if (params.individual_mass_acc || params.individual_windows) {
        log.info "Batch corr.  : true"
    }
    log.info ""

    // Run quantification
    QUANTIFY(
        samples_ch,
        library_file,
        fasta_file,
        ref_library_file
    )
}

workflow.onComplete {
    log.info ""
    log.info "Workflow completed at: ${workflow.complete}"
    log.info "Execution status: ${workflow.success ? 'Success' : 'Failed'}"
    log.info "Duration: ${workflow.duration}"
    log.info "Results: ${params.outdir}"
    log.info ""
}
