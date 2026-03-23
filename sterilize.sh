#!/bin/bash
# GameStack Sterilize Script
# Unconditionally overwrites all personal/network values with placeholders
# across all tracked files, making the repo safe to commit.
# No .env required — every field is simply reset to its default placeholder.
#
# Usage:
#   bash sterilize.sh           — apply all replacements
#   bash sterilize.sh --check   — dry run, show what would change
#
# Run from ~/Git/Gamestack/ — operates only within the current directory.

set -e

# ── Args ──────────────────────────────────────────────────────────────────────
DRY_RUN=false
for arg in "$@"; do
    case "$arg" in
        --check) DRY_RUN=true ;;
    esac
done

# ── Colours ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; DIM='\033[2m'; RESET='\033[0m'

ok()      { echo -e "  ${GREEN}✓${RESET}  $1"; }
warn()    { echo -e "  ${YELLOW}!${RESET}  $1"; }
info()    { echo -e "  ${DIM}$1${RESET}"; }
section() { echo -e "\n${BOLD}── $1 ──────────────────────────────────────────────${RESET}"; }

# ── Files ─────────────────────────────────────────────────────────────────────
# sterilize.sh excluded — must never rewrite its own sed expressions
# output/GameStack.html excluded — gitignored
FILES=(
    ".env.example"
    "docker-compose.yml"
    "portal/html/index.html"
    "portal/nginx/default.conf"
    "build.js"
    "configure.sh"
    "quicksetup.sh"
    "setup.sh"
    "gamestack"
    "preflight.sh"
    "README.md"
    "SETUP_CHECKLIST.md"
)

# ── Replacement sets ──────────────────────────────────────────────────────────

ENV_EXPRS=(
    's|^\(TZ=\).*|\1America/Los_Angeles|'
    's|^\(DATA_DIR=\).*|\1~/Gamestack|'
    's|^\(AMP_USERNAME=\).*|\1your_amp_username|'
    's|^\(USERNAME=\).*|\1your_amp_username|'
    's|^\(AMP_PASSWORD=\).*|\1your_amp_password|'
    's|^\(PASSWORD=\).*|\1your_amp_password|'
    's|^\(LICENCE=\).*|\1your_amp_licence_key|'
    's|^\(AMP_LICENCE=\).*|\1your_amp_licence_key|'
    's|^\(AMP_MAC=\).*|\102:42:xx:xx:xx:xx|'
    's|^\(VRISING_GAME_PORT=\).*|\19876|'
    's|^\(VRISING_QUERY_PORT=\).*|\19877|'
    's|^\(HOST_IP=\).*|\1YOUR_HOST_IP|'
    's|^\(PUBLIC_IP=\).*|\1YOUR_PUBLIC_IP|'
    's|^\(ROUTER_IP=\).*|\1YOUR_ROUTER_IP|'
    's|^\(UPSTREAM_IP=\).*|\1YOUR_UPSTREAM_ROUTER_IP|'
    's|^\(DOMAIN=\).*|\1yourdomain.com|'
    's|^\(GAME_SUBDOMAIN=\).*|\1game|'
)

PORTAL_EXPRS=(
    's|[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}:8080|YOUR_HOST_IP:8080|g'
    's|[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}:47989|YOUR_HOST_IP:47989|g'
    's|[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}:8088|YOUR_HOST_IP:8088|g'
    's|[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}:8089|YOUR_HOST_IP:8089|g'
    's|[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}:47990|YOUR_HOST_IP:47990|g'
    's|192\.168\.[0-9]\{1,3\}\.[0-9]\{1,3\}|YOUR_HOST_IP|g'
    's|76\.[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}|YOUR_PUBLIC_IP|g'
    's|play\.layonet\.org|game.yourdomain.com|g'
    's|layonet\.org|yourdomain.com|g'
    's|festro33|your-username|g'
    's|Daemonic-nucbox|your-hostname|g'
)

BUILD_EXPRS=(
    's|192\.168\.[0-9]\{1,3\}\.[0-9]\{1,3\}|YOUR_HOST_IP|g'
    's|76\.[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}|YOUR_PUBLIC_IP|g'
    's|festro33|your-username|g'
    's|Daemonic-nucbox|your-hostname|g'
    's|play\.layonet\.org|game.yourdomain.com|g'
    's|layonet\.org|yourdomain.com|g'
)

USER_EXPRS=(
    's|festro33|your-username|g'
    's|Daemonic-nucbox|your-hostname|g'
    's|play\.layonet\.org|game.yourdomain.com|g'
    's|layonet\.org|yourdomain.com|g'
)

CHECKLIST_EXPRS=(
    's|HOST_IP=192\.[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}|HOST_IP=YOUR_HOST_IP|g'
    's|ROUTER_IP=192\.[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}|ROUTER_IP=YOUR_ROUTER_IP|g'
    's|festro33|your-username|g'
    's|Daemonic-nucbox|your-hostname|g'
    's|play\.layonet\.org|game.yourdomain.com|g'
    's|layonet\.org|yourdomain.com|g'
)

# ── Simulate: apply all exprs to a string, return result ──────────────────────
simulate() {
    # simulate <content> <expr...>
    local content="$1"; shift
    for expr in "$@"; do
        content=$(printf '%s\n' "$content" | sed "$expr")
    done
    printf '%s\n' "$content"
}

