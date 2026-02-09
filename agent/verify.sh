#!/usr/bin/env bash
# verify.sh — Deterministic post-agent verification. No LLM, no API cost.
# Checks that all version strings were updated correctly.
# Exit 0 = all checks passed. Exit 1 = failures found (report written).
# Exit 2 = error (missing inputs).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CHANGE_REPORT="${CHANGE_REPORT:-/tmp/change-report.json}"
VERIFY_REPORT="${VERIFY_REPORT:-/tmp/verify-report.json}"

# ---------------------------------------------------------------------------
# Load change report
# ---------------------------------------------------------------------------

if [[ ! -f "$CHANGE_REPORT" ]]; then
  echo "ERROR: Change report not found at $CHANGE_REPORT" >&2
  exit 2
fi

OLD_VERSION=$(jq -r '.oldVersion' "$CHANGE_REPORT")
NEW_VERSION=$(jq -r '.newVersion' "$CHANGE_REPORT")
HAS_VERSION_CHANGE=$(jq -r '.changes[] | select(.type == "npm_version") | .type // empty' "$CHANGE_REPORT")

failures="[]"
warnings="[]"
checks_passed=0
checks_failed=0

fail() {
  local file="$1" reason="$2"
  failures=$(echo "$failures" | jq \
    --arg f "$file" --arg r "$reason" \
    '. + [{"file": $f, "reason": $r}]')
  ((checks_failed++))
  echo "  FAIL: $file — $reason"
}

pass() {
  local file="$1" check="$2"
  ((checks_passed++))
  echo "  OK:   $file — $check"
}

warn() {
  local msg="$1"
  warnings=$(echo "$warnings" | jq --arg m "$msg" '. + [$m]')
  echo "  WARN: $msg"
}

# ---------------------------------------------------------------------------
# 1. Version string checks (only when npm version changed)
# ---------------------------------------------------------------------------

