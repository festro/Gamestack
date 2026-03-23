#!/bin/bash
set -e

# Must be run from the Gamestack directory
cd "$(dirname "$0")"

echo "=== GameStack Setup ==="

# ── .env check ────────────────────────────────────────────────────────────────
if [ ! -f .env ]; then
  echo ""
  echo "[!] No .env file found."
  echo "    Copy .env.example to .env and fill in your values:"
  echo "    cp .env.example .env"
  exit 1
fi

# Load .env so DATA_DIR is available for directory creation
set -a; source .env; set +a

# ── Preflight ─────────────────────────────────────────────────────────────────
# Preflight is run by configure.sh — if .preflight_env exists we can skip.
# If missing, run configure.sh --preflight-only to generate it.
if [ ! -f .preflight_env ] || [ .env -nt .preflight_env ]; then
    echo ""
    echo "=== Running preflight check ==="
    if [ -f configure.sh ]; then
        if [ "$1" = "--auto" ]; then
            bash configure.sh --preflight-only --auto || {
                echo ""
                echo "[!] Preflight reported errors — fix them before continuing."
                exit 1
            }
        else
            bash configure.sh --preflight-only || {
                echo ""
                echo "[!] Preflight reported errors — fix them before continuing."
                exit 1
            }
        fi
    else
        echo "[!] configure.sh not found — cannot run preflight."
        echo "    Run 'bash configure.sh' first to set up your environment."
        exit 1
    fi
    echo ""
else
    echo "[=] Preflight already run — skipping (run 'bash configure.sh --preflight-only' to re-check)"
fi

# Load preflight results for GPU-specific behaviour later
[ -f .preflight_env ] && source .preflight_env

# ── Directories ───────────────────────────────────────────────────────────────
echo ""
echo "=== Creating directories ==="
mkdir -p "${DATA_DIR}/ampdata"
mkdir -p "${DATA_DIR}/wolf-config/cfg"
mkdir -p "${DATA_DIR}/images"
mkdir -p "${DATA_DIR}/portal/html"
mkdir -p "${DATA_DIR}/portal/nginx"
mkdir -p "${DATA_DIR}/portal/docs"
mkdir -p output
mkdir -p "${DATA_DIR}/logs"

sudo chown -R "${PUID:-1000}:${PGID:-1000}" \
  "${DATA_DIR}/ampdata" \
  "${DATA_DIR}/wolf-config"

# ── Logging ──────────────────────────────────────────────────────────────────
LOG_FILE="${DATA_DIR}/logs/startup-$(date +%Y%m%d-%H%M%S).log"
echo "GameStack startup log — $(date)" > "$LOG_FILE"
echo "Logging to: ${LOG_FILE}"

# ── uinput ────────────────────────────────────────────────────────────────────
if [ ! -e /dev/uinput ]; then
  echo "[+] Loading uinput kernel module..."
  sudo modprobe uinput
fi

# ── Wolf config ───────────────────────────────────────────────────────────────
if [ ! -f "${DATA_DIR}/wolf-config/cfg/config.toml" ]; then
  if [ -f wolf-config/cfg/config.toml.example ]; then
    echo "[+] Copying config.toml.example to wolf-config..."
    cp wolf-config/cfg/config.toml.example "${DATA_DIR}/wolf-config/cfg/config.toml"
  else
    echo "[!] No config.toml found — Wolf will generate a default on first start."
  fi
fi

# ── AMP data ──────────────────────────────────────────────────────────────────
if [ ! -f "${DATA_DIR}/ampdata/instances.json" ]; then
  if [ -f ampdata/instances.json.example ]; then
    echo "[+] Copying instances.json.example to ampdata..."
    cp ampdata/instances.json.example "${DATA_DIR}/ampdata/instances.json"
  fi
fi

# ── Portal files ──────────────────────────────────────────────────────────────
echo ""
echo "=== Syncing portal files ==="
cp portal/html/index.html   "${DATA_DIR}/portal/html/index.html"
cp portal/nginx/default.conf "${DATA_DIR}/portal/nginx/default.conf"

if [ -f output/GameStack.html ]; then
  cp output/GameStack.html "${DATA_DIR}/portal/docs/GameStack.html"
  echo "[+] Docs copied to portal/docs/"
else
  echo "[!] output/GameStack.html not found — run 'node build.js' to generate docs"
fi

# ── Image cache ───────────────────────────────────────────────────────────────
echo ""
echo "=== Checking for cached images ==="

load_if_cached() {
  local file=$1 label=$2
  if [ -f "${DATA_DIR}/images/${file}" ]; then
    echo "[+] Loading ${label} from local cache..."
    docker load < "${DATA_DIR}/images/${file}"
  else
    echo "[=] No cached ${label} image — will pull from registry."
  fi
}

load_if_cached "amp-image.tar.gz"  "AMP"
load_if_cached "wolf-image.tar.gz" "Wolf"

# ── Pull & start ──────────────────────────────────────────────────────────────
echo ""
echo "=== Pulling any missing images ==="
docker compose --env-file .env pull --ignore-pull-failures 2>&1 | tee -a "$LOG_FILE"

echo ""
echo "=== Starting stack ==="
docker compose --env-file .env up -d 2>&1 | tee -a "$LOG_FILE"

# Detect host IP for display
HOST_IP=$(ip route get 1.1.1.1 2>/dev/null | awk '/src/{for(i=1;i<=NF;i++) if($i=="src") print $(i+1); exit}')

echo ""
echo "=== Stack is up ==="
echo "  Portal:       http://${HOST_IP}/"
echo "  AMP:          http://${HOST_IP}:8080"
echo "  Wolf pairing: http://${HOST_IP}:47989"
echo "  WebRTC:       http://${HOST_IP}:8088/client"
echo ""
echo "Add ${HOST_IP} as a host in Moonlight to start streaming."
echo ""

# ── Cache images ──────────────────────────────────────────────────────────────
echo ""
echo "=== Checking image cache ==="

cache_image() {
  local image=$1 file=$2 label=$3
  local digest_file="${DATA_DIR}/images/${file%.tar.gz}.digest"
  local current_digest
  current_digest=$(docker inspect --format='{{index .RepoDigests 0}}' "$image" 2>/dev/null || echo "unknown")

  if [ ! -f "${DATA_DIR}/images/${file}" ] || \
     [ ! -f "$digest_file" ] || \
     [ "$current_digest" != "$(cat "$digest_file")" ]; then
    echo "[+] $label image changed or not cached — saving..."
    mkdir -p "${DATA_DIR}/images"
    docker save "$image" | gzip > "${DATA_DIR}/images/${file}"
    echo "$current_digest" > "$digest_file"
    echo "[+] $label cached."
  else
    echo "[=] $label cache is current."
  fi
}

cache_image "mitchtalmadge/amp-dockerized:latest" "amp-image.tar.gz"  "AMP"
cache_image "ghcr.io/games-on-whales/wolf:stable" "wolf-image.tar.gz" "Wolf"

echo ""
echo "=== Cache check complete ==="
echo "Total cache size: $(du -sh "${DATA_DIR}/images/" 2>/dev/null | cut -f1)"
