#ifndef W_RUNTIME_UNITY_INCLUDE
#ifdef __linux__
#define _GNU_SOURCE
#include <sched.h>
#endif
#include "runtime_internal.h"
#include <arpa/inet.h>
#include <dlfcn.h>
#include <errno.h>
#include <fcntl.h>
#include <netdb.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <poll.h>
#include <pthread.h>
#include <signal.h>
#include <stdatomic.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/time.h>
#include <sys/uio.h>
#include <time.h>
#include <unistd.h>
#ifdef __aarch64__
#include <arm_neon.h>
#endif
#ifdef __APPLE__
#include <dispatch/dispatch.h>
#include <mach/mach_time.h>
#include <mach/thread_act.h>
#include <mach/thread_policy.h>
#include <sys/sysctl.h>
#endif
#define die w_rt_die
#define as_str w_rt_as_str
#define as_hash w_rt_as_hash
#define w_string_n w_rt_string_n
#define w_string_n_known_ascii w_rt_string_n_known_ascii
#define w_string_ascii_p w_rt_string_ascii_p
#define w_bytes_ascii_p w_rt_bytes_ascii_p
#define w_string_take w_rt_string_take
#define w_slab_read w_rt_slab_read
#define w_string_ascii_case w_rt_string_ascii_case
#define cmp_numeric_double w_rt_cmp_numeric_double
#define bigint_alloc w_rt_bigint_alloc
#define bigint_release_if_live w_rt_bigint_release_if_live
#endif

/* ---- Memoization (open-addressing hash table) ---- */

#define MEMO_MAGIC "WMEM"

/* Fast 64-bit word mixer for 1-arg and 2-arg memo keys, FNV-1a fallback */
static inline uint64_t memo_hash(WValue *args, int arity) {
    if (arity == 1) {
        uint64_t x = (uint64_t)args[0] ^ 0x9e3779b97f4a7c15ULL;
        x = (x ^ (x >> 30)) * 0xbf58476d1ce4e5b9ULL;
        return x ^ (x >> 27);
    }
    if (arity == 2) {
        uint64_t x = ((uint64_t)args[0] * 0x9e3779b97f4a7c15ULL) ^ (uint64_t)args[1];
        x = (x ^ (x >> 30)) * 0xbf58476d1ce4e5b9ULL;
        return x ^ (x >> 27);
    }
    uint64_t h = 14695981039346656037ULL;
    const uint8_t *p = (const uint8_t *)args;
    int nbytes = arity * (int)sizeof(WValue);
    for (int i = 0; i < nbytes; i++) {
        h ^= p[i];
        h *= 1099511628211ULL;
    }
    return h;
}

static void memo_alloc(WMemoTable *t, int cap) {
    t->cap = cap;
    int arity = t->arity > 0 ? t->arity : 1;
    t->keys = malloc(sizeof(WValue) * cap * arity);
    for (int i = 0; i < cap; i++) t->keys[i * arity] = W_UNDEF;
    t->values = calloc(1, sizeof(WValue) * cap);
}

static void memo_insert_raw(WMemoTable *t, WValue *key, WValue val) {
    uint64_t h = memo_hash(key, t->arity);
    int mask = t->cap - 1;
    int idx = (int)(h & (uint64_t)mask);
    int arity = t->arity;
    while (t->keys[idx * arity] != W_UNDEF) {
        idx = (idx + 1) & mask;
    }
    memcpy(&t->keys[idx * arity], key, arity * sizeof(WValue));
    t->values[idx] = val;
    t->count++;
}

static void memo_resize(WMemoTable *t) {
    int old_cap = t->cap;
    WValue *old_keys = t->keys;
    WValue *old_values = t->values;
    int old_arity = t->arity;

    t->count = 0;
    memo_alloc(t, old_cap * 2);

    for (int i = 0; i < old_cap; i++) {
        if (old_keys[i * old_arity] != W_UNDEF) {
            memo_insert_raw(t, &old_keys[i * old_arity], old_values[i]);
        }
    }
}

static void w_memo_load(WMemoTable *t, const char *sha) {
    const char *home = getenv("HOME");
    if (!home) return;

    char path[512];
    snprintf(path, sizeof(path), "%s/.tungsten/cache/%s.memo", home, sha);

    FILE *f = fopen(path, "rb");
    if (!f) return;

    /* Read and verify header */
    char magic[4];
    uint32_t version, file_arity, file_count;
    if (fread(magic, 1, 4, f) != 4 || memcmp(magic, MEMO_MAGIC, 4) != 0) { fclose(f); return; }
    if (fread(&version, 4, 1, f) != 1 || version != MEMO_VERSION) { fclose(f); return; }
    if (fread(&file_arity, 4, 1, f) != 1) { fclose(f); return; }
    if (fread(&file_count, 4, 1, f) != 1) { fclose(f); return; }

    if ((int)file_arity != t->arity && t->arity != 0) { fclose(f); return; }
    t->arity = (int)file_arity;

    int needed = (int)file_count;
    if (needed > MEMO_MAX_ENTRIES) needed = MEMO_MAX_ENTRIES;

    int cap = 256;
    while (cap * MEMO_HT_LOAD_NUM < needed * MEMO_HT_LOAD_DEN * 2) cap *= 2;
    memo_alloc(t, cap);

    WValue *entry_buf = calloc(1, sizeof(WValue) * t->arity);
    for (int i = 0; i < needed; i++) {
        if (fread(entry_buf, sizeof(WValue), t->arity, f) != (size_t)t->arity) { fclose(f); return; }
        WValue val;
        if (fread(&val, sizeof(WValue), 1, f) != 1) { fclose(f); return; }
        memo_insert_raw(t, entry_buf, val);
    }
    fclose(f);
}

void *w_memo_init(const char *sha) {
    WMemoTable *t = calloc(1, sizeof(WMemoTable));
    t->arity = 0;
    t->count = 0;
    t->cap = 0;
    t->hits = 0;
    t->disabled = 0;
    t->keys = NULL;
    t->values = NULL;
    memset(t->sha, 0, 17);
    if (sha) {
        strncpy(t->sha, sha, 16);
        t->sha[16] = '\0';
        w_memo_load(t, sha);
    }

    return t;
}

WValue w_memo_lookup(void *table, WValue *args, int arity) {
    WMemoTable *t = (WMemoTable *)table;
    if (t->disabled) return W_MEMO_MISS;
    if (t->arity == 0 && arity != 0) t->arity = arity;
    if (!t->keys) memo_alloc(t, 256);

    uint64_t h = memo_hash(args, arity);
    int mask = t->cap - 1;
    int idx = (int)(h & (uint64_t)mask);
    int a = t->arity > 0 ? t->arity : 1;

    while (t->keys[idx * a] != W_UNDEF) {
        WValue *k = &t->keys[idx * a];
        int match = 1;
        for (int j = 0; j < arity; j++) {
            if (k[j] != args[j]) { match = 0; break; }
        }
        if (match) {
            t->hits++;
            return t->values[idx];
        }
        idx = (idx + 1) & mask;
    }

    return W_MEMO_MISS;
}

void w_memo_store(void *table, WValue *args, int arity, WValue result) {
    WMemoTable *t = (WMemoTable *)table;
    if (t->disabled) return;
    if (t->arity == 0 && arity != 0) t->arity = arity;
    if (!t->keys) memo_alloc(t, 256);

    if (t->count >= 4096 && (int64_t)t->hits * 64 < (int64_t)t->count) {
        t->disabled = 1;
        return;
    }
    if (t->count >= MEMO_MAX_ENTRIES) return;

    if ((t->count + 1) * MEMO_HT_LOAD_DEN > t->cap * MEMO_HT_LOAD_NUM) {
        memo_resize(t);
    }

    memo_insert_raw(t, args, result);
}

void w_memo_save(void *table, const char *sha) {
    WMemoTable *t = (WMemoTable *)table;
    if (t->count == 0) return;

    const char *home = getenv("HOME");
    if (!home) return;

    char dir[512];
    snprintf(dir, sizeof(dir), "%s/.tungsten", home);
    mkdir(dir, 0755);
    snprintf(dir, sizeof(dir), "%s/.tungsten/cache", home);
    mkdir(dir, 0755);

    char path[512];
    snprintf(path, sizeof(path), "%s/.tungsten/cache/%s.memo", home, sha);

    FILE *f = fopen(path, "wb");
    if (!f) return;

    fwrite(MEMO_MAGIC, 1, 4, f);
    uint32_t version = MEMO_VERSION;
    uint32_t w_arity = (uint32_t)t->arity;
    uint32_t w_count = (uint32_t)t->count;
    fwrite(&version, 4, 1, f);
    fwrite(&w_arity, 4, 1, f);
    fwrite(&w_count, 4, 1, f);

    int a = t->arity > 0 ? t->arity : 1;
    for (int i = 0; i < t->cap; i++) {
        if (t->keys[i * a] != W_UNDEF) {
            fwrite(&t->keys[i * a], sizeof(WValue), t->arity, f);
            fwrite(&t->values[i], sizeof(WValue), 1, f);
        }
    }
    fclose(f);
}

/* ---- Memoized call wrappers ---- */

WValue __w_memo_call0_i64(void *table, WValue (*fn)(void)) {
    WValue args[1] = {0};
    WValue cached = w_memo_lookup(table, args, 0);
    if (cached != W_MEMO_MISS) return cached;
    WValue result = fn();
    w_memo_store(table, args, 0, result);
    return result;
}

WValue __w_memo_call1_i64(void *table, WValue (*fn)(WValue), WValue arg0) {
    if (((WMemoTable *)table)->disabled) return fn(arg0);
    WValue args[1] = {arg0};
    WValue cached = w_memo_lookup(table, args, 1);
    if (cached != W_MEMO_MISS) return cached;
    WValue result = fn(arg0);
    w_memo_store(table, args, 1, result);
    return result;
}

WValue __w_memo_call2_i64(void *table, WValue (*fn)(WValue, WValue), WValue arg0, WValue arg1) {
    if (((WMemoTable *)table)->disabled) return fn(arg0, arg1);
    WValue args[2] = {arg0, arg1};
    WValue cached = w_memo_lookup(table, args, 2);
    if (cached != W_MEMO_MISS) return cached;
    WValue result = fn(arg0, arg1);
    w_memo_store(table, args, 2, result);
    return result;
}

/* GC mark procedure removed — no longer using Boehm GC */
void w_gc_mark_roots(void) { /* no-op */ }

/* ---- Value inspector ---- */

WValue w_inspect_s(WValue v) {
    char buf[128];
    if (w_is_nil(v)) {
        snprintf(buf, sizeof(buf), "[0x%016llX] nil", (unsigned long long)v);
    } else if (w_is_false(v)) {
        snprintf(buf, sizeof(buf), "[0x%016llX] false", (unsigned long long)v);
    } else if (w_is_true(v)) {
        snprintf(buf, sizeof(buf), "[0x%016llX] true", (unsigned long long)v);
    } else if (w_is_int(v)) {
        snprintf(buf, sizeof(buf), "[0x%016llX] int(%lld)",
                 (unsigned long long)v, (long long)w_as_int(v));
    } else if (w_is_double(v)) {
        snprintf(buf, sizeof(buf), "[0x%016llX] double(%g)",
                 (unsigned long long)v, w_as_double(v));
    } else if (w_is_decimal(v)) {
        snprintf(buf, sizeof(buf), "[0x%016llX] decimal(sig=%lld, scale=%d)",
                 (unsigned long long)v,
                 (long long)((int64_t)((v >> 7) & 0x1FFFFFFFFFFULL) << 23 >> 23),
                 (int)((int8_t)((v & 0x7F) << 1) >> 1));
    } else if (w_is_char(v)) {
        uint32_t cp = w_char_codepoint(v);
        snprintf(buf, sizeof(buf), "[0x%016llX] char(U+%04X)",
                 (unsigned long long)v, cp);
    } else if (w_is_symbol(v)) {
        char sbuf[6];
        const char *s;
        size_t len;
        w_str_data(v, sbuf, &s, &len);
        snprintf(buf, sizeof(buf), "[0x%016llX] symbol(:%.*s)",
                 (unsigned long long)v,
                 (int)len, s);
    } else if (w_is_instant(v)) {
        snprintf(buf, sizeof(buf), "[0x%016llX] instant(%lld ms)",
                 (unsigned long long)v, (long long)w_unbox_instant(v));
    } else if (w_is_string(v)) {
        const char *s = as_str(v);
        snprintf(buf, sizeof(buf), "[0x%016llX] string(\"%.*s\")",
                 (unsigned long long)v, 40, s);
    } else if (w_is_array(v)) {
        snprintf(buf, sizeof(buf), "[0x%016llX] array(%p)",
                 (unsigned long long)v, (void *)w_as_array(v));
    } else if (w_is_obj(v)) {
        void *ptr = w_as_ptr(v);
        const char *kind = "generic";
        switch (w_subtag(v)) {
            case W_SUBTAG_HASH:    kind = "hash";    break;
            case W_SUBTAG_CLOSURE: kind = "closure"; break;
            case W_SUBTAG_INSTANCE:  kind = "instance";  break;
            case W_SUBTAG_CLASS:   kind = "class";   break;
        }
        snprintf(buf, sizeof(buf), "[0x%016llX] object(%s, ptr=%p)",
                 (unsigned long long)v, kind, ptr);
    } else {
        snprintf(buf, sizeof(buf), "[0x%016llX] unknown", (unsigned long long)v);
    }
    return w_string(buf);
}

void w_inspect(WValue v) {
    WValue s = w_inspect_s(v);
    fprintf(stderr, "%s\n", as_str(s));
}

/* ---- Parallel support (libdispatch / GCD) ---- */

void w_init_parallel(void) {
    /* No-op: GC removed */
}

void w_thread_register(void) {
    /* No-op: GC removed */
}

void w_thread_unregister(void) {
    /* No-op: GC removed */
}

/* ---- Thread primitives ---- */

static __thread WMutex *g_thread_held_mutexes = NULL;

/* pthread cancellation does not execute Tungsten ensure bodies. Native
 * threads therefore register every held Mutex here so their cleanup handler
 * can release ownership before the thread disappears. Mutexes are explicitly
 * non-poisoning; protected-state validation remains the caller's policy. */
static void w_mutex_release_owned_by_current_thread(void) {
    WMutex *mutex = g_thread_held_mutexes;
    g_thread_held_mutexes = NULL;
    while (mutex) {
        WMutex *next = mutex->held_next;
        pthread_mutex_lock(&mutex->guard);
        if (mutex->locked && !mutex->owner_is_goroutine &&
            pthread_equal(mutex->owner_thread, pthread_self())) {
            mutex->locked = 0;
            mutex->owner_goroutine = NULL;
        }
        mutex->held_next = NULL;
        pthread_mutex_unlock(&mutex->guard);
        mutex = next;
    }
}

static void w_thread_mark_stopped(void *arg) {
    WThread *t = (WThread *)arg;
    w_mutex_release_owned_by_current_thread();
    /*
     * Pooled BigInts and arithmetic arenas are already dead, but their
     * backing allocations are ordinary TLS pointers.  Return all bignum
     * buffers to the system when a language thread exits instead of retaining
     * them until process shutdown.
     */
    w_rt_release_thread_tls();
    t->alive = 0;
}

static void *thread_entry(void *arg) {
    WThread *t = (WThread *)arg;

    /* Each thread gets its own exception stack (__thread) */
    w_exception_stack = NULL;

    /* Call the closure.  Cancellation bypasses ordinary epilogues, so keep
     * alive? accurate with a cleanup handler as well as on normal return. */
    pthread_cleanup_push(w_thread_mark_stopped, t);
    WClosure *cl = (WClosure *)w_as_ptr(t->closure);
    typedef WValue (*fn0_t)(WValue *);
    t->result = ((fn0_t)cl->fn_ptr)(cl->captures);
    pthread_cleanup_pop(1);
    return NULL;
}

static int w_capture_entry_looks_like_slot(WValue entry) {
    if (entry == 0) return 0;
    /* Capture cells are WValue-sized (8-byte) allocas — 8-byte aligned, NOT
     * necessarily 16. The old `& 0xF` (16-byte) check silently misclassified
     * every 8-aligned cell as a value, so its slot was never dereferenced and
     * the closure captured the raw pointer bits. Apple stacks happen to 16-align
     * these allocas so it was hidden on macOS; Linux 8-aligns them, corrupting
     * half the captures (surfaced as garbage host/port in the goroutine client). */
    if ((entry & 0x7ULL) != 0) return 0;
    if (entry < 4096) return 0;

    /* NaN-boxed WValues (int/float/string/heap-object) have all 11 exponent bits
     * set — top 12 bits are 0x7FF or 0xFFF. A raw pointer to a capture cell has a
     * zero exponent (user-space addresses are < 2^48). This subsumes the old
     * 0xFFF9/0xFFFA/0x7FF8 tag list and also covers every other boxed tag. */
    uint16_t exp = (uint16_t)((entry >> 52) & 0xFFF);
    if (exp == 0x7FF || exp == 0xFFF) return 0;

    return 1;
}

static WValue w_thread_capture_snapshot(WValue closure, int captures_are_slots) {
    WClosure *src = (WClosure *)w_as_ptr(closure);
    WClosure *dst = calloc(1, sizeof(WClosure));
    dst->fn_ptr = src->fn_ptr;
    dst->capture_count = src->capture_count;
    dst->arity = src->arity;
    dst->param_count = src->param_count;

    if (src->capture_count > 0 && src->captures != NULL) {
        int count = src->capture_count;
        WValue *storage = calloc(1, sizeof(WValue) * (size_t)count * 2);
        WValue *caps = storage;
        WValue *cells = storage + count;

        for (int i = 0; i < count; i++) {
            WValue entry = src->captures[i];
            if (captures_are_slots || w_capture_entry_looks_like_slot(entry)) {
                WValue *slot = (WValue *)(uintptr_t)entry;
                cells[i] = *slot;
                caps[i] = (WValue)(uintptr_t)&cells[i];
            } else {
                caps[i] = entry;
                cells[i] = W_NIL;
            }
        }

        dst->captures = caps;
    } else {
        dst->captures = NULL;
    }

    return w_box_ptr(dst, W_SUBTAG_CLOSURE);
}

static void w_thread_release_snapshot(WThread *t) {
    if (t->closure == W_NIL || !w_is_closure(t->closure)) return;
    WClosure *cl = (WClosure *)w_as_ptr(t->closure);
    if (cl->capture_count > 0) free(cl->captures);
    free(cl);
    t->closure = W_NIL;
}

static WValue w_thread_spawn_impl(WValue closure, int captures_are_slots) {
    if (!w_is_closure(closure)) {
        w_raise(w_string("Thread.new requires a closure"));
    }

    /* Thread.new is the other entrance to true parallelism besides `go`.
     * Enable the slab/intern mutex before pthread_create can run user code;
     * otherwise concurrent controller threads can publish one role's interned
     * path bytes under another role's string slot.  Initialize on the parent
     * first as the slab's lazy mmap/mutex setup is itself single-threaded. */
    if (!g_string_slab.base) w_slab_init();
    g_slab_needs_lock = 1;

    WThread *t = calloc(1, sizeof(WThread));
    t->type = W_TYPE_THREAD;
    t->closure = w_thread_capture_snapshot(closure, captures_are_slots);
    t->alive = 1;
    t->cancel = 0;
    t->joined = 0;
    t->result = W_NIL;

    int err = pthread_create(&t->handle, NULL, thread_entry, t);
    if (err != 0) {
        w_thread_release_snapshot(t);
        free(t);
        w_raise(w_string("Thread.new: pthread_create failed (EAGAIN)"));
    }

    return w_box_ptr(t, W_SUBTAG_GENERIC);
}

WValue w_thread_spawn(WValue closure) {
    /* C callers historically provide either direct WValues or capture-cell
     * pointers, so retain the compatibility heuristic for this public API. */
    return w_thread_spawn_impl(closure, 0);
}

WValue w_thread_spawn_slots(WValue closure) {
    /* Compiler-emitted closures always store pointers to lexical capture
     * cells.  Avoid pointer/value guessing: raw i32/f32 cells may only be
     * 4-byte aligned, and generic-object WValues are themselves aligned
     * pointers.  The strict entry point snapshots every cell unambiguously. */
    return w_thread_spawn_impl(closure, 1);
}

WValue w_thread_join(WValue thread) {
    if (!w_is_thread(thread)) {
        w_raise(w_string("Thread.join requires a thread"));
    }
    WThread *t = (WThread *)w_as_ptr(thread);
    if (!t->joined) {
        pthread_join(t->handle, NULL);
        t->joined = 1;
        w_thread_release_snapshot(t);
    }
    return t->result;
}

WValue w_thread_join_release(WValue thread) {
    if (!w_is_thread(thread)) {
        w_raise(w_string("Thread.join_release requires a thread"));
    }
    WThread *t = (WThread *)w_as_ptr(thread);
    WValue result = w_thread_join(thread);
    free(t);
    return result;
}

WValue w_thread_join_timeout(WValue thread, int64_t ms) {
    if (!w_is_thread(thread)) {
        w_raise(w_string("Thread.join requires a thread"));
    }
    WThread *t = (WThread *)w_as_ptr(thread);

    /* Sleep requests are not elapsed time: scheduler delays may lengthen a
     * sleep, while EINTR may shorten it. Recheck the monotonic clock after
     * each wake and cap the last poll at the remaining timeout. */
    struct timespec started;
    clock_gettime(CLOCK_MONOTONIC, &started);
    int64_t interval = 1;  /* start with 1ms, back off */
    while (t->alive && ms > 0) {
        struct timespec now;
        clock_gettime(CLOCK_MONOTONIC, &now);
        int64_t elapsed_ns = (int64_t)(now.tv_sec - started.tv_sec) * 1000000000
                           + now.tv_nsec - started.tv_nsec;
        int64_t elapsed_ms = elapsed_ns / 1000000;
        if (elapsed_ms >= ms) break;
        int64_t remaining_ms = ms - elapsed_ms;
        int64_t sleep_ns = interval * 1000000;
        if (remaining_ms <= interval)
            sleep_ns = remaining_ms * 1000000 - elapsed_ns % 1000000;
        struct timespec ts = { .tv_sec = 0, .tv_nsec = sleep_ns };
        nanosleep(&ts, NULL);
        if (interval < 10) interval++;
    }

    if (t->alive) {
        return W_FALSE;  /* timed out, thread still running */
    }
    if (!t->joined) {
        pthread_join(t->handle, NULL);
        t->joined = 1;
        w_thread_release_snapshot(t);
    }
    return W_TRUE;
}

WValue w_thread_sleep_ms(int64_t ms) {
    struct timespec ts;
    ts.tv_sec = ms / 1000;
    ts.tv_nsec = (ms % 1000) * 1000000;
    nanosleep(&ts, NULL);
    return W_NIL;
}

/* Global sleep(duration = nil) from core/global.w. Seconds as Int, Float,
 * or Decimal; nil blocks forever (Ruby semantics). Returns the duration. */
WValue __w_sleep(WValue duration) {
    if (duration == W_NIL) {
        for (;;) pause();
    }
    double secs = cmp_numeric_double(duration);
    if (secs > 0) {
        struct timespec ts;
        ts.tv_sec = (time_t)secs;
        ts.tv_nsec = (long)((secs - (double)ts.tv_sec) * 1e9);
        if (ts.tv_nsec < 0) ts.tv_nsec = 0;
        if (ts.tv_nsec > 999999999L) ts.tv_nsec = 999999999L;
        nanosleep(&ts, NULL);
    }
    return duration;
}

/* Raw-i64 sleep used by native Tungsten coordinators that poll atomic file
 * mailboxes. Plain ccall forwards machine-integer arguments without boxing. */
WValue __w_sleep_ms(int64_t milliseconds) {
    int64_t ms = milliseconds;
    if (ms < 0) ms = 0;
    struct timespec ts;
    ts.tv_sec = ms / 1000;
    ts.tv_nsec = (ms % 1000) * 1000000;
    nanosleep(&ts, NULL);
    return W_NIL;
}

WValue w_thread_alive(WValue thread) {
    if (!w_is_thread(thread)) {
        w_raise(w_string("Thread.alive? requires a thread"));
    }
    WThread *t = (WThread *)w_as_ptr(thread);
    return t->alive ? W_TRUE : W_FALSE;
}

WValue w_thread_kill(WValue thread) {
    if (!w_is_thread(thread)) {
        w_raise(w_string("Thread.kill requires a thread"));
    }
    WThread *t = (WThread *)w_as_ptr(thread);
    t->cancel = 1;
    pthread_cancel(t->handle);
    return W_NIL;
}

/* ---- Signal handling ---- */

#define MAX_SIGNAL_HANDLERS 32
static WValue signal_closures[MAX_SIGNAL_HANDLERS];

static void signal_handler_trampoline(int signum) {
    if (signum >= 0 && signum < MAX_SIGNAL_HANDLERS && signal_closures[signum] != W_NIL) {
        WClosure *cl = (WClosure *)w_as_ptr(signal_closures[signum]);
        typedef WValue (*fn0_t)(WValue *);
        ((fn0_t)cl->fn_ptr)(cl->captures);
    }
}

/* Cooperative shutdown latch: a coordinator polls __w_interrupted() each
 * round instead of dying mid-write. First SIGINT/SIGTERM latches, the second
 * hard-exits (130) for a wedged loop. Async-signal-safe: the handler touches
 * only a sig_atomic_t and _exit(). */
static volatile sig_atomic_t w_interrupt_count = 0;

static void w_interrupt_latch(int signum) {
    (void)signum;
    w_interrupt_count++;
    if (w_interrupt_count >= 2) _exit(130);
}

WValue __w_trap_interrupts(void) {
    struct sigaction sa;
    memset(&sa, 0, sizeof(sa));
    sa.sa_handler = w_interrupt_latch;
    sigemptyset(&sa.sa_mask);
    sa.sa_flags = SA_RESTART;
    sigaction(SIGINT, &sa, NULL);
    sigaction(SIGTERM, &sa, NULL);
    return W_TRUE;
}

WValue __w_interrupted(void) {
    return w_int((int64_t)w_interrupt_count);
}

WValue w_signal_trap(int signum, WValue closure) {
    if (signum < 0 || signum >= MAX_SIGNAL_HANDLERS) {
        w_raise(w_string("Signal.trap: invalid signal number"));
    }
    signal_closures[signum] = closure;

    struct sigaction sa;
    memset(&sa, 0, sizeof(sa));
    sa.sa_handler = signal_handler_trampoline;
    sigemptyset(&sa.sa_mask);
    sa.sa_flags = SA_RESTART;
    sigaction(signum, &sa, NULL);

    return W_NIL;
}

