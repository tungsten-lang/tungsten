#ifndef W_RUNTIME_UNITY_INCLUDE
#ifdef __linux__
#define _GNU_SOURCE
#include <sched.h>
#endif
#include "runtime_internal.h"
#include <arpa/inet.h>
#include <ctype.h>
#include <errno.h>
#include <fcntl.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <poll.h>
#include <pthread.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <sys/uio.h>
#include <time.h>
#include <unistd.h>
extern __thread WGoroutine *g_current;
extern ssize_t w_tls_read(WSocket *s, char *buf, size_t len);
extern ssize_t w_tls_write(WSocket *s, const char *buf, size_t len);
#define die w_rt_die
#define as_str w_rt_as_str
#define w_rope_len w_rt_rope_len
#define w_rope_write w_rt_rope_write
#define call_closure_1 w_rt_call_closure_1
#define w_socket_park_uring w_rt_socket_park_uring
#define w_fd_set_nonblocking w_rt_fd_set_nonblocking
#endif

/* ---- HTTP Response ---- */

/* Response pool — reuse WResponse structs instead of malloc per request.
 * Thread-local so each worker thread recycles independently (zero contention). */
#define RESPONSE_POOL_MAX 16
static __thread WResponse *g_response_pool[RESPONSE_POOL_MAX];
static __thread int g_response_pool_count = 0;

static inline WResponse *w_response_alloc(void) {
    WResponse *r;
    if (g_response_pool_count > 0) {
        r = g_response_pool[--g_response_pool_count];
    } else {
        r = calloc(1, sizeof(WResponse));
    }
    return r;
}

WValue w_response_new(int status, const char *body, size_t body_len) {
    WResponse *r = w_response_alloc();
    r->type = W_TYPE_RESPONSE;
    r->body_kind = W_BODY_PTR;
    r->status = status;
    r->body = body;
    r->body_len = body_len;
    r->body_val = 0;
    return w_box_ptr(r, W_SUBTAG_GENERIC);
}

/* Direct constructor for compiled code — skips method dispatch entirely */
WValue w_response_new_wv(WValue status_val, WValue body_val) {
    int status = (int)w_as_int(status_val);
    if (w_is_rope(body_val)) {
        WResponse *r = w_response_alloc();
        r->type = W_TYPE_RESPONSE;
        r->body_kind = W_BODY_ROPE;
        r->status = status;
        r->body = NULL;
        r->body_len = w_rope_len(body_val);
        r->body_val = body_val;
        return w_box_ptr(r, W_SUBTAG_GENERIC);
    }
    if (w_is_strbuf(body_val)) {
        WStrBuf *sb = (WStrBuf *)w_as_ptr(body_val);
        WResponse *r = w_response_alloc();
        r->type = W_TYPE_RESPONSE;
        r->body_kind = W_BODY_STRBUF;
        r->status = status;
        r->body = sb->data;
        r->body_len = (size_t)sb->size;
        r->body_val = body_val;
        return w_box_ptr(r, W_SUBTAG_GENERIC);
    }

    const char *body;
    size_t body_len;
    char inline_buf[6];
    w_str_data(body_val, inline_buf, &body, &body_len);

    WResponse *r = w_response_alloc();
    r->type = W_TYPE_RESPONSE;
    r->body_kind = W_BODY_PTR;
    r->status = status;
    r->body_len = body_len;
    r->body_val = 0;
    if (body == inline_buf) {
        memcpy(r->body_inline, inline_buf, body_len + 1);
        r->body_kind = W_BODY_INLINE;
        r->body = r->body_inline;
    } else {
        r->body = body;
    }
    return w_box_ptr(r, W_SUBTAG_GENERIC);
}

static inline void w_response_recycle(WResponse *r) {
    r->body = NULL;
    r->body_len = 0;
    r->body_val = 0;
    r->body_kind = W_BODY_PTR;
    if (g_response_pool_count < RESPONSE_POOL_MAX) {
        g_response_pool[g_response_pool_count++] = r;
    }
}

/* ---- HTTP/1.1 Zero-Copy Parser ---- */

typedef enum {
    HTTP_PARSE_OK,
    HTTP_PARSE_INCOMPLETE,
    HTTP_PARSE_ERROR
} HttpParseResult;

typedef struct {
    const char *method;
    int method_len;
    const char *path;
    int path_len;
    int header_end;       /* offset past \r\n\r\n */
    int64_t content_length;   /* -1 if not present */
    int keep_alive;       /* 1 = keep-alive, 0 = close */
} HttpRequest;

/* Strict, bounded integer parser for Content-Length values.
 *
 * Rejects any non-digit byte (atoi would accept leading whitespace, +/-, and
 * trailing garbage). Returns 1 on success and writes the value to *out; returns
 * 0 on parse error (caller treats as HTTP_PARSE_ERROR). Caps at 100 MiB —
 * larger bodies should use a streaming protocol, and accepting unbounded
 * Content-Length is a DoS vector (the parser advances buf_pos by this many
 * bytes). int64_t holds the value without overflow on any platform.
 *
 * RFC 7230 §3.3.2: Content-Length = 1*DIGIT. Anything else is malformed.
 */
static int parse_content_length_strict(const char *s, const char *end, int64_t *out) {
    int64_t v = 0;
    const int64_t cap = 100LL * 1024 * 1024; /* 100 MiB */
    int saw_digit = 0;
    while (s < end) {
        char c = *s;
        if (c < '0' || c > '9') return 0;
        v = v * 10 + (c - '0');
        if (v > cap) return 0;
        saw_digit = 1;
        s++;
    }
    if (!saw_digit) return 0;
    *out = v;
    return 1;
}

