/*
 * http3.c — HTTP/3 (QUIC) server support via ngtcp2 + nghttp3
 *
 * Implements QUIC transport (ngtcp2) with HTTP/3 mapping (nghttp3)
 * for Tungsten's serve_http. Runs a UDP event loop alongside the
 * TCP accept loop.
 *
 * Build with: -DTUNGSTEN_HTTP3 -lngtcp2 -lngtcp2_crypto_ossl -lnghttp3
 */

#ifdef TUNGSTEN_HTTP3

#include "runtime.h"
#include <ngtcp2/ngtcp2.h>
#include <ngtcp2/ngtcp2_crypto.h>
#include <ngtcp2/ngtcp2_crypto_ossl.h>
#include <nghttp3/nghttp3.h>
#include <openssl/ssl.h>
#include <openssl/err.h>
#include <openssl/rand.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <errno.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <poll.h>

/* Forward declarations */
extern void w_socket_park(int fd, int events);
extern __thread WGoroutine *g_current;

/* ---- Connection table (DCID -> connection) ---- */

#define MAX_QUIC_CONNECTIONS 1024

typedef struct WQuicConn {
    ngtcp2_conn *conn;
    nghttp3_conn *h3conn;
    SSL *ssl;
    ngtcp2_crypto_conn_ref conn_ref; /* required by ngtcp2_crypto callbacks */
    int fd;
    struct sockaddr_storage remote_addr;
    socklen_t remote_addrlen;
    struct sockaddr_storage local_addr;
    socklen_t local_addrlen;
    WClosure *handler;
    ngtcp2_ccerr last_error;
    uint8_t dcid[NGTCP2_MAX_CIDLEN];
    size_t dcid_len;
    int closed;
} WQuicConn;

/* Callback for ngtcp2_crypto to get ngtcp2_conn from SSL app data */
static ngtcp2_conn *quic_get_conn_cb(ngtcp2_crypto_conn_ref *ref) {
    WQuicConn *qc = (WQuicConn *)ref->user_data;
    return qc->conn;
}

/* Per-stream state */
typedef struct WH3Stream {
    int64_t stream_id;
    char method[16];
    char path[1024];
    int method_len;
    int path_len;
} WH3Stream;

/* Response body for h3 data read callback */
typedef struct H3ResponseBody {
    const char *data;
    size_t len;
    size_t offset;
} H3ResponseBody;

/* ---- DCID hash map (open-addressing, FNV-1a) ---- */

typedef struct {
    uint8_t dcid[NGTCP2_MAX_CIDLEN];
    size_t dcid_len;
    WQuicConn *conn;
    int occupied;
} QuicConnSlot;

static QuicConnSlot g_quic_map[MAX_QUIC_CONNECTIONS];
static int g_quic_conn_count = 0;
static SSL_CTX *g_quic_ssl_ctx = NULL;

static uint32_t quic_fnv1a(const uint8_t *data, size_t len) {
    uint32_t h = 2166136261u;
    for (size_t i = 0; i < len; i++) {
        h ^= data[i];
        h *= 16777619u;
    }
    return h;
}

static WQuicConn *quic_map_lookup(const uint8_t *dcid, size_t dcid_len) {
    uint32_t h = quic_fnv1a(dcid, dcid_len);
    for (int i = 0; i < MAX_QUIC_CONNECTIONS; i++) {
        int idx = (h + i) % MAX_QUIC_CONNECTIONS;
        QuicConnSlot *slot = &g_quic_map[idx];
        if (!slot->occupied) return NULL;
        if (slot->dcid_len == dcid_len && memcmp(slot->dcid, dcid, dcid_len) == 0) {
            return slot->conn;
        }
    }
    return NULL;
}

