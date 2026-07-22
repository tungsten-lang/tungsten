/* pg_bridge.c — minimal libpq bridge for Tungsten (ccall surface).
 *
 * Loaded into any project that `requires ["tungsten-pg"]` via the Bitfile
 * includes walk. libpq itself is dlopen'd at first use so nothing gains a
 * hard link dependency; if libpq is absent, w_pg_connect raises with an
 * actionable message.
 *
 * Conventions (matching runtime/sci_io_native.c):
 *   - every entry point is WValue f(WValue...)
 *   - connection handles are indices into a static 16-slot table
 *   - text format everywhere; a result set is a poly Array of row Arrays of
 *     String (SQL NULL → nil)
 *   - errors raise, except w_pg_last_error which reports.
 */
#include "runtime.h"
#include "wvalue.h"
#include <dlfcn.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* libpq enum values (stable ABI; headers deliberately not required) */
#define PG_CONNECTION_OK 0
#define PGRES_COMMAND_OK 1
#define PGRES_TUPLES_OK 2
#define PGRES_COPY_IN 4

typedef void PGconn_;
typedef void PGresult_;

static struct {
    void *lib;
    PGconn_ *(*PQconnectdb)(const char *);
    int (*PQstatus)(const PGconn_ *);
    char *(*PQerrorMessage)(const PGconn_ *);
    void (*PQfinish)(PGconn_ *);
    PGresult_ *(*PQexec)(PGconn_ *, const char *);
    PGresult_ *(*PQexecParams)(PGconn_ *, const char *, int, const void *,
                               const char *const *, const int *, const int *, int);
    int (*PQresultStatus)(const PGresult_ *);
    char *(*PQresultErrorMessage)(const PGresult_ *);
    int (*PQntuples)(const PGresult_ *);
    int (*PQnfields)(const PGresult_ *);
    char *(*PQgetvalue)(const PGresult_ *, int, int);
    int (*PQgetisnull)(const PGresult_ *, int, int);
    void (*PQclear)(PGresult_ *);
    int (*PQputCopyData)(PGconn_ *, const char *, int);
    int (*PQputCopyEnd)(PGconn_ *, const char *);
    PGresult_ *(*PQgetResult)(PGconn_ *);
} pq;

#define PG_MAX_CONNS 16
static PGconn_ *pg_conns[PG_MAX_CONNS];
static char pg_last_err[4096];

static void pg_set_err(const char *msg) {
    snprintf(pg_last_err, sizeof(pg_last_err), "%s", msg ? msg : "(null)");
}

static void *pg_sym(const char *name) {
    void *p = dlsym(pq.lib, name);
    if (!p) {
        pg_set_err(name);
        w_raise(w_string("pg_bridge: libpq missing symbol"));
    }
    return p;
}

static void pg_load(void) {
    if (pq.lib) return;
    const char *override = getenv("TUNGSTEN_PG_LIBPQ");
    if (override && *override) {
        pq.lib = dlopen(override, RTLD_NOW | RTLD_LOCAL);
        if (!pq.lib) {
            w_raise(w_string("pg_bridge: TUNGSTEN_PG_LIBPQ set but dlopen failed"));
            return;
        }
    }
    static const char *candidates[] = {
        "libpq.5.dylib",
        "/opt/homebrew/opt/libpq/lib/libpq.5.dylib",
        "/opt/homebrew/lib/libpq.5.dylib",
        /* Homebrew postgresql formula bundles libpq without exposing it */
        "/opt/homebrew/lib/postgresql@18/libpq.5.dylib",
        "/opt/homebrew/lib/postgresql@17/libpq.5.dylib",
        "/opt/homebrew/lib/postgresql@16/libpq.5.dylib",
        "/usr/local/opt/libpq/lib/libpq.5.dylib",
        "libpq.so.5",
        "libpq.so",
        NULL,
    };
    for (int i = 0; !pq.lib && candidates[i]; i++) {
        pq.lib = dlopen(candidates[i], RTLD_NOW | RTLD_LOCAL);
        if (pq.lib) break;
    }
    if (!pq.lib) {
        w_raise(w_string("pg_bridge: libpq not found — brew install libpq "
                         "(or apt install libpq5)"));
        return;
    }
    pq.PQconnectdb = pg_sym("PQconnectdb");
    pq.PQstatus = pg_sym("PQstatus");
    pq.PQerrorMessage = pg_sym("PQerrorMessage");
    pq.PQfinish = pg_sym("PQfinish");
    pq.PQexec = pg_sym("PQexec");
    pq.PQexecParams = pg_sym("PQexecParams");
    pq.PQresultStatus = pg_sym("PQresultStatus");
    pq.PQresultErrorMessage = pg_sym("PQresultErrorMessage");
    pq.PQntuples = pg_sym("PQntuples");
    pq.PQnfields = pg_sym("PQnfields");
    pq.PQgetvalue = pg_sym("PQgetvalue");
    pq.PQgetisnull = pg_sym("PQgetisnull");
    pq.PQclear = pg_sym("PQclear");
    pq.PQputCopyData = pg_sym("PQputCopyData");
    pq.PQputCopyEnd = pg_sym("PQputCopyEnd");
    pq.PQgetResult = pg_sym("PQgetResult");
}

