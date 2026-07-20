#!/usr/bin/env bash
# benchmarks/llm/run.sh — text generation benchmark. Delegates to the
# active runtime's own benchmark tool and normalizes output location.
set -euo pipefail
AWB_ROOT="${AWB_ROOT:?must be sourced from install.sh}"
# shellcheck source=runtimes/llama.cpp/benchmark.sh
source "${AWB_ROOT}/runtimes/llama.cpp/benchmark.sh"

benchmark_llm() {
    local model_path="${1:?usage: benchmark_llm <path-to-gguf>}"
    log_step "Running text generation benchmark"
    benchmark_llama_cpp "$model_path"
}
