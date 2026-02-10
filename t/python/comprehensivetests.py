#!/usr/bin/env python3
"""
Comprehensive HTTP protocol test suite.

Tests HTTP/1.1, HTTP/2, and HTTP/3 across 11 test categories (30 total tests):
   1. Consecutive downloads, no connection reuse
   2. Consecutive downloads, with connection reuse
   3. Parallel downloads, separate connections
   4. Parallel downloads, shared connection (HTTP/2 + HTTP/3 only)
   5. Consecutive uploads with checksum verification
   6. Parallel uploads, separate connections
   7. Parallel uploads, shared connection (HTTP/2 + HTTP/3 only)
   8. Consecutive WebSocket tests (30s each)
   9. Parallel WebSocket tests, separate connections (30s)
  10. Parallel WebSocket tests, shared connection (HTTP/2 + HTTP/3 only)
  11. Small file (30 KB) consecutive download stress test, no reuse

Usage:
  python3 comprehensivetests.py                        # run all tests
  python3 comprehensivetests.py --protocol http3       # run only HTTP/3 tests
  python3 comprehensivetests.py --test 4               # run test 4 across applicable protocols
  python3 comprehensivetests.py --protocol http2 --test 8
  python3 comprehensivetests.py --list                 # list all test categories
  python3 comprehensivetests.py --iterations 5         # 5 iterations instead of 10
  python3 comprehensivetests.py --small-iter 50        # 50 small-file downloads instead of 100
  python3 comprehensivetests.py --live                  # test against cavac.at instead of test.cavac.at
"""

import argparse
import asyncio
import hashlib
import json
import logging
import os
import ssl
import struct
import sys
import time
import warnings

# Force all output to stdout (libraries may write to stderr)
sys.stderr = sys.stdout

# Suppress warnings and logging from libraries
warnings.filterwarnings('ignore')
logging.disable(logging.CRITICAL)

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
HOST = "test.cavac.at"
PORT = 443
DOWNLOAD_PATH = "/public/pimenu/download/testfile_1.bin"
SMALL_DOWNLOAD_PATH = "/public/pimenu/download/test_30k.bin"
UPLOAD_PATH = "/guest/puttest/static"
WS_PATH = "/guest/kaffeesim/"
EXPECTED_MD5 = "ae525b610cdca28ffed9b81e2cfa47b8"
EXPECTED_SIZE = 31457280  # 31 MB
WS_DURATION = 30  # seconds per WebSocket test

DOWNLOAD_URL = f"https://{HOST}:{PORT}{DOWNLOAD_PATH}"
SMALL_DOWNLOAD_URL = f"https://{HOST}:{PORT}{SMALL_DOWNLOAD_PATH}"
UPLOAD_URL = f"https://{HOST}:{PORT}{UPLOAD_PATH}"

# Globals populated at startup / from CLI
NUM_ITERATIONS = 10
SMALL_ITERATIONS = 100
TESTFILE_DATA = None
UPLOAD_SHA256 = None
SMALL_FILE_DATA = None
SMALL_EXPECTED_MD5 = None
SMALL_EXPECTED_SIZE = None


# ---------------------------------------------------------------------------
# Dependency checks
# ---------------------------------------------------------------------------
def check_dependencies():
    """Verify all required Python packages are installed."""
    missing = []

    try:
        import httpx  # noqa: F401
    except ImportError:
        missing.append(("httpx[http2]", "pip install httpx[http2]"))

    try:
        import aioquic  # noqa: F401
    except ImportError:
        missing.append(("aioquic", "pip install aioquic"))

    try:
        import websockets  # noqa: F401
    except ImportError:
        missing.append(("websockets", "pip install websockets"))

    try:
        import h2  # noqa: F401
    except ImportError:
        missing.append(("h2", "pip install h2"))

    if missing:
        print("Missing dependencies:")
        for name, cmd in missing:
            print(f"  {name}: {cmd}")
        sys.exit(1)


# ---------------------------------------------------------------------------
# Test result tracking
# ---------------------------------------------------------------------------
class TestResult:
    def __init__(self, name, passed, error=""):
        self.name = name
        self.passed = passed
        self.error = error


results = []

# Per-test timeout: generous upper bound to prevent hangs
TEST_TIMEOUT = None  # computed in main() from iteration counts


async def run_test(name, coro):
    """Execute a single test coroutine, print status, record result."""
    print(f"{name} ... ", end="", flush=True)
    try:
        passed, error = await asyncio.wait_for(coro, timeout=TEST_TIMEOUT)
        if passed:
            print("OK")
            results.append(TestResult(name, True))
        else:
            print("FAILED")
            print(f"    {error}")
            results.append(TestResult(name, False, error))
    except asyncio.TimeoutError:
        print("FAILED")
        msg = f"test exceeded {TEST_TIMEOUT}s global timeout"
        print(f"    {msg}")
        results.append(TestResult(name, False, msg))
    except Exception as exc:
        print("FAILED")
        print(f"    Exception: {exc}")
        results.append(TestResult(name, False, str(exc)))


def print_summary():
    """Print final pass/fail summary."""
    failed = [r for r in results if not r.passed]
    print()
    if not failed:
        print(f"all tests OK ({len(results)} tests)")
    else:
        print(f"{len(failed)} tests failed (out of {len(results)}):")
        for r in failed:
            print(f"  - {r.name}")
            if r.error:
                print(f"      {r.error}")


def all_passed():
    return all(r.passed for r in results)


# ---------------------------------------------------------------------------
# Shared utility: checksum verification
# ---------------------------------------------------------------------------
def verify_download(data):
    """Check MD5 and size of downloaded data. Returns (ok, error_detail)."""
    size = len(data)
    md5 = hashlib.md5(data).hexdigest()
    errors = []
    if md5 != EXPECTED_MD5:
        errors.append(f"MD5 mismatch: got {md5}, expected {EXPECTED_MD5}")
    if size != EXPECTED_SIZE:
        errors.append(f"size mismatch: got {size}, expected {EXPECTED_SIZE}")
    if errors:
        return False, "; ".join(errors)
    return True, ""


def verify_small_download(data):
    """Check MD5 and size of small file download. Returns (ok, error_detail)."""
    size = len(data)
    md5 = hashlib.md5(data).hexdigest()
    errors = []
    if md5 != SMALL_EXPECTED_MD5:
        errors.append(f"MD5 mismatch: got {md5}, expected {SMALL_EXPECTED_MD5}")
    if size != SMALL_EXPECTED_SIZE:
        errors.append(f"size mismatch: got {size}, expected {SMALL_EXPECTED_SIZE}")
    if errors:
        return False, "; ".join(errors)
    return True, ""


def verify_upload_response(response_text, local_sha256, local_size):
    """Verify server response contains expected SHA256 and size."""
    errors = []
    if local_sha256 not in response_text:
        errors.append(f"SHA256 {local_sha256} not in response")
    if str(local_size) not in response_text:
        errors.append(f"size {local_size} not in response")
    if errors:
        return False, "; ".join(errors)
    return True, ""


