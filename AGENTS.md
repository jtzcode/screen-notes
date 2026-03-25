# AGENTS Guide

This file is for AI agents and automation tools working in this repo.

## Scope

- Main product: Chrome extension for quick notes from selected web text.
- macOS companion: `mac/` folder provides Preview Quick Action integration and Flomo sending.

## Key Paths

- `manifest.json`: extension entry and permissions.
- `background.js`: context menu + orchestration.
- `content.js`: in-page note bubble UI.
- `note-service.js`: provider-agnostic save flow.
- `providers.js`: note provider registry (Flomo currently).
- `storage.js`: extension settings/history storage.
- `mac/scripts/take-notes-service.sh`: runtime script used by macOS Quick Action.
- `mac/scripts/install-quick-action.sh`: installs/refreshes `Take Notes` workflow.
- `mac/scripts/uninstall-quick-action.sh`: removes workflow and refreshes cache.
- `mac/scripts/configure-flomo-webhook.sh`: writes webhook config.
- `mac/skills/baoyu-post-to-x/`: bundled X posting skill used by mac runtime.
- `mac/README.md`: mac setup + troubleshooting.

## macOS Runtime Notes

- Automator can fail with `Operation not permitted` if running scripts from protected folders like `Documents`.
- Installer copies runtime script to:
  - `~/Library/Application Support/ScreenNotesMac/take-notes-service.sh`
- Installed workflow should run:
  - `/bin/bash "/Users/<user>/Library/Application Support/ScreenNotesMac/take-notes-service.sh"`

## Validation Commands

- Extension syntax smoke check:
  - `node --check background.js`
  - `node --check content.js`
  - `node --check note-service.js`
- mac scripts syntax check:
  - `bash -n mac/scripts/install-quick-action.sh`
  - `bash -n mac/scripts/uninstall-quick-action.sh`
  - `bash -n mac/scripts/configure-flomo-webhook.sh`
  - `bash -n mac/scripts/take-notes-service.sh`

## mac Workflow Smoke Test

1. Configure webhook:
   - `./mac/scripts/configure-flomo-webhook.sh "<flomo-webhook-url>"`
2. Install service:
   - `./mac/scripts/install-quick-action.sh`
3. CLI test of workflow:
   - `automator -i "test text" "$HOME/Library/Services/Take Notes.workflow"`
4. Check logs:
   - `tail -n 120 "$HOME/Library/Logs/ScreenNotesMac/service.log"`

## Editing Guidance

- Keep Chrome extension behavior backward-compatible.
- For provider changes, update `providers.js` and any UI/config paths.
- For mac service reliability, prefer script-only flow and explicit logs.
- Do not commit `.build/` outputs.