static HttpParseResult w_http1_parse(const char *buf, int len, HttpRequest *req) {
    /* Find end of headers — scan for \r\n\r\n using 4-byte word match */
    const char *hdr_end = NULL;
    if (len >= 4) {
        const char *p = buf;
        const char *end = buf + len - 3;
        while (p < end) {
            /* Fast skip: if current byte isn't \r, advance past it */
            if (p[0] != '\r') { p++; continue; }
            if (p[1] == '\n' && p[2] == '\r' && p[3] == '\n') {
                hdr_end = p;
                break;
            }
            p++;
        }
    }
    if (!hdr_end) return HTTP_PARSE_INCOMPLETE;

    req->header_end = (int)(hdr_end - buf) + 4;

    /* Parse request line: METHOD SP PATH SP HTTP/x.x */
    req->method = buf;
    const char *sp1 = memchr(buf, ' ', hdr_end - buf);
    if (!sp1) return HTTP_PARSE_ERROR;
    req->method_len = (int)(sp1 - buf);

    req->path = sp1 + 1;
    const char *sp2 = memchr(req->path, ' ', hdr_end - req->path);
    if (!sp2) return HTTP_PARSE_ERROR;
    req->path_len = (int)(sp2 - req->path);

    /* Default: HTTP/1.1 keeps alive, HTTP/1.0 closes */
    req->keep_alive = (sp2[6] == '1' && sp2[8] == '1') ? 1 : 0;
    req->content_length = -1;

    /* Scan headers for Connection:, Content-Length:, Transfer-Encoding:.
     *
     * Security notes:
     *   - Duplicate Content-Length → HTTP_PARSE_ERROR (RFC 7230 §3.3.2
     *     requires rejection; a frontend that picks a different header than us
     *     enables request smuggling).
     *   - Content-Length is parsed strictly (digits only, capped at 100 MiB).
     *     atoi accepts garbage and has integer-overflow UB.
     *   - Transfer-Encoding of anything other than "identity" is rejected
     *     because this parser does not implement chunked decoding. Accepting
     *     such a request while ignoring the encoding would mis-frame the next
     *     request on a keep-alive connection (smuggling). RFC 7230 §3.3.3
     *     says TE wins over CL; we treat TE-with-CL as the smuggling attempt
     *     it usually is and reject.
     */
    int saw_content_length = 0;
    int saw_transfer_encoding = 0;
    const char *p = memchr(sp2, '\n', hdr_end - sp2);
    if (p) p++;
    while (p && p < hdr_end) {
        /* memchr up to hdr_end INCLUSIVE: hdr_end points at the \r that
         * terminates the final header line (the first \r of \r\n\r\n), so a
         * search range of [p, hdr_end) would miss it and skip the last header.
         * This was a latent bug that hid CL parsing when CL was the only/last
         * header — fixed alongside the strict CL hardening. */
        const char *line_end = memchr(p, '\r', hdr_end - p + 1);
        if (!line_end) break;
        int line_len = (int)(line_end - p);

        if (line_len > 11 && (p[0] == 'C' || p[0] == 'c')) {
            if (strncasecmp(p, "Connection:", 11) == 0) {
                const char *val = p + 11;
                while (*val == ' ') val++;
                if (strncasecmp(val, "close", 5) == 0)
                    req->keep_alive = 0;
                else if (strncasecmp(val, "keep-alive", 10) == 0)
                    req->keep_alive = 1;
            } else if (strncasecmp(p, "Content-Length:", 15) == 0) {
                /* Duplicate Content-Length is a smuggling primitive. */
                if (saw_content_length) return HTTP_PARSE_ERROR;
                const char *val_start = p + 15;
                const char *val_end = line_end;
                while (val_start < val_end && *val_start == ' ') val_start++;
                int64_t cl;
                if (!parse_content_length_strict(val_start, val_end, &cl))
                    return HTTP_PARSE_ERROR;
                req->content_length = cl;
                saw_content_length = 1;
            }
        } else if (line_len > 17 && (p[0] == 'T' || p[0] == 't')) {
            if (strncasecmp(p, "Transfer-Encoding:", 18) == 0) {
                const char *val = p + 18;
                while (val < line_end && *val == ' ') val++;
                /* "identity" is a no-op; anything else (chunked, etc.) we
                 * can't decode here, so reject the request. */
                if (strncasecmp(val, "identity", 8) != 0) {
                    return HTTP_PARSE_ERROR;
                }
                saw_transfer_encoding = 1;
            }
        }
        p = line_end + 2; /* skip \r\n */
    }

    /* TE + CL together is the canonical smuggling vector. */
    if (saw_transfer_encoding && saw_content_length)
        return HTTP_PARSE_ERROR;

    return HTTP_PARSE_OK;
}

/* ---- HTTP/1.1 Keep-Alive Connection Loop ---- */

/* Pre-built error response */
static const char HTTP_500_RESP[] =
    "HTTP/1.1 500 Internal Server Error\r\n"
    "Content-Length: 22\r\n"
    "Connection: close\r\n\r\n"
    "Internal Server Error\n";

/* Write raw bytes to socket (TLS-aware), no parking — used for HTTP response framing */
/* Write all bytes to socket (TLS-aware) with parking.
 * When kTLS is active, bypasses SSL_write and uses direct write() — the kernel
 * handles TLS encryption, avoiding OpenSSL userspace overhead. */
static ssize_t sock_write_all(WSocket *s, const char *buf, size_t len) {
    size_t written = 0;
    while (written < len) {
        ssize_t n;
#ifdef TUNGSTEN_TLS
        if (s->ssl && !s->ktls) {
            /* Userspace TLS — OpenSSL encrypts */
            extern ssize_t w_tls_write(WSocket *s, const char *buf, size_t len);
            n = w_tls_write(s, buf + written, len - written);
        } else
#endif
        {
            /* Plain socket or kTLS — kernel handles encryption if TLS active */
            n = write(s->fd, buf + written, len - written);
            if (n < 0) {
                if (errno == EINTR) continue;
                if (errno == EAGAIN || errno == EWOULDBLOCK) {
                    /* io_uring completion send disabled — readiness is faster
                     * for pipelined HTTP where write() usually succeeds on
                     * first attempt. The submit+CQE+eventfd overhead exceeds
                     * the benefit of avoiding the write() retry. */
                    WGoroutine *g = g_current;
                    WEventLoop *el = w_rt_get_coop_event_loop();
                    if (0 && g && el &&
                        w_event_submit_send(el, s->fd, buf + written,
                                            len - written, g) == 0) {
                        w_socket_park_uring();
                        if (g->io_result > 0) {
                            written += g->io_result;
                            continue;
                        }
                        if (g->io_result == -EAGAIN) continue;
                        return -1;
                    }
                    w_socket_park(s->fd, W_EVENT_WRITE);
                    continue;
                }
                return -1;
            }
        }
        if (n <= 0) return -1;
        written += n;
    }
    return (ssize_t)written;
}

static ssize_t sock_writev_all(WSocket *s, struct iovec *iov, int iovcnt) {
#ifdef TUNGSTEN_TLS
    if (s->ssl && !s->ktls) {
        ssize_t total = 0;
        for (int i = 0; i < iovcnt; i++) {
            ssize_t n = sock_write_all(s, (const char *)iov[i].iov_base, iov[i].iov_len);
            if (n < 0) return n;
            total += n;
        }
        return total;
    }
#endif

    ssize_t total = 0;
    while (iovcnt > 0) {
        ssize_t n = writev(s->fd, iov, iovcnt);
        if (n > 0) {
            total += n;
            while (iovcnt > 0 && (size_t)n >= iov[0].iov_len) {
                n -= (ssize_t)iov[0].iov_len;
                iov++;
                iovcnt--;
            }
            if (iovcnt > 0 && n > 0) {
                iov[0].iov_base = (char *)iov[0].iov_base + n;
                iov[0].iov_len -= (size_t)n;
            }
            continue;
        }
        if (n < 0) {
            if (errno == EINTR) continue;
            if (errno == EAGAIN || errno == EWOULDBLOCK) {
                w_socket_park(s->fd, W_EVENT_WRITE);
                continue;
            }
            return -1;
        }
        return -1;
    }
    return total;
}

