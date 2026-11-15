// Room relay for online co-op (Railway). The host player's game stays the authority:
// this server only hands out room codes and forwards packets between the host and its clients.
//
// Control messages are JSON text frames:
//   client -> relay  {op:"host"} | {op:"join", code} | {op:"lock", on} (host) | {op:"kick", id} (host)
//   relay -> client  {op:"hosted", code, id:1} | {op:"joined", id} | {op:"peer_joined", id}
//                    {op:"peer_left", id} | {op:"error", reason}  (reason: no_room | full | locked | busy | bad | host_left | expired)
// Game data are binary frames: [int32 LE peer][payload].
//   sent by the host: peer = target (0 all clients, >0 one client, <0 everyone except -peer)
//   sent by a client: always goes to the host (Godot's server relay does client <-> client)
//   received: peer = who sent it
"use strict";

const http = require("http");
const { WebSocketServer } = require("ws");

const PORT = Number(process.env.PORT) || 8080;
const MAX_PLAYERS = 4;                     // host included (same as Network.MAX_PLAYERS)
const CODE_LETTERS = "ABCDEFGHJKLMNPQRSTUVWXYZ";   // no I / O (look like 1 / 0)
const CODE_LENGTH = 4;
const MAX_ROOMS = 500;
const ROOM_MAX_AGE_MS = 3 * 60 * 60 * 1000;
const PING_MS = 20000;
const MAX_PAYLOAD = 1 << 20;
const JOIN_FAILS_PER_MIN = 20;             // per IP: slows down guessing codes

const rooms = new Map();                    // code -> {code, host, clients: Map<id, ws>, nextId, locked, created}
const joinFails = new Map();                // ip -> {count, since}

function newCode() {
  for (let tries = 0; tries < 1000; tries++) {
    let code = "";
    for (let i = 0; i < CODE_LENGTH; i++) code += CODE_LETTERS[Math.floor(Math.random() * CODE_LETTERS.length)];
    if (!rooms.has(code)) return code;
  }
  return null;
}

function send(ws, obj) {
  if (ws.readyState === ws.OPEN) ws.send(JSON.stringify(obj));
}

function forward(ws, from, payload) {
  if (ws.readyState !== ws.OPEN) return;
  const frame = Buffer.allocUnsafe(4 + payload.length);
  frame.writeInt32LE(from, 0);
  payload.copy(frame, 4);
  ws.send(frame, { binary: true });
}

function tooManyFails(ip) {
  const f = joinFails.get(ip);
  return !!f && Date.now() - f.since <= 60000 && f.count >= JOIN_FAILS_PER_MIN;
}

function noteFail(ip) {
  const now = Date.now();
  const f = joinFails.get(ip);
  if (!f || now - f.since > 60000) joinFails.set(ip, { count: 1, since: now });
  else f.count++;
}

function closeRoom(room, reason) {
  rooms.delete(room.code);
  for (const ws of room.clients.values()) {
    ws.room = null;
    send(ws, { op: "error", reason });
    ws.close(1000, reason);
  }
  room.clients.clear();
  room.host.room = null;
  if (room.host.readyState === room.host.OPEN) {
    send(room.host, { op: "error", reason });
    room.host.close(1000, reason);
  }
}

function onControl(ws, msg) {
  if (msg.op === "host" && !ws.room) {
    if (rooms.size >= MAX_ROOMS) return send(ws, { op: "error", reason: "busy" });
    const code = newCode();
    if (!code) return send(ws, { op: "error", reason: "busy" });
    const room = { code, host: ws, clients: new Map(), nextId: 2, locked: false, created: Date.now() };
    rooms.set(code, room);
    ws.room = room;
    ws.peerId = 1;
    send(ws, { op: "hosted", code, id: 1 });
  } else if (msg.op === "join" && !ws.room) {
    if (tooManyFails(ws.ip)) return send(ws, { op: "error", reason: "busy" });
    const room = rooms.get(String(msg.code || "").toUpperCase().trim());
    if (!room) { noteFail(ws.ip); return send(ws, { op: "error", reason: "no_room" }); }
    if (room.locked) return send(ws, { op: "error", reason: "locked" });
    if (room.clients.size + 1 >= MAX_PLAYERS) return send(ws, { op: "error", reason: "full" });
    const id = room.nextId++;
    room.clients.set(id, ws);
    ws.room = room;
    ws.peerId = id;
    send(ws, { op: "joined", id });
    send(room.host, { op: "peer_joined", id });
  } else if (msg.op === "lock" && ws.room && ws.peerId === 1) {
    ws.room.locked = !!msg.on;
  } else if (msg.op === "kick" && ws.room && ws.peerId === 1) {
    const target = ws.room.clients.get(Number(msg.id));
    if (target) target.close(1000, "kicked");
  } else {
    send(ws, { op: "error", reason: "bad" });
  }
}

function onData(ws, data) {
  const room = ws.room;
  if (!room || data.length < 4) return;
  const peer = data.readInt32LE(0);
  const payload = data.subarray(4);
  if (ws.peerId !== 1) return forward(room.host, ws.peerId, payload);
  if (peer > 0) {
    const target = room.clients.get(peer);
    if (target) forward(target, 1, payload);
    return;
  }
  for (const [id, target] of room.clients) {
    if (peer < 0 && id === -peer) continue;
    forward(target, 1, payload);
  }
}

function onClose(ws) {
  const room = ws.room;
  if (!room) return;
  ws.room = null;
  if (ws.peerId === 1) return closeRoom(room, "host_left");
  if (room.clients.get(ws.peerId) === ws) {
    room.clients.delete(ws.peerId);
    send(room.host, { op: "peer_left", id: ws.peerId });
  }
}

const server = http.createServer((req, res) => {
  // Health check for Railway (and a quick look in the browser).
  res.writeHead(200, { "Content-Type": "text/plain" });
  res.end(`space-turism relay ok, rooms: ${rooms.size}\n`);
});

const wss = new WebSocketServer({ server, maxPayload: MAX_PAYLOAD });

wss.on("connection", (ws, req) => {
  ws.ip = String(req.headers["x-forwarded-for"] || req.socket.remoteAddress || "").split(",")[0].trim();
  ws.alive = true;
  ws.room = null;
  ws.on("pong", () => { ws.alive = true; });
  ws.on("message", (data, isBinary) => {
    if (isBinary) return onData(ws, Buffer.isBuffer(data) ? data : Buffer.from(data));
    let msg;
    try { msg = JSON.parse(data.toString()); } catch { return send(ws, { op: "error", reason: "bad" }); }
    if (msg && typeof msg === "object") onControl(ws, msg);
  });
  ws.on("close", () => onClose(ws));
  ws.on("error", () => {});
});

// Keepalive (proxies drop idle sockets) + drop dead sockets + expire old rooms.
const timer = setInterval(() => {
  for (const ws of wss.clients) {
    if (!ws.alive) { ws.terminate(); continue; }
    ws.alive = false;
    ws.ping();
  }
  const now = Date.now();
  for (const room of rooms.values()) {
    if (now - room.created > ROOM_MAX_AGE_MS) closeRoom(room, "expired");
  }
  for (const [ip, f] of joinFails) if (now - f.since > 60000) joinFails.delete(ip);
}, PING_MS);
wss.on("close", () => clearInterval(timer));

if (require.main === module) {
  server.listen(PORT, () => console.log(`relay listening on :${PORT}`));
}

module.exports = { server, wss, rooms, timer };
