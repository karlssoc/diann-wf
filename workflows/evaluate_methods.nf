#!/usr/bin/env nextflow

/*
 * Method Evaluation Workflow
 *
 * Compares different search strategies and model presets on the same dataset.
 * Useful for evaluating:
 * - Standard vs iterative search
 * - Default vs tuned RT models
 * - Different model presets
 *
 * Conditions run:
 * 1. standard_default    - quantify_only with default models
 * 2. standard_presetA    - quantify_only with model_preset A
 * 3. standard_presetB    - quantify_only with model_preset B (optional)
 * 4. iterative_default   - iterative_quant with default models
 *
 * Metrics extracted:
 * - Protein.Groups identified
 * - Precursors identified
 * - Data completeness (missing value rate)
 * - Wall time / CPU hours
 */

nextflow.enable.dsl = 2

// Include modules
include { QUANTIFY as QUANTIFY_DEFAULT } from '../modules/quantify'
include { QUANTIFY as QUANTIFY_PRESET_A } from '../modules/quantify'
include { QUANTIFY as QUANTIFY_PRESET_B } from '../modules/quantify'
include { GENERATE_LIBRARY as GENERATE_LIBRARY_DEFAULT } from '../modules/library'
include { GENERATE_LIBRARY as GENERATE_LIBRARY_PRESET_A } from '../modules/library'
include { GENERATE_LIBRARY as GENERATE_LIBRARY_PRESET_B } from '../modules/library'
include { CONVERT_LIBRARY as CONVERT_LIBRARY_DEFAULT } from '../modules/convert_library'
include { CONVERT_LIBRARY as CONVERT_LIBRARY_PRESET_A } from '../modules/convert_library'
include { CONVERT_LIBRARY as CONVERT_LIBRARY_PRESET_B } from '../modules/convert_library'

// Include shared utilities
include { createSamplesChannel } from '../lib/samples'
include { resolveModelFiles; logModelInfo } from '../lib/models'

