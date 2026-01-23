/*
 * HTTP3.xs - Minimal XS wrapper for PageCamel unified HTTP/3 library
 *
 * This wrapper exposes only the public API. All internal ngtcp2<->nghttp3
 * callbacks are handled in C, eliminating the Perl trampoline overhead
 * that caused data corruption.
 */

#define PERL_NO_GET_CONTEXT
#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

#include "src/h3_api.h"
#include <string.h>

/* Wrapper structure to hold Perl callbacks */
typedef struct {
    h3_connection_t *conn;
    SV *send_packet_cb;
    SV *on_request_cb;
    SV *on_request_body_cb;
    SV *on_stream_close_cb;
    SV *log_cb;
    char *local_addr;      /* Local address for this connection */
    int local_port;        /* Local port for this connection */
} PageCamel_H3_Wrapper;

/* Global Perl interpreter reference for callbacks */
static PerlInterpreter *my_perl;

/*
 * Callback trampolines from C to Perl
 * Only these cross the XS boundary - internal ngtcp2<->nghttp3 stays in C
 */

static int xs_send_packet_cb(void *user_data, const uint8_t *data, size_t len,
                             const h3_addr_info_t *addr) {
    dTHX;
    PageCamel_H3_Wrapper *wrapper = (PageCamel_H3_Wrapper *)user_data;
    int retval = -1;

    if (!wrapper || !wrapper->send_packet_cb || !SvOK(wrapper->send_packet_cb)) {
        return -1;
    }

    dSP;
    ENTER;
    SAVETMPS;

    PUSHMARK(SP);
    XPUSHs(sv_2mortal(newSVpvn((const char *)data, len)));
    XPUSHs(sv_2mortal(newSVpv(addr->remote_addr, 0)));
    XPUSHs(sv_2mortal(newSViv(addr->remote_port)));
    PUTBACK;

    int count = call_sv(wrapper->send_packet_cb, G_SCALAR);

    SPAGAIN;
    if (count == 1) {
        retval = POPi;
    }
    PUTBACK;

    FREETMPS;
    LEAVE;

    return retval;
}

static void xs_on_request_cb(void *user_data, int64_t stream_id,
                             const h3_header_t *headers, size_t header_count,
                             const uint8_t *body, size_t body_len,
                             int is_connect) {
    dTHX;
    PageCamel_H3_Wrapper *wrapper = (PageCamel_H3_Wrapper *)user_data;

    if (!wrapper || !wrapper->on_request_cb || !SvOK(wrapper->on_request_cb)) {
        return;
    }

    dSP;
    ENTER;
    SAVETMPS;

    /* Build headers array */
    AV *headers_av = newAV();
    for (size_t i = 0; i < header_count; i++) {
        av_push(headers_av, newSVpvn((const char *)headers[i].name, headers[i].name_len));
        av_push(headers_av, newSVpvn((const char *)headers[i].value, headers[i].value_len));
    }

    PUSHMARK(SP);
    XPUSHs(sv_2mortal(newSViv(stream_id)));
    XPUSHs(sv_2mortal(newRV_noinc((SV *)headers_av)));
    if (body && body_len > 0) {
        XPUSHs(sv_2mortal(newSVpvn((const char *)body, body_len)));
    } else {
        XPUSHs(&PL_sv_undef);
    }
    XPUSHs(sv_2mortal(newSViv(is_connect)));
    PUTBACK;

    call_sv(wrapper->on_request_cb, G_DISCARD);

    FREETMPS;
    LEAVE;
}

static void xs_on_request_body_cb(void *user_data, int64_t stream_id,
                                  const uint8_t *data, size_t len, int fin) {
    dTHX;
    PageCamel_H3_Wrapper *wrapper = (PageCamel_H3_Wrapper *)user_data;

    if (!wrapper || !wrapper->on_request_body_cb || !SvOK(wrapper->on_request_body_cb)) {
        return;
    }

    dSP;
    ENTER;
    SAVETMPS;

    PUSHMARK(SP);
    XPUSHs(sv_2mortal(newSViv(stream_id)));
    if (data && len > 0) {
        XPUSHs(sv_2mortal(newSVpvn((const char *)data, len)));
    } else {
        XPUSHs(&PL_sv_undef);
    }
    XPUSHs(sv_2mortal(newSViv(fin)));
    PUTBACK;

    call_sv(wrapper->on_request_body_cb, G_DISCARD);

    FREETMPS;
    LEAVE;
}

