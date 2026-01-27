# HTTP/3 Rewrite - Implementation Tracking

## Current Status
- [x] Phase 1: C Library Source Files
- [x] Phase 2: Build System
- [x] Phase 3: XS Wrapper
- [x] Phase 4: Perl Module
- [x] Phase 5: Update HTTP3Handler
- [x] Phase 6: Remove Dead Code
- [x] Phase 7: Update Root Build System
- [x] Phase 8: Adapt Test Scripts
- [x] Phase 9: Build Verification
- [x] Phase 10: Integration Testing - COMPLETE
- [x] Phase 11: Upload Testing - COMPLETE
- [x] Phase 12: Python Client Verification - COMPLETE
- [x] Phase 13: WebSocket Testing - COMPLETE

## Step-by-Step Progress

### Phase 1: C Library
| Step | File | Status | Notes |
|------|------|--------|-------|
| 1.1 | src/h3_api.h | ✅ | Public API declarations |
| 1.2 | src/h3_internal.h | ✅ | Internal structures |
| 1.3 | src/h3_buffer.h | ✅ | Chunk buffer declarations |
| 1.4 | src/h3_buffer.c | ✅ | Chunk buffer implementation |
| 1.5 | src/h3_tls.h | ✅ | GnuTLS integration |
| 1.6 | src/h3_tls.c | ✅ | GnuTLS implementation |
| 1.7 | src/h3_callbacks.c | ✅ | CRITICAL - C-to-C wiring |
| 1.8 | src/h3_connection.c | ✅ | Connection lifecycle |
| 1.9 | src/h3_packet.h | ✅ | Packet processing |
| 1.10 | src/h3_packet.c | ✅ | Packet implementation |
| 1.11 | src/h3_api.c | ✅ | API implementation |

### Phase 2-4: Build & Wrapper
| Step | File | Status | Notes |
|------|------|--------|-------|
| 2.1 | Makefile.PL | ✅ | Build system for C + XS |
| 2.2 | typemap | ✅ | XS type mappings |
| 3.1 | HTTP3.xs | ✅ | Minimal XS wrapper |
| 4.1 | HTTP3.pm | ✅ | Perl interface |

### Phase 5-7: Integration
| Step | Task | Status | Notes |
|------|------|--------|-------|
| 5.1 | Update HTTP3Handler.pm | ✅ | Uses new PageCamel::Protocol::HTTP3 |
| 6.1 | Delete lib/PageCamel/XS/ | ✅ | Removed 15 files |
| 6.2 | Delete lib/PageCamel/Protocol/QUIC/ | ✅ | Removed 4 files |
| 6.3 | Delete QPACK/ + Server.pm | ✅ | Removed 5 files |
| 7.1 | Update root Makefile.PL | ✅ | DIR points to HTTP3/ |

### Phase 8-10: Testing
| Step | Task | Status | Notes |
|------|------|--------|-------|
| 8.1 | Delete obsolete tests | ✅ | Deleted 6 files |
| 8.2 | Rewrite t/78-http3-handler.t | ✅ | Updated for h3Config API |
| 8.3 | Create t/79-http3-module.t | ✅ | 26 tests pass |
| 9.1 | Pre-deletion build test | ✅ | HTTP3.so compiled and loads |
| 9.2 | Post-deletion build test | ✅ | Build succeeds, tests pass |
| 10.1 | curl-h3 download test | ✅ | 31MB file downloads correctly |
| 10.2 | MD5 verification | ✅ | 10/10 tests pass, MD5=ae525b610cdca28ffed9b81e2cfa47b8 |
| 10.3 | Multi-connection test | ✅ | Fixed by DCID-primary routing (was address-based) |

### Phase 11: Upload Testing
| Step | Task | Status | Notes |
|------|------|--------|-------|
| 11.1 | Create test data (5MB) | ✅ | SHA256=5e9757f67f94fa2d1a489abaf073d900b0e97093af3eda1ab8361f6f0aec2cd5 |
| 11.2 | File upload HTTP/1.1 baseline | ✅ | SHA256 match, 5MB |
| 11.3 | File upload HTTP/2 | ✅ | SHA256 match, 5MB |
| 11.4 | File upload HTTP/3 | ✅ | SHA256 match, 5MB + 30MB. Fixed flow control bug |
| 11.5 | Piped upload HTTP/1.1 baseline | ✅ | SHA256 match, 5MB |
| 11.6 | Piped upload HTTP/2 | ✅ | SHA256 match, 5MB |
| 11.7 | Piped upload HTTP/3 | ✅ | SHA256 match, 5MB |
| 11.8 | Streaming endpoint test | ✅ | SHA256 match, 5MB to /guest/puttest/dynamic |
| 11.9 | Known-data checksum test | ✅ | "Hello HTTP/3 Upload Test" → correct SHA256, 24 bytes |

