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

# Offer to cache images for portability
read -p "Cache images locally for portable use? (y/n): " cache
if [ "$cache" = "y" ]; then
  echo ""
  echo "=== Caching images to images/ folder ==="
  mkdir -p images
  echo "[+] Saving AMP image..."
  docker save mitchtalmadge/amp-dockerized:latest | gzip > images/amp-image.tar.gz
  echo "[+] Saving Wolf image..."
  docker save ghcr.io/games-on-whales/wolf:stable | gzip > images/wolf-image.tar.gz
  echo "[+] Done. Images cached in gamestack/images/"
  echo "    Total size: $(du -sh images/ | cut -f1)"
fi