/* ---- Atomic operations ---- */

static WAtomic *as_atomic(WValue v) {
    if (!w_is_atomic(v)) die("expected atomic");
    return (WAtomic *)w_as_ptr(v);
}

WValue w_atomic_new(WValue initial) {
    if (!w_is_integer_any(initial))
        w_raise(w_string("Atomic.new expects an Integer"));
    int64_t val = w_numeric_to_i64(initial);
    WAtomic *a = calloc(1, sizeof(WAtomic));
    /* type field gone — WAtomic now lives at W_SUBTAG_ATOMIC */
    atomic_store(&a->value, val);
    return w_box_ptr(a, W_SUBTAG_ATOMIC);
}

WValue w_atomic_get(WValue a) {
    return w_int(atomic_load(&as_atomic(a)->value));
}

WValue w_atomic_set(WValue a, WValue val) {
    if (!w_is_integer_any(val))
        w_raise(w_string("Atomic.store expects an Integer"));
    int64_t v = w_numeric_to_i64(val);
    atomic_store(&as_atomic(a)->value, v);
    return val;
}

WValue w_atomic_exchange(WValue a, WValue val) {
    if (!w_is_integer_any(val))
        w_raise(w_string("Atomic.exchange expects an Integer"));
    int64_t v = w_numeric_to_i64(val);
    return w_int(atomic_exchange(&as_atomic(a)->value, v));
}

WValue w_atomic_add(WValue a, WValue delta) {
    if (!w_is_integer_any(delta))
        w_raise(w_string("Atomic.fetch_add expects an Integer"));
    int64_t d = w_numeric_to_i64(delta);
    int64_t old = atomic_fetch_add(&as_atomic(a)->value, d);
    return w_int(old);
}

WValue w_atomic_fetch_sub(WValue a, WValue delta) {
    if (!w_is_integer_any(delta))
        w_raise(w_string("Atomic.fetch_sub expects an Integer"));
    int64_t d = w_numeric_to_i64(delta);
    int64_t old = atomic_fetch_sub(&as_atomic(a)->value, d);
    return w_int(old);
}

WValue w_atomic_add_raw(WValue a, int64_t delta) {
    atomic_fetch_add(&as_atomic(a)->value, delta);
    return W_NIL;
}

WValue w_atomic_cas(WValue a, WValue expected, WValue desired) {
    if (!w_is_integer_any(expected) || !w_is_integer_any(desired))
        w_raise(w_string("Atomic.compare_exchange expects Integer values"));
    int64_t exp = w_numeric_to_i64(expected);
    int64_t des = w_numeric_to_i64(desired);
    int ok = atomic_compare_exchange_strong(&as_atomic(a)->value, &exp, des);
    return ok ? W_TRUE : W_FALSE;
}

/* ---- Element-level atomics on typed i64 arrays ----------------------------
 * The publish protocol for cross-thread rings (seqlock): payload slots are
 * written plain, the sequence slot is store-RELEASED by the producer and
 * load-ACQUIRED by the consumer, so a consumer that observes the committed
 * sequence value is guaranteed to observe the payload writes that preceded
 * it. The ticket counter uses seq-cst fetch-add. int64_t slots are 8-aligned,
 * so the C11 atomic builtins apply directly. */

static inline _Atomic int64_t *w_i64_slot_atomic(WValue arr_val, WValue idx_val) {
    WArray *a = w_as_array(arr_val);
    int64_t idx = w_as_int(idx_val);
    return (_Atomic int64_t *)((int64_t *)a->slots + a->start + idx);
}

WValue __w_arr_load_acq(WValue arr_val, WValue idx_val) {
    return w_int(atomic_load_explicit(w_i64_slot_atomic(arr_val, idx_val),
                                      memory_order_acquire));
}

WValue __w_arr_store_rel(WValue arr_val, WValue idx_val, WValue v) {
    atomic_store_explicit(w_i64_slot_atomic(arr_val, idx_val), w_as_int(v),
                          memory_order_release);
    return W_NIL;
}

WValue __w_arr_fetch_add(WValue arr_val, WValue idx_val, WValue delta) {
    return w_int(atomic_fetch_add(w_i64_slot_atomic(arr_val, idx_val),
                                  w_as_int(delta)));
}

WValue __w_arr_compare_exchange(WValue arr_val, WValue idx_val,
                                WValue expected_val, WValue desired_val) {
    int64_t expected = w_as_int(expected_val);
    bool exchanged = atomic_compare_exchange_strong_explicit(
        w_i64_slot_atomic(arr_val, idx_val), &expected, w_as_int(desired_val),
        memory_order_acq_rel, memory_order_acquire);
    return w_int(exchanged ? 1 : 0);
}

/* Reserve one ticket without ever advancing the shared counter past `limit`.
 * Returns the new positive count to the winner, or zero when the budget is
 * already exhausted.  A fetch-add followed by rollback is not equivalent:
 * several racing workers can all observe/temporarily publish values above the
 * cap, and the solver must decide whether to analyze a conflict before doing
 * any such speculative increment. */
WValue __w_arr_try_inc_below(WValue arr_val, WValue idx_val,
                             WValue limit_val) {
    _Atomic int64_t *slot = w_i64_slot_atomic(arr_val, idx_val);
    int64_t limit = w_as_int(limit_val);
    int64_t current = atomic_load_explicit(slot, memory_order_acquire);

    while (current < limit) {
        int64_t next = current + 1;
        if (atomic_compare_exchange_weak_explicit(
                slot, &current, next,
                memory_order_acq_rel, memory_order_acquire))
            return w_int(next);
        /* On failure C11 writes the newly observed value into `current`. */
    }
    return w_int(0);
}

WValue w_atomic_increment(WValue a) {
    int64_t old = atomic_fetch_add(&as_atomic(a)->value, 1);
    return w_int((int64_t)((uint64_t)old + UINT64_C(1)));
}

WValue w_atomic_decrement(WValue a) {
    int64_t old = atomic_fetch_sub(&as_atomic(a)->value, 1);
    return w_int((int64_t)((uint64_t)old - UINT64_C(1)));
}

/* ---- TCP Sockets ---- */

/* Forward declarations for goroutine parking (definitions in the goroutine scheduler section below) */
extern __thread WGoroutine *g_current;
extern __thread WContext g_scheduler_ctx;
extern __thread WProcessor *p_current;
#ifdef W_CONTEXT_UCONTEXT
#define w_ctx_swap(save, restore) swapcontext((save), (restore))
#else
void w_ctx_swap(WContext *save, WContext *restore);
#endif
static __thread WEventLoop *g_coop_event_loop = NULL;  /* cooperative scheduler's event loop (per-thread) */

/* M:P still permits cross-worker expiry while a wait's owning processor is
 * busy. Cooperative waits use only their event loop's indexed frontier. */
static pthread_mutex_t g_wait_deadline_lock = PTHREAD_MUTEX_INITIALIZER;
static WGoroutine *g_wait_deadline_head = NULL;

/* Deterministic scheduler tests can stop at publication boundaries. Normal
 * builds emit no hook or branch. 1 = wake claimed, 2 = just before park swap. */
#ifndef W_SCHEDULER_TEST_HOOK
#define W_SCHEDULER_TEST_HOOK(point, g) ((void)0)
#endif

static int w_deadline_expired(int64_t deadline_ticks) {
    return deadline_ticks > 0 && __w_clock_ticks_raw() >= deadline_ticks;
}

static int w_deadline_timeout_ms(int64_t deadline_ticks, int default_ms) {
    if (deadline_ticks <= 0) return default_ms;

    int64_t now = __w_clock_ticks_raw();
    if (now >= deadline_ticks) return 0;

#ifdef __APPLE__
    static __thread mach_timebase_info_data_t tb;
    if (tb.denom == 0) mach_timebase_info(&tb);
    uint64_t delta_ticks = (uint64_t)(deadline_ticks - now);
    uint64_t ns = delta_ticks / (uint64_t)tb.denom * (uint64_t)tb.numer;
    ns += (delta_ticks % (uint64_t)tb.denom) * (uint64_t)tb.numer / (uint64_t)tb.denom;
#else
    uint64_t ns = (uint64_t)(deadline_ticks - now);
#endif

    uint64_t ms = (ns + 999999ULL) / 1000000ULL;
    if (ms > (uint64_t)INT_MAX) return INT_MAX;
    return (int)ms;
}

/* Absolute deadline (monotonic ticks) `ms` milliseconds from now. */
static int64_t w_deadline_ticks_after_ms(int64_t ms) {
#ifdef __APPLE__
    static __thread mach_timebase_info_data_t tb;
    if (tb.denom == 0) mach_timebase_info(&tb);
    uint64_t ticks_per_ms = (1000000ULL * (uint64_t)tb.denom) / (uint64_t)tb.numer;
    return __w_clock_ticks_raw() + ms * (int64_t)ticks_per_ms;
#else
    return __w_clock_ticks_raw() + ms * 1000000LL;
#endif
}

int w_event_deadline_queue_init(WEventDeadlineQueue *q) {
    memset(q, 0, sizeof(*q));
    return pthread_mutex_init(&q->lock, NULL);
}

void w_event_deadline_queue_destroy(WEventDeadlineQueue *q) {
    /* Poller/producers have stopped; waiting goroutines are still alive. */
    for (size_t i = 0; i < q->count; i++) {
        q->heap[i]->deadline_linked = 0;
        q->heap[i]->deadline_index = 0;
        q->heap[i]->wait_loop = NULL;
        q->heap[i]->deadline_kind = 0;
    }
    free(q->heap);
    pthread_mutex_destroy(&q->lock);
}

static void event_deadline_up(WEventDeadlineQueue *q, size_t i) {
    WGoroutine *g = q->heap[i];
    while (i > 0) {
        size_t parent = (i - 1) / 2;
        if (q->heap[parent]->wait_deadline_ticks <= g->wait_deadline_ticks) break;
        q->heap[i] = q->heap[parent];
        q->heap[i]->deadline_index = i;
        i = parent;
    }
    q->heap[i] = g;
    g->deadline_index = i;
}

static void event_deadline_down(WEventDeadlineQueue *q, size_t i) {
    WGoroutine *g = q->heap[i];
    while (i < q->count / 2) {
        size_t child = 2 * i + 1;
        if (child + 1 < q->count &&
            q->heap[child + 1]->wait_deadline_ticks < q->heap[child]->wait_deadline_ticks)
            child++;
        if (g->wait_deadline_ticks <= q->heap[child]->wait_deadline_ticks) break;
        q->heap[i] = q->heap[child];
        q->heap[i]->deadline_index = i;
        i = child;
    }
    q->heap[i] = g;
    g->deadline_index = i;
}

static void event_deadline_remove(WEventDeadlineQueue *q, WGoroutine *g) {
    size_t i = g->deadline_index;
    WGoroutine *tail = q->heap[--q->count];
    if (i < q->count) {
        q->heap[i] = tail;
        tail->deadline_index = i;
        if (i > 0 && tail->wait_deadline_ticks < q->heap[(i - 1) / 2]->wait_deadline_ticks)
            event_deadline_up(q, i);
        else
            event_deadline_down(q, i);
    }
    g->deadline_linked = 0;
    g->deadline_index = 0;
}

int w_event_deadline_set(WEventLoop *el, WGoroutine *g, int64_t ticks) {
    if (!el || !g || ticks <= 0) { errno = EINVAL; return -1; }
    WEventDeadlineQueue *q = w_event_deadline_queue(el);
    pthread_mutex_lock(&q->lock);
    if (g->deadline_linked && (g->deadline_linked != 1 || g->wait_loop != el)) {
        pthread_mutex_unlock(&q->lock);
        errno = EINVAL;
        return -1;
    }
    int64_t old_first = q->count ? q->heap[0]->wait_deadline_ticks : 0;
    if (!g->deadline_linked) {
        if (q->count == q->capacity) {
            size_t cap = q->capacity ? q->capacity * 2 : 16;
            if (cap < q->capacity || cap > SIZE_MAX / sizeof(*q->heap)) {
                pthread_mutex_unlock(&q->lock);
                errno = ENOMEM;
                return -1;
            }
            WGoroutine **heap = realloc(q->heap, cap * sizeof(*heap));
            if (!heap) { pthread_mutex_unlock(&q->lock); return -1; }
            q->heap = heap;
            q->capacity = cap;
        }
        g->wait_loop = el;
        g->deadline_kind = 1;
        g->wait_deadline_ticks = ticks;
        g->deadline_linked = 1;
        g->deadline_index = q->count;
        q->heap[q->count++] = g;
        event_deadline_up(q, g->deadline_index);
    } else {
        int64_t old = g->wait_deadline_ticks;
        g->wait_deadline_ticks = ticks;
        if (ticks < old) event_deadline_up(q, g->deadline_index);
        else if (ticks > old) event_deadline_down(q, g->deadline_index);
    }
    int wake = q->polling && old_first != q->heap[0]->wait_deadline_ticks;
    pthread_mutex_unlock(&q->lock);
    if (wake && w_event_wake(el) < 0) die("event loop deadline wake failed");
    return 0;
}

int w_event_deadline_cancel(WEventLoop *el, WGoroutine *g) {
    if (!el || !g) return 0;
    WEventDeadlineQueue *q = w_event_deadline_queue(el);
    pthread_mutex_lock(&q->lock);
    int found = g->deadline_linked == 1 && g->wait_loop == el;
    int wake = found && g->deadline_index == 0 && q->polling;
    if (found) event_deadline_remove(q, g);
    pthread_mutex_unlock(&q->lock);
    if (wake && w_event_wake(el) < 0) die("event loop deadline wake failed");
    return found;
}

int64_t w_event_deadline_next(WEventLoop *el) {
    WEventDeadlineQueue *q = w_event_deadline_queue(el);
    pthread_mutex_lock(&q->lock);
    int64_t next = q->count ? q->heap[0]->wait_deadline_ticks : 0;
    pthread_mutex_unlock(&q->lock);
    return next;
}

WGoroutine *w_event_deadline_pop(WEventLoop *el, int64_t now) {
    WEventDeadlineQueue *q = w_event_deadline_queue(el);
    pthread_mutex_lock(&q->lock);
    WGoroutine *g = q->count ? q->heap[0] : NULL;
    if (g && g->wait_deadline_ticks <= now) event_deadline_remove(q, g);
    else g = NULL;
    pthread_mutex_unlock(&q->lock);
    return g;
}

int w_event_deadline_prepare_poll(WEventLoop *el, int timeout_ms, int64_t *deadline_out) {
    if (deadline_out) *deadline_out = 0;
    if (timeout_ms == 0) return 0;
    WEventDeadlineQueue *q = w_event_deadline_queue(el);
    pthread_mutex_lock(&q->lock);
    /* Arm before taking the snapshot: a concurrent earlier insertion either
     * appears in this snapshot or triggers a persistent kernel wake event. */
    q->polling = 1;
    int64_t next = q->count ? q->heap[0]->wait_deadline_ticks : 0;
    pthread_mutex_unlock(&q->lock);
    /* A high-resolution backend applies this one captured deadline directly;
     * do not read the clock and round it to milliseconds only to undo that. */
    if (deadline_out) {
        *deadline_out = next;
        return timeout_ms;
    }
    if (next) {
        int deadline_ms = w_deadline_timeout_ms(next, -1);
        if (timeout_ms < 0 || deadline_ms < timeout_ms) timeout_ms = deadline_ms;
    }
    return timeout_ms;
}

void w_event_deadline_finish_poll(WEventLoop *el, int timeout_ms) {
    if (timeout_ms == 0) return;
    WEventDeadlineQueue *q = w_event_deadline_queue(el);
    pthread_mutex_lock(&q->lock);
    q->polling = 0;
    pthread_mutex_unlock(&q->lock);
}

/* Park deadline (0 = none) for one Socket#read on `s`: the read timeout from
 * Socket#set_timeout, measured from now. Shared with the TLS read and
 * handshake paths (tls.c) so a TLS socket honours the same deadline as a
 * plain one. */
int64_t w_socket_read_deadline_ticks(WSocket *s) {
    if (s->read_timeout_ms <= 0) return 0;
    return w_deadline_ticks_after_ms(s->read_timeout_ms);
}

static void g_deadline_add(WGoroutine *g) {
    if (g->wait_deadline_ticks <= 0) return;
    if (!p_current) {
        if (w_event_deadline_set(g->wait_loop, g, g->wait_deadline_ticks) < 0) {
            atomic_store_explicit(&g->state, G_RUNNING, memory_order_relaxed);
            w_raise(w_string("event deadline allocation failed"));
        }
        return;
    }
    g->deadline_kind = 2;
    pthread_mutex_lock(&g_wait_deadline_lock);
    if (!g->deadline_linked) {
        g->next = NULL;
        g->deadline_next = g_wait_deadline_head;
        if (g_wait_deadline_head) g_wait_deadline_head->next = g;
        g_wait_deadline_head = g;
        g->deadline_linked = 2;
    }
    pthread_mutex_unlock(&g_wait_deadline_lock);
}

/* Queue membership and deadline membership are mutually exclusive. During
 * a wait, next is the predecessor, not a runnable-queue link. Caller holds
 * g_wait_deadline_lock, and detaches before any runnable publication. */
static void g_deadline_remove_locked(WGoroutine *g) {
    if (g->deadline_linked != 2) die("invalid M:P deadline membership");
    if (g->next) g->next->deadline_next = g->deadline_next;
    else g_wait_deadline_head = g->deadline_next;
    if (g->deadline_next) g->deadline_next->next = g->next;
    g->next = NULL;
    g->deadline_next = NULL;
    g->deadline_linked = 0;
}

/* The wait's domain remains stable after removal. Always acquire its lock:
 * an expiry worker may have detached this entry but still be claiming it.
 * No readiness waker may publish RUNNABLE until that reader has finished. */
static void g_deadline_cancel(WGoroutine *g) {
    if (g->wait_deadline_ticks <= 0) return;
    if (g->deadline_kind == 1) {
        w_event_deadline_cancel(g->wait_loop, g);
        return;
    }
    if (g->deadline_kind != 2) die("invalid wait deadline domain");
    pthread_mutex_lock(&g_wait_deadline_lock);
    if (g->deadline_linked) g_deadline_remove_locked(g);
    pthread_mutex_unlock(&g_wait_deadline_lock);
}

static void g_finish_wait(WGoroutine *g, int deadline_locked) {
    if (!deadline_locked) g_deadline_cancel(g);
    if (g->wait_timed_out && g->wait_loop && g->wait_fd >= 0)
        w_event_unregister(g->wait_loop, g->wait_fd);
    atomic_store_explicit(&g->state, G_RUNNABLE, memory_order_release);
}

/* Return 1 only when this waker owns enqueueing. An early wake never makes a
 * still-running stack available: it records NOTIFIED, or takes over enqueueing
 * if the scheduler concurrently acknowledges the completed context save. */
static int g_try_wake_waiting_impl(WGoroutine *g, int timed_out, int deadline_locked) {
    if (!g) return 0;
    GState state = atomic_load_explicit(&g->state, memory_order_acquire);
    for (;;) {
        if (state != G_WAITING && state != G_PARKING) return 0;
        GState claimed = state == G_WAITING ? G_WAKING_PARKED : G_WAKING;
        if (atomic_compare_exchange_weak_explicit(&g->state, &state, claimed,
                memory_order_acq_rel, memory_order_acquire)) {
            W_SCHEDULER_TEST_HOOK(1, g);
            g->wait_timed_out = timed_out;
            if (claimed == G_WAKING) {
                GState expected = G_WAKING;
                if (atomic_compare_exchange_strong_explicit(&g->state, &expected, G_NOTIFIED,
                        memory_order_acq_rel, memory_order_acquire)) return 0;
                if (expected != G_WAKING_PARKED) die("invalid early goroutine wake state");
            }
            g_finish_wait(g, deadline_locked);
            return 1;
        }
    }
}

static int g_try_wake_waiting(WGoroutine *g, int timed_out) {
    return g_try_wake_waiting_impl(g, timed_out, 0);
}

/* Called only after w_ctx_swap has saved this goroutine's complete context.
 * Neither this function nor its caller may inspect g after publishing WAITING
 * or WAKING_PARKED: a different worker can then wake and run it immediately. */
static int g_commit_park(WGoroutine *g) {
    GState state = atomic_load_explicit(&g->state, memory_order_acquire);
    for (;;) {
        if (state == G_PARKING) {
            if (atomic_compare_exchange_weak_explicit(&g->state, &state, G_WAITING,
                    memory_order_acq_rel, memory_order_acquire)) return 0;
        } else if (state == G_WAKING) {
            if (atomic_compare_exchange_weak_explicit(&g->state, &state, G_WAKING_PARKED,
                    memory_order_acq_rel, memory_order_acquire)) return 0;
        } else if (state == G_NOTIFIED) {
            g_finish_wait(g, 0);
            return 1;
        } else {
            die("invalid goroutine park commit state");
        }
    }
}

static int g_wake_expired_deadlines(WEventLoop *loop, WGoroutine **out, int max_out) {
    if (max_out <= 0) return 0;

    int count = 0;
    int64_t now = __w_clock_ticks_raw();
    if (loop) {
        WEventDeadlineQueue *q = w_event_deadline_queue(loop);
        pthread_mutex_lock(&q->lock);
        while (q->count && count < max_out) {
            WGoroutine *g = q->heap[0];
            if (g->wait_deadline_ticks > now) break;
            event_deadline_remove(q, g);
            /* Keep removal and the winning wake claim in one lifetime
             * boundary. Readiness cleanup takes this same domain lock. */
            if (g_try_wake_waiting_impl(g, 1, 1)) out[count++] = g;
        }
        pthread_mutex_unlock(&q->lock);
        return count;
    }
    pthread_mutex_lock(&g_wait_deadline_lock);

    WGoroutine **link = &g_wait_deadline_head;
    while (*link && count < max_out) {
        WGoroutine *g = *link;
        GState state = atomic_load_explicit(&g->state, memory_order_acquire);
        int waiting = state == G_WAITING || state == G_PARKING;
        int expired_here = now >= g->wait_deadline_ticks;
        if (!waiting || g->wait_deadline_ticks <= 0 || expired_here) {
            g_deadline_remove_locked(g);
            if (waiting && g->wait_deadline_ticks > 0 && expired_here) {
                if (g_try_wake_waiting_impl(g, 1, 1)) out[count++] = g;
            }
        } else {
            link = &g->deadline_next;
        }
    }

    pthread_mutex_unlock(&g_wait_deadline_lock);
    return count;
}

/* Frontier probe for diagnostics (NULL means the M:P compatibility list).
 * Production cooperative blocking polls arm and snapshot in the backend. */
static int g_next_deadline_timeout_ms(WEventLoop *loop) {
    if (loop) return w_deadline_timeout_ms(w_event_deadline_next(loop), -1);
    int64_t nearest = 0;
    pthread_mutex_lock(&g_wait_deadline_lock);
    for (WGoroutine *g = g_wait_deadline_head; g; g = g->deadline_next) {
        GState state = atomic_load_explicit(&g->state, memory_order_acquire);
        if ((state != G_WAITING && state != G_PARKING) || g->wait_deadline_ticks <= 0) continue;
        if (nearest == 0 || g->wait_deadline_ticks < nearest) {
            nearest = g->wait_deadline_ticks;
        }
    }
    pthread_mutex_unlock(&g_wait_deadline_lock);

    if (nearest == 0) return -1;
    return w_deadline_timeout_ms(nearest, -1);
}

/* Park the current goroutine on an fd until events are ready.
 * If not running inside a goroutine, falls back to poll(2). */
/* Keep the TLS lookup inside each invocation: a suspended G may resume on
 * another worker, so callers must not hoist TLS addresses across park calls. */
__attribute__((noinline))
int w_socket_park_until(int fd, int events, int64_t deadline_ticks) {
    if (w_deadline_expired(deadline_ticks)) return 0;

    WGoroutine *g = g_current;
    if (g) {
        WEventLoop *el = NULL;
        if (p_current && p_current->event_loop) {
            el = p_current->event_loop;
        } else if (g_coop_event_loop) {
            el = g_coop_event_loop;
        }

        if (!el) {
            struct pollfd pfd;
            pfd.fd = fd;
            pfd.events = 0;
            if (events & W_EVENT_READ)  pfd.events |= POLLIN;
            if (events & W_EVENT_WRITE) pfd.events |= POLLOUT;
            int timeout_ms = w_deadline_timeout_ms(deadline_ticks, 100);
            return poll(&pfd, 1, timeout_ms) > 0;
        }

        /* Running inside a goroutine — park on the event loop */
        g->wait_fd = fd;
        g->wait_events = events;
        g->wait_timed_out = 0;
        g->wait_deadline_ticks = deadline_ticks;
        g->wait_loop = el;
        atomic_store_explicit(&g->state, G_PARKING, memory_order_release);

        g_deadline_add(g);
        w_event_register(el, fd, events, g);

        /* Swap back to scheduler — we'll be re-enqueued when fd is ready */
        W_SCHEDULER_TEST_HOOK(2, g);
        w_ctx_swap(&g->ctx, &g_scheduler_ctx);

        int timed_out = g->wait_timed_out;

        /* Resumed — clear wait state */
        g->wait_fd = -1;
        g->wait_events = 0;
        g->wait_loop = NULL;
        g->wait_deadline_ticks = 0;
        return !timed_out;
    }

    /* Main thread / no goroutine: blocking poll fallback */
    struct pollfd pfd;
    pfd.fd = fd;
    pfd.events = 0;
    if (events & W_EVENT_READ)  pfd.events |= POLLIN;
    if (events & W_EVENT_WRITE) pfd.events |= POLLOUT;
    int timeout_ms = w_deadline_timeout_ms(deadline_ticks, 100);
    return poll(&pfd, 1, timeout_ms) > 0;
}

void w_socket_park(int fd, int events) {
    (void)w_socket_park_until(fd, events, 0);
}

/* Park goroutine for an io_uring completion (SQE already submitted).
 * On resume, result is in g->io_result and buffer ID in g->io_buf_id. */
static void w_socket_park_uring(void) {
    WGoroutine *g = g_current;
    atomic_store_explicit(&g->state, G_PARKING, memory_order_release);
    w_ctx_swap(&g->ctx, &g_scheduler_ctx);
}

static WSocket *as_socket(WValue v) {
    if (!w_is_socket(v)) die("expected socket");
    return (WSocket *)w_as_ptr(v);
}

static int w_fd_set_nonblocking(int fd) {
    int flags = fcntl(fd, F_GETFL, 0);
    if (flags >= 0) {
        if ((flags & O_NONBLOCK) != 0) return 0;
        if (fcntl(fd, F_SETFL, flags | O_NONBLOCK) == 0) return 0;
    }

#ifdef FIONBIO
    int one = 1;
    return ioctl(fd, FIONBIO, &one);
#else
    return -1;
#endif
}

