#!/usr/bin/env bash
set -euo pipefail

# Verify that envs/development and envs/production share IDENTICAL code
# (only backend.tf, providers.tf, and terraform.tfvars are allowed to differ).
#
# Runs in the terraform-plan.yaml CI workflow.

FILES=(main.tf variables.tf)
FAIL=0

for f in "${FILES[@]}"; do
  if ! diff -q "envs/development/$f" "envs/production/$f" > /dev/null; then
    echo "ERROR: envs/development/$f and envs/production/$f must be IDENTICAL"
    diff "envs/development/$f" "envs/production/$f" || true
    FAIL=1
  fi
done

if [ "$FAIL" -ne 0 ]; then
  echo ""
  echo "Update both files in the same PR. See ARCHITECTURE.md section 3.7 for the rationale."
  exit 1
fi

echo "OK: envs/development and envs/production are in sync."
