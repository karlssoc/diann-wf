// DIANN Library Subsetting Module
// Filters a spectral library to include only protein groups found in source parquet file(s)
//
// Supports single or multiple input files (e.g., from .collect() across samples).
// Uses DuckDB for efficient parquet operations with schema preservation.

process SUBSET_LIBRARY {
    label 'duckdb'

    publishDir "${params.outdir}${subdir ? '/' + subdir : ''}",
        mode: 'copy',
        overwrite: true

    tag "${subdir ? subdir + '/' : ''}${library.baseName}"

    input:
    path pg_source     // Parquet file(s) containing Protein.Group column (out-lib or report)
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
    echo "PG source: ${pg_source}" | tee -a subset_library.log
    echo "Library:   ${library}" | tee -a subset_library.log
    echo "Output:    ${output_name}.parquet" | tee -a subset_library.log
    echo "" | tee -a subset_library.log

    # Build DuckDB list from staged Protein.Group source file(s)
    # Handles both single file and multiple files from .collect()
    PG_LIST=\$(echo "${pg_source}" | tr ' ' '\\n' | sed "s/.*/'&'/" | paste -sd, -)
    PG_COUNT=\$(echo "${pg_source}" | wc -w | tr -d ' ')
    echo "PG source files: \$PG_COUNT" | tee -a subset_library.log

    # Count input rows
    PG_ROWS=\$(/duckdb -csv -noheader -c "SELECT COUNT(*) FROM read_parquet([\$PG_LIST])")
    LIBRARY_ROWS=\$(/duckdb -csv -noheader -c "SELECT COUNT(*) FROM read_parquet('${library}')")
    echo "PG source rows (total): \$PG_ROWS" | tee -a subset_library.log
    echo "Library rows: \$LIBRARY_ROWS" | tee -a subset_library.log

    # Count unique Protein.Groups across all source files (union)
    UNIQUE_PG=\$(/duckdb -csv -noheader -c "SELECT COUNT(DISTINCT \\\"Protein.Group\\\") FROM read_parquet([\$PG_LIST])")
    echo "Unique Protein.Groups in source: \$UNIQUE_PG" | tee -a subset_library.log
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
                FROM read_parquet([\$PG_LIST])
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
