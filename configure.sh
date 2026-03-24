#!/bin/bash
# GameStack Configure
# Phase 1: Preflight  — system/hardware/dependency checks, logs verbose output
# Phase 2: Wizard     — hand-held configuration with validation
# Phase 3: Apply      — writes .env, updates portal files
#
# Usage:
#   bash configure.sh                — full run
#   bash configure.sh --preflight-only  — system check only
#   bash configure.sh --config-only     — skip preflight
#   bash configure.sh --auto            — auto-install missing packages
#
# Run from your Gamestack directory.

set -e

# ── Args ──────────────────────────────────────────────────────────────────────
PREFLIGHT_ONLY=false
CONFIG_ONLY=false
AUTO_INSTALL=false

for arg in "$@"; do
    case "$arg" in
        --preflight-only) PREFLIGHT_ONLY=true ;;
        --config-only)    CONFIG_ONLY=true ;;
        --auto)           AUTO_INSTALL=true ;;
    esac
done

# ── Colours ───────────────────────────────────────────────────────────────────
R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'
C='\033[0;36m'; BOLD='\033[1m'; DIM='\033[2m'; RESET='\033[0m'

ok()      { echo -e "  ${G}✓${RESET}  $1"; }
fail()    { echo -e "  ${R}✗${RESET}  $1"; }
warn()    { echo -e "  ${Y}!${RESET}  $1"; }
info()    { echo -e "  ${DIM}    $1${RESET}"; }
section() { echo -e "\n${BOLD}── $1 ──────────────────────────────────────────────${RESET}"; }
gap()     { echo ""; }

pause() {
    gap
    printf "  ${DIM}Press Enter to continue...${RESET}"
    read -r
}

