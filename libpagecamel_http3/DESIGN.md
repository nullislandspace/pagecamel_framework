# libpagecamel_http3 Design Document

## Overview

A C library that encapsulates the nghttp3/ngtcp2 integration, exposing a simple API
for Perl to handle UDP I/O and HTTP request/response processing.

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                         Perl Layer                              │
├─────────────────────────────────────────────────────────────────┤
│  UDP Socket I/O          │  Request Handler    │  Logging       │
│  (AnyEvent/IO::Socket)   │  (HTTP backend)     │  (debug/error) │
└──────────┬───────────────┴────────┬────────────┴───────┬────────┘
           │                        │                    │
           │ Callbacks              │ API calls          │ Callbacks
           ▼                        ▼                    ▼
┌─────────────────────────────────────────────────────────────────┐
│                    libpagecamel_http3.so                        │
├─────────────────────────────────────────────────────────────────┤
│  ┌─────────────┐    ┌──────────────┐    ┌─────────────────┐    │
│  │   ngtcp2    │◄──►│  Integration │◄──►│    nghttp3      │    │
│  │   (QUIC)    │    │    Layer     │    │   (HTTP/3)      │    │
│  └─────────────┘    └──────────────┘    └─────────────────┘    │
│                                                                 │
│  - Connection state management                                  │
│  - Callback wiring between libraries                            │
│  - Buffer management (chunk-based)                              │
│  - Timer management                                             │
│  - Flow control coordination                                    │
└─────────────────────────────────────────────────────────────────┘
```

## Design Principles

1. **All C-to-C communication stays in C** - nghttp3 and ngtcp2 callbacks are
   wired together in C, eliminating Perl/XS trampoline overhead and pointer
   lifetime issues.

2. **Perl handles I/O only** - UDP send/receive, which Perl already does well
   with AnyEvent.

3. **Simple return codes** - Perl callbacks return simple status codes, not
   complex structures.

4. **Logging via callback** - All debug/error output goes through a Perl
   callback for consistent logging.

5. **Based on proven patterns** - Implementation follows curl's ngtcp2
   integration patterns.

---

## API: Return Codes

```c
typedef enum {
    H3_OK = 0,              /* Success */
    H3_WOULDBLOCK = 1,      /* Operation would block, try again later */
    H3_ERROR = -1,          /* Generic error */
    H3_ERROR_NOMEM = -2,    /* Out of memory */
    H3_ERROR_INVALID = -3,  /* Invalid parameter */
    H3_ERROR_CLOSED = -4,   /* Connection closed */
    H3_ERROR_STREAM = -5,   /* Stream error */
    H3_ERROR_CRYPTO = -6,   /* TLS/crypto error */
} h3_result_t;
```

---

## API: Logging

```c
typedef enum {
    H3_LOG_ERROR = 0,
    H3_LOG_WARN = 1,
    H3_LOG_INFO = 2,
    H3_LOG_DEBUG = 3,
    H3_LOG_TRACE = 4,
} h3_log_level_t;

/* Callback signature for logging */
typedef void (*h3_log_callback_t)(
    h3_log_level_t level,
    const char *component,   /* "ngtcp2", "nghttp3", "h3conn", etc. */
    const char *message
);

/* Set global log callback and minimum level */
void h3_set_log_callback(h3_log_callback_t cb, h3_log_level_t min_level);
```

---

## API: UDP I/O Callbacks

```c
/* Callback for sending UDP packets
 * Returns: H3_OK if sent, H3_WOULDBLOCK if socket busy, H3_ERROR on failure
 */
typedef h3_result_t (*h3_send_packet_callback_t)(
    void *userdata,
    const uint8_t *data,
    size_t len,
    const struct sockaddr *remote_addr,
    socklen_t remote_addr_len
);

/* Callback when connection needs attention (timer expired, data ready) */
typedef void (*h3_wakeup_callback_t)(
    void *userdata
);
```

---

## API: HTTP Request/Response Callbacks

```c
/* Header field (name/value pair) */
typedef struct {
    const char *name;
    size_t name_len;
    const char *value;
    size_t value_len;
} h3_header_t;

/* Callback when a new request arrives */
typedef void (*h3_request_callback_t)(
    void *userdata,
    int64_t stream_id,
    const h3_header_t *headers,
    size_t header_count
);

