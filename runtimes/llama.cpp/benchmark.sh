#!/usr/bin/env bash
# runtimes/llama.cpp/benchmark.sh — wraps llama-bench and normalizes output
# into the shared benchmarks/ JSON schema (see benchmarks/llm/run.sh).
set -euo pipefail
AWB_ROOT="${AWB_ROOT:?must be sourced from install.sh}"

benchmark_llama_cpp() {
    local model_path="${1:?usage: benchmark_llama_cpp <path-to-gguf>}"
    local bin="${AI_HOME:-$HOME/ai}/src/llama.cpp/build/bin/llama-bench"

    [[ -x "$bin" ]] || fail_loud "llama-bench not found at $bin. Build llama.cpp first."
    [[ -f "$model_path" ]] || fail_loud "Model not found: $model_path"

    log_step "Benchmarking llama.cpp on $(basename "$model_path")"
    ensure_dir "${AWB_ROOT}/reports"

    "$bin" -m "$model_path" -p 512 -n 128 -o json \
        > "${AWB_ROOT}/reports/benchmark_llama_cpp_$(date +%Y%m%d_%H%M%S).json" \
        || fail_loud "llama-bench execution failed"

    log_ok "Benchmark complete. Results written to reports/."
}
