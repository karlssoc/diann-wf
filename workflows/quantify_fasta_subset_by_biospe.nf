#!/usr/bin/env nextflow

/*
========================================================================================
    DIANN Workflow: FASTA Subset + Quantification by Biospecimen
========================================================================================
    Biospecimen-stratified variant of QUANTIFY_FASTA_SUBSET.

    Each biospecimen gets its own FASTA subset derived from the union of all its
    batches' first-pass identifications. Use this when samples from different
    biospecimen types (e.g., plasma vs CSF) have sufficiently different protein
    profiles that pooling them would inflate FDR across types.

    Steps:
    1. Generate spectral library from full FASTA (shared across all biospecimens)
    2. Full FASTA quant: quantify all batches (MBR enabled)
       → report-first-pass.parquet collected per biospecimen
    3. Per biospecimen: subset FASTA to its detected Protein.Groups
    4. Per biospecimen: generate fresh spectral library from subset FASTA
    5. Subset FASTA quant: quantify all batches against their biospecimen's subset library

    Steps 3-4 run in parallel across biospecimens.

    Output structure:
      outdir/
      ├── library/                         # Full FASTA library (shared)
      ├── <biospe_id>/
      │   ├── quant_full/<batch_id>/        # Full FASTA quantification
      │   ├── subset_fasta/                 # Biospecimen-specific subset FASTA
      │   ├── library/subset/               # Biospecimen-specific subset library
      │   └── quant_subset/<batch_id>/      # Final quantification
      └── ...

    Re-keying strategy (no module changes required):
      SUBSET_FASTA output_name = biospe_id  → outfile = ${biospe_id}.fasta
      GENERATE_LIBRARY library_name = biospe_id → outfile = ${biospe_id}.predicted.speclib
      Both can be re-keyed from their filename after async completion.
----------------------------------------------------------------------------------------
*/

nextflow.enable.dsl = 2

// Include modules
include { GENERATE_LIBRARY                               } from '../modules/library'
include { GENERATE_LIBRARY as GENERATE_LIBRARY_FINAL     } from '../modules/library'
include { QUANTIFY as QUANTIFY_PASS1                     } from '../modules/quantify'
include { QUANTIFY as QUANTIFY_FINAL                     } from '../modules/quantify'
include { SUBSET_FASTA                                   } from '../modules/subset_fasta'

// Include shared utilities
include { resolveModelFiles; logModelInfo } from '../lib/models'
include { countMSFiles                    } from '../lib/files'

/*
========================================================================================
    HELPER FUNCTIONS (script level)
    Defined outside the workflow block to avoid Nextflow DSL2 nested-closure
    variable scoping issues. All Groovy list iteration lives here.
========================================================================================
*/

// Validate biospecimens list and return a batch_id → biospe_id lookup map.
// Batch IDs must be globally unique (they become QUANTIFY sample_id values).
def buildBatchBiospeMap(biospecimens_list) {
    def batch_map = [:]
    for (biospe in biospecimens_list) {
        def biospe_id      = biospe.get('id')
        def biospe_batches = biospe.get('batches')
        if (!biospe_id) {
            log.error "ERROR: Biospecimen missing 'id' field"
            System.exit(1)
        }
        if (!biospe_batches) {
            log.error "ERROR: Biospecimen '${biospe_id}' missing 'batches' list"
            System.exit(1)
        }
        for (batch in biospe_batches) {
            def batch_id = batch.get('id')
            if (batch_map.containsKey(batch_id)) {
                log.error "ERROR: Duplicate batch id '${batch_id}' — must be unique across all biospecimens"
                System.exit(1)
            }
            batch_map[batch_id] = biospe_id
        }
    }
    return batch_map
}

// Build the flat tuple list for QUANTIFY_PASS1.
// Returns: [ (batch_id, ms_dir, file_type, subdir, recursive, file_count), ... ]
def buildPass1Batches(biospecimens_list) {
    def result = []
    for (biospe in biospecimens_list) {
        def biospe_id      = biospe.get('id')
        def biospe_batches = biospe.get('batches')
        for (batch in biospe_batches) {
            def batch_id   = batch.get('id')
            def batch_dir  = batch.get('dir')
            def sample_dir = file(batch_dir)
            if (!sample_dir.exists()) {
                log.error "ERROR: Batch directory not found: ${batch_dir} (biospecimen: ${biospe_id})"
                System.exit(1)
            }
            def recursive  = batch.get('recursive') ?: false
            def file_count = countMSFiles(sample_dir, recursive)
            log.info "Batch ${batch_id} (${biospe_id}): ${file_count} MS files"
            result << [batch_id, sample_dir, batch.get('file_type') ?: 'dia',
                       "${biospe_id}/quant_full", recursive, file_count]
        }
    }
    return result
}