WValue w_socket_tcp_listen(const char *host, int port, int backlog) {
    w_sandbox_gate("socket_listen", host);
    /* A server must never be killed by a client hanging up. SO_NOSIGPIPE on
     * the accepted fd covers Darwin/BSD; it does not exist on Linux, where
     * write(2) has no MSG_NOSIGNAL equivalent, so a process that listens also
     * ignores SIGPIPE outright. w_socket_write already treats EPIPE as a short
     * write, which is what callers then see. */
    signal(SIGPIPE, SIG_IGN);
    int fd = socket(AF_INET, SOCK_STREAM, 0);
    if (fd < 0) {
        w_raise(w_string("socket: creation failed"));
    }

    /* SO_REUSEADDR to avoid "address already in use" */
    int opt = 1;
    setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt));
#ifdef SO_REUSEPORT
    setsockopt(fd, SOL_SOCKET, SO_REUSEPORT, &opt, sizeof(opt));
#endif

    /* TCP Fast Open: allow data in SYN-ACK, saves a round trip for returning clients */
#ifdef TCP_FASTOPEN
    int tfo = 5; /* queue length for TFO pending connections */
    setsockopt(fd, IPPROTO_TCP, TCP_FASTOPEN, &tfo, sizeof(tfo));
#endif

    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_port = htons(port);
    if (host == NULL || strcmp(host, "0.0.0.0") == 0) {
        addr.sin_addr.s_addr = INADDR_ANY;
    } else {
        inet_pton(AF_INET, host, &addr.sin_addr);
    }

    if (bind(fd, (struct sockaddr *)&addr, sizeof(addr)) < 0) {
        close(fd);
        w_raise(w_string("socket: bind failed"));
    }

    if (listen(fd, backlog) < 0) {
        close(fd);
        w_raise(w_string("socket: listen failed"));
    }

    /* Set non-blocking for event-loop-driven accept */
    if (w_fd_set_nonblocking(fd) < 0) {
        close(fd);
        w_raise(w_string("socket: listen nonblocking failed"));
    }

    WSocket *s = calloc(1, sizeof(WSocket));
    s->type = W_TYPE_SOCKET;
    s->fd = fd;
    s->listening = 1;
    s->closed = 0;
    s->ssl = NULL;
    return w_box_ptr(s, W_SUBTAG_SOCKET);
}

WValue w_socket_accept(WValue listener) {
    w_sandbox_gate("socket_accept", "");
    WSocket *ls = as_socket(listener);
    if (!ls->listening) {
        w_raise(w_string("socket: accept on non-listening socket"));
    }

    while (1) {
        struct sockaddr_in client_addr;
        socklen_t addr_len = sizeof(client_addr);
        int fd = accept(ls->fd, (struct sockaddr *)&client_addr, &addr_len);

        if (fd >= 0) {
            /* Set accepted connection to non-blocking + TCP_NODELAY */
            if (w_fd_set_nonblocking(fd) < 0) {
                close(fd);
                w_raise(w_string("socket: accept nonblocking failed"));
            }
            int nodelay = 1;
            setsockopt(fd, IPPROTO_TCP, TCP_NODELAY, &nodelay, sizeof(nodelay));
            /* Writing to a peer that has hung up must return EPIPE, not kill
             * the process with SIGPIPE. w_socket_connect already sets this on
             * outbound sockets; without it here, any hand-rolled accept loop
             * (Socket.listen/accept/write — the only way to stream a response,
             * since serve_http hands handlers just the path) dies the first
             * time a client disconnects mid-response. serve_http's own path
             * papered over this with a process-wide signal(SIGPIPE, SIG_IGN)
             * that a plain accept loop never reaches. */
#ifdef SO_NOSIGPIPE
            setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &nodelay, sizeof(nodelay));
#endif

            WSocket *conn = calloc(1, sizeof(WSocket));
            conn->type = W_TYPE_SOCKET;
            conn->fd = fd;
            conn->listening = 0;
            conn->closed = 0;
            conn->ssl = NULL;
            return w_box_ptr(conn, W_SUBTAG_SOCKET);
        }

        if (errno == EINTR) continue;
        if (errno == EAGAIN || errno == EWOULDBLOCK) {
            /* Non-blocking: park goroutine until readable */
            w_socket_park(ls->fd, W_EVENT_READ);
            continue;
        }
        if (errno == EMFILE || errno == ENFILE) {
            w_raise(w_string("socket: accept failed (too many open files)"));
        }
        w_raise(w_string("socket: accept failed"));
    }
}

/* TLS-aware read/write helpers (defined in tls.c when TUNGSTEN_TLS is set) */
#ifdef TUNGSTEN_TLS
extern ssize_t w_tls_read(WSocket *s, char *buf, size_t len);
extern ssize_t w_tls_write(WSocket *s, const char *buf, size_t len);
#endif

/* Socket reads reserve a large owned WString before the kernel tells us the
 * actual byte count. Preserve the global String representation invariant at
 * that boundary: a short read belongs entirely in the WValue, not in the
 * oversized buffer we happened to reserve for it. */
static inline WValue w_socket_read_string(WString *ws, size_t bytes) {
    w_heap_string_set_meta(ws, (uint32_t)bytes,
                           w_bytes_ascii_p((const uint8_t *)ws->data, bytes));
    ws->data[bytes] = '\0';
    if (bytes <= 5) {
        WValue value = w_box_inline_str(ws->data, bytes);
        free(ws);
        return value;
    }
    return w_box_heap_str(ws);
}

WValue w_socket_read(WValue sock, WValue buf_size) {
    WSocket *s = as_socket(sock);
    if (s->closed) return W_NIL;

    int64_t n = w_as_int(buf_size);
    if (n <= 0) n = 4096;
    if ((uint64_t)n > W_STRING_LEN_MASK)
        die("socket read buffer exceeds 31-bit string byte length limit");

    /* Read deadline (Socket#set_timeout): computed once per read call.
     * 0 = no deadline (park indefinitely, as before). */
    int64_t deadline_ticks = w_socket_read_deadline_ticks(s);

    WString *ws = malloc(sizeof(WString) + (size_t)n + 1);

#ifdef TUNGSTEN_TLS
    if (s->ssl) {
        ssize_t bytes = w_tls_read(s, ws->data, n);
        if (bytes > 0) {
            return w_socket_read_string(ws, (size_t)bytes);
        }
        free(ws);
        return W_NIL;
    }
#endif

    while (1) {
        ssize_t bytes = read(s->fd, ws->data, n);

        if (bytes > 0) {
            return w_socket_read_string(ws, (size_t)bytes);
        }
        if (bytes == 0) {
            free(ws);
            return W_NIL;  /* EOF / connection closed */
        }

        /* bytes < 0 */
        if (errno == EINTR) continue;
        if (errno == EAGAIN || errno == EWOULDBLOCK) {
            if (!w_socket_park_until(s->fd, W_EVENT_READ, deadline_ticks)) {
                free(ws);
                return W_NIL;  /* read deadline expired (set_timeout) */
            }
            continue;
        }
        if (errno == ECONNRESET) {
            free(ws);
            return W_NIL;
        }
        free(ws);
        w_raise(w_string("socket: read failed"));
    }
}

int64_t w_socket_read_ptr(WValue sock, int64_t data_ptr, int64_t len) {
    WSocket *s = as_socket(sock);
    if (s->closed) return 0;

    if (len <= 0) return 0;
    char *buf = (char *)(uintptr_t)data_ptr;

#ifdef TUNGSTEN_TLS
    if (s->ssl) {
        ssize_t bytes = w_tls_read(s, buf, (size_t)len);
        return bytes > 0 ? (int64_t)bytes : 0;
    }
#endif

    while (1) {
        ssize_t bytes = read(s->fd, buf, (size_t)len);

        if (bytes > 0) return (int64_t)bytes;
        if (bytes == 0) return 0;  /* EOF / connection closed */

        if (errno == EINTR) continue;
        if (errno == EAGAIN || errno == EWOULDBLOCK) {
            w_socket_park(s->fd, W_EVENT_READ);
            continue;
        }
        if (errno == ECONNRESET) return 0;
        w_raise(w_string("socket: read failed"));
    }
}

WValue w_socket_write(WValue sock, WValue data) {
    WSocket *s = as_socket(sock);
    if (s->closed) {
        w_raise(w_string("socket: write to closed socket"));
    }

    const char *str = as_str(data);
    size_t total = strlen(str);
    size_t written = 0;

#ifdef TUNGSTEN_TLS
    if (s->ssl) {
        while (written < total) {
            ssize_t n = w_tls_write(s, str + written, total - written);
            if (n > 0) { written += n; continue; }
            if (n <= 0) return w_box_int(written);
        }
        return w_box_int(written);
    }
#endif

    while (written < total) {
        ssize_t n = write(s->fd, str + written, total - written);

        if (n > 0) {
            written += n;
            continue;
        }
        if (n < 0) {
            if (errno == EINTR) continue;
            if (errno == EAGAIN || errno == EWOULDBLOCK) {
                w_socket_park(s->fd, W_EVENT_WRITE);
                continue;
            }
            if (errno == EPIPE || errno == ECONNRESET) {
                return w_box_int(written);
            }
            w_raise(w_string("socket: write failed"));
        }
    }
    return w_box_int(written);
}

WValue w_socket_write_ptr(WValue sock, int64_t data_ptr, int64_t len) {
    WSocket *s = as_socket(sock);
    if (s->closed) {
        w_raise(w_string("socket: write to closed socket"));
    }

    const char *str = (const char *)(uintptr_t)data_ptr;
    size_t total = (size_t)len;
    size_t written = 0;

#ifdef TUNGSTEN_TLS
    if (s->ssl) {
        while (written < total) {
            ssize_t n = w_tls_write(s, str + written, total - written);
            if (n > 0) { written += n; continue; }
            if (n <= 0) return w_box_int(written);
        }
        return w_box_int(written);
    }
#endif

    while (written < total) {
        ssize_t n = write(s->fd, str + written, total - written);

        if (n > 0) {
            written += n;
            continue;
        }
        if (n < 0) {
            if (errno == EINTR) continue;
            if (errno == EAGAIN || errno == EWOULDBLOCK) {
                w_socket_park(s->fd, W_EVENT_WRITE);
                continue;
            }
            if (errno == EPIPE || errno == ECONNRESET) {
                return w_box_int(written);
            }
            w_raise(w_string("socket: write failed"));
        }
    }
    return w_box_int(written);
}

WValue w_socket_set_timeout(WValue sock, int64_t ms) {
    WSocket *s = as_socket(sock);
    struct timeval tv;
    tv.tv_sec = ms / 1000;
    tv.tv_usec = (ms % 1000) * 1000;
    setsockopt(s->fd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));
    setsockopt(s->fd, SOL_SOCKET, SO_SNDTIMEO, &tv, sizeof(tv));
    /* SO_RCVTIMEO never fires on a non-blocking fd (runtime sockets are all
     * non-blocking), so also record the timeout as a park deadline:
     * w_socket_read parks with it and returns nil when it expires. */
    s->read_timeout_ms = ms > 0 ? ms : 0;
    return W_NIL;
}

WValue w_socket_shutdown(WValue sock, int how) {
    WSocket *s = as_socket(sock);
    shutdown(s->fd, how);
    return W_NIL;
}

WValue w_socket_close(WValue sock) {
    WSocket *s = as_socket(sock);
    if (!s->closed) {
        w_tls_socket_cleanup(s);
        close(s->fd);
        s->closed = 1;
    }
    return W_NIL;
}

int64_t w_raw_malloc(int64_t size) {
    if (size <= 0) size = 1;
    void *ptr = malloc((size_t)size);
    if (!ptr) w_raise(w_string("raw malloc failed"));
    return (int64_t)(uintptr_t)ptr;
}

int64_t w_raw_free(int64_t ptr) {
    free((void *)(uintptr_t)ptr);
    return 0;
}

int64_t w_raw_memmove(int64_t dst, int64_t src, int64_t len) {
    if (len > 0) {
        memmove((void *)(uintptr_t)dst, (const void *)(uintptr_t)src, (size_t)len);
    }
    return 0;
}

static inline int w_try_unbox_floats_fast(const WValue *src, double *dst, size_t n) {
#if defined(__ARM_NEON) || defined(__ARM_NEON__)
    const uint64x2_t bias = vdupq_n_u64(W_DOUBLE_BIAS);
    const uint64x2_t ceiling = vdupq_n_u64(0xFFF0000000000000ULL);
    uint64x2_t ok0 = vdupq_n_u64(~0ULL), ok1 = ok0, ok2 = ok0, ok3 = ok0;
    size_t i = 0;
    for (; i + 8 <= n; i += 8) {
        uint64x2_t b0 = vsubq_u64(vld1q_u64((const uint64_t *)(src + i + 0)), bias);
        uint64x2_t b1 = vsubq_u64(vld1q_u64((const uint64_t *)(src + i + 2)), bias);
        uint64x2_t b2 = vsubq_u64(vld1q_u64((const uint64_t *)(src + i + 4)), bias);
        uint64x2_t b3 = vsubq_u64(vld1q_u64((const uint64_t *)(src + i + 6)), bias);
        ok0 = vandq_u64(ok0, vcleq_u64(b0, ceiling));
        ok1 = vandq_u64(ok1, vcleq_u64(b1, ceiling));
        ok2 = vandq_u64(ok2, vcleq_u64(b2, ceiling));
        ok3 = vandq_u64(ok3, vcleq_u64(b3, ceiling));
        vst1q_f64(dst + i + 0, vreinterpretq_f64_u64(b0));
        vst1q_f64(dst + i + 2, vreinterpretq_f64_u64(b1));
        vst1q_f64(dst + i + 4, vreinterpretq_f64_u64(b2));
        vst1q_f64(dst + i + 6, vreinterpretq_f64_u64(b3));
    }
    uint64x2_t all = vandq_u64(vandq_u64(ok0, ok1), vandq_u64(ok2, ok3));
    if (__builtin_expect((vgetq_lane_u64(all, 0) & vgetq_lane_u64(all, 1)) != ~0ULL, 0))
        return 0;
    for (; i < n; i++) {
        WValue v = src[i];
        if (!w_is_double(v)) return 0;
        uint64_t u = v - W_DOUBLE_BIAS;
        memcpy(dst + i, &u, 8);
    }
    return 1;
#else
    for (size_t i = 0; i < n; i++) {
        WValue v = src[i];
        if (!w_is_double(v)) return 0;
        uint64_t u = v - W_DOUBLE_BIAS;
        memcpy(dst + i, &u, 8);
    }
    return 1;
#endif
}

static inline void w_box_floats_fast(const double *src, WValue *dst, size_t n) {
#if defined(__ARM_NEON) || defined(__ARM_NEON__)
    const uint64x2_t bias = vdupq_n_u64(W_DOUBLE_BIAS);
    const uint64x2_t abs_mask = vdupq_n_u64(0x7FFFFFFFFFFFFFFFULL);
    const uint64x2_t inf_exp  = vdupq_n_u64(0x7FF0000000000000ULL);
    const uint64x2_t qnan_val = vdupq_n_u64(0x7FF8000000000000ULL);
    size_t i = 0;
    for (; i + 4 <= n; i += 4) {
        uint64x2_t b0 = vreinterpretq_u64_f64(vld1q_f64(src + i));
        uint64x2_t b1 = vreinterpretq_u64_f64(vld1q_f64(src + i + 2));
        uint64x2_t nan0 = vcgtq_u64(vandq_u64(b0, abs_mask), inf_exp);
        uint64x2_t nan1 = vcgtq_u64(vandq_u64(b1, abs_mask), inf_exp);
        b0 = vbslq_u64(nan0, qnan_val, b0);
        b1 = vbslq_u64(nan1, qnan_val, b1);
        vst1q_u64((uint64_t *)(dst + i),     vaddq_u64(b0, bias));
        vst1q_u64((uint64_t *)(dst + i + 2), vaddq_u64(b1, bias));
    }
    for (; i < n; i++) dst[i] = w_box_double(src[i]);
#else
    for (size_t i = 0; i < n; i++) dst[i] = w_box_double(src[i]);
#endif
}

#ifdef __APPLE__
typedef struct { double *realp; double *imagp; } WDSPDoubleSplitComplex;
typedef void *WFFTSetupD;
typedef unsigned long WvDSP_Length;
typedef long WvDSP_Stride;
typedef int WFFTDirection;
static WFFTSetupD (*g_vdsp_create_fftsetupD)(WvDSP_Length, int) = NULL;
static void (*g_vdsp_fft_zipD)(WFFTSetupD, const WDSPDoubleSplitComplex *, WvDSP_Stride, WvDSP_Length, WFFTDirection) = NULL;
static void (*g_vdsp_vsmulD)(const double *, WvDSP_Stride, const double *, double *, WvDSP_Stride, WvDSP_Length) = NULL;
static int g_vdsp_init_state = 0;
static WFFTSetupD g_vdsp_setups[21];
static _Thread_local double *g_fft_scratch_re = NULL;
static _Thread_local double *g_fft_scratch_im = NULL;
static _Thread_local size_t g_fft_scratch_cap = 0;

static int w_ensure_vdsp(void) {
    if (__builtin_expect(g_vdsp_init_state == 1, 1)) return 1;
    if (g_vdsp_init_state == -1) return 0;
    void *h = dlopen("/System/Library/Frameworks/Accelerate.framework/Accelerate", RTLD_LAZY | RTLD_LOCAL);
    if (!h) h = RTLD_DEFAULT;
    g_vdsp_create_fftsetupD = (WFFTSetupD (*)(WvDSP_Length, int))dlsym(h, "vDSP_create_fftsetupD");
    g_vdsp_fft_zipD = (void (*)(WFFTSetupD, const WDSPDoubleSplitComplex *, WvDSP_Stride, WvDSP_Length, WFFTDirection))dlsym(h, "vDSP_fft_zipD");
    g_vdsp_vsmulD = (void (*)(const double *, WvDSP_Stride, const double *, double *, WvDSP_Stride, WvDSP_Length))dlsym(h, "vDSP_vsmulD");
    if (g_vdsp_create_fftsetupD && g_vdsp_fft_zipD && g_vdsp_vsmulD) {
        g_vdsp_init_state = 1;
        return 1;
    }
    g_vdsp_init_state = -1;
    return 0;
}
#endif

static int w_unpack_numeric_array_f64(WArray *a, double *dst, size_t n) {
    if (a->ebits == -64) {
        memcpy(dst, (const double *)a->slots + a->start, n * sizeof(double));
        return 1;
    }
    if (a->ebits == 65) {
        const WValue *xs = a->slots + a->start;
        if (w_try_unbox_floats_fast(xs, dst, n)) return 1;
        for (size_t j = 0; j < n; j++) {
            WValue v = xs[j];
            if (w_is_double(v)) {
                uint64_t u = v - W_DOUBLE_BIAS;
                memcpy(dst + j, &u, 8);
            } else if (w_is_int(v)) {
                dst[j] = (double)w_as_int(v);
            } else {
                return 0;
            }
        }
        return 1;
    }
    return 0;
}

WValue w_array_memmove_f64(WValue src_v, WValue dst_v, WValue count_v) {
    if (dst_v == W_NIL && w_is_array(src_v)) {
        WArray *src = w_as_array(src_v);
        int64_t count = ((uint64_t)count_v < 0x0001000000000000ULL)
                            ? (int64_t)count_v
                            : w_to_i64(count_v);
        if (src->ebits == -64 && count >= 0 && count <= src->size) {
            WValue out_v = w_array_new_uninit_sized(65, count);
            WArray *out = w_as_array(out_v);
            const double *src_ptr = (const double *)src->slots + src->start;
            WValue *dslots = (WValue *)out->slots;
            w_box_floats_fast(src_ptr, dslots, (size_t)count);
            return out_v;
        }
    }
    if (!w_is_array(src_v) || !w_is_array(dst_v)) {
        w_raise(w_string("array_memmove_f64: expected typed arrays"));
        return W_NIL;
    }
    WArray *src = w_as_array(src_v);
    WArray *dst = w_as_array(dst_v);
    int64_t count = ((int64_t)count_v >= -8 && (int64_t)count_v < 0) ||
                    ((uint64_t)count_v < 0x0001000000000000ULL)
                        ? (int64_t)count_v
                        : w_to_i64(count_v);
#ifdef __APPLE__
    if (count <= -2 && count >= -5) {
        int64_t n = (int64_t)src->size;
        if (n != (int64_t)dst->size || n < 2 || (n & (n - 1)) != 0 || n > (1 << 20))
            return W_NIL;
        if (!w_ensure_vdsp()) return W_NIL;
        unsigned lg = (unsigned)__builtin_ctzll((unsigned long long)n);
        WFFTSetupD setup = g_vdsp_setups[lg];
        if (!setup) {
            setup = g_vdsp_create_fftsetupD(lg, 0 /* kFFTRadix2 */);
            if (!setup) return W_NIL;
            g_vdsp_setups[lg] = setup;
        }
        if (g_fft_scratch_cap < (size_t)n) {
            free(g_fft_scratch_re);
            free(g_fft_scratch_im);
            g_fft_scratch_re = (double *)malloc((size_t)n * sizeof(double));
            g_fft_scratch_im = (double *)malloc((size_t)n * sizeof(double));
            g_fft_scratch_cap = (size_t)n;
        }
        if (!w_unpack_numeric_array_f64(src, g_fft_scratch_re, (size_t)n) ||
            !w_unpack_numeric_array_f64(dst, g_fft_scratch_im, (size_t)n))
            return W_NIL;
        int inverse = (count == -3 || count == -5) ? 1 : 0;
        WDSPDoubleSplitComplex sc = { g_fft_scratch_re, g_fft_scratch_im };
        g_vdsp_fft_zipD(setup, &sc, 1, lg, inverse ? -1 : +1);
        if (inverse) {
            double scale = 1.0 / (double)n;
            g_vdsp_vsmulD(g_fft_scratch_re, 1, &scale, g_fft_scratch_re, 1, (WvDSP_Length)n);
            g_vdsp_vsmulD(g_fft_scratch_im, 1, &scale, g_fft_scratch_im, 1, (WvDSP_Length)n);
        }
        if (count == -2 || count == -3) {
            WValue out_re = w_array_new_uninit_sized(65, n);
            WValue out_im = w_array_new_uninit_sized(65, n);
            w_box_floats_fast(g_fft_scratch_re, w_as_array(out_re)->slots, (size_t)n);
            w_box_floats_fast(g_fft_scratch_im, w_as_array(out_im)->slots, (size_t)n);
            WValue pair = w_array_new_uninit_sized(65, 2);
            WArray *pa = w_as_array(pair);
            pa->slots[0] = out_re;
            pa->slots[1] = out_im;
            return pair;
        } else {
            if (src->ebits == 65 && dst->ebits == 65) {
                w_box_floats_fast(g_fft_scratch_re, src->slots + src->start, (size_t)n);
                w_box_floats_fast(g_fft_scratch_im, dst->slots + dst->start, (size_t)n);
            } else if (src->ebits == -64 && dst->ebits == -64) {
                memcpy((double *)src->slots + src->start, g_fft_scratch_re, (size_t)n * sizeof(double));
                memcpy((double *)dst->slots + dst->start, g_fft_scratch_im, (size_t)n * sizeof(double));
            } else {
                return W_NIL;
            }
            return w_int(1);
        }
    }
#endif
    if (count == -1 && src->ebits == 65 && src->size >= 4) {
        WArray *ip_a = w_as_array(src->slots[src->start]);
        WArray *ix_a = w_as_array(src->slots[src->start + 1]);
        WArray *dv_a = w_as_array(src->slots[src->start + 2]);
        WArray *xv_a = w_as_array(src->slots[src->start + 3]);
        int64_t nrows = (int64_t)ip_a->size - 1;
        int64_t ncols = (int64_t)xv_a->size;
        const double *x_ptr = NULL;
        if (dst->ebits == -64 && (int64_t)dst->size >= ncols) {
            x_ptr = (const double *)dst->slots + dst->start;
        } else if (dst->ebits == 65 && (int64_t)dst->size >= ncols) {
            double *xv_ptr = (double *)xv_a->slots;
            if (!w_unpack_numeric_array_f64(dst, xv_ptr, (size_t)ncols))
                return W_NIL;
            x_ptr = xv_ptr;
        } else {
            return W_NIL;
        }
        const double *dv = (const double *)dv_a->slots + dv_a->start;
        WValue out_v = w_array_new_uninit_sized(65, nrows);
        WArray *out = w_as_array(out_v);
        WValue *dslots = (WValue *)out->slots;
        int64_t row_nnz = (src->size >= 5 && w_is_int(src->slots[src->start + 4]))
                              ? w_as_int(src->slots[src->start + 4]) : -1;
        if (ip_a->ebits == 33 && ix_a->ebits == 33) {
            const int32_t * restrict ip = (const int32_t *)ip_a->slots + ip_a->start;
            const int32_t * restrict ix = (const int32_t *)ix_a->slots + ix_a->start;
            const double * restrict dvp = dv;
            const double * restrict xp = x_ptr;
            if (row_nnz == 5) {
#if defined(__ARM_NEON) || defined(__ARM_NEON__)
                const uint64x2_t bias = vdupq_n_u64(W_DOUBLE_BIAS);
                const int32_t * restrict ixp = ix;
                int64_t i = 0;
                for (; i + 4 <= nrows; i += 4, dvp += 20, ixp += 20) {
                    double r0 = (dvp[0]  * xp[ixp[0]]  + dvp[1]  * xp[ixp[1]])  + (dvp[2]  * xp[ixp[2]]  + dvp[3]  * xp[ixp[3]])  + dvp[4]  * xp[ixp[4]];
                    double r1 = (dvp[5]  * xp[ixp[5]]  + dvp[6]  * xp[ixp[6]])  + (dvp[7]  * xp[ixp[7]]  + dvp[8]  * xp[ixp[8]])  + dvp[9]  * xp[ixp[9]];
                    double r2 = (dvp[10] * xp[ixp[10]] + dvp[11] * xp[ixp[11]]) + (dvp[12] * xp[ixp[12]] + dvp[13] * xp[ixp[13]]) + dvp[14] * xp[ixp[14]];
                    double r3 = (dvp[15] * xp[ixp[15]] + dvp[16] * xp[ixp[16]]) + (dvp[17] * xp[ixp[17]] + dvp[18] * xp[ixp[18]]) + dvp[19] * xp[ixp[19]];
                    float64x2_t pair0 = vcombine_f64(vdup_n_f64(r0), vdup_n_f64(r1));
                    float64x2_t pair1 = vcombine_f64(vdup_n_f64(r2), vdup_n_f64(r3));
                    vst1q_u64((uint64_t *)(dslots + i),     vaddq_u64(vreinterpretq_u64_f64(pair0), bias));
                    vst1q_u64((uint64_t *)(dslots + i + 2), vaddq_u64(vreinterpretq_u64_f64(pair1), bias));
                }
                for (; i < nrows; i++, dvp += 5, ixp += 5) {
                    double r = (dvp[0] * xp[ixp[0]] + dvp[1] * xp[ixp[1]]) +
                               (dvp[2] * xp[ixp[2]] + dvp[3] * xp[ixp[3]]) +
                               dvp[4] * xp[ixp[4]];
                    dslots[i] = w_box_double(r);
                }
#else
                for (int64_t i = 0; i < nrows; i++) {
                    int64_t p = i * 5;
                    double r = (dv[p] * x_ptr[ix[p]] + dv[p+1] * x_ptr[ix[p+1]]) +
                               (dv[p+2] * x_ptr[ix[p+2]] + dv[p+3] * x_ptr[ix[p+3]]) +
                               dv[p+4] * x_ptr[ix[p+4]];
                    dslots[i] = w_box_double(r);
                }
#endif
                return out_v;
            }
            for (int64_t i = 0; i < nrows; i++) {
                double s0 = 0.0, s1 = 0.0;
                int32_t p = ip[i], pend = ip[i + 1];
                for (; pend - p >= 4; p += 4) {
                    s0 += dv[p]   * x_ptr[ix[p]];
                    s1 += dv[p+1] * x_ptr[ix[p+1]];
                    s0 += dv[p+2] * x_ptr[ix[p+2]];
                    s1 += dv[p+3] * x_ptr[ix[p+3]];
                }
                for (; p < pend; p++) s0 += dv[p] * x_ptr[ix[p]];
                dslots[i] = w_box_double(s0 + s1);
            }
            return out_v;
        }
        const int64_t *ip = (const int64_t *)ip_a->slots + ip_a->start;
        const int64_t *ix = (const int64_t *)ix_a->slots + ix_a->start;
        for (int64_t i = 0; i < nrows; i++) {
            double s0 = 0.0, s1 = 0.0;
            int64_t p = ip[i];
            int64_t pend = ip[i + 1];
            int64_t pend2 = pend - 1;
            while (p < pend2) {
                s0 += dv[p] * x_ptr[ix[p]];
                s1 += dv[p + 1] * x_ptr[ix[p + 1]];
                p += 2;
            }
            if (p < pend) s0 += dv[p] * x_ptr[ix[p]];
            dslots[i] = w_box_double(s0 + s1);
        }
        return out_v;
    }
    if (count == 0 && dst->ebits == -64 && dst->size > 0 &&
        src->ebits == 65 && src->size > 0 && w_is_array(src->slots[src->start])) {
        double *dst_ptr = (double *)dst->slots + dst->start;
        int64_t total = dst->size;
        int64_t idx = 0;
        for (int64_t r = 0; r < src->size && idx < total; r++) {
            WValue rv = src->slots[src->start + r];
            if (!w_is_array(rv)) break;
            WArray *row = w_as_array(rv);
            int64_t rlen = row->size;
            if (idx + rlen > total) rlen = total - idx;
            if (row->ebits == 65) {
                const WValue *rslots = row->slots + row->start;
                if (!w_try_unbox_floats_fast(rslots, dst_ptr + idx, (size_t)rlen)) {
                    for (int64_t j = 0; j < rlen; j++) {
                        WValue v = rslots[j];
                        if (__builtin_expect(w_is_double(v), 1)) {
                            union { uint64_t u; double d; } u;
                            u.u = v - W_DOUBLE_BIAS;
                            dst_ptr[idx + j] = u.d;
                        } else if (w_is_int(v)) {
                            dst_ptr[idx + j] = (double)w_as_int(v);
                        } else {
                            dst_ptr[idx + j] = w_as_double(v);
                        }
                    }
                }
            } else if (row->ebits == -64) {
                memcpy(dst_ptr + idx, (const double *)row->slots + row->start, (size_t)rlen * sizeof(double));
            } else {
                for (int64_t j = 0; j < rlen; j++) {
                    WValue v = w_array_get(rv, w_int(j));
                    dst_ptr[idx + j] = w_is_int(v) ? (double)w_as_int(v) : w_as_double(v);
                }
            }
            idx += rlen;
        }
        return dst_v;
    }
    if (dst->ebits == 65 && src->ebits == -64 && count >= 0 &&
        count <= src->size && count <= dst->size) {
        const double *src_ptr = (const double *)src->slots + src->start;
        WValue *dslots = dst->slots + dst->start;
        w_box_floats_fast(src_ptr, dslots, (size_t)count);
        return dst_v;
    }
    if (dst->ebits != -64 || count < 0 || count > src->size ||
        count > dst->size) {
        w_raise(w_string("array_memmove_f64: bad type or length"));
        return W_NIL;
    }
    double *dst_ptr = (double *)dst->slots + dst->start;
    if (src->ebits == -64 && count > 0) {
        double *src_ptr = (double *)src->slots + src->start;
        memmove(dst_ptr, src_ptr, (size_t)count * sizeof(double));
    } else if (src->ebits == 65) {
        const WValue *sslots = src->slots + src->start;
        if (!w_try_unbox_floats_fast(sslots, dst_ptr, (size_t)count)) {
            for (int64_t i = 0; i < count; i++) {
                WValue v = sslots[i];
                if (__builtin_expect(w_is_double(v), 1)) {
                    union { uint64_t u; double d; } u;
                    u.u = v - W_DOUBLE_BIAS;
                    dst_ptr[i] = u.d;
                } else if (w_is_int(v)) {
                    dst_ptr[i] = (double)w_as_int(v);
                } else {
                    dst_ptr[i] = w_as_double(v);
                }
            }
        }
    } else if (src->ebits != -64) {
        /* List convenience lanes preserve their old numeric conversion while
         * typed f64 views take the overlap-safe bulk path above. */
        for (int64_t i = 0; i < count; i++) {
            WValue v = w_array_get(src_v, w_int(i));
            dst_ptr[i] = w_is_int(v) ? (double)w_as_int(v) : w_as_double(v);
        }
    }
    return dst_v;
}

