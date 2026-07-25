#!/usr/bin/env bash
# models/install.sh — Model Manager. Backs the `awb model install <name>`
# CLI command. Knows a small curated catalog of GGUF models; anything else
# can be installed by passing a raw "repo_id:filename" pair.
set -euo pipefail
AWB_ROOT="${AWB_ROOT:?must be sourced from install.sh}"

AWB_MODELS_DIR="${AI_HOME:-$HOME/ai}/models/gguf"

# Allow forced re-install via env var AWB_FORCE_REINSTALL=true
# (e.g. AWB_FORCE_REINSTALL=true awb model install qwen3)

# Curated catalog: name -> "hf_repo_id|filename|approx_size|notes"
_awb_model_catalog() {
    case "$1" in
        gemma3)
            echo "google/gemma-3-4b-it-qat-q4_0-gguf|gemma-3-4b-it-q4_0.gguf|~2.5GB|Gemma 3, quantized for low-memory systems" ;;
        gemma3-e2b)
            echo "google/gemma-3n-E2B-it-GGUF|gemma-3n-E2B-it-Q8_0.gguf|~2GB|Gemma E2B Q8_0 — recommended for memory-constrained iGPU setups" ;;
        qwen3)
            echo "Qwen/Qwen3-8B-GGUF|qwen3-8b-q4_k_m.gguf|~5GB|Qwen3 8B, general purpose" ;;
        qwen3-4b)
            echo "Qwen/Qwen3-4B-GGUF|qwen3-4b-q4_k_m.gguf|~2.5GB|Qwen3 4B, lighter footprint" ;;
        phi4)
            echo "microsoft/phi-4-gguf|phi-4-q4_k_m.gguf|~9GB|Phi-4, strong reasoning-per-parameter" ;;
        deepseek-coder-v2)
            echo "deepseek-ai/DeepSeek-Coder-V2-Lite-Instruct-GGUF|deepseek-coder-v2-lite-instruct-q4_k_m.gguf|~10GB|Code-specialized" ;;
        *)
            return 1 ;;
    esac
}

model_catalog_list() {
    printf '%b%s%b\n' "${C_BOLD}" "Available models (name — size — notes):" "${C_RESET}"
    for name in gemma3 gemma3-e2b qwen3 qwen3-4b phi4 deepseek-coder-v2; do
        local entry size notes
        entry="$(_awb_model_catalog "$name")"
        size="$(echo "$entry" | cut -d'|' -f3)"
        notes="$(echo "$entry" | cut -d'|' -f4)"
        printf '  %-20s %-10s %s\n' "$name" "$size" "$notes"
    done
    printf '\nInstall with: %bawb model install <name>%b\n' "${C_BOLD}" "${C_RESET}"
    printf 'Or a raw HF pair: %bawb model install custom <repo_id> <filename>%b\n' "${C_BOLD}" "${C_RESET}"
}

model_install() {
    local name="${1:?usage: model_install <name>|custom <repo_id> <filename>}"
    local force_flag=""
    [[ "${AWB_FORCE_REINSTALL:-false}" == "true" ]] && force_flag="--force"

    ensure_dir "$AWB_MODELS_DIR"

    if [[ "$name" == "custom" ]]; then
        local repo_id="${2:?repo_id required for custom install}"
        local filename="${3:?filename required for custom install}"
        awb_hf_download "$repo_id" "$filename" "$AWB_MODELS_DIR" "$force_flag"
        return 0
    fi

    local entry repo_id filename size notes
    entry="$(_awb_model_catalog "$name")" || fail_loud "Unknown model '$name'. Run 'awb model list' to see the catalog."
    repo_id="$(echo "$entry" | cut -d'|' -f1)"
    filename="$(echo "$entry" | cut -d'|' -f2)"
    size="$(echo "$entry" | cut -d'|' -f3)"
    notes="$(echo "$entry" | cut -d'|' -f4)"

    log_step "Installing model: ${name} (${size}) — ${notes}"

    if [[ "${AWB_LOW_MEMORY:-false}" == "true" ]]; then
        log_warn "Low-memory system detected (${RAM_GB:-?}GB RAM). Prefer Q8_0 quantization on small models over Q4_K_M — quality loss from 4-bit quantization is proportionally larger on small models."
    fi

    awb_hf_download "$repo_id" "$filename" "$AWB_MODELS_DIR" "$force_flag"
    log_ok "Model installed: ${AWB_MODELS_DIR}/${filename}"
}

model_remove() {
    local filename="${1:?usage: model_remove <filename>}"
    local path="${AWB_MODELS_DIR:?}/${filename}"
    if [[ -f "$path" ]]; then
        rm -f "$path" && log_ok "Removed model: ${filename}" \
            || fail_loud "Failed to remove model: ${filename}"
    else
        log_warn "Model not found: ${filename}"
    fi
}
