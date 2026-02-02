/*
 * h3_callbacks.c - C-to-C callback wiring between ngtcp2 and nghttp3
 *
 * CRITICAL: This file implements the direct C-to-C communication between
 * ngtcp2 (QUIC) and nghttp3 (HTTP/3). NO Perl trampolines are used for
 * internal ngtcp2<->nghttp3 callbacks. Only the final application callbacks
 * (on_request, on_request_body, on_stream_close, send_packet) cross into Perl.
 *
 * This eliminates the data corruption issues caused by Perl/XS boundary
 * crossing during the read_data callback.
 */

#include "h3_internal.h"
#include "h3_buffer.h"
#include <gnutls/crypto.h>  /* For gnutls_rnd */
#include <string.h>
#include <stdio.h>
#include <time.h>

/* Debug flag */
#define H3_CALLBACKS_DEBUG 0

/*
 * ============================================================================
 * QUIC (ngtcp2) Callbacks
 * ============================================================================
 */

/* Random number generator */
static void quic_rand_callback(uint8_t *dest, size_t destlen,
                               const ngtcp2_rand_ctx *rand_ctx) {
    (void)rand_ctx;
    gnutls_rnd(GNUTLS_RND_RANDOM, dest, destlen);
}

/* Generate new connection ID */
static int quic_get_new_connection_id_callback(ngtcp2_conn *conn, ngtcp2_cid *cid,
                                               uint8_t *token, size_t cidlen,
                                               void *user_data) {
    (void)conn;
    (void)user_data;

    /* Generate random connection ID */
    gnutls_rnd(GNUTLS_RND_RANDOM, cid->data, cidlen);
    cid->datalen = cidlen;

    /* Generate random stateless reset token */
    gnutls_rnd(GNUTLS_RND_RANDOM, token, NGTCP2_STATELESS_RESET_TOKENLEN);

    return 0;
}

/*
 * recv_stream_data callback - Called when QUIC stream data arrives
 *
 * CRITICAL: This feeds data directly to nghttp3 in C, no Perl trampoline!
 */
static int quic_recv_stream_data_callback(ngtcp2_conn *conn, uint32_t flags,
                                          int64_t stream_id, uint64_t offset,
                                          const uint8_t *data, size_t datalen,
                                          void *user_data, void *stream_user_data) {
    (void)conn;
    (void)offset;
    (void)stream_user_data;

    h3_connection_t *h3c = (h3_connection_t *)user_data;
    int fin = (flags & NGTCP2_STREAM_DATA_FLAG_FIN) ? 1 : 0;
    nghttp3_ssize consumed;

    if (H3_CALLBACKS_DEBUG) {
        fprintf(stderr, "h3_callbacks: recv_stream_data stream=%lld offset=%llu len=%zu fin=%d\n",
                (long long)stream_id, (unsigned long long)offset, datalen, fin);
    }

    if (!h3c->http3) {
        /* HTTP/3 not initialized yet - this happens during early handshake */
        return 0;
    }

    /* Feed data directly to nghttp3 - NO Perl trampoline! */
    consumed = nghttp3_conn_read_stream(h3c->http3, stream_id, data, datalen, fin);

    if (consumed < 0) {
        if (H3_CALLBACKS_DEBUG) {
            fprintf(stderr, "h3_callbacks: nghttp3_conn_read_stream error: %s\n",
                    nghttp3_strerror((int)consumed));
        }
        return NGTCP2_ERR_CALLBACK_FAILURE;
    }

    /* Extend flow control window */
    ngtcp2_conn_extend_max_stream_offset(conn, stream_id, (size_t)consumed);
    ngtcp2_conn_extend_max_offset(conn, (size_t)consumed);

    return 0;
}

/*
 * stream_open callback - Called when a new stream is opened
 */
static int quic_stream_open_callback(ngtcp2_conn *conn, int64_t stream_id,
                                     void *user_data) {
    (void)conn;
    h3_connection_t *h3c = (h3_connection_t *)user_data;

    if (H3_CALLBACKS_DEBUG) {
        fprintf(stderr, "h3_callbacks: stream_open stream=%lld\n", (long long)stream_id);
    }

    /* Create stream entry */
    h3_stream_create(&h3c->streams, stream_id);

    return 0;
}

