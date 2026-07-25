# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

AI-Workbench is a bash framework that prepares a Linux workstation (Ubuntu /
Pop!_OS / Linux Mint, x86_64 only) for local AI development: it detects
hardware, installs only the compatible acceleration stack, builds Python
venvs, compiles inference runtimes, manages GGUF models, runs benchmarks and
produces diagnostics — idempotently and observably. There is no application
server here; the "product" is the shell tooling itself. A small Python
surface (`benchmarks/`) exists purely to produce/parse benchmark numbers and
is unit-tested with pytest.

## Commands

```bash
./install.sh                          # full install
./install.sh --only <section>         # validate|system|detect|platform|python|runtimes|models|services|benchmark|report
./install.sh --skip <section>         # repeatable
./doctor.sh                           # 100+ diagnostic checks -> reports/doctor.{json,md}
./detect.sh                           # hardware detection summary -> reports/hardware.json
./update.sh                           # update framework + installed runtimes/models
make install | make doctor | make detect | make update | make monitor | make info
make install-platform / install-python / install-runtimes / install-models / install-services / install-benchmark
make model-install NAME=gemma3-e2b
make runtime-install NAME=llama.cpp
make benchmark TARGET=llm ARGS='path/to/model.gguf'
make clean-logs / make clean-reports

scripts/awb install|doctor|detect|update|monitor|info
scripts/awb model install|list|remove|update
scripts/awb runtime install|update|remove <name>
scripts/awb benchmark <llm|whisper|vision|embeddings> [args...]
```

Python side (benchmark scripts only):

```bash
pytest                                    # runs tests/, pythonpath is repo root (see pyproject.toml)
pytest tests/test_bench_embeddings.py -k test_normal   # single test
pytest --cov                              # coverage over benchmarks/, fail_under = 80
```

There is no separate lint command configured (no ruff/flake8/eslint config in
the repo); shell scripts are annotated with `# shellcheck source=` hints for
whoever runs shellcheck manually.

## Architecture

**Orchestration flow** (`install.sh`): validate → apt system update →
`section_prereqs` (unconditional) → `detect.sh` → platform module → Python
envs → runtimes → default model → docker services → benchmark → report.
Every section is a function (`section_*`) gated by a `RUN_*` boolean that
`--only`/`--skip` flip; re-running any subset is safe because every module is
idempotent (see docs/PRINCIPLES.md §1–3).

**Shared libraries** (`lib/`), sourced by nearly every script:
- `lib/logger.sh` — `log_info/log_ok/log_warn/log_error/log_step`, all
  writing to stdout/stderr *and* `logs/installation.log` (auto-rotated at
  10MB, 3 backups kept). `fail_loud <msg>` is the one exit point for fatal
  errors — it logs and calls `exit`, so never invoke it from a subshell you
  expect to keep running.
- `lib/utils.sh` — `has_cmd`, `require_cmd`, `is_true` (parses config.env
  booleans), `ensure_dir`, `ensure_prereq_dirs`, `retry`, `sudo_keepalive`,
  `apt_update_once`, `load_env`, `safe_source` (source-or-fail_loud),
  `json_kv` (hand-rolled JSON escaping for reports).
- `lib/validation.sh` — OS/arch/RAM/disk preflight checks, shared by
  `install.sh` and `doctor.sh`.
- `lib/colors.sh` — terminal color/symbol constants.

**Hardware detection** (`detect.sh`): PCI-enumeration-based (`lspci`), so it
works headlessly without vendor drivers installed. Exports `HAS_*_GPU`,
`HAS_VULKAN/OPENCL/CUDA/ROCM`, `RAM_GB`, `VRAM_GB`, etc., then
`resolve_platform_target()` picks one of `nvidia > amd > intel > cpu` (in
that priority order) into `PLATFORM_TARGET`. Parses `/etc/os-release` with
`awk`, deliberately never `source`s it (avoids executing arbitrary shell
from a system file). Can run standalone (prints summary + writes
`reports/hardware.json`) or be sourced for its exported variables.

