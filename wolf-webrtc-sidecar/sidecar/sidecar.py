#!/usr/bin/env python3
"""
Wolf WebRTC Sidecar
-------------------
Taps Wolf's GStreamer interpipe output and re-streams it to browsers via WebRTC.

Wolf publishes encoded video/audio on interpipe buses named:
  {session_id}_video
  {session_id}_audio

This sidecar discovers active session IDs by watching /var/run/wolf/wolf.sock
(via the Wolf API) and spins up a webrtcsink pipeline for each active session.

Each session gets its own WebRTC endpoint accessible at:
  http://<host>:8088/session/<session_id>

A session list is available at:
  http://<host>:8088/
"""

import asyncio
import json
import logging
import os
import signal
import sys
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
from http.server import HTTPServer, BaseHTTPRequestHandler
from urllib.parse import urlparse
import socket

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

# Session IDs can be passed explicitly or auto-discovered.
# Format: comma-separated list of session IDs
# e.g. WOLF_SESSION_IDS=6323913000772626619,4161966709011769559
MANUAL_SESSION_IDS = [
    s.strip() for s in os.environ.get('WOLF_SESSION_IDS', '').split(',')
    if s.strip()
]

Gst.init(None)

# ── Signalling ────────────────────────────────────────────────────────────────
# Simple per-session signalling: each browser connects via WebSocket,
# receives an SDP offer, sends back an SDP answer + ICE candidates.

class SignallingPeer:
    def __init__(self, session_id: str, ws):
        self.session_id = session_id
        self.ws = ws
        self.webrtcbin: Optional[Gst.Element] = None
        self.pipeline: Optional[Gst.Pipeline] = None
        self._ice_queue = []
        self._ready = False

    async def send(self, msg: dict):
        try:
            await self.ws.send(json.dumps(msg))
        except Exception as e:
            log.warning(f'[{self.session_id}] send error: {e}')

    async def send_offer(self, sdp: str):
        await self.send({'type': 'offer', 'sdp': sdp})

    async def send_ice(self, candidate: str, sdp_mline_index: int):
        await self.send({
            'type': 'ice',
            'candidate': candidate,
            'sdpMLineIndex': sdp_mline_index
        })


# ── GStreamer Pipeline ────────────────────────────────────────────────────────

