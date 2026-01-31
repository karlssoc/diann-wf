// ThermoRawFileParser Conversion Module
// Converts Thermo RAW files to indexed mzML format
//
// This is used specifically for InfinDIA presearch where the Linux
// ThermoRaw reader in DIA-NN may fail on certain instrument types.
// Regular DIA-NN quantification handles RAW files differently and
// typically works fine.

process CONVERT_RAW_TO_MZML {
    label 'thermoraw'

    tag "Converting ${raw_files instanceof List ? raw_files.size() : 1} RAW files"

    input:
    path raw_files    // RAW files to convert (can be list)

    output:
    path "*.mzML", emit: mzml_files

    script:
    // ThermoRawFileParser options:
    // -f 2 = indexed mzML output
    // -i = input file/directory
    // -o = output directory
    def files_list = raw_files instanceof List ? raw_files : [raw_files]
    def convert_cmds = files_list.collect { f ->
        "ThermoRawFileParser -i ${f} -o . -f 2"
    }.join('\n')

    """
    echo "=== Converting RAW to mzML ==="
    echo "Files to convert: ${files_list.size()}"
    echo ""

    ${convert_cmds}

    echo ""
    echo "=== Conversion Complete ==="
    ls -la *.mzML
    """
}
