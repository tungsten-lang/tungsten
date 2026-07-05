/*
 * hammer.c — M:N HTTP benchmark engine for Tungsten Hammer
 *
 * Architecture: M OS worker threads × N goroutines per worker.
 * Each goroutine manages one persistent TCP connection, sending requests
 * in a tight loop with keep-alive reuse. Uses the cooperative scheduler
 * with kqueue/epoll/io_uring for non-blocking I/O.
 *
 * Hot path: pre-resolved DNS, pre-built request, stack-local read buffer,
 * thread-local latency arrays (no atomics on fast path), minimal response
 * parsing (status code + Content-Length only).
 */

#define _GNU_SOURCE
#include "runtime.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <errno.h>
#include <fcntl.h>
#include <netdb.h>
#include <sys/socket.h>
#include <netinet/tcp.h>
#include <netinet/in.h>
#include <sys/uio.h>
#include <strings.h>
#include <termios.h>

#ifdef __linux__
#include <sched.h>
#endif

#ifdef __APPLE__
#include <mach/mach_time.h>
#include <mach/thread_policy.h>
#include <mach/mach.h>
#endif

#ifdef TUNGSTEN_TLS
#include <openssl/ssl.h>
#include <openssl/err.h>
#endif

/* ---- Configuration ---- */

#define HAMMER_READ_BUF      65536
#define HAMMER_MAX_LATENCIES  (4 * 1024 * 1024)  /* 4M samples per worker */
#define HAMMER_MAX_PIPELINE   4096 /* max pipeline depth */
#define HAMMER_PROTOCOL_H10  0   /* HTTP/1.0 — close after each response */
#define HAMMER_PROTOCOL_H11  1   /* HTTP/1.1 — keep-alive */
#define HAMMER_PROTOCOL_H2   2   /* HTTP/2   — multiplexed (future) */

/* ---- Shared benchmark state ---- */

typedef struct {
    /* Pre-resolved target */
    struct sockaddr_storage addr;
    socklen_t addr_len;
    char *host;
    int port;

    /* Pre-built request */
    char *request;
    int request_len;
    char *request_batch;
    int request_batch_len;

    /* Options */
    int use_tls;
    int protocol;      /* HAMMER_PROTOCOL_* */
    int num_workers;
    int conns_per_worker;
    volatile int pipeline_depth;    /* requests per writev batch (volatile for forge mode) */
    int forge_mode;                 /* interactive forge mode */
    int max_mode;                   /* max throughput: skip latency/capacity extras */
} HammerConfig;

typedef struct {
    uint64_t total_requests;
    uint64_t total_bytes;
    uint64_t status_2xx;
    uint64_t status_3xx;
    uint64_t status_4xx;
    uint64_t status_5xx;
    uint64_t errors;
    uint64_t connect_errors;
    uint64_t timeouts;

    /* Server capacity (from X-Forge-G / X-Forge-QD headers) */
    int64_t max_server_goroutines;
    int64_t max_server_queue_depth;
    int64_t last_server_goroutines;
    int64_t last_server_queue_depth;

    /* Latency recording (microseconds) */
    uint64_t *latencies;
    uint64_t latency_count;
    uint64_t latency_cap;
} HammerWorkerStats;

typedef struct {
    HammerConfig *config;
    HammerWorkerStats *stats;
    int worker_id;
} HammerWorkerArg;

/* Per-worker shared state for goroutine completion tracking */
typedef struct {
    volatile int remaining;  /* goroutines still running */
} HammerWorkerShared;

/* Per-goroutine argument (heap-allocated, passed via closure capture) */
typedef struct {
    HammerConfig *config;
    HammerWorkerStats *stats;
    HammerWorkerShared *shared;
} HammerGoroutineArg;

/* ---- Thread-local scheduler accessors (defined in runtime.c) ---- */
void w_scheduler_set_event_loop(WEventLoop *el);
void w_scheduler_set_persistent(int val);

/* ---- Helpers ---- */

static inline int64_t timespec_diff_us(struct timespec *a, struct timespec *b) {
    return (int64_t)(a->tv_sec - b->tv_sec) * 1000000 +
           (int64_t)(a->tv_nsec - b->tv_nsec) / 1000;
}

/* Deadline check — uses mach_absolute_time() on macOS for reliability.
 * Both clock_gettime(CLOCK_MONOTONIC) and time(NULL) advance at ~1/7th speed
 * inside goroutine context with -O3 -flto (likely commpage read issue with
 * goroutine stack swaps). mach_absolute_time() is a single MRS instruction
 * reading the ARM64 hardware counter directly. */
#ifdef __APPLE__
static uint64_t g_hammer_deadline_mach;
static double g_mach_to_ns;  /* conversion factor */

static void hammer_init_mach_time(void) {
    mach_timebase_info_data_t info;
    mach_timebase_info(&info);
    g_mach_to_ns = (double)info.numer / (double)info.denom;
}

__attribute__((noinline))
static int past_deadline(void) {
    return mach_absolute_time() >= g_hammer_deadline_mach;
}
#else
static time_t g_hammer_deadline;

__attribute__((noinline))
static int past_deadline(void) {
    struct timespec now;
    clock_gettime(CLOCK_MONOTONIC, &now);
    return now.tv_sec >= g_hammer_deadline;
}

static time_t monotonic_now(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return ts.tv_sec;
}
#endif

/* Non-blocking connect with goroutine parking */
static int hammer_connect(HammerConfig *cfg) {
    int fd = socket(cfg->addr.ss_family, SOCK_STREAM, 0);
    if (fd < 0) return -1;

    fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK);

    /* Enlarge send buffer so kernel absorbs small writes without blocking */
    int sndbuf = 262144;
    setsockopt(fd, SOL_SOCKET, SO_SNDBUF, &sndbuf, sizeof(sndbuf));

    /* TCP_NODELAY: disable Nagle so each request goes out immediately */
    int nodelay = 1;
    setsockopt(fd, IPPROTO_TCP, TCP_NODELAY, &nodelay, sizeof(nodelay));

    int ret = connect(fd, (struct sockaddr *)&cfg->addr, cfg->addr_len);
    if (ret == 0) return fd;

    if (errno == EINPROGRESS) {
        w_socket_park(fd, W_EVENT_WRITE);
        int err = 0;
        socklen_t errlen = sizeof(err);
        getsockopt(fd, SOL_SOCKET, SO_ERROR, &err, &errlen);
        if (err == 0) return fd;
    }

    close(fd);
    return -1;
}

/* Write entire buffer with parking on EAGAIN */
static int hammer_write(int fd, void *ssl, const char *buf, int len) {
    int written = 0;
    while (written < len) {
        ssize_t n;
#ifdef TUNGSTEN_TLS
        if (ssl) {
            n = SSL_write((SSL *)ssl, buf + written, len - written);
            if (n <= 0) {
                int err = SSL_get_error((SSL *)ssl, (int)n);
                if (err == SSL_ERROR_WANT_WRITE) {
                    w_socket_park(fd, W_EVENT_WRITE);
                    continue;
                }
                if (err == SSL_ERROR_WANT_READ) {
                    w_socket_park(fd, W_EVENT_READ);
                    continue;
                }
                return -1;
            }
        } else
#else
        (void)ssl;
#endif
        {
            n = write(fd, buf + written, len - written);
            if (n > 0) { written += (int)n; continue; }
            if (errno == EAGAIN || errno == EWOULDBLOCK) {
                w_socket_park(fd, W_EVENT_WRITE);
                continue;
            }
            return -1;
        }
        written += (int)n;
    }
    return written;
}

/* Batch-write N copies of the same request from a prebuilt contiguous buffer. */
static int hammer_write_pipeline(int fd, void *ssl, HammerConfig *cfg, int count) {
    int total = cfg->request_len * count;
    if (count <= 1) return hammer_write(fd, ssl, cfg->request, cfg->request_len);
    return hammer_write(fd, ssl, cfg->request_batch, total);
}

/* Read with parking on EAGAIN. Returns bytes read, 0 on close, -1 on error. */
static int hammer_read(int fd, void *ssl, char *buf, int max) {
    while (1) {
        ssize_t n;
#ifdef TUNGSTEN_TLS
        if (ssl) {
            n = SSL_read((SSL *)ssl, buf, max);
            if (n > 0) return (int)n;
            int err = SSL_get_error((SSL *)ssl, (int)n);
            if (err == SSL_ERROR_WANT_READ) {
                w_socket_park(fd, W_EVENT_READ);
                continue;
            }
            if (err == SSL_ERROR_WANT_WRITE) {
                w_socket_park(fd, W_EVENT_WRITE);
                continue;
            }
            if (err == SSL_ERROR_ZERO_RETURN) return 0;
            return -1;
        }
#else
        (void)ssl;
#endif
        n = read(fd, buf, max);
        if (n > 0) return (int)n;
        if (n == 0) return 0;
        if (errno == EAGAIN || errno == EWOULDBLOCK) {
            w_socket_park(fd, W_EVENT_READ);
            continue;
        }
        return -1;
    }
}

