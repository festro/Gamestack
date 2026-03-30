#!/bin/bash
# GameStack Configuration Script
# Prompts for all placeholder values and applies them across the stack.
# Run once after cloning, before setup.sh.
#
# Usage: bash configure.sh
# Must be run from ~/Gamestack/

set -e
cd "$(dirname "$0")"

# ── Colours ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; DIM='\033[2m'; RESET='\033[0m'

# ── Helpers ───────────────────────────────────────────────────────────────────
ask() {
    # ask <var_name> <prompt> <default>
    local var="$1" prompt="$2" default="$3" val
    if [ -n "$default" ]; then
        printf "${CYAN}${prompt}${RESET} ${DIM}[${default}]${RESET}: "
    else
        printf "${CYAN}${prompt}${RESET}: "
    fi
    read -r val
    val="${val:-$default}"
    eval "$var='$val'"
}

ask_secret() {
    # ask_secret <var_name> <prompt>
    local var="$1" prompt="$2" val
    printf "${CYAN}${prompt}${RESET} ${DIM}(hidden)${RESET}: "
    read -rs val
    echo
    eval "$var='$val'"
}

ask_mac() {
    # Offer to auto-generate a MAC or let user supply one
    local var="$1"
    printf "${CYAN}AMP fixed MAC address${RESET} ${DIM}(Enter to auto-generate)${RESET}: "
    read -r val
    if [ -z "$val" ]; then
        val=$(printf '02:42:%02x:%02x:%02x:%02x' \
            $((RANDOM % 256)) $((RANDOM % 256)) \
            $((RANDOM % 256)) $((RANDOM % 256)))
        echo -e "  ${GREEN}Generated: ${val}${RESET}"
    fi
    eval "$var='$val'"
}

confirm() {
    printf "\n${YELLOW}$1${RESET} [y/N]: "
    read -r ans
    [[ "$ans" =~ ^[Yy]$ ]]
}

section() {
    echo -e "\n${BOLD}── $1 ──────────────────────────────────────────────${RESET}"
}

apply_sed() {
    # apply_sed <file> <old> <new>
    # Uses | as delimiter to avoid issues with / in paths and IPs
    local file="$1" old="$2" new="$3"
    # Escape special sed chars in old and new
    old_esc=$(printf '%s\n' "$old" | sed 's|[\\&|]|\\&|g')
    new_esc=$(printf '%s\n' "$new" | sed 's|[\\&|]|\\&|g')
    sed -i "s|${old_esc}|${new_esc}|g" "$file"
}

# ── Header ────────────────────────────────────────────────────────────────────
clear
echo -e "${BOLD}"
echo "  ╔═══════════════════════════════════════╗"
echo "  ║       GameStack Configuration         ║"
echo "  ╚═══════════════════════════════════════╝"
echo -e "${RESET}"
echo "  This script will ask for your network and credential"
echo "  values, then apply them across all config files."
echo ""
echo -e "  ${DIM}Press Enter to accept a default value shown in [brackets].${RESET}"
echo -e "  ${DIM}Leave network entries blank to skip (display-only fields).${RESET}"

# ── Section 1: Host ───────────────────────────────────────────────────────────
section "Host"

ask     TZ          "Timezone (TZ database format)" "America/Los_Angeles"
ask     DATA_DIR    "GameStack data directory (absolute path)" "~/Gamestack"
ask     USERNAME    "Your Linux username" ""
ask     HOSTNAME    "Your machine hostname" "$(hostname 2>/dev/null || echo 'gamestack-host')"
ask     NETWORK     "Your network / VPN name" "HomeNetwork"
ask     HOST_IP     "Host LAN IP (static)" ""

# ── Section 2: AMP ────────────────────────────────────────────────────────────
section "AMP Credentials"

echo -e "  ${DIM}Get these from your AMP portal at cubecoders.com${RESET}"
ask        AMP_USERNAME "AMP username" ""
ask_secret AMP_PASSWORD "AMP password"
ask_secret AMP_LICENCE  "AMP licence key"
ask_mac    AMP_MAC

