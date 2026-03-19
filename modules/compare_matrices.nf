// PG Matrix Comparison Module
// Compares two pg_matrix.tsv files to assess quantitative agreement between runs
//
// Use case: "Sanity pair" comparison after running the same workflow with different
// parameters, models, or configurations. Detects systematic bias, PG overlap,
// and quantitative agreement.
//
// Outputs:
//   - comparison_metrics.tsv: Core metrics (overlap, correlation, log2 ratios)
//   - comparison_report.log: Detailed report

process COMPARE_PG_MATRICES {
    label 'duckdb'

    publishDir "${params.outdir}${subdir ? '/' + subdir : ''}",
        mode: 'copy',
        overwrite: true

    tag "${label_a}_vs_${label_b}"

    input:
    path matrix_a           // First pg_matrix.tsv
    path matrix_b           // Second pg_matrix.tsv
    val label_a             // Label for first matrix
    val label_b             // Label for second matrix
    val subdir              // Output subdirectory

    output:
    path "comparison_metrics.tsv", emit: metrics
    path "comparison_report.log", emit: report

    script:
    """
    echo "=== PG Matrix Comparison ===" | tee comparison_report.log
    echo "Matrix A: ${label_a}" | tee -a comparison_report.log
    echo "Matrix B: ${label_b}" | tee -a comparison_report.log
    echo "" | tee -a comparison_report.log

    # Count PGs
    PG_A=\$(( \$(wc -l < "${matrix_a}") - 1 ))
    PG_B=\$(( \$(wc -l < "${matrix_b}") - 1 ))
    echo "PGs in ${label_a}: \$PG_A" | tee -a comparison_report.log
    echo "PGs in ${label_b}: \$PG_B" | tee -a comparison_report.log
    echo "" | tee -a comparison_report.log

    # Compute overlap, quantitative agreement using DuckDB
    /duckdb -c "
        -- Load matrices
        CREATE TABLE A AS
        SELECT * FROM read_csv_auto('${matrix_a}', delim='\\t', header=true);

        CREATE TABLE B AS
        SELECT * FROM read_csv_auto('${matrix_b}', delim='\\t', header=true);

        -- Per-PG mean intensity (UNPIVOT handles variable sample columns)
        CREATE TABLE summary_a AS
        SELECT \\\"Protein.Group\\\",
               AVG(value) FILTER (WHERE value > 0 AND value IS NOT NULL) AS mean_intensity,
               COUNT(value) FILTER (WHERE value > 0 AND value IS NOT NULL) AS n_quantified
        FROM (
            UNPIVOT A
            ON COLUMNS(* EXCLUDE (\\\"Protein.Group\\\", \\\"Protein.Ids\\\", \\\"Protein.Names\\\",
                                   \\\"Genes\\\", \\\"First.Protein.Description\\\",
                                   \\\"N.Sequences\\\", \\\"N.Proteotypic.Sequences\\\"))
            INTO NAME sample VALUE value
        )
        GROUP BY \\\"Protein.Group\\\";

        CREATE TABLE summary_b AS
        SELECT \\\"Protein.Group\\\",
               AVG(value) FILTER (WHERE value > 0 AND value IS NOT NULL) AS mean_intensity,
               COUNT(value) FILTER (WHERE value > 0 AND value IS NOT NULL) AS n_quantified
        FROM (
            UNPIVOT B
            ON COLUMNS(* EXCLUDE (\\\"Protein.Group\\\", \\\"Protein.Ids\\\", \\\"Protein.Names\\\",
                                   \\\"Genes\\\", \\\"First.Protein.Description\\\",
                                   \\\"N.Sequences\\\", \\\"N.Proteotypic.Sequences\\\"))
            INTO NAME sample VALUE value
        )
        GROUP BY \\\"Protein.Group\\\";

        -- Overlap counts
        CREATE TABLE overlap AS
        SELECT
            (SELECT COUNT(*) FROM summary_a) AS pg_count_a,
            (SELECT COUNT(*) FROM summary_b) AS pg_count_b,
            (SELECT COUNT(*) FROM summary_a
             INNER JOIN summary_b USING (\\\"Protein.Group\\\")) AS shared,
            (SELECT COUNT(*) FROM summary_a a
             LEFT JOIN summary_b b USING (\\\"Protein.Group\\\")
             WHERE b.\\\"Protein.Group\\\" IS NULL) AS unique_a,
            (SELECT COUNT(*) FROM summary_b b
             LEFT JOIN summary_a a USING (\\\"Protein.Group\\\")
             WHERE a.\\\"Protein.Group\\\" IS NULL) AS unique_b;

        -- Combined metrics output
        COPY (
            SELECT
                '${label_a}' AS label_a,
                '${label_b}' AS label_b,
                o.pg_count_a,
                o.pg_count_b,
                o.shared,
                o.unique_a,
                o.unique_b,
                ROUND(o.shared * 100.0 / (o.pg_count_a + o.pg_count_b - o.shared), 1) AS overlap_pct,
                q.*
            FROM overlap o,
            (SELECT
                COUNT(*) AS n_compared,
                ROUND(CORR(log2_a, log2_b), 4) AS pearson_r,
                ROUND(MEDIAN(log2_ratio), 4) AS log2_ratio_median,
                ROUND(AVG(log2_ratio), 4) AS log2_ratio_mean,
                ROUND(STDDEV(log2_ratio), 4) AS log2_ratio_sd,
                ROUND(COUNT(CASE WHEN ABS(log2_ratio) > 0.2 THEN 1 END) * 1.0 / COUNT(*), 4) AS frac_gt_0_2,
                ROUND(COUNT(CASE WHEN ABS(log2_ratio) > 0.5 THEN 1 END) * 1.0 / COUNT(*), 4) AS frac_gt_0_5,
                ROUND(COUNT(CASE WHEN ABS(log2_ratio) > 1.0 THEN 1 END) * 1.0 / COUNT(*), 4) AS frac_gt_1_0
            FROM (
                SELECT
                    LN(a.mean_intensity) / LN(2) AS log2_a,
                    LN(b.mean_intensity) / LN(2) AS log2_b,
                    LN(a.mean_intensity / b.mean_intensity) / LN(2) AS log2_ratio
                FROM summary_a a
                INNER JOIN summary_b b ON a.\\\"Protein.Group\\\" = b.\\\"Protein.Group\\\"
                WHERE a.mean_intensity > 0 AND b.mean_intensity > 0
            )) q
        ) TO 'comparison_metrics.tsv' (HEADER, DELIMITER '\\t');
    "

    echo "Comparison metrics:" | tee -a comparison_report.log
    cat comparison_metrics.tsv | tee -a comparison_report.log
    echo "" | tee -a comparison_report.log
    echo "=== Comparison Complete ===" | tee -a comparison_report.log
    """
}
