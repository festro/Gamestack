#!/bin/bash
# GameStack Preflight Check
# Detects system architecture, distro, GPU vendor and validates/installs
# all dependencies required to run the stack.
#
# Usage:
#   bash preflight.sh              — check and prompt to install
#   bash preflight.sh --auto       — check and install without prompting
#   bash preflight.sh --check-only — check only, no installation
#
# Called automatically by setup.sh on first run or when --preflight flag passed.

set -e
cd "$(dirname "$0")"

# ── Args ──────────────────────────────────────────────────────────────────────
AUTO_INSTALL=false
CHECK_ONLY=false
for arg in "$@"; do
    case "$arg" in
        --auto)       AUTO_INSTALL=true ;;
        --check-only) CHECK_ONLY=true ;;
    esac
done

# ── Colours ───────────────────────────────────────────────────────────────────
R='\033[0;31m' G='\033[0;32m' Y='\033[1;33m'
C='\033[0;36m' BOLD='\033[1m' DIM='\033[2m' RESET='\033[0m'

ok()   { echo -e "  ${G}✓${RESET}  $1"; }
fail() { echo -e "  ${R}✗${RESET}  $1"; }
warn() { echo -e "  ${Y}!${RESET}  $1"; }
info() { echo -e "  ${DIM}    $1${RESET}"; }
section() { echo -e "\n${BOLD}── $1 ──────────────────────────────────────────────${RESET}"; }

# ── Result tracking ───────────────────────────────────────────────────────────
ERRORS=()
WARNINGS=()
TO_INSTALL=()

add_error()   { ERRORS+=("$1"); }
add_warning() { WARNINGS+=("$1"); }
add_install() { TO_INSTALL+=("$1"); }

# ══════════════════════════════════════════════════════════════════════════════
# DETECTION
# ══════════════════════════════════════════════════════════════════════════════

# ── Architecture ──────────────────────────────────────────────────────────────
section "System"

ARCH=$(uname -m)
case "$ARCH" in
    x86_64)  ARCH_LABEL="x86_64 (64-bit Intel/AMD)" ;;
    aarch64) ARCH_LABEL="aarch64 (64-bit ARM)" ;;
    armv7l)  ARCH_LABEL="armv7l (32-bit ARM)" ;;
    *)       ARCH_LABEL="$ARCH (unknown)" ;;
esac
ok "Architecture: ${ARCH_LABEL}"

# ── Kernel ────────────────────────────────────────────────────────────────────
KERNEL=$(uname -r)
ok "Kernel: ${KERNEL}"

# ── Distro ────────────────────────────────────────────────────────────────────
if [ -f /etc/os-release ]; then
    . /etc/os-release
    DISTRO_ID="${ID}"
    DISTRO_NAME="${PRETTY_NAME}"
    DISTRO_VERSION="${VERSION_ID:-unknown}"
    ok "Distro: ${DISTRO_NAME}"
else
    DISTRO_ID="unknown"
    DISTRO_NAME="Unknown Linux"
    warn "Could not detect distro — /etc/os-release not found"
fi

# Determine package manager
case "$DISTRO_ID" in
    ubuntu|debian|linuxmint|pop|neon|kali|raspbian)
        PKG_MGR="apt"
        PKG_INSTALL="apt-get install -y"
        PKG_UPDATE="apt-get update"
        ;;
    fedora|rhel|centos|rocky|almalinux)
        PKG_MGR="dnf"
        PKG_INSTALL="dnf install -y"
        PKG_UPDATE="dnf check-update || true"
        ;;
    arch|manjaro|endeavouros|garuda)
        PKG_MGR="pacman"
        PKG_INSTALL="pacman -S --noconfirm"
        PKG_UPDATE="pacman -Sy"
        ;;
    opensuse*|sles)
        PKG_MGR="zypper"
        PKG_INSTALL="zypper install -y"
        PKG_UPDATE="zypper refresh"
        ;;
    *)
        PKG_MGR="unknown"
        warn "Unknown package manager for distro: ${DISTRO_ID}"
        warn "Manual dependency installation may be required"
        ;;
esac

[ "$PKG_MGR" != "unknown" ] && info "Package manager: ${PKG_MGR}"

