#!/usr/bin/env python3
"""
Wolf WebRTC Sidecar (v2 — shm tap)
----------------------------------
Streams Wolf sessions to browsers via WebRTC, view-only.

How it gets the media (and why not interpipe):
gst-interpipe only connects pipelines *within one process*, so a separate
container can never "listen-to" Wolf's internal buses. Instead, Wolf's
per-session sink pipeline (user-configurable in config.toml) is patched with a
tee that serializes the already-encoded stream through gdppay into an shmsink
socket under /tmp/sockets (a bind mount shared with this container):

  tap_{session_id}_video   (H264/HEVC elementary stream, GDP-framed)
  tap_{session_id}_audio   (Opus elementary stream, GDP-framed)

See apply-wolf-tap.sh for the config.toml patch.

This sidecar watches TAP_DIR for tap_*_video sockets, builds one ingest
pipeline per session (shmsrc ! gdpdepay ! parsebin ! rtp payloader ! tee),
and attaches an independent webrtcbin per connected browser — so each peer
gets its own SDP offer and multiple viewers can co-watch one session.

Endpoints:
  http://<host>:8088/            session list (JSON)
  http://<host>:8088/status      ingest/peer stats (JSON)
  http://<host>:8088/wolf-pin    latest Moonlight pairing PIN URL from Wolf logs
  http://<host>:8088/client      browser client
  ws://<host>:8089/<session_id>  signalling

Known limitations (by design, documented in README):
  - View-only. Input is not forwarded; Moonlight remains the interactive path.
  - A viewer joining mid-stream shows video only from the next IDR frame.
  - Streams exist only while a Moonlight client has an active session.
"""

import asyncio
import concurrent.futures
import json
import logging
import os
import re
import signal
import threading
import time
from typing import Dict, Optional

import gi
gi.require_version('Gst', '1.0')
gi.require_version('GstWebRTC', '1.0')
gi.require_version('GstSdp', '1.0')
from gi.repository import Gst, GLib, GstWebRTC, GstSdp

import websockets
import websockets.server
from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler
from urllib.parse import urlparse

# ── Logging ───────────────────────────────────────────────────────────────────

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s [%(levelname)s] %(name)s: %(message)s',
    datefmt='%H:%M:%S'
)
log = logging.getLogger('wolf-sidecar')

# ── Config ────────────────────────────────────────────────────────────────────

HTTP_PORT   = int(os.environ.get('SIDECAR_HTTP_PORT', 8088))
WS_PORT     = int(os.environ.get('SIDECAR_WS_PORT',   8089))
STUN_SERVER = os.environ.get('STUN_SERVER', 'stun://stun.l.google.com:19302')
TAP_DIR     = os.environ.get('TAP_DIR', '/tmp/sockets')
SCAN_SECS   = float(os.environ.get('TAP_SCAN_SECS', '2'))

TAP_VIDEO_RE = re.compile(r'^tap_(.+)_video$')

Gst.init(None)

# ── GLib thread bridge ────────────────────────────────────────────────────────
# All pipeline graph surgery happens on the GLib main loop thread so it never
# races GStreamer callbacks. Returns a concurrent.futures.Future.

_glib_loop = GLib.MainLoop()

def glib_call(fn, *args):
    fut = concurrent.futures.Future()
    def _run():
        try:
            fut.set_result(fn(*args))
        except Exception as e:  # noqa: BLE001 — surfaced via future
            fut.set_exception(e)
        return False
    GLib.idle_add(_run)
    return fut


# ── Peer ──────────────────────────────────────────────────────────────────────

