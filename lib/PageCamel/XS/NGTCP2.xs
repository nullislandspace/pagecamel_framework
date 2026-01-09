/*
 * PageCamel::XS::NGTCP2 - XS bindings for ngtcp2 QUIC library
 *
 * This module provides Perl bindings to ngtcp2 for QUIC protocol support.
 */

#define PERL_NO_GET_CONTEXT
#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

#include <ngtcp2/ngtcp2.h>
#include <ngtcp2/ngtcp2_crypto.h>
#include <ngtcp2/ngtcp2_crypto_gnutls.h>
#include <gnutls/gnutls.h>
#include <gnutls/crypto.h>
#include <string.h>
#include <time.h>
#include <stdarg.h>

/* Structure for domain-specific credentials */
typedef struct {
    char *domain;
    gnutls_certificate_credentials_t cred;
    char *backend_socket;
} PageCamel_DomainCred;

/* Wrapper structure for QUIC connection with Perl callback storage */
typedef struct {
    ngtcp2_conn *conn;
    SV *recv_stream_data_cb;
    SV *stream_open_cb;
    SV *stream_close_cb;
    SV *recv_datagram_cb;
    SV *acked_stream_data_offset_cb;
    SV *handshake_completed_cb;
    SV *path_validation_cb;
    SV *user_data;

    /* Multi-domain SNI support */
    PageCamel_DomainCred *domains;
    int domain_count;
    char *default_domain;
    char *negotiated_hostname;
    char *selected_backend;
    int selected_domain_idx;

    gnutls_certificate_credentials_t shared_cred;
    gnutls_session_t session;

    /* Connection reference for ngtcp2_crypto callbacks */
    ngtcp2_crypto_conn_ref conn_ref;
} PageCamel_QUIC_Connection;

/* Wrapper for transport parameters */
typedef struct {
    ngtcp2_transport_params params;
} PageCamel_TransportParams;

/* Wrapper for settings */
typedef struct {
    ngtcp2_settings settings;
} PageCamel_Settings;

/* Wrapper for connection ID */
typedef struct {
    ngtcp2_cid cid;
} PageCamel_CID;

/* Wrapper for path */
typedef struct {
    ngtcp2_path path;
    struct sockaddr_storage local_addr;
    struct sockaddr_storage remote_addr;
} PageCamel_Path;

/* Forward declarations for callback trampolines */
static int recv_stream_data_trampoline(ngtcp2_conn *conn, uint32_t flags,
    int64_t stream_id, uint64_t offset, const uint8_t *data, size_t datalen,
    void *user_data, void *stream_user_data);

static int stream_open_trampoline(ngtcp2_conn *conn, int64_t stream_id,
    void *user_data);

static int stream_close_trampoline(ngtcp2_conn *conn, uint32_t flags,
    int64_t stream_id, uint64_t app_error_code, void *user_data,
    void *stream_user_data);

static int acked_stream_data_offset_trampoline(ngtcp2_conn *conn,
    int64_t stream_id, uint64_t offset, uint64_t datalen, void *user_data,
    void *stream_user_data);

static int handshake_completed_trampoline(ngtcp2_conn *conn, void *user_data);

static int path_validation_trampoline(ngtcp2_conn *conn, uint32_t flags,
    const ngtcp2_path *path, ngtcp2_path_validation_result res, void *user_data);

/* Utility to get current timestamp in nanoseconds */
static ngtcp2_tstamp get_timestamp(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (ngtcp2_tstamp)ts.tv_sec * NGTCP2_SECONDS + (ngtcp2_tstamp)ts.tv_nsec;
}

/* Callback for ngtcp2_crypto to get the ngtcp2_conn from conn_ref */
static ngtcp2_conn *get_conn_callback(ngtcp2_crypto_conn_ref *conn_ref) {
    PageCamel_QUIC_Connection *qc = (PageCamel_QUIC_Connection *)conn_ref->user_data;
    fprintf(stderr, "NGTCP2: get_conn_callback called, qc=%p, conn=%p\n", (void*)qc, qc ? (void*)qc->conn : NULL);
    return qc ? qc->conn : NULL;
}

/* Helper to find domain by hostname (case-insensitive) */
static int find_domain_by_hostname(PageCamel_QUIC_Connection *qc, const char *hostname) {
    int i;
    for (i = 0; i < qc->domain_count; i++) {
        if (strcasecmp(qc->domains[i].domain, hostname) == 0) {
            return i;
        }
    }
    /* Try matching without port if present */
    char *colon = strchr(hostname, ':');
    if (colon) {
        size_t len = colon - hostname;
        for (i = 0; i < qc->domain_count; i++) {
            if (strncasecmp(qc->domains[i].domain, hostname, len) == 0 &&
                qc->domains[i].domain[len] == '\0') {
                return i;
            }
        }
    }
    return -1;  /* Not found */
}

/* Capture SNI hostname and select backend - call after handshake starts */
static void capture_sni_hostname(PageCamel_QUIC_Connection *qc) {
    char hostname[256];
    size_t hostname_len = sizeof(hostname);
    unsigned int type;
    int rv, idx;

    if (!qc || !qc->session) return;

    /* Get the SNI hostname from the client */
    rv = gnutls_server_name_get(qc->session, hostname, &hostname_len, &type, 0);
    if (rv == GNUTLS_E_SUCCESS && type == GNUTLS_NAME_DNS) {
        hostname[hostname_len] = '\0';

        /* Store the negotiated hostname */
        if (qc->negotiated_hostname) {
            free(qc->negotiated_hostname);
        }
        qc->negotiated_hostname = strdup(hostname);

        /* Find matching domain for backend routing */
        idx = find_domain_by_hostname(qc, hostname);
        if (idx >= 0) {
            qc->selected_domain_idx = idx;
            qc->selected_backend = qc->domains[idx].backend_socket;
            return;
        }
    }

    /* Fall back to default domain */
    if (qc->default_domain) {
        idx = find_domain_by_hostname(qc, qc->default_domain);
        if (idx >= 0) {
            qc->selected_domain_idx = idx;
            qc->selected_backend = qc->domains[idx].backend_socket;
            if (!qc->negotiated_hostname) {
                qc->negotiated_hostname = strdup(qc->default_domain);
            }
        }
    }
}

/* Random number generator callback for ngtcp2 */
static void rand_callback(uint8_t *dest, size_t destlen,
    const ngtcp2_rand_ctx *rand_ctx)
{
    (void)rand_ctx;  /* unused */
    /* Use GnuTLS random for cryptographic quality randomness */
    gnutls_rnd(GNUTLS_RND_RANDOM, dest, destlen);
}

/* Get new connection ID callback - required for QUIC */
static int get_new_connection_id_callback(ngtcp2_conn *conn, ngtcp2_cid *cid,
    uint8_t *token, size_t cidlen, void *user_data)
{
    (void)conn;
    (void)user_data;

    /* Generate random connection ID */
    gnutls_rnd(GNUTLS_RND_RANDOM, cid->data, cidlen);
    cid->datalen = cidlen;

    /* Generate random stateless reset token (NGTCP2_STATELESS_RESET_TOKENLEN = 16 bytes) */
    gnutls_rnd(GNUTLS_RND_RANDOM, token, NGTCP2_STATELESS_RESET_TOKENLEN);

    return 0;
}

/* Debug logging callback for ngtcp2 */
static void ngtcp2_log_printf_cb(void *user_data, const char *format, ...) {
    va_list args;
    (void)user_data;
    va_start(args, format);
    fprintf(stderr, "NGTCP2-LOG: ");
    vfprintf(stderr, format, args);
    va_end(args);
}

