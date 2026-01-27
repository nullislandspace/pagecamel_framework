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

5. **Backpressure with max buffer size (10MB)**
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