class WolfWebRTCSession:
    """
    One GStreamer pipeline per Wolf session.
    Taps the interpipe buses Wolf published for that session
    and feeds into webrtcbin.
    """

    def __init__(self, session_id: str, loop: asyncio.AbstractEventLoop):
        self.session_id = session_id
        self.loop = loop
        self.pipeline: Optional[Gst.Pipeline] = None
        self.webrtcbin: Optional[Gst.Element] = None
        self.peers: Dict[str, SignallingPeer] = {}  # ws_id → peer
        self._lock = threading.Lock()
        self._running = False

    def _probe_codec(self, probe_timeout: float = 3.0) -> 'Optional[str]':
        """
        Probe the Wolf interpipe bus for this session to detect the video codec.
        Returns 'H264', 'HEVC', or None if caps could not be read within timeout.

        Builds a minimal throwaway pipeline:
          interpipesrc -> fakesink (sync=false)
        Attaches a pad probe on the sink pad to read caps, then tears it down.
        """
        sid = self.session_id
        detected = [None]
        done = threading.Event()

        probe_str = (
            f'interpipesrc listen-to={sid}_video is-live=true max-buffers=1 '
            f'leaky-type=downstream ! fakesink name=probe_sink sync=false'
        )

        try:
            probe_pipeline = Gst.parse_launch(probe_str)
        except Exception as e:
            log.warning(f'[{sid}] Codec probe pipeline failed to parse: {e}')
            return None

        sink = probe_pipeline.get_by_name('probe_sink')
        sink_pad = sink.get_static_pad('sink') if sink else None

        def on_pad_probe(pad, info):
            caps = pad.get_current_caps()
            if caps and not caps.is_empty() and not caps.is_any():
                struct = caps.get_structure(0)
                name = struct.get_name() if struct else ''
                if 'x-h264' in name:
                    detected[0] = 'H264'
                elif 'x-h265' in name or 'x-hevc' in name:
                    detected[0] = 'HEVC'
            if detected[0]:
                done.set()
            return Gst.PadProbeReturn.OK

        if sink_pad:
            sink_pad.add_probe(Gst.PadProbeType.BUFFER, on_pad_probe)

        probe_pipeline.set_state(Gst.State.PLAYING)
        done.wait(timeout=probe_timeout)
        probe_pipeline.set_state(Gst.State.NULL)

        return detected[0]

    def start(self):
        """
        Probe Wolf's interpipe bus for codec, then build and start the pipeline.
        Refuses to start if Wolf is using HEVC (not supported in most browsers
        via WebRTC). Returns False with a clear log message in that case.
        """
        sid = self.session_id

        log.info(f'[{sid}] Probing Wolf interpipe for codec...')
        codec = self._probe_codec()

        if codec is None:
            log.warning(
                f'[{sid}] Could not detect codec — Wolf may not be streaming yet. '
                f'Start a session in Moonlight first, then reconnect.'
            )
            return False

        if codec == 'HEVC':
            log.error(
                f'[{sid}] Wolf is using HEVC — not supported by Chrome/Firefox via WebRTC. '
                f'To fix: comment out [[gstreamer.video.hevc_encoders]] blocks in '
                f'wolf-config/cfg/config.toml and restart Wolf. '
                f'H264 will then be selected automatically.'
            )
            return False

        log.info(f'[{sid}] Codec detected: {codec} — building pipeline')

        pipeline_str = f"""
            interpipesrc
                name=video_src
                listen-to={sid}_video
                is-live=true
                stream-sync=restart-ts
                max-bytes=0
                max-buffers=1
                leaky-type=downstream
            ! queue max-size-buffers=5 leaky=downstream
            ! h264parse
            ! rtph264pay config-interval=-1 aggregate-mode=zero-latency
            ! application/x-rtp,media=video,encoding-name=H264,payload=97
            ! webrtcbin.sink_0

            interpipesrc
                name=audio_src
                listen-to={sid}_audio
                is-live=true
                stream-sync=restart-ts
                max-bytes=0
                max-buffers=3
                block=false
            ! queue max-size-buffers=5 leaky=downstream
            ! opusparse
            ! rtpopuspay
            ! application/x-rtp,media=audio,encoding-name=OPUS,payload=96
            ! webrtcbin.sink_1

            webrtcbin
                name=webrtcbin
                bundle-policy=max-bundle
                stun-server={STUN_SERVER}
        """

        self.pipeline = Gst.parse_launch(pipeline_str)
        self.webrtcbin = self.pipeline.get_by_name('webrtcbin')

        if not self.webrtcbin:
            log.error(f'[{sid}] Failed to get webrtcbin from pipeline')
            return False

        # Connect webrtcbin signals
        self.webrtcbin.connect('on-negotiation-needed', self._on_negotiation_needed)
        self.webrtcbin.connect('on-ice-candidate', self._on_ice_candidate)

        # Bus message handler
        bus = self.pipeline.get_bus()
        bus.add_signal_watch()
        bus.connect('message', self._on_bus_message)

        ret = self.pipeline.set_state(Gst.State.PLAYING)
        if ret == Gst.StateChangeReturn.FAILURE:
            log.error(f'[{sid}] Pipeline failed to start')
            return False

        self._running = True
        log.info(f'[{sid}] Pipeline started — tapping interpipes {sid}_video / {sid}_audio')
        return True

    def stop(self):
        if self.pipeline:
            self.pipeline.set_state(Gst.State.NULL)
            self._running = False
            log.info(f'[{self.session_id}] Pipeline stopped')

    def add_peer(self, peer: SignallingPeer):
        """Add a new browser peer to this session's webrtcbin."""
        with self._lock:
            self.peers[id(peer.ws)] = peer
            peer.webrtcbin = self.webrtcbin
            peer.pipeline = self.pipeline
        log.info(f'[{self.session_id}] Peer connected (total: {len(self.peers)})')

    def remove_peer(self, peer: SignallingPeer):
        with self._lock:
            self.peers.pop(id(peer.ws), None)
        log.info(f'[{self.session_id}] Peer disconnected (remaining: {len(self.peers)})')

    # ── GStreamer callbacks ───────────────────────────────────────────────────

    def _on_negotiation_needed(self, element):
        """Called when webrtcbin is ready to create an offer."""
        promise = Gst.Promise.new_with_change_func(self._on_offer_created, element, None)
        element.emit('create-offer', None, promise)

    def _on_offer_created(self, promise, element, user_data):
        promise.wait()
        reply = promise.get_reply()
        offer = reply.get_value('offer')
        element.emit('set-local-description', offer, None)

        sdp_text = offer.sdp.as_text()
        log.debug(f'[{self.session_id}] Offer created, sending to {len(self.peers)} peers')

        # Send offer to all connected peers
        asyncio.run_coroutine_threadsafe(
            self._broadcast_offer(sdp_text),
            self.loop
        )

    async def _broadcast_offer(self, sdp: str):
        with self._lock:
            peers = list(self.peers.values())
        for peer in peers:
            await peer.send_offer(sdp)

    def _on_ice_candidate(self, element, mline_index, candidate):
        asyncio.run_coroutine_threadsafe(
            self._broadcast_ice(candidate, mline_index),
            self.loop
        )

    async def _broadcast_ice(self, candidate: str, mline_index: int):
        with self._lock:
            peers = list(self.peers.values())
        for peer in peers:
            await peer.send_ice(candidate, mline_index)

    def _on_bus_message(self, bus, message):
        t = message.type
        if t == Gst.MessageType.ERROR:
            err, debug = message.parse_error()
            log.error(f'[{self.session_id}] GStreamer error: {err.message} | {debug}')
            # Interpipe source will error if no Wolf session is active yet —
            # this is expected when waiting for Wolf to start a stream.
        elif t == Gst.MessageType.WARNING:
            warn, debug = message.parse_warning()
            log.warning(f'[{self.session_id}] GStreamer warning: {warn.message}')
        elif t == Gst.MessageType.STATE_CHANGED:
            if message.src == self.pipeline:
                old, new, _ = message.parse_state_changed()
                log.debug(f'[{self.session_id}] Pipeline state: {old.value_nick} → {new.value_nick}')

    def handle_answer(self, sdp_str: str):
        """Apply an SDP answer received from a browser peer."""
        _, sdp = GstSdp.SDPMessage.new_from_text(sdp_str)
        answer = GstWebRTC.WebRTCSessionDescription.new(
            GstWebRTC.WebRTCSDPType.ANSWER, sdp
        )
        self.webrtcbin.emit('set-remote-description', answer, None)

    def handle_ice(self, candidate: str, sdp_mline_index: int):
        """Add an ICE candidate received from a browser peer."""
        self.webrtcbin.emit('add-ice-candidate', sdp_mline_index, candidate)


