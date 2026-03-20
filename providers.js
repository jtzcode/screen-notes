/**
 * Note provider registry.
 *
 * Each provider implements:
 *   id            — unique key (stored in settings)
 *   name          — display name
 *   configFields  — array of { key, label, type, placeholder, hint }
 *   validate(cfg) — returns { valid, error? }
 *   buildContent(selectedText, userNote, pageUrl) — returns string
 *   send(cfg, content) — returns Promise<void>
 */

const NoteProviders = {};

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

  buildContent(selectedText, userNote, pageUrl) {
    const parts = [selectedText];
    parts.push("——————————");
    if (userNote) parts.push(userNote);
    parts.push(pageUrl);
    parts.push("#Web-Reading");
    return parts.join("\n\n");
  },

  async send(cfg, content) {
    const resp = await fetch(cfg.webhookUrl.trim(), {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ content })
    });
    if (!resp.ok) {
      throw new Error(`Flomo API returned ${resp.status}`);
    }
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
