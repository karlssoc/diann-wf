// Model Accuracy Report Module
// Calculates RT and IM accuracy metrics for model evaluation
//
// Outputs:
//   - accuracy_metrics.tsv: Summary statistics (correlations, counts)
//   - rt_accuracy.tsv: Per-precursor RT data for plotting
//   - im_accuracy.tsv: Per-precursor IM data for plotting (if available)

process MODEL_ACCURACY_REPORT {
    label 'duckdb'

    publishDir "${params.outdir}${subdir ? '/' + subdir : ''}",
        mode: 'copy',
        overwrite: true

    tag "${preset_name}"

    input:
    path reports         // List of report.parquet files
    val preset_name      // Model preset name for labeling
    val subdir           // Output subdirectory

    output:
    path "accuracy_metrics.tsv", emit: metrics
    path "rt_accuracy.tsv", emit: rt_data
    path "im_accuracy.tsv", emit: im_data, optional: true
    path "accuracy_report.log", emit: log

    script:
    // Handle single file or list of files
    def report_files = reports instanceof List ? reports : [reports]
    def report_glob = report_files.size() > 1 ? "*.parquet" : reports

    """
    echo "=== Model Accuracy Report ===" | tee accuracy_report.log
    echo "Preset: ${preset_name}" | tee -a accuracy_report.log
    echo "Reports: ${report_files.size()}" | tee -a accuracy_report.log
    echo "" | tee -a accuracy_report.log

    # Calculate accuracy metrics using DuckDB
    # Use COPY TO for TSV output (DuckDB CLI meta-commands don't work with -c)
    # Note: iRT vs Predicted.iRT shows raw model accuracy (before calibration)
    #       RT vs Predicted.RT shows calibrated accuracy (after run-specific adjustment)
    /duckdb -c "
        COPY (
            SELECT
                '${preset_name}' AS preset,
                COUNT(*) AS total_precursors,
                COUNT(DISTINCT \\\"Precursor.Id\\\") AS unique_precursors,
                COUNT(DISTINCT \\\"Protein.Group\\\") AS unique_protein_groups,
                COUNT(DISTINCT \\\"Modified.Sequence\\\") AS unique_peptides,
                -- iRT metrics (raw model predictions, not calibrated)
                ROUND(CORR(\\\"iRT\\\", \\\"Predicted.iRT\\\"), 4) AS irt_correlation,
                ROUND(AVG(ABS(\\\"iRT\\\" - \\\"Predicted.iRT\\\")), 4) AS irt_mae,
                ROUND(MEDIAN(ABS(\\\"iRT\\\" - \\\"Predicted.iRT\\\")), 4) AS irt_median_ae,
                -- RT metrics (after calibration)
                ROUND(CORR(\\\"RT\\\", \\\"Predicted.RT\\\"), 4) AS rt_correlation,
                ROUND(AVG(ABS(\\\"RT\\\" - \\\"Predicted.RT\\\")), 4) AS rt_mae,
                ROUND(MEDIAN(ABS(\\\"RT\\\" - \\\"Predicted.RT\\\")), 4) AS rt_median_ae,
                -- IM metrics
                ROUND(CORR(\\\"IM\\\", \\\"Predicted.IM\\\"), 4) AS im_correlation,
                ROUND(AVG(ABS(\\\"IM\\\" - \\\"Predicted.IM\\\")), 4) AS im_mae,
                ROUND(MEDIAN(ABS(\\\"IM\\\" - \\\"Predicted.IM\\\")), 4) AS im_median_ae,
                -- FDR counts
                COUNT(CASE WHEN \\\"Q.Value\\\" <= 0.01 THEN 1 END) AS precursors_1pct_fdr,
                COUNT(CASE WHEN \\\"Q.Value\\\" <= 0.05 THEN 1 END) AS precursors_5pct_fdr,
                COUNT(CASE WHEN \\\"PG.Q.Value\\\" <= 0.01 THEN 1 END) AS pg_1pct_fdr
            FROM read_parquet('${report_glob}')
            WHERE \\\"iRT\\\" IS NOT NULL
              AND \\\"Predicted.iRT\\\" IS NOT NULL
        ) TO 'accuracy_metrics.tsv' (HEADER, DELIMITER '\t');
    "

    echo "Metrics calculated:" | tee -a accuracy_report.log
    cat accuracy_metrics.tsv | tee -a accuracy_report.log
    echo "" | tee -a accuracy_report.log

    # Export RT/iRT data for plotting
    /duckdb -c "
        COPY (
            SELECT
                \\\"Precursor.Id\\\",
                \\\"Modified.Sequence\\\",
                \\\"iRT\\\" AS observed_irt,
                \\\"Predicted.iRT\\\" AS predicted_irt,
                (\\\"iRT\\\" - \\\"Predicted.iRT\\\") AS irt_error,
                \\\"RT\\\" AS observed_rt,
                \\\"Predicted.RT\\\" AS predicted_rt,
                (\\\"RT\\\" - \\\"Predicted.RT\\\") AS rt_error,
                \\\"Q.Value\\\"
            FROM read_parquet('${report_glob}')
            WHERE \\\"iRT\\\" IS NOT NULL
              AND \\\"Predicted.iRT\\\" IS NOT NULL
              AND \\\"Q.Value\\\" <= 0.01
            ORDER BY \\\"iRT\\\"
        ) TO 'rt_accuracy.tsv' (HEADER, DELIMITER '\t');
    "

    RT_COUNT=\$(wc -l < rt_accuracy.tsv)
    echo "RT/iRT data points (1% FDR): \$((RT_COUNT - 1))" | tee -a accuracy_report.log

    # Export IM data for plotting (if available)
    IM_COUNT=\$(/duckdb -csv -noheader -c "
        SELECT COUNT(*)
        FROM read_parquet('${report_glob}')
        WHERE \\\"IM\\\" IS NOT NULL
          AND \\\"Predicted.IM\\\" IS NOT NULL
          AND \\\"IM\\\" > 0
          AND \\\"Predicted.IM\\\" > 0
    ")

    if [ "\$IM_COUNT" -gt 0 ]; then
        /duckdb -c "
            COPY (
                SELECT
                    \\\"Precursor.Id\\\",
                    \\\"Modified.Sequence\\\",
                    \\\"IM\\\" AS observed_im,
                    \\\"Predicted.IM\\\" AS predicted_im,
                    (\\\"IM\\\" - \\\"Predicted.IM\\\") AS im_error,
                    \\\"Q.Value\\\"
                FROM read_parquet('${report_glob}')
                WHERE \\\"IM\\\" IS NOT NULL
                  AND \\\"Predicted.IM\\\" IS NOT NULL
                  AND \\\"IM\\\" > 0
                  AND \\\"Predicted.IM\\\" > 0
                  AND \\\"Q.Value\\\" <= 0.01
                ORDER BY \\\"IM\\\"
            ) TO 'im_accuracy.tsv' (HEADER, DELIMITER '\t');
        "
        echo "IM data points (1% FDR): \$IM_COUNT" | tee -a accuracy_report.log
    else
        echo "No IM data available (Orbitrap instrument)" | tee -a accuracy_report.log
    fi

    echo "" | tee -a accuracy_report.log
    echo "=== Report Complete ===" | tee -a accuracy_report.log
    """
}