# ── GPU Detection ─────────────────────────────────────────────────────────────
section "GPU"

GPU_VENDOR="none"
GPU_LABEL="No GPU detected"

# Check for AMD
if lspci 2>/dev/null | grep -qi "AMD\|ATI\|Radeon"; then
    GPU_VENDOR="amd"
    GPU_LABEL=$(lspci 2>/dev/null | grep -i "AMD\|ATI\|Radeon\|VGA\|Display" | head -1 | sed 's/.*: //')
    ok "GPU: AMD — ${GPU_LABEL}"
# Check for NVIDIA
elif lspci 2>/dev/null | grep -qi "NVIDIA"; then
    GPU_VENDOR="nvidia"
    GPU_LABEL=$(lspci 2>/dev/null | grep -i "NVIDIA\|VGA\|Display" | head -1 | sed 's/.*: //')
    ok "GPU: NVIDIA — ${GPU_LABEL}"
# Check for Intel
elif lspci 2>/dev/null | grep -qi "Intel.*Graphics\|Intel.*VGA\|Intel.*Display"; then
    GPU_VENDOR="intel"
    GPU_LABEL=$(lspci 2>/dev/null | grep -i "Intel.*Graphics\|Intel.*VGA\|Intel.*Display" | head -1 | sed 's/.*: //')
    ok "GPU: Intel — ${GPU_LABEL}"
# Fallback: check /dev/dri
elif ls /dev/dri/renderD* &>/dev/null; then
    GPU_VENDOR="drm"
    GPU_LABEL="DRM device (vendor unknown)"
    warn "GPU: DRM device found but vendor undetected — VA-API may still work"
else
    warn "GPU: None detected — software encoding will be used (higher CPU load)"
    add_warning "No GPU detected — Wolf will fall back to software encoding"
fi

# Check VA-API for AMD/Intel
if [ "$GPU_VENDOR" = "amd" ] || [ "$GPU_VENDOR" = "intel" ]; then
    if command -v vainfo &>/dev/null; then
        VAINFO=$(vainfo 2>/dev/null | grep "VAProfile" | wc -l)
        if [ "$VAINFO" -gt 0 ]; then
            ok "VA-API: ${VAINFO} profiles available"
        else
            warn "VA-API: vainfo found but no profiles reported — driver may need installing"
            add_warning "VA-API profiles not found — check GPU driver installation"
        fi
    else
        warn "VA-API: vainfo not installed — cannot verify VA-API status"
        add_install "vainfo"
    fi
fi

# NVIDIA-specific checks
if [ "$GPU_VENDOR" = "nvidia" ]; then
    if command -v nvidia-smi &>/dev/null; then
        NVIDIA_DRIVER=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null | head -1)
        ok "NVIDIA driver: ${NVIDIA_DRIVER}"
    else
        fail "NVIDIA GPU detected but nvidia-smi not found — driver not installed"
        add_error "NVIDIA driver missing — install from https://www.nvidia.com/drivers or via your package manager"
    fi

    # Check for NVIDIA Container Toolkit (required for Wolf with NVIDIA)
    if ! docker info 2>/dev/null | grep -qi "nvidia"; then
        warn "NVIDIA Container Toolkit not detected — required for Wolf GPU passthrough"
        add_warning "Install nvidia-container-toolkit: https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/install-guide.html"
    else
        ok "NVIDIA Container Toolkit: detected"
    fi
fi

# ── /dev/dri and /dev/uinput ──────────────────────────────────────────────────
section "Devices"

if ls /dev/dri/renderD* &>/dev/null; then
    RENDER_DEV=$(ls /dev/dri/renderD* | head -1)
    ok "/dev/dri/renderD*: ${RENDER_DEV}"
else
    warn "/dev/dri/renderD*: not found — GPU passthrough to Wolf may fail"
    add_warning "/dev/dri render device not found"
fi

if [ -e /dev/uinput ]; then
    ok "/dev/uinput: present"
else
    warn "/dev/uinput: not present — will be loaded by setup.sh via modprobe"
fi

# ══════════════════════════════════════════════════════════════════════════════
# DEPENDENCY CHECKS
# ══════════════════════════════════════════════════════════════════════════════
section "Dependencies"

