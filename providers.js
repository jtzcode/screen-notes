/**
 * Note provider registry.
 *
 * Each provider implements:
 *   id            — unique key (stored in settings)
 *   name          — display name
 *   configFields  — array of { key, label, type, placeholder, hint }
 *   validate(cfg) — returns { valid, error? }
 *   buildPayload(noteInput, cfg) — returns provider-specific payload
 *   send(cfg, payload) — returns Promise<void>
 */

const NoteProviders = {};

function buildWebReadingContent(noteInput) {
  const parts = [noteInput.selectedText];
  parts.push("——————————");
  if (noteInput.userNote) parts.push(noteInput.userNote);
  parts.push(noteInput.pageUrl);
  parts.push("#Web-Reading");
  return parts.join("\n\n");
}

function buildNoteTitle(noteInput) {
  const candidates = [noteInput.pageTitle, noteInput.userNote, noteInput.selectedText];

  for (const candidate of candidates) {
    const singleLine = String(candidate || "")
      .replace(/\s+/g, " ")
      .trim();
    if (singleLine) {
      return singleLine.slice(0, 80);
    }
  }

  return "Web Note";
}

function parseTagList(rawValue) {
  return String(rawValue || "")
    .split(",")
    .map((tag) => tag.trim())
    .filter(Boolean);
}

async function ensureOkResponse(providerName, resp) {
  if (resp.ok) return;

  const responseText = (await resp.text()).trim();
  const suffix = responseText ? ": " + responseText.slice(0, 300) : "";
  throw new Error(providerName + " API returned " + resp.status + suffix);
}

// ——— Flomo ———
NoteProviders.flomo = {
  id: "flomo",
  name: "Flomo",

  configFields: [
    {
      key: "webhookUrl",
      label: "Flomo Webhook URL",
      type: "url",
      placeholder: "https://flomoapp.com/iwh/xxxxx/yyyyy/",
      hint: "Find your webhook URL in Flomo → Settings → API."
    }
  ],

  validate(cfg) {
    const url = (cfg.webhookUrl || "").trim();
    if (!url) return { valid: false, error: "Please enter a webhook URL." };
    if (!url.startsWith("https://flomoapp.com/iwh/")) {
      return { valid: false, error: "URL must start with https://flomoapp.com/iwh/" };
    }
    return { valid: true };
  },

  buildPayload(noteInput) {
    return buildWebReadingContent(noteInput);
  },

  async send(cfg, content) {
    const resp = await fetch(cfg.webhookUrl.trim(), {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ content })
    });
    await ensureOkResponse("Flomo", resp);
  }
};

// ——— Get 笔记 ———
NoteProviders.getbiji = {
  id: "getbiji",
  name: "Get 笔记",

  configFields: [
    {
      key: "clientId",
      label: "Get 笔记 Client ID",
      type: "text",
      placeholder: "cli_xxx",
      hint: "Configured in extension settings and sent as the X-Client-ID header."
    },
    {
      key: "apiKey",
      label: "Get 笔记 API Key",
      type: "password",
      placeholder: "gk_live_xxx",
      hint: "Configured at runtime in extension settings and sent as the Authorization header."
    },
    {
      key: "defaultTags",
      label: "Default Tags",
      type: "text",
      placeholder: "工作, 重要",
      hint: "Optional. Comma-separated tags added to each saved note."
    }
  ],

  validate(cfg) {
    const clientId = (cfg.clientId || "").trim();
    const apiKey = (cfg.apiKey || "").trim();

    if (!clientId) {
      return { valid: false, error: "Please enter your Get 笔记 Client ID." };
    }

    if (!apiKey) {
      return { valid: false, error: "Please enter your Get 笔记 API Key." };
    }

    return { valid: true };
  },

  buildPayload(noteInput, cfg) {
    const payload = {
      title: buildNoteTitle(noteInput),
      content: buildWebReadingContent(noteInput)
    };
    const tags = parseTagList(cfg.defaultTags);

    if (tags.length) {
      payload.tags = tags;
    }

    return payload;
  },

  async send(cfg, payload) {
    const resp = await fetch("https://openapi.biji.com/open/api/v1/resource/note/save", {
      method: "POST",
      headers: {
        "X-Client-ID": cfg.clientId.trim(),
        "Authorization": cfg.apiKey.trim(),
        "Content-Type": "application/json"
      },
      body: JSON.stringify(payload)
    });

    await ensureOkResponse("Get 笔记", resp);
  }
};

// ——— Helpers ———

/** Returns an array of all registered providers. */
function getProviderList() {
  return Object.values(NoteProviders);
}

/** Returns a provider by id, or undefined. */
function getProvider(id) {
  return NoteProviders[id];
}

/** Default provider id when none is configured yet. */
const DEFAULT_PROVIDER = "flomo";
