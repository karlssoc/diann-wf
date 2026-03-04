#!/usr/bin/env nextflow

/*
========================================================================================
    DIANN Workflow: FASTA Subset + Quantification
========================================================================================
    Search space reduction by subsetting the FASTA (not the spectral library).

    Steps:
    1. Generate spectral library from full FASTA
    2. Select N largest MS files for presearch
    3. Presearch: quantify N files (no MBR, relaxed FDR) to identify present proteins
    4. Subset FASTA to Protein.Groups detected in presearch
    5. Generate fresh spectral library from subset FASTA (native speclib, no --reannotate)
    6. Quantify all samples against subset speclib (with MBR)

    Advantage over PRESEARCH_AND_QUANTIFY (which subsets the library parquet):
    - Native speclib from subset FASTA: full predicted spectral quality preserved
    - No --reannotate needed: DIA-NN uses library intensities/RTs directly
    - ~78% smaller library: faster quantification, less decoy competition
    - Better FDR calibration -> more proteins passing the 1% FDR filter

    Use case: Large cohorts where the full proteome inflates FDR due to irrelevant
    proteins. A presearch on N representative files captures the relevant protein subset.
----------------------------------------------------------------------------------------
*/

nextflow.enable.dsl = 2

// Include modules
include { GENERATE_LIBRARY                    } from '../modules/library'
include { GENERATE_LIBRARY as GENERATE_LIBRARY_FINAL } from '../modules/library'
include { QUANTIFY as QUANTIFY_PRESEARCH      } from '../modules/quantify'
include { QUANTIFY as QUANTIFY_FINAL          } from '../modules/quantify'
include { SUBSET_FASTA                        } from '../modules/subset_fasta'

// Include shared utilities
include { parseSamples; createSamplesChannel  } from '../lib/samples'
include { resolveModelFiles; logModelInfo     } from '../lib/models'

/*
========================================================================================
    LOCAL PROCESS: Create presearch directory from selected files
    Note: Duplicated from presearch_and_quantify.nf for workflow isolation.
========================================================================================
*/

