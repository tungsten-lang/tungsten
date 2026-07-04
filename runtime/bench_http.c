/*
 * bench_http.c — Simulated HTTP request processing benchmark
 *
 * Exercises the NaN-boxed runtime the way tungsten-forge would:
 * string parsing, object creation, hash-like lookups, method dispatch,
 * response building, and mixed-type operations across the request lifecycle.
 *
 * Compile:
 *   clang -O2 runtime.c bench_http.c -o bench_http
 */

#include "runtime.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

/* Helper: extract a C string from a WValue string.
   Uses w_str_data() which handles both inline and heap strings.
   WARNING: returns a pointer to static storage — not thread-safe / reentrant. */
static const char *str_val(WValue v) {
    static char buf[6];
    const char *out; size_t len;
    w_str_data(v, buf, &out, &len);
    return out;
}

/* ---- Benchmark harness ---- */

static double bench(const char *name, void (*fn)(int64_t), int64_t iters) {
    struct timespec start, end;
    clock_gettime(CLOCK_MONOTONIC, &start);
    fn(iters);
    clock_gettime(CLOCK_MONOTONIC, &end);
    double elapsed = (end.tv_sec - start.tv_sec) + (end.tv_nsec - start.tv_nsec) / 1e9;
    double ops = iters / elapsed;
    printf("  %-40s  %12.0f ops/s  (%6.3f ms)\n", name, ops, elapsed * 1000);
    return ops;
}

/* ---- Simulated HTTP request processing ---- */

/* Pre-intern common symbols (like forge's router would) */
static WValue SYM_GET, SYM_POST, SYM_PUT, SYM_DELETE;
static WValue SYM_STATUS, SYM_HEADERS, SYM_BODY, SYM_METHOD, SYM_PATH;
static WValue SYM_CONTENT_TYPE, SYM_CONTENT_LENGTH, SYM_CONNECTION;
static WValue SYM_KEEP_ALIVE, SYM_CLOSE;
static WValue SYM_OK, SYM_NOT_FOUND, SYM_ERROR;

static void init_symbols(void) {
    SYM_GET = w_symbol("GET");
    SYM_POST = w_symbol("POST");
    SYM_PUT = w_symbol("PUT");
    SYM_DELETE = w_symbol("DELETE");
    SYM_STATUS = w_symbol("status");
    SYM_HEADERS = w_symbol("headers");
    SYM_BODY = w_symbol("body");
    SYM_METHOD = w_symbol("method");
    SYM_PATH = w_symbol("path");
    SYM_CONTENT_TYPE = w_symbol("content-type");
    SYM_CONTENT_LENGTH = w_symbol("content-length");
    SYM_CONNECTION = w_symbol("connection");
    SYM_KEEP_ALIVE = w_symbol("keep-alive");
    SYM_CLOSE = w_symbol("close");
    SYM_OK = w_symbol("ok");
    SYM_NOT_FOUND = w_symbol("not_found");
    SYM_ERROR = w_symbol("error");
}

/*
 * 1. Parse HTTP request line
 *    Simulates: "GET /api/users/42 HTTP/1.1\r\n" → method, path, version
 */
static void bench_parse_request_line(int64_t n) {
    const char *raw = "GET /api/users/42 HTTP/1.1\r\n";
    volatile WValue method, path;

    for (int64_t i = 0; i < n; i++) {
        /* Find first space → method */
        const char *p = raw;
        while (*p != ' ') p++;
        size_t mlen = p - raw;
        char mbuf[8];
        memcpy(mbuf, raw, mlen);
        mbuf[mlen] = '\0';

        /* Intern the method (GET/POST/etc) for fast symbol compare */
        WValue m = w_symbol(mbuf);
        method = m;

        /* Find second space → path */
        p++;
        const char *path_start = p;
        while (*p != ' ') p++;
        size_t plen = p - path_start;
        char pbuf[256];
        memcpy(pbuf, path_start, plen);
        pbuf[plen] = '\0';
        path = w_string(pbuf);
    }
}

/*
 * 2. Route matching
 *    Simulates checking a request method + path against 8 routes
 */

typedef struct {
    WValue method;
    const char *pattern;
    int handler_id;
} Route;

static Route routes[8];
static int route_count = 0;

static void init_routes(void) {
    routes[0] = (Route){ SYM_GET,    "/",               0 };
    routes[1] = (Route){ SYM_GET,    "/api/users",      1 };
    routes[2] = (Route){ SYM_GET,    "/api/users/:id",  2 };
    routes[3] = (Route){ SYM_POST,   "/api/users",      3 };
    routes[4] = (Route){ SYM_PUT,    "/api/users/:id",  4 };
    routes[5] = (Route){ SYM_DELETE, "/api/users/:id",  5 };
    routes[6] = (Route){ SYM_GET,    "/api/posts",      6 };
    routes[7] = (Route){ SYM_GET,    "/health",         7 };
    route_count = 8;
}

