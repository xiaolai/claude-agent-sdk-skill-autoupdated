#!/usr/bin/env bash
# monitor.sh — Zero API cost change detection for claude-agent-sdk skill.
# Checks npm registry + GitHub for SDK changes against saved state.
# Exit 0 = no changes. Exit 1 = changes detected (reports written).
# Exit 2 = error (missing tools, network failure, etc.)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_FILE="${SCRIPT_DIR}/state.json"
CHANGE_REPORT="${CHANGE_REPORT:-/tmp/change-report.json}"
FRESH_STATE="${FRESH_STATE:-/tmp/fresh-state.json}"

SDK_PACKAGE="@anthropic-ai/claude-agent-sdk"
SDK_REPO="anthropics/claude-agent-sdk-typescript"
CLAUDE_CODE_REPO="anthropics/claude-code"

PY_PACKAGE="claude-agent-sdk"
PY_REPO="anthropics/claude-agent-sdk-python"

# ---------------------------------------------------------------------------
# Prerequisites
# ---------------------------------------------------------------------------

for cmd in npm jq gh curl; do
  if ! command -v "$cmd" &>/dev/null; then
    echo "ERROR: '$cmd' is required but not found in PATH" >&2
    exit 2
  fi
done

if [[ ! -f "$STATE_FILE" ]]; then
  echo "ERROR: state.json not found at $STATE_FILE" >&2
  exit 2
fi

# ---------------------------------------------------------------------------
# Read current state
# ---------------------------------------------------------------------------

old_version=$(jq -r '.typescript.registry.version' "$STATE_FILE")
old_release_tag=$(jq -r '.typescript.github.latestRelease.tag' "$STATE_FILE")
last_scanned=$(jq -r '.typescript.lastScannedIssueNumber' "$STATE_FILE")

py_old_version=$(jq -r '.python.registry.version' "$STATE_FILE")
py_old_release_tag=$(jq -r '.python.github.latestRelease.tag // ""' "$STATE_FILE")
py_last_scanned=$(jq -r '.python.lastScannedIssueNumber // 0' "$STATE_FILE")

echo "Current state:"
echo "  TS: npm=$old_version  release=$old_release_tag  lastScanned=#$last_scanned"
echo "  PY: pypi=$py_old_version  release=$py_old_release_tag  lastScanned=#$py_last_scanned"

# ---------------------------------------------------------------------------
# 1. Fetch fresh npm metadata
# ---------------------------------------------------------------------------

echo "Fetching npm metadata for $SDK_PACKAGE ..."
npm_json=$(npm view "$SDK_PACKAGE" version peerDependencies engines --json 2>/dev/null) || {
  echo "ERROR: npm view failed" >&2
  exit 2
}

new_version=$(echo "$npm_json" | jq -r '.version')
new_peer_deps=$(echo "$npm_json" | jq -c '.peerDependencies // {}')
new_engines=$(echo "$npm_json" | jq -c '.engines // {}')

echo "  npm latest: $new_version"

# ---------------------------------------------------------------------------
# 1b. Fetch fresh PyPI metadata
# ---------------------------------------------------------------------------

echo "Fetching PyPI metadata for $PY_PACKAGE ..."
pypi_json=$(curl -s "https://pypi.org/pypi/$PY_PACKAGE/json") || {
  echo "ERROR: PyPI fetch failed" >&2
  exit 2
}

py_new_version=$(echo "$pypi_json" | jq -r '.info.version')
echo "  PyPI latest: $py_new_version"

# ---------------------------------------------------------------------------
# 2. Fetch latest GitHub release (TypeScript)
# ---------------------------------------------------------------------------

echo "Fetching latest release from $SDK_REPO ..."
release_json=$(gh api "repos/$SDK_REPO/releases/latest" 2>/dev/null) || {
  echo "WARN: Could not fetch latest release (may not exist yet)" >&2
  release_json='{"tag_name":"","name":"","body":""}'
}

