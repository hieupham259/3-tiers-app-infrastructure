#!/usr/bin/env bash
set -euo pipefail

# Validate both envs (must run after init).
# Only checks syntax + provider schema. AWS credentials are NOT required.

for env in development production; do
  echo "--- terraform validate: envs/$env ---"
  (
    cd "envs/$env"
    terraform init -backend=false -no-color > /dev/null
    terraform validate -no-color
  )
done

echo "OK: both development and production validate cleanly."
