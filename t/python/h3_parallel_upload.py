#!/usr/bin/env python3
"""
HTTP/3 parallel upload verification using aioquic.

Uploads 3 files simultaneously on separate streams over a single QUIC connection.
Each upload uses random data with a known SHA256. The server returns the SHA256
and size of what it received. All must match.

Tests true HTTP/3 upload multiplexing from a non-curl client.
"""

import asyncio
import hashlib
import os
import ssl
import sys

from aioquic.asyncio.client import connect
from aioquic.asyncio.protocol import QuicConnectionProtocol
from aioquic.quic.configuration import QuicConfiguration
from aioquic.h3.connection import H3Connection
from aioquic.h3.events import HeadersReceived, DataReceived

HOST = "test.cavac.at"
PORT = 443
UPLOAD_PATH = "/guest/puttest/static"
NUM_STREAMS = 3
UPLOAD_SIZE = 2 * 1024 * 1024  # 2MB each
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

    # Generate random upload data for each stream
    uploads = []
    for i in range(NUM_STREAMS):
        data = os.urandom(UPLOAD_SIZE)
        sha256 = hashlib.sha256(data).hexdigest()
        uploads.append({"data": data, "sha256": sha256})
        print(f"Stream {i}: {UPLOAD_SIZE:,} bytes, SHA256={sha256[:16]}...")

    print(f"\nConnecting to {HOST}:{PORT}...")
    async with connect(HOST, PORT, configuration=config, create_protocol=H3Client) as client:
        client._http = H3Connection(client._quic)

        # Send all upload requests
        stream_ids = []
        for i in range(NUM_STREAMS):
            stream_id = client._quic.get_next_available_stream_id()
            data = uploads[i]["data"]

            client._http.send_headers(
                stream_id=stream_id,
                headers=[
                    (b":method", b"PUT"),
                    (b":scheme", b"https"),
                    (b":authority", HOST.encode()),
                    (b":path", UPLOAD_PATH.encode()),
                    (b"content-length", str(len(data)).encode()),
                    (b"content-type", b"application/octet-stream"),
                ],
                end_stream=False,
            )

            # Send body in chunks
            chunk_size = 65536
            offset = 0
            while offset < len(data):
                end = min(offset + chunk_size, len(data))
                is_last = (end == len(data))
                client._http.send_data(
                    stream_id=stream_id,
                    data=data[offset:end],
                    end_stream=is_last,
                )
                offset = end

            stream_ids.append(stream_id)
            print(f"Stream {i}: PUT on stream_id={stream_id}")

        client.transmit()
        print(f"All {NUM_STREAMS} uploads sent\n")

        # Wait for all responses
        responses = {sid: bytearray() for sid in stream_ids}
        done = {sid: False for sid in stream_ids}
        start = asyncio.get_event_loop().time()

        while not all(done.values()):
            elapsed = asyncio.get_event_loop().time() - start
            if elapsed > TIMEOUT:
                print(f"TIMEOUT after {TIMEOUT}s")
                break
            await asyncio.sleep(0.05)

            for sid in stream_ids:
                events = client._request_events.get(sid, [])
                for event in events:
                    if isinstance(event, DataReceived):
                        responses[sid].extend(event.data)
                        if event.stream_ended:
                            done[sid] = True
                client._request_events[sid] = []

        elapsed = asyncio.get_event_loop().time() - start
        print(f"Completed in {elapsed:.1f}s\n")

        # Verify each stream
        all_ok = True
        for i, sid in enumerate(stream_ids):
            response_text = responses[sid].decode('utf-8', errors='replace').strip()
            expected_sha256 = uploads[i]["sha256"]
            match = expected_sha256 in response_text and str(UPLOAD_SIZE) in response_text
            status = "PASS" if match else "FAIL"
            if not match:
                all_ok = False
            print(f"Stream {i} (id={sid}): {status}")
            print(f"  Expected: SHA256={expected_sha256[:16]}... size={UPLOAD_SIZE}")
            print(f"  Response: {response_text}")

        if all_ok:
            print(f"\nPASS: All {NUM_STREAMS} parallel uploads verified")
        else:
            print(f"\nFAIL: Some uploads have incorrect data")
        return 0 if all_ok else 1


if __name__ == "__main__":
    rc = asyncio.run(main())
    sys.exit(rc)