static void xs_on_stream_close_cb(void *user_data, int64_t stream_id,
                                  uint64_t app_error_code) {
    dTHX;
    PageCamel_H3_Wrapper *wrapper = (PageCamel_H3_Wrapper *)user_data;

    if (!wrapper || !wrapper->on_stream_close_cb || !SvOK(wrapper->on_stream_close_cb)) {
        return;
    }

    dSP;
    ENTER;
    SAVETMPS;

    PUSHMARK(SP);
    XPUSHs(sv_2mortal(newSViv(stream_id)));
    XPUSHs(sv_2mortal(newSVuv(app_error_code)));
    PUTBACK;

    call_sv(wrapper->on_stream_close_cb, G_DISCARD);

    FREETMPS;
    LEAVE;
}

MODULE = PageCamel::Protocol::HTTP3    PACKAGE = PageCamel::Protocol::HTTP3

PROTOTYPES: DISABLE

BOOT:
    my_perl = PERL_GET_THX;

# Library initialization
int
init()
    CODE:
        RETVAL = h3_init();
    OUTPUT:
        RETVAL

void
cleanup()
    CODE:
        h3_cleanup();

# Get library version
const char *
version()
    CODE:
        RETVAL = h3_version();
    OUTPUT:
        RETVAL

# Get current timestamp in nanoseconds
UV
timestamp_ns()
    CODE:
        RETVAL = h3_timestamp_ns();
    OUTPUT:
        RETVAL

# Convert error code to string
const char *
strerror(error_code)
        int error_code
    CODE:
        RETVAL = h3_strerror(error_code);
    OUTPUT:
        RETVAL

# Return code constants
int
H3_OK()
    CODE:
        RETVAL = H3_OK;
    OUTPUT:
        RETVAL

int
H3_WOULDBLOCK()
    CODE:
        RETVAL = H3_WOULDBLOCK;
    OUTPUT:
        RETVAL

int
H3_ERROR()
    CODE:
        RETVAL = H3_ERROR;
    OUTPUT:
        RETVAL

int
H3_ERROR_NOMEM()
    CODE:
        RETVAL = H3_ERROR_NOMEM;
    OUTPUT:
        RETVAL

int
H3_ERROR_INVALID()
    CODE:
        RETVAL = H3_ERROR_INVALID;
    OUTPUT:
        RETVAL

int
H3_ERROR_TLS()
    CODE:
        RETVAL = H3_ERROR_TLS;
    OUTPUT:
        RETVAL

int
H3_ERROR_QUIC()
    CODE:
        RETVAL = H3_ERROR_QUIC;
    OUTPUT:
        RETVAL

int
H3_ERROR_HTTP3()
    CODE:
        RETVAL = H3_ERROR_HTTP3;
    OUTPUT:
        RETVAL

int
H3_ERROR_STREAM()
    CODE:
        RETVAL = H3_ERROR_STREAM;
    OUTPUT:
        RETVAL

int
H3_ERROR_CLOSED()
    CODE:
        RETVAL = H3_ERROR_CLOSED;
    OUTPUT:
        RETVAL

# Connection state constants
int
H3_STATE_INITIAL()
    CODE:
        RETVAL = H3_STATE_INITIAL;
    OUTPUT:
        RETVAL

int
H3_STATE_HANDSHAKING()
    CODE:
        RETVAL = H3_STATE_HANDSHAKING;
    OUTPUT:
        RETVAL

int
H3_STATE_ESTABLISHED()
    CODE:
        RETVAL = H3_STATE_ESTABLISHED;
    OUTPUT:
        RETVAL

int
H3_STATE_DRAINING()
    CODE:
        RETVAL = H3_STATE_DRAINING;
    OUTPUT:
        RETVAL

int
H3_STATE_CLOSED()
    CODE:
        RETVAL = H3_STATE_CLOSED;
    OUTPUT:
        RETVAL