/* TLS client handshake with goroutine parking */
static void *hammer_tls_wrap(int fd, const char *host) {
#ifdef TUNGSTEN_TLS
    /* Use w_tls_client_wrap which handles non-blocking handshake + parking */
    WSocket *ws = calloc(1, sizeof(WSocket));
    ws->type = W_TYPE_SOCKET;
    ws->fd = fd;
    ws->listening = 0;
    ws->closed = 0;
    ws->ssl = NULL;

    WValue sock = w_box_ptr(ws, W_SUBTAG_GENERIC);
    w_tls_client_wrap(sock, host);

    /* Extract SSL* — the socket now has it attached */
    void *ssl = ws->ssl;
    /* Don't free ws — it's referenced by the WValue (gets cleaned up eventually) */
    return ssl;
#else
    (void)fd; (void)host;
    return NULL;
#endif
}

/* Minimal HTTP response parser. Scans for status code, Content-Length,
 * and Forge capacity headers (X-Forge-G, X-Forge-QD).
 * Returns header length (bytes up to and including \r\n\r\n), or -1 if incomplete. */
static inline int hammer_is_content_length_header(const char *p) {
    return (((unsigned char)p[0] | 0x20) == 'c') &&
           (((unsigned char)p[1] | 0x20) == 'o') &&
           (((unsigned char)p[2] | 0x20) == 'n') &&
           (((unsigned char)p[3] | 0x20) == 't') &&
           (((unsigned char)p[4] | 0x20) == 'e') &&
           (((unsigned char)p[5] | 0x20) == 'n') &&
           (((unsigned char)p[6] | 0x20) == 't') &&
           p[7] == '-' &&
           (((unsigned char)p[8] | 0x20) == 'l') &&
           (((unsigned char)p[9] | 0x20) == 'e') &&
           (((unsigned char)p[10] | 0x20) == 'n') &&
           (((unsigned char)p[11] | 0x20) == 'g') &&
           (((unsigned char)p[12] | 0x20) == 't') &&
           (((unsigned char)p[13] | 0x20) == 'h') &&
           p[14] == ':';
}

static inline int hammer_parse_header_int(const char *p, const char *end) {
    int n = 0;
    while (p < end && *p == ' ') p++;
    while (p < end && *p >= '0' && *p <= '9') {
        n = n * 10 + (*p - '0');
        p++;
    }
    return n;
}

#if defined(__GNUC__) || defined(__clang__)
#define HAMMER_NOINLINE __attribute__((noinline))
#else
#define HAMMER_NOINLINE
#endif

#if defined(__aarch64__)
#include <arm_neon.h>
#elif defined(__SSE2__)
#include <emmintrin.h>
#endif

static HAMMER_NOINLINE const char *hammer_find_header_end(const char *buf, int len) {
    if (len < 4) return NULL;
    const char *end = buf + len - 3;
    const char *p = buf;

#if defined(__aarch64__)
    /* NEON: scan 16 bytes per iteration for '\r' (0x0D). On hit, check
     * the full '\r\n\r\n' pattern at that offset. Typical HTTP response
     * header ends within the first ~100B, so the happy path is one vload
     * + one narrow-shift-to-mask + a few scalar checks. */
    const uint8x16_t cr = vdupq_n_u8('\r');
    while (p + 16 <= end) {
        uint8x16_t v = vld1q_u8((const uint8_t *)p);
        uint8x16_t eq = vceqq_u8(v, cr);
        /* Collapse 16 per-byte bools to a 64-bit mask: 4 bits per byte. */
        uint64_t m = vget_lane_u64(
            vreinterpret_u64_u8(vshrn_n_u16(vreinterpretq_u16_u8(eq), 4)), 0);
        if (m) {
            int off = __builtin_ctzll(m) >> 2;
            while (off < 16) {
                const char *q = p + off;
                if (q + 3 < buf + len &&
                    q[0] == '\r' && q[1] == '\n' && q[2] == '\r' && q[3] == '\n') {
                    return q;
                }
                /* Advance to next '\r' in this 16B chunk. */
                m &= ~((uint64_t)0xF << (off << 2));
                if (!m) break;
                off = __builtin_ctzll(m) >> 2;
            }
        }
        p += 16;
    }
#elif defined(__SSE2__)
    const __m128i cr = _mm_set1_epi8('\r');
    while (p + 16 <= end) {
        __m128i v = _mm_loadu_si128((const __m128i *)p);
        int m = _mm_movemask_epi8(_mm_cmpeq_epi8(v, cr));
        while (m) {
            int off = __builtin_ctz(m);
            const char *q = p + off;
            if (q + 3 < buf + len &&
                q[0] == '\r' && q[1] == '\n' && q[2] == '\r' && q[3] == '\n') {
                return q;
            }
            m &= m - 1;
        }
        p += 16;
    }
#endif

    /* Scalar tail (also the whole body when SIMD disabled). */
    while (p <= end) {
        if (p[0] == '\r' && p[1] == '\n' && p[2] == '\r' && p[3] == '\n') return p;
        p++;
    }
    return NULL;
}

/* 16-byte vectorized scan for '\n'. Returns first match in [p, end), or end.
 * Same narrow-shift mask trick as hammer_find_header_end. */
static inline const char *hammer_scan_to_lf(const char *p, const char *end) {
#if defined(__aarch64__)
    const uint8x16_t lf = vdupq_n_u8('\n');
    while (p + 16 <= end) {
        uint8x16_t v = vld1q_u8((const uint8_t *)p);
        uint8x16_t eq = vceqq_u8(v, lf);
        uint64_t m = vget_lane_u64(
            vreinterpret_u64_u8(vshrn_n_u16(vreinterpretq_u16_u8(eq), 4)), 0);
        if (m) return p + (__builtin_ctzll(m) >> 2);
        p += 16;
    }
#elif defined(__SSE2__)
    const __m128i lf = _mm_set1_epi8('\n');
    while (p + 16 <= end) {
        __m128i v = _mm_loadu_si128((const __m128i *)p);
        int m = _mm_movemask_epi8(_mm_cmpeq_epi8(v, lf));
        if (m) return p + __builtin_ctz(m);
        p += 16;
    }
#endif
    while (p < end && *p != '\n') p++;
    return p;
}

static HAMMER_NOINLINE void hammer_scan_response_headers(const char *buf, const char *end,
                                                         int *content_length,
                                                         int *server_goroutines,
                                                         int *server_queue_depth,
                                                         int parse_capacity) {
    const char *p = buf;
    while (p < end) {
        if ((*p == 'C' || *p == 'c') && end - p > 16) {
            if (hammer_is_content_length_header(p)) {
                const char *v = p + 15;
                *content_length = hammer_parse_header_int(v, end);
            }
        } else if (parse_capacity && *p == 'X' && end - p > 12) {
            if (strncmp(p, "X-Forge-G: ", 11) == 0) {
                *server_goroutines = hammer_parse_header_int(p + 11, end);
            } else if (strncmp(p, "X-Forge-QD: ", 12) == 0) {
                *server_queue_depth = hammer_parse_header_int(p + 12, end);
            }
        }
        p = hammer_scan_to_lf(p, end);
        if (p >= end) break;
        p++;
    }
}

static int parse_response_headers(const char *buf, int len, int *status,
                                  int *content_length, int *server_goroutines,
                                  int *server_queue_depth, int parse_capacity) {
    if (len < 15) return -1;

    const char *end = hammer_find_header_end(buf, len);
    if (!end) return -1;

    int header_len = (int)(end - buf) + 4;
    *status = (buf[9] - '0') * 100 + (buf[10] - '0') * 10 + (buf[11] - '0');

    *content_length = -1;
    *server_goroutines = -1;
    *server_queue_depth = -1;

    hammer_scan_response_headers(buf, end, content_length, server_goroutines,
                                 server_queue_depth, parse_capacity);

    return header_len;
}

/* ---- Goroutine function: one persistent connection, request loop ---- */

#if defined(TUNGSTEN_HTTP2) && defined(TUNGSTEN_TLS)
#include <nghttp2/nghttp2.h>

/* ---- HTTP/2 client: real nghttp2 framing over TLS+ALPN ---- */

typedef struct HammerH2Session {
    nghttp2_session *session;
    int fd;
    SSL *ssl;
    HammerConfig *cfg;
    HammerWorkerStats *stats;
    int outstanding;   /* active streams */
    int max_concurrent;
    int terminated;    /* peer closed or fatal error */
    const char *authority;
    size_t authority_len;
    const char *path;
    size_t path_len;
} HammerH2Session;

