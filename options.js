// ——— Populate provider dropdown ———
const providerSelect = document.getElementById("provider-select");
const configContainer = document.getElementById("provider-config");

for (const p of getProviderList()) {
  const opt = document.createElement("option");
  opt.value = p.id;
  opt.textContent = p.name;
  providerSelect.appendChild(opt);
}

// Render config fields for the selected provider
function renderConfigFields(providerId, savedConfig) {
  const provider = getProvider(providerId);
  configContainer.innerHTML = "";
  if (!provider) return;

  for (const field of provider.configFields) {
    const group = document.createElement("div");
    group.className = "form-group";

    const label = document.createElement("label");
    label.setAttribute("for", "cfg-" + field.key);
    label.textContent = field.label + ":";
    group.appendChild(label);

    const input = document.createElement("input");
    input.type = field.type || "text";
    input.id = "cfg-" + field.key;
    input.placeholder = field.placeholder || "";
    input.value = (savedConfig && savedConfig[field.key]) || "";
    group.appendChild(input);

    if (field.hint) {
      const hint = document.createElement("p");
      hint.className = "hint";
      hint.textContent = field.hint;
      group.appendChild(hint);
    }

    configContainer.appendChild(group);
  }
}

// ——— Load saved settings (with migration from old format) ———
chrome.storage.sync.get(["provider", "providerConfig", "flomoWebhookUrl"], (data) => {
  let providerId = data.provider || DEFAULT_PROVIDER;
  let config = data.providerConfig || {};

  // Migrate old flomoWebhookUrl → new format
  if (!data.provider && data.flomoWebhookUrl) {
    providerId = "flomo";
    config = { webhookUrl: data.flomoWebhookUrl };
    // Persist migrated data and clean up old key
    chrome.storage.sync.set({ provider: providerId, providerConfig: config });
    chrome.storage.sync.remove("flomoWebhookUrl");
  }

  providerSelect.value = providerId;
  renderConfigFields(providerId, config);
});

// Re-render fields when provider changes
providerSelect.addEventListener("change", () => {
  renderConfigFields(providerSelect.value, {});
});

// ——— Save ———
document.getElementById("btn-save").addEventListener("click", () => {
  const providerId = providerSelect.value;
  const provider = getProvider(providerId);
  if (!provider) {
    showStatus("Unknown provider.", true);
    return;
  }

  // Collect config from rendered fields
  const config = {};
  for (const field of provider.configFields) {
    config[field.key] = document.getElementById("cfg-" + field.key).value.trim();
  }

  const { valid, error } = provider.validate(config);
  if (!valid) {
    showStatus(error, true);
    return;
  }

  chrome.storage.sync.set({ provider: providerId, providerConfig: config }, () => {
    showStatus("Saved ✓", false);
  });
});

function showStatus(msg, isError) {
  const el = document.getElementById("status-msg");
  el.textContent = msg;
  el.className = "status-msg " + (isError ? "error" : "success");
}