MODULE = PageCamel::Protocol::HTTP3    PACKAGE = PageCamel::Protocol::HTTP3::Connection

# Create new server connection
PageCamel_H3_Wrapper *
new_server(class, ...)
        const char *class
    PREINIT:
        PageCamel_H3_Wrapper *wrapper;
        h3_server_config_t config;
        h3_callbacks_t callbacks;
        h3_addr_info_t addr;
        h3_domain_config_t *domains = NULL;
        const uint8_t *dcid = NULL;
        size_t dcid_len = 0;
        const uint8_t *scid = NULL;
        size_t scid_len = 0;
        const uint8_t *original_dcid = NULL;
        size_t original_dcid_len = 0;
        uint32_t version = 1;  /* QUIC v1 */
        int i;
    CODE:
        wrapper = (PageCamel_H3_Wrapper *)calloc(1, sizeof(PageCamel_H3_Wrapper));
        if (!wrapper) {
            croak("Out of memory");
        }

        memset(&config, 0, sizeof(config));
        memset(&callbacks, 0, sizeof(callbacks));
        memset(&addr, 0, sizeof(addr));

        /* Parse named parameters */
        for (i = 1; i < items; i += 2) {
            const char *key;
            SV *val;

            if (i + 1 >= items) {
                free(wrapper);
                croak("Odd number of arguments");
            }

            key = SvPV_nolen(ST(i));
            val = ST(i + 1);

            if (strEQ(key, "dcid")) {
                STRLEN len;
                dcid = (const uint8_t *)SvPVbyte(val, len);
                dcid_len = len;
            }
            else if (strEQ(key, "scid")) {
                STRLEN len;
                scid = (const uint8_t *)SvPVbyte(val, len);
                scid_len = len;
            }
            else if (strEQ(key, "original_dcid")) {
                STRLEN len;
                original_dcid = (const uint8_t *)SvPVbyte(val, len);
                original_dcid_len = len;
            }
            else if (strEQ(key, "local_addr")) {
                addr.local_addr = SvPV_nolen(val);
                fprintf(stderr, "XS new_server: local_addr=%s\n", addr.local_addr);
            }
            else if (strEQ(key, "local_port")) {
                addr.local_port = SvIV(val);
                fprintf(stderr, "XS new_server: local_port=%d\n", addr.local_port);
            }
            else if (strEQ(key, "remote_addr")) {
                addr.remote_addr = SvPV_nolen(val);
                fprintf(stderr, "XS new_server: remote_addr=%s\n", addr.remote_addr);
            }
            else if (strEQ(key, "remote_port")) {
                addr.remote_port = SvIV(val);
                fprintf(stderr, "XS new_server: remote_port=%d\n", addr.remote_port);
            }
            else if (strEQ(key, "version")) {
                version = SvUV(val);
            }
            else if (strEQ(key, "default_domain")) {
                config.default_domain = SvPV_nolen(val);
            }
            else if (strEQ(key, "default_backend")) {
                config.default_backend = SvPV_nolen(val);
            }
            else if (strEQ(key, "initial_max_data")) {
                config.initial_max_data = SvUV(val);
            }
            else if (strEQ(key, "initial_max_stream_data_bidi")) {
                config.initial_max_stream_data_bidi = SvUV(val);
            }
            else if (strEQ(key, "initial_max_streams_bidi")) {
                config.initial_max_streams_bidi = SvUV(val);
            }
            else if (strEQ(key, "max_idle_timeout_ms")) {
                config.max_idle_timeout_ms = SvUV(val);
            }
            else if (strEQ(key, "cc_algo")) {
                config.cc_algo = SvIV(val);
            }
            else if (strEQ(key, "enable_debug")) {
                config.enable_debug = SvTRUE(val) ? 1 : 0;
            }
            else if (strEQ(key, "ssl_domains")) {
                /* Parse ssl_domains hash */
                if (!SvROK(val) || SvTYPE(SvRV(val)) != SVt_PVHV) {
                    free(wrapper);
                    croak("ssl_domains must be a hash reference");
                }
                HV *hv = (HV *)SvRV(val);
                I32 num_domains = hv_iterinit(hv);

                domains = (h3_domain_config_t *)calloc(num_domains, sizeof(h3_domain_config_t));
                config.domains = domains;

                SV *domain_val;
                char *domain_key;
                I32 key_len;
                int idx = 0;

                while ((domain_val = hv_iternextsv(hv, &domain_key, &key_len)) != NULL) {
                    if (!SvROK(domain_val) || SvTYPE(SvRV(domain_val)) != SVt_PVHV) {
                        continue;
                    }
                    HV *domain_hv = (HV *)SvRV(domain_val);

                    domains[idx].domain = domain_key;

                    SV **cert_sv = hv_fetch(domain_hv, "sslcert", 7, 0);
                    if (cert_sv && SvOK(*cert_sv)) {
                        domains[idx].cert_path = SvPV_nolen(*cert_sv);
                    }

                    SV **key_sv = hv_fetch(domain_hv, "sslkey", 6, 0);
                    if (key_sv && SvOK(*key_sv)) {
                        domains[idx].key_path = SvPV_nolen(*key_sv);
                    }

                    SV **backend_sv = hv_fetch(domain_hv, "internal_socket", 15, 0);
                    if (backend_sv && SvOK(*backend_sv)) {
                        domains[idx].backend_socket = SvPV_nolen(*backend_sv);
                    }

                    idx++;
                }
                config.domain_count = idx;
            }
            else if (strEQ(key, "on_send_packet")) {
                wrapper->send_packet_cb = newSVsv(val);
            }
            else if (strEQ(key, "on_request")) {
                wrapper->on_request_cb = newSVsv(val);
            }
            else if (strEQ(key, "on_request_body")) {
                wrapper->on_request_body_cb = newSVsv(val);
            }
            else if (strEQ(key, "on_stream_close")) {
                wrapper->on_stream_close_cb = newSVsv(val);
            }
        }

        if (!dcid || dcid_len == 0 || !scid || scid_len == 0 ||
            !original_dcid || original_dcid_len == 0) {
            free(domains);
            free(wrapper);
            croak("new_server requires dcid, scid, and original_dcid");
        }

        if (config.domain_count == 0) {
            free(domains);
            free(wrapper);
            croak("new_server requires ssl_domains");
        }

        /* Set up callbacks */
        callbacks.send_packet = xs_send_packet_cb;
        callbacks.on_request = xs_on_request_cb;
        callbacks.on_request_body = xs_on_request_body_cb;
        callbacks.on_stream_close = xs_on_stream_close_cb;
        callbacks.user_data = wrapper;

        /* Create connection */
        wrapper->conn = h3_connection_new_server(
            &config,
            &callbacks,
            dcid, dcid_len,
            scid, scid_len,
            original_dcid, original_dcid_len,
            &addr,
            version
        );

        free(domains);

        if (!wrapper->conn) {
            if (wrapper->send_packet_cb) SvREFCNT_dec(wrapper->send_packet_cb);
            if (wrapper->on_request_cb) SvREFCNT_dec(wrapper->on_request_cb);
            if (wrapper->on_request_body_cb) SvREFCNT_dec(wrapper->on_request_body_cb);
            if (wrapper->on_stream_close_cb) SvREFCNT_dec(wrapper->on_stream_close_cb);
            free(wrapper);
            croak("Failed to create HTTP/3 connection");
        }

        /* Store local address for packet processing */
        wrapper->local_addr = addr.local_addr ? strdup(addr.local_addr) : strdup("0.0.0.0");
        wrapper->local_port = addr.local_port;
        fprintf(stderr, "XS new_server: stored local=%s:%d\n", wrapper->local_addr, wrapper->local_port);

        RETVAL = wrapper;
    OUTPUT:
        RETVAL