static ssize_t hammer_h2_send_cb(nghttp2_session *session, const uint8_t *data,
                                  size_t length, int flags, void *user_data) {
    (void)session; (void)flags;
    HammerH2Session *s = (HammerH2Session *)user_data;
    while (1) {
        int n = SSL_write(s->ssl, data, (int)length);
        if (n > 0) return n;
        int err = SSL_get_error(s->ssl, n);
        if (err == SSL_ERROR_WANT_WRITE) { w_socket_park(s->fd, W_EVENT_WRITE); continue; }
        if (err == SSL_ERROR_WANT_READ)  { w_socket_park(s->fd, W_EVENT_READ);  continue; }
        return NGHTTP2_ERR_CALLBACK_FAILURE;
    }
}

static ssize_t hammer_h2_recv_cb(nghttp2_session *session, uint8_t *buf,
                                  size_t length, int flags, void *user_data) {
    (void)session; (void)flags;
    HammerH2Session *s = (HammerH2Session *)user_data;
    int n = SSL_read(s->ssl, buf, (int)length);
    if (n > 0) return n;
    int err = SSL_get_error(s->ssl, n);
    if (err == SSL_ERROR_ZERO_RETURN) return NGHTTP2_ERR_EOF;
    if (err == SSL_ERROR_WANT_READ || err == SSL_ERROR_WANT_WRITE)
        return NGHTTP2_ERR_WOULDBLOCK;
    return NGHTTP2_ERR_CALLBACK_FAILURE;
}

static int hammer_h2_on_header_cb(nghttp2_session *session,
                                   const nghttp2_frame *frame,
                                   const uint8_t *name, size_t namelen,
                                   const uint8_t *value, size_t valuelen,
                                   uint8_t flags, void *user_data) {
    (void)session; (void)flags;
    HammerH2Session *s = (HammerH2Session *)user_data;
    if (frame->hd.type != NGHTTP2_HEADERS) return 0;
    if (namelen == 7 && memcmp(name, ":status", 7) == 0) {
        int status = 0;
        for (size_t i = 0; i < valuelen; i++) status = status * 10 + (value[i] - '0');
        if (status >= 200 && status < 300) s->stats->status_2xx++;
        else if (status < 400) s->stats->status_3xx++;
        else if (status < 500) s->stats->status_4xx++;
        else s->stats->status_5xx++;
    }
    return 0;
}

static int hammer_h2_submit(HammerH2Session *s);

static int hammer_h2_on_stream_close_cb(nghttp2_session *session, int32_t stream_id,
                                         uint32_t error_code, void *user_data) {
    (void)session; (void)stream_id;
    HammerH2Session *s = (HammerH2Session *)user_data;
    s->stats->total_requests++;
    if (error_code != NGHTTP2_NO_ERROR) s->stats->errors++;
    s->outstanding--;
    /* Refill if deadline not reached */
    if (!past_deadline() && s->outstanding < s->max_concurrent) {
        hammer_h2_submit(s);
    }
    return 0;
}

static int hammer_h2_submit(HammerH2Session *s) {
    nghttp2_nv hdrs[4];
    hdrs[0] = (nghttp2_nv){ (uint8_t *)":method", (uint8_t *)"GET",   7, 3, NGHTTP2_NV_FLAG_NONE };
    hdrs[1] = (nghttp2_nv){ (uint8_t *)":scheme", (uint8_t *)"https", 7, 5, NGHTTP2_NV_FLAG_NONE };
    hdrs[2] = (nghttp2_nv){ (uint8_t *)":path",   (uint8_t *)s->path, 5, s->path_len, NGHTTP2_NV_FLAG_NONE };
    hdrs[3] = (nghttp2_nv){ (uint8_t *)":authority", (uint8_t *)s->authority, 10, s->authority_len, NGHTTP2_NV_FLAG_NONE };
    int32_t sid = nghttp2_submit_request(s->session, NULL, hdrs, 4, NULL, NULL);
    if (sid < 0) return -1;
    s->outstanding++;
    return 0;
}

/* Own SSL_CTX for hammer h2 client: ALPN=h2, no verification (benchmark tool). */
static SSL_CTX *hammer_h2_ctx(void) {
    static SSL_CTX *ctx = NULL;
    if (ctx) return ctx;
    SSL_library_init();
    SSL_load_error_strings();
    ctx = SSL_CTX_new(TLS_client_method());
    SSL_CTX_set_min_proto_version(ctx, TLS1_2_VERSION);
    SSL_CTX_set_verify(ctx, SSL_VERIFY_NONE, NULL);
    static const unsigned char alpn[] = "\x02h2";
    SSL_CTX_set_alpn_protos(ctx, alpn, sizeof(alpn) - 1);
    return ctx;
}

static SSL *hammer_h2_tls_handshake(int fd, const char *host) {
    SSL *ssl = SSL_new(hammer_h2_ctx());
    if (!ssl) return NULL;
    SSL_set_fd(ssl, fd);
    SSL_set_tlsext_host_name(ssl, host);
    while (1) {
        int ret = SSL_connect(ssl);
        if (ret == 1) break;
        int err = SSL_get_error(ssl, ret);
        if (err == SSL_ERROR_WANT_READ)  { w_socket_park(fd, W_EVENT_READ);  continue; }
        if (err == SSL_ERROR_WANT_WRITE) { w_socket_park(fd, W_EVENT_WRITE); continue; }
        SSL_free(ssl);
        return NULL;
    }
    /* Verify ALPN negotiated h2 */
    const unsigned char *proto = NULL;
    unsigned int proto_len = 0;
    SSL_get0_alpn_selected(ssl, &proto, &proto_len);
    if (proto_len != 2 || memcmp(proto, "h2", 2) != 0) {
        SSL_shutdown(ssl);
        SSL_free(ssl);
        return NULL;
    }
    return ssl;
}

static WValue hammer_h2_goroutine_fn(WValue *captures) {
    HammerGoroutineArg *arg = (HammerGoroutineArg *)w_as_ptr(captures[0]);
    HammerConfig *cfg = arg->config;
    HammerWorkerStats *stats = arg->stats;

    char authority_buf[256];
    int al = snprintf(authority_buf, sizeof(authority_buf), "%s:%d", cfg->host, cfg->port);
    if (al < 0 || al >= (int)sizeof(authority_buf)) al = strlen(cfg->host);
    HammerH2Session s = {0};
    s.cfg = cfg;
    s.stats = stats;
    s.max_concurrent = cfg->pipeline_depth > 0 ? cfg->pipeline_depth : 100;
    s.authority = authority_buf;
    s.authority_len = (size_t)al;
    s.path = "/";
    s.path_len = 1;

    while (!past_deadline()) {
        s.fd = hammer_connect(cfg);
        if (s.fd < 0) { stats->connect_errors++; w_goroutine_yield(); continue; }
        s.ssl = hammer_h2_tls_handshake(s.fd, cfg->host);
        if (!s.ssl) { close(s.fd); stats->errors++; continue; }

        nghttp2_session_callbacks *cbs;
        nghttp2_session_callbacks_new(&cbs);
        nghttp2_session_callbacks_set_send_callback(cbs, hammer_h2_send_cb);
        nghttp2_session_callbacks_set_recv_callback(cbs, hammer_h2_recv_cb);
        nghttp2_session_callbacks_set_on_header_callback(cbs, hammer_h2_on_header_cb);
        nghttp2_session_callbacks_set_on_stream_close_callback(cbs, hammer_h2_on_stream_close_cb);
        nghttp2_session_client_new(&s.session, cbs, &s);
        nghttp2_session_callbacks_del(cbs);

        nghttp2_settings_entry iv[1] = {
            { NGHTTP2_SETTINGS_MAX_CONCURRENT_STREAMS, (uint32_t)s.max_concurrent },
        };
        nghttp2_submit_settings(s.session, NGHTTP2_FLAG_NONE, iv, 1);

        /* Prime with max_concurrent streams */
        s.outstanding = 0;
        for (int i = 0; i < s.max_concurrent && !past_deadline(); i++) {
            if (hammer_h2_submit(&s) < 0) break;
        }

        /* Drive session */
        while (!past_deadline()) {
            int rv = nghttp2_session_send(s.session);
            if (rv != 0) break;
            rv = nghttp2_session_recv(s.session);
            if (rv == NGHTTP2_ERR_EOF) break;
            if (rv != 0 && rv != NGHTTP2_ERR_WOULDBLOCK) break;
            if (!nghttp2_session_want_read(s.session) &&
                !nghttp2_session_want_write(s.session)) break;
        }

        nghttp2_session_del(s.session);
        s.session = NULL;
        SSL_shutdown(s.ssl);
        SSL_free(s.ssl);
        s.ssl = NULL;
        close(s.fd);
        s.fd = -1;
    }

    HammerWorkerShared *shared = arg->shared;
    int rem = __sync_sub_and_fetch(&shared->remaining, 1);
    if (rem <= 0) w_scheduler_set_persistent(0);
    free(arg);
    return W_NIL;
}
#endif /* TUNGSTEN_HTTP2 && TUNGSTEN_TLS */