/*
 * stream_close callback - Called when a stream is closed
 *
 * Notifies Perl via on_stream_close callback.
 */
static int quic_stream_close_callback(ngtcp2_conn *conn, uint32_t flags,
                                      int64_t stream_id, uint64_t app_error_code,
                                      void *user_data, void *stream_user_data) {
    (void)conn;
    (void)flags;
    (void)stream_user_data;

    h3_connection_t *h3c = (h3_connection_t *)user_data;

    if (H3_CALLBACKS_DEBUG) {
        fprintf(stderr, "h3_callbacks: stream_close stream=%lld error=%llu\n",
                (long long)stream_id, (unsigned long long)app_error_code);
    }

    /* Notify nghttp3 */
    if (h3c->http3) {
        nghttp3_conn_close_stream(h3c->http3, stream_id, app_error_code);
    }

    /* Notify Perl callback */
    if (h3c->callbacks.on_stream_close) {
        h3c->callbacks.on_stream_close(
            h3c->callbacks.user_data,
            stream_id,
            app_error_code
        );
    }

    /* Clean up stream resources */
    h3_stream_remove(&h3c->streams, stream_id);

    return 0;
}

/*
 * acked_stream_data_offset callback - Called when stream data is acknowledged
 *
 * CRITICAL: This feeds ACK info directly to nghttp3 and our buffer tracking.
 * NO Perl trampoline! This ensures the buffer can track what's been ACKed.
 */
static int quic_acked_stream_data_offset_callback(ngtcp2_conn *conn,
                                                  int64_t stream_id,
                                                  uint64_t offset,
                                                  uint64_t datalen,
                                                  void *user_data,
                                                  void *stream_user_data) {
    (void)conn;
    (void)offset;
    (void)stream_user_data;

    h3_connection_t *h3c = (h3_connection_t *)user_data;

    if (H3_CALLBACKS_DEBUG) {
        fprintf(stderr, "h3_callbacks: acked_stream_data stream=%lld offset=%llu len=%llu\n",
                (long long)stream_id, (unsigned long long)offset, (unsigned long long)datalen);
    }

    /* Notify nghttp3 of acknowledged data */
    if (h3c->http3) {
        nghttp3_conn_add_ack_offset(h3c->http3, stream_id, (size_t)datalen);
    }

    /* NOTE: We don't free buffers here! The acked_stream_data callback from
     * nghttp3 will be called, which updates our h3_stream_buffer_t.
     * Buffer memory is freed later via h3_buffer_flush_acked() at a safe point.
     */

    return 0;
}

/*
 * handshake_completed callback
 */
static int quic_handshake_completed_callback(ngtcp2_conn *conn, void *user_data) {
    (void)conn;
    h3_connection_t *h3c = (h3_connection_t *)user_data;

    if (H3_CALLBACKS_DEBUG) {
        fprintf(stderr, "h3_callbacks: handshake_completed\n");
    }

    h3c->state = H3_STATE_ESTABLISHED;

    /* Capture SNI hostname */
    if (h3c->tls) {
        h3_tls_capture_sni(h3c->tls);
    }

    return 0;
}

/*
 * recv_client_initial wrapper - handles Initial packet processing
 */
static int quic_recv_client_initial_callback(ngtcp2_conn *conn,
                                             const ngtcp2_cid *dcid,
                                             void *user_data) {
    if (H3_CALLBACKS_DEBUG) {
        fprintf(stderr, "h3_callbacks: recv_client_initial dcid_len=%zu\n", dcid->datalen);
    }

    int rv = ngtcp2_crypto_recv_client_initial_cb(conn, dcid, user_data);
    if (H3_CALLBACKS_DEBUG) {
        fprintf(stderr, "h3_callbacks: recv_client_initial returned %d\n", rv);
    }
    return rv;
}

/*
 * recv_crypto_data wrapper - handles TLS crypto data
 */