### Phase 12: Python Client Verification (aioquic)
| Step | Task | Status | Notes |
|------|------|--------|-------|
| 12.0 | Set up t/python/ directory | ✅ | Moved http2_websocket_client.py, copied h3_multiplex.py |
| 12.1 | Create h3_download.py | ✅ | Single download + MD5 |
| 12.2 | Create h3_parallel_download.py | ✅ | 3 parallel streams + MD5 |
| 12.3 | Create h3_upload.py | ✅ | Small + 5MB + connection reuse uploads |
| 12.4 | Create h3_parallel_upload.py | ✅ | 3 parallel 2MB uploads + SHA256 |
| 12.5 | Create h3_connection_reuse.py | ✅ | 3 downloads + GET + upload on 1 connection |
| 12.6 | Run single download test | ✅ | 31MB, MD5 match, 3.1s |
| 12.7 | Run parallel download test | ✅ | 3x31MB, all MD5 match, 8.8s |
| 12.8 | Run upload tests | ✅ | 24B + 5MB + 1MB reuse, all SHA256 match |
| 12.9 | Run parallel upload test | ✅ | 3x2MB, all SHA256 match, 1.0s |
| 12.10 | Run connection reuse test | ✅ | 3 downloads + GET + upload on single conn |

### Phase 13: WebSocket Testing (Extended CONNECT, RFC 9220)
| Step | Task | Status | Notes |
|------|------|--------|-------|
| 13.1 | Enable enable_connect_protocol in nghttp3 settings | ✅ | h3_connection.c: `http3_settings.enable_connect_protocol = 1` |
| 13.2 | Create h3_websocket.py | ✅ | Uses aioquic, manual WS framing, KaffeeSim protocol |
| 13.3 | Verify HTTP/2 WebSocket baseline | ✅ | Extended CONNECT works via h2 library, VALUE msgs received |
| 13.4 | Verify HTTP/3 header reception | ✅ | C callbacks receive all 8 headers, is_connect=1 detected |
| 13.5 | Verify Perl callback fires | ✅ | on_request called and returns, is_connect=1 passed |
| 13.6 | Debug tunnel response | ✅ | Fixed 3 bugs: state mismatch, header filtering, missing flush_packets |
| 13.7 | Run full WebSocket test | ✅ | All 4 tests PASS: PING/PONG, NOTIFY, continuous stream, graceful close |
| 13.8 | Clean build verification | ✅ | All 4 WS tests PASS, download MD5 match, upload SHA256 match |

## Remaining Work

### WebFrontend.pm Integration - COMPLETED

All WebFrontend.pm changes have been completed:

1. ✅ Updated HTTP/3 availability check (require PageCamel::Protocol::HTTP3)
2. ✅ Updated timestamp calls to use `PageCamel::Protocol::HTTP3::timestamp_ns()`
3. ✅ Rewrote `handleNewQUICConnection()` to use new API
   - Creates h3Config hash with connection parameters
   - Creates HTTP3Handler with h3Config and sendPacketCallback
   - Handler's init() creates the connection internally
4. ✅ Updated packet routing (`handleQUICPacket()`) to use handlers
5. ✅ Updated `handleHTTP3Backends()` for new handler API
6. ✅ Updated `handleQUICTimeouts()` for new handler API
7. ✅ Updated `processIncomingUdpNonBlocking()` for handlers
8. ✅ Updated `cleanupQUICConnection()` for handlers
9. ✅ Updated `cleanupClosedQUICConnections()` for handlers
10. ✅ Updated `runHTTP3Handler()` timeout calculation
11. ✅ Removed obsolete functions:
    - handleQUICStreamData (handled by h3conn callbacks)
    - handleQUICHandshake (no longer needed)
    - handleHTTP3Request (handled by h3conn callbacks)
    - handleHTTP3ConnectRequest (handled by h3conn callbacks)
    - sendQUICPackets (packets sent via handler callback)
    - flushPendingUdpPackets (no longer needed)
    - isUdpBackPressured (no longer needed)

HTTP3Handler.pm was also updated:
- Added `init()` method for lazy connection initialization
- Added `h3conn()` accessor method
- Added `is_closing()`, `get_timeout_ms()`, `handle_timeout()` methods
- Added `get_connection_ids()` method
- Modified `run()` to call `init()` instead of creating connection inline

The core C library, XS wrapper, HTTP3Handler, and WebFrontend integration are all complete. Ready for integration testing (curl-h3).

## Lessons Learned

### Things That DON'T Work (from previous attempts)

1. **Perl trampolines for ngtcp2<->nghttp3 callbacks**
   - Causes data corruption in large file transfers
   - nghttp3 caches pointers from read_data callback
   - Perl/XS boundary crossing introduces pointer lifetime issues

2. **Realloc of chunk buffers while nghttp3 holds pointers**
   - NEVER reallocate chunks that nghttp3 might reference
   - Use fixed-size chunks, only free after ACK

3. **Freeing chunks in acked_stream_data callback**
   - Can be called during writev_stream loop
   - nghttp3 may still have cached pointers
   - Must defer freeing to safe point (flush_acked_data)

4. **Single global buffer for all streams**
   - Causes cross-stream data corruption
   - Need per-stream buffer tracking with absolute offsets