void
DESTROY(self)
        PageCamel_H3_Wrapper *self
    CODE:
        if (self->conn) {
            h3_connection_free(self->conn);
        }
        if (self->send_packet_cb) SvREFCNT_dec(self->send_packet_cb);
        if (self->on_request_cb) SvREFCNT_dec(self->on_request_cb);
        if (self->on_request_body_cb) SvREFCNT_dec(self->on_request_body_cb);
        if (self->on_stream_close_cb) SvREFCNT_dec(self->on_stream_close_cb);
        if (self->local_addr) free(self->local_addr);
        if (self->log_cb) SvREFCNT_dec(self->log_cb);
        free(self);

# Process incoming packet
int
process_packet(self_sv, data, remote_addr, remote_port)
        SV *self_sv
        SV *data
        const char *remote_addr
        int remote_port
    PREINIT:
        h3_addr_info_t addr;
        PageCamel_H3_Wrapper *self;
    CODE:
        setbuf(stderr, NULL);  /* Ensure unbuffered output */

        if (!SvROK(self_sv)) {
            fprintf(stderr, "XS process_packet: self_sv is not a reference!\n");
            croak("Not a reference");
        }

        SV *rv = SvRV(self_sv);

        if (!sv_derived_from(self_sv, "PageCamel::Protocol::HTTP3::Connection")) {
            fprintf(stderr, "XS process_packet: Not a Connection object!\n");
            croak("Not a PageCamel::Protocol::HTTP3::Connection");
        }

        IV tmp = SvIV(rv);
        self = INT2PTR(PageCamel_H3_Wrapper *, tmp);

        STRLEN len;
        const uint8_t *pkt = (const uint8_t *)SvPVbyte(data, len);
        fprintf(stderr, "XS process_packet: len=%zu, local=%s:%d, remote=%s:%d\n",
                len, self->local_addr, self->local_port, remote_addr, remote_port);

        addr.local_addr = self->local_addr;
        addr.local_port = self->local_port;
        addr.remote_addr = remote_addr;
        addr.remote_port = remote_port;

        RETVAL = h3_process_packet(self->conn, pkt, len, &addr);
        fprintf(stderr, "XS process_packet: returned %d\n", RETVAL);
    OUTPUT:
        RETVAL

