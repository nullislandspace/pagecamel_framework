#!/usr/bin/env python3
"""
HTTP/3 upload verification using aioquic.

Uploads data via PUT to /guest/puttest/static and verifies the server returns
the correct SHA256 checksum and file size.

Tests:
  1. Small known-data upload (exact checksum verification)
  2. Large random upload (5MB, checksum round-trip)
  3. Multiple uploads on same connection (connection reuse)
"""

import asyncio
import hashlib
import json
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


async def do_upload(client, data, label):
    """Upload data and return the response body as string."""
    sha256_local = hashlib.sha256(data).hexdigest()

    stream_id = client._quic.get_next_available_stream_id()
    print(f"  [{label}] PUT {UPLOAD_PATH} on stream {stream_id} ({len(data):,} bytes)")

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

    # Send body in chunks to avoid overwhelming the connection
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
    client.transmit()

    # Wait for response
    response_data = bytearray()
    done = False
    start = asyncio.get_event_loop().time()

    while not done:
        elapsed = asyncio.get_event_loop().time() - start
        if elapsed > TIMEOUT:
            print(f"  [{label}] TIMEOUT after {TIMEOUT}s")
            return None, sha256_local
        await asyncio.sleep(0.05)

        events = client._request_events.get(stream_id, [])
        for event in events:
            if isinstance(event, DataReceived):
                response_data.extend(event.data)
                if event.stream_ended:
                    done = True
        client._request_events[stream_id] = []

    response_text = response_data.decode('utf-8', errors='replace').strip()
    return response_text, sha256_local


async def main():
    config = QuicConfiguration(is_client=True, alpn_protocols=["h3"])
    config.verify_mode = ssl.CERT_NONE

    print(f"Connecting to {HOST}:{PORT}...")
    async with connect(HOST, PORT, configuration=config, create_protocol=H3Client) as client:
        client._http = H3Connection(client._quic)
        all_ok = True

        # Test 1: Small known-data upload
        print("\nTest 1: Small known-data upload")
        small_data = b"Hello HTTP/3 Upload Test"
        small_sha256 = hashlib.sha256(small_data).hexdigest()
        response, _ = await do_upload(client, small_data, "small")
        if response is not None:
            print(f"  Response: {response}")
            if small_sha256 in response and "24" in response:
                print("  PASS: Small upload checksum verified")
            else:
                print(f"  FAIL: Expected SHA256={small_sha256}, size=24")
                all_ok = False
        else:
            print("  FAIL: No response")
            all_ok = False

        # Test 2: 5MB random upload
        print("\nTest 2: 5MB random upload")
        large_data = os.urandom(5 * 1024 * 1024)
        large_sha256 = hashlib.sha256(large_data).hexdigest()
        response, _ = await do_upload(client, large_data, "5MB")
        if response is not None:
            print(f"  Response: {response[:200]}")
            if large_sha256 in response:
                print("  PASS: 5MB upload checksum verified")
            else:
                print(f"  FAIL: Expected SHA256={large_sha256}")
                all_ok = False
        else:
            print("  FAIL: No response")
            all_ok = False

        # Test 3: Connection reuse - another upload on same connection
        print("\nTest 3: Connection reuse (second 1MB upload)")
        reuse_data = os.urandom(1 * 1024 * 1024)
        reuse_sha256 = hashlib.sha256(reuse_data).hexdigest()
        response, _ = await do_upload(client, reuse_data, "reuse")
        if response is not None:
            print(f"  Response: {response[:200]}")
            if reuse_sha256 in response:
                print("  PASS: Connection reuse upload verified")
            else:
                print(f"  FAIL: Expected SHA256={reuse_sha256}")
                all_ok = False
        else:
            print("  FAIL: No response")
            all_ok = False

        if all_ok:
            print("\nPASS: All upload tests passed")
        else:
            print("\nFAIL: Some upload tests failed")
        return 0 if all_ok else 1


if __name__ == "__main__":
    rc = asyncio.run(main())
    sys.exit(rc)