confirm() {
    local prompt="$1" ans
    printf "\n  ${Y}${prompt}${RESET} [y/N]: "
    read -rt 0.1 discard 2>/dev/null || true  # drain leftover newline from prior read -rsn1
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

# ── Logging ───────────────────────────────────────────────────────────────────
# Logs go to ./logs/ before DATA_DIR is known, moved later if needed
LOG_DIR="./logs"
mkdir -p "$LOG_DIR"
LOG_FILE="${LOG_DIR}/preflight-$(date +%Y%m%d-%H%M%S).log"
echo "GameStack Preflight Log — $(date)" > "$LOG_FILE"

log()  { echo "$1" >> "$LOG_FILE"; }
logok(){ echo "[OK]   $1" >> "$LOG_FILE"; }
logw() { echo "[WARN] $1" >> "$LOG_FILE"; }
loge() { echo "[ERR]  $1" >> "$LOG_FILE"; }

# ── Result tracking ───────────────────────────────────────────────────────────
ERRORS=()
WARNINGS=()
TO_INSTALL=()

# ══════════════════════════════════════════════════════════════════════════════
# PHASE 1 — PREFLIGHT
# ══════════════════════════════════════════════════════════════════════════════

run_preflight() {

    log ""
    log "=== SYSTEM ==="

    # ── Architecture ──────────────────────────────────────────────────────────
    ARCH=$(uname -m)
    case "$ARCH" in
        x86_64)  ARCH_LABEL="x86_64 (64-bit Intel/AMD)" ;;
        aarch64) ARCH_LABEL="aarch64 (64-bit ARM)" ;;
        armv7l)  ARCH_LABEL="armv7l (32-bit ARM)" ;;
        *)       ARCH_LABEL="$ARCH (unknown)" ;;
    esac
    logok "Architecture: ${ARCH_LABEL}"
    logok "Kernel: $(uname -r)"

    # ── Distro ────────────────────────────────────────────────────────────────
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        DISTRO_ID="${ID}"
        DISTRO_NAME="${PRETTY_NAME}"
        logok "Distro: ${DISTRO_NAME}"
    else
        DISTRO_ID="unknown"
        DISTRO_NAME="Unknown Linux"
        logw "Could not detect distro — /etc/os-release not found"
        warn "Could not detect Linux distro"
    fi

    # ── Package manager ───────────────────────────────────────────────────────
    case "$DISTRO_ID" in
        ubuntu|debian|linuxmint|pop|neon|kali|raspbian)
            PKG_MGR="apt"; PKG_INSTALL="apt-get install -y"; PKG_UPDATE="apt-get update" ;;
        fedora|rhel|centos|rocky|almalinux)
            PKG_MGR="dnf"; PKG_INSTALL="dnf install -y"; PKG_UPDATE="dnf check-update || true" ;;
        arch|manjaro|endeavouros|garuda)
            PKG_MGR="pacman"; PKG_INSTALL="pacman -S --noconfirm"; PKG_UPDATE="pacman -Sy" ;;
        opensuse*|sles)
            PKG_MGR="zypper"; PKG_INSTALL="zypper install -y"; PKG_UPDATE="zypper refresh" ;;
        *)
            PKG_MGR="unknown"
            logw "Unknown package manager for distro: ${DISTRO_ID}"
            warn "Unknown package manager — manual dependency install may be required" ;;
    esac
    logok "Package manager: ${PKG_MGR}"

    # ── GPU ───────────────────────────────────────────────────────────────────
    log ""
    log "=== GPU ==="
    GPU_VENDOR="none"
    GPU_LABEL="No GPU detected"

    if lspci 2>/dev/null | grep -qi "AMD\|ATI\|Radeon"; then
        GPU_VENDOR="amd"
        GPU_LABEL=$(lspci 2>/dev/null | grep -i "AMD\|ATI\|Radeon\|VGA\|Display" | head -1 | sed 's/.*: //')
        logok "GPU: AMD — ${GPU_LABEL}"
    elif lspci 2>/dev/null | grep -qi "NVIDIA"; then
        GPU_VENDOR="nvidia"
        GPU_LABEL=$(lspci 2>/dev/null | grep -i "NVIDIA\|VGA\|Display" | head -1 | sed 's/.*: //')
        logok "GPU: NVIDIA — ${GPU_LABEL}"
    elif lspci 2>/dev/null | grep -qi "Intel.*Graphics\|Intel.*VGA\|Intel.*Display"; then
        GPU_VENDOR="intel"
        GPU_LABEL=$(lspci 2>/dev/null | grep -i "Intel.*Graphics\|Intel.*VGA\|Intel.*Display" | head -1 | sed 's/.*: //')
        logok "GPU: Intel — ${GPU_LABEL}"
    elif ls /dev/dri/renderD* &>/dev/null; then
        GPU_VENDOR="drm"
        GPU_LABEL="DRM device (vendor unknown)"
        logw "GPU: DRM device found but vendor undetected — VA-API may still work"
        warn "GPU vendor undetected — VA-API may still work. Check log: ${LOG_FILE}"
    else
        logw "No GPU detected — Wolf will use software encoding"
        warn "No GPU detected — Wolf will fall back to software encoding (higher CPU load)"
        WARNINGS+=("No GPU detected")
    fi

    # VA-API check (AMD/Intel)
    if [ "$GPU_VENDOR" = "amd" ] || [ "$GPU_VENDOR" = "intel" ]; then
        if command -v vainfo &>/dev/null; then
            VAINFO=$(vainfo 2>/dev/null | grep "VAProfile" | wc -l)
            if [ "$VAINFO" -gt 0 ]; then
                logok "VA-API: ${VAINFO} profiles available"
            else
                logw "VA-API: vainfo found but no profiles reported"
                warn "VA-API: no profiles reported — check GPU driver. Log: ${LOG_FILE}"
                WARNINGS+=("VA-API profiles not found")
            fi
        else
            logw "VA-API: vainfo not installed"
            TO_INSTALL+=("vainfo")
        fi
    fi

    # NVIDIA
    if [ "$GPU_VENDOR" = "nvidia" ]; then
        if command -v nvidia-smi &>/dev/null; then
            NVIDIA_VER=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null | head -1)
            logok "NVIDIA driver: ${NVIDIA_VER}"
        else
            loge "NVIDIA GPU detected but nvidia-smi not found"
            fail "NVIDIA driver not installed"
            ERRORS+=("NVIDIA driver missing — install from https://www.nvidia.com/drivers or your package manager")
        fi
        if ! docker info 2>/dev/null | grep -qi "nvidia"; then
            logw "NVIDIA Container Toolkit not detected"
            warn "NVIDIA Container Toolkit not detected — required for Wolf GPU passthrough"
            WARNINGS+=("NVIDIA Container Toolkit missing")
        else
            logok "NVIDIA Container Toolkit: present"
        fi
    fi

    # ── GPU driver packages ───────────────────────────────────────────────────
    case "$GPU_VENDOR" in
        amd)
            case "$PKG_MGR" in
                apt)    VAAPI_PKG="mesa-va-drivers libva-drm2 libva2" ;;
                dnf)    VAAPI_PKG="mesa-va-drivers libva libva-utils" ;;
                pacman) VAAPI_PKG="mesa libva libva-utils" ;;
                zypper) VAAPI_PKG="Mesa-dri libva2 libva-utils" ;;
                *)      VAAPI_PKG="" ;;
            esac
            if ! (dpkg -l mesa-va-drivers &>/dev/null 2>&1 || \
                  rpm -q mesa-va-drivers &>/dev/null 2>&1 || \
                  pacman -Q mesa &>/dev/null 2>&1); then
                logw "AMD VA-API drivers may not be installed"
                [ -n "$VAAPI_PKG" ] && TO_INSTALL+=("$VAAPI_PKG")
            else
                logok "AMD VA-API drivers: installed"
            fi
            ;;
        intel)
            case "$PKG_MGR" in
                apt)    VAAPI_PKG="intel-media-va-driver-non-free libva-drm2 libva2" ;;
                dnf)    VAAPI_PKG="intel-media-driver libva libva-utils" ;;
                pacman) VAAPI_PKG="intel-media-driver libva libva-utils" ;;
                *)      VAAPI_PKG="" ;;
            esac
            logw "Intel VA-API drivers vary by GPU generation — verify manually"
            warn "Intel GPU: VA-API driver varies by generation — see log: ${LOG_FILE}"
            log "  Gen8-11 (Broadwell-Ice Lake): intel-media-va-driver"
            log "  Gen12+  (Tiger Lake+):         intel-media-va-driver-non-free"
            [ -n "$VAAPI_PKG" ] && TO_INSTALL+=("$VAAPI_PKG")
            ;;
    esac

    # ── Devices ───────────────────────────────────────────────────────────────
    log ""
    log "=== DEVICES ==="

    if ls /dev/dri/renderD* &>/dev/null; then
        RENDER_DEV=$(ls /dev/dri/renderD* | head -1)
        logok "/dev/dri/renderD*: ${RENDER_DEV}"
    else
        logw "/dev/dri/renderD* not found"
        warn "/dev/dri render device not found — Wolf GPU passthrough may fail"
        WARNINGS+=("/dev/dri render device not found")
    fi

    if [ -e /dev/uinput ]; then
        logok "/dev/uinput: present"
    else
        logok "/dev/uinput: not present — setup.sh will load it via modprobe"
    fi

    # ── Dependencies ─────────────────────────────────────────────────────────
    log ""
    log "=== DEPENDENCIES ==="

    # Docker
    if command -v docker &>/dev/null; then
        DOCKER_VER=$(docker --version 2>/dev/null | grep -oP '\d+\.\d+\.\d+' | head -1)
        logok "Docker: ${DOCKER_VER}"

        if ! docker info &>/dev/null; then
            loge "Docker daemon not running"
            fail "Docker is installed but not running"
            ERRORS+=("Docker daemon not running — run: sudo systemctl start docker")
        else
            logok "Docker daemon: running"
        fi

        if ! groups | grep -q docker; then
            logw "Current user not in docker group"
            warn "Not in docker group — you may need sudo for docker commands"
            warn "Fix: sudo usermod -aG docker \$USER  (then log out and back in)"
            WARNINGS+=("User not in docker group")
        else
            logok "Docker group: current user is member"
        fi
    else
        loge "Docker not installed"
        fail "Docker is not installed — this is required"
        ERRORS+=("Docker not installed — run: curl -fsSL https://get.docker.com | sh")
        TO_INSTALL+=("docker")
    fi

    # Docker Compose v2
    if docker compose version &>/dev/null 2>&1; then
        COMPOSE_VER=$(docker compose version 2>/dev/null | grep -oP '\d+\.\d+\.\d+' | head -1)
        logok "Docker Compose v2: ${COMPOSE_VER}"
    elif command -v docker-compose &>/dev/null; then
        loge "Docker Compose v1 found — v2 required"
        fail "Docker Compose v1 found — v2 is required (use 'docker compose' not 'docker-compose')"
        ERRORS+=("Docker Compose v2 required — install docker-compose-plugin")
        TO_INSTALL+=("docker-compose-plugin")
    else
        loge "Docker Compose not found"
        fail "Docker Compose not found — this is required"
        ERRORS+=("Docker Compose v2 required")
        TO_INSTALL+=("docker-compose-plugin")
    fi

    # Git
    if command -v git &>/dev/null; then
        logok "Git: $(git --version | grep -oP '\d+\.\d+\.\d+')"
    else
        logw "Git not installed (optional)"
        TO_INSTALL+=("git")
    fi

    # iproute2
    if command -v ip &>/dev/null; then
        logok "iproute2: present"
    else
        logw "iproute2 not found — host IP detection may fail"
        TO_INSTALL+=("iproute2")
    fi

    # Node.js (optional)
    if command -v node &>/dev/null; then
        logok "Node.js: $(node --version) (optional — for build.js)"
    else
        logw "Node.js not installed (optional — only needed for build.js doc generation)"
    fi

    # ── Write preflight env ───────────────────────────────────────────────────
    cat > .preflight_env << ENVEOF