/* Read from socket (TLS-aware) with parking.
 * When kTLS is active, bypasses SSL_read and uses direct read() — the kernel
 * handles TLS decryption, avoiding OpenSSL userspace overhead. */
static ssize_t sock_read(WSocket *s, char *buf, size_t len) {
    while (1) {
        ssize_t n;
#ifdef TUNGSTEN_TLS
        if (s->ssl && !s->ktls) {
            /* Userspace TLS — OpenSSL decrypts */
            extern ssize_t w_tls_read(WSocket *s, char *buf, size_t len);
            n = w_tls_read(s, buf, len);
        } else
#endif
        {
            /* Plain socket or kTLS — kernel handles decryption if TLS active */
            n = read(s->fd, buf, len);
        }
        if (n > 0) return n;
        if (n == 0) return 0; /* EOF */
        if (errno == EINTR) continue;
        if (errno == EAGAIN || errno == EWOULDBLOCK) {
            /* io_uring completion recv disabled — same rationale as send:
             * read() fast path succeeds immediately under pipelining. */
            WGoroutine *g = g_current;
            WEventLoop *el = w_rt_get_coop_event_loop();
            if (0 && g && el &&
                w_event_submit_recv(el, s->fd, buf, len, g) == 0) {
                w_socket_park_uring();
                if (g->io_result > 0) return g->io_result;
                if (g->io_result == 0) return 0;
                if (g->io_result == -EAGAIN) continue;
                return -1;
            }
            w_socket_park(s->fd, W_EVENT_READ);
            continue;
        }
        return -1;
    }
}

/* Fast integer-to-string for Content-Length (avoids snprintf) */
static int uint_to_str(size_t val, char *buf) {
    if (val == 0) { buf[0] = '0'; return 1; }
    char tmp[20];
    int len = 0;
    while (val > 0) { tmp[len++] = '0' + (val % 10); val /= 10; }
    for (int i = 0; i < len; i++) buf[i] = tmp[len - 1 - i];
    return len;
}

/* Pre-computed response templates — fill in content-length + body at write time.
 * This avoids snprintf (which is ~200ns) on every request. */
static const char RESP_200_KA_PREFIX[] = "HTTP/1.1 200 OK\r\nContent-Length: ";
static const char RESP_200_CL_PREFIX[] = "HTTP/1.1 200 OK\r\nContent-Length: ";

/* Cached Date header — refreshed once per second, zero cost per request.
 * Format: "Date: Mon, 23 Mar 2026 09:37:15 GMT\r\n" (fixed 37 bytes) */
static __thread char g_date_header[40] = "Date: Thu, 01 Jan 1970 00:00:00 GMT\r\n";
static __thread time_t g_date_epoch = 0;

static void refresh_date_header(void) {
    time_t now = time(NULL);
    if (now != g_date_epoch) {
        g_date_epoch = now;
        struct tm tm;
        gmtime_r(&now, &tm);
        strftime(g_date_header, sizeof(g_date_header), "Date: %a, %d %b %Y %H:%M:%S GMT\r\n", &tm);
    }
}

/* Suffix after content-length value: \r\nDate: ...\r\nConnection: keep-alive|close\r\n\r\n
 * Built dynamically since date changes, but only once per second.
 * When cap reporting is enabled, includes X-Forge-G (active goroutines)
 * and X-Forge-QD (run queue depth) for Hammer auto-tuning. */
static __thread char g_suffix_ka[256];
static __thread int  g_suffix_ka_len;
static __thread char g_suffix_cl[256];
static __thread int  g_suffix_cl_len;
static __thread int  g_suffix_version;
static __thread int  g_suffix_mode = -1;

/* Optional Forge benchmark headers. Disabled by default; bin/tungsten forge
 * enables them with --cap for interactive tuning. */
static volatile int g_forge_capacity_headers = 0;
static volatile int g_forge_date_header = 1;
static volatile int g_forge_resp_buf_size = 32768;
static volatile int g_forge_nopush = 0;
static volatile int g_forge_options_loaded = 0;

static void forge_load_options(void) {
    if (g_forge_options_loaded) return;
    const char *cap = getenv("TUNGSTEN_FORGE_CAPACITY");
    const char *max_mode = getenv("TUNGSTEN_FORGE_MAX");
    const char *resp_buf_size = getenv("TUNGSTEN_FORGE_RESP_BUF");
    const char *nopush = getenv("TUNGSTEN_FORGE_NOPUSH");
    g_forge_capacity_headers = (cap && cap[0] && cap[0] != '0') ? 1 : 0;
    if (max_mode && max_mode[0] && max_mode[0] != '0') {
        g_forge_capacity_headers = 0;
        g_forge_date_header = 0;
    }
    if (resp_buf_size && resp_buf_size[0]) {
        int size = atoi(resp_buf_size);
        if (size >= 4096 && size <= 262144) g_forge_resp_buf_size = size;
    }
    g_forge_nopush = (nopush && nopush[0] && nopush[0] != '0') ? 1 : 0;
    w_goroutine_count_set_enabled(g_forge_capacity_headers);
    g_forge_options_loaded = 1;
}

static void forge_print_stats(int sig) {
    (void)sig;
    _exit(0);
}

static void refresh_response_suffixes(void) {
    int mode = (g_forge_date_header ? 1 : 0) | (g_forge_capacity_headers ? 2 : 0);
    if (!g_forge_date_header && !g_forge_capacity_headers && g_suffix_mode == mode) {
        return;
    }

    if (g_forge_date_header || g_forge_capacity_headers) {
        time_t now = time(NULL);
        if (__builtin_expect(now == g_date_epoch && g_suffix_mode == mode, 1)) return;
        g_date_epoch = now;
        if (g_forge_date_header) {
            struct tm tm;
            gmtime_r(&now, &tm);
            strftime(g_date_header, sizeof(g_date_header), "Date: %a, %d %b %Y %H:%M:%S GMT\r\n", &tm);
        } else {
            g_date_header[0] = '\0';
        }
    }

    if (g_forge_capacity_headers) {
        int64_t goroutines = w_goroutine_count();
        int qd = w_scheduler_queue_depth();
        g_suffix_ka_len = snprintf(g_suffix_ka, sizeof(g_suffix_ka),
            "\r\n%sConnection: keep-alive\r\nX-Forge-G: %lld\r\nX-Forge-QD: %d\r\n\r\n",
            g_date_header, (long long)goroutines, qd);
        g_suffix_cl_len = snprintf(g_suffix_cl, sizeof(g_suffix_cl),
            "\r\n%sConnection: close\r\nX-Forge-G: %lld\r\nX-Forge-QD: %d\r\n\r\n",
            g_date_header, (long long)goroutines, qd);
    } else {
        g_suffix_ka_len = snprintf(g_suffix_ka, sizeof(g_suffix_ka),
            "\r\n%sConnection: keep-alive\r\n\r\n", g_forge_date_header ? g_date_header : "");
        g_suffix_cl_len = snprintf(g_suffix_cl, sizeof(g_suffix_cl),
            "\r\n%sConnection: close\r\n\r\n", g_forge_date_header ? g_date_header : "");
    }
    g_suffix_mode = mode;
    g_suffix_version++;
}

