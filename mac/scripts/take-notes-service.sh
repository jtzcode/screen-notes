#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_SUPPORT_DIR="$HOME/Library/Application Support/ScreenNotesMac"
LOG_DIR="$HOME/Library/Logs/ScreenNotesMac"
LOG_FILE="$LOG_DIR/service.log"
CONFIG_FILE="$APP_SUPPORT_DIR/config.json"
RUNTIME_X_SKILL_DIR="$APP_SUPPORT_DIR/skills/baoyu-post-to-x"
CODEX_X_SKILL_DIR="${CODEX_HOME:-$HOME/.codex}/skills/baoyu-post-to-x"
X_SKILL_DIR="$RUNTIME_X_SKILL_DIR"
if [[ ! -d "$X_SKILL_DIR" ]]; then
  X_SKILL_DIR="$CODEX_X_SKILL_DIR"
fi
X_POST_SCRIPT="$X_SKILL_DIR/scripts/x-browser.ts"
X_PROFILE_DIR="$APP_SUPPORT_DIR/x-profile"
mkdir -p "$LOG_DIR"

X_POST_ERROR=""
X_RUNTIME=()
ACTIVE_PROVIDER_ID=""
PROVIDER_ID=""
PROVIDER_NAME=""
PROVIDER_WEBHOOK_URL=""
PROVIDER_CLIENT_ID=""
PROVIDER_API_KEY=""
PROVIDER_DEFAULT_TAGS=""
FLOMO_WEBHOOK_URL=""
GETBIJI_CLIENT_ID=""
GETBIJI_API_KEY=""
GETBIJI_DEFAULT_TAGS=""
AVAILABLE_PROVIDER_IDS=()

find_runtime_bin() {
  local name="$1"
  local path_value

  path_value="$(command -v "$name" 2>/dev/null || true)"
  if [[ -n "${path_value//[[:space:]]/}" ]]; then
    printf '%s' "$path_value"
    return 0
  fi

  for candidate in "/opt/homebrew/bin/$name" "/usr/local/bin/$name" "/usr/bin/$name"; do
    if [[ -x "$candidate" ]]; then
      printf '%s' "$candidate"
      return 0
    fi
  done

  return 1
}

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

notify_banner() {
  /usr/bin/osascript -e "display notification \"$1\" with title \"Screen Notes\"" >/dev/null 2>&1 || true
}

resolve_x_runtime() {
  local bun_bin
  local npx_bin

  if bun_bin="$(find_runtime_bin bun)"; then
    X_RUNTIME=("$bun_bin")
    return 0
  fi

  if npx_bin="$(find_runtime_bin npx)"; then
    X_RUNTIME=("$npx_bin" -y bun)
    return 0
  fi

  return 1
}

extract_composer_note() {
  /usr/bin/osascript -l JavaScript - "$1" <<'JXA'
function run(argv) {
  const payload = JSON.parse(argv[0] || "{}");
  return typeof payload.note === "string" ? payload.note : "";
}
JXA
}

extract_composer_post_flag() {
  /usr/bin/osascript -l JavaScript - "$1" <<'JXA'
function run(argv) {
  const payload = JSON.parse(argv[0] || "{}");
  return payload.postToX ? "1" : "0";
}
JXA
}

extract_composer_provider_id() {
  /usr/bin/osascript -l JavaScript - "$1" <<'JXA'
function run(argv) {
  const payload = JSON.parse(argv[0] || "{}");
  return typeof payload.providerId === "string" ? payload.providerId : "";
}
JXA
}

build_x_post_content() {
  local selected_text="$1"
  local note_text="$2"

  printf '%s' "$selected_text"
  printf '\n\n%s\n\n' "——————————"
  printf '%s' "$note_text"
}

json_stringify() {
  /usr/bin/osascript -l JavaScript -e 'function run(argv){ return JSON.stringify(argv[0] || ""); }' "${1-}"
}

json_stringify_tag_list() {
  /usr/bin/osascript -l JavaScript -e 'function run(argv){ const tags = (argv[0] || "").split(",").map((tag) => tag.trim()).filter(Boolean); return JSON.stringify(tags); }' "${1-}"
}

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

