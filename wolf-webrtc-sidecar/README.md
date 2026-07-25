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
Wolf (host net, ipc host)                      sidecar (host net, ipc host)
  encoder ─ tee ─ rtpmoonlightpay ─ appsink → Moonlight client (unchanged)
              └── queue(leaky) ─ parsebin ─ mpegtsmux ─ shmsink
                                    /tmp/sockets/tap_<session>_video
                                                  └─ shmsrc ─ tsdemux ─ parser
                                                       ─ rtp payloader ─ tee
                                                            ├─ queue ─ webrtcbin → browser 1
                                                            └─ queue ─ webrtcbin → browser 2
```

No re-encoding happens: frames are copied post-encoder, so the cost is a memcpy
plus TS packetisation. Both tap branches are `leaky=downstream` with
`allow-not-linked`, so a stopped, slow, or crashed sidecar cannot stall Wolf's
Moonlight path.

Two non-obvious constraints, both learned the hard way and load-bearing:

- **MPEG-TS, not GDP.** The sidecar always attaches *mid-session* — the tap
  socket only exists once a session is running. GDP sends caps once at stream
  start, so a late consumer gets `Received a buffer without first receiving
  caps` forever. TS repeats PAT/PMT, so a late joiner self-describes.
- **`ipc: host` on both containers.** GStreamer's shm transport passes a
  `/dev/shm` segment *name* over the unix socket. Docker gives each container a
  private `/dev/shm`, so the name doesn't resolve on the other side and
  `shmsrc` dies instantly with EIO. Sharing the IPC namespace fixes it; without
  it the tap looks connected and delivers nothing.

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

## Testing without Wolf

```bash
bash wolf-webrtc-sidecar/test/run-harness.sh
```

Stands up a producer container writing the exact tap a patched Wolf writes,
then drives the sidecar with a real `webrtcbin` peer that completes
offer/answer/ICE and counts delivered RTP. Needs only Docker — no GPU, no
Moonlight, no pairing. Exits non-zero if media never reaches the peer, and
`--keep` leaves the containers up for poking.

It checks ingest, H264 + Opus payloading, a full WebRTC handshake, and two
simultaneous viewers. Four separate bugs turned up here that all looked fine
from "the container starts and the log says ready", so run it after touching
the pipeline or bumping the base image.

## Operational notes

- **Stale sockets are normal.** A socket file outlives the session that made
  it, and `shmsink` will not reuse a taken path — it creates
  `tap_<id>_video.0` next to it. Discovery therefore takes the newest socket
  per session and quarantines ones that refuse to connect (logged once, not
  every scan). Nothing to clean up by hand.
- **Audio can arrive late.** Wolf's audio and video sinks come up
  independently, so a session may be video-only for a moment; the audio tap is
  attached to the running session when it appears. Viewers already connected
  keep the video-only stream they negotiated — reconnect to pick up audio.
- **`/status` is the diagnosis endpoint.** `receiving: false` means Wolf isn't
  writing (no session, or the config patch is missing); `receiving: true` with
  `peers: 0` means ingest is fine and the problem is browser-side.

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
