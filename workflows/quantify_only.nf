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
          file_type: 'd'      # Options: 'd', 'raw', 'mzML'
        - id: 'sample2'
          dir: 'input/sample2'
          file_type: 'raw'

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
    // Parse samples
    // Samples can be provided as:
    // 1. YAML/JSON file path
    // 2. Inline JSON string
    // 3. Already parsed list from params file

    def samples_list
    if (params.samples instanceof List) {
        samples_list = params.samples
    } else if (params.samples instanceof String && params.samples.startsWith('[')) {
        // Inline JSON
        samples_list = new groovy.json.JsonSlurper().parseText(params.samples)
    } else if (params.samples instanceof String) {
        // File path
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
    // Optional: params.subdir can be used to organize outputs into subdirectories
    def subdir = params.subdir ?: ''

    samples_ch = Channel.fromList(samples_list)
        .map { sample ->
            def sample_id = sample.id
            def sample_dir = file(sample.dir)
            def file_type = sample.file_type ?: 'raw'

            if (!sample_dir.exists()) {
                log.error "ERROR: Sample directory not found: ${sample.dir}"
                exit 1
            }

            tuple(sample_id, sample_dir, file_type, subdir)
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

workflow.onComplete {
    log.info ""
    log.info "Workflow completed at: ${workflow.complete}"
    log.info "Execution status: ${workflow.success ? 'Success' : 'Failed'}"
    log.info "Duration: ${workflow.duration}"
    log.info "Results: ${params.outdir}"
    log.info ""
}
