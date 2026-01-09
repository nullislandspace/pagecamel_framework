/*
 * PageCamel::XS::NGHTTP3 - XS bindings for nghttp3 HTTP/3 library
 *
 * This module provides Perl bindings to nghttp3 for HTTP/3 protocol support.
 */

#define PERL_NO_GET_CONTEXT
#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

#include <nghttp3/nghttp3.h>
#include <string.h>
#include <stdlib.h>

/* Wrapper structure for HTTP/3 connection with Perl callback storage */
typedef struct {
    nghttp3_conn *conn;
    SV *recv_header_cb;
    SV *end_headers_cb;
    SV *recv_data_cb;
    SV *end_stream_cb;
    SV *reset_stream_cb;
    SV *stop_sending_cb;
    SV *user_data;
} PageCamel_HTTP3_Connection;

/* Wrapper for settings */
typedef struct {
    nghttp3_settings settings;
} PageCamel_HTTP3_Settings;

/* Wrapper for name-value pair (header) */
typedef struct {
    nghttp3_nv nv;
    char *name_buf;
    char *value_buf;
} PageCamel_HTTP3_NV;

/* Forward declarations for callback trampolines */
static int recv_header_trampoline(nghttp3_conn *conn, int64_t stream_id,
    int32_t token, nghttp3_rcbuf *name, nghttp3_rcbuf *value, uint8_t flags,
    void *user_data, void *stream_user_data);

static int end_headers_trampoline(nghttp3_conn *conn, int64_t stream_id,
    int fin, void *user_data, void *stream_user_data);

static int recv_data_trampoline(nghttp3_conn *conn, int64_t stream_id,
    const uint8_t *data, size_t datalen, void *user_data, void *stream_user_data);

static int end_stream_trampoline(nghttp3_conn *conn, int64_t stream_id,
    void *user_data, void *stream_user_data);

static int reset_stream_trampoline(nghttp3_conn *conn, int64_t stream_id,
    uint64_t app_error_code, void *user_data, void *stream_user_data);

static int stop_sending_trampoline(nghttp3_conn *conn, int64_t stream_id,
    uint64_t app_error_code, void *user_data, void *stream_user_data);