# ---------------------------------------------------------------------------
# Shared utility: WebSocket framing (for HTTP/2 and HTTP/3 manual tunnels)
# ---------------------------------------------------------------------------
def ws_encode_text(text):
    """Encode a WebSocket text frame (client-to-server, masked)."""
    payload = text.encode('utf-8')
    mask_key = os.urandom(4)
    frame = bytearray()
    frame.append(0x81)  # FIN=1, opcode=1 (text)
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
        if len(data) < offset + 4:
            return None
        mask_key = data[offset:offset + 4]
        offset += 4
    if len(data) < offset + plen:
        return None
    payload = data[offset:offset + plen]
    if masked:
        payload = bytes(b ^ mask_key[i % 4] for i, b in enumerate(payload))
    return (opcode, payload, offset + plen)


# ===========================================================================
# HTTP/1.1 and HTTP/2 tests (httpx)
# ===========================================================================

# --- Downloads ---

async def httpx_download_consecutive_no_reuse(http2):
    """Test 1: consecutive downloads, no connection reuse."""
    import httpx
    url = DOWNLOAD_URL
    for i in range(NUM_ITERATIONS):
        async with httpx.AsyncClient(http2=http2, verify=False,
                                     timeout=httpx.Timeout(120.0)) as client:
            resp = await client.get(url)
            ok, err = verify_download(resp.content)
            if not ok:
                return False, f"iteration {i + 1}/{NUM_ITERATIONS}: {err}"
    return True, ""


async def httpx_download_consecutive_reuse(http2):
    """Test 2: consecutive downloads, with connection reuse."""
    import httpx
    url = DOWNLOAD_URL
    async with httpx.AsyncClient(http2=http2, verify=False,
                                 timeout=httpx.Timeout(120.0)) as client:
        for i in range(NUM_ITERATIONS):
            resp = await client.get(url)
            ok, err = verify_download(resp.content)
            if not ok:
                return False, f"iteration {i + 1}/{NUM_ITERATIONS}: {err}"
    return True, ""


async def httpx_download_parallel_separate(http2):
    """Test 3: parallel downloads, separate connections."""
    import httpx
    url = DOWNLOAD_URL

    async def task(i):
        async with httpx.AsyncClient(http2=http2, verify=False,
                                     timeout=httpx.Timeout(120.0)) as client:
            resp = await client.get(url)
            return verify_download(resp.content)

    task_results = await asyncio.gather(*[task(i) for i in range(NUM_ITERATIONS)])
    for i, (ok, err) in enumerate(task_results):
        if not ok:
            return False, f"task {i + 1}/{NUM_ITERATIONS}: {err}"
    return True, ""


async def httpx_download_parallel_shared():
    """Test 4: parallel downloads, shared HTTP/2 connection."""
    import httpx
    url = DOWNLOAD_URL
    async with httpx.AsyncClient(http2=True, verify=False,
                                 timeout=httpx.Timeout(120.0)) as client:
        tasks = [client.get(url) for _ in range(NUM_ITERATIONS)]
        responses = await asyncio.gather(*tasks)
        for i, resp in enumerate(responses):
            ok, err = verify_download(resp.content)
            if not ok:
                return False, f"stream {i + 1}/{NUM_ITERATIONS}: {err}"
    return True, ""


# --- Uploads ---

async def httpx_upload_consecutive(http2):
    """Test 5: consecutive uploads with checksum verification."""
    import httpx
    url = UPLOAD_URL
    for i in range(NUM_ITERATIONS):
        async with httpx.AsyncClient(http2=http2, verify=False,
                                     timeout=httpx.Timeout(120.0)) as client:
            resp = await client.put(url, content=TESTFILE_DATA,
                                    headers={"content-type": "application/octet-stream"})
            ok, err = verify_upload_response(resp.text, UPLOAD_SHA256, EXPECTED_SIZE)
            if not ok:
                return False, f"iteration {i + 1}/{NUM_ITERATIONS}: {err}"
    return True, ""


async def httpx_upload_parallel_separate(http2):
    """Test 6: parallel uploads, separate connections."""
    import httpx
    url = UPLOAD_URL

    async def task(i):
        async with httpx.AsyncClient(http2=http2, verify=False,
                                     timeout=httpx.Timeout(120.0)) as client:
            resp = await client.put(url, content=TESTFILE_DATA,
                                    headers={"content-type": "application/octet-stream"})
            return verify_upload_response(resp.text, UPLOAD_SHA256, EXPECTED_SIZE)

    task_results = await asyncio.gather(*[task(i) for i in range(NUM_ITERATIONS)])
    for i, (ok, err) in enumerate(task_results):
        if not ok:
            return False, f"task {i + 1}/{NUM_ITERATIONS}: {err}"
    return True, ""


async def httpx_upload_parallel_shared():
    """Test 7: parallel uploads, shared HTTP/2 connection."""
    import httpx
    url = UPLOAD_URL
    async with httpx.AsyncClient(http2=True, verify=False,
                                 timeout=httpx.Timeout(120.0)) as client:
        tasks = [client.put(url, content=TESTFILE_DATA,
                            headers={"content-type": "application/octet-stream"})
                 for _ in range(NUM_ITERATIONS)]
        responses = await asyncio.gather(*tasks)
        for i, resp in enumerate(responses):
            ok, err = verify_upload_response(resp.text, UPLOAD_SHA256, EXPECTED_SIZE)
            if not ok:
                return False, f"stream {i + 1}/{NUM_ITERATIONS}: {err}"
    return True, ""


# --- Small file stress test ---

async def httpx_small_download_stress(http2):
    """Test 11: small file consecutive download stress test, no reuse."""
    import httpx
    url = SMALL_DOWNLOAD_URL
    for i in range(SMALL_ITERATIONS):
        async with httpx.AsyncClient(http2=http2, verify=False,
                                     timeout=httpx.Timeout(30.0)) as client:
            resp = await client.get(url)
            ok, err = verify_small_download(resp.content)
            if not ok:
                return False, f"iteration {i + 1}/{SMALL_ITERATIONS}: {err}"
    return True, ""


# --- HTTP/1.1 WebSocket (websockets library) ---

async def ws_test_h1(duration=WS_DURATION):
    """Single HTTP/1.1 WebSocket test session."""
    import websockets
    ssl_ctx = ssl.create_default_context()
    ssl_ctx.check_hostname = False
    ssl_ctx.verify_mode = ssl.CERT_NONE

    uri = f"wss://{HOST}{WS_PATH}"
    async with websockets.connect(uri, ssl=ssl_ctx,
                                  subprotocols=["pagecamel"]) as ws:
        # Send NOTIFY to trigger VALUE messages
        await ws.send(json.dumps({"type": "NOTIFY", "varname": "update_all"}))

        # Wait for at least one VALUE message to confirm connectivity
        got_value = False
        deadline = time.monotonic() + 10.0
        while time.monotonic() < deadline:
            try:
                reply = await asyncio.wait_for(ws.recv(), timeout=1.0)
                obj = json.loads(reply)
                if obj.get("type") == "PING":
                    await ws.send(json.dumps({"type": "PONG"}))
                elif obj.get("type") == "VALUE":
                    got_value = True
                    break
            except asyncio.TimeoutError:
                pass
        if not got_value:
            return False, "no VALUE message received after NOTIFY"

        # Monitor for duration, responding to server PINGs
        message_count = 0
        last_message_time = time.monotonic()
        end_time = time.monotonic() + duration

        while time.monotonic() < end_time:
            try:
                msg = await asyncio.wait_for(ws.recv(), timeout=1.0)
                obj = json.loads(msg)
                if obj.get("type") == "PING":
                    await ws.send(json.dumps({"type": "PONG"}))
                else:
                    message_count += 1
                    last_message_time = time.monotonic()
            except asyncio.TimeoutError:
                if time.monotonic() - last_message_time > 10:
                    return False, f"stall detected after {message_count} messages"

        if message_count == 0:
            return False, "no messages received during monitoring"

    return True, ""


