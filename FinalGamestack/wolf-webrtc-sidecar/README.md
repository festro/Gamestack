# wolf-webrtc-sidecar

Browser streaming sidecar for Wolf. Taps Wolf's GStreamer interpipe output
and re-streams to any browser via WebRTC. Zero changes to Wolf or AMP required.

## Architecture

```
Wolf (GStreamer)
  └─ interpipe bus: {session_id}_video / {session_id}_audio
       └─ wolf-webrtc sidecar
            ├─ GStreamer: interpipesrc → h264parse → rtph264pay → webrtcbin
            ├─ WebSocket signalling server (:8089)
            └─ HTTP server (:8088)
                 └─ Browser client (HTML/JS WebRTC peer)
```

Wolf and Moonlight continue to work exactly as before. The sidecar is a
completely separate container that only reads from the interpipe bus.
Remove it any time with no impact on Wolf.

## Quick Start

### 1. Find your Wolf session ID

Session IDs are the numeric folder names under `wolf-config/cfg/`:

```bash
ls ~/gamestack/wolf-config/cfg/
# → <session_id>  4161966709011769559
```

Or check your `config.toml` — they're the `app_state_folder` values under
`[[paired_clients]]`.

### 2. Add to docker-compose.yml

Paste the contents of `docker-compose.sidecar.yml` into your main
`docker-compose.yml` under `services:`.

Optionally set `WOLF_SESSION_IDS` in your `.env` file to pre-start sessions:

```bash
# .env
WOLF_SESSION_IDS=<session_id>,4161966709011769559
```

### 3. Start the sidecar

```bash
cd ~/gamestack
docker compose up -d wolf-webrtc
```

### 4. Open in browser

Navigate to `http://<host-ip>:8088/client` from any browser on the network.

- Enter the sidecar host IP (pre-filled from page URL)
- Enter the session ID, or click one from the auto-detected list
- Click Connect

A Wolf session must be active (app launched via Moonlight) for the stream
to appear. The sidecar will connect to the interpipe bus once Wolf starts
publishing the session.

### Direct session URL

```
http://<host-ip>:8088/session/<session_id>
```

Auto-connects to that session on load.

## Controls

| Key / Action        | Effect                        |
|---------------------|-------------------------------|
| Click video         | Capture keyboard + mouse input |
| Esc                 | Disconnect and return to menu |
| F2                  | Toggle stats HUD (fps, RTT, RX) |
| Mouse (pointer lock)| Forwarded to Wolf session     |

## Ports

| Port | Protocol | Purpose                    |
|------|----------|----------------------------|
| 8088 | HTTP     | Session list + browser client |
| 8089 | WebSocket| WebRTC signalling          |

## Notes

- **H264 only (Phase 1):** The sidecar taps the H264 stream. If Wolf selects
  HEVC for a session, the pipeline will error. HEVC browser support via WebRTC
  is limited — H264 is the safe default. To force Wolf to use H264, you can
  comment out the `[[gstreamer.video.hevc_encoders]]` blocks in `config.toml`.

- **Input forwarding (Phase 2):** Keyboard and mouse events are captured in the
  browser and sent back over the WebSocket. Server-side forwarding to Wolf's
  inputtino socket (`/var/run/wolf/wolf.sock`) is the next step — the sidecar
  currently receives input events but does not yet inject them.

- **Multi-peer:** Multiple browsers can connect to the same session ID
  simultaneously. Each gets its own WebRTC connection. webrtcbin re-encodes
  per peer (no shared encoding yet).

- **STUN:** Uses Google's public STUN server by default. For LAN-only use
  this is fine. For WAN access set `STUN_SERVER` in your `.env` and consider
  adding a TURN server.

## Roadmap

- [ ] Input forwarding → Wolf inputtino socket
- [ ] HEVC support (Safari, some mobile browsers)
- [ ] Auto-discover active Wolf sessions via wolf.sock API
- [ ] TURN server support for WAN relay
- [ ] Per-session auth token
