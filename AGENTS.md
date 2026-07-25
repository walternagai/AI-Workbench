# AGENTS.md — AI-Workbench

## What this is

Bash framework (no app server, no DB, no API) that prepares a Linux workstation for local AI dev. The "product" is shell tooling. Python in `benchmarks/` is only for benchmark scripts, unit-tested with pytest.

## Commands

```bash
# Unified CLI entrypoint (preferred)
scripts/awb install|doctor|detect|update|monitor|info
scripts/awb model install|list|remove|update
scripts/awb runtime install|update|remove <name>
scripts/awb benchmark <llm|whisper|vision|embeddings> [args...]

# Make shortcuts
make install         # full install
make doctor          # diagnostics -> reports/doctor.{json,md}
make detect          # hardware detection -> reports/hardware.json
make update          # git pull + optional runtime/model updates
make model-install NAME=gemma3-e2b
make runtime-install NAME=llama.cpp
make benchmark TARGET=llm ARGS='path/to/model.gguf'

# Section-level selective re-execution
./install.sh --only <validate|system|detect|platform|python|runtimes|models|services|benchmark|report>
./install.sh --skip <section>
```

## Testing

```bash
# Python (benchmarks/) — requires requirements-test.txt (pytest, pytest-cov,
# and the libs bench_embeddings.py/bench_onnx.py import at collection time)
pip install -r requirements-test.txt
pytest                              # pythonpath = repo root (pyproject.toml sets it)
pytest --cov                        # coverage over benchmarks/, fail_under=80
pytest tests/test_bench_*.py -k test_function  # single test

# Bash — pure helpers in lib/ (no hardware/network needed), via bats-core
bats tests/bats/

# Shellcheck — same check CI runs, at --severity=warning (see notes below)
shellcheck -x --severity=warning $(find . -name '*.sh' -not -path './.git/*') scripts/awb
```

No Python lint/format/typecheck config in the repo (no ruff, flake8, mypy).
Shell scripts are linted in CI (`.github/workflows/ci.yml`: shellcheck +
pytest + bats, on every push/PR) at `--severity=warning` — a handful of
pre-existing "info"-level style notes (SC2015 `A && B || C`, SC2021 `tr []`
classes, SC2317 trap-invoked "unreachable" code) are reviewed, deliberate
idioms rather than bugs.

## Architecture

- **`install.sh`** — orchestrator: validate → system update → `section_prereqs` (unconditional) → detect → platform → python envs → runtimes → models → services → benchmark → report. Each section is gated by `RUN_*` booleans.
- **`scripts/awb`** — unified CLI, sources libs and dispatches to same underlying scripts.
- **`config.env`** — controls ALL optional behavior via `INSTALL_*` flags, read by `is_true()`.
- **`lib/*.sh`** — shared libraries sourced by nearly every script: `logger.sh`, `utils.sh`, `colors.sh`, `downloader.sh`, `validation.sh`.
- **`detect.sh`** — PCI-based hardware detection, exports `PLATFORM_TARGET`, `HAS_*_GPU`, `VRAM_GB`, etc. Many sections silently depend on it. Parses `/etc/os-release` with `awk` (never `source`s it).
- **`doctor.sh`** — 100+ diagnostics, writes `reports/doctor.{json,md}`.
- **Reports & logs** are gitignored: `reports/*.json`, `reports/*.md`, `logs/*.log`.

## Module contract

`platforms/<vendor>/install.sh` and `runtimes/<name>/install.sh` each expose `install_<name>()`, optionally `update_<name>()` and `remove_<name>()`. Can be added without touching core scripts. Dots in runtime names translate to underscores (`llama.cpp` → `install_llama_cpp()`).

## Non-obvious conventions

- **`section_prereqs()` always runs unconditionally** before any conditional branch. `ensure_prereq_dirs()` creates `logs/`, `reports/`, `$AI_HOME/models/`, `$AI_HOME/bin/`, `~/venvs/`. Never move these inside an `if` — a real bug class was fixed in v1.0 QA.
- **`fail_loud`** is the one exit point for fatal errors in `lib/logger.sh`. Never call it from a subshell you expect to keep running.
- **`doctor.sh`** deliberately uses `set -uo pipefail` (no `-e`) — a failed check must not kill the diagnosis.
- **All other scripts** follow `set -euo pipefail`.
- **Python venvs** live in `~/venvs/` (core, openvino, rag, vision, speech), not inside the repo.
- **`DEBIAN_FRONTEND=noninteractive`** is exported globally in `lib/utils.sh`.
- **`load_env <path> true|false`** — second arg marks the file as required; omitting/calling with `false` silently skips missing file.
- **`sudo_keepalive`** spawns a background process; always cleaned up via `EXIT`/`INT`/`TERM` traps in `install.sh`.
- **`apt_update_once`** ensures apt update runs at most once per process tree using an env marker (not temp file).
