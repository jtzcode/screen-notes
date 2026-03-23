# ADR-001: Force Take Notes Dialog to Foreground

**Date:** 2026-03-23
**Status:** Accepted

## Context

When the Take Notes Quick Action is triggered from Preview (or any app), the note
composer dialog sometimes appears behind the active window. The user must click the
dialog or the Dock icon before they can interact with it, adding unnecessary friction.

This happens because `activateIgnoringOtherApps` alone is not reliable when the
process launches from an Automator service context on modern macOS. The OS
deprioritizes activation requests from background-spawned processes.

## Decision

Set the alert window level to **floating** (`NSFloatingWindowLevel`) and call
`makeKeyAndOrderFront` before running the modal, in both code paths:

- **Shell script (JXA)** — `take-notes-service.sh`: added `setLevel($.NSFloatingWindowLevel)`
  and `makeKeyAndOrderFront(null)` on the alert window. Also added
  `NSApplicationActivateAllWindows` to the activation options.
- **Swift binary** — `main.swift`: added `alert.window.level = .floating` and
  `alert.window.makeKeyAndOrderFront(nil)` in both `showAlert` and `showComposer`.

## Consequences

- The note dialog now reliably appears in front of all windows with keyboard focus.
- The floating level is only set on the modal alert, not on the app globally, so it
  does not affect other system behavior.
- Activation flags remain as defense-in-depth; the floating window level is the
  primary mechanism.
