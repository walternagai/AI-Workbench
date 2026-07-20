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

    if [[ -f "$dest" && -n "$sha256" ]]; then
        if awb_verify_checksum "$dest" "$sha256"; then
            log_ok "Already downloaded and verified: $(basename "$dest")"
            return 0
        else
            log_warn "Existing file failed checksum, re-downloading: $(basename "$dest")"
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

# awb_hf_download <repo_id> <filename> <dest_dir>
# Thin wrapper around the Hugging Face CLI for GGUF/model downloads.
awb_hf_download() {
    local repo_id="$1" filename="$2" dest_dir="$3"
    require_cmd hf "Hugging Face model downloads (pip install huggingface_hub)"
    ensure_dir "$dest_dir"
    log_info "Fetching ${repo_id}/${filename} from Hugging Face ..."
    hf download "$repo_id" "$filename" --local-dir "$dest_dir" \
        || fail_loud "Hugging Face download failed: ${repo_id}/${filename}"
    log_ok "Fetched ${filename} into ${dest_dir}"
}
