#!/usr/bin/env nextflow

/*
 * Model Evaluation Workflow (Simplified)
 *
 * Evaluates pre-trained models from ./models by comparing iRT prediction
 * accuracy. Supports comparing multiple model presets in parallel.
 *
 * Simplified flow (no calibration needed for model accuracy comparison):
 * 1. InfinDIA presearch: Library-free peptide identification (shared)
 * 2. Library generation: Generate predicted library per model preset
 * 3. Quantification: Single-stage quantification per preset
 * 4. Accuracy report: iRT/RT/IM correlation metrics per preset
 *
 * Required parameters:
 *   --fasta           Path to FASTA file
 *   --samples         Sample definitions (id, dir, file_type, recursive)
 *   --model_presets   List of model preset names to evaluate
 *
 * Optional parameters:
 *   --calibration_files  Number of MS files for presearch (default: 5)
 *   --instrument_type    'hfx' or 'timstof' for mass accuracy presets
 */

nextflow.enable.dsl = 2

// Include modules
include { QUANTIFY } from '../modules/quantify'
include { CONVERT_LIBRARY } from '../modules/convert_library'
include { GENERATE_LIBRARY } from '../modules/library'
include { INFINDIA_PRESEARCH } from '../modules/infindia_presearch'
include { EXTRACT_SEQUENCES } from '../modules/extract_sequences'
include { MODEL_ACCURACY_REPORT } from '../modules/model_accuracy_report'

// Include shared utilities
include { createSamplesChannel } from '../lib/samples'
include { resolveModelFiles; logModelInfo; validateModelPreset; listAvailablePresets; findModelsDir } from '../lib/models'

