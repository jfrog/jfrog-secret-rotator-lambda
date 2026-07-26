# (c) JFrog Ltd. (2026)

# Python sources to lint/format (line-length 120, see pyproject.toml).
PY_DIRS := secret-rotator
# Markdown docs to lint (markdownlint).
MD_GLOBS := "*.md" "docs/*.md"

.DEFAULT_GOAL := help

.PHONY: help lint lint-py lint-docs format check

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}'

lint: lint-py lint-docs ## Run all linters (Python + docs)

lint-py: ## Lint Python (ruff + black --check + isort --check)
	ruff check $(PY_DIRS)
	black --check $(PY_DIRS)
	isort --check-only $(PY_DIRS)

lint-docs: ## Lint Markdown docs (markdownlint)
	markdownlint $(MD_GLOBS)

format: ## Auto-format Python (isort + black + ruff --fix)
	isort $(PY_DIRS)
	black $(PY_DIRS)
	ruff check --fix $(PY_DIRS)

check: lint ## Run all checks (alias used by CONTRIBUTING/AGENTS)