/* Debug wrapper for recv_client_initial to trace initial packet processing */
static int recv_client_initial_wrapper(ngtcp2_conn *conn,
    const ngtcp2_cid *dcid, void *user_data)
{
    int rv;
    fprintf(stderr, "NGTCP2: recv_client_initial called, dcid len=%zu\n", dcid->datalen);

    rv = ngtcp2_crypto_recv_client_initial_cb(conn, dcid, user_data);

    fprintf(stderr, "NGTCP2: recv_client_initial returned %d\n", rv);
    if (rv != 0) {
        fprintf(stderr, "NGTCP2: recv_client_initial ERROR: %s\n", ngtcp2_strerror(rv));
    }

    return rv;
}

/* Debug wrapper for recv_crypto_data to trace transport params processing */
static int recv_crypto_data_wrapper(ngtcp2_conn *conn,
    ngtcp2_crypto_level crypto_level, uint64_t offset,
    const uint8_t *data, size_t datalen, void *user_data)
{
    int rv;
    const char *level_str;
    PageCamel_QUIC_Connection *qc = (PageCamel_QUIC_Connection *)user_data;
    const ngtcp2_cid *rcid;

    switch (crypto_level) {
        case NGTCP2_CRYPTO_LEVEL_INITIAL:
            level_str = "INITIAL";
            break;
        case NGTCP2_CRYPTO_LEVEL_HANDSHAKE:
            level_str = "HANDSHAKE";
            break;
        case NGTCP2_CRYPTO_LEVEL_APPLICATION:
            level_str = "APPLICATION";
            break;
        case NGTCP2_CRYPTO_LEVEL_EARLY:
            level_str = "EARLY";
            break;
        default:
            level_str = "UNKNOWN";
            break;
    }

    fprintf(stderr, "NGTCP2: recv_crypto_data level=%s offset=%lu datalen=%zu\n",
            level_str, (unsigned long)offset, datalen);

    /* Dump first 32 bytes of crypto data in hex */
    if (datalen > 0) {
        size_t dump_len = datalen < 32 ? datalen : 32;
        size_t i;
        fprintf(stderr, "NGTCP2: crypto_data[0..%zu]: ", dump_len - 1);
        for (i = 0; i < dump_len; i++) {
            fprintf(stderr, "%02x ", data[i]);
        }
        fprintf(stderr, "\n");
    }

    /* Debug: show connection's stored CIDs before processing */
    rcid = ngtcp2_conn_get_dcid(conn);
    if (rcid) {
        fprintf(stderr, "NGTCP2: conn dcid len=%zu\n", rcid->datalen);
    }

    /* Call the real crypto callback */
    rv = ngtcp2_crypto_recv_crypto_data_cb(conn, crypto_level, offset, data, datalen, user_data);

    fprintf(stderr, "NGTCP2: recv_crypto_data returned %d\n", rv);

    if (rv != 0) {
        fprintf(stderr, "NGTCP2: recv_crypto_data ERROR: %s\n", ngtcp2_strerror(rv));

        /* Check GnuTLS state */
        if (qc && qc->session) {
            int alert = gnutls_alert_get(qc->session);
            if (alert != 0) {
                fprintf(stderr, "NGTCP2: GnuTLS alert: %d (%s)\n", alert, gnutls_alert_get_name(alert));
            }
        }
    }

    /* After successful processing, show remote transport params */
    if (rv == 0) {
        const ngtcp2_transport_params *rparams = ngtcp2_conn_get_remote_transport_params(conn);
        if (rparams) {
            fprintf(stderr, "NGTCP2: remote transport params:\n");
            fprintf(stderr, "  initial_scid.datalen=%zu\n", rparams->initial_scid.datalen);
            fprintf(stderr, "  initial_max_data=%lu\n", (unsigned long)rparams->initial_max_data);
        }
    }

    return rv;
}

/* Callback implementations that call back to Perl */
static int recv_stream_data_trampoline(ngtcp2_conn *conn, uint32_t flags,
    int64_t stream_id, uint64_t offset, const uint8_t *data, size_t datalen,
    void *user_data, void *stream_user_data)
{
    dTHX;
    PageCamel_QUIC_Connection *qc = (PageCamel_QUIC_Connection *)user_data;

    fprintf(stderr, "NGTCP2: recv_stream_data_trampoline called! stream_id=%lld offset=%llu datalen=%zu flags=0x%x\n",
            (long long)stream_id, (unsigned long long)offset, datalen, flags);
    fprintf(stderr, "NGTCP2: qc=%p, recv_stream_data_cb=%p\n", (void*)qc, qc ? (void*)qc->recv_stream_data_cb : NULL);

    if (qc->recv_stream_data_cb && SvOK(qc->recv_stream_data_cb)) {
        fprintf(stderr, "NGTCP2: recv_stream_data_trampoline: callback is set, calling Perl\n");
        dSP;
        int count;
        int retval = 0;

        ENTER;
        SAVETMPS;

        PUSHMARK(SP);
        XPUSHs(sv_2mortal(newSViv(stream_id)));
        XPUSHs(sv_2mortal(newSVuv(offset)));
        XPUSHs(sv_2mortal(newSVpvn((const char *)data, datalen)));
        XPUSHs(sv_2mortal(newSVuv(flags)));
        PUTBACK;

        count = call_sv(qc->recv_stream_data_cb, G_SCALAR);

        SPAGAIN;

        if (count == 1) {
            retval = POPi;
        }

        FREETMPS;
        LEAVE;

        fprintf(stderr, "NGTCP2: recv_stream_data_trampoline: Perl callback returned %d\n", retval);
        return retval;
    } else {
        fprintf(stderr, "NGTCP2: recv_stream_data_trampoline: NO callback set or callback invalid!\n");
    }

    return 0;
}

static int stream_open_trampoline(ngtcp2_conn *conn, int64_t stream_id,
    void *user_data)
{
    dTHX;
    PageCamel_QUIC_Connection *qc = (PageCamel_QUIC_Connection *)user_data;

    fprintf(stderr, "NGTCP2: stream_open_trampoline called! stream_id=%lld\n", (long long)stream_id);

    if (qc->stream_open_cb && SvOK(qc->stream_open_cb)) {
        dSP;
        int count;
        int retval = 0;

        ENTER;
        SAVETMPS;

        PUSHMARK(SP);
        XPUSHs(sv_2mortal(newSViv(stream_id)));
        PUTBACK;

        count = call_sv(qc->stream_open_cb, G_SCALAR);

        SPAGAIN;

        if (count == 1) {
            retval = POPi;
        }

        FREETMPS;
        LEAVE;

        return retval;
    }

    return 0;
}

static int stream_close_trampoline(ngtcp2_conn *conn, uint32_t flags,
    int64_t stream_id, uint64_t app_error_code, void *user_data,
    void *stream_user_data)
{
    dTHX;
    PageCamel_QUIC_Connection *qc = (PageCamel_QUIC_Connection *)user_data;

    if (qc->stream_close_cb && SvOK(qc->stream_close_cb)) {
        dSP;
        int count;
        int retval = 0;

        ENTER;
        SAVETMPS;

        PUSHMARK(SP);
        XPUSHs(sv_2mortal(newSViv(stream_id)));
        XPUSHs(sv_2mortal(newSVuv(app_error_code)));
        XPUSHs(sv_2mortal(newSVuv(flags)));
        PUTBACK;

        count = call_sv(qc->stream_close_cb, G_SCALAR);

        SPAGAIN;

        if (count == 1) {
            retval = POPi;
        }

        FREETMPS;
        LEAVE;

        return retval;
    }

    return 0;
}