static int quic_recv_crypto_data_callback(ngtcp2_conn *conn,
                                          ngtcp2_encryption_level crypto_level,
                                          uint64_t offset,
                                          const uint8_t *data, size_t datalen,
                                          void *user_data) {
    if (H3_CALLBACKS_DEBUG) {
        fprintf(stderr, "h3_callbacks: recv_crypto_data level=%d offset=%llu len=%zu\n",
                crypto_level, (unsigned long long)offset, datalen);
    }

    int rv = ngtcp2_crypto_recv_crypto_data_cb(conn, crypto_level, offset, data, datalen, user_data);
    if (H3_CALLBACKS_DEBUG) {
        fprintf(stderr, "h3_callbacks: recv_crypto_data returned %d\n", rv);
    }
    return rv;
}

/*
 * Setup QUIC callbacks
 */
void h3_setup_quic_callbacks(ngtcp2_callbacks *cb) {
    memset(cb, 0, sizeof(*cb));

    /* Random number generator */
    cb->rand = quic_rand_callback;

    /* Connection ID management */
    cb->get_new_connection_id = quic_get_new_connection_id_callback;

    /* Crypto callbacks from ngtcp2_crypto */
    cb->recv_client_initial = quic_recv_client_initial_callback;
    cb->recv_crypto_data = quic_recv_crypto_data_callback;
    cb->encrypt = ngtcp2_crypto_encrypt_cb;
    cb->decrypt = ngtcp2_crypto_decrypt_cb;
    cb->hp_mask = ngtcp2_crypto_hp_mask_cb;
    cb->update_key = ngtcp2_crypto_update_key_cb;
    cb->delete_crypto_aead_ctx = ngtcp2_crypto_delete_crypto_aead_ctx_cb;
    cb->delete_crypto_cipher_ctx = ngtcp2_crypto_delete_crypto_cipher_ctx_cb;
    cb->get_path_challenge_data = ngtcp2_crypto_get_path_challenge_data_cb;
    cb->version_negotiation = ngtcp2_crypto_version_negotiation_cb;

    /* Stream callbacks */
    cb->recv_stream_data = quic_recv_stream_data_callback;
    cb->stream_open = quic_stream_open_callback;
    cb->stream_close = quic_stream_close_callback;
    cb->acked_stream_data_offset = quic_acked_stream_data_offset_callback;
    cb->handshake_completed = quic_handshake_completed_callback;
}

/*
 * ============================================================================
 * HTTP/3 (nghttp3) Callbacks
 * ============================================================================
 */

/*
 * recv_header callback - Called for each header received
 */
static int http3_recv_header_callback(nghttp3_conn *conn, int64_t stream_id,
                                      int32_t token, nghttp3_rcbuf *name,
                                      nghttp3_rcbuf *value, uint8_t flags,
                                      void *user_data, void *stream_user_data) {
    (void)conn;
    (void)token;
    (void)flags;
    (void)stream_user_data;

    h3_connection_t *h3c = (h3_connection_t *)user_data;
    nghttp3_vec name_vec = nghttp3_rcbuf_get_buf(name);
    nghttp3_vec value_vec = nghttp3_rcbuf_get_buf(value);

    /* Find or create stream */
    h3_stream_t *stream = h3_stream_find(&h3c->streams, stream_id);
    if (!stream) {
        stream = h3_stream_create(&h3c->streams, stream_id);
        if (!stream) {
            return NGHTTP3_ERR_CALLBACK_FAILURE;
        }
    }

    /* Check for extended CONNECT */
    if (name_vec.len == 7 && memcmp(name_vec.base, ":method", 7) == 0 &&
        value_vec.len == 7 && memcmp(value_vec.base, "CONNECT", 7) == 0) {
        stream->is_connect = 1;
    }

    /* Store header */
    if (h3_stream_add_header(stream, name_vec.base, name_vec.len,
                             value_vec.base, value_vec.len) < 0) {
        return NGHTTP3_ERR_CALLBACK_FAILURE;
    }

    return 0;
}

/*
 * end_headers callback - Called when all headers have been received
 */