static int quic_map_insert(const uint8_t *dcid, size_t dcid_len, WQuicConn *conn) {
    if (g_quic_conn_count >= MAX_QUIC_CONNECTIONS * 3 / 4) {
        fprintf(stderr, "http3: connection table full (%d/%d)\n",
                g_quic_conn_count, MAX_QUIC_CONNECTIONS);
        return -1;
    }
    uint32_t h = quic_fnv1a(dcid, dcid_len);
    for (int i = 0; i < MAX_QUIC_CONNECTIONS; i++) {
        int idx = (h + i) % MAX_QUIC_CONNECTIONS;
        QuicConnSlot *slot = &g_quic_map[idx];
        if (!slot->occupied) {
            memcpy(slot->dcid, dcid, dcid_len);
            slot->dcid_len = dcid_len;
            slot->conn = conn;
            slot->occupied = 1;
            g_quic_conn_count++;
            return 0;
        }
        /* Allow overwrite if same DCID */
        if (slot->dcid_len == dcid_len && memcmp(slot->dcid, dcid, dcid_len) == 0) {
            slot->conn = conn;
            return 0;
        }
    }
    fprintf(stderr, "http3: connection table full (probe exhausted)\n");
    return -1;
}

static void quic_map_remove(const uint8_t *dcid, size_t dcid_len) {
    uint32_t h = quic_fnv1a(dcid, dcid_len);
    for (int i = 0; i < MAX_QUIC_CONNECTIONS; i++) {
        int idx = (h + i) % MAX_QUIC_CONNECTIONS;
        QuicConnSlot *slot = &g_quic_map[idx];
        if (!slot->occupied) return;
        if (slot->dcid_len == dcid_len && memcmp(slot->dcid, dcid, dcid_len) == 0) {
            /* Deletion with backward-shift to maintain probe chains */
            slot->occupied = 0;
            slot->dcid_len = 0;
            g_quic_conn_count--;
            /* Rehash subsequent entries in the same cluster */
            int j = (idx + 1) % MAX_QUIC_CONNECTIONS;
            while (g_quic_map[j].occupied) {
                QuicConnSlot tmp = g_quic_map[j];
                g_quic_map[j].occupied = 0;
                g_quic_map[j].dcid_len = 0;
                g_quic_conn_count--;
                quic_map_insert(tmp.dcid, tmp.dcid_len, tmp.conn);
                j = (j + 1) % MAX_QUIC_CONNECTIONS;
            }
            return;
        }
    }
}

/* ---- Active connection list for iteration ---- */
static WQuicConn *g_quic_active[MAX_QUIC_CONNECTIONS];
static int g_quic_active_count = 0;

/* ---- Timestamp helper ---- */
static ngtcp2_tstamp quic_timestamp(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (ngtcp2_tstamp)(ts.tv_sec * NGTCP2_SECONDS + ts.tv_nsec);
}

/* ---- Random bytes ---- */
static void quic_rand(uint8_t *dest, size_t destlen) {
    RAND_bytes(dest, (int)destlen);
}

/* ---- ngtcp2 callbacks ---- */

static void quic_rand_cb(uint8_t *dest, size_t destlen,
                           const ngtcp2_rand_ctx *rand_ctx) {
    (void)rand_ctx;
    quic_rand(dest, destlen);
}

static int quic_get_new_connection_id_cb(ngtcp2_conn *conn, ngtcp2_cid *cid,
                                          uint8_t *token, size_t cidlen,
                                          void *user_data) {
    (void)conn;
    WQuicConn *qc = (WQuicConn *)user_data;
    quic_rand(cid->data, cidlen);
    cid->datalen = cidlen;
    quic_rand(token, NGTCP2_STATELESS_RESET_TOKENLEN);

    /* Register new CID in hash map for CID rotation */
    quic_map_insert(cid->data, cid->datalen, qc);
    return 0;
}

/* ---- ngtcp2 stream data callbacks (bridge to nghttp3) ---- */

static int quic_recv_stream_data_cb(ngtcp2_conn *conn, uint32_t flags,
                                     int64_t stream_id, uint64_t offset,
                                     const uint8_t *data, size_t datalen,
                                     void *user_data, void *stream_user_data) {
    (void)conn; (void)offset; (void)stream_user_data;
    WQuicConn *qc = (WQuicConn *)user_data;
    if (!qc->h3conn) return 0;
    ngtcp2_ssize consumed = nghttp3_conn_read_stream(qc->h3conn, stream_id, data, datalen,
                                                      flags & NGTCP2_STREAM_DATA_FLAG_FIN);
    if (consumed < 0) return NGTCP2_ERR_CALLBACK_FAILURE;
    ngtcp2_conn_extend_max_stream_offset(conn, stream_id, (uint64_t)consumed);
    ngtcp2_conn_extend_max_offset(conn, (uint64_t)consumed);
    return 0;
}

