importScripts("providers.js", "storage.js", "note-service.js");

const QUICK_NOTE_MENU_ID = "quick-notes-take-note";

// Register context menu item on install
chrome.runtime.onInstalled.addListener(() => {
  chrome.contextMenus.removeAll(() => {
    chrome.contextMenus.create({
      id: QUICK_NOTE_MENU_ID,
      title: "Take quick notes",
      contexts: ["selection"]
    });
  });
});

// Handle context menu click — inject bubble into the page
chrome.contextMenus.onClicked.addListener(async (info, tab) => {
  if (info.menuItemId !== QUICK_NOTE_MENU_ID || !tab || typeof tab.id !== "number") return;

  let configuredProvider;
  try {
    configuredProvider = await QuickNotesNoteService.getConfiguredProvider();
  } catch (err) {
    chrome.runtime.openOptionsPage();
    return;
  }

  const pendingSelection = {
    selectedText: info.selectionText || "",
    pageUrl: tab.url || "",
    pageTitle: tab.title || ""
  };

  await QuickNotesStorage.setPendingSelection(tab.id, pendingSelection);

  try {
    await chrome.scripting.executeScript({
      target: { tabId: tab.id },
      files: ["content.js"]
    });

    await chrome.tabs.sendMessage(tab.id, {
      type: "qn-populate",
      data: {
        selectedText: pendingSelection.selectedText,
        pageUrl: pendingSelection.pageUrl,
        pageTitle: pendingSelection.pageTitle,
        providerName: configuredProvider.provider.name
      }
    });
  } catch (err) {
    await openFallbackNoteWindow(tab.id, pendingSelection);
  }
});

// Handle save requests from the content script
chrome.runtime.onMessage.addListener((msg, sender, sendResponse) => {
  if (msg.type !== "qn-save") return;

  const tabId = sender.tab && sender.tab.id;

  // Async work — must return true to keep the message channel open
  (async () => {
    try {
      const pendingSelection = await QuickNotesStorage.getPendingSelection(tabId);
      const result = await QuickNotesNoteService.savePendingNote(pendingSelection, msg.userNote);
      await QuickNotesStorage.clearPendingSelection(tabId);
      sendResponse({ success: true, message: result.message });
    } catch (err) {
      sendResponse({ success: false, message: "Failed: " + err.message });
    }
  })();

  return true; // keep message channel open for async response
});

async function openFallbackNoteWindow(tabId, pendingSelection) {
  await QuickNotesStorage.clearPendingSelection(tabId);
  await QuickNotesStorage.setFallbackPendingNote(pendingSelection);

  const noteUrl = chrome.runtime.getURL("note.html");

  try {
    await chrome.windows.create({
      url: noteUrl,
      type: "popup",
      width: 460,
      height: 640
    });
  } catch (err) {
    await chrome.tabs.create({ url: noteUrl });
  }
}
