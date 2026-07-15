/*
 * http2.c — HTTP/2 server support via nghttp2
 *
 * Implements HTTP/2 connection handling for Tungsten's serve_http.
 * Each TLS connection with ALPN "h2" is dispatched here instead of
 * the HTTP/1.1 keep-alive loop.
 *
 * Build with: -DTUNGSTEN_HTTP2 -lnghttp2
 */

#ifdef TUNGSTEN_HTTP2

#include "runtime.h"
#include <nghttp2/nghttp2.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <errno.h>
#include <unistd.h>
#ifdef TUNGSTEN_TLS
#include <openssl/ssl.h>
#endif

/* Forward declarations */
extern void w_socket_park(int fd, int events);
extern __thread WGoroutine *g_current;

/* Per-stream state */
typedef struct WH2Stream {
    int32_t stream_id;
    char method[16];
    char path[1024];
    int method_len;
    int path_len;
} WH2Stream;

/* Per-connection session */
typedef struct WH2Session {
    nghttp2_session *session;
    WSocket *conn;
    WClosure *handler;
} WH2Session;

/* ---- nghttp2 callbacks ---- */

/* Send data to the network */
static ssize_t h2_send_cb(nghttp2_session *session, const uint8_t *data,
                           size_t length, int flags, void *user_data) {
    (void)session; (void)flags;
    WH2Session *s = (WH2Session *)user_data;

    while (1) {
        ssize_t n;
#ifdef TUNGSTEN_TLS
        if (s->conn->ssl) {
            extern ssize_t w_tls_write(WSocket *s, const char *buf, size_t len);
            n = w_tls_write(s->conn, (const char *)data, length);
        } else
#endif
        {
            n = write(s->conn->fd, data, length);
        }

        if (n > 0) return n;
        if (n == 0) return NGHTTP2_ERR_WOULDBLOCK;
        if (errno == EINTR) continue;
        if (errno == EAGAIN || errno == EWOULDBLOCK) {
            w_socket_park(s->conn->fd, W_EVENT_WRITE);
            continue;
        }
        return NGHTTP2_ERR_CALLBACK_FAILURE;
    }
}

/* Receive data from the network.
 * IMPORTANT: Must NOT block when no data is available — return WOULDBLOCK
 * so the session loop can cycle back to send pending response frames. */
static ssize_t h2_recv_cb(nghttp2_session *session, uint8_t *buf,
                           size_t length, int flags, void *user_data) {
    (void)session; (void)flags;
    WH2Session *s = (WH2Session *)user_data;

    ssize_t n;
#ifdef TUNGSTEN_TLS
    if (s->conn->ssl) {
        /* Non-blocking TLS read: SSL_read returns immediately if no data buffered.
         * We must NOT call w_tls_read() here because it parks the goroutine. */
        SSL *ssl = (SSL *)s->conn->ssl;
        n = SSL_read(ssl, buf, (int)length);
        if (n > 0) return n;
        int err = SSL_get_error(ssl, n);
        if (err == SSL_ERROR_ZERO_RETURN) return NGHTTP2_ERR_EOF;
        if (err == SSL_ERROR_WANT_READ || err == SSL_ERROR_WANT_WRITE)
            return NGHTTP2_ERR_WOULDBLOCK;
        return NGHTTP2_ERR_CALLBACK_FAILURE;
    }
#endif
    n = read(s->conn->fd, buf, length);
    if (n > 0) return n;
    if (n == 0) return NGHTTP2_ERR_EOF;
    if (errno == EINTR) return NGHTTP2_ERR_WOULDBLOCK;
    if (errno == EAGAIN || errno == EWOULDBLOCK)
        return NGHTTP2_ERR_WOULDBLOCK;
    return NGHTTP2_ERR_CALLBACK_FAILURE;
}

/* Called when a new stream's headers begin */
static int h2_on_begin_headers_cb(nghttp2_session *session,
                                   const nghttp2_frame *frame,
                                   void *user_data) {
    (void)user_data;
    if (frame->hd.type != NGHTTP2_HEADERS ||
        frame->headers.cat != NGHTTP2_HCAT_REQUEST) {
        return 0;
    }

    WH2Stream *stream = calloc(1, sizeof(WH2Stream));
    stream->stream_id = frame->hd.stream_id;
    nghttp2_session_set_stream_user_data(session, frame->hd.stream_id, stream);
    return 0;
}