build_note_content() {
  local selected_text="$1"
  local note_text="$2"
  local source_name="$3"

  printf '%s\n\n%s\n\n%s\n\n%s\n\n%s' \
    "$selected_text" \
    "——————————" \
    "$note_text" \
    "$source_name" \
    "#Mac-Reading"
}

provider_name_for_id() {
  case "$1" in
    flomo)
      printf 'Flomo'
      ;;
    getbiji)
      printf 'Get笔记'
      ;;
    *)
      printf '%s' "$1"
      ;;
  esac
}

write_provider_config_file() {
  local active_provider_id="$1"

  mkdir -p "$APP_SUPPORT_DIR"

  {
    printf '{"providerId":"%s","providerConfigs":{' "$(json_escape "$active_provider_id")"

    local wrote_provider=""
    if [[ -n "${FLOMO_WEBHOOK_URL//[[:space:]]/}" ]]; then
      printf '"flomo":{"webhookUrl":"%s"}' "$(json_escape "$FLOMO_WEBHOOK_URL")"
      wrote_provider="1"
    fi

    if [[ -n "${GETBIJI_CLIENT_ID//[[:space:]]/}" && -n "${GETBIJI_API_KEY//[[:space:]]/}" ]]; then
      if [[ -n "$wrote_provider" ]]; then
        printf ','
      fi
      printf '"getbiji":{"clientId":"%s","apiKey":"%s","defaultTags":"%s"}' \
        "$(json_escape "$GETBIJI_CLIENT_ID")" \
        "$(json_escape "$GETBIJI_API_KEY")" \
        "$(json_escape "$GETBIJI_DEFAULT_TAGS")"
    fi

    printf '}}\n'
  } >"$CONFIG_FILE"
}

apply_provider_selection() {
  local selected_provider_id="$1"

  case "$selected_provider_id" in
    flomo)
      if [[ -z "${FLOMO_WEBHOOK_URL//[[:space:]]/}" ]]; then
        return 1
      fi

      PROVIDER_ID="flomo"
      PROVIDER_NAME="Flomo"
      PROVIDER_WEBHOOK_URL="$FLOMO_WEBHOOK_URL"
      PROVIDER_CLIENT_ID=""
      PROVIDER_API_KEY=""
      PROVIDER_DEFAULT_TAGS=""
      return 0
      ;;
    getbiji)
      if [[ -z "${GETBIJI_CLIENT_ID//[[:space:]]/}" || -z "${GETBIJI_API_KEY//[[:space:]]/}" ]]; then
        return 1
      fi

      PROVIDER_ID="getbiji"
      PROVIDER_NAME="Get笔记"
      PROVIDER_WEBHOOK_URL=""
      PROVIDER_CLIENT_ID="$GETBIJI_CLIENT_ID"
      PROVIDER_API_KEY="$GETBIJI_API_KEY"
      PROVIDER_DEFAULT_TAGS="$GETBIJI_DEFAULT_TAGS"
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

