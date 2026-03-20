// Content script — injected on demand by background.js
// Creates a floating bubble near the selected text for quick note-taking.
// Uses Shadow DOM to isolate styles from the host page.

(() => {
  // Prevent double-injection
  if (document.getElementById("qn-bubble-host")) {
    document.getElementById("qn-bubble-host").remove();
  }

  // ——— Positioning: get selection bounding rect ———
  const selection = window.getSelection();
  let anchorRect = null;
  if (selection && selection.rangeCount > 0) {
    anchorRect = selection.getRangeAt(0).getBoundingClientRect();
  }

  // ——— Create host element + shadow DOM ———
  const host = document.createElement("div");
  host.id = "qn-bubble-host";
  host.style.cssText = "all:initial; position:fixed; z-index:2147483647;";
  document.body.appendChild(host);

  const shadow = host.attachShadow({ mode: "closed" });

  // ——— Styles (fully isolated inside shadow) ———
  const style = document.createElement("style");
  style.textContent = `
    :host {
      all: initial;
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
    }
    .qn-bubble {
      position: fixed;
      width: 380px;
      background: #fff;
      border-radius: 12px;
      box-shadow: 0 8px 32px rgba(0,0,0,0.18), 0 2px 8px rgba(0,0,0,0.08);
      padding: 16px;
      font-size: 14px;
      color: #333;
      line-height: 1.5;
      animation: qn-fade-in 0.15s ease-out;
    }
    @keyframes qn-fade-in {
      from { opacity: 0; transform: translateY(6px); }
      to   { opacity: 1; transform: translateY(0); }
    }
    .qn-arrow {
      position: absolute;
      top: -8px;
      left: 24px;
      width: 16px;
      height: 8px;
      overflow: hidden;
    }
    .qn-arrow::after {
      content: '';
      position: absolute;
      top: 4px;
      left: 2px;
      width: 12px;
      height: 12px;
      background: #fff;
      transform: rotate(45deg);
      box-shadow: -2px -2px 6px rgba(0,0,0,0.06);
    }
    .qn-header {
      font-weight: 600;
      font-size: 14px;
      color: #222;
      margin-bottom: 10px;
      display: flex;
      align-items: center;
      gap: 6px;
    }
    .qn-quote {
      padding: 8px 12px;
      background: #f3f4f6;
      border-left: 3px solid #4f8ff7;
      border-radius: 4px;
      font-style: italic;
      color: #555;
      font-size: 13px;
      max-height: 80px;
      overflow-y: auto;
      word-break: break-word;
      margin-bottom: 10px;
    }
    .qn-textarea {
      width: 100%;
      box-sizing: border-box;
      padding: 8px 10px;
      border: 1px solid #ddd;
      border-radius: 8px;
      font-family: inherit;
      font-size: 14px;
      resize: vertical;
      min-height: 70px;
      outline: none;
      transition: border-color 0.15s;
    }
    .qn-textarea:focus {
      border-color: #4f8ff7;
      box-shadow: 0 0 0 2px rgba(79,143,247,0.2);
    }
    .qn-actions {
      display: flex;
      gap: 8px;
      justify-content: flex-end;
      margin-top: 10px;
    }
    .qn-btn {
      padding: 7px 16px;
      border: none;
      border-radius: 8px;
      font-size: 13px;
      font-weight: 500;
      cursor: pointer;
      transition: background 0.15s;
    }
    .qn-btn-primary {
      background: #4f8ff7;
      color: #fff;
    }
    .qn-btn-primary:hover { background: #3a7be0; }
    .qn-btn-primary:disabled {
      background: #a8c8f7;
      cursor: not-allowed;
    }
    .qn-btn-secondary {
      background: #f0f0f0;
      color: #555;
    }
    .qn-btn-secondary:hover { background: #e0e0e0; }
    .qn-status {
      margin-top: 8px;
      padding: 6px 10px;
      border-radius: 6px;
      font-size: 12px;
      display: none;
    }
    .qn-status.success { display: block; background: #e6f9ee; color: #1a7a3a; }
    .qn-status.error   { display: block; background: #fde8e8; color: #b91c1c; }
  `;
  shadow.appendChild(style);

  // ——— Build bubble DOM ———
  const bubble = document.createElement("div");
  bubble.className = "qn-bubble";

  bubble.innerHTML = `
    <div class="qn-arrow"></div>
    <div class="qn-header">📝 Quick Note</div>
    <div class="qn-quote"></div>
    <textarea class="qn-textarea" placeholder="What are you thinking?" rows="3"></textarea>
    <div class="qn-actions">
      <button class="qn-btn qn-btn-secondary" data-action="cancel">Cancel</button>
      <button class="qn-btn qn-btn-primary" data-action="save">Save</button>
    </div>
    <div class="qn-status"></div>
  `;
  shadow.appendChild(bubble);

  // ——— Position the bubble near the selection ———
  function positionBubble() {
    const bw = 380;
    const vw = window.innerWidth;
    const vh = window.innerHeight;

    let left, top;

    if (anchorRect && anchorRect.width > 0) {
      // Place below the selection
      left = anchorRect.left + anchorRect.width / 2 - bw / 2;
      top = anchorRect.bottom + 10;

      // If it would go off-bottom, place above instead
      const bubbleHeight = bubble.offsetHeight || 280;
      if (top + bubbleHeight > vh) {
        top = anchorRect.top - bubbleHeight - 10;
        // Flip arrow to bottom
        const arrow = shadow.querySelector(".qn-arrow");
        arrow.style.top = "auto";
        arrow.style.bottom = "-8px";
        arrow.style.transform = "rotate(180deg)";
      }
    } else {
      // Fallback: center
      left = (vw - bw) / 2;
      top = vh * 0.2;
    }

    // Clamp horizontal
    left = Math.max(8, Math.min(left, vw - bw - 8));
    top = Math.max(8, top);

    bubble.style.left = left + "px";
    bubble.style.top = top + "px";
  }

  positionBubble();

  // ——— Populate with data from background message ———
  function populate(data) {
    shadow.querySelector(".qn-quote").textContent = data.selectedText;
    const saveBtn = shadow.querySelector('[data-action="save"]');
    saveBtn.textContent = "Save to " + (data.providerName || "Notes");
  }

  // ——— Listen for data from background ———
  chrome.runtime.onMessage.addListener((msg, sender, sendResponse) => {
    if (msg.type === "qn-populate") {
      populate(msg.data);
      // Focus the textarea
      setTimeout(() => shadow.querySelector(".qn-textarea").focus(), 50);
    }
  });

  // ——— Button handlers ———
  shadow.querySelector('[data-action="cancel"]').addEventListener("click", () => {
    host.remove();
  });

  shadow.querySelector('[data-action="save"]').addEventListener("click", () => {
    const userNote = shadow.querySelector(".qn-textarea").value.trim();
    const saveBtn = shadow.querySelector('[data-action="save"]');
    saveBtn.disabled = true;
    saveBtn.textContent = "Saving…";

    chrome.runtime.sendMessage({ type: "qn-save", userNote }, (response) => {
      const statusEl = shadow.querySelector(".qn-status");
      if (response && response.success) {
        statusEl.textContent = response.message;
        statusEl.className = "qn-status success";
        setTimeout(() => host.remove(), 800);
      } else {
        statusEl.textContent = (response && response.message) || "Failed to save.";
        statusEl.className = "qn-status error";
        saveBtn.disabled = false;
        saveBtn.textContent = "Save";
      }
    });
  });

  // ——— Close on Escape ———
  document.addEventListener("keydown", function escHandler(e) {
    if (e.key === "Escape") {
      host.remove();
      document.removeEventListener("keydown", escHandler);
    }
  });

  // ——— Close when clicking outside the bubble ———
  document.addEventListener("mousedown", function outsideHandler(e) {
    if (!host.contains(e.target)) {
      host.remove();
      document.removeEventListener("mousedown", outsideHandler);
    }
  });
})();
