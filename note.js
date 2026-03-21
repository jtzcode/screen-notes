let pendingNote = null;

// Load the stashed selection data
async function loadPendingNote() {
  const data = await QuickNotesStorage.getFallbackPendingNote();
  if (!data) {
    showStatus("No selected text found.", true);
    return false;
  }

  pendingNote = data;

  document.getElementById("selected-text").textContent = data.selectedText;

  const urlEl = document.getElementById("page-url");
  urlEl.textContent = data.pageTitle || data.pageUrl;
  urlEl.href = data.pageUrl;
  return true;
}

// Load provider settings — update button label and check config
async function loadProviderState() {
  const saveBtn = document.getElementById("btn-save");

  try {
    const { provider } = await QuickNotesNoteService.getConfiguredProvider();
    saveBtn.textContent = "Save to " + provider.name;
    saveBtn.disabled = !pendingNote;
  } catch (err) {
    saveBtn.disabled = true;
    showStatus(err.message + " Please set it up in the extension options.", true);
  }
}

// Save button
document.getElementById("btn-save").addEventListener("click", async () => {
  const userNote = document.getElementById("user-note").value.trim();
  if (!pendingNote) {
    showStatus("Nothing to save.", true);
    return;
  }

  const saveBtn = document.getElementById("btn-save");
  saveBtn.disabled = true;
  saveBtn.textContent = "Saving…";

  try {
    const result = await QuickNotesNoteService.savePendingNote(pendingNote, userNote);
    await QuickNotesStorage.clearFallbackPendingNote();
    showStatus(result.message, false);

    // Close window after a short delay
    setTimeout(() => window.close(), 800);
  } catch (err) {
    showStatus("Failed to save: " + err.message, true);
    saveBtn.disabled = false;
    loadProviderState();
  }
});

// Cancel button
document.getElementById("btn-cancel").addEventListener("click", async () => {
  await QuickNotesStorage.clearFallbackPendingNote();
  window.close();
});

function showStatus(msg, isError) {
  const el = document.getElementById("status-msg");
  el.textContent = msg;
  el.className = "status-msg " + (isError ? "error" : "success");
}

initializePage();

async function initializePage() {
  try {
    await loadPendingNote();
    await loadProviderState();
  } catch (err) {
    showStatus("Failed to load note page: " + err.message, true);
  }
}
