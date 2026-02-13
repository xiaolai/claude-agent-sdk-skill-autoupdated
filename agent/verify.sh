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

# Prefer language-specific fields (tsOldVersion/tsNewVersion) with fallback
# to the legacy top-level oldVersion/newVersion for backward compatibility.
TS_OLD=$(jq -r '.tsOldVersion // .oldVersion' "$CHANGE_REPORT")
TS_NEW=$(jq -r '.tsNewVersion // .newVersion' "$CHANGE_REPORT")
OLD_VERSION="$TS_OLD"
NEW_VERSION="$TS_NEW"

HAS_VERSION_CHANGE=$(jq -r '
  .changes[]
  | select(.type == "npm_version" and .language == "typescript")
  | .type // empty
' "$CHANGE_REPORT" 2>/dev/null || true)

# Fallback: legacy change reports without .language
if [[ -z "$HAS_VERSION_CHANGE" ]]; then
  HAS_VERSION_CHANGE=$(jq -r '.changes[] | select(.type == "npm_version") | .type // empty' "$CHANGE_REPORT" 2>/dev/null || true)
fi

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

  # --- SKILL-typescript.md (TS-specific version checks) ---
  echo "Checking SKILL-typescript.md ..."
  SKILL_TS_FILE="$SKILL_ROOT/SKILL-typescript.md"
  if [[ ! -f "$SKILL_TS_FILE" ]]; then
    fail "SKILL-typescript.md" "File not found"
  else
    # Title / header line
    if grep -q "(v${NEW_VERSION})" "$SKILL_TS_FILE"; then
      pass "SKILL-typescript.md" "Contains '(v${NEW_VERSION})'"
    else
      fail "SKILL-typescript.md" "Missing '(v${NEW_VERSION})' in header"
    fi

    # Package line (~line 12)
    if grep -q "@${NEW_VERSION}" "$SKILL_TS_FILE"; then
      pass "SKILL-typescript.md" "Contains '@${NEW_VERSION}'"
    else
      fail "SKILL-typescript.md" "Missing '@${NEW_VERSION}' in package line"
    fi

    # Footer (~line 585)
    if grep -q "SDK version.*${NEW_VERSION}" "$SKILL_TS_FILE"; then
      pass "SKILL-typescript.md" "Footer has version ${NEW_VERSION}"
    else
      fail "SKILL-typescript.md" "Footer missing version ${NEW_VERSION}"
    fi

    # Stale version check
    if grep -q "SDK v${OLD_VERSION}\|@${OLD_VERSION}\|(v${OLD_VERSION})" "$SKILL_TS_FILE"; then
      fail "SKILL-typescript.md" "Still contains old version '${OLD_VERSION}'"
    else
      pass "SKILL-typescript.md" "No stale '${OLD_VERSION}' references"
    fi
  fi

  # --- SKILL.md (router — must reference both TS and PY versions) ---
  echo "Checking SKILL.md (router) ..."
  SKILL_FILE="$SKILL_ROOT/SKILL.md"
  if [[ ! -f "$SKILL_FILE" ]]; then
    fail "SKILL.md" "File not found"
  else
    # TS version should appear in the router
    if grep -q "v${NEW_VERSION}" "$SKILL_FILE"; then
      pass "SKILL.md" "Contains TS version v${NEW_VERSION}"
    else
      fail "SKILL.md" "Missing TS version v${NEW_VERSION}"
    fi

    # Stale TS version check
    if grep -q "v${OLD_VERSION}" "$SKILL_FILE"; then
      fail "SKILL.md" "Still contains old TS version v${OLD_VERSION}"
    else
      pass "SKILL.md" "No stale TS version v${OLD_VERSION}"
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

  # --- rules/claude-agent-sdk-ts.md ---
  echo "Checking rules/claude-agent-sdk-ts.md ..."
  RULES_FILE="$SKILL_ROOT/rules/claude-agent-sdk-ts.md"
  if [[ ! -f "$RULES_FILE" ]]; then
    fail "rules/claude-agent-sdk-ts.md" "File not found"
  else
    if grep -q "v${NEW_VERSION}" "$RULES_FILE"; then
      pass "rules/claude-agent-sdk-ts.md" "Contains v${NEW_VERSION}"
    else
      fail "rules/claude-agent-sdk-ts.md" "Missing v${NEW_VERSION}"
    fi

    if grep -q "v${OLD_VERSION}" "$RULES_FILE"; then
      fail "rules/claude-agent-sdk-ts.md" "Still contains old v${OLD_VERSION}"
    else
      pass "rules/claude-agent-sdk-ts.md" "No stale version"
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
    # README contains a historical table of older versions; only validate the
    # current "SDK Version" line near the top to avoid false positives.
    if grep -qE "^\*\*SDK Version\*\*:.*TypeScript v${NEW_VERSION}" "$README_FILE"; then
      pass "README.md" "SDK Version line has TypeScript v${NEW_VERSION}"
    else
      fail "README.md" "SDK Version line missing TypeScript v${NEW_VERSION}"
    fi

    if head -n 10 "$README_FILE" | grep -q "TypeScript v${OLD_VERSION}"; then
      fail "README.md" "Top section still contains old TypeScript v${OLD_VERSION}"
    else
      pass "README.md" "Top section has no stale TS version"
    fi
  fi

  # --- templates/typescript/package.json ---
  echo "Checking templates/typescript/package.json ..."
  TPL_PKG="$SKILL_ROOT/templates/typescript/package.json"
  if [[ ! -f "$TPL_PKG" ]]; then
    fail "templates/typescript/package.json" "File not found"
  else
    if ! jq empty "$TPL_PKG" 2>/dev/null; then
      fail "templates/typescript/package.json" "Invalid JSON"
    elif jq -r '.dependencies["@anthropic-ai/claude-agent-sdk"]' "$TPL_PKG" | grep -q "${NEW_VERSION}"; then
      pass "templates/typescript/package.json" "SDK dep contains ${NEW_VERSION}"
    else
      fail "templates/typescript/package.json" "SDK dep missing ${NEW_VERSION}"
    fi
  fi

  # --- Global stale TS version sweep ---
  echo ""
  echo "Sweeping for any remaining '${OLD_VERSION}' references ..."
  stale_hits=$(grep -rn "${OLD_VERSION}" "$SKILL_ROOT" \
    --include="*.md" --include="*.json" --include="*.sh" --include="*.ts" \
    --exclude-dir=agent --exclude-dir=node_modules --exclude-dir=reports --exclude-dir=.git --exclude-dir=tmp \
    --exclude="README.md" --exclude="CHANGELOG.md" \
    --exclude="SKILL-python.md" --exclude="claude-agent-sdk-py.md" \
    --exclude="package-lock.json" \
    2>/dev/null || true)

  if [[ -n "$stale_hits" ]]; then
    fail "GLOBAL" "Stale TS version '${OLD_VERSION}' found in:\n$stale_hits"
  else
    pass "GLOBAL" "No stale TS '${OLD_VERSION}' anywhere in skill files"
  fi
fi

# ---------------------------------------------------------------------------
# 1b. Python version string checks (only when PyPI version changed)
# ---------------------------------------------------------------------------

PY_OLD=$(jq -r '.pyOldVersion // empty' "$CHANGE_REPORT" 2>/dev/null || true)
PY_NEW=$(jq -r '.pyNewVersion // empty' "$CHANGE_REPORT" 2>/dev/null || true)

HAS_PY_VERSION_CHANGE=$(jq -r '
  .changes[]
  | select(.type == "pypi_version" and .language == "python")
  | .type // empty
' "$CHANGE_REPORT" 2>/dev/null || true)

if [[ -n "$HAS_PY_VERSION_CHANGE" && -n "$PY_OLD" && -n "$PY_NEW" && "$PY_OLD" != "$PY_NEW" ]]; then
  echo ""
  echo "Checking Python version strings: $PY_OLD → $PY_NEW"
  echo ""

  # --- SKILL-python.md ---
  echo "Checking SKILL-python.md ..."
  SKILL_PY_FILE="$SKILL_ROOT/SKILL-python.md"
  if [[ ! -f "$SKILL_PY_FILE" ]]; then
    fail "SKILL-python.md" "File not found"
  else
    if grep -q "(v${PY_NEW})" "$SKILL_PY_FILE"; then
      pass "SKILL-python.md" "Contains '(v${PY_NEW})'"
    else
      fail "SKILL-python.md" "Missing '(v${PY_NEW})' in header"
    fi

    if grep -q "claude-agent-sdk==${PY_NEW}" "$SKILL_PY_FILE"; then
      pass "SKILL-python.md" "Contains 'claude-agent-sdk==${PY_NEW}'"
    else
      fail "SKILL-python.md" "Missing 'claude-agent-sdk==${PY_NEW}'"
    fi

    if grep -q "SDK version.*${PY_NEW}" "$SKILL_PY_FILE"; then
      pass "SKILL-python.md" "Footer has version ${PY_NEW}"
    else
      fail "SKILL-python.md" "Footer missing version ${PY_NEW}"
    fi

    if grep -q "(v${PY_OLD})\|==${PY_OLD}" "$SKILL_PY_FILE"; then
      fail "SKILL-python.md" "Still contains old version '${PY_OLD}'"
    else
      pass "SKILL-python.md" "No stale '${PY_OLD}' references"
    fi
  fi

  # --- SKILL.md router (Python version) ---
  echo "Checking SKILL.md (router) for Python version ..."
  SKILL_FILE="$SKILL_ROOT/SKILL.md"
  if [[ -f "$SKILL_FILE" ]]; then
    if grep -q "v${PY_NEW}" "$SKILL_FILE"; then
      pass "SKILL.md" "Contains Python version v${PY_NEW}"
    else
      fail "SKILL.md" "Missing Python version v${PY_NEW}"
    fi

    if grep -q "Python v${PY_OLD}" "$SKILL_FILE"; then
      fail "SKILL.md" "Still contains old Python version v${PY_OLD}"
    else
      pass "SKILL.md" "No stale Python version v${PY_OLD}"
    fi
  fi

  # --- rules/claude-agent-sdk-py.md ---
  echo "Checking rules/claude-agent-sdk-py.md ..."
  PY_RULES_FILE="$SKILL_ROOT/rules/claude-agent-sdk-py.md"
  if [[ ! -f "$PY_RULES_FILE" ]]; then
    fail "rules/claude-agent-sdk-py.md" "File not found"
  else
    if grep -q "v${PY_NEW}" "$PY_RULES_FILE"; then
      pass "rules/claude-agent-sdk-py.md" "Contains v${PY_NEW}"
    else
      fail "rules/claude-agent-sdk-py.md" "Missing v${PY_NEW}"
    fi

    if grep -q "v${PY_OLD}" "$PY_RULES_FILE"; then
      fail "rules/claude-agent-sdk-py.md" "Still contains old v${PY_OLD}"
    else
      pass "rules/claude-agent-sdk-py.md" "No stale version"
    fi
  fi

  # --- templates/python/pyproject.toml ---
  echo "Checking templates/python/pyproject.toml ..."
  PY_TPL="$SKILL_ROOT/templates/python/pyproject.toml"
  if [[ ! -f "$PY_TPL" ]]; then
    fail "templates/python/pyproject.toml" "File not found"
  else
    if grep -q "${PY_NEW}" "$PY_TPL"; then
      pass "templates/python/pyproject.toml" "Contains ${PY_NEW}"
    else
      fail "templates/python/pyproject.toml" "Missing ${PY_NEW}"
    fi
  fi

  # --- Global stale Python version sweep ---
  echo ""
  echo "Sweeping for any remaining '${PY_OLD}' references in Python files ..."
  py_stale_hits=$(grep -rn "${PY_OLD}" "$SKILL_ROOT" \
    --include="SKILL-python.md" --include="claude-agent-sdk-py.md" --include="pyproject.toml" \
    --exclude-dir=agent --exclude-dir=node_modules --exclude-dir=reports --exclude-dir=.git --exclude-dir=tmp \
    2>/dev/null || true)

  if [[ -n "$py_stale_hits" ]]; then
    fail "GLOBAL-PY" "Stale Python version '${PY_OLD}' found in:\n$py_stale_hits"
  else
    pass "GLOBAL-PY" "No stale Python '${PY_OLD}' in Python skill files"
  fi
fi

# ---------------------------------------------------------------------------
# 2. JSON validity checks (always run)
# ---------------------------------------------------------------------------

echo ""
echo "Validating JSON files ..."
for json_file in "$SKILL_ROOT/templates/typescript/package.json" "$SKILL_ROOT/.claude-plugin/plugin.json"; do
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