/* Callback when request body data arrives */
typedef void (*h3_request_body_callback_t)(
    void *userdata,
    int64_t stream_id,
    const uint8_t *data,
    size_t len,
    int eof  /* 1 if this is the last chunk */
);

/* Callback when a stream is closed/reset */
typedef void (*h3_stream_close_callback_t)(
    void *userdata,
    int64_t stream_id,
    uint64_t app_error_code
);
```

---

## API: Connection Management

```c
/* Opaque connection handle */
typedef struct h3_connection h3_connection_t;

/* Configuration for new connections */
typedef struct {
    /* TLS certificate and key files */
    const char *cert_file;
    const char *key_file;

    /* Server name (for SNI) */
    const char *server_name;

    /* QUIC settings */
    uint64_t max_stream_data_bidi_local;   /* default: 256KB */
    uint64_t max_stream_data_bidi_remote;  /* default: 256KB */
    uint64_t max_stream_data_uni;          /* default: 256KB */
    uint64_t max_data;                     /* default: 1MB */
    uint64_t max_streams_bidi;             /* default: 100 */
    uint64_t max_streams_uni;              /* default: 3 */
    uint64_t idle_timeout_ms;              /* default: 30000 (30s) */

    /* Callbacks */
    h3_send_packet_callback_t send_packet;
    h3_wakeup_callback_t wakeup;
    h3_request_callback_t on_request;
    h3_request_body_callback_t on_request_body;
    h3_stream_close_callback_t on_stream_close;

    /* Userdata passed to callbacks */
    void *userdata;
} h3_config_t;

/* Initialize library (call once at startup) */
h3_result_t h3_init(void);

/* Cleanup library (call once at shutdown) */
void h3_cleanup(void);

/* Create a new server connection
 * client_addr: the remote client's address
 * scid/dcid: source/destination connection IDs from Initial packet
 */
h3_result_t h3_connection_new_server(
    h3_connection_t **conn_out,
    const h3_config_t *config,
    const struct sockaddr *client_addr,
    socklen_t client_addr_len,
    const uint8_t *scid, size_t scid_len,
    const uint8_t *dcid, size_t dcid_len
);

/* Destroy a connection */
void h3_connection_free(h3_connection_t *conn);

/* Get connection state */
typedef enum {
    H3_CONN_STATE_HANDSHAKING,
    H3_CONN_STATE_ESTABLISHED,
    H3_CONN_STATE_DRAINING,
    H3_CONN_STATE_CLOSED,
} h3_conn_state_t;

h3_conn_state_t h3_connection_get_state(h3_connection_t *conn);
```

---

## API: Packet Processing

```c
/* Process an incoming UDP packet
 * Call this when Perl receives data on the UDP socket
 */
h3_result_t h3_process_packet(
    h3_connection_t *conn,
    const uint8_t *data,
    size_t len,
    const struct sockaddr *remote_addr,
    socklen_t remote_addr_len
);

/* Generate and send outgoing packets
 * Call this after processing packets or when wakeup callback fires
 * Returns H3_OK if all packets sent, H3_WOULDBLOCK if socket busy
 */
h3_result_t h3_flush_packets(h3_connection_t *conn);

/* Retry sending packets after WOULDBLOCK
 * Call this when socket becomes writable again
 */
h3_result_t h3_retry_send(h3_connection_t *conn);

/* Get timeout in milliseconds until next required action
 * Returns 0 if action needed now, UINT64_MAX if no timer needed
 */
uint64_t h3_get_timeout_ms(h3_connection_t *conn);

/* Handle timeout expiry
 * Call this when the timer from h3_get_timeout_ms expires
 */
h3_result_t h3_handle_timeout(h3_connection_t *conn);
```

---

## API: Sending HTTP Responses

```c
/* Begin sending a response (headers)
 * status: HTTP status code (200, 404, etc.)
 * headers: array of additional headers (can be NULL if header_count is 0)
 * header_count: number of additional headers
 */
h3_result_t h3_send_response_headers(
    h3_connection_t *conn,
    int64_t stream_id,
    int status,
    const h3_header_t *headers,
    size_t header_count
);

