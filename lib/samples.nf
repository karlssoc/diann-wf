/*
 * Shared Sample Parsing Utilities for DIA-NN Workflow
 *
 * This module provides reusable functions for parsing sample definitions from various formats.
 */

// Import file counting utilities
include { countMSFiles } from './files'

/**
 * Parse samples from various input formats
 *
 * Handles sample definitions provided in multiple formats:
 *   1. Already parsed List (from params file)
 *   2. Inline JSON string (command line)
 *   3. YAML file path
 *   4. JSON file path
 *
 * @param samples_param  The samples parameter (can be List, String, or file path)
 * @return              List of sample maps with keys: id, dir, file_type, recursive
 *
 * Example sample format:
 *   [
 *     [id: 'sample1', dir: 'input/sample1', file_type: 'd', recursive: false],
 *     [id: 'sample2', dir: 'input/sample2', file_type: 'raw', recursive: true]
 *   ]
 */
def parseSamples(samples_param) {
    def samples_list

    if (samples_param instanceof List) {
        // Already parsed list from params file
        samples_list = samples_param
    } else if (samples_param instanceof String && samples_param.startsWith('[')) {
        // Inline JSON string
        samples_list = new groovy.json.JsonSlurper().parseText(samples_param)
    } else if (samples_param instanceof String) {
        // File path
        def samples_file = file(samples_param)
        if (!samples_file.exists()) {
            log.error "ERROR: Samples file not found: ${samples_param}"
            System.exit(1)
        }

        if (samples_file.name.endsWith('.yaml') || samples_file.name.endsWith('.yml')) {
            // Parse YAML file
            samples_list = new org.yaml.snakeyaml.Yaml().load(samples_file.text).samples
        } else {
            // Parse JSON file
            samples_list = new groovy.json.JsonSlurper().parseText(samples_file.text)
        }
    } else {
        log.error "ERROR: Invalid samples parameter type: ${samples_param.getClass()}"
        System.exit(1)
    }

    return samples_list
}

/**
 * Create samples channel with file counting
 *
 * Creates a Nextflow channel from sample definitions, validates directories,
 * counts MS files, and prepares tuples for downstream processes.
 *
 * @param samples_list  List of sample maps (from parseSamples())
 * @param subdir        Optional subdirectory for output organization (default: '')
 * @return             Channel emitting tuples: (sample_id, sample_dir, file_type, subdir, recursive, file_count)
 */
def createSamplesChannel(samples_list, subdir = '') {
    return Channel.fromList(samples_list)
        .map { sample ->
            def sample_id = sample.id
            def sample_dir = file(sample.dir)
            def file_type = sample.file_type ?: 'raw'
            def recursive = sample.recursive ?: false

            // Validate sample directory exists
            if (!sample_dir.exists()) {
                log.error "ERROR: Sample directory not found: ${sample.dir}"
                System.exit(1)
            }

            // Count MS files in directory for dynamic time allocation
            def file_count = countMSFiles(sample_dir, recursive)

            // Log file count for user awareness
            def subdir_info = subdir ? " (${subdir})" : ""
            log.info "Sample ${sample_id}${subdir_info}: Found ${file_count} MS files"

            tuple(sample_id, sample_dir, file_type, subdir, recursive, file_count)
        }
}

/**
 * Validate sample definition
 *
 * Checks that a sample map contains required fields and valid values.
 *
 * @param sample  Sample map to validate
 * @return       True if valid, false otherwise
 */
def validateSample(sample) {
    if (!sample.id) {
        log.error "ERROR: Sample missing 'id' field: ${sample}"
        return false
    }

    if (!sample.dir) {
        log.error "ERROR: Sample '${sample.id}' missing 'dir' field"
        return false
    }

    def valid_file_types = ['d', 'raw', 'mzML', 'wiff']
    def file_type = sample.file_type ?: 'raw'
    if (!valid_file_types.contains(file_type)) {
        log.warn "WARNING: Sample '${sample.id}' has unusual file_type: ${file_type}"
    }

    return true
}