static int acked_stream_data_offset_trampoline(ngtcp2_conn *conn,
    int64_t stream_id, uint64_t offset, uint64_t datalen, void *user_data,
    void *stream_user_data)
{
    dTHX;
    PageCamel_QUIC_Connection *qc = (PageCamel_QUIC_Connection *)user_data;

    if (qc->acked_stream_data_offset_cb && SvOK(qc->acked_stream_data_offset_cb)) {
        dSP;
        int count;
        int retval = 0;

        ENTER;
        SAVETMPS;

        PUSHMARK(SP);
        XPUSHs(sv_2mortal(newSViv(stream_id)));
        XPUSHs(sv_2mortal(newSVuv(offset)));
        XPUSHs(sv_2mortal(newSVuv(datalen)));
        PUTBACK;

        count = call_sv(qc->acked_stream_data_offset_cb, G_SCALAR);

        SPAGAIN;

        if (count == 1) {
            retval = POPi;
        }

        FREETMPS;
        LEAVE;

        return retval;
    }

    return 0;
}

static int handshake_completed_trampoline(ngtcp2_conn *conn, void *user_data)
{
    dTHX;
    PageCamel_QUIC_Connection *qc = (PageCamel_QUIC_Connection *)user_data;

    if (qc->handshake_completed_cb && SvOK(qc->handshake_completed_cb)) {
        dSP;
        int count;
        int retval = 0;

        ENTER;
        SAVETMPS;

        PUSHMARK(SP);
        PUTBACK;

        count = call_sv(qc->handshake_completed_cb, G_SCALAR);

        SPAGAIN;

        if (count == 1) {
            retval = POPi;
        }

        FREETMPS;
        LEAVE;

        return retval;
    }

    return 0;
}

static int path_validation_trampoline(ngtcp2_conn *conn, uint32_t flags,
    const ngtcp2_path *path, ngtcp2_path_validation_result res, void *user_data)
{
    dTHX;
    PageCamel_QUIC_Connection *qc = (PageCamel_QUIC_Connection *)user_data;

    if (qc->path_validation_cb && SvOK(qc->path_validation_cb)) {
        dSP;
        int count;
        int retval = 0;

        ENTER;
        SAVETMPS;

        PUSHMARK(SP);
        XPUSHs(sv_2mortal(newSViv(res)));
        XPUSHs(sv_2mortal(newSVuv(flags)));
        PUTBACK;

        count = call_sv(qc->path_validation_cb, G_SCALAR);

        SPAGAIN;

        if (count == 1) {
            retval = POPi;
        }

        FREETMPS;
        LEAVE;

        return retval;
    }

    return 0;
}

MODULE = PageCamel::XS::NGTCP2    PACKAGE = PageCamel::XS::NGTCP2

PROTOTYPES: DISABLE

# Return library version string
const char *
version()
    CODE:
        RETVAL = ngtcp2_version(0)->version_str;
    OUTPUT:
        RETVAL

# Get current timestamp in nanoseconds
UV
timestamp()
    CODE:
        RETVAL = get_timestamp();
    OUTPUT:
        RETVAL

# Check if a QUIC version is supported
int
is_supported_version(version)
        UV version
    CODE:
        RETVAL = ngtcp2_is_supported_version((uint32_t)version);
    OUTPUT:
        RETVAL

# Protocol version constants
UV
NGTCP2_PROTO_VER_V1()
    CODE:
        RETVAL = NGTCP2_PROTO_VER_V1;
    OUTPUT:
        RETVAL

UV
NGTCP2_PROTO_VER_V2()
    CODE:
        RETVAL = NGTCP2_PROTO_VER_V2_DRAFT;
    OUTPUT:
        RETVAL

# Connection ID limits
UV
NGTCP2_MAX_CIDLEN()
    CODE:
        RETVAL = NGTCP2_MAX_CIDLEN;
    OUTPUT:
        RETVAL

UV
NGTCP2_MIN_CIDLEN()
    CODE:
        RETVAL = NGTCP2_MIN_CIDLEN;
    OUTPUT:
        RETVAL

# UDP payload size
UV
NGTCP2_MAX_UDP_PAYLOAD_SIZE()
    CODE:
        RETVAL = NGTCP2_MAX_UDP_PAYLOAD_SIZE;
    OUTPUT:
        RETVAL

UV
NGTCP2_DEFAULT_MAX_RECV_UDP_PAYLOAD_SIZE()
    CODE:
        RETVAL = NGTCP2_DEFAULT_MAX_RECV_UDP_PAYLOAD_SIZE;
    OUTPUT:
        RETVAL

# Default values
UV
NGTCP2_DEFAULT_ACK_DELAY_EXPONENT()
    CODE:
        RETVAL = NGTCP2_DEFAULT_ACK_DELAY_EXPONENT;
    OUTPUT:
        RETVAL

UV
NGTCP2_DEFAULT_MAX_ACK_DELAY()
    CODE:
        RETVAL = NGTCP2_DEFAULT_MAX_ACK_DELAY;
    OUTPUT:
        RETVAL

UV
NGTCP2_DEFAULT_ACTIVE_CONNECTION_ID_LIMIT()
    CODE:
        RETVAL = NGTCP2_DEFAULT_ACTIVE_CONNECTION_ID_LIMIT;
    OUTPUT:
        RETVAL

UV
NGTCP2_TLSEXT_QUIC_TRANSPORT_PARAMETERS_V1()
    CODE:
        RETVAL = NGTCP2_TLSEXT_QUIC_TRANSPORT_PARAMETERS_V1;
    OUTPUT:
        RETVAL

# Error codes
IV
NGTCP2_ERR_INVALID_ARGUMENT()
    CODE:
        RETVAL = NGTCP2_ERR_INVALID_ARGUMENT;
    OUTPUT:
        RETVAL

IV
NGTCP2_ERR_NOBUF()
    CODE:
        RETVAL = NGTCP2_ERR_NOBUF;
    OUTPUT:
        RETVAL

IV
NGTCP2_ERR_PROTO()
    CODE:
        RETVAL = NGTCP2_ERR_PROTO;
    OUTPUT:
        RETVAL

IV
NGTCP2_ERR_INVALID_STATE()
    CODE:
        RETVAL = NGTCP2_ERR_INVALID_STATE;
    OUTPUT:
        RETVAL

IV
NGTCP2_ERR_ACK_FRAME()
    CODE:
        RETVAL = NGTCP2_ERR_ACK_FRAME;
    OUTPUT:
        RETVAL

IV
NGTCP2_ERR_STREAM_ID_BLOCKED()
    CODE:
        RETVAL = NGTCP2_ERR_STREAM_ID_BLOCKED;
    OUTPUT:
        RETVAL

IV
NGTCP2_ERR_STREAM_IN_USE()
    CODE:
        RETVAL = NGTCP2_ERR_STREAM_IN_USE;
    OUTPUT:
        RETVAL

IV
NGTCP2_ERR_STREAM_DATA_BLOCKED()
    CODE:
        RETVAL = NGTCP2_ERR_STREAM_DATA_BLOCKED;
    OUTPUT:
        RETVAL

IV
NGTCP2_ERR_FLOW_CONTROL()
    CODE:
        RETVAL = NGTCP2_ERR_FLOW_CONTROL;
    OUTPUT:
        RETVAL

IV
NGTCP2_ERR_CONNECTION_ID_LIMIT()
    CODE:
        RETVAL = NGTCP2_ERR_CONNECTION_ID_LIMIT;
    OUTPUT:
        RETVAL