process SELECT_PRESEARCH_FILES {
    publishDir "${params.outdir}/presearch", mode: 'copy', pattern: 'selection.log', overwrite: true

    input:
    path ms_files

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

workflow QUANTIFY_FASTA_SUBSET {
    if (!params.fasta) {
        error "ERROR: Missing required parameter --fasta"
    }
    if (!params.samples) {
        error "ERROR: Missing required parameter --samples"
    }

    def samples_list = parseSamples(params.samples)

    // Set defaults
    def library_name      = params.library_name     ?: 'library'
    def library_subdir    = params.library_subdir   ?: 'library'
    def presearch_n       = params.presearch_files  ?: 5
    def qvalue_presearch  = params.qvalue_presearch ?: 0.05

    def fasta_file = file(params.fasta)
    if (!fasta_file.exists()) {
        error "ERROR: FASTA file not found: ${params.fasta}"
    }

    def models          = resolveModelFiles(params, projectDir)
    def ref_library_file = params.ref_library ? file(params.ref_library) : file('NO_FILE')
    def file_type       = samples_list[0].file_type ?: 'dia'

    /*
    ========================================================================================
        FILE SELECTION: Find N largest MS files across all samples
    ========================================================================================
    */

    def all_ms_files = []
    samples_list.each { sample ->
        def dir = file(sample.dir)
        def ft  = sample.file_type ?: 'dia'
        if (!dir.exists()) {
            error "ERROR: Sample directory not found: ${sample.dir}"
        }
        dir.listFiles()?.each { f ->
            if (ft == 'd') {
                if (f.isDirectory() && f.name.endsWith('.d')) all_ms_files << f
            } else {
                if (f.isFile() && f.name.toLowerCase().endsWith(".${ft}")) all_ms_files << f
            }
        }
    }

    all_ms_files.sort { -it.size() }
    def n_select      = Math.min(presearch_n as int, all_ms_files.size())
    def selected_files = all_ms_files.take(n_select)

    log.info ""
    log.info "DIANN FASTA Subset + Quantification Workflow"
    log.info "============================================="
    log.info "FASTA         : ${params.fasta}"
    log.info "Samples       : ${samples_list.size()}"
    log.info "Total MS files: ${all_ms_files.size()}"
    log.info "Presearch     : ${n_select} largest files (of ${all_ms_files.size()})"
    log.info "Q-value (pre) : ${qvalue_presearch}"
    log.info "Output dir    : ${params.outdir}"
    logModelInfo(models, params)
    log.info ""
    log.info "Selected presearch files:"
    selected_files.each { f ->
        log.info "  ${f.name} (${String.format('%.0f', f.size() / 1048576.0)} MB)"
    }
    log.info ""

    def search_params = params.library ?: [:]

    /*
    ========================================================================================
        STEP 1: Generate spectral library from full FASTA (used for presearch)
        Runs in parallel with Step 2.
    ========================================================================================
    */

    GENERATE_LIBRARY(
        fasta_file,
        library_name,
        library_subdir,
        search_params,
        models.tokens,
        models.rt_model,
        models.im_model,
        models.fr_model,
        file('NO_FILE')
    )

    /*
    ========================================================================================
        STEP 2: Select presearch files (runs in parallel with Step 1)
    ========================================================================================
    */

    def selected_files_ch = Channel.fromList(selected_files).collect()
    SELECT_PRESEARCH_FILES(selected_files_ch)

    /*
    ========================================================================================
        STEP 3: Presearch - quantify N files against full speclib (no MBR, relaxed FDR)
    ========================================================================================
    */

    // Convert to value channel at assignment time (avoids .first() warning downstream)
    def presearch_library = GENERATE_LIBRARY.out.library.first()

    def presearch_sample = SELECT_PRESEARCH_FILES.out.presearch_dir
        .map { dir -> tuple('presearch', dir, file_type, 'presearch', false, n_select) }

    QUANTIFY_PRESEARCH(
        presearch_sample,
        presearch_library,
        fasta_file,
        file('NO_FILE'),   // No ref library for presearch
        false,             // No MBR for presearch
        qvalue_presearch   // Relaxed FDR (default 0.05) to capture more proteins
    )

    /*
    ========================================================================================
        STEP 4: Subset FASTA to Protein.Groups detected in presearch
    ========================================================================================
    */

    def presearch_reports = QUANTIFY_PRESEARCH.out.report
        .map { sample_id, report -> report }
        .collect()

    SUBSET_FASTA(
        presearch_reports,
        fasta_file,
        'subset_fasta',
        'subset'
    )

    /*
    ========================================================================================
        STEP 5: Generate fresh spectral library from subset FASTA
        Native speclib format: DIA-NN uses predicted intensities/RTs directly.
        No --reannotate needed in final quantification.
    ========================================================================================
    */

    // Convert to value channel at assignment time (broadcasts to GENERATE_LIBRARY_FINAL + QUANTIFY_FINAL)
    def subset_fasta_ch = SUBSET_FASTA.out.subset_fasta.first()

    GENERATE_LIBRARY_FINAL(
        subset_fasta_ch,
        "${library_name}_subset",
        "${library_subdir}/subset",
        search_params,
        models.tokens,
        models.rt_model,
        models.im_model,
        models.fr_model,
        file('NO_FILE')
    )

    /*
    ========================================================================================
        STEP 6: Final quantification with subset speclib and MBR
    ========================================================================================
    */

    def subdir    = params.quantify_subdir ?: ''
    def samples_ch = createSamplesChannel(samples_list, subdir)
    def mbr       = params.mbr_final != null ? params.mbr_final : true

    // Convert to value channel at assignment time
    def subset_library = GENERATE_LIBRARY_FINAL.out.library.first()

    QUANTIFY_FINAL(
        samples_ch,
        subset_library,
        subset_fasta_ch,    // Subset FASTA for consistent protein annotations
        ref_library_file,
        mbr,
        params.qvalue ?: 0  // Default FDR (0.01) for final quantification
    )

    emit:
    presearch_library  = GENERATE_LIBRARY.out.library
    presearch_report   = QUANTIFY_PRESEARCH.out.report
    subset_fasta       = SUBSET_FASTA.out.subset_fasta
    subset_library     = GENERATE_LIBRARY_FINAL.out.library
    quantify_reports   = QUANTIFY_FINAL.out.report
    quantify_out_libs  = QUANTIFY_FINAL.out.out_lib
    quantify_matrices  = QUANTIFY_FINAL.out.matrices
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
    Subset FASTA:      ${params.outdir}/subset_fasta/subset.fasta
    Subset library:    ${params.outdir}/${params.library_subdir ?: 'library'}/subset/${params.library_name ?: 'library'}_subset.predicted.speclib
    Samples quantified: ${sample_count}
    Results directory: ${params.outdir}
    ========================================================================================
    """
}