#define ROPE_IOV_MAX 64

typedef struct {
    WSocket *conn;
    struct iovec iov[ROPE_IOV_MAX];
    char inline_buf[ROPE_IOV_MAX][6];
    int count;
} RopeIovWriter;

static int rope_iov_flush(RopeIovWriter *w) {
    if (w->count == 0) return 0;
    int count = w->count;
    w->count = 0;
    return sock_writev_all(w->conn, w->iov, count) < 0 ? -1 : 0;
}

static int rope_iov_push(RopeIovWriter *w, const char *data, size_t len) {
    if (len == 0) return 0;
    if (w->count >= ROPE_IOV_MAX && rope_iov_flush(w) < 0) return -1;
    w->iov[w->count].iov_base = (void *)data;
    w->iov[w->count].iov_len = len;
    w->count++;
    return 0;
}

static int rope_iov_push_value(RopeIovWriter *w, WValue v) {
    if (w_is_rope(v)) {
        WRope *r = (WRope *)w_as_ptr(v);
        if (r->flat) return rope_iov_push_value(w, r->flat);
        if (rope_iov_push_value(w, r->left) < 0) return -1;
        return rope_iov_push_value(w, r->right);
    }

    if (w->count >= ROPE_IOV_MAX && rope_iov_flush(w) < 0) return -1;
    char *tmp = w->inline_buf[w->count];
    const char *s;
    size_t len;
    w_str_data(v, tmp, &s, &len);
    if (len == 0) return 0;
    w->iov[w->count].iov_base = (void *)s;
    w->iov[w->count].iov_len = len;
    w->count++;
    return 0;
}

static int w_http1_write_value_response(WSocket *conn, int status, int keep_alive, size_t body_len, WValue body_val) {
    char header[512];
    char *hp = header;
    const char *suffix;
    int suffix_len;

    if (__builtin_expect(status == 200, 1)) {
        const char *prefix = keep_alive ? RESP_200_KA_PREFIX : RESP_200_CL_PREFIX;
        int prefix_len = keep_alive ? (int)sizeof(RESP_200_KA_PREFIX) - 1 : (int)sizeof(RESP_200_CL_PREFIX) - 1;
        suffix = keep_alive ? g_suffix_ka : g_suffix_cl;
        suffix_len = keep_alive ? g_suffix_ka_len : g_suffix_cl_len;
        memcpy(hp, prefix, prefix_len); hp += prefix_len;
        hp += uint_to_str(body_len, hp);
        memcpy(hp, suffix, suffix_len); hp += suffix_len;
    } else {
        refresh_date_header();
        hp += snprintf(hp, sizeof(header),
            keep_alive
                ? "HTTP/1.1 %d OK\r\nContent-Length: %zu\r\n%sConnection: keep-alive\r\n\r\n"
                : "HTTP/1.1 %d OK\r\nContent-Length: %zu\r\n%sConnection: close\r\n\r\n",
            status, body_len, g_date_header);
    }

    RopeIovWriter writer = {.conn = conn, .count = 0};
    if (rope_iov_push(&writer, header, (size_t)(hp - header)) < 0) return -1;
    if (body_len > 0 && rope_iov_push_value(&writer, body_val) < 0) return -1;
    return rope_iov_flush(&writer);
}