5. **Consuming buffer based on ngtcp2's ndatalen**
   - `ndatalen` from `ngtcp2_conn_writev_stream()` includes HTTP/3 framing (HEADERS, DATA frame headers)
   - Body buffer only contains body data, NOT framing
   - Consuming ndatalen from body buffer causes over-consumption
   - Symptoms: data missing from start of file, records "jumping backwards"
   - **FIX**: Consume in `read_data` callback where we know exact body data returned

6. **Extending flow control only from recv_stream_data callback**
   - `nghttp3_conn_read_stream()` return value EXCLUDES body data payload
   - Only covers HTTP/3 framing overhead (HEADERS, DATA frame headers, QPACK)
   - Flow control must be extended from THREE sites:
     a. `recv_stream_data` (ngtcp2): by nghttp3_conn_read_stream() return value (framing)
     b. `recv_data` (nghttp3): by datalen (body data)
     c. `deferred_consume` (nghttp3): by consumed (deferred bytes)
   - Missing any site causes flow control stall at initial window size

7. **grep filtering on flat name/value header arrays**
   - `grep { $_ ne 'content-length' } @headers` removes only the name, leaving orphaned value
   - Creates odd-length array (broken pairs) → corrupted HTTP/3 response headers
   - Must iterate in pairs: `for(my $i = 0; $i < scalar(@h); $i += 2)` and skip both elements

8. **Sending tunnel response headers without flush_packets()**
   - WebSocket tunnel: send_response_headers with 0 body bytes
   - Without explicit flush_packets(), response stays queued in nghttp3 indefinitely
   - Client times out waiting for response

9. **Using different state names in handleConnectRequest vs processBackendResponse**
   - handleConnectRequest set `tunnel_pending`, processBackendResponse only handled `waiting_response`
   - Backend 101 response was silently ignored because state check failed
   - Fix: Use consistent state name + separate flag for tunnel detection

### Known Working Patterns

1. **Chunk-based buffer system (64KB chunks)**
   - From NGHTTP3.xs: DataChunk struct, never reallocated
   - Track: total_len, consumed_bytes, acked_bytes, freed_bytes

2. **GnuTLS for TLS 1.3**
   - Working multi-domain SNI support in NGTCP2.xs
   - ALPN: "h3" for HTTP/3

3. **Test file format**
   - testfile_1.bin: Sequential 4-byte numbers (01 XX XX XX, big-endian record number)
   - 31,457,280 bytes = 7,864,320 records
   - MD5: ae525b610cdca28ffed9b81e2cfa47b8
   - Easy to detect corruption by checking sequence

4. **Buffer consumption in read_data callback**
   - Only consume body data when `read_data` returns it
   - Never consume based on `ndatalen` (includes HTTP/3 framing)
   - This ensures exact byte accounting for body data only

5. **Three-site flow control extension for uploads**
   - recv_stream_data: extend by nghttp3_conn_read_stream() return (framing only)
   - recv_data: extend by datalen (body data payload)
   - deferred_consume: extend by consumed (deferred bytes)
   - All three MUST call ngtcp2_conn_extend_max_stream_offset AND ngtcp2_conn_extend_max_offset
   - Verified: 100MB uploads work with 1MB initial window

6. **Backpressure with max buffer size (10MB)**
   - `H3_MAX_BUFFER_SIZE` = 10MB per stream
   - `h3_send_response_body()` returns `H3_WOULDBLOCK` when exceeded
   - Memory usage = `total_len - freed_bytes` (data still in chunks)
   - Chunks freed progressively as ACKs arrive via `h3_buffer_flush_acked()`
   - Verified: 478 of 480 chunks freed during 31MB transfer
   - Never consume based on `ndatalen` (includes HTTP/3 framing)
   - This ensures exact byte accounting for body data only

## Test Results Log

