#!/usr/bin/env nextflow

/*
========================================================================================
    DIANN Workflow: FASTA Subset + Quantification
========================================================================================
    Two-pass search space reduction by subsetting the FASTA via a full first-pass
    quantification, then regenerating a fresh spectral library from the subset FASTA.

    Steps:
    1. Generate spectral library from full FASTA
    2. Pass 1: Quantify ALL samples against full library (MBR enabled)
       → report-first-pass.parquet contains the union of identified proteins
         across all samples at per-run 1% FDR before cross-run transfer
    3. Subset FASTA to Protein.Groups detected in pass 1
    4. Generate fresh spectral library from subset FASTA (native speclib, no --reannotate)
    5. Pass 2: Quantify ALL samples against subset speclib (MBR enabled)

    Advantage over PRESEARCH_AND_QUANTIFY (which subsets the library parquet):
    - Native speclib from subset FASTA: full predicted spectral quality preserved
    - No --reannotate: DIA-NN uses library intensities/RTs directly
    - ~78% smaller library: faster pass 2, less decoy competition, better FDR calibration
    - FASTA subset source (report-first-pass, all samples, MBR) is maximally rich:
      union of per-run 1% FDR identifications across all samples

    Time cost:
    - Pass 1 uses full FASTA but MBR adds little overhead vs a standard run
    - Pass 2 is ~5x faster than pass 1 (smaller library)
    - Total ≈ 1.2x a standard single-pass run

    Use case: Cohorts where the full proteome inflates FDR due to irrelevant proteins.
    Pass 1 establishes which proteins are actually present; pass 2 quantifies them cleanly.
----------------------------------------------------------------------------------------
*/

nextflow.enable.dsl = 2

// Include modules
include { GENERATE_LIBRARY                         } from '../modules/library'
include { GENERATE_LIBRARY as GENERATE_LIBRARY_FINAL } from '../modules/library'
include { QUANTIFY as QUANTIFY_PASS1               } from '../modules/quantify'
include { QUANTIFY as QUANTIFY_FINAL               } from '../modules/quantify'
include { SUBSET_FASTA                             } from '../modules/subset_fasta'

// Include shared utilities
include { parseSamples; createSamplesChannel       } from '../lib/samples'
include { resolveModelFiles; logModelInfo          } from '../lib/models'

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
    def library_name   = params.library_name   ?: 'library'
    def library_subdir = params.library_subdir ?: 'library'

    def fasta_file = file(params.fasta)
    if (!fasta_file.exists()) {
        error "ERROR: FASTA file not found: ${params.fasta}"
    }

    def models           = resolveModelFiles(params, projectDir)
    def ref_library_file = params.ref_library ? file(params.ref_library) : file('NO_FILE')

    log.info ""
    log.info "DIANN FASTA Subset + Quantification Workflow"
    log.info "============================================="
    log.info "FASTA      : ${params.fasta}"
    log.info "Samples    : ${samples_list.size()}"
    log.info "Output dir : ${params.outdir}"
    logModelInfo(models, params)
    log.info ""
    log.info "Pass 1: full FASTA, all samples, MBR enabled"
    log.info "  → report-first-pass.parquet used to subset FASTA"
    log.info "Pass 2: subset speclib, all samples, MBR enabled"
    log.info ""

    def search_params = params.library ?: [:]

    /*
    ========================================================================================
        STEP 1: Generate spectral library from full FASTA
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
        STEP 2: Pass 1 - Quantify ALL samples against full speclib with MBR
        report-first-pass.parquet = per-run 1% FDR identifications across all samples
        (before cross-run MBR transfer). Union of all samples gives the richest
        possible protein list for FASTA subsetting.
    ========================================================================================
    */

    // Convert to value channel at assignment time
    def full_library = GENERATE_LIBRARY.out.library.first()

    def samples_pass1_ch = createSamplesChannel(samples_list, 'pass1')

    QUANTIFY_PASS1(
        samples_pass1_ch,
        full_library,
        fasta_file,
        ref_library_file,
        true,              // MBR enabled: generates report-first-pass.parquet
        params.qvalue ?: 0
    )

    /*
    ========================================================================================
        STEP 3: Subset FASTA to Protein.Groups from pass 1 first-pass reports
        Union across all samples = all proteins detected in any sample at 1% FDR
    ========================================================================================
    */

    def first_pass_reports = QUANTIFY_PASS1.out.first_pass_report
        .map { sample_id, report -> report }
        .collect()

    SUBSET_FASTA(
        first_pass_reports,
        fasta_file,
        'subset_fasta',
        'subset'
    )

    /*
    ========================================================================================
        STEP 4: Generate fresh spectral library from subset FASTA
        Native speclib format: no --reannotate needed in pass 2.
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
        STEP 5: Pass 2 - Quantify ALL samples against subset speclib with MBR
        ~5x faster than pass 1 (smaller library), better FDR calibration
    ========================================================================================
    */

    def subdir    = params.quantify_subdir ?: ''
    def samples_final_ch = createSamplesChannel(samples_list, subdir)
    def mbr       = params.mbr_final != null ? params.mbr_final : true

    // Convert to value channel at assignment time
    def subset_library = GENERATE_LIBRARY_FINAL.out.library.first()

    QUANTIFY_FINAL(
        samples_final_ch,
        subset_library,
        subset_fasta_ch,    // Subset FASTA for consistent protein annotations
        ref_library_file,
        mbr,
        params.qvalue ?: 0
    )

    emit:
    pass1_library     = GENERATE_LIBRARY.out.library
    pass1_reports     = QUANTIFY_PASS1.out.report
    subset_fasta      = SUBSET_FASTA.out.subset_fasta
    subset_library    = GENERATE_LIBRARY_FINAL.out.library
    quantify_reports  = QUANTIFY_FINAL.out.report
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
    Subset FASTA:      ${params.outdir}/subset_fasta/subset.fasta
    Subset library:    ${params.outdir}/${params.library_subdir ?: 'library'}/subset/${params.library_name ?: 'library'}_subset.predicted.speclib
    Pass 1 results:    ${params.outdir}/pass1/<sample>/
    Pass 2 results:    ${params.outdir}/<sample>/
    Samples:           ${sample_count}
    ========================================================================================
    """
}