class Peer:
    """One browser connection: its own webrtcbin + queues inside the session pipeline."""

    _counter = 0

    def __init__(self, session, ws, loop):
        Peer._counter += 1
        self.n = Peer._counter
        self.session = session
        self.ws = ws
        self.loop = loop
        self.webrtcbin: Optional[Gst.Element] = None
        self.queues = []
        self.tee_pads = []  # (tee, pad) pairs to release on teardown

    # -- signalling (called from GStreamer threads) --

    def _send(self, msg: dict):
        asyncio.run_coroutine_threadsafe(self._async_send(msg), self.loop)

    async def _async_send(self, msg: dict):
        try:
            await self.ws.send(json.dumps(msg))
        except Exception:
            pass  # peer going away; teardown happens in ws handler

    # -- graph construction (GLib thread only) --

    def attach(self):
        s = self.session
        pipeline = s.pipeline
        name = f'peer{self.n}'

        self.webrtcbin = Gst.ElementFactory.make('webrtcbin', name)
        self.webrtcbin.set_property('bundle-policy', GstWebRTC.WebRTCBundlePolicy.MAX_BUNDLE)
        self.webrtcbin.set_property('stun-server', STUN_SERVER)
        self.webrtcbin.connect('on-negotiation-needed', self._on_negotiation_needed)
        self.webrtcbin.connect('on-ice-candidate', self._on_ice_candidate)
        pipeline.add(self.webrtcbin)

        for tee in [t for t in (s.video_tee, s.audio_tee) if t is not None]:
            q = Gst.ElementFactory.make('queue', None)
            q.set_property('max-size-buffers', 30)
            q.set_property('leaky', 2)  # downstream — never stall other peers
            pipeline.add(q)
            tee_pad = tee.request_pad_simple('src_%u')
            tee_pad.link(q.get_static_pad('sink'))
            q.link(self.webrtcbin)
            q.sync_state_with_parent()
            self.queues.append(q)
            self.tee_pads.append((tee, tee_pad))

        self.webrtcbin.sync_state_with_parent()
        log.info(f'[{s.session_id}] peer{self.n} attached '
                 f'({len(self.queues)} track(s), total peers: {len(s.peers) + 1})')

    def detach(self):
        pipeline = self.session.pipeline
        for tee, pad in self.tee_pads:
            pad.set_active(False)
            tee.release_request_pad(pad)
        for q in self.queues:
            q.set_state(Gst.State.NULL)
            pipeline.remove(q)
        if self.webrtcbin:
            self.webrtcbin.set_state(Gst.State.NULL)
            pipeline.remove(self.webrtcbin)
            self.webrtcbin = None
        log.info(f'[{self.session.session_id}] peer{self.n} detached')

    # -- webrtcbin callbacks (GStreamer threads) --

    def _on_negotiation_needed(self, element):
        promise = Gst.Promise.new_with_change_func(self._on_offer_created, element, None)
        element.emit('create-offer', None, promise)

    def _on_offer_created(self, promise, element, _):
        promise.wait()
        reply = promise.get_reply()
        if reply is None:
            log.error(f'peer{self.n}: create-offer failed')
            return
        offer = reply.get_value('offer')
        element.emit('set-local-description', offer, None)
        self._send({'type': 'offer', 'sdp': offer.sdp.as_text()})

    def _on_ice_candidate(self, element, mline_index, candidate):
        self._send({'type': 'ice', 'candidate': candidate, 'sdpMLineIndex': mline_index})

    # -- browser messages (asyncio thread; graph-safe ops go via glib_call) --

    def handle_answer(self, sdp_str: str):
        res, sdp = GstSdp.SDPMessage.new_from_text(sdp_str)
        answer = GstWebRTC.WebRTCSessionDescription.new(GstWebRTC.WebRTCSDPType.ANSWER, sdp)
        self.webrtcbin.emit('set-remote-description', answer, None)

    def handle_ice(self, candidate: str, mline_index: int):
        self.webrtcbin.emit('add-ice-candidate', mline_index, candidate)


# ── Session ───────────────────────────────────────────────────────────────────

