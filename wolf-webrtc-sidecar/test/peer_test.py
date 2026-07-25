#!/usr/bin/env python3
"""
Stand-in for the browser: a real WebRTC peer built on webrtcbin.

Connects to the sidecar's signalling socket, completes offer/answer/ICE, and
counts RTP payload actually delivered over the peer connection. Exits non-zero
unless media arrives, so it can gate a deploy.
"""
import asyncio, json, sys, threading

import gi
gi.require_version('Gst', '1.0')
gi.require_version('GstWebRTC', '1.0')
gi.require_version('GstSdp', '1.0')
from gi.repository import Gst, GstWebRTC, GstSdp, GLib

import websockets

Gst.init(None)

SESSION = sys.argv[1] if len(sys.argv) > 1 else '99887766'
SECONDS = int(sys.argv[2]) if len(sys.argv) > 2 else 12
URL = f'ws://127.0.0.1:8089/{SESSION}'

stats = {'buffers': 0, 'bytes': 0, 'offer_sdp': None, 'ice_state': 'new', 'pads': []}
glib_loop = GLib.MainLoop()


class BrowserPeer:
    def __init__(self, send_json):
        self.send_json = send_json
        # Build explicitly: parse_launch with a lone element returns the element
        # itself rather than a pipeline, so get_by_name would find nothing.
        self.pipe = Gst.Pipeline.new('peer')
        self.wrb = Gst.ElementFactory.make('webrtcbin', 'recv')
        self.wrb.set_property('bundle-policy', GstWebRTC.WebRTCBundlePolicy.MAX_BUNDLE)
        self.pipe.add(self.wrb)
        self.wrb.connect('on-ice-candidate', self._on_ice)
        self.wrb.connect('pad-added', self._on_pad)
        self.wrb.connect('notify::ice-connection-state', self._on_ice_state)
        self.pipe.set_state(Gst.State.PLAYING)

    def _on_ice(self, _el, mline, candidate):
        self.send_json({'type': 'ice', 'candidate': candidate, 'sdpMLineIndex': mline})

    def _on_ice_state(self, el, _param):
        stats['ice_state'] = el.get_property('ice-connection-state').value_nick

    def _on_pad(self, _el, pad):
        if pad.get_direction() != Gst.PadDirection.SRC:
            return
        caps = pad.get_current_caps()
        stats['pads'].append(caps.to_string()[:90] if caps else '?')
        sink = Gst.parse_bin_from_description('queue ! fakesink sync=false', True)
        self.pipe.add(sink)
        sink.sync_state_with_parent()
        pad.link(sink.get_static_pad('sink'))
        pad.add_probe(Gst.PadProbeType.BUFFER, self._count)

    def _count(self, _pad, info):
        buf = info.get_buffer()
        if buf:
            stats['buffers'] += 1
            stats['bytes'] += buf.get_size()
        return Gst.PadProbeReturn.OK

    def handle_offer(self, sdp_text):
        stats['offer_sdp'] = sdp_text
        _, sdp = GstSdp.SDPMessage.new_from_text(sdp_text)
        offer = GstWebRTC.WebRTCSessionDescription.new(GstWebRTC.WebRTCSDPType.OFFER, sdp)
        promise = Gst.Promise.new()
        self.wrb.emit('set-remote-description', offer, promise)
        promise.interrupt()
        promise = Gst.Promise.new_with_change_func(self._on_answer, None, None)
        self.wrb.emit('create-answer', None, promise)

    def _on_answer(self, promise, _a, _b):
        promise.wait()
        reply = promise.get_reply()
        answer = reply.get_value('answer')
        self.wrb.emit('set-local-description', answer, None)
        self.send_json({'type': 'answer', 'sdp': answer.sdp.as_text()})

    def handle_ice(self, candidate, mline):
        self.wrb.emit('add-ice-candidate', mline, candidate)


async def main():
    threading.Thread(target=glib_loop.run, daemon=True).start()
    loop = asyncio.get_running_loop()
    outbox = asyncio.Queue()

    def send_json(msg):
        loop.call_soon_threadsafe(outbox.put_nowait, msg)

    async with websockets.connect(URL) as ws:
        peer = BrowserPeer(send_json)

        async def pump():
            while True:
                msg = await outbox.get()
                await ws.send(json.dumps(msg))

        pump_task = asyncio.create_task(pump())

        async def recv():
            async for raw in ws:
                msg = json.loads(raw)
                if msg.get('type') == 'offer':
                    peer.handle_offer(msg['sdp'])
                elif msg.get('type') == 'ice' and msg.get('candidate'):
                    peer.handle_ice(msg['candidate'], msg.get('sdpMLineIndex', 0))

        recv_task = asyncio.create_task(recv())
        await asyncio.sleep(SECONDS)
        pump_task.cancel()
        recv_task.cancel()

    sdp = stats['offer_sdp'] or ''
    directions = [ln.strip()[2:] for ln in sdp.splitlines()
                  if ln.strip() in ('a=sendonly', 'a=sendrecv', 'a=recvonly', 'a=inactive')]
    print(f'offer received : {bool(sdp)}')
    print(f'offer has H264 : {"H264" in sdp}')
    print(f'offer direction: {", ".join(directions) or "(unspecified)"}')
    print(f'ice state      : {stats["ice_state"]}')
    print(f'incoming pads  : {stats["pads"] or "none"}')
    print(f'RTP buffers    : {stats["buffers"]}')
    print(f'RTP bytes      : {stats["bytes"]}')
    ok = stats['buffers'] > 0 and stats['bytes'] > 0
    print('RESULT         :', 'MEDIA FLOWING' if ok else 'NO MEDIA')
    return 0 if ok else 1


if __name__ == '__main__':
    sys.exit(asyncio.run(main()))