IV
NGTCP2_ERR_STREAM_LIMIT()
    CODE:
        RETVAL = NGTCP2_ERR_STREAM_LIMIT;
    OUTPUT:
        RETVAL

IV
NGTCP2_ERR_FINAL_SIZE()
    CODE:
        RETVAL = NGTCP2_ERR_FINAL_SIZE;
    OUTPUT:
        RETVAL

IV
NGTCP2_ERR_CRYPTO()
    CODE:
        RETVAL = NGTCP2_ERR_CRYPTO;
    OUTPUT:
        RETVAL

IV
NGTCP2_ERR_PKT_NUM_EXHAUSTED()
    CODE:
        RETVAL = NGTCP2_ERR_PKT_NUM_EXHAUSTED;
    OUTPUT:
        RETVAL

IV
NGTCP2_ERR_REQUIRED_TRANSPORT_PARAM()
    CODE:
        RETVAL = NGTCP2_ERR_REQUIRED_TRANSPORT_PARAM;
    OUTPUT:
        RETVAL

IV
NGTCP2_ERR_MALFORMED_TRANSPORT_PARAM()
    CODE:
        RETVAL = NGTCP2_ERR_MALFORMED_TRANSPORT_PARAM;
    OUTPUT:
        RETVAL

IV
NGTCP2_ERR_FRAME_ENCODING()
    CODE:
        RETVAL = NGTCP2_ERR_FRAME_ENCODING;
    OUTPUT:
        RETVAL

IV
NGTCP2_ERR_DECRYPT()
    CODE:
        RETVAL = NGTCP2_ERR_DECRYPT;
    OUTPUT:
        RETVAL

IV
NGTCP2_ERR_STREAM_SHUT_WR()
    CODE:
        RETVAL = NGTCP2_ERR_STREAM_SHUT_WR;
    OUTPUT:
        RETVAL

IV
NGTCP2_ERR_STREAM_NOT_FOUND()
    CODE:
        RETVAL = NGTCP2_ERR_STREAM_NOT_FOUND;
    OUTPUT:
        RETVAL

IV
NGTCP2_ERR_STREAM_STATE()
    CODE:
        RETVAL = NGTCP2_ERR_STREAM_STATE;
    OUTPUT:
        RETVAL

IV
NGTCP2_ERR_RECV_VERSION_NEGOTIATION()
    CODE:
        RETVAL = NGTCP2_ERR_RECV_VERSION_NEGOTIATION;
    OUTPUT:
        RETVAL

IV
NGTCP2_ERR_CLOSING()
    CODE:
        RETVAL = NGTCP2_ERR_CLOSING;
    OUTPUT:
        RETVAL

IV
NGTCP2_ERR_DRAINING()
    CODE:
        RETVAL = NGTCP2_ERR_DRAINING;
    OUTPUT:
        RETVAL

IV
NGTCP2_ERR_TRANSPORT_PARAM()
    CODE:
        RETVAL = NGTCP2_ERR_TRANSPORT_PARAM;
    OUTPUT:
        RETVAL

IV
NGTCP2_ERR_DISCARD_PKT()
    CODE:
        RETVAL = NGTCP2_ERR_DISCARD_PKT;
    OUTPUT:
        RETVAL

IV
NGTCP2_ERR_CONN_ID_BLOCKED()
    CODE:
        RETVAL = NGTCP2_ERR_CONN_ID_BLOCKED;
    OUTPUT:
        RETVAL

IV
NGTCP2_ERR_INTERNAL()
    CODE:
        RETVAL = NGTCP2_ERR_INTERNAL;
    OUTPUT:
        RETVAL

IV
NGTCP2_ERR_CRYPTO_BUFFER_EXCEEDED()
    CODE:
        RETVAL = NGTCP2_ERR_CRYPTO_BUFFER_EXCEEDED;
    OUTPUT:
        RETVAL

IV
NGTCP2_ERR_WRITE_MORE()
    CODE:
        RETVAL = NGTCP2_ERR_WRITE_MORE;
    OUTPUT:
        RETVAL

IV
NGTCP2_ERR_RETRY()
    CODE:
        RETVAL = NGTCP2_ERR_RETRY;
    OUTPUT:
        RETVAL

IV
NGTCP2_ERR_DROP_CONN()
    CODE:
        RETVAL = NGTCP2_ERR_DROP_CONN;
    OUTPUT:
        RETVAL

IV
NGTCP2_ERR_AEAD_LIMIT_REACHED()
    CODE:
        RETVAL = NGTCP2_ERR_AEAD_LIMIT_REACHED;
    OUTPUT:
        RETVAL

IV
NGTCP2_ERR_NO_VIABLE_PATH()
    CODE:
        RETVAL = NGTCP2_ERR_NO_VIABLE_PATH;
    OUTPUT:
        RETVAL

IV
NGTCP2_ERR_VERSION_NEGOTIATION()
    CODE:
        RETVAL = NGTCP2_ERR_VERSION_NEGOTIATION;
    OUTPUT:
        RETVAL

IV
NGTCP2_ERR_HANDSHAKE_TIMEOUT()
    CODE:
        RETVAL = NGTCP2_ERR_HANDSHAKE_TIMEOUT;
    OUTPUT:
        RETVAL

IV
NGTCP2_ERR_VERSION_NEGOTIATION_FAILURE()
    CODE:
        RETVAL = NGTCP2_ERR_VERSION_NEGOTIATION_FAILURE;
    OUTPUT:
        RETVAL

IV
NGTCP2_ERR_IDLE_CLOSE()
    CODE:
        RETVAL = NGTCP2_ERR_IDLE_CLOSE;
    OUTPUT:
        RETVAL

# Convert error code to string
const char *
strerror(error_code)
        IV error_code
    CODE:
        RETVAL = ngtcp2_strerror((int)error_code);
    OUTPUT:
        RETVAL


MODULE = PageCamel::XS::NGTCP2    PACKAGE = PageCamel::XS::NGTCP2::Settings

# Create new settings object
PageCamel_Settings *
new(class)
        const char *class
    CODE:
        PageCamel_Settings *s;
        Newxz(s, 1, PageCamel_Settings);
        ngtcp2_settings_default(&s->settings);
        RETVAL = s;
    OUTPUT:
        RETVAL

void
DESTROY(self)
        PageCamel_Settings *self
    CODE:
        Safefree(self);

void
set_initial_ts(self, ts)
        PageCamel_Settings *self
        UV ts
    CODE:
        self->settings.initial_ts = (ngtcp2_tstamp)ts;

UV
get_initial_ts(self)
        PageCamel_Settings *self
    CODE:
        RETVAL = self->settings.initial_ts;
    OUTPUT:
        RETVAL

void
set_max_tx_udp_payload_size(self, size)
        PageCamel_Settings *self
        UV size
    CODE:
        self->settings.max_tx_udp_payload_size = (size_t)size;

void
set_handshake_timeout(self, timeout)
        PageCamel_Settings *self
        UV timeout
    CODE:
        self->settings.handshake_timeout = (ngtcp2_duration)timeout;

void
set_initial_rtt(self, rtt)
        PageCamel_Settings *self
        UV rtt
    CODE:
        self->settings.initial_rtt = (ngtcp2_duration)rtt;

void
enable_logging(self)
        PageCamel_Settings *self
    CODE:
        self->settings.log_printf = ngtcp2_log_printf_cb;


MODULE = PageCamel::XS::NGTCP2    PACKAGE = PageCamel::XS::NGTCP2::TransportParams

