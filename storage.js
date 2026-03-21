const QUICK_NOTES_STORAGE_KEYS = {
  provider: "provider",
  providerConfig: "providerConfig",
  legacyFlomoWebhookUrl: "flomoWebhookUrl",
  notes: "notes",
  fallbackPendingNote: "pendingNote"
};

const QUICK_NOTES_DEFAULT_PROVIDER_ID = "flomo";
const QUICK_NOTES_MAX_NOTES = 50;

const QuickNotesStorage = {
  async getSettings() {
    const data = await chrome.storage.sync.get([
      QUICK_NOTES_STORAGE_KEYS.provider,
      QUICK_NOTES_STORAGE_KEYS.providerConfig,
      QUICK_NOTES_STORAGE_KEYS.legacyFlomoWebhookUrl
    ]);

    let providerId = data[QUICK_NOTES_STORAGE_KEYS.provider] || this.getDefaultProviderId();
    let providerConfig = data[QUICK_NOTES_STORAGE_KEYS.providerConfig] || {};

    if (!data[QUICK_NOTES_STORAGE_KEYS.provider] && data[QUICK_NOTES_STORAGE_KEYS.legacyFlomoWebhookUrl]) {
      providerId = this.getDefaultProviderId();
      providerConfig = { webhookUrl: data[QUICK_NOTES_STORAGE_KEYS.legacyFlomoWebhookUrl] };
      await this.saveSettings(providerId, providerConfig);
      await chrome.storage.sync.remove(QUICK_NOTES_STORAGE_KEYS.legacyFlomoWebhookUrl);
    }

    return { providerId, providerConfig };
  },

  async saveSettings(providerId, providerConfig) {
    await chrome.storage.sync.set({
      [QUICK_NOTES_STORAGE_KEYS.provider]: providerId,
      [QUICK_NOTES_STORAGE_KEYS.providerConfig]: providerConfig
    });
  },

  async getNotes() {
    const { notes = [] } = await chrome.storage.local.get(QUICK_NOTES_STORAGE_KEYS.notes);
    return notes.map((note) => this.normalizeNote(note));
  },

  async appendNote(note) {
    const notes = await this.getNotes();
    notes.unshift(this.normalizeNote(note));
    if (notes.length > QUICK_NOTES_MAX_NOTES) {
      notes.length = QUICK_NOTES_MAX_NOTES;
    }
    await chrome.storage.local.set({ [QUICK_NOTES_STORAGE_KEYS.notes]: notes });
    return notes;
  },

  async deleteNote(noteId) {
    const notes = await this.getNotes();
    const filtered = notes.filter((note) => note.id !== noteId);
    await chrome.storage.local.set({ [QUICK_NOTES_STORAGE_KEYS.notes]: filtered });
    return filtered;
  },

  async setPendingSelection(tabId, pendingSelection) {
    await chrome.storage.session.set({
      [this.getPendingSelectionKey(tabId)]: pendingSelection
    });
  },

  async getPendingSelection(tabId) {
    const key = this.getPendingSelectionKey(tabId);
    const data = await chrome.storage.session.get(key);
    return data[key] || null;
  },

  async clearPendingSelection(tabId) {
    await chrome.storage.session.remove(this.getPendingSelectionKey(tabId));
  },

  async setFallbackPendingNote(pendingSelection) {
    await chrome.storage.local.set({
      [QUICK_NOTES_STORAGE_KEYS.fallbackPendingNote]: pendingSelection
    });
  },

  async getFallbackPendingNote() {
    const data = await chrome.storage.local.get(QUICK_NOTES_STORAGE_KEYS.fallbackPendingNote);
    return data[QUICK_NOTES_STORAGE_KEYS.fallbackPendingNote] || null;
  },

  async clearFallbackPendingNote() {
    await chrome.storage.local.remove(QUICK_NOTES_STORAGE_KEYS.fallbackPendingNote);
  },

  getPendingSelectionKey(tabId) {
    return "pending_" + tabId;
  },

  normalizeNote(note) {
    if (!note) return note;
    return {
      id: note.id || this.createLegacyId(note),
      selectedText: note.selectedText || "",
      userNote: note.userNote || "",
      pageUrl: note.pageUrl || "",
      pageTitle: note.pageTitle || "",
      provider: note.provider || this.getDefaultProviderId(),
      timestamp: note.timestamp || Date.now()
    };
  },

  getDefaultProviderId() {
    return typeof DEFAULT_PROVIDER === "string" ? DEFAULT_PROVIDER : QUICK_NOTES_DEFAULT_PROVIDER_ID;
  },

  createId() {
    if (globalThis.crypto && typeof globalThis.crypto.randomUUID === "function") {
      return globalThis.crypto.randomUUID();
    }
    return "note_" + Date.now() + "_" + Math.random().toString(36).slice(2, 10);
  },

  createLegacyId(note) {
    if (note && note.timestamp) {
      return "legacy_" + note.timestamp;
    }
    return this.createId();
  }
};