/* ---- ALPN protocol query ---- */

/* Implementation in tls.c when TLS enabled, stub below for non-TLS */
#ifndef TUNGSTEN_TLS
WValue w_socket_alpn_protocol(WValue sock) {
    (void)sock;
    return W_NIL;
}
#endif

/* ---- ByteArray (thin wrappers over WArray<u8>) ----
 *
 * WBytes was originally a dedicated 24-byte struct with its own
 * subtag and dispatch path; it has since been collapsed into WArray with
 * ebits=8 so a single representation backs both `ByteArray.new(n)` and
 * `u8[n]`. The public C API (w_bytes_*) is preserved for internal
 * callers; each function is now a thin shim over w_array_* primitives. */

static WArray *as_bytes_arr(WValue v) {
    if (!w_is_bytes(v)) die("expected ByteArray (WArray<u8>)");
    return w_as_array(v);
}

WValue w_bytes_new(int64_t length) {
    WValue arr = w_array_new(8, length > 0 ? length : 1);
    WArray *a = w_as_array(arr);
    a->size = (int32_t)length;  /* size==length, payload zero-init by w_array_new */
    return arr;
}

WValue w_bytes_from_data(const uint8_t *data, int64_t length) {
    WValue arr = w_bytes_new(length);
    if (length > 0) {
        WArray *a = w_as_array(arr);
        memcpy(a->slots, data, (size_t)length);
    }
    return arr;
}

WValue w_bytes_get(WValue bytes, WValue index) {
    WArray *a = as_bytes_arr(bytes);
    int64_t i = w_as_int(index);
    if (i < 0 || i >= a->size) return W_NIL;
    return w_int(((uint8_t *)a->slots)[i]);
}

WValue w_bytes_set(WValue bytes, WValue index, WValue val) {
    WArray *a = as_bytes_arr(bytes);
    int64_t i = w_as_int(index);
    if (i < 0 || i >= a->size) {
        w_raise(w_string("ByteArray: index out of range"));
    }
    ((uint8_t *)a->slots)[i] = (uint8_t)w_to_i64(val);
    return val;
}

WValue w_bytes_length(WValue bytes) {
    return w_int(as_bytes_arr(bytes)->size);
}

WValue w_bytes_slice(WValue bytes, WValue start, WValue len) {
    WArray *a = as_bytes_arr(bytes);
    int64_t s = w_as_int(start);
    int64_t l = w_as_int(len);
    if (s < 0) s = 0;
    if (s + l > a->size) l = a->size - s;
    WValue out = (l <= 0) ? w_bytes_new(0) : w_bytes_from_data(((uint8_t *)a->slots) + s, l);
    w_as_array(out)->_pad[0] = a->_pad[0];
    return out;
}

WValue w_bytes_concat(WValue a_val, WValue b_val) {
    WArray *aa = as_bytes_arr(a_val);
    WArray *bb = as_bytes_arr(b_val);
    int64_t total = (int64_t)aa->size + bb->size;
    WValue out = w_bytes_new(total);
    WArray *out_a = w_as_array(out);
    if (aa->size > 0) memcpy(out_a->slots, aa->slots, (size_t)aa->size);
    if (bb->size > 0) memcpy(((uint8_t *)out_a->slots) + aa->size, bb->slots, (size_t)bb->size);
    return out;
}

/* ---- BoolArray (thin wrappers over WArray<u1>) ----
 *
 * Bit-packed array of booleans, backed by ebits=1 in the WArray tier.
 * The dispatch boundary maps W_TRUE/W_FALSE to bit values 1/0 on write
 * and back to W_TRUE/W_FALSE on read so user-facing truthiness still
 * matches Tungsten convention (only W_NIL and W_FALSE are falsy). */

WValue w_bool_array_new(int64_t cap) {
    /* BoolArray.new(N) reserves N bits with size 0 for push-to-fill use.
     * The `bool[N]` literal instead follows the fixed-size T[N] contract
     * and lowers to w_array_zeros(1, N). */
    return w_array_new(1, cap > 0 ? cap : 1);
}

WValue w_bool_array_get(WValue arr, WValue index) {
    WArray *a = w_as_array(arr);
    int64_t i = w_as_int(index);
    if (i < 0 || i >= a->size) return W_FALSE;
    int64_t abs_i = a->start + i;
    uint8_t *bytes = (uint8_t *)a->slots;
    return ((bytes[abs_i >> 3] >> (abs_i & 7)) & 1) ? W_TRUE : W_FALSE;
}

WValue w_bool_array_set(WValue arr, WValue index, WValue val) {
    WArray *a = w_as_array(arr);
    int64_t i = w_as_int(index);
    if (i < 0 || i >= a->size) return val;
    /* Tungsten truthiness: only W_NIL and W_FALSE are falsy. */
    int bit = (val == W_NIL || val == W_FALSE) ? 0 : 1;
    int64_t abs_i = a->start + i;
    uint8_t *bytes = (uint8_t *)a->slots;
    uint8_t mask = (uint8_t)(1u << (abs_i & 7));
    if (bit) bytes[abs_i >> 3] |=  mask;
    else     bytes[abs_i >> 3] &= (uint8_t)~mask;
    return val;
}

WValue w_bool_array_size(WValue arr) {
    return w_int((w_as_array(arr))->size);
}

/* Typed Array / View / Small Array / Sort / Matmul implementation lives in runtime_arrays.c */

/* Binary socket I/O — reads exactly n bytes into a ByteArray (WArray<u8>) */
WValue w_socket_read_exact(WValue sock, WValue n_val) {
    WSocket *s = as_socket(sock);
    if (s->closed) return W_NIL;

    int64_t n = w_as_int(n_val);
    if (n <= 0) return w_bytes_new(0);

    uint8_t *buf = malloc(n);
    int64_t total_read = 0;

    while (total_read < n) {
        ssize_t bytes;
#ifdef TUNGSTEN_TLS
        if (s->ssl) {
            bytes = w_tls_read(s, (char *)(buf + total_read), n - total_read);
        } else
#endif
        {
            bytes = read(s->fd, buf + total_read, n - total_read);
        }

        if (bytes > 0) {
            total_read += bytes;
            continue;
        }
        if (bytes == 0) {
            /* EOF before all bytes read */
            if (total_read == 0) return W_NIL;
            return w_bytes_from_data(buf, total_read);
        }
        /* bytes < 0 */
        if (errno == EINTR) continue;
        if (errno == EAGAIN || errno == EWOULDBLOCK) {
            w_socket_park(s->fd, W_EVENT_READ);
            continue;
        }
        if (errno == ECONNRESET) {
            if (total_read == 0) return W_NIL;
            return w_bytes_from_data(buf, total_read);
        }
        w_raise(w_string("socket: read_exact failed"));
    }
    return w_bytes_from_data(buf, n);
}

/* Read exactly n bytes into a caller-owned ByteArray at `offset` —
 * allocation-free twin of w_socket_read_exact for pooled read buffers.
 * Returns bytes-read as Int; W_NIL when the socket is closed or EOF
 * arrives before the first byte (same semantics as read_exact returning
 * nil); a short count on EOF/ECONNRESET mid-frame. The buffer is never
 * grown — offset+n must fit inside the array's current size. The data
 * pointer is recomputed after every park so a blocking wait can never
 * hold a stale pointer. */
WValue w_socket_read_into(WValue sock, WValue buf_val, WValue off_val, WValue n_val) {
    WSocket *s = as_socket(sock);
    if (s->closed) return W_NIL;

    WArray *a = as_bytes_arr(buf_val);
    int64_t off = w_as_int(off_val);
    int64_t n = w_as_int(n_val);
    if (n <= 0) return w_int(0);
    if (off < 0 || off + n > a->size)
        w_raise(w_string("socket: read_into out of range"));

    int64_t total_read = 0;
    while (total_read < n) {
        uint8_t *dst = (uint8_t *)a->slots + a->start + off + total_read;
        ssize_t bytes;
#ifdef TUNGSTEN_TLS
        if (s->ssl) {
            bytes = w_tls_read(s, (char *)dst, n - total_read);
        } else
#endif
        {
            bytes = read(s->fd, dst, n - total_read);
        }

        if (bytes > 0) {
            total_read += bytes;
            continue;
        }
        if (bytes == 0) {
            /* EOF before all bytes read */
            if (total_read == 0) return W_NIL;
            return w_int(total_read);
        }
        /* bytes < 0 */
        if (errno == EINTR) continue;
        if (errno == EAGAIN || errno == EWOULDBLOCK) {
            w_socket_park(s->fd, W_EVENT_READ);
            continue;
        }
        if (errno == ECONNRESET) {
            if (total_read == 0) return W_NIL;
            return w_int(total_read);
        }
        w_raise(w_string("socket: read_into failed"));
    }
    return w_int(n);
}

/* Write ByteArray to socket (length-aware, no strlen).
 * ByteArray is now a WArray<u8>, so dig the payload out of `slots`. */
WValue w_socket_write_bytes(WValue sock, WValue bytes_val) {
    WSocket *s = as_socket(sock);
    if (s->closed) {
        w_raise(w_string("socket: write to closed socket"));
    }

    WArray *a = as_bytes_arr(bytes_val);
    const uint8_t *data = (const uint8_t *)a->slots;
    size_t total = (size_t)a->size;
    size_t written = 0;

#ifdef TUNGSTEN_TLS
    if (s->ssl) {
        while (written < total) {
            ssize_t n = w_tls_write(s, (const char *)(data + written), total - written);
            if (n > 0) { written += n; continue; }
            if (n <= 0) return w_box_int(written);
        }
        return w_box_int(written);
    }
#endif

    while (written < total) {
        ssize_t n = write(s->fd, data + written, total - written);
        if (n > 0) { written += n; continue; }
        if (n < 0) {
            if (errno == EINTR) continue;
            if (errno == EAGAIN || errno == EWOULDBLOCK) {
                w_socket_park(s->fd, W_EVENT_WRITE);
                continue;
            }
            if (errno == EPIPE || errno == ECONNRESET) return w_box_int(written);
            w_raise(w_string("socket: write_bytes failed"));
        }
    }
    return w_box_int(written);
}

/* Write a sub-range of a ByteArray to the socket — allocation-free twin
 * of w_socket_write_bytes for pooled send buffers (no .slice copy needed).
 * Returns bytes written as Int, mirroring write_bytes; raises on a closed
 * socket or hard error; out-of-range offset/len raises rather than
 * clamping. The data pointer is recomputed after every park. */
WValue w_socket_write_slice(WValue sock, WValue bytes_val, WValue off_val, WValue len_val) {
    WSocket *s = as_socket(sock);
    if (s->closed) {
        w_raise(w_string("socket: write to closed socket"));
    }

    WArray *a = as_bytes_arr(bytes_val);
    int64_t off = w_as_int(off_val);
    int64_t len = w_as_int(len_val);
    if (len <= 0) return w_box_int(0);
    if (off < 0 || off + len > a->size)
        w_raise(w_string("socket: write_slice out of range"));

    size_t total = (size_t)len;
    size_t written = 0;

#ifdef TUNGSTEN_TLS
    if (s->ssl) {
        while (written < total) {
            const uint8_t *data = (const uint8_t *)a->slots + a->start + off;
            ssize_t n = w_tls_write(s, (const char *)(data + written), total - written);
            if (n > 0) { written += n; continue; }
            if (n <= 0) return w_box_int(written);
        }
        return w_box_int(written);
    }
#endif

    while (written < total) {
        const uint8_t *data = (const uint8_t *)a->slots + a->start + off;
        ssize_t n = write(s->fd, data + written, total - written);
        if (n > 0) { written += n; continue; }
        if (n < 0) {
            if (errno == EINTR) continue;
            if (errno == EAGAIN || errno == EWOULDBLOCK) {
                w_socket_park(s->fd, W_EVENT_WRITE);
                continue;
            }
            if (errno == EPIPE || errno == ECONNRESET) return w_box_int(written);
            w_raise(w_string("socket: write_slice failed"));
        }
    }
    return w_box_int(written);
}

/* ---- Outbound TCP connect ---- */

#include <netdb.h>

static int w_socket_tcp_connect_fd_impl(const char *host, int port, int64_t deadline_ticks, int raise_errors) {
    w_sandbox_gate("socket_connect", host);
    char port_str[16];
    snprintf(port_str, sizeof(port_str), "%d", port);

    struct addrinfo hints, *result;
    memset(&hints, 0, sizeof(hints));
    hints.ai_family = AF_INET;
    hints.ai_socktype = SOCK_STREAM;

    int err = getaddrinfo(host, port_str, &hints, &result);
    if (err != 0) {
        if (raise_errors) w_raise(w_string("socket: DNS resolution failed"));
        return -1;
    }

    int fd = socket(result->ai_family, result->ai_socktype, result->ai_protocol);
    if (fd < 0) {
        freeaddrinfo(result);
        if (raise_errors) w_raise(w_string("socket: creation failed"));
        return -1;
    }

    /* Set non-blocking */
    if (w_fd_set_nonblocking(fd) < 0) {
        close(fd);
        freeaddrinfo(result);
        if (raise_errors) w_raise(w_string("socket: connect nonblocking failed"));
        return -1;
    }

    int one = 1;
#ifdef SO_NOSIGPIPE
    setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, sizeof(one));
#endif

    int sndbuf = 262144;
    setsockopt(fd, SOL_SOCKET, SO_SNDBUF, &sndbuf, sizeof(sndbuf));

    setsockopt(fd, IPPROTO_TCP, TCP_NODELAY, &one, sizeof(one));

    int ret = connect(fd, result->ai_addr, result->ai_addrlen);
    freeaddrinfo(result);

    if (ret < 0 && errno != EINPROGRESS && errno != EALREADY && errno != EWOULDBLOCK) {
        close(fd);
        if (raise_errors) w_raise(w_string("socket: connect failed"));
        return -1;
    }

    if (ret < 0) {
        /* EINPROGRESS — park on write-ready. Outside a goroutine the park is a
         * poll(2) of at most 100 ms when there is no deadline, so keep waiting:
         * without this a native Thread (or the main thread) failed every connect
         * slower than 100 ms and got back a Socket with fd -1. No deadline means
         * the kernel's own connect timeout decides. */
        int ready = 0;
        for (;;) {
            if (w_socket_park_until(fd, W_EVENT_WRITE, deadline_ticks)) { ready = 1; break; }
            if (deadline_ticks > 0 || w_deadline_expired(deadline_ticks)) break;
            int so_err = 0;
            socklen_t so_len = sizeof(so_err);
            if (getsockopt(fd, SOL_SOCKET, SO_ERROR, &so_err, &so_len) == 0 && so_err != 0) { ready = 1; break; }
        }
        if (!ready) {
            close(fd);
            if (raise_errors) w_raise(w_string("socket: connect timed out"));
            return -1;
        }

        /* Check SO_ERROR */
        int so_err = 0;
        socklen_t so_len = sizeof(so_err);
        getsockopt(fd, SOL_SOCKET, SO_ERROR, &so_err, &so_len);
        if (so_err != 0) {
            close(fd);
            if (raise_errors) w_raise(w_string("socket: connect failed (async)"));
            return -1;
        }
    }

    return fd;
}

WValue w_socket_tcp_connect(const char *host, int port) {
    int fd = w_socket_tcp_connect_fd_impl(host, port, 0, 1);
    if (fd < 0) w_raise(w_string("socket: connect failed"));
    WSocket *s = calloc(1, sizeof(WSocket));
    s->type = W_TYPE_SOCKET;
    s->fd = fd;
    s->listening = 0;
    s->closed = 0;
    s->ssl = NULL;
    return w_box_ptr(s, W_SUBTAG_SOCKET);
}

WValue w_socket_connect_raw(WValue host, int64_t port) {
    return w_socket_tcp_connect(as_str(host), (int)port);
}

/* Socket.connect(host, port, timeout_ms): raises "socket: connect timed out" when the
 * handshake has not completed within timeout_ms (> 0). */
WValue w_socket_connect_timeout(WValue host, WValue port, WValue timeout_ms) {
    int64_t ms = w_is_int(timeout_ms) ? w_as_int(timeout_ms) : 0;
    int64_t deadline = ms > 0 ? __w_deadline_ticks_after_ms(ms) : 0;
    int fd = w_socket_tcp_connect_fd_impl(as_str(host), (int)w_as_int(port), deadline, 1);
    if (fd < 0) w_raise(w_string("socket: connect failed"));
    WSocket *s = calloc(1, sizeof(WSocket));
    s->type = W_TYPE_SOCKET;
    s->fd = fd;
    s->listening = 0;
    s->closed = 0;
    s->ssl = NULL;
    return w_box_ptr(s, W_SUBTAG_SOCKET);
}

int64_t w_socket_connect_fd(WValue host, int64_t port) {
    return (int64_t)w_socket_tcp_connect_fd_impl(as_str(host), (int)port, 0, 1);
}

int64_t w_socket_connect_fd_until(WValue host, int64_t port, int64_t deadline_ticks) {
    return (int64_t)w_socket_tcp_connect_fd_impl(as_str(host), (int)port, deadline_ticks, 0);
}

int64_t w_socket_read_fd(int64_t fd_value, int64_t data_ptr, int64_t len) {
    return w_socket_read_fd_until(fd_value, data_ptr, len, 0);
}

int64_t w_socket_read_fd_until(int64_t fd_value, int64_t data_ptr, int64_t len, int64_t deadline_ticks) {
    if (len <= 0) return 0;
    int fd = (int)fd_value;
    char *buf = (char *)(uintptr_t)data_ptr;

    while (1) {
        if (w_deadline_expired(deadline_ticks)) return 0;
        ssize_t bytes = read(fd, buf, (size_t)len);
        if (bytes > 0) return (int64_t)bytes;
        if (bytes == 0) return 0;
        if (errno == EINTR) continue;
        if (errno == EAGAIN || errno == EWOULDBLOCK) {
            if (!w_socket_park_until(fd, W_EVENT_READ, deadline_ticks)) return 0;
            continue;
        }
        if (errno == ECONNRESET) return 0;
        w_raise(w_string("socket: read failed"));
    }
}

int64_t w_socket_write_fd(int64_t fd_value, int64_t data_ptr, int64_t len) {
    return w_socket_write_fd_until(fd_value, data_ptr, len, 0);
}

int64_t w_socket_write_fd_until(int64_t fd_value, int64_t data_ptr, int64_t len, int64_t deadline_ticks) {
    int fd = (int)fd_value;
    const char *str = (const char *)(uintptr_t)data_ptr;
    size_t total = (size_t)len;
    size_t written = 0;

    while (written < total) {
        if (w_deadline_expired(deadline_ticks)) return (int64_t)written;
        ssize_t n = write(fd, str + written, total - written);
        if (n > 0) {
            written += (size_t)n;
            continue;
        }
        if (n < 0) {
            if (errno == EINTR) continue;
            if (errno == EAGAIN || errno == EWOULDBLOCK) {
                if (!w_socket_park_until(fd, W_EVENT_WRITE, deadline_ticks)) return (int64_t)written;
                continue;
            }
            if (errno == EPIPE || errno == ECONNRESET) return (int64_t)written;
            w_raise(w_string("socket: write failed"));
        }
    }
    return (int64_t)written;
}

int64_t w_socket_close_fd(int64_t fd_value) {
    close((int)fd_value);
    return 0;
}

/* ---- StringBuffer (mutable growable char buffer) ---- */

WValue w_strbuf_new(WValue cap_val) {
    int64_t cap = w_is_int(cap_val) ? w_as_int(cap_val) : 16;
    if (cap < 16) cap = 16;
    WStrBuf *sb = malloc(sizeof(WStrBuf));
    sb->flags = W_STRBUF_FLAG_ASCII;  /* empty buffer starts ASCII */
    sb->data = malloc(cap);
    sb->data[0] = '\0';
    sb->size = 0;
    sb->cap = cap;
    return w_box_ptr(sb, W_SUBTAG_STRBUF);
}

/* Call-site reuse StringBuffer allocation. Cached hit: reset length=0,
 * data[0]='\0', grow cap if requested > current. Miss: allocate fresh
 * and cache. Caller contract: buffer must not escape the call site. */