async def h1_ws_consecutive():
    """Test 8: consecutive HTTP/1.1 WebSocket tests."""
    for i in range(NUM_ITERATIONS):
        ok, err = await ws_test_h1()
        if not ok:
            return False, f"iteration {i + 1}/{NUM_ITERATIONS}: {err}"
    return True, ""


async def h1_ws_parallel_separate():
    """Test 9: parallel HTTP/1.1 WebSocket tests, separate connections."""
    task_results = await asyncio.gather(*[ws_test_h1() for _ in range(NUM_ITERATIONS)])
    for i, (ok, err) in enumerate(task_results):
        if not ok:
            return False, f"task {i + 1}/{NUM_ITERATIONS}: {err}"
    return True, ""


# ===========================================================================
# HTTP/2 WebSocket tests (h2 + asyncio)
# ===========================================================================

class H2WebSocketClient:
    """Async HTTP/2 WebSocket via Extended CONNECT (RFC 8441)."""

    def __init__(self):
        self.reader = None
        self.writer = None
        self.conn = None
        self.stream_id = None
        self.tunnel_data = bytearray()

    async def connect(self):
        """Establish HTTP/2 connection and open WebSocket tunnel."""
        import h2.connection
        import h2.config
        import h2.events

        ssl_ctx = ssl.create_default_context()
        ssl_ctx.check_hostname = False
        ssl_ctx.verify_mode = ssl.CERT_NONE
        ssl_ctx.set_alpn_protocols(['h2'])

        self.reader, self.writer = await asyncio.open_connection(
            HOST, PORT, ssl=ssl_ctx)

        config = h2.config.H2Configuration(client_side=True)
        self.conn = h2.connection.H2Connection(config=config)
        self.conn.initiate_connection()
        self._send()

        # Receive server SETTINGS
        enable_connect = False
        data = await asyncio.wait_for(self.reader.read(65535), timeout=10.0)
        events = self.conn.receive_data(data)
        self._send()

        for event in events:
            if isinstance(event, h2.events.RemoteSettingsChanged):
                if 0x8 in event.changed_settings:
                    enable_connect = event.changed_settings[0x8].new_value == 1

        if not enable_connect:
            raise RuntimeError("Server does not support Extended CONNECT (RFC 8441)")

        # Send Extended CONNECT
        self.stream_id = self.conn.get_next_available_stream_id()
        headers = [
            (':method', 'CONNECT'),
            (':protocol', 'websocket'),
            (':scheme', 'https'),
            (':authority', HOST),
            (':path', WS_PATH),
            ('sec-websocket-version', '13'),
            ('sec-websocket-protocol', 'pagecamel'),
            ('origin', f'https://{HOST}'),
        ]
        self.conn.send_headers(self.stream_id, headers, end_stream=False)
        self._send()

        # Wait for 200 response
        import h2.events as h2e
        deadline = time.monotonic() + 10.0
        while time.monotonic() < deadline:
            data = await asyncio.wait_for(self.reader.read(65535), timeout=10.0)
            if not data:
                raise RuntimeError("Connection closed while waiting for response")
            events = self.conn.receive_data(data)
            self._send()
            for event in events:
                if isinstance(event, h2e.ResponseReceived):
                    status = None
                    for hname, hval in event.headers:
                        key = hname if isinstance(hname, str) else hname.decode()
                        val = hval if isinstance(hval, str) else hval.decode()
                        if key == ':status':
                            status = val
                            break
                    if status != '200':
                        raise RuntimeError(f"Expected 200, got {status}")
                    return True
                elif isinstance(event, h2e.DataReceived):
                    self.tunnel_data.extend(event.data)
                    self.conn.acknowledge_received_data(len(event.data), event.stream_id)
                    self._send()

        raise RuntimeError("Timeout waiting for Extended CONNECT response")

    def _send(self):
        data = self.conn.data_to_send()
        if data:
            self.writer.write(data)

    async def send_ws_frame(self, frame_bytes):
        self.conn.send_data(self.stream_id, frame_bytes, end_stream=False)
        self._send()
        await self.writer.drain()

    async def receive_ws_messages(self, duration_s):
        """Read tunnel data for duration_s seconds, return list of (opcode, payload)."""
        import h2.events as h2e
        end_time = time.monotonic() + duration_s
        messages = []

        while time.monotonic() < end_time:
            try:
                data = await asyncio.wait_for(self.reader.read(65535), timeout=0.5)
                if not data:
                    break
                events = self.conn.receive_data(data)
                self._send()
                for event in events:
                    if isinstance(event, h2e.DataReceived):
                        if event.stream_id == self.stream_id:
                            self.tunnel_data.extend(event.data)
                        self.conn.acknowledge_received_data(len(event.data), event.stream_id)
                        self._send()
                    elif isinstance(event, (h2e.StreamEnded, h2e.StreamReset)):
                        break
            except asyncio.TimeoutError:
                pass

            # Parse accumulated frames
            while True:
                result = ws_decode_frame(self.tunnel_data)
                if result is None:
                    break
                opcode, payload, consumed = result
                self.tunnel_data = self.tunnel_data[consumed:]
                messages.append((opcode, payload))

        return messages

    async def close(self):
        try:
            close_frame = ws_encode_close(1000, "test complete")
            self.conn.send_data(self.stream_id, close_frame, end_stream=False)
            self._send()
            await self.writer.drain()
            # Brief wait for close ack
            try:
                data = await asyncio.wait_for(self.reader.read(65535), timeout=2.0)
                if data:
                    self.conn.receive_data(data)
            except (asyncio.TimeoutError, Exception):
                pass
            self.conn.end_stream(self.stream_id)
            self._send()
            await self.writer.drain()
        except Exception:
            pass
        finally:
            if self.writer:
                self.writer.close()
                try:
                    await self.writer.wait_closed()
                except Exception:
                    pass


async def ws_test_h2(duration=WS_DURATION):
    """Single HTTP/2 WebSocket test session."""
    client = H2WebSocketClient()
    try:
        await client.connect()

        # Send NOTIFY to trigger VALUE messages
        await client.send_ws_frame(ws_encode_text(
            json.dumps({"type": "NOTIFY", "varname": "update_all"})))

        # Wait for at least one VALUE message to confirm connectivity
        got_value = False
        deadline = time.monotonic() + 10.0
        while time.monotonic() < deadline and not got_value:
            chunk = min(2.0, deadline - time.monotonic())
            msgs = await client.receive_ws_messages(chunk)
            for op, p in msgs:
                if op == 1:
                    try:
                        obj = json.loads(p)
                        if obj.get("type") == "PING":
                            await client.send_ws_frame(ws_encode_text(json.dumps({"type": "PONG"})))
                        elif obj.get("type") == "VALUE":
                            got_value = True
                    except (json.JSONDecodeError, UnicodeDecodeError):
                        pass
        if not got_value:
            return False, "no VALUE message received after NOTIFY"

        # Monitor, responding to server PINGs
        message_count = 0
        last_message_time = time.monotonic()
        remaining = duration
        while remaining > 0:
            chunk = min(remaining, 5.0)
            msgs = await client.receive_ws_messages(chunk)
            got_data = False
            for op, p in msgs:
                if op == 1:
                    try:
                        obj = json.loads(p)
                        if obj.get("type") == "PING":
                            await client.send_ws_frame(ws_encode_text(json.dumps({"type": "PONG"})))
                        else:
                            message_count += 1
                            got_data = True
                    except (json.JSONDecodeError, UnicodeDecodeError):
                        message_count += 1
                        got_data = True
                else:
                    message_count += 1
                    got_data = True
            if got_data:
                last_message_time = time.monotonic()
            elif time.monotonic() - last_message_time > 10:
                return False, f"stall detected after {message_count} messages"
            remaining -= chunk

        if message_count == 0:
            return False, "no messages received during monitoring"

        return True, ""
    finally:
        await client.close()


