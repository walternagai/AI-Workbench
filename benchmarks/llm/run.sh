#!/usr/bin/env bash
# benchmarks/llm/run.sh — text generation benchmark. Delegates to the
# active runtime's own benchmark tool and normalizes output location.
set -euo pipefail
AWB_ROOT="${AWB_ROOT:?must be sourced from install.sh}"
# shellcheck source=runtimes/llama.cpp/benchmark.sh
source "${AWB_ROOT}/runtimes/llama.cpp/benchmark.sh"
# shellcheck source=benchmarks/llm/sweep.sh
source "${AWB_ROOT}/benchmarks/llm/sweep.sh"

# Arguments after <model> are forwarded verbatim to llama-bench,
# per `awb benchmark <target> [args...]`.
# `awb benchmark llm sweep ...` runs the parameter sweep to CSV instead.
benchmark_llm() {
    if [[ "${1:-}" == "sweep" ]]; then
        shift
        benchmark_llm_sweep "$@"
        return
    fi
    local model_path="${1:?usage: benchmark_llm <path-to-gguf> [llama-bench args...]}"
    shift
    log_step "Running text generation benchmark"
    benchmark_llama_cpp "$model_path" "$@"
}