PREFLIGHT_ARCH="${ARCH}"
PREFLIGHT_DISTRO_ID="${DISTRO_ID}"
PREFLIGHT_DISTRO_NAME="${DISTRO_NAME}"
PREFLIGHT_PKG_MGR="${PKG_MGR}"
PREFLIGHT_GPU_VENDOR="${GPU_VENDOR}"
PREFLIGHT_GPU_LABEL="${GPU_LABEL}"
ENVEOF
    logok ".preflight_env written"

    # ── Install missing packages ──────────────────────────────────────────────
    if [ ${#TO_INSTALL[@]} -gt 0 ] && [ "$PKG_MGR" != "unknown" ]; then
        gap
        echo -e "  ${BOLD}Missing packages:${RESET}"
        for pkg in "${TO_INSTALL[@]}"; do
            echo -e "  ${DIM}  • ${pkg}${RESET}"
        done

        DO_INSTALL=false
        if [ "$AUTO_INSTALL" = true ]; then
            DO_INSTALL=true
            gap
            info "Auto-install enabled — installing now"
        else
            gap
            printf "  Install missing packages now? [y/N]: "
    read -rt 0.1 discard 2>/dev/null || true  # drain leftover newline from prior read -rsn1
            read -r ans
            [[ "$ans" =~ ^[Yy]$ ]] && DO_INSTALL=true
        fi

        if [ "$DO_INSTALL" = true ]; then
            gap
            echo -e "  ${BOLD}Installing...${RESET}"
            sudo $PKG_UPDATE >> "$LOG_FILE" 2>&1
            for pkg in "${TO_INSTALL[@]}"; do
                # Docker requires special handling
                if [ "$pkg" = "docker" ]; then
                    warn "Docker requires the official installer — skipping apt install"
                    warn "Run: curl -fsSL https://get.docker.com | sh"
                    warn "Then: sudo usermod -aG docker \$USER"
                    loge "Docker skipped — needs manual install via get.docker.com"
                    continue
                fi
                echo -e "  ${DIM}Installing: ${pkg}${RESET}"
                sudo $PKG_INSTALL $pkg >> "$LOG_FILE" 2>&1 \
                    && logok "Installed: ${pkg}" \
                    || { logw "Failed to install: ${pkg}"; warn "Failed to install ${pkg} — may need manual install"; }
            done
            gap
            ok "Package installation complete"
        fi
    fi

    # ── Summary ───────────────────────────────────────────────────────────────
    log ""
    log "=== SUMMARY ==="
    log "Errors:   ${#ERRORS[@]}"
    log "Warnings: ${#WARNINGS[@]}"

    if [ ${#ERRORS[@]} -gt 0 ]; then
        gap
        echo -e "  ${R}${BOLD}Errors — must fix before continuing:${RESET}"
        for e in "${ERRORS[@]}"; do
            fail "$e"
            loge "$e"
        done
        gap
        echo -e "  ${DIM}Full log: ${LOG_FILE}${RESET}"
        gap
        echo -e "  ${R}Preflight failed — fix the errors above and re-run.${RESET}"
        gap
        exit 1
    fi

    if [ ${#WARNINGS[@]} -gt 0 ]; then
        gap
        echo -e "  ${Y}Warnings (stack may still work):${RESET}"
        for w in "${WARNINGS[@]}"; do
            warn "$w"
        done
        gap
        echo -e "  ${DIM}Full log: ${LOG_FILE}${RESET}"
    else
        gap
        ok "${BOLD}System ready${RESET} — all checks passed"
        gap
        info "Full log: ${LOG_FILE}"
    fi
}

# ══════════════════════════════════════════════════════════════════════════════
# PHASE 2 — CONFIGURATION WIZARD
# ══════════════════════════════════════════════════════════════════════════════

# ── Input helpers ─────────────────────────────────────────────────────────────

ask() {
    local var="$1" prompt="$2" default="$3" val
    while true; do
        if [ -n "$default" ]; then
            printf "\n  ${C}▸ ${prompt}${RESET}\n  ${DIM}  Default: ${default}${RESET}\n  > "
        else
            printf "\n  ${C}▸ ${prompt}${RESET} ${R}(required)${RESET}\n  > "
        fi
        read -r val
        val="${val:-$default}"
        if [ -z "$val" ]; then
            echo -e "  ${R}This field is required — please enter a value.${RESET}"
            continue
        fi
        break
    done
    eval "$var='$val'"
}

ask_optional() {
    local var="$1" prompt="$2" default="$3" val
    if [ -n "$default" ]; then
        printf "\n  ${C}▸ ${prompt}${RESET}\n  ${DIM}  Default: ${default} — Enter to accept, or type a new value${RESET}\n  > "
    else
        printf "\n  ${C}▸ ${prompt}${RESET}\n  ${DIM}  Optional — press Enter to skip${RESET}\n  > "
    fi
    read -r val
    val="${val:-$default}"
    eval "$var='$val'"
}

ask_secret() {
    local var="$1" prompt="$2" val
    while true; do
        printf "\n  ${C}▸ ${prompt}${RESET} ${R}(required, hidden)${RESET}\n  > "
        read -rs val
        echo ""
        if [ -z "$val" ]; then
            echo -e "  ${R}This field is required — please enter a value.${RESET}"
            continue
        fi
        break
    done
    eval "$var='$val'"
}

ask_secret_confirm() {
    local var="$1" prompt="$2" val val2
    while true; do
        printf "\n  ${C}▸ ${prompt}${RESET} ${R}(required, hidden)${RESET}\n  > "
        read -rs val; echo ""
        if [ -z "$val" ]; then
            echo -e "  ${R}Password cannot be blank.${RESET}"
            continue
        fi
        printf "  ${C}▸ Confirm ${prompt}${RESET}\n  > "
        read -rs val2; echo ""
        if [ "$val" != "$val2" ]; then
            echo -e "  ${R}Passwords do not match — try again.${RESET}"
            continue
        fi
        break
    done
    eval "$var='$val'"
}

ask_mac() {
    local var="$1" val
    while true; do
        printf "\n  ${C}▸ AMP fixed MAC address${RESET}\n  ${DIM}  Press Enter to auto-generate, or enter one manually (XX:XX:XX:XX:XX:XX)${RESET}\n  > "
        read -r val
        if [ -z "$val" ]; then
            val=$(printf '02:42:%02x:%02x:%02x:%02x' \
                $((RANDOM % 256)) $((RANDOM % 256)) \
                $((RANDOM % 256)) $((RANDOM % 256)))
            echo -e "  ${G}Generated: ${BOLD}${val}${RESET}"
            break
        fi
        if echo "$val" | grep -qE '^([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}$'; then
            break
        fi
        echo -e "  ${R}Invalid format. Expected XX:XX:XX:XX:XX:XX (hex pairs separated by colons).${RESET}"
    done
    eval "$var='$val'"
}

ask_ip() {
    local var="$1" prompt="$2" default="$3" required="${4:-false}" val
    while true; do
        if [ -n "$default" ]; then
            printf "\n  ${C}▸ ${prompt}${RESET}\n  ${DIM}  Detected: ${default} — Enter to accept${RESET}\n  > "
        elif [ "$required" = true ]; then
            printf "\n  ${C}▸ ${prompt}${RESET} ${R}(required)${RESET}\n  > "
        else
            printf "\n  ${C}▸ ${prompt}${RESET}\n  ${DIM}  Optional — press Enter to skip${RESET}\n  > "
        fi
        read -r val
        val="${val:-$default}"

        if [ -z "$val" ]; then
            [ "$required" = true ] && { echo -e "  ${R}Host IP is required.${RESET}"; continue; }
            break
        fi

        if echo "$val" | grep -qE '^([0-9]{1,3}\.){3}[0-9]{1,3}$'; then
            local valid=true
            IFS='.' read -ra octets <<< "$val"
            for o in "${octets[@]}"; do
                [ "$o" -gt 255 ] 2>/dev/null && valid=false
            done
            [ "$valid" = true ] && break
        fi
        echo -e "  ${R}Invalid IP address. Expected format: 192.168.1.100${RESET}"
    done
    eval "$var='$val'"
}

ask_port() {
    local var="$1" prompt="$2" default="$3" val
    while true; do
        printf "\n  ${C}▸ ${prompt}${RESET}\n  ${DIM}  Default: ${default}${RESET}\n  > "
        read -r val
        val="${val:-$default}"
        if echo "$val" | grep -qE '^[0-9]+$' && [ "$val" -ge 1 ] && [ "$val" -le 65535 ]; then
            break
        fi
        echo -e "  ${R}Invalid port. Must be a number between 1 and 65535.${RESET}"
    done
    eval "$var='$val'"
}

explain() {
    echo ""
    echo -e "  ${DIM}┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄${RESET}"
    echo -e "  ${DIM}$1${RESET}"
    echo -e "  ${DIM}┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄${RESET}"
}

run_quick_edit() {
    # Reads current values from .env, shows them, lets user change specific ones.
    # Blank entry = keep existing value. Uses apply_sed to patch .env in place.

    get_env() { grep "^${1}=" .env | cut -d= -f2- | tr -d '"' | tr -d "'"; }

    clear
    section "Quick Edit — Current Configuration"
    gap
    echo -e "  ${DIM}Press Enter to keep the current value shown in [brackets].${RESET}"
    echo -e "  ${DIM}Type a new value and press Enter to change it.${RESET}"
    gap

    # ── AMP credentials ───────────────────────────────────────────────────────
    section "AMP Credentials"

    CUR_AMP_USER=$(get_env AMP_USERNAME)
    CUR_AMP_MAC=$(get_env AMP_MAC)
    AMP_CREDS_CHANGED=false

    printf "\n  ${C}▸ AMP username${RESET} ${DIM}[${CUR_AMP_USER}]${RESET}\n  > "
    read -r val
    if [ -n "$val" ] && [ "$val" != "$CUR_AMP_USER" ]; then
        apply_sed .env "$CUR_AMP_USER" "$val"
        NEW_AMP_USER="$val"
        AMP_CREDS_CHANGED=true
        ok "AMP username updated"
    else
        NEW_AMP_USER="$CUR_AMP_USER"
    fi

    printf "\n  ${C}▸ AMP password${RESET} ${DIM}(Enter to keep current, hidden)${RESET}\n  > "
    read -rs val; echo ""
    if [ -n "$val" ]; then
        CUR_AMP_PASS=$(get_env AMP_PASSWORD)
        apply_sed .env "$CUR_AMP_PASS" "$val"
        NEW_AMP_PASS="$val"
        AMP_CREDS_CHANGED=true
        ok "AMP password updated"
    fi

    printf "\n  ${C}▸ AMP licence key${RESET} ${DIM}(Enter to keep current, hidden)${RESET}\n  > "
    read -rs val; echo ""
    if [ -n "$val" ]; then
        CUR_AMP_LIC=$(get_env AMP_LICENCE)
        apply_sed .env "$CUR_AMP_LIC" "$val"
        ok "AMP licence updated"
    fi

    printf "\n  ${C}▸ AMP MAC address${RESET} ${DIM}[${CUR_AMP_MAC}]${RESET}\n  > "
    read -r val
    if [ -n "$val" ] && [ "$val" != "$CUR_AMP_MAC" ]; then
        if echo "$val" | grep -qE '^([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}$'; then
            apply_sed .env "$CUR_AMP_MAC" "$val"
            ok "AMP MAC updated"
        else
            warn "Invalid MAC format — skipped"
        fi
    fi

    # ── Reset AMP credentials if changed ─────────────────────────────────────
    if [ "$AMP_CREDS_CHANGED" = true ]; then
        gap
        if docker ps --format "{{.Names}}" 2>/dev/null | grep -q "^amp$"; then
            echo -e "  ${Y}AMP credentials changed.${RESET}"
            echo -e "  ${DIM}Restart AMP for new credentials to take effect:${RESET}"
            echo -e "  ${BOLD}  docker compose --env-file .env restart amp${RESET}"
        else
            info "AMP container not running — credentials will apply on next start"
        fi
    fi

    # ── System ────────────────────────────────────────────────────────────────
    section "System"

    CUR_TZ=$(get_env TZ)
    CUR_DATA=$(get_env DATA_DIR)

    printf "\n  ${C}▸ Timezone${RESET} ${DIM}[${CUR_TZ}]${RESET}\n  > "
    read -r val
    if [ -n "$val" ] && [ "$val" != "$CUR_TZ" ]; then
        apply_sed .env "$CUR_TZ" "$val"
        ok "Timezone updated"
    fi

    printf "\n  ${C}▸ Data directory${RESET} ${DIM}[${CUR_DATA}]${RESET}\n  > "
    read -r val
    if [ -n "$val" ] && [ "$val" != "$CUR_DATA" ]; then
        apply_sed .env "$CUR_DATA" "$val"
        ok "Data directory updated"
    fi

    # ── Network ───────────────────────────────────────────────────────────────
    section "Network"

    CUR_HOST_IP=$(get_env HOST_IP)
    CUR_PUBLIC_IP=$(get_env PUBLIC_IP)
    CUR_ROUTER_IP=$(get_env ROUTER_IP)
    CUR_UPSTREAM=$(get_env UPSTREAM_IP)
    CUR_DOMAIN=$(get_env DOMAIN)
    CUR_SUBDOMAIN=$(get_env GAME_SUBDOMAIN)

    PORTAL="portal/html/index.html"

    edit_ip_field() {
        # edit_ip_field <label> <current> <env_key> <portal_placeholder>
        local label="$1" cur="$2" key="$3" placeholder="$4"
        printf "\n  ${C}▸ ${label}${RESET} ${DIM}[${cur:-(not set)}]${RESET}\n  > "
        read -r val
        if [ -n "$val" ] && [ "$val" != "$cur" ]; then
            if echo "$val" | grep -qE '^([0-9]{1,3}\.){3}[0-9]{1,3}$'; then
                # Update .env
                if [ -n "$cur" ]; then
                    apply_sed .env "$cur" "$val"
                else
                    # Key not present — append
                    echo "${key}=${val}" >> .env
                fi
                # Update portal
                [ -f "$PORTAL" ] && apply_sed "$PORTAL" "${cur:-$placeholder}" "$val"
                ok "${label} updated"
            else
                warn "Invalid IP — skipped"
            fi
        fi
    }

    edit_ip_field "Host LAN IP"         "$CUR_HOST_IP"   "HOST_IP"    "YOUR_HOST_IP"
    edit_ip_field "Public/WAN IP"       "$CUR_PUBLIC_IP" "PUBLIC_IP"  "YOUR_PUBLIC_IP"
    edit_ip_field "Router LAN IP"       "$CUR_ROUTER_IP" "ROUTER_IP"  "YOUR_ROUTER_IP"
    edit_ip_field "Upstream router IP"  "$CUR_UPSTREAM"  "UPSTREAM_IP" "YOUR_UPSTREAM_ROUTER_IP"

    printf "\n  ${C}▸ Public domain${RESET} ${DIM}[${CUR_DOMAIN:-(not set)}]${RESET}\n  > "
    read -r val
    if [ -n "$val" ] && [ "$val" != "$CUR_DOMAIN" ]; then
        if [ -n "$CUR_DOMAIN" ]; then
            apply_sed .env "$CUR_DOMAIN" "$val"
            [ -f "$PORTAL" ] && apply_sed "$PORTAL" "$CUR_DOMAIN" "$val"
        else
            echo "DOMAIN=${val}" >> .env
            [ -f "$PORTAL" ] && apply_sed "$PORTAL" "yourdomain.com" "$val"
        fi
        ok "Domain updated"
        CUR_DOMAIN="$val"
    fi

    printf "\n  ${C}▸ Game subdomain prefix${RESET} ${DIM}[${CUR_SUBDOMAIN:-game}]${RESET}\n  > "
    read -r val
    if [ -n "$val" ] && [ "$val" != "$CUR_SUBDOMAIN" ]; then
        apply_sed .env "${CUR_SUBDOMAIN:-game}" "$val"
        [ -f "$PORTAL" ] && [ -n "$CUR_DOMAIN" ] && \
            apply_sed "$PORTAL" "${CUR_SUBDOMAIN:-game}.${CUR_DOMAIN}" "${val}.${CUR_DOMAIN}"
        ok "Game subdomain updated"
    fi

    # ── Game ports ────────────────────────────────────────────────────────────
    section "Game Ports"

    CUR_PORT1=$(get_env VRISING_GAME_PORT)
    CUR_PORT2=$(get_env VRISING_QUERY_PORT)

    printf "\n  ${C}▸ Game port (main)${RESET} ${DIM}[${CUR_PORT1:-9876}]${RESET}\n  > "
    read -r val
    if [ -n "$val" ] && [ "$val" != "$CUR_PORT1" ]; then
        if echo "$val" | grep -qE '^[0-9]+$' && [ "$val" -ge 1 ] && [ "$val" -le 65535 ]; then
            apply_sed .env "${CUR_PORT1:-9876}" "$val"
            ok "Game port updated"
        else
            warn "Invalid port — skipped"
        fi
    fi

    printf "\n  ${C}▸ Game port (query)${RESET} ${DIM}[${CUR_PORT2:-9877}]${RESET}\n  > "
    read -r val
    if [ -n "$val" ] && [ "$val" != "$CUR_PORT2" ]; then
        if echo "$val" | grep -qE '^[0-9]+$' && [ "$val" -ge 1 ] && [ "$val" -le 65535 ]; then
            apply_sed .env "${CUR_PORT2:-9877}" "$val"
            ok "Query port updated"
        else
            warn "Invalid port — skipped"
        fi
    fi

    # ── Done ──────────────────────────────────────────────────────────────────
    gap
    ok "Quick edit complete"
    gap
    if confirm "Start the stack now? (runs setup.sh)"; then
        gap
        bash setup.sh
    else
        info "Run 'bash setup.sh' when ready."
    fi
    gap
}

run_wizard() {

    # ── Already configured? ───────────────────────────────────────────────────
    if [ -f .env ]; then
        clear
        echo -e "${BOLD}"
        echo "  ╔══════════════════════════════════════════╗"
        echo "  ║       GameStack Already Configured       ║"
        echo "  ╚══════════════════════════════════════════╝"
        echo -e "${RESET}"
        echo -e "  An existing configuration was found. What would you like to do?"
        gap
        echo -e "  ${BOLD}[e]${RESET}  Quick edit — change specific values only"
        echo -e "  ${BOLD}[f]${RESET}  Full reconfigure — redo the whole wizard"
        echo -e "  ${BOLD}[s]${RESET}  Skip to setup — start the stack with current config"
        echo -e "  ${BOLD}[x]${RESET}  Exit"
        gap
        printf "  Choice: "
        read -rsn1 existing_choice
        echo ""

        case "$existing_choice" in
            e|E)
                run_quick_edit
                return
                ;;
            f|F)
                # Fall through to full wizard below
                ;;
            s|S)
                gap
                if [ -f setup.sh ]; then
                    bash setup.sh
                else
                    warn "setup.sh not found"
                fi
                exit 0
                ;;
            x|X)
                gap
                exit 0
                ;;
            *)
                gap
                info "No change — exiting."
                exit 0
                ;;
        esac
    fi

    clear
    echo -e "${BOLD}"
    echo "  ╔══════════════════════════════════════════╗"
    echo "  ║       GameStack Setup Wizard             ║"
    echo "  ╚══════════════════════════════════════════╝"
    echo -e "${RESET}"
    echo -e "  Welcome to GameStack. This wizard will walk you through"
    echo -e "  everything needed to get your stack running."
    echo ""
    echo -e "  ${DIM}  • Required fields are marked — you cannot skip them"
    echo -e "     • Optional fields can be filled in later"
    echo -e "     • Passwords are hidden as you type"
    echo -e "     • Your settings will be saved to .env${RESET}"
    pause

    # ══════════════════════════════════════════════════════════════════════════
    # STEP 1 — AMP ACCOUNT
    # ══════════════════════════════════════════════════════════════════════════
    clear
    section "Step 1 of 5 — AMP Account"
    echo ""
    echo -e "  AMP (Application Management Panel) is the web interface"
    echo -e "  used to manage your game servers. GameStack uses it to run"
    echo -e "  and monitor game server instances."
    echo ""
    echo -e "  You need a free account at ${C}cubecoders.com${RESET} and a licence key."
    echo -e "  A free Community licence is sufficient."
    echo ""

    printf "  ${DIM}Do you already have an AMP account and licence key?${RESET} [y/N]: "
    read -rt 0.1 discard 2>/dev/null || true  # drain leftover newline from prior read -rsn1
    read -r HAS_ACCOUNT

    if [[ ! "$HAS_ACCOUNT" =~ ^[Yy]$ ]]; then
        gap
        echo -e "  ${BOLD}How to get an AMP licence:${RESET}"
        echo ""
        echo -e "  ${DIM}  1.  Go to https://cubecoders.com${RESET}"
        echo -e "  ${DIM}  2.  Create a free account${RESET}"
        echo -e "  ${DIM}  3.  Go to Licences in your dashboard${RESET}"
        echo -e "  ${DIM}  4.  Generate a new Community licence${RESET}"
        echo -e "  ${DIM}  5.  Copy the key — format: XXXX-XXXX-XXXX-XXXX${RESET}"
        gap
        # Try to open browser
        if [ -z "$SSH_CLIENT" ] && [ -z "$SSH_TTY" ]; then
            if command -v xdg-open &>/dev/null; then xdg-open "https://cubecoders.com" &>/dev/null & fi
        else
            echo -e "  ${Y}SSH session detected — open this URL on your local machine:${RESET}"
            echo -e "  ${C}https://cubecoders.com${RESET}"
        fi
        pause
    fi

    # ══════════════════════════════════════════════════════════════════════════
    # STEP 2 — AMP CREDENTIALS
    # ══════════════════════════════════════════════════════════════════════════
    clear
    section "Step 2 of 5 — AMP Credentials"

    explain "These are the login credentials for the AMP web panel.
  Choose a strong password — the panel will be accessible on your LAN.
  The licence key comes from your cubecoders.com account dashboard."

    ask        AMP_USERNAME "AMP panel username"
    ask_secret_confirm AMP_PASSWORD "AMP panel password"
    ask_secret AMP_LICENCE  "AMP licence key (format: XXXX-XXXX-XXXX-XXXX)"

    gap
    explain "AMP uses a fixed MAC address to prevent licence deactivation
  every time the container restarts. We generate one for you automatically,
  or you can supply your own."

    ask_mac AMP_MAC

    # ══════════════════════════════════════════════════════════════════════════
    # STEP 3 — HOST & SYSTEM
    # ══════════════════════════════════════════════════════════════════════════
    clear
    section "Step 3 of 5 — Host & System"

    explain "These settings tell GameStack where it lives on your machine.
  DATA_DIR is where all persistent data (game saves, configs, logs) will
  be stored. The host IP is your machine's LAN IP address — this is used
  to display correct links in the portal."

    # Auto-detect sensible defaults
    DETECTED_IP=$(ip route get 1.1.1.1 2>/dev/null | awk '/src/{for(i=1;i<=NF;i++) if($i=="src") print $(i+1); exit}' || echo "")
    DETECTED_HOST=$(hostname 2>/dev/null || echo "gamestack-host")
    DETECTED_USER=$(whoami 2>/dev/null || echo "")
    DETECTED_TZ=$(timedatectl show --property=Timezone --value 2>/dev/null || echo "America/Los_Angeles")

    ask          TZ        "Timezone (TZ database format)"              "$DETECTED_TZ"
    ask          DATA_DIR  "GameStack data directory (absolute path)"   "~/Git/Gamestack"
    ask          USERNAME  "Your Linux username"                        "$DETECTED_USER"
    ask          HOSTNAME_VAL "Your machine hostname"                   "$DETECTED_HOST"
    ask_ip       HOST_IP   "Host LAN IP (static)"                      "$DETECTED_IP" true

    # Validate / create DATA_DIR
    DATA_DIR_EXP="${DATA_DIR/#\~/$HOME}"
    if [ ! -d "$DATA_DIR_EXP" ]; then
        gap
        echo -e "  ${Y}Directory '${DATA_DIR}' does not exist.${RESET}"
        if confirm "Create it now?"; then
            mkdir -p "$DATA_DIR_EXP"
            ok "Created: ${DATA_DIR}"
        else
            warn "Directory not created — setup.sh will create it when you run the stack"
        fi
    else
        ok "Data directory exists: ${DATA_DIR}"
    fi

    # ══════════════════════════════════════════════════════════════════════════
    # STEP 4 — NETWORK (OPTIONAL)
    # ══════════════════════════════════════════════════════════════════════════
    clear
    section "Step 4 of 5 — Network & Domain"

    explain "These are display-only values used in the portal's network info page.
  The stack runs perfectly without them — they just show placeholder text
  instead of your real values. You can skip any or all of these for now
  and fill them in later by re-running configure.sh."

    ask_ip       PUBLIC_IP     "Your public/WAN IP address"             ""
    ask_optional DOMAIN        "Your public domain (e.g. example.com)"  ""
    ask_optional GAME_SUBDOMAIN "Game server subdomain prefix"          "game"
    ask_ip       ROUTER_IP     "Your router's LAN IP"                   ""
    ask_ip       UPSTREAM_IP   "Upstream router IP (double-NAT only)"   ""
    ask_ip       MODEM_IP      "ISP modem/gateway IP"                   ""

    # ══════════════════════════════════════════════════════════════════════════
    # STEP 5 — GAME PORTS
    # ══════════════════════════════════════════════════════════════════════════
    clear
    section "Step 5 of 5 — Game Server Ports"

    explain "These are the network ports your game server will use.
  The defaults (9876/9877) work for most setups. Change them only if
  you know your game server uses different ports, or if those ports
  are already in use on your machine.
  Ports must be forwarded on your router for external access."

    ask_port GAME_PORT_1 "Game server port (main)"          "9876"
    ask_port GAME_PORT_2 "Game server port (query/secondary)" "9877"

    # ══════════════════════════════════════════════════════════════════════════
    # SUMMARY
    # ══════════════════════════════════════════════════════════════════════════
    clear
    section "Review Your Settings"
    gap

    printf "  ${BOLD}%-26s${RESET} %s\n" "Timezone:"           "$TZ"
    printf "  ${BOLD}%-26s${RESET} %s\n" "Data directory:"     "$DATA_DIR"
    printf "  ${BOLD}%-26s${RESET} %s\n" "Linux username:"     "${USERNAME:-(not set)}"
    printf "  ${BOLD}%-26s${RESET} %s\n" "Hostname:"           "$HOSTNAME_VAL"
    printf "  ${BOLD}%-26s${RESET} %s\n" "Host LAN IP:"        "$HOST_IP"
    gap
    printf "  ${BOLD}%-26s${RESET} %s\n" "AMP username:"       "$AMP_USERNAME"
    printf "  ${BOLD}%-26s${RESET} %s\n" "AMP password:"       "(set)"
    printf "  ${BOLD}%-26s${RESET} %s\n" "AMP licence:"        "(set)"
    printf "  ${BOLD}%-26s${RESET} %s\n" "AMP MAC:"            "$AMP_MAC"
    gap
    printf "  ${BOLD}%-26s${RESET} %s\n" "Public IP:"          "${PUBLIC_IP:-(not set)}"
    printf "  ${BOLD}%-26s${RESET} %s\n" "Domain:"             "${DOMAIN:-(not set)}"
    printf "  ${BOLD}%-26s${RESET} %s\n" "Game subdomain:"     "${GAME_SUBDOMAIN:-game}.${DOMAIN:-(not set)}"
    printf "  ${BOLD}%-26s${RESET} %s\n" "Router IP:"          "${ROUTER_IP:-(not set)}"
    printf "  ${BOLD}%-26s${RESET} %s\n" "Upstream router IP:" "${UPSTREAM_IP:-(not set)}"
    printf "  ${BOLD}%-26s${RESET} %s\n" "Modem IP:"           "${MODEM_IP:-(not set)}"
    gap
    printf "  ${BOLD}%-26s${RESET} %s\n" "Game port (main):"   "$GAME_PORT_1"
    printf "  ${BOLD}%-26s${RESET} %s\n" "Game port (query):"  "$GAME_PORT_2"
    gap

    if ! confirm "Apply these settings?"; then
        gap
        echo -e "  ${Y}Aborted — no files changed.${RESET}"
        gap
        exit 0
    fi
}


