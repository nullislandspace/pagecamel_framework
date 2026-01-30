/*
 * h3_packet.h - Packet processing structures and functions
 */

#ifndef H3_PACKET_H
#define H3_PACKET_H

#include "h3_api.h"
#include <stdint.h>
#include <stddef.h>
#include <sys/socket.h>
#include <netinet/in.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Forward declaration */
struct h3_connection;

/*
 * Packet processing
 */

/* Feed a received UDP packet to the QUIC stack
 * Returns: H3_OK on success, error code on failure
 */
int h3_packet_process(
    struct h3_connection *conn,
    const uint8_t *data, size_t len,
    const h3_addr_info_t *addr
);

/* Generate outgoing packets and send via callback
 * Returns: number of packets sent, or error code
 */
int h3_packet_flush(struct h3_connection *conn);

/* Handle timeout expiry
 * Returns: H3_OK on success, error code on failure
 */
int h3_packet_handle_expiry(struct h3_connection *conn);

/* Get timeout until next event in nanoseconds */
uint64_t h3_packet_get_expiry_ns(struct h3_connection *conn);

/*
 * Address conversion utilities
 */

/* Fill sockaddr from h3_addr_info_t
 * Returns: address length, or 0 on error
 */
int h3_addr_to_sockaddr(
    const h3_addr_info_t *addr,
    struct sockaddr_storage *local,
    struct sockaddr_storage *remote
);

/* Fill h3_addr_info_t from sockaddr */
void h3_sockaddr_to_addr(
    const struct sockaddr_storage *local,
    const struct sockaddr_storage *remote,
    h3_addr_info_t *addr
);

/*
 * Timestamp utilities
 */

/* Get current timestamp in nanoseconds (monotonic clock) */
uint64_t h3_timestamp_ns(void);

#ifdef __cplusplus
}
#endif

#endif /* H3_PACKET_H */