static WValue hammer_goroutine_fn(WValue *captures) {
    HammerGoroutineArg *arg = (HammerGoroutineArg *)w_as_ptr(captures[0]);
    HammerConfig *cfg = arg->config;
#if defined(TUNGSTEN_HTTP2) && defined(TUNGSTEN_TLS)
    if (cfg->protocol == HAMMER_PROTOCOL_H2 && cfg->use_tls) {
        return hammer_h2_goroutine_fn(captures);
    }
#endif
    HammerWorkerStats *stats = arg->stats;
    /* Heap-allocate read buffer — goroutine stacks are only 64KB */
    char *buf = malloc(HAMMER_READ_BUF);
    if (!buf) return W_NIL;

    int fd = -1;
    void *ssl = NULL;

    /* Outer loop: connect → request loop → reconnect on error */
    while (!past_deadline()) {
        /* Connect */
        fd = hammer_connect(cfg);
        if (fd < 0) {
            stats->connect_errors++;
            if (past_deadline()) break;
            /* Brief yield before retry */
            w_goroutine_yield();
            continue;
        }

        /* TLS handshake */
        if (cfg->use_tls) {
            ssl = hammer_tls_wrap(fd, cfg->host);
            if (!ssl) {
                stats->connect_errors++;
                close(fd);
                fd = -1;
                continue;
            }
        }

        /* Persistent read buffer state — carries leftover bytes across pipeline batches.
         * A single read() from the kernel may return data spanning multiple responses. */
        int buf_pos = 0;   /* start of unconsumed data */
        int buf_end = 0;   /* end of valid data */

        /* Request loop: write N requests (one writev), read N responses */
        while (!past_deadline()) {
            /* Read pipeline depth each iteration (volatile — forge mode updates it) */
            int pipeline = (cfg->protocol == HAMMER_PROTOCOL_H11) ? cfg->pipeline_depth : 1;
#ifdef __APPLE__
            uint64_t req_start = 0;
            if (!cfg->max_mode) req_start = mach_absolute_time();
#else
            struct timespec req_start;
            if (!cfg->max_mode) clock_gettime(CLOCK_MONOTONIC, &req_start);
#endif

            /* Send batch of requests */
            if (pipeline > 1) {
                if (hammer_write_pipeline(fd, ssl, cfg, pipeline) < 0) {
                    stats->errors++;
                    break;
                }
            } else {
                if (hammer_write(fd, ssl, cfg->request, cfg->request_len) < 0) {
                    stats->errors++;
                    break;
                }
            }

            /* Read all pipelined responses */
            int resp_ok = 1;
            for (int p = 0; p < pipeline && resp_ok; p++) {
                int header_len = -1;
                int status = 0;
                int content_length = -1;
                int server_goroutines = -1;
                int server_queue_depth = -1;
                int response_len = 0;

                while (1) {
                    /* Try parsing what we already have in the buffer */
                    int avail = buf_end - buf_pos;
                    if (avail > 0 && header_len < 0) {
                        if (cfg->max_mode) {
                            header_len = parse_response_headers(buf + buf_pos, avail, &status, &content_length,
                                                                &server_goroutines, &server_queue_depth, 0);
                        } else {
                            header_len = parse_response_headers(buf + buf_pos, avail, &status, &content_length,
                                                                &server_goroutines, &server_queue_depth, 1);
                        }
                    }
                    if (header_len >= 0) {
                        if (content_length >= 0) {
                            response_len = header_len + content_length;
                        } else {
                            /* No Content-Length and not HTTP/1.0: assume body ends at available data past headers */
                            response_len = avail > header_len ? avail : header_len;
                        }
                        if (avail >= response_len) {
                            /* Complete response */
                            break;
                        }
                    }

                    /* Need more data — compact buffer if needed */
                    if (buf_pos > 0) {
                        int remaining = buf_end - buf_pos;
                        memmove(buf, buf + buf_pos, remaining);
                        buf_end = remaining;
                        buf_pos = 0;
                    }

                    int space = HAMMER_READ_BUF - buf_end;
                    if (space <= 0) { resp_ok = 0; break; }

                    int n = hammer_read(fd, ssl, buf + buf_end, space);
                    if (n <= 0) {
                        if (n == 0 && header_len >= 0) break;
                        stats->errors++;
                        resp_ok = 0;
                        goto reconnect;
                    }
                    buf_end += n;
                }

                /* Account for this response */
                stats->total_requests++;
                stats->total_bytes += (uint64_t)response_len;

                if (server_goroutines >= 0) {
                    stats->last_server_goroutines = server_goroutines;
                    if (server_goroutines > stats->max_server_goroutines)
                        stats->max_server_goroutines = server_goroutines;
                }
                if (server_queue_depth >= 0) {
                    stats->last_server_queue_depth = server_queue_depth;
                    if (server_queue_depth > stats->max_server_queue_depth)
                        stats->max_server_queue_depth = server_queue_depth;
                }

                if (status >= 200 && status < 300) stats->status_2xx++;
                else if (status >= 300 && status < 400) stats->status_3xx++;
                else if (status >= 400 && status < 500) stats->status_4xx++;
                else if (status >= 500) stats->status_5xx++;
                buf_pos += response_len;
            }

            if (!resp_ok) break;

            /* Record latency (amortized across pipeline batch) */
            if (!cfg->max_mode) {
#ifdef __APPLE__
                uint64_t req_end = mach_absolute_time();
                uint64_t latency_us = (uint64_t)((double)(req_end - req_start) * g_mach_to_ns / 1000.0) / pipeline;
#else
                struct timespec req_end;
                clock_gettime(CLOCK_MONOTONIC, &req_end);
                uint64_t latency_us = (uint64_t)timespec_diff_us(&req_end, &req_start) / pipeline;
#endif

                if (stats->latency_count < stats->latency_cap) {
                    stats->latencies[stats->latency_count++] = latency_us;
                }
            }

            /* HTTP/1.0: must reconnect */
            if (cfg->protocol == HAMMER_PROTOCOL_H10) break;
        }

    reconnect:
#ifdef TUNGSTEN_TLS
        if (ssl) { SSL_shutdown((SSL *)ssl); SSL_free((SSL *)ssl); ssl = NULL; }
#endif
        if (fd >= 0) { close(fd); fd = -1; }
    }

    /* Cleanup */
#ifdef TUNGSTEN_TLS
    if (ssl) { SSL_shutdown((SSL *)ssl); SSL_free((SSL *)ssl); }
#endif
    if (fd >= 0) close(fd);
    free(buf);

    /* Signal completion: decrement remaining, flip scheduler when all done */
    HammerWorkerShared *shared = arg->shared;
    int rem = __sync_sub_and_fetch(&shared->remaining, 1);
    if (rem <= 0) {
        /* All goroutines done — switch scheduler to non-persistent so it exits */
        w_scheduler_set_persistent(0);
    }

    free(arg);
    return W_NIL;
}

/* ---- Worker thread: event loop + goroutine pool ---- */

static void *hammer_worker_thread(void *raw_arg) {
    HammerWorkerArg *wa = (HammerWorkerArg *)raw_arg;

#ifdef __linux__
    /* Pin to CPU core for cache locality */
    cpu_set_t cpuset;
    CPU_ZERO(&cpuset);
    CPU_SET(wa->worker_id % sysconf(_SC_NPROCESSORS_ONLN), &cpuset);
    pthread_setaffinity_np(pthread_self(), sizeof(cpu_set_t), &cpuset);
#elif defined(__APPLE__)
    /* Thread affinity hint — tells macOS to keep workers on separate L2 clusters */
    thread_affinity_policy_data_t policy = { .affinity_tag = wa->worker_id + 1 };
    thread_policy_set(mach_thread_self(), THREAD_AFFINITY_POLICY,
                      (thread_policy_t)&policy, 1);
#endif

    /* Per-thread event loop */
    WEventLoop *el = w_event_init();
    w_scheduler_set_event_loop(el);

    /* Shared completion tracker */
    HammerWorkerShared shared = { .remaining = wa->config->conns_per_worker };

    /* Spawn benchmark goroutines */
    for (int i = 0; i < wa->config->conns_per_worker; i++) {
        HammerGoroutineArg *ga = calloc(1, sizeof(HammerGoroutineArg));
        ga->config = wa->config;
        ga->stats = wa->stats;
        ga->shared = &shared;

        WValue captures[1];
        captures[0] = w_box_ptr(ga, W_SUBTAG_GENERIC);
        WValue closure = w_closure_new((void *)hammer_goroutine_fn, captures, 1);
        w_goroutine_spawn(closure);
    }

    /* Persistent scheduler — last goroutine flips to non-persistent when done */
    w_scheduler_set_persistent(1);
    w_scheduler_run();

    w_event_destroy(el);
    w_scheduler_set_event_loop(NULL);
    return NULL;
}