| Date | Test | Result | Notes |
|------|------|--------|-------|
| 2026-01-23 | t/79-http3-module.t | ✅ PASS | 26/26 tests pass |
| 2026-01-23 | t/78-http3-handler.t | ✅ PASS | 34/34 tests pass |
| 2026-01-23 | Module load test | ✅ PASS | PageCamel::Protocol::HTTP3 loads correctly |
| 2026-01-23 | Post-deletion build | ✅ PASS | Clean build after removing dead code |
| 2026-01-23 | WebFrontend.pm update | ✅ PASS | Syntax OK, all functions updated |
| 2026-01-23 | Post-WebFrontend build | ✅ PASS | Build succeeds, 60/60 tests pass |
| 2026-01-23 | curl-h3 connection test | ❌→✅ | Fixed with original_dcid parameter |
| 2026-01-23 | curl-h3 small request | ✅ PASS | GET / returns 301 redirect correctly |
| 2026-01-23 | curl-h3 31MB download | ✅ PASS | 10/10 tests pass after buffer consume fix |
| 2026-01-26 | Sequential downloads | ✅ PASS | 9-10/10 pass with fresh server |
| 2026-01-26 | 3 parallel downloads | ✅ PASS | 3/3 pass consistently |
| 2026-01-26 | 5 parallel downloads | ⚠️ PARTIAL | 1-4/5 pass, inconsistent |
| 2026-01-26 | 10 parallel downloads | ❌ FAIL | 0-7/10 pass, connections enter DRAINING |
| 2026-01-27 | Sequential (post DCID fix) | ✅ PASS | 10/10 pass |
| 2026-01-27 | 3 parallel downloads | ✅ PASS | 3/3 pass |
| 2026-01-27 | 5 parallel downloads | ✅ PASS | 5/5 pass (was 1-4/5) |
| 2026-01-27 | 10 parallel downloads | ✅ PASS | 10/10 pass x2 runs (was 0-7/10) |
| 2026-01-27 | Sequential after parallel | ✅ PASS | 10/10 pass |
| 2026-01-27 | Upload HTTP/1.1 5MB | ✅ PASS | SHA256 match |
| 2026-01-27 | Upload HTTP/2 5MB | ✅ PASS | SHA256 match |
| 2026-01-27 | Upload HTTP/3 5MB | ✅ PASS | SHA256 match (after flow control fix) |
| 2026-01-27 | Upload HTTP/3 30MB | ✅ PASS | SHA256 match |
| 2026-01-27 | Piped upload all protocols | ✅ PASS | All 3 protocols match |
| 2026-01-27 | Streaming endpoint | ✅ PASS | SHA256 match |
| 2026-01-27 | Download regression | ✅ PASS | MD5=ae525b610cdca28ffed9b81e2cfa47b8 |
| 2026-01-27 | Upload HTTP/3 100MB piped | ✅ PASS | SHA256 match, chunked (no Content-Length) |
| 2026-01-27 | Upload HTTP/3 100MB file | ✅ PASS | SHA256 match, with Content-Length |
| 2026-01-27 | Upload HTTP/1.1 100MB piped | ✅ PASS | SHA256=2e39e466ea3c5ea57795a38e1782821d4715da498c58dda079fb9e8aa7cb6081 |
| 2026-01-27 | aioquic single download | ✅ PASS | 31MB, MD5 match, 3.1s |
| 2026-01-27 | aioquic 3 parallel downloads | ✅ PASS | 3x31MB on 1 conn, all MD5 match, 8.8s |
| 2026-01-27 | aioquic uploads (24B+5MB+1MB) | ✅ PASS | All SHA256 match, connection reuse works |
| 2026-01-27 | aioquic 3 parallel uploads | ✅ PASS | 3x2MB on 1 conn, all SHA256 match, 1.0s |
| 2026-01-27 | aioquic connection reuse | ✅ PASS | 3 downloads + GET + upload on single conn |
| 2026-01-27 | HTTP/2 WebSocket baseline | ✅ PASS | Extended CONNECT, status 200, VALUE msgs received |
| 2026-01-27 | HTTP/3 WebSocket headers | ✅ PASS | C layer receives 8 headers, is_connect=1 detected |
| 2026-01-27 | HTTP/3 WebSocket tunnel | ✅ PASS | Fixed 3 bugs: state mismatch, header pair filtering, missing flush_packets |
| 2026-01-27 | HTTP/3 WebSocket full test | ✅ PASS | 4/4: PING/PONG, NOTIFY update_all (16 vars), continuous stream (8 updates/2s), graceful close |
| 2026-01-27 | Debug cleanup + rebuild | ✅ PASS | All temp debug removed from HTTP3Handler, WebFrontend, HTTP3.xs, h3_callbacks.c |
| 2026-01-27 | WebSocket clean verify | ✅ PASS | 4/4 WS tests pass on clean build (no debug code) |
| 2026-01-27 | Download regression | ✅ PASS | MD5=ae525b610cdca28ffed9b81e2cfa47b8 (post-WS fix) |
| 2026-01-27 | Upload regression (5MB) | ✅ PASS | SHA256 match, 5,242,880 bytes (post-WS fix) |

## Build Fixes Applied

