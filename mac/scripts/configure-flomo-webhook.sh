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

read_config_value() {
  local path="$1"
  plutil -extract "$path" raw -o - "$CONFIG_FILE" 2>/dev/null || true
}

EXISTING_GETBIJI_CLIENT_ID="$(read_config_value providerConfigs.getbiji.clientId)"
if [[ -z "${EXISTING_GETBIJI_CLIENT_ID//[[:space:]]/}" ]]; then
  EXISTING_GETBIJI_CLIENT_ID="$(read_config_value providerConfig.clientId)"
fi

EXISTING_GETBIJI_API_KEY="$(read_config_value providerConfigs.getbiji.apiKey)"
if [[ -z "${EXISTING_GETBIJI_API_KEY//[[:space:]]/}" ]]; then
  EXISTING_GETBIJI_API_KEY="$(read_config_value providerConfig.apiKey)"
fi

EXISTING_GETBIJI_TAGS="$(read_config_value providerConfigs.getbiji.defaultTags)"
if [[ -z "${EXISTING_GETBIJI_TAGS//[[:space:]]/}" ]]; then
  EXISTING_GETBIJI_TAGS="$(read_config_value providerConfig.defaultTags)"
fi

{
  printf '{"providerId":"flomo","providerConfigs":{'
  printf '"flomo":{"webhookUrl":"%s"}' "$(json_escape "$WEBHOOK_URL")"

  if [[ -n "${EXISTING_GETBIJI_CLIENT_ID//[[:space:]]/}" && -n "${EXISTING_GETBIJI_API_KEY//[[:space:]]/}" ]]; then
    printf ',"getbiji":{"clientId":"%s","apiKey":"%s","defaultTags":"%s"}' \
      "$(json_escape "$EXISTING_GETBIJI_CLIENT_ID")" \
      "$(json_escape "$EXISTING_GETBIJI_API_KEY")" \
      "$(json_escape "$EXISTING_GETBIJI_TAGS")"
  fi

  printf '}}\n'
} >"$CONFIG_FILE"

echo "Saved Flomo config to $CONFIG_FILE"
