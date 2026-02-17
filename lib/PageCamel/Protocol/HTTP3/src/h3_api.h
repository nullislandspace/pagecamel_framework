/*
 * h3_api.h - Public API for PageCamel HTTP/3 unified library
 *
 * This library integrates ngtcp2 (QUIC) and nghttp3 (HTTP/3) with direct
 * C-to-C callback wiring, eliminating Perl/XS trampoline overhead that
 * causes data corruption in large file transfers.
 */

#ifndef H3_API_H
#define H3_API_H

#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Opaque connection handle */
typedef struct h3_connection h3_connection_t;

/* Return codes */
#define H3_OK                 0
#define H3_WOULDBLOCK         1
#define H3_ERROR             -1
#define H3_ERROR_NOMEM       -2
#define H3_ERROR_INVALID     -3
#define H3_ERROR_TLS         -4
#define H3_ERROR_QUIC        -5
#define H3_ERROR_HTTP3       -6
#define H3_ERROR_STREAM      -7
#define H3_ERROR_CLOSED      -8

/* Connection states */
typedef enum {
    H3_STATE_INITIAL = 0,
    H3_STATE_HANDSHAKING,
    H3_STATE_ESTABLISHED,
    H3_STATE_DRAINING,
    H3_STATE_CLOSED
} h3_connection_state_t;

/* Header name-value pair */
typedef struct {
    const uint8_t *name;
    size_t name_len;
    const uint8_t *value;
    size_t value_len;
} h3_header_t;

/* Domain TLS configuration */
typedef struct {
    const char *domain;          /* Domain name (e.g., "example.com") */
    const char *cert_path;       /* Path to certificate file (PEM) */
    const char *key_path;        /* Path to private key file (PEM) */
    const char *backend_socket;  /* Backend Unix socket path (optional) */
} h3_domain_config_t;

/* Server configuration */
typedef struct {
    /* TLS/domain settings */
    h3_domain_config_t *domains;
    size_t domain_count;
    const char *default_domain;
    const char *default_backend;

    /* QUIC transport parameters */
    uint64_t initial_max_data;              /* Default: 10MB */
    uint64_t initial_max_stream_data_bidi;  /* Default: 1MB */
    uint64_t initial_max_stream_data_uni;   /* Default: 1MB */
    uint64_t initial_max_streams_bidi;      /* Default: 100 */
    uint64_t initial_max_streams_uni;       /* Default: 100 */
    uint64_t max_idle_timeout_ms;           /* Default: 30000ms */

    /* Congestion control */
    int cc_algo;  /* 0=RENO, 1=CUBIC, 2=BBR, 3=BBR2 */

    /* Logging */
    int enable_debug;
} h3_server_config_t;

/* Address info for packets */
typedef struct {
    const char *local_addr;
    int local_port;
    const char *remote_addr;
    int remote_port;
} h3_addr_info_t;

/*
 * Callbacks from C to Perl (minimal set)
 * Only these callbacks cross the XS boundary.
 */

/* Called when a packet needs to be sent via UDP
 * Returns: >= 0 bytes sent on success, -1 if would block, < -1 on error
 */
typedef int (*h3_send_packet_cb)(
    void *user_data,
    const uint8_t *data,
    size_t len,
    const h3_addr_info_t *addr
);

/* Called when a complete HTTP request is received */
typedef void (*h3_on_request_cb)(
    void *user_data,
    int64_t stream_id,
    const h3_header_t *headers,
    size_t header_count,
    const uint8_t *body,
    size_t body_len,
    int is_connect  /* 1 for extended CONNECT (WebSocket) */
);

/* Called when request body data arrives (for streaming uploads) */
typedef void (*h3_on_request_body_cb)(
    void *user_data,
    int64_t stream_id,
    const uint8_t *data,
    size_t len,
    int fin
);

/* Called when a stream is closed */
typedef void (*h3_on_stream_close_cb)(
    void *user_data,
    int64_t stream_id,
    uint64_t app_error_code
);

/* Called for logging (optional) */
typedef void (*h3_log_cb)(
    void *user_data,
    int level,
    const char *message
);

/* Callback structure */
typedef struct {
    h3_send_packet_cb send_packet;
    h3_on_request_cb on_request;
    h3_on_request_body_cb on_request_body;
    h3_on_stream_close_cb on_stream_close;
    h3_log_cb log;
    void *user_data;
} h3_callbacks_t;