/* ---- URL parsing ---- */

typedef struct {
    char *host;
    int port;
    char *path;
    int use_tls;
} ParsedURL;

static int parse_url(const char *url, ParsedURL *out) {
    memset(out, 0, sizeof(*out));
    out->path = "/";

    const char *p = url;
    if (strncmp(p, "https://", 8) == 0) {
        out->use_tls = 1;
        out->port = 443;
        p += 8;
    } else if (strncmp(p, "http://", 7) == 0) {
        out->use_tls = 0;
        out->port = 80;
        p += 7;
    } else {
        out->use_tls = 0;
        out->port = 80;
    }

    /* host[:port][/path] */
    const char *colon = NULL;
    const char *slash = NULL;
    const char *scan = p;
    while (*scan && *scan != '/' && *scan != ':') scan++;
    if (*scan == ':') colon = scan;
    else if (*scan == '/') slash = scan;

    int host_len;
    if (colon) {
        host_len = (int)(colon - p);
        out->port = atoi(colon + 1);
        const char *s = colon + 1;
        while (*s >= '0' && *s <= '9') s++;
        if (*s == '/') slash = s;
    } else if (slash) {
        host_len = (int)(slash - p);
    } else {
        host_len = (int)strlen(p);
    }

    out->host = malloc(host_len + 1);
    memcpy(out->host, p, host_len);
    out->host[host_len] = '\0';

    if (slash && *slash) {
        out->path = strdup(slash);
    } else {
        out->path = strdup("/");
    }

    return 0;
}

/* ---- Stats printing ---- */

static int cmp_u64(const void *a, const void *b) {
    uint64_t va = *(const uint64_t *)a;
    uint64_t vb = *(const uint64_t *)b;
    return (va > vb) - (va < vb);
}

static void format_latency(char *buf, size_t bufsz, uint64_t us) {
    if (us < 1000) {
        snprintf(buf, bufsz, "%lluμs", (unsigned long long)us);
    } else if (us < 1000000) {
        snprintf(buf, bufsz, "%.2fms", us / 1000.0);
    } else {
        snprintf(buf, bufsz, "%.2fs", us / 1000000.0);
    }
}

static void format_count(char *buf, size_t bufsz, uint64_t n) {
    if (n >= 1000000) {
        snprintf(buf, bufsz, "%.2fM", n / 1000000.0);
    } else if (n >= 1000) {
        snprintf(buf, bufsz, "%.2fK", n / 1000.0);
    } else {
        snprintf(buf, bufsz, "%llu", (unsigned long long)n);
    }
}

static void format_bytes(char *buf, size_t bufsz, uint64_t bytes) {
    if (bytes >= 1073741824ULL) {
        snprintf(buf, bufsz, "%.2f GiB", bytes / 1073741824.0);
    } else if (bytes >= 1048576ULL) {
        snprintf(buf, bufsz, "%.2f MiB", bytes / 1048576.0);
    } else if (bytes >= 1024ULL) {
        snprintf(buf, bufsz, "%.2f KiB", bytes / 1024.0);
    } else {
        snprintf(buf, bufsz, "%llu B", (unsigned long long)bytes);
    }
}

static void print_histogram(uint64_t *sorted, uint64_t count) {
    if (count == 0) return;

    /* Logarithmic histogram with 20 buckets */
    uint64_t min_val = sorted[0];
    uint64_t max_val = sorted[count - 1];
    if (min_val == max_val) {
        char lat[32];
        format_latency(lat, sizeof(lat), min_val);
        printf("  %s |%.*s| %llu\n", lat, 40, "████████████████████████████████████████",
               (unsigned long long)count);
        return;
    }

    #define HIST_BUCKETS 15
    uint64_t buckets[HIST_BUCKETS] = {0};
    uint64_t bucket_max[HIST_BUCKETS];
    uint64_t bucket_min[HIST_BUCKETS];

    /* Linear buckets from min to max */
    uint64_t range = max_val - min_val;
    for (uint64_t i = 0; i < count; i++) {
        int b = (int)((sorted[i] - min_val) * (HIST_BUCKETS - 1) / range);
        if (b >= HIST_BUCKETS) b = HIST_BUCKETS - 1;
        buckets[b]++;
        if (buckets[b] == 1 || sorted[i] < bucket_min[b]) bucket_min[b] = sorted[i];
        if (buckets[b] == 1 || sorted[i] > bucket_max[b]) bucket_max[b] = sorted[i];
    }

    uint64_t max_bucket = 0;
    for (int i = 0; i < HIST_BUCKETS; i++) {
        if (buckets[i] > max_bucket) max_bucket = buckets[i];
    }

    for (int i = 0; i < HIST_BUCKETS; i++) {
        if (buckets[i] == 0) continue;
        char lat[32];
        format_latency(lat, sizeof(lat), bucket_min[i]);
        int bar_width = max_bucket > 0 ? (int)(buckets[i] * 30 / max_bucket) : 0;
        if (bar_width == 0 && buckets[i] > 0) bar_width = 1;
        printf("  %10s |", lat);
        for (int j = 0; j < bar_width; j++) printf("█");
        char cnt[32];
        format_count(cnt, sizeof(cnt), buckets[i]);
        printf(" %s\n", cnt);
    }
    #undef HIST_BUCKETS
}

/* ---- Forge interactive mode ---- */

static struct termios g_orig_termios;
static int g_terminal_restored = 0;

static void hammer_restore_terminal(void) {
    if (!g_terminal_restored) {
        g_terminal_restored = 1;
        tcsetattr(STDIN_FILENO, TCSAFLUSH, &g_orig_termios);
        printf("\033[?25h");  /* show cursor */
        fflush(stdout);
    }
}

static void hammer_raw_mode(void) {
    tcgetattr(STDIN_FILENO, &g_orig_termios);
    g_terminal_restored = 0;
    atexit(hammer_restore_terminal);
    struct termios raw = g_orig_termios;
    raw.c_lflag &= ~(ICANON | ECHO);
    raw.c_cc[VMIN] = 0;
    raw.c_cc[VTIME] = 0;
    tcsetattr(STDIN_FILENO, TCSAFLUSH, &raw);
    printf("\033[?25l");  /* hide cursor */
}

static int hammer_poll_key(void) {
    char c;
    if (read(STDIN_FILENO, &c, 1) == 1) return (unsigned char)c;
    return -1;
}

/* Animation state */
enum {
    FORGE_ANIM_IDLE = 0,
    FORGE_ANIM_WINDUP,
    FORGE_ANIM_SWING,
    FORGE_ANIM_IMPACT,
    FORGE_ANIM_SPARKS,
    FORGE_ANIM_SETTLE,
    FORGE_ANIM_FRAMES
};