new_release_tag=$(echo "$release_json" | jq -r '.tag_name')
new_release_name=$(echo "$release_json" | jq -r '.name')
new_release_body=$(echo "$release_json" | jq -r '.body')

echo "  latest release: $new_release_tag"

# ---------------------------------------------------------------------------
# 2b. Fetch latest GitHub release (Python)
# ---------------------------------------------------------------------------

echo "Fetching latest release from $PY_REPO ..."
py_release_json=$(gh api "repos/$PY_REPO/releases/latest" 2>/dev/null) || {
  echo "WARN: Could not fetch Python latest release (may not exist yet)" >&2
  py_release_json='{"tag_name":"","name":"","body":""}'
}

py_new_release_tag=$(echo "$py_release_json" | jq -r '.tag_name')
py_new_release_name=$(echo "$py_release_json" | jq -r '.name')
py_new_release_body=$(echo "$py_release_json" | jq -r '.body')

echo "  latest Python release: $py_new_release_tag"

# ---------------------------------------------------------------------------
# 3. Check tracked issues state (TypeScript SDK repo)
# ---------------------------------------------------------------------------

echo "Checking tracked issues ..."
tracked_numbers=$(jq -r '.typescript.trackedIssues | keys[]' "$STATE_FILE")
issue_changes="[]"

for num in $tracked_numbers; do
  old_state=$(jq -r ".typescript.trackedIssues[\"$num\"].state" "$STATE_FILE")
  new_state=$(gh api "repos/$SDK_REPO/issues/$num" --jq '.state' 2>/dev/null) || {
    echo "  WARN: Could not fetch issue #$num" >&2
    continue
  }
  echo "  #$num: $old_state -> $new_state"
  if [[ "$old_state" != "$new_state" ]]; then
    issue_changes=$(echo "$issue_changes" | jq \
      --arg num "$num" --arg old "$old_state" --arg new "$new_state" \
      '. + [{"issue": $num, "repo": "'"$SDK_REPO"'", "oldState": $old, "newState": $new}]')
  fi
done

# Check external tracked issues (claude-code repo)
ext_numbers=$(jq -r '.typescript.trackedIssuesExternal | keys[]' "$STATE_FILE" 2>/dev/null) || ext_numbers=""

for num in $ext_numbers; do
  repo=$(jq -r ".typescript.trackedIssuesExternal[\"$num\"].repo" "$STATE_FILE")
  old_state=$(jq -r ".typescript.trackedIssuesExternal[\"$num\"].state" "$STATE_FILE")
  new_state=$(gh api "repos/$repo/issues/$num" --jq '.state' 2>/dev/null) || {
    echo "  WARN: Could not fetch $repo#$num" >&2
    continue
  }
  echo "  $repo#$num: $old_state -> $new_state"
  if [[ "$old_state" != "$new_state" ]]; then
    issue_changes=$(echo "$issue_changes" | jq \
      --arg num "$num" --arg old "$old_state" --arg new "$new_state" --arg repo "$repo" \
      '. + [{"issue": $num, "repo": $repo, "oldState": $old, "newState": $new}]')
  fi
done

# ---------------------------------------------------------------------------
# 4. Scan for new bug-labeled issues above last scanned number
# ---------------------------------------------------------------------------

echo "Scanning for new bug issues above #$last_scanned ..."
new_bugs="[]"
new_last_scanned="$last_scanned"

# Fetch recent issues with bug label, sorted by creation (newest first)
bug_issues=$(gh api "repos/$SDK_REPO/issues?labels=bug&state=open&sort=created&direction=desc&per_page=30" 2>/dev/null) || {
  echo "WARN: Could not fetch bug issues" >&2
  bug_issues="[]"
}

