/*
 * Shared Model Resolution Utilities for DIA-NN Workflow
 *
 * This module provides reusable functions for resolving pre-trained model files.
 */

/**
 * Resolve model files from preset or explicit paths
 *
 * Implements a 3-tier priority system:
 *   1. Explicit file paths (highest priority)
 *   2. Model preset from models/ directory
 *   3. NO_FILE placeholder (use DIA-NN defaults)
 *
 * @param params     Parameters object containing model settings
 * @param projectDir Project directory for resolving preset paths
 * @return          Map with keys: tokens, rt_model, im_model, fr_model (all File objects)
 *
 * Example usage:
 *   def models = resolveModelFiles(params, projectDir)
 *   GENERATE_LIBRARY(..., models.tokens, models.rt_model, models.im_model, models.fr_model)
 */
def resolveModelFiles(params, projectDir) {
    def tokens_file = file('NO_FILE')
    def rt_model_file = file('NO_FILE')
    def im_model_file = file('NO_FILE')
    def fr_model_file = file('NO_FILE')

    // Tokens file - Priority 1: Explicit path
    if (params.tokens) {
        tokens_file = file(params.tokens)
        if (!tokens_file.exists()) {
            log.error "ERROR: Tokens file not found: ${params.tokens}"
            System.exit(1)
        }
    } else if (params.model_preset) {
        // Priority 2: Model preset
        def tokens_path = "${projectDir}/models/${params.model_preset}/dict.txt"
        if (file(tokens_path).exists()) {
            tokens_file = file(tokens_path)
            log.info "Using model preset: ${params.model_preset}"
        } else {
            log.warn "Model preset '${params.model_preset}' tokens not found at ${tokens_path}"
        }
    }

    // RT model
    if (params.rt_model) {
        rt_model_file = file(params.rt_model)
        if (!rt_model_file.exists()) {
            log.error "ERROR: RT model file not found: ${params.rt_model}"
            System.exit(1)
        }
    } else if (params.model_preset) {
        def rt_path = "${projectDir}/models/${params.model_preset}/tuned_rt.pt"
        if (file(rt_path).exists()) {
            rt_model_file = file(rt_path)
        }
    }

    // IM model
    if (params.im_model) {
        im_model_file = file(params.im_model)
        if (!im_model_file.exists()) {
            log.error "ERROR: IM model file not found: ${params.im_model}"
            System.exit(1)
        }
    } else if (params.model_preset) {
        def im_path = "${projectDir}/models/${params.model_preset}/tuned_im.pt"
        if (file(im_path).exists()) {
            im_model_file = file(im_path)
        }
    }

    // FR model
    if (params.fr_model) {
        fr_model_file = file(params.fr_model)
        if (!fr_model_file.exists()) {
            log.error "ERROR: FR model file not found: ${params.fr_model}"
            System.exit(1)
        }
    } else if (params.model_preset) {
        def fr_path = "${projectDir}/models/${params.model_preset}/tuned_fr.pt"
        if (file(fr_path).exists()) {
            fr_model_file = file(fr_path)
        }
    }

    return [
        tokens: tokens_file,
        rt_model: rt_model_file,
        im_model: im_model_file,
        fr_model: fr_model_file
    ]
}

/**
 * Log model resolution details
 *
 * Provides user-friendly logging about which models are being used.
 *
 * @param models Map returned from resolveModelFiles()
 * @param params Parameters object
 */
def logModelInfo(models, params) {
    def using_models = (models.tokens.name != 'NO_FILE')

    log.info "Using models : ${using_models}"
    if (using_models) {
        if (params.model_preset) {
            log.info "  Preset     : ${params.model_preset}"
        }
        log.info "  Tokens     : ${models.tokens.name != 'NO_FILE' ? (params.tokens ?: 'from preset') : 'not provided'}"
        log.info "  RT model   : ${models.rt_model.name != 'NO_FILE' ? (params.rt_model ?: 'from preset') : 'not provided'}"
        log.info "  IM model   : ${models.im_model.name != 'NO_FILE' ? (params.im_model ?: 'from preset') : 'not provided'}"
        log.info "  FR model   : ${models.fr_model.name != 'NO_FILE' ? (params.fr_model ?: 'from preset') : 'not provided'}"
    }
}

/**
 * Check if model preset exists
 *
 * Validates that a model preset directory exists and contains expected files.
 *
 * @param preset_name Name of the preset
 * @param projectDir  Project directory
 * @return           True if preset exists and is valid
 */
def validateModelPreset(preset_name, projectDir) {
    def preset_dir = file("${projectDir}/models/${preset_name}")

    if (!preset_dir.exists() || !preset_dir.isDirectory()) {
        log.error "ERROR: Model preset directory not found: ${preset_dir}"
        return false
    }

    // Check for at least one model file
    def has_models = false
    ['dict.txt', 'tuned_rt.pt', 'tuned_im.pt', 'tuned_fr.pt'].each { filename ->
        if (file("${preset_dir}/${filename}").exists()) {
            has_models = true
        }
    }

    if (!has_models) {
        log.error "ERROR: Model preset '${preset_name}' contains no model files"
        return false
    }

    return true
}

/**
 * List available model presets
 *
 * Scans the models/ directory and returns list of available presets.
 *
 * @param projectDir Project directory
 * @return          List of preset names
 */
def listAvailablePresets(projectDir) {
    def models_dir = file("${projectDir}/models")

    if (!models_dir.exists()) {
        return []
    }

    def presets = []
    models_dir.eachDir { dir ->
        // Skip example and hidden directories
        if (!dir.name.startsWith('.') && !dir.name.startsWith('example-')) {
            presets << dir.name
        }
    }

    return presets
}
