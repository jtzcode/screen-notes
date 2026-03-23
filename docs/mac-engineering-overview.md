# macOS Tool Engineering Overview

This note explains how the macOS `Take Notes` tool works, using beginner-friendly language.

## 1) High-level architecture

The mac tool is not a Preview plugin. It uses macOS Services:

1. You select text in Preview.
2. You click the Quick Action `Take Notes`.
3. macOS runs a workflow at `~/Library/Services/Take Notes.workflow`.
4. The workflow runs a shell script.
5. The script opens a note dialog and sends content to Flomo.

Key files:

- `mac/scripts/install-quick-action.sh`: installs and refreshes the workflow.
- `mac/scripts/take-notes-service.sh`: runtime behavior (UI + API call).
- `mac/scripts/configure-flomo-webhook.sh`: saves webhook config.
- `~/Library/Application Support/ScreenNotesMac/config.json`: saved Flomo webhook.
- `~/Library/Logs/ScreenNotesMac/service.log`: runtime logs.

## 2) Why this design

- Preview has no stable public API for custom right-click menu injection.
- Quick Action/Service is the supported macOS path for selected text.
- Shell + AppleScript/JXA is lightweight and easy to debug.

## 3) Request flow details

When `Take Notes` runs:

1. Read selected text from stdin.
2. If stdin is empty, fallback to clipboard (`pbpaste`).
3. Read webhook URL from config JSON.
4. Ask Preview for current document name (`name of front document`).
5. Show a multi-line note editor dialog (JXA + AppKit).
6. Build final note content:
   - selected text
   - separator
   - your note
   - source document name
   - tag `#Mac-Reading`
7. POST JSON to Flomo webhook.
8. Write logs + show success/failure notification.

## 4) Important macOS concepts

- **Quick Action / Service**: system automation entry shown in context menu.
- **Workflow bundle (`.workflow`)**: plist-based package containing actions.
- **Automator runner**: process that executes workflow actions.
- **TCC permissions**: macOS privacy/security system.
- **Protected folders**: paths like `Documents` can be blocked for automation.

## 5) Why runtime script is in Application Support

We copy the runtime script to:

- `~/Library/Application Support/ScreenNotesMac/take-notes-service.sh`

instead of running directly from repo path (often in `Documents`), because Automator can fail with:

- `Operation not permitted`

This avoids common permission failures.

## 6) Debugging checklist

### A) Check logs first

```bash
tail -n 120 "$HOME/Library/Logs/ScreenNotesMac/service.log"
```

### B) Reinstall workflow cleanly

```bash
./mac/scripts/uninstall-quick-action.sh
./mac/scripts/install-quick-action.sh
```

### C) CLI smoke test (without Preview click)

```bash
automator -i "test text" "$HOME/Library/Services/Take Notes.workflow"
```

For a non-interactive validation of the runtime script that still exercises the dialog construction path without posting to Flomo:

```bash
SCREEN_NOTES_TEST_MODE=smoke "$HOME/Library/Application Support/ScreenNotesMac/take-notes-service.sh" <<< "test text"
```

### D) Verify workflow command path

```bash
plutil -extract actions.0.action.ActionParameters.COMMAND_STRING raw -o - "$HOME/Library/Services/Take Notes.workflow/Contents/Resources/document.wflow"
```

Expected path should point to `Application Support`, not `Documents`.

### E) If Quick Action doesn’t appear

1. System Settings → Keyboard → Keyboard Shortcuts → Services.
2. Enable `Take Notes`.
3. Reopen Preview.

## 7) Extension points

- Add new note providers: keep `take-notes-service.sh` content building separate from send logic.
- Add metadata (page number, timestamp): append to content before POST.
- Replace dialog UI: keep same input/output contract so workflow remains stable.
