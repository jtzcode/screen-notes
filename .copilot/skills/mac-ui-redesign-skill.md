# mac-ui-redesign-skill

Use this file as the design brief for the `screen-notes` macOS tool UI.

Paste the external guidance you want me to follow below, then tell me to redesign again using this skill file.

## Source material

Paste the article or skill content here.

---

## Extracted principles

After pasting source material, optionally summarize the principles you want emphasized.

- Clear visual hierarchy
- Strong primary action
- Calm spacing and typography
- Reduced label clutter
- Better alignment and rhythm
- Native macOS feel

## Project-specific constraints

- Target: `screen-notes` macOS Quick Action UI in `mac/scripts/take-notes-service.sh`
- Keep the Preview → Quick Action → note dialog → Flomo flow unchanged
- Keep source filename hidden in the dialog UI
- Keep selected text visible as context
- Preserve smoke-test support
- Avoid brittle JXA/AppKit calls that are not supported in this environment
- Prefer layout polish, alignment, spacing, and visual hierarchy improvements

## Current UI issues to revisit

- Alignment still feels off in parts of the panel
- Foreground behavior is still unresolved and should not be assumed fixed
- The quotation-mark treatment is good and can be kept or refined

## Next redesign request

When ready, tell me something like:

`Use .copilot/skills/mac-ui-redesign-skill.md and redesign the mac tool UI again.`