static int quic_acked_stream_data_cb(ngtcp2_conn *conn, int64_t stream_id,
                                      uint64_t offset, uint64_t datalen,
                                      void *user_data, void *stream_user_data) {
    (void)conn; (void)offset; (void)stream_user_data;
    WQuicConn *qc = (WQuicConn *)user_data;
    if (qc->h3conn) nghttp3_conn_add_ack_offset(qc->h3conn, stream_id, datalen);
    return 0;
}

static int quic_stream_close_cb(ngtcp2_conn *conn, uint32_t flags,
                                 int64_t stream_id, uint64_t app_error_code,
                                 void *user_data, void *stream_user_data) {
    (void)conn; (void)flags; (void)stream_user_data;
    WQuicConn *qc = (WQuicConn *)user_data;
    if (qc->h3conn) {
        int rv = nghttp3_conn_close_stream(qc->h3conn, stream_id, app_error_code);
        if (rv != 0 && rv != NGHTTP3_ERR_STREAM_NOT_FOUND) return NGTCP2_ERR_CALLBACK_FAILURE;
    }
    return 0;
}

static int quic_extend_max_stream_data_cb(ngtcp2_conn *conn, int64_t stream_id,
                                           uint64_t max_data, void *user_data,
                                           void *stream_user_data) {
    (void)conn; (void)max_data; (void)stream_user_data;
    WQuicConn *qc = (WQuicConn *)user_data;
    if (qc->h3conn) nghttp3_conn_unblock_stream(qc->h3conn, stream_id);
    return 0;
}

/* ---- Handshake completed callback — sets up nghttp3 ---- */

static int quic_setup_h3(WQuicConn *qc);

static int quic_handshake_completed_cb(ngtcp2_conn *conn, void *user_data) {
    (void)conn;
    WQuicConn *qc = (WQuicConn *)user_data;
    return quic_setup_h3(qc);
}

/* ---- nghttp3 callbacks ---- */

static int h3_recv_header_cb(nghttp3_conn *conn, int64_t stream_id,
                              int32_t token, nghttp3_rcbuf *name,
                              nghttp3_rcbuf *value, uint8_t flags,
                              void *user_data, void *stream_user_data) {
    (void)conn; (void)token; (void)flags; (void)user_data;
    WH3Stream *stream = (WH3Stream *)stream_user_data;
    if (!stream) return 0;

    nghttp3_vec namev = nghttp3_rcbuf_get_buf(name);
    nghttp3_vec valuev = nghttp3_rcbuf_get_buf(value);

    if (namev.len == 7 && memcmp(namev.base, ":method", 7) == 0) {
        int len = valuev.len < sizeof(stream->method) - 1 ? (int)valuev.len : (int)sizeof(stream->method) - 1;
        memcpy(stream->method, valuev.base, len);
        stream->method[len] = '\0';
        stream->method_len = len;
    } else if (namev.len == 5 && memcmp(namev.base, ":path", 5) == 0) {
        int len = valuev.len < sizeof(stream->path) - 1 ? (int)valuev.len : (int)sizeof(stream->path) - 1;
        memcpy(stream->path, valuev.base, len);
        stream->path[len] = '\0';
        stream->path_len = len;
    }
    return 0;
}

/* ---- h3 data read callback for response body delivery ---- */

static nghttp3_ssize h3_data_read_cb(nghttp3_conn *conn, int64_t stream_id,
                                      nghttp3_vec *vec, size_t veccnt,
                                      uint32_t *pflags, void *user_data,
                                      void *stream_user_data) {
    (void)conn; (void)stream_id; (void)veccnt; (void)user_data;
    H3ResponseBody *body = (H3ResponseBody *)stream_user_data;
    if (!body || body->offset >= body->len) {
        *pflags |= NGHTTP3_DATA_FLAG_EOF;
        return 0;
    }
    vec[0].base = (uint8_t *)(body->data + body->offset);
    vec[0].len = body->len - body->offset;
    body->offset = body->len;
    *pflags |= NGHTTP3_DATA_FLAG_EOF;
    return 1;
}

