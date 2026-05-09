#!/usr/bin/env bash
set -euo pipefail

# Run tflint over all modules and envs.
# Requires tflint >= 0.50 and the config at .tflint.hcl in the repo root.

if ! command -v tflint > /dev/null; then
  echo "ERROR: tflint is not installed. See https://github.com/terraform-linters/tflint"
  exit 1
fi

tflint --init --config "$(pwd)/.tflint.hcl"
tflint --recursive --config "$(pwd)/.tflint.hcl"
