/*
 * h3_tls.h - GnuTLS integration for HTTP/3
 *
 * Handles TLS 1.3 setup for QUIC, including multi-domain SNI support
 * and certificate management.
 */

#ifndef H3_TLS_H
#define H3_TLS_H

#include <gnutls/gnutls.h>
#include <ngtcp2/ngtcp2.h>
#include <ngtcp2/ngtcp2_crypto.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Forward declaration */
struct h3_connection;

/* Domain-specific credential storage */
typedef struct h3_domain_cred {
    char *domain;                              /* Domain name (heap-allocated) */
    char *backend_socket;                      /* Backend socket path (heap-allocated) */
    /* Note: Certificates are loaded into shared_cred, not per-domain */
} h3_domain_cred_t;

/* TLS context for a connection */
typedef struct h3_tls_context {
    /* GnuTLS session */
    gnutls_session_t session;

    /* Shared credentials (all certificates loaded here) */
    gnutls_certificate_credentials_t shared_cred;

    /* Multi-domain support */
    h3_domain_cred_t *domains;
    int domain_count;
    char *default_domain;
    char *default_backend;

    /* Negotiated values (set during handshake) */
    char *negotiated_hostname;  /* SNI hostname from client */
    char *selected_backend;     /* Backend socket for matched domain */
    int selected_domain_idx;    /* Index of matched domain (-1 if none) */

    /* Connection reference for ngtcp2_crypto */
    ngtcp2_crypto_conn_ref conn_ref;

    /* Back-pointer to parent connection */
    struct h3_connection *conn;
} h3_tls_context_t;

/* Domain configuration for initialization */
typedef struct h3_tls_domain_config {
    const char *domain;
    const char *cert_path;
    const char *key_path;
    const char *backend_socket;  /* May be NULL */
} h3_tls_domain_config_t;

/*
 * TLS context management
 */

/* Create TLS context for a server connection
 * Returns: new context on success, NULL on failure
 */
h3_tls_context_t *h3_tls_context_new_server(
    const h3_tls_domain_config_t *domains,
    size_t domain_count,
    const char *default_domain,
    const char *default_backend  /* May be NULL */
);

/* Free TLS context */
void h3_tls_context_free(h3_tls_context_t *ctx);

/* Link TLS context to QUIC connection
 * Must be called after ngtcp2_conn is created.
 */
int h3_tls_link_connection(h3_tls_context_t *ctx, struct h3_connection *conn);

/*
 * SNI handling
 */

/* Capture SNI hostname from TLS handshake
 * Call this after initial crypto data is processed.
 * Updates negotiated_hostname, selected_backend, and selected_domain_idx.
 */
void h3_tls_capture_sni(h3_tls_context_t *ctx);

/* Get negotiated hostname */
const char *h3_tls_get_hostname(h3_tls_context_t *ctx);

/* Get selected backend socket path */
const char *h3_tls_get_backend(h3_tls_context_t *ctx);

/*
 * GnuTLS session configuration
 */

/* Configure GnuTLS session for QUIC
 * Sets up TLS 1.3, ALPN "h3", and ngtcp2_crypto callbacks.
 * Returns: 0 on success, -1 on failure
 */
int h3_tls_configure_session(h3_tls_context_t *ctx);

/*
 * ngtcp2_crypto callback support
 */

/* Get ngtcp2_conn from conn_ref (for ngtcp2_crypto callbacks) */
ngtcp2_conn *h3_tls_get_conn_callback(ngtcp2_crypto_conn_ref *conn_ref);

#ifdef __cplusplus
}
#endif

#endif /* H3_TLS_H */
