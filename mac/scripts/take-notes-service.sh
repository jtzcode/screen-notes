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

  ObjC.registerSubclass({
    name: "SNHelper",
    methods: {
      "doSave:": {
        types: ["void", ["id"]],
        implementation: function(_) {
          $.NSApplication.sharedApplication.stopModalWithCode(1000);
        }
      },
      "doCancel:": {
        types: ["void", ["id"]],
        implementation: function(_) {
          $.NSApplication.sharedApplication.stopModalWithCode(1001);
        }
      }
    }
  });
  const helper = $.SNHelper.alloc.init;

  const W = 380;
  const pad = 16;
  const innerW = W - 2 * pad;
  const labelH = 16;
  const btnH = 28;
  const editorH = 90;
  const maxPrevH = 64;

  // Estimate preview height
  const lineH = 17;
  const cpl = Math.floor(innerW / 7.5);
  const numLines = snippet.split("\n").reduce(function(n, ln) {
    return n + Math.max(1, Math.ceil((ln.length || 1) / cpl));
  }, 0);
  const prevH = Math.max(24, Math.min(numLines * lineH + 8, maxPrevH));

  // Layout (bottom-up)
  const botPad = 10;
  const cardH = labelH + prevH;
  const totalH = botPad + btnH + 8 + editorH + 2 + labelH + 8 + cardH + 8;

  const panel = $.NSPanel.alloc.initWithContentRectStyleMaskBackingDefer(
    $.NSMakeRect(0, 0, W, totalH),
    $.NSTitledWindowMask,
    $.NSBackingStoreBuffered,
    false
  );
  panel.setTitle($("\u270F\uFE0F Take Notes"));
  panel.setLevel($.NSFloatingWindowLevel);
  const cv = panel.contentView;

  var y = botPad;

  // -- Buttons --
  const saveBtnW = 120;
  const cancelBtnW = 80;
  const saveBtn = $.NSButton.alloc.initWithFrame(
    $.NSMakeRect(W - pad - saveBtnW, y, saveBtnW, btnH)
  );
  saveBtn.setTitle($("Save to Flomo"));
  saveBtn.setBezelStyle(1);
  saveBtn.setKeyEquivalent($("\r"));
  saveBtn.setTarget(helper);
  saveBtn.setAction("doSave:");
  cv.addSubview(saveBtn);

  const cancelBtn = $.NSButton.alloc.initWithFrame(
    $.NSMakeRect(W - pad - saveBtnW - 8 - cancelBtnW, y, cancelBtnW, btnH)
  );
  cancelBtn.setTitle($("Cancel"));
  cancelBtn.setBezelStyle(1);
  cancelBtn.setKeyEquivalent($("\x1b"));
  cancelBtn.setTarget(helper);
  cancelBtn.setAction("doCancel:");
  cv.addSubview(cancelBtn);
  y += btnH + 8;

  // -- Editor --
  const scroll = $.NSScrollView.alloc.initWithFrame(
    $.NSMakeRect(pad, y, innerW, editorH)
  );
  scroll.setHasVerticalScroller(true);
  scroll.setBorderType($.NSBezelBorder);
  scroll.setDrawsBackground(true);
  scroll.setWantsLayer(true);
  scroll.setValueForKeyPath($(6), "layer.cornerRadius");
  scroll.setValueForKeyPath($(true), "layer.masksToBounds");

  const textView = $.NSTextView.alloc.initWithFrame(
    $.NSMakeRect(0, 0, innerW, editorH)
  );
  textView.setFont($.NSFont.systemFontOfSize(13));
  textView.setEditable(true);
  textView.setRichText(false);
  textView.setImportsGraphics(false);
  textView.setUsesFindBar(false);
  textView.setTextContainerInset($.NSMakeSize(6, 4));
  textView.textContainer.setWidthTracksTextView(true);
  scroll.setDocumentView(textView);
  cv.addSubview(scroll);
  y += editorH + 2;

  // -- YOUR NOTE label --
  const noteLabel = $.NSTextField.alloc.initWithFrame(
    $.NSMakeRect(pad, y, innerW, labelH)
  );
  noteLabel.setStringValue($("YOUR NOTE"));
  noteLabel.setBezeled(false);
  noteLabel.setDrawsBackground(false);
  noteLabel.setEditable(false);
  noteLabel.setSelectable(false);
  noteLabel.setFont($.NSFont.boldSystemFontOfSize(10));
  noteLabel.setTextColor($.NSColor.secondaryLabelColor);
  cv.addSubview(noteLabel);
  y += labelH + 8;

  // -- Selected text card --
  const card = $.NSView.alloc.initWithFrame(
    $.NSMakeRect(pad, y, innerW, cardH)
  );
  card.setWantsLayer(true);
  card.setValueForKeyPath($.NSColor.controlBackgroundColor, "layer.backgroundColor");
  card.setValueForKeyPath($(6), "layer.cornerRadius");
  card.setValueForKeyPath($(true), "layer.masksToBounds");

  const selLabel = $.NSTextField.alloc.initWithFrame(
    $.NSMakeRect(0, cardH - labelH - 2, innerW, labelH)
  );
  selLabel.setStringValue($("SELECTED TEXT"));
  selLabel.setBezeled(false);
  selLabel.setDrawsBackground(false);
  selLabel.setEditable(false);
  selLabel.setSelectable(false);
  selLabel.setFont($.NSFont.boldSystemFontOfSize(10));
  selLabel.setTextColor($.NSColor.tertiaryLabelColor);
  card.addSubview(selLabel);

  const previewScroll = $.NSScrollView.alloc.initWithFrame(
    $.NSMakeRect(0, 0, innerW, prevH)
  );
  previewScroll.setHasVerticalScroller(true);
  previewScroll.setBorderType($.NSNoBorder);
  previewScroll.setDrawsBackground(false);

  const previewView = $.NSTextView.alloc.initWithFrame(
    $.NSMakeRect(0, 0, innerW, prevH)
  );
  previewView.setFont($.NSFont.systemFontOfSize(13));
  previewView.setEditable(false);
  previewView.setSelectable(true);
  previewView.setRichText(false);
  previewView.setTextColor($.NSColor.secondaryLabelColor);
  previewView.setDrawsBackground(false);
  previewView.setTextContainerInset($.NSMakeSize(6, 2));
  previewView.textContainer.setWidthTracksTextView(true);
  previewView.setString($(snippet));
  previewScroll.setDocumentView(previewView);
  card.addSubview(previewScroll);
  cv.addSubview(card);

  if (isSmokeTest) {
    return "__SCREEN_NOTES_SMOKE_TEST_OK__";
  }

  // Center on screen (panel.center() is not bridged in JXA)
  const screen = $.NSScreen.mainScreen.frame;
  const panelFrame = panel.frame;
  const cx = (screen.size.width - panelFrame.size.width) / 2;
  const cy = (screen.size.height - panelFrame.size.height) / 2;
  panel.setFrameOrigin($.NSMakePoint(cx, cy));

  panel.makeKeyAndOrderFront(null);
  panel.makeFirstResponder(textView);
  const result = app.runModalForWindow(panel);
  panel.orderOut(null);

  if (result !== 1000) {
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