// Build the flat tuple list for QUANTIFY_FINAL, keyed by biospe_id for .join().
// Returns: [ (biospe_id, batch_id, ms_dir, file_type, subdir, recursive, file_count), ... ]
def buildFinalBatches(biospecimens_list) {
    def result = []
    for (biospe in biospecimens_list) {
        def biospe_id      = biospe.get('id')
        def biospe_batches = biospe.get('batches')
        for (batch in biospe_batches) {
            def batch_id   = batch.get('id')
            def sample_dir = file(batch.get('dir'))
            def recursive  = batch.get('recursive') ?: false
            def file_count = countMSFiles(sample_dir, recursive)
            result << [biospe_id, batch_id, sample_dir, batch.get('file_type') ?: 'dia',
                       "${biospe_id}/quant_subset", recursive, file_count]
        }
    }
    return result
}

/*
========================================================================================
    WORKFLOW
========================================================================================
*/

workflow QUANTIFY_FASTA_SUBSET_BY_BIOSPE {
    if (!params.fasta) {
        error "ERROR: Missing required parameter --fasta"
    }
    if (!params.biospecimens) {
        error "ERROR: Missing required parameter --biospecimens"
    }

    def biospecimens_list = params.biospecimens

    // Validate + build lookup map via script-level function (avoids DSL2 nested-closure issues)
    def batch_biospe_map = buildBatchBiospeMap(biospecimens_list)

    // Set defaults
    def library_name   = params.library_name   ?: 'library'
    def library_subdir = params.library_subdir ?: 'library'
    def mbr_final      = params.mbr_final != null ? params.mbr_final : true

    def fasta_file = file(params.fasta)
    if (!fasta_file.exists()) {
        error "ERROR: FASTA file not found: ${params.fasta}"
    }

    def models           = resolveModelFiles(params, projectDir)
    def ref_library_file = params.ref_library ? file(params.ref_library) : file('NO_FILE')
    def search_params    = params.library ?: [:]

    log.info ""
    log.info "DIANN FASTA Subset + Quantification by Biospecimen"
    log.info "==================================================="
    log.info "FASTA          : ${params.fasta}"
    log.info "Biospecimens   : ${biospecimens_list.size()}"
    log.info "Total batches  : ${batch_biospe_map.size()}"
    log.info "Output dir     : ${params.outdir}"
    logModelInfo(models, params)
    log.info ""

    /*
    ========================================================================================
        STEP 1: Generate spectral library from full FASTA (shared)
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

    // Value channel: broadcasts to all QUANTIFY_PASS1 invocations
    def full_library = GENERATE_LIBRARY.out.library.first()

    /*
    ========================================================================================
        STEP 2: Full FASTA quant — all batches against full library (MBR enabled)
        report-first-pass.parquet = per-run 1% FDR identifications (pre-MBR transfer)
        These are collected per biospecimen for FASTA subsetting in Step 3.
    ========================================================================================
    */

    // Channel construction via script-level function (avoids DSL2 nested-closure issues)
    def pass1_batches_ch = Channel.fromList(buildPass1Batches(biospecimens_list))

    QUANTIFY_PASS1(
        pass1_batches_ch,
        full_library,
        fasta_file,
        ref_library_file,
        true,              // MBR enabled: generates report-first-pass.parquet
        params.qvalue ?: 0
    )

    /*
    ========================================================================================
        STEP 3: Per-biospecimen FASTA subsetting
        Group first-pass reports by biospecimen_id, then run SUBSET_FASTA in parallel.

        Re-keying: output_name = biospe_id, so output file = ${biospe_id}.fasta.
        This allows reliable re-keying from filename after async process completion,
        without requiring module signature changes.
    ========================================================================================
    */

    // Map each batch's first-pass report to its biospecimen, then group
    def biospe_reports = QUANTIFY_PASS1.out.first_pass_report
        .map { batch_id, report -> tuple(batch_biospe_map[batch_id], report) }
        .groupTuple()
    // → (biospe_id, [report1, report2, ...])

    // multiMap to fork channel (avoids consuming biospe_reports twice)
    def subset_fasta_in = biospe_reports.multiMap { biospe_id, reports ->
        pg_sources:   reports
        subdirs:      "${biospe_id}/subset_fasta"
        output_names: biospe_id               // output = ${biospe_id}.fasta → re-keyed by baseName
    }

    SUBSET_FASTA(
        subset_fasta_in.pg_sources,
        fasta_file,
        subset_fasta_in.subdirs,
        subset_fasta_in.output_names
    )

    // Re-key by parsing biospe_id from output filename: plasma.fasta → 'plasma'
    def subset_fasta_keyed = SUBSET_FASTA.out.subset_fasta
        .map { fasta -> tuple(fasta.baseName, fasta) }
    // → (biospe_id, subset_fasta_path)

    /*
    ========================================================================================
        STEP 4: Per-biospecimen library generation from subset FASTA
        Runs in parallel across biospecimens (Steps 3-4 are independent per biospecimen).

        Re-keying: library_name = biospe_id, so output = ${biospe_id}.predicted.speclib.
    ========================================================================================
    */

    def gen_lib_in = subset_fasta_keyed.multiMap { biospe_id, fasta ->
        fastas:          fasta
        library_names:   biospe_id                     // output = ${biospe_id}.predicted.speclib
        library_subdirs: "${biospe_id}/library/subset"
    }

    GENERATE_LIBRARY_FINAL(
        gen_lib_in.fastas,
        gen_lib_in.library_names,
        gen_lib_in.library_subdirs,
        search_params,
        models.tokens,
        models.rt_model,
        models.im_model,
        models.fr_model,
        file('NO_FILE')
    )

    // Re-key by parsing biospe_id from library filename: plasma.predicted.speclib → 'plasma'
    def subset_lib_keyed = GENERATE_LIBRARY_FINAL.out.library
        .map { lib -> tuple(lib.name.replace('.predicted.speclib', ''), lib) }
    // → (biospe_id, library_path)

    /*
    ========================================================================================
        STEP 5: Subset FASTA quant — each batch against its biospecimen's subset library
        Join batches with their matching subset library on biospe_id, then split
        into parallel channels for QUANTIFY (library is per-biospe, not a value channel).
    ========================================================================================
    */

    // Channel construction via script-level function (avoids DSL2 nested-closure issues)
    def final_batches_ch = Channel.fromList(buildFinalBatches(biospecimens_list))

    // Join batches with their biospecimen's subset library on biospe_id
    def final_joined = final_batches_ch
        .join(subset_lib_keyed, by: 0)
    // → (biospe_id, batch_id, sample_dir, file_type, subdir, recursive, file_count, library)

    // Fork: QUANTIFY requires sample tuple and library as separate inputs
    def final_fork = final_joined.multiMap { biospe_id, batch_id, sample_dir, file_type, subdir, recursive, file_count, library ->
        samples:   tuple(batch_id, sample_dir, file_type, subdir, recursive, file_count)
        libraries: library
    }

    // Note: final_fork.libraries is a queue channel (not value) — each batch gets its
    // own biospecimen's library. Items stay in sync because both forks share the same source.
    QUANTIFY_FINAL(
        final_fork.samples,
        final_fork.libraries,
        fasta_file,
        ref_library_file,
        mbr_final,
        params.qvalue ?: 0
    )

    emit:
    pass1_library    = GENERATE_LIBRARY.out.library
    pass1_reports    = QUANTIFY_PASS1.out.report
    subset_fastas    = SUBSET_FASTA.out.subset_fasta
    subset_libraries = GENERATE_LIBRARY_FINAL.out.library
    quant_reports    = QUANTIFY_FINAL.out.report
    quant_matrices   = QUANTIFY_FINAL.out.matrices
}

/*
========================================================================================
    WORKFLOW INTROSPECTION
========================================================================================
*/

workflow.onComplete {
    def biospe_list   = params.biospecimens instanceof List ? params.biospecimens : []
    def id_list = []
    for (biospe in biospe_list) { id_list << biospe.get('id') }
    def biospe_ids    = id_list.join(', ')
    def total_batches = 0
    for (biospe in biospe_list) { total_batches += biospe.get('batches')?.size() ?: 0 }

    println """
    ========================================================================================
    Workflow completed!
    ========================================================================================
    Full FASTA library: ${params.outdir}/${params.library_subdir ?: 'library'}/${params.library_name ?: 'library'}.predicted.speclib
    Biospecimens: ${biospe_ids}
    Per-biospecimen outputs in: ${params.outdir}/<biospe_id>/
      ├── quant_full/<batch_id>/    Full FASTA quantification
      ├── subset_fasta/             Biospecimen-specific subset FASTA
      ├── library/subset/           Biospecimen-specific subset library
      └── quant_subset/<batch_id>/  Final quantification
    Total batches: ${total_batches}
    ========================================================================================
    """
}