static void w_http1_connection_loop(WSocket *conn, WClosure *handler) {
    char buf[8192];
    int buf_pos = 0;
    int buf_end = 0;

    /* Stack-allocated path buffer — avoids malloc per request */
    char path_buf[2048];

    /* Batched response buffer — accumulates multiple responses for one write().
     * 32KB fits the full Hammer -b128 default response burst while staying
     * within the goroutine stack budget. */
    forge_load_options();
    char stack_resp_buf[32768];
    char *heap_resp_buf = NULL;
    int resp_buf_size = g_forge_resp_buf_size;
    if (resp_buf_size <= (int)sizeof(stack_resp_buf)) {
        resp_buf_size = (int)sizeof(stack_resp_buf);
    } else {
        heap_resp_buf = malloc((size_t)resp_buf_size);
        if (!heap_resp_buf) resp_buf_size = (int)sizeof(stack_resp_buf);
    }
    char *resp_buf = heap_resp_buf ? heap_resp_buf : stack_resp_buf;
    char cached_200_ka[512];
    const char *cached_200_body = NULL;
    size_t cached_200_body_len = 0;
    int cached_200_len = 0;
    int cached_200_suffix_version = -1;

    while (1) {
        if (buf_pos == buf_end) {
            buf_pos = 0;
            buf_end = 0;
        } else if (buf_end == (int)sizeof(buf) && buf_pos > 0) {
            int remaining = buf_end - buf_pos;
            memmove(buf, buf + buf_pos, remaining);
            buf_pos = 0;
            buf_end = remaining;
        }

        int read_closed = 0;

        /* Read more data into buffer (skip if we already have unparsed requests) */
        if (buf_end < (int)sizeof(buf)) {
            ssize_t n = sock_read(conn, buf + buf_end, sizeof(buf) - buf_end);
            if (n <= 0) {
                if (buf_pos == buf_end) break;
                read_closed = 1;
                /* Fall through to process remaining buffered requests */
            } else {
                buf_end += n;
            }
        }

        /* Process complete requests, batching responses into resp_buf.
         * When resp_buf fills up, flush and loop back to process more
         * without reading — handles deep pipelines (>16 requests). */
    process_batch:;
        char *rp = resp_buf;
        char *rp_end = resp_buf + resp_buf_size - 512; /* leave room */
        int close_after = 0;
        int batch_count = 0;

        /* Refresh date header once per batch */
        refresh_response_suffixes();

        /* Per-batch exception frame — one _setjmp per read batch instead of per request.
         * Saves ~4% CPU on the hot path (setjmp was ~30ns per call). */
        WExceptionFrame *prev_stack = w_exception_stack;
        WExceptionFrame frame;
        w_exception_frame_push(&frame);
        volatile int handler_error = 0;

        if (W_FAST_SETJMP(frame.buf) != 0) {
            /* Handler raised an exception — send 500 for current request */
            handler_error = 1;
        }

        while (buf_pos < buf_end && rp < rp_end) {
            HttpRequest req;
            HttpParseResult result = w_http1_parse(buf + buf_pos, buf_end - buf_pos, &req);
            if (result == HTTP_PARSE_INCOMPLETE) break;
            if (result == HTTP_PARSE_ERROR) { close_after = 1; break; }

            /* Build request path — inline for short paths */
            int path_len = req.path_len < (int)sizeof(path_buf) - 1 ? req.path_len : (int)sizeof(path_buf) - 1;
            WValue req_val;
            if (path_len <= 5) {
                memcpy(path_buf, req.path, path_len);
                path_buf[path_len] = '\0';
                req_val = w_box_inline_str(path_buf, path_len);
            } else {
                memcpy(path_buf, req.path, path_len);
                path_buf[path_len] = '\0';
                req_val = w_string(path_buf);
            }

            /* Call handler — exception jumps back to the _setjmp above */
            WValue response;
            if (handler_error) {
                handler_error = 0;
                /* Flush batch, send 500, consume request */
                if (rp > resp_buf) {
                    sock_write_all(conn, resp_buf, rp - resp_buf);
                    rp = resp_buf;
                }
                sock_write_all(conn, HTTP_500_RESP, sizeof(HTTP_500_RESP) - 1);
                if (!req.keep_alive) { close_after = 1; }
                int consumed = req.header_end;
                if (req.content_length > 0) consumed += req.content_length;
                buf_pos += consumed;
                if (buf_pos >= buf_end) {
                    buf_pos = 0;
                    buf_end = 0;
                }
                continue;
            }

            response = call_closure_1(handler, req_val);

            /* Extract response fields */
            const char *body;
            size_t body_len;
            WValue body_val = 0;
            char body_tmp[6];
            int status;
            int body_kind = W_BODY_PTR;

            WResponse *resp_to_recycle = NULL;
            if (w_is_response(response)) {
                WResponse *r = (WResponse *)w_as_ptr(response);
                status = r->status;
                body_len = r->body_len;
                body_val = r->body_val;
                body = r->body;
                body_kind = r->body_kind;
                resp_to_recycle = r;
            } else if (w_is_string(response) || w_is_rope(response)) {
                status = 200;
                body_val = response;
                if (w_is_rope(response)) {
                    body = NULL;
                    body_len = w_rope_len(response);
                    body_kind = W_BODY_ROPE;
                } else {
                    w_str_data(response, body_tmp, &body, &body_len);
                    body_kind = body == body_tmp ? W_BODY_INLINE : W_BODY_PTR;
                }
            } else {
                status = 200;
                body = "";
                body_len = 0;
                body_kind = W_BODY_PTR;
            }

            int body_is_rope = body_kind == W_BODY_ROPE || (body_val && w_is_rope(body_val));
            int body_is_mutable = body_kind == W_BODY_STRBUF;
            int max_header_size = 256;  /* generous upper bound for headers */

            /* Bodies >= 8KB bypass the batch-buffer memcpy and go straight to
             * writev(header, body). Threshold chosen by A/B: flat at 8KB,
             * +2.6% req/s at 16KB. Ropes always take this path. */
            int body_is_large = !body_is_rope && !body_is_mutable && body_len >= 8192;
            if (body_is_rope || body_is_large) {
                if (body_is_rope && max_header_size + (int)body_len >= (int)(rp_end - resp_buf)) {
                    /* existing rope path */
                } else if (!body_is_rope) {
                    /* fall through to normal append for small bodies */
                    goto small_body_append;
                }
                if (rp > resp_buf) {
                    sock_write_all(conn, resp_buf, rp - resp_buf);
                    rp = resp_buf;
                }
                if (body_is_large) {
                    /* writev(header_iov, body_iov) — header built on stack, body by ref */
                    char hdr[512];
                    char *hp2 = hdr;
                    if (__builtin_expect(status == 200, 1)) {
                        const char *prefix = req.keep_alive ? RESP_200_KA_PREFIX : RESP_200_CL_PREFIX;
                        int prefix_len = req.keep_alive ? (int)sizeof(RESP_200_KA_PREFIX) - 1 : (int)sizeof(RESP_200_CL_PREFIX) - 1;
                        const char *suffix2 = req.keep_alive ? g_suffix_ka : g_suffix_cl;
                        int suffix2_len = req.keep_alive ? g_suffix_ka_len : g_suffix_cl_len;
                        memcpy(hp2, prefix, prefix_len); hp2 += prefix_len;
                        hp2 += uint_to_str(body_len, hp2);
                        memcpy(hp2, suffix2, suffix2_len); hp2 += suffix2_len;
                    } else {
                        refresh_date_header();
                        hp2 += snprintf(hp2, sizeof(hdr),
                            req.keep_alive
                                ? "HTTP/1.1 %d OK\r\nContent-Length: %zu\r\n%sConnection: keep-alive\r\n\r\n"
                                : "HTTP/1.1 %d OK\r\nContent-Length: %zu\r\n%sConnection: close\r\n\r\n",
                            status, body_len, g_date_header);
                    }
                    struct iovec iov[2];
                    iov[0].iov_base = hdr; iov[0].iov_len = (size_t)(hp2 - hdr);
                    iov[1].iov_base = (void *)body; iov[1].iov_len = body_len;
                    if (sock_writev_all(conn, iov, 2) < 0) close_after = 1;
                } else if (w_http1_write_value_response(conn, status, req.keep_alive, body_len, body_val) < 0) {
                    close_after = 1;
                }
                if (resp_to_recycle) w_response_recycle(resp_to_recycle);
                if (!req.keep_alive) close_after = 1;

                int consumed = req.header_end;
                if (req.content_length > 0) consumed += req.content_length;
                buf_pos += consumed;
                if (buf_pos >= buf_end) {
                    buf_pos = 0;
                    buf_end = 0;
                }
                batch_count++;
                if (close_after) break;
                continue;
            }
        small_body_append:;

            /* Append response to batch buffer.
             * Flush if the complete response (headers + body) won't fit. */
            if (rp + max_header_size + (int)body_len >= rp_end && rp > resp_buf) {
                if (body_is_mutable) {
                    body_val = w_strbuf_to_s(body_val);
                    body_kind = W_BODY_PTR;
                    body_is_mutable = 0;
                    w_str_data(body_val, body_tmp, &body, &body_len);
                }
                sock_write_all(conn, resp_buf, rp - resp_buf);
                rp = resp_buf;
            }

            if (__builtin_expect(status == 200, 1)) {
                const char *prefix, *suffix;
                int prefix_len, suffix_len;
                if (req.keep_alive) {
                    prefix = RESP_200_KA_PREFIX; prefix_len = sizeof(RESP_200_KA_PREFIX) - 1;
                    suffix = g_suffix_ka; suffix_len = g_suffix_ka_len;
                } else {
                    prefix = RESP_200_CL_PREFIX; prefix_len = sizeof(RESP_200_CL_PREFIX) - 1;
                    suffix = g_suffix_cl; suffix_len = g_suffix_cl_len;
                }

                int can_cache_200 = !body_is_rope && !body_is_mutable && req.keep_alive && resp_to_recycle && body_len <= 128;
                if (can_cache_200 &&
                    cached_200_body == body &&
                    cached_200_body_len == body_len &&
                    cached_200_suffix_version == g_suffix_version) {
                    if (rp + cached_200_len >= rp_end && rp > resp_buf) {
                        sock_write_all(conn, resp_buf, rp - resp_buf);
                        rp = resp_buf;
                    }
                    memcpy(rp, cached_200_ka, cached_200_len);
                    rp += cached_200_len;
                    body_len = 0;
                } else if (can_cache_200) {
                    char *cp = cached_200_ka;
                    memcpy(cp, prefix, prefix_len); cp += prefix_len;
                    cp += uint_to_str(body_len, cp);
                    memcpy(cp, suffix, suffix_len); cp += suffix_len;
                    if (body_len > 0) {
                        memcpy(cp, body, body_len);
                        cp += body_len;
                    }
                    cached_200_body = body;
                    cached_200_body_len = body_len;
                    cached_200_suffix_version = g_suffix_version;
                    cached_200_len = (int)(cp - cached_200_ka);

                    if (rp + cached_200_len >= rp_end && rp > resp_buf) {
                        sock_write_all(conn, resp_buf, rp - resp_buf);
                        rp = resp_buf;
                    }
                    memcpy(rp, cached_200_ka, cached_200_len);
                    rp += cached_200_len;
                    body_len = 0;
                } else {
                    memcpy(rp, prefix, prefix_len); rp += prefix_len;
                    rp += uint_to_str(body_len, rp);
                    memcpy(rp, suffix, suffix_len); rp += suffix_len;
                }
            } else {
                refresh_date_header();
                rp += snprintf(rp, rp_end - rp,
                    req.keep_alive
                        ? "HTTP/1.1 %d OK\r\nContent-Length: %zu\r\n%sConnection: keep-alive\r\n\r\n"
                        : "HTTP/1.1 %d OK\r\nContent-Length: %zu\r\n%sConnection: close\r\n\r\n",
                    status, body_len, g_date_header);
            }

            if (body_len > 0) {
                if (body_is_rope) {
                    uint32_t pos = 0;
                    w_rope_write(body_val, rp, &pos);
                    rp += pos;
                } else {
                    memcpy(rp, body, body_len);
                    rp += body_len;
                }
            }

            if (resp_to_recycle) w_response_recycle(resp_to_recycle);
            if (!req.keep_alive) close_after = 1;

            /* Consume parsed request from buffer */
            int consumed = req.header_end;
            if (req.content_length > 0) consumed += req.content_length;
            buf_pos += consumed;
            if (buf_pos >= buf_end) {
                buf_pos = 0;
                buf_end = 0;
            }
            batch_count++;

            if (close_after) break;
        }

        /* Pop per-batch exception frame */
        w_exception_stack = prev_stack;

        /* Flush the batched responses in a single write */
        if (rp > resp_buf) {
            sock_write_all(conn, resp_buf, rp - resp_buf);
        }

        if (close_after) break;

        /* If we still have unparsed requests (resp_buf was full), process
         * them immediately without waiting for more data from the socket.
         * This prevents deadlock with deep pipelines (e.g. 32+ requests). */
        if (buf_pos < buf_end && batch_count > 0) goto process_batch;

        /* If we parsed nothing (incomplete), loop back to read more */
        if (batch_count == 0 && read_closed) {
            break; /* peer closed with a partial request buffered */
        }
        if (batch_count == 0 && buf_end >= (int)sizeof(buf) && buf_pos == 0) {
            break; /* buffer full but no complete request — bad client */
        }
    }

    free(heap_resp_buf);
    close(conn->fd);
    conn->closed = 1;
}