static int h3_end_stream_cb(nghttp3_conn *conn, int64_t stream_id,
                              void *user_data, void *stream_user_data) {
    (void)conn;
    WQuicConn *qc = (WQuicConn *)user_data;
    WH3Stream *stream = (WH3Stream *)stream_user_data;
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
        response = ((WValue (*)(WValue *, WValue))qc->handler->fn_ptr)(qc->handler->captures, req_val);
        w_exception_stack = prev_stack;

        if (w_is_response(response)) {
            WResponse *r = (WResponse *)w_as_ptr(response);
            status = r->status;
            if (r->body_kind == W_BODY_STRBUF) {
                body = r->body;
                body_len = r->body_len;
            } else if (r->body_val) {
                static char _h3_resp_sbuf[6];
                const char *sout; size_t slen;
                w_str_data(r->body_val, _h3_resp_sbuf, &sout, &slen);
                body = sout;
                body_len = slen;
            } else {
                body = r->body;
                body_len = r->body_len;
            }
        } else if (w_is_string(response) || w_is_rope(response)) {
            static char _h3_sbuf[6];
            const char *sout; size_t slen;
            w_str_data(response, _h3_sbuf, &sout, &slen);
            body = sout;
            body_len = slen;
        }
    } else {
        w_exception_stack = prev_stack;
        status = 500;
    }

    /* Submit HTTP/3 response */
    char status_str[16];
    snprintf(status_str, sizeof(status_str), "%d", status);
    char cl_str[32];
    snprintf(cl_str, sizeof(cl_str), "%zu", body_len);

    nghttp3_nv hdrs[] = {
        {(uint8_t *)":status", (uint8_t *)status_str, 7, strlen(status_str), NGHTTP3_NV_FLAG_NONE},
        {(uint8_t *)"content-length", (uint8_t *)cl_str, 14, strlen(cl_str), NGHTTP3_NV_FLAG_NONE},
    };

    H3ResponseBody *resp_body = calloc(1, sizeof(H3ResponseBody));
    resp_body->data = body;
    resp_body->len = body_len;

    nghttp3_data_reader data_rd;
    data_rd.read_data = h3_data_read_cb;

    /* Set stream user data to response body for the read callback */
    nghttp3_conn_set_stream_user_data(conn, stream_id, resp_body);

    nghttp3_conn_submit_response(conn, stream_id, hdrs, 2, &data_rd);

    /* Free the original stream struct — it's been replaced by resp_body */
    free(stream);

    return 0;
}

static int h3_begin_headers_cb(nghttp3_conn *conn, int64_t stream_id,
                                void *user_data, void *stream_user_data) {
    (void)conn; (void)user_data; (void)stream_user_data;
    WH3Stream *stream = calloc(1, sizeof(WH3Stream));
    stream->stream_id = stream_id;
    nghttp3_conn_set_stream_user_data(conn, stream_id, stream);
    return 0;
}

static int h3_stop_sending_cb(nghttp3_conn *conn, int64_t stream_id,
                               uint64_t app_error_code, void *user_data,
                               void *stream_user_data) {
    (void)conn; (void)stream_user_data;
    WQuicConn *qc = (WQuicConn *)user_data;
    ngtcp2_conn_shutdown_stream_read(qc->conn, 0, stream_id, app_error_code);
    return 0;
}

static int h3_reset_stream_cb(nghttp3_conn *conn, int64_t stream_id,
                               uint64_t app_error_code, void *user_data,
                               void *stream_user_data) {
    (void)conn; (void)stream_user_data;
    WQuicConn *qc = (WQuicConn *)user_data;
    ngtcp2_conn_shutdown_stream_write(qc->conn, 0, stream_id, app_error_code);
    return 0;
}

/* ---- Set up nghttp3 after handshake completes ---- */

static int quic_setup_h3(WQuicConn *qc) {
    nghttp3_callbacks h3_cbs;
    memset(&h3_cbs, 0, sizeof(h3_cbs));
    h3_cbs.recv_header = h3_recv_header_cb;
    h3_cbs.end_stream = h3_end_stream_cb;
    h3_cbs.begin_headers = h3_begin_headers_cb;
    h3_cbs.stop_sending = h3_stop_sending_cb;
    h3_cbs.reset_stream = h3_reset_stream_cb;

    nghttp3_settings h3_settings;
    nghttp3_settings_default(&h3_settings);

    int rv = nghttp3_conn_server_new(&qc->h3conn, &h3_cbs, &h3_settings, NULL, qc);
    if (rv != 0) return -1;

    int64_t ctrl_id, qenc_id, qdec_id;
    rv = ngtcp2_conn_open_uni_stream(qc->conn, &ctrl_id, NULL);
    if (rv != 0) return -1;
    rv = ngtcp2_conn_open_uni_stream(qc->conn, &qenc_id, NULL);
    if (rv != 0) return -1;
    rv = ngtcp2_conn_open_uni_stream(qc->conn, &qdec_id, NULL);
    if (rv != 0) return -1;

    rv = nghttp3_conn_bind_control_stream(qc->h3conn, ctrl_id);
    if (rv != 0) return -1;
    rv = nghttp3_conn_bind_qpack_streams(qc->h3conn, qenc_id, qdec_id);
    if (rv != 0) return -1;

    return 0;
}