# ── Per-file expr map — returns exprs for a given file ────────────────────────
get_exprs_for() {
    local file="$1"
    case "$file" in
        .env.example)              printf '%s\n' "${ENV_EXPRS[@]}" ;;
        portal/html/index.html)    printf '%s\n' "${PORTAL_EXPRS[@]}" ;;
        build.js)                  printf '%s\n' "${BUILD_EXPRS[@]}" ;;
        SETUP_CHECKLIST.md)        printf '%s\n' "${CHECKLIST_EXPRS[@]}" ;;
        *)                         printf '%s\n' "${USER_EXPRS[@]}" ;;
    esac
}

# ── Core apply function ───────────────────────────────────────────────────────
apply() {
    local file="$1"; shift
    [ -f "$file" ] || { info "skipping (not found): $file"; return; }

    local original current
    original=$(cat "$file")
    current=$(simulate "$original" "$@")

    if [ "$DRY_RUN" = true ]; then
        if [ "$current" != "$original" ]; then
            echo -e "  ${CYAN}would change${RESET} $file"
            diff <(echo "$original") <(echo "$current") \
                | grep '^[<>]' | head -20 | sed 's/^/    /'
        else
            info "no changes: $file"
        fi
    else
        printf '%s\n' "$current" > "$file"
        ok "$file"
    fi
}

# ── Banner ────────────────────────────────────────────────────────────────────
clear
echo -e "${BOLD}"
echo "  ╔═══════════════════════════════════════╗"
echo "  ║       GameStack Sterilize             ║"
echo "  ╚═══════════════════════════════════════╝"
echo -e "${RESET}"
echo "  Resets all personal/network values to placeholders."
echo "  Working directory: $(pwd)"
echo ""
[ "$DRY_RUN" = true ] && echo -e "  ${YELLOW}Dry run — no files will be modified.${RESET}\n"

if [ "$DRY_RUN" = false ]; then
    printf "  ${YELLOW}This will overwrite values in tracked files. Continue?${RESET} [y/N]: "
    read -r ans
    [[ "$ans" =~ ^[Yy]$ ]] || { echo -e "\n  ${YELLOW}Aborted.${RESET}\n"; exit 0; }
fi

# ── Apply ─────────────────────────────────────────────────────────────────────
section "Sterilizing"

apply ".env.example"               "${ENV_EXPRS[@]}"
apply "docker-compose.yml"         "${USER_EXPRS[@]}"
apply "portal/html/index.html"     "${PORTAL_EXPRS[@]}"
apply "portal/nginx/default.conf"  "${USER_EXPRS[@]}"
apply "build.js"                   "${BUILD_EXPRS[@]}"
apply "configure.sh"               "${USER_EXPRS[@]}"
apply "quicksetup.sh"              "${USER_EXPRS[@]}"
apply "setup.sh"                   "${USER_EXPRS[@]}"
apply "gamestack"                  "${USER_EXPRS[@]}"
apply "preflight.sh"               "${USER_EXPRS[@]}"
apply "README.md"                  "${USER_EXPRS[@]}"
apply "SETUP_CHECKLIST.md"         "${CHECKLIST_EXPRS[@]}"

# ── Verification ──────────────────────────────────────────────────────────────
# In dry-run mode, verify against the simulated post-replacement content.
# In apply mode, verify the actual files on disk.
section "Verification"

check_content() {
    local file="$1" content="$2"
    local found=0

    # Bare IPs — skip known-safe and doc-example patterns
    hits=$(echo "$content" \
        | grep -nE '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' \
        | grep -vE '(YOUR_|your_|127\.0\.0\.|1\.1\.1\.1|1\.0\.0\.1|0\.0\.0\.0)' \
        | grep -vE '(x\.[0-9]|[0-9]\.x|\bx\b|1\.2\.3\.4)' \
        || true)
    if [ -n "$hits" ]; then
        warn "Possible live IP in: $file"
        echo "$hits" | sed 's/^/    /'
        found=1
    fi

    # Real MACs
    mac_hits=$(echo "$content" \
        | grep -nE '([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}' \
        | grep -v '02:42:xx' || true)
    if [ -n "$mac_hits" ]; then
        warn "Possible real MAC in: $file"
        echo "$mac_hits" | sed 's/^/    /'
        found=1
    fi

    # Personal username
    if echo "$content" | grep -q 'festro33'; then
        warn "Username 'festro33' still in: $file"
        echo "$content" | grep -n 'festro33' | sed 's/^/    /'
        found=1
    fi

    # Personal domain
    if echo "$content" | grep -qE 'layonet\.org'; then
        warn "Personal domain still in: $file"
        echo "$content" | grep -nE 'layonet\.org' | sed 's/^/    /'
        found=1
    fi

    return $found
}

FOUND=0
for f in "${FILES[@]}"; do
    [ -f "$f" ] || continue
    mapfile -t exprs < <(get_exprs_for "$f")
    if [ "$DRY_RUN" = true ]; then
        content=$(simulate "$(cat "$f")" "${exprs[@]}")
    else
        content=$(cat "$f")
    fi
    check_content "$f" "$content" || FOUND=1
done

[ "$FOUND" -eq 0 ] && ok "All clear — no personal values detected in tracked files"

# ── Done ──────────────────────────────────────────────────────────────────────
echo ""
if [ "$DRY_RUN" = true ]; then
    echo -e "  ${YELLOW}Dry run complete — no files modified.${RESET}"
    echo ""
    echo "  Run without --check to apply:"
    echo -e "  ${BOLD}bash sterilize.sh${RESET}"
else
    echo -e "  ${GREEN}${BOLD}Sterilization complete.${RESET}"
    echo ""
    echo "  Safe to commit:"
    echo -e "  ${BOLD}git add -A && git commit -m 'v1.2 initial'${RESET}"
fi
echo ""
