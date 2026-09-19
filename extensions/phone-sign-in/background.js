import { installCookies } from "./import.js";
let socket,
  heartbeat,
  reconnectTimer,
  connecting = false,
  importing = false;
const status = (message) => chrome.storage.session.set({ status: message });
async function connect() {
  if (connecting) {
    clearTimeout(reconnectTimer);
    reconnectTimer = setTimeout(connect, 100);
    return;
  }
  if (socket) return;
  connecting = true;
  try {
    const {
      token,
      name,
      port = "8766",
    } = await chrome.storage.local.get(["token", "name", "port"]);
    if (
      !/^[a-f0-9]{64}$/.test(token || "") ||
      !/^\d{2,5}$/.test(port) ||
      +port > 65535
    ) {
      await status("Set up the connection below.");
      return;
    }
    const ws = new WebSocket(
      `ws://127.0.0.1:${port}/api/browser-sign-in/adapter`,
    );
    socket = ws;
    ws.onopen = () => {
      ws.send(
        JSON.stringify({
          type: "hello",
          token,
          name: name || "Chrome — personal",
          kind: "chrome",
        }),
      );
      heartbeat = setInterval(() => {
        if (ws.readyState === WebSocket.OPEN) ws.send('{"type":"ping"}');
      }, 20000);
    };
    ws.onmessage = async (event) => {
      try {
        if (event.data.length > 262144) {
          ws.close();
          return;
        }
        const job = JSON.parse(event.data);
        if (job.type === "ready") {
          await status(
            "Connected. This Chrome profile is available on your phone.",
          );
          return;
        }
        if (job.type !== "import") return;
        if (importing) {
          ws.send(JSON.stringify({ type: "result", id: job.id, installed: 0, reason: "busy" }));
          return;
        }
        importing = true;
        let result;
        try {
          result = await installCookies(chrome, job);
        } catch {
          result = { installed: 0, uncertain: true, reason: "invalid-cookie" };
        } finally {
          importing = false;
        }
        if (ws.readyState === WebSocket.OPEN)
          ws.send(JSON.stringify({ type: "result", id: job.id, ...result }));
        await status(
          result.installed === job.cookies.length
            ? "Sign-in received. Refresh the destination website."
            : `Sign-in incomplete (${result.reason || "unknown"}). Fix the cause and try again from your phone.`,
        );
      } catch {
        ws.close();
      }
    };
    ws.onclose = () => {
      if (socket !== ws) return;
      socket = undefined;
      clearInterval(heartbeat);
      void status("Disconnected. Keep LFG running on this Mac.");
      clearTimeout(reconnectTimer);
      reconnectTimer = setTimeout(connect, 5000);
    };
    ws.onerror = () => ws.close();
  } finally {
    connecting = false;
  }
}
chrome.action.onClicked.addListener(() => chrome.runtime.openOptionsPage());
chrome.runtime.onInstalled.addListener(() => {
  chrome.alarms.create("reconnect", { periodInMinutes: 0.5 });
  void connect();
});
chrome.runtime.onStartup.addListener(() => void connect());
chrome.alarms.onAlarm.addListener(() => void connect());
chrome.storage.onChanged.addListener((_, area) => {
  if (area === "local") {
    if (socket) socket.close();
    else void connect();
  }
});
void connect();