/* ---- SSL context for QUIC ---- */

static int quic_alpn_select_cb(SSL *ssl, const unsigned char **out,
                                unsigned char *outlen,
                                const unsigned char *in, unsigned int inlen,
                                void *arg) {
    (void)ssl; (void)arg;
    /* Walk the ALPN list from the client and select "h3" */
    unsigned int i = 0;
    while (i < inlen) {
        unsigned int proto_len = in[i];
        i++;
        if (i + proto_len > inlen) break;
        if (proto_len == 2 && in[i] == 'h' && in[i + 1] == '3') {
            *out = &in[i];
            *outlen = 2;
            return SSL_TLSEXT_ERR_OK;
        }
        i += proto_len;
    }
    return SSL_TLSEXT_ERR_ALERT_FATAL;
}

static void ensure_quic_ssl_ctx(void) {
    if (g_quic_ssl_ctx) return;

    ngtcp2_crypto_ossl_init();

    g_quic_ssl_ctx = SSL_CTX_new(TLS_server_method());
    if (!g_quic_ssl_ctx) return;

    SSL_CTX_set_min_proto_version(g_quic_ssl_ctx, TLS1_3_VERSION);
    SSL_CTX_set_max_proto_version(g_quic_ssl_ctx, TLS1_3_VERSION);

    /* QUIC requires server-side ALPN selection callback */
    SSL_CTX_set_alpn_select_cb(g_quic_ssl_ctx, quic_alpn_select_cb, NULL);

    /* Load cert/key from TLS module paths */
    const char *cert_path = w_tls_get_cert_path();
    const char *key_path = w_tls_get_key_path();
    if (cert_path && key_path) {
        SSL_CTX_use_certificate_chain_file(g_quic_ssl_ctx, cert_path);
        SSL_CTX_use_PrivateKey_file(g_quic_ssl_ctx, key_path, SSL_FILETYPE_PEM);
    }
}

/* ---- Write streams: drain nghttp3 through ngtcp2 ---- */

static int quic_write_streams(WQuicConn *qc, int fd) {
    uint8_t buf[1280];
    ngtcp2_path_storage ps;
    ngtcp2_path_storage_zero(&ps);
    ngtcp2_pkt_info pi;
    ngtcp2_tstamp now = quic_timestamp();

    for (;;) {
        int64_t stream_id = -1;
        nghttp3_vec vec[16];
        nghttp3_ssize sveccnt = 0;
        int fin = 0;

        if (qc->h3conn) {
            sveccnt = nghttp3_conn_writev_stream(qc->h3conn, &stream_id, &fin, vec, 16);
            if (sveccnt < 0) return -1;
        }

        ngtcp2_ssize ndatalen;
        uint32_t flags = NGTCP2_WRITE_STREAM_FLAG_MORE;
        if (fin) flags |= NGTCP2_WRITE_STREAM_FLAG_FIN;

        ngtcp2_ssize wn;
        if (sveccnt > 0) {
            wn = ngtcp2_conn_writev_stream(qc->conn, &ps.path, &pi,
                                            buf, sizeof(buf), &ndatalen,
                                            flags, stream_id,
                                            (const ngtcp2_vec *)vec, (size_t)sveccnt, now);
        } else {
            wn = ngtcp2_conn_write_pkt(qc->conn, &ps.path, &pi, buf, sizeof(buf), now);
            ndatalen = -1;
        }

        if (wn < 0) {
            if (wn == NGTCP2_ERR_WRITE_MORE) {
                if (qc->h3conn && ndatalen >= 0)
                    nghttp3_conn_add_write_offset(qc->h3conn, stream_id, ndatalen);
                continue;
            }
            fprintf(stderr, "[h3] write failed: %zd (%s)\n", wn, ngtcp2_strerror((int)wn));
            return (int)wn;
        }
        if (wn == 0) break;

        if (qc->h3conn && ndatalen >= 0)
            nghttp3_conn_add_write_offset(qc->h3conn, stream_id, ndatalen);

        sendto(fd, buf, (size_t)wn, 0, (struct sockaddr *)&qc->remote_addr, qc->remote_addrlen);
    }
    return 0;
}