# Create new transport params object
PageCamel_TransportParams *
new(class)
        const char *class
    CODE:
        PageCamel_TransportParams *tp;
        Newxz(tp, 1, PageCamel_TransportParams);
        ngtcp2_transport_params_default(&tp->params);
        RETVAL = tp;
    OUTPUT:
        RETVAL

void
DESTROY(self)
        PageCamel_TransportParams *self
    CODE:
        Safefree(self);

void
set_initial_max_streams_bidi(self, val)
        PageCamel_TransportParams *self
        UV val
    CODE:
        self->params.initial_max_streams_bidi = (uint64_t)val;

void
set_initial_max_streams_uni(self, val)
        PageCamel_TransportParams *self
        UV val
    CODE:
        self->params.initial_max_streams_uni = (uint64_t)val;

void
set_initial_max_data(self, val)
        PageCamel_TransportParams *self
        UV val
    CODE:
        self->params.initial_max_data = (uint64_t)val;

void
set_initial_max_stream_data_bidi_local(self, val)
        PageCamel_TransportParams *self
        UV val
    CODE:
        self->params.initial_max_stream_data_bidi_local = (uint64_t)val;

void
set_initial_max_stream_data_bidi_remote(self, val)
        PageCamel_TransportParams *self
        UV val
    CODE:
        self->params.initial_max_stream_data_bidi_remote = (uint64_t)val;

void
set_initial_max_stream_data_uni(self, val)
        PageCamel_TransportParams *self
        UV val
    CODE:
        self->params.initial_max_stream_data_uni = (uint64_t)val;

void
set_max_idle_timeout(self, val)
        PageCamel_TransportParams *self
        UV val
    CODE:
        self->params.max_idle_timeout = (ngtcp2_duration)val;

void
set_max_udp_payload_size(self, val)
        PageCamel_TransportParams *self
        UV val
    CODE:
        self->params.max_udp_payload_size = (uint64_t)val;

void
set_active_connection_id_limit(self, val)
        PageCamel_TransportParams *self
        UV val
    CODE:
        self->params.active_connection_id_limit = (uint64_t)val;

void
set_original_dcid(self, cid)
        PageCamel_TransportParams *self
        PageCamel_CID *cid
    CODE:
        /* Server MUST set original_dcid to the client's DCID from Initial packet */
        fprintf(stderr, "NGTCP2: set_original_dcid, len=%zu\n", cid->cid.datalen);
        memcpy(&self->params.original_dcid, &cid->cid, sizeof(ngtcp2_cid));

void
set_initial_scid(self, cid)
        PageCamel_TransportParams *self
        PageCamel_CID *cid
    CODE:
        /* Server's own Source Connection ID */
        fprintf(stderr, "NGTCP2: set_initial_scid, len=%zu\n", cid->cid.datalen);
        memcpy(&self->params.initial_scid, &cid->cid, sizeof(ngtcp2_cid));


MODULE = PageCamel::XS::NGTCP2    PACKAGE = PageCamel::XS::NGTCP2::CID

# Create new connection ID object
PageCamel_CID *
new(class, data_sv = &PL_sv_undef)
        const char *class
        SV *data_sv
    CODE:
        PageCamel_CID *cid;
        Newxz(cid, 1, PageCamel_CID);

        if (SvOK(data_sv)) {
            STRLEN len;
            const char *data = SvPVbyte(data_sv, len);
            if (len > NGTCP2_MAX_CIDLEN) {
                len = NGTCP2_MAX_CIDLEN;
            }
            ngtcp2_cid_init(&cid->cid, (const uint8_t *)data, len);
        }
        RETVAL = cid;
    OUTPUT:
        RETVAL

void
DESTROY(self)
        PageCamel_CID *self
    CODE:
        Safefree(self);

# Initialize CID from raw bytes
void
init(self, data)
        PageCamel_CID *self
        SV *data
    CODE:
        STRLEN len;
        const char *bytes = SvPVbyte(data, len);
        if (len > NGTCP2_MAX_CIDLEN) {
            len = NGTCP2_MAX_CIDLEN;
        }
        ngtcp2_cid_init(&self->cid, (const uint8_t *)bytes, len);

# Get CID as raw bytes
SV *
data(self)
        PageCamel_CID *self
    CODE:
        RETVAL = newSVpvn((const char *)self->cid.data, self->cid.datalen);
    OUTPUT:
        RETVAL

# Get CID length
UV
datalen(self)
        PageCamel_CID *self
    CODE:
        RETVAL = self->cid.datalen;
    OUTPUT:
        RETVAL

# Compare two CIDs
int
eq(self, other)
        PageCamel_CID *self
        PageCamel_CID *other
    CODE:
        RETVAL = ngtcp2_cid_eq(&self->cid, &other->cid);
    OUTPUT:
        RETVAL


MODULE = PageCamel::XS::NGTCP2    PACKAGE = PageCamel::XS::NGTCP2::Path

# Create new path object
PageCamel_Path *
new(class, local_addr, local_port, remote_addr, remote_port)
        const char *class
        const char *local_addr
        int local_port
        const char *remote_addr
        int remote_port
    CODE:
        PageCamel_Path *p;
        struct sockaddr_in *local, *remote;

        Newxz(p, 1, PageCamel_Path);

        /* Initialize local address */
        local = (struct sockaddr_in *)&p->local_addr;
        local->sin_family = AF_INET;
        local->sin_port = htons(local_port);
        inet_pton(AF_INET, local_addr, &local->sin_addr);

        /* Initialize remote address */
        remote = (struct sockaddr_in *)&p->remote_addr;
        remote->sin_family = AF_INET;
        remote->sin_port = htons(remote_port);
        inet_pton(AF_INET, remote_addr, &remote->sin_addr);

        /* Set up ngtcp2_path structure */
        p->path.local.addr = (struct sockaddr *)&p->local_addr;
        p->path.local.addrlen = sizeof(struct sockaddr_in);
        p->path.remote.addr = (struct sockaddr *)&p->remote_addr;
        p->path.remote.addrlen = sizeof(struct sockaddr_in);

        RETVAL = p;
    OUTPUT:
        RETVAL

void
DESTROY(self)
        PageCamel_Path *self
    CODE:
        Safefree(self);


MODULE = PageCamel::XS::NGTCP2    PACKAGE = PageCamel::XS::NGTCP2::Connection