/* Simple route match: exact or single :param segment */
static int match_route(WValue method, const char *path, Route *r) {
    if (method != r->method) return 0;
    const char *p = path;
    const char *pat = r->pattern;
    while (*p && *pat) {
        if (*pat == ':') {
            /* Skip param segment in both */
            while (*pat && *pat != '/') pat++;
            while (*p && *p != '/') p++;
        } else {
            if (*p != *pat) return 0;
            p++;
            pat++;
        }
    }
    return (*p == '\0' && *pat == '\0');
}

static void bench_route_match(int64_t n) {
    WValue method = SYM_GET;
    const char *paths[] = {
        "/api/users/42", "/api/posts", "/health",
        "/api/users", "/", "/api/users/99",
        "/nonexistent", "/api/posts",
    };
    int npaths = 8;
    volatile int handler = -1;

    for (int64_t i = 0; i < n; i++) {
        const char *path = paths[i % npaths];
        int found = -1;
        for (int r = 0; r < route_count; r++) {
            if (match_route(method, path, &routes[r])) {
                found = routes[r].handler_id;
                break;
            }
        }
        handler = found;
    }
}

/*
 * 3. Header parsing
 *    Parse 8 typical HTTP headers into key-value pairs
 */
static void bench_parse_headers(int64_t n) {
    const char *raw_headers =
        "Host: example.com\r\n"
        "Content-Type: application/json\r\n"
        "Content-Length: 42\r\n"
        "Connection: keep-alive\r\n"
        "Accept: text/html\r\n"
        "User-Agent: tungsten/1.0\r\n"
        "Authorization: Bearer tok123\r\n"
        "X-Request-Id: abc-def-ghi\r\n"
        "\r\n";

    volatile WValue last_key, last_val;

    for (int64_t i = 0; i < n; i++) {
        const char *p = raw_headers;
        while (*p && !(p[0] == '\r' && p[1] == '\n' && p[2] == '\r')) {
            /* Find colon → key */
            const char *key_start = p;
            while (*p != ':') p++;
            size_t klen = p - key_start;

            /* Skip ": " → value */
            p += 2;
            const char *val_start = p;
            while (*p != '\r') p++;
            size_t vlen = p - val_start;

            /* Intern key, allocate value string */
            char kbuf[64], vbuf[256];
            memcpy(kbuf, key_start, klen); kbuf[klen] = '\0';
            memcpy(vbuf, val_start, vlen); vbuf[vlen] = '\0';

            WValue key = w_symbol(kbuf);
            WValue val = w_string(vbuf);
            last_key = key;
            last_val = val;

            p += 2; /* skip \r\n */
        }
    }
}

/*
 * 4. Build a request object
 *    Create an object with method, path, headers, body
 */
static WValue request_class;

static void init_request_class(void) {
    request_class = w_class_new("Request", W_NIL);
}

static void bench_build_request(int64_t n) {
    volatile WValue req;

    for (int64_t i = 0; i < n; i++) {
        WValue obj = w_object_new(request_class);
        w_ivar_set(obj, "@method", SYM_GET);
        w_ivar_set(obj, "@path", w_string("/api/users/42"));
        w_ivar_set(obj, "@body", w_string("{\"name\":\"alice\"}"));
        w_ivar_set(obj, "@status", w_int(0));
        w_ivar_set(obj, "@content_type", SYM_CONTENT_TYPE);
        req = obj;
    }
}

/*
 * 5. Build a response
 *    Create response with status, headers, body — then serialize to string
 */
static void bench_build_response(int64_t n) {
    volatile WValue response_str;

    for (int64_t i = 0; i < n; i++) {
        WValue status = w_int(200);
        WValue body = w_string("{\"id\":42,\"name\":\"alice\",\"email\":\"alice@example.com\"}");
        WValue content_type = w_string("application/json");

        /* Build response line */
        WValue line = w_string("HTTP/1.1 ");
        line = w_str_concat(line, w_to_s(status));
        line = w_str_concat(line, w_string(" OK\r\n"));

        /* Headers */
        line = w_str_concat(line, w_string("Content-Type: "));
        line = w_str_concat(line, content_type);
        line = w_str_concat(line, w_string("\r\n"));

        WValue body_len = w_to_s(w_int((int64_t)strlen(str_val(body))));
        line = w_str_concat(line, w_string("Content-Length: "));
        line = w_str_concat(line, body_len);
        line = w_str_concat(line, w_string("\r\n"));

        line = w_str_concat(line, w_string("Connection: keep-alive\r\n"));
        line = w_str_concat(line, w_string("\r\n"));

        /* Body */
        line = w_str_concat(line, body);

        response_str = line;
    }
}