/* Called for each header in a request */
static int h2_on_header_cb(nghttp2_session *session,
                            const nghttp2_frame *frame,
                            const uint8_t *name, size_t namelen,
                            const uint8_t *value, size_t valuelen,
                            uint8_t flags, void *user_data) {
    (void)flags; (void)user_data;
    if (frame->hd.type != NGHTTP2_HEADERS) return 0;

    WH2Stream *stream = nghttp2_session_get_stream_user_data(session, frame->hd.stream_id);
    if (!stream) return 0;

    if (namelen == 7 && memcmp(name, ":method", 7) == 0) {
        int len = valuelen < sizeof(stream->method) - 1 ? (int)valuelen : (int)sizeof(stream->method) - 1;
        memcpy(stream->method, value, len);
        stream->method[len] = '\0';
        stream->method_len = len;
    } else if (namelen == 5 && memcmp(name, ":path", 5) == 0) {
        int len = valuelen < sizeof(stream->path) - 1 ? (int)valuelen : (int)sizeof(stream->path) - 1;
        memcpy(stream->path, value, len);
        stream->path[len] = '\0';
        stream->path_len = len;
    }
    return 0;
}

/* Called for each DATA frame */
static int h2_on_data_chunk_recv_cb(nghttp2_session *session,
                                     uint8_t flags, int32_t stream_id,
                                     const uint8_t *data, size_t len,
                                     void *user_data) {
    (void)session; (void)flags; (void)stream_id;
    (void)data; (void)len; (void)user_data;
    /* We don't process request bodies for now */
    return 0;
}

/* Data source callback for response body */
typedef struct {
    const char *body;
    size_t body_len;
    size_t offset;
} H2DataSource;

static ssize_t h2_data_source_read_cb(nghttp2_session *session,
                                       int32_t stream_id,
                                       uint8_t *buf, size_t length,
                                       uint32_t *data_flags,
                                       nghttp2_data_source *source,
                                       void *user_data) {
    (void)session; (void)stream_id; (void)user_data;
    H2DataSource *ds = (H2DataSource *)source->ptr;
    size_t remaining = ds->body_len - ds->offset;
    size_t nread = remaining < length ? remaining : length;
    memcpy(buf, ds->body + ds->offset, nread);
    ds->offset += nread;
    if (ds->offset >= ds->body_len) {
        *data_flags |= NGHTTP2_DATA_FLAG_EOF;
    }
    return (ssize_t)nread;
}

/* Called when a frame is fully received */
static int h2_on_frame_recv_cb(nghttp2_session *session,
                                const nghttp2_frame *frame,
                                void *user_data) {
    WH2Session *h2s = (WH2Session *)user_data;

    if (frame->hd.type == NGHTTP2_HEADERS &&
        frame->headers.cat == NGHTTP2_HCAT_REQUEST &&
        (frame->hd.flags & NGHTTP2_FLAG_END_HEADERS)) {
        /* Request headers complete — if no body expected, handle now */
        if (frame->hd.flags & NGHTTP2_FLAG_END_STREAM) {
            goto handle_request;
        }
        return 0;
    }

    if (frame->hd.type == NGHTTP2_DATA &&
        (frame->hd.flags & NGHTTP2_FLAG_END_STREAM)) {
        goto handle_request;
    }

    return 0;

handle_request: ;
    WH2Stream *stream = nghttp2_session_get_stream_user_data(session, frame->hd.stream_id);
    if (!stream) return 0;

    /* Build request path WValue */
    char *path = malloc(stream->path_len + 1);
    memcpy(path, stream->path, stream->path_len);
    path[stream->path_len] = '\0';
    WValue req_val = w_string(path);
    free(path);

    /* Call handler with error wrapping */
    WValue response;
    int status = 200;
    const char *body = "Internal Server Error\n";
    size_t body_len = 22;

    WExceptionFrame *prev_stack = w_exception_stack;
    WExceptionFrame exc_frame;
    w_exception_frame_push(&exc_frame);

    if (_setjmp(exc_frame.buf) == 0) {
        response = ((WValue (*)(WValue *, WValue))h2s->handler->fn_ptr)(h2s->handler->captures, req_val);
        w_exception_stack = prev_stack;

        if (w_is_response(response)) {
            WResponse *r = (WResponse *)w_as_ptr(response);
            status = r->status;
            if (r->body_kind == W_BODY_STRBUF) {
                body = r->body;
                body_len = r->body_len;
            } else if (r->body_val) {
                static char _h2_resp_sbuf[6];
                const char *sout; size_t slen;
                w_str_data(r->body_val, _h2_resp_sbuf, &sout, &slen);
                body = sout;
                body_len = slen;
            } else {
                body = r->body;
                body_len = r->body_len;
            }
        } else if (w_is_string(response) || w_is_rope(response)) {
            static char _h2_sbuf[6];
            const char *sout; size_t slen;
            w_str_data(response, _h2_sbuf, &sout, &slen);
            body = sout;
            body_len = slen;
        }
    } else {
        w_exception_stack = prev_stack;
        status = 500;
    }

    /* Submit HTTP/2 response */
    char status_str[16];
    snprintf(status_str, sizeof(status_str), "%d", status);

    char content_length_str[32];
    snprintf(content_length_str, sizeof(content_length_str), "%zu", body_len);

    nghttp2_nv hdrs[] = {
        {(uint8_t *)":status", (uint8_t *)status_str, 7, strlen(status_str), NGHTTP2_NV_FLAG_NONE},
        {(uint8_t *)"content-length", (uint8_t *)content_length_str, 14, strlen(content_length_str), NGHTTP2_NV_FLAG_NONE},
    };

    H2DataSource *ds = calloc(1, sizeof(H2DataSource));
    ds->body = body;
    ds->body_len = body_len;
    ds->offset = 0;

    nghttp2_data_provider data_prd;
    data_prd.source.ptr = ds;
    data_prd.read_callback = h2_data_source_read_cb;

    nghttp2_submit_response(session, frame->hd.stream_id, hdrs, 2, &data_prd);
    return 0;
}

