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
#include <string.h>
#include <time.h>

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
    gnutls_certificate_credentials_t cred;
    gnutls_session_t session;
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

/* Callback implementations that call back to Perl */
static int recv_stream_data_trampoline(ngtcp2_conn *conn, uint32_t flags,
    int64_t stream_id, uint64_t offset, const uint8_t *data, size_t datalen,
    void *user_data, void *stream_user_data)
{
    dTHX;
    PageCamel_QUIC_Connection *qc = (PageCamel_QUIC_Connection *)user_data;

    if (qc->recv_stream_data_cb && SvOK(qc->recv_stream_data_cb)) {
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

        return retval;
    }

    return 0;
}

static int stream_open_trampoline(ngtcp2_conn *conn, int64_t stream_id,
    void *user_data)
{
    dTHX;
    PageCamel_QUIC_Connection *qc = (PageCamel_QUIC_Connection *)user_data;

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
        }

        if (!dcid || !scid || !path || !settings || !params) {
            Safefree(qc);
            croak("server_new requires dcid, scid, path, settings, and params");
        }

        /* Set up callbacks */
        memset(&callbacks, 0, sizeof(callbacks));
        callbacks.recv_stream_data = recv_stream_data_trampoline;
        callbacks.stream_open = stream_open_trampoline;
        callbacks.stream_close = stream_close_trampoline;
        callbacks.acked_stream_data_offset = acked_stream_data_offset_trampoline;
        callbacks.handshake_completed = handshake_completed_trampoline;
        callbacks.path_validation = path_validation_trampoline;

        /* Create the ngtcp2 connection - full implementation would include TLS setup */
        /* This is a placeholder - actual implementation needs ngtcp2_crypto integration */
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
            Safefree(qc);
            croak("ngtcp2_conn_server_new failed: %s", ngtcp2_strerror(rv));
        }

        RETVAL = qc;
    OUTPUT:
        RETVAL

void
DESTROY(self)
        PageCamel_QUIC_Connection *self
    CODE:
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
        if (self->cred) gnutls_certificate_free_credentials(self->cred);
        Safefree(self);

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

        RETVAL = ngtcp2_conn_read_pkt(
            self->conn,
            &path->path,
            &pi,
            pktdata,
            pktlen,
            (ngtcp2_tstamp)ts
        );
    OUTPUT:
        RETVAL

# Write outgoing packets
void
write_pkt(self, ts)
        PageCamel_QUIC_Connection *self
        UV ts
    PREINIT:
        uint8_t buf[NGTCP2_MAX_UDP_PAYLOAD_SIZE];
        ngtcp2_path_storage ps;
        ngtcp2_pkt_info pi;
        ngtcp2_ssize nwrite;
    PPCODE:
        ngtcp2_path_storage_zero(&ps);

        nwrite = ngtcp2_conn_write_pkt(
            self->conn,
            &ps.path,
            &pi,
            buf,
            sizeof(buf),
            (ngtcp2_tstamp)ts
        );

        if (nwrite > 0) {
            mXPUSHs(newSVpvn((const char *)buf, nwrite));
        }

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

# Write stream data
IV
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
    CODE:
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

        RETVAL = nwrite;
    OUTPUT:
        RETVAL

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
