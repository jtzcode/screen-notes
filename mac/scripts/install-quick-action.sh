#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  cat <<'EOF'
Usage:
  ./mac/scripts/install-quick-action.sh [--dry-run]

Options:
  --dry-run   Write the workflow into /tmp instead of ~/Library/Services.
EOF
  exit 0
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
SERVICE_NAME="Take Notes"
SERVICE_SCRIPT="$ROOT_DIR/mac/scripts/take-notes-service.sh"
BUNDLE_ID="com.screennotes.mac.takenotes.v2"

if [[ ! -f "$SERVICE_SCRIPT" ]]; then
  echo "Missing service script: $SERVICE_SCRIPT" >&2
  exit 1
fi

chmod +x "$SERVICE_SCRIPT"

if [[ "${1:-}" == "--dry-run" ]]; then
  SERVICES_DIR="/tmp/ScreenNotesServices"
  RUNTIME_DIR="/tmp/ScreenNotesRuntime"
else
  SERVICES_DIR="${SCREEN_NOTES_SERVICES_DIR:-$HOME/Library/Services}"
  RUNTIME_DIR="$HOME/Library/Application Support/ScreenNotesMac"
fi

WORKFLOW_DIR="$SERVICES_DIR/$SERVICE_NAME.workflow"
CONTENTS_DIR="$WORKFLOW_DIR/Contents"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
RUNTIME_SCRIPT="$RUNTIME_DIR/take-notes-service.sh"

xml_escape() {
  local value="$1"
  value="${value//&/&amp;}"
  value="${value//</&lt;}"
  value="${value//>/&gt;}"
  value="${value//\"/&quot;}"
  value="${value//\'/&apos;}"
  printf '%s' "$value"
}

mkdir -p "$RUNTIME_DIR"
cp "$SERVICE_SCRIPT" "$RUNTIME_SCRIPT"
chmod +x "$RUNTIME_SCRIPT"
xattr -d com.apple.quarantine "$RUNTIME_SCRIPT" >/dev/null 2>&1 || true

COMMAND_STRING_ESCAPED="$(xml_escape "/bin/bash \"$RUNTIME_SCRIPT\"")"
ACTION_UUID="$(uuidgen)"
INPUT_UUID="$(uuidgen)"
OUTPUT_UUID="$(uuidgen)"

rm -rf "$WORKFLOW_DIR"
mkdir -p "$RESOURCES_DIR"

cat >"$CONTENTS_DIR/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en_US</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleName</key>
  <string>$SERVICE_NAME</string>
  <key>CFBundleShortVersionString</key>
  <string>1.0</string>
  <key>NSServices</key>
  <array>
    <dict>
      <key>NSMenuItem</key>
      <dict>
        <key>default</key>
        <string>$SERVICE_NAME</string>
      </dict>
      <key>NSMessage</key>
      <string>runWorkflowAsService</string>
      <key>NSSendTypes</key>
      <array>
        <string>public.utf8-plain-text</string>
      </array>
    </dict>
  </array>
</dict>
</plist>
EOF

cat >"$CONTENTS_DIR/version.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>BuildVersion</key>
  <string>1</string>
  <key>CFBundleShortVersionString</key>
  <string>1.0</string>
  <key>ProjectName</key>
  <string>Automator</string>
  <key>SourceVersion</key>
  <string>1</string>
</dict>
</plist>
EOF

cat >"$RESOURCES_DIR/document.wflow" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>actions</key>
  <array>
    <dict>
      <key>action</key>
      <dict>
        <key>ActionBundlePath</key>
        <string>/System/Library/Automator/Run Shell Script.action</string>
        <key>ActionName</key>
        <string>Run Shell Script</string>
        <key>ActionParameters</key>
        <dict>
          <key>CheckedForUserDefaultShell</key>
          <true/>
          <key>COMMAND_STRING</key>
          <string>$COMMAND_STRING_ESCAPED</string>
          <key>inputMethod</key>
          <integer>0</integer>
          <key>shell</key>
          <string>/bin/bash</string>
          <key>source</key>
          <string></string>
        </dict>
        <key>AMAccepts</key>
        <dict>
          <key>Container</key>
          <string>List</string>
          <key>Optional</key>
          <true/>
          <key>Types</key>
          <array>
            <string>com.apple.cocoa.string</string>
          </array>
        </dict>
        <key>AMActionVersion</key>
        <string>2.0.3</string>
        <key>AMApplication</key>
        <array>
          <string>Automator</string>
        </array>
        <key>AMParameterProperties</key>
        <dict>
          <key>CheckedForUserDefaultShell</key>
          <dict/>
          <key>COMMAND_STRING</key>
          <dict/>
          <key>inputMethod</key>
          <dict/>
          <key>shell</key>
          <dict/>
          <key>source</key>
          <dict/>
        </dict>
        <key>AMProvides</key>
        <dict>
          <key>Container</key>
          <string>List</string>
          <key>Types</key>
          <array>
            <string>com.apple.cocoa.string</string>
          </array>
        </dict>
        <key>BundleIdentifier</key>
        <string>com.apple.RunShellScript</string>
        <key>CanShowSelectedItemsWhenRun</key>
        <false/>
        <key>CanShowWhenRun</key>
        <true/>
        <key>Category</key>
        <array>
          <string>AMCategoryUtilities</string>
        </array>
        <key>CFBundleVersion</key>
        <string>2.0.3</string>
        <key>Class Name</key>
        <string>RunShellScriptAction</string>
        <key>InputUUID</key>
        <string>$INPUT_UUID</string>
        <key>OutputUUID</key>
        <string>$OUTPUT_UUID</string>
        <key>UUID</key>
        <string>$ACTION_UUID</string>
        <key>UnlocalizedApplications</key>
        <array>
          <string>Automator</string>
        </array>
      </dict>
      <key>isViewVisible</key>
      <true/>
    </dict>
  </array>
  <key>AMApplicationBuild</key>
  <string>346</string>
  <key>AMApplicationVersion</key>
  <string>2.3</string>
  <key>AMDocumentVersion</key>
  <string>2</string>
  <key>connectors</key>
  <dict/>
  <key>workflowMetaData</key>
  <dict>
    <key>serviceApplicationBundleID</key>
    <string></string>
    <key>serviceApplicationPath</key>
    <string></string>
    <key>serviceInputTypeIdentifier</key>
    <string>com.apple.Automator.text</string>
    <key>serviceOutputTypeIdentifier</key>
    <string>com.apple.Automator.nothing</string>
    <key>serviceProcessesInput</key>
    <integer>1</integer>
    <key>workflowTypeIdentifier</key>
    <string>com.apple.Automator.servicesMenu</string>
  </dict>
</dict>
</plist>
EOF

plutil -lint "$CONTENTS_DIR/Info.plist" >/dev/null
plutil -lint "$CONTENTS_DIR/version.plist" >/dev/null
plutil -lint "$RESOURCES_DIR/document.wflow" >/dev/null

if [[ "${1:-}" != "--dry-run" ]]; then
  /System/Library/CoreServices/pbs -flush >/dev/null 2>&1 || true
  /System/Library/CoreServices/pbs -update >/dev/null 2>&1 || true
fi

echo "Installed Quick Action: $WORKFLOW_DIR"
echo "Action script: $RUNTIME_SCRIPT"
if [[ "${1:-}" == "--dry-run" ]]; then
  echo "Dry run mode: workflow written to /tmp only."
else
  echo "If it does not appear immediately in Preview, reopen Preview."
fi
