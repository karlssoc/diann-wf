#!/usr/bin/env nextflow

/*
 * Model Evaluation Workflow
 *
 * Evaluates pre-trained models from ./models by running full iterative
 * quantification with MBR. Supports comparing multiple model presets
 * in parallel and generates RT/IM accuracy metrics.
 *
 * For each model preset:
 * 1. Library generation: Generate predicted library using model preset
 * 2. Calibration: InfinDIA pre-search + peptide-level subsetting
 * 3. Identification: Quantify WITHOUT MBR
 * 4. Subsetting: Reduce library to identified Protein.Groups
 * 5. Final quantification: Quantify WITH MBR
 * 6. Accuracy report: RT/IM correlation metrics and plots
 *
 * Required parameters:
 *   --fasta           Path to FASTA file
 *   --samples         Sample definitions (id, dir, file_type, recursive)
 *   --model_presets   List of model preset names to evaluate
 *
 * Optional parameters:
 *   --calibration_files  Number of MS files for calibration (default: 5)
 *   --instrument_type    'hfx' or 'timstof' for mass accuracy presets
 */

nextflow.enable.dsl = 2

// Include modules
include { QUANTIFY as QUANTIFY_IDENTIFY } from '../modules/quantify'
include { QUANTIFY as QUANTIFY_FINAL } from '../modules/quantify'
include { SUBSET_LIBRARY } from '../modules/subset_library'
include { SUBSET_LIBRARY_PEPTIDE } from '../modules/subset_library_peptide'
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
    Model Evaluation Workflow

    Evaluates pre-trained models by running full iterative quantification
    with MBR. Compares multiple model presets and generates accuracy metrics.

    Usage:
      nextflow run workflows/evaluate_models.nf -params-file <config.yaml> -profile <profile>

    Required Parameters:
      --fasta PATH            FASTA sequence database
      --samples LIST          Sample definitions [{id, dir, file_type, recursive}]
      --model_presets LIST    Model preset names to evaluate
                              Example: ['hfx-vneo-50spd', 'hfx-nlc-120min-260128']

    Optional Parameters:
      --calibration_files N   Number of MS files for calibration (default: 5)
      --instrument_type TYPE  Mass accuracy presets: 'hfx' or 'timstof'
      --pre_select N          Limit precursors in InfinDIA (default: 0 = unlimited)
      --mbr_identify BOOL     Enable MBR in identification stage (default: false)
      --mbr_final BOOL        Enable MBR in final stage (default: true)
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
      ├── <preset_name>/
      │   ├── library/              # Generated library
      │   ├── calibration/          # Calibration library
      │   ├── identification/       # Identification stage results
      │   ├── subset_library/       # Subset library
      │   ├── final/                # Final quantification
      │   └── accuracy/             # RT/IM accuracy metrics
      └── comparison/               # Cross-preset comparison summary

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

