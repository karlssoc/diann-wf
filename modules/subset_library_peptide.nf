// DIANN Library Subsetting Module (Peptide-Level)
// Filters a spectral library to include only peptides identified in a quantification report
//
// Uses Modified.Sequence for joining, which creates a smaller, more targeted library
// compared to Protein.Group-based subsetting. This is particularly useful for:
// - Calibration libraries (only need peptides with empirical RT/IM evidence)
// - InfinDIA presearch output (Protein.Group column is not populated)
//
// Uses DuckDB for efficient parquet operations with schema preservation

process SUBSET_LIBRARY_PEPTIDE {
    label 'duckdb'

    publishDir "${params.outdir}${subdir ? '/' + subdir : ''}",
        mode: 'copy',
        overwrite: true

    tag "${subdir ? subdir + '/' : ''}${library.baseName}"

    input:
    path report        // Quantification report parquet (source of Modified.Sequence filter)
    path library       // Full spectral library parquet (to be filtered)
    val subdir         // Optional output subdirectory
    val output_name    // Output file name (without .parquet extension)

    output:
    path "${output_name}.parquet", emit: subset_library
    path "subset_library_peptide.log", emit: log

    script:
    """
    # Log subsetting operation
    echo "=== Library Subsetting (Peptide-Level) ===" | tee subset_library_peptide.log
    echo "Report:  ${report}" | tee -a subset_library_peptide.log
    echo "Library: ${library}" | tee -a subset_library_peptide.log
    echo "Output:  ${output_name}.parquet" | tee -a subset_library_peptide.log
    echo "Join on: Modified.Sequence" | tee -a subset_library_peptide.log
    echo "" | tee -a subset_library_peptide.log

    # Count input rows (use -csv -noheader for clean output)
    REPORT_ROWS=\$(/duckdb -csv -noheader -c "SELECT COUNT(*) FROM read_parquet('${report}')")
    LIBRARY_ROWS=\$(/duckdb -csv -noheader -c "SELECT COUNT(*) FROM read_parquet('${library}')")
    echo "Report rows:  \$REPORT_ROWS" | tee -a subset_library_peptide.log
    echo "Library rows: \$LIBRARY_ROWS" | tee -a subset_library_peptide.log

    # Count unique Modified.Sequence in report
    UNIQUE_PEPTIDES=\$(/duckdb -csv -noheader -c "SELECT COUNT(DISTINCT \\\"Modified.Sequence\\\") FROM read_parquet('${report}')")
    echo "Unique peptides (Modified.Sequence) in report: \$UNIQUE_PEPTIDES" | tee -a subset_library_peptide.log
    echo "" | tee -a subset_library_peptide.log

    # Perform subsetting with inner join on unique Modified.Sequence
    # This preserves the exact schema of the library parquet
    echo "Subsetting library by peptide..." | tee -a subset_library_peptide.log
    /duckdb -c "
        COPY (
            SELECT L.*
            FROM read_parquet('${library}') L
            INNER JOIN (
                SELECT DISTINCT \\\"Modified.Sequence\\\"
                FROM read_parquet('${report}')
            ) R ON L.\\\"Modified.Sequence\\\" = R.\\\"Modified.Sequence\\\"
        ) TO '${output_name}.parquet' (FORMAT PARQUET);
    "

    # Count output rows
    OUTPUT_ROWS=\$(/duckdb -csv -noheader -c "SELECT COUNT(*) FROM read_parquet('${output_name}.parquet')")
    echo "Output rows:  \$OUTPUT_ROWS" | tee -a subset_library_peptide.log

    # Calculate reduction using awk (bc not available in minimal containers)
    if [ "\$LIBRARY_ROWS" -gt 0 ]; then
        REDUCTION=\$(awk "BEGIN {printf \\"%.2f\\", (1 - \$OUTPUT_ROWS / \$LIBRARY_ROWS) * 100}")
        echo "Reduction:    \$REDUCTION%" | tee -a subset_library_peptide.log
    fi

    # Verify output unique peptides
    OUTPUT_PEPTIDES=\$(/duckdb -csv -noheader -c "SELECT COUNT(DISTINCT \\\"Modified.Sequence\\\") FROM read_parquet('${output_name}.parquet')")
    echo "Unique peptides in output: \$OUTPUT_PEPTIDES" | tee -a subset_library_peptide.log

    # Also report Protein.Group stats for context
    OUTPUT_PG=\$(/duckdb -csv -noheader -c "SELECT COUNT(DISTINCT \\\"Protein.Group\\\") FROM read_parquet('${output_name}.parquet')")
    echo "Unique Protein.Groups in output: \$OUTPUT_PG" | tee -a subset_library_peptide.log
    echo "" | tee -a subset_library_peptide.log
    echo "=== Subsetting Complete ===" | tee -a subset_library_peptide.log
    """
}