# ── Docker ────────────────────────────────────────────────────────────────────
if command -v docker &>/dev/null; then
    DOCKER_VER=$(docker --version 2>/dev/null | grep -oP '\d+\.\d+\.\d+' | head -1)
    ok "Docker: ${DOCKER_VER}"

    # Check Docker daemon is running
    if ! docker info &>/dev/null; then
        fail "Docker daemon not running"
        add_error "Docker is installed but not running — run: sudo systemctl start docker"
    else
        ok "Docker daemon: running"
    fi

    # Check current user is in docker group
    if ! groups | grep -q docker; then
        warn "Current user not in docker group — sudo may be required"
        add_warning "Add user to docker group: sudo usermod -aG docker \$USER (then log out/in)"
    else
        ok "Docker group: current user is member"
    fi
else
    fail "Docker: not installed"
    add_error "Docker required"
    add_install "docker"
fi

# ── Docker Compose v2 ─────────────────────────────────────────────────────────
if docker compose version &>/dev/null 2>&1; then
    COMPOSE_VER=$(docker compose version 2>/dev/null | grep -oP '\d+\.\d+\.\d+' | head -1)
    ok "Docker Compose v2: ${COMPOSE_VER}"
elif command -v docker-compose &>/dev/null; then
    COMPOSE_VER=$(docker-compose --version 2>/dev/null | grep -oP '\d+\.\d+\.\d+' | head -1)
    fail "Docker Compose v1 found (${COMPOSE_VER}) — v2 required (use 'docker compose' not 'docker-compose')"
    add_error "Docker Compose v2 required — install via Docker Desktop or 'apt install docker-compose-plugin'"
else
    fail "Docker Compose: not found"
    add_error "Docker Compose v2 required"
    add_install "docker-compose-plugin"
fi

# ── Git ───────────────────────────────────────────────────────────────────────
if command -v git &>/dev/null; then
    GIT_VER=$(git --version | grep -oP '\d+\.\d+\.\d+')
    ok "Git: ${GIT_VER}"
else
    warn "Git: not installed (optional — needed to clone/update repo)"
    add_install "git"
fi

# ── iproute2 (ip command for host IP detection) ───────────────────────────────
if command -v ip &>/dev/null; then
    ok "iproute2: present"
else
    warn "iproute2: not found — host IP detection will fall back to hostname"
    add_install "iproute2"
fi

# ── Node.js (optional — for build.js doc generation) ─────────────────────────
if command -v node &>/dev/null; then
    NODE_VER=$(node --version)
    ok "Node.js: ${NODE_VER} (optional — for build.js)"
else
    warn "Node.js: not installed (optional — only needed to regenerate docs with build.js)"
fi

# ── GPU driver packages by vendor ─────────────────────────────────────────────
section "GPU Drivers"

case "$GPU_VENDOR" in
    amd)
        case "$PKG_MGR" in
            apt)   VAAPI_PKG="mesa-va-drivers libva-drm2 libva2" ;;
            dnf)   VAAPI_PKG="mesa-va-drivers libva libva-utils" ;;
            pacman)VAAPI_PKG="mesa libva libva-utils" ;;
            zypper)VAAPI_PKG="Mesa-dri libva2 libva-utils" ;;
            *)     VAAPI_PKG="" ;;
        esac
        if dpkg -l mesa-va-drivers &>/dev/null 2>&1 || \
           rpm -q mesa-va-drivers &>/dev/null 2>&1 || \
           pacman -Q mesa &>/dev/null 2>&1; then
            ok "AMD VA-API drivers: installed"
        else
            warn "AMD VA-API drivers: may not be installed"
            [ -n "$VAAPI_PKG" ] && add_install "$VAAPI_PKG"
        fi
        ;;
    intel)
        case "$PKG_MGR" in
            apt)   VAAPI_PKG="intel-media-va-driver-non-free libva-drm2 libva2" ;;
            dnf)   VAAPI_PKG="intel-media-driver libva libva-utils" ;;
            pacman)VAAPI_PKG="intel-media-driver libva libva-utils" ;;
            *)     VAAPI_PKG="" ;;
        esac
        warn "Intel VA-API drivers: check manually (varies by generation)"
        info "For Gen8-11 (Broadwell–Ice Lake): intel-media-va-driver"
        info "For Gen12+ (Tiger Lake+):          intel-media-va-driver-non-free"
        [ -n "$VAAPI_PKG" ] && add_install "$VAAPI_PKG"
        ;;
    nvidia)
        ok "NVIDIA: uses NVENC via nvidia-container-toolkit (no VA-API needed)"
        ;;
    *)
        warn "GPU driver check skipped — vendor not detected"
        ;;