// Sub-workflow for evaluating a single model preset
workflow EVALUATE_PRESET {
    take:
    preset_name          // Model preset name
    fasta_file           // FASTA file
    samples_list         // List of sample definitions
    calibration_files_ch // Calibration MS files
    instrument_type      // Instrument type for mass accuracy
    pre_select           // Pre-select limit
    mbr_identify         // MBR for identification
    mbr_final            // MBR for final

    main:
    log.info "============================================"
    log.info "Evaluating model preset: ${preset_name}"
    log.info "============================================"

    // Resolve model files for this preset
    def models_dir = findModelsDir(projectDir)
    def tokens_file = file("${models_dir}/${preset_name}/dict.txt")
    def rt_model_file = file("${models_dir}/${preset_name}/tuned_rt.pt")
    def im_model_file = file("${models_dir}/${preset_name}/tuned_im.pt")
    def fr_model_file = file("${models_dir}/${preset_name}/tuned_fr.pt")

    // Use NO_FILE for missing models
    tokens_file = tokens_file.exists() ? tokens_file : file('NO_FILE')
    rt_model_file = rt_model_file.exists() ? rt_model_file : file('NO_FILE')
    im_model_file = im_model_file.exists() ? im_model_file : file('NO_FILE')
    fr_model_file = fr_model_file.exists() ? fr_model_file : file('NO_FILE')

    log.info "  Tokens : ${tokens_file.name != 'NO_FILE' ? 'yes' : 'no'}"
    log.info "  RT     : ${rt_model_file.name != 'NO_FILE' ? 'yes' : 'no'}"
    log.info "  IM     : ${im_model_file.name != 'NO_FILE' ? 'yes' : 'no'}"
    log.info "  FR     : ${fr_model_file.name != 'NO_FILE' ? 'yes' : 'no'}"

    // 1. InfinDIA presearch FIRST (library-free search to identify peptides)
    INFINDIA_PRESEARCH(
        calibration_files_ch,
        fasta_file,
        "${preset_name}/calibration",
        instrument_type,
        pre_select
    )

    // 2. Extract stripped sequences for fasta-filter (speeds up library generation)
    EXTRACT_SEQUENCES(
        INFINDIA_PRESEARCH.out.report
    )

    // 3. Generate library with preset models (filtered to identified peptides only)
    GENERATE_LIBRARY(
        fasta_file,
        "${preset_name}_library",
        "${preset_name}/library",
        tokens_file,
        rt_model_file,
        im_model_file,
        fr_model_file,
        EXTRACT_SEQUENCES.out.sequences
    )

    // 4. Convert library to parquet
    def cut = params.library?.cut ?: 'K*,R*'
    def missed_cleavages = params.library?.missed_cleavages ?: 1

    CONVERT_LIBRARY(
        GENERATE_LIBRARY.out.library,
        "${preset_name}/library",
        fasta_file,
        cut,
        missed_cleavages
    )

    // 5. Subset library by peptides for calibration (from presearch)
    SUBSET_LIBRARY_PEPTIDE(
        INFINDIA_PRESEARCH.out.report,
        CONVERT_LIBRARY.out.parquet_library,
        "${preset_name}/calibration",
        'calibration_lib'
    )

    // 5. Identification stage (without MBR)
    def samples_ch_identify = createSamplesChannel(samples_list, "${preset_name}/identification")

    QUANTIFY_IDENTIFY(
        samples_ch_identify,
        CONVERT_LIBRARY.out.parquet_library,
        fasta_file,
        SUBSET_LIBRARY_PEPTIDE.out.subset_library,
        mbr_identify
    )

    // 6. Subset library by Protein.Group
    def identify_report = QUANTIFY_IDENTIFY.out.report
        .first()
        .map { sample_id, report -> report }

    SUBSET_LIBRARY(
        identify_report,
        CONVERT_LIBRARY.out.parquet_library,
        "${preset_name}/subset_library",
        'subset_lib'
    )

    // 7. Final quantification (with MBR)
    def samples_ch_final = createSamplesChannel(samples_list, "${preset_name}/final")

    QUANTIFY_FINAL(
        samples_ch_final,
        SUBSET_LIBRARY.out.subset_library.first(),
        fasta_file,
        SUBSET_LIBRARY_PEPTIDE.out.subset_library,
        mbr_final
    )

    // 8. Generate accuracy report
    // Collect all final reports for this preset
    def final_reports = QUANTIFY_FINAL.out.report
        .map { sample_id, report -> report }
        .collect()

    MODEL_ACCURACY_REPORT(
        final_reports,
        preset_name,
        "${preset_name}/accuracy"
    )

    emit:
    accuracy_report = MODEL_ACCURACY_REPORT.out.metrics
    final_reports = QUANTIFY_FINAL.out.report
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
    def mbr_identify = params.mbr_identify != null ? params.mbr_identify : false
    def mbr_final = params.mbr_final != null ? params.mbr_final : true
    def instrument_type = params.instrument_type ?: ''
    def pre_select = params.pre_select ?: 0
    def calibration_files_count = params.calibration_files ?: 5

    // Log workflow parameters
    log.info ""
    log.info "Model Evaluation Workflow"
    log.info "========================="
    log.info "FASTA          : ${params.fasta}"
    log.info "Samples        : ${samples_list.size()}"
    log.info "Model presets  : ${model_presets.join(', ')}"
    log.info "MBR (identify) : ${mbr_identify}"
    log.info "MBR (final)    : ${mbr_final}"
    log.info "Calibration    : ${calibration_files_count} files"
    log.info "Instrument     : ${instrument_type ?: 'auto'}"
    log.info "Output dir     : ${params.outdir}"
    log.info ""

    // Prepare calibration files (same for all presets)
    def first_sample = samples_list[0]
    def calibration_sample_dir = file(first_sample.dir)
    def file_type = first_sample.file_type ?: 'raw'

    if (!calibration_sample_dir.exists()) {
        log.error "ERROR: Calibration sample directory not found: ${first_sample.dir}"
        exit 1
    }

    // Find MS files
    def all_ms_files = calibration_sample_dir.listFiles().findAll { f ->
        if (file_type == 'd') {
            return f.isDirectory() && f.name.endsWith('.d')
        } else {
            return f.isFile() && f.name.toLowerCase().endsWith(".${file_type.toLowerCase()}")
        }
    }

    if (all_ms_files.size() == 0) {
        log.error "ERROR: No ${file_type} files found in ${calibration_sample_dir}"
        exit 1
    }

    // Shuffle and select calibration files
    Collections.shuffle(all_ms_files)
    def selected_files = all_ms_files.take(calibration_files_count)
    log.info "Selected ${selected_files.size()} of ${all_ms_files.size()} files for calibration"

    def calibration_files_ch = Channel.fromList(selected_files).collect()

    // Create channel of presets with all required context
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

    // 1. InfinDIA presearch (same for all presets - library-free)
    INFINDIA_PRESEARCH(
        calibration_files_ch,
        fasta_file,
        'presearch',
        instrument_type,
        pre_select
    )

    // 2. Extract sequences for fasta-filter
    EXTRACT_SEQUENCES(
        INFINDIA_PRESEARCH.out.report
    )

    // 3. Generate library for each preset (with fasta-filter)
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

    // 4. Convert library to parquet (track preset)
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

    // 5. Subset library by peptides for calibration (per preset)
    SUBSET_LIBRARY_PEPTIDE(
        INFINDIA_PRESEARCH.out.report,
        parquet_libs_with_preset.map { preset, lib -> lib },
        parquet_libs_with_preset.map { preset, lib -> preset + '/calibration' },
        'calibration_lib'
    )

    // Track preset with calibration library
    def calibration_libs_with_preset = SUBSET_LIBRARY_PEPTIDE.out.subset_library
        .map { lib ->
            // Extract preset from parent directory path
            def preset = lib.parent.parent.name
            tuple(preset, lib)
        }

    // 6. Create samples channel for identification - pair with preset-specific library
    // For each preset, create sample tuples joined with the correct library
    def samples_with_libs_ch = parquet_libs_with_preset
        .combine(calibration_libs_with_preset, by: 0)  // Join by preset name
        .flatMap { preset, lib, cal_lib ->
            samples_list.collect { sample ->
                def sample_dir = file(sample.dir)
                // tuple: sample_id, sample_dir, file_type, subdir, recursive, file_count (optional), library, calibration_lib
                tuple(sample.id, sample_dir, sample.file_type ?: 'raw', "${preset}/identification", sample.recursive ?: false, lib, cal_lib)
            }
        }

    QUANTIFY_IDENTIFY(
        samples_with_libs_ch.map { id, dir, ft, subdir, rec, lib, cal -> tuple(id, dir, ft, subdir, rec) },
        samples_with_libs_ch.map { id, dir, ft, subdir, rec, lib, cal -> lib },
        fasta_file,
        samples_with_libs_ch.map { id, dir, ft, subdir, rec, lib, cal -> cal },
        mbr_identify
    )

    // 7. Subset library by Protein.Group (per preset)
    // Group identification reports by preset, then subset each preset's library
    def identify_reports_with_preset = QUANTIFY_IDENTIFY.out.report
        .map { sample_id, report ->
            // Extract preset from report path: results/preset/identification/sample_id/report.parquet
            def preset = report.parent.parent.parent.name
            tuple(preset, report)
        }

    // Join reports with libraries by preset
    def subset_input = identify_reports_with_preset
        .combine(parquet_libs_with_preset, by: 0)
        .map { preset, report, lib -> tuple(preset, report, lib) }

    SUBSET_LIBRARY(
        subset_input.map { preset, report, lib -> report },
        subset_input.map { preset, report, lib -> lib },
        subset_input.map { preset, report, lib -> preset + '/subset_library' },
        'subset_lib'
    )

    // Track preset with subset library
    def subset_libs_with_preset = SUBSET_LIBRARY.out.subset_library
        .map { lib ->
            def preset = lib.parent.parent.name
            tuple(preset, lib)
        }

    // 8. Final quantification with MBR (per preset)
    def samples_final_with_libs_ch = subset_libs_with_preset
        .combine(calibration_libs_with_preset, by: 0)  // Join by preset name
        .flatMap { preset, subset_lib, cal_lib ->
            samples_list.collect { sample ->
                def sample_dir = file(sample.dir)
                tuple(sample.id, sample_dir, sample.file_type ?: 'raw', "${preset}/final", sample.recursive ?: false, subset_lib, cal_lib)
            }
        }

    QUANTIFY_FINAL(
        samples_final_with_libs_ch.map { id, dir, ft, subdir, rec, lib, cal -> tuple(id, dir, ft, subdir, rec) },
        samples_final_with_libs_ch.map { id, dir, ft, subdir, rec, lib, cal -> lib },
        fasta_file,
        samples_final_with_libs_ch.map { id, dir, ft, subdir, rec, lib, cal -> cal },
        mbr_final
    )

    // 9. Generate accuracy report for each preset
    // Group final reports by preset
    def final_reports_with_preset = QUANTIFY_FINAL.out.report
        .map { sample_id, report ->
            def preset = report.parent.parent.parent.name
            tuple(preset, report)
        }
        .groupTuple()

    MODEL_ACCURACY_REPORT(
        final_reports_with_preset.map { preset, reports -> reports },
        final_reports_with_preset.map { preset, reports -> preset },
        final_reports_with_preset.map { preset, reports -> preset + '/accuracy' }
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
        log.info "    Library:        ${params.outdir}/${preset}/library/"
        log.info "    Calibration:    ${params.outdir}/${preset}/calibration/"
        log.info "    Identification: ${params.outdir}/${preset}/identification/"
        log.info "    Final:          ${params.outdir}/${preset}/final/"
        log.info "    Accuracy:       ${params.outdir}/${preset}/accuracy/"
    }
    log.info ""
}
