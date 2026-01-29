// DIANN Library Subsetting Module
// Filters a spectral library to include only protein groups identified in a quantification report
//
// Uses DuckDB for efficient parquet operations with schema preservation

process SUBSET_LIBRARY {
    label 'duckdb'

    publishDir "${params.outdir}${subdir ? '/' + subdir : ''}",
        mode: 'copy',
        overwrite: true

    tag "${subdir ? subdir + '/' : ''}${library.baseName}"

    input:
    path report        // Quantification report parquet (source of Protein.Group filter)
    path library       // Full spectral library parquet (to be filtered)
    val subdir         // Optional output subdirectory
    val output_name    // Output file name (without .parquet extension)

    output:
    path "${output_name}.parquet", emit: subset_library
    path "subset_library.log", emit: log

    script:
    """
    # Log subsetting operation
    echo "=== Library Subsetting ===" | tee subset_library.log
    echo "Report:  ${report}" | tee -a subset_library.log
    echo "Library: ${library}" | tee -a subset_library.log
    echo "Output:  ${output_name}.parquet" | tee -a subset_library.log
    echo "" | tee -a subset_library.log

    # Count input rows (use -csv -noheader for clean output)
    REPORT_ROWS=\$(/duckdb -csv -noheader -c "SELECT COUNT(*) FROM read_parquet('${report}')")
    LIBRARY_ROWS=\$(/duckdb -csv -noheader -c "SELECT COUNT(*) FROM read_parquet('${library}')")
    echo "Report rows:  \$REPORT_ROWS" | tee -a subset_library.log
    echo "Library rows: \$LIBRARY_ROWS" | tee -a subset_library.log

    # Count unique Protein.Groups in report
    UNIQUE_PG=\$(/duckdb -csv -noheader -c "SELECT COUNT(DISTINCT \\\"Protein.Group\\\") FROM read_parquet('${report}')")
    echo "Unique Protein.Groups in report: \$UNIQUE_PG" | tee -a subset_library.log
    echo "" | tee -a subset_library.log

    # Perform subsetting with inner join on unique Protein.Groups
    # This preserves the exact schema of the library parquet
    echo "Subsetting library..." | tee -a subset_library.log
    /duckdb -c "
        COPY (
            SELECT L.*
            FROM read_parquet('${library}') L
            INNER JOIN (
                SELECT DISTINCT \\\"Protein.Group\\\"
                FROM read_parquet('${report}')
            ) R ON L.\\\"Protein.Group\\\" = R.\\\"Protein.Group\\\"
        ) TO '${output_name}.parquet' (FORMAT PARQUET);
    "

    # Count output rows
    OUTPUT_ROWS=\$(/duckdb -csv -noheader -c "SELECT COUNT(*) FROM read_parquet('${output_name}.parquet')")
    echo "Output rows:  \$OUTPUT_ROWS" | tee -a subset_library.log

    # Calculate reduction using awk (bc not available in minimal containers)
    if [ "\$LIBRARY_ROWS" -gt 0 ]; then
        REDUCTION=\$(awk "BEGIN {printf \\"%.2f\\", (1 - \$OUTPUT_ROWS / \$LIBRARY_ROWS) * 100}")
        echo "Reduction:    \$REDUCTION%" | tee -a subset_library.log
    fi

    # Verify output unique Protein.Groups
    OUTPUT_PG=\$(/duckdb -csv -noheader -c "SELECT COUNT(DISTINCT \\\"Protein.Group\\\") FROM read_parquet('${output_name}.parquet')")
    echo "Unique Protein.Groups in output: \$OUTPUT_PG" | tee -a subset_library.log
    echo "" | tee -a subset_library.log
    echo "=== Subsetting Complete ===" | tee -a subset_library.log
    """
}
