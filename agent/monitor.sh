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

# ---------------------------------------------------------------------------
# Prerequisites
# ---------------------------------------------------------------------------

for cmd in npm jq gh; do
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

old_version=$(jq -r '.npm.version' "$STATE_FILE")
old_release_tag=$(jq -r '.github.latestRelease.tag' "$STATE_FILE")
last_scanned=$(jq -r '.lastScannedIssueNumber' "$STATE_FILE")

echo "Current state: npm=$old_version  release=$old_release_tag  lastScanned=#$last_scanned"

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
# 2. Fetch latest GitHub release
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
# 3. Check tracked issues state (SDK repo)
# ---------------------------------------------------------------------------

echo "Checking tracked issues ..."
tracked_numbers=$(jq -r '.trackedIssues | keys[]' "$STATE_FILE")
issue_changes="[]"

for num in $tracked_numbers; do
  old_state=$(jq -r ".trackedIssues[\"$num\"].state" "$STATE_FILE")
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
ext_numbers=$(jq -r '.trackedIssuesExternal | keys[]' "$STATE_FILE" 2>/dev/null) || ext_numbers=""

for num in $ext_numbers; do
  repo=$(jq -r ".trackedIssuesExternal[\"$num\"].repo" "$STATE_FILE")
  old_state=$(jq -r ".trackedIssuesExternal[\"$num\"].state" "$STATE_FILE")
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
# 5. Compare against state — determine if anything changed
# ---------------------------------------------------------------------------

changes="[]"

if [[ "$old_version" != "$new_version" ]]; then
  changes=$(echo "$changes" | jq \
    --arg old "$old_version" --arg new "$new_version" \
    '. + [{"type": "npm_version", "old": $old, "new": $new}]')
fi

old_peer_deps=$(jq -c '.npm.peerDependencies // {}' "$STATE_FILE")
if [[ "$old_peer_deps" != "$new_peer_deps" ]]; then
  changes=$(echo "$changes" | jq \
    --argjson old "$old_peer_deps" --argjson new "$new_peer_deps" \
    '. + [{"type": "peer_deps", "old": $old, "new": $new}]')
fi

old_engines=$(jq -c '.npm.engines // {}' "$STATE_FILE")
if [[ "$old_engines" != "$new_engines" ]]; then
  changes=$(echo "$changes" | jq \
    --argjson old "$old_engines" --argjson new "$new_engines" \
    '. + [{"type": "engines", "old": $old, "new": $new}]')
fi

if [[ "$old_release_tag" != "$new_release_tag" ]]; then
  changes=$(echo "$changes" | jq \
    --arg old "$old_release_tag" --arg new "$new_release_tag" \
    --arg body "$new_release_body" \
    '. + [{"type": "github_release", "old": $old, "new": $new, "releaseNotes": $body}]')
fi

issue_count=$(echo "$issue_changes" | jq 'length')
if (( issue_count > 0 )); then
  changes=$(echo "$changes" | jq --argjson ic "$issue_changes" \
    '. + [{"type": "issue_state_changes", "changes": $ic}]')
fi

bug_count=$(echo "$new_bugs" | jq 'length')
if (( bug_count > 0 )); then
  changes=$(echo "$changes" | jq --argjson nb "$new_bugs" \
    '. + [{"type": "new_bug_issues", "issues": $nb}]')
fi

total_changes=$(echo "$changes" | jq 'length')

# ---------------------------------------------------------------------------
# 6. Write outputs or exit clean
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
  --argjson ti "$(jq '.trackedIssues' "$STATE_FILE")" \
  --argjson tie "$(jq '.trackedIssuesExternal // {}' "$STATE_FILE")" \
  --arg ls "$new_last_scanned" \
  '{
    npm: { version: $ver, peerDependencies: $peer, engines: $eng },
    github: { latestRelease: { tag: $rtag, name: $rname } },
    trackedIssues: $ti,
    trackedIssuesExternal: $tie,
    lastScannedIssueNumber: ($ls | tonumber),
    lastUpdated: (now | todate)
  }' > "$FRESH_STATE"

# Update issue states in fresh state
while IFS= read -r row; do
  num=$(echo "$row" | jq -r '.issue')
  new_st=$(echo "$row" | jq -r '.newState')
  repo=$(echo "$row" | jq -r '.repo')
  if [[ "$repo" == "$SDK_REPO" ]]; then
    jq --arg n "$num" --arg s "$new_st" \
      '.trackedIssues[$n].state = $s' "$FRESH_STATE" > "${FRESH_STATE}.tmp" \
      && mv "${FRESH_STATE}.tmp" "$FRESH_STATE"
  else
    jq --arg n "$num" --arg s "$new_st" \
      '.trackedIssuesExternal[$n].state = $s' "$FRESH_STATE" > "${FRESH_STATE}.tmp" \
      && mv "${FRESH_STATE}.tmp" "$FRESH_STATE"
  fi
done < <(echo "$issue_changes" | jq -c '.[]')

# Write change report
jq -n \
  --argjson changes "$changes" \
  --arg old_version "$old_version" \
  --arg new_version "$new_version" \
  --argjson new_bugs "$new_bugs" \
  --argjson issue_changes "$issue_changes" \
  '{
    detectedAt: (now | todate),
    oldVersion: $old_version,
    newVersion: $new_version,
    changes: $changes,
    issueStateChanges: $issue_changes,
    newBugIssues: $new_bugs
  }' > "$CHANGE_REPORT"

echo "Change report written to: $CHANGE_REPORT"
echo "Fresh state written to:   $FRESH_STATE"

exit 1