WValue w_strbuf_reuse_or_new(WValue *slot, int64_t cap) {
    WValue v = *slot;
    if (v != W_NIL) {
        WStrBuf *sb = (WStrBuf *)w_as_ptr(v);
        sb->flags = W_STRBUF_FLAG_ASCII;
        sb->size = 0;
        sb->data[0] = '\0';
        if (cap > sb->cap) {
            sb->data = realloc(sb->data, cap);
            sb->cap = cap;
        }
        return v;
    }
    if (cap < 16) cap = 16;
    WStrBuf *sb = malloc(sizeof(WStrBuf));
    sb->flags = W_STRBUF_FLAG_ASCII;  /* empty buffer starts ASCII */
    sb->data = malloc(cap);
    sb->data[0] = '\0';
    sb->size = 0;
    sb->cap = cap;
    v = w_box_ptr(sb, W_SUBTAG_STRBUF);
    *slot = v;
    return v;
}

/* Append a string (WValue) to the buffer in place; returns the buffer. */
WValue w_strbuf_append(WValue buf, WValue str) {
    WStrBuf *sb = (WStrBuf *)w_as_ptr(buf);
    if (__builtin_expect((str & (W_TAG_MASK | 1)) == W_TAG_STRINGSYM, 1)) {
        size_t mode = (str >> 1) & 7;
        if (mode <= 5) {
            if (mode == 0) return buf;
            if (__builtin_expect(sb->size + 8 < sb->cap, 1)) {
                uint64_t pay = str >> 4;
                memcpy(sb->data + sb->size, &pay, 8);
                sb->size += (int64_t)mode;
                sb->data[sb->size] = '\0';
                if (__builtin_expect((str & 0x0000080808080800ULL) != 0, 0))
                    sb->flags &= (uint8_t)~W_STRBUF_FLAG_ASCII;
                return buf;
            }
        } else {
            const char *s;
            size_t slen;
            if (mode == 7) {
                WString *ws = w_as_heap_str(str);
                s = ws->data;
                slen = w_heap_string_len(ws);
                if (!w_heap_string_ascii_p(ws)) sb->flags &= (uint8_t)~W_STRBUF_FLAG_ASCII;
            } else {
                uint32_t idx = (uint32_t)((str >> 4) & 0xFFFFFF);
                const uint8_t *slot = g_string_slab.base + ((size_t)idx << 5);
                s = (const char *)(slot + W_SLAB_DATA_OFFSET);
                size_t cached = (size_t)((str >> 28) & 0x3F);
                slen = cached ? cached : slot[1];
                if ((slot[0] & W_SFLAG_ASCII) == 0) sb->flags &= (uint8_t)~W_STRBUF_FLAG_ASCII;
            }
            if (__builtin_expect(sb->size + (int64_t)slen >= sb->cap, 0)) {
                int64_t new_cap = (sb->size + (int64_t)slen + 1) * 2;
                sb->data = realloc(sb->data, new_cap);
                sb->cap = new_cap;
            }
            memcpy(sb->data + sb->size, s, slen);
            sb->size += (int64_t)slen;
            sb->data[sb->size] = '\0';
            return buf;
        }
    }
    /* as_str() calls w_str_data -- which already returns the byte length --
     * discards it, and stages inline-mode bytes in a thread-local rotating
     * buffer; the length then had to be recovered with strlen. That cost an
     * O(n) rescan of every appended chunk plus a TLS access per append, on
     * the hottest string-building path there is. Take the length w_str_data
     * already computed.
     *
     * This also settles an embedded-NUL inconsistency: strlen stopped at the
     * first NUL, so `sb << "a\0b"` appended one byte while String#+,
     * String#<< and String#size all count three. StringBuffer was the lone
     * outlier; it now agrees with them. */
    if (w_is_rope(str)) str = w_rope_flatten(str);
    if (!w_is_stringy(str)) die("expected string or symbol");
    if (!w_string_ascii_p(str)) sb->flags &= (uint8_t)~W_STRBUF_FLAG_ASCII;
    char sbuf[6];
    const char *s;
    size_t slen;
    w_str_data(str, sbuf, &s, &slen);
    if (sb->size + (int64_t)slen >= sb->cap) {
        int64_t new_cap = (sb->size + slen + 1) * 2;
        sb->data = realloc(sb->data, new_cap);
        sb->cap = new_cap;
    }
    memcpy(sb->data + sb->size, s, slen);
    sb->size += slen;
    sb->data[sb->size] = '\0';
    return buf;
}

__attribute__((noinline, cold))
static WValue w_strbuf_append_any_slow(WValue buf, WValue val) {
    return w_bit_shl(buf, val);
}

WValue w_strbuf_append_any(WValue buf, WValue val) {
    if (__builtin_expect(w_is_strbuf(buf), 1)) {
        if (__builtin_expect(w_is_string(val) || w_is_rope(val), 1))
            return w_strbuf_append(buf, val);
        return w_strbuf_append(buf, w_to_s(val));
    }
    return w_strbuf_append_any_slow(buf, val);
}

/* Convert buffer contents to an immutable WValue string. */
WValue w_strbuf_to_s(WValue buf) {
    WStrBuf *sb = (WStrBuf *)w_as_ptr(buf);
    /* w_string() would strlen the whole buffer -- a full extra pass over
     * everything appended (10 MB in the string_build benchmark) to recover a
     * length sb->size already holds. It also truncated at an embedded NUL,
     * which is the other half of the inconsistency fixed in
     * w_strbuf_append: String#+/#<</#size are all byte-exact, so
     * StringBuffer is too. */
    return w_string_n_known_ascii(
        sb->data, (size_t)sb->size,
        (sb->flags & W_STRBUF_FLAG_ASCII) != 0);
}

/* ---- Base64 storage boundaries ----
 *
 * The RFC 4648 transforms live in core/base64.w. These helpers expose String
 * storage as a borrowed u8[] view and materialize the encoded u8[] as an
 * immutable String. There is intentionally no C codec or public wrapper here:
 * both Base64's class API and the legacy global functions execute the source
 * loops. */

/* Borrowed u8[] view of a String's bytes — the generic storage boundary for
 * core source methods that loop over string bytes (base64, case transforms).
 * Inline-mode strings are copied into an owned buffer: their bytes live in
 * the caller's stack scratch, and source-level classes can be reopened, so a
 * re-entrant call would otherwise overwrite an outer call's live view. */
WValue w_string_bytes_view(WValue text) {
    if (w_is_rope(text)) text = w_rope_flatten(text);
    if (!w_is_stringy(text) || w_is_symbol(text))
        die("string bytes view: expected String");

    char inline_buf[6];
    const char *data;
    size_t len;
    w_str_data(text, inline_buf, &data, &len);
    if (data == inline_buf)
        return w_bytes_from_data((const uint8_t *)inline_buf, (int64_t)len);
    return w_array_view_raw((uint8_t *)data, 8, (int64_t)len);
}

WValue w_base64_encode_input(WValue data) {
    if (w_is_bytes(data)) return data;
    return w_string_bytes_view(data);
}

WValue w_base64_decode_input(WValue text) {
    return w_string_bytes_view(text);
}

WValue w_string_from_byte_array(WValue bytes) {
    WArray *a = as_bytes_arr(bytes);
    if (a->size == 0) return w_string("");
    const char *data = (const char *)a->slots + a->start;
    return w_string_n(data, (size_t)a->size);
}

/* Raw byte pointer of a slab/heap String (modes 6-7), for core source
 * methods that walk string bytes without materializing a view. Inline
 * modes (0-5) have no stable storage — their bytes live in the WValue
 * itself and callers transform them via $value bit ops instead. Ropes
 * flatten first. */
int64_t w_string_data_ptr(WValue v) {
    if (w_is_rope(v)) v = w_rope_flatten(v);
    if (!w_is_stringy(v)) die("w_string_data_ptr: expected String");
    size_t mode = (v >> 1) & 7;
    if (mode == 6) {
        size_t len;
        return (int64_t)(intptr_t)w_slab_read((uint32_t)((v >> 4) & 0xFFFFFF), &len);
    }
    if (mode == 7) {
        WString *ws = w_as_heap_str(v);
        return (int64_t)(intptr_t)ws->data;
    }
    die("w_string_data_ptr: inline-mode string has no stable storage");
    return 0;
}

/* Mint a String by STEALING a u8 array's slot buffer — the no-copy twin of
 * w_string_from_byte_array for core string transforms. The caller allocates
 * u8[len+1] (one spare byte for the NUL) and passes the payload length; the
 * array is left empty with its buffer relinquished to w_string_take. Any
 * shape this can't own safely (view, shifted start, undersized) falls back
 * to the copying constructor. */
static WValue w_string_ascii_squeeze(WValue recv) {
    if (w_is_rope(recv)) recv = w_rope_flatten(recv);
    char sbuf6[6];
    const char *str;
    size_t str_len;
    w_str_data(recv, sbuf6, &str, &str_len);
    if (str_len <= 1) return recv & ~1ULL;
    char stack_out[256];
    char *dst = str_len < sizeof(stack_out) ? stack_out : (char *)malloc(str_len + 1);
    size_t w = 0;
    int prev = -1;
    for (size_t i = 0; i < str_len; i++) {
        uint8_t b = (uint8_t)str[i];
        if ((int)b != prev) {
            dst[w++] = (char)b;
            prev = (int)b;
        }
    }
    if (w == str_len) {
        if (dst != stack_out) free(dst);
        return recv & ~1ULL;
    }
    dst[w] = '\0';
    WValue res = w_string_n_known_ascii(dst, w, 1);
    if (dst != stack_out) free(dst);
    return res;
}

static WValue w_string_ascii_camelize(WValue recv) {
    if (w_is_rope(recv)) recv = w_rope_flatten(recv);
    char sbuf6[6];
    const char *str;
    size_t str_len;
    w_str_data(recv, sbuf6, &str, &str_len);
    if (str_len == 0) return recv & ~1ULL;
    char stack_out[256];
    char *dst = str_len < sizeof(stack_out) ? stack_out : (char *)malloc(str_len + 1);
    size_t w = 0;
    int up = 1;
    for (size_t i = 0; i < str_len; i++) {
        uint8_t b = (uint8_t)str[i];
        if (b == '_' || b == '-' || b == ' ') {
            up = 1;
        } else {
            if (up) {
                if (b >= 'a' && b <= 'z') b -= 32;
                up = 0;
            }
            dst[w++] = (char)b;
        }
    }
    dst[w] = '\0';
    WValue res = w_string_n_known_ascii(dst, w, 1);
    if (dst != stack_out) free(dst);
    return res;
}

static WValue w_string_ascii_underscore(WValue recv) {
    if (w_is_rope(recv)) recv = w_rope_flatten(recv);
    char sbuf6[6];
    const char *str;
    size_t str_len;
    w_str_data(recv, sbuf6, &str, &str_len);
    if (str_len == 0) return recv & ~1ULL;
    char stack_out[512];
    char *dst = (str_len * 2 < sizeof(stack_out)) ? stack_out : (char *)malloc(str_len * 2 + 1);
    size_t w = 0;
    for (size_t i = 0; i < str_len; i++) {
        uint8_t o = (uint8_t)str[i];
        if (o >= 'A' && o <= 'Z') {
            if (i > 0) {
                uint8_t prev = (uint8_t)str[i - 1];
                uint8_t next = (i + 1 < str_len) ? (uint8_t)str[i + 1] : 0;
                int prev_soft = (prev >= 'a' && prev <= 'z') || (prev >= '0' && prev <= '9');
                int prev_upper = (prev >= 'A' && prev <= 'Z');
                int next_lower = (next >= 'a' && next <= 'z');
                if (prev_soft || (prev_upper && next_lower)) dst[w++] = '_';
            }
            dst[w++] = (char)(o + 32);
        } else if (o == '-') {
            dst[w++] = '_';
        } else {
            dst[w++] = (char)o;
        }
    }
    dst[w] = '\0';
    WValue res = w_string_n_known_ascii(dst, w, 1);
    if (dst != stack_out) free(dst);
    return res;
}

static WValue w_base64_encode_fast(WValue data, int url_safe, int padded) {
    char sbuf6[6];
    const uint8_t *src;
    size_t n;
    if (w_is_bytes(data)) {
        WArray *a = w_as_array(data);
        src = (const uint8_t *)a->slots + a->start;
        n = (size_t)a->size;
    } else {
        const char *s;
        w_str_data(data, sbuf6, &s, &n);
        src = (const uint8_t *)s;
    }
    if (n == 0) return w_string_n_known_ascii("", 0, 1);
    size_t out_n = padded ? ((n + 2) / 3) * 4 : (n / 3) * 4 + (n % 3 ? (n % 3 + 1) : 0);
    uint8_t stack_dst[72];
    WString *ws = NULL;
    uint8_t *dst;
    if (out_n > W_SLAB_SSO2_MAX) {
        ws = (WString *)malloc(sizeof(WString) + out_n + 1);
        dst = (uint8_t *)ws->data;
    } else {
        dst = stack_dst;
    }
    const uint8_t *alpha = (const uint8_t *)(url_safe
        ? "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"
        : "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/");
    size_t i = 0, j = 0;
#if defined(__ARM_NEON) || defined(__ARM_NEON__)
    if (n >= 48) {
        uint8x16x4_t lut = vld1q_u8_x4(alpha);
        uint8x16_t mask3f = vdupq_n_u8(0x3F);
        while (i + 96 <= n) {
            uint8x16x3_t in0 = vld3q_u8(src + i);
            uint8x16x3_t in1 = vld3q_u8(src + i + 48);
            uint8x16x4_t out0, out1;
            out0.val[0] = vqtbl4q_u8(lut, vshrq_n_u8(in0.val[0], 2));
            out0.val[1] = vqtbl4q_u8(lut, vandq_u8(vorrq_u8(vshlq_n_u8(in0.val[0], 4), vshrq_n_u8(in0.val[1], 4)), mask3f));
            out0.val[2] = vqtbl4q_u8(lut, vandq_u8(vorrq_u8(vshlq_n_u8(in0.val[1], 2), vshrq_n_u8(in0.val[2], 6)), mask3f));
            out0.val[3] = vqtbl4q_u8(lut, vandq_u8(in0.val[2], mask3f));
            out1.val[0] = vqtbl4q_u8(lut, vshrq_n_u8(in1.val[0], 2));
            out1.val[1] = vqtbl4q_u8(lut, vandq_u8(vorrq_u8(vshlq_n_u8(in1.val[0], 4), vshrq_n_u8(in1.val[1], 4)), mask3f));
            out1.val[2] = vqtbl4q_u8(lut, vandq_u8(vorrq_u8(vshlq_n_u8(in1.val[1], 2), vshrq_n_u8(in1.val[2], 6)), mask3f));
            out1.val[3] = vqtbl4q_u8(lut, vandq_u8(in1.val[2], mask3f));
            vst4q_u8(dst + j, out0);
            vst4q_u8(dst + j + 64, out1);
            i += 96;
            j += 128;
        }
        while (i + 48 <= n) {
            uint8x16x3_t in = vld3q_u8(src + i);
            uint8x16x4_t out;
            out.val[0] = vqtbl4q_u8(lut, vshrq_n_u8(in.val[0], 2));
            out.val[1] = vqtbl4q_u8(lut, vandq_u8(vorrq_u8(vshlq_n_u8(in.val[0], 4), vshrq_n_u8(in.val[1], 4)), mask3f));
            out.val[2] = vqtbl4q_u8(lut, vandq_u8(vorrq_u8(vshlq_n_u8(in.val[1], 2), vshrq_n_u8(in.val[2], 6)), mask3f));
            out.val[3] = vqtbl4q_u8(lut, vandq_u8(in.val[2], mask3f));
            vst4q_u8(dst + j, out);
            i += 48;
            j += 64;
        }
    }
#endif
    while (i + 3 <= n) {
        uint32_t t = ((uint32_t)src[i] << 16) | ((uint32_t)src[i + 1] << 8) | (uint32_t)src[i + 2];
        dst[j]     = alpha[(t >> 18) & 0x3F];
        dst[j + 1] = alpha[(t >> 12) & 0x3F];
        dst[j + 2] = alpha[(t >> 6)  & 0x3F];
        dst[j + 3] = alpha[t & 0x3F];
        i += 3;
        j += 4;
    }
    if (i < n) {
        uint32_t t = (uint32_t)src[i] << 16;
        if (i + 1 < n) t |= (uint32_t)src[i + 1] << 8;
        dst[j]     = alpha[(t >> 18) & 0x3F];
        dst[j + 1] = alpha[(t >> 12) & 0x3F];
        if (i + 1 < n) {
            dst[j + 2] = alpha[(t >> 6) & 0x3F];
        } else if (padded) {
            dst[j + 2] = '=';
        }
        if (padded) {
            dst[j + 3] = '=';
        }
    }
    if (ws) {
        dst[out_n] = '\0';
        w_heap_string_set_meta(ws, (uint32_t)out_n, 1);
        return w_box_heap_str(ws);
    }
    return w_string_n_known_ascii((const char *)dst, out_n, 1);
}

static const uint8_t b64_dec_p1_std_20_5f[64] = {
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 63, 0, 0, 0, 64,
    53, 54, 55, 56, 57, 58, 59, 60, 61, 62, 0, 0, 0, 0, 0, 0,
    0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15,
    16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 0, 0, 0, 0, 0
};
static const uint8_t b64_dec_p1_url_20_5f[64] = {
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 63, 0, 0,
    53, 54, 55, 56, 57, 58, 59, 60, 61, 62, 0, 0, 0, 0, 0, 0,
    0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15,
    16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 0, 0, 0, 0, 64
};
static const uint8_t b64_dec_p1_60_7f[32] = {
    0, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41,
    42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 0, 0, 0, 0, 0
};

static inline int w_b64_decode_digit_p1(uint8_t b, int url_safe) {
    if ((uint8_t)(b - 0x20) < 64)
        return url_safe ? b64_dec_p1_url_20_5f[b - 0x20] : b64_dec_p1_std_20_5f[b - 0x20];
    if ((uint8_t)(b - 0x60) < 32)
        return b64_dec_p1_60_7f[b - 0x60];
    return 0;
}

static WValue w_base64_decode_fast(WValue text, int url_safe) {
    char sbuf6[6];
    const uint8_t *src;
    size_t n;
    if (w_is_bytes(text)) {
        WArray *a = w_as_array(text);
        src = (const uint8_t *)a->slots + a->start;
        n = (size_t)a->size;
    } else {
        const char *s;
        w_str_data(text, sbuf6, &s, &n);
        src = (const uint8_t *)s;
    }
    while (n > 0 && src[n - 1] == '=') n--;
    size_t out_n = (n * 3) / 4;
    WValue arr_v = w_array_new_uninit_sized(8, (int64_t)(out_n > 0 ? out_n : 1));
    WArray *out_arr = w_as_array(arr_v);
    out_arr->size = (int32_t)out_n;
    uint8_t *dst = (uint8_t *)out_arr->slots;
    size_t i = 0, j = 0;
#if defined(__ARM_NEON) || defined(__ARM_NEON__)
    if (n >= 64) {
        uint8x16x4_t tbl_lo = vld1q_u8_x4(url_safe ? b64_dec_p1_url_20_5f : b64_dec_p1_std_20_5f);
        uint8x16x2_t tbl_hi = vld1q_u8_x2(b64_dec_p1_60_7f);
        uint8x16_t v20 = vdupq_n_u8(0x20);
        uint8x16_t v60 = vdupq_n_u8(0x60);
        uint8x16_t v1  = vdupq_n_u8(1);
        uint8x16_t valid_min = vdupq_n_u8(0xFF);
        while (i + 64 <= n) {
            uint8x16x4_t in = vld4q_u8(src + i);
            uint8x16_t a_p1 = vorrq_u8(vqtbl4q_u8(tbl_lo, vsubq_u8(in.val[0], v20)),
                                       vqtbl2q_u8(tbl_hi, vsubq_u8(in.val[0], v60)));
            uint8x16_t b_p1 = vorrq_u8(vqtbl4q_u8(tbl_lo, vsubq_u8(in.val[1], v20)),
                                       vqtbl2q_u8(tbl_hi, vsubq_u8(in.val[1], v60)));
            uint8x16_t c_p1 = vorrq_u8(vqtbl4q_u8(tbl_lo, vsubq_u8(in.val[2], v20)),
                                       vqtbl2q_u8(tbl_hi, vsubq_u8(in.val[2], v60)));
            uint8x16_t d_p1 = vorrq_u8(vqtbl4q_u8(tbl_lo, vsubq_u8(in.val[3], v20)),
                                       vqtbl2q_u8(tbl_hi, vsubq_u8(in.val[3], v60)));
            uint8x16_t min_all = vminq_u8(vminq_u8(a_p1, b_p1), vminq_u8(c_p1, d_p1));
            valid_min = vminq_u8(valid_min, min_all);
            uint8x16_t a = vsubq_u8(a_p1, v1);
            uint8x16_t b = vsubq_u8(b_p1, v1);
            uint8x16_t c = vsubq_u8(c_p1, v1);
            uint8x16_t d = vsubq_u8(d_p1, v1);
            uint8x16x3_t out;
            out.val[0] = vorrq_u8(vshlq_n_u8(a, 2), vshrq_n_u8(b, 4));
            out.val[1] = vorrq_u8(vshlq_n_u8(b, 4), vshrq_n_u8(c, 2));
            out.val[2] = vorrq_u8(vshlq_n_u8(c, 6), d);
            vst3q_u8(dst + j, out);
            i += 64;
            j += 48;
        }
        if (__builtin_expect(vminvq_u8(valid_min) == 0, 0)) {
            w_raise(w_string(url_safe ? "base64url: invalid character" : "base64: invalid character"));
        }
    }
#endif
    while (i + 4 <= n) {
        int a = w_b64_decode_digit_p1(src[i],     url_safe) - 1;
        int b = w_b64_decode_digit_p1(src[i + 1], url_safe) - 1;
        int c = w_b64_decode_digit_p1(src[i + 2], url_safe) - 1;
        int d = w_b64_decode_digit_p1(src[i + 3], url_safe) - 1;
        if (__builtin_expect((a | b | c | d) < 0, 0)) {
            w_raise(w_string(url_safe ? "base64url: invalid character" : "base64: invalid character"));
        }
        uint32_t t = ((uint32_t)a << 18) | ((uint32_t)b << 12) | ((uint32_t)c << 6) | (uint32_t)d;
        dst[j]     = (uint8_t)((t >> 16) & 0xFF);
        dst[j + 1] = (uint8_t)((t >> 8)  & 0xFF);
        dst[j + 2] = (uint8_t)(t & 0xFF);
        i += 4;
        j += 3;
    }
    if (i < n) {
        int a = w_b64_decode_digit_p1(src[i], url_safe) - 1;
        int b = (i + 1 < n) ? (w_b64_decode_digit_p1(src[i + 1], url_safe) - 1) : 0;
        int c = (i + 2 < n) ? (w_b64_decode_digit_p1(src[i + 2], url_safe) - 1) : 0;
        if (__builtin_expect((a | b | c) < 0, 0)) {
            w_raise(w_string(url_safe ? "base64url: invalid character" : "base64: invalid character"));
        }
        uint32_t t = ((uint32_t)a << 18) | ((uint32_t)b << 12) | ((uint32_t)c << 6);
        if (j < out_n) dst[j++] = (uint8_t)((t >> 16) & 0xFF);
        if (j < out_n) dst[j++] = (uint8_t)((t >> 8)  & 0xFF);
        if (j < out_n) dst[j++] = (uint8_t)(t & 0xFF);
    }
    return arr_v;
}

static const uint8_t w_http_tchar_tbl[128] = {
    0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
    0,1,0,1,1,1,1,1,0,0,1,1,0,1,1,0, 1,1,1,1,1,1,1,1,1,1,0,0,0,0,0,0,
    0,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1, 1,1,1,1,1,1,1,1,1,1,1,0,0,0,1,1,
    1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1, 1,1,1,1,1,1,1,1,1,1,1,0,1,0,1,0
};

#if defined(__ARM_NEON) || defined(__ARM_NEON__)
static inline uint64_t w_http_mask16_nibbles(uint8x16_t mask) {
    return vget_lane_u64(vreinterpret_u64_u8(vshrn_n_u16(vreinterpretq_u16_u8(mask), 4)), 0);
}
#endif

static inline size_t w_http_field_end(const uint8_t *p, size_t n, size_t k) {
#if defined(__ARM_NEON) || defined(__ARM_NEON__)
    uint8x16_t v32  = vdupq_n_u8(32);
    uint8x16_t v9   = vdupq_n_u8(9);
    uint8x16_t v127 = vdupq_n_u8(127);
    while (k + 16 <= n) {
        uint8x16_t v = vld1q_u8(p + k);
        uint8x16_t controls = vbicq_u8(vcltq_u8(v, v32), vceqq_u8(v, v9));
        uint8x16_t event = vorrq_u8(controls, vceqq_u8(v, v127));
        uint64_t m = w_http_mask16_nibbles(event);
        if (m == 0) {
            k += 16;
            continue;
        }
        k += (unsigned)__builtin_ctzll(m) >> 2;
        return (k + 1 < n && p[k] == '\r' && p[k + 1] == '\n') ? k : SIZE_MAX;
    }
#endif
    while (k + 1 < n) {
        uint8_t b = p[k];
        if (b == '\r' && p[k + 1] == '\n') return k;
        if (!(b == 9 || (b >= 32 && b != 127))) return SIZE_MAX;
        k++;
    }
    return SIZE_MAX;
}

static inline size_t w_http_name_colon(const uint8_t *p, size_t n, size_t k) {
    size_t start = k;
#if defined(__ARM_NEON) || defined(__ARM_NEON__)
    if (k + 16 <= n) {
        uint8x16_t v = vld1q_u8(p + k);
        uint8x16_t lower = vorrq_u8(v, vdupq_n_u8(32));
        uint8x16_t letters = vcleq_u8(vsubq_u8(lower, vdupq_n_u8('a')), vdupq_n_u8(25));
        uint8x16_t digits = vcleq_u8(vsubq_u8(v, vdupq_n_u8('0')), vdupq_n_u8(9));
        uint8x16_t good = vorrq_u8(vorrq_u8(letters, digits), vceqq_u8(v, vdupq_n_u8('-')));
        uint64_t m = w_http_mask16_nibbles(vmvnq_u8(good));
        if (m != 0) {
            unsigned adv = (unsigned)__builtin_ctzll(m) >> 2;
            k += adv;
            if (p[k] == ':' && k != start) return k;
        } else {
            k += 16;
        }
    }
#endif
    while (k < n && p[k] != ':') {
        uint8_t b = p[k];
        if (b >= 128 || !w_http_tchar_tbl[b]) return SIZE_MAX;
        k++;
    }
    return (k < n && k != start) ? k : SIZE_MAX;
}

