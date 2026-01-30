/*
 * h3_tls.c - GnuTLS integration for HTTP/3
 *
 * Handles TLS 1.3 setup for QUIC with multi-domain SNI support.
 */

#define _GNU_SOURCE  /* For strdup on some systems */
#include "h3_tls.h"
#include "h3_internal.h"
#include <stdlib.h>
#include <string.h>
#include <strings.h>  /* For strcasecmp, strncasecmp */
#include <stdio.h>

/* Debug flag */
#define H3_TLS_DEBUG 0

/*
 * ngtcp2_crypto conn_ref callback
 */

ngtcp2_conn *h3_tls_get_conn_callback(ngtcp2_crypto_conn_ref *conn_ref) {
    h3_tls_context_t *ctx = (h3_tls_context_t *)conn_ref->user_data;
    if (H3_TLS_DEBUG) {
        fprintf(stderr, "h3_tls: get_conn_callback: conn_ref=%p, ctx=%p\n",
                (void*)conn_ref, (void*)ctx);
    }
    if (!ctx || !ctx->conn) {
        if (H3_TLS_DEBUG) {
            fprintf(stderr, "h3_tls: get_conn_callback: returning NULL (ctx=%p, ctx->conn=%p)\n",
                    (void*)ctx, ctx ? (void*)ctx->conn : NULL);
        }
        return NULL;
    }
    if (H3_TLS_DEBUG) {
        fprintf(stderr, "h3_tls: get_conn_callback: returning quic=%p\n", (void*)ctx->conn->quic);
    }
    return ctx->conn->quic;
}

/*
 * Helper to find domain by hostname (case-insensitive)
 */

static int find_domain_by_hostname(h3_tls_context_t *ctx, const char *hostname) {
    if (!hostname) return -1;

    for (int i = 0; i < ctx->domain_count; i++) {
        if (strcasecmp(ctx->domains[i].domain, hostname) == 0) {
            return i;
        }
    }

    /* Try matching without port if present */
    const char *colon = strchr(hostname, ':');
    if (colon) {
        size_t len = colon - hostname;
        for (int i = 0; i < ctx->domain_count; i++) {
            if (strncasecmp(ctx->domains[i].domain, hostname, len) == 0 &&
                ctx->domains[i].domain[len] == '\0') {
                return i;
            }
        }
    }

    return -1;  /* Not found */
}

/*
 * TLS context management
 */

h3_tls_context_t *h3_tls_context_new_server(
    const h3_tls_domain_config_t *domains,
    size_t domain_count,
    const char *default_domain,
    const char *default_backend)
{
    h3_tls_context_t *ctx = NULL;
    int rv;

    if (domain_count == 0) {
        fprintf(stderr, "h3_tls: No domains configured\n");
        return NULL;
    }

    ctx = (h3_tls_context_t *)calloc(1, sizeof(h3_tls_context_t));
    if (!ctx) {
        return NULL;
    }

    ctx->selected_domain_idx = -1;

    /* Allocate domain array */
    ctx->domains = (h3_domain_cred_t *)calloc(domain_count, sizeof(h3_domain_cred_t));
    if (!ctx->domains) {
        free(ctx);
        return NULL;
    }

    /* Allocate shared credentials */
    rv = gnutls_certificate_allocate_credentials(&ctx->shared_cred);
    if (rv != GNUTLS_E_SUCCESS) {
        fprintf(stderr, "h3_tls: gnutls_certificate_allocate_credentials failed: %s\n",
                gnutls_strerror(rv));
        free(ctx->domains);
        free(ctx);
        return NULL;
    }

    /* Load certificates for each domain */
    int loaded_count = 0;
    for (size_t i = 0; i < domain_count; i++) {
        if (!domains[i].cert_path || !domains[i].key_path) {
            continue;
        }

        rv = gnutls_certificate_set_x509_key_file(
            ctx->shared_cred,
            domains[i].cert_path,
            domains[i].key_path,
            GNUTLS_X509_FMT_PEM
        );

        if (rv < 0) {
            fprintf(stderr, "h3_tls: Failed to load certificate for %s: %s\n",
                    domains[i].domain, gnutls_strerror(rv));
            continue;
        }

        /* Store domain info */
        ctx->domains[loaded_count].domain = strdup(domains[i].domain);
        if (domains[i].backend_socket) {
            ctx->domains[loaded_count].backend_socket = strdup(domains[i].backend_socket);
        } else if (default_backend) {
            ctx->domains[loaded_count].backend_socket = strdup(default_backend);
        } else {
            ctx->domains[loaded_count].backend_socket = NULL;
        }

        if (H3_TLS_DEBUG) {
            fprintf(stderr, "h3_tls: Loaded certificate for domain %s\n", domains[i].domain);
        }

        loaded_count++;
    }

    if (loaded_count == 0) {
        fprintf(stderr, "h3_tls: No valid certificates loaded\n");
        gnutls_certificate_free_credentials(ctx->shared_cred);
        free(ctx->domains);
        free(ctx);
        return NULL;
    }

    ctx->domain_count = loaded_count;

    if (default_domain) {
        ctx->default_domain = strdup(default_domain);
    }
    if (default_backend) {
        ctx->default_backend = strdup(default_backend);
    }

    /* Initialize GnuTLS session for server (QUIC mode) */
    rv = gnutls_init(&ctx->session, GNUTLS_SERVER | GNUTLS_NO_AUTO_REKEY);
    if (rv != GNUTLS_E_SUCCESS) {
        fprintf(stderr, "h3_tls: gnutls_init failed: %s\n", gnutls_strerror(rv));
        h3_tls_context_free(ctx);
        return NULL;
    }

    /* Set credentials */
    rv = gnutls_credentials_set(ctx->session, GNUTLS_CRD_CERTIFICATE, ctx->shared_cred);
    if (rv != GNUTLS_E_SUCCESS) {
        fprintf(stderr, "h3_tls: gnutls_credentials_set failed: %s\n", gnutls_strerror(rv));
        h3_tls_context_free(ctx);
        return NULL;
    }

    /* Set priority (TLS 1.3 required for QUIC) */
    rv = gnutls_priority_set_direct(ctx->session, "NORMAL:-VERS-ALL:+VERS-TLS1.3", NULL);
    if (rv != GNUTLS_E_SUCCESS) {
        fprintf(stderr, "h3_tls: gnutls_priority_set_direct failed: %s\n", gnutls_strerror(rv));
        h3_tls_context_free(ctx);
        return NULL;
    }

    /* Set ALPN for HTTP/3 */
    gnutls_datum_t alpn = { (unsigned char *)"h3", 2 };
    gnutls_alpn_set_protocols(ctx->session, &alpn, 1, 0);

    /* Set up conn_ref callback */
    ctx->conn_ref.get_conn = h3_tls_get_conn_callback;
    ctx->conn_ref.user_data = ctx;
    gnutls_session_set_ptr(ctx->session, &ctx->conn_ref);

    return ctx;
}