/* Spark positions for impact/sparks frames — randomized each strike */
static void hammer_draw_frame(int frame, int pipeline_depth) {
    /* Each frame is 6 lines. We use ANSI colors for visual pop.
     * Yellow=\033[33m  Red=\033[31m  Cyan=\033[36m  Bold=\033[1m  Dim=\033[2m  Reset=\033[0m */

    switch (frame) {
    case FORGE_ANIM_IDLE:
        printf("                                            \n");
        printf("                                            \n");
        printf("       \033[1mo\033[0m  \033[2m,─\033[33;1m⚒\033[0m                            \n");
        printf("      \033[1m/|\033[0m\033[2m\\/\033[0m                                \n");
        printf("      \033[1m/ \\\033[0m                                 \n");
        printf("            \033[36m┌───┐\033[0m                        \n");
        printf("       \033[2m═════╧───╧═════\033[0m   \033[2mpipeline: %d\033[0m    \n", pipeline_depth);
        break;
    case FORGE_ANIM_WINDUP:
        printf("                                            \n");
        printf("                \033[33;1m⚒\033[0m                       \n");
        printf("       \033[1mo\033[0m  \033[2m_/\033[0m                              \n");
        printf("      \033[1m/|\033[0m\033[2m/\033[0m                                \n");
        printf("      \033[1m/ \\\033[0m                                 \n");
        printf("            \033[36m┌───┐\033[0m                        \n");
        printf("       \033[2m═════╧───╧═════\033[0m   \033[2mpipeline: %d\033[0m    \n", pipeline_depth);
        break;
    case FORGE_ANIM_SWING:
        printf("                                            \n");
        printf("                                            \n");
        printf("       \033[1mo\033[0m                                    \n");
        printf("      \033[1m/|\\\033[0m \033[33;1m⚒\033[0m                              \n");
        printf("      \033[1m/ \\\033[0m                                 \n");
        printf("            \033[36m┌───┐\033[0m                        \n");
        printf("       \033[2m═════╧───╧═════\033[0m   \033[2mpipeline: %d\033[0m    \n", pipeline_depth);
        break;
    case FORGE_ANIM_IMPACT:
        printf("                                            \n");
        printf("                  \033[33m✦\033[0m \033[31m·\033[0m  \033[33m*\033[0m                 \n");
        printf("       \033[1mo\033[0m       \033[31m·\033[0m \033[33m✦\033[0m  \033[31m*\033[0m                  \n");
        printf("      \033[1m/|\\\033[0m   \033[33m*\033[0m \033[31m·\033[0m  \033[33m✦\033[0m                   \n");
        printf("      \033[1m/ \\\033[0m \033[33;1m⚒\033[0m\033[33m✦\033[0m  \033[31m·\033[0m \033[33m*\033[0m                   \n");
        printf("           \033[33m✦\033[0m\033[36m┌───┐\033[0m\033[33m✦\033[0m                   \n");
        printf("       \033[2m═════╧───╧═════\033[0m   \033[1mpipeline: %d\033[0m    \n", pipeline_depth);
        break;
    case FORGE_ANIM_SPARKS:
        printf("                                            \n");
        printf("               \033[31m·\033[0m    \033[33m*\033[0m \033[31m·\033[0m                \n");
        printf("       \033[1mo\033[0m        \033[33m✦\033[0m  \033[31m·\033[0m                    \n");
        printf("      \033[1m/|\\\033[0m    \033[31m·\033[0m  \033[33m*\033[0m                     \n");
        printf("      \033[1m/ \\\033[0m \033[33;1m⚒\033[0m  \033[31m·\033[0m                       \n");
        printf("            \033[36m┌───┐\033[0m  \033[31m·\033[0m                   \n");
        printf("       \033[2m═════╧───╧═════\033[0m   \033[1mpipeline: %d\033[0m    \n", pipeline_depth);
        break;
    case FORGE_ANIM_SETTLE:
        printf("                                            \n");
        printf("                       \033[2m·\033[0m                  \n");
        printf("       \033[1mo\033[0m                                    \n");
        printf("      \033[1m/|\\\033[0m                                 \n");
        printf("      \033[1m/ \\\033[0m \033[33;1m⚒\033[0m                              \n");
        printf("            \033[36m┌───┐\033[0m                        \n");
        printf("       \033[2m═════╧───╧═════\033[0m   \033[1mpipeline: %d\033[0m    \n", pipeline_depth);
        break;
    }
}

static void hammer_draw_stats(HammerWorkerStats *all_stats, int num_workers,
                               double elapsed, int pipeline_depth,
                               int show_capacity_msg) {
    /* Aggregate from all workers */
    uint64_t total_reqs = 0;
    for (int i = 0; i < num_workers; i++) {
        total_reqs += all_stats[i].total_requests;
    }

    double rps = elapsed > 0.1 ? total_reqs / elapsed : 0;

    /* Sample recent latencies for live percentiles */
    uint64_t sample_buf[20000];
    uint64_t sample_count = 0;
    for (int i = 0; i < num_workers && sample_count < 20000; i++) {
        uint64_t wc = all_stats[i].latency_count;
        if (wc == 0) continue;
        uint64_t start = wc > 2000 ? wc - 2000 : 0;
        for (uint64_t j = start; j < wc && sample_count < 20000; j++) {
            sample_buf[sample_count++] = all_stats[i].latencies[j];
        }
    }

    char p50[32] = "—", p95[32] = "—", p99[32] = "—";
    char min_lat[32] = "—", max_lat[32] = "—";

    if (sample_count > 1) {
        qsort(sample_buf, sample_count, sizeof(uint64_t), cmp_u64);
        format_latency(p50, sizeof(p50), sample_buf[(uint64_t)(sample_count * 0.50)]);
        format_latency(p95, sizeof(p95), sample_buf[(uint64_t)(sample_count * 0.95)]);
        uint64_t p99_idx = (uint64_t)(sample_count * 0.99);
        if (p99_idx >= sample_count) p99_idx = sample_count - 1;
        format_latency(p99, sizeof(p99), sample_buf[p99_idx]);
        format_latency(min_lat, sizeof(min_lat), sample_buf[0]);
        format_latency(max_lat, sizeof(max_lat), sample_buf[sample_count - 1]);
    }

    char rps_str[32], total_str[32];
    format_count(rps_str, sizeof(rps_str), (uint64_t)rps);
    format_count(total_str, sizeof(total_str), total_reqs);

    printf("\n");
    printf("  \033[1mRequests\033[0m  %-12s  \033[2m%.1fs elapsed\033[0m         \n", total_str, elapsed);
    printf("  \033[1mReq/s\033[0m     \033[36m%-12s\033[0m                        \n", rps_str);
    printf("  \033[1mLatency\033[0m   p50 %-8s  p95 %-8s  p99 %-8s\n", p50, p95, p99);
    printf("            min %-8s  max %-8s              \n", min_lat, max_lat);
    printf("\n");

    if (show_capacity_msg && pipeline_depth < HAMMER_MAX_PIPELINE) {
        printf("  \033[31;1mTHE FORGE IS CALLING FOR MORE\033[0m               \n");
        printf("  \033[2m(press space)\033[0m                                \n");
    } else if (pipeline_depth >= HAMMER_MAX_PIPELINE) {
        printf("  \033[33;1m⚒ MAXIMUM POWER ⚒\033[0m                         \n");
        printf("                                                \n");
    } else {
        printf("                                                \n");
        printf("                                                \n");
    }
}

static void hammer_forge_loop(HammerConfig *cfg, HammerWorkerStats *all_stats,
                               int num_workers, int duration_secs) {
    hammer_raw_mode();

    /* Animation state */
    int anim_frame = FORGE_ANIM_IDLE;
    int anim_ticks = 0;      /* ticks remaining in current animation frame */
    int strike_pending = 0;  /* strike animation queued */

    /* Stats tracking — only update every 1 second */
    double last_stats_time = -1.0;
    int stats_dirty = 1;     /* force first draw */

#ifdef __APPLE__
    uint64_t loop_start = mach_absolute_time();
#else
    struct timespec loop_start;
    clock_gettime(CLOCK_MONOTONIC, &loop_start);
#endif

    /* Clear screen and draw initial frame */
    printf("\033[2J\033[H");
    printf("\n");
    printf("  \033[1m\033[33m⚒ Hammer × Forge\033[0m  \033[2minteractive mode\033[0m\n\n");
    fflush(stdout);

    while (!past_deadline()) {
        /* Poll keyboard */
        int key = hammer_poll_key();
        if (key == ' ' && cfg->pipeline_depth < HAMMER_MAX_PIPELINE) {
            int new_depth = cfg->pipeline_depth * 2;
            if (new_depth > HAMMER_MAX_PIPELINE) new_depth = HAMMER_MAX_PIPELINE;
            cfg->pipeline_depth = new_depth;
            strike_pending = 1;
        } else if (key == 'q' || key == 27) {  /* q or ESC */
            break;
        }

        /* Advance animation */
        int prev_frame = anim_frame;
        if (strike_pending && anim_frame == FORGE_ANIM_IDLE) {
            strike_pending = 0;
            anim_frame = FORGE_ANIM_WINDUP;
            anim_ticks = 2;  /* 200ms per frame at 100ms tick */
        }

        if (anim_ticks > 0) {
            anim_ticks--;
        } else if (anim_frame != FORGE_ANIM_IDLE) {
            anim_frame++;
            if (anim_frame >= FORGE_ANIM_FRAMES) {
                anim_frame = FORGE_ANIM_IDLE;
            } else {
                anim_ticks = (anim_frame == FORGE_ANIM_IMPACT) ? 3 : 2;
            }
        }
        int anim_changed = (anim_frame != prev_frame);

        /* Compute elapsed */
#ifdef __APPLE__
        uint64_t now_mach = mach_absolute_time();
        double elapsed = (double)(now_mach - loop_start) * g_mach_to_ns / 1e9;
#else
        struct timespec now_ts;
        clock_gettime(CLOCK_MONOTONIC, &now_ts);
        double elapsed = (now_ts.tv_sec - loop_start.tv_sec) +
                         (now_ts.tv_nsec - loop_start.tv_nsec) / 1e9;
#endif

        /* Only redraw when something changed */
        int stats_due = (elapsed - last_stats_time >= 1.0) || stats_dirty;
        if (anim_changed || stats_due) {
            /* Draw animation — move cursor to row 4 (after banner) */
            printf("\033[4;1H");
            hammer_draw_frame(anim_frame, cfg->pipeline_depth);

            /* Update stats only every 1 second */
            if (stats_due) {
                last_stats_time = elapsed;
                stats_dirty = 0;

                /* Detect excess capacity: server has goroutines but low queue depth */
                int show_capacity = 0;
                for (int i = 0; i < num_workers; i++) {
                    if (all_stats[i].last_server_goroutines > 0 &&
                        all_stats[i].last_server_queue_depth <= 0) {
                        show_capacity = 1;
                        break;
                    }
                }

                hammer_draw_stats(all_stats, num_workers, elapsed,
                                  cfg->pipeline_depth, show_capacity);
            }
            fflush(stdout);
        }

        usleep(100000);  /* 100ms tick — 10fps */
    }

    hammer_restore_terminal();
    printf("\033[2J\033[H");  /* clear screen for final report */
}

