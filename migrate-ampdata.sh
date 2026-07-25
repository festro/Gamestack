#!/bin/bash
# migrate-ampdata.sh
# Copies ampdata/ from Gamestack_Live → Gamestack
# Backs up any existing destination data before overwriting.
# Run from: ~/Git/Gamestack_Live/

set -e

# ── Colours ───────────────────────────────────────────────────────────────────
G='\033[0;32m'; Y='\033[1;33m'; R='\033[0;31m'
BOLD='\033[1m'; DIM='\033[2m'; RESET='\033[0m'

ok()      { echo -e "  ${G}✓${RESET}  $1"; }
warn()    { echo -e "  ${Y}!${RESET}  $1"; }
fail()    { echo -e "  ${R}✗${RESET}  $1"; }
section() { echo -e "\n${BOLD}── $1 ──────────────────────────────────────────────${RESET}"; }

# ── Paths ─────────────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SRC="${SCRIPT_DIR}/ampdata"
DEST_BASE="${HOME}/Git/Gamestack"
DEST="${DEST_BASE}/ampdata"
BACKUP="${DEST_BASE}/ampdata.backup-$(date +%Y%m%d-%H%M%S)"

# ── Banner ────────────────────────────────────────────────────────────────────
clear
echo -e "${BOLD}"
echo "  ╔══════════════════════════════════════════╗"
echo "  ║       AMP Data Migration                 ║"
echo "  ║       Gamestack_Live → Gamestack         ║"
echo "  ╚══════════════════════════════════════════╝"
echo -e "${RESET}"
echo -e "  ${DIM}Source:      ${SRC}${RESET}"
echo -e "  ${DIM}Destination: ${DEST}${RESET}"
echo ""

# ── Preflight checks ──────────────────────────────────────────────────────────
section "Preflight"

if [ ! -d "$SRC" ]; then
    fail "Source not found: ${SRC}"
    echo ""
    echo -e "  Run this script from ~/Git/Gamestack_Live/"
    echo -e "  Expected: ${SRC}"
    exit 1
fi
ok "Source exists: ${SRC}"

if [ ! -d "$DEST_BASE" ]; then
    fail "Destination base not found: ${DEST_BASE}"
    echo -e "  Is ~/Git/Gamestack present?"
    exit 1
fi
ok "Destination base exists: ${DEST_BASE}"

# Show source contents
echo ""
echo -e "  ${DIM}Source contents:${RESET}"
du -sh "${SRC}"/* 2>/dev/null | sed 's/^/    /' || echo "    (empty or unreadable)"
echo ""

# ── Confirm ───────────────────────────────────────────────────────────────────
printf "  ${Y}Proceed? Existing ampdata/ will be backed up then overwritten.${RESET} [y/N]: "
read -r ans
[[ "$ans" =~ ^[Yy]$ ]] || { echo -e "\n  ${Y}Aborted — nothing changed.${RESET}\n"; exit 0; }

# ── Backup existing destination ───────────────────────────────────────────────
section "Backup"

if [ -d "$DEST" ]; then
    echo -e "  ${DIM}Backing up existing ampdata/ to:${RESET}"
    echo -e "  ${DIM}  ${BACKUP}${RESET}"
    cp -a "$DEST" "$BACKUP"
    ok "Backup created: ${BACKUP}"
else
    echo -e "  ${DIM}No existing ampdata/ at destination — skipping backup.${RESET}"
fi

# ── Copy ──────────────────────────────────────────────────────────────────────
section "Copying"

echo -e "  ${DIM}Copying ${SRC} → ${DEST}${RESET}"
echo ""

# rsync preferred (progress + safety); falls back to cp
if command -v rsync &>/dev/null; then
    rsync -a --info=progress2 "${SRC}/" "${DEST}/"
else
    cp -av "${SRC}/." "${DEST}/"
fi

ok "Copy complete"

# ── Fix ownership ─────────────────────────────────────────────────────────────
section "Ownership"

# Match ownership to the AMP container user (uid 1000 by default)
PUID="${PUID:-1000}"
PGID="${PGID:-1000}"

echo -e "  ${DIM}Setting ownership to ${PUID}:${PGID}${RESET}"
sudo chown -R "${PUID}:${PGID}" "$DEST"
ok "Ownership set: ${PUID}:${PGID}"

# ── Summary ───────────────────────────────────────────────────────────────────
section "Done"

echo ""
ok "ampdata migrated to ${DEST}"
[ -d "$BACKUP" ] && echo -e "  ${DIM}Backup at: ${BACKUP}${RESET}"
echo ""
echo -e "  ${DIM}Next steps:${RESET}"
echo -e "  ${DIM}  1. Make sure AMP container is stopped: docker stop amp${RESET}"
echo -e "  ${DIM}  2. Start the stack: bash ~/Git/Gamestack/setup.sh${RESET}"
echo -e "  ${DIM}     or via the dashboard: bash ~/Git/Gamestack/gamestack${RESET}"
echo ""