// Help message
def helpMessage() {
    log.info"""
    Model Evaluation Workflow (Simplified)

    Evaluates pre-trained models by comparing iRT prediction accuracy.
    Compares multiple model presets and generates accuracy metrics.

    Usage:
      nextflow run workflows/evaluate_models.nf -params-file <config.yaml> -profile <profile>

    Required Parameters:
      --fasta PATH            FASTA sequence database
      --samples LIST          Sample definitions [{id, dir, file_type, recursive}]
      --model_presets LIST    Model preset names to evaluate
                              Example: ['default', 'hfx-vneo-50spd']

    Optional Parameters:
      --calibration_files N   Number of MS files for presearch (default: 5)
      --instrument_type TYPE  Mass accuracy presets: 'hfx' or 'timstof'
      --pre_select N          Limit precursors in InfinDIA (default: 0 = unlimited)
      --mbr BOOL              Enable MBR in quantification (default: true)
      --outdir PATH           Output directory (default: results)

    Library Generation Parameters:
      --library.min_fr_mz 200      Min fragment m/z
      --library.max_fr_mz 1800     Max fragment m/z
      --library.min_pep_len 7      Min peptide length
      --library.max_pep_len 30     Max peptide length
      --library.min_pr_mz 350      Min precursor m/z
      --library.max_pr_mz 1650     Max precursor m/z

    Output Structure:
      results/
      ├── presearch/              # Shared InfinDIA presearch results
      └── <preset_name>/
          ├── library/            # Generated library
          ├── quant/              # Quantification results
          └── accuracy/           # iRT/RT/IM accuracy metrics

    Available Model Presets:
    """.stripIndent()

    // List available presets
    def presets = listAvailablePresets(projectDir)
    if (presets.size() > 0) {
        presets.each { preset ->
            log.info "      - ${preset}"
        }
    } else {
        log.info "      (no presets found in models/)"
    }
    log.info ""
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
if (!params.model_presets) {
    log.error "ERROR: --model_presets parameter is required"
    helpMessage()
    exit 1
}

// Main workflow
workflow {
    // Validate input files
    def fasta_file = file(params.fasta)
    if (!fasta_file.exists()) {
        log.error "ERROR: FASTA file not found: ${params.fasta}"
        exit 1
    }

    // Get samples list
    def samples_list = params.samples

    // Get model presets to evaluate
    def model_presets = params.model_presets
    if (!(model_presets instanceof List)) {
        model_presets = [model_presets]
    }

    // Validate all presets exist (skip validation for 'default')
    model_presets.each { preset ->
        if (preset != 'default' && !validateModelPreset(preset, projectDir)) {
            exit 1
        }
    }

    // Settings
    def mbr = params.mbr != null ? params.mbr : true
    def instrument_type = params.instrument_type ?: ''
    def pre_select = params.pre_select ?: 0
    def calibration_files_count = params.calibration_files ?: 5

    // Log workflow parameters
    log.info ""
    log.info "Model Evaluation Workflow (Simplified)"
    log.info "======================================"
    log.info "FASTA          : ${params.fasta}"
    log.info "Samples        : ${samples_list.size()}"
    log.info "Model presets  : ${model_presets.join(', ')}"
    log.info "MBR            : ${mbr}"
    log.info "Presearch files: ${calibration_files_count}"
    log.info "Instrument     : ${instrument_type ?: 'auto'}"
    log.info "Output dir     : ${params.outdir}"
    log.info ""

    // Prepare presearch files (same for all presets)
    def first_sample = samples_list[0]
    def sample_dir = file(first_sample.dir)
    def file_type = first_sample.file_type ?: 'raw'

    if (!sample_dir.exists()) {
        log.error "ERROR: Sample directory not found: ${first_sample.dir}"
        exit 1
    }

    // Find MS files
    def all_ms_files = sample_dir.listFiles().findAll { f ->
        if (file_type == 'd') {
            return f.isDirectory() && f.name.endsWith('.d')
        } else {
            return f.isFile() && f.name.toLowerCase().endsWith(".${file_type.toLowerCase()}")
        }
    }

    if (all_ms_files.size() == 0) {
        log.error "ERROR: No ${file_type} files found in ${sample_dir}"
        exit 1
    }

    // Shuffle and select presearch files
    Collections.shuffle(all_ms_files)
    def selected_files = all_ms_files.take(calibration_files_count)
    log.info "Selected ${selected_files.size()} of ${all_ms_files.size()} files for presearch"

    def presearch_files_ch = Channel.fromList(selected_files).collect()

    // Create channel of presets with model files
    // Special preset "default" uses NO_FILE for all models (standard DIA-NN predictions)
    def presets_ch = Channel.fromList(model_presets)
        .map { preset_name ->
            if (preset_name == 'default') {
                // Use default DIA-NN models (no tuning)
                tuple(
                    preset_name,
                    file('NO_FILE'),
                    file('NO_FILE'),
                    file('NO_FILE'),
                    file('NO_FILE')
                )
            } else {
                def models_dir = findModelsDir(projectDir)
                def tokens = file("${models_dir}/${preset_name}/dict.txt")
                def rt = file("${models_dir}/${preset_name}/tuned_rt.pt")
                def im = file("${models_dir}/${preset_name}/tuned_im.pt")
                def fr = file("${models_dir}/${preset_name}/tuned_fr.pt")
                tuple(
                    preset_name,
                    tokens.exists() ? tokens : file('NO_FILE'),
                    rt.exists() ? rt : file('NO_FILE'),
                    im.exists() ? im : file('NO_FILE'),
                    fr.exists() ? fr : file('NO_FILE')
                )
            }
        }

    // =========================================================================
    // Step 1: InfinDIA presearch (shared across all presets - library-free)
    // =========================================================================
    INFINDIA_PRESEARCH(
        presearch_files_ch,
        fasta_file,
        'presearch',
        instrument_type,
        pre_select
    )

    // Extract sequences for fasta-filter (speeds up library generation)
    EXTRACT_SEQUENCES(
        INFINDIA_PRESEARCH.out.report
    )

    // =========================================================================
    // Step 2: Generate library for each preset (with fasta-filter)
    // =========================================================================
    def cut = params.library?.cut ?: 'K*,R*'
    def missed_cleavages = params.library?.missed_cleavages ?: 1

    presets_ch
        .combine(EXTRACT_SEQUENCES.out.sequences)
        .map { preset_name, tokens, rt, im, fr, seqs ->
            tuple(preset_name, tokens, rt, im, fr, seqs)
        }
        .set { preset_with_filter_ch }

    GENERATE_LIBRARY(
        fasta_file,
        preset_with_filter_ch.map { it[0] + '_library' },  // library_name
        preset_with_filter_ch.map { it[0] + '/library' },  // subdir
        preset_with_filter_ch.map { it[1] },  // tokens
        preset_with_filter_ch.map { it[2] },  // rt
        preset_with_filter_ch.map { it[3] },  // im
        preset_with_filter_ch.map { it[4] },  // fr
        preset_with_filter_ch.map { it[5] }   // fasta_filter
    )

    // Track preset name with generated library
    // Extract preset name from library filename: "preset_library.predicted.speclib" -> "preset"
    def libraries_with_preset = GENERATE_LIBRARY.out.library
        .map { lib ->
            def preset = lib.baseName.replace('_library.predicted', '')
            tuple(preset, lib)
        }

    // Convert library to parquet (track preset)
    CONVERT_LIBRARY(
        libraries_with_preset.map { preset, lib -> lib },
        libraries_with_preset.map { preset, lib -> preset + '/library' },
        fasta_file,
        cut,
        missed_cleavages
    )

    // Track preset with converted library
    def parquet_libs_with_preset = CONVERT_LIBRARY.out.parquet_library
        .map { lib ->
            def preset = lib.baseName.replace('_library.predicted', '')
            tuple(preset, lib)
        }

    // =========================================================================
    // Step 3: Quantification (single stage per preset)
    // =========================================================================
    // Create samples channel paired with preset-specific library
    // Use preset__sample_id format to track preset through QUANTIFY process
    def samples_with_libs_ch = parquet_libs_with_preset
        .flatMap { preset, lib ->
            samples_list.collect { sample ->
                def sample_dir_path = file(sample.dir)
                def ft = sample.file_type ?: 'raw'
                // Count MS files in directory
                def file_count = sample_dir_path.listFiles().findAll { f ->
                    if (ft == 'd') {
                        return f.isDirectory() && f.name.endsWith('.d')
                    } else {
                        return f.isFile() && f.name.toLowerCase().endsWith(".${ft.toLowerCase()}")
                    }
                }.size()
                // Encode preset in sample_id for tracking: "preset__original_id"
                def unique_id = "${preset}__${sample.id}"
                tuple(unique_id, sample_dir_path, ft, "${preset}/quant", sample.recursive ?: false, file_count, lib)
            }
        }

    // For model evaluation, no calibration library needed
    QUANTIFY(
        samples_with_libs_ch.map { id, dir, ft, subdir, rec, fc, lib -> tuple(id, dir, ft, subdir, rec, fc) },
        samples_with_libs_ch.map { id, dir, ft, subdir, rec, fc, lib -> lib },
        fasta_file,
        file('NO_FILE'),
        mbr
    )

    // =========================================================================
    // Step 4: Generate accuracy report for each preset
    // =========================================================================
    // Group reports by preset
    def reports_with_preset = QUANTIFY.out.report
        .map { sample_id, report ->
            // Extract preset from sample_id: "preset__original_sample_id" -> "preset"
            def preset = sample_id.split('__')[0]
            tuple(preset, report)
        }
        .groupTuple()

    MODEL_ACCURACY_REPORT(
        reports_with_preset.map { preset, reports -> reports },
        reports_with_preset.map { preset, reports -> preset },
        reports_with_preset.map { preset, reports -> preset + '/accuracy' }
    )
}

workflow.onComplete {
    log.info ""
    log.info "Model Evaluation completed at: ${workflow.complete}"
    log.info "Execution status: ${workflow.success ? 'Success' : 'Failed'}"
    log.info "Duration: ${workflow.duration}"
    log.info ""
    log.info "Results by preset:"
    params.model_presets.each { preset ->
        log.info "  ${preset}:"
        log.info "    Library:  ${params.outdir}/${preset}/library/"
        log.info "    Quant:    ${params.outdir}/${preset}/quant/"
        log.info "    Accuracy: ${params.outdir}/${preset}/accuracy/"
    }
    log.info ""
}
