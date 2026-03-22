# Quick Notes — Chrome Extension

Highlight text on any webpage, jot down your thoughts, and save to your favorite note app — all without leaving the page.

![Quick Note floating bubble](screenshots/intro.png)

## Features

- **Context menu integration** — Select text, right-click → "Take quick notes"
- **Floating bubble** — A note-taking popup appears right next to your selection (no new windows)
- **Save to Flomo** — Notes are sent to [Flomo](https://flomoapp.com) via webhook API
- **Notes history** — Click the extension icon to browse your latest 50 notes
- **Provider abstraction** — Designed to support multiple note apps (only Flomo for now)
- **Shadow DOM isolation** — The bubble UI won't interfere with any website's styles
- **Fallback note window** — If inline injection is unavailable, the note flow opens in an extension window instead of failing silently

## Installation

1. Clone or download this repository
2. Open `chrome://extensions` in Chrome
3. Enable **Developer mode** (toggle in the top right)
4. Click **Load unpacked** and select the project folder
5. Click the extension icon → ⚙️ to open settings
6. Select **Flomo** as your provider and paste your webhook URL

### Getting your Flomo webhook URL

Go to [Flomo](https://flomoapp.com) → Settings → API → copy the webhook URL (starts with `https://flomoapp.com/iwh/...`).

## Usage

1. Select any text on a webpage
2. Right-click → **Take quick notes**
3. A floating bubble appears near the selection — type your thoughts
4. Click **Save** — the note is sent to Flomo and stored locally
5. Click the extension icon anytime to see your recent notes

### Note format in Flomo

```
<selected text>

<your note>

<page URL>

#Web-Reading
```

## Project Structure

```
├── manifest.json      # Chrome extension manifest (V3)
├── background.js      # Service worker: context menu, injection, fallback orchestration
├── content.js         # Floating bubble UI (injected into pages)
├── providers.js       # Provider registry and provider implementations
├── storage.js         # Shared storage boundary for settings, history, and pending state
├── note-service.js    # Shared note save workflow used by background and fallback UI
├── popup.html/js      # Extension icon popup: recent notes list
├── options.html/js    # Settings page: provider selection & config
├── note.html/js       # Fallback note window when page injection is unavailable
├── styles.css         # Shared styles for popup, options, and fallback window
└── icons/             # Extension icons (16, 48, 128px)
```

## macOS Preview Workflow

This repo also includes a macOS companion flow under `mac/` for Preview PDF reading:

- Trigger via macOS Quick Action/Service from selected text in Preview
- Pop native note window
- Save directly to Flomo webhook
- Install with `./mac/scripts/install-quick-action.sh`

See [`mac/README.md`](mac/README.md) for setup.
See [`docs/mac-engineering-overview.md`](docs/mac-engineering-overview.md) for implementation and debugging details.

## Adding a new provider

Add an entry to `providers.js`:

```js
NoteProviders.notion = {
  id: "notion",
  name: "Notion",
  configFields: [
    { key: "apiKey", label: "API Key", type: "text", placeholder: "secret_...", hint: "..." }
  ],
  validate(cfg) { /* return { valid, error? } */ },
  buildContent(selectedText, userNote, pageUrl) { /* return string */ },
  async send(cfg, content) { /* POST to API */ }
};
```

The options page and save logic will pick it up automatically. If the provider uses a different API host, update `host_permissions` in [manifest.json](manifest.json) as well.

## Permissions

| Permission | Why |
|---|---|
| `contextMenus` | "Take quick notes" in the right-click menu |
| `activeTab` | Access the current tab to inject the bubble |
| `scripting` | Inject `content.js` into pages |
| `storage` | Store settings and note history |
| `host_permissions: flomoapp.com` | Send notes to the Flomo API |

## License

See [LICENSE](LICENSE).