# ── Session Manager ───────────────────────────────────────────────────────────

class SessionManager:
    def __init__(self, loop: asyncio.AbstractEventLoop):
        self.loop = loop
        self.sessions: Dict[str, WolfWebRTCSession] = {}

    def get_or_create(self, session_id: str) -> WolfWebRTCSession:
        if session_id not in self.sessions:
            session = WolfWebRTCSession(session_id, self.loop)
            if session.start():
                self.sessions[session_id] = session
                log.info(f'Session created: {session_id}')
            else:
                log.error(f'Failed to start session: {session_id}')
        return self.sessions.get(session_id)

    def list_sessions(self):
        return list(self.sessions.keys())

    def stop_all(self):
        for session in self.sessions.values():
            session.stop()
        self.sessions.clear()


# ── WebSocket Signalling Server ───────────────────────────────────────────────

async def ws_handler(websocket, manager: SessionManager):
    """
    WebSocket URL: ws://<host>:8089/<session_id>
    Each browser connects here to receive offer + exchange ICE candidates.
    """
    path = websocket.request.path.lstrip('/')
    session_id = path or None

    if not session_id:
        await websocket.close(1008, 'Missing session_id in path')
        return

    log.info(f'WS connection for session {session_id}')

    session = manager.get_or_create(session_id)
    if not session:
        await websocket.close(1011, f'Could not start session {session_id}')
        return

    peer = SignallingPeer(session_id, websocket)
    session.add_peer(peer)

    try:
        async for raw in websocket:
            try:
                msg = json.loads(raw)
            except json.JSONDecodeError:
                continue

            msg_type = msg.get('type')

            if msg_type == 'answer':
                log.info(f'[{session_id}] Got answer from browser')
                session.handle_answer(msg['sdp'])

            elif msg_type == 'ice':
                session.handle_ice(msg['candidate'], msg.get('sdpMLineIndex', 0))

            elif msg_type == 'ping':
                await peer.send({'type': 'pong'})

    except websockets.exceptions.ConnectionClosed:
        pass
    finally:
        session.remove_peer(peer)


