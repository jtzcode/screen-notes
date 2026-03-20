importScripts("providers.js");

const MAX_NOTES = 50;

// Register context menu item on install
chrome.runtime.onInstalled.addListener(() => {
  chrome.contextMenus.create({
    id: "flomo-quick-note",
    title: "Take quick notes",
    contexts: ["selection"]
  });
});

// Handle context menu click — inject bubble into the page
chrome.contextMenus.onClicked.addListener(async (info, tab) => {
  if (info.menuItemId !== "flomo-quick-note") return;

  // Check if provider is configured
  const { provider, providerConfig } = await chrome.storage.sync.get(["provider", "providerConfig"]);
  const p = getProvider(provider || DEFAULT_PROVIDER);

  if (!p || !providerConfig || !p.validate(providerConfig).valid) {
    chrome.runtime.openOptionsPage();
    return;
  }

  const selectedText = info.selectionText || "";
  const pageUrl = tab.url || "";
  const pageTitle = tab.title || "";

  // Store pending data in session storage (survives service worker restarts)
  await chrome.storage.session.set({
    ["pending_" + tab.id]: { selectedText, pageUrl, pageTitle }
  });

  // Inject the content script into the active tab
  await chrome.scripting.executeScript({
    target: { tabId: tab.id },
    files: ["content.js"]
  });

  // Send the data to the injected script
  chrome.tabs.sendMessage(tab.id, {
    type: "qn-populate",
    data: { selectedText, pageUrl, pageTitle, providerName: p.name }
  });
});

// Handle save requests from the content script
chrome.runtime.onMessage.addListener((msg, sender, sendResponse) => {
  if (msg.type !== "qn-save") return;

  const tabId = sender.tab && sender.tab.id;

  // Async work — must return true to keep the message channel open
  (async () => {
    try {
      const sessionData = await chrome.storage.session.get("pending_" + tabId);
      const pending = sessionData["pending_" + tabId];

      if (!pending) {
        sendResponse({ success: false, message: "No pending note found. Please try selecting the text again." });
        return;
      }

      const { provider: providerId, providerConfig } = await chrome.storage.sync.get(["provider", "providerConfig"]);
      const provider = getProvider(providerId || DEFAULT_PROVIDER);

      if (!provider) throw new Error("Provider not configured.");

      const config = providerConfig || {};
      const content = provider.buildContent(pending.selectedText, msg.userNote, pending.pageUrl);
      await provider.send(config, content);

      // Save to local history
      const { notes = [] } = await chrome.storage.local.get("notes");
      notes.unshift({
        selectedText: pending.selectedText,
        userNote: msg.userNote,
        pageUrl: pending.pageUrl,
        pageTitle: pending.pageTitle,
        provider: provider.id,
        timestamp: Date.now()
      });
      if (notes.length > MAX_NOTES) notes.length = MAX_NOTES;
      await chrome.storage.local.set({ notes });

      // Clean up
      await chrome.storage.session.remove("pending_" + tabId);
      sendResponse({ success: true, message: "Saved to " + provider.name + " ✓" });
    } catch (err) {
      sendResponse({ success: false, message: "Failed: " + err.message });
    }
  })();

  return true; // keep message channel open for async response
});