async def h2_ws_consecutive():
    """Test 8: consecutive HTTP/2 WebSocket tests."""
    for i in range(NUM_ITERATIONS):
        ok, err = await ws_test_h2()
        if not ok:
            return False, f"iteration {i + 1}/{NUM_ITERATIONS}: {err}"
    return True, ""


async def h2_ws_parallel_separate():
    """Test 9: parallel HTTP/2 WebSocket tests, separate connections."""
    task_results = await asyncio.gather(*[ws_test_h2() for _ in range(NUM_ITERATIONS)])
    for i, (ok, err) in enumerate(task_results):
        if not ok:
            return False, f"task {i + 1}/{NUM_ITERATIONS}: {err}"
    return True, ""


def _h2_extract_status(headers_list):
    """Extract :status from h2 header list, handling bytes or str."""
    for hname, hval in headers_list:
        key = hname if isinstance(hname, str) else hname.decode()
        val = hval if isinstance(hval, str) else hval.decode()
        if key == ':status':
            return val
    return None


async def h2_ws_parallel_shared():
    """Test 10: parallel HTTP/2 WebSocket tests, shared connection."""
    import h2.connection
    import h2.config
    import h2.events as h2e

    ssl_ctx = ssl.create_default_context()
    ssl_ctx.check_hostname = False
    ssl_ctx.verify_mode = ssl.CERT_NONE
    ssl_ctx.set_alpn_protocols(['h2'])

    reader, writer = await asyncio.open_connection(HOST, PORT, ssl=ssl_ctx)

    config = h2.config.H2Configuration(client_side=True)
    conn = h2.connection.H2Connection(config=config)
    conn.initiate_connection()
    writer.write(conn.data_to_send())
    await writer.drain()

    # Receive server SETTINGS
    data = await asyncio.wait_for(reader.read(65535), timeout=10.0)
    events = conn.receive_data(data)
    writer.write(conn.data_to_send())
    await writer.drain()

    enable_connect = False
    for event in events:
        if isinstance(event, h2e.RemoteSettingsChanged):
            if 0x8 in event.changed_settings:
                enable_connect = event.changed_settings[0x8].new_value == 1

    if not enable_connect:
        writer.close()
        return False, "Server does not support Extended CONNECT (RFC 8441)"

    # Open NUM_ITERATIONS WebSocket streams
    stream_ids = []
    tunnel_data = {}
    stream_ready = {}

    for _ in range(NUM_ITERATIONS):
        sid = conn.get_next_available_stream_id()
        headers = [
            (':method', 'CONNECT'),
            (':protocol', 'websocket'),
            (':scheme', 'https'),
            (':authority', HOST),
            (':path', WS_PATH),
            ('sec-websocket-version', '13'),
            ('sec-websocket-protocol', 'pagecamel'),
            ('origin', f'https://{HOST}'),
        ]
        conn.send_headers(sid, headers, end_stream=False)
        stream_ids.append(sid)
        tunnel_data[sid] = bytearray()
        stream_ready[sid] = False

    writer.write(conn.data_to_send())
    await writer.drain()

    # Wait for all 200 responses
    deadline = time.monotonic() + 10.0
    while not all(stream_ready.values()) and time.monotonic() < deadline:
        try:
            data = await asyncio.wait_for(reader.read(65535), timeout=5.0)
            if not data:
                break
            events = conn.receive_data(data)
            writer.write(conn.data_to_send())
            await writer.drain()
            for event in events:
                if isinstance(event, h2e.ResponseReceived):
                    status = _h2_extract_status(event.headers)
                    if status == '200':
                        stream_ready[event.stream_id] = True
                elif isinstance(event, h2e.DataReceived):
                    if event.stream_id in tunnel_data:
                        tunnel_data[event.stream_id].extend(event.data)
                    conn.acknowledge_received_data(len(event.data), event.stream_id)
                    writer.write(conn.data_to_send())
                    await writer.drain()
        except asyncio.TimeoutError:
            pass

    if not all(stream_ready.values()):
        writer.close()
        return False, "not all streams received 200 response"

    # Send NOTIFY on all streams
    for sid in stream_ids:
        frame = ws_encode_text(json.dumps({"type": "NOTIFY", "varname": "update_all"}))
        conn.send_data(sid, frame, end_stream=False)
    writer.write(conn.data_to_send())
    await writer.drain()

    # Monitor all streams for WS_DURATION
    message_counts = {sid: 0 for sid in stream_ids}
    last_message_times = {sid: time.monotonic() for sid in stream_ids}
    monitor_end = time.monotonic() + WS_DURATION

    while time.monotonic() < monitor_end:
        try:
            data = await asyncio.wait_for(reader.read(65535), timeout=0.5)
            if not data:
                break
            events = conn.receive_data(data)
            writer.write(conn.data_to_send())
            await writer.drain()
            for event in events:
                if isinstance(event, h2e.DataReceived):
                    if event.stream_id in tunnel_data:
                        tunnel_data[event.stream_id].extend(event.data)
                    conn.acknowledge_received_data(len(event.data), event.stream_id)
                    writer.write(conn.data_to_send())
                    await writer.drain()
        except asyncio.TimeoutError:
            pass

        # Parse frames per stream, respond to PINGs
        for sid in stream_ids:
            while True:
                result = ws_decode_frame(tunnel_data[sid])
                if result is None:
                    break
                opcode, payload, consumed = result
                tunnel_data[sid] = tunnel_data[sid][consumed:]
                if opcode == 1:
                    try:
                        obj = json.loads(payload)
                        if obj.get("type") == "PING":
                            pong_frame = ws_encode_text(json.dumps({"type": "PONG"}))
                            conn.send_data(sid, pong_frame, end_stream=False)
                            writer.write(conn.data_to_send())
                            await writer.drain()
                            continue
                    except (json.JSONDecodeError, UnicodeDecodeError):
                        pass
                message_counts[sid] += 1
                last_message_times[sid] = time.monotonic()

        # Stall detection
        now = time.monotonic()
        for sid in stream_ids:
            if now - last_message_times[sid] > 10:
                writer.close()
                return False, f"stream {sid}: stall detected after {message_counts[sid]} messages"

    # Close all streams
    for sid in stream_ids:
        close_frame = ws_encode_close(1000, "test complete")
        try:
            conn.send_data(sid, close_frame, end_stream=False)
        except Exception:
            pass
    writer.write(conn.data_to_send())
    await writer.drain()

    for sid in stream_ids:
        try:
            conn.end_stream(sid)
        except Exception:
            pass
    writer.write(conn.data_to_send())
    await writer.drain()

    writer.close()
    try:
        await writer.wait_closed()
    except Exception:
        pass

    for sid in stream_ids:
        if message_counts[sid] == 0:
            return False, f"stream {sid}: no messages received"

    return True, ""