static WValue w_http_parse_fast(WValue raw) {
    char sbuf6[6];
    const char *s;
    size_t n;
    w_str_data(raw, sbuf6, &s, &n);
    const uint8_t *p = (const uint8_t *)s;
    if (n < 16) return W_NIL;
    if (p[0] != 'H' || p[1] != 'T' || p[2] != 'T' || p[3] != 'P' ||
        p[4] != '/' || p[5] != '1' || p[6] != '.' ||
        (p[7] != '1' && p[7] != '0') || p[8] != ' ')
        return W_NIL;
    unsigned d0 = (unsigned)(p[9] - '0');
    unsigned d1 = (unsigned)(p[10] - '0');
    unsigned d2 = (unsigned)(p[11] - '0');
    if (d0 > 9 || d1 > 9 || d2 > 9) return W_NIL;
    int status = (int)(d0 * 100 + d1 * 10 + d2);
    if (status < 200 || status == 204 || status == 304) return W_NIL;
    size_t line_end;
    if (p[12] == ' ') {
        line_end = w_http_field_end(p, n, 13);
        if (line_end == SIZE_MAX) return W_NIL;
    } else if (p[12] == '\r' && p[13] == '\n') {
        line_end = 12;
    } else {
        return W_NIL;
    }
    size_t pos = line_end + 2;
    int has_cl = 0;
    size_t expected_len = 0;
    while (pos + 1 < n) {
        if (p[pos] == '\r' && p[pos + 1] == '\n') {
            size_t separator = pos - 2;
            if (separator >= 262143 || line_end >= 65535) return W_NIL;
            size_t body_len = n - (pos + 2);
            if (has_cl && body_len != expected_len) return W_NIL;
            int is_11 = (p[7] == '1') ? 1 : 0;
            int is_ok = (line_end == 15 && p[13] == 'O' && p[14] == 'K') ? 1 : 0;
            int64_t packed = (int64_t)status | ((int64_t)is_11 << 10) |
                             ((int64_t)is_ok << 11) | ((int64_t)line_end << 12) |
                             ((int64_t)separator << 28);
            return w_int(packed);
        }
        size_t colon = w_http_name_colon(p, n, pos);
        if (colon == SIZE_MAX) return W_NIL;
        size_t key_len = colon - pos;
        size_t k = colon + 1;
        while (k < n && (p[k] == ' ' || p[k] == '\t')) k++;
        size_t val_start = k;
        size_t next_crlf = w_http_field_end(p, n, val_start);
        if (next_crlf == SIZE_MAX) return W_NIL;
        size_t val_end = next_crlf;
        while (val_end > val_start && (p[val_end - 1] == ' ' || p[val_end - 1] == '\t'))
            val_end--;
        if (key_len == 14 && (p[pos] | 0x20) == 'c' && (p[pos + 8] | 0x20) == 'l') {
            static const char cl_name[14] = "content-length";
            int match = 1;
            for (size_t m = 0; m < 14; m++) {
                if ((p[pos + m] | 0x20) != cl_name[m]) { match = 0; break; }
            }
            if (match) {
                if (has_cl || val_start == val_end) return W_NIL;
                /* More than 18 digits could wrap size_t and compare equal to
                 * the body length; leave those to the reader-based framing. */
                if (val_end - val_start > 18) return W_NIL;
                size_t cl_v = 0;
                for (size_t m = val_start; m < val_end; m++) {
                    unsigned d = (unsigned)(p[m] - '0');
                    if (d > 9) return W_NIL;
                    cl_v = cl_v * 10 + d;
                }
                has_cl = 1;
                expected_len = cl_v;
            }
        } else if (key_len == 17 && (p[pos] | 0x20) == 't') {
            static const char te_name[17] = "transfer-encoding";
            int match = 1;
            for (size_t m = 0; m < 17; m++) {
                if ((p[pos + m] | 0x20) != te_name[m]) { match = 0; break; }
            }
            if (match) return W_NIL;
        }
        pos = next_crlf + 2;
    }
    return W_NIL;
}

WValue w_string_take_byte_array(WValue bytes, WValue len_wv) {
    int64_t mode = w_as_int(len_wv);
    if (mode <= -8 && mode >= -14) {
        if (mode == -8)  return w_base64_encode_fast(bytes, 0, 1);
        if (mode == -9)  return w_base64_encode_fast(bytes, 1, 0);
        if (mode == -10) return w_base64_encode_fast(bytes, 1, 1);
        if (mode == -11) return w_base64_encode_fast(bytes, 0, 0);
        if (mode == -12) return w_base64_decode_fast(bytes, 0);
        if (mode == -13) return w_base64_decode_fast(bytes, 1);
        if (mode == -14) return w_http_parse_fast(bytes);
    }
    if (w_is_stringy(bytes) || w_is_rope(bytes)) {
        if (mode == -1) return w_string_ascii_case(bytes, 1);
        if (mode == -2) return w_string_ascii_case(bytes, 0);
        if (mode == -3) return w_string_ascii_case(bytes, 2);
        if (mode == -4) return w_string_ascii_case(bytes, 3);
        if (mode == -5) return w_string_ascii_squeeze(bytes);
        if (mode == -6) return w_string_ascii_camelize(bytes);
        if (mode == -7) return w_string_ascii_underscore(bytes);
    }
    WArray *a = as_bytes_arr(bytes);
    int64_t len = mode;
    if (len < 0) len = 0;
    if (len >= a->size || a->start != 0 || (a->flags & W_FLAG_OWNED) == 0)
        return w_string_n((const char *)a->slots + a->start, (size_t)len);
    char *buf = (char *)a->slots;
    buf[len] = '\0';
    a->slots = NULL;
    a->size = 0;
    a->cap = 0;
    return w_string_take(buf, (size_t)len);
}

/* ---- Goroutine Arena + Scheduler ---- */

/* Suppress macOS deprecation warnings for ucontext */
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"

static size_t g_cached_page_size = 0;
static size_t g_cached_stack_size = 0;
static size_t g_cached_slot_size = 0;

/* Goroutine stack size: W_GOROUTINE_STACK_SIZE unless a host asked for more
 * before the first spawn (w_goroutine_stack_size_hint). The tree-walking
 * interpreter runs each `go` body as a goroutine and its recursive evaluator
 * needs an order of magnitude more stack per source-level call than compiled
 * code; the arena is a PROT_NONE reservation, so a larger slot costs address
 * space, not memory. */
static size_t g_stack_size_hint = 0;

static inline size_t g_align_up(size_t v, size_t a) { return (v + a - 1) & ~(a - 1); }
static inline size_t g_requested_stack_size(void) {
    return g_stack_size_hint > (size_t)W_GOROUTINE_STACK_SIZE ? g_stack_size_hint : (size_t)W_GOROUTINE_STACK_SIZE;
}
static inline size_t g_page_size(void) {
    if (__builtin_expect(g_cached_page_size != 0, 1)) return g_cached_page_size;
    return (size_t)sysconf(_SC_PAGESIZE);
}
static inline size_t g_stack_size(void) {
    if (__builtin_expect(g_cached_stack_size != 0, 1)) return g_cached_stack_size;
    return g_align_up(g_requested_stack_size(), g_page_size());
}
static inline size_t g_slot_size(void) {
    if (__builtin_expect(g_cached_slot_size != 0, 1)) return g_cached_slot_size;
    return g_stack_size() + g_page_size();
}

/* ---- Per-goroutine unwind state ----
 * Exception frames, block-return frames and the cleanup stack are
 * thread-locals, but a goroutine that parks inside a rescue region (a
 * Channel#send under `begin`, say) hands the thread back with its frames
 * still linked, and whoever runs next pushes and pops on top of them: a
 * raise then longjmps into the wrong context. The scheduler therefore swaps
 * the three around every switch into a goroutine (g_unwind_enter /
 * g_unwind_leave), so each context only ever sees its own frames; a fresh
 * goroutine starts empty.
 *
 * While the goroutine is switched out its state is parked in the top
 * W_GOROUTINE_UNWIND_RESERVE bytes of its own stack slot, above the initial
 * stack pointer (w_goroutine_spawn makes the context below it). It is cold —
 * touched only at a switch — so it stays out of WGoroutine, whose 256-byte
 * layout holds the scheduler's hot fields. The slot travels with the stack:
 * a pooled goroutine keeps its cleanup-stack allocation for reuse. */
typedef struct WGoroutineUnwind {
    WExceptionFrame *exception_stack;
    WBlockReturnFrame *block_return_stack;
    WCleanupEntry *cleanup_stack;
    int cleanup_top;
    WValue *ctx_locals;      /* context locals, shared with the spawning context */
} WGoroutineUnwind;

/* ---- Context locals (core ThreadLocal) ----
 * A small array of WValues per execution context: each OS thread (main, a
 * Thread.new thread) gets its own, and a goroutine shares the array of the
 * context that spawned it, swapped in and out with its unwind state. So a
 * value set on a thread is seen by every goroutine that thread spawns, even
 * when an M:P worker runs it on another OS thread. Slots are numbered by
 * ThreadLocal.new (w_ctx_local_alloc) and start nil in every new thread. */
#define W_CTX_LOCALS_MAX 256
static __thread WValue *g_ctx_locals = NULL;
static _Atomic int64_t g_ctx_locals_next = 0;

static WValue *w_ctx_locals(void) {
    if (__builtin_expect(g_ctx_locals != NULL, 1)) return g_ctx_locals;
    WValue *a = malloc(sizeof(WValue) * W_CTX_LOCALS_MAX);
    for (int i = 0; i < W_CTX_LOCALS_MAX; i++) a[i] = W_NIL;
    g_ctx_locals = a;
    return a;
}

/* Reserve n consecutive slots; returns the first index. */
WValue w_ctx_local_alloc(WValue n) {
    int64_t k = w_is_int(n) ? w_as_int(n) : 1;
    if (k < 1) k = 1;
    int64_t base = atomic_fetch_add(&g_ctx_locals_next, k);
    if (base + k > W_CTX_LOCALS_MAX) w_raise(w_string("ThreadLocal: out of context-local slots"));
    return w_int(base);
}

WValue w_ctx_local_get(WValue i) {
    int64_t k = w_as_int(i);
    if ((uint64_t)k >= W_CTX_LOCALS_MAX) return W_NIL;
    return w_ctx_locals()[k];
}

WValue w_ctx_local_set(WValue i, WValue v) {
    int64_t k = w_as_int(i);
    if ((uint64_t)k < W_CTX_LOCALS_MAX) w_ctx_locals()[k] = v;
    return v;
}

#define W_GOROUTINE_UNWIND_RESERVE 48  /* >= sizeof(WGoroutineUnwind), multiple of 16 */
_Static_assert(sizeof(WGoroutineUnwind) <= W_GOROUTINE_UNWIND_RESERVE, "goroutine unwind slot too small");

static inline WGoroutineUnwind *g_unwind_slot(WGoroutine *g) {
    return (WGoroutineUnwind *)((char *)g->stack_base + g_stack_size() - W_GOROUTINE_UNWIND_RESERVE);
}

typedef struct WUnwindSave {
    WExceptionFrame *exception_stack;
    WBlockReturnFrame *block_return_stack;
    WCleanupEntry *cleanup_stack;
    int cleanup_top;
    WValue *ctx_locals;
} WUnwindSave;

static inline void g_unwind_enter(WGoroutine *g, WUnwindSave *save) {
    WGoroutineUnwind *u = g_unwind_slot(g);
    save->exception_stack = w_exception_stack;
    save->block_return_stack = w_block_return_stack;
    save->cleanup_stack = g_cleanup_stack;
    save->cleanup_top = g_cleanup_top;
    w_exception_stack = u->exception_stack;
    w_block_return_stack = u->block_return_stack;
    g_cleanup_stack = u->cleanup_stack;
    g_cleanup_top = u->cleanup_top;
    save->ctx_locals = g_ctx_locals;
    g_ctx_locals = u->ctx_locals;
}

static inline void g_unwind_leave(WGoroutine *g, const WUnwindSave *save) {
    WGoroutineUnwind *u = g_unwind_slot(g);
    u->exception_stack = w_exception_stack;
    u->block_return_stack = w_block_return_stack;
    u->cleanup_stack = g_cleanup_stack;
    u->cleanup_top = g_cleanup_top;
    w_exception_stack = save->exception_stack;
    w_block_return_stack = save->block_return_stack;
    g_cleanup_stack = save->cleanup_stack;
    g_cleanup_top = save->cleanup_top;
    u->ctx_locals = g_ctx_locals;
    g_ctx_locals = save->ctx_locals;
}

typedef struct {
    void *base;
    size_t total_size;
    int next_slot;
    pthread_mutex_t lock;
} GArena;

static GArena g_arena;
static int g_arena_initialized = 0;
static pthread_once_t g_arena_once = PTHREAD_ONCE_INIT;

/* Goroutine pool: recycle entire WGoroutine (struct + stack) as a unit.
 * Per-thread free list eliminates mutex contention on the hot path.
 * Global overflow list handles cross-thread recycling. */
#define W_GPOOL_LOCAL_MAX  2048  /* per-thread cache */
#define W_GPOOL_GLOBAL_MAX 8192  /* shared overflow */

static __thread WGoroutine *g_local_pool[W_GPOOL_LOCAL_MAX];
static __thread int g_local_pool_count = 0;

static WGoroutine *g_global_pool[W_GPOOL_GLOBAL_MAX];
static int g_global_pool_count = 0;
static pthread_mutex_t g_global_pool_lock = PTHREAD_MUTEX_INITIALIZER;

/* Legacy stack-only free list — kept for backward compat */
#define W_STACK_FREELIST_MAX 4096
static void *g_stack_freelist[W_STACK_FREELIST_MAX];
static int g_stack_freelist_count = 0;
static pthread_mutex_t g_stack_freelist_lock = PTHREAD_MUTEX_INITIALIZER;

/* Ask for goroutine stacks of at least `bytes` (see g_stack_size_hint).
 * Effective only before the stack arena exists — the first spawn fixes the
 * slot size for the process; returns whether the request took. */
WValue w_goroutine_stack_size_hint(WValue bytes) {
    if (g_arena_initialized || !w_is_int(bytes) || w_as_int(bytes) <= 0) return W_FALSE;
    g_stack_size_hint = (size_t)w_as_int(bytes);
    return W_TRUE;
}

static void g_arena_init_once(void) {
    g_cached_page_size = (size_t)sysconf(_SC_PAGESIZE);
    g_cached_stack_size = g_align_up(g_requested_stack_size(), g_cached_page_size);
    g_cached_slot_size = g_cached_stack_size + g_cached_page_size;
    size_t total = g_cached_slot_size * W_MAX_GOROUTINES;
    g_arena.base = mmap(NULL, total, PROT_NONE, MAP_PRIVATE | MAP_ANON, -1, 0);
    if (g_arena.base == MAP_FAILED) {
        die("goroutine arena: mmap failed");
    }
    g_arena.total_size = total;
    g_arena.next_slot = 0;
    pthread_mutex_init(&g_arena.lock, NULL);
    g_arena_initialized = 1;
}

static void g_arena_init(void) {
    pthread_once(&g_arena_once, g_arena_init_once);
}

static void g_stack_free(void *stack) {
    pthread_mutex_lock(&g_stack_freelist_lock);
    if (g_stack_freelist_count < W_STACK_FREELIST_MAX) {
        g_stack_freelist[g_stack_freelist_count++] = stack;
    }
    pthread_mutex_unlock(&g_stack_freelist_lock);
}

/* Return a dead goroutine to the pool (struct + stack stay paired) */
static void g_pool_return(WGoroutine *g) {
    /* Try thread-local cache first (no lock) */
    if (g_local_pool_count < W_GPOOL_LOCAL_MAX) {
        g_local_pool[g_local_pool_count++] = g;
        return;
    }
    /* Overflow to global pool */
    pthread_mutex_lock(&g_global_pool_lock);
    if (g_global_pool_count < W_GPOOL_GLOBAL_MAX) {
        g_global_pool[g_global_pool_count++] = g;
    } else {
        /* Pool full — fall back to stack-only recycling */
        free(g_unwind_slot(g)->cleanup_stack);
        g_stack_free(g->stack_base);
        free(g);
    }
    pthread_mutex_unlock(&g_global_pool_lock);
}

/* Get a recycled goroutine from the pool, or NULL if empty */
static WGoroutine *g_pool_get(void) {
    /* Try thread-local cache first (no lock) */
    if (g_local_pool_count > 0) {
        return g_local_pool[--g_local_pool_count];
    }
    /* Try global pool — steal a batch to refill local cache */
    pthread_mutex_lock(&g_global_pool_lock);
    if (g_global_pool_count > 0) {
        int steal = g_global_pool_count < 32 ? g_global_pool_count : 32;
        for (int i = 0; i < steal; i++) {
            g_local_pool[i] = g_global_pool[--g_global_pool_count];
        }
        g_local_pool_count = steal;
        pthread_mutex_unlock(&g_global_pool_lock);
        return g_local_pool[--g_local_pool_count];
    }
    pthread_mutex_unlock(&g_global_pool_lock);
    return NULL;
}

static void *g_arena_alloc_stack(void) {
    /* Try free list first */
    pthread_mutex_lock(&g_stack_freelist_lock);
    if (g_stack_freelist_count > 0) {
        void *stack = g_stack_freelist[--g_stack_freelist_count];
        pthread_mutex_unlock(&g_stack_freelist_lock);
        return stack;
    }
    pthread_mutex_unlock(&g_stack_freelist_lock);

    /* Allocate new slot */
    pthread_mutex_lock(&g_arena.lock);
    if (g_arena.next_slot >= W_MAX_GOROUTINES) {
        pthread_mutex_unlock(&g_arena.lock);
        return NULL;
    }
    int slot = g_arena.next_slot++;
    pthread_mutex_unlock(&g_arena.lock);

    size_t ss = g_slot_size();
    size_t gs = g_page_size();
    size_t stk = g_stack_size();
    char *slot_base = (char *)g_arena.base + (size_t)slot * ss;
    char *stack_base = slot_base + gs;
    if (mprotect(stack_base, stk, PROT_READ | PROT_WRITE) != 0) {
        return NULL;
    }
    return stack_base;
}

/* ---- Lightweight context switch (no syscalls) ---- */

#if defined(__aarch64__) && !defined(W_CONTEXT_UCONTEXT)

/* ARM64 context switch: save callee-saved regs to *save, restore from *restore.
 * Zero syscalls — just register saves/restores + stack pointer swap.
 * Replaces swapcontext() which does 3-4 syscalls (sigprocmask, sigaltstack, getrlimit). */
void __attribute__((naked)) w_ctx_swap(WContext *save, WContext *restore) {
    __asm__ volatile(
        /* Save callee-saved registers to save (x0) */
        "stp x19, x20, [x0, #0]\n"
        "stp x21, x22, [x0, #16]\n"
        "stp x23, x24, [x0, #32]\n"
        "stp x25, x26, [x0, #48]\n"
        "stp x27, x28, [x0, #64]\n"
        "stp x29, x30, [x0, #80]\n"
        "mov x9, sp\n"
        "str x9, [x0, #96]\n"
        /* Save callee-saved NEON registers */
        "stp d8,  d9,  [x0, #104]\n"
        "stp d10, d11, [x0, #120]\n"
        "stp d12, d13, [x0, #136]\n"
        "stp d14, d15, [x0, #152]\n"

        /* Restore callee-saved registers from restore (x1) */
        "ldp x19, x20, [x1, #0]\n"
        "ldp x21, x22, [x1, #16]\n"
        "ldp x23, x24, [x1, #32]\n"
        "ldp x25, x26, [x1, #48]\n"
        "ldp x27, x28, [x1, #64]\n"
        "ldp x29, x30, [x1, #80]\n"
        "ldr x9, [x1, #96]\n"
        "mov sp, x9\n"
        "ldp d8,  d9,  [x1, #104]\n"
        "ldp d10, d11, [x1, #120]\n"
        "ldp d12, d13, [x1, #136]\n"
        "ldp d14, d15, [x1, #152]\n"

        "ret\n"  /* jumps to restored x30 (link register) */
    );
}

/* Set up initial context: when switched to, starts executing entry() on the given stack. */
static inline void w_ctx_make(WContext *ctx, void *stack, size_t stack_size, void (*entry)(void)) {
    /* ARM64 stack grows downward, must be 16-byte aligned */
    uintptr_t sp = ((uintptr_t)stack + stack_size) & ~15UL;
    ctx->sp = sp;
    ctx->x30 = (uint64_t)entry;  /* LR = entry point; ret in w_ctx_swap jumps here */
    ctx->x29 = 0;                /* frame pointer = NULL (top of call chain) */
}

#elif defined(__x86_64__) && !defined(W_CONTEXT_UCONTEXT)

/* x86_64 context switch following Boost.Context's proven pattern.
 * Save callee-saved regs + MXCSR + x87 CW on the STACK (not a struct),
 * swap stack pointers, restore from the new stack.
 * The WContext struct just holds the stack pointer. */
void __attribute__((naked, noinline)) w_ctx_swap(WContext *save, WContext *restore) {
    __asm__ volatile(
        /* Save callee-saved registers + FP control state onto current stack.
         * Following Boost.Context: save MXCSR + x87 FCW for OpenSSL SSE state. */
        "pushq %%rbp\n"
        "pushq %%rbx\n"
        "pushq %%r15\n"
        "pushq %%r14\n"
        "pushq %%r13\n"
        "pushq %%r12\n"
        /* Save MXCSR (4 bytes) + x87 FCW (2 bytes) packed into 8 bytes on stack */
        "subq $8, %%rsp\n"
        "stmxcsr 4(%%rsp)\n"
        "fnstcw (%%rsp)\n"

        /* Save current stack pointer */
        "movq %%rsp, 0(%%rdi)\n"

        /* Restore target stack pointer */
        "movq 0(%%rsi), %%rsp\n"

        /* Restore MXCSR + x87 FCW */
        "fldcw (%%rsp)\n"
        "ldmxcsr 4(%%rsp)\n"
        "addq $8, %%rsp\n"

        /* Restore callee-saved registers */
        "popq %%r12\n"
        "popq %%r13\n"
        "popq %%r14\n"
        "popq %%r15\n"
        "popq %%rbx\n"
        "popq %%rbp\n"

        /* Return to new context */
        "ret\n"
        ::: "memory"
    );
}

static void w_ctx_make(WContext *ctx, void *stack, size_t stack_size, void (*entry)(void)) {
    uintptr_t sp = ((uintptr_t)stack + stack_size) & ~15UL;
    /* Stack frame must match what w_ctx_swap pushes:
     *   [MXCSR+FCW: 8 bytes] [r12] [r13] [r14] [r15] [rbx] [rbp] [ret_addr]
     * That's 8 pushes = 64 bytes. After restore (pop FP + 6 regs + ret = 64 bytes),
     * entry sees rsp = initial_sp + 64. Need (initial_sp + 64) % 16 == 8.
     * 64 % 16 == 0, so initial_sp must be 8 mod 16. Start from 0mod16 top - 8. */
    sp -= 8; /* alignment padding: now 8 mod 16 */
    sp -= 8; *(uint64_t *)sp = (uint64_t)entry; /* return address = entry point */
    sp -= 8; *(uint64_t *)sp = 0;               /* rbp = 0 */
    sp -= 8; *(uint64_t *)sp = 0;               /* rbx = 0 */
    sp -= 8; *(uint64_t *)sp = 0;               /* r15 = 0 */
    sp -= 8; *(uint64_t *)sp = 0;               /* r14 = 0 */
    sp -= 8; *(uint64_t *)sp = 0;               /* r13 = 0 */
    sp -= 8; *(uint64_t *)sp = 0;               /* r12 = 0 */
    /* MXCSR (default 0x1F80) + x87 FCW (default 0x037F) packed into 8 bytes */
    sp -= 8;
    *(uint16_t *)(sp) = 0x037F;       /* x87 FCW */
    *(uint32_t *)(sp + 4) = 0x1F80;   /* MXCSR */
    memset(ctx, 0, sizeof(*ctx));
    ctx->rsp = sp;
}

#else
/* Fallback: ucontext (with syscall overhead) */
#define w_ctx_swap(save, restore) swapcontext((save), (restore))
/* w_ctx_make: use getcontext + makecontext */
#endif

/* Simple cooperative scheduler: per-thread run queue + current goroutine.
 * In cooperative mode, each thread uses its own TLS queue (no locking).
 * In M:P mode, we switch to a shared global queue protected by g_sched_lock. */
static __thread WGoroutine *g_run_queue_head = NULL;
static __thread WGoroutine *g_run_queue_tail = NULL;
static __thread int g_coop_live_goroutines = 0;
__thread WGoroutine *g_current = NULL;
__thread WContext g_scheduler_ctx;

/* Shared global queue for M:P mode (NOT __thread) */
static WGoroutine *g_shared_queue_head = NULL;
static WGoroutine *g_shared_queue_tail = NULL;
static pthread_mutex_t g_sched_lock = PTHREAD_MUTEX_INITIALIZER;
/* Lock-free fast path for cooperative (single-threaded) scheduler.
 * The mutex is only needed when the M:P scheduler is active. */
static _Atomic int g_mp_scheduler_active = 0;
static volatile int g_scheduler_initialized = 0;
static pthread_once_t g_scheduler_once = PTHREAD_ONCE_INIT;
static WProcessor g_processors[W_MAX_PROCESSORS];
static int g_num_processors = 0;
static _Atomic int g_scheduler_active = 0;

static pthread_mutex_t g_debug_goroutines_lock = PTHREAD_MUTEX_INITIALIZER;
static WGoroutine *g_debug_goroutines[W_MAX_GOROUTINES];
static int g_debug_goroutine_count = 0;
static volatile sig_atomic_t g_scheduler_dump_requested = 0;

static const char *g_state_name(GState state) {
    switch (state) {
        case G_IDLE: return "idle";
        case G_RUNNABLE: return "runnable";
        case G_RUNNING: return "running";
        case G_WAITING: return "waiting";
        case G_DEAD: return "dead";
        case G_YIELDING: return "yielding";
        case G_PARKING: return "parking";
        case G_WAKING: return "waking";
        case G_NOTIFIED: return "notified";
        case G_WAKING_PARKED: return "waking-parked";
    }
    return "unknown";
}

static void g_debug_register_goroutine(WGoroutine *g) {
    pthread_mutex_lock(&g_debug_goroutines_lock);
    if (g_debug_goroutine_count < W_MAX_GOROUTINES) {
        g_debug_goroutines[g_debug_goroutine_count++] = g;
    }
    pthread_mutex_unlock(&g_debug_goroutines_lock);
}

static inline int g_mark_queued(WGoroutine *g) {
    int expected = 0;
    return atomic_compare_exchange_strong_explicit(&g->queued, &expected, 1,
        memory_order_acq_rel, memory_order_relaxed);
}

static inline void g_mark_dequeued(WGoroutine *g) {
    atomic_store_explicit(&g->queued, 0, memory_order_relaxed);
}

