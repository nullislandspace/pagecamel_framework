/*
 * h3_packet.c - Packet processing for HTTP/3
 *
 * Handles incoming/outgoing QUIC packets and timeout management.
 */

#define _POSIX_C_SOURCE 199309L  /* For clock_gettime and CLOCK_MONOTONIC */
#include "h3_packet.h"
#include "h3_internal.h"
#include <string.h>
#include <stdio.h>
#include <time.h>
#include <arpa/inet.h>

/* Debug flag */
#define H3_PACKET_DEBUG 0

/*
 * Timestamp utility
 */

uint64_t h3_timestamp_ns(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (uint64_t)ts.tv_sec * 1000000000ULL + (uint64_t)ts.tv_nsec;
}

/*
 * Address conversion utilities
 */

int h3_addr_to_sockaddr(
    const h3_addr_info_t *addr,
    struct sockaddr_storage *local,
    struct sockaddr_storage *remote)
{
    memset(local, 0, sizeof(*local));
    memset(remote, 0, sizeof(*remote));

    /* Detect address family by checking for ':' in the address string */
    int is_local_ipv6 = addr->local_addr && strchr(addr->local_addr, ':') != NULL;
    int is_remote_ipv6 = addr->remote_addr && strchr(addr->remote_addr, ':') != NULL;

    /* Initialize local address */
    if (is_local_ipv6) {
        struct sockaddr_in6 *local_in6 = (struct sockaddr_in6 *)local;
        local_in6->sin6_family = AF_INET6;
        local_in6->sin6_port = htons(addr->local_port);
        if (inet_pton(AF_INET6, addr->local_addr, &local_in6->sin6_addr) != 1) {
            return 0;
        }
    } else {
        struct sockaddr_in *local_in = (struct sockaddr_in *)local;
        local_in->sin_family = AF_INET;
        local_in->sin_port = htons(addr->local_port);
        if (inet_pton(AF_INET, addr->local_addr, &local_in->sin_addr) != 1) {
            return 0;
        }
    }

    /* Initialize remote address */
    if (is_remote_ipv6) {
        struct sockaddr_in6 *remote_in6 = (struct sockaddr_in6 *)remote;
        remote_in6->sin6_family = AF_INET6;
        remote_in6->sin6_port = htons(addr->remote_port);
        if (inet_pton(AF_INET6, addr->remote_addr, &remote_in6->sin6_addr) != 1) {
            return 0;
        }
        return sizeof(struct sockaddr_in6);
    } else {
        struct sockaddr_in *remote_in = (struct sockaddr_in *)remote;
        remote_in->sin_family = AF_INET;
        remote_in->sin_port = htons(addr->remote_port);
        if (inet_pton(AF_INET, addr->remote_addr, &remote_in->sin_addr) != 1) {
            return 0;
        }
        return sizeof(struct sockaddr_in);
    }
}

void h3_sockaddr_to_addr(
    const struct sockaddr_storage *local,
    const struct sockaddr_storage *remote,
    h3_addr_info_t *addr)
{
    static char local_buf[INET6_ADDRSTRLEN];
    static char remote_buf[INET6_ADDRSTRLEN];

    if (local->ss_family == AF_INET6) {
        const struct sockaddr_in6 *local_in6 = (const struct sockaddr_in6 *)local;
        inet_ntop(AF_INET6, &local_in6->sin6_addr, local_buf, sizeof(local_buf));
        addr->local_addr = local_buf;
        addr->local_port = ntohs(local_in6->sin6_port);
    } else {
        const struct sockaddr_in *local_in = (const struct sockaddr_in *)local;
        inet_ntop(AF_INET, &local_in->sin_addr, local_buf, sizeof(local_buf));
        addr->local_addr = local_buf;
        addr->local_port = ntohs(local_in->sin_port);
    }

    if (remote->ss_family == AF_INET6) {
        const struct sockaddr_in6 *remote_in6 = (const struct sockaddr_in6 *)remote;
        inet_ntop(AF_INET6, &remote_in6->sin6_addr, remote_buf, sizeof(remote_buf));
        addr->remote_addr = remote_buf;
        addr->remote_port = ntohs(remote_in6->sin6_port);
    } else {
        const struct sockaddr_in *remote_in = (const struct sockaddr_in *)remote;
        inet_ntop(AF_INET, &remote_in->sin_addr, remote_buf, sizeof(remote_buf));
        addr->remote_addr = remote_buf;
        addr->remote_port = ntohs(remote_in->sin_port);
    }
}

