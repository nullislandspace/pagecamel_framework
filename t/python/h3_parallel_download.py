#!/usr/bin/env python3
"""
HTTP/3 parallel download verification using aioquic.

Downloads testfile_1.bin on 3 simultaneous streams over a single QUIC connection.
Each stream's data is checksummed independently. All must match the known-good MD5.

This tests true HTTP/3 multiplexing from a non-curl client.

Expected per stream:
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
NUM_STREAMS = 3
TIMEOUT = 180


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

        # Send NUM_STREAMS requests simultaneously
        stream_ids = []
        for i in range(NUM_STREAMS):
            stream_id = client._quic.get_next_available_stream_id()
            print(f"Stream {i}: sending GET {PATH} on stream_id={stream_id}")
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
            stream_ids.append(stream_id)

        client.transmit()
        print(f"All {NUM_STREAMS} requests sent")

        # Collect data per stream
        buffers = {sid: bytearray() for sid in stream_ids}
        done = {sid: False for sid in stream_ids}
        start = asyncio.get_event_loop().time()
        last_progress = start

        while not all(done.values()):
            now = asyncio.get_event_loop().time()
            if now - start > TIMEOUT:
                print(f"TIMEOUT after {TIMEOUT}s")
                break
            await asyncio.sleep(0.05)

            for sid in stream_ids:
                events = client._request_events.get(sid, [])
                for event in events:
                    if isinstance(event, HeadersReceived):
                        pass  # status logged below if needed
                    elif isinstance(event, DataReceived):
                        buffers[sid].extend(event.data)
                        if event.stream_ended:
                            done[sid] = True
                client._request_events[sid] = []

            # Progress every 5 seconds
            if now - last_progress > 5:
                sizes = [len(buffers[sid]) for sid in stream_ids]
                total = sum(sizes)
                pcts = [f"{s*100//EXPECTED_SIZE}%" for s in sizes]
                print(f"  Progress: {' / '.join(pcts)} (total {total:,} bytes)")
                last_progress = now

        elapsed = asyncio.get_event_loop().time() - start
        print(f"\nCompleted in {elapsed:.1f}s")

        # Verify each stream
        all_ok = True
        for i, sid in enumerate(stream_ids):
            size = len(buffers[sid])
            md5 = hashlib.md5(buffers[sid]).hexdigest()
            status = "PASS" if md5 == EXPECTED_MD5 and size == EXPECTED_SIZE else "FAIL"
            if status == "FAIL":
                all_ok = False
            print(f"Stream {i} (id={sid}): {size:,} bytes, MD5={md5} [{status}]")

        if all_ok:
            print(f"\nPASS: All {NUM_STREAMS} parallel downloads verified")
        else:
            print(f"\nFAIL: Some streams have incorrect data")
        return 0 if all_ok else 1


if __name__ == "__main__":
    rc = asyncio.run(main())
    sys.exit(rc)