/* ---- serve_http: accept loop with goroutine dispatch ---- */

/* Goroutine entry for HTTP connection handling */
typedef struct {
    WSocket *conn;
    WClosure *handler;
} HttpConnArg;

/* Forward declaration for HTTP/2 */
#ifdef TUNGSTEN_HTTP2
extern void w_http2_serve_connection(WSocket *conn, WClosure *handler);
#endif

static WValue http_conn_goroutine_fn(WValue *captures, WValue arg) {
    (void)arg;
    HttpConnArg *a = (HttpConnArg *)w_as_ptr(captures[0]);

#ifdef TUNGSTEN_TLS
    /* Auto-wrap in TLS when server TLS context is configured */
    if (w_tls_server_configured()) {
        WExceptionFrame *prev_stack = w_exception_stack;
        WExceptionFrame exc_frame;
        w_exception_frame_push(&exc_frame);

        if (W_FAST_SETJMP(exc_frame.buf) == 0) {
            WValue sock_val = w_box_ptr(a->conn, W_SUBTAG_GENERIC);
            w_tls_wrap(sock_val);
            w_exception_stack = prev_stack;
        } else {
            /* TLS handshake failed (scanner bot, malformed ClientHello, etc.) */
            w_exception_stack = prev_stack;
            close(a->conn->fd);
            a->conn->closed = 1;
            return W_NIL;
        }
    }
#endif

#ifdef TUNGSTEN_HTTP2
    /* Check ALPN — if negotiated "h2", use HTTP/2 */
    WValue alpn = w_socket_alpn_protocol(w_box_ptr(a->conn, W_SUBTAG_GENERIC));
    if (w_is_string(alpn) && strcmp(as_str(alpn), "h2") == 0) {
        w_http2_serve_connection(a->conn, a->handler);
        return W_NIL;
    }
#endif

    w_http1_connection_loop(a->conn, a->handler);
    return W_NIL;
}

/* Set up a newly accepted connection fd (non-blocking, TCP tuning) */
static int setup_accepted_fd(int fd) {
    forge_load_options();
    if (w_fd_set_nonblocking(fd) < 0) return -1;
    int one = 1;
    setsockopt(fd, IPPROTO_TCP, TCP_NODELAY, &one, sizeof(one));
#ifdef SO_NOSIGPIPE
    setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, sizeof(one));
