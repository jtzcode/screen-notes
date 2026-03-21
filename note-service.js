const QuickNotesNoteService = {
  MAX_NOTES: 50,

  async getConfiguredProvider() {
    const { providerId, providerConfig } = await QuickNotesStorage.getSettings();
    const provider = getProvider(providerId || DEFAULT_PROVIDER);

    if (!provider) {
      throw new Error("Provider not configured.");
    }

    const config = providerConfig || {};
    const validation = provider.validate(config);
    if (!validation.valid) {
      throw new Error(validation.error || "Provider is not configured.");
    }

    return { provider, config };
  },

  async savePendingNote(pendingSelection, userNote) {
    if (!pendingSelection) {
      throw new Error("No pending note found. Please try selecting the text again.");
    }

    const { provider, config } = await this.getConfiguredProvider();
    const content = provider.buildContent(
      pendingSelection.selectedText,
      userNote,
      pendingSelection.pageUrl
    );

    await provider.send(config, content);

    const note = QuickNotesStorage.normalizeNote({
      selectedText: pendingSelection.selectedText,
      userNote,
      pageUrl: pendingSelection.pageUrl,
      pageTitle: pendingSelection.pageTitle,
      provider: provider.id,
      timestamp: Date.now()
    });

    await QuickNotesStorage.appendNote(note);

    return {
      note,
      provider,
      message: "Saved to " + provider.name + " ✓"
    };
  }
};