while IFS= read -r row; do
  issue_num=$(echo "$row" | jq -r '.number')
  if (( issue_num > last_scanned )); then
    title=$(echo "$row" | jq -r '.title')
    echo "  NEW: #$issue_num - $title"
    new_bugs=$(echo "$new_bugs" | jq \
      --arg num "$issue_num" --arg title "$title" \
      '. + [{"issue": ($num | tonumber), "title": $title}]')
    if (( issue_num > new_last_scanned )); then
      new_last_scanned=$issue_num
    fi
  fi
done < <(echo "$bug_issues" | jq -c '.[]')

# ---------------------------------------------------------------------------
# 4b. Check tracked Python issues state
# ---------------------------------------------------------------------------

echo "Checking tracked Python issues ..."
py_tracked_numbers=$(jq -r '.python.trackedIssues | keys[]' "$STATE_FILE" 2>/dev/null) || py_tracked_numbers=""

for num in $py_tracked_numbers; do
  old_state=$(jq -r ".python.trackedIssues[\"$num\"].state" "$STATE_FILE")
  new_state=$(gh api "repos/$PY_REPO/issues/$num" --jq '.state' 2>/dev/null) || {
    echo "  WARN: Could not fetch Python issue #$num" >&2
    continue
  }
  echo "  PY#$num: $old_state -> $new_state"
  if [[ "$old_state" != "$new_state" ]]; then
    issue_changes=$(echo "$issue_changes" | jq \
      --arg num "$num" --arg old "$old_state" --arg new "$new_state" \
      '. + [{"issue": $num, "repo": "'"$PY_REPO"'", "oldState": $old, "newState": $new}]')
  fi
done

# ---------------------------------------------------------------------------
# 4c. Scan for new Python bug issues
# ---------------------------------------------------------------------------

echo "Scanning for new Python bug issues above #$py_last_scanned ..."
py_new_bugs="[]"
py_new_last_scanned="$py_last_scanned"

py_bug_issues=$(gh api "repos/$PY_REPO/issues?labels=bug&state=open&sort=created&direction=desc&per_page=30" 2>/dev/null) || {
  echo "WARN: Could not fetch Python bug issues" >&2
  py_bug_issues="[]"
}

while IFS= read -r row; do
  issue_num=$(echo "$row" | jq -r '.number')
  if (( issue_num > py_last_scanned )); then
    title=$(echo "$row" | jq -r '.title')
    echo "  NEW PY: #$issue_num - $title"
    py_new_bugs=$(echo "$py_new_bugs" | jq \
      --arg num "$issue_num" --arg title "$title" \
      '. + [{"issue": ($num | tonumber), "title": $title}]')
    if (( issue_num > py_new_last_scanned )); then
      py_new_last_scanned=$issue_num
    fi
  fi
done < <(echo "$py_bug_issues" | jq -c '.[]')

# ---------------------------------------------------------------------------
# 5. Drift check — skill files must match state.json version
# ---------------------------------------------------------------------------

skill_version=$(grep -oP 'claude-agent-sdk@\K[0-9.]+' "${SCRIPT_DIR}/../SKILL-typescript.md" 2>/dev/null || echo "")
if [[ -n "$skill_version" && "$skill_version" != "$new_version" ]]; then
  echo "  DRIFT: SKILL-typescript.md says $skill_version but npm/state says $new_version — forcing update"
fi

# Python drift check
py_skill_version=$(grep -oP 'claude-agent-sdk==\K[0-9.]+' "${SCRIPT_DIR}/../SKILL-python.md" 2>/dev/null || echo "")
if [[ -n "$py_skill_version" && "$py_skill_version" != "$py_new_version" ]]; then
  echo "  DRIFT: SKILL-python.md says $py_skill_version but PyPI/state says $py_new_version — forcing update"
fi

# ---------------------------------------------------------------------------
# 6. Compare against state — determine if anything changed
# ---------------------------------------------------------------------------

changes="[]"

# --- TypeScript changes ---
if [[ -n "$skill_version" && "$skill_version" != "$new_version" ]]; then
  changes=$(echo "$changes" | jq \
    --arg old "$skill_version" --arg new "$new_version" \
    '. + [{"type": "npm_version", "language": "typescript", "old": $old, "new": $new}]')