| Date | File | Issue | Fix |
|------|------|-------|-----|
| 2026-01-23 | src/h3_tls.c | Missing strcasecmp/strdup | Added `#define _GNU_SOURCE` and `#include <strings.h>` |
| 2026-01-23 | src/h3_callbacks.c | Missing gnutls_rnd | Added `#include <gnutls/crypto.h>` |
| 2026-01-23 | src/h3_packet.c | Missing clock_gettime | Added `#define _POSIX_C_SOURCE 199309L` |
| 2026-01-23 | src/h3_packet.h | Missing sockaddr_storage | Added `#include <sys/socket.h>` and `#include <netinet/in.h>` |
| 2026-01-23 | src/h3_internal.h | Macro name conflicts | Renamed logging macros to H3_ERR, H3_WARN, etc. |
| 2026-01-23 | src/h3_api.c | Duplicate function definitions | Removed wrapper functions (implementations in h3_connection.c) |
| 2026-01-23 | typemap | Missing PageCamel_H3_Wrapper | Added T_H3_WRAPPER typemap entry |
| 2026-01-23 | HTTP3.xs | Missing state constants | Added H3_STATE_* constant exports |
| 2026-01-23 | HTTP3Handler.pm | Undefined $h3conn in callbacks | Changed to use $self->{h3conn} |
| 2026-01-23 | h3_connection.c | Wrong original_dcid in transport params | Added original_dcid parameter, use for params.original_dcid |
| 2026-01-23 | h3_callbacks.c | Buffer over-consumption causing data loss | Moved h3_buffer_consume() into read_data callback |
| 2026-01-23 | h3_packet.c | Incorrect buffer consumption | Removed h3_buffer_consume() calls (now in read_data) |
| 2026-01-23 | h3_buffer.h | No backpressure mechanism | Added H3_MAX_BUFFER_SIZE (10MB), h3_buffer_can_write(), h3_buffer_memory_usage() |
| 2026-01-23 | h3_api.c | Unbounded buffer growth | h3_send_response_body() returns H3_WOULDBLOCK when buffer exceeds 10MB |
| 2026-01-27 | h3_callbacks.c | Upload flow control not extended for body data | Added extend_max_stream_offset/extend_max_offset in recv_data + new deferred_consume callback |
| 2026-01-27 | h3_connection.c | Extended CONNECT not advertised | Set `http3_settings.enable_connect_protocol = 1` for RFC 9220 WebSocket support |
| 2026-01-27 | HTTP3Handler.pm | WebSocket tunnel state mismatch | Changed handleConnectRequest to use `waiting_response` + `streamTunnelPending` flag |
| 2026-01-27 | HTTP3Handler.pm | Header pair filtering corruption | Replaced broken `grep` with paired iteration, filtering content-length/upgrade/connection |
| 2026-01-27 | HTTP3Handler.pm | Missing flush_packets after tunnel headers | Added `$h3conn->flush_packets()` after `send_response_headers` for tunnels |

## Debug Notes

### WebFrontend.pm Integration Status (2026-01-23) - COMPLETED

All WebFrontend.pm updates are now complete:
- ✅ HTTP/3 availability check updated to use new module
- ✅ Timestamp calls updated to PageCamel::Protocol::HTTP3::timestamp_ns()
- ✅ handleNewQUICConnection() rewritten to use new API
- ✅ All packet routing functions updated for handler-based model
- ✅ Obsolete functions removed (handleQUICHandshake, handleHTTP3Request, etc.)
- ✅ Build and unit tests pass (60/60 tests)

The architecture is now:
1. `handleNewQUICConnection()` creates h3Config hash and HTTP3Handler
2. Handler's `init()` creates `PageCamel::Protocol::HTTP3::Connection`
3. Handler is stored in `quicConnections` hash (not old quicConn)
4. Packets are sent via handler's `sendPacketCallback` (not sendQUICPackets)
5. All h3conn callbacks (on_request, on_request_body, on_stream_close) handled in C

Ready for integration testing with curl-h3.

### curl-h3 Integration Testing (2026-01-23) - IN PROGRESS

#### Issue 1: TLS Handshake Failing - FIXED ✅

**Root Cause**: Missing `original_dcid` parameter in transport params.

The transport params `original_dcid` field was incorrectly set to client's SCID instead of client's original DCID from the Initial packet. The client validates this during handshake.

**Fix Applied**:
- Added `original_dcid` parameter to XS wrapper and h3_connection_new_server()
- WebFrontend.pm already passed `original_dcid` in h3Config, now XS uses it
- Updated h3_connection.c to use original_dcid_obj for params.original_dcid

**Files Modified**:
- `lib/PageCamel/Protocol/HTTP3/HTTP3.xs` - Added original_dcid parsing
- `lib/PageCamel/Protocol/HTTP3/src/h3_api.h` - Updated function signature
- `lib/PageCamel/Protocol/HTTP3/src/h3_connection.c` - Use original_dcid for transport params
- `lib/PageCamel/CMDLine/WebFrontend/HTTP3Handler.pm` - Pass original_dcid to new_server

**Result**: TLS handshake now completes, HTTP/3 requests work.

#### Issue 2: Data Corruption in Large Downloads - FIXED ✅

**Symptoms**:
- 31MB test file download: baseline=31457280 bytes, HTTP/3=31455423 bytes
- Missing 1857 bytes (varied between runs)
- First corruption at byte 4 (start of file!)
- Data started at record 89 instead of record 0

**Root Cause**:
The `h3_buffer_consume()` function was being called from `h3_packet.c` with `ndatalen` from `ngtcp2_conn_writev_stream()`. However, `ndatalen` includes ALL HTTP/3 stream data:
- HTTP/3 HEADERS frame (~356 bytes for this response)
- HTTP/3 DATA frame headers
- Actual body data

But our body buffer ONLY contains body data, not HTTP/3 framing. So when we consumed 356 bytes (the HEADERS frame size) before any body data was written, we skipped the first 356 bytes of actual body data.

