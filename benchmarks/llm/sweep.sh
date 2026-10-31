#!/usr/bin/env bash
# benchmarks/llm/sweep.sh — varredura do llama-bench sobre uma matriz de
# parâmetros, acumulando os resultados em um único CSV. Sourced por
# benchmarks/llm/run.sh e acessada via:
#   awb benchmark llm sweep -o results.csv [-r 3] [-p 128] [-n 32]
#       [-t 6] [-l 0,99] [-b 2048] model1.gguf [model2.gguf ...]
#
# Listas separadas por vírgula (-t, -l, -b) são expandidas pelo próprio
# llama-bench, gerando uma linha por combinação. Cada linha do CSV recebe
# uma coluna extra `run_at` com o instante da execução.
set -euo pipefail
AWB_ROOT="${AWB_ROOT:?must be sourced from install.sh}"

benchmark_llm_sweep() {
    local out="" reps=3 pp=128 tg=32 threads=6 ngl=99 batch=2048 opt
    local bin="${LLAMA_BENCH:-${AI_HOME:-$HOME/ai}/src/llama.cpp/build/bin/llama-bench}"

    # OPTIND local: esta função pode ser chamada mais de uma vez na mesma shell.
    local OPTIND=1
    while getopts ":o:r:p:n:t:l:b:" opt; do
        case "$opt" in
            o) out="$OPTARG" ;;
            r) reps="$OPTARG" ;;
            p) pp="$OPTARG" ;;
            n) tg="$OPTARG" ;;
            t) threads="$OPTARG" ;;
            l) ngl="$OPTARG" ;;
            b) batch="$OPTARG" ;;
            *) fail_loud "sweep: opção inválida -$OPTARG (uso: awb benchmark llm sweep -o arquivo.csv [opções] <modelo.gguf>...)" ;;
        esac
    done
    shift $((OPTIND - 1))

    [[ -n "$out" ]] || fail_loud "sweep: informe o arquivo de saída com -o"
    (( $# > 0 )) || fail_loud "sweep: informe ao menos um modelo .gguf"
    [[ -x "$bin" ]] || fail_loud "llama-bench not found at $bin. Build llama.cpp first (or set LLAMA_BENCH)."

    local model
    for model in "$@"; do
        [[ -f "$model" ]] || fail_loud "Model not found: $model"
    done

    ensure_dir "$(dirname "$out")"

    local ts tmp
    ts="$(date -Iseconds)"
    tmp="$(mktemp)"

    log_step "Sweep llama-bench -> $out"
    for model in "$@"; do
        log_info "$(basename "$model")  ngl=$ngl t=$threads p=$pp n=$tg r=$reps b=$batch"
        # stdout = CSV do llama-bench; progresso e avisos seguem para o terminal.
        if ! "$bin" -m "$model" -p "$pp" -n "$tg" -r "$reps" \
                -t "$threads" -ngl "$ngl" -b "$batch" -o csv > "$tmp"; then
            rm -f "$tmp"
            fail_loud "llama-bench execution failed for $model"
        fi

        if [[ ! -s "$out" ]]; then
            # Primeira gravação: cabeçalho + linhas com run_at.
            awk -v ts="$ts" 'NR == 1 { print "run_at," $0; next } { print ts "," $0 }' "$tmp" > "$out"
        else
            # Arquivo já existe: só anexa as linhas de dados.
            awk -v ts="$ts" 'NR > 1 { print ts "," $0 }' "$tmp" >> "$out"
        fi
    done
    rm -f "$tmp"

    log_ok "Sweep complete: $(( $(wc -l < "$out") - 1 )) linhas em $out"
}
