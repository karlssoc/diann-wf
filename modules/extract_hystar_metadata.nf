// Extract Bruker HyStar acquisition metadata from TimsTOF .d directories
//
// Scans sample directories (file_type == 'd') defined in the workflow YAML and
// extracts acquisition metadata from HyStarMetadata.xml inside each .d folder.
//
// Output CSV columns:
//   YamlSampleId, SampleID, CreationDateTime, FileName, WindowsPath, LocalPath
//
// Note: runs as a local process with the python_container image.

process EXTRACT_HYSTAR_METADATA {
    label 'local_script'

    publishDir "${params.outdir}",
        mode: 'copy',
        overwrite: true

    input:
    path params_yaml    // The workflow YAML params file

    output:
    path "hystar_metadata.csv", emit: metadata

    script:
    """
    extract_hystar_metadata.py ${params_yaml} \\
        --basedir ${launchDir} \\
        --output hystar_metadata.csv
    """
}
