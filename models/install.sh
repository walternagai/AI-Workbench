#!/usr/bin/env bash
# models/install.sh — Model Manager. Backs the `awb model install <name>`
# CLI command. Knows a small curated catalog of GGUF LLM models and a
# separate one of whisper.cpp GGML speech models; anything else can be
# installed by passing a raw "repo_id:filename" pair.
set -euo pipefail
AWB_ROOT="${AWB_ROOT:?must be sourced from install.sh}"

AWB_MODELS_DIR="${AI_HOME:-$HOME/ai}/models/gguf"
AWB_WHISPER_MODELS_DIR="${AI_HOME:-$HOME/ai}/models/whisper"

# Allow forced re-install via env var AWB_FORCE_REINSTALL=true
# (e.g. AWB_FORCE_REINSTALL=true awb model install qwen3)

# Curated catalog: name -> "hf_repo_id|filename|approx_size|notes"
_awb_model_catalog() {
    case "$1" in
        gemma4-e2b)
            echo "ggml-org/gemma-4-E2B-it-GGUF|gemma-4-E2B-it-Q8_0.gguf|~5GB|Gemma 4 E2B Q8_0 — new default; multimodal (text/image/audio), 128K ctx, Apache-2.0" ;;
        gemma4-e4b)
            echo "ggml-org/gemma-4-E4B-it-GGUF|gemma-4-E4B-it-Q8_0.gguf|~8GB|Gemma 4 E4B Q8_0 — stronger edge model, same feature set" ;;
        gemma4-26b)
            echo "ggml-org/gemma-4-26B-A4B-it-GGUF|gemma-4-26B-A4B-it-Q4_0.gguf|~14.6GB|Gemma 4 26B A4B Q4_0 — MoE, frontier-level reasoning, needs ~16GB VRAM" ;;
        gemma3)
            echo "google/gemma-3-4b-it-qat-q4_0-gguf|gemma-3-4b-it-q4_0.gguf|~3.2GB|Gemma 3, quantized for low-memory systems (gated repo: accept the license at hf.co/google/gemma-3-4b-it-qat-q4_0-gguf first)" ;;
        gemma3-e2b)
            echo "ggml-org/gemma-3n-E2B-it-GGUF|gemma-3n-E2B-it-Q8_0.gguf|~4.8GB|Gemma 3n E2B Q8_0 — superseded by gemma4-e2b, kept for existing installs" ;;
        qwen3)
            echo "Qwen/Qwen3-8B-GGUF|Qwen3-8B-Q4_K_M.gguf|~5GB|Qwen3 8B, general purpose" ;;
        qwen3-4b)
            echo "Qwen/Qwen3-4B-GGUF|Qwen3-4B-Q4_K_M.gguf|~2.5GB|Qwen3 4B, lighter footprint" ;;
        phi4)
            echo "microsoft/phi-4-gguf|phi-4-Q4_K.gguf|~9GB|Phi-4, strong reasoning-per-parameter" ;;
        deepseek-coder-v2)
            echo "bartowski/DeepSeek-Coder-V2-Lite-Instruct-GGUF|DeepSeek-Coder-V2-Lite-Instruct-Q4_K_M.gguf|~10.4GB|Code-specialized" ;;
        *)
            return 1 ;;
    esac
}

# Curated catalog of whisper.cpp GGML speech models (distinct from the GGUF
# LLM catalog above: different upstream repo, different destination dir).
# benchmarks/whisper/run.sh expects whisper-base.en by default.
_awb_whisper_catalog() {
    case "$1" in
        whisper-tiny.en)
            echo "ggerganov/whisper.cpp|ggml-tiny.en.bin|~75MB|Fastest, English-only, lowest accuracy" ;;
        whisper-base.en)
            echo "ggerganov/whisper.cpp|ggml-base.en.bin|~142MB|Good speed/accuracy balance, English-only — used by benchmarks/whisper" ;;
        whisper-small.en)
            echo "ggerganov/whisper.cpp|ggml-small.en.bin|~466MB|Higher accuracy, English-only" ;;
        whisper-medium.en)
            echo "ggerganov/whisper.cpp|ggml-medium.en.bin|~1.5GB|High accuracy, English-only" ;;
        whisper-large-v3-turbo)
            echo "ggerganov/whisper.cpp|ggml-large-v3-turbo.bin|~1.6GB|Large v3 Turbo — best accuracy/speed of the .en line, multilingual" ;;
        *)
            return 1 ;;
    esac
}

