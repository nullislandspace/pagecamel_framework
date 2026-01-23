/*
 * h3_api.c - Public API implementation
 *
 * This file implements the public API functions that wrap the internal
 * implementation details.
 */

#include "h3_api.h"
#include "h3_internal.h"
#include "h3_packet.h"
#include <string.h>
#include <stdio.h>

/* Global logging state */
h3_log_cb g_log_callback = NULL;
void *g_log_user_data = NULL;
int g_log_level = H3_LOG_WARN;

/* Version string */
static const char *H3_VERSION_STR = "1.0.0";

/* Forward declaration */
extern nghttp3_data_reader *h3_get_body_data_reader(void);

/*
 * Library initialization/cleanup
 */

int h3_init(void) {
    /* Initialize GnuTLS if needed */
    int rv = gnutls_global_init();
    if (rv != GNUTLS_E_SUCCESS) {
        fprintf(stderr, "h3_init: gnutls_global_init failed: %s\n",
                gnutls_strerror(rv));
        return H3_ERROR_TLS;
    }

    return H3_OK;
}

void h3_cleanup(void) {
    gnutls_global_deinit();
}

const char *h3_version(void) {
    return H3_VERSION_STR;
}

/*
 * Connection management functions are implemented in h3_connection.c:
 *   h3_connection_new_server()
 *   h3_connection_free()
 *   h3_connection_get_state()
 *   h3_connection_get_hostname()
 *   h3_connection_get_backend()
 *   h3_connection_close()
 *   h3_connection_is_closing()
 *   h3_connection_is_handshake_complete()
 */

/*
 * Packet processing
 */

int h3_process_packet(
    h3_connection_t *conn,
    const uint8_t *data, size_t len,
    const h3_addr_info_t *addr)
{
    return h3_packet_process(conn, data, len, addr);
}

int h3_flush_packets(h3_connection_t *conn) {
    setbuf(stderr, NULL);
    fprintf(stderr, "h3_flush_packets: ENTRY conn=%p\n", (void*)conn);
    return h3_packet_flush(conn);
}

uint64_t h3_get_timeout_ms(h3_connection_t *conn) {
    uint64_t expiry_ns = h3_packet_get_expiry_ns(conn);
    uint64_t now_ns = h3_timestamp_ns();

    if (expiry_ns <= now_ns) {
        return 0;
    }

    return (expiry_ns - now_ns) / 1000000ULL;  /* Convert ns to ms */
}

int h3_handle_timeout(h3_connection_t *conn) {
    return h3_packet_handle_expiry(conn);
}

/*
 * Response sending
 */

int h3_send_response_headers(
    h3_connection_t *conn,
    int64_t stream_id,
    int status_code,
    const h3_header_t *headers,
    size_t header_count,
    int has_body)
{
    if (!conn || !conn->http3) {
        return H3_ERROR_INVALID;
    }

    /* Build nghttp3 header array */
    size_t nva_count = header_count + 1;  /* +1 for :status */
    nghttp3_nv *nva = (nghttp3_nv *)malloc(nva_count * sizeof(nghttp3_nv));
    if (!nva) {
        return H3_ERROR_NOMEM;
    }

    /* Add :status pseudo-header */
    char status_str[16];
    snprintf(status_str, sizeof(status_str), "%d", status_code);
    nva[0].name = (uint8_t *)":status";
    nva[0].namelen = 7;
    nva[0].value = (uint8_t *)status_str;
    nva[0].valuelen = strlen(status_str);
    nva[0].flags = NGHTTP3_NV_FLAG_NONE;

    /* Add other headers */
    for (size_t i = 0; i < header_count; i++) {
        nva[i + 1].name = (uint8_t *)headers[i].name;
        nva[i + 1].namelen = headers[i].name_len;
        nva[i + 1].value = (uint8_t *)headers[i].value;
        nva[i + 1].valuelen = headers[i].value_len;
        nva[i + 1].flags = NGHTTP3_NV_FLAG_NONE;
    }

    /* Find or create stream for body buffer */
    h3_stream_t *stream = h3_stream_find(&conn->streams, stream_id);
    if (!stream) {
        stream = h3_stream_create(&conn->streams, stream_id);
    }
    if (stream) {
        stream->response_headers_sent = 1;
    }

    int rv;
    if (has_body) {
        /* Submit with data reader for body to follow */
        rv = nghttp3_conn_submit_response(
            conn->http3,
            stream_id,
            nva,
            nva_count,
            h3_get_body_data_reader()
        );
    } else {
        /* Submit without body (headers only) */
        rv = nghttp3_conn_submit_response(
            conn->http3,
            stream_id,
            nva,
            nva_count,
            NULL
        );
    }

    free(nva);

    if (rv != 0) {
        return H3_ERROR_HTTP3;
    }

    return H3_OK;
}

