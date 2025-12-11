/**
 * Sample parsing utilities
 * Provides reusable functions for parsing sample definitions from various formats
 */
class SampleParser {

    /**
     * Parse samples from various input formats
     * Supports:
     * - List: Already parsed samples list from params file
     * - JSON String: Inline JSON array
     * - File Path: YAML or JSON file containing samples
     *
     * @param samplesInput The samples parameter (can be List, String, or file path)
     * @return List of sample definitions
     */
    static List parseSamples(samplesInput) {
        def samples_list

        if (samplesInput instanceof List) {
            // Already a parsed list from params file
            samples_list = samplesInput

        } else if (samplesInput instanceof String && samplesInput.startsWith('[')) {
            // Inline JSON string
            samples_list = new groovy.json.JsonSlurper().parseText(samplesInput)

        } else if (samplesInput instanceof String) {
            // File path - read and parse
            def samples_file = new File(samplesInput)

            if (!samples_file.exists()) {
                log.error "ERROR: Samples file not found: ${samplesInput}"
                System.exit(1)
            }

            // Parse based on file extension
            if (samples_file.name.endsWith('.yaml') || samples_file.name.endsWith('.yml')) {
                def yaml_content = new org.yaml.snakeyaml.Yaml().load(samples_file.text)
                samples_list = yaml_content.samples
            } else {
                samples_list = new groovy.json.JsonSlurper().parseText(samples_file.text)
            }

        } else {
            log.error "ERROR: Invalid samples format. Must be List, JSON string, or file path"
            System.exit(1)
        }

        return samples_list
    }

    /**
     * Validate that all required fields exist in sample definitions
     * @param samples_list List of sample maps
     * @return true if valid, exits workflow otherwise
     */
    static void validateSamples(List samples_list) {
        if (!samples_list || samples_list.isEmpty()) {
            log.error "ERROR: No samples defined"
            System.exit(1)
        }

        samples_list.eachWithIndex { sample, index ->
            if (!sample.id) {
                log.error "ERROR: Sample at index ${index} missing required field 'id'"
                System.exit(1)
            }
            if (!sample.dir) {
                log.error "ERROR: Sample '${sample.id}' missing required field 'dir'"
                System.exit(1)
            }
        }
    }
}