class TapSession:
    """
    Ingest pipeline for one Wolf session tap:

      shmsrc(tap_<id>_video) ! gdpdepay ! parsebin ─(by caps)→ rtp payloader ! tee ┐
      shmsrc(tap_<id>_audio) ! gdpdepay ! opusparse ! rtpopuspay ! tee ────────────┤
                                                        per-peer: tee ! queue ! webrtcbin
    """

    def __init__(self, session_id: str, video_sock: str, audio_sock: Optional[str], loop):
        self.session_id = session_id
        self.video_sock = video_sock
        self.audio_sock = audio_sock
        self.loop = loop
        self.pipeline: Optional[Gst.Pipeline] = None
        self.video_tee: Optional[Gst.Element] = None
        self.audio_tee: Optional[Gst.Element] = None
        self.peers: Dict[int, Peer] = {}
        self.video_codec = 'pending'
        self.video_bytes = 0
        self.dead = False

    # -- lifecycle (GLib thread) --

    def start(self) -> bool:
        sid = self.session_id
        desc = (
            f'shmsrc socket-path="{self.video_sock}" is-live=true '
            f'! gdpdepay ! parsebin name=pb_{sid} '
            # tee needs a permanent drain so it flows with zero peers
            f'tee name=vtee_{sid} allow-not-linked=true '
        )
        if self.audio_sock:
            desc += (
                f'shmsrc socket-path="{self.audio_sock}" is-live=true '
                f'! gdpdepay ! opusparse ! rtpopuspay pt=96 '
                f'! application/x-rtp,media=audio,encoding-name=OPUS,payload=96 '
                f'! tee name=atee_{sid} allow-not-linked=true '
            )

        try:
            self.pipeline = Gst.parse_launch(desc)
        except GLib.Error as e:
            log.error(f'[{sid}] pipeline parse failed: {e}')
            return False

        self.video_tee = self.pipeline.get_by_name(f'vtee_{sid}')
        self.audio_tee = self.pipeline.get_by_name(f'atee_{sid}') if self.audio_sock else None

        parsebin = self.pipeline.get_by_name(f'pb_{sid}')
        parsebin.connect('pad-added', self._on_parse_pad)

        bus = self.pipeline.get_bus()
        bus.add_signal_watch()
        bus.connect('message', self._on_bus_message)

        if self.pipeline.set_state(Gst.State.PLAYING) == Gst.StateChangeReturn.FAILURE:
            log.error(f'[{sid}] pipeline failed to start')
            return False

        log.info(f'[{sid}] ingest started (video={os.path.basename(self.video_sock)}'
                 f'{", audio" if self.audio_sock else ", no audio tap"})')
        return True

    def _on_parse_pad(self, parsebin, pad):
        """Link the right RTP payloader for whatever codec Wolf negotiated."""
        caps = pad.get_current_caps() or pad.query_caps(None)
        name = caps.get_structure(0).get_name() if caps.get_size() else '?'
        sid = self.session_id

        if name == 'video/x-h264':
            chain = ('h264parse config-interval=-1 ! rtph264pay pt=97 '
                     'config-interval=-1 aggregate-mode=zero-latency '
                     '! application/x-rtp,media=video,encoding-name=H264,payload=97')
            self.video_codec = 'H264'
        elif name == 'video/x-h265':
            chain = ('h265parse config-interval=-1 ! rtph265pay pt=98 config-interval=-1 '
                     '! application/x-rtp,media=video,encoding-name=H265,payload=98')
            self.video_codec = 'H265'
            log.warning(f'[{sid}] HEVC session — most browsers cannot decode this; '
                        f'prefer H264 in the Moonlight client for co-viewing')
        else:
            self.video_codec = f'unsupported:{name}'
            log.error(f'[{sid}] unsupported tapped codec {name} (AV1 co-view not implemented); '
                      f'set the Moonlight client to H264')
            return

        payl = Gst.parse_bin_from_description(chain, True)
        self.pipeline.add(payl)
        payl.sync_state_with_parent()
        pad.link(payl.get_static_pad('sink'))
        payl.link(self.video_tee)

        # count ingest bytes for /status
        payl.get_static_pad('src').add_probe(Gst.PadProbeType.BUFFER, self._count_probe)
        log.info(f'[{sid}] video codec {self.video_codec} → RTP ready')

    def _count_probe(self, pad, info):
        buf = info.get_buffer()
        if buf:
            self.video_bytes += buf.get_size()
        return Gst.PadProbeReturn.OK

    def _on_bus_message(self, bus, message):
        if message.type == Gst.MessageType.ERROR:
            err, dbg = message.parse_error()
            log.error(f'[{self.session_id}] GStreamer: {err.message}')
            # shmsrc errors when Wolf tears the session down — mark dead so the
            # scanner reaps us (and re-creates if the socket comes back).
            self.dead = True

    def stop(self):
        for peer in list(self.peers.values()):
            peer.detach()
        self.peers.clear()
        if self.pipeline:
            self.pipeline.set_state(Gst.State.NULL)
            self.pipeline = None
        log.info(f'[{self.session_id}] ingest stopped')

    # -- peers (called from asyncio via glib_call) --

    def add_peer(self, peer: Peer):
        peer.attach()
        self.peers[peer.n] = peer

    def remove_peer(self, peer: Peer):
        if peer.n in self.peers:
            del self.peers[peer.n]
            peer.detach()