#endif

#ifdef TCP_NOOPT
    setsockopt(fd, IPPROTO_TCP, TCP_NOOPT, &one, sizeof(one));
#endif

    /* TCP_NOPUSH/TCP_CORK set-once path removed: without an explicit
     * uncork at batch-flush, kernel holds pipelined responses until a
     * timeout, collapsing throughput to ~8K req/s. The userspace
     * resp_buf in w_http1_connection_loop already coalesces N responses
     * into one write(), so corking is redundant at our batching level.
     * Re-introduce only if paired with cork-before-build / uncork-on-flush. */
    (void)g_forge_nopush;

#ifdef TCP_NOTSENT_LOWAT
    int lowat = 16384;
    setsockopt(fd, IPPROTO_TCP, TCP_NOTSENT_LOWAT, &lowat, sizeof(lowat));
#endif
    return 0;
}

/* Spawn a connection handler goroutine for an accepted fd */
static void spawn_connection_handler(int fd, WClosure *handler_cl) {
    WSocket *conn = calloc(1, sizeof(WSocket));
    conn->type = W_TYPE_SOCKET;
    conn->fd = fd;
    conn->listening = 0;
    conn->closed = 0;
    conn->ssl = NULL;

    HttpConnArg *carg = calloc(1, sizeof(HttpConnArg));
    carg->conn = conn;
    carg->handler = handler_cl;

    WValue cap[1];
    cap[0] = w_box_ptr(carg, W_SUBTAG_GENERIC);
    WValue closure = w_closure_new((void *)http_conn_goroutine_fn, cap, 1);
    w_goroutine_spawn(closure);
}

/* Accept loop goroutine — runs as a goroutine in the cooperative scheduler.
 * Uses io_uring multi-shot accept when available (one SQE services many
 * connections), falls back to readiness-based accept() + epoll. */
static WValue serve_http_accept_goroutine(WValue *captures, WValue arg) {
    (void)arg;
    HttpConnArg *a = (HttpConnArg *)w_as_ptr(captures[0]);
    WSocket *ls = a->conn;
    WClosure *handler_cl = a->handler;

    /* Try multi-shot accept: one SQE generates a CQE per new connection */
    WGoroutine *g = g_current;
    WEventLoop *el = w_rt_get_coop_event_loop();
    struct sockaddr_in client_addr;
    socklen_t addr_len = sizeof(client_addr);

    if (g && el &&
        w_event_submit_accept_multishot(el, ls->fd,
            (struct sockaddr *)&client_addr, &addr_len, g) == 0) {
        while (1) {
            w_socket_park_uring();
            int fd = g->io_result;
            if (fd >= 0) {
                if (setup_accepted_fd(fd) == 0) {
                    spawn_connection_handler(fd, handler_cl);
                } else {
                    close(fd);
                }
                continue;
            }
            /* Negative = -errno. Resubmit multi-shot on transient errors. */
            if (fd == -EMFILE || fd == -ENFILE) {
                w_goroutine_yield();
            }
            /* Multi-shot terminated — resubmit */
            addr_len = sizeof(client_addr);
            if (w_event_submit_accept_multishot(el, ls->fd,
                    (struct sockaddr *)&client_addr, &addr_len, g) != 0) {
                break;  /* Can't resubmit — fall through to readiness */
            }
        }
    }

    /* Fallback: readiness-based accept */
    while (1) {
        struct sockaddr_in client_addr2;
        socklen_t addr_len2 = sizeof(client_addr2);
        int fd = accept(ls->fd, (struct sockaddr *)&client_addr2, &addr_len2);

        if (fd >= 0) {
            if (setup_accepted_fd(fd) == 0) {
                spawn_connection_handler(fd, handler_cl);
            } else {
                close(fd);
            }
            continue;
        }

        if (errno == EINTR) continue;
        if (errno == EAGAIN || errno == EWOULDBLOCK) {
            w_socket_park(ls->fd, W_EVENT_READ);
            continue;
        }
        if (errno == EMFILE || errno == ENFILE) {
            w_goroutine_yield();
            continue;
        }
        break;
    }
    return W_NIL;
}

/* Worker thread entry — each thread runs its own cooperative scheduler
 * with its own event loop. All threads share the listen socket via accept(). */
typedef struct {
    WSocket *listener;
    WClosure *handler;
    int worker_id;
} ServeWorkerArg;

/* Clone a listening socket: new fd, same bound port, fresh accept queue.
 * Each worker calls this so SO_REUSEPORT gives per-thread queues instead of
 * N threads racing on a single shared accept queue. Returns a heap WSocket
 * owned by the caller (leaked intentionally — lives for the server lifetime). */
static WSocket *clone_listener_for_worker(WSocket *origin) {
    struct sockaddr_in addr;
    socklen_t alen = sizeof(addr);
    if (getsockname(origin->fd, (struct sockaddr *)&addr, &alen) < 0) return NULL;

    int fd = socket(AF_INET, SOCK_STREAM, 0);
    if (fd < 0) return NULL;

    int opt = 1;
    setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt));
#ifdef SO_REUSEPORT
    setsockopt(fd, SOL_SOCKET, SO_REUSEPORT, &opt, sizeof(opt));
#endif
#ifdef TCP_FASTOPEN
    int tfo = 5;
    setsockopt(fd, IPPROTO_TCP, TCP_FASTOPEN, &tfo, sizeof(tfo));
#endif

    if (bind(fd, (struct sockaddr *)&addr, sizeof(addr)) < 0) {
        close(fd);
        return NULL;
    }
    if (listen(fd, 1024) < 0) {
        close(fd);
        return NULL;
    }
    if (w_fd_set_nonblocking(fd) < 0) {
        close(fd);
        return NULL;
    }

    WSocket *s = calloc(1, sizeof(WSocket));
    s->type = W_TYPE_SOCKET;
    s->fd = fd;
    s->listening = 1;
    return s;
}