/* Send response body data
 * data: body data to send
 * len: length of data
 * eof: 1 if this is the last chunk, 0 otherwise
 *
 * Returns: H3_OK if queued, H3_WOULDBLOCK if flow control limited
 */
h3_result_t h3_send_response_body(
    h3_connection_t *conn,
    int64_t stream_id,
    const uint8_t *data,
    size_t len,
    int eof
);

/* Reset a stream with an error code */
h3_result_t h3_reset_stream(
    h3_connection_t *conn,
    int64_t stream_id,
    uint64_t app_error_code
);

/* Get amount of data queued for a stream (for flow control decisions) */
size_t h3_stream_get_queued_bytes(
    h3_connection_t *conn,
    int64_t stream_id
);
```

---

## API: Connection Info

```c
/* Get connection statistics */
typedef struct {
    uint64_t bytes_sent;
    uint64_t bytes_received;
    uint64_t packets_sent;
    uint64_t packets_received;
    uint64_t packets_lost;
    uint64_t rtt_ms;          /* Smoothed RTT */
    uint64_t cwnd;            /* Congestion window */
    uint64_t streams_opened;
    uint64_t streams_closed;
} h3_stats_t;

void h3_connection_get_stats(h3_connection_t *conn, h3_stats_t *stats);

/* Get the original destination connection ID (for routing) */
void h3_connection_get_dcid(
    h3_connection_t *conn,
    uint8_t *dcid_out,
    size_t *dcid_len_out
);
```

---

## Internal Architecture

### Connection Structure (internal, not exposed to Perl)

```c
struct h3_connection {
    /* ngtcp2 connection */
    ngtcp2_conn *quic_conn;

    /* nghttp3 connection */
    nghttp3_conn *http3_conn;

    /* TLS state (GnuTLS or OpenSSL) */
    void *tls_ctx;

    /* Configuration and callbacks */
    h3_config_t config;

    /* Remote address */
    struct sockaddr_storage remote_addr;
    socklen_t remote_addr_len;

    /* Packet buffer for outgoing data */
    uint8_t *send_buf;
    size_t send_buf_size;

    /* Pending send data (when WOULDBLOCK) */
    uint8_t *pending_data;
    size_t pending_len;

    /* Stream data buffers (chunk-based) */
    struct stream_buffer *streams;

    /* State */
    h3_conn_state_t state;
    uint64_t last_error;

    /* Timers */
    uint64_t next_timeout;
};
```

### Internal Callback Wiring

The key integration happens in these internal functions:

```c
/* ngtcp2 callback: stream data received */
static int on_recv_stream_data(ngtcp2_conn *conn, uint32_t flags,
                               int64_t stream_id, uint64_t offset,
                               const uint8_t *data, size_t datalen,
                               void *user_data, void *stream_user_data) {
    h3_connection_t *h3 = user_data;

    /* Feed directly to nghttp3 - no Perl involved */
    int rv = nghttp3_conn_read_stream(h3->http3_conn, stream_id,
                                      data, datalen, flags & NGTCP2_STREAM_DATA_FLAG_FIN);
    /* ... handle errors ... */
    return 0;
}

/* nghttp3 callback: need to read application data for sending */
static nghttp3_ssize on_read_data(nghttp3_conn *conn, int64_t stream_id,
                                   nghttp3_vec *vec, size_t veccnt,
                                   uint32_t *pflags, void *conn_user_data,
                                   void *stream_user_data) {
    h3_connection_t *h3 = conn_user_data;
    stream_buffer_t *buf = find_stream_buffer(h3, stream_id);

    /* Return pointer directly into our stable chunk memory */
    /* All in C - no XS boundary crossing */
    return fill_vectors_from_buffer(buf, vec, veccnt, pflags);
}

/* nghttp3 callback: data acknowledged */
static int on_acked_stream_data(nghttp3_conn *conn, int64_t stream_id,
                                 uint64_t datalen, void *conn_user_data,
                                 void *stream_user_data) {
    h3_connection_t *h3 = conn_user_data;
    stream_buffer_t *buf = find_stream_buffer(h3, stream_id);

    /* Free acknowledged chunks - all in C */
    free_acked_data(buf, datalen);
    return 0;
}
```

---

## Perl XS Wrapper

The XS wrapper is minimal:

```perl
package PageCamel::HTTP3;

