# Screen Notes for macOS (Quick Actions + Flomo)

This directory adds a macOS-native note flow for selected text in apps that expose macOS Quick Actions / Services:

1. Select text in Preview, a browser, a reader app, or another compatible macOS app.
2. Trigger a Quick Action named `Take Notes`.
3. A multi-line macOS note dialog appears with the selected text preview.
4. Save sends the note to Flomo webhook API.
5. After save, the tool shows an in-app success or error dialog instead of relying on Notification Center banners.

## Feasibility and limits

- You cannot inject a fully custom top-level item directly into an app's private right-click menu.
- You can reliably integrate through macOS **Quick Actions / Services** in apps that expose selected text to the Services system.
- In practice, many apps keep custom actions under **Quick Actions** or **Services** rather than the first context-menu level.
- The fastest supported way to trigger `Take Notes` is to assign it a keyboard shortcut in **System Settings** → **Keyboard** → **Keyboard Shortcuts** → **Services**.
- The user experience is close to what you want, and works across many macOS apps.

## What's included

- `scripts/configure-flomo-webhook.sh` — one-time webhook configuration.
- `scripts/take-notes-service.sh` — workflow runner: prompt note dialog + post to Flomo.
- `scripts/install-quick-action.sh` — installs a `Take Notes` Quick Action into `~/Library/Services`.
- `../docs/mac-engineering-overview.md` — implementation details and debugging guide.

## One-time setup

### 1) Configure your Flomo webhook

From project root:

```bash
./mac/scripts/configure-flomo-webhook.sh "https://flomoapp.com/iwh/xxxxx/yyyyy/"
```

It stores config at:

`~/Library/Application Support/ScreenNotesMac/config.json`

### 2) Install the Quick Action automatically

From project root:

```bash
./mac/scripts/install-quick-action.sh
```

This creates:

`~/Library/Services/Take Notes.workflow`

It also installs runtime script to:

`~/Library/Application Support/ScreenNotesMac/take-notes-service.sh`

To remove and reset it:

```bash
./mac/scripts/uninstall-quick-action.sh
```

### 3) Verify in an app with selected text support

1. Reopen Preview, a browser, or another compatible app.
2. Select some text.
3. Right-click and find **Take Notes** under **Quick Actions** or **Services**.
4. On first run, wait a few seconds because the helper may build once.
5. Optional: assign a keyboard shortcut to **Take Notes** in **System Settings** → **Keyboard** → **Keyboard Shortcuts** → **Services** for a faster flow than navigating the context menu each time.

If the item is missing:

1. Open **System Settings** → **Keyboard** → **Keyboard Shortcuts** → **Services**.
2. Enable **Take Notes**.
3. Reopen the source app and try again.

If clicking does nothing:

1. Check `~/Library/Logs/ScreenNotesMac/service.log` for build/runtime errors.
2. Rerun installer:

```bash
./mac/scripts/install-quick-action.sh
```

If you see `Operation not permitted` pointing to a script under `Documents`, run install again to refresh to the `Application Support` runtime path.

For a non-interactive runtime smoke test that exercises the dialog construction path without opening a manual save flow or sending a test note to Flomo:

```bash
SCREEN_NOTES_TEST_MODE=smoke "$HOME/Library/Application Support/ScreenNotesMac/take-notes-service.sh" <<< "test text"
```

## Manual fallback (Automator)

If you prefer manual setup:

1. Open **Automator**.
2. Create a new **Quick Action**.
3. Set:
   - "Workflow receives current": `text`
   - "in": `any application` (or `Preview`)
4. Add action: **Run Shell Script**.
5. Set:
   - "Shell": `/bin/bash`
   - "Pass input": `to stdin`
6. Use script body:

```bash
/Users/panpan/Documents/Projects/screen-notes/mac/scripts/take-notes-service.sh
```

7. Save as: `Take Notes`.

## Note format sent to Flomo

```text
<selected text>

——————————

<your note>

<preview document name or source app name>

#Mac-Reading
```