# ── HTTP Server (session list + static client) ────────────────────────────────

def make_http_handler(manager: SessionManager, client_dir: str):
    class Handler(BaseHTTPRequestHandler):
        def do_GET(self):
            parsed = urlparse(self.path)
            path = parsed.path.rstrip('/')

            if path == '' or path == '/':
                # Session list as JSON
                sessions = manager.list_sessions()
                body = json.dumps({
                    'sessions': sessions,
                    'ws_port': WS_PORT
                }).encode()
                self._respond(200, 'application/json', body)

            elif path == '/client' or path == '/client/index.html':
                html_path = os.path.join(client_dir, 'index.html')
                try:
                    with open(html_path, 'rb') as f:
                        self._respond(200, 'text/html', f.read())
                except FileNotFoundError:
                    self._respond(404, 'text/plain', b'Not found')

            elif path.startswith('/session/'):
                # /session/<id> → serve browser client
                html_path = os.path.join(client_dir, 'index.html')
                try:
                    with open(html_path, 'rb') as f:
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
            pass  # suppress default access log

    return Handler


# ── Main ──────────────────────────────────────────────────────────────────────

async def main():
    loop = asyncio.get_running_loop()
    manager = SessionManager(loop)

    # Pre-start sessions for any manually configured IDs
    for sid in MANUAL_SESSION_IDS:
        log.info(f'Pre-starting session from WOLF_SESSION_IDS: {sid}')
        manager.get_or_create(sid)

    client_dir = os.path.join(os.path.dirname(__file__), '..', 'client')
    client_dir = os.path.abspath(client_dir)

    # HTTP server in a thread
    http_handler = make_http_handler(manager, client_dir)
    http_server = HTTPServer(('0.0.0.0', HTTP_PORT), http_handler)
    http_thread = threading.Thread(target=http_server.serve_forever, daemon=True)
    http_thread.start()
    log.info(f'HTTP server on :{HTTP_PORT}')

    # GLib main loop for GStreamer (in a thread)
    glib_loop = GLib.MainLoop()
    glib_thread = threading.Thread(target=glib_loop.run, daemon=True)
    glib_thread.start()

    # WebSocket signalling server
    log.info(f'WebSocket signalling on :{WS_PORT}')
    async with websockets.server.serve(
        lambda ws: ws_handler(ws, manager),
        '0.0.0.0',
        WS_PORT
    ):
        log.info(f'Wolf WebRTC Sidecar ready')
        log.info(f'  HTTP:      http://0.0.0.0:{HTTP_PORT}/')
        log.info(f'  WebSocket: ws://0.0.0.0:{WS_PORT}/<session_id>')
        log.info(f'  Client:    http://0.0.0.0:{HTTP_PORT}/client')

        # Keep running until interrupted
        stop = loop.create_future()
        loop.add_signal_handler(signal.SIGINT,  stop.set_result, None)
        loop.add_signal_handler(signal.SIGTERM, stop.set_result, None)
        await stop

    manager.stop_all()
    http_server.shutdown()
    glib_loop.quit()
    log.info('Sidecar stopped')


if __name__ == '__main__':
    asyncio.run(main())
