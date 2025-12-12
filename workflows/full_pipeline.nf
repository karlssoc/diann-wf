#!/usr/bin/env nextflow

/*
 * DIANN Full Pipeline Workflow
 *
 * Complete multi-stage workflow with flexible output organization:
 *   Stage 1: Generate library with default models → Quantify samples
 *   Tuning:  Fine-tune prediction models using specified sample
 *   Stage 2: Generate library with RT+IM tuned models → Quantify samples
 *   Stage 3: Generate library with RT+IM+FR tuned models → Quantify samples
 *
 * Output organization is configurable via params.output_organization:
 *   - 'by_stage' (default): Separate results by stage (stage1/, stage2/, stage3/)
 *   - 'flat': All results in same directory (samples may be overwritten)
 *   - custom: Use params.stage_names to define custom stage names
 *
 * Required parameters:
 *   --fasta              Path to FASTA file
 *   --samples            Sample definitions
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

    Workflow Control:
      --stages LIST             List of stages to run [default: [1,2,3]]
      --tune_after_stage INT    Which stage to tune after [default: 1]
      --tune_sample ID          Sample to use for model tuning [required if tuning]

    Output Organization:
      --output_organization STR Organization strategy: 'by_stage', 'flat' [default: 'by_stage']
      --stage_names MAP         Custom stage names (e.g., [1:'baseline', 2:'optimized'])

    Stage-Specific Settings:
      --stage_configs MAP       Per-stage configuration (DIANN version, library name, etc.)

    Examples:
      # Full 3-stage pipeline with separated outputs
      nextflow run workflows/full_pipeline.nf \\
        -params-file configs/full_pipeline.yaml \\
        -profile slurm

      # Run only stages 1 and 2
      nextflow run workflows/full_pipeline.nf \\
        -params-file configs/full_pipeline.yaml \\
        --stages '[1,2]' \\
        -profile slurm

      # Custom stage names
      nextflow run workflows/full_pipeline.nf \\
        -params-file configs/full_pipeline.yaml \\
        --stage_names '{1:"baseline", 2:"rt_im_optimized", 3:"full_optimized"}' \\
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

// Set defaults with backward compatibility
params.stages = params.stages ?: [1, 2, 3]
params.tune_after_stage = params.tune_after_stage ?: 1
params.output_organization = params.output_organization ?: 'by_stage'

// Backward compatibility: map old parameters to new structure
if (params.run_r1 != null || params.run_r2 != null || params.run_r3 != null) {
    log.warn "DEPRECATED: run_r1, run_r2, run_r3 are deprecated. Use --stages instead."
    def active_stages = []
    if (params.run_r1) active_stages.add(1)
    if (params.run_r2) active_stages.add(2)
    if (params.run_r3) active_stages.add(3)
    params.stages = active_stages
}

// Default stage names
def default_stage_names = [
    1: 'stage1',
    2: 'stage2',
    3: 'stage3'
]

// Default stage configurations
def default_stage_configs = [
    1: [
        diann_version: params.r1_diann_version ?: params.diann_version ?: '2.3.1',
        library_name: 'library_stage1',
        use_tuned_models: false
    ],
    2: [
        diann_version: params.r2_diann_version ?: params.diann_version ?: '2.2.0',
        library_name: 'library_stage2',
        use_tuned_models: true,
        use_fr_model: false
    ],
    3: [
        diann_version: params.r3_diann_version ?: params.diann_version ?: '2.3.1',
        library_name: 'library_stage3',
        use_tuned_models: true,
        use_fr_model: true
    ]
]

// Merge user-provided configurations
def stage_names = params.stage_names ?: default_stage_names
def stage_configs = params.stage_configs ?: default_stage_configs

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
    log.info "FASTA                : ${params.fasta}"
    log.info "Samples              : ${samples_list.size()}"
    log.info "Stages to run        : ${params.stages}"
    log.info "Output organization  : ${params.output_organization}"
    log.info "Tune after stage     : ${params.tune_after_stage}"
    log.info "Tune sample          : ${params.tune_sample ?: 'not specified'}"
    log.info ""

    // Initialize tuned model files
    def tuned_tokens = file('NO_FILE')
    def tuned_rt = file('NO_FILE')
    def tuned_im = file('NO_FILE')
    def tuned_fr = file('NO_FILE')
    def last_stage_out_libs = null

    // Execute stages
    params.stages.each { stage_num ->
        def config = stage_configs[stage_num]
        def stage_name = stage_names[stage_num]

        // Determine output subdirectory based on organization strategy
        def lib_subdir = params.output_organization == 'by_stage' ? "${stage_name}/library" : 'library'
        def quant_subdir = params.output_organization == 'by_stage' ? stage_name : ''

        log.info "Starting Stage ${stage_num}: ${stage_name}"
        log.info "  DIANN version: ${config.diann_version}"
        log.info "  Output subdir: ${quant_subdir ?: '(root)'}"

        // Generate library for this stage
        def use_tuned = config.use_tuned_models && tuned_tokens.name != 'NO_FILE'
        def fr_param = (use_tuned && config.use_fr_model) ? tuned_fr : file('NO_FILE')

        GENERATE_LIBRARY(
            fasta_file,
            config.library_name,
            lib_subdir,
            use_tuned ? tuned_tokens : file('NO_FILE'),
            use_tuned ? tuned_rt : file('NO_FILE'),
            use_tuned ? tuned_im : file('NO_FILE'),
            fr_param
        )

        // Create samples channel for this stage
        def samples_ch = Channel.fromList(samples_list)
            .map { sample ->
                def sample_id = sample.id
                def sample_dir = file(sample.dir)
                def file_type = sample.file_type ?: 'raw'
                def recursive = sample.recursive ?: false

                // Count MS files in directory for dynamic time allocation
                def file_extensions = ['.mzML', '.raw', '.d', '.wiff']
                def file_count = 0

                if (recursive) {
                    // Recursive counting: traverse all subdirectories
                    sample_dir.eachFileRecurse { file ->
                        if (file.isFile()) {
                            def extension = file.name.substring(file.name.lastIndexOf('.'))
                            if (file_extensions.contains(extension)) {
                                file_count++
                            }
                        } else if (file.isDirectory() && file.name.endsWith('.d')) {
                            // Count Bruker .d directories as one file
                            file_count++
                        }
                    }
                } else {
                    // Non-recursive: only immediate directory
                    sample_dir.listFiles().each { file ->
                        if (file.isFile()) {
                            def extension = file.name.substring(file.name.lastIndexOf('.'))
                            if (file_extensions.contains(extension)) {
                                file_count++
                            }
                        } else if (file.isDirectory() && file.name.endsWith('.d')) {
                            // Count Bruker .d directories as one file
                            file_count++
                        }
                    }
                }

                // Log file count for user awareness
                log.info "Sample ${sample_id}: Found ${file_count} MS files"

                tuple(sample_id, sample_dir, file_type, quant_subdir, recursive, file_count)
            }

        // Handle optional reference library for batch correction
        def ref_library_file = params.ref_library ? file(params.ref_library) : file('NO_FILE')

        // Quantify samples
        QUANTIFY(
            samples_ch,
            GENERATE_LIBRARY.out.library,
            fasta_file,
            ref_library_file
        )

        // Store out-lib results for tuning
        last_stage_out_libs = QUANTIFY.out.out_lib

        // Tune models after specified stage
        if (stage_num == params.tune_after_stage && params.tune_sample) {
            log.info "Starting Model Tuning after Stage ${stage_num}"
            log.info "  Using sample: ${params.tune_sample}"

            // Get the out-lib.parquet from the specified sample
            def tune_lib = last_stage_out_libs
                .filter { sample_id, lib -> sample_id == params.tune_sample }
                .map { sample_id, lib -> lib }

            // Determine tuning output subdirectory
            def tune_subdir = 'tuning'  // Tuning always goes to tuning/ directory

            // Tune models
            TUNE_MODELS(
                tune_lib,
                "tuned_models",
                tune_subdir
            )

            tuned_tokens = TUNE_MODELS.out.tokens
            tuned_rt = TUNE_MODELS.out.rt_model
            tuned_im = TUNE_MODELS.out.im_model
            tuned_fr = TUNE_MODELS.out.fr_model
        }
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
