#!/usr/bin/env bash
# benchmarks/embeddings/run.sh — embedding generation throughput (sentence-transformers).
set -euo pipefail
AWB_ROOT="${AWB_ROOT:?must be sourced from install.sh}"

benchmark_embeddings() {
    local venv="$HOME/venvs/rag"
    [[ -d "$venv" ]] || fail_loud "rag venv missing; run python/create_envs.sh first."

    log_step "Benchmarking embedding generation"
    # shellcheck disable=SC1091
    source "$venv/bin/activate"
    python3 "${AWB_ROOT}/benchmarks/embeddings/bench_embeddings.py" \
        || { deactivate; fail_loud "Embeddings benchmark script failed"; }
    deactivate
    log_ok "Embeddings benchmark complete."
}
