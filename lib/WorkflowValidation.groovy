/**
 * Workflow parameter validation utilities
 * Provides reusable validation functions for workflow parameters
 */
class WorkflowValidation {

    /**
     * Validate that required parameters are provided
     * @param params The workflow params object
     * @param required Map of parameter names to descriptions
     * @return true if all required params exist, exits workflow otherwise
     */
    static void validateRequired(params, Map<String, String> required) {
        def missing = []

        required.each { param, description ->
            if (!params[param]) {
                missing << "  --${param}: ${description}"
            }
        }

        if (missing) {
            log.error "ERROR: Missing required parameters:\n${missing.join('\n')}"
            System.exit(1)
        }
    }

    /**
     * Validate that a file exists
     * @param filePath Path to the file
     * @param paramName Parameter name for error message
     * @return true if file exists, exits workflow otherwise
     */
    static void validateFileExists(filePath, String paramName) {
        def file = filePath instanceof java.nio.file.Path ? filePath : new File(filePath.toString())

        if (!file.exists()) {
            log.error "ERROR: ${paramName} file not found: ${filePath}"
            System.exit(1)
        }
    }
}
