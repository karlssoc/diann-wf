#!/usr/bin/env nextflow

/*
========================================================================================
    DIANN Workflow: Presearch + Quantification
========================================================================================
    Simplified search space reduction workflow:
    1. Generate spectral library from FASTA
    2. Convert library to parquet (for subsetting)
    3. Select N largest MS files for presearch
    4. Presearch: quantify N files against full library (no MBR, relaxed FDR)
    5. Subset library to detected Protein.Groups
    6. Quantify all samples against subset library (with MBR)

    This approach captures ~91% of protein groups with just 5 files (largest by size),
    avoiding the need to search ALL files for identification (as in ITERATIVE_QUANT).

    Use case: Large cohorts where searching the full proteome is too slow, but you
    don't have a pre-filtered FASTA for your sample type.
----------------------------------------------------------------------------------------
*/

nextflow.enable.dsl = 2

// Include modules
include { GENERATE_LIBRARY } from '../modules/library'
include { GENERATE_LIBRARY as GENERATE_LIBRARY_PRESEARCH } from '../modules/library'
include { CONVERT_LIBRARY } from '../modules/convert_library'
include { CONVERT_LIBRARY as CONVERT_LIBRARY_PRESEARCH } from '../modules/convert_library'
include { QUANTIFY as QUANTIFY_PRESEARCH } from '../modules/quantify'
include { QUANTIFY as QUANTIFY_FINAL } from '../modules/quantify'
include { SUBSET_LIBRARY } from '../modules/subset_library'

// Include shared utilities
include { parseSamples; createSamplesChannel } from '../lib/samples'
include { resolveModelFiles; logModelInfo } from '../lib/models'

/*
========================================================================================
    LOCAL PROCESS: Create presearch directory from selected files
========================================================================================
*/

process SELECT_PRESEARCH_FILES {
    publishDir "${params.outdir}/presearch", mode: 'copy', pattern: 'selection.log', overwrite: true

    input:
    path ms_files    // N selected files (staged as symlinks by Nextflow)

    output:
    path "presearch_dir", emit: presearch_dir
    path "selection.log", emit: log

    script:
    """
    mkdir presearch_dir
    for f in ${ms_files}; do
        ln -s "\$(realpath "\$f")" presearch_dir/
    done

    echo "Selected files for presearch:" > selection.log
    ls -lhS presearch_dir/ >> selection.log
    TOTAL=\$(ls presearch_dir/ | wc -l | tr -d ' ')
    echo "" >> selection.log
    echo "Total: \$TOTAL files" >> selection.log
    """
}

/*
========================================================================================
    WORKFLOW
========================================================================================
*/

