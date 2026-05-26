// ——— Populate provider dropdown ———
const providerSelect = document.getElementById("provider-select");
const configContainer = document.getElementById("provider-config");
const providerHelp = document.getElementById("provider-help");
const activeProviderMessage = document.getElementById("active-provider-msg");
const saveButton = document.getElementById("btn-save");

let providerConfigs = {};
let activeProviderId = DEFAULT_PROVIDER;

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

function updateProviderUi(selectedProviderId) {
  const selectedProvider = getProvider(selectedProviderId);
  const activeProvider = getProvider(activeProviderId);

  providerHelp.textContent = selectedProvider
    ? "Credentials are stored per provider. Saving here updates this provider and makes it the active note destination."
    : "";

  activeProviderMessage.textContent = activeProvider
    ? "Current active provider: " + activeProvider.name
    : "";

  saveButton.textContent = selectedProvider
    ? "Save Credentials and Use " + selectedProvider.name
    : "Save";
}

// ——— Load saved settings ———
async function loadSettings() {
  const { providerId, providerConfigs: savedProviderConfigs } = await QuickNotesStorage.getSettings();
  providerConfigs = savedProviderConfigs || {};
  activeProviderId = providerId;
  providerSelect.value = providerId;
  renderConfigFields(providerId, providerConfigs[providerId] || {});
  updateProviderUi(providerId);
}

// Re-render fields when provider changes
providerSelect.addEventListener("change", () => {
  const providerId = providerSelect.value;
  renderConfigFields(providerId, providerConfigs[providerId] || {});
  updateProviderUi(providerId);
});

// ——— Save ———
saveButton.addEventListener("click", async () => {
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

  providerConfigs = {
    ...providerConfigs,
    [providerId]: config
  };
  activeProviderId = providerId;

  await QuickNotesStorage.saveSettings(providerId, config, providerConfigs);
  renderConfigFields(providerId, config);
  updateProviderUi(providerId);
  showStatus("Saved credentials and set " + provider.name + " as active provider ✓", false);
});

function showStatus(msg, isError) {
  const el = document.getElementById("status-msg");
  el.textContent = msg;
  el.className = "status-msg " + (isError ? "error" : "success");
}

loadSettings().catch((err) => {
  showStatus("Failed to load settings: " + err.message, true);
});