# ── Section 3: Network (optional) ────────────────────────────────────────────
section "Network (display only — press Enter to skip any)"

echo -e "  ${DIM}These populate the portal's Network page and docs.${RESET}"
echo -e "  ${DIM}The stack runs fine without them.${RESET}"
ask PUBLIC_IP       "WAN / public IP" ""
ask DOMAIN          "Public domain (e.g. example.com)" ""
ask GAME_SUBDOMAIN  "Game server subdomain prefix" "game"
ask ROUTER_IP       "Router LAN IP" ""
ask UPSTREAM_IP     "Upstream router IP (if double-NAT, else leave blank)" ""
ask MODEM_IP        "ISP modem/gateway IP (if visible, else leave blank)" ""

# ── Section 4: Game Ports (optional) ─────────────────────────────────────────
section "Game Ports"

echo -e "  ${DIM}Set these to match the ports your game server uses in AMP.${RESET}"
ask GAME_PORT_1 "Game port 1" "9876"
ask GAME_PORT_2 "Game port 2 (query/secondary)" "9877"

# ── Preview ───────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}── Summary ─────────────────────────────────────────────${RESET}"
echo ""
printf "  %-22s %s\n" "Timezone:"       "$TZ"
printf "  %-22s %s\n" "Data dir:"       "$DATA_DIR"
printf "  %-22s %s\n" "Username:"       "${USERNAME:-(not set)}"
printf "  %-22s %s\n" "Hostname:"       "$HOSTNAME"
printf "  %-22s %s\n" "Network name:"   "$NETWORK"
printf "  %-22s %s\n" "Host LAN IP:"    "${HOST_IP:-(not set)}"
printf "  %-22s %s\n" "AMP username:"   "$AMP_USERNAME"
printf "  %-22s %s\n" "AMP password:"   "$([ -n "$AMP_PASSWORD" ] && echo '(set)' || echo '(not set)')"
printf "  %-22s %s\n" "AMP licence:"    "$([ -n "$AMP_LICENCE"  ] && echo '(set)' || echo '(not set)')"
printf "  %-22s %s\n" "AMP MAC:"        "$AMP_MAC"
printf "  %-22s %s\n" "Public IP:"      "${PUBLIC_IP:-(not set)}"
printf "  %-22s %s\n" "Domain:"         "${DOMAIN:-(not set)}"
printf "  %-22s %s\n" "Game subdomain:" "${GAME_SUBDOMAIN}.${DOMAIN:-(not set)}"
printf "  %-22s %s\n" "Router IP:"      "${ROUTER_IP:-(not set)}"
printf "  %-22s %s\n" "Game ports:"     "${GAME_PORT_1}/${GAME_PORT_2}"

echo ""
if ! confirm "Apply these values?"; then
    echo -e "\n${YELLOW}Aborted — no files changed.${RESET}\n"
    exit 0
fi

# ── Apply: .env ───────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}Applying...${RESET}"

cp .env.example .env

apply_sed .env "America/Los_Angeles"   "$TZ"
apply_sed .env "~/Gamestack"           "$DATA_DIR"
apply_sed .env "your_amp_username"     "$AMP_USERNAME"
apply_sed .env "your_amp_password"     "$AMP_PASSWORD"
apply_sed .env "your_amp_licence_key"  "$AMP_LICENCE"
apply_sed .env "02:42:xx:xx:xx:xx"     "$AMP_MAC"
apply_sed .env "9876"    "$GAME_PORT_1"
apply_sed .env "9877"    "$GAME_PORT_2"

echo -e "  ${GREEN}✓${RESET} .env"

# ── Apply: portal/html/index.html ─────────────────────────────────────────────
PORTAL="portal/html/index.html"