model_catalog_list() {
    printf '%b%s%b\n' "${C_BOLD}" "Available LLM models (name — size — notes):" "${C_RESET}"
    for name in gemma3 gemma3-e2b gemma4-e2b gemma4-e4b gemma4-26b qwen3 qwen3-4b phi4 deepseek-coder-v2; do
        local entry size notes
        entry="$(_awb_model_catalog "$name")"
        size="$(echo "$entry" | cut -d'|' -f3)"
        notes="$(echo "$entry" | cut -d'|' -f4)"
        printf '  %-20s %-10s %s\n' "$name" "$size" "$notes"
    done
    printf '\n%b%s%b\n' "${C_BOLD}" "Available Whisper speech models (name — size — notes):" "${C_RESET}"
    for name in whisper-tiny.en whisper-base.en whisper-small.en whisper-medium.en whisper-large-v3-turbo; do
        local entry size notes
        entry="$(_awb_whisper_catalog "$name")"
        size="$(echo "$entry" | cut -d'|' -f3)"
        notes="$(echo "$entry" | cut -d'|' -f4)"
        printf '  %-20s %-10s %s\n' "$name" "$size" "$notes"
    done
    printf '\nInstall with: %bawb model install <name>%b\n' "${C_BOLD}" "${C_RESET}"
    printf 'Or a raw HF pair: %bawb model install custom <repo_id> <filename>%b\n' "${C_BOLD}" "${C_RESET}"
}

# _install_catalog_entry <entry> <dest_dir> <force_flag> — shared by both
# catalogs: parses one "repo_id|filename|size|notes" line and downloads it.
_install_catalog_entry() {
    local entry="$1" dest_dir="$2" force_flag="$3"
    local repo_id filename size notes
    repo_id="$(echo "$entry" | cut -d'|' -f1)"
    filename="$(echo "$entry" | cut -d'|' -f2)"
    size="$(echo "$entry" | cut -d'|' -f3)"
    notes="$(echo "$entry" | cut -d'|' -f4)"

    log_step "Installing model: ${filename} (${size}) — ${notes}"
    ensure_dir "$dest_dir"
    awb_hf_download "$repo_id" "$filename" "$dest_dir" "$force_flag"
    log_ok "Model installed: ${dest_dir}/${filename}"
}

model_install() {
    local name="${1:?usage: model_install <name>|custom <repo_id> <filename>}"
    local force_flag=""
    [[ "${AWB_FORCE_REINSTALL:-false}" == "true" ]] && force_flag="--force"

    if [[ "$name" == "custom" ]]; then
        local repo_id="${2:?repo_id required for custom install}"
        local filename="${3:?filename required for custom install}"
        ensure_dir "$AWB_MODELS_DIR"
        awb_hf_download "$repo_id" "$filename" "$AWB_MODELS_DIR" "$force_flag"
        return 0
    fi

    local entry
    if entry="$(_awb_model_catalog "$name")"; then
        if [[ "${AWB_LOW_MEMORY:-false}" == "true" ]]; then
            log_warn "Low-memory system detected (${RAM_GB:-?}GB RAM). Prefer Q8_0 quantization on small models over Q4_K_M — quality loss from 4-bit quantization is proportionally larger on small models."
        fi
        _install_catalog_entry "$entry" "$AWB_MODELS_DIR" "$force_flag"
    elif entry="$(_awb_whisper_catalog "$name")"; then
        _install_catalog_entry "$entry" "$AWB_WHISPER_MODELS_DIR" "$force_flag"
    else
        fail_loud "Unknown model '$name'. Run 'awb model list' to see the catalog."
    fi
}

model_remove() {
    local filename="${1:?usage: model_remove <filename>}"
    local path
    for path in "${AWB_MODELS_DIR:?}/${filename}" "${AWB_WHISPER_MODELS_DIR:?}/${filename}"; do
        if [[ -f "$path" ]]; then
            rm -f "$path" && log_ok "Removed model: ${filename}" \
                || fail_loud "Failed to remove model: ${filename}"
            return 0
        fi
    done
    log_warn "Model not found: ${filename}"
}