elif [[ "$old_version" != "$new_version" ]]; then
  changes=$(echo "$changes" | jq \
    --arg old "$old_version" --arg new "$new_version" \
    '. + [{"type": "npm_version", "language": "typescript", "old": $old, "new": $new}]')
fi

old_peer_deps=$(jq -c '.typescript.registry.peerDependencies // {}' "$STATE_FILE")
if [[ "$old_peer_deps" != "$new_peer_deps" ]]; then
  changes=$(echo "$changes" | jq \
    --argjson old "$old_peer_deps" --argjson new "$new_peer_deps" \
    '. + [{"type": "peer_deps", "old": $old, "new": $new}]')
fi

old_engines=$(jq -c '.typescript.registry.engines // {}' "$STATE_FILE")
if [[ "$old_engines" != "$new_engines" ]]; then
  changes=$(echo "$changes" | jq \
    --argjson old "$old_engines" --argjson new "$new_engines" \
    '. + [{"type": "engines", "old": $old, "new": $new}]')
fi

if [[ "$old_release_tag" != "$new_release_tag" ]]; then
  changes=$(echo "$changes" | jq \
    --arg old "$old_release_tag" --arg new "$new_release_tag" \
    --arg body "$new_release_body" \
    '. + [{"type": "github_release", "language": "typescript", "old": $old, "new": $new, "releaseNotes": $body}]')
fi

# --- Python changes ---
if [[ -n "$py_skill_version" && "$py_skill_version" != "$py_new_version" ]]; then
  changes=$(echo "$changes" | jq \
    --arg old "$py_skill_version" --arg new "$py_new_version" \
    '. + [{"type": "pypi_version", "language": "python", "old": $old, "new": $new}]')
elif [[ "$py_old_version" != "$py_new_version" ]]; then
  changes=$(echo "$changes" | jq \
    --arg old "$py_old_version" --arg new "$py_new_version" \
    '. + [{"type": "pypi_version", "language": "python", "old": $old, "new": $new}]')
fi

if [[ "$py_old_release_tag" != "$py_new_release_tag" ]]; then
  changes=$(echo "$changes" | jq \
    --arg old "$py_old_release_tag" --arg new "$py_new_release_tag" \
    --arg body "$py_new_release_body" \
    '. + [{"type": "github_release", "language": "python", "old": $old, "new": $new, "releaseNotes": $body}]')
fi

# --- Shared changes (issues from both repos) ---
issue_count=$(echo "$issue_changes" | jq 'length')
if (( issue_count > 0 )); then
  changes=$(echo "$changes" | jq --argjson ic "$issue_changes" \
    '. + [{"type": "issue_state_changes", "changes": $ic}]')
fi

bug_count=$(echo "$new_bugs" | jq 'length')
if (( bug_count > 0 )); then
  changes=$(echo "$changes" | jq --argjson nb "$new_bugs" \
    '. + [{"type": "new_bug_issues", "language": "typescript", "issues": $nb}]')
fi

py_bug_count=$(echo "$py_new_bugs" | jq 'length')
if (( py_bug_count > 0 )); then
  changes=$(echo "$changes" | jq --argjson nb "$py_new_bugs" \
    '. + [{"type": "new_bug_issues", "language": "python", "issues": $nb}]')
fi

total_changes=$(echo "$changes" | jq 'length')

# ---------------------------------------------------------------------------
# 7. Write outputs or exit clean
# ---------------------------------------------------------------------------

if (( total_changes == 0 )); then
  echo ""
  echo "No changes detected. Everything is up to date."
  exit 0
fi

echo ""
echo "$total_changes change(s) detected!"

