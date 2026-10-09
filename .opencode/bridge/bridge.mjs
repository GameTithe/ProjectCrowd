import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, "..", "..");
const server = "http://127.0.0.1:4096";
const idsPath = path.join(root, "opencode-session-ids.txt");
const statePath = path.join(here, "bridge-state.json");

function loadState() {
  try {
    return JSON.parse(fs.readFileSync(statePath, "utf8"));
  } catch {
    return { initialized: false, sessions: {}, seen: [] };
  }
}

const state = loadState();
const seen = new Set(state.seen ?? []);
let running = false;

function saveState(sessions) {
  state.initialized = true;
  state.sessions = sessions;
  state.seen = [...seen].slice(-1000);
  fs.writeFileSync(
    statePath,
    JSON.stringify(state, null, 2),
  );
}

function readSessions() {
  if (!fs.existsSync(idsPath)) {
    throw new Error("opencode-session-ids.txt was not found. Create sessions first.");
  }

  const values = Object.fromEntries(
    fs
      .readFileSync(idsPath, "utf8")
      .split(/\r?\n/)
      .filter(Boolean)
      .map((line) => line.split("=", 2)),
  );

  if (!values.MANAGER_SESSION || !values.WORKER_SESSION) {
    throw new Error("Manager or Worker session ID is missing.");
  }

  return values;
}

async function getMessages(sessionID) {
  const response = await fetch(`${server}/session/${sessionID}/message`);
  if (!response.ok) throw new Error(`Could not read messages: ${response.status}`);

  const body = await response.json();
  return body.data ?? body;
}

async function sendMessage(sessionID, text) {
  const response = await fetch(`${server}/session/${sessionID}/prompt_async`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ parts: [{ type: "text", text }] }),
  });

  if (!response.ok) throw new Error(`Could not send message: ${response.status}`);
}

function messageText(message) {
  return message.parts
    .filter((part) => part.type === "text")
    .map((part) => part.text)
    .join("\n")
    .trim();
}

async function initialize(sessions) {
  for (const sessionID of [sessions.MANAGER_SESSION, sessions.WORKER_SESSION]) {
    for (const message of await getMessages(sessionID)) {
      seen.add(message.info.id);
    }
  }

  saveState(sessions);
  console.log("Bridge ready. New @worker and @manager messages will be forwarded.");
}

async function forward(sourceName, sourceID, targetName, targetID, marker) {
  for (const message of await getMessages(sourceID)) {
    const id = message.info.id;
    if (seen.has(id)) continue;

    // Wait for a complete assistant reply so streaming text is sent only once.
    if (message.info.role === "assistant" && !message.info.time.completed) continue;

    const text = messageText(message);
    if (!text.startsWith(marker)) {
      seen.add(id);
      continue;
    }

    const payload = text.slice(marker.length).trim();
    if (!payload) {
      seen.add(id);
      continue;
    }

    await sendMessage(
      targetID,
      `[BRIDGE FROM ${sourceName.toUpperCase()}]\n${payload}`,
    );
    seen.add(id);
    console.log(`${sourceName} -> ${targetName}: ${payload.slice(0, 100)}`);
  }
}

async function tick() {
  if (running) return;
  running = true;

  try {
    const health = await fetch(`${server}/global/health`);
    if (!health.ok) throw new Error("OpenCode server is unavailable.");

    const sessions = readSessions();
    const sessionsChanged =
      state.sessions?.MANAGER_SESSION !== sessions.MANAGER_SESSION ||
      state.sessions?.WORKER_SESSION !== sessions.WORKER_SESSION;

    if (!state.initialized || sessionsChanged) {
      seen.clear();
      await initialize(sessions);
      return;
    }

    await forward(
      "manager",
      sessions.MANAGER_SESSION,
      "worker",
      sessions.WORKER_SESSION,
      "@worker",
    );
    await forward(
      "worker",
      sessions.WORKER_SESSION,
      "manager",
      sessions.MANAGER_SESSION,
      "@manager",
    );
    saveState(sessions);
  } catch (error) {
    console.error(error instanceof Error ? error.message : error);
  } finally {
    running = false;
  }
}

console.log("OpenCode bridge started.");
await tick();
setInterval(tick, 1000);
