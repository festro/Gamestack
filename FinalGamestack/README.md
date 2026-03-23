# GameStack

A self-contained portable gaming LAN stack. Runs game servers and streams containerised desktops/games to Moonlight clients or any browser via WebRTC. Fully portable — tar the folder, move to any Linux + Docker machine, run `setup.sh`.

**Designed to run from `~/Gamestack`.**

## Stack

| Container | Image | Role | Port |
|-----------|-------|------|------|
| `amp` | mitchtalmadge/amp-dockerized | Game server management panel | 8080 |
| `wolf` | ghcr.io/games-on-whales/wolf:stable | Moonlight streaming host | 47989 |
| `wolf-webrtc` | local build | WebRTC browser streaming sidecar | 8088/8089 |
| `portal` | nginx:alpine | GameStack portal UI | 80 |

## Requirements

- Linux host with Docker and Docker Compose v2
- GPU with VA-API support recommended (AMD iGPU/dGPU, Intel) — NVIDIA supported via NVENC
- `uinput` kernel module (loaded automatically by `setup.sh`)
- Node.js (optional — only needed to regenerate docs with `build.js`)

## Quick start

```bash
git clone https://github.com/festro/Gamestack ~/Gamestack
# Or if installing from zip:
# unzip -X Gamestack-final.zip && mv FinalGamestack ~/Gamestack
cd ~/Gamestack
cp .env.example .env
# Edit .env — fill in DATA_DIR, AMP credentials, licence key, MAC address
bash setup.sh
```

Portal: `http://<host-ip>/`

## Structure

```
~/Gamestack/
  docker-compose.yml              # All four services
  setup.sh                        # First-run and update script
  build.js                        # Generates output/GameStack.html + .docx
  .env.example                    # Environment variable template → copy to .env
  .gitignore
  README.md
  SETUP_CHECKLIST.md              # Every field that needs changing, with line numbers
  ampdata/
    instances.json.example        # AMP instance config template
  wolf-config/
    cfg/
      config.toml.example         # Wolf config template (certs scrubbed)
      cert.pem.example            # Placeholder — Wolf auto-generates on first start
      key.pem.example             # Placeholder — Wolf auto-generates on first start
  output/
    GameStack.html                # Built ops docs (regenerate: node build.js)
  portal/
    html/index.html               # Portal UI
    nginx/default.conf            # nginx config
    docs/                         # Gitignored — GameStack.html copied here at deploy time
  wolf-webrtc-sidecar/
    Dockerfile
    sidecar/sidecar.py            # GStreamer → WebRTC bridge
    client/index.html             # Standalone browser streaming client
    README.md
```

## Services

### Portal — `http://<host-ip>/`
Dashboard with live service health checks, AMP embedded in an iframe, Wolf WebRTC stream launcher, network topology reference, and ops docs. Host IP auto-detected from `window.location.hostname`.

### AMP — `http://<host-ip>:8080`
Game server management. Add any AMP-supported game server via the AMP web UI. Servers auto-start on AMP boot.

### Wolf — pairing at `http://<host-ip>:47989`
Streams containerised desktops and games to Moonlight clients. HEVC/H264/AV1 encoding via VA-API (AMD/Intel) or NVENC (NVIDIA). Client certificates stored in `wolf-config/cfg/config.toml` after pairing.

### Wolf WebRTC Sidecar — `http://<host-ip>:8088/client`
Browser streaming without Moonlight. Taps Wolf's GStreamer interpipe output and re-streams via WebRTC. Wolf and Moonlight continue to work unchanged — the sidecar is a read-only tap that can be stopped at any time.

## Stopping the stack

```bash
cd ~/Gamestack
docker compose down
# Also stop any Wolf child containers (app sessions):
docker ps -a --filter "name=Wolf" --format "{{.Names}}" | xargs -r docker rm -f
```

## Moving to another machine

```bash
# On current machine
tar -czf gamestack-backup.tar.gz ~/Gamestack/

# On new machine
tar -xzf gamestack-backup.tar.gz
cd ~/Gamestack
bash setup.sh
```

## Docs

```bash
node build.js    # Builds output/GameStack.html and output/GameStack.docx
```

`build.js` is your personal ops notebook — hardware inventory, network topology, session notes. Regenerate after each session. `setup.sh` automatically copies `output/GameStack.html` to `portal/docs/` so it appears in the portal.

## License

GPL-3.0