static int http3_end_headers_callback(nghttp3_conn *conn, int64_t stream_id,
                                      int fin, void *user_data,
                                      void *stream_user_data) {
    (void)conn;
    (void)stream_user_data;

    h3_connection_t *h3c = (h3_connection_t *)user_data;
    h3_stream_t *stream = h3_stream_find(&h3c->streams, stream_id);

    if (!stream) {
        return 0;
    }

    stream->headers_complete = 1;

    /* Always notify Perl when headers are complete so it can set up the
     * backend connection. For requests with a body (fin=0), body data
     * will follow via on_request_body callbacks. */
    if (h3c->callbacks.on_request) {
        h3c->callbacks.on_request(
            h3c->callbacks.user_data,
            stream_id,
            stream->headers,
            stream->header_count,
            stream->request_body,
            stream->request_body_len,
            stream->is_connect
        );
    }

    return 0;
}

/*
 * recv_data callback - Called when request body data arrives
 */
static int http3_recv_data_callback(nghttp3_conn *conn, int64_t stream_id,
                                    const uint8_t *data, size_t datalen,
                                    void *user_data, void *stream_user_data) {
    (void)conn;
    (void)stream_user_data;

    h3_connection_t *h3c = (h3_connection_t *)user_data;
    h3_stream_t *stream = h3_stream_find(&h3c->streams, stream_id);

    if (H3_CALLBACKS_DEBUG) {
        fprintf(stderr, "h3_callbacks: recv_data stream=%lld len=%zu\n",
                (long long)stream_id, datalen);
    }

    if (!stream) {
        return 0;
    }

    /* Append to request body buffer */
    h3_stream_append_request_body(stream, data, datalen);

    /* CRITICAL: Extend QUIC flow control for body data bytes.
     * nghttp3_conn_read_stream() return value only covers HTTP/3 framing
     * overhead, NOT body data. Body data flow control must be extended here. */
    ngtcp2_conn_extend_max_stream_offset(h3c->quic, stream_id, datalen);
    ngtcp2_conn_extend_max_offset(h3c->quic, datalen);

    /* Notify Perl of streaming body data */
    if (h3c->callbacks.on_request_body) {
        h3c->callbacks.on_request_body(
            h3c->callbacks.user_data,
            stream_id,
            data,
            datalen,
            0  /* not fin yet */
        );
    }

    return 0;
}

/*
 * end_stream callback - Called when request is complete
 */
static int http3_end_stream_callback(nghttp3_conn *conn, int64_t stream_id,
                                     void *user_data, void *stream_user_data) {
    (void)conn;
    (void)stream_user_data;

    h3_connection_t *h3c = (h3_connection_t *)user_data;
    h3_stream_t *stream = h3_stream_find(&h3c->streams, stream_id);

    if (H3_CALLBACKS_DEBUG) {
        fprintf(stderr, "h3_callbacks: end_stream stream=%lld\n", (long long)stream_id);
    }

    if (!stream) {
        return 0;
    }

    /* Notify that the request body is complete.
     * on_request was already called in end_headers for all requests. */
    if (h3c->callbacks.on_request_body) {
        h3c->callbacks.on_request_body(
            h3c->callbacks.user_data,
            stream_id,
            NULL,
            0,
            1  /* fin */
        );
    }

    return 0;
}

/*
 * acked_stream_data callback - Called when response body data is acknowledged
 *
 * This updates our buffer tracking. Memory is NOT freed here to avoid
 * use-after-free during writev_stream loops.
 */
static int http3_acked_stream_data_callback(nghttp3_conn *conn, int64_t stream_id,
                                            uint64_t datalen, void *user_data,
                                            void *stream_user_data) {
    (void)conn;
    (void)stream_user_data;

    h3_connection_t *h3c = (h3_connection_t *)user_data;
    h3_stream_t *stream = h3_stream_find(&h3c->streams, stream_id);

    if (H3_CALLBACKS_DEBUG) {
        fprintf(stderr, "h3_callbacks: acked_stream_data stream=%lld len=%llu\n",
                (long long)stream_id, (unsigned long long)datalen);
    }

    if (stream) {
        /* Update buffer tracking - don't free memory yet */
        h3_buffer_ack(&stream->body_buffer, (size_t)datalen);
    }

    return 0;
}

