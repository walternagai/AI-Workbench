#!/usr/bin/env bash
# benchmarks/whisper/run.sh — transcription throughput benchmark.
set -euo pipefail
AWB_ROOT="${AWB_ROOT:?must be sourced from install.sh}"

benchmark_whisper() {
    local audio_path="${1:?usage: benchmark_whisper <path-to-audio>}"
    local bin="${AI_HOME:-$HOME/ai}/bin/whisper-cli"
    local model="${AI_HOME:-$HOME/ai}/models/whisper/ggml-base.en.bin"

    [[ -x "$bin" ]] || fail_loud "whisper-cli not found. Run: awb runtime install whisper"
    [[ -f "$model" ]] || fail_loud "Whisper model not found at $model. Run: awb model install whisper-base.en"
    [[ -f "$audio_path" ]] || fail_loud "Audio file not found: $audio_path"

    log_step "Benchmarking Whisper transcription"
    ensure_dir "${AWB_ROOT}/reports"

    local start end
    start=$(date +%s.%N)
    "$bin" -f "$audio_path" -m "$model" > /tmp/awb_whisper_out.$$ 2>&1 \
        || fail_loud "whisper-cli execution failed"
    end=$(date +%s.%N)

    local elapsed
    elapsed=$(echo "$end - $start" | bc)
    log_ok "Transcription completed in ${elapsed}s"
    rm -f /tmp/awb_whisper_out.$$
}