load_provider_config() {
  local configured_provider_id
  local legacy_webhook_url

  ACTIVE_PROVIDER_ID=""
  PROVIDER_ID=""
  PROVIDER_NAME=""
  PROVIDER_WEBHOOK_URL=""
  PROVIDER_CLIENT_ID=""
  PROVIDER_API_KEY=""
  PROVIDER_DEFAULT_TAGS=""
  FLOMO_WEBHOOK_URL=""
  GETBIJI_CLIENT_ID=""
  GETBIJI_API_KEY=""
  GETBIJI_DEFAULT_TAGS=""
  AVAILABLE_PROVIDER_IDS=()

  if [[ ! -f "$CONFIG_FILE" ]]; then
    return 1
  fi

  configured_provider_id="$(read_config_value providerId)"
  FLOMO_WEBHOOK_URL="$(read_config_value providerConfigs.flomo.webhookUrl)"
  if [[ -z "${FLOMO_WEBHOOK_URL//[[:space:]]/}" ]]; then
    legacy_webhook_url="$(read_config_value webhookUrl)"
    if [[ -n "${legacy_webhook_url//[[:space:]]/}" ]]; then
      FLOMO_WEBHOOK_URL="$legacy_webhook_url"
    elif [[ "$configured_provider_id" == "flomo" ]]; then
      FLOMO_WEBHOOK_URL="$(read_config_value providerConfig.webhookUrl)"
    fi
  fi

  GETBIJI_CLIENT_ID="$(read_config_value providerConfigs.getbiji.clientId)"
  GETBIJI_API_KEY="$(read_config_value providerConfigs.getbiji.apiKey)"
  GETBIJI_DEFAULT_TAGS="$(read_config_value providerConfigs.getbiji.defaultTags)"
  if [[ -z "${GETBIJI_CLIENT_ID//[[:space:]]/}" && "$configured_provider_id" == "getbiji" ]]; then
    GETBIJI_CLIENT_ID="$(read_config_value providerConfig.clientId)"
    GETBIJI_API_KEY="$(read_config_value providerConfig.apiKey)"
    GETBIJI_DEFAULT_TAGS="$(read_config_value providerConfig.defaultTags)"
  fi

  if [[ -n "${FLOMO_WEBHOOK_URL//[[:space:]]/}" ]]; then
    AVAILABLE_PROVIDER_IDS+=("flomo")
  fi

  if [[ -n "${GETBIJI_CLIENT_ID//[[:space:]]/}" && -n "${GETBIJI_API_KEY//[[:space:]]/}" ]]; then
    AVAILABLE_PROVIDER_IDS+=("getbiji")
  fi

  if (( ${#AVAILABLE_PROVIDER_IDS[@]} == 0 )); then
    return 1
  fi

  ACTIVE_PROVIDER_ID="$configured_provider_id"
  if ! apply_provider_selection "$ACTIVE_PROVIDER_ID"; then
    ACTIVE_PROVIDER_ID="${AVAILABLE_PROVIDER_IDS[0]}"
    apply_provider_selection "$ACTIVE_PROVIDER_ID" || return 1
  fi

  return 0
}

send_note_to_provider() {
  local content="$1"
  local title="$2"
  local resp_file="$3"
  local content_json
  local payload
  local tags_json
  local title_json

  case "$PROVIDER_ID" in
    flomo)
      content_json="$(json_stringify "$content")"
      payload="{\"content\":$content_json}"

      /usr/bin/curl -sS -o "$resp_file" -w "%{http_code}" \
        -X POST \
        -H "Content-Type: application/json" \
        --data "$payload" \
        "$PROVIDER_WEBHOOK_URL" \
        2>>"$LOG_FILE" || true
      ;;
    getbiji)
      title_json="$(json_stringify "$title")"
      content_json="$(json_stringify "$content")"
      tags_json="$(json_stringify_tag_list "$PROVIDER_DEFAULT_TAGS")"
      payload="{\"title\":$title_json,\"content\":$content_json}"
      if [[ "$tags_json" != "[]" ]]; then
        payload="{\"title\":$title_json,\"content\":$content_json,\"tags\":$tags_json}"
      fi

      /usr/bin/curl -sS -o "$resp_file" -w "%{http_code}" \
        -X POST \
        -H "X-Client-ID: $PROVIDER_CLIENT_ID" \
        -H "Authorization: $PROVIDER_API_KEY" \
        -H "Content-Type: application/json" \
        --data "$payload" \
        "https://openapi.biji.com/open/api/v1/resource/note/save" \
        2>>"$LOG_FILE" || true
      ;;
    *)
      printf '000'
      ;;
  esac
}

ensure_x_skill_dependencies() {
  local scripts_dir="$X_SKILL_DIR/scripts"

  if [[ ! -f "$scripts_dir/package.json" ]]; then
    return 0
  fi

  if [[ -d "$scripts_dir/node_modules" ]]; then
    return 0
  fi

  if ! resolve_x_runtime; then
    X_POST_ERROR="Install Bun or Node.js (for npx) to enable X posting."
    return 1
  fi

  log_line "Installing X skill dependencies for $scripts_dir"
  if (cd "$scripts_dir" && "${X_RUNTIME[@]}" install >>"$LOG_FILE" 2>&1); then
    return 0
  fi

  X_POST_ERROR="Failed to install X skill dependencies. Check $LOG_FILE."
  return 1
}