use strict;
use warnings;

# Load the XS module
require XSLoader;
XSLoader::load('PageCamel::HTTP3', $VERSION);

# Callback storage (prevent garbage collection)
my %callbacks;

sub new_server {
    my ($class, %config) = @_;

    my $self = bless {}, $class;

    # Store callbacks to prevent GC
    $callbacks{$self} = {
        send_packet => $config{send_packet},
        on_request => $config{on_request},
        on_request_body => $config{on_request_body},
        on_stream_close => $config{on_stream_close},
        log => $config{log},
    };

    # Create the C connection
    $self->{_conn} = _connection_new_server(
        $config{cert_file},
        $config{key_file},
        $config{client_addr},
        $config{scid},
        $config{dcid},
        # ... etc
    );

    return $self;
}

# ... etc
```

---

## File Structure

```
libpagecamel_http3/
├── DESIGN.md           # This file
├── Makefile.PL         # Perl XS build
├── lib/
│   └── PageCamel/
│       └── HTTP3.pm    # Perl interface
├── src/
│   ├── h3_connection.c # Connection management
│   ├── h3_connection.h
│   ├── h3_internal.h   # Internal structures
│   ├── h3_callbacks.c  # nghttp3/ngtcp2 callback wiring
│   ├── h3_buffer.c     # Stream buffer management
│   ├── h3_tls.c        # TLS integration (GnuTLS)
│   ├── h3_packet.c     # Packet processing
│   └── h3_api.c        # Public API implementation
├── xs/
│   └── HTTP3.xs        # Minimal XS wrapper
└── t/
    └── *.t             # Tests
```

---

## Migration Path

1. **Phase 1**: Implement core C library with test harness
2. **Phase 2**: Create XS wrapper
3. **Phase 3**: Update Server.pm to use new API
4. **Phase 4**: Remove old NGHTTP3.xs and NGTCP2.xs
5. **Phase 5**: Testing and optimization

---

## Dependencies

- ngtcp2 (QUIC) - already installed
- nghttp3 (HTTP/3) - already installed
- GnuTLS or OpenSSL - for TLS 1.3
- pkg-config - for library detection

---

## Open Questions

1. **TLS backend**: GnuTLS (current) or OpenSSL? GnuTLS is already used.

2. **Connection routing**: How to route incoming packets to correct connection?
   - Use DCID as lookup key
   - Perl maintains connection table, C just processes packets

3. **Memory limits**: Maximum buffer sizes per stream/connection?
   - Should be configurable in h3_config_t

4. **WebSocket support**: Extended CONNECT for WebSocket over HTTP/3?
   - Can be added later as h3_upgrade_to_websocket()

---

## Testing Setup

### Test Server Management

```bash
# Restart the test server (kills all processes - server AUTOMATICALLY restarts)
# No need to manually start the server or run any start script
killall -9 cavac_webgui_frontend_test_master cavac_webgui_frontend_test_http3 cavac_webgui_frontend_test

# Server log file location
/home/cavac/src/pagecamel_cavac/server/test.log

# Watch server log in real-time
tail -f /home/cavac/src/pagecamel_cavac/server/test.log

# Check recent log entries
tail -50 /home/cavac/src/pagecamel_cavac/server/test.log

# Check for errors in log
grep -E '(ERROR|WARN|error|failed|Assertion)' /home/cavac/src/pagecamel_cavac/server/test.log
```

### Test Domain

- **Test domain**: `test.cavac.at` (NOT cavac.at)
- Server is configured with valid TLS certificates for this domain

### Test Files

| File | URL | Size | MD5 |
|------|-----|------|-----|
| testfile_1.bin | `https://test.cavac.at/public/pimenu/download/testfile_1.bin` | 31,457,280 bytes | `ae525b610cdca28ffed9b81e2cfa47b8` |
| colordemo_20240209.tar.gz | `https://test.cavac.at/public/pimenu/download/colordemo_20240209.tar.gz` | ~34MB | (varies) |

**testfile_1.bin format**: Sequential 4-byte numbers (format: `01 XX XX XX` where XX XX XX is big-endian sequence number). This makes corruption easy to detect and analyze.

### Test Tools