# Create new server connection
PageCamel_QUIC_Connection *
server_new(class, ...)
        const char *class
    PREINIT:
        PageCamel_QUIC_Connection *qc;
        PageCamel_CID *dcid = NULL;
        PageCamel_CID *scid = NULL;
        PageCamel_Path *path = NULL;
        PageCamel_Settings *settings = NULL;
        PageCamel_TransportParams *params = NULL;
        uint32_t version = NGTCP2_PROTO_VER_V1;
        ngtcp2_callbacks callbacks;
        SV *ssl_domains_sv = NULL;
        const char *default_domain = NULL;
        gnutls_certificate_credentials_t cred = NULL;
        int rv;
        int i;
    CODE:
        Newxz(qc, 1, PageCamel_QUIC_Connection);

        /* Parse named parameters */
        for (i = 1; i < items; i += 2) {
            const char *key;
            SV *val;

            if (i + 1 >= items) {
                croak("Odd number of arguments");
            }

            key = SvPV_nolen(ST(i));
            val = ST(i + 1);

            if (strEQ(key, "dcid")) {
                if (!sv_derived_from(val, "PageCamel::XS::NGTCP2::CID")) {
                    croak("dcid must be a PageCamel::XS::NGTCP2::CID object");
                }
                dcid = INT2PTR(PageCamel_CID *, SvIV((SV*)SvRV(val)));
            }
            else if (strEQ(key, "scid")) {
                if (!sv_derived_from(val, "PageCamel::XS::NGTCP2::CID")) {
                    croak("scid must be a PageCamel::XS::NGTCP2::CID object");
                }
                scid = INT2PTR(PageCamel_CID *, SvIV((SV*)SvRV(val)));
            }
            else if (strEQ(key, "path")) {
                if (!sv_derived_from(val, "PageCamel::XS::NGTCP2::Path")) {
                    croak("path must be a PageCamel::XS::NGTCP2::Path object");
                }
                path = INT2PTR(PageCamel_Path *, SvIV((SV*)SvRV(val)));
            }
            else if (strEQ(key, "settings")) {
                if (!sv_derived_from(val, "PageCamel::XS::NGTCP2::Settings")) {
                    croak("settings must be a PageCamel::XS::NGTCP2::Settings object");
                }
                settings = INT2PTR(PageCamel_Settings *, SvIV((SV*)SvRV(val)));
            }
            else if (strEQ(key, "params")) {
                if (!sv_derived_from(val, "PageCamel::XS::NGTCP2::TransportParams")) {
                    croak("params must be a PageCamel::XS::NGTCP2::TransportParams object");
                }
                params = INT2PTR(PageCamel_TransportParams *, SvIV((SV*)SvRV(val)));
            }
            else if (strEQ(key, "version")) {
                version = (uint32_t)SvUV(val);
            }
            else if (strEQ(key, "on_recv_stream_data")) {
                qc->recv_stream_data_cb = newSVsv(val);
            }
            else if (strEQ(key, "on_stream_open")) {
                qc->stream_open_cb = newSVsv(val);
            }
            else if (strEQ(key, "on_stream_close")) {
                qc->stream_close_cb = newSVsv(val);
            }
            else if (strEQ(key, "on_acked_stream_data_offset")) {
                qc->acked_stream_data_offset_cb = newSVsv(val);
            }
            else if (strEQ(key, "on_handshake_completed")) {
                qc->handshake_completed_cb = newSVsv(val);
            }
            else if (strEQ(key, "on_path_validation")) {
                qc->path_validation_cb = newSVsv(val);
            }
            else if (strEQ(key, "ssl_domains")) {
                if (!SvROK(val) || SvTYPE(SvRV(val)) != SVt_PVHV) {
                    croak("ssl_domains must be a hash reference");
                }
                ssl_domains_sv = val;
            }
            else if (strEQ(key, "default_domain")) {
                default_domain = SvPV_nolen(val);
            }
        }

        if (!dcid || !scid || !path || !settings || !params) {
            Safefree(qc);
            croak("server_new requires dcid, scid, path, settings, and params");
        }

        if (!ssl_domains_sv || !default_domain) {
            Safefree(qc);
            croak("server_new requires ssl_domains and default_domain for TLS");
        }

        /* Initialize certificate credentials */
        rv = gnutls_certificate_allocate_credentials(&cred);
        if (rv != GNUTLS_E_SUCCESS) {
            Safefree(qc);
            croak("gnutls_certificate_allocate_credentials failed: %s", gnutls_strerror(rv));
        }

        /* Parse ssl_domains hash and load all certificates */
        {
            HV *domains_hv = (HV *)SvRV(ssl_domains_sv);
            I32 num_domains = hv_iterinit(domains_hv);
            SV *domain_val;
            char *domain_key;
            I32 key_len;
            int domain_idx = 0;

            /* Allocate domains array */
            Newxz(qc->domains, num_domains, PageCamel_DomainCred);
            qc->domain_count = 0;
            qc->default_domain = strdup(default_domain);
            qc->selected_domain_idx = -1;

            while ((domain_val = hv_iternextsv(domains_hv, &domain_key, &key_len)) != NULL) {
                HV *domain_config;
                SV **cert_sv, **key_sv, **backend_sv;
                const char *cert_path, *key_path, *backend_path;

                if (!SvROK(domain_val) || SvTYPE(SvRV(domain_val)) != SVt_PVHV) {
                    continue;  /* Skip invalid entries */
                }

                domain_config = (HV *)SvRV(domain_val);

                /* Get certificate path */
                cert_sv = hv_fetch(domain_config, "sslcert", 7, 0);
                if (!cert_sv || !SvOK(*cert_sv)) {
                    continue;  /* Skip domains without cert */
                }
                cert_path = SvPV_nolen(*cert_sv);

                /* Get key path */
                key_sv = hv_fetch(domain_config, "sslkey", 6, 0);
                if (!key_sv || !SvOK(*key_sv)) {
                    continue;  /* Skip domains without key */
                }
                key_path = SvPV_nolen(*key_sv);

                /* Get backend socket path (optional) */
                backend_sv = hv_fetch(domain_config, "internal_socket", 15, 0);
                backend_path = (backend_sv && SvOK(*backend_sv)) ? SvPV_nolen(*backend_sv) : NULL;

                /* Load certificate into credentials */
                rv = gnutls_certificate_set_x509_key_file(cred, cert_path, key_path, GNUTLS_X509_FMT_PEM);
                if (rv < 0) {
                    warn("Failed to load certificate for %s: %s", domain_key, gnutls_strerror(rv));
                    continue;
                }

                /* Store domain info for backend routing */
                qc->domains[domain_idx].domain = strdup(domain_key);
                qc->domains[domain_idx].cred = NULL;  /* Using shared credentials */
                qc->domains[domain_idx].backend_socket = backend_path ? strdup(backend_path) : NULL;
                domain_idx++;
                qc->domain_count = domain_idx;
            }

            if (qc->domain_count == 0) {
                gnutls_certificate_free_credentials(cred);
                Safefree(qc->domains);
                Safefree(qc);
                croak("No valid SSL domains configured");
            }
        }

        /* Initialize GnuTLS session for server */
        /* Use simpler flags - GNUTLS_NO_AUTO_REKEY is important for QUIC */
        rv = gnutls_init(&qc->session, GNUTLS_SERVER | GNUTLS_NO_AUTO_REKEY);
        if (rv != GNUTLS_E_SUCCESS) {
            gnutls_certificate_free_credentials(cred);
            Safefree(qc);
            croak("gnutls_init failed: %s", gnutls_strerror(rv));
        }

        /* Set up connection reference for ngtcp2_crypto callbacks */
        qc->conn_ref.get_conn = get_conn_callback;
        qc->conn_ref.user_data = qc;
        gnutls_session_set_ptr(qc->session, &qc->conn_ref);

        /* Set credentials on the session */
        rv = gnutls_credentials_set(qc->session, GNUTLS_CRD_CERTIFICATE, cred);
        if (rv != GNUTLS_E_SUCCESS) {
            gnutls_deinit(qc->session);
            gnutls_certificate_free_credentials(cred);
            Safefree(qc);
            croak("gnutls_credentials_set failed: %s", gnutls_strerror(rv));
        }

        /* Store credentials for cleanup */
        qc->shared_cred = cred;

        /* Set default priority (TLS 1.3 required for QUIC) - simplified string */
        rv = gnutls_priority_set_direct(qc->session, "NORMAL:-VERS-ALL:+VERS-TLS1.3", NULL);
        if (rv != GNUTLS_E_SUCCESS) {
            gnutls_deinit(qc->session);
            Safefree(qc);
            croak("gnutls_priority_set_direct failed: %s", gnutls_strerror(rv));
        }

        /* Set ALPN for HTTP/3 */
        {
            gnutls_datum_t alpn = { (unsigned char *)"h3", 2 };
            gnutls_alpn_set_protocols(qc->session, &alpn, 1, 0);
        }

        /* Set up callbacks - crypto callbacks from ngtcp2_crypto_gnutls */
        memset(&callbacks, 0, sizeof(callbacks));

        /* Random number generator - required */
        callbacks.rand = rand_callback;

        /* Required crypto callbacks from ngtcp2_crypto library */
        rv = ngtcp2_crypto_gnutls_configure_server_session(qc->session);
        if (rv != 0) {
            fprintf(stderr, "NGTCP2: ngtcp2_crypto_gnutls_configure_server_session failed: %d\n", rv);
            gnutls_deinit(qc->session);
            gnutls_certificate_free_credentials(cred);
            Safefree(qc);
            croak("ngtcp2_crypto_gnutls_configure_server_session failed");
        }
        fprintf(stderr, "NGTCP2: crypto session configured successfully\n");
        callbacks.recv_client_initial = recv_client_initial_wrapper;
        callbacks.recv_crypto_data = recv_crypto_data_wrapper;
        callbacks.encrypt = ngtcp2_crypto_encrypt_cb;
        callbacks.decrypt = ngtcp2_crypto_decrypt_cb;
        callbacks.hp_mask = ngtcp2_crypto_hp_mask_cb;
        callbacks.update_key = ngtcp2_crypto_update_key_cb;
        callbacks.delete_crypto_aead_ctx = ngtcp2_crypto_delete_crypto_aead_ctx_cb;
        callbacks.delete_crypto_cipher_ctx = ngtcp2_crypto_delete_crypto_cipher_ctx_cb;
        callbacks.get_path_challenge_data = ngtcp2_crypto_get_path_challenge_data_cb;
        callbacks.version_negotiation = ngtcp2_crypto_version_negotiation_cb;

        /* Connection ID management - required */
        callbacks.get_new_connection_id = get_new_connection_id_callback;

        /* Application-level callbacks (trampolines to Perl) */
        callbacks.recv_stream_data = recv_stream_data_trampoline;
        callbacks.stream_open = stream_open_trampoline;
        callbacks.stream_close = stream_close_trampoline;
        callbacks.acked_stream_data_offset = acked_stream_data_offset_trampoline;
        callbacks.handshake_completed = handshake_completed_trampoline;
        callbacks.path_validation = path_validation_trampoline;

        /* Debug: show transport params */
        fprintf(stderr, "NGTCP2: server_new transport params:\n");
        fprintf(stderr, "  original_dcid.datalen=%zu\n", params->params.original_dcid.datalen);
        fprintf(stderr, "  initial_scid.datalen=%zu\n", params->params.initial_scid.datalen);
        fprintf(stderr, "  initial_max_data=%lu\n", (unsigned long)params->params.initial_max_data);
        fprintf(stderr, "  initial_max_streams_bidi=%lu\n", (unsigned long)params->params.initial_max_streams_bidi);
        fprintf(stderr, "  dcid param len=%zu, scid param len=%zu\n", dcid->cid.datalen, scid->cid.datalen);

        /* Create the ngtcp2 connection */
        rv = ngtcp2_conn_server_new(
            &qc->conn,
            &dcid->cid,
            &scid->cid,
            &path->path,
            version,
            &callbacks,
            &settings->settings,
            &params->params,
            NULL,  /* mem */
            qc     /* user_data */
        );

        if (rv != 0) {
            gnutls_deinit(qc->session);
            gnutls_certificate_free_credentials(qc->shared_cred);
            Safefree(qc);
            croak("ngtcp2_conn_server_new failed: %s", ngtcp2_strerror(rv));
        }

        fprintf(stderr, "NGTCP2: server_new succeeded, conn=%p, session=%p\n",
                (void*)qc->conn, (void*)qc->session);

        /* Link the GnuTLS session to the ngtcp2 connection - CRITICAL */
        ngtcp2_conn_set_tls_native_handle(qc->conn, qc->session);

        fprintf(stderr, "NGTCP2: TLS handle linked, conn_ref callback=%p\n",
                (void*)qc->conn_ref.get_conn);

        RETVAL = qc;
    OUTPUT:
        RETVAL