workflow PRESEARCH_AND_QUANTIFY {
    // Validate required parameters (inside workflow block so they only run when this entry is selected)
    if (!params.fasta) {
        error "ERROR: Missing required parameter --fasta"
    }
    if (!params.samples) {
        error "ERROR: Missing required parameter --samples"
    }

    // Parse samples using shared utility
    def samples_list = parseSamples(params.samples)

    // Set defaults
    def library_name = params.library_name ?: 'library'
    def library_subdir = params.library_subdir ?: 'library'
    def presearch_n = params.presearch_files ?: 5
    def qvalue_presearch = params.qvalue_presearch ?: 0.05
    def dual_library = params.presearch_library ? true : false

    // Create file objects
    def fasta_file = file(params.fasta)
    if (!fasta_file.exists()) {
        error "ERROR: FASTA file not found: ${params.fasta}"
    }

    // Resolve model files using shared utility
    def models = resolveModelFiles(params, projectDir)

    // Optional reference library for batch correction
    def ref_library_file = params.ref_library ? file(params.ref_library) : file('NO_FILE')

    // Determine file type from first sample (all samples assumed same type)
    def file_type = samples_list[0].file_type ?: 'dia'

    /*
    ========================================================================================
        FILE SELECTION: Find N largest MS files across all samples
    ========================================================================================
    */

    def all_ms_files = []
    samples_list.each { sample ->
        def dir = file(sample.dir)
        def ft = sample.file_type ?: 'dia'

        if (!dir.exists()) {
            error "ERROR: Sample directory not found: ${sample.dir}"
        }

        dir.listFiles()?.each { f ->
            if (ft == 'd') {
                if (f.isDirectory() && f.name.endsWith('.d')) {
                    all_ms_files << f
                }
            } else {
                if (f.isFile() && f.name.toLowerCase().endsWith(".${ft}")) {
                    all_ms_files << f
                }
            }
        }
    }

    // Sort by size descending and take top N
    all_ms_files.sort { -it.size() }
    def n_select = Math.min(presearch_n as int, all_ms_files.size())
    def selected_files = all_ms_files.take(n_select)

    log.info ""
    log.info "DIANN Presearch + Quantification Workflow"
    log.info "=========================================="
    log.info "FASTA         : ${params.fasta}"
    log.info "Samples       : ${samples_list.size()}"
    log.info "Total MS files: ${all_ms_files.size()}"
    log.info "Presearch     : ${n_select} largest files (of ${all_ms_files.size()})"
    log.info "Q-value (pre) : ${qvalue_presearch}"
    if (dual_library) {
        log.info "Dual library  : enabled (presearch_library overrides for presearch)"
    }
    log.info "Output dir    : ${params.outdir}"
    logModelInfo(models, params)
    log.info ""
    log.info "Selected presearch files:"
    selected_files.each { f ->
        log.info "  ${f.name} (${String.format('%.0f', f.size() / 1048576.0)} MB)"
    }
    log.info ""

    /*
    ========================================================================================
        STEP 1-2: Generate and Convert Libraries
        When presearch_library is set, generates TWO libraries in parallel:
          - Presearch library (narrow, e.g. charge 2-3): for fast protein identification
          - Final library (broad, e.g. charge 1-4): subset by detected proteins for quant
        When presearch_library is not set, generates a single library for both stages.
    ========================================================================================
    */

    def final_search_params = params.library ?: [:]
    def final_cut = final_search_params.cut ?: 'K*,R*,!*P'
    def final_mc = final_search_params.missed_cleavages ?: 1

    // Library channels (set below based on single/dual mode)
    def library_for_presearch = null
    def library_for_final = null

    if (dual_library) {
        // Dual library mode: presearch_library overrides library for presearch
        def presearch_search_params = (params.library ?: [:]) + (params.presearch_library ?: [:])
        def presearch_cut = presearch_search_params.cut ?: 'K*,R*,!*P'
        def presearch_mc = presearch_search_params.missed_cleavages ?: 1

        log.info "Generating dual libraries from FASTA..."

        // Generate presearch (narrow) library
        GENERATE_LIBRARY_PRESEARCH(
            fasta_file,
            "${library_name}_presearch",
            'library/presearch',
            presearch_search_params,
            models.tokens,
            models.rt_model,
            models.im_model,
            models.fr_model,
            file('NO_FILE')
        )

        CONVERT_LIBRARY_PRESEARCH(
            GENERATE_LIBRARY_PRESEARCH.out.library,
            'library/presearch',
            fasta_file,
            presearch_cut,
            presearch_mc
        )
        library_for_presearch = CONVERT_LIBRARY_PRESEARCH.out.parquet_library.first()

        // Generate final (broad) library — runs in parallel with presearch library
        GENERATE_LIBRARY(
            fasta_file,
            library_name,
            library_subdir,
            final_search_params,
            models.tokens,
            models.rt_model,
            models.im_model,
            models.fr_model,
            file('NO_FILE')
        )

        CONVERT_LIBRARY(
            GENERATE_LIBRARY.out.library,
            library_subdir,
            fasta_file,
            final_cut,
            final_mc
        )
        library_for_final = CONVERT_LIBRARY.out.parquet_library.first()
    } else {
        // Single library mode: same library for presearch and final
        GENERATE_LIBRARY(
            fasta_file,
            library_name,
            library_subdir,
            final_search_params,
            models.tokens,
            models.rt_model,
            models.im_model,
            models.fr_model,
            file('NO_FILE')
        )

        CONVERT_LIBRARY(
            GENERATE_LIBRARY.out.library,
            library_subdir,
            fasta_file,
            final_cut,
            final_mc
        )
        // Convert once to value channel for broadcasting to multiple consumers
        def single_lib = CONVERT_LIBRARY.out.parquet_library.first()
        library_for_presearch = single_lib
        library_for_final = single_lib
    }

    /*
    ========================================================================================
        STEP 3: Select Presearch Files (parallel with Steps 1-2)
    ========================================================================================
    */

    def selected_files_ch = Channel.fromList(selected_files).collect()

    SELECT_PRESEARCH_FILES(selected_files_ch)

    /*
    ========================================================================================
        STEP 4: Presearch - Quantify N files against full library
        No MBR, relaxed FDR to capture more Protein.Groups for subsetting
    ========================================================================================
    */

    def presearch_sample = SELECT_PRESEARCH_FILES.out.presearch_dir
        .map { dir -> tuple('presearch', dir, file_type, '', false, n_select) }

    QUANTIFY_PRESEARCH(
        presearch_sample,
        library_for_presearch,
        fasta_file,
        file('NO_FILE'),  // No ref library for presearch
        false,            // No MBR for presearch
        qvalue_presearch  // Relaxed FDR (default 0.05)
    )

    /*
    ========================================================================================
        STEP 5: Subset Library by detected Protein.Groups
    ========================================================================================
    */

    def presearch_reports = QUANTIFY_PRESEARCH.out.report
        .map { sample_id, report -> report }
        .collect()

    SUBSET_LIBRARY(
        presearch_reports,
        library_for_final,  // Subset the FINAL (broad) library
        'subset_library',
        'subset_lib'
    )

    /*
    ========================================================================================
        STEP 6: Final Quantification with subset library
    ========================================================================================
    */

    def subdir = params.quantify_subdir ?: 'quantification'
    def samples_ch = createSamplesChannel(samples_list, subdir)
    // Use mbr_final for the final stage (params.mbr defaults to false in nextflow.config
    // for identification stages; mbr_final defaults to true for final quantification)
    def mbr = params.mbr_final != null ? params.mbr_final : true

    // Convert to value channel at assignment time (avoids .first() warning downstream)
    def subset_lib = SUBSET_LIBRARY.out.subset_library.first()

    QUANTIFY_FINAL(
        samples_ch,
        subset_lib,
        fasta_file,
        ref_library_file,
        mbr,
        params.qvalue ?: 0  // Default FDR (0.01) for final quantification
    )

    // Emit outputs
    emit:
    library = GENERATE_LIBRARY.out.library
    library_parquet = library_for_final
    presearch_report = QUANTIFY_PRESEARCH.out.report
    subset_library = SUBSET_LIBRARY.out.subset_library
    quantify_reports = QUANTIFY_FINAL.out.report
    quantify_out_libs = QUANTIFY_FINAL.out.out_lib
    quantify_matrices = QUANTIFY_FINAL.out.matrices
}

/*
========================================================================================
    WORKFLOW INTROSPECTION
========================================================================================
*/

workflow.onComplete {
    def sample_count = params.samples instanceof List ? params.samples.size() : 0

    println """
    ========================================================================================
    Workflow completed!
    ========================================================================================
    Presearch files:   ${params.presearch_files ?: 5}
    Library generated: ${params.outdir}/${params.library_subdir ?: 'library'}/${params.library_name ?: 'library'}.predicted.speclib
    Subset library:    ${params.outdir}/subset_library/subset_lib.parquet
    Presearch results: ${params.outdir}/presearch/
    Final results:     ${params.outdir}/${params.quantify_subdir ?: 'quantification'}/<sample>/
    Samples quantified: ${sample_count}
    ========================================================================================
    """
}