/* Copy a Tungsten string into a fresh NUL-terminated heap buffer. */
static char *pg_cstr(WValue v) {
    char tmp[6];
    const char *s = NULL;
    size_t len = 0;
    w_str_data(v, tmp, &s, &len);
    char *buf = malloc(len + 1);
    memcpy(buf, s, len);
    buf[len] = 0;
    return buf;
}

static PGconn_ *pg_conn(WValue handle) {
    int64_t h = w_as_int(handle);
    if (h < 0 || h >= PG_MAX_CONNS || !pg_conns[h]) {
        w_raise(w_string("pg_bridge: bad connection handle"));
        return NULL;
    }
    return pg_conns[h];
}

/* w_pg_connect(url) -> handle Int; raises on failure */
WValue w_pg_connect(WValue url) {
    pg_load();
    int slot = -1;
    for (int i = 0; i < PG_MAX_CONNS; i++) {
        if (!pg_conns[i]) { slot = i; break; }
    }
    if (slot < 0) {
        w_raise(w_string("pg_bridge: all 16 connection slots in use"));
        return W_NIL;
    }
    char *cs = pg_cstr(url);
    PGconn_ *conn = pq.PQconnectdb(cs);
    free(cs);
    if (!conn || pq.PQstatus(conn) != PG_CONNECTION_OK) {
        pg_set_err(conn ? pq.PQerrorMessage(conn) : "PQconnectdb returned NULL");
        if (conn) pq.PQfinish(conn);
        w_raise(w_string("pg_bridge: connect failed (see w_pg_last_error)"));
        return W_NIL;
    }
    pg_conns[slot] = conn;
    return w_int(slot);
}

/* w_pg_close(handle) -> nil (idempotent) */
WValue w_pg_close(WValue handle) {
    int64_t h = w_as_int(handle);
    if (h >= 0 && h < PG_MAX_CONNS && pg_conns[h]) {
        pq.PQfinish(pg_conns[h]);
        pg_conns[h] = NULL;
    }
    return W_NIL;
}

/* Build the poly Array-of-row-Arrays result, then clear res. */
static WValue pg_rows(PGresult_ *res) {
    WValue rows = w_array_new_empty();
    int nt = pq.PQntuples(res), nf = pq.PQnfields(res);
    for (int r = 0; r < nt; r++) {
        WValue row = w_array_new_empty();
        for (int c = 0; c < nf; c++) {
            if (pq.PQgetisnull(res, r, c))
                row = w_array_push(row, W_NIL);
            else
                row = w_array_push(row, w_string(pq.PQgetvalue(res, r, c)));
        }
        rows = w_array_push(rows, row);
    }
    pq.PQclear(res);
    return rows;
}

static WValue pg_check_and_rows(PGconn_ *conn, PGresult_ *res, const char *who) {
    if (!res) {
        pg_set_err(pq.PQerrorMessage(conn));
        w_raise(w_string("pg_bridge: exec returned NULL (see w_pg_last_error)"));
        return W_NIL;
    }
    int st = pq.PQresultStatus(res);
    if (st != PGRES_COMMAND_OK && st != PGRES_TUPLES_OK) {
        pg_set_err(pq.PQresultErrorMessage(res));
        pq.PQclear(res);
        (void)who;
        w_raise(w_string("pg_bridge: SQL error (see w_pg_last_error)"));
        return W_NIL;
    }
    return pg_rows(res);
}

