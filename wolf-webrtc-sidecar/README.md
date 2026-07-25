# wolf-webrtc-sidecar

Watch a running Wolf session in a browser — no Moonlight client needed.
**View-only:** the stream is one-way. Input still goes through Moonlight.

## Why v2 exists

v1 tried to read Wolf's video with `interpipesrc listen-to={session_id}_video`
from its own container. That can never work: `gst-interpipe` links pipelines
inside a single process, so the sidecar's pipeline went `PLAYING` and then sat
there receiving nothing — a black screen with no error in the log.

v2 has Wolf hand the data over explicitly. `apply-wolf-tap.sh` patches Wolf's
`config.toml` so each session's sink pipeline `tee`s the already-encoded frames
into an `shmsink` socket in `/tmp/sockets`, a directory both containers already
bind-mount. The sidecar picks those up with `shmsrc`.

```
Wolf (host net)                                    sidecar (host net)
  encoder ─ tee ─ rtpmoonlightpay ─ appsink → Moonlight client (unchanged)
              └── queue(leaky) ─ gdppay ─ shmsink
                                    /tmp/sockets/tap_<session>_video
                                                  └─ shmsrc ─ gdpdepay ─ parsebin
                                                       ─ rtp payloader ─ tee
                                                            ├─ queue ─ webrtcbin → browser 1
                                                            └─ queue ─ webrtcbin → browser 2
```

No re-encoding happens: frames are copied post-encoder, so the cost is a memcpy
per frame. Both tap branches are `leaky=downstream` with `allow-not-linked`, so
a stopped, slow, or crashed sidecar cannot stall Wolf's Moonlight path.

## Setup

```bash
bash wolf-webrtc-sidecar/apply-wolf-tap.sh   # backs up config.toml, then patches
docker restart wolf
```

Then start a session from Moonlight as usual and open `http://<host-ip>:8088/client`.
Sessions appear within ~2s of the tap socket showing up.

- `--check` — report whether the tap is applied
- `--revert` — restore the pre-tap backup
- Wolf upgrades that rewrite `config.toml` drop the tap; re-run the script.

## Endpoints

| Path | Purpose |
|---|---|
| `GET /` | active session IDs + WS port |
| `GET /status` | per-session codec, bytes ingested, peer count |
| `GET /wolf-pin` | latest Moonlight pairing PIN URL, scraped from Wolf's logs |
| `GET /client` | browser client |
| `ws://<host-ip>:8089/<session_id>` | signalling (offer/answer/ICE) |

`/status` is the first thing to check when a stream looks dead: `receiving:
false` means Wolf isn't writing to the tap (session not started, or the config
patch is missing), while `receiving: true` with `peers: 0` means the ingest
works and the problem is on the browser side.

## Controls

| Key / Action | Effect |
|---|---|
| Esc | Disconnect and return to menu |
| F2 | Toggle stats HUD (fps, RTT, RX) |
| Click video | Reminder that the stream is view-only |

## Limits

- **View-only.** Wolf takes input over Moonlight's encrypted control channel;
  a browser can't join it. Clicking the video says so.
- **H264 only in practice.** HEVC taps stream but most browsers can't decode
  them; AV1 isn't wired up. Set the Moonlight client to H264 for co-viewing.
- **Late joiners wait for the next IDR frame** — up to a few seconds of black
  before the picture appears.
- **A session exists only while Moonlight is connected.** The tap socket
  disappears with the session and the sidecar reaps it.
- **STUN:** Google's public STUN by default — fine for LAN. WAN access needs a
  TURN server (`STUN_SERVER` is configurable; TURN is not wired up).
- Signalling is unauthenticated: anyone on the LAN who can reach :8089 and
  guess a session ID can watch. Don't expose these ports to the internet.

## Roadmap

- [ ] Per-session auth token
- [ ] AV1 co-view (browser support is arriving)
- [ ] TURN support for WAN relay
- [ ] Force-IDR on peer join, to kill the late-join black screen
