#!/usr/bin/env python3
"""Test HTTP/3 multiplexing with simultaneous streams"""
import asyncio
import ssl
import sys

print("Starting...", flush=True)

from aioquic.asyncio.client import connect
from aioquic.asyncio.protocol import QuicConnectionProtocol
from aioquic.quic.configuration import QuicConfiguration
from aioquic.h3.connection import H3Connection
from aioquic.h3.events import HeadersReceived, DataReceived

print("Imports done", flush=True)

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
    print("Creating config...", flush=True)
    config = QuicConfiguration(is_client=True, alpn_protocols=["h3"])
    config.verify_mode = ssl.CERT_NONE

    print("Connecting to test.cavac.at:443...", flush=True)
    async with connect("test.cavac.at", 443, configuration=config, create_protocol=H3Client) as client:
        print("Connected!", flush=True)
        client._http = H3Connection(client._quic)

        # Send TWO requests simultaneously
        urls = [
            "/public/pimenu/download/testfile_1.bin",
            "/public/pimenu/download/testfile_2.bin",
        ]

        stream_ids = []
        for url in urls:
            stream_id = client._quic.get_next_available_stream_id()
            print(f"Sending request on stream {stream_id}: {url}", flush=True)
            client._http.send_headers(
                stream_id=stream_id,
                headers=[
                    (b":method", b"GET"),
                    (b":scheme", b"https"),
                    (b":authority", b"test.cavac.at"),
                    (b":path", url.encode()),
                ],
                end_stream=True,
            )
            stream_ids.append(stream_id)

        # Transmit
        client.transmit()
        print(f"Requests sent on streams: {stream_ids}", flush=True)

        # Wait for responses with timeout
        received = {sid: 0 for sid in stream_ids}
        done = {sid: False for sid in stream_ids}
        timeout = 90  # 90 seconds
        start = asyncio.get_event_loop().time()
        last_progress = start

        while not all(done.values()):
            now = asyncio.get_event_loop().time()
            if now - start > timeout:
                print(f"TIMEOUT after {timeout}s", flush=True)
                break
            await asyncio.sleep(0.1)

            progress_made = False
            for sid in stream_ids:
                events = client._request_events.get(sid, [])
                for event in events:
                    if isinstance(event, HeadersReceived):
                        print(f"Stream {sid}: Headers received", flush=True)
                        progress_made = True
                    elif isinstance(event, DataReceived):
                        received[sid] += len(event.data)
                        progress_made = True
                        if event.stream_ended:
                            done[sid] = True
                            print(f"Stream {sid}: Complete, {received[sid]} bytes", flush=True)
                client._request_events[sid] = []

            # Print progress every 2 seconds
            if progress_made:
                last_progress = now
            if now - last_progress > 2:
                total = sum(received.values())
                print(f"Progress: stream0={received[stream_ids[0]]:,} bytes, stream4={received[stream_ids[1]]:,} bytes, total={total:,} bytes", flush=True)
                last_progress = now

        print(f"\nResults:", flush=True)
        for sid in stream_ids:
            status = "COMPLETE" if done[sid] else "INCOMPLETE"
            print(f"  Stream {sid}: {received[sid]:,} bytes - {status}", flush=True)

if __name__ == "__main__":
    print("Running main...", flush=True)
    asyncio.run(main())
    print("Done", flush=True)
