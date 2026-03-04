// FASTA Subsetting Module
// Filters a FASTA file to proteins identified in DIA-NN parquet report(s).
//
// Extracts unique protein accessions from the Protein.Group column
// (splitting semicolon-delimited groups) and retains matching FASTA entries.
// Intended for search space reduction in the QUANTIFY_FASTA_SUBSET workflow.

process SUBSET_FASTA {
    label 'duckdb'

    publishDir "${params.outdir}${subdir ? '/' + subdir : ''}",
        mode: 'copy',
        overwrite: true

    tag "${fasta.baseName}"

    input:
    path pg_source     // Parquet file(s) containing Protein.Group column
    path fasta         // Input FASTA file
    val subdir         // Optional output subdirectory
    val output_name    // Output file name (without .fasta extension)

    output:
    path "${output_name}.fasta", emit: subset_fasta
    path "subset_fasta.log", emit: log

    script:
    """
    echo "=== FASTA Subsetting ===" | tee subset_fasta.log
    echo "PG source: ${pg_source}" | tee -a subset_fasta.log
    echo "FASTA:     ${fasta}" | tee -a subset_fasta.log
    echo "Output:    ${output_name}.fasta" | tee -a subset_fasta.log
    echo "" | tee -a subset_fasta.log

    # Build DuckDB list from staged Protein.Group source file(s)
    # (same pattern as subset_library.nf)
    PG_LIST=\$(echo "${pg_source}" | tr ' ' '\\n' | sed "s/.*/'&'/" | paste -sd, -)

    # Extract unique protein accessions (split semicolon-delimited Protein.Group values)
    # Note: avoid '' (empty string literal) in script blocks - triggers Nextflow DSL2 lexer bug
    /duckdb -csv -noheader -c "
        SELECT DISTINCT \\\"Protein.Group\\\"
        FROM read_parquet([\$PG_LIST])
        WHERE \\\"Protein.Group\\\" IS NOT NULL
    " | tr ';' '\\n' | awk NF | sort -u > protein_ids.txt

    ID_COUNT=\$(wc -l < protein_ids.txt | tr -d ' ')
    echo "Unique protein IDs: \$ID_COUNT" | tee -a subset_fasta.log

    if [ "\$ID_COUNT" -eq 0 ]; then
        echo "ERROR: No protein IDs found in presearch report" | tee -a subset_fasta.log
        exit 1
    fi

    # Count input FASTA sequences
    INPUT_SEQS=\$(grep -c '^>' ${fasta} || echo 0)
    echo "Input FASTA sequences: \$INPUT_SEQS" | tee -a subset_fasta.log
    echo "" | tee -a subset_fasta.log

    # Filter FASTA by matching UniProt accession from header
    # Supports: >sp|ACCESSION|GENE, >tr|ACCESSION|GENE, or plain >ACCESSION
    awk '
        NR==FNR { ids[\$1]=1; next }
        /^>/ {
            n = split(\$1, parts, "|")
            accession = (n >= 2) ? parts[2] : substr(\$1, 2)
            write = (accession in ids)
        }
        write { print }
    ' protein_ids.txt ${fasta} > "${output_name}.fasta"

    OUTPUT_SEQS=\$(grep -c '^>' "${output_name}.fasta" || echo 0)
    echo "Output FASTA sequences: \$OUTPUT_SEQS" | tee -a subset_fasta.log

    if [ "\$INPUT_SEQS" -gt 0 ]; then
        REDUCTION=\$(awk "BEGIN {printf \\"%.1f\\", (1 - \$OUTPUT_SEQS / \$INPUT_SEQS) * 100}")
        echo "Reduction:              \$REDUCTION%" | tee -a subset_fasta.log
    fi

    echo "" | tee -a subset_fasta.log
    echo "=== FASTA Subsetting Complete ===" | tee -a subset_fasta.log
    """
}