/*
 * Library initialization/cleanup
 */

/* Initialize the library (call once at startup) */
int h3_init(void);

/* Clean up the library (call once at shutdown) */
void h3_cleanup(void);

/* Get library version string */
const char *h3_version(void);

/*
 * Connection management
 */

/* Create a new server connection */
h3_connection_t *h3_connection_new_server(
    const h3_server_config_t *config,
    const h3_callbacks_t *callbacks,
    const uint8_t *dcid, size_t dcid_len,  /* Client's SCID (our destination) */
    const uint8_t *scid, size_t scid_len,  /* Our SCID */
    const uint8_t *original_dcid, size_t original_dcid_len,  /* Client's original DCID for transport params */
    const h3_addr_info_t *addr,
    uint32_t quic_version
);

/* Destroy a connection */
void h3_connection_free(h3_connection_t *conn);

/* Get connection state */
h3_connection_state_t h3_connection_get_state(h3_connection_t *conn);

/* Get negotiated hostname (SNI) */
const char *h3_connection_get_hostname(h3_connection_t *conn);

/* Get selected backend socket path */
const char *h3_connection_get_backend(h3_connection_t *conn);

/*
 * Packet processing
 */

/* Process an incoming UDP packet
 * Returns: H3_OK on success, H3_WOULDBLOCK if more data needed,
 *          H3_ERROR_* on error
 */
int h3_process_packet(
    h3_connection_t *conn,
    const uint8_t *data, size_t len,
    const h3_addr_info_t *addr
);

/* Generate and send outgoing packets via send_packet callback
 * Returns: number of packets sent, or H3_ERROR_* on error
 */
int h3_flush_packets(h3_connection_t *conn);

/* Get timeout in milliseconds until next required processing */
uint64_t h3_get_timeout_ms(h3_connection_t *conn);

/* Handle timeout expiry */
int h3_handle_timeout(h3_connection_t *conn);

/*
 * Response sending
 */

/* Send response headers
 * Returns: H3_OK on success, H3_ERROR_* on error
 */
int h3_send_response_headers(
    h3_connection_t *conn,
    int64_t stream_id,
    int status_code,
    const h3_header_t *headers,
    size_t header_count,
    int has_body  /* 0 for no body, 1 for body to follow */
);

/* Queue response body data (copies to internal buffer)
 * Returns: H3_OK on success, H3_WOULDBLOCK if buffer full,
 *          H3_ERROR_* on error
 */
int h3_send_response_body(
    h3_connection_t *conn,
    int64_t stream_id,
    const uint8_t *data, size_t len,
    int eof  /* 1 to signal end of body */
);

/* Send complete response (headers + body) for small responses
 * Returns: H3_OK on success, H3_ERROR_* on error
 */
int h3_send_response(
    h3_connection_t *conn,
    int64_t stream_id,
    int status_code,
    const h3_header_t *headers,
    size_t header_count,
    const uint8_t *body, size_t body_len
);

/*
 * Stream management
 */

/* Close a stream with error code */
int h3_close_stream(h3_connection_t *conn, int64_t stream_id, uint64_t error_code);

/* Get buffered body data size for a stream */
size_t h3_get_stream_buffer_size(h3_connection_t *conn, int64_t stream_id);

/*
 * Connection control
 */

/* Initiate graceful connection close */
int h3_connection_close(h3_connection_t *conn, uint64_t error_code, const char *reason);

/* Check if connection is closing/draining */
int h3_connection_is_closing(h3_connection_t *conn);

/* Check if handshake is complete */
int h3_connection_is_handshake_complete(h3_connection_t *conn);

/*
 * Logging
 */

/* Log levels */
#define H3_LOG_ERROR   0
#define H3_LOG_WARN    1
#define H3_LOG_INFO    2
#define H3_LOG_DEBUG   3
#define H3_LOG_TRACE   4

/* Set global log callback (for library-level logging) */
void h3_set_log_callback(h3_log_cb callback, void *user_data);

/* Set log level threshold */
void h3_set_log_level(int level);

/*
 * Utility functions
 */

/* Get current timestamp in nanoseconds */
uint64_t h3_timestamp_ns(void);

/* Convert error code to string */
const char *h3_strerror(int error_code);

#ifdef __cplusplus
}
#endif

#endif /* H3_API_H */