# ===========================================================================
# HTTP/3 tests (aioquic)
# ===========================================================================

class H3Client:
    """QuicConnectionProtocol subclass for HTTP/3, created at import time."""
    pass


# We define the actual class inside a function to defer the aioquic import
def _get_h3_client_class():
    from aioquic.asyncio.protocol import QuicConnectionProtocol

    class _H3Client(QuicConnectionProtocol):
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

    return _H3Client


def _h3_config():
    from aioquic.quic.configuration import QuicConfiguration
    config = QuicConfiguration(is_client=True, alpn_protocols=["h3"])
    config.verify_mode = ssl.CERT_NONE
    return config


async def h3_do_get(client, path, timeout=120):
    """Send GET and return (status, body_bytes)."""
    from aioquic.h3.events import HeadersReceived, DataReceived

    stream_id = client._quic.get_next_available_stream_id()
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
        if elapsed > timeout:
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


async def h3_do_put(client, path, body, timeout=120):
    """Send PUT and return (status, response_text)."""
    from aioquic.h3.events import HeadersReceived, DataReceived

    stream_id = client._quic.get_next_available_stream_id()
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
        if elapsed > timeout:
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


# --- HTTP/3 Downloads ---

async def h3_download_consecutive_no_reuse():
    """Test 1: consecutive downloads, no connection reuse."""
    from aioquic.asyncio.client import connect
    from aioquic.h3.connection import H3Connection

    H3ClientCls = _get_h3_client_class()
    for i in range(NUM_ITERATIONS):
        config = _h3_config()
        async with connect(HOST, PORT, configuration=config,
                           create_protocol=H3ClientCls) as client:
            client._http = H3Connection(client._quic)
            status, data = await h3_do_get(client, DOWNLOAD_PATH)
            ok, err = verify_download(data)
            if not ok:
                return False, f"iteration {i + 1}/{NUM_ITERATIONS}: {err}"
    return True, ""


async def h3_download_consecutive_reuse():
    """Test 2: consecutive downloads, with connection reuse."""
    from aioquic.asyncio.client import connect
    from aioquic.h3.connection import H3Connection

    H3ClientCls = _get_h3_client_class()
    config = _h3_config()
    async with connect(HOST, PORT, configuration=config,
                       create_protocol=H3ClientCls) as client:
        client._http = H3Connection(client._quic)
        for i in range(NUM_ITERATIONS):
            status, data = await h3_do_get(client, DOWNLOAD_PATH)
            ok, err = verify_download(data)
            if not ok:
                return False, f"iteration {i + 1}/{NUM_ITERATIONS}: {err}"
    return True, ""


async def h3_download_parallel_separate():
    """Test 3: parallel downloads, separate connections."""
    from aioquic.asyncio.client import connect
    from aioquic.h3.connection import H3Connection

    H3ClientCls = _get_h3_client_class()

    async def task(i):
        config = _h3_config()
        async with connect(HOST, PORT, configuration=config,
                           create_protocol=H3ClientCls) as client:
            client._http = H3Connection(client._quic)
            status, data = await h3_do_get(client, DOWNLOAD_PATH)
            return verify_download(data)

    task_results = await asyncio.gather(*[task(i) for i in range(NUM_ITERATIONS)])
    for i, (ok, err) in enumerate(task_results):
        if not ok:
            return False, f"task {i + 1}/{NUM_ITERATIONS}: {err}"
    return True, ""


async def h3_download_parallel_shared():
    """Test 4: parallel downloads, shared QUIC connection."""
    from aioquic.asyncio.client import connect
    from aioquic.h3.connection import H3Connection
    from aioquic.h3.events import HeadersReceived, DataReceived

    H3ClientCls = _get_h3_client_class()
    config = _h3_config()

    async with connect(HOST, PORT, configuration=config,
                       create_protocol=H3ClientCls) as client:
        client._http = H3Connection(client._quic)

        # Send NUM_ITERATIONS requests simultaneously
        stream_ids = []
        for _ in range(NUM_ITERATIONS):
            stream_id = client._quic.get_next_available_stream_id()
            client._http.send_headers(
                stream_id=stream_id,
                headers=[
                    (b":method", b"GET"),
                    (b":scheme", b"https"),
                    (b":authority", HOST.encode()),
                    (b":path", DOWNLOAD_PATH.encode()),
                ],
                end_stream=True,
            )
            stream_ids.append(stream_id)
        client.transmit()

        # Collect data per stream
        buffers = {sid: bytearray() for sid in stream_ids}
        done = {sid: False for sid in stream_ids}
        start = asyncio.get_event_loop().time()
        timeout = 180

        while not all(done.values()):
            if asyncio.get_event_loop().time() - start > timeout:
                return False, "timeout waiting for all streams"
            await asyncio.sleep(0.05)
            for sid in stream_ids:
                events = client._request_events.get(sid, [])
                for event in events:
                    if isinstance(event, DataReceived):
                        buffers[sid].extend(event.data)
                        if event.stream_ended:
                            done[sid] = True
                client._request_events[sid] = []

        for i, sid in enumerate(stream_ids):
            ok, err = verify_download(buffers[sid])
            if not ok:
                return False, f"stream {i + 1}/{NUM_ITERATIONS}: {err}"

    return True, ""


# --- HTTP/3 Uploads ---

async def h3_upload_consecutive():
    """Test 5: consecutive uploads with checksum verification."""
    from aioquic.asyncio.client import connect
    from aioquic.h3.connection import H3Connection

    H3ClientCls = _get_h3_client_class()
    for i in range(NUM_ITERATIONS):
        config = _h3_config()
        async with connect(HOST, PORT, configuration=config,
                           create_protocol=H3ClientCls) as client:
            client._http = H3Connection(client._quic)
            status, response_text = await h3_do_put(client, UPLOAD_PATH, TESTFILE_DATA)
            ok, err = verify_upload_response(response_text, UPLOAD_SHA256, EXPECTED_SIZE)
            if not ok:
                return False, f"iteration {i + 1}/{NUM_ITERATIONS}: {err}"
    return True, ""


async def h3_upload_parallel_separate():
    """Test 6: parallel uploads, separate connections."""
    from aioquic.asyncio.client import connect
    from aioquic.h3.connection import H3Connection

    H3ClientCls = _get_h3_client_class()

    async def task(i):
        config = _h3_config()
        async with connect(HOST, PORT, configuration=config,
                           create_protocol=H3ClientCls) as client:
            client._http = H3Connection(client._quic)
            status, response_text = await h3_do_put(client, UPLOAD_PATH, TESTFILE_DATA)
            return verify_upload_response(response_text, UPLOAD_SHA256, EXPECTED_SIZE)

    task_results = await asyncio.gather(*[task(i) for i in range(NUM_ITERATIONS)])
    for i, (ok, err) in enumerate(task_results):
        if not ok:
            return False, f"task {i + 1}/{NUM_ITERATIONS}: {err}"
    return True, ""


