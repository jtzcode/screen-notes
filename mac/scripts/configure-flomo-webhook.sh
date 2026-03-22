#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <flomo-webhook-url>" >&2
  exit 1
fi

WEBHOOK_URL="$1"
if [[ "$WEBHOOK_URL" != https://flomoapp.com/iwh/* ]]; then
  echo "Webhook URL must start with https://flomoapp.com/iwh/" >&2
  exit 1
fi

CONFIG_DIR="$HOME/Library/Application Support/ScreenNotesMac"
CONFIG_FILE="$CONFIG_DIR/config.json"
mkdir -p "$CONFIG_DIR"

json_escape() {
  local value="$1"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  printf '%s' "$value"
}

printf '{"webhookUrl":"%s"}\n' "$(json_escape "$WEBHOOK_URL")" >"$CONFIG_FILE"
echo "Saved webhook config to $CONFIG_FILE"
