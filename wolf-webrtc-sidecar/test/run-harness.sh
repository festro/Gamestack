#!/bin/bash
# run-harness.sh — exercise the sidecar without Wolf, Moonlight, or a GPU.
#
# Stands up a producer container that writes exactly the tap Wolf writes once
# config.toml is patched (parsebin ! mpegtsmux ! shmsink), then drives the
# sidecar with a real webrtcbin peer that completes offer/answer/ICE and counts
# the RTP that actually arrives. Everything runs on the sidecar image, so the
# only requirement is Docker.
#
# Usage:
#   bash test/run-harness.sh            # full run, cleans up after itself
#   bash test/run-harness.sh --keep     # leave containers up for poking
#
# Exit code is non-zero if media never reached the peer, so CI can gate on it.

set -e

KEEP=false
[ "$1" = "--keep" ] && KEEP=true

IMAGE=gamestack-wolf-webrtc:harness
VOL=gs-harness-sockets
SID=12345678
HERE="$(cd "$(dirname "$0")" && pwd)"

G='\033[0;32m'; R='\033[0;31m'; Y='\033[1;33m'; DIM='\033[2m'; RESET='\033[0m'
ok()   { echo -e "  ${G}✓${RESET} $1"; }
bad()  { echo -e "  ${R}✗${RESET} $1"; }
info() { echo -e "  ${DIM}$1${RESET}"; }

cleanup() {
    $KEEP && { info "leaving containers up (--keep)"; return; }
    docker rm -f gsh-sidecar gsh-video gsh-audio >/dev/null 2>&1 || true
    docker volume rm -f "$VOL" >/dev/null 2>&1 || true
}
trap cleanup EXIT

echo ""
echo "  Wolf WebRTC sidecar — offline harness"
echo ""

docker build -q -t "$IMAGE" "$HERE/.." >/dev/null
ok "image built"

docker rm -f gsh-sidecar gsh-video gsh-audio >/dev/null 2>&1 || true
docker volume rm -f "$VOL" >/dev/null 2>&1 || true
docker volume create "$VOL" >/dev/null

# ipc=host matters: the shm transport passes a /dev/shm segment name across the
# socket, and a private per-container /dev/shm cannot resolve it.
docker run -d --name gsh-sidecar --ipc=host -v "$VOL":/tmp/sockets \
    -p 8088:8088 -p 8089:8089 -e TAP_DIR=/tmp/sockets "$IMAGE" >/dev/null
ok "sidecar started"

producer() { # producer <name> <gst-source-chain> <socket> <shm-size>
    docker run -d --name "$1" --ipc=host -v "$VOL":/tmp/sockets --entrypoint sh "$IMAGE" -c \
        "gst-launch-1.0 -q $2 ! parsebin ! mpegtsmux ! shmsink socket-path=/tmp/sockets/$3 \
         shm-size=$4 wait-for-connection=false sync=false async=false" >/dev/null
}

producer gsh-video "videotestsrc is-live=true pattern=ball ! video/x-raw,width=1280,height=720,framerate=30/1 ! x264enc tune=zerolatency key-int-max=30 bitrate=4000" "tap_${SID}_video" 16777216
producer gsh-audio "audiotestsrc is-live=true wave=sine ! audioconvert ! audioresample ! opusenc" "tap_${SID}_audio" 4194304
ok "producers started (mimicking a patched Wolf session)"

info "waiting for ingest…"
for _ in $(seq 1 20); do
    sleep 2
    STATUS=$(curl -s --max-time 5 http://localhost:8088/status || echo '{}')
    echo "$STATUS" | grep -q '"receiving": true' && break
done

echo ""
echo "  status: $STATUS"
FAIL=0
echo "$STATUS" | grep -q '"receiving": true'  && ok "ingest receiving"        || { bad "no ingest";        FAIL=1; }
echo "$STATUS" | grep -q '"video_codec": "H264"' && ok "video codec H264"     || { bad "video not H264";   FAIL=1; }
echo "$STATUS" | grep -q '"audio": true'      && ok "audio tap linked"        || { bad "no audio tap";     FAIL=1; }

echo ""
info "running a real WebRTC peer (offer/answer/ICE, counts delivered RTP)…"
docker cp "$HERE/peer_test.py" gsh-sidecar:/tmp/peer_test.py >/dev/null
if docker exec gsh-sidecar python3 /tmp/peer_test.py "$SID" 15 2>/dev/null | sed 's/^/    /'; then
    ok "media reached the peer"
else
    bad "peer received no media"
    FAIL=1
fi

echo ""
info "second viewer (v1 broke here — peers shared one webrtcbin)…"
docker exec -d gsh-sidecar sh -c "python3 /tmp/peer_test.py $SID 18 > /tmp/p1.log 2>&1"
docker exec -d gsh-sidecar sh -c "python3 /tmp/peer_test.py $SID 18 > /tmp/p2.log 2>&1"
sleep 10
PEERS=$(curl -s --max-time 5 http://localhost:8088/status)
echo "$PEERS" | grep -q '"peers": 2' && ok "two viewers attached at once" || { bad "peer fan-out broken: $PEERS"; FAIL=1; }
sleep 12
BOTH=$(docker exec gsh-sidecar sh -c 'grep -h -c "MEDIA FLOWING" /tmp/p1.log /tmp/p2.log | tr "\n" " "')
[ "$BOTH" = "1 1 " ] && ok "both viewers got media" || { bad "viewers did not both stream ($BOTH)"; FAIL=1; }

echo ""
if [ "$FAIL" -eq 0 ]; then
    echo -e "  ${G}harness passed${RESET}"
else
    echo -e "  ${R}harness FAILED${RESET}"
fi
echo ""
exit $FAIL