if [[ -n "$HAS_VERSION_CHANGE" ]]; then
  echo "Checking version strings: $OLD_VERSION → $NEW_VERSION"
  echo ""

  # --- SKILL.md ---
  echo "Checking SKILL.md ..."
  SKILL_FILE="$SKILL_ROOT/SKILL.md"
  if [[ ! -f "$SKILL_FILE" ]]; then
    fail "SKILL.md" "File not found"
  else
    # Frontmatter description (~line 4)
    if grep -q "SDK v${NEW_VERSION}" "$SKILL_FILE"; then
      pass "SKILL.md" "Contains 'SDK v${NEW_VERSION}'"
    else
      fail "SKILL.md" "Missing 'SDK v${NEW_VERSION}'"
    fi

    # Header (~line 10)
    if grep -q "(v${NEW_VERSION})" "$SKILL_FILE"; then
      pass "SKILL.md" "Contains '(v${NEW_VERSION})'"
    else
      fail "SKILL.md" "Missing '(v${NEW_VERSION})' in header"
    fi

    # Package line (~line 12)
    if grep -q "@${NEW_VERSION}" "$SKILL_FILE"; then
      pass "SKILL.md" "Contains '@${NEW_VERSION}'"
    else
      fail "SKILL.md" "Missing '@${NEW_VERSION}' in package line"
    fi

    # Footer (~line 585)
    if grep -q "SDK version.*${NEW_VERSION}" "$SKILL_FILE"; then
      pass "SKILL.md" "Footer has version ${NEW_VERSION}"
    else
      fail "SKILL.md" "Footer missing version ${NEW_VERSION}"
    fi

    # Stale version check
    if grep -q "SDK v${OLD_VERSION}\|@${OLD_VERSION}\|(v${OLD_VERSION})" "$SKILL_FILE"; then
      fail "SKILL.md" "Still contains old version '${OLD_VERSION}'"
    else
      pass "SKILL.md" "No stale '${OLD_VERSION}' references"
    fi
  fi

  # --- plugin.json ---
  echo "Checking plugin.json ..."
  PLUGIN_FILE="$SKILL_ROOT/.claude-plugin/plugin.json"
  if [[ ! -f "$PLUGIN_FILE" ]]; then
    fail "plugin.json" "File not found"
  else
    if ! jq empty "$PLUGIN_FILE" 2>/dev/null; then
      fail "plugin.json" "Invalid JSON"
    elif jq -r '.description' "$PLUGIN_FILE" | grep -q "v${NEW_VERSION}"; then
      pass "plugin.json" "Description contains v${NEW_VERSION}"
    else
      fail "plugin.json" "Description missing v${NEW_VERSION}"
    fi

    if jq -r '.description' "$PLUGIN_FILE" | grep -q "v${OLD_VERSION}"; then
      fail "plugin.json" "Description still has old v${OLD_VERSION}"
    else
      pass "plugin.json" "No stale version in description"
    fi
  fi

  # --- rules/claude-agent-sdk.md ---
  echo "Checking rules/claude-agent-sdk.md ..."
  RULES_FILE="$SKILL_ROOT/rules/claude-agent-sdk.md"
  if [[ ! -f "$RULES_FILE" ]]; then
    fail "rules/claude-agent-sdk.md" "File not found"
  else
    if grep -q "v${NEW_VERSION}" "$RULES_FILE"; then
      pass "rules/claude-agent-sdk.md" "Contains v${NEW_VERSION}"
    else
      fail "rules/claude-agent-sdk.md" "Missing v${NEW_VERSION}"
    fi

    if grep -q "v${OLD_VERSION}" "$RULES_FILE"; then
      fail "rules/claude-agent-sdk.md" "Still contains old v${OLD_VERSION}"
    else
      pass "rules/claude-agent-sdk.md" "No stale version"
    fi
  fi

  # --- scripts/check-versions.sh ---
  echo "Checking scripts/check-versions.sh ..."
  CHECK_FILE="$SKILL_ROOT/scripts/check-versions.sh"
  if [[ ! -f "$CHECK_FILE" ]]; then
    fail "scripts/check-versions.sh" "File not found"
  else
    if grep -q "\"${NEW_VERSION}\"" "$CHECK_FILE"; then
      pass "scripts/check-versions.sh" "Contains \"${NEW_VERSION}\""
    else
      fail "scripts/check-versions.sh" "Missing \"${NEW_VERSION}\""
    fi

    if grep -q "\"${OLD_VERSION}\"" "$CHECK_FILE"; then
      fail "scripts/check-versions.sh" "Still contains old \"${OLD_VERSION}\""
    else
      pass "scripts/check-versions.sh" "No stale version"
    fi
  fi

  # --- README.md ---
  echo "Checking README.md ..."
  README_FILE="$SKILL_ROOT/README.md"
  if [[ ! -f "$README_FILE" ]]; then
    fail "README.md" "File not found"
  else
    if grep -q "v${NEW_VERSION}" "$README_FILE"; then
      pass "README.md" "Contains v${NEW_VERSION}"
    else
      fail "README.md" "Missing v${NEW_VERSION}"
    fi

    if grep -q "v${OLD_VERSION}" "$README_FILE"; then
      fail "README.md" "Still contains old v${OLD_VERSION}"
    else
      pass "README.md" "No stale version"
    fi
  fi

  # --- templates/package.json ---
  echo "Checking templates/package.json ..."
  TPL_PKG="$SKILL_ROOT/templates/package.json"
  if [[ ! -f "$TPL_PKG" ]]; then
    fail "templates/package.json" "File not found"
  else
    if ! jq empty "$TPL_PKG" 2>/dev/null; then
      fail "templates/package.json" "Invalid JSON"
    elif jq -r '.dependencies["@anthropic-ai/claude-agent-sdk"]' "$TPL_PKG" | grep -q "${NEW_VERSION}"; then
      pass "templates/package.json" "SDK dep contains ${NEW_VERSION}"
    else
      fail "templates/package.json" "SDK dep missing ${NEW_VERSION}"
    fi
  fi

  # --- Global stale version sweep ---
  echo ""
  echo "Sweeping for any remaining '${OLD_VERSION}' references ..."
  stale_hits=$(grep -rn "${OLD_VERSION}" "$SKILL_ROOT" \
    --include="*.md" --include="*.json" --include="*.sh" --include="*.ts" \
    --exclude-dir=agent --exclude-dir=node_modules \
    2>/dev/null || true)

  if [[ -n "$stale_hits" ]]; then
    fail "GLOBAL" "Stale version '${OLD_VERSION}' found in:\n$stale_hits"
  else
    pass "GLOBAL" "No stale '${OLD_VERSION}' anywhere in skill files"
  fi
fi

# ---------------------------------------------------------------------------
# 2. JSON validity checks (always run)
# ---------------------------------------------------------------------------

echo ""
echo "Validating JSON files ..."
for json_file in "$SKILL_ROOT/templates/package.json" "$SKILL_ROOT/.claude-plugin/plugin.json"; do
  if [[ -f "$json_file" ]]; then
    if jq empty "$json_file" 2>/dev/null; then
      pass "$(basename "$json_file")" "Valid JSON"
    else
      fail "$(basename "$json_file")" "Invalid JSON"
    fi
  fi
done

# ---------------------------------------------------------------------------
# 3. Write report and exit
# ---------------------------------------------------------------------------

echo ""
echo "========================================="
echo "  Passed: $checks_passed"
echo "  Failed: $checks_failed"
echo "========================================="

jq -n \
  --argjson failures "$failures" \
  --argjson warnings "$warnings" \
  --arg old "$OLD_VERSION" \
  --arg new "$NEW_VERSION" \
  --arg passed "$checks_passed" \
  --arg failed "$checks_failed" \
  '{
    oldVersion: $old,
    newVersion: $new,
    checksPassed: ($passed | tonumber),
    checksFailed: ($failed | tonumber),
    failures: $failures,
    warnings: $warnings,
    verifiedAt: (now | todate)
  }' > "$VERIFY_REPORT"

if (( checks_failed > 0 )); then
  echo ""
  echo "VERIFICATION FAILED — $checks_failed issue(s) found."
  echo "Report: $VERIFY_REPORT"
  exit 1
else
  echo ""
  echo "VERIFICATION PASSED — all checks OK."
  exit 0
fi
