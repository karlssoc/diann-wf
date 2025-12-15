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
    // Use absolute path to DIANN binary (container ENTRYPOINT interferes with PATH)
    def diann_cmd = "/usr/bin/diann-${params.diann_version}/diann-linux"

    // Determine which models to tune
    def tune_rt = params.tuning?.tune_rt ? "--tune-rt" : ""
    def tune_im = params.tuning?.tune_im ? "--tune-im" : ""
    def tune_fr = params.tuning?.tune_fr ? "--tune-fr" : ""

    // Note: FR tuning only works with DIANN 2.3.1+
    if (tune_fr && !params.diann_version.startsWith('2.3')) {
        log.warn "FR tuning (--tune-fr) requires DIANN 2.3.1+. Current version: ${params.diann_version}"
    }

    """
    # Create working directory and link library (preserve original extension)
    mkdir -p tune_work
    ln -s \$(realpath ${library}) tune_work/${library.name}

    # Run tuning
    ${diann_cmd} \\
        --threads ${task.cpus} \\
        --tune-lib tune_work/${library.name} \\
        ${tune_rt} \\
        ${tune_im} \\
        ${tune_fr} \\
        2>&1 | tee tune_full.log

    # Filter warnings and save clean log
    grep -v 'Warning' tune_full.log > tune.log || true

    # Move tuned model files to output (using base name from input library)
    # DIANN generates files based on the input library name (without extension)
    # Create placeholder files for missing optional outputs to ensure downstream processes can run
    BASENAME=\$(basename ${library.name} | sed 's/\\.[^.]*\$//')

    # Required output: tokens file must exist
    mv tune_work/\${BASENAME}.dict.txt out-lib.dict.txt 2>/dev/null || {
        echo "ERROR: No tokens file generated" >&2
        exit 1
    }

    # Optional outputs: create empty placeholders if not generated
    if [ -f "tune_work/\${BASENAME}.tuned_rt.pt" ]; then
        mv tune_work/\${BASENAME}.tuned_rt.pt out-lib.tuned_rt.pt
    else
        echo "No RT model generated - creating placeholder"
        touch out-lib.tuned_rt.pt
    fi

    if [ -f "tune_work/\${BASENAME}.tuned_im.pt" ]; then
        mv tune_work/\${BASENAME}.tuned_im.pt out-lib.tuned_im.pt
    else
        echo "No IM model generated - creating placeholder"
        touch out-lib.tuned_im.pt
    fi

    if [ -f "tune_work/\${BASENAME}.tuned_fr.pt" ]; then
        mv tune_work/\${BASENAME}.tuned_fr.pt out-lib.tuned_fr.pt
    else
        echo "No FR model generated - creating placeholder"
        touch out-lib.tuned_fr.pt
    fi
    """
}
