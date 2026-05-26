#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 2 || $# -gt 3 ]]; then
  echo "Usage: $0 <getbiji-client-id> <getbiji-api-key> [default-tags-csv]" >&2
  exit 1
fi

CLIENT_ID="$1"
API_KEY="$2"
DEFAULT_TAGS="${3:-}"

if [[ -z "${CLIENT_ID//[[:space:]]/}" ]]; then
  echo "Client ID cannot be empty." >&2
  exit 1
fi

if [[ -z "${API_KEY//[[:space:]]/}" ]]; then
  echo "API key cannot be empty." >&2
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

read_config_value() {
  local path="$1"
  plutil -extract "$path" raw -o - "$CONFIG_FILE" 2>/dev/null || true
}

EXISTING_FLOMO_WEBHOOK_URL="$(read_config_value providerConfigs.flomo.webhookUrl)"
if [[ -z "${EXISTING_FLOMO_WEBHOOK_URL//[[:space:]]/}" ]]; then
  EXISTING_FLOMO_WEBHOOK_URL="$(read_config_value providerConfig.webhookUrl)"
fi
if [[ -z "${EXISTING_FLOMO_WEBHOOK_URL//[[:space:]]/}" ]]; then
  EXISTING_FLOMO_WEBHOOK_URL="$(read_config_value webhookUrl)"
fi

{
  printf '{"providerId":"getbiji","providerConfigs":{'

  if [[ -n "${EXISTING_FLOMO_WEBHOOK_URL//[[:space:]]/}" ]]; then
    printf '"flomo":{"webhookUrl":"%s"},' "$(json_escape "$EXISTING_FLOMO_WEBHOOK_URL")"
  fi

  printf '"getbiji":{"clientId":"%s","apiKey":"%s","defaultTags":"%s"}' \
    "$(json_escape "$CLIENT_ID")" \
    "$(json_escape "$API_KEY")" \
    "$(json_escape "$DEFAULT_TAGS")"

  printf '}}\n'
} >"$CONFIG_FILE"

echo "Saved Get笔记 config to $CONFIG_FILE"