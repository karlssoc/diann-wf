// DIANN Model Tuning Module
// Fine-tunes prediction models (RT, IM, FR) using an existing library

process TUNE_MODELS {
    label 'diann_tune'

    // Dynamic publishDir: supports optional subdirectory organization
    // If subdir is provided: outdir/subdir/
    // If subdir is empty:    outdir/
    publishDir "${params.outdir}${subdir ? '/' + subdir : ''}",
        mode: 'copy',
        overwrite: true

    tag "${subdir ? subdir + '/' : ''}${tune_name}"

    input:
    path library
    val tune_name
    val subdir

    output:
    path "out-lib.dict.txt", emit: tokens
    path "out-lib.tuned_rt.pt", emit: rt_model, optional: true
    path "out-lib.tuned_im.pt", emit: im_model, optional: true
    path "out-lib.tuned_fr.pt", emit: fr_model, optional: true
    path "tune.log", emit: log

    script:
    // Determine which models to tune
    def tune_rt = params.tuning?.tune_rt ? "--tune-rt" : ""
    def tune_im = params.tuning?.tune_im ? "--tune-im" : ""
    def tune_fr = params.tuning?.tune_fr ? "--tune-fr" : ""

    // Note: FR tuning only works with DIANN 2.3.1+
    if (tune_fr && !params.diann_version.startsWith('2.3')) {
        log.warn "FR tuning (--tune-fr) requires DIANN 2.3.1+. Current version: ${params.diann_version}"
    }

    """
    # Create working directory and link library
    mkdir -p tune_work
    ln -s \$(realpath ${library}) tune_work/out-lib.parquet

    # Run tuning
    diann \\
        --threads ${task.cpus} \\
        --tune-lib tune_work/out-lib.parquet \\
        ${tune_rt} \\
        ${tune_im} \\
        ${tune_fr} \\
        2>&1 | tee tune_full.log

    # Filter warnings and save clean log
    grep -v 'Warning' tune_full.log > tune.log || true

    # Move tuned model files to output
    mv tune_work/out-lib.dict.txt . 2>/dev/null || echo "No tokens file generated"
    mv tune_work/out-lib.tuned_rt.pt . 2>/dev/null || echo "No RT model generated"
    mv tune_work/out-lib.tuned_im.pt . 2>/dev/null || echo "No IM model generated"
    mv tune_work/out-lib.tuned_fr.pt . 2>/dev/null || echo "No FR model generated"
    """
}
