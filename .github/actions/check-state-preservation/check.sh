#!/usr/bin/env bash
#
# check.sh - State preservation gate for Terraform plans.
#
# Reads a `terraform show -json tfplan` JSON document, walks resource_changes,
# and fails when the plan would destroy or replace a stateful resource without
# explicit acknowledgement.
#
# Inputs (environment variables, set by the composite action wrapper):
#   PLAN_JSON_PATH   Path to the plan JSON file. Required.
#   COMMIT_MESSAGE   Free-form text scanned for `acknowledged-destroy:<addr>`.
#                    Typically the head commit message or PR title.
#   PR_LABELS        JSON array of PR label names, also scanned for the magic
#                    string. Pass `[]` outside pull_request context.
#
# Exit codes:
#   0 - clean, or all stateful destroys explicitly acknowledged.
#   1 - at least one stateful destroy was not acknowledged, or invalid input.
#
# Acknowledge syntax (case-sensitive, exact resource address match):
#   acknowledged-destroy:<resource_address>
#
# Example commit message:
#   chore: replace primary RDS to upgrade engine version
#   acknowledged-destroy:module.rds.aws_db_instance.main

set -euo pipefail

PLAN_JSON_PATH="${PLAN_JSON_PATH:-}"
COMMIT_MESSAGE="${COMMIT_MESSAGE:-}"
PR_LABELS="${PR_LABELS:-[]}"

# Allowlist of stateful AWS resource types. Mirrors the list documented in
# CLAUDE.md and enforced by iac-builder, iac-reviewer, and terraform-planner.
# Update all four locations together when this list changes.
STATEFUL_TYPES=(
  aws_db_instance
  aws_rds_cluster
  aws_s3_bucket
  aws_kms_key
  aws_efs_file_system
  aws_dynamodb_table
  aws_eip
  aws_secretsmanager_secret
  aws_elasticache_cluster
  aws_msk_cluster
  aws_eks_cluster
  aws_eks_node_group
)

if [[ -z "$PLAN_JSON_PATH" ]]; then
  echo "ERROR: PLAN_JSON_PATH is empty. The composite action must pass plan-json-path." >&2
  exit 1
fi

if [[ ! -f "$PLAN_JSON_PATH" ]]; then
  echo "ERROR: Plan JSON file not found at: $PLAN_JSON_PATH" >&2
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "ERROR: jq is required but was not found on PATH." >&2
  exit 1
fi

# Validate PR_LABELS is a JSON array.
if ! printf '%s' "$PR_LABELS" | jq -e 'type == "array"' >/dev/null 2>&1; then
  echo "ERROR: pr-labels input must be a JSON array string. Got: $PR_LABELS" >&2
  exit 1
fi

# Convert allowlist to JSON array for jq --argjson.
allowlist_json=$(printf '%s\n' "${STATEFUL_TYPES[@]}" | jq -R . | jq -s .)

# Build acknowledgement corpus: commit message text plus each PR label on its
# own line. Both surfaces accept the magic string.
ack_text="$COMMIT_MESSAGE"
while IFS= read -r label; do
  ack_text+=$'\n'"$label"
done < <(printf '%s' "$PR_LABELS" | jq -r '.[]?')

# Find stateful destroys in the plan. A destroy is any change whose actions
# array contains "delete", which covers both pure destroy (["delete"]) and
# replacement (["delete","create"] or ["create","delete"]).
#
# Output format per line: <address>|<type>|<actions_csv>
violations=$(jq -r --argjson allow "$allowlist_json" '
  .resource_changes[]?
  | select(.change.actions | index("delete"))
  | select(.type as $t | $allow | index($t))
  | "\(.address)|\(.type)|\(.change.actions | join(","))"
' "$PLAN_JSON_PATH")

if [[ -z "$violations" ]]; then
  echo "OK - no stateful resource destroys or replacements detected."
  exit 0
fi

echo "Stateful resource destroys detected. Checking acknowledgements..."
echo

fail=0
acknowledged=0
unacknowledged=0
while IFS='|' read -r address type actions; do
  [[ -z "$address" ]] && continue
  marker="acknowledged-destroy:${address}"
  if printf '%s' "$ack_text" | grep -qF -- "$marker"; then
    echo "ACK   - $address ($type, actions=$actions) acknowledged via commit message or PR label."
    acknowledged=$((acknowledged + 1))
  else
    echo "BLOCK - $address ($type, actions=$actions) NOT acknowledged."
    unacknowledged=$((unacknowledged + 1))
    fail=1
  fi
done <<< "$violations"

echo
echo "Summary: ${acknowledged} acknowledged, ${unacknowledged} unacknowledged."

if [[ "$fail" -eq 1 ]]; then
  echo
  echo "To acknowledge an intentional destroy, add the following line to the"
  echo "head commit message or apply a PR label with this exact text:"
  echo "  acknowledged-destroy:<resource_address>"
  echo
  echo "One marker per resource address. The address must match the Terraform"
  echo "address shown above, including any module. prefix."
  exit 1
fi

echo "All stateful destroys explicitly acknowledged. Passing."
exit 0
