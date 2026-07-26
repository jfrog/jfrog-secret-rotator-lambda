# Contributing to jfrog-secret-rotator-lambda

Thanks for your interest. This repository is a jfrog-secret-rotator-lambda Aws
lambda helper for auto-rotating a AWS secret that holds a JFrog
short-lived token.

## Contributor License Agreement (CLA)

Before your first contribution can be merged you must sign the
[JFrog Contributor License Agreement](https://jfrog.com/cla/). This is a
one-time requirement per contributor; the CLAssistant bot will comment on your
first PR with the signing link, and the `cla` check gates the merge.

## Getting started

We use [uv](https://docs.astral.sh/uv/) for a reproducible, locked dev
environment. Pip works as a fallback.

```bash
uv sync                          # creates .venv, installs locked dev deps
uv run pre-commit install        # enables the lint/secret/header hooks on commit
make check                       # lint + tests - should pass before you start
```

Pip fallback:

```bash
python -m venv .venv && source .venv/bin/activate
pip install -e ".[dev]"
make check
```

## Development workflow

1. Branch from the latest `main`.
2. Make your change. New source files must start with `(c) JFrog Ltd. (YEAR)`.
3. `make check` (lint + tests) must pass.
4. Open a PR into `main` and apply one release-note label (`new feature` /
  `improvement` / `bug` / `breaking change` / `ignore for release`).

## What runs where

| Check | Local (`make check`) | CI on every PR | Frogbot (gated) |
| --- | :---: | :---: | :---: |
| CLAssistant (CLA signed) | - | ✅ | - |
| markdownlint | ✅ | ✅ | - |
| gitleaks (secrets) | ✅ | ✅ | - |
| bandit (SAST) | ✅ | ✅ | - |
| copyright headers | ✅ | ✅ | - |
| Frogbot SCA + secrets | - | - | ✅ |

The `safe to test` label is auto-stripped after each run by
`[removeLabel.yml](.github/workflows/removeLabel.yml)`, so each credentialed
run requires a fresh maintainer review of the diff.

- `vX.Y.Z-rcN` (pre-release) -> TestPyPI rehearsal.
- `vX.Y.Z` (clean) -> PyPI (reviewer-gated) + a GitHub Release with auto-notes.

Operational setup (Trusted Publisher registration, GitHub Environments, branch
protection) is summarized in [README.md](README.md) ("When you fork").

## License

By contributing, you agree your contributions are licensed under the
[Apache License 2.0](LICENSE).