static void *serve_worker_thread(void *arg) {
    ServeWorkerArg *wa = (ServeWorkerArg *)arg;

    /* Pin thread to a CPU core — reduces spinlock contention (5.6% of CPU
     * was _raw_spin_unlock_irqrestore from TCP stack socket locks).
     * Each worker on its own core avoids cross-core cache bouncing. */
#ifdef __linux__
    {
        cpu_set_t cpuset;
        CPU_ZERO(&cpuset);
        CPU_SET(wa->worker_id % sysconf(_SC_NPROCESSORS_ONLN), &cpuset);
        pthread_setaffinity_np(pthread_self(), sizeof(cpu_set_t), &cpuset);
    }
#endif

    /* Create a per-thread event loop */
    WEventLoop *el = w_event_init();
    w_rt_set_coop_event_loop(el);

    /* Optional: per-worker SO_REUSEPORT listener (own accept queue).
     * Worker 0 always keeps the origin listener; other workers clone it. */
    WSocket *worker_listener = wa->listener;
    if (wa->worker_id > 0) {
        const char *rp = getenv("TUNGSTEN_FORGE_REUSEPORT");
        if (rp && rp[0] && rp[0] != '0') {
            WSocket *cloned = clone_listener_for_worker(wa->listener);
            if (cloned) worker_listener = cloned;
        }
    }

    /* Spawn accept loop goroutine for this thread */
    HttpConnArg *a = calloc(1, sizeof(HttpConnArg));
    a->conn = worker_listener;
    a->handler = wa->handler;

    WValue captures[1];
    captures[0] = w_box_ptr(a, W_SUBTAG_GENERIC);
    WValue closure = w_closure_new((void *)serve_http_accept_goroutine, captures, 1);
    w_goroutine_spawn(closure);

    /* Run this thread's cooperative scheduler forever */
    w_rt_set_scheduler_persistent(1);
    w_scheduler_run();

    return NULL;
}

/* HTTP/3 thread wrapper — runs on a dedicated OS thread since QUIC uses
 * a poll()-based UDP event loop incompatible with the goroutine scheduler */
#if defined(TUNGSTEN_HTTP3) && defined(TUNGSTEN_TLS)
typedef struct {
    int port;
    WClosure *handler;
} H3ServeArg;

extern void w_http3_serve(int port, WClosure *handler, const char *cert_path, const char *key_path);

static void *h3_serve_thread_fn(void *arg) {
    H3ServeArg *a = (H3ServeArg *)arg;
    const char *cert = w_tls_get_cert_path();
    const char *key = w_tls_get_key_path();
    w_http3_serve(a->port, a->handler, cert, key);
    return NULL;
}
#endif

WValue w_socket_serve_http(WValue listener, WValue handler, int workers) {
    w_sandbox_gate("serve_http", "");
    WSocket *ls = (WSocket *)w_as_ptr(listener);
    if (!ls || !ls->listening) {
        w_raise(w_string("serve_http: requires a listening socket"));
    }

    signal(SIGPIPE, SIG_IGN);
    forge_load_options();

    /* Print request count on SIGINT for verification */
    signal(SIGINT, forge_print_stats);

    WClosure *handler_cl = (WClosure *)w_as_ptr(handler);
    if (!handler_cl) {
        w_raise(w_string("serve_http: requires a closure"));
    }

    /* Auto-detect worker count: cpucount - 2 (reserve for OS + oha),
     * minimum of min(2, cpucount). workers=0 triggers auto-detect. */
    if (workers <= 0) {
        long ncpu = sysconf(_SC_NPROCESSORS_ONLN);
        if (ncpu <= 0) ncpu = 1;
        workers = (int)(ncpu - 2);
        int min_workers = ncpu < 2 ? (int)ncpu : 2;
        if (workers < min_workers) workers = min_workers;
    }

    /* Determine if HTTP/3 should be started alongside TCP */
    int h3_port = 0;
#if defined(TUNGSTEN_HTTP3) && defined(TUNGSTEN_TLS)
    if (w_tls_server_configured()) {
        struct sockaddr_in sin;
        socklen_t sinlen = sizeof(sin);
        if (getsockname(ls->fd, (struct sockaddr *)&sin, &sinlen) == 0) {
            h3_port = ntohs(sin.sin_port);
        }
    }
#endif

    if (workers > 1) {
        /* Multi-threaded: N independent cooperative schedulers sharing the listen fd.
         * Each thread runs accept() + its own goroutine pool + its own event loop.
         * No cross-thread swapcontext needed (macOS deprecated ucontext). */
        w_scheduler_init();  /* init shared goroutine arena once before spawning */
        pthread_t threads[workers - 1];
        ServeWorkerArg was[workers - 1];

        for (int i = 0; i < workers - 1; i++) {
            was[i].listener = ls;
            was[i].handler = handler_cl;
            was[i].worker_id = i + 1;  /* 0 = main thread */
            pthread_create(&threads[i], NULL, serve_worker_thread, &was[i]);
        }

#if defined(TUNGSTEN_HTTP3) && defined(TUNGSTEN_TLS)
        /* Spawn HTTP/3 UDP listener on a dedicated OS thread */
        if (h3_port > 0) {
            H3ServeArg *h3a = calloc(1, sizeof(H3ServeArg));
            h3a->port = h3_port;
            h3a->handler = handler_cl;
            pthread_t h3_thread;
            pthread_create(&h3_thread, NULL, h3_serve_thread_fn, h3a);
            pthread_detach(h3_thread);
        }
#endif

        /* Main thread also runs as worker 0 */
        ServeWorkerArg wa0 = { .listener = ls, .handler = handler_cl, .worker_id = 0 };
        serve_worker_thread(&wa0);

        /* If we ever return (shouldn't in server mode), join workers */
        for (int i = 0; i < workers - 1; i++) {
            pthread_join(threads[i], NULL);
        }
    } else {
        /* Single-threaded cooperative scheduler (default) */
        /* Lazy-init goroutine arena */
        w_scheduler_init();

        if (!w_rt_get_coop_event_loop()) {
            w_rt_set_coop_event_loop(w_event_init());
        }

        HttpConnArg *arg = calloc(1, sizeof(HttpConnArg));
        arg->conn = ls;
        arg->handler = handler_cl;

        WValue captures[1];
        captures[0] = w_box_ptr(arg, W_SUBTAG_GENERIC);
        WValue closure = w_closure_new((void *)serve_http_accept_goroutine, captures, 1);
        w_goroutine_spawn(closure);

#if defined(TUNGSTEN_HTTP3) && defined(TUNGSTEN_TLS)
        /* Spawn HTTP/3 UDP listener on a dedicated OS thread */
        if (h3_port > 0) {
            H3ServeArg *h3a = calloc(1, sizeof(H3ServeArg));
            h3a->port = h3_port;
            h3a->handler = handler_cl;
            pthread_t h3_thread;
            pthread_create(&h3_thread, NULL, h3_serve_thread_fn, h3a);
            pthread_detach(h3_thread);
        }
#endif

        w_rt_set_scheduler_persistent(1);
        w_scheduler_run();
    }

    return W_NIL;
}


#ifndef W_RUNTIME_UNITY_INCLUDE
#undef die
#undef as_str
#undef w_rope_len
#undef w_rope_write
#undef call_closure_1
#undef w_socket_park_uring
#undef w_fd_set_nonblocking
#endif