// Help message
def helpMessage() {
    log.info"""
    Method Evaluation Workflow
    ==========================

    Compares search strategies and model presets on the same dataset.

    Usage:
      nextflow run workflows/evaluate_methods.nf -params-file <config.yaml> -profile <profile>

    Required Parameters:
      --fasta PATH          FASTA sequence database
      --samples LIST        Sample definitions [{id, dir, file_type, recursive}]

    Model Preset Parameters:
      --model_preset_a NAME   First model preset to compare (required)
      --model_preset_b NAME   Second model preset to compare (optional)
      --run_default BOOL      Run with default models (default: true)
      --run_preset_a BOOL     Run with preset A (default: true)
      --run_preset_b BOOL     Run with preset B (default: false)
      --run_iterative BOOL    Run iterative search (default: false)

    Output:
      --outdir PATH         Output directory (default: results/evaluation)

    Output Structure:
      results/evaluation/
      ├── standard_default/     # Standard search, default models
      │   ├── library/
      │   └── <sample_id>/
      ├── standard_presetA/     # Standard search, preset A
      │   ├── library/
      │   └── <sample_id>/
      ├── standard_presetB/     # Standard search, preset B (if enabled)
      │   ├── library/
      │   └── <sample_id>/
      ├── iterative_default/    # Iterative search (if enabled)
      │   └── ...
      └── metrics/              # Extracted metrics
          ├── summary.tsv
          └── comparison.html

    Example:
      nextflow run workflows/evaluate_methods.nf \\
        --fasta protein.fasta \\
        --samples '[{id:"sample1",dir:"data/sample1",file_type:"raw"}]' \\
        --model_preset_a hfx-nlc-120min-260128 \\
        --model_preset_b hfx-elc-120min-260131 \\
        --run_preset_b true \\
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

// Main workflow
workflow EVALUATE_METHODS {
    // Validate input files
    def fasta_file = file(params.fasta)

    if (!fasta_file.exists()) {
        log.error "ERROR: FASTA file not found: ${params.fasta}"
        exit 1
    }

    // Configuration
    def run_default = params.run_default != null ? params.run_default : true
    def run_preset_a = params.run_preset_a != null ? params.run_preset_a : true
    def run_preset_b = params.run_preset_b != null ? params.run_preset_b : false
    def run_iterative = params.run_iterative != null ? params.run_iterative : false

    def model_preset_a = params.model_preset_a ?: null
    def model_preset_b = params.model_preset_b ?: null

    // Validate presets
    if (run_preset_a && !model_preset_a) {
        log.error "ERROR: --model_preset_a is required when --run_preset_a is true"
        exit 1
    }
    if (run_preset_b && !model_preset_b) {
        log.error "ERROR: --model_preset_b is required when --run_preset_b is true"
        exit 1
    }

    // Get samples list
    def samples_list = params.samples

    // Log configuration
    log.info ""
    log.info "Method Evaluation Workflow"
    log.info "=========================="
    log.info "FASTA        : ${params.fasta}"
    log.info "Samples      : ${samples_list.size()}"
    log.info "Output dir   : ${params.outdir}"
    log.info ""
    log.info "Conditions:"
    if (run_default) log.info "  - standard_default (DIA-NN default models)"
    if (run_preset_a) log.info "  - standard_presetA (${model_preset_a})"
    if (run_preset_b) log.info "  - standard_presetB (${model_preset_b})"
    if (run_iterative) log.info "  - iterative_default (two-pass search)"
    log.info ""

    // Library parameters
    def cut = params.library?.cut ?: 'K*,R*'
    def missed_cleavages = params.library?.missed_cleavages ?: 1

    // Placeholder for ref library
    def ref_library_file = file('NO_FILE')

    // MBR setting
    def mbr = params.mbr != null ? params.mbr : true

    // ========================================
    // CONDITION 1: Standard search with default models
    // ========================================
    if (run_default) {
        log.info "Running: standard_default"

        // Generate library with default models
        GENERATE_LIBRARY_DEFAULT(
            fasta_file,
            'library',
            'standard_default/library',
            file('NO_FILE'),  // tokens
            file('NO_FILE'),  // rt_model
            file('NO_FILE'),  // im_model
            file('NO_FILE'),  // fr_model
            file('NO_FILE')   // fasta_filter
        )

        // Convert to parquet
        CONVERT_LIBRARY_DEFAULT(
            GENERATE_LIBRARY_DEFAULT.out.library,
            'standard_default/library',
            fasta_file,
            cut,
            missed_cleavages
        )

        // Create samples channel
        def samples_ch_default = createSamplesChannel(samples_list, 'standard_default')

        // Quantify
        QUANTIFY_DEFAULT(
            samples_ch_default,
            CONVERT_LIBRARY_DEFAULT.out.parquet_library,
            fasta_file,
            Channel.value(ref_library_file),
            mbr
        )
    }

    // ========================================
    // CONDITION 2: Standard search with preset A
    // ========================================
    if (run_preset_a) {
        log.info "Running: standard_presetA (${model_preset_a})"

        // Resolve model files for preset A
        def models_a = resolveModelFiles([model_preset: model_preset_a], projectDir)

        // Generate library with preset A models
        GENERATE_LIBRARY_PRESET_A(
            fasta_file,
            'library',
            'standard_presetA/library',
            models_a.tokens,
            models_a.rt_model,
            models_a.im_model,
            models_a.fr_model,
            file('NO_FILE')   // fasta_filter
        )

        // Convert to parquet
        CONVERT_LIBRARY_PRESET_A(
            GENERATE_LIBRARY_PRESET_A.out.library,
            'standard_presetA/library',
            fasta_file,
            cut,
            missed_cleavages
        )

        // Create samples channel
        def samples_ch_preset_a = createSamplesChannel(samples_list, 'standard_presetA')

        // Quantify
        QUANTIFY_PRESET_A(
            samples_ch_preset_a,
            CONVERT_LIBRARY_PRESET_A.out.parquet_library,
            fasta_file,
            Channel.value(ref_library_file),
            mbr
        )
    }

    // ========================================
    // CONDITION 3: Standard search with preset B
    // ========================================
    if (run_preset_b) {
        log.info "Running: standard_presetB (${model_preset_b})"

        // Resolve model files for preset B
        def models_b = resolveModelFiles([model_preset: model_preset_b], projectDir)

        // Generate library with preset B models
        GENERATE_LIBRARY_PRESET_B(
            fasta_file,
            'library',
            'standard_presetB/library',
            models_b.tokens,
            models_b.rt_model,
            models_b.im_model,
            models_b.fr_model,
            file('NO_FILE')   // fasta_filter
        )

        // Convert to parquet
        CONVERT_LIBRARY_PRESET_B(
            GENERATE_LIBRARY_PRESET_B.out.library,
            'standard_presetB/library',
            fasta_file,
            cut,
            missed_cleavages
        )

        // Create samples channel
        def samples_ch_preset_b = createSamplesChannel(samples_list, 'standard_presetB')

        // Quantify
        QUANTIFY_PRESET_B(
            samples_ch_preset_b,
            CONVERT_LIBRARY_PRESET_B.out.parquet_library,
            fasta_file,
            Channel.value(ref_library_file),
            mbr
        )
    }

    // Note: Iterative search would require importing the full iterative_quant workflow
    // For simplicity, we recommend running iterative_quant separately and comparing results
    if (run_iterative) {
        log.warn "Iterative search comparison not yet implemented in this workflow."
        log.warn "Run iterative_quant.nf separately with --outdir ${params.outdir}/iterative_default"
    }
}

workflow.onComplete {
    log.info ""
    log.info "Method Evaluation completed at: ${workflow.complete}"
    log.info "Execution status: ${workflow.success ? 'Success' : 'Failed'}"
    log.info "Duration: ${workflow.duration}"
    log.info ""
    log.info "Results in: ${params.outdir}/"
    log.info ""
    log.info "Next step: Extract and compare metrics"
    log.info "  python bin/extract_metrics.py ${params.outdir} --output ${params.outdir}/metrics/summary.tsv"
    log.info ""
}

// Default entry point
workflow {
    EVALUATE_METHODS()
}
