#!/usr/bin/env bash
# benchmarks/embeddings/run.sh — embedding generation throughput (sentence-transformers).
set -euo pipefail
AWB_ROOT="${AWB_ROOT:?must be sourced from install.sh}"

# Extra arguments are forwarded verbatim to bench_embeddings.py
# (--model, --batch-size, --iterations), per `awb benchmark <target> [args...]`.
benchmark_embeddings() {
    local venv="$HOME/venvs/rag"
    [[ -d "$venv" ]] || fail_loud "rag venv missing at ${venv}. Run './install.sh --only python' first, or './install.sh' for a full install."

    log_step "Benchmarking embedding generation"
    # shellcheck disable=SC1091
    source "$venv/bin/activate"
    python3 "${AWB_ROOT}/benchmarks/embeddings/bench_embeddings.py" "$@" \
        || { deactivate; fail_loud "Embeddings benchmark script failed"; }
    deactivate
    log_ok "Embeddings benchmark complete."
}
