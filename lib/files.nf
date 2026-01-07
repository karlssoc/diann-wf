/*
 * Shared File Utilities for DIA-NN Workflow
 *
 * This module provides reusable functions for file operations used across workflows.
 */

/**
 * Count MS files in a directory
 *
 * Counts mass spectrometry files in a directory, handling both recursive and non-recursive modes.
 * Supports common MS file formats: .mzML, .raw, .d, .wiff, .dia
 *
 * @param sample_dir  File object representing the sample directory
 * @param recursive   Boolean flag for recursive directory traversal
 * @return            Integer count of MS files found
 *
 * Special handling:
 *   - Bruker .d directories are counted as single files (not traversed)
 *   - Recursive mode traverses all subdirectories
 *   - Non-recursive mode only checks immediate directory contents
 */
def countMSFiles(sample_dir, recursive = false) {
    def file_extensions = ['.mzML', '.raw', '.d', '.wiff', '.dia']
    def file_count = 0

    if (recursive) {
        // Recursive counting: traverse all subdirectories
        sample_dir.eachFileRecurse { file ->
            if (file.isFile()) {
                def extension = file.name.substring(file.name.lastIndexOf('.'))
                if (file_extensions.contains(extension)) {
                    file_count++
                }
            } else if (file.isDirectory() && file.name.endsWith('.d')) {
                // Count Bruker .d directories as one file
                file_count++
            }
        }
    } else {
        // Non-recursive: only immediate directory
        sample_dir.listFiles().each { file ->
            if (file.isFile()) {
                def extension = file.name.substring(file.name.lastIndexOf('.'))
                if (file_extensions.contains(extension)) {
                    file_count++
                }
            } else if (file.isDirectory() && file.name.endsWith('.d')) {
                // Count Bruker .d directories as one file
                file_count++
            }
        }
    }

    return file_count
}

/**
 * Get MS file extensions
 *
 * Returns list of supported MS file extensions.
 * Useful for validation and filtering operations.
 *
 * @return List of file extensions (with dots)
 */
def getSupportedExtensions() {
    return ['.mzML', '.raw', '.d', '.wiff']
}