**Debug trace showing the bug**:
```
h3_buffer_read: WOULDBLOCK (pos beyond data)      # No body data yet
h3_buffer_consume: bytes=356 consumed_before=0    # Consuming HEADERS frame size!
!!! ERROR: consumed(356) > total(0)!              # Over-consumption detected
h3_buffer_write: first_bytes=01000000 01000001    # Body data arrives (record 0)
h3_buffer_read: stream_offset=356, first=01000059 # Reading at offset 356 = record 89!
```

**Fix Applied**:
1. Moved `h3_buffer_consume()` call into the `read_data` callback in `h3_callbacks.c`
2. Consume happens immediately when returning body data, with exact byte count
3. Removed consume calls from `h3_packet.c` (they were consuming framing+body)
4. Added safeguard in `h3_buffer_consume()` to never consume more than available

**Files Modified**:
- `src/h3_callbacks.c` - Added `h3_buffer_consume()` call in `http3_read_data_callback()`
- `src/h3_packet.c` - Removed `h3_buffer_consume()` calls after `writev_stream`
- `src/h3_buffer.c` - Added over-consumption protection (clamp to available)

**Result**: 10/10 download tests pass with correct MD5 checksum.

**Key Insight**: Only the `read_data` callback knows how much actual body data is being returned. The caller (`h3_packet.c`) only knows `ndatalen` which includes HTTP/3 framing overhead.

#### Issue 3: Parallel Connection Failures - FIXED ✅

**Symptoms**:
- Sequential downloads: 9-10/10 pass
- 3 parallel connections: 3/3 pass
- 5 parallel connections: 1-4/5 pass (inconsistent)
- 10 parallel connections: 0-7/10 pass (highly variable)
- Fresh server performs better than server running for hours
- Failures manifest as:
  - Exit code 55: "Failed sending network data" (connection dropped)
  - Exit code 56: "Failure in receiving network data"
  - Exit code 124: Timeout (60 seconds)
- Server logs show: `is_closing() returned: 1` immediately after connection init
- Connections enter DRAINING state unexpectedly

**Investigation So Far**:

1. **Removed excessive debug logging** - `fprintf(stderr, ...)` calls in h3_packet.c were causing I/O blocking
   - Disabled `H3_PACKET_DEBUG`, `H3_TLS_DEBUG`, `H3_CALLBACKS_DEBUG`
   - Removed unconditional fprintf calls from flush function
   - Result: Slight improvement but not fixed

2. **Added packet drain loop** - Modified main event loop to drain all UDP packets
   - `handleQUICPacket()` now returns 1 if packet processed, 0 if none
   - Main loop calls in a while loop until no more packets
   - Result: No significant improvement

3. **Checked flush iteration limits** - `maxFlushIterations` was 100 per connection
   - Reduced to 5: Made things worse (0/5 passed)
   - Reduced to 20: No improvement
   - Reverted to 100
   - Result: Not the cause

4. **Connection state analysis**:
   - Working connections: `is_closing() returned: 0` → "HTTP/3 connection established"
   - Failed connections: `is_closing() returned: 1` → "HTTP3Handler connection failed or closing"
   - `ngtcp2_conn_read_pkt` returns `NGTCP2_ERR_DRAINING` causing immediate close

**Theories**:

1. **Event loop starvation**: Single HTTP/3 process handles all connections. When processing heavy data transfers, new connection handshakes may be delayed, causing client timeouts.

2. **UDP buffer overflow**: Multiple clients sending packets simultaneously may overflow the server's UDP receive buffer, causing packet loss during handshake.

3. **Connection ID collision**: Multiple simultaneous Initial packets may cause confusion in connection ID tracking.

4. **TLS session issues**: GnuTLS may have issues with concurrent handshakes in a single process.

5. **ngtcp2 state machine**: Something in the packet processing order may be confusing the QUIC state machine when multiple connections are active.

