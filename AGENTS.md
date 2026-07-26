# AGENTS.md

Guidance for AI coding agents working in this repository. (Human contributors:
see [CONTRIBUTING.md](CONTRIBUTING.md).)

## What this is

`jfrog-secret-rotator-lambda` is a Python lambda manual and Terraform
setup instructions. It is a working example of a service that rotates a JFrog
short-lived access token stored in AWS Secret Manager.

The value is integrating that rotating secret with an ECR Cluster pulling images from JFrog repository.

## Layout

- `secret-rotator/main.py` - the function that performs the JFrog AWS IAM role token
  exchange and secret rotation.
- `docs/manual-setup.md` - manual setup instructions.
- `docs/terraform-setup.md` - Terraform setup instructions.
- `terraform-example` - Terraform files for the rotation components and secret.
- `README.md` - canonical entrypoint: disclaimer, what's applied here, and the
  apply-on-fork settings.

## Conventions (must follow)

- **Copyright header:** every new `*.py` / `*.sh` file starts with
  `# (c) JFrog Ltd. (<year>)` (e.g. `# (c) JFrog Ltd. (2026)`).
- **Style:** black + isort + ruff at line-length 120 for code, markdownlint for
  docs; `make check` must pass.
- **ASCII-only prose:** use ASCII hyphens (`-`), never the Unicode em-dash
  (U+2014) or en-dash (U+2013), in docs and comments.
- **No secrets** in any per-PR workflow; credentialed jobs are
  `pull_request_target` + `safe to test` gated, SHA-pinned.
- **Zero runtime dependencies** by default. If you add one, it must be in an
  Acceptable license bucket (the JFrog Xray SBOM is authoritative) and you must
  add a matching entry to `NOTICE`.
- **Durable docs:** do not assert exact counts ("N tests", "N agents") that
  drift; link the source of truth or use a CLI command instead.
- **Release model:** tag-driven only. Never add auto-publish-on-merge.
