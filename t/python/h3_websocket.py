#!/usr/bin/env python3
"""
HTTP/3 WebSocket test using aioquic (Extended CONNECT, RFC 9220).

Connects to wss://test.cavac.at/guest/kaffeesim/ws over HTTP/3 using the
Extended CONNECT method with :protocol=websocket. Exchanges JSON messages
with the KaffeeSim coffee machine simulator backend.

WebSocket framing is done manually since this is a raw HTTP/3 tunnel.

KaffeeSim protocol (JSON over WebSocket text frames):
  Client→Server: {"type":"PING"}
  Client→Server: {"type":"NOTIFY","varname":"update_all"}
  Client→Server: {"type":"SET","varname":"...","varvalue":N}
  Server→Client: {"type":"PING"}
  Server→Client: {"type":"VALUE","varname":"...","varval":"..."}
"""

import asyncio
import hashlib
import json
import os
import ssl
import struct
import sys

from aioquic.asyncio.client import connect
from aioquic.asyncio.protocol import QuicConnectionProtocol
from aioquic.quic.configuration import QuicConfiguration
from aioquic.h3.connection import H3Connection
from aioquic.h3.events import HeadersReceived, DataReceived

HOST = "test.cavac.at"
PORT = 443
WS_PATH = "/guest/kaffeesim/ws"
TIMEOUT = 30


class H3Client(QuicConnectionProtocol):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self._http = None
        self._request_events = {}

    def quic_event_received(self, event):
        if self._http is None:
            return
        for h3_event in self._http.handle_event(event):
            stream_id = getattr(h3_event, 'stream_id', None)
            if stream_id is not None:
                if stream_id not in self._request_events:
                    self._request_events[stream_id] = []
                self._request_events[stream_id].append(h3_event)


def ws_encode_text(text):
    """Encode a WebSocket text frame (client-to-server, masked)."""
    payload = text.encode('utf-8')
    mask_key = os.urandom(4)

    # FIN=1, opcode=1 (text)
    frame = bytearray()
    frame.append(0x81)

    # Mask bit = 1 + payload length
    plen = len(payload)
    if plen < 126:
        frame.append(0x80 | plen)
    elif plen < 65536:
        frame.append(0x80 | 126)
        frame.extend(struct.pack('!H', plen))
    else:
        frame.append(0x80 | 127)
        frame.extend(struct.pack('!Q', plen))

    frame.extend(mask_key)

    # Mask payload
    for i, b in enumerate(payload):
        frame.append(b ^ mask_key[i % 4])

    return bytes(frame)


def ws_encode_close(code=1000, reason=""):
    """Encode a WebSocket close frame (client-to-server, masked)."""
    mask_key = os.urandom(4)
    payload = struct.pack('!H', code) + reason.encode('utf-8')

    frame = bytearray()
    frame.append(0x88)  # FIN=1, opcode=8 (close)
    frame.append(0x80 | len(payload))
    frame.extend(mask_key)

    for i, b in enumerate(payload):
        frame.append(b ^ mask_key[i % 4])

    return bytes(frame)


def ws_decode_frame(data):
    """Decode a WebSocket frame. Returns (opcode, payload, bytes_consumed) or None."""
    if len(data) < 2:
        return None

    byte0 = data[0]
    byte1 = data[1]

    fin = (byte0 >> 7) & 1
    opcode = byte0 & 0x0F
    masked = (byte1 >> 7) & 1
    plen = byte1 & 0x7F

    offset = 2
    if plen == 126:
        if len(data) < 4:
            return None
        plen = struct.unpack('!H', data[2:4])[0]
        offset = 4
    elif plen == 127:
        if len(data) < 10:
            return None
        plen = struct.unpack('!Q', data[2:10])[0]
        offset = 10

    if masked:
        mask_key = data[offset:offset+4]
        offset += 4

    if len(data) < offset + plen:
        return None

    payload = data[offset:offset+plen]
    if masked:
        payload = bytes(b ^ mask_key[i % 4] for i, b in enumerate(payload))

    return (opcode, payload, offset + plen)