/* ---- New QUIC connection ---- */

static WQuicConn *quic_new_connection(int fd,
                                       const uint8_t *pkt, size_t pktlen,
                                       const ngtcp2_pkt_hd *hd,
                                       const struct sockaddr *local_addr, socklen_t local_addrlen,
                                       const struct sockaddr *remote_addr, socklen_t remote_addrlen,
                                       WClosure *handler) {
    WQuicConn *qc = calloc(1, sizeof(WQuicConn));
    if (!qc) return NULL;
    qc->fd = fd;
    qc->handler = handler;
    memcpy(&qc->remote_addr, remote_addr, remote_addrlen);
    qc->remote_addrlen = remote_addrlen;
    memcpy(&qc->local_addr, local_addr, local_addrlen);
    qc->local_addrlen = local_addrlen;

    /* Generate random server SCID */
    ngtcp2_cid scid;
    scid.datalen = NGTCP2_MAX_CIDLEN;
    quic_rand(scid.data, scid.datalen);

    /* Set up ngtcp2 callbacks using crypto convenience callbacks */
    ngtcp2_callbacks callbacks;
    memset(&callbacks, 0, sizeof(callbacks));

    /* Crypto callbacks from ngtcp2_crypto */
    callbacks.recv_client_initial = ngtcp2_crypto_recv_client_initial_cb;
    callbacks.recv_crypto_data = ngtcp2_crypto_recv_crypto_data_cb;
    callbacks.encrypt = ngtcp2_crypto_encrypt_cb;
    callbacks.decrypt = ngtcp2_crypto_decrypt_cb;
    callbacks.hp_mask = ngtcp2_crypto_hp_mask_cb;
    callbacks.update_key = ngtcp2_crypto_update_key_cb;
    callbacks.delete_crypto_aead_ctx = ngtcp2_crypto_delete_crypto_aead_ctx_cb;
    callbacks.delete_crypto_cipher_ctx = ngtcp2_crypto_delete_crypto_cipher_ctx_cb;
    callbacks.get_path_challenge_data = ngtcp2_crypto_get_path_challenge_data_cb;
    callbacks.version_negotiation = ngtcp2_crypto_version_negotiation_cb;

    /* Local callbacks */
    callbacks.rand = quic_rand_cb;
    callbacks.get_new_connection_id = quic_get_new_connection_id_cb;
    callbacks.recv_stream_data = quic_recv_stream_data_cb;
    callbacks.acked_stream_data_offset = quic_acked_stream_data_cb;
    callbacks.stream_close = quic_stream_close_cb;
    callbacks.extend_max_stream_data = quic_extend_max_stream_data_cb;
    callbacks.handshake_completed = quic_handshake_completed_cb;

    /* Initialize settings and transport params */
    ngtcp2_settings settings;
    ngtcp2_settings_default(&settings);
    settings.initial_ts = quic_timestamp();

    ngtcp2_transport_params params;
    ngtcp2_transport_params_default(&params);
    params.initial_max_streams_uni = 3; /* control + qpack encoder + qpack decoder */
    params.initial_max_streams_bidi = 128;
    params.initial_max_data = 1048576;
    params.initial_max_stream_data_bidi_local = 262144;
    params.initial_max_stream_data_bidi_remote = 262144;
    params.initial_max_stream_data_uni = 262144;
    params.original_dcid = hd->dcid;
    params.original_dcid_present = 1;

    /* Build ngtcp2_path from local/remote addresses */
    ngtcp2_path path;
    ngtcp2_addr_init(&path.local, (struct sockaddr *)local_addr, local_addrlen);
    ngtcp2_addr_init(&path.remote, (struct sockaddr *)remote_addr, remote_addrlen);

    /* Create server connection */
    int rv = ngtcp2_conn_server_new(&qc->conn, &hd->dcid, &scid, &path,
                                     hd->version, &callbacks, &settings,
                                     &params, NULL, qc);
    if (rv != 0) {
        fprintf(stderr, "[h3] conn_server_new failed: %d (%s)\n", rv, ngtcp2_strerror(rv));
        free(qc);
        return NULL;
    }

    /* Create per-connection SSL */
    qc->ssl = SSL_new(g_quic_ssl_ctx);
    if (!qc->ssl) {
        fprintf(stderr, "[h3] SSL_new failed\n");
        ngtcp2_conn_del(qc->conn);
        free(qc);
        return NULL;
    }

    /* Configure SSL for QUIC server mode */
    ngtcp2_crypto_ossl_configure_server_session(qc->ssl);
    SSL_set_accept_state(qc->ssl);

    /* Set up conn_ref so ngtcp2_crypto callbacks can find ngtcp2_conn from SSL */
    qc->conn_ref.get_conn = quic_get_conn_cb;
    qc->conn_ref.user_data = qc;
    SSL_set_app_data(qc->ssl, &qc->conn_ref);

    /* Create ngtcp2_crypto_ossl_ctx wrapper — required for ngtcp2_conn_set_tls_native_handle */
    ngtcp2_crypto_ossl_ctx *ossl_ctx;
    rv = ngtcp2_crypto_ossl_ctx_new(&ossl_ctx, qc->ssl);
    if (rv != 0) {
        fprintf(stderr, "[h3] ossl_ctx_new failed: %d\n", rv);
        SSL_free(qc->ssl);
        ngtcp2_conn_del(qc->conn);
        free(qc);
        return NULL;
    }
    ngtcp2_conn_set_tls_native_handle(qc->conn, ossl_ctx);

    /* Feed the initial packet */
    ngtcp2_pkt_info pi;
    memset(&pi, 0, sizeof(pi));
    rv = ngtcp2_conn_read_pkt(qc->conn, &path, &pi, pkt, pktlen, quic_timestamp());
    if (rv != 0) {
        fprintf(stderr, "[h3] read_pkt failed: %d (%s)\n", rv, ngtcp2_strerror(rv));
        SSL_free(qc->ssl);
        ngtcp2_conn_del(qc->conn);
        free(qc);
        return NULL;
    }

    /* Store SCID in hash map */
    memcpy(qc->dcid, scid.data, scid.datalen);
    qc->dcid_len = scid.datalen;
    quic_map_insert(scid.data, scid.datalen, qc);

    /* Also register under client's DCID for Initial packets */
    quic_map_insert(hd->dcid.data, hd->dcid.datalen, qc);

    /* Add to active connection list */
    if (g_quic_active_count < MAX_QUIC_CONNECTIONS) {
        g_quic_active[g_quic_active_count++] = qc;
    }

    return qc;
}

