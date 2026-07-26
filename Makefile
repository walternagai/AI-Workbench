.PHONY: install doctor detect update monitor info \
        install-cli install-platform install-python install-runtimes install-models install-services install-benchmark \
        model-install model-list runtime-install benchmark clean-logs clean-reports help \
        test test-shell test-bats test-python

SHELL := /bin/bash

help:
	@echo "AI-Workbench Core v1.0"
	@echo ""
	@echo "  make install              Full install"
	@echo "  make doctor               Run diagnostics"
	@echo "  make detect               Hardware detection summary"
	@echo "  make update               Update AI-Workbench itself"
	@echo "  make monitor              Live resource snapshot"
	@echo "  make info                 Version + hardware summary"
	@echo ""
	@echo "  make install-cli          Re-install the awb CLI symlink"
	@echo "  make install-platform     Re-run only the platform section"
	@echo "  make install-python       Re-run only Python env creation"
	@echo "  make install-runtimes     Re-run only runtime installation"
	@echo "  make install-models       Re-run only model downloads"
	@echo "  make install-services     Re-run only Docker services"
	@echo "  make install-benchmark    Re-run only the benchmark"
	@echo ""
	@echo "  make model-install NAME=gemma3-e2b"
	@echo "  make model-list"
	@echo "  make runtime-install NAME=llama.cpp"
	@echo "  make benchmark TARGET=llm ARGS='path/to/model.gguf'"
	@echo ""
	@echo "  make test                 Everything CI runs (shellcheck + bats + pytest)"
	@echo "  make test-shell           ShellCheck only"
	@echo "  make test-bats            Bash unit tests only"
	@echo "  make test-python          pytest + coverage only"
	@echo ""
	@echo "  make clean-logs           Remove logs/*"
	@echo "  make clean-reports        Remove reports/*"

install:
	./install.sh

doctor:
	./doctor.sh

detect:
	./detect.sh

update:
	./update.sh

monitor:
	./scripts/awb monitor

info:
	./scripts/awb info

install-cli:
	./install.sh --only cli

install-platform:
	./install.sh --only platform

install-python:
	./install.sh --only python

install-runtimes:
	./install.sh --only runtimes

install-models:
	./install.sh --only models

install-services:
	./install.sh --only services

install-benchmark:
	./install.sh --only benchmark

model-install:
	./scripts/awb model install $(NAME)

model-list:
	./scripts/awb model list

runtime-install:
	./scripts/awb runtime install $(NAME)

benchmark:
	./scripts/awb benchmark $(TARGET) $(ARGS)

# The three checks below mirror the three jobs in .github/workflows/ci.yml —
# keep them in step, so a green `make test` means a green CI. Missing tooling
# aborts with the install line rather than skipping the check: a test run that
# quietly covers less than it claims is worse than no test run.
test: test-shell test-bats test-python
	@echo "All checks passed."

test-shell:
	@command -v shellcheck >/dev/null \
	  || { echo "shellcheck not installed: sudo apt install shellcheck" >&2; exit 1; }
	@mapfile -t files < <(find . -name '*.sh' -not -path './.git/*' | sort); \
	 files+=(scripts/awb); \
	 shellcheck -x --severity=warning "$${files[@]}"

test-bats:
	@command -v bats >/dev/null \
	  || { echo "bats not installed: sudo apt install bats" >&2; exit 1; }
	bats tests/bats/

test-python:
	@command -v pytest >/dev/null \
	  || { echo "pytest not installed: pip install -r requirements-test.txt" >&2; exit 1; }
	pytest --cov

clean-logs:
	rm -f logs/*.log logs/*.log.*

clean-reports:
	rm -f reports/*.json reports/*.md
