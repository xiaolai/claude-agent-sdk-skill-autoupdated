#!/usr/bin/env bash
# typecheck-templates.sh — Type-check all template files. No LLM, no API cost.
# TypeScript: tsc --noEmit (catches type errors, broken imports, wrong signatures)
# Python: py_compile (syntax) + import resolution check
# Exit 0 = all checks passed. Exit 1 = failures found.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

failures=0
checks_passed=0

pass() { ((checks_passed++)); echo "  OK:   $1"; }
fail() { ((failures++));       echo "  FAIL: $1"; }

# ---------------------------------------------------------------------------
# 1. TypeScript — tsc --noEmit
# ---------------------------------------------------------------------------

echo "=== TypeScript template type-check ==="
TS_DIR="$SKILL_ROOT/templates/typescript"

if [[ -d "$TS_DIR" ]]; then
  pushd "$TS_DIR" > /dev/null

  # Install deps if not present (idempotent, uses lockfile if available)
  if [[ ! -d "node_modules" ]]; then
    echo "  Installing TypeScript dependencies..."
    npm install --silent 2>/dev/null || true
  fi

  # Run tsc --noEmit to check types without generating output
  TSC_OUTPUT=$(npx tsc --noEmit 2>&1) || true
  TSC_EXIT=$?

  if [[ $TSC_EXIT -eq 0 ]]; then
    # Count .ts files checked
    TS_COUNT=$(ls -1 *.ts 2>/dev/null | wc -l | tr -d ' ')
    pass "All $TS_COUNT TypeScript templates pass type-check"
  else
    fail "TypeScript templates have type errors:"
    echo "$TSC_OUTPUT" | head -50
    # Report each error file
    echo "$TSC_OUTPUT" | grep -oP '^\S+\.ts' | sort -u | while read -r f; do
      fail "  $f"
    done
  fi

  popd > /dev/null
else
  echo "  SKIP: templates/typescript/ not found"
fi

# ---------------------------------------------------------------------------
# 2. Python — py_compile (syntax check)
# ---------------------------------------------------------------------------

echo ""
echo "=== Python template syntax-check ==="
PY_DIR="$SKILL_ROOT/templates/python"

if [[ -d "$PY_DIR" ]]; then
  for pyfile in "$PY_DIR"/*.py; do
    [[ -f "$pyfile" ]] || continue
    basename=$(basename "$pyfile")
    if python3 -m py_compile "$pyfile" 2>&1; then
      pass "$basename — valid syntax"
    else
      fail "$basename — syntax error"
    fi
  done
else
  echo "  SKIP: templates/python/ not found"
fi

# ---------------------------------------------------------------------------
# 3. Python — import resolution check
# ---------------------------------------------------------------------------

echo ""
echo "=== Python import resolution check ==="

if command -v python3 &> /dev/null; then
  # Check if the SDK is importable at all
  if python3 -c "import claude_agent_sdk" 2>/dev/null; then
    # Extract all unique imports used across templates
    IMPORTS=$(grep -hroP 'from claude_agent_sdk import \K[^)]+' "$PY_DIR"/*.py 2>/dev/null \
      | tr ',' '\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | sort -u | grep -v '^$')

    if [[ -n "$IMPORTS" ]]; then
      IMPORT_LIST=$(echo "$IMPORTS" | paste -sd, -)
      if python3 -c "from claude_agent_sdk import $IMPORT_LIST" 2>&1; then
        pass "All template imports resolve: $IMPORT_LIST"
      else
        fail "Some template imports don't resolve"
        # Test each import individually to find the broken one(s)
        while IFS= read -r imp; do
          if ! python3 -c "from claude_agent_sdk import $imp" 2>/dev/null; then
            fail "  Cannot import: $imp"
          fi
        done <<< "$IMPORTS"
      fi
    else
      pass "No claude_agent_sdk imports found to check"
    fi
  else
    echo "  SKIP: claude_agent_sdk not installed (expected in some environments)"
  fi
else
  echo "  SKIP: python3 not found"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

echo ""
echo "========================================="
echo "  Passed: $checks_passed"
echo "  Failed: $failures"
echo "========================================="

if (( failures > 0 )); then
  echo ""
  echo "TEMPLATE CHECK FAILED — $failures issue(s)"
  exit 1
else
  echo ""
  echo "TEMPLATE CHECK PASSED"
  exit 0
fi
