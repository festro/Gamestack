#!/bin/bash
# GameStack Quick Setup Wizard
# Guides you through AMP account setup, credentials, network config,
# then runs configure.sh and optionally setup.sh.
# Can be run standalone or via the gamestack launcher.

cd "$(dirname "$0")"

# ── Colours ───────────────────────────────────────────────────────────────────
R='\033[0;31m' G='\033[0;32m' Y='\033[1;33m'
B='\033[0;34m' C='\033[0;36m' BOLD='\033[1m' DIM='\033[2m' RESET='\033[0m'

# ── Helpers ───────────────────────────────────────────────────────────────────
step_header() {
    local num="$1" total="$2" title="$3"
    echo ""
    echo -e "  ${DIM}────────────────────────────────────────────────${RESET}"
    echo -e "  ${BOLD}Step ${num} of ${total} — ${title}${RESET}"
    echo -e "  ${DIM}────────────────────────────────────────────────${RESET}"
    echo ""
}

info() { echo -e "  ${DIM}$1${RESET}"; }
ok()   { echo -e "  ${G}✓${RESET}  $1"; }
warn() { echo -e "  ${Y}!${RESET}  $1"; }
err()  { echo -e "  ${R}✗${RESET}  $1"; }

ask() {
    local var="$1" prompt="$2" default="$3" val
    if [ -n "$default" ]; then
        printf "  ${C}${prompt}${RESET} ${DIM}[${default}]${RESET}: "
    else
        printf "  ${C}${prompt}${RESET}: "
    fi
    read -r val
    eval "$var='${val:-$default}'"
}

ask_secret() {
    local var="$1" prompt="$2" val
    printf "  ${C}${prompt}${RESET} ${DIM}(hidden)${RESET}: "
    read -rs val
    echo ""
    eval "$var='$val'"
}

ask_mac() {
    printf "  ${C}AMP fixed MAC address${RESET} ${DIM}(Enter to auto-generate)${RESET}: "
    read -r AMP_MAC
    if [ -z "$AMP_MAC" ]; then
        AMP_MAC=$(printf '02:42:%02x:%02x:%02x:%02x' \
            $((RANDOM%256)) $((RANDOM%256)) $((RANDOM%256)) $((RANDOM%256)))
        ok "Generated MAC: ${BOLD}${AMP_MAC}${RESET}"
    fi
}

pause() {
    echo ""
    printf "  ${DIM}Press Enter to continue...${RESET}"
    read -r
}

is_remote_session() {
    [ -n "$SSH_CLIENT" ] || [ -n "$SSH_TTY" ] || [ -n "$SSH_CONNECTION" ]
}

open_url() {
    local url="$1"
    is_remote_session && return  # Skip silently on headless/SSH
    if   command -v xdg-open &>/dev/null; then xdg-open "$url" &>/dev/null &
    elif command -v wslview  &>/dev/null; then wslview  "$url" &>/dev/null &
    elif command -v open     &>/dev/null; then open     "$url" &>/dev/null &
    fi
}

confirm() {
    printf "\n  ${Y}$1${RESET} [y/N]: "
    read -r ans
    [[ "$ans" =~ ^[Yy]$ ]]
}

skip() {
    printf "  ${DIM}Skip this section?${RESET} [y/N]: "
    read -r ans
    [[ "$ans" =~ ^[Yy]$ ]]
}

apply_sed() {
    local file="$1" old="$2" new="$3"
    local old_esc new_esc
    old_esc=$(printf '%s\n' "$old" | sed 's|[\\&|]|\\&|g')
    new_esc=$(printf '%s\n' "$new" | sed 's|[\\&|]|\\&|g')
    sed -i "s|${old_esc}|${new_esc}|g" "$file"
}

# ── Banner ────────────────────────────────────────────────────────────────────
clear
echo -e "${BOLD}"
echo "  ╔══════════════════════════════════════════╗"
echo "  ║       GameStack Quick Setup              ║"
echo "  ╚══════════════════════════════════════════╝"
echo -e "${RESET}"
echo -e "  This wizard will walk you through:"
echo ""
echo -e "  ${DIM}  1.  AMP account & licensing"
echo -e "      2.  AMP credentials"
echo -e "      3.  Host & network details"
echo -e "      4.  Apply config + start stack${RESET}"
echo ""
info "All values are written to .env and your portal/docs."
info "You can re-run this wizard any time to update them."
pause

# ══════════════════════════════════════════════════════════════════════════════
# STEP 1 — AMP Account
# ══════════════════════════════════════════════════════════════════════════════
step_header 1 4 "AMP account & licensing"

echo -e "  AMP (Application Management Panel) is the game server"
echo -e "  management panel used by GameStack."
echo ""
echo -e "  You need a free account at ${C}cubecoders.com${RESET} and a licence key."
echo ""