async def h3_upload_parallel_shared():
    """Test 7: parallel uploads, shared QUIC connection."""
    from aioquic.asyncio.client import connect
    from aioquic.h3.connection import H3Connection
    from aioquic.h3.events import DataReceived

    H3ClientCls = _get_h3_client_class()
    config = _h3_config()

    async with connect(HOST, PORT, configuration=config,
                       create_protocol=H3ClientCls) as client:
        client._http = H3Connection(client._quic)

        # Send all uploads
        stream_ids = []
        for _ in range(NUM_ITERATIONS):
            stream_id = client._quic.get_next_available_stream_id()
            client._http.send_headers(
                stream_id=stream_id,
                headers=[
                    (b":method", b"PUT"),
                    (b":scheme", b"https"),
                    (b":authority", HOST.encode()),
                    (b":path", UPLOAD_PATH.encode()),
                    (b"content-length", str(len(TESTFILE_DATA)).encode()),
                    (b"content-type", b"application/octet-stream"),
                ],
                end_stream=False,
            )
            # Send body in chunks
            chunk_size = 65536
            offset = 0
            while offset < len(TESTFILE_DATA):
                end = min(offset + chunk_size, len(TESTFILE_DATA))
                is_last = (end == len(TESTFILE_DATA))
                client._http.send_data(
                    stream_id=stream_id,
                    data=TESTFILE_DATA[offset:end],
                    end_stream=is_last,
                )
                offset = end
            stream_ids.append(stream_id)
        client.transmit()

        # Wait for all responses
        responses = {sid: bytearray() for sid in stream_ids}
        done = {sid: False for sid in stream_ids}
        start = asyncio.get_event_loop().time()
        timeout = 180

        while not all(done.values()):
            if asyncio.get_event_loop().time() - start > timeout:
                return False, "timeout waiting for all upload responses"
            await asyncio.sleep(0.05)
            for sid in stream_ids:
                events = client._request_events.get(sid, [])
                for event in events:
                    if isinstance(event, DataReceived):
                        responses[sid].extend(event.data)
                        if event.stream_ended:
                            done[sid] = True
                client._request_events[sid] = []

        for i, sid in enumerate(stream_ids):
            response_text = responses[sid].decode('utf-8', errors='replace').strip()
            ok, err = verify_upload_response(response_text, UPLOAD_SHA256, EXPECTED_SIZE)
            if not ok:
                return False, f"stream {i + 1}/{NUM_ITERATIONS}: {err}"

    return True, ""


# --- HTTP/3 Small file stress test ---

async def h3_small_download_stress():
    """Test 11: small file consecutive download stress test, no reuse."""
    from aioquic.asyncio.client import connect
    from aioquic.h3.connection import H3Connection

    H3ClientCls = _get_h3_client_class()
    for i in range(SMALL_ITERATIONS):
        config = _h3_config()
        async with connect(HOST, PORT, configuration=config,
                           create_protocol=H3ClientCls) as client:
            client._http = H3Connection(client._quic)
            status, data = await h3_do_get(client, SMALL_DOWNLOAD_PATH, timeout=30)
            ok, err = verify_small_download(data)
            if not ok:
                return False, f"iteration {i + 1}/{SMALL_ITERATIONS}: {err}"
    return True, ""


# --- HTTP/3 WebSocket ---

async def ws_test_h3(duration=WS_DURATION):
    """Single HTTP/3 WebSocket test session."""
    from aioquic.asyncio.client import connect
    from aioquic.h3.connection import H3Connection
    from aioquic.h3.events import HeadersReceived, DataReceived

    H3ClientCls = _get_h3_client_class()
    config = _h3_config()

    async with connect(HOST, PORT, configuration=config,
                       create_protocol=H3ClientCls) as client:
        client._http = H3Connection(client._quic)

        # Extended CONNECT
        stream_id = client._quic.get_next_available_stream_id()
        client._http.send_headers(
            stream_id=stream_id,
            headers=[
                (b":method", b"CONNECT"),
                (b":protocol", b"websocket"),
                (b":scheme", b"https"),
                (b":authority", HOST.encode()),
                (b":path", WS_PATH.encode()),
                (b"sec-websocket-version", b"13"),
                (b"sec-websocket-protocol", b"pagecamel"),
                (b"origin", f"https://{HOST}".encode()),
            ],
            end_stream=False,
        )
        client.transmit()

        tunnel_data = bytearray()

        # Wait for 200 response
        response_status = None
        start = asyncio.get_event_loop().time()
        while response_status is None:
            if asyncio.get_event_loop().time() - start > 10:
                return False, "timeout waiting for WebSocket response"
            await asyncio.sleep(0.05)
            events = client._request_events.get(stream_id, [])
            for event in events:
                if isinstance(event, HeadersReceived):
                    for name, value in event.headers:
                        if name == b":status":
                            response_status = value.decode()
                elif isinstance(event, DataReceived):
                    tunnel_data.extend(event.data)
            client._request_events[stream_id] = []

        if response_status != "200":
            return False, f"expected 200, got {response_status}"

        # Helper to drain events
        async def drain_events(timeout_s):
            s = asyncio.get_event_loop().time()
            while asyncio.get_event_loop().time() - s < timeout_s:
                await asyncio.sleep(0.05)
                events = client._request_events.get(stream_id, [])
                for event in events:
                    if isinstance(event, DataReceived):
                        tunnel_data.extend(event.data)
                client._request_events[stream_id] = []

        def collect_ws_messages():
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

        # Send NOTIFY to trigger VALUE messages
        client._http.send_data(
            stream_id=stream_id,
            data=ws_encode_text(json.dumps({"type": "NOTIFY", "varname": "update_all"})),
            end_stream=False)
        client.transmit()

        # Wait for at least one VALUE message to confirm connectivity
        got_value = False
        val_deadline = time.monotonic() + 10.0
        while time.monotonic() < val_deadline and not got_value:
            await drain_events(min(1.0, val_deadline - time.monotonic()))
            msgs = collect_ws_messages()
            for op, p in msgs:
                if op == 1:
                    try:
                        obj = json.loads(p)
                        if obj.get("type") == "PING":
                            client._http.send_data(stream_id=stream_id,
                                                   data=ws_encode_text(json.dumps({"type": "PONG"})),
                                                   end_stream=False)
                            client.transmit()
                        elif obj.get("type") == "VALUE":
                            got_value = True
                    except (json.JSONDecodeError, UnicodeDecodeError):
                        pass
        if not got_value:
            return False, "no VALUE message received after NOTIFY"

        # Monitor for duration, responding to server PINGs
        message_count = 0
        last_message_time = time.monotonic()
        end_time = time.monotonic() + duration

        while time.monotonic() < end_time:
            await drain_events(min(1.0, end_time - time.monotonic()))
            msgs = collect_ws_messages()
            got_data = False
            for op, p in msgs:
                if op == 1:
                    try:
                        obj = json.loads(p)
                        if obj.get("type") == "PING":
                            client._http.send_data(stream_id=stream_id,
                                                   data=ws_encode_text(json.dumps({"type": "PONG"})),
                                                   end_stream=False)
                            client.transmit()
                            continue
                    except (json.JSONDecodeError, UnicodeDecodeError):
                        pass
                message_count += 1
                got_data = True
            if got_data:
                last_message_time = time.monotonic()
            elif time.monotonic() - last_message_time > 10:
                return False, f"stall detected after {message_count} messages"

        if message_count == 0:
            return False, "no messages received during monitoring"

        # Close
        client._http.send_data(stream_id=stream_id,
                               data=ws_encode_close(1000, "test complete"),
                               end_stream=False)
        client.transmit()
        await drain_events(2)
        client._http.send_data(stream_id=stream_id, data=b"", end_stream=True)
        client.transmit()

    return True, ""