**Module contract** — `platforms/<vendor>/install.sh` and
`runtimes/<name>/install.sh` are independent, addable without touching the
core (`install.sh`/`doctor.sh`/`detect.sh`). Each exposes `install_<name>()`
and optionally `update_<name>()`/`remove_<name>()`. They assume `AWB_ROOT` is
already set and lib/*.sh already sourced (`AWB_ROOT="${AWB_ROOT:?must be
sourced from install.sh}"` at the top of every module — these scripts are
never meant to run standalone). `scripts/awb runtime <cmd> <name>` sources
`runtimes/<name>/install.sh` and calls the matching function dynamically
(dots in runtime names are translated to underscores, e.g. `llama.cpp` →
`install_llama_cpp`).

- `platforms/cpu/install.sh` always runs first regardless of detected GPU
  (universal fallback); the vendor-specific module (`intel`/`amd`/`nvidia`)
  runs additionally based on `PLATFORM_TARGET`.
- `runtimes/llama.cpp/install.sh` picks CMake backend flags from
  `PLATFORM_TARGET` (CUDA/HIP/Vulkan/OpenBLAS) and additionally installs a
  systemd `--user` service (`INSTALL_LLAMACPP_SERVICE` in config.env).
- `models/install.sh` is a small curated GGUF catalog (name →
  `repo_id|filename|size|notes`) plus a `custom <repo_id> <filename>`
  escape hatch; downloads go through `lib/downloader.sh`'s HF helper.

**Configuration** (`config.env`): every optional behavior — which runtimes
to build, which Docker services to start, validation thresholds, default
model — is a flag here, read via `is_true()`. This is what makes selective
re-execution meaningful: flip a flag, re-run just that section.

**Reports & logs**: `reports/hardware.json`, `reports/doctor.{json,md}`,
`reports/install_report.md` are generated artifacts (gitignored); `logs/installation.log`
is the full timestamped trail. Both directories are created unconditionally
by `ensure_prereq_dirs()` before any platform/runtime branch runs — do not
move that call inside a conditional (see docs/PRINCIPLES.md §2, a real bug
class fixed in v1.0 QA).

**Python side** (`python/create_envs.sh`, `benchmarks/`): creates separate
venvs per concern (core, openvino, rag, vision, speech) under `~/venvs`.
`benchmarks/<domain>/bench_*.py` scripts separate pure/testable logic
(`parse_args`, `compute_stats`, `format_report`) from the GPU/model-loading
side effects, which is why `tests/` can unit-test them without hardware.

## Project principles (docs/PRINCIPLES.md)

These are normative — code review should reject contributions that violate
them without documented justification:

1. **Fail-loud over silent degradation** — a missing prerequisite aborts via
   `fail_loud`, never continues into a state that fails confusingly later.
   Deliberate exceptions (`log_warn` + continue) are documented at the call
   site, e.g. `platforms/intel/oneapi.sh` and `intel/npu.sh` are
   best-effort, non-critical paths.
2. **Shared prerequisites, unconditionally, first** — `ensure_prereq_dirs()`
   runs before any platform/runtime conditional branch.
3. **Selective re-execution via boolean flags** in `config.env`, read via
   `is_true()`.
4. **Vulkan (Mesa ANV) is the practical acceleration path on Intel iGPUs** —
   not the XPU/SYCL (vLLM/IPEX-LLM) path, which is impractical to configure
   on iGPUs.
5. **Quantization scales with model size** — prefer `Q8_0` over `Q4_K_M` on
   small models (e.g. Gemma E2B); larger models tolerate aggressive
   quantization better. `models/install.sh` warns on low-memory systems.
6. **Observability** — every action logs structurally to
   `logs/installation.log`; final reports document what was checked/fixed.
7. **Modularity** — `platforms/*` and `runtimes/*` are independent modules
   following the `install_<name>`/`update_<name>`/`remove_<name>` contract;
   new ones can be added without touching the core scripts.