# Build fresh state
jq -n \
  --arg ver "$new_version" \
  --argjson peer "$new_peer_deps" \
  --argjson eng "$new_engines" \
  --arg rtag "$new_release_tag" \
  --arg rname "$new_release_name" \
  --argjson ti "$(jq '.typescript.trackedIssues' "$STATE_FILE")" \
  --argjson tie "$(jq '.typescript.trackedIssuesExternal // {}' "$STATE_FILE")" \
  --arg ls "$new_last_scanned" \
  --arg pyver "$py_new_version" \
  --arg pyrtag "$py_new_release_tag" \
  --arg pyrname "$py_new_release_name" \
  --argjson pyti "$(jq '.python.trackedIssues // {}' "$STATE_FILE")" \
  --argjson pytie "$(jq '.python.trackedIssuesExternal // {}' "$STATE_FILE")" \
  --arg pyls "$py_new_last_scanned" \
  --arg pylav "$(jq -r '.python.lastAuditedVersion // "none"' "$STATE_FILE")" \
  '{
    typescript: {
      registry: { version: $ver, peerDependencies: $peer, engines: $eng },
      github: { repo: "anthropics/claude-agent-sdk-typescript", latestRelease: { tag: $rtag, name: $rname } },
      trackedIssues: $ti,
      trackedIssuesExternal: $tie,
      lastScannedIssueNumber: ($ls | tonumber),
      lastAuditedVersion: $ver
    },
    python: {
      registry: { version: $pyver },
      github: { repo: "anthropics/claude-agent-sdk-python", latestRelease: { tag: $pyrtag, name: $pyrname } },
      trackedIssues: $pyti,
      trackedIssuesExternal: $pytie,
      lastScannedIssueNumber: ($pyls | tonumber),
      lastAuditedVersion: $pylav
    },
    lastUpdated: (now | todate)
  }' > "$FRESH_STATE"

# Update issue states in fresh state
while IFS= read -r row; do
  num=$(echo "$row" | jq -r '.issue')
  new_st=$(echo "$row" | jq -r '.newState')
  repo=$(echo "$row" | jq -r '.repo')
  if [[ "$repo" == "$SDK_REPO" ]]; then
    jq --arg n "$num" --arg s "$new_st" \
      '.typescript.trackedIssues[$n].state = $s' "$FRESH_STATE" > "${FRESH_STATE}.tmp" \
      && mv "${FRESH_STATE}.tmp" "$FRESH_STATE"
  elif [[ "$repo" == "$PY_REPO" ]]; then
    jq --arg n "$num" --arg s "$new_st" \
      '.python.trackedIssues[$n].state = $s' "$FRESH_STATE" > "${FRESH_STATE}.tmp" \
      && mv "${FRESH_STATE}.tmp" "$FRESH_STATE"
  else
    jq --arg n "$num" --arg s "$new_st" \
      '.typescript.trackedIssuesExternal[$n].state = $s' "$FRESH_STATE" > "${FRESH_STATE}.tmp" \
      && mv "${FRESH_STATE}.tmp" "$FRESH_STATE"
  fi
done < <(echo "$issue_changes" | jq -c '.[]')

# Write change report
jq -n \
  --argjson changes "$changes" \
  --arg old_version "$old_version" \
  --arg new_version "$new_version" \
  --arg py_old_version "$py_old_version" \
  --arg py_new_version "$py_new_version" \
  --argjson new_bugs "$new_bugs" \
  --argjson py_new_bugs "$py_new_bugs" \
  --argjson issue_changes "$issue_changes" \
  '{
    detectedAt: (now | todate),
    tsOldVersion: $old_version,
    tsNewVersion: $new_version,
    pyOldVersion: $py_old_version,
    pyNewVersion: $py_new_version,
    oldVersion: $old_version,
    newVersion: $new_version,
    changes: $changes,
    issueStateChanges: $issue_changes,
    newBugIssues: $new_bugs,
    pyNewBugIssues: $py_new_bugs
  }' > "$CHANGE_REPORT"

echo "Change report written to: $CHANGE_REPORT"
echo "Fresh state written to:   $FRESH_STATE"

exit 1
