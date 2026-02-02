// Filter Library Module
// Filters a spectral library parquet by precursor charge
//
// Outputs:
//   - filtered_lib.parquet: Library with specified charges removed

process FILTER_LIBRARY_CHARGE {
    label 'duckdb'

    publishDir "${params.outdir}${subdir ? '/' + subdir : ''}",
        mode: 'copy',
        overwrite: true

    tag "${library.baseName}"

    input:
    path library            // Input library parquet
    val exclude_charges     // List of charges to exclude, e.g., [1] or [1, 4]
    val output_name         // Output filename (without .parquet)
    val subdir              // Output subdirectory

    output:
    path "${output_name}.parquet", emit: filtered_library
    path "filter_library.log", emit: log

    script:
    // Convert list to SQL IN clause
    def exclude_list = exclude_charges.collect { charge -> charge.toString() }.join(', ')

    """
    echo "=== Library Charge Filter ===" | tee filter_library.log
    echo "Input:  ${library}" | tee -a filter_library.log
    echo "Output: ${output_name}.parquet" | tee -a filter_library.log
    echo "Excluding charges: ${exclude_list}" | tee -a filter_library.log
    echo "" | tee -a filter_library.log

    # Count before filtering
    BEFORE=\$(/duckdb -csv -noheader -c "SELECT COUNT(*) FROM read_parquet('${library}')")
    echo "Precursors before: \$BEFORE" | tee -a filter_library.log

    # Filter library - exclude specified charges
    /duckdb -c "
        COPY (
            SELECT *
            FROM read_parquet('${library}')
            WHERE \\\"Precursor.Charge\\\" NOT IN (${exclude_list})
        ) TO '${output_name}.parquet' (FORMAT PARQUET);
    "

    # Count after filtering
    AFTER=\$(/duckdb -csv -noheader -c "SELECT COUNT(*) FROM read_parquet('${output_name}.parquet')")
    REMOVED=\$((BEFORE - AFTER))
    echo "Precursors after:  \$AFTER" | tee -a filter_library.log
    echo "Removed:           \$REMOVED" | tee -a filter_library.log
    echo "" | tee -a filter_library.log
    echo "=== Filter Complete ===" | tee -a filter_library.log
    """
}
