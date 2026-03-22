# Screen Notes for macOS (Preview + Flomo)

This directory adds a macOS-native note flow for PDF reading in Preview:

1. Select text in Preview.
2. Trigger a Quick Action named `Take Notes`.
3. A multi-line macOS note dialog appears with the selected text preview.
4. Save sends the note to Flomo webhook API.

## Feasibility and limits

- You cannot inject a fully custom top-level item directly into Preview's private highlight menu.
- You can reliably integrate through macOS **Quick Actions / Services**, which Preview exposes for selected text.
- The user experience is close to what you want, and works across many macOS apps.

## What's included

- `scripts/configure-flomo-webhook.sh` — one-time webhook configuration.
- `scripts/take-notes-service.sh` — workflow runner: prompt note dialog + post to Flomo.
- `scripts/install-quick-action.sh` — installs a `Take Notes` Quick Action into `~/Library/Services`.

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

### 3) Verify in Preview

1. Reopen Preview.
2. Select text in a PDF.
3. Right-click and find **Take Notes** under **Quick Actions** or **Services**.
4. On first run, wait a few seconds because the helper may build once.

If the item is missing:

1. Open **System Settings** → **Keyboard** → **Keyboard Shortcuts** → **Services**.
2. Enable **Take Notes**.
3. Reopen Preview and try again.

If clicking does nothing:

1. Check `~/Library/Logs/ScreenNotesMac/service.log` for build/runtime errors.
2. Rerun installer:

```bash
./mac/scripts/install-quick-action.sh
```

If you see `Operation not permitted` pointing to a script under `Documents`, run install again to refresh to the `Application Support` runtime path.

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

<preview document name>

#Mac-Reading
```
