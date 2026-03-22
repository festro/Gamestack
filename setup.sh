#!/bin/bash
set -e

echo "=== GameStack Setup ==="

# Create directories
mkdir -p ampdata wolf-config images

# Set permissions
sudo chown -R 1000:1000 ampdata wolf-config

# Create uinput device if missing
if [ ! -e /dev/uinput ]; then
  sudo modprobe uinput
fi

# Load images from local cache if present, otherwise pull
echo ""
echo "=== Checking for cached images ==="

if [ -f images/amp-image.tar.gz ]; then
  echo "[+] Loading AMP from local cache..."
  docker load < images/amp-image.tar.gz
else
  echo "[+] No local AMP cache found, will pull from registry..."
fi

if [ -f images/wolf-image.tar.gz ]; then
  echo "[+] Loading Wolf from local cache..."
  docker load < images/wolf-image.tar.gz
else
  echo "[+] No local Wolf cache found, will pull from registry..."
fi

# Pull any missing images not loaded from cache
echo ""
echo "=== Pulling any missing images ==="
docker compose pull --ignore-pull-failures

# Start stack
echo ""
echo "=== Starting stack ==="
docker compose up -d

echo ""
echo "=== Stack is up ==="
echo "AMP Web UI:  http://192.168.8.115:8080"
echo "Wolf pairing: http://192.168.8.115:47989"
echo ""
echo "Open Moonlight on your Chromebook and add 192.168.8.115 as a host"
echo ""

# Auto-cache images if they've changed or cache doesn't exist
echo ""
echo "=== Checking image cache ==="

cache_image() {
  local image=$1
  local file=$2
  local label=$3

  current_digest=$(docker inspect --format='{{index .RepoDigests 0}}' "$image" 2>/dev/null || echo "unknown")
  digest_file="images/${file%.tar.gz}.digest"

  if [ ! -f "images/$file" ] || [ ! -f "$digest_file" ] || [ "$current_digest" != "$(cat $digest_file)" ]; then
    echo "[+] $label image changed or not cached — saving..."
    mkdir -p images
    docker save "$image" | gzip > "images/$file"
    echo "$current_digest" > "$digest_file"
    echo "[+] $label cached."
  else
    echo "[=] $label cache is up to date, skipping."
  fi
}

cache_image "mitchtalmadge/amp-dockerized:latest" "amp-image.tar.gz" "AMP"
cache_image "ghcr.io/games-on-whales/wolf:stable" "wolf-image.tar.gz" "Wolf"

echo ""
echo "=== Cache check complete ==="
echo "Total cache size: $(du -sh images/ 2>/dev/null | cut -f1)"