/*
 * Bind control streams (called after handshake)
 */

static int bind_control_streams(h3_connection_t *conn) {
    int rv;
    int64_t stream_id;

    if (conn->control_streams_bound) {
        return H3_OK;
    }

    /* Open control stream */
    rv = ngtcp2_conn_open_uni_stream(conn->quic, &stream_id, NULL);
    if (rv != 0) {
        if (H3_PACKET_DEBUG) {
            fprintf(stderr, "h3_packet: Failed to open control stream: %s\n",
                    ngtcp2_strerror(rv));
        }
        return H3_ERROR_QUIC;
    }
    conn->ctrl_stream_id = stream_id;

    rv = nghttp3_conn_bind_control_stream(conn->http3, stream_id);
    if (rv != 0) {
        if (H3_PACKET_DEBUG) {
            fprintf(stderr, "h3_packet: Failed to bind control stream: %s\n",
                    nghttp3_strerror(rv));
        }
        return H3_ERROR_HTTP3;
    }

    /* Open QPACK encoder stream */
    rv = ngtcp2_conn_open_uni_stream(conn->quic, &stream_id, NULL);
    if (rv != 0) {
        return H3_ERROR_QUIC;
    }
    conn->qpack_enc_stream_id = stream_id;

    /* Open QPACK decoder stream */
    rv = ngtcp2_conn_open_uni_stream(conn->quic, &stream_id, NULL);
    if (rv != 0) {
        return H3_ERROR_QUIC;
    }
    conn->qpack_dec_stream_id = stream_id;

    /* Bind QPACK streams */
    rv = nghttp3_conn_bind_qpack_streams(conn->http3,
                                         conn->qpack_enc_stream_id,
                                         conn->qpack_dec_stream_id);
    if (rv != 0) {
        if (H3_PACKET_DEBUG) {
            fprintf(stderr, "h3_packet: Failed to bind QPACK streams: %s\n",
                    nghttp3_strerror(rv));
        }
        return H3_ERROR_HTTP3;
    }

    conn->control_streams_bound = 1;

    if (H3_PACKET_DEBUG) {
        fprintf(stderr, "h3_packet: Control streams bound: ctrl=%lld qenc=%lld qdec=%lld\n",
                (long long)conn->ctrl_stream_id,
                (long long)conn->qpack_enc_stream_id,
                (long long)conn->qpack_dec_stream_id);
    }

    return H3_OK;
}

/*
 * Process incoming packet
 */

int h3_packet_process(
    h3_connection_t *conn,
    const uint8_t *data, size_t len,
    const h3_addr_info_t *addr)
{
    ngtcp2_pkt_info pi;
    int rv;

    if (!conn || !conn->quic) {
        return H3_ERROR_INVALID;
    }

    memset(&pi, 0, sizeof(pi));

    /* Update path if address changed */
    if (addr) {
        h3_addr_to_sockaddr(addr,
                            (struct sockaddr_storage *)&conn->local_addr,
                            (struct sockaddr_storage *)&conn->remote_addr);

        /* Update path addrlen to match the new address families */
        conn->path.local.addrlen = conn->local_addr.ss_family == AF_INET6 ?
                                   sizeof(struct sockaddr_in6) : sizeof(struct sockaddr_in);
        conn->path.remote.addrlen = conn->remote_addr.ss_family == AF_INET6 ?
                                    sizeof(struct sockaddr_in6) : sizeof(struct sockaddr_in);
    }

    /* Feed packet to QUIC */
    rv = ngtcp2_conn_read_pkt(
        conn->quic,
        &conn->path,
        &pi,
        data,
        len,
        h3_timestamp_ns()
    );

    if (rv != 0) {
        if (rv == NGTCP2_ERR_DRAINING) {
            conn->state = H3_STATE_DRAINING;
            return H3_ERROR_CLOSED;
        }
        if (rv == NGTCP2_ERR_DISCARD_PKT) {
            /* Ignore malformed packets */
            return H3_OK;
        }
        conn->last_error = rv;
        return H3_ERROR_QUIC;
    }

    /* Bind control streams after handshake completes */
    if (ngtcp2_conn_get_handshake_completed(conn->quic) && !conn->control_streams_bound) {
        rv = bind_control_streams(conn);
        if (rv != H3_OK) {
            return rv;
        }
    }

    return H3_OK;
}

