/*
 * h3_connection.c - Connection lifecycle management
 *
 * Handles creation and destruction of unified ngtcp2 + nghttp3 + TLS connections.
 */

#include "h3_internal.h"
#include "h3_packet.h"
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <arpa/inet.h>

/* Debug flag */
#define H3_CONN_DEBUG 0

/* Forward declaration */
extern nghttp3_data_reader *h3_get_body_data_reader(void);

/*
 * Stream table implementation
 */

static inline unsigned int stream_hash(int64_t stream_id) {
    return (unsigned int)(stream_id % H3_STREAM_HASH_SIZE);
}

void h3_stream_table_init(h3_stream_table_t *table) {
    memset(table->buckets, 0, sizeof(table->buckets));
    table->count = 0;
}

void h3_stream_table_cleanup(h3_stream_table_t *table) {
    for (int i = 0; i < H3_STREAM_HASH_SIZE; i++) {
        h3_stream_t *stream = table->buckets[i];
        while (stream) {
            h3_stream_t *next = stream->next;
            h3_stream_free(stream);
            stream = next;
        }
        table->buckets[i] = NULL;
    }
    table->count = 0;
}

h3_stream_t *h3_stream_find(h3_stream_table_t *table, int64_t stream_id) {
    unsigned int bucket = stream_hash(stream_id);
    h3_stream_t *stream = table->buckets[bucket];

    while (stream) {
        if (stream->stream_id == stream_id) {
            return stream;
        }
        stream = stream->next;
    }

    return NULL;
}

h3_stream_t *h3_stream_create(h3_stream_table_t *table, int64_t stream_id) {
    /* Check if already exists */
    h3_stream_t *existing = h3_stream_find(table, stream_id);
    if (existing) {
        return existing;
    }

    h3_stream_t *stream = (h3_stream_t *)calloc(1, sizeof(h3_stream_t));
    if (!stream) {
        return NULL;
    }

    stream->stream_id = stream_id;
    h3_buffer_init(&stream->body_buffer);

    /* Insert into hash table */
    unsigned int bucket = stream_hash(stream_id);
    stream->next = table->buckets[bucket];
    table->buckets[bucket] = stream;
    table->count++;

    return stream;
}

void h3_stream_remove(h3_stream_table_t *table, int64_t stream_id) {
    unsigned int bucket = stream_hash(stream_id);
    h3_stream_t **pp = &table->buckets[bucket];

    while (*pp) {
        if ((*pp)->stream_id == stream_id) {
            h3_stream_t *stream = *pp;
            *pp = stream->next;
            h3_stream_free(stream);
            table->count--;
            return;
        }
        pp = &(*pp)->next;
    }
}

void h3_stream_free(h3_stream_t *stream) {
    if (!stream) return;

    /* Free headers */
    if (stream->headers) {
        for (size_t i = 0; i < stream->header_count; i++) {
            free((void *)stream->headers[i].name);
            free((void *)stream->headers[i].value);
        }
        free(stream->headers);
    }

    /* Free request body */
    free(stream->request_body);

    /* Free response body buffer */
    h3_buffer_cleanup(&stream->body_buffer);

    free(stream);
}

int h3_stream_add_header(h3_stream_t *stream,
                         const uint8_t *name, size_t name_len,
                         const uint8_t *value, size_t value_len) {
    /* Grow header array if needed */
    if (stream->header_count >= stream->header_capacity) {
        size_t new_capacity = stream->header_capacity == 0 ? 16 : stream->header_capacity * 2;
        if (new_capacity > H3_MAX_HEADERS) {
            new_capacity = H3_MAX_HEADERS;
        }
        if (stream->header_count >= new_capacity) {
            return -1;  /* Too many headers */
        }

        h3_header_t *new_headers = (h3_header_t *)realloc(stream->headers,
                                                          new_capacity * sizeof(h3_header_t));
        if (!new_headers) {
            return -1;
        }
        stream->headers = new_headers;
        stream->header_capacity = new_capacity;
    }

    /* Copy header name and value */
    uint8_t *name_copy = (uint8_t *)malloc(name_len + 1);
    uint8_t *value_copy = (uint8_t *)malloc(value_len + 1);
    if (!name_copy || !value_copy) {
        free(name_copy);
        free(value_copy);
        return -1;
    }

    memcpy(name_copy, name, name_len);
    name_copy[name_len] = '\0';
    memcpy(value_copy, value, value_len);
    value_copy[value_len] = '\0';

    stream->headers[stream->header_count].name = name_copy;
    stream->headers[stream->header_count].name_len = name_len;
    stream->headers[stream->header_count].value = value_copy;
    stream->headers[stream->header_count].value_len = value_len;
    stream->header_count++;

    return 0;
}

int h3_stream_append_request_body(h3_stream_t *stream,
                                  const uint8_t *data, size_t len) {
    if (len == 0) return 0;

    size_t new_len = stream->request_body_len + len;
    if (new_len > stream->request_body_capacity) {
        size_t new_capacity = stream->request_body_capacity == 0 ? 4096 : stream->request_body_capacity * 2;
        while (new_capacity < new_len) {
            new_capacity *= 2;
        }

        uint8_t *new_body = (uint8_t *)realloc(stream->request_body, new_capacity);
        if (!new_body) {
            return -1;
        }
        stream->request_body = new_body;
        stream->request_body_capacity = new_capacity;
    }

    memcpy(stream->request_body + stream->request_body_len, data, len);
    stream->request_body_len = new_len;

    return 0;
}

