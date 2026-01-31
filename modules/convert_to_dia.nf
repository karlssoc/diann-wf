// DIA-NN Format Conversion Module
// Converts RAW/.d files to .dia format for faster subsequent processing
//
// Benefits:
//   - RAW/.d files read only once (during conversion)
//   - .dia files load much faster in all subsequent stages
//   - Eliminates need for mzML conversion in presearch
//   - Significant speedup for iterative workflows
//
// Supports: Thermo RAW, Bruker .d, mzML, WIFF

// Single file conversion (parallel execution)
process CONVERT_TO_DIA {
    label 'diann_convert'

    publishDir "${params.outdir}/dia_converted/${sample_id}",
        mode: 'copy',
        overwrite: true

    tag "${sample_id}/${ms_file.name}"

    input:
    tuple val(sample_id), path(ms_file)    // Sample ID and MS file

    output:
    tuple val(sample_id), path("*.dia"), emit: dia_file

    script:
    def diann_cmd = params.diann_binary
    def base_name = ms_file.name.replaceAll(/(?i)\.(raw|d|mzML|wiff)$/, '')

    """
    echo "=== Converting to .dia format ==="
    echo "Input: ${ms_file}"
    echo ""

    ${diann_cmd} \\
        --f ${ms_file} \\
        --convert \\
        --threads ${task.cpus} \\
        --verbose 1

    # DIA-NN outputs filename.raw.dia or filename.d.dia, rename to filename.dia
    if [ -f "${ms_file}.dia" ]; then
        mv "${ms_file}.dia" "${base_name}.dia"
    fi

    echo ""
    echo "=== Conversion Complete ==="
    ls -lh *.dia
    """
}

// Batch conversion - all files in one job (sequential execution)
// Use this when parallel container extraction is problematic (e.g., /tmp space)
process CONVERT_TO_DIA_BATCH {
    label 'diann_library'  // Use library label for longer time/more resources

    publishDir "${params.outdir}/dia_converted",
        mode: 'copy',
        overwrite: true

    tag "batch_${ms_files.size()}_files"

    input:
    path(ms_files)           // All MS files (staged to work dir)
    path(manifest)           // CSV: filename,sample_id

    output:
    path("*/**.dia"), emit: dia_files
    path("output_manifest.csv"), emit: manifest

    script:
    def diann_cmd = params.diann_binary

    """
    echo "=== Batch Converting ${ms_files.size()} files to .dia format ==="
    echo ""

    # Process each file from manifest
    while IFS=, read -r filename sample_id; do
        # Skip header
        [ "\$filename" = "filename" ] && continue

        echo "Converting: \$filename (sample: \$sample_id)"

        # Create sample output directory
        mkdir -p "\$sample_id"

        # Convert file
        ${diann_cmd} \\
            --f "\$filename" \\
            --convert \\
            --threads ${task.cpus} \\
            --verbose 1

        # Get base name without extension (case-insensitive)
        base_name=\$(echo "\$filename" | sed -E 's/\\.[rR][aA][wW]\$|\\.[dD]\$|\\.[mM][zZ][mM][lL]\$|\\.[wW][iI][fF][fF]\$//')

        # DIA-NN creates filename.raw.dia - move to sample directory
        # Check for both the file and any .dia file that matches
        if [ -f "\${filename}.dia" ]; then
            mv "\${filename}.dia" "\${sample_id}/\${base_name}.dia"
            echo "  -> \${sample_id}/\${base_name}.dia"
        else
            echo "  WARNING: No .dia file created for \$filename"
            ls -la *.dia 2>/dev/null || echo "  No .dia files in current directory"
        fi
        echo ""
    done < ${manifest}

    # Create output manifest
    echo "dia_file,sample_id" > output_manifest.csv
    for sample_dir in */; do
        sample_id=\${sample_dir%/}
        for dia_file in "\$sample_dir"*.dia; do
            [ -f "\$dia_file" ] && echo "\$dia_file,\$sample_id" >> output_manifest.csv
        done
    done

    echo "=== Batch Conversion Complete ==="
    find . -name "*.dia" -exec ls -lh {} \\;
    """
}