# ══════════════════════════════════════════════════════════════════════════════
# AMP LICENCE ACTIVATION
# ══════════════════════════════════════════════════════════════════════════════

amp_activate_licence() {
    local host_ip licence_key amp_url session result status grade_name reason login_response
    host_ip="${HOST_IP:-$(ip route get 1.1.1.1 2>/dev/null | awk '/src/{for(i=1;i<=NF;i++) if($i=="src") print $(i+1); exit}')}"
    licence_key="${AMP_LICENCE}"
    amp_url="http://${host_ip}:8080"

    if [ -z "$licence_key" ] || [ "$licence_key" = "your_amp_licence_key" ]; then
        warn "AMP licence key not set — skipping activation"
        return 1
    fi

    # Wait for AMP to become ready (up to 60 seconds)
    gap
    echo -e "  ${DIM}Waiting for AMP to be ready...${RESET}"
    local attempts=0
    while [ $attempts -lt 12 ]; do
        if curl -sf "${amp_url}/" &>/dev/null 2>&1; then
            break
        fi
        sleep 5
        attempts=$((attempts + 1))
    done

    if [ $attempts -ge 12 ]; then
        warn "AMP did not become ready in time — skipping licence activation"
        info "Run configure.sh --config-only again once AMP is up to activate the licence"
        return 1
    fi

    # Login to get session token
    login_response=$(curl -s -X POST "${amp_url}/API/Core/Login" \
        -H "Content-Type: application/json" \
        -H "Accept: application/json" \
        -d "{\"username\":\"${AMP_USERNAME}\",\"password\":\"${AMP_PASSWORD}\",\"token\":\"\",\"rememberMe\":false}" \
        2>/dev/null)

    session=$(printf '%s' "$login_response" | \
        python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('sessionID',''))" 2>/dev/null)

    if [ -z "$session" ]; then
        warn "Could not log in to AMP — skipping licence activation"
        info "Check AMP credentials and run configure.sh --config-only again"
        return 1
    fi

    # Activate licence
    result=$(curl -s -X POST "${amp_url}/API/Core/ActivateAMPLicence" \
        -H "Accept: application/json" \
        -H "Content-Type: application/json" \
        -d "{\"SESSIONID\":\"${session}\",\"LicenceKey\":\"${licence_key}\",\"QueryOnly\":false}" \
        2>/dev/null)

    status=$(printf '%s' "$result" | \
        python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('Status',False))" 2>/dev/null)
    grade_name=$(printf '%s' "$result" | \
        python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('Result',{}).get('GradeName',''))" 2>/dev/null)

    if [ "$status" = "True" ]; then
        ok "AMP licence activated — ${grade_name}"

        # Set licence key in Instance Deployment defaults so new instances use it
        local cfg_result
        cfg_result=$(curl -s -X POST "${amp_url}/API/Core/SetConfigs" \
            -H "Accept: application/json" \
            -H "Content-Type: application/json" \
            -d "{\"SESSIONID\":\"${session}\",\"data\":{\"ADSModule.Defaults.NewInstanceKey\":\"${licence_key}\"}}" \
            2>/dev/null)
        if [ "$cfg_result" = "true" ]; then
            ok "AMP instance deployment licence key set"
        else
            warn "Could not set instance deployment licence key — set manually via Configuration → Instance Deployment → Deployment Defaults → Licence Key"
        fi
    else
        reason=$(printf '%s' "$result" | \
            python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('Reason','Unknown error'))" 2>/dev/null)
        warn "AMP licence activation failed: ${reason}"
        info "Log in to AMP at ${amp_url} and activate manually via Admin → Licence"
    fi
}