/*
 * 6. Middleware chain
 *    Simulate logging + rate limiting + CORS middleware
 */
static void bench_middleware_chain(int64_t n) {
    volatile WValue result;

    for (int64_t i = 0; i < n; i++) {
        WValue req_method = SYM_GET;
        WValue req_path = w_string("/api/users/42");

        /* Logger middleware: check truthiness, build log string */
        WValue log_entry = W_NIL;
        if (w_truthy(req_method) && w_truthy(req_path)) {
            log_entry = w_str_concat(w_to_s(req_method), w_string(" "));
            log_entry = w_str_concat(log_entry, req_path);
        }

        /* Rate limiter: int compare + increment */
        WValue counter = w_int(i % 100);
        WValue limit = w_int(100);
        WValue allowed = w_lt(counter, limit);

        /* CORS: symbol compare for method check */
        WValue is_options = w_eq(req_method, w_symbol("OPTIONS"));
        WValue is_get = w_eq(req_method, SYM_GET);

        if (w_truthy(allowed) && (w_truthy(is_get) || w_truthy(is_options))) {
            result = log_entry;
        } else {
            result = w_string("429 Too Many Requests");
        }
    }
}

/*
 * 7. Full request cycle
 *    Parse → route → middleware → handler → response → serialize
 */
static void bench_full_request_cycle(int64_t n) {
    const char *raw_request = "GET /api/users/42 HTTP/1.1\r\n";
    volatile WValue final_response;

    for (int64_t i = 0; i < n; i++) {
        /* Parse request line */
        const char *p = raw_request;
        while (*p != ' ') p++;
        size_t mlen = p - raw_request;
        char mbuf[8];
        memcpy(mbuf, raw_request, mlen);
        mbuf[mlen] = '\0';
        WValue method = w_symbol(mbuf);

        p++;
        const char *path_start = p;
        while (*p != ' ') p++;
        size_t plen = p - path_start;
        char pbuf[256];
        memcpy(pbuf, path_start, plen);
        pbuf[plen] = '\0';
        WValue path = w_string(pbuf);

        /* Route match */
        int handler_id = -1;
        const char *path_cstr = str_val(path);
        for (int r = 0; r < route_count; r++) {
            if (match_route(method, path_cstr, &routes[r])) {
                handler_id = routes[r].handler_id;
                break;
            }
        }

        /* Build request object */
        WValue req = w_object_new(request_class);
        w_ivar_set(req, "@method", method);
        w_ivar_set(req, "@path", path);

        /* Middleware: truthiness checks */
        if (!w_truthy(method) || !w_truthy(path)) continue;

        /* Handler: produce response body */
        WValue body;
        if (handler_id == 2) {
            body = w_string("{\"id\":42,\"name\":\"alice\"}");
        } else if (handler_id >= 0) {
            body = w_string("{\"ok\":true}");
        } else {
            body = w_string("{\"error\":\"not found\"}");
        }

        /* Build response */
        WValue status = (handler_id >= 0) ? w_int(200) : w_int(404);
        WValue resp = w_string("HTTP/1.1 ");
        resp = w_str_concat(resp, w_to_s(status));
        resp = w_str_concat(resp, w_string(handler_id >= 0 ? " OK\r\n" : " Not Found\r\n"));
        resp = w_str_concat(resp, w_string("Content-Type: application/json\r\n"));
        resp = w_str_concat(resp, w_string("Content-Length: "));
        resp = w_str_concat(resp, w_to_s(w_int((int64_t)strlen(str_val(body)))));
        resp = w_str_concat(resp, w_string("\r\n\r\n"));
        resp = w_str_concat(resp, body);

        final_response = resp;
    }
}

/* ---- Main ---- */

int main(void) {
    init_symbols();
    init_routes();
    init_request_class();

    printf("\n");
    printf("  HTTP request processing benchmark (NaN-boxed runtime)\n");
    printf("  =====================================================\n\n");

    bench("parse request line",          bench_parse_request_line,  1000000);
    bench("route match (8 routes)",      bench_route_match,         10000000);
    bench("parse headers (8 headers)",   bench_parse_headers,       1000000);
    bench("build request object",        bench_build_request,       1000000);
    bench("build + serialize response",  bench_build_response,      1000000);
    bench("middleware chain (3 layers)", bench_middleware_chain,     1000000);
    bench("full request cycle",          bench_full_request_cycle,  1000000);

    printf("\n  Done.\n\n");
    return 0;
}
