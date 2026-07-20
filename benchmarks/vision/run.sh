#!/usr/bin/env bash
# benchmarks/vision/run.sh — computer vision inference throughput (ONNX Runtime).
set -euo pipefail
AWB_ROOT="${AWB_ROOT:?must be sourced from install.sh}"

benchmark_vision() {
    local model_path="${1:?usage: benchmark_vision <path-to-onnx-model>}"
    local venv="$HOME/venvs/vision"

    [[ -d "$venv" ]] || fail_loud "vision venv missing; run python/create_envs.sh first."
    [[ -f "$model_path" ]] || fail_loud "Model not found: $model_path"

    log_step "Benchmarking vision inference"
    # shellcheck disable=SC1091
    source "$venv/bin/activate"
    python3 "${AWB_ROOT}/benchmarks/vision/bench_onnx.py" "$model_path" \
        || { deactivate; fail_loud "Vision benchmark script failed"; }
    deactivate
    log_ok "Vision benchmark complete."
}