void
DESTROY(self)
        PageCamel_QUIC_Connection *self
    CODE:
        int i;
        if (self->conn) {
            ngtcp2_conn_del(self->conn);
        }
        if (self->recv_stream_data_cb) SvREFCNT_dec(self->recv_stream_data_cb);
        if (self->stream_open_cb) SvREFCNT_dec(self->stream_open_cb);
        if (self->stream_close_cb) SvREFCNT_dec(self->stream_close_cb);
        if (self->recv_datagram_cb) SvREFCNT_dec(self->recv_datagram_cb);
        if (self->acked_stream_data_offset_cb) SvREFCNT_dec(self->acked_stream_data_offset_cb);
        if (self->handshake_completed_cb) SvREFCNT_dec(self->handshake_completed_cb);
        if (self->path_validation_cb) SvREFCNT_dec(self->path_validation_cb);
        if (self->user_data) SvREFCNT_dec(self->user_data);
        if (self->session) gnutls_deinit(self->session);
        if (self->shared_cred) gnutls_certificate_free_credentials(self->shared_cred);
        /* Free domain info */
        if (self->domains) {
            for (i = 0; i < self->domain_count; i++) {
                if (self->domains[i].domain) free(self->domains[i].domain);
                if (self->domains[i].backend_socket) free(self->domains[i].backend_socket);
            }
            Safefree(self->domains);
        }
        if (self->default_domain) free(self->default_domain);
        if (self->negotiated_hostname) free(self->negotiated_hostname);
        Safefree(self);

# Get the negotiated hostname (SNI from client)
SV *
get_hostname(self)
        PageCamel_QUIC_Connection *self
    CODE:
        /* Try to capture SNI if not already done */
        if (!self->negotiated_hostname) {
            capture_sni_hostname(self);
        }
        if (self->negotiated_hostname) {
            RETVAL = newSVpv(self->negotiated_hostname, 0);
        } else {
            RETVAL = &PL_sv_undef;
        }
    OUTPUT:
        RETVAL

# Get the backend socket path for the negotiated domain
SV *
get_backend_socket(self)
        PageCamel_QUIC_Connection *self
    CODE:
        /* Try to capture SNI if not already done */
        if (!self->negotiated_hostname) {
            capture_sni_hostname(self);
        }
        if (self->selected_backend) {
            RETVAL = newSVpv(self->selected_backend, 0);
        } else {
            RETVAL = &PL_sv_undef;
        }
    OUTPUT:
        RETVAL

# Capture SNI hostname from TLS handshake
void
capture_sni(self)
        PageCamel_QUIC_Connection *self
    CODE:
        capture_sni_hostname(self);

# NOTE: Initial keys are derived automatically by ngtcp2_crypto_recv_client_initial_cb
# callback when read_pkt processes the first Initial packet. No manual key derivation
# is needed. The recv_client_initial callback is set up in server_new.

# Process incoming packet
IV
read_pkt(self, path, pkt, ts)
        PageCamel_QUIC_Connection *self
        PageCamel_Path *path
        SV *pkt
        UV ts
    CODE:
        STRLEN pktlen;
        const uint8_t *pktdata = (const uint8_t *)SvPVbyte(pkt, pktlen);
        ngtcp2_pkt_info pi;

        memset(&pi, 0, sizeof(pi));

        fprintf(stderr, "NGTCP2: read_pkt called, pktlen=%zu, ts=%lu\n", pktlen, (unsigned long)ts);

        RETVAL = ngtcp2_conn_read_pkt(
            self->conn,
            &path->path,
            &pi,
            pktdata,
            pktlen,
            (ngtcp2_tstamp)ts
        );
        fprintf(stderr, "NGTCP2: read_pkt returned %d (%s)\n", (int)RETVAL,
                RETVAL < 0 ? ngtcp2_strerror((int)RETVAL) : "OK");
    OUTPUT:
        RETVAL