/* ---- Public API ---- */

void w_http3_serve(int port, WClosure *handler, const char *cert_path, const char *key_path) {
    ensure_quic_ssl_ctx();

    /* Load cert/key if provided directly (overrides defaults from ensure_quic_ssl_ctx) */
    if (cert_path && key_path) {
        SSL_CTX_use_certificate_chain_file(g_quic_ssl_ctx, cert_path);
        SSL_CTX_use_PrivateKey_file(g_quic_ssl_ctx, key_path, SSL_FILETYPE_PEM);
    }

    /* Create UDP socket */
    int fd = socket(AF_INET, SOCK_DGRAM, 0);
    if (fd < 0) { fprintf(stderr, "[h3] socket() failed: %s\n", strerror(errno)); return; }

    int reuse = 1;
    setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &reuse, sizeof(reuse));
#ifdef SO_REUSEPORT
    setsockopt(fd, SOL_SOCKET, SO_REUSEPORT, &reuse, sizeof(reuse));
#endif

    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_port = htons(port);
    addr.sin_addr.s_addr = INADDR_ANY;

    if (bind(fd, (struct sockaddr *)&addr, sizeof(addr)) < 0) {
        fprintf(stderr, "[h3] bind(port=%d) failed: %s\n", port, strerror(errno));
        close(fd);
        return;
    }
    fprintf(stderr, "[h3] UDP listening on port %d (fd=%d)\n", port, fd);

    /* Set non-blocking */
    int flags = fcntl(fd, F_GETFL, 0);
    fcntl(fd, F_SETFL, flags | O_NONBLOCK);

    /* Get bound local address for ngtcp2_path */
    struct sockaddr_storage local_ss;
    socklen_t local_sslen = sizeof(local_ss);
    getsockname(fd, (struct sockaddr *)&local_ss, &local_sslen);

    /* UDP receive loop */
    uint8_t buf[65535];
    struct sockaddr_storage remote;
    socklen_t remote_len;

    while (1) {
        remote_len = sizeof(remote);
        ssize_t n = recvfrom(fd, buf, sizeof(buf), 0,
                              (struct sockaddr *)&remote, &remote_len);

        if (n < 0) {
            if (errno == EAGAIN || errno == EWOULDBLOCK) {
                /* Compute minimum timeout from all active connections */
                ngtcp2_tstamp now = quic_timestamp();
                int timeout_ms = 100; /* Default 100ms */
                for (int i = 0; i < g_quic_active_count; i++) {
                    WQuicConn *qc = g_quic_active[i];
                    if (!qc || qc->closed) continue;
                    ngtcp2_tstamp expiry = ngtcp2_conn_get_expiry(qc->conn);
                    if (expiry != UINT64_MAX) {
                        int64_t delta_ms;
                        if (expiry <= now) {
                            delta_ms = 0;
                        } else {
                            delta_ms = (int64_t)((expiry - now) / NGTCP2_MILLISECONDS);
                        }
                        if (delta_ms < timeout_ms) {
                            timeout_ms = (int)delta_ms;
                        }
                    }
                }
                if (timeout_ms < 0) timeout_ms = 0;

                struct pollfd pfd = {fd, POLLIN, 0};
                poll(&pfd, 1, timeout_ms);

                /* Process expired connections */
                now = quic_timestamp();
                for (int i = 0; i < g_quic_active_count; i++) {
                    WQuicConn *qc = g_quic_active[i];
                    if (!qc || qc->closed) continue;
                    ngtcp2_tstamp expiry = ngtcp2_conn_get_expiry(qc->conn);
                    if (expiry <= now) {
                        int rv = ngtcp2_conn_handle_expiry(qc->conn, now);
                        if (rv != 0) {
                            qc->closed = 1;
                            continue;
                        }
                        quic_write_streams(qc, fd);
                    }
                }
                continue;
            }
            if (errno == EINTR) continue;
            break;
        }

        /* Decode packet header to find DCID */
        ngtcp2_version_cid vc;
        int rv = ngtcp2_pkt_decode_version_cid(&vc, buf, (size_t)n, NGTCP2_MAX_CIDLEN);
        if (rv != 0) continue;

        /* Look up existing connection */
        WQuicConn *qc = quic_map_lookup(vc.dcid, vc.dcidlen);
        if (qc && !qc->closed) {
            /* Feed packet to existing connection */
            ngtcp2_path path;
            memset(&path, 0, sizeof(path));
            ngtcp2_addr_init(&path.local, (struct sockaddr *)&qc->local_addr, qc->local_addrlen);
            ngtcp2_addr_init(&path.remote, (struct sockaddr *)&remote, remote_len);

            ngtcp2_pkt_info pi;
            memset(&pi, 0, sizeof(pi));

            ngtcp2_tstamp now = quic_timestamp();
            rv = ngtcp2_conn_read_pkt(qc->conn, &path, &pi, buf, (size_t)n, now);
            if (rv != 0) {
                qc->closed = 1;
                continue;
            }

            /* Write response packets */
            quic_write_streams(qc, fd);
        } else {
            /* New connection — decode full header for version and DCID */
            ngtcp2_pkt_hd hdr;
            rv = ngtcp2_accept(&hdr, buf, (size_t)n);
            if (rv != 0) { fprintf(stderr, "[h3] ngtcp2_accept: %d (%s)\n", rv, ngtcp2_strerror(rv)); continue; }

            WQuicConn *new_qc = quic_new_connection(fd, buf, (size_t)n, &hdr,
                                                     (struct sockaddr *)&local_ss, local_sslen,
                                                     (struct sockaddr *)&remote, remote_len,
                                                     handler);
            if (new_qc) {
                quic_write_streams(new_qc, fd);
            }
        }
    }

    close(fd);
}

#endif /* TUNGSTEN_HTTP3 */
