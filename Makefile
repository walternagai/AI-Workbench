.PHONY: install doctor detect update monitor info \
        install-platform install-python install-runtimes install-models install-services install-benchmark \
        model-install model-list runtime-install benchmark clean-logs clean-reports help

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
	@echo "  make install-platform     Re-run only the platform section"
	@echo "  make install-python       Re-run only Python env creation"
	@echo "  make install-runtimes     Re-run only runtime installation"
	@echo "  make install-models       Re-run only default model download"
	@echo "  make install-services     Re-run only Docker services"
	@echo "  make install-benchmark    Re-run only the benchmark"
	@echo ""
	@echo "  make model-install NAME=gemma3-e2b"
	@echo "  make model-list"
	@echo "  make runtime-install NAME=llama.cpp"
	@echo "  make benchmark TARGET=llm ARGS='path/to/model.gguf'"
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

clean-logs:
	rm -f logs/*.log logs/*.log.*

clean-reports:
	rm -f reports/*.json reports/*.md