static inline void g_claim_running(WGoroutine *g) {
    GState expected = G_RUNNABLE;
    if (!atomic_compare_exchange_strong_explicit(&g->state, &expected, G_RUNNING,
            memory_order_acquire, memory_order_relaxed))
        die("scheduler dequeued a goroutine without runnable ownership");
}

/* Cooperative queues have one execution owner. There is no competing runner
 * to arbitrate here; retain the publication check without a CAS transaction. */
static inline void g_claim_running_local(WGoroutine *g) {
    /* w_scheduler_run can also drain the shared queue when M:P is active. */
    if (atomic_load_explicit(&g_mp_scheduler_active, memory_order_relaxed)) {
        g_claim_running(g);
        return;
    }
    if (atomic_load_explicit(&g->state, memory_order_acquire) != G_RUNNABLE)
        die("local scheduler dequeued a goroutine without runnable ownership");
    atomic_store_explicit(&g->state, G_RUNNING, memory_order_relaxed);
}

/* 1: caller owns enqueue; -1: caller owns recycling; 0: park ownership was
 * handed off and the caller must no longer inspect this goroutine. */
static inline int g_after_switch(WGoroutine *g) {
    GState state = atomic_load_explicit(&g->state, memory_order_acquire);
    if (state == G_YIELDING) {
        atomic_store_explicit(&g->state, G_RUNNABLE, memory_order_release);
        return 1;
    }
    if (state == G_DEAD) return -1;
    return g_commit_park(g);
}

static void g_scheduler_debug_signal_handler(int signum) {
    (void)signum;
    g_scheduler_dump_requested = 1;
}

WValue w_scheduler_install_debug_signal(void) {
#ifdef SIGUSR1
    struct sigaction sa;
    memset(&sa, 0, sizeof(sa));
    sa.sa_handler = g_scheduler_debug_signal_handler;
    sigemptyset(&sa.sa_mask);
    sa.sa_flags = SA_RESTART;
    sigaction(SIGUSR1, &sa, NULL);
#endif
    return W_NIL;
}

static void g_scheduler_maybe_dump(const char *where) {
    if (!g_scheduler_dump_requested) return;
    if (!__sync_bool_compare_and_swap(&g_scheduler_dump_requested, 1, 0)) return;

    int idle = 0, runnable = 0, running = 0, waiting = 0, dead = 0, queued = 0;
    int64_t now = __w_clock_ticks_raw();

    pthread_mutex_lock(&g_debug_goroutines_lock);
    for (int i = 0; i < g_debug_goroutine_count; i++) {
        WGoroutine *g = g_debug_goroutines[i];
        if (g->queued) queued++;
        switch (g->state) {
            case G_IDLE: idle++; break;
            case G_RUNNABLE: runnable++; break;
            case G_RUNNING: running++; break;
            case G_WAITING: waiting++; break;
            case G_DEAD: dead++; break;
            case G_YIELDING: running++; break;
            case G_PARKING: case G_WAKING: case G_NOTIFIED:
            case G_WAKING_PARKED: waiting++; break;
        }
    }

    pthread_mutex_lock(&g_sched_lock);
    int shared_depth = 0;
    for (WGoroutine *g = g_shared_queue_head; g; g = g->next) shared_depth++;
    pthread_mutex_unlock(&g_sched_lock);

    fprintf(stderr,
        "\n[scheduler dump:%s] goroutines=%d idle=%d runnable=%d running=%d waiting=%d dead=%d queued=%d "
        "shared_queue=%d mp=%d processors=%d\n",
        where, g_debug_goroutine_count, idle, runnable, running, waiting, dead,
        queued, shared_depth, g_mp_scheduler_active, g_num_processors);

    for (int i = 0; i < g_num_processors; i++) {
        uint64_t head = atomic_load_explicit(&g_processors[i].local_head, memory_order_acquire);
        uint64_t depth = atomic_load_explicit(&g_processors[i].local_tail, memory_order_acquire) - head;
        if (depth > W_LOCAL_QUEUE_MAX) depth = W_LOCAL_QUEUE_MAX;
        fprintf(stderr, "  processor %d active=%d local_queue=%llu\n",
                g_processors[i].id, g_processors[i].active, (unsigned long long)depth);
    }

    int shown = 0;
    for (int i = 0; i < g_debug_goroutine_count && shown < 64; i++) {
        WGoroutine *g = g_debug_goroutines[i];
        if (g->state != G_WAITING) continue;
        int64_t ms_left = -1;
        if (g->wait_deadline_ticks > 0) {
            ms_left = w_deadline_timeout_ms(g->wait_deadline_ticks, 0);
            if (now >= g->wait_deadline_ticks) ms_left = 0;
        }
        fprintf(stderr,
            "  waiting[%d] g=%p fd=%d events=%d deadline_ms=%lld timed_out=%d linked=%d\n",
            shown, (void *)g, g->wait_fd, g->wait_events,
            (long long)ms_left, g->wait_timed_out, g->deadline_linked);
        shown++;
    }
    shown = 0;
    for (int i = 0; i < g_debug_goroutine_count && shown < 16; i++) {
        WGoroutine *g = g_debug_goroutines[i];
        if (g->state != G_RUNNABLE || g->queued) continue;
        fprintf(stderr, "  stranded_runnable[%d] g=%p fd=%d events=%d\n",
                shown, (void *)g, g->wait_fd, g->wait_events);
        shown++;
    }
    pthread_mutex_unlock(&g_debug_goroutines_lock);
    fflush(stderr);
}

static inline void g_enqueue_local_claimed(WGoroutine *g) {
    g->next = NULL;
    if (g_run_queue_tail) g_run_queue_tail->next = g;
    else g_run_queue_head = g;
    g_run_queue_tail = g;
}

static inline void g_enqueue_claimed(WGoroutine *g) {
    g->next = NULL;
    if (g_mp_scheduler_active) {
        /* M:P mode: push to shared queue so any worker can pick it up */
        pthread_mutex_lock(&g_sched_lock);
        if (g_shared_queue_tail) {
            g_shared_queue_tail->next = g;
        } else {
            g_shared_queue_head = g;
        }
        g_shared_queue_tail = g;
        pthread_mutex_unlock(&g_sched_lock);
    } else {
        /* Cooperative mode: push to per-thread TLS queue (no lock needed) */
        g_enqueue_local_claimed(g);
    }
}

static inline void g_enqueue(WGoroutine *g) {
    if (atomic_load_explicit(&g_mp_scheduler_active, memory_order_relaxed)) {
        if (!g_mark_queued(g)) return;
        g_enqueue_claimed(g);
    } else {
        /* Only this thread accesses its cooperative run queue. Other threads
         * must publish a wake to its owner, never enqueue into this TLS list. */
        if (atomic_load_explicit(&g->queued, memory_order_relaxed)) return;
        atomic_store_explicit(&g->queued, 1, memory_order_relaxed);
        g_enqueue_local_claimed(g);
    }
}

static inline WGoroutine *g_dequeue(void) {
    if (g_mp_scheduler_active) {
        /* M:P mode: pop from shared queue */
        pthread_mutex_lock(&g_sched_lock);
        WGoroutine *g = g_shared_queue_head;
        if (g) {
            g_shared_queue_head = g->next;
            if (!g_shared_queue_head) g_shared_queue_tail = NULL;
            g->next = NULL;
            g_mark_dequeued(g);
        }
        pthread_mutex_unlock(&g_sched_lock);
        return g;
    } else {
        /* Cooperative mode: pop from per-thread TLS queue */
        WGoroutine *g = g_run_queue_head;
        if (g) {
            g_run_queue_head = g->next;
            if (!g_run_queue_head) g_run_queue_tail = NULL;
            g->next = NULL;
            g_mark_dequeued(g);
        }
        return g;
    }
}

/* Forward declarations for cap metrics */
void w_goroutine_count_inc(void);
void w_goroutine_count_dec(void);

static void g_body_entry(void) {
    WGoroutine *g = g_current;

    /* Each goroutine gets its own exception stack */
    w_exception_stack = NULL;

    WClosure *cl = (WClosure *)w_as_ptr(g->closure);
    typedef WValue (*fn0_t)(WValue *);
    g->result = ((fn0_t)cl->fn_ptr)(cl->captures);
    atomic_store_explicit(&g->state, G_DEAD, memory_order_release);
    if (!p_current && g_coop_live_goroutines > 0) g_coop_live_goroutines--;
    w_goroutine_count_dec();

    /* Return to scheduler */
    w_ctx_swap(&g->ctx, &g_scheduler_ctx);
}

WValue w_goroutine_spawn(WValue closure) {
    if (__builtin_expect(!g_scheduler_initialized, 0)) w_scheduler_init();
    if (!w_is_closure(closure)) {
        w_raise(w_string("go requires a closure"));
    }

    /* Try recycled goroutine first (per-thread pool, no lock) */
    WGoroutine *g = g_pool_get();
    if (g) {
        /* Reuse struct + stack — just reset fields */
        atomic_store_explicit(&g->state, G_IDLE, memory_order_relaxed);
        g->queued = 0;
        g->closure = closure;
        g->result = W_NIL;
        g->next = NULL;
        g->wait_fd = -1;
        g->wait_events = 0;
        g->wait_timed_out = 0;
        g->wait_deadline_ticks = 0;
        g->wait_loop = NULL;
        g->deadline_linked = 0;
        g->deadline_next = NULL;
        g->io_result = 0;
        g->io_buf_id = -1;
        g->io_zc_pending = 0;
        /* Fresh unwind state; the cleanup-stack allocation is kept for reuse */
        WGoroutineUnwind *u = g_unwind_slot(g);
        u->exception_stack = NULL;
        u->block_return_stack = NULL;
        u->cleanup_top = 0;
        u->ctx_locals = w_ctx_locals();
    } else {
        /* Allocate fresh goroutine */
        void *stack = g_arena_alloc_stack();
        if (!stack) {
            w_raise(w_string("goroutine limit exceeded"));
        }
        g = calloc(1, sizeof(WGoroutine));
        g_debug_register_goroutine(g);
        g->stack_base = stack;
        atomic_init(&g->state, G_IDLE);
        g->queued = 0;
        g->closure = closure;
        g->result = W_NIL;
        g->next = NULL;
        g->wait_fd = -1;
        g->wait_events = 0;
        g->wait_timed_out = 0;
        g->wait_deadline_ticks = 0;
        g->wait_loop = NULL;
        g->io_buf_id = -1;
        /* Empty unwind state (a stack from the freelist may carry stale
         * words; its previous cleanup stack was freed with its struct) */
        memset(g_unwind_slot(g), 0, sizeof(WGoroutineUnwind));
        g_unwind_slot(g)->ctx_locals = w_ctx_locals();
    }

    /* (Re)initialize context — stack is reused, entry point reset. The
     * context's stack ends below the parked unwind slot at the top. */
    size_t g_usable_stack = g_stack_size() - W_GOROUTINE_UNWIND_RESERVE;
#ifdef W_CONTEXT_UCONTEXT
    getcontext(&g->ctx);
    g->ctx.uc_stack.ss_sp = g->stack_base;
    g->ctx.uc_stack.ss_size = g_usable_stack;
    g->ctx.uc_link = &g_scheduler_ctx;
    makecontext(&g->ctx, g_body_entry, 0);
#else
    w_ctx_make(&g->ctx, g->stack_base, g_usable_stack, g_body_entry);
#endif

    w_goroutine_count_inc();
    if (!atomic_load_explicit(&g_mp_scheduler_active, memory_order_relaxed))
        g_coop_live_goroutines++;
    atomic_store_explicit(&g->state, G_RUNNABLE, memory_order_release);
    g_enqueue(g);
    return w_box_ptr(g, W_SUBTAG_GENERIC);
}

/* An out-of-line suspension boundary prevents a caller's loop from caching
 * this worker's TLS addresses across a migration to another worker. */
__attribute__((noinline))
void w_goroutine_yield(void) {
    WGoroutine *g = g_current;
    if (!g) return;  /* main thread, no-op */
    /* The current stack is still live. Publish runnable and enqueue only
     * after returning to the scheduler with the context completely saved. */
    atomic_store_explicit(&g->state, G_YIELDING, memory_order_release);
    w_ctx_swap(&g->ctx, &g_scheduler_ctx);
}

__attribute__((noinline))
WValue w_goroutine_current(void) {
    if (!g_current) return W_NIL;
    return w_box_ptr(g_current, W_SUBTAG_GENERIC);
}

/* Run scheduler: pick next goroutine and switch to it.
 * Call this from main thread to drive goroutines cooperatively. */
static __thread volatile int g_scheduler_persistent = 0; /* 1 = don't exit when idle (server mode) */

void w_scheduler_run(void) {
    /* Fast path: if no goroutines were ever spawned, nothing to drain */
    if (!g_arena_initialized && !g_run_queue_head) return;

    /* Initialize event loop for cooperative scheduler if needed */
    if (!g_coop_event_loop) {
        g_coop_event_loop = w_event_init();
    }

    while (1) {
        g_scheduler_maybe_dump("coop");
        WGoroutine *g = g_dequeue();

        if (!g) {
            /* A drained batch has nothing left to wait for. Do not perform
             * a final empty event syscall. */
            if (!g_scheduler_persistent && g_coop_live_goroutines == 0) break;

            /* Readiness is level-triggered in the kernel until consumed:
             * a blocking poll also returns immediately for already-ready
             * I/O. Repeating 64 empty nonblocking polls adds no information.
             * The backend arms sticky wakes before taking its per-loop
             * deadline snapshot, so an earlier timer cannot be missed. */
            if (g_coop_event_loop) {
                WGoroutine *woken[256];
                int n = w_event_poll(g_coop_event_loop, -1, woken, 256);
                for (int i = 0; i < n; i++) {
                    if (g_try_wake_waiting(woken[i], 0)) {
                        g_enqueue(woken[i]);
                    }
                }
                int expired = g_wake_expired_deadlines(g_coop_event_loop, woken, 256);
                for (int i = 0; i < expired; i++) {
                    g_enqueue(woken[i]);
                }
            }
            continue;
        }

        g_claim_running_local(g);
        g_current = g;
        WUnwindSave unwind;
        g_unwind_enter(g, &unwind);
        w_ctx_swap(&g_scheduler_ctx, &g->ctx);
        g_unwind_leave(g, &unwind);
        g_current = NULL;

        int action = g_after_switch(g);
        if (action > 0) g_enqueue(g);
        else if (action < 0) g_pool_return(g);
    }
}

WValue w_scheduler_run_w(void) {
    w_scheduler_run();
    return W_NIL;
}

/* Run exactly one goroutine from the run queue and return.
 * Returns 1 if a goroutine was run, 0 if the queue was empty.
 * Used by w_chan_recv/send on the main thread to drive goroutines
 * cooperatively without entering the full scheduler loop. */
static int w_scheduler_run_one(void) {
    WGoroutine *g = g_dequeue();
    if (!g) return 0;
    g_claim_running_local(g);
    g_current = g;
    WUnwindSave unwind;
    g_unwind_enter(g, &unwind);
    w_ctx_swap(&g_scheduler_ctx, &g->ctx);
    g_unwind_leave(g, &unwind);
    g_current = NULL;
    int action = g_after_switch(g);
    if (action > 0) g_enqueue(g);
    else if (action < 0) g_pool_return(g);
    return 1;
}

/* ---- Scheduler accessors (for separate compilation units like hammer.c) ---- */
void w_scheduler_set_event_loop(WEventLoop *el) { g_coop_event_loop = el; }
void w_scheduler_set_persistent(int val)        { g_scheduler_persistent = val; }

/* ---- Capacity metrics (for Forge → Hammer cap handshake) ---- */
static volatile int64_t g_active_goroutines = 0;  /* total live goroutines across all threads */
static volatile int g_track_goroutine_count = 0;

void w_goroutine_count_set_enabled(int enabled) {
    g_track_goroutine_count = enabled ? 1 : 0;
    if (!enabled) g_active_goroutines = 0;
}

void w_goroutine_count_inc(void) {
    if (__builtin_expect(g_track_goroutine_count, 0)) {
        __sync_fetch_and_add(&g_active_goroutines, 1);
    }
}

void w_goroutine_count_dec(void) {
    if (__builtin_expect(g_track_goroutine_count, 0)) {
        __sync_fetch_and_sub(&g_active_goroutines, 1);
    }
}

int64_t w_goroutine_count(void)  { return g_active_goroutines; }

/* Run queue depth — walk the cooperative scheduler queue.
 * Thread-local, so only accurate from the current worker thread. */
int w_scheduler_queue_depth(void) {
    int depth = 0;
    WGoroutine *g = g_run_queue_head;
    while (g) { depth++; g = g->next; }
    return depth;
}

/* ---- M:P Scheduler ---- */

/* Per-P FIFO: one owner publishes tail; owner and thieves claim head.
 * Queue ownership is independent of the goroutine's execution state. */
static void p_local_push_claimed(WProcessor *p, WGoroutine *g) {
    uint64_t tail = atomic_load_explicit(&p->local_tail, memory_order_relaxed);
    uint64_t head = atomic_load_explicit(&p->local_head, memory_order_acquire);
    if (tail - head >= W_LOCAL_QUEUE_MAX) {
        /* Overflow: push to global queue. g is already marked queued. */
        g_enqueue_claimed(g);
        return;
    }
    atomic_store_explicit(&p->local_queue[tail % W_LOCAL_QUEUE_MAX], g, memory_order_relaxed);
    atomic_store_explicit(&p->local_tail, tail + 1, memory_order_release);
}

static void p_local_push(WProcessor *p, WGoroutine *g) {
    if (!g_mark_queued(g)) return;
    p_local_push_claimed(p, g);
}

static WGoroutine *p_fifo_take(WProcessor *p) {
    uint64_t head = atomic_load_explicit(&p->local_head, memory_order_acquire);
    for (;;) {
        uint64_t tail = atomic_load_explicit(&p->local_tail, memory_order_acquire);
        if (head == tail) return NULL;
        if (tail - head > W_LOCAL_QUEUE_MAX) {
            head = atomic_load_explicit(&p->local_head, memory_order_acquire);
            continue;
        }
        WGoroutine *g = atomic_load_explicit(
            &p->local_queue[head % W_LOCAL_QUEUE_MAX], memory_order_relaxed);
        if (atomic_compare_exchange_weak_explicit(&p->local_head, &head, head + 1,
                memory_order_acq_rel, memory_order_acquire)) {
            g_mark_dequeued(g);
            return g;
        }
    }
}

static WGoroutine *p_local_pop(WProcessor *p) { return p_fifo_take(p); }

static WGoroutine *p_steal(WProcessor *victim) {
    return p_fifo_take(victim);
}

__thread WProcessor *p_current = NULL;

/* Pin the calling thread to a specific CPU core.
 * Linux: hard pin via sched_setaffinity.
 * macOS: affinity tag hint via thread_policy_set (kernel may still migrate). */
static void p_set_affinity(int core_id) {
#ifdef __linux__
    cpu_set_t cpuset;
    CPU_ZERO(&cpuset);
    CPU_SET(core_id, &cpuset);
    pthread_setaffinity_np(pthread_self(), sizeof(cpu_set_t), &cpuset);
#elif defined(__APPLE__)
    thread_affinity_policy_data_t policy = { .affinity_tag = core_id + 1 };
    thread_policy_set(pthread_mach_thread_np(pthread_self()),
                      THREAD_AFFINITY_POLICY,
                      (thread_policy_t)&policy, 1);
#endif
}

static void *p_thread_entry(void *arg) {
    WProcessor *p = (WProcessor *)arg;
    p_current = p;
    p_set_affinity(p->id);
    unsigned dispatches = 0;

    while (atomic_load_explicit(&g_scheduler_active, memory_order_acquire)) {
        g_scheduler_maybe_dump("mp");
        WGoroutine *g = NULL;

        /* Bound global-queue starvation even when local work keeps yielding.
         * This is a dispatch budget, not a wall-clock preemption guarantee. */
        if ((dispatches++ & 63u) == 0) g = g_dequeue();

        /* 1. Try local queue */
        if (!g) g = p_local_pop(p);

        /* 2. Try global queue */
        if (!g) g = g_dequeue();

        /* 3. Work stealing */
        if (!g) {
            for (int i = 0; i < g_num_processors && !g; i++) {
                if (i == p->id) continue;
                g = p_steal(&g_processors[i]);
            }
        }

        if (g) {
            g_claim_running(g);
            g_current = g;
            WUnwindSave unwind;
            g_unwind_enter(g, &unwind);
            w_ctx_swap(&g_scheduler_ctx, &g->ctx);
            g_unwind_leave(g, &unwind);
            g_current = NULL;

            int action = g_after_switch(g);
            if (action > 0) {
                p_local_push(p, g);
            } else if (action < 0) {
                g_pool_return(g);
            }
            /* A committed park transfers ownership; do not read g again. */
        } else {
            /* No work: poll event loop for I/O-parked goroutines */
            if (p->event_loop) {
                WGoroutine *woken[256];
                int n = w_event_poll(p->event_loop, 1/*ms*/, woken, 256);
                for (int i = 0; i < n; i++) {
                    if (g_try_wake_waiting(woken[i], 0)) {
                        p_local_push(p, woken[i]);
                    }
                }
                int expired = g_wake_expired_deadlines(NULL, woken, 256);
                for (int i = 0; i < expired; i++) {
                    p_local_push(p, woken[i]);
                }
            } else {
                struct timespec ts = {0, 100000};  /* 100µs */
                nanosleep(&ts, NULL);
            }
        }
    }

    return NULL;
}

static void w_scheduler_init_once(void) {
    g_arena_init();
    g_scheduler_initialized = 1;
}

void w_scheduler_init(void) {
    pthread_once(&g_scheduler_once, w_scheduler_init_once);
}

void w_scheduler_start(WValue num_procs_wv) {
    int num_procs = (int)w_as_int(num_procs_wv);
    if (num_procs <= 0) {
        num_procs = (int)sysconf(_SC_NPROCESSORS_ONLN);
    }
    if (num_procs > W_MAX_PROCESSORS) {
        num_procs = W_MAX_PROCESSORS;
    }

    g_num_processors = num_procs;
    g_slab_needs_lock = 1;
    g_scheduler_active = 1;
    g_mp_scheduler_active = 1;

    for (int i = 0; i < num_procs; i++) {
        g_processors[i].id = i;
        g_processors[i].local_head = 0;
        g_processors[i].local_tail = 0;
        g_processors[i].spinning = 0;
        g_processors[i].active = 1;
        g_processors[i].event_loop = w_event_init();
    }
    /* No worker may steal from a processor whose ring is still being reset,
     * especially after a stop/restart with nonzero old head/tail positions. */
    for (int i = 0; i < num_procs; i++) {
        pthread_create(&g_processors[i].thread, NULL, p_thread_entry, &g_processors[i]);
    }
}

/* Block until all worker threads exit (server mode — they run forever) */
void w_scheduler_wait(void) {
    for (int i = 0; i < g_num_processors; i++) {
        pthread_join(g_processors[i].thread, NULL);
    }
}

void w_scheduler_stop(void) {
    atomic_store_explicit(&g_scheduler_active, 0, memory_order_release);
    for (int i = 0; i < g_num_processors; i++) {
        pthread_join(g_processors[i].thread, NULL);
    }
    /* A worker can finish a deadline registered on another worker's loop.
     * Keep all loops alive until no scheduler thread can still access them. */
    for (int i = 0; i < g_num_processors; i++) {
        g_processors[i].active = 0;
        if (g_processors[i].event_loop) {
            w_event_destroy(g_processors[i].event_loop);
            g_processors[i].event_loop = NULL;
        }
    }
    atomic_store_explicit(&g_mp_scheduler_active, 0, memory_order_release);
    g_num_processors = 0;
}

#pragma clang diagnostic pop

/* ---- Mutexes ---- */

static WMutex *as_mutex(WValue value) {
    if (!w_is_mutex(value)) die("expected Mutex");
    return (WMutex *)w_as_ptr(value);
}

static int w_mutex_owned_by_current(WMutex *mutex, WGoroutine *self) {
    if (!mutex->locked) return 0;
    if (self) {
        return mutex->owner_is_goroutine &&
               mutex->owner_goroutine == self;
    }
    return !mutex->owner_is_goroutine &&
           pthread_equal(mutex->owner_thread, pthread_self());
}

static void w_mutex_track_thread_lock(WMutex *mutex) {
    mutex->held_next = g_thread_held_mutexes;
    g_thread_held_mutexes = mutex;
}

static void w_mutex_untrack_thread_lock(WMutex *mutex) {
    WMutex **link = &g_thread_held_mutexes;
    while (*link) {
        if (*link == mutex) {
            *link = mutex->held_next;
            mutex->held_next = NULL;
            return;
        }
        link = &(*link)->held_next;
    }
}

static __attribute__((noinline)) void w_mutex_pause(WGoroutine *self) {
    if (self) {
        w_goroutine_yield();
    } else if (!g_mp_scheduler_active && w_scheduler_run_one()) {
        /* drove a goroutine cooperatively */
    } else {
        sched_yield();
    }
}

static void w_mutex_take(WMutex *mutex, WGoroutine *self) {
    mutex->locked = 1;
    mutex->owner_is_goroutine = self ? 1 : 0;
    mutex->owner_goroutine = self;
    if (!self) {
        mutex->owner_thread = pthread_self();
        w_mutex_track_thread_lock(mutex);
    }
}

WValue w_mutex_new(void) {
    WMutex *mutex = calloc(1, sizeof(WMutex));
    if (!mutex) w_raise(w_string("Mutex allocation failed"));
    mutex->type = W_TYPE_MUTEX;
    if (pthread_mutex_init(&mutex->guard, NULL) != 0) {
        free(mutex);
        w_raise(w_string("Mutex initialization failed"));
    }
    return w_box_ptr(mutex, W_SUBTAG_GENERIC);
}

WValue w_mutex_lock(WValue value) {
    WMutex *mutex = as_mutex(value);
    /* A G's identity survives migration; the address of its original worker's
     * TLS does not. Keep the identity, never a TLS slot, across the wait loop. */
    WGoroutine *self = g_current;
    while (1) {
        pthread_mutex_lock(&mutex->guard);
        if (!mutex->locked) {
            w_mutex_take(mutex, self);
            pthread_mutex_unlock(&mutex->guard);
            return value;
        }
        if (w_mutex_owned_by_current(mutex, self)) {
            pthread_mutex_unlock(&mutex->guard);
            w_raise(w_string("Mutex is not reentrant"));
        }
        pthread_mutex_unlock(&mutex->guard);
        w_mutex_pause(self);
    }
}