/*
 * Connection creation
 */

h3_connection_t *h3_connection_new_server(
    const h3_server_config_t *config,
    const h3_callbacks_t *callbacks,
    const uint8_t *dcid, size_t dcid_len,
    const uint8_t *scid, size_t scid_len,
    const uint8_t *original_dcid, size_t original_dcid_len,
    const h3_addr_info_t *addr,
    uint32_t quic_version)
{
    h3_connection_t *conn = NULL;
    ngtcp2_callbacks quic_callbacks;
    ngtcp2_settings settings;
    ngtcp2_transport_params params;
    ngtcp2_cid scid_obj, dcid_obj, original_dcid_obj;
    int rv;

    if (H3_CONN_DEBUG) {
        fprintf(stderr, "h3_connection_new_server: creating connection\n");
    }

    /* Allocate connection */
    conn = (h3_connection_t *)calloc(1, sizeof(h3_connection_t));
    if (!conn) {
        return NULL;
    }

    conn->state = H3_STATE_INITIAL;
    conn->ctrl_stream_id = -1;
    conn->qpack_enc_stream_id = -1;
    conn->qpack_dec_stream_id = -1;

    /* Copy callbacks */
    if (callbacks) {
        conn->callbacks = *callbacks;
    }

    /* Initialize stream table */
    h3_stream_table_init(&conn->streams);

    /* Allocate packet buffer */
    conn->pkt_buf_size = H3_MAX_UDP_PAYLOAD;
    conn->pkt_buf = (uint8_t *)malloc(conn->pkt_buf_size);
    if (!conn->pkt_buf) {
        h3_connection_free(conn);
        return NULL;
    }

    /* Create TLS context */
    h3_tls_domain_config_t *tls_domains = NULL;
    if (config->domain_count > 0) {
        tls_domains = (h3_tls_domain_config_t *)calloc(config->domain_count,
                                                        sizeof(h3_tls_domain_config_t));
        if (!tls_domains) {
            h3_connection_free(conn);
            return NULL;
        }

        for (size_t i = 0; i < config->domain_count; i++) {
            tls_domains[i].domain = config->domains[i].domain;
            tls_domains[i].cert_path = config->domains[i].cert_path;
            tls_domains[i].key_path = config->domains[i].key_path;
            tls_domains[i].backend_socket = config->domains[i].backend_socket;
        }
    }

    conn->tls = h3_tls_context_new_server(
        tls_domains,
        config->domain_count,
        config->default_domain,
        config->default_backend
    );

    free(tls_domains);

    if (!conn->tls) {
        fprintf(stderr, "h3_connection_new_server: TLS context creation failed\n");
        h3_connection_free(conn);
        return NULL;
    }

    /* Set up QUIC path */
    h3_addr_to_sockaddr(addr,
                        (struct sockaddr_storage *)&conn->local_addr,
                        (struct sockaddr_storage *)&conn->remote_addr);

    conn->path.local.addr = (struct sockaddr *)&conn->local_addr;
    conn->path.local.addrlen = conn->local_addr.ss_family == AF_INET6 ?
                               sizeof(struct sockaddr_in6) : sizeof(struct sockaddr_in);
    conn->path.remote.addr = (struct sockaddr *)&conn->remote_addr;
    conn->path.remote.addrlen = conn->remote_addr.ss_family == AF_INET6 ?
                                sizeof(struct sockaddr_in6) : sizeof(struct sockaddr_in);

    /* Initialize connection IDs */
    ngtcp2_cid_init(&dcid_obj, dcid, dcid_len);
    ngtcp2_cid_init(&scid_obj, scid, scid_len);
    ngtcp2_cid_init(&original_dcid_obj, original_dcid, original_dcid_len);

    /* Set up QUIC callbacks (C-to-C wiring) */
    h3_setup_quic_callbacks(&quic_callbacks);

    /* Initialize settings */
    ngtcp2_settings_default(&settings);
    settings.initial_ts = h3_timestamp_ns();
    settings.max_tx_udp_payload_size = H3_MAX_UDP_PAYLOAD;
    settings.cc_algo = config->cc_algo >= 0 && config->cc_algo <= 3 ?
                       (ngtcp2_cc_algo)config->cc_algo : NGTCP2_CC_ALGO_CUBIC;

    if (config->enable_debug) {
        conn->debug = 1;
    }

    /* Initialize transport parameters */
    ngtcp2_transport_params_default(&params);
    params.initial_max_data = config->initial_max_data > 0 ?
                              config->initial_max_data : 10 * 1024 * 1024;
    params.initial_max_stream_data_bidi_local = config->initial_max_stream_data_bidi > 0 ?
                                                config->initial_max_stream_data_bidi : 1024 * 1024;
    params.initial_max_stream_data_bidi_remote = params.initial_max_stream_data_bidi_local;
    params.initial_max_stream_data_uni = config->initial_max_stream_data_uni > 0 ?
                                         config->initial_max_stream_data_uni : 1024 * 1024;
    params.initial_max_streams_bidi = config->initial_max_streams_bidi > 0 ?
                                      config->initial_max_streams_bidi : 100;
    params.initial_max_streams_uni = config->initial_max_streams_uni > 0 ?
                                     config->initial_max_streams_uni : 100;
    params.max_idle_timeout = config->max_idle_timeout_ms > 0 ?
                              config->max_idle_timeout_ms * NGTCP2_MILLISECONDS : 30 * NGTCP2_SECONDS;
    params.max_udp_payload_size = H3_MAX_UDP_PAYLOAD;
    params.active_connection_id_limit = NGTCP2_DEFAULT_ACTIVE_CONNECTION_ID_LIMIT;

    /* Server MUST set original_dcid to client's original DCID from Initial packet */
    memcpy(&params.original_dcid, &original_dcid_obj, sizeof(ngtcp2_cid));
    params.original_dcid_present = 1;
    memcpy(&params.initial_scid, &scid_obj, sizeof(ngtcp2_cid));

    if (H3_CONN_DEBUG) {
        fprintf(stderr, "h3_connection_new_server: dcid_len=%zu, scid_len=%zu, original_dcid_len=%zu\n",
                dcid_len, scid_len, original_dcid_len);
    }

    /* Create QUIC connection */
    rv = ngtcp2_conn_server_new(
        &conn->quic,
        &dcid_obj,
        &scid_obj,
        &conn->path,
        quic_version,
        &quic_callbacks,
        &settings,
        &params,
        NULL,  /* mem */
        conn   /* user_data */
    );

    if (rv != 0) {
        fprintf(stderr, "h3_connection_new_server: ngtcp2_conn_server_new failed: %s\n",
                ngtcp2_strerror(rv));
        h3_connection_free(conn);
        return NULL;
    }

    /* Link TLS to QUIC */
    if (h3_tls_link_connection(conn->tls, conn) < 0) {
        fprintf(stderr, "h3_connection_new_server: TLS link failed\n");
        h3_connection_free(conn);
        return NULL;
    }

    /* Create HTTP/3 connection */
    nghttp3_callbacks http3_callbacks;
    nghttp3_settings http3_settings;

    h3_setup_http3_callbacks(&http3_callbacks);
    nghttp3_settings_default(&http3_settings);
    http3_settings.enable_connect_protocol = 1;  /* RFC 9220: WebSocket over HTTP/3 */

    rv = nghttp3_conn_server_new(
        &conn->http3,
        &http3_callbacks,
        &http3_settings,
        NULL,  /* mem */
        conn   /* user_data */
    );

    if (rv != 0) {
        fprintf(stderr, "h3_connection_new_server: nghttp3_conn_server_new failed: %s\n",
                nghttp3_strerror(rv));
        h3_connection_free(conn);
        return NULL;
    }

    conn->state = H3_STATE_HANDSHAKING;

    if (H3_CONN_DEBUG) {
        fprintf(stderr, "h3_connection_new_server: connection created successfully\n");
    }

    return conn;
}

