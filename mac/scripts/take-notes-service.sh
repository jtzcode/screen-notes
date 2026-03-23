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

show_feedback() {
  /usr/bin/osascript -l JavaScript - "$1" "$2" "${3:-}" <<'JXA' >/dev/null 2>&1 || true
function run(argv) {
  const kind = (argv.length > 0 && argv[0]) ? argv[0] : "info";
  const message = (argv.length > 1 && argv[1]) ? argv[1] : "";
  const detail = (argv.length > 2 && argv[2]) ? argv[2] : "";
  const app = Application.currentApplication();
  app.includeStandardAdditions = true;
  app.activate();

  const options = {
    withTitle: "Screen Notes",
    buttons: ["OK"],
    defaultButton: "OK"
  };

  if (kind === "success" || kind === "info") {
    options.givingUpAfter = 1.6;
  }

  if (kind === "error") {
    options.withIcon = "caution";
  }

  const text = detail ? (message + "\n\n" + detail) : message;
  app.displayDialog(text, options);
}
JXA
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

get_front_app_name() {
  /usr/bin/osascript -l JavaScript <<'JXA' 2>/dev/null || true
ObjC.import("AppKit");

function run() {
  const app = $.NSWorkspace.sharedWorkspace.frontmostApplication;
  if (!app) {
    return "";
  }

  const name = ObjC.unwrap(app.localizedName);
  return name || "";
}
JXA
}

prompt_note_multiline() {
  /usr/bin/osascript -l JavaScript - "$1" "${2:-}" <<'JXA'
ObjC.import("AppKit");

function run(argv) {
  const snippet = (argv.length > 0 && argv[0]) ? argv[0] : "";
  const mode = (argv.length > 1 && argv[1]) ? argv[1] : "";
  const isSmokeTest = mode === "__SCREEN_NOTES_SMOKE_TEST__";
  const isSavePathTest = mode === "__SCREEN_NOTES_SAVE_PATH_TEST__";
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

  const W = 500;
  const pad = 22;
  const innerW = W - 2 * pad;
  const titleH = 30;
  const subtitleH = 34;
  const helperH = 16;
  const btnH = 32;
  const editorH = 150;
  const maxPrevH = 96;
  const minPrevH = 34;
  const quoteLeadW = 34;
  const sectionGap = 18;

  // Estimate preview height
  const lineH = 18;
  const cpl = Math.max(26, Math.floor((innerW - quoteLeadW - 18) / 7.2));
  const numLines = snippet.split("\n").reduce(function(n, ln) {
    return n + Math.max(1, Math.ceil((ln.length || 1) / cpl));
  }, 0);
  const prevH = Math.max(minPrevH, Math.min(numLines * lineH + 4, maxPrevH));

  // Layout (bottom-up)
  const botPad = 16;
  const topPad = 18;
  const totalH = botPad + btnH + 12 + helperH + sectionGap + editorH + sectionGap + prevH + sectionGap + subtitleH + 6 + titleH + topPad;

  const panel = $.NSPanel.alloc.initWithContentRectStyleMaskBackingDefer(
    $.NSMakeRect(0, 0, W, totalH),
    $.NSTitledWindowMask,
    $.NSBackingStoreBuffered,
    false
  );
  panel.setTitle($("Take Notes"));
  panel.setLevel($.NSFloatingWindowLevel);
  panel.setBackgroundColor($.NSColor.windowBackgroundColor);
  const cv = panel.contentView;

  var y = botPad;

  // -- Buttons --
  const saveBtnW = 132;
  const cancelBtnW = 82;
  const saveBtn = $.NSButton.alloc.initWithFrame(
    $.NSMakeRect(W - pad - saveBtnW, y, saveBtnW, btnH)
  );
  saveBtn.setTitle($("Save note"));
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
  y += btnH + 12;

  // -- Footer helper copy --
  const helperText = $.NSTextField.alloc.initWithFrame(
    $.NSMakeRect(pad, y, innerW, helperH)
  );
  helperText.setStringValue($("Preview source and #Mac-Reading are added automatically in Flomo."));
  helperText.setBezeled(false);
  helperText.setDrawsBackground(false);
  helperText.setEditable(false);
  helperText.setSelectable(false);
  helperText.setFont($.NSFont.systemFontOfSize(11));
  helperText.setTextColor($.NSColor.secondaryLabelColor);
  cv.addSubview(helperText);
  y += helperH + sectionGap;

  // -- Note editor --
  const editorSurface = $.NSView.alloc.initWithFrame(
    $.NSMakeRect(pad, y, innerW, editorH)
  );
  editorSurface.setWantsLayer(true);
  editorSurface.setValueForKeyPath($.NSColor.textBackgroundColor, "layer.backgroundColor");
  editorSurface.setValueForKeyPath($(12), "layer.cornerRadius");
  editorSurface.setValueForKeyPath($(true), "layer.masksToBounds");
  cv.addSubview(editorSurface);

  const editorScroll = $.NSScrollView.alloc.initWithFrame(
    $.NSMakeRect(pad + 1, y + 1, innerW - 2, editorH - 2)
  );
  editorScroll.setHasVerticalScroller(true);
  editorScroll.setBorderType($.NSNoBorder);
  editorScroll.setDrawsBackground(false);

  const textView = $.NSTextView.alloc.initWithFrame(
    $.NSMakeRect(0, 0, innerW, editorH)
  );
  textView.setFont($.NSFont.systemFontOfSize(15));
  textView.setEditable(true);
  textView.setRichText(false);
  textView.setImportsGraphics(false);
  textView.setUsesFindBar(false);
  textView.setTextColor($.NSColor.labelColor);
  textView.setDrawsBackground(false);
  textView.setTextContainerInset($.NSMakeSize(12, 10));
  textView.setAlignment($.NSLeftTextAlignment);
  textView.textContainer.setWidthTracksTextView(true);
  editorScroll.setDocumentView(textView);
  cv.addSubview(editorScroll);
  y += editorH + sectionGap;

  // -- Selected text quote --
  const accent = $.NSView.alloc.initWithFrame(
    $.NSMakeRect(pad, y + 4, 2, prevH - 8)
  );
  accent.setWantsLayer(true);
  accent.setValueForKeyPath($.NSColor.controlAccentColor, "layer.backgroundColor");
  cv.addSubview(accent);

  const quoteMark = $.NSTextField.alloc.initWithFrame(
    $.NSMakeRect(pad + 10, y + prevH - 24, 24, 24)
  );
  quoteMark.setStringValue($("\u201c"));
  quoteMark.setBezeled(false);
  quoteMark.setDrawsBackground(false);
  quoteMark.setEditable(false);
  quoteMark.setSelectable(false);
  quoteMark.setFont($.NSFont.systemFontOfSize(28));
  quoteMark.setTextColor($.NSColor.tertiaryLabelColor);
  cv.addSubview(quoteMark);

  const previewScroll = $.NSScrollView.alloc.initWithFrame(
    $.NSMakeRect(pad + quoteLeadW, y, innerW - quoteLeadW, prevH)
  );
  previewScroll.setHasVerticalScroller(true);
  previewScroll.setBorderType($.NSNoBorder);
  previewScroll.setDrawsBackground(false);

  const previewView = $.NSTextView.alloc.initWithFrame(
    $.NSMakeRect(0, 0, innerW - quoteLeadW, prevH)
  );
  previewView.setFont($.NSFont.systemFontOfSize(14));
  previewView.setEditable(false);
  previewView.setSelectable(true);
  previewView.setRichText(false);
  previewView.setAlignment($.NSLeftTextAlignment);
  previewView.setTextColor($.NSColor.secondaryLabelColor);
  previewView.setDrawsBackground(false);
  previewView.setTextContainerInset($.NSMakeSize(0, 2));
  previewView.textContainer.setWidthTracksTextView(true);
  previewView.setString($(snippet));
  previewScroll.setDocumentView(previewView);
  cv.addSubview(previewScroll);
  y += prevH + sectionGap;

  // -- Header --
  const subtitle = $.NSTextField.alloc.initWithFrame(
    $.NSMakeRect(pad, y, innerW, subtitleH)
  );
  subtitle.setStringValue($("Keep the selected text for context, then write the note you want to save."));
  subtitle.setBezeled(false);
  subtitle.setDrawsBackground(false);
  subtitle.setEditable(false);
  subtitle.setSelectable(false);
  subtitle.setFont($.NSFont.systemFontOfSize(13));
  subtitle.setTextColor($.NSColor.secondaryLabelColor);
  subtitle.setLineBreakMode($.NSLineBreakByWordWrapping);
  cv.addSubview(subtitle);
  y += subtitleH + 6;

  const title = $.NSTextField.alloc.initWithFrame(
    $.NSMakeRect(pad, y, innerW, titleH)
  );
  title.setStringValue($("Take Notes"));
  title.setBezeled(false);
  title.setDrawsBackground(false);
  title.setEditable(false);
  title.setSelectable(false);
  title.setFont($.NSFont.boldSystemFontOfSize(23));
  title.setTextColor($.NSColor.labelColor);
  cv.addSubview(title);

  if (isSmokeTest) {
    return "__SCREEN_NOTES_SMOKE_TEST_OK__";
  }

  if (isSavePathTest) {
    return "__SCREEN_NOTES_SAVE_PATH_OK__";
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
  const modalCode = Number(result);
  panel.orderOut(null);

  if (modalCode !== 1000) {
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
  show_feedback "error" "No selected text received from Preview."
  log_line "Empty selection input."
  exit 0
fi

WEBHOOK_URL=""
if [[ "$TEST_MODE" != "smoke" ]]; then
  WEBHOOK_URL="$(plutil -extract webhookUrl raw -o - "$CONFIG_FILE" 2>/dev/null || true)"
  if [[ -z "${WEBHOOK_URL//[[:space:]]/}" ]]; then
    show_feedback "error" "Please configure Flomo webhook first."
    log_line "Missing webhook config."
    exit 1
  fi
else
  log_line "Smoke test mode enabled."
fi

PREVIEW_TEXT="$(printf "%s" "$SELECTED_TEXT" | head -c 500)"
SOURCE_NAME="$(get_preview_doc_name)"
if [[ -z "${SOURCE_NAME//[[:space:]]/}" ]]; then
  SOURCE_NAME="$(get_front_app_name)"
fi
if [[ -z "${SOURCE_NAME//[[:space:]]/}" ]]; then
  SOURCE_NAME="Selected Text"
fi

PROMPT_MODE=""
if [[ "$TEST_MODE" == "smoke" ]]; then
  PROMPT_MODE="__SCREEN_NOTES_SMOKE_TEST__"
elif [[ "$TEST_MODE" == "save-path" ]]; then
  PROMPT_MODE="__SCREEN_NOTES_SAVE_PATH_TEST__"
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

if [[ "$NOTE_TEXT" == "__SCREEN_NOTES_SAVE_PATH_OK__" ]]; then
  log_line "Save-path test completed successfully."
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
  ERROR_DETAIL="HTTP status: $HTTP_CODE"
  if [[ -s "$RESP_FILE" ]]; then
    ERROR_BODY="$(tr '\n' ' ' < "$RESP_FILE" | head -c 220)"
    ERROR_DETAIL="$ERROR_DETAIL

$ERROR_BODY"
  fi
  rm -f "$RESP_FILE"
  show_feedback "error" "Failed to save to Flomo." "$ERROR_DETAIL"
  exit 1
fi

rm -f "$RESP_FILE"
log_line "Completed successfully."
show_feedback "success" "Saved to Flomo."
