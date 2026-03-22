#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LOG_DIR="$HOME/Library/Logs/ScreenNotesMac"
LOG_FILE="$LOG_DIR/service.log"
CONFIG_FILE="$HOME/Library/Application Support/ScreenNotesMac/config.json"
mkdir -p "$LOG_DIR"

log_line() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >>"$LOG_FILE"
}

notify() {
  /usr/bin/osascript -e "display notification \"$1\" with title \"Screen Notes\"" >/dev/null 2>&1 || true
}

get_preview_doc_name() {
  /usr/bin/osascript <<'APPLESCRIPT' 2>/dev/null || true
try
  tell application "Preview"
    if (count of documents) > 0 then
      return name of front document
    end if
  end tell
on error
end try
return ""
APPLESCRIPT
}

prompt_note_multiline() {
  /usr/bin/osascript -l JavaScript - "$1" "$2" <<'JXA'
ObjC.import("AppKit");

function run(argv) {
  const snippet = (argv.length > 0 && argv[0]) ? argv[0] : "";
  const sourceName = (argv.length > 1 && argv[1]) ? argv[1] : "Preview";

  const app = $.NSApplication.sharedApplication;
  app.setActivationPolicy($.NSApplicationActivationPolicyRegular);
  app.activateIgnoringOtherApps(true);

  const alert = $.NSAlert.alloc.init;
  alert.setMessageText("Take Notes");
  alert.setInformativeText("Source: " + sourceName + "\n\nSelected text preview:\n" + snippet);
  alert.addButtonWithTitle("Save");
  alert.addButtonWithTitle("Cancel");
  alert.setAlertStyle($.NSInformationalAlertStyle);

  const container = $.NSView.alloc.initWithFrame($.NSMakeRect(0, 0, 560, 220));
  const scroll = $.NSScrollView.alloc.initWithFrame($.NSMakeRect(0, 0, 560, 220));
  scroll.setHasVerticalScroller(true);
  scroll.setBorderType($.NSBezelBorder);

  const textView = $.NSTextView.alloc.initWithFrame($.NSMakeRect(0, 0, 560, 220));
  textView.setFont($.NSFont.systemFontOfSize(13));
  textView.setEditable(true);
  scroll.setDocumentView(textView);

  container.addSubview(scroll);
  alert.setAccessoryView(container);

  const response = alert.runModal;
  if (response !== $.NSAlertFirstButtonReturn) {
    return "__SCREEN_NOTES_CANCELLED__";
  }

  return ObjC.unwrap(textView.string);
}
JXA
}

log_line "Service invoked. PID=$$"

SELECTED_TEXT="$(cat)"
log_line "Raw stdin bytes: ${#SELECTED_TEXT}"

if [[ -z "${SELECTED_TEXT//[[:space:]]/}" ]]; then
  if command -v pbpaste >/dev/null 2>&1; then
    SELECTED_TEXT="$(pbpaste || true)"
    log_line "Fallback pbpaste bytes: ${#SELECTED_TEXT}"
  fi
fi

if [[ -z "${SELECTED_TEXT//[[:space:]]/}" ]]; then
  notify "No selected text received from Preview."
  log_line "Empty selection input."
  exit 0
fi

WEBHOOK_URL="$(plutil -extract webhookUrl raw -o - "$CONFIG_FILE" 2>/dev/null || true)"
if [[ -z "${WEBHOOK_URL//[[:space:]]/}" ]]; then
  notify "Please configure Flomo webhook first."
  log_line "Missing webhook config."
  exit 1
fi

PREVIEW_TEXT="$(printf "%s" "$SELECTED_TEXT" | head -c 500)"
SOURCE_NAME="$(get_preview_doc_name)"
if [[ -z "${SOURCE_NAME//[[:space:]]/}" ]]; then
  SOURCE_NAME="Preview Document"
fi

NOTE_TEXT="$(prompt_note_multiline "$PREVIEW_TEXT" "$SOURCE_NAME")"

if [[ "$NOTE_TEXT" == "__SCREEN_NOTES_CANCELLED__" ]]; then
  log_line "User cancelled note dialog."
  exit 0
fi

CONTENT="$SELECTED_TEXT

——————————

$NOTE_TEXT

$SOURCE_NAME

#Mac-Reading"

CONTENT_JSON=$(/usr/bin/osascript -l JavaScript -e 'function run(argv){ return JSON.stringify(argv[0]); }' "$CONTENT")
PAYLOAD="{\"content\":$CONTENT_JSON}"

RESP_FILE="$(mktemp "${TMPDIR:-/tmp}/screen-notes-response.XXXXXX.txt")"
HTTP_CODE="$(
  /usr/bin/curl -sS -o "$RESP_FILE" -w "%{http_code}" \
    -X POST \
    -H "Content-Type: application/json" \
    --data "$PAYLOAD" \
    "$WEBHOOK_URL" \
    2>>"$LOG_FILE" || true
)"

if [[ ! "$HTTP_CODE" =~ ^2[0-9][0-9]$ ]]; then
  log_line "Flomo request failed. HTTP=$HTTP_CODE Body=$(cat "$RESP_FILE")"
  rm -f "$RESP_FILE"
  notify "Failed to save to Flomo."
  exit 1
fi

rm -f "$RESP_FILE"
log_line "Completed successfully."
notify "Saved to Flomo."