# Write outgoing packets (loops until no more packets to send)
void
write_pkt(self, ts)
        PageCamel_QUIC_Connection *self
        UV ts
    PREINIT:
        uint8_t buf[NGTCP2_MAX_UDP_PAYLOAD_SIZE];
        ngtcp2_path_storage ps;
        ngtcp2_pkt_info pi;
        ngtcp2_ssize nwrite;
        int packet_count = 0;
    PPCODE:
        fprintf(stderr, "NGTCP2: write_pkt called, ts=%lu\n", (unsigned long)ts);

        /* Loop to get all available packets */
        while (1) {
            ngtcp2_path_storage_zero(&ps);

            nwrite = ngtcp2_conn_write_pkt(
                self->conn,
                &ps.path,
                &pi,
                buf,
                sizeof(buf),
                (ngtcp2_tstamp)ts
            );

            fprintf(stderr, "NGTCP2: write_pkt iteration %d returned %zd\n", packet_count, nwrite);

            if (nwrite < 0) {
                /* Error */
                fprintf(stderr, "NGTCP2: write_pkt error: %s\n", ngtcp2_strerror((int)nwrite));
                break;
            }

            if (nwrite == 0) {
                /* No more packets to write */
                break;
            }

            /* Push packet data onto Perl stack */
            mXPUSHs(newSVpvn((const char *)buf, nwrite));
            packet_count++;

            /* Safety limit to prevent infinite loops */
            if (packet_count >= 100) {
                fprintf(stderr, "NGTCP2: write_pkt hit safety limit of 100 packets\n");
                break;
            }
        }

        fprintf(stderr, "NGTCP2: write_pkt returning %d packets\n", packet_count);

# Get connection expiry time
UV
get_expiry(self)
        PageCamel_QUIC_Connection *self
    CODE:
        RETVAL = ngtcp2_conn_get_expiry(self->conn);
    OUTPUT:
        RETVAL

# Handle timeout
IV
handle_expiry(self, ts)
        PageCamel_QUIC_Connection *self
        UV ts
    CODE:
        RETVAL = ngtcp2_conn_handle_expiry(self->conn, (ngtcp2_tstamp)ts);
    OUTPUT:
        RETVAL

# Check if handshake is completed
int
is_handshake_completed(self)
        PageCamel_QUIC_Connection *self
    CODE:
        RETVAL = ngtcp2_conn_get_handshake_completed(self->conn);
    OUTPUT:
        RETVAL

# Check if connection is in closing state
int
is_in_closing_period(self)
        PageCamel_QUIC_Connection *self
    CODE:
        RETVAL = ngtcp2_conn_is_in_closing_period(self->conn);
    OUTPUT:
        RETVAL

# Check if connection is in draining state
int
is_in_draining_period(self)
        PageCamel_QUIC_Connection *self
    CODE:
        RETVAL = ngtcp2_conn_is_in_draining_period(self->conn);
    OUTPUT:
        RETVAL

# Open bidirectional stream
IV
open_bidi_stream(self)
        PageCamel_QUIC_Connection *self
    PREINIT:
        int64_t stream_id;
        int rv;
    CODE:
        rv = ngtcp2_conn_open_bidi_stream(self->conn, &stream_id, NULL);
        if (rv != 0) {
            RETVAL = rv;
        } else {
            RETVAL = stream_id;
        }
    OUTPUT:
        RETVAL

# Open unidirectional stream
IV
open_uni_stream(self)
        PageCamel_QUIC_Connection *self
    PREINIT:
        int64_t stream_id;
        int rv;
    CODE:
        rv = ngtcp2_conn_open_uni_stream(self->conn, &stream_id, NULL);
        if (rv != 0) {
            RETVAL = rv;
        } else {
            RETVAL = stream_id;
        }
    OUTPUT:
        RETVAL

# Write stream data - returns packet data that MUST be sent via UDP
# Returns: ($packet_data) on success, () on error or nothing to send
void
write_stream(self, stream_id, data, ts, fin = 0)
        PageCamel_QUIC_Connection *self
        IV stream_id
        SV *data
        UV ts
        int fin
    PREINIT:
        STRLEN datalen;
        const uint8_t *dataptr;
        uint8_t buf[NGTCP2_MAX_UDP_PAYLOAD_SIZE];
        ngtcp2_path_storage ps;
        ngtcp2_pkt_info pi;
        ngtcp2_ssize nwrite;
        ngtcp2_ssize ndatalen;
        uint32_t flags = 0;
        ngtcp2_vec datavec;
    PPCODE:
        dataptr = (const uint8_t *)SvPVbyte(data, datalen);
        ngtcp2_path_storage_zero(&ps);

        if (fin) {
            flags |= NGTCP2_WRITE_STREAM_FLAG_FIN;
        }

        datavec.base = (uint8_t *)dataptr;
        datavec.len = datalen;

        nwrite = ngtcp2_conn_writev_stream(
            self->conn,
            &ps.path,
            &pi,
            buf,
            sizeof(buf),
            &ndatalen,
            flags,
            (int64_t)stream_id,
            &datavec,
            1,
            (ngtcp2_tstamp)ts
        );

        /* Return packet data if we have something to send */
        if (nwrite > 0) {
            mXPUSHs(newSVpvn((const char *)buf, nwrite));
        }
        /* On error or nothing to write, return empty list */

# Shutdown stream
IV
shutdown_stream(self, stream_id, app_error_code)
        PageCamel_QUIC_Connection *self
        IV stream_id
        UV app_error_code
    CODE:
        RETVAL = ngtcp2_conn_shutdown_stream(
            self->conn,
            (int64_t)stream_id,
            (uint64_t)app_error_code
        );
    OUTPUT:
        RETVAL

# Extend stream max offset (flow control)
IV
extend_max_stream_offset(self, stream_id, datalen)
        PageCamel_QUIC_Connection *self
        IV stream_id
        UV datalen
    CODE:
        RETVAL = ngtcp2_conn_extend_max_stream_offset(
            self->conn,
            (int64_t)stream_id,
            (uint64_t)datalen
        );
    OUTPUT:
        RETVAL

# Extend connection max offset (flow control)
void
extend_max_offset(self, datalen)
        PageCamel_QUIC_Connection *self
        UV datalen
    CODE:
        ngtcp2_conn_extend_max_offset(self->conn, (uint64_t)datalen);

# Initiate connection migration
IV
initiate_migration(self, path, ts)
        PageCamel_QUIC_Connection *self
        PageCamel_Path *path
        UV ts
    CODE:
        RETVAL = ngtcp2_conn_initiate_migration(
            self->conn,
            &path->path,
            (ngtcp2_tstamp)ts
        );
    OUTPUT:
        RETVAL

# Get number of active bidi streams
UV
get_num_scid(self)
        PageCamel_QUIC_Connection *self
    CODE:
        RETVAL = ngtcp2_conn_get_num_scid(self->conn);
    OUTPUT:
        RETVAL

# Get negotiated QUIC version
UV
get_negotiated_version(self)
        PageCamel_QUIC_Connection *self
    CODE:
        RETVAL = ngtcp2_conn_get_negotiated_version(self->conn);
    OUTPUT:
        RETVAL