# ── Session registry / tap scanner ────────────────────────────────────────────

class SessionManager:
    def __init__(self, loop):
        self.loop = loop
        self.sessions: Dict[str, TapSession] = {}

    def scan_once(self):
        """Discover tap sockets; start new sessions, reap dead/vanished ones."""
        found = {}
        try:
            for entry in os.scandir(TAP_DIR):
                m = TAP_VIDEO_RE.match(entry.name)
                if m:
                    sid = m.group(1)
                    audio = os.path.join(TAP_DIR, f'tap_{sid}_audio')
                    found[sid] = (entry.path, audio if os.path.exists(audio) else None)
        except FileNotFoundError:
            log.warning(f'TAP_DIR {TAP_DIR} missing — is /tmp/sockets mounted?')
            return

        for sid, (vsock, asock) in found.items():
            if sid not in self.sessions:
                session = TapSession(sid, vsock, asock, self.loop)
                if glib_call(session.start).result(timeout=10):
                    self.sessions[sid] = session
                else:
                    glib_call(session.stop).result(timeout=10)

        for sid in list(self.sessions):
            sess = self.sessions[sid]
            if sid not in found or sess.dead:
                reason = 'tap vanished' if sid not in found else 'pipeline died'
                log.info(f'[{sid}] reaping session ({reason})')
                for peer in list(sess.peers.values()):
                    asyncio.run_coroutine_threadsafe(
                        peer.ws.close(1001, 'session ended'), self.loop)
                glib_call(sess.stop).result(timeout=10)
                del self.sessions[sid]

    async def scan_loop(self):
        while True:
            try:
                self.scan_once()
            except Exception as e:  # noqa: BLE001 — scanner must survive anything
                log.error(f'tap scan error: {e}')
            await asyncio.sleep(SCAN_SECS)

    def status(self):
        return {
            sid: {
                'video_codec': s.video_codec,
                'video_bytes': s.video_bytes,
                'receiving': s.video_bytes > 0,
                'peers': len(s.peers),
                'audio': s.audio_sock is not None,
            }
            for sid, s in self.sessions.items()
        }

    def stop_all(self):
        for s in self.sessions.values():
            glib_call(s.stop).result(timeout=10)
        self.sessions.clear()


# ── WebSocket signalling ──────────────────────────────────────────────────────

async def ws_handler(websocket, manager: SessionManager):
    session_id = websocket.request.path.lstrip('/') or None
    if not session_id:
        await websocket.close(1008, 'Missing session_id in path')
        return

    session = manager.sessions.get(session_id)
    if not session:
        await websocket.close(1011, f'No active tap for session {session_id}')
        return

    peer = Peer(session, websocket, asyncio.get_running_loop())
    glib_call(session.add_peer, peer).result(timeout=10)
    warned_input = False

    try:
        async for raw in websocket:
            try:
                msg = json.loads(raw)
            except json.JSONDecodeError:
                continue
            t = msg.get('type')
            if t == 'answer':
                peer.handle_answer(msg['sdp'])
            elif t == 'ice' and msg.get('candidate'):
                peer.handle_ice(msg['candidate'], msg.get('sdpMLineIndex', 0))
            elif t == 'ping':
                await websocket.send(json.dumps({'type': 'pong'}))
            elif t == 'input' and not warned_input:
                warned_input = True
                await websocket.send(json.dumps(
                    {'type': 'info', 'msg': 'co-view is view-only; use Moonlight for input'}))
    except websockets.exceptions.ConnectionClosed:
        pass
    finally:
        glib_call(session.remove_peer, peer).result(timeout=10)