/*
 * deferred_consume callback - Called by nghttp3 when bytes are consumed later
 * due to stream synchronization. Must extend QUIC flow control for these bytes.
 */
static int http3_deferred_consume_callback(nghttp3_conn *conn, int64_t stream_id,
                                           size_t consumed, void *user_data,
                                           void *stream_user_data) {
    (void)conn;
    (void)stream_user_data;

    h3_connection_t *h3c = (h3_connection_t *)user_data;

    ngtcp2_conn_extend_max_stream_offset(h3c->quic, stream_id, consumed);
    ngtcp2_conn_extend_max_offset(h3c->quic, consumed);

    return 0;
}

/*
 * read_data callback - Called by nghttp3 when it needs response body data
 *
 * CRITICAL: Returns pointers directly into our chunk buffers.
 * These pointers MUST remain valid until acked_stream_data is called.
 * This is why we use fixed-size chunks that are never reallocated.
 */
static nghttp3_ssize http3_read_data_callback(nghttp3_conn *conn, int64_t stream_id,
                                              nghttp3_vec *vec, size_t veccnt,
                                              uint32_t *pflags, void *user_data,
                                              void *stream_user_data) {
    (void)conn;
    (void)stream_user_data;

    h3_connection_t *h3c = (h3_connection_t *)user_data;
    h3_stream_t *stream = h3_stream_find(&h3c->streams, stream_id);

    if (veccnt == 0) {
        return 0;
    }

    if (!stream) {
        return NGHTTP3_ERR_WOULDBLOCK;
    }

    h3_buffer_read_result_t result;
    int rv = h3_buffer_read(&stream->body_buffer, &result);

    if (rv <= 0) {
        /* No data available */
        if (stream->body_buffer.eof) {
            *pflags |= NGHTTP3_DATA_FLAG_EOF;
            if (H3_CALLBACKS_DEBUG) {
                fprintf(stderr, "h3_callbacks: read_data stream=%lld EOF (no data)\n",
                        (long long)stream_id);
            }
            return 0;
        }
        if (H3_CALLBACKS_DEBUG) {
            fprintf(stderr, "h3_callbacks: read_data stream=%lld WOULDBLOCK\n",
                    (long long)stream_id);
        }
        return NGHTTP3_ERR_WOULDBLOCK;
    }

    /* Return pointer into chunk buffer (ONE vector only for simplicity) */
    vec[0].base = result.base;
    vec[0].len = result.len;

    /* Consume the body data we're returning - this is the ONLY place consumption happens.
     * This ensures we only consume actual body data, not HTTP/3 framing. */
    h3_buffer_consume(&stream->body_buffer, result.len);

    if (result.eof) {
        *pflags |= NGHTTP3_DATA_FLAG_EOF;
    }

    if (H3_CALLBACKS_DEBUG && result.len >= 8) {
        fprintf(stderr, "h3_callbacks: read_data stream=%lld len=%zu first=%02x%02x%02x%02x eof=%d\n",
                (long long)stream_id, result.len,
                result.base[0], result.base[1], result.base[2], result.base[3],
                result.eof);
    }

    return 1;  /* Number of vectors filled */
}

/*
 * Setup HTTP/3 callbacks
 */
void h3_setup_http3_callbacks(nghttp3_callbacks *cb) {
    memset(cb, 0, sizeof(*cb));

    cb->recv_header = http3_recv_header_callback;
    cb->end_headers = http3_end_headers_callback;
    cb->recv_data = http3_recv_data_callback;
    cb->end_stream = http3_end_stream_callback;
    cb->acked_stream_data = http3_acked_stream_data_callback;
    cb->deferred_consume = http3_deferred_consume_callback;
}

/*
 * Data reader for nghttp3 response submission
 */
static nghttp3_data_reader g_body_data_reader = {
    http3_read_data_callback
};

nghttp3_data_reader *h3_get_body_data_reader(void) {
    return &g_body_data_reader;
}