/* Called when a stream is closed */
static int h2_on_stream_close_cb(nghttp2_session *session, int32_t stream_id,
                                  uint32_t error_code, void *user_data) {
    (void)error_code; (void)user_data;
    WH2Stream *stream = nghttp2_session_get_stream_user_data(session, stream_id);
    if (stream) {
        free(stream);
        nghttp2_session_set_stream_user_data(session, stream_id, NULL);
    }
    return 0;
}

/* ---- Public API ---- */

void w_http2_serve_connection(WSocket *conn, WClosure *handler) {
    WH2Session h2s;
    h2s.conn = conn;
    h2s.handler = handler;

    nghttp2_session_callbacks *callbacks;
    nghttp2_session_callbacks_new(&callbacks);
    nghttp2_session_callbacks_set_send_callback(callbacks, h2_send_cb);
    nghttp2_session_callbacks_set_recv_callback(callbacks, h2_recv_cb);
    nghttp2_session_callbacks_set_on_begin_headers_callback(callbacks, h2_on_begin_headers_cb);
    nghttp2_session_callbacks_set_on_header_callback(callbacks, h2_on_header_cb);
    nghttp2_session_callbacks_set_on_frame_recv_callback(callbacks, h2_on_frame_recv_cb);
    nghttp2_session_callbacks_set_on_data_chunk_recv_callback(callbacks, h2_on_data_chunk_recv_cb);
    nghttp2_session_callbacks_set_on_stream_close_callback(callbacks, h2_on_stream_close_cb);

    int rv = nghttp2_session_server_new(&h2s.session, callbacks, &h2s);
    nghttp2_session_callbacks_del(callbacks);
    if (rv != 0) {
        close(conn->fd);
        conn->closed = 1;
        return;
    }

    /* Send server connection preface (SETTINGS frame) */
    nghttp2_settings_entry settings[] = {
        {NGHTTP2_SETTINGS_MAX_CONCURRENT_STREAMS, 100},
    };
    nghttp2_submit_settings(h2s.session, NGHTTP2_FLAG_NONE, settings, 1);

    /* Main session loop: send pending, then receive.
     * The recv callback is non-blocking (returns WOULDBLOCK when no data).
     * When both send and recv have nothing to do, park the goroutine on
     * the socket fd until more data arrives. */
    while (nghttp2_session_want_read(h2s.session) ||
           nghttp2_session_want_write(h2s.session)) {

        /* Send any pending frames */
        if (nghttp2_session_want_write(h2s.session)) {
            rv = nghttp2_session_send(h2s.session);
            if (rv != 0) break;
        }

        /* Receive incoming frames (non-blocking) */
        if (nghttp2_session_want_read(h2s.session)) {
            rv = nghttp2_session_recv(h2s.session);
            if (rv == NGHTTP2_ERR_WOULDBLOCK) {
                /* No data available — check if we need to send first */
                if (nghttp2_session_want_write(h2s.session)) continue;
                /* Nothing to send or recv — park goroutine until data arrives */
                w_socket_park(conn->fd, W_EVENT_READ);
                continue;
            }
            if (rv != 0) break;
        }
    }

    nghttp2_session_del(h2s.session);
    close(conn->fd);
    conn->closed = 1;
}

#endif /* TUNGSTEN_HTTP2 */