async def h3_ws_consecutive():
    """Test 8: consecutive HTTP/3 WebSocket tests."""
    for i in range(NUM_ITERATIONS):
        ok, err = await ws_test_h3()
        if not ok:
            return False, f"iteration {i + 1}/{NUM_ITERATIONS}: {err}"
    return True, ""


async def h3_ws_parallel_separate():
    """Test 9: parallel HTTP/3 WebSocket tests, separate connections."""
    task_results = await asyncio.gather(*[ws_test_h3() for _ in range(NUM_ITERATIONS)])
    for i, (ok, err) in enumerate(task_results):
        if not ok:
            return False, f"task {i + 1}/{NUM_ITERATIONS}: {err}"
    return True, ""


async def h3_ws_parallel_shared():
    """Test 10: parallel HTTP/3 WebSocket tests, shared QUIC connection."""
    from aioquic.asyncio.client import connect
    from aioquic.h3.connection import H3Connection
    from aioquic.h3.events import HeadersReceived, DataReceived

    H3ClientCls = _get_h3_client_class()
    config = _h3_config()

    async with connect(HOST, PORT, configuration=config,
                       create_protocol=H3ClientCls) as client:
        client._http = H3Connection(client._quic)

        # Open NUM_ITERATIONS WebSocket streams
        stream_ids = []
        tunnel_data = {}

        for _ in range(NUM_ITERATIONS):
            stream_id = client._quic.get_next_available_stream_id()
            client._http.send_headers(
                stream_id=stream_id,
                headers=[
                    (b":method", b"CONNECT"),
                    (b":protocol", b"websocket"),
                    (b":scheme", b"https"),
                    (b":authority", HOST.encode()),
                    (b":path", WS_PATH.encode()),
                    (b"sec-websocket-version", b"13"),
                    (b"sec-websocket-protocol", b"pagecamel"),
                    (b"origin", f"https://{HOST}".encode()),
                ],
                end_stream=False,
            )
            stream_ids.append(stream_id)
            tunnel_data[stream_id] = bytearray()
        client.transmit()

        # Wait for all 200 responses
        stream_ready = {sid: False for sid in stream_ids}
        start = asyncio.get_event_loop().time()

        while not all(stream_ready.values()):
            if asyncio.get_event_loop().time() - start > 10:
                return False, "timeout waiting for WebSocket responses"
            await asyncio.sleep(0.05)
            for sid in stream_ids:
                events = client._request_events.get(sid, [])
                for event in events:
                    if isinstance(event, HeadersReceived):
                        for name, value in event.headers:
                            if name == b":status" and value.decode() == "200":
                                stream_ready[sid] = True
                    elif isinstance(event, DataReceived):
                        tunnel_data[sid].extend(event.data)
                client._request_events[sid] = []

        # Helper to drain all streams
        async def drain_all(timeout_s):
            s = asyncio.get_event_loop().time()
            while asyncio.get_event_loop().time() - s < timeout_s:
                await asyncio.sleep(0.05)
                for sid in stream_ids:
                    events = client._request_events.get(sid, [])
                    for event in events:
                        if isinstance(event, DataReceived):
                            tunnel_data[sid].extend(event.data)
                    client._request_events[sid] = []

        def collect_ws_messages(sid):
            msgs = []
            while True:
                result = ws_decode_frame(tunnel_data[sid])
                if result is None:
                    break
                opcode, payload, consumed = result
                tunnel_data[sid] = tunnel_data[sid][consumed:]
                msgs.append((opcode, payload))
            return msgs

        # Send NOTIFY on all streams
        for sid in stream_ids:
            client._http.send_data(
                stream_id=sid,
                data=ws_encode_text(json.dumps({"type": "NOTIFY", "varname": "update_all"})),
                end_stream=False)
        client.transmit()

        # Monitor for WS_DURATION
        message_counts = {sid: 0 for sid in stream_ids}
        last_message_times = {sid: time.monotonic() for sid in stream_ids}
        end_time = time.monotonic() + WS_DURATION

        while time.monotonic() < end_time:
            await drain_all(min(1.0, end_time - time.monotonic()))
            for sid in stream_ids:
                msgs = collect_ws_messages(sid)
                got_data = False
                for op, p in msgs:
                    if op == 1:
                        try:
                            obj = json.loads(p)
                            if obj.get("type") == "PING":
                                client._http.send_data(
                                    stream_id=sid,
                                    data=ws_encode_text(json.dumps({"type": "PONG"})),
                                    end_stream=False)
                                client.transmit()
                                continue
                        except (json.JSONDecodeError, UnicodeDecodeError):
                            pass
                    message_counts[sid] += 1
                    got_data = True
                if got_data:
                    last_message_times[sid] = time.monotonic()

            now = time.monotonic()
            for sid in stream_ids:
                if now - last_message_times[sid] > 10:
                    return False, f"stream {sid}: stall detected after {message_counts[sid]} messages"

        # Check all streams got messages
        for sid in stream_ids:
            if message_counts[sid] == 0:
                return False, f"stream {sid}: no messages received"

        # Close all streams
        for sid in stream_ids:
            client._http.send_data(
                stream_id=sid,
                data=ws_encode_close(1000, "test complete"),
                end_stream=False)
        client.transmit()
        await drain_all(2)
        for sid in stream_ids:
            client._http.send_data(stream_id=sid, data=b"", end_stream=True)
        client.transmit()

    return True, ""


# ===========================================================================
# Test registry
# ===========================================================================

def _test_desc(num):
    """Build dynamic test description using current iteration counts."""
    n = NUM_ITERATIONS
    s = SMALL_ITERATIONS
    descs = {
        1: f"{n} consecutive downloads (no reuse)",
        2: f"{n} consecutive downloads (with reuse)",
        3: f"{n} parallel downloads (separate connections)",
        4: f"{n} parallel downloads (shared connection)",
        5: f"{n} consecutive uploads (checksum verified)",
        6: f"{n} parallel uploads (separate connections)",
        7: f"{n} parallel uploads (shared connection)",
        8: f"{n} consecutive WebSocket tests ({WS_DURATION}s each)",
        9: f"{n} parallel WebSocket tests (separate connections, {WS_DURATION}s)",
        10: f"{n} parallel WebSocket tests (shared connection, {WS_DURATION}s)",
        11: f"{s} consecutive small-file downloads (no reuse)",
    }
    return descs[num]


