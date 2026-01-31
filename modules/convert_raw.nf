// ThermoRawFileParser Conversion Module
// Converts Thermo RAW files to indexed mzML format
//
// This is used specifically for InfinDIA presearch where the Linux
// ThermoRaw reader in DIA-NN may fail on certain instrument types.
// Regular DIA-NN quantification handles RAW files differently and
// typically works fine.

process CONVERT_RAW_TO_MZML {
    label 'thermoraw'

    tag "${raw_file.name}"

    input:
    path raw_file    // Single RAW file to convert

    output:
    path "*.mzML", emit: mzml_file

    script:
    // ThermoRawFileParser options:
    // -f 2 = indexed mzML output
    // -i = input file
    // -o = output directory
    """
    echo "Converting ${raw_file} to mzML..."
    ThermoRawFileParser -i ${raw_file} -o . -f 2
    ls -la *.mzML
    """
}
