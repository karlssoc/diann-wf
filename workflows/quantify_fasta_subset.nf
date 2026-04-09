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
include { GENERATE_LIBRARY                              } from '../modules/library'
include { GENERATE_LIBRARY as GENERATE_LIBRARY_FINAL    } from '../modules/library'
include { GENERATE_LIBRARY as GENERATE_LIBRARY_REF      } from '../modules/library'
include { QUANTIFY as QUANTIFY_PASS1                    } from '../modules/quantify'
include { QUANTIFY as QUANTIFY_FINAL                    } from '../modules/quantify'
include { SUBSET_FASTA                                  } from '../modules/subset_fasta'
include { SUBSET_FASTA as SUBSET_FASTA_REF              } from '../modules/subset_fasta'
include { PRESEARCH_ULTRAFAST                           } from '../modules/presearch_ultrafast'

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
    if (!params.batches) {
        error "ERROR: Missing required parameter --batches"
    }

    def samples_list = parseSamples(params.batches)

    // Set defaults
    def library_name   = params.library_name   ?: 'library'
    def library_subdir = params.library_subdir ?: 'library'

    def fasta_file = file(params.fasta)
    if (!fasta_file.exists()) {
        error "ERROR: FASTA file not found: ${params.fasta}"
    }

    def models        = resolveModelFiles(params, projectDir)
    def search_params = params.library ?: [:]

    // Ref library priority: auto-generated (ref_n_proteins) > manual (ref_library) > NO_FILE
    // auto_ref_lib is overwritten below if ref_n_proteins is set
    def auto_ref_lib = params.ref_library ? file(params.ref_library) : file('NO_FILE')

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
    if (params.ref_n_proteins) {
        def n_samp = params.ref_n_samples ?: 2
        log.info "Calibration ref library: auto-generating (top ${params.ref_n_proteins} proteins from ${n_samp} sample(s), ultrafast)"
    } else if (params.ref_library) {
        log.info "Calibration ref library: ${params.ref_library} (manual)"
    }
    log.info ""

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

    /*
    ========================================================================================
        STEP 1.5 (optional): Auto-generate calibration ref library
        Activated by setting ref_n_proteins in config (null = skip).
        Samples the first N batches in ultrafast mode against the full library,
        selects the top-N most detected proteins, generates a small speclib with
        identical parameters to the full library, and uses it as --ref in all
        QUANTIFY steps for faster RT/IM calibration.
    ========================================================================================
    */

    if (params.ref_n_proteins) {
        def ref_n_samples = params.ref_n_samples ?: 2
        def ref_samples_list = samples_list.take(ref_n_samples)
        def ref_samples_ch = createSamplesChannel(ref_samples_list, 'ref_presearch')

        PRESEARCH_ULTRAFAST(
            ref_samples_ch,
            full_library,
            fasta_file
        )

        def ref_presearch_reports = PRESEARCH_ULTRAFAST.out.report
            .map { sample_id, report -> report }
            .collect()

        SUBSET_FASTA_REF(
            ref_presearch_reports,
            fasta_file,
            'ref_presearch',
            'ref',
            params.ref_n_proteins
        )

        def ref_fasta_ch = SUBSET_FASTA_REF.out.subset_fasta.first()

        GENERATE_LIBRARY_REF(
            ref_fasta_ch,
            'ref_library',
            'ref_library',
            search_params,
            models.tokens,
            models.rt_model,
            models.im_model,
            models.fr_model,
            file('NO_FILE')
        )

        auto_ref_lib = GENERATE_LIBRARY_REF.out.library.first()
    }

    def samples_pass1_ch = createSamplesChannel(samples_list, 'quant_full')

    QUANTIFY_PASS1(
        samples_pass1_ch,
        full_library,
        fasta_file,
        auto_ref_lib,
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
        'subset',
        0   // top_n = 0: no limit (use all detected proteins for FASTA subsetting)
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

    def subdir    = params.quantify_subdir ?: 'quant_subset'
    def samples_final_ch = createSamplesChannel(samples_list, subdir)
    def mbr       = params.mbr_final != null ? params.mbr_final : true

    // Convert to value channel at assignment time
    // Note: use different name from emit output 'subset_library' to avoid Nextflow name collision
    def subset_lib = GENERATE_LIBRARY_FINAL.out.library.first()

    QUANTIFY_FINAL(
        samples_final_ch,
        subset_lib,
        subset_fasta_ch,    // Subset FASTA for consistent protein annotations
        auto_ref_lib,
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
    def sample_count = params.batches instanceof List ? params.batches.size() : 0

    println """
    ========================================================================================
    Workflow completed!
    ========================================================================================
    Subset FASTA:      ${params.outdir}/subset_fasta/subset.fasta
    Subset library:    ${params.outdir}/${params.library_subdir ?: 'library'}/subset/${params.library_name ?: 'library'}_subset.predicted.speclib
    Full FASTA quant:  ${params.outdir}/quant_full/<batch>/
    Subset FASTA quant:${params.outdir}/${params.quantify_subdir ?: 'quant_subset'}/<batch>/
    Batches:           ${sample_count}
    ========================================================================================
    """
}