void h3_tls_context_free(h3_tls_context_t *ctx) {
    if (!ctx) return;

    if (ctx->session) {
        gnutls_deinit(ctx->session);
    }

    if (ctx->shared_cred) {
        gnutls_certificate_free_credentials(ctx->shared_cred);
    }

    if (ctx->domains) {
        for (int i = 0; i < ctx->domain_count; i++) {
            free(ctx->domains[i].domain);
            free(ctx->domains[i].backend_socket);
        }
        free(ctx->domains);
    }

    free(ctx->default_domain);
    free(ctx->default_backend);
    free(ctx->negotiated_hostname);

    free(ctx);
}

int h3_tls_link_connection(h3_tls_context_t *ctx, struct h3_connection *conn) {
    if (!ctx || !conn) return -1;

    ctx->conn = conn;

    /* Configure ngtcp2_crypto callbacks for GnuTLS */
    int rv = ngtcp2_crypto_gnutls_configure_server_session(ctx->session);
    if (rv != 0) {
        fprintf(stderr, "h3_tls: ngtcp2_crypto_gnutls_configure_server_session failed: %d\n", rv);
        return -1;
    }

    /* Link TLS session to QUIC connection */
    ngtcp2_conn_set_tls_native_handle(conn->quic, ctx->session);

    if (H3_TLS_DEBUG) {
        fprintf(stderr, "h3_tls: TLS linked to QUIC connection\n");
    }

    return 0;
}

/*
 * SNI handling
 */

void h3_tls_capture_sni(h3_tls_context_t *ctx) {
    char hostname[256];
    size_t hostname_len = sizeof(hostname);
    unsigned int type;
    int rv, idx;

    if (!ctx || !ctx->session) return;

    /* Get the SNI hostname from the client */
    rv = gnutls_server_name_get(ctx->session, hostname, &hostname_len, &type, 0);
    if (rv == GNUTLS_E_SUCCESS && type == GNUTLS_NAME_DNS) {
        hostname[hostname_len] = '\0';

        /* Store the negotiated hostname */
        if (ctx->negotiated_hostname) {
            free(ctx->negotiated_hostname);
        }
        ctx->negotiated_hostname = strdup(hostname);

        if (H3_TLS_DEBUG) {
            fprintf(stderr, "h3_tls: SNI hostname: %s\n", hostname);
        }

        /* Find matching domain for backend routing */
        idx = find_domain_by_hostname(ctx, hostname);
        if (idx >= 0) {
            ctx->selected_domain_idx = idx;
            ctx->selected_backend = ctx->domains[idx].backend_socket;
            if (H3_TLS_DEBUG) {
                fprintf(stderr, "h3_tls: Matched domain %d, backend: %s\n",
                        idx, ctx->selected_backend ? ctx->selected_backend : "(null)");
            }
            return;
        }
    }

    /* Fall back to default domain */
    if (ctx->default_domain) {
        idx = find_domain_by_hostname(ctx, ctx->default_domain);
        if (idx >= 0) {
            ctx->selected_domain_idx = idx;
            ctx->selected_backend = ctx->domains[idx].backend_socket;
            if (!ctx->negotiated_hostname) {
                ctx->negotiated_hostname = strdup(ctx->default_domain);
            }
            if (H3_TLS_DEBUG) {
                fprintf(stderr, "h3_tls: Using default domain %s\n", ctx->default_domain);
            }
        }
    }
}

const char *h3_tls_get_hostname(h3_tls_context_t *ctx) {
    if (!ctx) return NULL;

    /* Try to capture if not done yet */
    if (!ctx->negotiated_hostname) {
        h3_tls_capture_sni(ctx);
    }

    return ctx->negotiated_hostname;
}

const char *h3_tls_get_backend(h3_tls_context_t *ctx) {
    if (!ctx) return NULL;

    /* Try to capture if not done yet */
    if (!ctx->negotiated_hostname) {
        h3_tls_capture_sni(ctx);
    }

    return ctx->selected_backend;
}

int h3_tls_configure_session(h3_tls_context_t *ctx) {
    /* Session is already configured in h3_tls_context_new_server */
    return 0;
}
