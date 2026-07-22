#!/usr/bin/env bash
# (c) 2026 JFrog Ltd.
# Build a Lambda deployment zip from secret-rotator/ for manual AWS CLI setup.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC_DIR="${ROOT_DIR}/secret-rotator"
BUILD_DIR="${ROOT_DIR}/build"
ZIP_PATH="${BUILD_DIR}/jfrog-secret-rotator-lambda.zip"

mkdir -p "${BUILD_DIR}"
rm -f "${ZIP_PATH}"

# Zip handler at archive root (lambda_function.lambda_handler).
# boto3, botocore, and urllib3 are provided by the managed Python Lambda runtime.
(
  cd "${SRC_DIR}"
  zip -j "${ZIP_PATH}" lambda_function.py -q
)

echo "Created ${ZIP_PATH}"
unzip -l "${ZIP_PATH}" || true