[ -n "$USERNAME"    ] && apply_sed "$PORTAL" "your-username"    "$USERNAME"
[ -n "$NETWORK"     ] && apply_sed "$PORTAL" "YourNetwork"      "$NETWORK"
[ -n "$HOSTNAME"    ] && apply_sed "$PORTAL" "your-hostname"    "$HOSTNAME"
[ -n "$HOST_IP"     ] && apply_sed "$PORTAL" "YOUR_HOST_IP"     "$HOST_IP"
[ -n "$PUBLIC_IP"   ] && apply_sed "$PORTAL" "YOUR_PUBLIC_IP"   "$PUBLIC_IP"
[ -n "$ROUTER_IP"   ] && apply_sed "$PORTAL" "YOUR_ROUTER_IP"   "$ROUTER_IP"
[ -n "$UPSTREAM_IP" ] && apply_sed "$PORTAL" "YOUR_UPSTREAM_ROUTER_IP" "$UPSTREAM_IP"
[ -n "$MODEM_IP"    ] && apply_sed "$PORTAL" "YOUR_MODEM_IP"    "$MODEM_IP"

if [ -n "$DOMAIN" ]; then
    GAME_DOMAIN="${GAME_SUBDOMAIN}.${DOMAIN}"
    apply_sed "$PORTAL" "game.yourdomain.com"  "$GAME_DOMAIN"
    apply_sed "$PORTAL" "yourdomain.com"       "$DOMAIN"
fi

echo -e "  ${GREEN}✓${RESET} portal/html/index.html"

# ── Apply: output/GameStack.html (docs) ──────────────────────────────────────
DOCS="output/GameStack.html"
if [ -f "$DOCS" ]; then
    [ -n "$USERNAME"    ] && apply_sed "$DOCS" "your-username"    "$USERNAME"
    [ -n "$NETWORK"     ] && apply_sed "$DOCS" "YourNetwork"      "$NETWORK"
    [ -n "$HOSTNAME"    ] && apply_sed "$DOCS" "your-hostname"    "$HOSTNAME"
    [ -n "$HOST_IP"     ] && apply_sed "$DOCS" "YOUR_HOST_IP"     "$HOST_IP"
    [ -n "$PUBLIC_IP"   ] && apply_sed "$DOCS" "YOUR_PUBLIC_IP"   "$PUBLIC_IP"
    [ -n "$ROUTER_IP"   ] && apply_sed "$DOCS" "YOUR_ROUTER_IP"   "$ROUTER_IP"
    [ -n "$UPSTREAM_IP" ] && apply_sed "$DOCS" "YOUR_UPSTREAM_ROUTER_IP" "$UPSTREAM_IP"
    [ -n "$MODEM_IP"    ] && apply_sed "$DOCS" "YOUR_MODEM_IP"    "$MODEM_IP"
    if [ -n "$DOMAIN" ]; then
        apply_sed "$DOCS" "game.yourdomain.com"  "$GAME_DOMAIN"
        apply_sed "$DOCS" "yourdomain.com"       "$DOMAIN"
    fi
    echo -e "  ${GREEN}✓${RESET} output/GameStack.html"
fi

# ── Done ──────────────────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}${BOLD}Configuration applied.${RESET}"
echo ""
echo "  Next step:"
echo -e "  ${BOLD}bash setup.sh${RESET}"
echo ""

# ── Optional: warn about any remaining placeholders ──────────────────────────
REMAINING=$(grep -rl \
    "YOUR_HOST_IP\|YOUR_PUBLIC_IP\|YOUR_ROUTER_IP\|YOUR_UPSTREAM_ROUTER_IP\|YOUR_MODEM_IP\|your-username\|YourNetwork\|your-hostname\|yourdomain\.com\|your_amp_username\|your_amp_password\|your_amp_licence\|02:42:xx" \
    .env portal/html/index.html output/GameStack.html 2>/dev/null || true)

if [ -n "$REMAINING" ]; then
    echo -e "  ${YELLOW}Note: some placeholders remain (skipped or not provided):${RESET}"
    grep -n \
        "YOUR_HOST_IP\|YOUR_PUBLIC_IP\|YOUR_ROUTER_IP\|YOUR_UPSTREAM_ROUTER_IP\|YOUR_MODEM_IP\|your-username\|YourNetwork\|your-hostname\|yourdomain\.com\|your_amp_username\|your_amp_password\|your_amp_licence\|02:42:xx" \
        .env portal/html/index.html output/GameStack.html 2>/dev/null \
        | sed 's/^/    /' | head -20
fi
echo ""