printf "  ${DIM}Do you already have an AMP account and licence key?${RESET} [y/N]: "
read -r HAS_ACCOUNT

if [[ ! "$HAS_ACCOUNT" =~ ^[Yy]$ ]]; then
    echo ""
    echo -e "  ${BOLD}To get an AMP account:${RESET}"
    echo ""
    echo -e "  ${DIM}  1.  Go to https://cubecoders.com/${RESET}"
    echo -e "  ${DIM}  2.  Create a free account${RESET}"
    echo -e "  ${DIM}  3.  In your account dashboard, go to Licences${RESET}"
    echo -e "  ${DIM}  4.  Generate a new licence — a free Community licence is fine${RESET}"
    echo -e "  ${DIM}  5.  Copy the licence key (format: XXXX-XXXX-XXXX-XXXX)${RESET}"
    echo ""
    if is_remote_session; then
        echo -e "  ${Y}Remote session — open this URL on your local machine:${RESET}"
        echo -e "  ${C}https://cubecoders.com/${RESET}"
    else
        printf "  ${Y}Opening cubecoders.com in your browser...${RESET}"
        open_url "https://cubecoders.com/"
        echo ""
    fi
    echo ""
    info "Come back here once you have your account and licence key."
    pause
fi

ok "AMP account ready"

# ══════════════════════════════════════════════════════════════════════════════
# STEP 2 — AMP Credentials
# ══════════════════════════════════════════════════════════════════════════════
step_header 2 4 "AMP credentials"

echo -e "  These are the credentials AMP will use for its web panel."
echo -e "  Choose a strong password — the panel will be accessible on your LAN."
echo ""

ask        AMP_USERNAME "AMP panel username" ""
ask_secret AMP_PASSWORD "AMP panel password"
ask_secret AMP_LICENCE  "AMP licence key"
echo ""
ask_mac

# ══════════════════════════════════════════════════════════════════════════════
# STEP 3 — Host & Network
# ══════════════════════════════════════════════════════════════════════════════
step_header 3 4 "Host & network details"

echo -e "  These populate the portal's network page and docs."
echo -e "  All entries are optional — press Enter to skip any."
echo ""

# Auto-detect host IP as a default
DETECTED_IP=$(ip route get 1.1.1.1 2>/dev/null | awk '/src/{for(i=1;i<=NF;i++) if($i=="src") print $(i+1); exit}')
DETECTED_HOST=$(hostname 2>/dev/null || echo "gamestack-host")

ask TZ       "Timezone (TZ format)"      "America/Los_Angeles"
ask DATA_DIR "GameStack data directory"  "~/Gamestack"
ask USERNAME "Your Linux username"       "$(whoami 2>/dev/null || echo '')"
ask HOSTNAME_VAL "Machine hostname"      "$DETECTED_HOST"
ask NETWORK  "Network / VPN name"        "HomeNetwork"
ask HOST_IP  "Host LAN IP"               "$DETECTED_IP"

echo ""
info "WAN / DNS details (skip if you don't have a public domain yet):"
echo ""

ask PUBLIC_IP      "Public WAN IP"                     ""
ask DOMAIN         "Public domain (e.g. example.com)"  ""
ask GAME_SUBDOMAIN "Game server subdomain prefix"      "game"
ask ROUTER_IP      "Router LAN IP"                     ""
ask UPSTREAM_IP    "Upstream router IP (if double-NAT, else leave blank)" ""
ask MODEM_IP       "ISP modem/gateway IP (if visible, else leave blank)"  ""
ask GAME_PORT_1    "Game server port 1"                "9876"
ask GAME_PORT_2    "Game server port 2 (query/RCON)"   "9877"

# ══════════════════════════════════════════════════════════════════════════════
# STEP 4 — Apply & Start
# ══════════════════════════════════════════════════════════════════════════════
step_header 4 4 "Apply config & start stack"

echo -e "  ${BOLD}Summary${RESET}"
echo ""
printf "  %-24s %s\n" "Timezone:"         "$TZ"
printf "  %-24s %s\n" "Data directory:"   "$DATA_DIR"
printf "  %-24s %s\n" "Username:"         "${USERNAME:-(not set)}"
printf "  %-24s %s\n" "Hostname:"         "$HOSTNAME_VAL"
printf "  %-24s %s\n" "Network:"          "$NETWORK"
printf "  %-24s %s\n" "Host LAN IP:"      "${HOST_IP:-(not set)}"
printf "  %-24s %s\n" "AMP username:"     "$AMP_USERNAME"
printf "  %-24s %s\n" "AMP password:"     "$([ -n "$AMP_PASSWORD" ] && echo '(set)' || echo '(not set)')"
printf "  %-24s %s\n" "AMP licence:"      "$([ -n "$AMP_LICENCE"  ] && echo '(set)' || echo '(not set)')"
printf "  %-24s %s\n" "AMP MAC:"          "$AMP_MAC"
printf "  %-24s %s\n" "Public IP:"        "${PUBLIC_IP:-(not set)}"
printf "  %-24s %s\n" "Domain:"           "${DOMAIN:-(not set)}"
printf "  %-24s %s\n" "Game ports:"       "${GAME_PORT_1} / ${GAME_PORT_2}"

