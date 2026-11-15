// node --test test.js : host, join, forwarding, lock, full room, host leaving.
"use strict";
const test = require("node:test");
const assert = require("node:assert");
const WebSocket = require("ws");
const { server, wss, timer } = require("./server.js");

let url;
test.before(() => new Promise((ok) => server.listen(0, () => { url = `ws://127.0.0.1:${server.address().port}`; ok(); })));
test.after(() => { clearInterval(timer); for (const c of wss.clients) c.terminate(); server.close(); });

function client() {
  return new Promise((ok, fail) => {
    const ws = new WebSocket(url);
    ws.inbox = [];
    ws.waiters = [];
    ws.on("message", (data, isBinary) => {
      const m = isBinary ? { from: data.readInt32LE(0), body: data.subarray(4).toString() } : JSON.parse(data.toString());
      const w = ws.waiters.shift();
      if (w) w(m); else ws.inbox.push(m);
    });
    ws.on("open", () => ok(ws));
    ws.on("error", fail);
  });
}
const next = (ws) => ws.inbox.length ? Promise.resolve(ws.inbox.shift()) : new Promise((ok) => ws.waiters.push(ok));
const ctl = (ws, obj) => ws.send(JSON.stringify(obj));
function data(ws, peer, text) {
  const b = Buffer.alloc(4 + Buffer.byteLength(text));
  b.writeInt32LE(peer, 0);
  b.write(text, 4);
  ws.send(b);
}

test("host, join, forward, lock, full, host leaves", async () => {
  const host = await client();
  ctl(host, { op: "host" });
  const hosted = await next(host);
  assert.equal(hosted.op, "hosted");
  assert.match(hosted.code, /^[A-HJ-NP-Z]{4}$/);

  const a = await client();
  ctl(a, { op: "join", code: hosted.code.toLowerCase() });
  assert.deepEqual(await next(a), { op: "joined", id: 2 });
  assert.deepEqual(await next(host), { op: "peer_joined", id: 2 });

  const b = await client();
  ctl(b, { op: "join", code: hosted.code });
  assert.equal((await next(b)).id, 3);
  await next(host);

  // client -> host (target ignored), host -> one / all / all-but-one
  data(a, 3, "hi host");
  assert.deepEqual(await next(host), { from: 2, body: "hi host" });
  data(host, 3, "only b");
  assert.deepEqual(await next(b), { from: 1, body: "only b" });
  data(host, 0, "all");
  assert.deepEqual(await next(a), { from: 1, body: "all" });
  assert.deepEqual(await next(b), { from: 1, body: "all" });
  data(host, -2, "not a");
  assert.deepEqual(await next(b), { from: 1, body: "not a" });

  const c = await client();
  ctl(c, { op: "join", code: hosted.code });
  assert.equal((await next(c)).id, 4);
  await next(host);
  const d = await client();
  ctl(d, { op: "join", code: hosted.code });
  assert.deepEqual(await next(d), { op: "error", reason: "full" });

  c.close();
  assert.deepEqual(await next(host), { op: "peer_left", id: 4 });
  ctl(host, { op: "lock", on: true });
  await new Promise((r) => setTimeout(r, 50));
  ctl(d, { op: "join", code: hosted.code });
  assert.deepEqual(await next(d), { op: "error", reason: "locked" });
  ctl(d, { op: "join", code: "ZZZZ" === hosted.code ? "YYYY" : "ZZZZ" });
  assert.deepEqual(await next(d), { op: "error", reason: "no_room" });

  const closed = new Promise((ok) => a.on("close", ok));
  host.close();
  assert.deepEqual(await next(a), { op: "error", reason: "host_left" });
  await closed;
  b.close(); d.close();
});
