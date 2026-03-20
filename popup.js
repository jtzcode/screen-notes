// Open options page
document.getElementById("open-options").addEventListener("click", (e) => {
  e.preventDefault();
  chrome.runtime.openOptionsPage();
});

// Load and render notes
chrome.storage.local.get("notes", ({ notes = [] }) => {
  const container = document.getElementById("notes-list");

  if (notes.length === 0) return; // keep the empty state message

  container.innerHTML = "";

  for (const note of notes) {
    const card = document.createElement("div");
    card.className = "note-card";

    const selectedText = truncate(note.selectedText, 100);
    const fullText = note.selectedText || "";
    const needsExpand = fullText.length > 100;
    const userNote = note.userNote ? truncate(note.userNote, 80) : "";
    const time = formatTime(note.timestamp);

    card.innerHTML = `
      <div class="note-card-header">
        <div class="note-selected">"${escapeHtml(selectedText)}"</div>
        <button class="btn-delete" title="Delete note">×</button>
      </div>
      ${needsExpand ? `<button class="btn-show-more">Show more</button>` : ""}
      ${userNote ? `<div class="note-user">${escapeHtml(userNote)}</div>` : ""}
      <div class="note-meta">
        <a class="note-url" href="${escapeHtml(note.pageUrl)}" target="_blank" rel="noopener noreferrer"
           title="${escapeHtml(note.pageTitle || note.pageUrl)}">${escapeHtml(truncate(note.pageTitle || note.pageUrl, 40))}</a>
        <span class="note-time">${escapeHtml(time)}</span>
      </div>
    `;

    card.querySelector(".btn-delete").addEventListener("click", async () => {
      const { notes: current = [] } = await chrome.storage.local.get("notes");
      const updated = current.filter(n => n.timestamp !== note.timestamp);
      await chrome.storage.local.set({ notes: updated });
      card.remove();
      if (container.children.length === 0) {
        container.innerHTML = '<p class="empty-state">No notes yet. Select text on a webpage, right-click, and choose "Take quick notes"!</p>';
      }
    });

    if (needsExpand) {
      const btn = card.querySelector(".btn-show-more");
      const textEl = card.querySelector(".note-selected");
      let expanded = false;
      btn.addEventListener("click", () => {
        expanded = !expanded;
        textEl.textContent = expanded ? `"${fullText}"` : `"${selectedText}"`;
        btn.textContent = expanded ? "Show less" : "Show more";
      });
    }

    container.appendChild(card);
  }
});

function truncate(str, max) {
  if (!str) return "";
  return str.length > max ? str.slice(0, max) + "…" : str;
}

function escapeHtml(text) {
  const div = document.createElement("div");
  div.appendChild(document.createTextNode(text));
  return div.innerHTML;
}

function formatTime(ts) {
  if (!ts) return "";
  const d = new Date(ts);
  const now = new Date();
  const diffMs = now - d;
  const diffMin = Math.floor(diffMs / 60000);

  if (diffMin < 1) return "just now";
  if (diffMin < 60) return diffMin + "m ago";

  const diffHr = Math.floor(diffMin / 60);
  if (diffHr < 24) return diffHr + "h ago";

  const diffDay = Math.floor(diffHr / 24);
  if (diffDay < 7) return diffDay + "d ago";

  return d.toLocaleDateString();
}