/* w_pg_exec(handle, sql) -> Array of row Arrays (empty for commands) */
WValue w_pg_exec(WValue handle, WValue sql) {
    PGconn_ *conn = pg_conn(handle);
    char *cs = pg_cstr(sql);
    PGresult_ *res = pq.PQexec(conn, cs);
    free(cs);
    return pg_check_and_rows(conn, res, "exec");
}

/* w_pg_exec_params(handle, sql, params) — params: poly Array of String/nil.
 * Text format in and out ($1..$n). */
WValue w_pg_exec_params(WValue handle, WValue sql, WValue params) {
    PGconn_ *conn = pg_conn(handle);
    WArray *a = (WArray *)w_as_ptr(params);
    int n = (int)a->size;
    char **vals = calloc((size_t)(n ? n : 1), sizeof(char *));
    for (int i = 0; i < n; i++) {
        WValue p = ((WValue *)a->slots)[a->start + i];
        vals[i] = (p == W_NIL) ? NULL : pg_cstr(p);
    }
    char *cs = pg_cstr(sql);
    PGresult_ *res = pq.PQexecParams(conn, cs, n, NULL,
                                     (const char *const *)vals, NULL, NULL, 0);
    free(cs);
    for (int i = 0; i < n; i++) free(vals[i]);
    free(vals);
    return pg_check_and_rows(conn, res, "exec_params");
}

/* w_pg_copy_start(handle, copy_sql) — copy_sql must be COPY ... FROM STDIN */
WValue w_pg_copy_start(WValue handle, WValue sql) {
    PGconn_ *conn = pg_conn(handle);
    char *cs = pg_cstr(sql);
    PGresult_ *res = pq.PQexec(conn, cs);
    free(cs);
    if (!res || pq.PQresultStatus(res) != PGRES_COPY_IN) {
        pg_set_err(res ? pq.PQresultErrorMessage(res) : pq.PQerrorMessage(conn));
        if (res) pq.PQclear(res);
        w_raise(w_string("pg_bridge: COPY start failed (see w_pg_last_error)"));
        return W_NIL;
    }
    pq.PQclear(res);
    return w_int(1);
}

/* w_pg_copy_write(handle, chunk) — raw bytes, no NUL needed */
WValue w_pg_copy_write(WValue handle, WValue chunk) {
    PGconn_ *conn = pg_conn(handle);
    char tmp[6];
    const char *s = NULL;
    size_t len = 0;
    w_str_data(chunk, tmp, &s, &len);
    if (pq.PQputCopyData(conn, s, (int)len) != 1) {
        pg_set_err(pq.PQerrorMessage(conn));
        w_raise(w_string("pg_bridge: COPY write failed (see w_pg_last_error)"));
    }
    return W_NIL;
}

/* w_pg_copy_finish(handle) -> rows Int is not exposed by PQputCopyEnd;
 * drains results and raises if the server reports an error. */
WValue w_pg_copy_finish(WValue handle) {
    PGconn_ *conn = pg_conn(handle);
    if (pq.PQputCopyEnd(conn, NULL) != 1) {
        pg_set_err(pq.PQerrorMessage(conn));
        w_raise(w_string("pg_bridge: COPY end failed (see w_pg_last_error)"));
        return W_NIL;
    }
    PGresult_ *res;
    int64_t bad = 0;
    while ((res = pq.PQgetResult(conn)) != NULL) {
        int st = pq.PQresultStatus(res);
        if (st != PGRES_COMMAND_OK && st != PGRES_TUPLES_OK) {
            pg_set_err(pq.PQresultErrorMessage(res));
            bad = 1;
        }
        pq.PQclear(res);
    }
    if (bad) {
        w_raise(w_string("pg_bridge: COPY failed server-side (see w_pg_last_error)"));
        return W_NIL;
    }
    return w_int(1);
}

/* w_pg_last_error(handle?) -> String (handle ignored; last bridge error) */
WValue w_pg_last_error(WValue handle) {
    (void)handle;
    return w_string(pg_last_err);
}