# ══════════════════════════════════════════════════════════════════════════════
# PHASE 3 — APPLY
# ══════════════════════════════════════════════════════════════════════════════

run_apply() {
    clear
    section "Applying Configuration"
    gap

    # ── .env ──────────────────────────────────────────────────────────────────
    if [ ! -f .env.example ]; then
        fail ".env.example not found — cannot create .env"
        echo -e "  ${R}Make sure you are running this from your Gamestack directory.${RESET}"
        exit 1
    fi

    cp .env.example .env

    apply_sed .env "America/Los_Angeles"  "$TZ"
    apply_sed .env "~/Git/Gamestack"          "$DATA_DIR"
    apply_sed .env "your_amp_username"    "$AMP_USERNAME"
    apply_sed .env "your_amp_password"    "$AMP_PASSWORD"
    apply_sed .env "your_amp_licence_key" "$AMP_LICENCE"
    apply_sed .env "02:42:xx:xx:xx:xx"    "$AMP_MAC"
    apply_sed .env "9876"                 "$GAME_PORT_1"
    apply_sed .env "9877"                 "$GAME_PORT_2"

    # Write optional network values to .env as comments for reference
    cat >> .env << ENVEOF

# ── Network display values (used by portal) ───────────────────────────────────
HOST_IP=${HOST_IP}
PUBLIC_IP=${PUBLIC_IP}
ROUTER_IP=${ROUTER_IP}
UPSTREAM_IP=${UPSTREAM_IP}
DOMAIN=${DOMAIN}
GAME_SUBDOMAIN=${GAME_SUBDOMAIN:-game}
ENVEOF

    ok ".env written"

    # ── AMP data purge ────────────────────────────────────────────────────────
    # On a full configure, wipe existing AMP data so credentials take effect.
    # AMP bakes credentials at first-run time — if old data exists it ignores env vars.
    DATA_DIR_EXP="${DATA_DIR/#\~/$HOME}"
    AMP_DATA="${DATA_DIR_EXP}/ampdata/.ampdata"
    if [ -d "$AMP_DATA" ]; then
        gap
        echo -e "  ${Y}Existing AMP data found at: ${AMP_DATA}${RESET}"
        echo -e "  ${DIM}AMP stores credentials internally and will ignore the new ones${RESET}"
        echo -e "  ${DIM}unless this data is cleared.${RESET}"
        gap
        echo -e "  ${R}Warning: this will delete all AMP instance data including${RESET}"
        echo -e "  ${R}game server configurations. Game save data is NOT affected.${RESET}"
        gap
        if confirm "Purge AMP data so new credentials take effect?"; then
            docker stop amp 2>/dev/null || true
            docker rm amp 2>/dev/null || true
            rm -rf "$AMP_DATA"
            ok "AMP data purged — will rebuild on next start with new credentials"
        else
            warn "AMP data kept — new credentials may not work until data is purged"
            info "To apply new credentials without purging, restart AMP: docker compose --env-file .env restart amp"
        fi
    fi

    # ── portal/html/index.html ────────────────────────────────────────────────
    PORTAL="portal/html/index.html"
    if [ -f "$PORTAL" ]; then
        [ -n "$USERNAME"     ] && apply_sed "$PORTAL" "your-username"           "$USERNAME"
        [ -n "$HOSTNAME_VAL" ] && apply_sed "$PORTAL" "your-hostname"           "$HOSTNAME_VAL"
        [ -n "$HOST_IP"      ] && apply_sed "$PORTAL" "YOUR_HOST_IP"            "$HOST_IP"
        [ -n "$PUBLIC_IP"    ] && apply_sed "$PORTAL" "YOUR_PUBLIC_IP"          "$PUBLIC_IP"
        [ -n "$ROUTER_IP"    ] && apply_sed "$PORTAL" "YOUR_ROUTER_IP"          "$ROUTER_IP"
        [ -n "$UPSTREAM_IP"  ] && apply_sed "$PORTAL" "YOUR_UPSTREAM_ROUTER_IP" "$UPSTREAM_IP"
        [ -n "$MODEM_IP"     ] && apply_sed "$PORTAL" "YOUR_MODEM_IP"           "$MODEM_IP"
        if [ -n "$DOMAIN" ]; then
            GAME_DOMAIN="${GAME_SUBDOMAIN:-game}.${DOMAIN}"
            apply_sed "$PORTAL" "game.yourdomain.com" "$GAME_DOMAIN"
            apply_sed "$PORTAL" "yourdomain.com"      "$DOMAIN"
        fi
        ok "portal/html/index.html updated"
    else
        warn "portal/html/index.html not found — skipped"
    fi

    # ── Remaining placeholders check ──────────────────────────────────────────
    REMAINING=$(grep -l \
        "YOUR_HOST_IP\|YOUR_PUBLIC_IP\|YOUR_ROUTER_IP\|YOUR_UPSTREAM_ROUTER_IP\|YOUR_MODEM_IP\|your-username\|your-hostname\|yourdomain\.com\|your_amp_username\|your_amp_password\|your_amp_licence\|02:42:xx" \
        .env "$PORTAL" 2>/dev/null || true)

    if [ -n "$REMAINING" ]; then
        gap
        warn "Some placeholders remain (fields you skipped):"
        grep -n \
            "YOUR_HOST_IP\|YOUR_PUBLIC_IP\|YOUR_ROUTER_IP\|YOUR_UPSTREAM_ROUTER_IP\|YOUR_MODEM_IP\|your-username\|your-hostname\|yourdomain\.com\|your_amp_username\|your_amp_password\|your_amp_licence\|02:42:xx" \
            .env "$PORTAL" 2>/dev/null \
            | sed 's/^/    /' | head -15
        gap
        info "Re-run configure.sh any time to fill these in."
    fi

    gap
    echo -e "  ${G}${BOLD}Configuration complete.${RESET}"
    gap

    # ── Offer to run setup.sh ─────────────────────────────────────────────────
    if [ -f setup.sh ]; then
        if confirm "Start the stack now? (runs setup.sh)"; then
            gap
            bash setup.sh
            gap
            echo -e "  ${BOLD}Activating AMP licence...${RESET}"
            amp_activate_licence
        else
            gap
            info "Run 'bash setup.sh' when you're ready to start the stack."
            info "Then run 'bash configure.sh --config-only' to activate the AMP licence."
        fi
    else
        warn "setup.sh not found — cannot start stack automatically"
        info "Make sure setup.sh is in the same directory."
    fi

    gap
}

# ══════════════════════════════════════════════════════════════════════════════
# MAIN
# ══════════════════════════════════════════════════════════════════════════════

clear
echo -e "${BOLD}"
echo "  ╔══════════════════════════════════════════╗"
echo "  ║           GameStack Configure            ║"
echo "  ╚══════════════════════════════════════════╝"
echo -e "${RESET}"

if [ "$CONFIG_ONLY" = false ]; then
    echo -e "  ${BOLD}Phase 1 — System Check${RESET}"
    echo -e "  ${DIM}Checking your system is ready to run GameStack...${RESET}"
    gap
    run_preflight
    [ "$PREFLIGHT_ONLY" = true ] && exit 0
    pause
fi

run_wizard
run_apply
