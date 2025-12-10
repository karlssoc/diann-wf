#!/usr/bin/env nextflow

/*
 * DIANN Full Pipeline Workflow
 *
 * Complete multi-round workflow:
 *   Round 1: Generate library with default models → Quantify samples
 *   Tuning:  Fine-tune prediction models using specified sample
 *   Round 2: Generate library with RT+IM tuned models → Quantify samples
 *   Round 3: Generate library with RT+IM+FR tuned models → Quantify samples (DIANN 2.3.1+)
 *
 * This is the complex workflow used for comprehensive analysis with model optimization.
 * For most cases, use quantify_only.nf or create_library.nf instead.
 *
 * Required parameters:
 *   --fasta              Path to FASTA file
 *   --samples            Sample definitions
 *   --tune_sample        Which sample to use for tuning (sample id)
 *
 * Example usage:
 *   nextflow run workflows/full_pipeline.nf -params-file configs/full_pipeline.yaml -profile slurm
 */

nextflow.enable.dsl = 2

// Include modules
include { GENERATE_LIBRARY } from '../modules/library'
include { TUNE_MODELS } from '../modules/tune'
include { QUANTIFY } from '../modules/quantify'

// Help message
def helpMessage() {
    log.info"""
    DIANN Full Pipeline Workflow

    Usage:
      nextflow run workflows/full_pipeline.nf -params-file <config.yaml> -profile <profile>

    Required Parameters:
      --fasta PATH              FASTA file
      --samples LIST            Sample definitions
      --tune_sample ID          Sample to use for model tuning

    Workflow Control:
      --run_r1 true/false       Run round 1 (default library) [default: true]
      --run_tune true/false     Run model tuning [default: true]
      --run_r2 true/false       Run round 2 (RT+IM tuning) [default: true]
      --run_r3 true/false       Run round 3 (RT+IM+FR tuning) [default: false]

    Version Control:
      --r1_diann_version VER    DIANN version for R1 [default: 2.3.1]
      --r2_diann_version VER    DIANN version for R2 [default: 2.2.0]
      --r3_diann_version VER    DIANN version for R3 [default: 2.3.1]

    Examples:
      # Full 3-round pipeline
      nextflow run workflows/full_pipeline.nf \\
        -params-file configs/full_pipeline.yaml \\
        -profile slurm

      # Only R1 and tuning (skip R2/R3)
      nextflow run workflows/full_pipeline.nf \\
        -params-file configs/full_pipeline.yaml \\
        --run_r2 false \\
        --run_r3 false \\
        -profile slurm
    """.stripIndent()
}

// Show help message if requested
if (params.help) {
    helpMessage()
    exit 0
}

// Validate required parameters
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

// Set defaults
params.run_r1 = params.run_r1 != null ? params.run_r1 : true
params.run_tune = params.run_tune != null ? params.run_tune : true
params.run_r2 = params.run_r2 != null ? params.run_r2 : true
params.run_r3 = params.run_r3 != null ? params.run_r3 : false

params.r1_diann_version = params.r1_diann_version ?: '2.3.1'
params.r2_diann_version = params.r2_diann_version ?: '2.2.0'
params.r3_diann_version = params.r3_diann_version ?: '2.3.1'