/* Callback implementations */
static int recv_header_trampoline(nghttp3_conn *conn, int64_t stream_id,
    int32_t token, nghttp3_rcbuf *name, nghttp3_rcbuf *value, uint8_t flags,
    void *user_data, void *stream_user_data)
{
    dTHX;
    PageCamel_HTTP3_Connection *h3c = (PageCamel_HTTP3_Connection *)user_data;

    if (h3c->recv_header_cb && SvOK(h3c->recv_header_cb)) {
        dSP;
        int count;
        int retval = 0;
        nghttp3_vec name_vec = nghttp3_rcbuf_get_buf(name);
        nghttp3_vec value_vec = nghttp3_rcbuf_get_buf(value);

        ENTER;
        SAVETMPS;

        PUSHMARK(SP);
        XPUSHs(sv_2mortal(newSViv(stream_id)));
        XPUSHs(sv_2mortal(newSVpvn((const char *)name_vec.base, name_vec.len)));
        XPUSHs(sv_2mortal(newSVpvn((const char *)value_vec.base, value_vec.len)));
        XPUSHs(sv_2mortal(newSVuv(flags)));
        PUTBACK;

        count = call_sv(h3c->recv_header_cb, G_SCALAR);

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

static int end_headers_trampoline(nghttp3_conn *conn, int64_t stream_id,
    int fin, void *user_data, void *stream_user_data)
{
    dTHX;
    PageCamel_HTTP3_Connection *h3c = (PageCamel_HTTP3_Connection *)user_data;

    if (h3c->end_headers_cb && SvOK(h3c->end_headers_cb)) {
        dSP;
        int count;
        int retval = 0;

        ENTER;
        SAVETMPS;

        PUSHMARK(SP);
        XPUSHs(sv_2mortal(newSViv(stream_id)));
        XPUSHs(sv_2mortal(newSViv(fin)));
        PUTBACK;

        count = call_sv(h3c->end_headers_cb, G_SCALAR);

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

static int recv_data_trampoline(nghttp3_conn *conn, int64_t stream_id,
    const uint8_t *data, size_t datalen, void *user_data, void *stream_user_data)
{
    dTHX;
    PageCamel_HTTP3_Connection *h3c = (PageCamel_HTTP3_Connection *)user_data;

    if (h3c->recv_data_cb && SvOK(h3c->recv_data_cb)) {
        dSP;
        int count;
        int retval = 0;

        ENTER;
        SAVETMPS;

        PUSHMARK(SP);
        XPUSHs(sv_2mortal(newSViv(stream_id)));
        XPUSHs(sv_2mortal(newSVpvn((const char *)data, datalen)));
        PUTBACK;

        count = call_sv(h3c->recv_data_cb, G_SCALAR);

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

static int end_stream_trampoline(nghttp3_conn *conn, int64_t stream_id,
    void *user_data, void *stream_user_data)
{
    dTHX;
    PageCamel_HTTP3_Connection *h3c = (PageCamel_HTTP3_Connection *)user_data;

    if (h3c->end_stream_cb && SvOK(h3c->end_stream_cb)) {
        dSP;
        int count;
        int retval = 0;

        ENTER;
        SAVETMPS;

        PUSHMARK(SP);
        XPUSHs(sv_2mortal(newSViv(stream_id)));
        PUTBACK;

        count = call_sv(h3c->end_stream_cb, G_SCALAR);

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

static int reset_stream_trampoline(nghttp3_conn *conn, int64_t stream_id,
    uint64_t app_error_code, void *user_data, void *stream_user_data)
{
    dTHX;
    PageCamel_HTTP3_Connection *h3c = (PageCamel_HTTP3_Connection *)user_data;

    if (h3c->reset_stream_cb && SvOK(h3c->reset_stream_cb)) {
        dSP;
        int count;
        int retval = 0;

        ENTER;
        SAVETMPS;

        PUSHMARK(SP);
        XPUSHs(sv_2mortal(newSViv(stream_id)));
        XPUSHs(sv_2mortal(newSVuv(app_error_code)));
        PUTBACK;

        count = call_sv(h3c->reset_stream_cb, G_SCALAR);

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

static int stop_sending_trampoline(nghttp3_conn *conn, int64_t stream_id,
    uint64_t app_error_code, void *user_data, void *stream_user_data)
{
    dTHX;
    PageCamel_HTTP3_Connection *h3c = (PageCamel_HTTP3_Connection *)user_data;

    if (h3c->stop_sending_cb && SvOK(h3c->stop_sending_cb)) {
        dSP;
        int count;
        int retval = 0;

        ENTER;
        SAVETMPS;

        PUSHMARK(SP);
        XPUSHs(sv_2mortal(newSViv(stream_id)));
        XPUSHs(sv_2mortal(newSVuv(app_error_code)));
        PUTBACK;

        count = call_sv(h3c->stop_sending_cb, G_SCALAR);

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


MODULE = PageCamel::XS::NGHTTP3    PACKAGE = PageCamel::XS::NGHTTP3

PROTOTYPES: DISABLE

# Return library version string
const char *
version()
    CODE:
        RETVAL = nghttp3_version(0)->version_str;
    OUTPUT:
        RETVAL

# Convert error code to string
const char *
strerror(error_code)
        IV error_code
    CODE:
        RETVAL = nghttp3_strerror((int)error_code);
    OUTPUT:
        RETVAL

# QPACK constants
UV
NGHTTP3_QPACK_MAX_TABLE_CAPACITY()
    CODE:
        RETVAL = 4096;  /* Default QPACK max table capacity */
    OUTPUT:
        RETVAL

UV
NGHTTP3_QPACK_BLOCKED_STREAMS()
    CODE:
        RETVAL = 100;  /* Default blocked streams */
    OUTPUT:
        RETVAL

# HTTP/3 error codes
IV
NGHTTP3_H3_NO_ERROR()
    CODE:
        RETVAL = NGHTTP3_H3_NO_ERROR;
    OUTPUT:
        RETVAL

IV
NGHTTP3_H3_GENERAL_PROTOCOL_ERROR()
    CODE:
        RETVAL = NGHTTP3_H3_GENERAL_PROTOCOL_ERROR;
    OUTPUT:
        RETVAL

IV
NGHTTP3_H3_INTERNAL_ERROR()
    CODE:
        RETVAL = NGHTTP3_H3_INTERNAL_ERROR;
    OUTPUT:
        RETVAL

IV
NGHTTP3_H3_STREAM_CREATION_ERROR()
    CODE:
        RETVAL = NGHTTP3_H3_STREAM_CREATION_ERROR;
    OUTPUT:
        RETVAL

IV
NGHTTP3_H3_CLOSED_CRITICAL_STREAM()
    CODE:
        RETVAL = NGHTTP3_H3_CLOSED_CRITICAL_STREAM;
    OUTPUT:
        RETVAL

IV
NGHTTP3_H3_FRAME_UNEXPECTED()
    CODE:
        RETVAL = NGHTTP3_H3_FRAME_UNEXPECTED;
    OUTPUT:
        RETVAL

IV
NGHTTP3_H3_FRAME_ERROR()
    CODE:
        RETVAL = NGHTTP3_H3_FRAME_ERROR;
    OUTPUT:
        RETVAL

IV
NGHTTP3_H3_EXCESSIVE_LOAD()
    CODE:
        RETVAL = NGHTTP3_H3_EXCESSIVE_LOAD;
    OUTPUT:
        RETVAL

IV
NGHTTP3_H3_ID_ERROR()
    CODE:
        RETVAL = NGHTTP3_H3_ID_ERROR;
    OUTPUT:
        RETVAL

IV
NGHTTP3_H3_SETTINGS_ERROR()
    CODE:
        RETVAL = NGHTTP3_H3_SETTINGS_ERROR;
    OUTPUT:
        RETVAL

IV
NGHTTP3_H3_MISSING_SETTINGS()
    CODE:
        RETVAL = NGHTTP3_H3_MISSING_SETTINGS;
    OUTPUT:
        RETVAL

IV
NGHTTP3_H3_REQUEST_REJECTED()
    CODE:
        RETVAL = NGHTTP3_H3_REQUEST_REJECTED;
    OUTPUT:
        RETVAL

IV
NGHTTP3_H3_REQUEST_CANCELLED()
    CODE:
        RETVAL = NGHTTP3_H3_REQUEST_CANCELLED;
    OUTPUT:
        RETVAL

IV
NGHTTP3_H3_REQUEST_INCOMPLETE()
    CODE:
        RETVAL = NGHTTP3_H3_REQUEST_INCOMPLETE;
    OUTPUT:
        RETVAL

IV
NGHTTP3_H3_MESSAGE_ERROR()
    CODE:
        RETVAL = NGHTTP3_H3_MESSAGE_ERROR;
    OUTPUT:
        RETVAL

IV
NGHTTP3_H3_CONNECT_ERROR()
    CODE:
        RETVAL = NGHTTP3_H3_CONNECT_ERROR;
    OUTPUT:
        RETVAL

IV
NGHTTP3_H3_VERSION_FALLBACK()
    CODE:
        RETVAL = NGHTTP3_H3_VERSION_FALLBACK;
    OUTPUT:
        RETVAL

# Library error codes
IV
NGHTTP3_ERR_INVALID_ARGUMENT()
    CODE:
        RETVAL = NGHTTP3_ERR_INVALID_ARGUMENT;
    OUTPUT:
        RETVAL

IV
NGHTTP3_ERR_NOBUF()
    CODE:
        RETVAL = NGHTTP3_ERR_NOBUF;
    OUTPUT:
        RETVAL

IV
NGHTTP3_ERR_INVALID_STATE()
    CODE:
        RETVAL = NGHTTP3_ERR_INVALID_STATE;
    OUTPUT:
        RETVAL

IV
NGHTTP3_ERR_WOULDBLOCK()
    CODE:
        RETVAL = NGHTTP3_ERR_WOULDBLOCK;
    OUTPUT:
        RETVAL

IV
NGHTTP3_ERR_STREAM_NOT_FOUND()
    CODE:
        RETVAL = NGHTTP3_ERR_STREAM_NOT_FOUND;
    OUTPUT:
        RETVAL

IV
NGHTTP3_ERR_MALFORMED_HTTP_HEADER()
    CODE:
        RETVAL = NGHTTP3_ERR_MALFORMED_HTTP_HEADER;
    OUTPUT:
        RETVAL

IV
NGHTTP3_ERR_REMOVE_HTTP_HEADER()
    CODE:
        RETVAL = NGHTTP3_ERR_REMOVE_HTTP_HEADER;
    OUTPUT:
        RETVAL

IV
NGHTTP3_ERR_MALFORMED_HTTP_MESSAGING()
    CODE:
        RETVAL = NGHTTP3_ERR_MALFORMED_HTTP_MESSAGING;
    OUTPUT:
        RETVAL

IV
NGHTTP3_ERR_QPACK_FATAL()
    CODE:
        RETVAL = NGHTTP3_ERR_QPACK_FATAL;
    OUTPUT:
        RETVAL

IV
NGHTTP3_ERR_QPACK_HEADER_TOO_LARGE()
    CODE:
        RETVAL = NGHTTP3_ERR_QPACK_HEADER_TOO_LARGE;
    OUTPUT:
        RETVAL

# NGHTTP3_ERR_IGNORE_STREAM removed - not available in this version

IV
NGHTTP3_ERR_CONN_CLOSING()
    CODE:
        RETVAL = NGHTTP3_ERR_CONN_CLOSING;
    OUTPUT:
        RETVAL

IV
NGHTTP3_ERR_QPACK_DECOMPRESSION_FAILED()
    CODE:
        RETVAL = NGHTTP3_ERR_QPACK_DECOMPRESSION_FAILED;
    OUTPUT:
        RETVAL

IV
NGHTTP3_ERR_QPACK_ENCODER_STREAM_ERROR()
    CODE:
        RETVAL = NGHTTP3_ERR_QPACK_ENCODER_STREAM_ERROR;
    OUTPUT:
        RETVAL

IV
NGHTTP3_ERR_QPACK_DECODER_STREAM_ERROR()
    CODE:
        RETVAL = NGHTTP3_ERR_QPACK_DECODER_STREAM_ERROR;
    OUTPUT:
        RETVAL

IV
NGHTTP3_ERR_H3_FRAME_UNEXPECTED()
    CODE:
        RETVAL = NGHTTP3_ERR_H3_FRAME_UNEXPECTED;
    OUTPUT:
        RETVAL

IV
NGHTTP3_ERR_H3_FRAME_ERROR()
    CODE:
        RETVAL = NGHTTP3_ERR_H3_FRAME_ERROR;
    OUTPUT:
        RETVAL

IV
NGHTTP3_ERR_H3_MISSING_SETTINGS()
    CODE:
        RETVAL = NGHTTP3_ERR_H3_MISSING_SETTINGS;
    OUTPUT:
        RETVAL

IV
NGHTTP3_ERR_H3_INTERNAL_ERROR()
    CODE:
        RETVAL = NGHTTP3_ERR_H3_INTERNAL_ERROR;
    OUTPUT:
        RETVAL

IV
NGHTTP3_ERR_H3_CLOSED_CRITICAL_STREAM()
    CODE:
        RETVAL = NGHTTP3_ERR_H3_CLOSED_CRITICAL_STREAM;
    OUTPUT:
        RETVAL

IV
NGHTTP3_ERR_H3_GENERAL_PROTOCOL_ERROR()
    CODE:
        RETVAL = NGHTTP3_ERR_H3_GENERAL_PROTOCOL_ERROR;
    OUTPUT:
        RETVAL

IV
NGHTTP3_ERR_H3_ID_ERROR()
    CODE:
        RETVAL = NGHTTP3_ERR_H3_ID_ERROR;
    OUTPUT:
        RETVAL

IV
NGHTTP3_ERR_H3_SETTINGS_ERROR()
    CODE:
        RETVAL = NGHTTP3_ERR_H3_SETTINGS_ERROR;
    OUTPUT:
        RETVAL

IV
NGHTTP3_ERR_H3_STREAM_CREATION_ERROR()
    CODE:
        RETVAL = NGHTTP3_ERR_H3_STREAM_CREATION_ERROR;
    OUTPUT:
        RETVAL

IV
NGHTTP3_ERR_H3_MESSAGE_ERROR()
    CODE:
        RETVAL = NGHTTP3_H3_MESSAGE_ERROR;
    OUTPUT:
        RETVAL

IV
NGHTTP3_ERR_NOMEM()
    CODE:
        RETVAL = NGHTTP3_ERR_NOMEM;
    OUTPUT:
        RETVAL

IV
NGHTTP3_ERR_CALLBACK_FAILURE()
    CODE:
        RETVAL = NGHTTP3_ERR_CALLBACK_FAILURE;
    OUTPUT:
        RETVAL


MODULE = PageCamel::XS::NGHTTP3    PACKAGE = PageCamel::XS::NGHTTP3::Settings

# Create new settings object
PageCamel_HTTP3_Settings *
new(class)
        const char *class
    CODE:
        PageCamel_HTTP3_Settings *s;
        Newxz(s, 1, PageCamel_HTTP3_Settings);
        nghttp3_settings_default(&s->settings);
        RETVAL = s;
    OUTPUT:
        RETVAL

void
DESTROY(self)
        PageCamel_HTTP3_Settings *self
    CODE:
        Safefree(self);

void
set_max_field_section_size(self, size)
        PageCamel_HTTP3_Settings *self
        UV size
    CODE:
        self->settings.max_field_section_size = (uint64_t)size;

UV
get_max_field_section_size(self)
        PageCamel_HTTP3_Settings *self
    CODE:
        RETVAL = self->settings.max_field_section_size;
    OUTPUT:
        RETVAL

void
set_qpack_max_dtable_capacity(self, capacity)
        PageCamel_HTTP3_Settings *self
        UV capacity
    CODE:
        self->settings.qpack_max_dtable_capacity = (size_t)capacity;

void
set_qpack_blocked_streams(self, streams)
        PageCamel_HTTP3_Settings *self
        UV streams
    CODE:
        self->settings.qpack_blocked_streams = (size_t)streams;

void
set_enable_connect_protocol(self, enable)
        PageCamel_HTTP3_Settings *self
        int enable
    CODE:
        self->settings.enable_connect_protocol = enable ? 1 : 0;


MODULE = PageCamel::XS::NGHTTP3    PACKAGE = PageCamel::XS::NGHTTP3::Connection

# Create new server connection
PageCamel_HTTP3_Connection *
server_new(class, ...)
        const char *class
    PREINIT:
        PageCamel_HTTP3_Connection *h3c;
        PageCamel_HTTP3_Settings *settings = NULL;
        nghttp3_callbacks callbacks;
        int rv;
        int i;
    CODE:
        Newxz(h3c, 1, PageCamel_HTTP3_Connection);

        /* Parse named parameters */
        for (i = 1; i < items; i += 2) {
            const char *key;
            SV *val;

            if (i + 1 >= items) {
                croak("Odd number of arguments");
            }

            key = SvPV_nolen(ST(i));
            val = ST(i + 1);

            if (strEQ(key, "settings")) {
                if (!sv_derived_from(val, "PageCamel::XS::NGHTTP3::Settings")) {
                    croak("settings must be a PageCamel::XS::NGHTTP3::Settings object");
                }
                settings = INT2PTR(PageCamel_HTTP3_Settings *, SvIV((SV*)SvRV(val)));
            }
            else if (strEQ(key, "on_recv_header")) {
                h3c->recv_header_cb = newSVsv(val);
            }
            else if (strEQ(key, "on_end_headers")) {
                h3c->end_headers_cb = newSVsv(val);
            }
            else if (strEQ(key, "on_recv_data")) {
                h3c->recv_data_cb = newSVsv(val);
            }
            else if (strEQ(key, "on_end_stream")) {
                h3c->end_stream_cb = newSVsv(val);
            }
            else if (strEQ(key, "on_reset_stream")) {
                h3c->reset_stream_cb = newSVsv(val);
            }
            else if (strEQ(key, "on_stop_sending")) {
                h3c->stop_sending_cb = newSVsv(val);
            }
        }

        /* Set up callbacks */
        memset(&callbacks, 0, sizeof(callbacks));
        callbacks.recv_header = recv_header_trampoline;
        callbacks.end_headers = end_headers_trampoline;
        callbacks.recv_data = recv_data_trampoline;
        callbacks.end_stream = end_stream_trampoline;
        callbacks.reset_stream = reset_stream_trampoline;
        callbacks.stop_sending = stop_sending_trampoline;

        /* Create the nghttp3 server connection */
        rv = nghttp3_conn_server_new(
            &h3c->conn,
            &callbacks,
            settings ? &settings->settings : NULL,
            NULL,  /* mem */
            h3c    /* user_data */
        );

        if (rv != 0) {
            Safefree(h3c);
            croak("nghttp3_conn_server_new failed: %s", nghttp3_strerror(rv));
        }

        RETVAL = h3c;
    OUTPUT:
        RETVAL

void
DESTROY(self)
        PageCamel_HTTP3_Connection *self
    CODE:
        if (self->conn) {
            nghttp3_conn_del(self->conn);
        }
        if (self->recv_header_cb) SvREFCNT_dec(self->recv_header_cb);
        if (self->end_headers_cb) SvREFCNT_dec(self->end_headers_cb);
        if (self->recv_data_cb) SvREFCNT_dec(self->recv_data_cb);
        if (self->end_stream_cb) SvREFCNT_dec(self->end_stream_cb);
        if (self->reset_stream_cb) SvREFCNT_dec(self->reset_stream_cb);
        if (self->stop_sending_cb) SvREFCNT_dec(self->stop_sending_cb);
        if (self->user_data) SvREFCNT_dec(self->user_data);
        Safefree(self);

# Bind control streams (must be called after connection setup)
IV
bind_control_stream(self, stream_id)
        PageCamel_HTTP3_Connection *self
        IV stream_id
    CODE:
        RETVAL = nghttp3_conn_bind_control_stream(self->conn, (int64_t)stream_id);
    OUTPUT:
        RETVAL

# Bind QPACK streams - MUST be called with both encoder and decoder stream IDs together
IV
bind_qpack_streams(self, qenc_stream_id, qdec_stream_id)
        PageCamel_HTTP3_Connection *self
        IV qenc_stream_id
        IV qdec_stream_id
    CODE:
        RETVAL = nghttp3_conn_bind_qpack_streams(self->conn, (int64_t)qenc_stream_id, (int64_t)qdec_stream_id);
    OUTPUT:
        RETVAL

# Read stream data from QUIC
IV
read_stream(self, stream_id, data, fin)
        PageCamel_HTTP3_Connection *self
        IV stream_id
        SV *data
        int fin
    CODE:
        STRLEN datalen;
        const uint8_t *dataptr = (const uint8_t *)SvPVbyte(data, datalen);

        RETVAL = nghttp3_conn_read_stream(
            self->conn,
            (int64_t)stream_id,
            dataptr,
            datalen,
            fin
        );
    OUTPUT:
        RETVAL

# Get data to write to QUIC stream
void
writev_stream(self, stream_id)
        PageCamel_HTTP3_Connection *self
        IV stream_id
    PREINIT:
        nghttp3_vec vec[16];
        int vcnt;
        int64_t pstream_id = (int64_t)stream_id;
        int fin = 0;
        int i;
    PPCODE:
        vcnt = nghttp3_conn_writev_stream(
            self->conn,
            &pstream_id,
            &fin,
            vec,
            16
        );

        if (vcnt > 0) {
            SV *data_sv;
            size_t total_len = 0;
            char *buf;
            size_t offset = 0;

            /* Calculate total length */
            for (i = 0; i < vcnt; i++) {
                total_len += vec[i].len;
            }

            /* Create single buffer */
            data_sv = newSV(total_len);
            SvPOK_on(data_sv);
            SvCUR_set(data_sv, total_len);
            buf = SvPVX(data_sv);

            /* Copy all vectors */
            for (i = 0; i < vcnt; i++) {
                memcpy(buf + offset, vec[i].base, vec[i].len);
                offset += vec[i].len;
            }

            /* Return (actual_stream_id, data, fin) - nghttp3 may have changed pstream_id */
            mXPUSHi((IV)pstream_id);
            mXPUSHs(data_sv);
            mXPUSHi(fin);
        }

# Acknowledge sent data
IV
add_write_offset(self, stream_id, n)
        PageCamel_HTTP3_Connection *self
        IV stream_id
        UV n
    CODE:
        RETVAL = nghttp3_conn_add_write_offset(self->conn, (int64_t)stream_id, (size_t)n);
    OUTPUT:
        RETVAL

# Acknowledge received data (for flow control)
IV
add_ack_offset(self, stream_id, n)
        PageCamel_HTTP3_Connection *self
        IV stream_id
        UV n
    CODE:
        RETVAL = nghttp3_conn_add_ack_offset(self->conn, (int64_t)stream_id, (size_t)n);
    OUTPUT:
        RETVAL

# Submit HTTP/3 response
IV
submit_response(self, stream_id, headers_ref)
        PageCamel_HTTP3_Connection *self
        IV stream_id
        SV *headers_ref
    PREINIT:
        AV *headers_av;
        nghttp3_nv *nva;
        size_t nvlen;
        size_t i;
        int rv;
    CODE:
        if (!SvROK(headers_ref) || SvTYPE(SvRV(headers_ref)) != SVt_PVAV) {
            croak("headers must be an array reference");
        }

        headers_av = (AV *)SvRV(headers_ref);
        nvlen = (av_len(headers_av) + 1) / 2;

        if (nvlen == 0) {
            croak("headers array is empty");
        }

        Newxz(nva, nvlen, nghttp3_nv);

        for (i = 0; i < nvlen; i++) {
            SV **name_sv = av_fetch(headers_av, i * 2, 0);
            SV **value_sv = av_fetch(headers_av, i * 2 + 1, 0);
            STRLEN name_len, value_len;

            if (!name_sv || !value_sv) {
                Safefree(nva);
                croak("Invalid header at index %lu", (unsigned long)i);
            }

            nva[i].name = (uint8_t *)SvPV(*name_sv, name_len);
            nva[i].namelen = name_len;
            nva[i].value = (uint8_t *)SvPV(*value_sv, value_len);
            nva[i].valuelen = value_len;
            nva[i].flags = NGHTTP3_NV_FLAG_NONE;
        }

        rv = nghttp3_conn_submit_response(
            self->conn,
            (int64_t)stream_id,
            nva,
            nvlen,
            NULL  /* data_reader - we'll push data separately */
        );

        Safefree(nva);
        RETVAL = rv;
    OUTPUT:
        RETVAL

# Submit HTTP/3 trailers
IV
submit_trailers(self, stream_id, headers_ref)
        PageCamel_HTTP3_Connection *self
        IV stream_id
        SV *headers_ref
    PREINIT:
        AV *headers_av;
        nghttp3_nv *nva;
        size_t nvlen;
        size_t i;
        int rv;
    CODE:
        if (!SvROK(headers_ref) || SvTYPE(SvRV(headers_ref)) != SVt_PVAV) {
            croak("headers must be an array reference");
        }

        headers_av = (AV *)SvRV(headers_ref);
        nvlen = (av_len(headers_av) + 1) / 2;

        Newxz(nva, nvlen, nghttp3_nv);

        for (i = 0; i < nvlen; i++) {
            SV **name_sv = av_fetch(headers_av, i * 2, 0);
            SV **value_sv = av_fetch(headers_av, i * 2 + 1, 0);
            STRLEN name_len, value_len;

            if (!name_sv || !value_sv) {
                Safefree(nva);
                croak("Invalid header at index %lu", (unsigned long)i);
            }

            nva[i].name = (uint8_t *)SvPV(*name_sv, name_len);
            nva[i].namelen = name_len;
            nva[i].value = (uint8_t *)SvPV(*value_sv, value_len);
            nva[i].valuelen = value_len;
            nva[i].flags = NGHTTP3_NV_FLAG_NONE;
        }

        rv = nghttp3_conn_submit_trailers(
            self->conn,
            (int64_t)stream_id,
            nva,
            nvlen
        );

        Safefree(nva);
        RETVAL = rv;
    OUTPUT:
        RETVAL

# Check if stream is blocked
int
is_stream_writable(self, stream_id)
        PageCamel_HTTP3_Connection *self
        IV stream_id
    CODE:
        /* nghttp3 doesn't have a direct "is_writable" check,
           but we can check if there's pending data */
        RETVAL = 1;
    OUTPUT:
        RETVAL

# Shutdown stream read side
IV
shutdown_stream_read(self, stream_id)
        PageCamel_HTTP3_Connection *self
        IV stream_id
    CODE:
        RETVAL = nghttp3_conn_shutdown_stream_read(self->conn, (int64_t)stream_id);
    OUTPUT:
        RETVAL

# Shutdown stream write side
void
shutdown_stream_write(self, stream_id)
        PageCamel_HTTP3_Connection *self
        IV stream_id
    CODE:
        nghttp3_conn_shutdown_stream_write(self->conn, (int64_t)stream_id);

# Close stream with error
void
close_stream(self, stream_id, app_error_code)
        PageCamel_HTTP3_Connection *self
        IV stream_id
        UV app_error_code
    CODE:
        nghttp3_conn_close_stream(self->conn, (int64_t)stream_id, (uint64_t)app_error_code);

# Resume stream (after being blocked)
IV
resume_stream(self, stream_id)
        PageCamel_HTTP3_Connection *self
        IV stream_id
    CODE:
        RETVAL = nghttp3_conn_resume_stream(self->conn, (int64_t)stream_id);
    OUTPUT:
        RETVAL

# Set stream user data
void
set_stream_user_data(self, stream_id, user_data)
        PageCamel_HTTP3_Connection *self
        IV stream_id
        SV *user_data
    CODE:
        /* Store in connection's hash for later retrieval */
        nghttp3_conn_set_stream_user_data(
            self->conn,
            (int64_t)stream_id,
            SvREFCNT_inc(user_data)
        );

# Block stream (prevent reading/processing)
void
block_stream(self, stream_id)
        PageCamel_HTTP3_Connection *self
        IV stream_id
    CODE:
        nghttp3_conn_block_stream(self->conn, (int64_t)stream_id);

# Unblock stream
IV
unblock_stream(self, stream_id)
        PageCamel_HTTP3_Connection *self
        IV stream_id
    CODE:
        RETVAL = nghttp3_conn_unblock_stream(self->conn, (int64_t)stream_id);
    OUTPUT:
        RETVAL

# Check if the connection is draining
int
is_draining(self)
        PageCamel_HTTP3_Connection *self
    CODE:
        RETVAL = 0;  /* nghttp3 handles this at the QUIC layer */
    OUTPUT:
        RETVAL

# Get next stream ID to open for request (client) or push (server)
IV
get_next_stream_id(self)
        PageCamel_HTTP3_Connection *self
    CODE:
        /* For server, this would be for push streams */
        /* Return -1 to indicate push is not currently supported */
        RETVAL = -1;
    OUTPUT:
        RETVAL
