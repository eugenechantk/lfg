const $ = (id) => document.getElementById(id);
const saved = await chrome.storage.local.get(["name", "port"]);
$("name").value = saved.name || "Chrome — personal";
$("port").value = saved.port || "8766";
async function update() {
  const state = await chrome.storage.session.get("status");
  $("status").textContent = state.status || "Not connected.";
  const p = await chrome.permissions.getAll();
  $("grants").replaceChildren(
    ...(p.origins || [])
      .filter((x) => x.startsWith("https:"))
      .map((origin) => {
        const li = document.createElement("li");
        li.textContent = origin === "https://*/*" ? "All HTTPS websites" : origin;
        const button = document.createElement("button");
        button.textContent = "Remove";
        button.onclick = async () => {
          await chrome.permissions.remove({ origins: [origin] });
          await update();
        };
        li.append(" ", button);
        return li;
      }),
  );
}
chrome.storage.onChanged.addListener(() => void update());
await update();
$("connection").onsubmit = async (e) => {
  e.preventDefault();
  const token = $("token").value.trim(),
    port = $("port").value.trim();
  if (
    !/^[a-f0-9]{64}$/.test(token) ||
    !/^\d{2,5}$/.test(port) ||
    +port > 65535
  ) {
    $("status").textContent =
      "Enter the 64-character setup token and a valid port.";
    return;
  }
  await chrome.storage.local.set({ token, port, name: $("name").value.trim() });
  $("token").value = "";
  $("status").textContent = "Connecting…";
};
$("permission").onsubmit = async (e) => {
  e.preventDefault();
  const domain = $("domain").value.trim().toLowerCase().replace(/^\./, "");
  if (!/^(?:[a-z0-9](?:[a-z0-9-]*[a-z0-9])?\.)+[a-z0-9-]+$/.test(domain)) {
    $("permissionStatus").textContent = "Enter a domain such as example.com.";
    return;
  }
  try {
    const granted = await chrome.permissions.request({
      origins: [`https://${domain}/*`, `https://*.${domain}/*`],
    });
    $("permissionStatus").textContent = granted
      ? "Website allowed."
      : "Website permission was not granted.";
    await update();
  } catch {
    $("permissionStatus").textContent = "Could not allow this website.";
  }
};

$("allowAll").onclick = async () => {
  try {
    const granted = await chrome.permissions.request({ origins: ["https://*/*"] });
    $("permissionStatus").textContent = granted
      ? "All HTTPS websites allowed."
      : "Website permission was not granted.";
    await update();
  } catch {
    $("permissionStatus").textContent = "Could not allow all websites.";
  }
};
