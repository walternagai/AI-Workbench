#!/usr/bin/env bash
# lib/downloader.sh — single choke point for every file/model/asset download
# in AI-Workbench, so retry, resume and checksum behavior is consistent
# everywhere instead of every module reimplementing curl/wget flags.

[[ -n "${AWB_DOWNLOADER_LOADED:-}" ]] && return 0
AWB_DOWNLOADER_LOADED=1

# awb_download <url> <dest_path> [sha256]
# Downloads with resume support; verifies checksum if provided.
# Fails loud on any network or verification error — never leaves a
# partial/corrupt file behind silently.
awb_download() {
    local url="$1" dest="$2" sha256="${3:-}"

    require_cmd curl "downloading assets"
    ensure_dir "$(dirname "$dest")"

    # If the file already exists, skip download — with checksum verification
    # when available, or at minimum a non-zero size guard.
    if [[ -f "$dest" ]]; then
        if [[ -n "$sha256" ]]; then
            if awb_verify_checksum "$dest" "$sha256"; then
                log_ok "Already downloaded and verified: $(basename "$dest")"
                return 0
            else
                log_warn "Existing file failed checksum, re-downloading: $(basename "$dest")"
                rm -f "$dest"
            fi
        elif [[ -s "$dest" ]]; then
            log_ok "Already downloaded: $(basename "$dest")"
            return 0
        else
            log_warn "Existing file is empty, re-downloading: $(basename "$dest")"
            rm -f "$dest"
        fi
    fi

    log_info "Downloading $(basename "$dest") ..."
    if ! curl --fail --location --continue-at - --progress-bar \
            --retry 3 --retry-delay 5 \
            --output "$dest" "$url"; then
        rm -f "$dest"
        fail_loud "Download failed: $url"
    fi

    if [[ -n "$sha256" ]]; then
        awb_verify_checksum "$dest" "$sha256" || fail_loud "Checksum mismatch for $dest"
    fi

    log_ok "Downloaded $(basename "$dest")"
}

# awb_verify_checksum <path> <expected_sha256>
awb_verify_checksum() {
    local path="$1" expected="$2" actual
    require_cmd sha256sum "checksum verification"
    actual="$(sha256sum "$path" | awk '{print $1}')"
    [[ "$actual" == "$expected" ]]
}

# _awb_hf_cli — resolve an invocable Hugging Face CLI, or return 1.
#
# Two things this has to get right:
#   1. `hf` is the current CLI; `huggingface-cli` is deprecated and, from
#      huggingface_hub 1.x on, refuses to run at all ("deprecated and no
#      longer works"). So `hf` must be tried FIRST — `huggingface-cli` is
#      only a fallback for installs old enough to predate `hf`.
#   2. python/create_envs.sh installs huggingface_hub into ~/venvs/core,
#      which is never on PATH, and nothing in the model-download path
#      activates it. A venv's console scripts embed their own interpreter
#      in the shebang, so invoking them by absolute path works without
#      activation — that's what makes the default install able to download
#      its own model on a machine with no system-wide huggingface_hub.
_awb_hf_cli() {
    local venv_bin="${AWB_VENV_ROOT:-$HOME/venvs}/core/bin"
    local candidate
    for candidate in hf huggingface-cli; do
        if has_cmd "$candidate"; then
            printf '%s' "$candidate"
            return 0
        fi
        if [[ -x "${venv_bin}/${candidate}" ]]; then
            printf '%s' "${venv_bin}/${candidate}"
            return 0
        fi
    done
    return 1
}

# awb_hf_download <repo_id> <filename> <dest_dir> [--force]
# Thin wrapper around the Hugging Face CLI for GGUF/model downloads.
# Hugging Face's CLI has built-in caching (~/.cache/huggingface/hub/); this
# adds a size > 0 guard, a .partial marker for interrupted downloads, and
# optional --force to bypass local cache.
awb_hf_download() {
    local repo_id="$1" filename="$2" dest_dir="$3"
    local force=false
    [[ "${4:-}" == "--force" ]] && force=true

    ensure_dir "$dest_dir"

    local dest_path="${dest_dir}/${filename}"
    local partial_marker="${dest_dir}/.${filename}.partial"

    # Force re-download: remove cached file and partial marker
    if $force; then
        rm -f "$dest_path" "$partial_marker"
        log_info "Forced re-download of ${filename}"
    fi

    # If the final file exists and has non-zero size, it's valid — skip.
    if [[ -f "$dest_path" && -s "$dest_path" ]]; then
        log_ok "Model already present: ${filename}"
        return 0
    fi

    # Clean up any leftover partial file from a previous interrupted run
    if [[ -f "$partial_marker" ]]; then
        log_warn "Resuming interrupted download: ${filename}"
        rm -f "$partial_marker"
    fi

    # Write a marker so future invocations know a download was in progress
    touch "$partial_marker"

    log_info "Fetching ${repo_id}/${filename} from Hugging Face ..."

    local hf_cli
    if ! hf_cli="$(_awb_hf_cli)"; then
        rm -f "$partial_marker"
        fail_loud "No Hugging Face CLI found. Install it with 'pip install huggingface_hub', or run install.sh's python section (./install.sh --only python) to create ~/venvs/core."
    fi

    # No --resume-download: the flag was removed from the modern `hf`
    # CLI (resume is the default). stderr is deliberately NOT silenced —
    # swallowing it is what previously hid the huggingface-cli deprecation
    # notice and made a dead code path look like a working one.
    if ! "$hf_cli" download "$repo_id" "$filename" --local-dir "$dest_dir"; then
        rm -f "$partial_marker"
        fail_loud "Hugging Face download failed: ${repo_id}/${filename} (using ${hf_cli})"
    fi

    # Post-download validation: must exist and be non-empty
    if [[ ! -f "$dest_path" || ! -s "$dest_path" ]]; then
        rm -f "$partial_marker"
        fail_loud "Downloaded file is missing or empty: ${dest_path}"
    fi

    rm -f "$partial_marker"
    log_ok "Fetched ${filename} into ${dest_dir} ($(du -h "$dest_path" | cut -f1))"
}
