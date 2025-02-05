#!/usr/bin/env bash

set -euo pipefail

: "${GITHUB_TOKEN:?GITHUB_TOKEN must be set}"
: "${TELEGRAM_BOT_TOKEN:?TELEGRAM_BOT_TOKEN must be set}"
: "${TELEGRAM_CHAT_ID:?TELEGRAM_CHAT_ID must be set}"

START_TIME=$(date -u -d '24 hours ago' +%Y-%m-%dT%H:%M:%SZ)
# List of repos (e.g. "org/repo1,org/repo2")
IFS=',' read -ra REPO_LIST <<< "${REPOSITORIES:-"isboston/appGHA,isboston/appGHA2"}"
RESULT=""

for REPO in "${REPO_LIST[@]}"; do
  # Fetch last 100 runs
  DATA="$(curl -s -H "Authorization: Bearer $GITHUB_TOKEN" "https://api.github.com/repos/${REPO}/actions/runs?per_page=100")"
  FAILS="$(jq --arg start "$START_TIME" '[.workflow_runs[]
    | select(.created_at >= $start)
    | select(((.conclusion? // "failure") | test("failure|failed|error|startup_failure")))
    | select(.head_branch | test("^(main|release/.+|hotfix/.+|develop)$"))]' <<< "$DATA")"
  COUNT="$(jq length <<< "$FAILS")"

  if (( COUNT > 0 )); then
    LINES="$(jq -r '[.[] |
      "\u25FB [\(.name[:28] + (if (.name | length > 25) then "..." else "" end))](\(.html_url)) (\(.head_branch))"
    ] | join("\n")' <<< "$FAILS")"

    RESULT+="*\u274C $COUNT FAILED | 24h | REPO: $REPO*\n$LINES\n\n"
  fi
done

[ -z "$RESULT" ] && { echo "No failures found in the last 24 hours."; exit 0; }

curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
  -H "Content-Type: application/json" \
  -d "{\"chat_id\":\"${TELEGRAM_CHAT_ID}\",\"text\":\"${RESULT}\",\"parse_mode\":\"Markdown\",\"disable_web_page_preview\":true}"