if ! confirm "Apply these values?"; then
    echo ""
    warn "Aborted — no files changed."
    echo ""
    exit 0
fi

echo ""
echo -e "  ${BOLD}Applying...${RESET}"
echo ""

# ── Write .env ────────────────────────────────────────────────────────────────
cp .env.example .env

apply_sed .env "America/Los_Angeles"  "$TZ"
apply_sed .env "~/Gamestack"          "$DATA_DIR"
apply_sed .env "your_amp_username"    "$AMP_USERNAME"
apply_sed .env "your_amp_password"    "$AMP_PASSWORD"
apply_sed .env "your_amp_licence_key" "$AMP_LICENCE"
apply_sed .env "02:42:xx:xx:xx:xx"    "$AMP_MAC"
apply_sed .env "9876"                 "$GAME_PORT_1"
apply_sed .env "9877"                 "$GAME_PORT_2"
ok ".env written"

# ── Apply portal HTML ─────────────────────────────────────────────────────────
PORTAL="portal/html/index.html"
DOCS="output/GameStack.html"

for target in "$PORTAL" "$DOCS"; do
    [ -f "$target" ] || continue
    [ -n "$USERNAME"     ] && apply_sed "$target" "your-username"           "$USERNAME"
    [ -n "$NETWORK"      ] && apply_sed "$target" "YourNetwork"             "$NETWORK"
    [ -n "$HOSTNAME_VAL" ] && apply_sed "$target" "your-hostname"           "$HOSTNAME_VAL"
    [ -n "$HOST_IP"      ] && apply_sed "$target" "YOUR_HOST_IP"            "$HOST_IP"
    [ -n "$PUBLIC_IP"    ] && apply_sed "$target" "YOUR_PUBLIC_IP"          "$PUBLIC_IP"
    [ -n "$ROUTER_IP"    ] && apply_sed "$target" "YOUR_ROUTER_IP"          "$ROUTER_IP"
    [ -n "$UPSTREAM_IP"  ] && apply_sed "$target" "YOUR_UPSTREAM_ROUTER_IP" "$UPSTREAM_IP"
    [ -n "$MODEM_IP"     ] && apply_sed "$target" "YOUR_MODEM_IP"           "$MODEM_IP"
    if [ -n "$DOMAIN" ]; then
        GAME_DOMAIN="${GAME_SUBDOMAIN}.${DOMAIN}"
        apply_sed "$target" "game.yourdomain.com" "$GAME_DOMAIN"
        apply_sed "$target" "yourdomain.com"      "$DOMAIN"
    fi
done
ok "portal/html/index.html updated"
ok "output/GameStack.html updated"

# ── Run setup.sh ──────────────────────────────────────────────────────────────
echo ""
if confirm "Run setup.sh now to start the stack?"; then
    echo ""
    bash setup.sh
else
    echo ""
    info "Skipped. Run 'bash setup.sh' when you're ready."
fi

# ── Done ──────────────────────────────────────────────────────────────────────
echo ""
echo -e "  ${G}${BOLD}Quick setup complete.${RESET}"
echo ""

HOST_DISPLAY="${HOST_IP:-$(ip route get 1.1.1.1 2>/dev/null | awk '/src/{for(i=1;i<=NF;i++) if($i=="src") print $(i+1); exit}')}"
echo -e "  Portal: ${C}http://${HOST_DISPLAY}/${RESET}"
echo ""

# Warn about remaining placeholders
REMAINING=$(grep -rl \
    "YOUR_HOST_IP\|YOUR_PUBLIC_IP\|YOUR_ROUTER_IP\|YOUR_UPSTREAM_ROUTER_IP\|YOUR_MODEM_IP\|your-username\|YourNetwork\|your-hostname\|yourdomain\.com\|your_amp_username\|02:42:xx" \
    .env portal/html/index.html output/GameStack.html 2>/dev/null || true)

if [ -n "$REMAINING" ]; then
    warn "Some placeholders remain (fields you skipped)."
    info "Re-run this wizard or edit the files directly to fill them in."
    info "See SETUP_CHECKLIST.md for exact file locations."
fi

echo ""