esac

# ── Write detection results to file for setup.sh to consume ──────────────────
cat > .preflight_env << ENVEOF
PREFLIGHT_ARCH="${ARCH}"
PREFLIGHT_DISTRO_ID="${DISTRO_ID}"
PREFLIGHT_DISTRO_NAME="${DISTRO_NAME}"
PREFLIGHT_PKG_MGR="${PKG_MGR}"
PREFLIGHT_GPU_VENDOR="${GPU_VENDOR}"
PREFLIGHT_GPU_LABEL="${GPU_LABEL}"
ENVEOF

# ══════════════════════════════════════════════════════════════════════════════
# SUMMARY
# ══════════════════════════════════════════════════════════════════════════════
section "Summary"

if [ ${#ERRORS[@]} -gt 0 ]; then
    echo ""
    echo -e "  ${R}${BOLD}Errors (must fix before running setup.sh):${RESET}"
    for e in "${ERRORS[@]}"; do
        echo -e "  ${R}✗${RESET}  ${e}"
    done
fi

if [ ${#WARNINGS[@]} -gt 0 ]; then
    echo ""
    echo -e "  ${Y}Warnings:${RESET}"
    for w in "${WARNINGS[@]}"; do
        echo -e "  ${Y}!${RESET}  ${w}"
    done
fi

if [ ${#ERRORS[@]} -eq 0 ] && [ ${#WARNINGS[@]} -eq 0 ]; then
    echo ""
    ok "${BOLD}All checks passed — system is ready${RESET}"
fi

# ══════════════════════════════════════════════════════════════════════════════
# INSTALL
# ══════════════════════════════════════════════════════════════════════════════
if [ ${#TO_INSTALL[@]} -gt 0 ] && [ "$CHECK_ONLY" = false ] && [ "$PKG_MGR" != "unknown" ]; then

    echo ""
    echo -e "  ${BOLD}Packages to install:${RESET}"
    for pkg in "${TO_INSTALL[@]}"; do
        echo -e "  ${DIM}  • ${pkg}${RESET}"
    done

    DO_INSTALL=false
    if [ "$AUTO_INSTALL" = true ]; then
        DO_INSTALL=true
        echo ""
        echo -e "  ${Y}--auto flag set — installing without prompt${RESET}"
    else
        echo ""
        printf "  Install missing packages now? [y/N]: "
        read -r ans
        [[ "$ans" =~ ^[Yy]$ ]] && DO_INSTALL=true
    fi

    if [ "$DO_INSTALL" = true ]; then
        echo ""
        echo -e "  ${BOLD}Installing...${RESET}"
        sudo $PKG_UPDATE
        for pkg in "${TO_INSTALL[@]}"; do
            echo -e "  ${DIM}Installing: ${pkg}${RESET}"
            sudo $PKG_INSTALL $pkg || warn "Failed to install ${pkg} — may need manual install"
        done
        echo ""
        ok "Installation complete"
    fi
fi

# ── Special case: Docker not installed ───────────────────────────────────────
if [[ " ${TO_INSTALL[*]} " =~ " docker " ]]; then
    echo ""
    echo -e "  ${Y}Docker requires special installation — package manager alone is not enough.${RESET}"
    echo -e "  ${DIM}Run the official installer:${RESET}"
    echo ""
    echo -e "  ${C}curl -fsSL https://get.docker.com | sh${RESET}"
    echo -e "  ${C}sudo usermod -aG docker \$USER${RESET}"
    echo ""
    echo -e "  ${DIM}Then log out and back in, and re-run preflight.sh${RESET}"
fi

echo ""

# Exit with error code if blockers exist
[ ${#ERRORS[@]} -gt 0 ] && exit 1
exit 0
