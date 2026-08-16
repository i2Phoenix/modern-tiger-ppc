SHELL := /bin/bash

.PHONY: help lint download deploy remote-check remote-verify-sources \
	verify-dist release-check

help:
	@echo "modern-tiger-ppc"
	@echo ""
	@echo "Host-side targets:"
	@echo "  make lint          Static and repository-safety checks"
	@echo "  make download      Download pinned source archives"
	@echo "  make deploy        Copy source tree and cache to a Tiger host"
	@echo "  make remote-check  Run read-only checks on a Tiger host"
	@echo "  make remote-verify-sources  Verify every archive on Tiger"
	@echo "  make verify-dist   Verify generated packages on the configured Tiger host"
	@echo "  make release-check Require locked source checksums and clean artifacts"

lint:
	bash scripts/host/lint.sh

download:
	bash scripts/host/download-sources.sh

deploy:
	bash scripts/host/deploy.sh

remote-check:
	bash scripts/host/remote-check.sh

remote-verify-sources:
	bash scripts/host/remote-verify-sources.sh

verify-dist:
	bash scripts/host/remote-verify-dist.sh

release-check: lint
	bash scripts/host/release-check.sh
