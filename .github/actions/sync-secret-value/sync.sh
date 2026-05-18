#!/usr/bin/env bash
#
# sync.sh - Idempotent Secrets Manager secret value sync.
#
# Compares current AWSCURRENT value with desired value.
# - If equal: no-op (exit 0, no new version).
# - If different (or version does not exist yet): PutSecretValue.
#
# Inputs (environment variables, set by the composite action wrapper):
#   SECRET_ARN  ARN or name of the secret. Required.
#   DESIRED     Desired SecretString (JSON or arbitrary string). Required.
#
# Exit codes:
#   0 - synced (no-op or new version written).
#   1 - invalid input or AWS API failure.
#
# Note: AWS Secrets Manager creates a new version on every successful
# PutSecretValue call regardless of content. UpdateSecret has the same
# behavior. To avoid version sprawl and the documented soft limit of one
# update per 10 minutes per secret, this script does a server-side fetch
# and client-side equality check before writing.

set -euo pipefail

if [ -z "${SECRET_ARN:-}" ]; then
  echo "ERROR: SECRET_ARN is empty" >&2
  exit 1
fi

if [ -z "${DESIRED:-}" ]; then
  echo "ERROR: DESIRED is empty" >&2
  exit 1
fi

# Fetch current value. Returns empty string on ResourceNotFoundException
# (first apply: the secret exists but has no AWSCURRENT version yet).
current=$(aws secretsmanager get-secret-value \
  --secret-id "$SECRET_ARN" \
  --query SecretString \
  --output text 2>/dev/null || echo "")

if [ "$current" = "$DESIRED" ]; then
  echo "OK - secret value already matches desired state, no PutSecretValue needed."
  exit 0
fi

echo "Secret value differs (or version absent), writing new version..."
aws secretsmanager put-secret-value \
  --secret-id "$SECRET_ARN" \
  --secret-string "$DESIRED" \
  > /dev/null
echo "OK - new version written."
