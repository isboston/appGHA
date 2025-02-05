#!/usr/bin/env bash

set -euo pipefail

# List of repos (e.g. "org/repo1,org/repo2")
REPOSITORIES=${REPOSITORIES:-"isboston/appGHA,isboston/appGHA2"}
: "${GITHUB_TOKEN:?GITHUB_TOKEN must be set}"
: "${TELEGRAM_BOT_TOKEN:?TELEGRAM_BOT_TOKEN must be set}"
: "${TELEGRAM_CHAT_ID:?TELEGRAM_CHAT_ID must be set}"

START_TIME=$(date -u -d '24 hours ago' +%Y-%m-%dT%H:%M:%SZ)
AGGREGATED_RESULTS=()

IFS=',' read -ra REPO_ARRAY <<< "$REPOSITORIES"
for REPO in "${REPO_ARRAY[@]}"; do
  REPO=$(echo "$REPO" | xargs)

  # Pull last 100 runs in the last 24 hours
  DATA=$(curl -s -H "Authorization: Bearer $GITHUB_TOKEN" "https://api.github.com/repos/${REPO}/actions/runs?per_page=100")

  FAILURES=$(echo "$DATA" | jq --arg start "$START_TIME" '
    [.workflow_runs[]
      | select(.created_at >= $start)
      | select((.conclusion? // "failure") | test("failure|failed|error|startup_failure"))
      | select(.head_branch | test("^(main|release/.+|hotfix/.+|develop)$"))]'
  )
  COUNT=$(echo "$FAILURES" | jq 'length')

  if [[ "$COUNT" -gt 0 ]]; then
    TEXT_LINES=$(echo "$FAILURES" | jq -r '
      [
        .[]
        | "\u25FB [\(.name[:28] + (if (.name | length > 25) then "..." else "" end))](\(.html_url)) (\(.head_branch))"
      ] | join("\n")'
    )
    AGGREGATED_RESULTS+=("*\u274C ${COUNT} FAILED | 24h | REPO: ${REPO}*\n${TEXT_LINES}\n")
  fi
done

if [[ "${#AGGREGATED_RESULTS[@]}" -eq 0 ]]; then
  echo "No failures found in the last 24 hours."
  exit 0
fi

MESSAGE=$(printf "%s\n" "${AGGREGATED_RESULTS[@]}")

curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
  -H "Content-Type: application/json" \
  -d "{
    \"chat_id\": \"${TELEGRAM_CHAT_ID}\",
    \"text\": \"${MESSAGE}\",
    \"parse_mode\": \"Markdown\",
    \"disable_web_page_preview\": true
  }"
