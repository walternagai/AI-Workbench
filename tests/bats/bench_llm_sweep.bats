#!/usr/bin/env bats
# Unit tests for `awb benchmark llm sweep` (benchmarks/llm/sweep.sh).
#
# llama-bench is replaced by a fake binary (LLAMA_BENCH) that prints a CSV
# shaped like the real one, so these run without hardware or a built llama.cpp.
#
# Run with:
#   bats tests/bats/bench_llm_sweep.bats

setup() {
    AWB_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
    export AWB_ROOT
    export AWB_LOG_FILE="${BATS_TEST_TMPDIR}/awb.log"

    # shellcheck source=lib/colors.sh
    source "${AWB_ROOT}/lib/colors.sh"
    # shellcheck source=lib/logger.sh
    source "${AWB_ROOT}/lib/logger.sh"
    # shellcheck source=lib/utils.sh
    source "${AWB_ROOT}/lib/utils.sh"
    # shellcheck source=benchmarks/llm/run.sh
    source "${AWB_ROOT}/benchmarks/llm/run.sh"

    FAKE_BIN="${BATS_TEST_TMPDIR}/llama-bench"
    cat > "$FAKE_BIN" <<'EOF'
#!/usr/bin/env bash
# Fake llama-bench: echoes the -ngl value back so tests can tell runs apart.
ngl=""
while (( $# )); do
    [[ "$1" == "-ngl" ]] && ngl="$2"
    shift
done
echo "build_commit,model_filename,n_gpu_layers,avg_ts"
echo "\"abc\",\"m.gguf\",$ngl,10.0"
echo "\"abc\",\"m.gguf\",$ngl,1.0"
EOF
    chmod +x "$FAKE_BIN"
    export LLAMA_BENCH="$FAKE_BIN"

    MODEL="${BATS_TEST_TMPDIR}/m.gguf"
    : > "$MODEL"
    OUT="${BATS_TEST_TMPDIR}/results.csv"
}

@test "sweep writes header once and one row per llama-bench row" {
    # The fake binary does not expand comma lists, so one call -> 2 data rows.
    run benchmark_llm sweep -o "$OUT" -l 0,99 "$MODEL"
    [ "$status" -eq 0 ]
    [ "$(wc -l < "$OUT")" -eq 3 ]
    [ "$(head -1 "$OUT" | cut -d, -f1)" = "run_at" ]
    [ "$(grep -c '^run_at,' "$OUT")" -eq 1 ]
}

@test "second invocation appends data rows without repeating the header" {
    benchmark_llm sweep -o "$OUT" -l 0 "$MODEL"
    run benchmark_llm sweep -o "$OUT" -l 99 "$MODEL"
    [ "$status" -eq 0 ]
    [ "$(wc -l < "$OUT")" -eq 5 ]
    [ "$(grep -c '^run_at,' "$OUT")" -eq 1 ]
    grep -q ',99,10.0$' "$OUT"
}

@test "every data row carries an ISO-8601 run_at timestamp" {
    benchmark_llm sweep -o "$OUT" "$MODEL"
    tail -n +2 "$OUT" | while IFS= read -r line; do
        [[ "$line" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T ]] || { echo "bad row: $line"; return 1; }
    done
}

@test "sweep fails without -o" {
    run benchmark_llm sweep "$MODEL"
    [ "$status" -ne 0 ]
    [[ "$output" == *"-o"* ]]
}

@test "sweep fails without a model" {
    run benchmark_llm sweep -o "$OUT"
    [ "$status" -ne 0 ]
    [[ "$output" == *"modelo"* ]]
}

@test "sweep fails on a missing model file" {
    run benchmark_llm sweep -o "$OUT" "${BATS_TEST_TMPDIR}/nope.gguf"
    [ "$status" -ne 0 ]
    [[ "$output" == *"Model not found"* ]]
}

@test "sweep fails loudly when llama-bench exits non-zero" {
    printf '#!/usr/bin/env bash\nexit 3\n' > "$FAKE_BIN"
    run benchmark_llm sweep -o "$OUT" "$MODEL"
    [ "$status" -ne 0 ]
    [[ "$output" == *"execution failed"* ]]
}

@test "plain llm benchmark still dispatches to llama-bench path (no sweep keyword)" {
    run benchmark_llm "${BATS_TEST_TMPDIR}/missing.gguf"
    [ "$status" -ne 0 ]
    [[ "$output" != *"sweep"* ]]
    [[ "$output" == *"not found"* ]]
}
