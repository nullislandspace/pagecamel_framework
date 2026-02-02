#!/usr/bin/env python3
"""
HTTP/3 connection reuse and sequential request test using aioquic.

Sends multiple sequential GET requests on a single QUIC connection to verify
that the connection remains healthy after each request completes.

Tests:
  1. First download of testfile_1.bin (baseline)
  2. Small GET request (/) to verify connection still works
  3. Second download of testfile_1.bin (must match first)
  4. Upload via PUT (mixed read/write on same connection)
  5. Third download after upload (connection still healthy)

All downloads must produce MD5 = ae525b610cdca28ffed9b81e2cfa47b8
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

EXPECTED_MD5 = "ae525b610cdca28ffed9b81e2cfa47b8"
EXPECTED_SIZE = 31457280
HOST = "test.cavac.at"
PORT = 443
DOWNLOAD_PATH = "/public/pimenu/download/testfile_1.bin"
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


async def do_get(client, path, label):
    """Send GET request and return (status, body_bytes)."""
    stream_id = client._quic.get_next_available_stream_id()
    print(f"  [{label}] GET {path} on stream {stream_id}")
    client._http.send_headers(
        stream_id=stream_id,
        headers=[
            (b":method", b"GET"),
            (b":scheme", b"https"),
            (b":authority", HOST.encode()),
            (b":path", path.encode()),
        ],
        end_stream=True,
    )
    client.transmit()

    data = bytearray()
    done = False
    status = None
    start = asyncio.get_event_loop().time()

    while not done:
        elapsed = asyncio.get_event_loop().time() - start
        if elapsed > TIMEOUT:
            print(f"  [{label}] TIMEOUT after {TIMEOUT}s, received {len(data):,} bytes")
            return status, data
        await asyncio.sleep(0.05)

        events = client._request_events.get(stream_id, [])
        for event in events:
            if isinstance(event, HeadersReceived):
                for name, value in event.headers:
                    if name == b":status":
                        status = value.decode()
            elif isinstance(event, DataReceived):
                data.extend(event.data)
                if event.stream_ended:
                    done = True
        client._request_events[stream_id] = []

    return status, data


async def do_put(client, path, body, label):
    """Send PUT request and return (status, response_body_text)."""
    stream_id = client._quic.get_next_available_stream_id()
    print(f"  [{label}] PUT {path} on stream {stream_id} ({len(body):,} bytes)")
    client._http.send_headers(
        stream_id=stream_id,
        headers=[
            (b":method", b"PUT"),
            (b":scheme", b"https"),
            (b":authority", HOST.encode()),
            (b":path", path.encode()),
            (b"content-length", str(len(body)).encode()),
            (b"content-type", b"application/octet-stream"),
        ],
        end_stream=False,
    )

    chunk_size = 65536
    offset = 0
    while offset < len(body):
        end = min(offset + chunk_size, len(body))
        is_last = (end == len(body))
        client._http.send_data(
            stream_id=stream_id,
            data=body[offset:end],
            end_stream=is_last,
        )
        offset = end
    client.transmit()

    data = bytearray()
    done = False
    status = None
    start = asyncio.get_event_loop().time()

    while not done:
        elapsed = asyncio.get_event_loop().time() - start
        if elapsed > TIMEOUT:
            print(f"  [{label}] TIMEOUT")
            return status, data.decode('utf-8', errors='replace')
        await asyncio.sleep(0.05)

        events = client._request_events.get(stream_id, [])
        for event in events:
            if isinstance(event, HeadersReceived):
                for name, value in event.headers:
                    if name == b":status":
                        status = value.decode()
            elif isinstance(event, DataReceived):
                data.extend(event.data)
                if event.stream_ended:
                    done = True
        client._request_events[stream_id] = []

    return status, data.decode('utf-8', errors='replace').strip()


def verify_download(data, label):
    """Verify download data matches expected MD5 and size."""
    size = len(data)
    md5 = hashlib.md5(data).hexdigest()
    ok = (md5 == EXPECTED_MD5 and size == EXPECTED_SIZE)
    status = "PASS" if ok else "FAIL"
    print(f"  [{label}] {size:,} bytes, MD5={md5} [{status}]")
    return ok


async def main():
    config = QuicConfiguration(is_client=True, alpn_protocols=["h3"])
    config.verify_mode = ssl.CERT_NONE

    print(f"Connecting to {HOST}:{PORT}...")
    async with connect(HOST, PORT, configuration=config, create_protocol=H3Client) as client:
        client._http = H3Connection(client._quic)
        all_ok = True

        # Test 1: First download
        print("\nTest 1: First download")
        status, data = await do_get(client, DOWNLOAD_PATH, "dl1")
        print(f"  Status: {status}")
        if not verify_download(data, "dl1"):
            all_ok = False

        # Test 2: Small GET (connection still works?)
        print("\nTest 2: Small GET / (connection health check)")
        status, data = await do_get(client, "/", "small")
        print(f"  Status: {status}, body: {len(data)} bytes")
        if status in ("200", "301", "302"):
            print("  PASS: Connection still healthy")
        else:
            print(f"  FAIL: Unexpected status {status}")
            all_ok = False

        # Test 3: Second download (same connection)
        print("\nTest 3: Second download (connection reuse)")
        status, data = await do_get(client, DOWNLOAD_PATH, "dl2")
        print(f"  Status: {status}")
        if not verify_download(data, "dl2"):
            all_ok = False

        # Test 4: Upload on same connection
        print("\nTest 4: Upload 1MB (mixed operations)")
        upload_data = os.urandom(1 * 1024 * 1024)
        upload_sha256 = hashlib.sha256(upload_data).hexdigest()
        status, response = await do_put(client, UPLOAD_PATH, upload_data, "upload")
        print(f"  Status: {status}")
        print(f"  Response: {response[:200]}")
        if upload_sha256 in response:
            print("  PASS: Upload checksum verified")
        else:
            print(f"  FAIL: Expected SHA256={upload_sha256}")
            all_ok = False

        # Test 5: Third download after upload
        print("\nTest 5: Download after upload (connection still healthy)")
        status, data = await do_get(client, DOWNLOAD_PATH, "dl3")
        print(f"  Status: {status}")
        if not verify_download(data, "dl3"):
            all_ok = False

        if all_ok:
            print("\nPASS: All connection reuse tests passed")
        else:
            print("\nFAIL: Some tests failed")
        return 0 if all_ok else 1


if __name__ == "__main__":
    rc = asyncio.run(main())
    sys.exit(rc)