# Flush outgoing packets
int
flush_packets(self)
        PageCamel_H3_Wrapper *self
    CODE:
        setbuf(stderr, NULL);
        fprintf(stderr, "XS flush_packets: self=%p, conn=%p\n", (void*)self, (void*)(self ? self->conn : NULL));
        RETVAL = h3_flush_packets(self->conn);
        fprintf(stderr, "XS flush_packets: returned %d\n", RETVAL);
    OUTPUT:
        RETVAL

# Get timeout in milliseconds
UV
get_timeout_ms(self)
        PageCamel_H3_Wrapper *self
    CODE:
        RETVAL = h3_get_timeout_ms(self->conn);
    OUTPUT:
        RETVAL

# Handle timeout
int
handle_timeout(self)
        PageCamel_H3_Wrapper *self
    CODE:
        RETVAL = h3_handle_timeout(self->conn);
    OUTPUT:
        RETVAL

# Send response headers
int
send_response_headers(self, stream_id, status_code, headers_ref, has_body)
        PageCamel_H3_Wrapper *self
        IV stream_id
        int status_code
        SV *headers_ref
        int has_body
    PREINIT:
        AV *headers_av;
        h3_header_t *headers;
        size_t header_count;
        size_t i;
    CODE:
        if (!SvROK(headers_ref) || SvTYPE(SvRV(headers_ref)) != SVt_PVAV) {
            croak("headers must be an array reference");
        }

        headers_av = (AV *)SvRV(headers_ref);
        header_count = (av_len(headers_av) + 1) / 2;

        headers = (h3_header_t *)calloc(header_count, sizeof(h3_header_t));
        if (!headers) {
            croak("Out of memory");
        }

        for (i = 0; i < header_count; i++) {
            SV **name_sv = av_fetch(headers_av, i * 2, 0);
            SV **value_sv = av_fetch(headers_av, i * 2 + 1, 0);
            STRLEN name_len, value_len;

            if (!name_sv || !value_sv) {
                free(headers);
                croak("Invalid header at index %lu", (unsigned long)i);
            }

            headers[i].name = (const uint8_t *)SvPV(*name_sv, name_len);
            headers[i].name_len = name_len;
            headers[i].value = (const uint8_t *)SvPV(*value_sv, value_len);
            headers[i].value_len = value_len;
        }

        RETVAL = h3_send_response_headers(self->conn, stream_id, status_code,
                                          headers, header_count, has_body);

        free(headers);
    OUTPUT:
        RETVAL