def build_test_list():
    """Build the full test list: [(protocol, test_num, description, coro_factory), ...]"""
    tests = []

    # HTTP/1.1 tests (tests 1-3, 5-6, 8-9, 11; skip 4, 7, 10)
    h1_tests = [
        (1, lambda: httpx_download_consecutive_no_reuse(http2=False)),
        (2, lambda: httpx_download_consecutive_reuse(http2=False)),
        (3, lambda: httpx_download_parallel_separate(http2=False)),
        (5, lambda: httpx_upload_consecutive(http2=False)),
        (6, lambda: httpx_upload_parallel_separate(http2=False)),
        (8, lambda: h1_ws_consecutive()),
        (9, lambda: h1_ws_parallel_separate()),
        (11, lambda: httpx_small_download_stress(http2=False)),
    ]
    for num, factory in h1_tests:
        tests.append(("HTTP/1.1", num, _test_desc(num), factory))

    # HTTP/2 tests (all 11)
    h2_tests = [
        (1, lambda: httpx_download_consecutive_no_reuse(http2=True)),
        (2, lambda: httpx_download_consecutive_reuse(http2=True)),
        (3, lambda: httpx_download_parallel_separate(http2=True)),
        (4, lambda: httpx_download_parallel_shared()),
        (5, lambda: httpx_upload_consecutive(http2=True)),
        (6, lambda: httpx_upload_parallel_separate(http2=True)),
        (7, lambda: httpx_upload_parallel_shared()),
        (8, lambda: h2_ws_consecutive()),
        (9, lambda: h2_ws_parallel_separate()),
        (10, lambda: h2_ws_parallel_shared()),
        (11, lambda: httpx_small_download_stress(http2=True)),
    ]
    for num, factory in h2_tests:
        tests.append(("HTTP/2", num, _test_desc(num), factory))

    # HTTP/3 tests (all 11)
    h3_tests = [
        (1, lambda: h3_download_consecutive_no_reuse()),
        (2, lambda: h3_download_consecutive_reuse()),
        (3, lambda: h3_download_parallel_separate()),
        (4, lambda: h3_download_parallel_shared()),
        (5, lambda: h3_upload_consecutive()),
        (6, lambda: h3_upload_parallel_separate()),
        (7, lambda: h3_upload_parallel_shared()),
        (8, lambda: h3_ws_consecutive()),
        (9, lambda: h3_ws_parallel_separate()),
        (10, lambda: h3_ws_parallel_shared()),
        (11, lambda: h3_small_download_stress()),
    ]
    for num, factory in h3_tests:
        tests.append(("HTTP/3", num, _test_desc(num), factory))

    return tests


def protocol_matches(filter_str, protocol):
    """Check if a protocol filter matches a protocol name."""
    norm = filter_str.lower().replace("/", "").replace(".", "")
    proto_norm = protocol.lower().replace("/", "").replace(".", "")
    return norm == proto_norm


# ===========================================================================
# Main
# ===========================================================================

def parse_args():
    parser = argparse.ArgumentParser(
        description="Comprehensive HTTP protocol test suite")
    parser.add_argument("--test", type=int,
                        help="Run only the specified test number (1-11)")
    parser.add_argument("--protocol", type=str,
                        choices=["http1.1", "http2", "http3"],
                        help="Run only the specified protocol")
    parser.add_argument("--list", action="store_true",
                        help="List all available test categories and exit")
    parser.add_argument("--iterations", type=int, default=10,
                        help="Number of iterations for tests 1-10 (default: 10)")
    parser.add_argument("--small-iter", type=int, default=100,
                        help="Number of iterations for small-file stress test 11 (default: 100)")
    parser.add_argument("--live", action="store_true",
                        help="Test against live server (cavac.at) instead of test.cavac.at")
    return parser.parse_args()


async def main():
    global TESTFILE_DATA, UPLOAD_SHA256
    global SMALL_FILE_DATA, SMALL_EXPECTED_MD5, SMALL_EXPECTED_SIZE
    global NUM_ITERATIONS, SMALL_ITERATIONS, TEST_TIMEOUT
    global HOST, DOWNLOAD_URL, SMALL_DOWNLOAD_URL, UPLOAD_URL

    args = parse_args()

    if args.live:
        HOST = "cavac.at"
        DOWNLOAD_URL = f"https://{HOST}:{PORT}{DOWNLOAD_PATH}"
        SMALL_DOWNLOAD_URL = f"https://{HOST}:{PORT}{SMALL_DOWNLOAD_PATH}"
        UPLOAD_URL = f"https://{HOST}:{PORT}{UPLOAD_PATH}"

    NUM_ITERATIONS = args.iterations
    SMALL_ITERATIONS = args.small_iter

    # Per-test timeout: enough for the slowest possible test
    # WebSocket consecutive: N * (WS_DURATION + 15s overhead)
    # Download/upload: N * 150s
    # Small file: S * 30s
    TEST_TIMEOUT = max(
        NUM_ITERATIONS * (WS_DURATION + 30),
        NUM_ITERATIONS * 150,
        SMALL_ITERATIONS * 30,
        600,
    )

    all_tests = build_test_list()

    if args.list:
        for proto, num, desc, _ in all_tests:
            print(f"[{proto}] Test {num}: {desc}")
        sys.exit(0)

    check_dependencies()

    # --- Download test files once ---
    import httpx

    print("Preparing test files...")

    # Large file (31 MB)
    async with httpx.AsyncClient(verify=False, timeout=httpx.Timeout(120.0)) as client:
        resp = await client.get(DOWNLOAD_URL)
        TESTFILE_DATA = resp.content

    md5 = hashlib.md5(TESTFILE_DATA).hexdigest()
    if md5 != EXPECTED_MD5:
        print(f"FATAL: test file MD5 mismatch: {md5} != {EXPECTED_MD5}")
        sys.exit(1)
    if len(TESTFILE_DATA) != EXPECTED_SIZE:
        print(f"FATAL: test file size mismatch: {len(TESTFILE_DATA)} != {EXPECTED_SIZE}")
        sys.exit(1)

    UPLOAD_SHA256 = hashlib.sha256(TESTFILE_DATA).hexdigest()
    print(f"  Large file: {EXPECTED_SIZE:,} bytes, MD5={EXPECTED_MD5}, SHA256={UPLOAD_SHA256[:16]}...")

    # Small file (30 KB)
    async with httpx.AsyncClient(verify=False, timeout=httpx.Timeout(30.0)) as client:
        resp = await client.get(SMALL_DOWNLOAD_URL)
        SMALL_FILE_DATA = resp.content

    SMALL_EXPECTED_SIZE = len(SMALL_FILE_DATA)
    SMALL_EXPECTED_MD5 = hashlib.md5(SMALL_FILE_DATA).hexdigest()
    print(f"  Small file: {SMALL_EXPECTED_SIZE:,} bytes, MD5={SMALL_EXPECTED_MD5}")

    if SMALL_EXPECTED_SIZE == 0:
        print("FATAL: small test file is empty")
        sys.exit(1)

    print(f"  Iterations: {NUM_ITERATIONS} (tests 1-10), {SMALL_ITERATIONS} (test 11)")
    print(f"  Per-test timeout: {TEST_TIMEOUT}s")
    print()

    # --- Run tests ---
    current_proto = None
    for proto, num, desc, coro_factory in all_tests:
        if args.protocol and not protocol_matches(args.protocol, proto):
            continue
        if args.test and args.test != num:
            continue

        if proto != current_proto:
            current_proto = proto
            print(f"{'=' * 60}")
            print(f"{proto} TESTS")
            print(f"{'=' * 60}")

        await run_test(f"[{proto}] Test {num}: {desc}", coro_factory())

    print_summary()
    sys.exit(0 if all_passed() else 1)


if __name__ == "__main__":
    asyncio.run(main())