open_x_compose() {
  local post_text="$1"
  local output_file
  local attempt=1

  X_POST_ERROR=""

  if [[ ! -f "$X_POST_SCRIPT" ]]; then
    X_POST_ERROR="Install the baoyu-post-to-x skill under $RUNTIME_X_SKILL_DIR or $CODEX_X_SKILL_DIR."
    return 1
  fi

  if ! resolve_x_runtime; then
    X_POST_ERROR="Install Bun or Node.js (for npx) to enable X posting."
    return 1
  fi

  if ! ensure_x_skill_dependencies; then
    return 1
  fi

  if [[ ! -x "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" ]] \
    && [[ ! -x "/Applications/Chromium.app/Contents/MacOS/Chromium" ]] \
    && [[ ! -x "/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge" ]]; then
    X_POST_ERROR="Install Google Chrome, Chromium, or Edge, or set X_BROWSER_CHROME_PATH."
    return 1
  fi

  mkdir -p "$X_PROFILE_DIR"
  output_file="$(mktemp "${TMPDIR:-/tmp}/screen-notes-x-post.XXXXXX.log")"

  while (( attempt <= 2 )); do
    : >"$output_file"
    if "${X_RUNTIME[@]}" "$X_POST_SCRIPT" "$post_text" --profile "$X_PROFILE_DIR" >>"$output_file" 2>&1; then
      cat "$output_file" >>"$LOG_FILE"
      rm -f "$output_file"
      return 0
    fi

    cat "$output_file" >>"$LOG_FILE"

    if grep -Eq 'Chrome debug port not ready|Unable to connect' "$output_file" && (( attempt == 1 )); then
      log_line "X compose failed due to Chrome debug port issue. Retrying after cleanup."
      pkill -f "Chrome.*remote-debugging-port" >/dev/null 2>&1 || true
      pkill -f "Chromium.*remote-debugging-port" >/dev/null 2>&1 || true
      sleep 2
      attempt=$((attempt + 1))
      continue
    fi

    X_POST_ERROR="$(tail -n 8 "$output_file")"
    break
  done

  rm -f "$output_file"

  if [[ -z "${X_POST_ERROR//[[:space:]]/}" ]]; then
    X_POST_ERROR="Failed to open the X compose window."
  fi

  return 1
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
  /usr/bin/osascript -l JavaScript - "$1" "${2:-}" "${3:-}" "${4:-}" <<'JXA'
ObjC.import("AppKit");

function run(argv) {
  const snippet = (argv.length > 0 && argv[0]) ? argv[0] : "";
  const mode = (argv.length > 1 && argv[1]) ? argv[1] : "";
  const activeProviderId = (argv.length > 2 && argv[2]) ? argv[2] : "flomo";
  const availableProviderIds = (argv.length > 3 && argv[3])
    ? argv[3].split(",").filter(Boolean)
    : [activeProviderId];
  const isSmokeTest = mode === "__SCREEN_NOTES_SMOKE_TEST__";
  const isSavePathTest = mode === "__SCREEN_NOTES_SAVE_PATH_TEST__";
  const providerNames = {
    flomo: "Flomo",
    getbiji: "Get笔记"
  };
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
  const subtitleH = 34;
  const helperH = 16;
  const providerLabelH = 16;
  const providerPickerH = 28;
  const providerBlockH = providerLabelH + 6 + providerPickerH;
  const checkboxH = 22;
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
  const totalH = botPad + btnH + 12 + helperH + 10 + providerBlockH + 10 + checkboxH + sectionGap + editorH + sectionGap + prevH + sectionGap + subtitleH + topPad;

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

  const slogans = [
    "Read widely. Think slowly. Write clearly.",
    "A good note is a thought made visible.",
    "What you reread shapes what you remember.",
    "Turn fragments into understanding.",
    "Pause, reflect, then keep only the essential.",
    "Reading collects sparks. Thinking makes fire.",
    "Small notes become long memory.",
    "Clarity begins when you name the idea."
  ];
  const slogan = slogans[Math.floor(Math.random() * slogans.length)];
  const sloganFont =
    $.NSFont.fontWithNameSize($("Baskerville-Italic"), 15) ||
    $.NSFont.fontWithNameSize($("Times New Roman Italic"), 15) ||
    $.NSFont.italicSystemFontOfSize(15);

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
  helperText.setStringValue($("Selected text and #Mac-Reading are added automatically."));
  helperText.setBezeled(false);
  helperText.setDrawsBackground(false);
  helperText.setEditable(false);
  helperText.setSelectable(false);
  helperText.setFont($.NSFont.systemFontOfSize(11));
  helperText.setTextColor($.NSColor.secondaryLabelColor);
  cv.addSubview(helperText);
  y += helperH + 10;

  // -- Provider picker --
  const providerPicker = $.NSPopUpButton.alloc.initWithFramePullsDown(
    $.NSMakeRect(pad, y, innerW, providerPickerH),
    false
  );
  availableProviderIds.forEach(function(providerId) {
    providerPicker.addItemWithTitle($(providerNames[providerId] || providerId));
  });

  const activeProviderIndex = Math.max(0, availableProviderIds.indexOf(activeProviderId));
  providerPicker.selectItemAtIndex(activeProviderIndex);
  providerPicker.setEnabled(availableProviderIds.length > 1);
  cv.addSubview(providerPicker);

  const providerLabel = $.NSTextField.alloc.initWithFrame(
    $.NSMakeRect(pad, y + providerPickerH + 6, innerW, providerLabelH)
  );
  providerLabel.setStringValue($(availableProviderIds.length > 1 ? "Send note to" : "Configured note provider"));
  providerLabel.setBezeled(false);
  providerLabel.setDrawsBackground(false);
  providerLabel.setEditable(false);
  providerLabel.setSelectable(false);
  providerLabel.setFont($.NSFont.systemFontOfSize(12));
  providerLabel.setTextColor($.NSColor.secondaryLabelColor);
  cv.addSubview(providerLabel);
  y += providerBlockH + 10;

  // -- X toggle --
  const postToXCheckbox = $.NSButton.alloc.initWithFrame(
    $.NSMakeRect(pad - 2, y, innerW, checkboxH)
  );
  postToXCheckbox.setButtonType($.NSSwitchButton);
  postToXCheckbox.setTitle($("Also post to X"));
  postToXCheckbox.setFont($.NSFont.systemFontOfSize(13));
  postToXCheckbox.setState($.NSControlStateValueOff);
  cv.addSubview(postToXCheckbox);
  y += checkboxH + sectionGap;

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
  subtitle.setStringValue($(slogan));
  subtitle.setBezeled(false);
  subtitle.setDrawsBackground(false);
  subtitle.setEditable(false);
  subtitle.setSelectable(false);
  subtitle.setFont(sloganFont);
  subtitle.setTextColor($.NSColor.secondaryLabelColor);
  subtitle.setLineBreakMode($.NSLineBreakByWordWrapping);
  cv.addSubview(subtitle);

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

  const selectedProviderName = ObjC.unwrap(providerPicker.titleOfSelectedItem) || "";
  const selectedProviderId = availableProviderIds.find(function(providerId) {
    return (providerNames[providerId] || providerId) === selectedProviderName;
  }) || activeProviderId;

  return JSON.stringify({
    note: ObjC.unwrap(textView.string),
    postToX: Number(postToXCheckbox.state) === 1,
    providerId: selectedProviderId
  });
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
  show_feedback "error" "No selected text received."
  log_line "Empty selection input."
  exit 0
fi

if [[ "$TEST_MODE" != "smoke" ]]; then
  if ! load_provider_config; then
    show_feedback "error" "Please configure a note provider first." "Use ./mac/scripts/configure-flomo-webhook.sh for Flomo or ./mac/scripts/configure-getbiji.sh for Get笔记."
    log_line "Missing or invalid provider config."
    exit 1
  fi
else
  log_line "Smoke test mode enabled."
  ACTIVE_PROVIDER_ID="flomo"
  AVAILABLE_PROVIDER_IDS=("flomo")
  PROVIDER_NAME="note provider"
fi

PREVIEW_TEXT="$(printf "%s" "$SELECTED_TEXT" | head -c 500)"
FRONT_APP_NAME="$(get_front_app_name)"
SOURCE_NAME=""
if [[ "$FRONT_APP_NAME" == "Preview" ]]; then
  SOURCE_NAME="$(get_preview_doc_name)"
fi
if [[ -z "${SOURCE_NAME//[[:space:]]/}" ]]; then
  SOURCE_NAME="$FRONT_APP_NAME"
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

AVAILABLE_PROVIDER_IDS_CSV="$(IFS=,; printf '%s' "${AVAILABLE_PROVIDER_IDS[*]}")"
COMPOSER_RESULT="$(prompt_note_multiline "$PREVIEW_TEXT" "$PROMPT_MODE" "$ACTIVE_PROVIDER_ID" "$AVAILABLE_PROVIDER_IDS_CSV")"

if [[ "$COMPOSER_RESULT" == "__SCREEN_NOTES_CANCELLED__" ]]; then
  log_line "User cancelled note dialog."
  exit 0
fi

if [[ "$COMPOSER_RESULT" == "__SCREEN_NOTES_SMOKE_TEST_OK__" ]]; then
  log_line "Smoke test completed successfully."
  exit 0
fi

if [[ "$COMPOSER_RESULT" == "__SCREEN_NOTES_SAVE_PATH_OK__" ]]; then
  log_line "Save-path test completed successfully."
  exit 0
fi

NOTE_TEXT="$(extract_composer_note "$COMPOSER_RESULT")"
POST_TO_X="$(extract_composer_post_flag "$COMPOSER_RESULT")"
SELECTED_PROVIDER_ID="$(extract_composer_provider_id "$COMPOSER_RESULT")"

if [[ -z "${SELECTED_PROVIDER_ID//[[:space:]]/}" ]]; then
  SELECTED_PROVIDER_ID="$ACTIVE_PROVIDER_ID"
fi

if ! apply_provider_selection "$SELECTED_PROVIDER_ID"; then
  show_feedback "error" "The selected provider is not configured." "Configure it first, then try saving again."
  log_line "Selected provider missing config: $SELECTED_PROVIDER_ID"
  exit 1
fi

ACTIVE_PROVIDER_ID="$SELECTED_PROVIDER_ID"
if [[ "$TEST_MODE" != "smoke" ]]; then
  write_provider_config_file "$ACTIVE_PROVIDER_ID"
fi

CONTENT="$(build_note_content "$SELECTED_TEXT" "$NOTE_TEXT" "$SOURCE_NAME")"

RESP_FILE="$(mktemp "${TMPDIR:-/tmp}/screen-notes-response.XXXXXX.txt")"
HTTP_CODE="$(send_note_to_provider "$CONTENT" "" "$RESP_FILE")"

if [[ ! "$HTTP_CODE" =~ ^2[0-9][0-9]$ ]]; then
  log_line "$PROVIDER_NAME request failed. HTTP=$HTTP_CODE Body=$(cat "$RESP_FILE")"
  ERROR_DETAIL="HTTP status: $HTTP_CODE"
  if [[ -s "$RESP_FILE" ]]; then
    ERROR_BODY="$(tr '\n' ' ' < "$RESP_FILE" | head -c 220)"
    ERROR_DETAIL="$ERROR_DETAIL

$ERROR_BODY"
  fi
  rm -f "$RESP_FILE"
  show_feedback "error" "Failed to save to $PROVIDER_NAME." "$ERROR_DETAIL"
  exit 1
fi

rm -f "$RESP_FILE"
log_line "Completed successfully. Provider=$PROVIDER_ID"

if [[ "$POST_TO_X" == "1" ]]; then
  X_POST_TEXT="$(build_x_post_content "$SELECTED_TEXT" "$NOTE_TEXT")"
  log_line "Also post to X selected. Launching compose window."

  if open_x_compose "$X_POST_TEXT"; then
    log_line "X compose opened successfully."
    notify_banner "Saved to $PROVIDER_NAME and opened X draft."
    exit 0
  fi

  log_line "X compose failed: $X_POST_ERROR"
  notify_banner "Saved to $PROVIDER_NAME. X draft failed to open."
  exit 0
fi

notify_banner "Saved to $PROVIDER_NAME."