# ── HTTP ──────────────────────────────────────────────────────────────────────

def get_wolf_pin():
    """Latest Moonlight pairing PIN URL from the wolf container's logs."""
    try:
        import docker
        client = docker.from_env()
        logs = client.containers.get('wolf').logs(tail=400).decode('utf-8', errors='ignore')
        matches = re.findall(r'http://[^\s]+/pin/#[0-9A-Fa-f]+', logs)
        if matches:
            return json.dumps({'pin_url': matches[-1], 'found': True})
        return json.dumps({'pin_url': None, 'found': False})
    except Exception as e:  # noqa: BLE001 — endpoint must always answer
        return json.dumps({'pin_url': None, 'found': False, 'error': str(e)})


def make_http_handler(manager: SessionManager, client_dir: str):
    class Handler(BaseHTTPRequestHandler):
        def do_GET(self):
            path = urlparse(self.path).path.rstrip('/')
            if path == '':
                body = json.dumps({'sessions': list(manager.sessions.keys()),
                                   'ws_port': WS_PORT}).encode()
                self._respond(200, 'application/json', body)
            elif path == '/status':
                self._respond(200, 'application/json', json.dumps(manager.status()).encode())
            elif path == '/wolf-pin':
                self._respond(200, 'application/json', get_wolf_pin().encode())
            elif path in ('/client', '/client/index.html') or path.startswith('/session/'):
                try:
                    with open(os.path.join(client_dir, 'index.html'), 'rb') as f:
                        self._respond(200, 'text/html', f.read())
                except FileNotFoundError:
                    self._respond(404, 'text/plain', b'Not found')
            else:
                self._respond(404, 'text/plain', b'Not found')

        def _respond(self, code, content_type, body):
            self.send_response(code)
            self.send_header('Content-Type', content_type)
            self.send_header('Content-Length', len(body))
            self.send_header('Access-Control-Allow-Origin', '*')
            self.end_headers()
            self.wfile.write(body)

        def log_message(self, fmt, *args):
            pass

    return Handler


# ── Main ──────────────────────────────────────────────────────────────────────

async def main():
    loop = asyncio.get_running_loop()
    manager = SessionManager(loop)

    client_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', 'client'))

    http_server = ThreadingHTTPServer(('0.0.0.0', HTTP_PORT),
                                      make_http_handler(manager, client_dir))
    threading.Thread(target=http_server.serve_forever, daemon=True).start()
    log.info(f'HTTP server on :{HTTP_PORT}')

    threading.Thread(target=_glib_loop.run, daemon=True).start()

    scanner = asyncio.create_task(manager.scan_loop())

    async with websockets.server.serve(
        lambda ws: ws_handler(ws, manager), '0.0.0.0', WS_PORT
    ):
        log.info('Wolf WebRTC Sidecar ready (shm tap mode)')
        log.info(f'  tap dir:   {TAP_DIR}/tap_<session>_video|_audio')
        log.info(f'  HTTP:      http://0.0.0.0:{HTTP_PORT}/  (/status, /wolf-pin, /client)')
        log.info(f'  WebSocket: ws://0.0.0.0:{WS_PORT}/<session_id>')

        stop = loop.create_future()
        loop.add_signal_handler(signal.SIGINT,  stop.set_result, None)
        loop.add_signal_handler(signal.SIGTERM, stop.set_result, None)
        await stop

    scanner.cancel()
    manager.stop_all()
    http_server.shutdown()
    _glib_loop.quit()
    log.info('Sidecar stopped')


if __name__ == '__main__':
    asyncio.run(main())