void h3_connection_free(h3_connection_t *conn) {
    if (!conn) return;

    if (H3_CONN_DEBUG) {
        fprintf(stderr, "h3_connection_free: destroying connection\n");
    }

    /* Clean up streams */
    h3_stream_table_cleanup(&conn->streams);

    /* Clean up HTTP/3 */
    if (conn->http3) {
        nghttp3_conn_del(conn->http3);
    }

    /* Clean up QUIC */
    if (conn->quic) {
        ngtcp2_conn_del(conn->quic);
    }

    /* Clean up TLS */
    if (conn->tls) {
        h3_tls_context_free(conn->tls);
    }

    /* Free buffers */
    free(conn->pkt_buf);

    free(conn);
}

h3_connection_state_t h3_connection_get_state(h3_connection_t *conn) {
    if (!conn) return H3_STATE_CLOSED;
    return conn->state;
}

const char *h3_connection_get_hostname(h3_connection_t *conn) {
    if (!conn || !conn->tls) return NULL;
    return h3_tls_get_hostname(conn->tls);
}

const char *h3_connection_get_backend(h3_connection_t *conn) {
    if (!conn || !conn->tls) return NULL;
    return h3_tls_get_backend(conn->tls);
}

int h3_connection_close(h3_connection_t *conn, uint64_t error_code, const char *reason) {
    if (!conn || !conn->quic) return H3_ERROR_INVALID;

    /* TODO: Implement graceful connection close */
    conn->state = H3_STATE_DRAINING;

    return H3_OK;
}

int h3_connection_is_closing(h3_connection_t *conn) {
    if (!conn) return 1;
    return conn->state == H3_STATE_DRAINING || conn->state == H3_STATE_CLOSED;
}

int h3_connection_is_handshake_complete(h3_connection_t *conn) {
    if (!conn || !conn->quic) return 0;
    return ngtcp2_conn_get_handshake_completed(conn->quic);
}