6. **Packet misrouting during cleanup**: Packets are routed primarily by peer
   address (`quicConnectionsByAddr{"$ip:$port"}`), with connection ID lookup as
   fallback. `cleanupQUICConnection` deletes from both hashes, but these deletions
   are not atomic. If a new packet arrives from the same peer address between
   the cleanup of the old connection and the creation of the new one, OR if the
   old handler's `quicConnectionsByAddr` entry is deleted but some
   `quicConnections` entries remain (or vice versa), packets could be:
   - Fed to a stale/dead handler → returns error → connection fails
   - Treated as a new connection when they belong to an existing one → ngtcp2
     sees unexpected DCID → enters DRAINING
   - Routed via address to the wrong handler (if a previous connection from the
     same IP:port wasn't fully cleaned up)
   This is especially likely under parallel load where connections are being
   created and torn down rapidly from the same IP.

**Investigation Round 2 (2026-01-27)**:

5. **Removed remaining debug fprintf/print** - Removed all debug output from:
   - HTTP3.xs: process_packet, flush_packets, new_server fprintf calls
   - h3_api.c: h3_flush_packets fprintf call
   - HTTP3Handler.pm: All DEBUG print STDERR lines
   - Result: Much less I/O noise, no functional change

6. **Added early-out in h3_packet_flush for closed connections** - REVERTED
   - First tried: skip DRAINING and CLOSED → 0/5 sequential passed (REGRESSION)
   - Then tried: skip only CLOSED → 2/5 sequential passed (still worse)
   - Reverted entirely → needs retest
   - Lesson: h3_packet_flush MUST run even for closing connections (ngtcp2 needs to
     send CONNECTION_CLOSE frames; skipping causes clients to hang)

7. **Added is_closing() guards** in Perl event loop functions:
   - `flushPendingStreams()` returns 0 early if closing
   - `handleHTTP3Backends()` skips closing handlers
   - `handleQUICTimeouts()` skips closing handlers
   - Result: Prevents wasted work on dead connections

8. **Fixed tunnel_active EOF handling** - was sending EOF before buffer was empty:
   - Both `readFromBackends` and `flushPendingStreams` now check `$bufferEmpty`
     before sending EOF when backend disconnects in tunnel_active state
   - Previously could lose buffered data

9. **Changed streaming/tunnel cleanup to defer via streamPendingFlush**:
   - After sending EOF, set `streamPendingFlush` instead of calling `cleanupStream()`
   - Wait for C-level buffer to drain (checked in flushPendingStreams loop)
   - Prevents premature stream cleanup while C library still has data to send

**Packet Routing Architecture** (discovered during investigation):

```
UDP packet arrives
  → Primary lookup: quicConnectionsByAddr{"$peerhost:$peerPort"}
  → Fallback: extractQUICConnectionId(packet) → quicConnections{$dcid}
  → No match: handleNewQUICConnection()
```

- Routing is primarily by **peer address** (IP:port), NOT by connection ID
- Connection ID lookup is only used as fallback (connection migration case)
- Short header packets (most traffic) don't contain SCID, only DCID
- Each connection is stored under 3 keys: client_dcid, client_scid, server_scid
- **Potential issue**: if cleanup removes quicConnectionsByAddr entry but not all
  quicConnections entries (or vice versa), stale handlers could receive packets
  meant for new connections

**Files Modified (Round 2)**:
- `lib/PageCamel/Protocol/HTTP3/HTTP3.xs` - Removed all debug fprintf
- `lib/PageCamel/Protocol/HTTP3/src/h3_api.c` - Removed h3_flush_packets fprintf
- `lib/PageCamel/Protocol/HTTP3/src/h3_packet.c` - Reverted early-out (h3_packet_flush)
- `lib/PageCamel/CMDLine/WebFrontend/HTTP3Handler.pm` - Removed DEBUG prints,
  added is_closing guard in flushPendingStreams, fixed tunnel_active EOF,
  changed streaming/tunnel to use streamPendingFlush
- `lib/PageCamel/CMDLine/WebFrontend.pm` - Added is_closing guards in
  handleHTTP3Backends and handleQUICTimeouts

**Investigation Round 3 (2026-01-27) - DCID Routing Fix**:

10. **Root cause identified: Address-based primary routing**
    - Our `handleQUICPacket` routes packets primarily by peer address (`quicConnectionsByAddr{"$ip:$port"}`)
    - DCID-based lookup is only a fallback when address lookup fails
    - This is the **opposite** of what every QUIC server does (ngtcp2 examples, nginx, quiche, h2o, quic-go)
    - RFC 9000 Section 5.2 explicitly states DCID should be the primary routing key
    - Address-based routing is "fragile" per RFC 9000 and breaks on connection migration

11. **Specific bugs caused by address-based routing**:
    a. **Packet misrouting on IP:port reuse**: When client B sends Initial from same IP:port as
       active connection A (NAT rebinding, rapid reconnect), `quicConnectionsByAddr` routes B's
       packet to handler A → ngtcp2 sees unexpected packet → DRAINING/error
    b. **processIncomingUdpNonBlocking feeds ALL packets to one handler**: During flush loops,
       packets for connection B are fed to handler A → ngtcp2 sees wrong DCID → connection failure
    c. **Connection migration breaks cleanup**: Address-based cleanup can miss entries or remove
       wrong entries when addresses change

12. **Fix applied: DCID-primary routing**
    - Removed `quicConnectionsByAddr` hash entirely
    - `handleQUICPacket`: Extract DCID first → look up in `quicConnections` → route
    - `processIncomingUdpNonBlocking`: Removed handler parameter, routes each packet by DCID
    - Unknown DCID + long header → `handleNewQUICConnection` (potential Initial)
    - Unknown DCID + short header → drop silently (stale/invalid)
    - Updated all callers of `processIncomingUdpNonBlocking`

**Research findings (from ngtcp2 examples, nginx, quiche, h2o, quic-go)**:
- ALL use `HashMap<ConnectionID, Handler>` as the primary routing structure
- New connections: validate with `ngtcp2_accept()` or check for Initial packet type
- Connection migration: transparent when routing by DCID (just pass actual source addr to ngtcp2)
- Draining: keep CID entries in map during draining period (3x PTO) to consume late packets
- Multiple CIDs per connection: all mapped to same handler (initial DCID + server SCIDs + new CIDs)

### Upload Bug: QUIC Flow Control Window Not Extended (2026-01-27) - FIXED ✅

**Symptom**: HTTP/3 uploads fail (timeout, no response) when body size exceeds the
`initial_max_stream_data_bidi` flow control window (default 1MB). Small uploads work.

**Exact threshold**: Body of 1,048,512 bytes works; 1,048,514 bytes fails. The total
stream data (body + ~62 bytes HTTP/3 framing overhead) crosses exactly 1,048,576 (1MB).

**Root Cause**: `nghttp3_conn_read_stream()` return value only covers HTTP/3 framing
overhead (HEADERS frame, DATA frame headers, QPACK), NOT the body data payload. We were
calling `ngtcp2_conn_extend_max_stream_offset()` only with the framing byte count from
the `recv_stream_data` ngtcp2 callback, but body data bytes were never accounted for.
The client's flow control window was never extended for body data, so uploads exceeding
the initial window would stall.

**Fix Applied**: Extend flow control from THREE callback sites:

1. **`recv_stream_data` (ngtcp2 callback)**: Extend by `nghttp3_conn_read_stream()` return
   value — covers HTTP/3 framing overhead only. (Already existed at h3_callbacks.c:92-93)

2. **`recv_data` (nghttp3 callback)**: Added `ngtcp2_conn_extend_max_stream_offset()` and
   `ngtcp2_conn_extend_max_offset()` calls with `datalen` — covers body data payload.

3. **`deferred_consume` (nghttp3 callback)**: New callback — extends flow control for
   bytes that nghttp3 consumed internally (deferred processing).

**Files Modified**:
- `src/h3_callbacks.c` - Added flow control extension in `http3_recv_data_callback`,
  added new `http3_deferred_consume_callback`, registered in `h3_setup_http3_callbacks`

**Verification**: Uploads of 1MB, 5MB, 30MB, and 100MB all pass with correct SHA256
checksums across HTTP/1.1, HTTP/2, and HTTP/3 protocols.

### WebSocket over HTTP/3: Extended CONNECT (2026-01-27) - FIXED ✅

**Goal**: WebSocket over HTTP/3 via Extended CONNECT (RFC 9220).

**Endpoint**: `wss://test.cavac.at/guest/kaffeesim/ws` (KaffeeSim coffee machine simulator)

**KaffeeSim WebSocket Protocol** (JSON over WebSocket text frames):
```
Client→Server: {"type":"PING"}                                    → Server echoes PING
Client→Server: {"type":"NOTIFY","varname":"update_all"}           → Server sends all state
Client→Server: {"type":"SET","varname":"...","varvalue":N}        → Control machine (manual mode)
Client→Server: {"type":"LISTEN","varname":"..."}                  → Subscribe to variable
Server→Client: {"type":"PING"}                                    → Keep-alive ack
Server→Client: {"type":"VALUE","varname":"...","varval":"..."}    → State update
```

**Three bugs found and fixed**:

1. **Stream state mismatch** (`tunnel_pending` vs `waiting_response`):
   - `handleConnectRequest` set stream state to `tunnel_pending`
   - `processBackendResponse` only processes `waiting_response` state
   - Backend's `101 Switching Protocols` was ignored because state didn't match
   - Fix: Use `waiting_response` state + `streamTunnelPending` flag

2. **Header pair filtering corruption** (33 elements, broken pairs):
   - `grep { $_ ne 'content-length' } @responseHeaders` on flat name/value array
   - Only removed the name string, leaving orphaned value (odd count = broken pairs)
   - Corrupted HTTP/3 headers caused ngtcp2 to enter DRAINING state → H3_ERROR_CLOSED
   - Fix: Proper paired iteration filtering content-length, upgrade, connection headers

3. **Missing `flush_packets()` after tunnel headers**:
   - Code only called `flush_packets()` when body had data
   - WebSocket tunnel with 0 body bytes: response queued in nghttp3 but never transmitted
   - Fix: Added unconditional `$h3conn->flush_packets()` after `send_response_headers`

**Files modified** (permanent changes):
- `lib/PageCamel/CMDLine/WebFrontend/HTTP3Handler.pm` - All 3 bug fixes

**All temporary debug code removed** from:
- `h3_callbacks.c` - recv_header/end_headers/on_request fprintf
- `HTTP3.xs` - xs_on_request_cb fprintf
- `HTTP3Handler.pm` - handleRequest/handleConnectRequest/handleBackendData/processBackendResponse print STDERR
- `WebFrontend.pm` - main loop/handleHTTP3Backends/handleQUICTimeouts print STDERR

**Test results**: 4/4 WebSocket tests PASS:
- PING/PONG echo
- NOTIFY update_all → 16 VALUE messages (boiler_temp, boiler_waterlevel, production_enable present)
- Continuous stream → 8 updates in 2 seconds
- Graceful close