```bash
# HTTP/3 enabled curl (custom build)
/usr/local/bin/curl-h3

# Check curl-h3 version and HTTP/3 support
/usr/local/bin/curl-h3 --version | grep -E 'HTTP3|ngtcp2|nghttp3'
```

### Test Commands

```bash
# Download baseline via HTTP/1.1 (known working)
curl --http1.1 -s -o /tmp/baseline.bin https://test.cavac.at/public/pimenu/download/testfile_1.bin
md5sum /tmp/baseline.bin  # Should be ae525b610cdca28ffed9b81e2cfa47b8

# Test HTTP/3 download
/usr/local/bin/curl-h3 --http3-only -s -o /tmp/h3_test.bin https://test.cavac.at/public/pimenu/download/testfile_1.bin
md5sum /tmp/h3_test.bin

# Find first byte of corruption
cmp /tmp/baseline.bin /tmp/h3_test.bin

# Analyze corruption area (replace OFFSET with byte from cmp output)
xxd -s OFFSET -l 64 /tmp/baseline.bin
xxd -s OFFSET -l 64 /tmp/h3_test.bin

# Large file download with timing info
/usr/local/bin/curl-h3 --http3-only -o /dev/null -w "Downloaded: %{size_download} bytes\nTime: %{time_total}s\nSpeed: %{speed_download} bytes/s\n" https://test.cavac.at/public/pimenu/download/colordemo_20240209.tar.gz

# Basic HTTP/3 connectivity test
/usr/local/bin/curl-h3 --http3-only -v https://test.cavac.at/
```

### Upload Tests

```bash
# Create test file
dd if=/dev/urandom of=/tmp/testfile.bin bs=1M count=10

# Static upload (Content-Length)
/usr/local/bin/curl-h3 --http3-only -T /tmp/testfile.bin https://test.cavac.at/guest/puttest/static

# Streaming upload
dd if=/dev/urandom bs=1M count=10 2>/dev/null | /usr/local/bin/curl-h3 --http3-only -X PUT --data-binary @- https://test.cavac.at/guest/puttest/static
```

### Multi-Stream Tests (Critical)

```bash
# Parallel downloads - tests HTTP/3 multiplexing
/usr/local/bin/curl-h3 --http3-only --parallel --parallel-max 3 \
  -o /tmp/dl1.bin https://test.cavac.at/public/pimenu/download/testfile_1.bin \
  -o /tmp/dl2.bin https://test.cavac.at/public/pimenu/download/testfile_1.bin \
  -o /tmp/dl3.bin https://test.cavac.at/public/pimenu/download/testfile_1.bin

# Verify all files
md5sum /tmp/dl*.bin
# All should be: ae525b610cdca28ffed9b81e2cfa47b8
```

### Alt-Svc Header Verification

```bash
# HTTP/1.1 should advertise HTTP/3
/usr/local/bin/curl-h3 -s -k --http1.1 -D - -o /dev/null https://test.cavac.at/ | grep -i alt-svc

# HTTP/2 should advertise HTTP/3
/usr/local/bin/curl-h3 -s -k --http2 -D - -o /dev/null https://test.cavac.at/ | grep -i alt-svc
```

### Build and Install

```bash
# Build the PageCamel framework (after making changes)
cd /home/cavac/src/pagecamel_framework
perl Makefile.PL && make && make test

# For libpagecamel_http3 specifically (once implemented)
cd /home/cavac/src/pagecamel_framework/libpagecamel_http3
perl Makefile.PL && make && make test
```

### Debugging Tips

1. **Corruption at specific byte offset**: Use `xxd -s OFFSET -l 64` to compare baseline vs corrupted
2. **Intermittent failures**: Run download 10 times in a loop to check consistency
3. **Server-side issues**: Check `test.log` for errors immediately after failed download
4. **Connection issues**: Use `-v` flag with curl for verbose output

---

## References

- curl's ngtcp2 integration: https://github.com/curl/curl/blob/master/lib/vquic/curl_ngtcp2.c
- ngtcp2 programmer's guide: https://nghttp2.org/ngtcp2/programmers-guide.html
- nghttp3 programmer's guide: https://nghttp2.org/nghttp3/programmers-guide.html
- ngtcp2 examples: https://github.com/ngtcp2/ngtcp2/tree/main/examples

---

## Date

2026-01-23