# Send response body
int
send_response_body(self, stream_id, data, eof)
        PageCamel_H3_Wrapper *self
        IV stream_id
        SV *data
        int eof
    CODE:
        STRLEN len;
        const uint8_t *body = (const uint8_t *)SvPVbyte(data, len);

        RETVAL = h3_send_response_body(self->conn, stream_id, body, len, eof);
    OUTPUT:
        RETVAL

# Send complete response
int
send_response(self, stream_id, status_code, headers_ref, body_sv)
        PageCamel_H3_Wrapper *self
        IV stream_id
        int status_code
        SV *headers_ref
        SV *body_sv
    PREINIT:
        AV *headers_av;
        h3_header_t *headers;
        size_t header_count;
        size_t i;
        const uint8_t *body = NULL;
        size_t body_len = 0;
    CODE:
        if (!SvROK(headers_ref) || SvTYPE(SvRV(headers_ref)) != SVt_PVAV) {
            croak("headers must be an array reference");
        }

        headers_av = (AV *)SvRV(headers_ref);
        header_count = (av_len(headers_av) + 1) / 2;

        headers = (h3_header_t *)calloc(header_count, sizeof(h3_header_t));
        if (!headers) {
            croak("Out of memory");
        }

        for (i = 0; i < header_count; i++) {
            SV **name_sv = av_fetch(headers_av, i * 2, 0);
            SV **value_sv = av_fetch(headers_av, i * 2 + 1, 0);
            STRLEN name_len, value_len;

            if (!name_sv || !value_sv) {
                free(headers);
                croak("Invalid header at index %lu", (unsigned long)i);
            }

            headers[i].name = (const uint8_t *)SvPV(*name_sv, name_len);
            headers[i].name_len = name_len;
            headers[i].value = (const uint8_t *)SvPV(*value_sv, value_len);
            headers[i].value_len = value_len;
        }

        if (SvOK(body_sv)) {
            STRLEN len;
            body = (const uint8_t *)SvPVbyte(body_sv, len);
            body_len = len;
        }

        RETVAL = h3_send_response(self->conn, stream_id, status_code,
                                  headers, header_count, body, body_len);

        free(headers);
    OUTPUT:
        RETVAL

# Get connection state
int
get_state(self)
        PageCamel_H3_Wrapper *self
    CODE:
        RETVAL = h3_connection_get_state(self->conn);
    OUTPUT:
        RETVAL

# Get negotiated hostname
SV *
get_hostname(self)
        PageCamel_H3_Wrapper *self
    CODE:
        const char *hostname = h3_connection_get_hostname(self->conn);
        if (hostname) {
            RETVAL = newSVpv(hostname, 0);
        } else {
            RETVAL = &PL_sv_undef;
        }
    OUTPUT:
        RETVAL

# Get selected backend socket
SV *
get_backend(self)
        PageCamel_H3_Wrapper *self
    CODE:
        const char *backend = h3_connection_get_backend(self->conn);
        if (backend) {
            RETVAL = newSVpv(backend, 0);
        } else {
            RETVAL = &PL_sv_undef;
        }
    OUTPUT:
        RETVAL

# Check if handshake is complete
int
is_handshake_complete(self)
        PageCamel_H3_Wrapper *self
    CODE:
        RETVAL = h3_connection_is_handshake_complete(self->conn);
    OUTPUT:
        RETVAL

# Check if connection is closing
int
is_closing(self)
        PageCamel_H3_Wrapper *self
    CODE:
        RETVAL = h3_connection_is_closing(self->conn);
    OUTPUT:
        RETVAL

# Close stream
int
close_stream(self, stream_id, error_code)
        PageCamel_H3_Wrapper *self
        IV stream_id
        UV error_code
    CODE:
        RETVAL = h3_close_stream(self->conn, stream_id, error_code);
    OUTPUT:
        RETVAL

# Get stream buffer size
UV
get_stream_buffer_size(self, stream_id)
        PageCamel_H3_Wrapper *self
        IV stream_id
    CODE:
        RETVAL = h3_get_stream_buffer_size(self->conn, stream_id);
    OUTPUT:
        RETVAL
