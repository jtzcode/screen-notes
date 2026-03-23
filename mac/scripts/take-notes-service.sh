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
  /usr/bin/osascript -l JavaScript - "$1" "${2:-}" <<'JXA'
ObjC.import("AppKit");

function run(argv) {
  const snippet = (argv.length > 0 && argv[0]) ? argv[0] : "";
  const mode = (argv.length > 1 && argv[1]) ? argv[1] : "";
  const isSmokeTest = mode === "__SCREEN_NOTES_SMOKE_TEST__";
  const currentApp = Application.currentApplication();
  currentApp.includeStandardAdditions = true;
  currentApp.activate();

  const app = $.NSApplication.sharedApplication;
  app.setActivationPolicy($.NSApplicationActivationPolicyRegular);
  app.activateIgnoringOtherApps(true);
  $.NSRunningApplication.currentApplication.activateWithOptions(
    $.NSApplicationActivateIgnoringOtherApps | $.NSApplicationActivateAllWindows
  );

  const alert = $.NSAlert.alloc.init;
  alert.setMessageText("Take Notes");
  alert.addButtonWithTitle("Save");
  alert.addButtonWithTitle("Cancel");
  alert.setAlertStyle($.NSInformationalAlertStyle);

  const containerWidth = 600;
  const previewHeight = 96;
  const editorHeight = 220;
  const spacing = 12;
  const container = $.NSView.alloc.initWithFrame(
    $.NSMakeRect(0, 0, containerWidth, previewHeight + editorHeight + spacing)
  );

  const previewScroll = $.NSScrollView.alloc.initWithFrame(
    $.NSMakeRect(0, editorHeight + spacing, containerWidth, previewHeight)
  );
  previewScroll.setHasVerticalScroller(true);
  previewScroll.setBorderType($.NSBezelBorder);
  previewScroll.setDrawsBackground(true);

  const previewView = $.NSTextView.alloc.initWithFrame(
    $.NSMakeRect(0, 0, containerWidth, previewHeight)
  );
  previewView.setFont($.NSFont.systemFontOfSize(14));
  previewView.setEditable(false);
  previewView.setSelectable(true);
  previewView.setRichText(false);
  previewView.setImportsGraphics(false);
  previewView.setUsesFindBar(false);
  previewView.setAlignment($.NSLeftTextAlignment);
  previewView.setTextColor($.NSColor.secondaryLabelColor);
  previewView.setBackgroundColor($.NSColor.controlBackgroundColor);
  previewView.setTextContainerInset($.NSMakeSize(10, 10));
  previewView.textContainer.setWidthTracksTextView(true);
  previewView.setString($(snippet));
  previewScroll.setDocumentView(previewView);

  const scroll = $.NSScrollView.alloc.initWithFrame(
    $.NSMakeRect(0, 0, containerWidth, editorHeight)
  );
  scroll.setHasVerticalScroller(true);
  scroll.setBorderType($.NSBezelBorder);
  scroll.setDrawsBackground(true);

  const textView = $.NSTextView.alloc.initWithFrame(
    $.NSMakeRect(0, 0, containerWidth, editorHeight)
  );
  textView.setFont($.NSFont.systemFontOfSize(15));
  textView.setEditable(true);
  textView.setRichText(false);
  textView.setImportsGraphics(false);
  textView.setUsesFindBar(false);
  textView.setAlignment($.NSLeftTextAlignment);
  textView.setTextContainerInset($.NSMakeSize(10, 10));
  textView.textContainer.setWidthTracksTextView(true);
  scroll.setDocumentView(textView);

  container.addSubview(previewScroll);
  container.addSubview(scroll);
  alert.setAccessoryView(container);

  alert.window.setLevel($.NSFloatingWindowLevel);
  alert.window.makeKeyAndOrderFront(null);

  if (isSmokeTest) {
    return "__SCREEN_NOTES_SMOKE_TEST_OK__";
  }

  const response = alert.runModal;
  if (response !== $.NSAlertFirstButtonReturn) {
    return "__SCREEN_NOTES_CANCELLED__";
  }

  return ObjC.unwrap(textView.string);
}
JXA
}

log_line "Service invoked. PID=$$"

TEST_MODE="${SCREEN_NOTES_TEST_MODE:-}"

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

WEBHOOK_URL=""
if [[ "$TEST_MODE" != "smoke" ]]; then
  WEBHOOK_URL="$(plutil -extract webhookUrl raw -o - "$CONFIG_FILE" 2>/dev/null || true)"
  if [[ -z "${WEBHOOK_URL//[[:space:]]/}" ]]; then
    notify "Please configure Flomo webhook first."
    log_line "Missing webhook config."
    exit 1
  fi
else
  log_line "Smoke test mode enabled."
fi

PREVIEW_TEXT="$(printf "%s" "$SELECTED_TEXT" | head -c 500)"
SOURCE_NAME="$(get_preview_doc_name)"
if [[ -z "${SOURCE_NAME//[[:space:]]/}" ]]; then
  SOURCE_NAME="Preview Document"
fi

PROMPT_MODE=""
if [[ "$TEST_MODE" == "smoke" ]]; then
  PROMPT_MODE="__SCREEN_NOTES_SMOKE_TEST__"
fi

NOTE_TEXT="$(prompt_note_multiline "$PREVIEW_TEXT" "$PROMPT_MODE")"

if [[ "$NOTE_TEXT" == "__SCREEN_NOTES_CANCELLED__" ]]; then
  log_line "User cancelled note dialog."
  exit 0
fi

if [[ "$NOTE_TEXT" == "__SCREEN_NOTES_SMOKE_TEST_OK__" ]]; then
  log_line "Smoke test completed successfully."
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
