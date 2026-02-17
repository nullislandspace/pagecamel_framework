#!/usr/bin/env python3
"""
HTTP/3 single download verification using aioquic.

Downloads testfile_1.bin and verifies MD5 checksum matches the known-good value.
This validates our HTTP/3 server with a completely independent QUIC/HTTP/3 stack.

Expected:
  - File size: 31,457,280 bytes
  - MD5: ae525b610cdca28ffed9b81e2cfa47b8
"""

import asyncio
import hashlib
import ssl
import sys

from aioquic.asyncio.client import connect
from aioquic.asyncio.protocol import QuicConnectionProtocol
from aioquic.quic.configuration import QuicConfiguration
from aioquic.h3.connection import H3Connection
from aioquic.h3.events import HeadersReceived, DataReceived

EXPECTED_MD5 = "ae525b610cdca28ffed9b81e2cfa47b8"
EXPECTED_SIZE = 31457280
HOST = "test.cavac.at"
PORT = 443
PATH = "/public/pimenu/download/testfile_1.bin"
TIMEOUT = 120


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


async def main():
    config = QuicConfiguration(is_client=True, alpn_protocols=["h3"])
    config.verify_mode = ssl.CERT_NONE

    print(f"Connecting to {HOST}:{PORT}...")
    async with connect(HOST, PORT, configuration=config, create_protocol=H3Client) as client:
        client._http = H3Connection(client._quic)

        stream_id = client._quic.get_next_available_stream_id()
        print(f"Sending GET {PATH} on stream {stream_id}")
        client._http.send_headers(
            stream_id=stream_id,
            headers=[
                (b":method", b"GET"),
                (b":scheme", b"https"),
                (b":authority", HOST.encode()),
                (b":path", PATH.encode()),
            ],
            end_stream=True,
        )
        client.transmit()

        data = bytearray()
        done = False
        headers_received = False
        start = asyncio.get_event_loop().time()

        while not done:
            elapsed = asyncio.get_event_loop().time() - start
            if elapsed > TIMEOUT:
                print(f"TIMEOUT after {TIMEOUT}s, received {len(data)} bytes")
                break
            await asyncio.sleep(0.05)

            events = client._request_events.get(stream_id, [])
            for event in events:
                if isinstance(event, HeadersReceived):
                    status = None
                    for name, value in event.headers:
                        if name == b":status":
                            status = value.decode()
                    print(f"Response status: {status}")
                    headers_received = True
                elif isinstance(event, DataReceived):
                    data.extend(event.data)
                    if event.stream_ended:
                        done = True
            client._request_events[stream_id] = []

        elapsed = asyncio.get_event_loop().time() - start
        md5 = hashlib.md5(data).hexdigest()
        size = len(data)

        print(f"Received: {size:,} bytes in {elapsed:.1f}s")
        print(f"MD5:      {md5}")
        print(f"Expected: {EXPECTED_MD5}")

        ok = True
        if md5 != EXPECTED_MD5:
            print("FAIL: MD5 mismatch!")
            ok = False
        if size != EXPECTED_SIZE:
            print(f"FAIL: Size mismatch! Expected {EXPECTED_SIZE:,}")
            ok = False

        if ok:
            print("PASS: Single download verified")
        return 0 if ok else 1


if __name__ == "__main__":
    rc = asyncio.run(main())
    sys.exit(rc)
