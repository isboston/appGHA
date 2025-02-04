#!/usr/bin/env bash
# This script checks failed GitHub Actions for multiple repositories over last 24 hours
# and sends a single aggregated message to Telegram.

set -euo pipefail

# Comma-separated list of repos (e.g. "org/repo1,org/repo2")
# or можно сделать массивом ниже, если удобнее
REPOSITORIES=${REPOSITORIES:-"isboston/appGHA"}

# Environment variables for auth and messaging
GITHUB_TOKEN=${GITHUB_TOKEN:-""}
TELEGRAM_BOT_TOKEN=${TELEGRAM_BOT_TOKEN:-""}
TELEGRAM_CHAT_ID=${TELEGRAM_CHAT_ID:-""}

# Exit if tokens are not provided
if [[ -z "$GITHUB_TOKEN" || -z "$TELEGRAM_BOT_TOKEN" || -z "$TELEGRAM_CHAT_ID" ]]; then
  echo "ERROR: GITHUB_TOKEN, TELEGRAM_BOT_TOKEN, and TELEGRAM_CHAT_ID must be set."
  exit 1
fi

# Time window for checking failed runs
START_TIME=$(date -u -d '24 hours ago' +%Y-%m-%dT%H:%M:%SZ)

# Placeholder for aggregated results
AGGREGATED_RESULTS=()

# Loop through repositories and gather failures
IFS=',' read -ra REPO_ARRAY <<< "$REPOSITORIES"
for REPO in "${REPO_ARRAY[@]}"; do
  REPO=$(echo "$REPO" | xargs)  # Trim spaces

  # Pull last 100 runs in the last 24 hours from GitHub Actions
  DATA=$(curl -s -H "Authorization: Bearer $GITHUB_TOKEN" \
    "https://api.github.com/repos/${REPO}/actions/runs?per_page=100" )

  # Filter runs: created_at >= START_TIME, failed conclusion, branches main/release*/hotfix*/develop
  FAILURES=$(echo "$DATA" | jq --arg start "$START_TIME" '
    [
      .workflow_runs[] 
      | select(.created_at >= $start) 
      | select((.conclusion? // "failure") | test("failure|failed|error|startup_failure")) 
      | select(.head_branch | test("^(main|release/.+|hotfix/.+|develop)$"))
    ]'
  )

  COUNT=$(echo "$FAILURES" | jq 'length')
  if [[ "$COUNT" -gt 0 ]]; then
    # Build short lines for each failed run
    TEXT_LINES=$(echo "$FAILURES" | jq -r '
      [
        .[] 
        | "🔹 [\(.name | if (.|length) > 25 then ((.|.[:25]) + \"...\") else . end)](\(.html_url)) (\(.head_branch))"
      ] | join("\n")'
    )

    AGGREGATED_RESULTS+=("🕒 *24h | ${REPO} | ❌ ${COUNT} FAILED*\n${TEXT_LINES}\n")
  fi
done

# If no failures across all repos, just exit
if [[ "${#AGGREGATED_RESULTS[@]}" -eq 0 ]]; then
  echo "No failures found in the last 24 hours."
  exit 0
fi

# Merge all text blocks in one message
MESSAGE=$(printf "%s\n" "${AGGREGATED_RESULTS[@]}")

# Send message to Telegram
curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
  -H "Content-Type: application/json" \
  -d "{
    \"chat_id\": \"${TELEGRAM_CHAT_ID}\",
    \"text\": \"${MESSAGE}\",
    \"parse_mode\": \"Markdown\",
    \"disable_web_page_preview\": true
  }"