OPCODE_NAMES = {0: "continuation", 1: "text", 2: "binary", 8: "close", 9: "ping", 10: "pong"}


async def main():
    config = QuicConfiguration(is_client=True, alpn_protocols=["h3"])
    config.verify_mode = ssl.CERT_NONE

    print(f"Connecting to {HOST}:{PORT}...")
    async with connect(HOST, PORT, configuration=config, create_protocol=H3Client) as client:
        client._http = H3Connection(client._quic)

        # Send Extended CONNECT for WebSocket (RFC 9220)
        stream_id = client._quic.get_next_available_stream_id()
        print(f"Sending Extended CONNECT to {WS_PATH} on stream {stream_id}")

        client._http.send_headers(
            stream_id=stream_id,
            headers=[
                (b":method", b"CONNECT"),
                (b":protocol", b"websocket"),
                (b":scheme", b"https"),
                (b":authority", HOST.encode()),
                (b":path", WS_PATH.encode()),
                (b"sec-websocket-version", b"13"),
                (b"sec-websocket-protocol", b"base64"),
                (b"origin", f"https://{HOST}".encode()),
            ],
            end_stream=False,
        )
        client.transmit()

        # Helper: collect tunnel data from events
        tunnel_data = bytearray()

        async def drain_events(timeout_s):
            nonlocal tunnel_data
            start = asyncio.get_event_loop().time()
            while True:
                elapsed = asyncio.get_event_loop().time() - start
                if elapsed > timeout_s:
                    break
                await asyncio.sleep(0.05)
                events = client._request_events.get(stream_id, [])
                if not events:
                    continue
                for event in events:
                    if isinstance(event, DataReceived):
                        tunnel_data.extend(event.data)
                client._request_events[stream_id] = []

        def collect_ws_messages():
            """Parse all complete WebSocket frames from tunnel_data, return list of (opcode, payload)."""
            nonlocal tunnel_data
            msgs = []
            while True:
                result = ws_decode_frame(tunnel_data)
                if result is None:
                    break
                opcode, payload, consumed = result
                tunnel_data = tunnel_data[consumed:]
                msgs.append((opcode, payload))
            return msgs

        # Wait for response headers (expect 200)
        response_status = None
        start = asyncio.get_event_loop().time()

        while response_status is None:
            elapsed = asyncio.get_event_loop().time() - start
            if elapsed > TIMEOUT:
                print("TIMEOUT waiting for response headers")
                return 1
            await asyncio.sleep(0.05)

            events = client._request_events.get(stream_id, [])
            for event in events:
                if isinstance(event, HeadersReceived):
                    for name, value in event.headers:
                        if name == b":status":
                            response_status = value.decode()
                    print(f"Response status: {response_status}")
                elif isinstance(event, DataReceived):
                    tunnel_data.extend(event.data)
            client._request_events[stream_id] = []

        if response_status != "200":
            print(f"FAIL: Expected status 200, got {response_status}")
            return 1

        print("WebSocket tunnel established via Extended CONNECT\n")

        all_ok = True

        # ------------------------------------------------------------------
        # Test 1: Send PING, expect PING back
        # ------------------------------------------------------------------
        print("Test 1: PING/PONG")
        ping_msg = json.dumps({"type": "PING"}).encode()
        ws_frame = ws_encode_text(ping_msg.decode())
        client._http.send_data(stream_id=stream_id, data=ws_frame, end_stream=False)
        client.transmit()

        await drain_events(3)
        msgs = collect_ws_messages()

        got_ping = False
        for opcode, payload in msgs:
            if opcode == 1:
                try:
                    obj = json.loads(payload)
                    print(f"  Received: {obj}")
                    if obj.get("type") == "PING":
                        got_ping = True
                except json.JSONDecodeError:
                    print(f"  Received non-JSON: {payload[:100]}")

        if got_ping:
            print("  PASS: Server replied with PING\n")
        else:
            print("  FAIL: No PING response received\n")
            all_ok = False

        # ------------------------------------------------------------------
        # Test 2: Send NOTIFY update_all, expect VALUE messages
        # ------------------------------------------------------------------
        print("Test 2: NOTIFY update_all → VALUE messages")
        notify_msg = json.dumps({"type": "NOTIFY", "varname": "update_all"}).encode()
        ws_frame = ws_encode_text(notify_msg.decode())
        client._http.send_data(stream_id=stream_id, data=ws_frame, end_stream=False)
        client.transmit()

        await drain_events(5)
        msgs = collect_ws_messages()

        value_vars = set()
        for opcode, payload in msgs:
            if opcode == 1:
                try:
                    obj = json.loads(payload)
                    if obj.get("type") == "VALUE":
                        varname = obj.get("varname", "?")
                        varval = obj.get("varval", "?")
                        value_vars.add(varname)
                        print(f"  VALUE: {varname} = {varval}")
                except json.JSONDecodeError:
                    pass

        # Expect at least some key variables
        expected_vars = {"boiler_temp", "boiler_waterlevel", "production_enable"}
        found = expected_vars & value_vars
        if len(found) >= 2:
            print(f"  PASS: Received {len(value_vars)} variables ({len(found)}/{len(expected_vars)} key vars)\n")
        else:
            print(f"  FAIL: Only got {len(value_vars)} variables, missing key vars\n")
            all_ok = False

        # ------------------------------------------------------------------
        # Test 3: Ongoing VALUE stream (simulator runs continuously)
        # ------------------------------------------------------------------
        print("Test 3: Continuous VALUE stream (2 second sample)")
        await drain_events(2)
        msgs = collect_ws_messages()

        continuous_count = 0
        for opcode, payload in msgs:
            if opcode == 1:
                try:
                    obj = json.loads(payload)
                    if obj.get("type") == "VALUE":
                        continuous_count += 1
                except json.JSONDecodeError:
                    pass

        if continuous_count > 0:
            print(f"  PASS: Received {continuous_count} VALUE updates in 2s\n")
        else:
            print("  FAIL: No continuous updates received\n")
            all_ok = False

        # ------------------------------------------------------------------
        # Test 4: Graceful close
        # ------------------------------------------------------------------
        print("Test 4: Graceful WebSocket close")
        close_frame = ws_encode_close(1000, "test complete")
        client._http.send_data(stream_id=stream_id, data=close_frame, end_stream=False)
        client.transmit()

        await drain_events(2)
        msgs = collect_ws_messages()

        close_ack = False
        for opcode, payload in msgs:
            oname = OPCODE_NAMES.get(opcode, str(opcode))
            print(f"  Received: [{oname}] {len(payload)} bytes")
            if opcode == 8:
                close_ack = True

        # End the HTTP/3 stream
        client._http.send_data(stream_id=stream_id, data=b"", end_stream=True)
        client.transmit()

        if close_ack:
            print("  PASS: Close acknowledged\n")
        else:
            print("  WARN: No close ack (may be normal)\n")

        # ------------------------------------------------------------------
        # Results
        # ------------------------------------------------------------------
        print("--- Results ---")
        print(f"Extended CONNECT: {'PASS' if response_status == '200' else 'FAIL'}")
        print(f"PING/PONG:        {'PASS' if got_ping else 'FAIL'}")
        print(f"VALUE messages:   {'PASS' if len(found) >= 2 else 'FAIL'} ({len(value_vars)} vars)")
        print(f"Continuous stream: {'PASS' if continuous_count > 0 else 'FAIL'} ({continuous_count} updates)")
        print(f"Close handshake:  {'PASS' if close_ack else 'WARN'}")

        if all_ok:
            print("\nPASS: WebSocket over HTTP/3 works")
        else:
            print("\nFAIL: WebSocket test failed")
        return 0 if all_ok else 1


if __name__ == "__main__":
    rc = asyncio.run(main())
    sys.exit(rc)
