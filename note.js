const MAX_NOTES = 50;

let pendingNote = null;

// Load the stashed selection data
chrome.storage.local.get("pendingNote", ({ pendingNote: data }) => {
  if (!data) {
    showStatus("No selected text found.", true);
    return;
  }
  pendingNote = data;

  document.getElementById("selected-text").textContent = data.selectedText;

  const urlEl = document.getElementById("page-url");
  urlEl.textContent = data.pageTitle || data.pageUrl;
  urlEl.href = data.pageUrl;
});

// Load provider settings — update button label and check config
chrome.storage.sync.get(["provider", "providerConfig"], ({ provider, providerConfig }) => {
  const p = getProvider(provider || DEFAULT_PROVIDER);
  const saveBtn = document.getElementById("btn-save");

  if (!p) {
    saveBtn.disabled = true;
    showStatus("No note provider configured. Please set one in the extension options.", true);
    return;
  }

  const config = providerConfig || {};
  const { valid } = p.validate(config);
  if (!valid) {
    saveBtn.textContent = "Save to " + p.name;
    saveBtn.disabled = true;
    showStatus(p.name + " is not configured yet. Please set it up in the extension options.", true);
    return;
  }

  saveBtn.textContent = "Save to " + p.name;
  saveBtn.disabled = false;
});

// Save button
document.getElementById("btn-save").addEventListener("click", async () => {
  const userNote = document.getElementById("user-note").value.trim();
  if (!pendingNote) {
    showStatus("Nothing to save.", true);
    return;
  }

  // Get provider settings
  const { provider: providerId, providerConfig } = await chrome.storage.sync.get(["provider", "providerConfig"]);
  const provider = getProvider(providerId || DEFAULT_PROVIDER);

  if (!provider) {
    showStatus("No note provider configured. Please set one in extension options.", true);
    return;
  }

  const config = providerConfig || {};
  const { valid, error } = provider.validate(config);
  if (!valid) {
    showStatus(error + " Please check extension options.", true);
    return;
  }

  // Build content and send
  const content = provider.buildContent(pendingNote.selectedText, userNote, pendingNote.pageUrl);

  const saveBtn = document.getElementById("btn-save");
  saveBtn.disabled = true;
  saveBtn.textContent = "Saving…";

  try {
    await provider.send(config, content);

    // Save to local storage for history
    await saveNoteLocally({
      selectedText: pendingNote.selectedText,
      userNote,
      pageUrl: pendingNote.pageUrl,
      pageTitle: pendingNote.pageTitle,
      provider: provider.id,
      timestamp: Date.now()
    });

    // Clean up pending data
    await chrome.storage.local.remove("pendingNote");

    showStatus("Saved to " + provider.name + " ✓", false);

    // Close window after a short delay
    setTimeout(() => window.close(), 800);
  } catch (err) {
    showStatus("Failed to save: " + err.message, true);
    saveBtn.disabled = false;
    saveBtn.textContent = "Save to " + provider.name;
  }
});

// Cancel button
document.getElementById("btn-cancel").addEventListener("click", () => {
  chrome.storage.local.remove("pendingNote");
  window.close();
});

// Save note to local storage (keep latest MAX_NOTES)
async function saveNoteLocally(note) {
  const { notes = [] } = await chrome.storage.local.get("notes");
  notes.unshift(note);
  if (notes.length > MAX_NOTES) {
    notes.length = MAX_NOTES;
  }
  await chrome.storage.local.set({ notes });
}

function showStatus(msg, isError) {
  const el = document.getElementById("status-msg");
  el.textContent = msg;
  el.className = "status-msg " + (isError ? "error" : "success");
}