/* ---- Main entry point ---- */

WValue w_hammer_run(WValue url_val, WValue conns_val, WValue duration_val,
                    WValue workers_val, WValue protocol_val, WValue pipeline_val,
                    WValue forge_mode_val, WValue max_mode_val) {
    /* Parse arguments */
    char buf[6];
    const char *url_str;
    size_t url_len;
    w_str_data(url_val, buf, &url_str, &url_len);

    int connections = (int)w_as_int(conns_val);
    int duration_secs = (int)w_as_int(duration_val);
    int num_workers = (int)w_as_int(workers_val);
    int protocol = (int)w_as_int(protocol_val);
    int pipeline_depth = (int)w_as_int(pipeline_val);
    int forge_mode = (int)w_as_int(forge_mode_val);
    int max_mode = (int)w_as_int(max_mode_val);
    if (pipeline_depth <= 0 && !forge_mode) pipeline_depth = 256;
    if (pipeline_depth <= 0) pipeline_depth = 1;
    if (pipeline_depth > HAMMER_MAX_PIPELINE) pipeline_depth = HAMMER_MAX_PIPELINE;

    /* Auto-detect worker count */
    if (num_workers <= 0) {
        long ncpu = sysconf(_SC_NPROCESSORS_ONLN);
        if (ncpu <= 0) ncpu = 1;
        num_workers = (int)(ncpu - 1);
        if (num_workers < 1) num_workers = 1;
        if (num_workers > 8) num_workers = 8;
    }

    /* Parse URL */
    char *url_copy = malloc(url_len + 1);
    memcpy(url_copy, url_str, url_len);
    url_copy[url_len] = '\0';

    ParsedURL parsed;
    if (parse_url(url_copy, &parsed) < 0) {
        fprintf(stderr, "hammer: invalid URL: %s\n", url_copy);
        free(url_copy);
        return W_NIL;
    }
    free(url_copy);

    /* Resolve DNS once */
    struct addrinfo hints = {0}, *result;
    hints.ai_family = AF_INET;
    hints.ai_socktype = SOCK_STREAM;
    char port_str[16];
    snprintf(port_str, sizeof(port_str), "%d", parsed.port);

    int gai = getaddrinfo(parsed.host, port_str, &hints, &result);
    if (gai != 0) {
        fprintf(stderr, "hammer: DNS resolution failed for %s: %s\n",
                parsed.host, gai_strerror(gai));
        return W_NIL;
    }

    /* Build config */
    HammerConfig cfg = {0};
    memcpy(&cfg.addr, result->ai_addr, result->ai_addrlen);
    cfg.addr_len = result->ai_addrlen;
    cfg.host = parsed.host;
    cfg.port = parsed.port;
    cfg.use_tls = parsed.use_tls;
    cfg.protocol = protocol;
    cfg.num_workers = num_workers;
    cfg.pipeline_depth = pipeline_depth;
    cfg.forge_mode = forge_mode;
    cfg.max_mode = max_mode;
    freeaddrinfo(result);

    /* Distribute connections across workers */
    if (connections < num_workers) connections = num_workers;
    cfg.conns_per_worker = connections / num_workers;

    /* Pre-build HTTP request */
    const char *version = (protocol == HAMMER_PROTOCOL_H10) ? "HTTP/1.0" : "HTTP/1.1";
    const char *conn_header = (protocol == HAMMER_PROTOCOL_H11) ? "Connection: keep-alive\r\n" : "";

    int req_len = snprintf(NULL, 0, "GET %s %s\r\nHost: %s\r\n%s\r\n",
                           parsed.path, version, parsed.host, conn_header);
    cfg.request = malloc(req_len + 1);
    snprintf(cfg.request, req_len + 1, "GET %s %s\r\nHost: %s\r\n%s\r\n",
             parsed.path, version, parsed.host, conn_header);
    cfg.request_len = req_len;
    cfg.request_batch_len = req_len * HAMMER_MAX_PIPELINE;
    cfg.request_batch = malloc((size_t)cfg.request_batch_len);
    for (int i = 0; i < HAMMER_MAX_PIPELINE; i++) {
        memcpy(cfg.request_batch + (i * req_len), cfg.request, (size_t)req_len);
    }

    /* Set deadline */
#ifdef __APPLE__
    hammer_init_mach_time();
    g_hammer_deadline_mach = mach_absolute_time() +
        (uint64_t)((double)duration_secs * 1e9 / g_mach_to_ns);
#else
    g_hammer_deadline = monotonic_now() + duration_secs;
#endif

    /* Print banner (skip in forge mode — it has its own) */
    const char *proto_name = protocol == HAMMER_PROTOCOL_H10 ? "HTTP/1.0" :
                             protocol == HAMMER_PROTOCOL_H11 ? "HTTP/1.1" : "HTTP/2";
    int is_tty = isatty(fileno(stdout));
    if (!forge_mode) {
        if (is_tty) {
            printf("\n");
            printf("  \033[1m\033[33m⚒ Hammer\033[0m  %s\n", proto_name);
            printf("  \033[2m%s%s://%s:%d%s\033[0m\n",
                   cfg.use_tls ? "" : "", cfg.use_tls ? "https" : "http",
                   parsed.host, parsed.port, parsed.path);
            printf("  \033[2m%d connections · %d workers · %d pipeline · %ds\033[0m\n\n",
                   connections, num_workers, pipeline_depth, duration_secs);
        } else {
            printf("\nHammer  %s\n", proto_name);
            printf("%s://%s:%d%s\n", cfg.use_tls ? "https" : "http",
                   parsed.host, parsed.port, parsed.path);
            printf("%d connections, %d workers, %d pipeline, %ds\n\n", connections, num_workers, pipeline_depth, duration_secs);
        }
        fflush(stdout);
    }

    /* Allocate per-worker stats */
    HammerWorkerStats *all_stats = calloc(num_workers, sizeof(HammerWorkerStats));
    for (int i = 0; i < num_workers; i++) {
        all_stats[i].max_server_goroutines = -1;
        all_stats[i].max_server_queue_depth = -1;
        all_stats[i].last_server_goroutines = -1;
        all_stats[i].last_server_queue_depth = -1;
        all_stats[i].latency_cap = max_mode ? 0 : HAMMER_MAX_LATENCIES;
        all_stats[i].latencies = max_mode ? NULL : calloc(HAMMER_MAX_LATENCIES, sizeof(uint64_t));
    }

    /* Initialize goroutine arena */
    w_scheduler_init();
    w_scheduler_install_debug_signal();

    /* Record start time */
#ifdef __APPLE__
    uint64_t bench_start_mach = mach_absolute_time();
#else
    struct timespec bench_start;
    clock_gettime(CLOCK_MONOTONIC, &bench_start);
#endif

    /* Spawn worker threads */
    HammerWorkerArg *was = calloc(num_workers, sizeof(HammerWorkerArg));
    pthread_t *threads;

    for (int i = 0; i < num_workers; i++) {
        was[i].config = &cfg;
        was[i].stats = &all_stats[i];
        was[i].worker_id = i;
    }

    if (forge_mode) {
        /* Forge mode: ALL workers on separate threads, main thread runs display */
        threads = calloc(num_workers, sizeof(pthread_t));
        for (int i = 0; i < num_workers; i++) {
            pthread_create(&threads[i], NULL, hammer_worker_thread, &was[i]);
        }

        /* Main thread runs interactive display loop */
        hammer_forge_loop(&cfg, all_stats, num_workers, duration_secs);

        /* Join all worker threads */
        for (int i = 0; i < num_workers; i++) {
            pthread_join(threads[i], NULL);
        }
    } else {
        /* Normal mode: main thread is worker 0 */
        threads = calloc(num_workers - 1, sizeof(pthread_t));
        for (int i = 1; i < num_workers; i++) {
            pthread_create(&threads[i - 1], NULL, hammer_worker_thread, &was[i]);
        }

        hammer_worker_thread(&was[0]);

        for (int i = 1; i < num_workers; i++) {
            pthread_join(threads[i - 1], NULL);
        }
    }

    /* Record end time */
#ifdef __APPLE__
    uint64_t bench_end_mach = mach_absolute_time();
    double elapsed = (double)(bench_end_mach - bench_start_mach) * g_mach_to_ns / 1e9;
#else
    struct timespec bench_end;
    clock_gettime(CLOCK_MONOTONIC, &bench_end);
    double elapsed = (bench_end.tv_sec - bench_start.tv_sec) +
                     (bench_end.tv_nsec - bench_start.tv_nsec) / 1e9;
#endif

    /* Aggregate stats */
    uint64_t total_reqs = 0, total_bytes = 0;
    uint64_t s2xx = 0, s3xx = 0, s4xx = 0, s5xx = 0;
    uint64_t errors = 0, connect_errors = 0;
    uint64_t total_latency_count = 0;

    int64_t peak_server_goroutines = -1, peak_server_queue_depth = -1;
    int64_t last_server_goroutines = -1, last_server_queue_depth = -1;

    for (int i = 0; i < num_workers; i++) {
        total_reqs += all_stats[i].total_requests;
        total_bytes += all_stats[i].total_bytes;
        s2xx += all_stats[i].status_2xx;
        s3xx += all_stats[i].status_3xx;
        s4xx += all_stats[i].status_4xx;
        s5xx += all_stats[i].status_5xx;
        errors += all_stats[i].errors;
        connect_errors += all_stats[i].connect_errors;
        total_latency_count += all_stats[i].latency_count;
        if (all_stats[i].max_server_goroutines > peak_server_goroutines)
            peak_server_goroutines = all_stats[i].max_server_goroutines;
        if (all_stats[i].max_server_queue_depth > peak_server_queue_depth)
            peak_server_queue_depth = all_stats[i].max_server_queue_depth;
        if (all_stats[i].last_server_goroutines >= 0)
            last_server_goroutines = all_stats[i].last_server_goroutines;
        if (all_stats[i].last_server_queue_depth >= 0)
            last_server_queue_depth = all_stats[i].last_server_queue_depth;
    }
    int has_capacity = (peak_server_goroutines >= 0);

    /* Merge latency arrays */
    uint64_t *all_latencies = total_latency_count > 0 ? malloc(total_latency_count * sizeof(uint64_t)) : NULL;
    if (total_latency_count > 0) {
        uint64_t offset = 0;
        for (int i = 0; i < num_workers; i++) {
            memcpy(all_latencies + offset, all_stats[i].latencies,
                   all_stats[i].latency_count * sizeof(uint64_t));
            offset += all_stats[i].latency_count;
        }

        /* Sort latencies for percentile computation */
        qsort(all_latencies, total_latency_count, sizeof(uint64_t), cmp_u64);
    }

    /* Compute percentiles */
    char p50[32] = "-", p75[32] = "-", p90[32] = "-", p95[32] = "-", p99[32] = "-", p999[32] = "-";
    char min_lat[32] = "-", max_lat[32] = "-", avg_lat[32] = "-";

    if (total_latency_count > 0) {
        format_latency(p50, sizeof(p50), all_latencies[(uint64_t)(total_latency_count * 0.50)]);
        format_latency(p75, sizeof(p75), all_latencies[(uint64_t)(total_latency_count * 0.75)]);
        format_latency(p90, sizeof(p90), all_latencies[(uint64_t)(total_latency_count * 0.90)]);
        format_latency(p95, sizeof(p95), all_latencies[(uint64_t)(total_latency_count * 0.95)]);
        uint64_t p99_idx = (uint64_t)(total_latency_count * 0.99);
        if (p99_idx >= total_latency_count) p99_idx = total_latency_count - 1;
        format_latency(p99, sizeof(p99), all_latencies[p99_idx]);
        uint64_t p999_idx = (uint64_t)(total_latency_count * 0.999);
        if (p999_idx >= total_latency_count) p999_idx = total_latency_count - 1;
        format_latency(p999, sizeof(p999), all_latencies[p999_idx]);
        format_latency(min_lat, sizeof(min_lat), all_latencies[0]);
        format_latency(max_lat, sizeof(max_lat), all_latencies[total_latency_count - 1]);

        uint64_t sum = 0;
        for (uint64_t i = 0; i < total_latency_count; i++) sum += all_latencies[i];
        format_latency(avg_lat, sizeof(avg_lat), sum / total_latency_count);
    }

    double rps = total_reqs / elapsed;
    double throughput = total_bytes / elapsed;

    char rps_str[32], total_str[32], bytes_str[32], tput_str[32];
    format_count(rps_str, sizeof(rps_str), (uint64_t)rps);
    format_count(total_str, sizeof(total_str), total_reqs);
    format_bytes(bytes_str, sizeof(bytes_str), total_bytes);
    format_bytes(tput_str, sizeof(tput_str), (uint64_t)throughput);

    /* Print results */
    if (is_tty) {
        printf("  \033[1mLatency\033[0m\n");
        printf("    avg    %s\n", avg_lat);
        printf("    p50    %s\n", p50);
        printf("    p75    %s\n", p75);
        printf("    p90    %s\n", p90);
        printf("    p95    %s\n", p95);
        printf("    p99    %s\n", p99);
        printf("    p99.9  %s\n", p999);
        printf("    min    %s\n", min_lat);
        printf("    max    %s\n", max_lat);
        printf("\n  \033[1mLatency Distribution\033[0m\n");
        print_histogram(all_latencies, total_latency_count);
        printf("\n  \033[1mSummary\033[0m\n");
        printf("    \033[32m%s\033[0m requests in %.2fs\n", total_str, elapsed);
        printf("    \033[36m%s\033[0m req/s\n", rps_str);
        printf("    %s transferred (%s/s)\n", bytes_str, tput_str);
        if (s2xx) printf("    \033[32m2xx: %llu\033[0m", (unsigned long long)s2xx);
        if (s3xx) printf("  \033[33m3xx: %llu\033[0m", (unsigned long long)s3xx);
        if (s4xx) printf("  \033[31m4xx: %llu\033[0m", (unsigned long long)s4xx);
        if (s5xx) printf("  \033[31m5xx: %llu\033[0m", (unsigned long long)s5xx);
        if (s2xx || s3xx || s4xx || s5xx) printf("\n");
        if (errors) printf("    \033[31merrors: %llu\033[0m\n", (unsigned long long)errors);
        if (connect_errors) printf("    \033[31mconnect errors: %llu\033[0m\n", (unsigned long long)connect_errors);
        if (has_capacity) {
            printf("\n  \033[1mServer Capacity\033[0m  \033[2m(Forge handshake)\033[0m\n");
            printf("    goroutines  %lld peak, %lld last\n",
                   (long long)peak_server_goroutines, (long long)last_server_goroutines);
            printf("    queue depth %lld peak, %lld last\n",
                   (long long)peak_server_queue_depth, (long long)last_server_queue_depth);
        }
        printf("\n");
    } else {
        printf("Latency:\n");
        printf("  avg    %s\n", avg_lat);
        printf("  p50    %s\n", p50);
        printf("  p75    %s\n", p75);
        printf("  p90    %s\n", p90);
        printf("  p95    %s\n", p95);
        printf("  p99    %s\n", p99);
        printf("  p99.9  %s\n", p999);
        printf("  min    %s\n", min_lat);
        printf("  max    %s\n", max_lat);
        printf("\nSummary:\n");
        printf("  %s requests in %.2fs\n", total_str, elapsed);
        printf("  %s req/s\n", rps_str);
        printf("  %s transferred (%s/s)\n", bytes_str, tput_str);
        if (s2xx) printf("  2xx: %llu", (unsigned long long)s2xx);
        if (s3xx) printf("  3xx: %llu", (unsigned long long)s3xx);
        if (s4xx) printf("  4xx: %llu", (unsigned long long)s4xx);
        if (s5xx) printf("  5xx: %llu", (unsigned long long)s5xx);
        if (s2xx || s3xx || s4xx || s5xx) printf("\n");
        if (errors) printf("  errors: %llu\n", (unsigned long long)errors);
        if (connect_errors) printf("  connect errors: %llu\n", (unsigned long long)connect_errors);
        if (has_capacity) {
            printf("\nServer Capacity (Forge handshake):\n");
            printf("  goroutines  %lld peak, %lld last\n",
                   (long long)peak_server_goroutines, (long long)last_server_goroutines);
            printf("  queue depth %lld peak, %lld last\n",
                   (long long)peak_server_queue_depth, (long long)last_server_queue_depth);
        }
        printf("\n");
    }

    /* Cleanup */
    for (int i = 0; i < num_workers; i++) {
        free(all_stats[i].latencies);
    }
    free(all_stats);
    free(all_latencies);
    free(was);
    free(threads);
    free(cfg.request);
    free(cfg.request_batch);
    free(parsed.host);
    free(parsed.path);

    return w_int((int64_t)rps);
}
