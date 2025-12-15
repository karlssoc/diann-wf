#!/usr/bin/env nextflow

/*
 * Simple workflow for testing TUNE_MODELS process
 * Useful for verifying SLURM configuration before running complex workflows
 */

nextflow.enable.dsl=2

// Import tune module
include { TUNE_MODELS } from '../modules/tune'

// Workflow
workflow {
    // Input validation
    if (!params.tune_library) {
        error "ERROR: tune_library parameter is required. Provide a path to an existing spectral library (.tsv or .parquet)"
    }

    if (!file(params.tune_library).exists()) {
        error "ERROR: tune_library file not found: ${params.tune_library}"
    }

    // Set default tuning parameters if not specified
    if (!params.tuning) {
        params.tuning = [
            tune_rt: true,
            tune_im: true,
            tune_fr: false
        ]
    }

    log.info """
    ============================================
    DIANN Tuning Test Workflow
    ============================================
    Input Library : ${params.tune_library}
    Output Dir    : ${params.outdir}
    Tune RT       : ${params.tuning?.tune_rt ?: false}
    Tune IM       : ${params.tuning?.tune_im ?: false}
    Tune FR       : ${params.tuning?.tune_fr ?: false}
    DIANN Version : ${params.diann_version}
    Profile       : ${workflow.profile}
    ============================================
    """.stripIndent()

    // Create input channel
    tune_lib = Channel.fromPath(params.tune_library, checkIfExists: true)

    // Run tuning
    TUNE_MODELS(
        tune_lib,
        "test_tune",
        "tuning_test"
    )

    // Log completion
    TUNE_MODELS.out.log.view { log ->
        println "\nTuning completed successfully!"
        println "Check output in: ${params.outdir}/tuning_test/"
    }
}

workflow.onComplete {
    log.info """
    ============================================
    Workflow completed: ${workflow.success ? 'SUCCESS' : 'FAILED'}
    Duration          : ${workflow.duration}
    Exit status       : ${workflow.exitStatus}
    ============================================
    """.stripIndent()
}

workflow.onError {
    log.info """
    ============================================
    Workflow execution stopped with error
    Error message: ${workflow.errorMessage}
    ============================================
    """.stripIndent()
}