int h3_send_response_body(
    h3_connection_t *conn,
    int64_t stream_id,
    const uint8_t *data, size_t len,
    int eof)
{
    if (!conn) {
        return H3_ERROR_INVALID;
    }

    h3_stream_t *stream = h3_stream_find(&conn->streams, stream_id);
    if (!stream) {
        return H3_ERROR_STREAM;
    }

    /* Append data to buffer */
    if (len > 0) {
        if (h3_buffer_write(&stream->body_buffer, data, len) < 0) {
            return H3_ERROR_NOMEM;
        }
    }

    if (eof) {
        h3_buffer_set_eof(&stream->body_buffer);
        stream->response_eof = 1;
    }

    /* Resume stream to trigger read_data callback */
    if (conn->http3) {
        nghttp3_conn_resume_stream(conn->http3, stream_id);
    }

    return H3_OK;
}

int h3_send_response(
    h3_connection_t *conn,
    int64_t stream_id,
    int status_code,
    const h3_header_t *headers,
    size_t header_count,
    const uint8_t *body, size_t body_len)
{
    int rv;

    /* Send headers with body flag */
    rv = h3_send_response_headers(conn, stream_id, status_code,
                                  headers, header_count, body_len > 0 ? 1 : 0);
    if (rv != H3_OK) {
        return rv;
    }

    /* Send body if present */
    if (body_len > 0) {
        rv = h3_send_response_body(conn, stream_id, body, body_len, 1);
        if (rv != H3_OK) {
            return rv;
        }
    }

    return H3_OK;
}

/*
 * Stream management
 */

int h3_close_stream(h3_connection_t *conn, int64_t stream_id, uint64_t error_code) {
    if (!conn) {
        return H3_ERROR_INVALID;
    }

    if (conn->http3) {
        nghttp3_conn_close_stream(conn->http3, stream_id, error_code);
    }

    if (conn->quic) {
        ngtcp2_conn_shutdown_stream(conn->quic, 0, stream_id, error_code);
    }

    h3_stream_remove(&conn->streams, stream_id);

    return H3_OK;
}

size_t h3_get_stream_buffer_size(h3_connection_t *conn, int64_t stream_id) {
    if (!conn) {
        return 0;
    }

    h3_stream_t *stream = h3_stream_find(&conn->streams, stream_id);
    if (!stream) {
        return 0;
    }

    return h3_buffer_pending(&stream->body_buffer);
}

/*
 * Connection control functions are implemented in h3_connection.c:
 *   h3_connection_close()
 *   h3_connection_is_closing()
 *   h3_connection_is_handshake_complete()
 */

/*
 * Logging
 */

void h3_set_log_callback(h3_log_cb callback, void *user_data) {
    g_log_callback = callback;
    g_log_user_data = user_data;
}

void h3_set_log_level(int level) {
    g_log_level = level;
}

/*
 * Utility functions
 */

const char *h3_strerror(int error_code) {
    switch (error_code) {
        case H3_OK: return "Success";
        case H3_WOULDBLOCK: return "Would block";
        case H3_ERROR: return "General error";
        case H3_ERROR_NOMEM: return "Out of memory";
        case H3_ERROR_INVALID: return "Invalid argument";
        case H3_ERROR_TLS: return "TLS error";
        case H3_ERROR_QUIC: return "QUIC error";
        case H3_ERROR_HTTP3: return "HTTP/3 error";
        case H3_ERROR_STREAM: return "Stream error";
        case H3_ERROR_CLOSED: return "Connection closed";
        default: return "Unknown error";
    }
}