// Main workflow
workflow {
    // Parse samples (similar to quantify_only.nf)
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

    // Check FASTA file
    fasta_file = file(params.fasta)
    if (!fasta_file.exists()) {
        log.error "ERROR: FASTA file not found: ${params.fasta}"
        exit 1
    }

    // Log workflow info
    log.info ""
    log.info "DIANN Full Pipeline Workflow"
    log.info "============================="
    log.info "FASTA          : ${params.fasta}"
    log.info "Samples        : ${samples_list.size()}"
    log.info "Tune sample    : ${params.tune_sample ?: 'not specified'}"
    log.info ""
    log.info "Workflow stages:"
    log.info "  Round 1      : ${params.run_r1} (DIANN ${params.r1_diann_version})"
    log.info "  Tuning       : ${params.run_tune}"
    log.info "  Round 2      : ${params.run_r2} (DIANN ${params.r2_diann_version})"
    log.info "  Round 3      : ${params.run_r3} (DIANN ${params.r3_diann_version})"
    log.info ""

    // ====== ROUND 1: Default models ======
    if (params.run_r1) {
        log.info "Starting Round 1: Library generation and quantification with default models"

        // Generate R1 library
        GENERATE_LIBRARY(
            fasta_file,
            "library_r1",
            file('NO_FILE'),  // No tuned models
            file('NO_FILE'),
            file('NO_FILE'),
            file('NO_FILE')
        )

        // Create samples channel
        samples_r1_ch = Channel.fromList(samples_list)
            .map { sample ->
                tuple(
                    sample.id,
                    file(sample.dir),
                    sample.file_type ?: 'raw'
                )
            }

        // Quantify R1
        QUANTIFY(
            samples_r1_ch,
            GENERATE_LIBRARY.out.library,
            fasta_file
        )

        r1_results = QUANTIFY.out.out_lib
    }

    // ====== TUNING: Fine-tune models ======
    if (params.run_tune) {
        if (!params.tune_sample) {
            log.error "ERROR: --tune_sample is required when tuning is enabled"
            exit 1
        }

        log.info "Starting Model Tuning using sample: ${params.tune_sample}"

        // Get the out-lib.parquet from the specified sample
        tune_lib = r1_results
            .filter { sample_id, lib -> sample_id == params.tune_sample }
            .map { sample_id, lib -> lib }

        // Tune models
        TUNE_MODELS(
            tune_lib,
            "tuned_models"
        )

        tuned_tokens = TUNE_MODELS.out.tokens
        tuned_rt = TUNE_MODELS.out.rt_model
        tuned_im = TUNE_MODELS.out.im_model
        tuned_fr = TUNE_MODELS.out.fr_model
    }

    // ====== ROUND 2: RT + IM tuned models ======
    if (params.run_r2 && params.run_tune) {
        log.info "Starting Round 2: Library generation with RT+IM tuned models"

        // Generate R2 library with RT+IM models
        GENERATE_LIBRARY(
            fasta_file,
            "library_r2",
            tuned_tokens,
            tuned_rt,
            tuned_im,
            file('NO_FILE')  // No FR model for R2
        )

        // Create samples channel for R2
        samples_r2_ch = Channel.fromList(samples_list)
            .map { sample ->
                tuple(
                    sample.id,
                    file(sample.dir),
                    sample.file_type ?: 'raw'
                )
            }

        // Quantify R2
        QUANTIFY(
            samples_r2_ch,
            GENERATE_LIBRARY.out.library,
            fasta_file
        )
    }

    // ====== ROUND 3: RT + IM + FR tuned models ======
    if (params.run_r3 && params.run_tune) {
        log.info "Starting Round 3: Library generation with RT+IM+FR tuned models (DIANN 2.3.1+)"

        // Generate R3 library with RT+IM+FR models
        GENERATE_LIBRARY(
            fasta_file,
            "library_r3",
            tuned_tokens,
            tuned_rt,
            tuned_im,
            tuned_fr
        )

        // Create samples channel for R3
        samples_r3_ch = Channel.fromList(samples_list)
            .map { sample ->
                tuple(
                    sample.id,
                    file(sample.dir),
                    sample.file_type ?: 'raw'
                )
            }

        // Quantify R3
        QUANTIFY(
            samples_r3_ch,
            GENERATE_LIBRARY.out.library,
            fasta_file
        )
    }
}

workflow.onComplete {
    log.info ""
    log.info "Full Pipeline completed at: ${workflow.complete}"
    log.info "Execution status: ${workflow.success ? 'Success' : 'Failed'}"
    log.info "Duration: ${workflow.duration}"
    log.info "Results: ${params.outdir}"
    log.info ""
}
