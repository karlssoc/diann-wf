// Extract Stripped Sequences Module
// Extracts unique stripped sequences from a DIA-NN report for use with --fasta-filter
//
// This dramatically speeds up library generation by limiting predictions to
// only peptides that were actually identified in the sample.

process EXTRACT_SEQUENCES {
    label 'duckdb'

    tag "${report.baseName}"

    input:
    path report        // DIA-NN report parquet (e.g., from InfinDIA presearch)

    output:
    path "stripped_sequences.txt", emit: sequences
    path "extract_sequences.log", emit: log

    script:
    """
    echo "=== Extracting Stripped Sequences ===" | tee extract_sequences.log
    echo "Report: ${report}" | tee -a extract_sequences.log

    # Extract unique stripped sequences (one per line, no header)
    /duckdb -csv -noheader -c "
        SELECT DISTINCT \\\"Stripped.Sequence\\\"
        FROM read_parquet('${report}')
        WHERE \\\"Stripped.Sequence\\\" IS NOT NULL
          AND \\\"Stripped.Sequence\\\" != ''
        ORDER BY \\\"Stripped.Sequence\\\"
    " > stripped_sequences.txt

    SEQ_COUNT=\$(wc -l < stripped_sequences.txt)
    echo "Unique sequences: \$SEQ_COUNT" | tee -a extract_sequences.log
    echo "=== Extraction Complete ===" | tee -a extract_sequences.log
    """
}
