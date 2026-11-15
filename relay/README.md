# Room relay (online co-op)

A tiny WebSocket server: it hands out 4-letter room codes and forwards packets between the
host player's game and its clients. The host's game stays the authority; the relay knows
nothing about the game. Godot side: `scripts/net/relay_peer.gd` (`RelayPeer`).

## Run locally
```
cd relay
npm install
npm start            # ws://127.0.0.1:8080
npm test             # protocol test: host, join, forward, lock, full room, host leaving
```
Start the game with `--relay=ws://127.0.0.1:8080` (after `--` or as a plain argument) to use a local relay.

## Deploy on Railway
1. railway.com → New Project → Deploy from GitHub repo → this repo.
2. Service → Settings → **Root Directory** = `relay`. Railway detects Node and runs `npm start`.
3. Settings → Networking → **Generate Domain** (port: the one Railway shows; the server reads `PORT`).
4. Open `https://<domain>` in a browser: it should say `space-turism relay ok, rooms: 0`.
5. Put `wss://<domain>` into `RELAY_URL` in `scripts/network.gd` and rebuild the game.

Region: pick the one closest to the players (EU West for Europe). One small instance is plenty.

## Protocol
- JSON text frames: `{op:"host"}` → `{op:"hosted", code, id:1}`; `{op:"join", code}` →
  `{op:"joined", id}` (+ the host gets `{op:"peer_joined", id}`); `{op:"peer_left", id}`;
  host only: `{op:"lock", on}`, `{op:"kick", id}`; errors `{op:"error", reason}`
  (`no_room`, `full`, `locked`, `busy`, `bad`, `host_left`, `expired`).
- Binary frames: `[int32 LE peer][payload]`. From the host, `peer` = target (0 = all clients,
  N = one client, -N = all but N); a client's frames always go to the host. Received frames
  carry the sender's id.
- Limits: 4 players per room, rooms close when the host leaves or after 3 h, 1 MB per message,
  20 failed joins per minute per IP, ping every 20 s.
