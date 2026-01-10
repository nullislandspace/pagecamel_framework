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

/* Per-stream body data buffer for read_data callback */
typedef struct StreamDataBuffer {
    char *data;
    size_t len;
    size_t alloc;     /* Allocated size of buffer */
    size_t offset;    /* Amount already consumed by nghttp3 */
    int eof;          /* Set when all data has been queued */
    int64_t stream_id;
    struct StreamDataBuffer *next;
} StreamDataBuffer;

/* Wrapper structure for HTTP/3 connection with Perl callback storage */
typedef struct {
    nghttp3_conn *conn;
    SV *recv_header_cb;
    SV *end_headers_cb;
    SV *recv_data_cb;
    SV *end_stream_cb;
    SV *reset_stream_cb;
    SV *stop_sending_cb;
    SV *acked_stream_data_cb;  /* Called when data is ACKed */
    SV *user_data;

    /* Per-stream body data buffers (linked list) */
    StreamDataBuffer *stream_buffers;
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

static int acked_stream_data_trampoline(nghttp3_conn *conn, int64_t stream_id,
    uint64_t datalen, void *user_data, void *stream_user_data);

static nghttp3_ssize read_data_trampoline(nghttp3_conn *conn, int64_t stream_id,
    nghttp3_vec *vec, size_t veccnt, uint32_t *pflags,
    void *user_data, void *stream_user_data);

/* Track consumed body data offset per stream.
 * This is updated by acked_stream_data_trampoline when nghttp3 confirms data was sent. */
static size_t stream_consumed_offset[4096];  /* Simple array keyed by stream_id % 4096 */

/* Helper functions for stream buffer management */
static StreamDataBuffer *find_stream_buffer(PageCamel_HTTP3_Connection *h3c, int64_t stream_id) {
    StreamDataBuffer *buf = h3c->stream_buffers;
    while (buf) {
        if (buf->stream_id == stream_id) {
            return buf;
        }
        buf = buf->next;
    }
    return NULL;
}

static StreamDataBuffer *get_or_create_stream_buffer(PageCamel_HTTP3_Connection *h3c, int64_t stream_id) {
    StreamDataBuffer *buf = find_stream_buffer(h3c, stream_id);
    if (buf) {
        return buf;
    }

    /* Create new buffer */
    buf = (StreamDataBuffer *)malloc(sizeof(StreamDataBuffer));
    if (!buf) return NULL;

    buf->data = NULL;
    buf->len = 0;
    buf->alloc = 0;
    buf->offset = 0;
    buf->eof = 0;
    buf->stream_id = stream_id;
    buf->next = h3c->stream_buffers;
    h3c->stream_buffers = buf;

    return buf;
}

static void free_stream_buffer(PageCamel_HTTP3_Connection *h3c, int64_t stream_id) {
    StreamDataBuffer **prev = &h3c->stream_buffers;
    StreamDataBuffer *buf = h3c->stream_buffers;

    while (buf) {
        if (buf->stream_id == stream_id) {
            *prev = buf->next;
            if (buf->data) free(buf->data);
            free(buf);
            return;
        }
        prev = &buf->next;
        buf = buf->next;
    }
}

static void free_all_stream_buffers(PageCamel_HTTP3_Connection *h3c) {
    StreamDataBuffer *buf = h3c->stream_buffers;
    while (buf) {
        StreamDataBuffer *next = buf->next;
        if (buf->data) free(buf->data);
        free(buf);
        buf = next;
    }
    h3c->stream_buffers = NULL;
}

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

static int acked_stream_data_trampoline(nghttp3_conn *conn, int64_t stream_id,
    uint64_t datalen, void *user_data, void *stream_user_data)
{
    dTHX;
    PageCamel_HTTP3_Connection *h3c = (PageCamel_HTTP3_Connection *)user_data;
    size_t idx = stream_id % 4096;

    /* Advance the consumed offset - this is how many BODY bytes were ACKed.
     * This is the authoritative signal that data was consumed by nghttp3. */
    size_t old_offset = stream_consumed_offset[idx];
    stream_consumed_offset[idx] += datalen;
    fprintf(stderr, "NGHTTP3: acked_stream_data stream=%lld datalen=%llu offset %zu -> %zu\n",
            (long long)stream_id, (unsigned long long)datalen, old_offset, stream_consumed_offset[idx]);

    /* Also update the buffer's offset for cleanup tracking */
    StreamDataBuffer *buf = find_stream_buffer(h3c, stream_id);
    if (buf && buf->data) {
        buf->offset += datalen;

        /* If all data has been consumed and ACKed, free the buffer */
        if (buf->offset >= buf->len && buf->eof) {
            free_stream_buffer(h3c, stream_id);
        }
    }

    /* Call Perl callback if provided */
    if (h3c->acked_stream_data_cb && SvOK(h3c->acked_stream_data_cb)) {
        dSP;
        int count;
        int retval = 0;

        ENTER;
        SAVETMPS;

        PUSHMARK(SP);
        XPUSHs(sv_2mortal(newSViv(stream_id)));
        XPUSHs(sv_2mortal(newSVuv(datalen)));
        PUTBACK;

        count = call_sv(h3c->acked_stream_data_cb, G_SCALAR);

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

/* read_data callback - called by nghttp3 when it needs body data to send */
static nghttp3_ssize read_data_trampoline(nghttp3_conn *conn, int64_t stream_id,
    nghttp3_vec *vec, size_t veccnt, uint32_t *pflags,
    void *user_data, void *stream_user_data)
{
    PageCamel_HTTP3_Connection *h3c = (PageCamel_HTTP3_Connection *)user_data;
    size_t idx = stream_id % 4096;

    if (veccnt == 0) {
        return 0;
    }

    /* Find stream buffer */
    StreamDataBuffer *buf = find_stream_buffer(h3c, stream_id);

    if (!buf) {
        /* No buffer yet - block until data arrives */
        return NGHTTP3_ERR_WOULDBLOCK;
    }

    /* Get consumed offset - updated by acked_stream_data_trampoline when data is ACKed */
    size_t consumed = stream_consumed_offset[idx];

    if (!buf->data || consumed >= buf->len) {
        /* No data available beyond what's been consumed */
        if (buf->eof) {
            /* Signal end of data */
            *pflags |= NGHTTP3_DATA_FLAG_EOF;
            return 0;
        }
        /* Block until more data arrives - caller should call resume_stream() */
        return NGHTTP3_ERR_WOULDBLOCK;
    }

    /* Return pointer to unconsumed data */
    size_t available = buf->len - consumed;
    vec[0].base = (uint8_t *)(buf->data + consumed);
    vec[0].len = available;

    /* Check for 15736 boundary crossing (corruption point) */
    size_t range_start = consumed;
    size_t range_end = consumed + available;
    if (range_start <= 15736 && range_end > 15736) {
        size_t offset_in_data = 15736 - consumed;
        uint8_t *p = (uint8_t *)(buf->data + consumed);
        fprintf(stderr, "NGHTTP3: *** READ BOUNDARY 15736 *** stream=%lld consumed=%zu available=%zu buf->data=%p\n",
                (long long)stream_id, consumed, available, (void *)buf->data);
        if (offset_in_data >= 4 && offset_in_data + 8 <= available) {
            fprintf(stderr, "NGHTTP3: read bytes 15732-15751: [%02x %02x %02x %02x | %02x %02x %02x %02x | %02x %02x %02x %02x]\n",
                    p[offset_in_data - 4], p[offset_in_data - 3], p[offset_in_data - 2], p[offset_in_data - 1],
                    p[offset_in_data], p[offset_in_data + 1], p[offset_in_data + 2], p[offset_in_data + 3],
                    p[offset_in_data + 4], p[offset_in_data + 5], p[offset_in_data + 6], p[offset_in_data + 7]);
        }
    }

    fprintf(stderr, "NGHTTP3: read_data stream=%lld consumed=%zu available=%zu buf->len=%zu\n",
            (long long)stream_id, consumed, available, buf->len);

    /* CRITICAL: Advance consumed offset NOW.
     * nghttp3 keeps its own copy of data for retransmission.
     * If we don't advance, next read_data call returns same data,
     * causing nghttp3 to create duplicate DATA frames. */
    stream_consumed_offset[idx] = consumed + available;
    fprintf(stderr, "NGHTTP3: read_data advancing consumed %zu -> %zu\n",
            consumed, stream_consumed_offset[idx]);

    /* Check if this is all the data */
    if (buf->eof) {
        *pflags |= NGHTTP3_DATA_FLAG_EOF;
    }

    return 1;  /* Number of vectors filled */
}

/* Static data reader that uses our trampoline */
static nghttp3_data_reader body_data_reader = {
    read_data_trampoline
};


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
            else if (strEQ(key, "on_acked_stream_data")) {
                h3c->acked_stream_data_cb = newSVsv(val);
            }
        }

        /* Initialize stream buffers list */
        h3c->stream_buffers = NULL;

        /* Set up callbacks */
        memset(&callbacks, 0, sizeof(callbacks));
        callbacks.recv_header = recv_header_trampoline;
        callbacks.end_headers = end_headers_trampoline;
        callbacks.recv_data = recv_data_trampoline;
        callbacks.end_stream = end_stream_trampoline;
        callbacks.reset_stream = reset_stream_trampoline;
        callbacks.stop_sending = stop_sending_trampoline;
        callbacks.acked_stream_data = acked_stream_data_trampoline;

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
        /* Free all stream buffers first */
        free_all_stream_buffers(self);

        if (self->conn) {
            nghttp3_conn_del(self->conn);
        }
        if (self->recv_header_cb) SvREFCNT_dec(self->recv_header_cb);
        if (self->end_headers_cb) SvREFCNT_dec(self->end_headers_cb);
        if (self->recv_data_cb) SvREFCNT_dec(self->recv_data_cb);
        if (self->end_stream_cb) SvREFCNT_dec(self->end_stream_cb);
        if (self->reset_stream_cb) SvREFCNT_dec(self->reset_stream_cb);
        if (self->stop_sending_cb) SvREFCNT_dec(self->stop_sending_cb);
        if (self->acked_stream_data_cb) SvREFCNT_dec(self->acked_stream_data_cb);
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

            fprintf(stderr, "NGHTTP3: writev_stream stream=%lld vcnt=%d total=%zu fin=%d\n",
                    (long long)pstream_id, vcnt, total_len, fin);

            /* Debug: dump first few bytes of each vec to see structure */
            if (vcnt > 0 && total_len > 100) {
                fprintf(stderr, "NGHTTP3: writev vecs: ");
                for (i = 0; i < vcnt; i++) {
                    if (vec[i].len > 0) {
                        fprintf(stderr, "[v%d len=%zu first4=%02x%02x%02x%02x] ",
                                i, vec[i].len,
                                ((uint8_t *)vec[i].base)[0],
                                vec[i].len > 1 ? ((uint8_t *)vec[i].base)[1] : 0,
                                vec[i].len > 2 ? ((uint8_t *)vec[i].base)[2] : 0,
                                vec[i].len > 3 ? ((uint8_t *)vec[i].base)[3] : 0);
                    }
                }
                fprintf(stderr, "\n");
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
        /* Tell nghttp3 that n bytes were written to QUIC */
        RETVAL = nghttp3_conn_add_write_offset(self->conn, (int64_t)stream_id, (size_t)n);

        /* NOTE: We do NOT call add_ack_offset here anymore.
         * Calling it immediately caused nghttp3 to return duplicate data in writev_stream
         * because it thought data was ACKed before read_data returned it.
         *
         * For now, we track consumed offset ourselves in read_data based on what
         * nghttp3 actually reads from our buffer. The acked_stream_data callback
         * will be called by nghttp3 based on add_write_offset alone for cleanup. */
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

# Submit HTTP/3 response with body data reader
# Use this instead of submit_response when you plan to send body data
IV
submit_response_with_body(self, stream_id, headers_ref)
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

        /* Initialize consumed offset for this stream */
        stream_consumed_offset[stream_id % 4096] = 0;

        /* Create empty stream buffer - data will be added via set_stream_body_data */
        get_or_create_stream_buffer(self, stream_id);

        /* Submit response WITH data_reader - nghttp3 will call read_data_trampoline */
        rv = nghttp3_conn_submit_response(
            self->conn,
            (int64_t)stream_id,
            nva,
            nvlen,
            &body_data_reader
        );

        Safefree(nva);
        RETVAL = rv;
    OUTPUT:
        RETVAL

# Set/append body data for a stream
# Call this to push data to the stream buffer, then call resume_stream
IV
set_stream_body_data(self, stream_id, data)
        PageCamel_HTTP3_Connection *self
        IV stream_id
        SV *data
    PREINIT:
        STRLEN datalen;
        const char *dataptr;
        StreamDataBuffer *buf;
    CODE:
        dataptr = SvPVbyte(data, datalen);

        /* Debug: print info and check for 15736 boundary (corruption point) */
        {
            size_t prev_len = 0;
            StreamDataBuffer *existing = find_stream_buffer(self, stream_id);
            if (existing) prev_len = existing->len;
            size_t new_len = prev_len + datalen;

            /* Print boundary crossing details at 15736 */
            if (prev_len <= 15736 && new_len > 15736) {
                size_t offset_in_chunk = 15736 - prev_len;
                fprintf(stderr, "NGHTTP3: *** SET BOUNDARY 15736 *** stream=%lld prev=%zu add=%zu offset=%zu\n",
                        (long long)stream_id, prev_len, datalen, offset_in_chunk);
                if (offset_in_chunk + 8 <= datalen && offset_in_chunk >= 4) {
                    fprintf(stderr, "NGHTTP3: set bytes 15732-15751: [%02x %02x %02x %02x | %02x %02x %02x %02x | %02x %02x %02x %02x]\n",
                            (unsigned char)dataptr[offset_in_chunk - 4],
                            (unsigned char)dataptr[offset_in_chunk - 3],
                            (unsigned char)dataptr[offset_in_chunk - 2],
                            (unsigned char)dataptr[offset_in_chunk - 1],
                            (unsigned char)dataptr[offset_in_chunk],
                            (unsigned char)dataptr[offset_in_chunk + 1],
                            (unsigned char)dataptr[offset_in_chunk + 2],
                            (unsigned char)dataptr[offset_in_chunk + 3],
                            (unsigned char)dataptr[offset_in_chunk + 4],
                            (unsigned char)dataptr[offset_in_chunk + 5],
                            (unsigned char)dataptr[offset_in_chunk + 6],
                            (unsigned char)dataptr[offset_in_chunk + 7]);
                }
            }

            fprintf(stderr, "NGHTTP3: set_stream_body_data stream=%lld prev_len=%zu adding=%zu new_len=%zu\n",
                    (long long)stream_id, prev_len, datalen, new_len);
        }

        buf = get_or_create_stream_buffer(self, stream_id);
        if (!buf) {
            RETVAL = -1;  /* Memory allocation failed */
        }
        else {
            /* Append data to buffer.
             * IMPORTANT: We do NOT memmove/compact the buffer because nghttp3 may
             * internally cache pointers returned from read_data even after acked_stream_data.
             * Instead, we let the buffer grow and free_stream_buffer handles cleanup. */
            if (buf->data) {
                /* Check if we have enough pre-allocated space */
                if (buf->len + datalen <= buf->alloc) {
                    /* Fast path: no realloc needed */
                    memcpy(buf->data + buf->len, dataptr, datalen);
                    buf->len += datalen;
                    RETVAL = 0;
                }
                else {
                    /* Need to grow - this is unexpected with 2MB pre-alloc */
                    char *olddata = buf->data;
                    size_t newalloc = buf->alloc * 2;
                    if (newalloc < buf->len + datalen) {
                        newalloc = buf->len + datalen;
                    }
                    char *newdata = (char *)realloc(buf->data, newalloc);
                    if (!newdata) {
                        RETVAL = -1;
                    }
                    else {
                        fprintf(stderr, "NGHTTP3: set_stream_body_data stream=%lld REALLOC %p -> %p (alloc %zu -> %zu)\n",
                                (long long)stream_id, (void *)olddata, (void *)newdata, buf->alloc, newalloc);
                        memcpy(newdata + buf->len, dataptr, datalen);
                        buf->data = newdata;
                        buf->len += datalen;
                        buf->alloc = newalloc;
                        RETVAL = 0;
                    }
                }
            }
            else {
                /* First data for this stream - pre-allocate 2MB to avoid realloc */
                size_t initial_alloc = datalen > (2 * 1024 * 1024) ? datalen : (2 * 1024 * 1024);
                buf->data = (char *)malloc(initial_alloc);
                if (!buf->data) {
                    RETVAL = -1;
                }
                else {
                    memcpy(buf->data, dataptr, datalen);
                    buf->len = datalen;
                    buf->alloc = initial_alloc;  /* Track allocated size */
                    fprintf(stderr, "NGHTTP3: set_stream_body_data stream=%lld INITIAL alloc %zu bytes at %p\n",
                            (long long)stream_id, initial_alloc, (void *)buf->data);
                    RETVAL = 0;
                }
            }
        }
    OUTPUT:
        RETVAL

# Mark stream body as complete (EOF)
# Call this when all body data has been pushed
void
set_stream_eof(self, stream_id)
        PageCamel_HTTP3_Connection *self
        IV stream_id
    PREINIT:
        StreamDataBuffer *buf;
    CODE:
        buf = find_stream_buffer(self, stream_id);
        if (buf) {
            buf->eof = 1;
        }

# Clear stream buffer (for cleanup)
void
clear_stream_buffer(self, stream_id)
        PageCamel_HTTP3_Connection *self
        IV stream_id
    CODE:
        free_stream_buffer(self, stream_id);
        stream_consumed_offset[stream_id % 4096] = 0;

# Get amount of buffered data for a stream
UV
get_stream_buffer_size(self, stream_id)
        PageCamel_HTTP3_Connection *self
        IV stream_id
    PREINIT:
        StreamDataBuffer *buf;
    CODE:
        buf = find_stream_buffer(self, stream_id);
        if (buf && buf->data) {
            size_t consumed = stream_consumed_offset[stream_id % 4096];
            RETVAL = (buf->len > consumed) ? (buf->len - consumed) : 0;
        }
        else {
            RETVAL = 0;
        }
    OUTPUT:
        RETVAL
