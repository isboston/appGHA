import os
import requests
from datetime import datetime, timedelta
import json

def get_failed_workflows(repo_name, token):
    url = f"https://api.github.com/repos/{repo_name}/actions/runs"
    
    # Calculate time range (last 24 hours)
    now = datetime.utcnow()
    start_time = now - timedelta(hours=24)
    
    headers = {
        "Authorization": f"token {token}",
        "Accept": "application/vnd.github.v3+json"
    }
    
    params = {
        "status": "completed",
        "created": f">{start_time.isoformat()}Z",
        "per_page": 100  # Increase if you have more than 100 runs/day
    }
    
    response = requests.get(url, headers=headers, params=params)
    response.raise_for_status()
    
    failed_runs = []
    data = response.json()
    
    for run in data.get("workflow_runs", []):
        if run["conclusion"] == "failure":
            failed_runs.append({
                "name": run["name"],
                "url": run["html_url"],
                "created_at": run["created_at"]
            })
    
    return failed_runs

def send_telegram_message(message):
    bot_token = os.getenv("TELEGRAM_BOT_TOKEN")
    chat_id = os.getenv("TELEGRAM_CHAT_ID")
    
    if not bot_token or not chat_id:
        raise ValueError("Telegram credentials not found")
    
    url = f"https://api.telegram.org/bot{bot_token}/sendMessage"
    payload = {
        "chat_id": chat_id,
        "text": message,
        "parse_mode": "HTML"
    }
    
    response = requests.post(url, json=payload)
    response.raise_for_status()

def main():
    all_failed = []
    
    # Check first repository
    repo1 = os.getenv("GITHUB_REPO1")
    token1 = os.getenv("GITHUB_TOKEN_REPO1")
    if repo1 and token1:
        all_failed += get_failed_workflows(repo1, token1)
    
    # Check second repository
    repo2 = os.getenv("GITHUB_REPO2")
    token2 = os.getenv("GITHUB_TOKEN_REPO2")
    if repo2 and token2:
        all_failed += get_failed_workflows(repo2, token2)
    
    if not all_failed:
        print("No failed workflows found")
        return
    
    # Format message
    message = ["⛔ <b>Failed Workflows Report (24h)</b>"]
    for i, run in enumerate(all_failed, 1):
        message.append(
            f"{i}. {run['name']}\n"
            f"   Time: {run['created_at']}\n"
            f"   URL: {run['url']}"
        )
    
    full_message = "\n\n".join(message)
    send_telegram_message(full_message)
    print("Report sent successfully")

if __name__ == "__main__":
    main()