/*
 * Flush outgoing packets
 */

int h3_packet_flush(h3_connection_t *conn) {
    uint8_t buf[H3_MAX_UDP_PAYLOAD];
    ngtcp2_path_storage ps;
    ngtcp2_pkt_info pi;
    ngtcp2_ssize nwrite;
    int packet_count = 0;
    uint64_t ts = h3_timestamp_ns();
    nghttp3_vec vec[16];
    nghttp3_ssize sveccnt;
    int64_t stream_id;
    int fin;

    if (!conn || !conn->quic) {
        return H3_ERROR_INVALID;
    }

    /* First, write any QUIC handshake/control packets */
    for (;;) {
        ngtcp2_path_storage_zero(&ps);

        nwrite = ngtcp2_conn_write_pkt(
            conn->quic,
            &ps.path,
            &pi,
            buf,
            sizeof(buf),
            ts
        );

        if (nwrite < 0) {
            if (nwrite == NGTCP2_ERR_WRITE_MORE) {
                continue;
            }
            if (H3_PACKET_DEBUG) {
                fprintf(stderr, "h3_packet_flush: write_pkt error: %s\n",
                        ngtcp2_strerror((int)nwrite));
            }
            break;
        }

        if (nwrite == 0) {
            break;
        }

        /* Send packet via callback */
        if (conn->callbacks.send_packet) {
            h3_addr_info_t addr;
            h3_sockaddr_to_addr(
                (struct sockaddr_storage *)ps.path.local.addr,
                (struct sockaddr_storage *)ps.path.remote.addr,
                &addr
            );
            int send_rv = conn->callbacks.send_packet(
                conn->callbacks.user_data,
                buf,
                (size_t)nwrite,
                &addr
            );

            if (send_rv == -1) {
                /* Would block - stop sending, return what we have */
                return H3_WOULDBLOCK;
            } else if (send_rv < -1) {
                /* Send error */
                return H3_ERROR;
            }
            /* send_rv >= 0 means success (bytes sent) */
        }

        packet_count++;

        if (packet_count >= 100) {
            break;  /* Safety limit */
        }
    }

    /* Now write HTTP/3 stream data */
    if (conn->http3 && conn->control_streams_bound) {
        for (;;) {
            stream_id = -1;
            fin = 0;

            sveccnt = nghttp3_conn_writev_stream(
                conn->http3,
                &stream_id,
                &fin,
                vec,
                16
            );

            if (sveccnt < 0) {
                if (H3_PACKET_DEBUG) {
                    fprintf(stderr, "h3_packet: writev_stream error: %s\n",
                            nghttp3_strerror((int)sveccnt));
                }
                break;
            }

            if (sveccnt == 0) {
                break;
            }

            /* Write stream data to QUIC */
            ngtcp2_path_storage_zero(&ps);

            uint32_t flags = NGTCP2_WRITE_STREAM_FLAG_MORE;
            if (fin) {
                flags |= NGTCP2_WRITE_STREAM_FLAG_FIN;
            }

            ngtcp2_ssize ndatalen = 0;
            nwrite = ngtcp2_conn_writev_stream(
                conn->quic,
                &ps.path,
                &pi,
                buf,
                sizeof(buf),
                &ndatalen,
                flags,
                stream_id,
                (const ngtcp2_vec *)vec,
                (size_t)sveccnt,
                ts
            );

            if (nwrite < 0) {
                if (nwrite == NGTCP2_ERR_WRITE_MORE) {
                    /* Tell nghttp3 how much was consumed */
                    if (ndatalen > 0) {
                        nghttp3_conn_add_write_offset(conn->http3, stream_id, (size_t)ndatalen);
                        /* NOTE: Buffer consumption now happens in read_data callback */
                    }
                    continue;
                }
                if (H3_PACKET_DEBUG) {
                    fprintf(stderr, "h3_packet: writev_stream QUIC error: %s\n",
                            ngtcp2_strerror((int)nwrite));
                }
                break;
            }

            if (nwrite == 0) {
                break;
            }

            /* Tell nghttp3 how much was consumed */
            if (ndatalen >= 0) {
                nghttp3_conn_add_write_offset(conn->http3, stream_id, (size_t)ndatalen);
                /* NOTE: Buffer consumption now happens in read_data callback */
            }

            /* Send packet via callback */
            if (conn->callbacks.send_packet) {
                h3_addr_info_t addr;
                h3_sockaddr_to_addr(
                    (struct sockaddr_storage *)ps.path.local.addr,
                    (struct sockaddr_storage *)ps.path.remote.addr,
                    &addr
                );
                conn->callbacks.send_packet(
                    conn->callbacks.user_data,
                    buf,
                    (size_t)nwrite,
                    &addr
                );
            }

            packet_count++;

            if (packet_count >= 100) {
                break;
            }
        }
    }

    /* Flush any remaining QUIC packets */
    for (;;) {
        ngtcp2_path_storage_zero(&ps);

        nwrite = ngtcp2_conn_write_pkt(
            conn->quic,
            &ps.path,
            &pi,
            buf,
            sizeof(buf),
            ts
        );

        if (nwrite <= 0) {
            break;
        }

        if (conn->callbacks.send_packet) {
            h3_addr_info_t addr;
            h3_sockaddr_to_addr(
                (struct sockaddr_storage *)ps.path.local.addr,
                (struct sockaddr_storage *)ps.path.remote.addr,
                &addr
            );
            conn->callbacks.send_packet(
                conn->callbacks.user_data,
                buf,
                (size_t)nwrite,
                &addr
            );
        }

        packet_count++;

        if (packet_count >= 100) {
            break;
        }
    }

    /* Flush acknowledged buffer chunks at a safe point */
    h3_stream_t *bucket;
    for (int i = 0; i < H3_STREAM_HASH_SIZE; i++) {
        bucket = conn->streams.buckets[i];
        while (bucket) {
            h3_buffer_flush_acked(&bucket->body_buffer);
            bucket = bucket->next;
        }
    }

    if (H3_PACKET_DEBUG && packet_count > 0) {
        fprintf(stderr, "h3_packet: flushed %d packets\n", packet_count);
    }

    return packet_count;
}

/*
 * Timeout handling
 */

int h3_packet_handle_expiry(h3_connection_t *conn) {
    if (!conn || !conn->quic) {
        return H3_ERROR_INVALID;
    }

    int rv = ngtcp2_conn_handle_expiry(conn->quic, h3_timestamp_ns());
    if (rv != 0) {
        if (H3_PACKET_DEBUG) {
            fprintf(stderr, "h3_packet: handle_expiry error: %s\n",
                    ngtcp2_strerror(rv));
        }
        if (rv == NGTCP2_ERR_IDLE_CLOSE) {
            conn->state = H3_STATE_CLOSED;
            return H3_ERROR_CLOSED;
        }
        return H3_ERROR_QUIC;
    }

    return H3_OK;
}

uint64_t h3_packet_get_expiry_ns(h3_connection_t *conn) {
    if (!conn || !conn->quic) {
        return UINT64_MAX;
    }

    return ngtcp2_conn_get_expiry(conn->quic);
}
