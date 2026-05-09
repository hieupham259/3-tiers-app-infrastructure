#!/usr/bin/env bash
set -euo pipefail

# Format every Terraform file in the repository.
# Run locally before pushing, or in a pre-commit hook.

terraform fmt -recursive -diff
