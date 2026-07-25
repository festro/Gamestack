#!/bin/bash
# apply-wolf-tap.sh
# Patches Wolf's config.toml so each session's encoded stream is also written to
# an shmsink socket in /tmp/sockets, where the WebRTC sidecar can pick it up.
#
# Wolf's own Moonlight path is untouched: the tee's first branch still feeds
# rtpmoonlightpay → appsink exactly as before. The tap branch is leaky and
# allow-not-linked, so a stalled or absent sidecar cannot block Wolf.
#
# Usage:
#   bash apply-wolf-tap.sh [--config PATH] [--revert] [--check]
#
# After applying, restart Wolf:  docker restart wolf

set -e

CONFIG="${DATA_DIR:-$HOME/Git/Gamestack}/wolf-config/cfg/config.toml"
MODE=apply

while [ $# -gt 0 ]; do
    case "$1" in
        --config) CONFIG="$2"; shift 2 ;;
        --revert) MODE=revert; shift ;;
        --check)  MODE=check;  shift ;;
        *) echo "unknown arg: $1"; exit 1 ;;
    esac
done

G='\033[0;32m'; Y='\033[1;33m'; R='\033[0;31m'; DIM='\033[2m'; RESET='\033[0m'
ok()   { echo -e "  ${G}✓${RESET}  $1"; }
warn() { echo -e "  ${Y}!${RESET}  $1"; }
fail() { echo -e "  ${R}✗${RESET}  $1"; exit 1; }

[ -f "$CONFIG" ] || fail "config.toml not found: $CONFIG"

MARKER='wolf_webrtc_tap'

# ── Check ─────────────────────────────────────────────────────────────────────
if grep -q "$MARKER" "$CONFIG"; then
    APPLIED=yes
else
    APPLIED=no
fi

if [ "$MODE" = check ]; then
    [ "$APPLIED" = yes ] && ok "tap is applied in $CONFIG" || warn "tap is NOT applied in $CONFIG"
    exit 0
fi

# ── Revert ────────────────────────────────────────────────────────────────────
if [ "$MODE" = revert ]; then
    [ "$APPLIED" = no ] && { warn "tap not present — nothing to revert"; exit 0; }
    BACKUP=$(ls -t "${CONFIG}.pre-tap."* 2>/dev/null | head -1)
    [ -n "$BACKUP" ] || fail "no ${CONFIG}.pre-tap.* backup found; revert by hand"
    cp -a "$BACKUP" "$CONFIG"
    ok "reverted from $BACKUP"
    echo -e "  ${DIM}Restart Wolf:  docker restart wolf${RESET}"
    exit 0
fi

# ── Apply ─────────────────────────────────────────────────────────────────────
[ "$APPLIED" = yes ] && { warn "tap already applied — nothing to do"; exit 0; }

BACKUP="${CONFIG}.pre-tap.$(date +%Y%m%d-%H%M%S)"
cp -a "$CONFIG" "$BACKUP"
ok "backup: $BACKUP"

# Wolf substitutes {session_id} in sink pipelines, so socket names are per-session.
# shm-size 16MB: a few frames of headroom at 4K bitrates.
python3 - "$CONFIG" <<'PYEOF'
import re, sys

path = sys.argv[1]
src = open(path).read()

VIDEO_OLD = """default_sink = '''rtpmoonlightpay_video name=moonlight_pay payload_size={payload_size} fec_percentage={fec_percentage} min_required_fec_packets={min_required_fec_packets} !
appsink sync=false name=wolf_udp_sink
'''"""

VIDEO_NEW = """# wolf_webrtc_tap: tee one branch to Moonlight (unchanged), one to the sidecar.
# MPEG-TS (not GDP) because its PAT/PMT repeat, so a sidecar attaching
# mid-session still learns the caps; GDP sends them once and never again.
default_sink = '''tee name=wolf_webrtc_tap_v allow-not-linked=true !
queue max-size-buffers=3 leaky=downstream !
rtpmoonlightpay_video name=moonlight_pay payload_size={payload_size} fec_percentage={fec_percentage} min_required_fec_packets={min_required_fec_packets} !
appsink sync=false name=wolf_udp_sink
wolf_webrtc_tap_v. !
queue max-size-buffers=3 leaky=downstream !
parsebin !
mpegtsmux !
shmsink socket-path=/tmp/sockets/tap_{session_id}_video shm-size=16777216 wait-for-connection=false sync=false async=false
'''"""

AUDIO_OLD = """default_sink = '''rtpmoonlightpay_audio name=moonlight_pay packet_duration={packet_duration} encrypt={encrypt} aes_key="{aes_key}" aes_iv="{aes_iv}" !
appsink name=wolf_udp_sink'''"""

AUDIO_NEW = """# wolf_webrtc_tap: tee one branch to Moonlight (unchanged), one to the sidecar.
default_sink = '''tee name=wolf_webrtc_tap_a allow-not-linked=true !
queue max-size-buffers=3 leaky=downstream !
rtpmoonlightpay_audio name=moonlight_pay packet_duration={packet_duration} encrypt={encrypt} aes_key="{aes_key}" aes_iv="{aes_iv}" !
appsink name=wolf_udp_sink
wolf_webrtc_tap_a. !
queue max-size-buffers=3 leaky=downstream !
parsebin !
mpegtsmux !
shmsink socket-path=/tmp/sockets/tap_{session_id}_audio shm-size=4194304 wait-for-connection=false sync=false async=false'''"""

for old, new, label in ((VIDEO_OLD, VIDEO_NEW, 'video'), (AUDIO_OLD, AUDIO_NEW, 'audio')):
    if old not in src:
        sys.exit(f'FAILED: stock {label} default_sink not found — config.toml differs from '
                 f'the expected Wolf layout. Patch it by hand (see this script for the shape).')
    src = src.replace(old, new, 1)

open(path, 'w').write(src)
print('patched video + audio default_sink')
PYEOF

ok "config.toml patched"
echo ""
echo -e "  ${DIM}Next:${RESET}"
echo -e "  ${DIM}  docker restart wolf${RESET}"
echo -e "  ${DIM}  Start a Moonlight session, then check:  curl -s http://localhost:8088/status${RESET}"
echo -e "  ${DIM}  Revert any time:  bash apply-wolf-tap.sh --revert${RESET}"
echo ""
