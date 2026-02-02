/*
 * h3_internal.h - Internal structures for PageCamel HTTP/3 library
 *
 * These structures are not exposed in the public API.
 */

#ifndef H3_INTERNAL_H
#define H3_INTERNAL_H

#include "h3_api.h"
#include "h3_buffer.h"
#include "h3_tls.h"

#include <ngtcp2/ngtcp2.h>
#include <ngtcp2/ngtcp2_crypto.h>
#include <ngtcp2/ngtcp2_crypto_gnutls.h>
#include <nghttp3/nghttp3.h>
#include <gnutls/gnutls.h>

#include <netinet/in.h>
#include <sys/socket.h>
#include <pthread.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Maximum UDP payload size */
#define H3_MAX_UDP_PAYLOAD 1350

/* Maximum headers per request */
#define H3_MAX_HEADERS 256

/* Stream type flags */
#define H3_STREAM_TYPE_BIDI    0
#define H3_STREAM_TYPE_UNI     1
#define H3_STREAM_TYPE_CONTROL 2
#define H3_STREAM_TYPE_QPACK   3

/* Per-stream state */
typedef struct h3_stream {
    int64_t stream_id;
    int type;  /* H3_STREAM_TYPE_* */

    /* Request parsing state */
    int headers_complete;
    int is_connect;  /* Extended CONNECT for WebSocket */

    /* Header storage (decoded from QPACK) */
    h3_header_t *headers;
    size_t header_count;
    size_t header_capacity;

    /* Request body buffer (for buffered requests) */
    uint8_t *request_body;
    size_t request_body_len;
    size_t request_body_capacity;

    /* Response body buffer (chunk-based, never reallocated) */
    h3_stream_buffer_t body_buffer;
    int response_headers_sent;
    int response_eof;

    /* Link to next stream in hash bucket */
    struct h3_stream *next;
} h3_stream_t;

/* Stream hash table for fast lookup */
#define H3_STREAM_HASH_SIZE 256

typedef struct {
    h3_stream_t *buckets[H3_STREAM_HASH_SIZE];
    size_t count;
} h3_stream_table_t;

/* Main connection structure */
struct h3_connection {
    /* QUIC connection */
    ngtcp2_conn *quic;

    /* HTTP/3 connection */
    nghttp3_conn *http3;

    /* TLS state */
    h3_tls_context_t *tls;

    /* Connection state */
    h3_connection_state_t state;

    /* QUIC path */
    ngtcp2_path path;
    struct sockaddr_storage local_addr;
    struct sockaddr_storage remote_addr;

    /* Control stream IDs */
    int64_t ctrl_stream_id;
    int64_t qpack_enc_stream_id;
    int64_t qpack_dec_stream_id;
    int control_streams_bound;

    /* Stream management */
    h3_stream_table_t streams;

    /* Callbacks to Perl */
    h3_callbacks_t callbacks;

    /* Packet buffer for outgoing data */
    uint8_t *pkt_buf;
    size_t pkt_buf_size;

    /* Connection reference for ngtcp2_crypto */
    ngtcp2_crypto_conn_ref conn_ref;

    /* Error state */
    int last_error;
    char error_reason[256];

    /* Debug flag */
    int debug;
};

/*
 * Stream management functions (h3_stream.c)
 */

/* Initialize stream table */
void h3_stream_table_init(h3_stream_table_t *table);

/* Clean up stream table */
void h3_stream_table_cleanup(h3_stream_table_t *table);

/* Find or create stream */
h3_stream_t *h3_stream_find(h3_stream_table_t *table, int64_t stream_id);
h3_stream_t *h3_stream_create(h3_stream_table_t *table, int64_t stream_id);

/* Remove stream */
void h3_stream_remove(h3_stream_table_t *table, int64_t stream_id);

/* Free stream resources */
void h3_stream_free(h3_stream_t *stream);

/* Add header to stream */
int h3_stream_add_header(h3_stream_t *stream,
                         const uint8_t *name, size_t name_len,
                         const uint8_t *value, size_t value_len);

/* Append to request body */
int h3_stream_append_request_body(h3_stream_t *stream,
                                  const uint8_t *data, size_t len);

/*
 * Internal callback wiring (h3_callbacks.c)
 */

/* Set up ngtcp2 callbacks */
void h3_setup_quic_callbacks(ngtcp2_callbacks *cb);

/* Set up nghttp3 callbacks */
void h3_setup_http3_callbacks(nghttp3_callbacks *cb);

/*
 * Logging helpers
 */

/* Global log state */
extern h3_log_cb g_log_callback;
extern void *g_log_user_data;
extern int g_log_level;

/* Internal logging macro */
#define H3_LOG(level, conn, fmt, ...) \
    do { \
        if (g_log_level >= (level) && g_log_callback) { \
            char _msg[1024]; \
            snprintf(_msg, sizeof(_msg), fmt, ##__VA_ARGS__); \
            g_log_callback(g_log_user_data, (level), _msg); \
        } \
    } while (0)

/* Convenience logging macros (use different names to avoid conflict with level constants) */
#define H3_ERR(conn, fmt, ...) H3_LOG(H3_LOG_ERROR, conn, fmt, ##__VA_ARGS__)
#define H3_WARN(conn, fmt, ...) H3_LOG(H3_LOG_WARN, conn, fmt, ##__VA_ARGS__)
#define H3_INFO(conn, fmt, ...) H3_LOG(H3_LOG_INFO, conn, fmt, ##__VA_ARGS__)
#define H3_DBG(conn, fmt, ...) H3_LOG(H3_LOG_DEBUG, conn, fmt, ##__VA_ARGS__)
#define H3_TRC(conn, fmt, ...) H3_LOG(H3_LOG_TRACE, conn, fmt, ##__VA_ARGS__)

#ifdef __cplusplus
}
#endif

#endif /* H3_INTERNAL_H */