WValue w_mutex_try_lock(WValue value) {
    WMutex *mutex = as_mutex(value);
    WGoroutine *self = g_current;
    pthread_mutex_lock(&mutex->guard);
    if (mutex->locked) {
        pthread_mutex_unlock(&mutex->guard);
        return W_FALSE;
    }
    w_mutex_take(mutex, self);
    pthread_mutex_unlock(&mutex->guard);
    return W_TRUE;
}

WValue w_mutex_unlock(WValue value) {
    WMutex *mutex = as_mutex(value);
    WGoroutine *self = g_current;
    pthread_mutex_lock(&mutex->guard);
    if (!mutex->locked) {
        pthread_mutex_unlock(&mutex->guard);
        w_raise(w_string("unlock of unlocked Mutex"));
    }
    if (!w_mutex_owned_by_current(mutex, self)) {
        pthread_mutex_unlock(&mutex->guard);
        w_raise(w_string("Mutex unlocked by non-owner"));
    }
    if (!mutex->owner_is_goroutine) w_mutex_untrack_thread_lock(mutex);
    mutex->locked = 0;
    mutex->owner_is_goroutine = 0;
    mutex->owner_goroutine = NULL;
    pthread_mutex_unlock(&mutex->guard);
    return value;
}

WValue w_mutex_locked(WValue value) {
    WMutex *mutex = as_mutex(value);
    pthread_mutex_lock(&mutex->guard);
    WValue locked = mutex->locked ? W_TRUE : W_FALSE;
    pthread_mutex_unlock(&mutex->guard);
    return locked;
}

/* ---- Channels ---- */

static inline WChan *as_chan(WValue v) {
    if (__builtin_expect(!w_is_channel(v), 0)) die("expected channel");
    return (WChan *)w_as_ptr(v);
}

static inline void w_chan_lock(WChan *ch) {
    if (__builtin_expect(g_slab_needs_lock, 0)) pthread_mutex_lock(&ch->lock);
}

static inline void w_chan_unlock(WChan *ch) {
    if (__builtin_expect(g_slab_needs_lock, 0)) pthread_mutex_unlock(&ch->lock);
}

/* Call with the lock held after a value arrives or the channel closes: wake any
 * native receiver sleeping in w_chan_native_sleep. */
static inline void w_chan_wake_locked(WChan *ch) {
    if (__builtin_expect(ch->sleepers > 0, 0)) pthread_cond_broadcast(&ch->ready);
}

/* A native (non-goroutine) receiver found the channel empty: sleep on the
 * condition variable until a sender or close wakes it, or until deadline_ns
 * (monotonic; INT64_MAX = none) — capped so a scheduler-less process still
 * drives cooperative goroutines at the old 1 ms cadence. Returns 0 when it
 * cannot sleep here (single-threaded, or running on a goroutine), so the
 * caller falls back to the yield/spin path. */
static int w_chan_native_sleep(WChan *ch, int64_t deadline_ns) {
    if (!g_slab_needs_lock || g_current) return 0;
    int64_t cap_ns = g_mp_scheduler_active ? 100000000LL : 1000000LL;  /* 100 ms / 1 ms */
    int64_t wait_ns = cap_ns;
    if (deadline_ns != INT64_MAX) {
        int64_t left = deadline_ns - __w_clock_ns_raw();
        if (left <= 0) return 1;
        if (left < wait_ns) wait_ns = left;
    }
    pthread_mutex_lock(&ch->lock);
    if (ch->count == 0 && !ch->closed) {
        ch->sleepers++;
        struct timespec ts = { (time_t)(wait_ns / 1000000000LL), (long)(wait_ns % 1000000000LL) };
#ifdef __APPLE__
        pthread_cond_timedwait_relative_np(&ch->ready, &ch->lock, &ts);
#else
        struct timespec now;
        clock_gettime(CLOCK_REALTIME, &now);
        ts.tv_sec += now.tv_sec;
        ts.tv_nsec += now.tv_nsec;
        if (ts.tv_nsec >= 1000000000L) { ts.tv_sec++; ts.tv_nsec -= 1000000000L; }
        pthread_cond_timedwait(&ch->ready, &ch->lock, &ts);
#endif
        ch->sleepers--;
    }
    pthread_mutex_unlock(&ch->lock);
    return 1;
}

static WValue w_chan_allocate(int64_t cap, int unbounded) {
    WChan *ch = calloc(1, sizeof(WChan));
    if (!ch) {
        w_raise(w_string("Channel allocation failed"));
    }
    ch->type = W_TYPE_CHANNEL;
    ch->cap = cap;
    ch->count = 0;
    ch->head = 0;
    ch->tail = 0;
    ch->closed = 0;
    ch->unbounded = unbounded ? 1 : 0;
    ch->send_waitq = NULL;
    ch->recv_waitq = NULL;
    pthread_mutex_init(&ch->lock, NULL);
    pthread_cond_init(&ch->ready, NULL);
    ch->sleepers = 0;
    size_t slots = cap > 0 ? (size_t)cap : 1;
    ch->buffer = calloc(slots, sizeof(WValue));
    if (!ch->buffer) {
        pthread_cond_destroy(&ch->ready);
        pthread_mutex_destroy(&ch->lock);
        free(ch);
        w_raise(w_string("Channel buffer allocation failed"));
    }
    return w_box_ptr(ch, W_SUBTAG_GENERIC);
}

WValue w_chan_new(WValue capacity_wv) {
    if (!w_is_int(capacity_wv)) {
        w_raise(w_string("Channel capacity must be an Integer"));
    }
    int64_t cap = w_as_int(capacity_wv);
    if (cap < 0) {
        w_raise(w_string("Channel capacity must be non-negative"));
    }
    return w_chan_allocate(cap, 0);
}

WValue w_chan_new_unbounded(void) {
    return w_chan_allocate(8, 1);
}

static int w_chan_grow_unbounded(WChan *ch) {
    if (ch->cap > INT64_MAX / 2 || (uint64_t)ch->cap > SIZE_MAX / (2 * sizeof(WValue))) {
        return 0;
    }
    int64_t new_cap = ch->cap * 2;
    WValue *buffer = malloc((size_t)new_cap * sizeof(WValue));
    if (!buffer) return 0;
    if (ch->count > 0) {
        int64_t first = ch->cap - ch->head;
        if (first > ch->count) first = ch->count;
        memcpy(buffer, ch->buffer + ch->head, (size_t)first * sizeof(WValue));
        if (ch->count > first) {
            memcpy(buffer + first, ch->buffer, (size_t)(ch->count - first) * sizeof(WValue));
        }
    }
    free(ch->buffer);
    ch->buffer = buffer;
    ch->cap = new_cap;
    ch->head = 0;
    ch->tail = ch->count;
    return 1;
}

enum {
    W_CHAN_RESULT_CLOSED = -1,
    W_CHAN_RESULT_UNAVAILABLE = 0,
    W_CHAN_RESULT_RECEIVED = 1
};

/* A native thread (no goroutine) waiting on a channel: yield for the first rounds, then
 * sleep with exponential backoff (10us doubling to 1ms). A fixed 10us sleep kept every
 * idle waiter at ~100k wakeups/s — a worker pool parked on a channel burned whole cores. */
static void w_chan_idle_sleep(int s) {
    if (s < 16) {
        sched_yield();
        return;
    }
    int k = s - 16;
    long us = k >= 7 ? 1000 : (10L << k);
    if (us > 1000) us = 1000;
    struct timespec ts = {0, us * 1000L};
    nanosleep(&ts, NULL);
}

/* Keep TLS lookup inside a fresh call: inlining into a retry loop lets the C
 * compiler retain the old worker's TLS address across a migrating yield. */
static __attribute__((noinline)) void w_chan_pause_spin(int *spin) {
    if (g_current) {
        w_goroutine_yield();
    } else if (!g_mp_scheduler_active && w_scheduler_run_one()) {
        /* drove a goroutine cooperatively */
        if (spin) *spin = 0;
    } else {
        int s = spin ? (*spin)++ : 16;
        w_chan_idle_sleep(s);
    }
}

static __attribute__((noinline)) void w_chan_pause(void) {
    w_chan_pause_spin(NULL);
}

static __attribute__((noinline)) void w_chan_sender_pause_spin(WChan *ch, uint64_t ticket, int *spin) {
    if (g_current) {
        w_goroutine_yield();
        return;
    }
    if (!g_mp_scheduler_active && w_scheduler_run_one()) {
        if (spin) *spin = 0;
        return;
    }
    for (int k = 0; k < 4096; k++) {
        if (*(volatile uint8_t *)&ch->closed) {
            if (spin) *spin = 0;
            return;
        }
        if (ticket != 0) {
            if (*(volatile uint64_t *)&ch->received_seq >= ticket) {
                if (spin) *spin = 0;
                return;
            }
        } else if (ch->cap == 0) {
            if (*(volatile int64_t *)&ch->count == 0) {
                if (spin) *spin = 0;
                return;
            }
        } else {
            if (*(volatile int64_t *)&ch->count < *(volatile int64_t *)&ch->cap) {
                if (spin) *spin = 0;
                return;
            }
        }
#if defined(__aarch64__)
        __asm__ volatile("yield" ::: "memory");
#elif defined(__x86_64__)
        __asm__ volatile("pause" ::: "memory");
#endif
    }
    int s = spin ? (*spin)++ : 16;
    w_chan_idle_sleep(s);
}

static void w_chan_receiver_wait_cleanup(void *arg) {
    WChan *ch = (WChan *)arg;
    w_chan_lock(ch);
    if (ch->recv_waiters > 0) ch->recv_waiters--;
    w_chan_unlock(ch);
}

static __attribute__((noinline)) void w_chan_receiver_wait_core(WChan *ch, int *spin) {
    if (g_current) {
        w_goroutine_yield();
        return;
    }
    if (!g_mp_scheduler_active && w_scheduler_run_one()) {
        if (spin) *spin = 0;
        return;
    }
    int spins = (spin && *spin >= 16) ? 0 : 4096;
    for (int k = 0; k < spins; k++) {
        if (*(volatile int64_t *)&ch->count > 0 || *(volatile uint8_t *)&ch->closed) {
            if (spin) *spin = 0;
            return;
        }
#if defined(__aarch64__)
        __asm__ volatile("yield" ::: "memory");
#elif defined(__x86_64__)
        __asm__ volatile("pause" ::: "memory");
#endif
    }
    int s = spin ? (*spin)++ : 16;
    w_chan_idle_sleep(s);
}

/* Advertise an unbuffered receiver only for one cancellable scheduler pause.
 * pthread cleanup prevents a killed native receiver from leaving stale
 * readiness behind and making try_send lose a value. */
static __attribute__((noinline)) void w_chan_receiver_pause_spin(WChan *ch, int *spin) {
    if (ch->cap != 0) {
        w_chan_receiver_wait_core(ch, spin);
        return;
    }
    WGoroutine *self = g_current;
    w_chan_lock(ch);
    ch->recv_waiters++;
    w_chan_unlock(ch);
    if (self) {
        /* pthread cleanup belongs to an OS thread, not a migrating G. No
         * native cleanup frame may remain installed across a G suspension. */
        w_goroutine_yield();
        w_chan_receiver_wait_cleanup(ch);
        return;
    }
    pthread_cleanup_push(w_chan_receiver_wait_cleanup, ch);
    w_chan_receiver_wait_core(ch, spin);
    pthread_cleanup_pop(1);
}

static int64_t w_chan_timeout_deadline(WValue milliseconds) {
    if (!w_is_int(milliseconds) || w_as_int(milliseconds) < 0) {
        w_raise(w_string("Channel timeout must be a non-negative Integer in milliseconds"));
    }
    int64_t ms = w_as_int(milliseconds);
    int64_t now = __w_clock_ns_raw();
    if (ms > (INT64_MAX - now) / 1000000LL) return INT64_MAX;
    return now + ms * 1000000LL;
}

static int w_chan_deadline_expired(int64_t deadline) {
    return __w_clock_ns_raw() >= deadline;
}

static __thread WArray *g_chan_pair_arr = NULL;

static inline WValue w_chan_pair_result(WValue v0, WValue v1) {
    WArray *a = g_chan_pair_arr;
    if (__builtin_expect(!a, 0)) {
        WValue wv = w_array_new_inline(65, 2);
        a = w_as_array(wv);
        a->size = 2;
        g_chan_pair_arr = a;
    }
    WValue *slots = (WValue *)a->slots;
    slots[0] = v0;
    slots[1] = v1;
    a->size = 2;
    return w_box_array(a);
}

static WValue w_chan_status_result(WValue value, int status) {
    return w_chan_pair_result(value, w_int(status));
}

/* Caller holds ch->lock. */
static inline int w_chan_take_locked(WChan *ch, WValue *value) {
    if (ch->count <= 0) return 0;
    *value = ch->buffer[ch->head];
    if (ch->cap == 0) {
        ch->count = 0;
        ch->received_seq = ch->handoff_seq;
        ch->handoff_committed = 0;
    } else {
        int64_t next = ch->head + 1;
        ch->head = (next == ch->cap) ? 0 : next;
        ch->count--;
    }
    return 1;
}

static int w_chan_try_send_status(WValue channel, WValue val) {
    WChan *ch = as_chan(channel);
    w_chan_lock(ch);

    if (__builtin_expect(ch->closed, 0)) {
        w_chan_unlock(ch);
        return W_CHAN_RESULT_CLOSED;
    }

    if (ch->unbounded) {
        if (ch->count == ch->cap && !w_chan_grow_unbounded(ch)) {
            w_chan_unlock(ch);
            w_raise(w_string("Channel buffer allocation failed"));
        }
        ch->buffer[ch->tail] = val;
        int64_t next = ch->tail + 1;
        ch->tail = (next == ch->cap) ? 0 : next;
        ch->count++;
        w_chan_wake_locked(ch);
        w_chan_unlock(ch);
        return W_CHAN_RESULT_RECEIVED;
    }

    if (ch->cap == 0) {
        if (ch->recv_waiters <= 0 || ch->count != 0) {
            w_chan_unlock(ch);
            return W_CHAN_RESULT_UNAVAILABLE;
        }
        ch->buffer[0] = val;
        ch->count = 1;
        w_chan_wake_locked(ch);
        ch->handoff_seq++;
        ch->handoff_committed = 1;
        w_chan_unlock(ch);
        return W_CHAN_RESULT_RECEIVED;
    }

    if (ch->count >= ch->cap) {
        w_chan_unlock(ch);
        return W_CHAN_RESULT_UNAVAILABLE;
    }
    ch->buffer[ch->tail] = val;
    int64_t next = ch->tail + 1;
    ch->tail = (next == ch->cap) ? 0 : next;
    ch->count++;
    w_chan_wake_locked(ch);
    w_chan_unlock(ch);
    return W_CHAN_RESULT_RECEIVED;
}

WValue w_chan_try_send(WValue channel, WValue val) {
    int status = w_chan_try_send_status(channel, val);
    if (status == W_CHAN_RESULT_CLOSED) {
        w_raise(w_string("send on closed channel"));
    }
    return w_bool(status == W_CHAN_RESULT_RECEIVED);
}

/* Non-raising three-state probe for mixed Channel.select arms. Keep the
 * public try_send compatibility contract above: it still raises on closed. */
WValue w_chan_try_send_result(WValue channel, WValue val) {
    return w_int(w_chan_try_send_status(channel, val));
}

WValue w_chan_send_timeout(WValue channel, WValue val, WValue milliseconds) {
    int64_t deadline = w_chan_timeout_deadline(milliseconds);
    int spin = 0;
    while (1) {
        if (w_chan_try_send(channel, val) == W_TRUE) return W_TRUE;
        if (w_chan_deadline_expired(deadline)) return W_FALSE;
        w_chan_pause_spin(&spin);
    }
}

WValue w_chan_send(WValue channel, WValue val) {
    WChan *ch = as_chan(channel);
    w_chan_lock(ch);

    if (__builtin_expect(ch->closed, 0)) {
        w_chan_unlock(ch);
        w_raise(w_string("send on closed channel"));
    }

    if (__builtin_expect(ch->cap > 0 && ch->count < ch->cap, 1)) {
        /* Fast path: buffered with room available (also covers unbounded with room) */
        ch->buffer[ch->tail] = val;
        int64_t next = ch->tail + 1;
        ch->tail = (next == ch->cap) ? 0 : next;
        ch->count++;
        w_chan_wake_locked(ch);
        w_chan_unlock(ch);
        return W_NIL;
    }

    if (ch->unbounded) {
        if (ch->count == ch->cap && !w_chan_grow_unbounded(ch)) {
            w_chan_unlock(ch);
            w_raise(w_string("Channel buffer allocation failed"));
        }
        ch->buffer[ch->tail] = val;
        int64_t next = ch->tail + 1;
        ch->tail = (next == ch->cap) ? 0 : next;
        ch->count++;
        w_chan_wake_locked(ch);
        w_chan_unlock(ch);
        return W_NIL;
    }

    if (ch->cap == 0) {
        uint64_t ticket = 0;
        int spin = 0;
        while (ticket == 0) {
            if (ch->closed) {
                w_chan_unlock(ch);
                w_raise(w_string("send on closed channel"));
            }
            if (ch->count == 0) {
                ch->buffer[0] = val;
                ch->count = 1;
                w_chan_wake_locked(ch);
                ch->handoff_committed = 0;
                ticket = ++ch->handoff_seq;
                w_chan_unlock(ch);
                break;
            }
            w_chan_unlock(ch);
            w_chan_sender_pause_spin(ch, 0, &spin);
            w_chan_lock(ch);
        }

        spin = 0;
        while (1) {
            w_chan_lock(ch);
            if (ch->received_seq >= ticket) {
                w_chan_unlock(ch);
                return W_NIL;
            }
            if (ch->closed) {
                w_chan_unlock(ch);
                w_raise(w_string("send on closed channel"));
            }
            w_chan_unlock(ch);
            w_chan_sender_pause_spin(ch, ticket, &spin);
        }
    }

    /* Buffer full: park sender (cooperative yield or adaptive spin) */
    w_chan_unlock(ch);
    int spin = 0;

    while (1) {
        w_chan_lock(ch);
        if (ch->closed) {
            w_chan_unlock(ch);
            w_raise(w_string("send on closed channel"));
        }
        if (ch->cap > 0 && ch->count < ch->cap) {
            ch->buffer[ch->tail] = val;
            int64_t next = ch->tail + 1;
            ch->tail = (next == ch->cap) ? 0 : next;
            ch->count++;
            w_chan_wake_locked(ch);
            w_chan_unlock(ch);
            return W_NIL;
        }
        w_chan_unlock(ch);
        w_chan_sender_pause_spin(ch, 0, &spin);
    }
}

static WValue w_chan_recv_value(WValue channel, int *received) {
    WChan *ch = as_chan(channel);
    int spin = 0;

    while (1) {
        w_chan_lock(ch);
        WValue val = W_NIL;
        if (__builtin_expect(w_chan_take_locked(ch, &val), 1)) {
            w_chan_unlock(ch);
            *received = 1;
            return val;
        }
        if (ch->closed) {
            w_chan_unlock(ch);
            *received = 0;
            return W_NIL;
        }
        w_chan_unlock(ch);
        if (ch->cap != 0 && spin > 0 && w_chan_native_sleep(ch, INT64_MAX)) continue;
        w_chan_receiver_pause_spin(ch, &spin);
    }
}

WValue w_chan_recv(WValue channel) {
    int received = 0;
    return w_chan_recv_value(channel, &received);
}

WValue w_chan_recv_result(WValue channel) {
    int received = 0;
    WValue value = w_chan_recv_value(channel, &received);
    return w_chan_pair_result(value, received ? W_TRUE : W_FALSE);
}

WValue w_chan_try_recv_result(WValue channel) {
    WChan *ch = as_chan(channel);
    w_chan_lock(ch);
    WValue value = W_NIL;
    if (w_chan_take_locked(ch, &value)) {
        w_chan_unlock(ch);
        return w_chan_status_result(value, W_CHAN_RESULT_RECEIVED);
    }
    int status = ch->closed ? W_CHAN_RESULT_CLOSED : W_CHAN_RESULT_UNAVAILABLE;
    w_chan_unlock(ch);
    return w_chan_status_result(W_NIL, status);
}

WValue w_chan_recv_timeout_result(WValue channel, WValue milliseconds) {
    WChan *ch = as_chan(channel);
    int64_t deadline = w_chan_timeout_deadline(milliseconds);
    int spin = 0;

    while (1) {
        w_chan_lock(ch);
        WValue value = W_NIL;
        if (w_chan_take_locked(ch, &value)) {
            w_chan_unlock(ch);
            return w_chan_status_result(value, W_CHAN_RESULT_RECEIVED);
        }
        if (ch->closed) {
            w_chan_unlock(ch);
            return w_chan_status_result(W_NIL, W_CHAN_RESULT_CLOSED);
        }
        if (w_chan_deadline_expired(deadline)) {
            w_chan_unlock(ch);
            return w_chan_status_result(W_NIL, W_CHAN_RESULT_UNAVAILABLE);
        }
        w_chan_unlock(ch);
        if (ch->cap != 0 && spin > 0 && w_chan_native_sleep(ch, deadline)) continue;
        w_chan_receiver_pause_spin(ch, &spin);
    }
}

WValue w_chan_close(WValue channel) {
    WChan *ch = as_chan(channel);
    w_chan_lock(ch);
    ch->closed = 1;
    if (ch->cap == 0 && !ch->handoff_committed) ch->count = 0;
    w_chan_wake_locked(ch);
    w_chan_unlock(ch);
    return W_NIL;
}

/* ---- Freeze / Immutability ---- */

/* Transitive freeze with cycle detection using a visited set */
#define FREEZE_VISITED_MAX 1024

static __thread int freeze_visited_count = 0;
static __thread void *freeze_visited[FREEZE_VISITED_MAX];

static int freeze_is_visited(void *ptr) {
    for (int i = 0; i < freeze_visited_count; i++) {
        if (freeze_visited[i] == ptr) return 1;
    }
    return 0;
}

static void freeze_mark_visited(void *ptr) {
    if (freeze_visited_count < FREEZE_VISITED_MAX) {
        freeze_visited[freeze_visited_count++] = ptr;
    }
}

static void freeze_recursive(WValue v);

static void freeze_recursive(WValue v) {
    /* Mark before traversing: a hash may contain itself, directly or through
     * another container. Frozen hashes never enter the scratch/recycle pools. */
    if (w_is_hash(v)) {
        WHash *hash = as_hash(v);
        if (hash->flags & W_HASH_FLAG_FROZEN) return;
        hash->flags |= W_HASH_FLAG_FROZEN;
        for (uint32_t i = 0; i < hash->used; i++) {
            if (hash->keys[i] == W_MEMO_MISS) continue;
            freeze_recursive(hash->keys[i]);
            freeze_recursive(hash->values[i]);
        }
        return;
    }
    /* Arrays left object space (v5: W_TAG_ARRAY) — handle them before
     * the object-space gate below or their elements never freeze. */
    if (w_is_array(v)) {
        WArray *arr = w_as_array(v);
        if (!arr) return;
        if (freeze_is_visited(arr)) return;
        freeze_mark_visited(arr);
        /* #62: only polymorphic w64 arrays carry WValues that can be frozen.
         * Typed arrays store raw scalar bit patterns—even u64 at the same
         * physical width—so there is no nested object to recurse into and
         * reading arr->slots[i] as WValue would be a type-confused load. */
        if (arr->ebits == 65) {
            for (int32_t i = 0; i < arr->size; i++) {
                freeze_recursive(arr->slots[arr->start + i]);
            }
        }
        return;
    }

    /* Value types are always frozen */
    if (!w_is_obj(v)) return;

    void *ptr = w_as_ptr(v);
    if (!ptr) return;
    if (freeze_is_visited(ptr)) return;
    freeze_mark_visited(ptr);

    int subtag = w_subtag(v);

    if (subtag == W_SUBTAG_INSTANCE) {
        WObject *obj = (WObject *)ptr;
        obj->flags |= W_OBJ_FLAG_FROZEN;
        /* Recursively freeze ivars */
        for (int i = 0; i < obj->ivar_count; i++) {
            freeze_recursive(obj->ivars[i]);
        }
    } else if (subtag == W_SUBTAG_CLOSURE) {
        WClosure *cl = (WClosure *)ptr;
        for (int i = 0; i < cl->capture_count; i++) {
            freeze_recursive(cl->captures[i]);
        }
    }
}

WValue w_freeze(WValue obj) {
    freeze_visited_count = 0;
    freeze_recursive(obj);
    return obj;
}


WValue w_frozen_p(WValue obj) {
    if (w_is_hash(obj))
        return (as_hash(obj)->flags & W_HASH_FLAG_FROZEN) ? W_TRUE : W_FALSE;
    /* Value types are always frozen */
    if (!w_is_obj(obj)) return W_TRUE;

    int subtag = w_subtag(obj);
    if (subtag == W_SUBTAG_INSTANCE) {
        WObject *o = (WObject *)w_as_ptr(obj);
        return (o->flags & W_OBJ_FLAG_FROZEN) ? W_TRUE : W_FALSE;
    }
    /* Non-object heap types: closures, arrays — not freeze-tracked yet */
    return W_FALSE;
}

WValue w_assert_frozen(WValue obj) {
    if (w_frozen_p(obj) == W_FALSE) {
        w_raise(w_string("RuntimeError: value must be frozen before sharing across goroutines"));
    }
    return W_TRUE;
}

W_RT_INTERNAL WEventLoop *w_rt_get_coop_event_loop(void) { return g_coop_event_loop; }
W_RT_INTERNAL void w_rt_set_coop_event_loop(WEventLoop *el) { g_coop_event_loop = el; }
W_RT_INTERNAL void w_rt_set_scheduler_persistent(int val) { g_scheduler_persistent = val; }
W_RT_INTERNAL void w_rt_socket_park_uring(void) { w_socket_park_uring(); }
W_RT_INTERNAL int w_rt_fd_set_nonblocking(int fd) { return w_fd_set_nonblocking(fd); }
W_RT_INTERNAL int64_t w_rt_deadline_ticks_after_ms(int64_t ms) { return w_deadline_ticks_after_ms(ms); }
W_RT_INTERNAL WValue w_rt_socket_read_string(WString *ws, size_t bytes) { return w_socket_read_string(ws, bytes); }

#ifndef W_RUNTIME_UNITY_INCLUDE
#undef die
#undef as_str
#undef as_hash
#undef w_string_n
#undef w_string_n_known_ascii
#undef w_string_ascii_p
#undef w_bytes_ascii_p
#undef w_string_take
#undef w_slab_read
#undef w_string_ascii_case
#undef cmp_numeric_double
#undef bigint_alloc
#undef bigint_release_if_live
#endif
