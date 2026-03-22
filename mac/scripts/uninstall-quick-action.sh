#!/usr/bin/env bash
set -euo pipefail

SERVICE_NAME="Take Notes"
WORKFLOW_DIR="${SCREEN_NOTES_SERVICES_DIR:-$HOME/Library/Services}/$SERVICE_NAME.workflow"
RUNTIME_SCRIPT="$HOME/Library/Application Support/ScreenNotesMac/take-notes-service.sh"

if [[ -d "$WORKFLOW_DIR" ]]; then
  rm -rf "$WORKFLOW_DIR"
  echo "Removed: $WORKFLOW_DIR"
else
  echo "Not found: $WORKFLOW_DIR"
fi

if [[ -f "$RUNTIME_SCRIPT" ]]; then
  rm -f "$RUNTIME_SCRIPT"
  echo "Removed: $RUNTIME_SCRIPT"
fi

/System/Library/CoreServices/pbs -flush >/dev/null 2>&1 || true
/System/Library/CoreServices/pbs -update >/dev/null 2>&1 || true

echo "Services cache refreshed."
