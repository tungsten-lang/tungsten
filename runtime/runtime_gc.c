#include "runtime_internal.h"
#include <errno.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#if !defined(__wasm__)
#include <pthread.h>
#endif

#if defined(__APPLE__)
#include <mach-o/dyld.h>
#include <mach-o/getsect.h>
#include <malloc/malloc.h>
#endif

/* =========================================================================
 * Tungsten Garbage Collector
 *
 * Architecture:
 *   1. Zero-cost when off (default): `g_gc_track == 0` and `g_gc_auto == 0`.
 *      No background threads, no radix tables, and zero inline mutator write
 *      barriers in LLVM/Cinder codegen.
 *   2. Non-moving generational heap (Nursery -> Old + Keep/Immortal):
 *      - Thread-local 256-entry nursery registration buffers (lock-free fast path).
 *      - 2-level radix page bitmap (16-byte granules over 48-bit VA space) for
 *        crash-proof O(1) conservative validation of CPU registers, C/LLVM
 *        thread stacks, goroutine stacks, and Mach-O/ELF data sections.
 *      - Header flags (`W_GC_TRACKED`, `W_GC_MARK`, `W_GC_OLD`, `W_GC_DIRTY`,
 *        `W_GC_KEEP`) live inside existing struct padding bytes so field offsets
 *        never change.
 *      - Minor GC skips sweeping all Old/Keep objects and skips scanning all
 *        Old leaf allocations (`WString`, `ByteArray`/typed `WArray`, `WStrBuf`),
 *        all frozen Old objects, and all clean (`!W_GC_DIRTY`) Old `WHash` tables.
 *   3. Parallel mark: persistent worker pool drains 64-object gray work chunks
 *      with atomic `W_GC_MARK` claiming.
 *   4. Concurrent sweep: mutators resume immediately after mark/partition; a
 *      background sweeper thread (assisted by parallel workers on large batches)
 *      reclaims dead objects off the mutator critical path.
 * ========================================================================= */

W_GC_HIDDEN uint8_t g_gc_track = 0;
W_GC_HIDDEN uint8_t g_gc_auto  = 0;
W_GC_HIDDEN _Atomic int g_gc_safepoint_req = 0;

/* ---- Radix page map (48-bit user VA, 16-byte granules) ----
 *   addr[47:34] -> L1 (16384 slots)
 *   addr[33:20] -> L2 (16384 slots, 1 MiB per chunk)
 *   addr[19:4]  -> 65536 granules per 1 MiB chunk
 */
#define GC_L1_SIZE       16384u
#define GC_L2_SIZE       16384u
#define GC_CHUNK_GRAN    65536u
#define GC_CHUNK_WORDS   (GC_CHUNK_GRAN / 64u)

typedef struct GCChunk {
    uint64_t live_bits[GC_CHUNK_WORDS];
    uint8_t  kinds[GC_CHUNK_GRAN];
} GCChunk;

typedef struct GCL2 {
    GCChunk *chunks[GC_L2_SIZE];
} GCL2;

static GCL2 **g_gc_l1 = NULL;
static uintptr_t g_gc_min_addr = UINTPTR_MAX;
static uintptr_t g_gc_max_addr = 0;

static inline void gc_radix_insert(void *ptr, uint8_t kind) {
    uintptr_t a = (uintptr_t)ptr;
    if ((a & 0xFULL) != 0 || (a >> 48) != 0) return;
    if (!g_gc_l1) {
        g_gc_l1 = (GCL2 **)calloc(GC_L1_SIZE, sizeof(GCL2 *));
        if (!g_gc_l1) return;
    }
    size_t i1 = (size_t)(a >> 34);
    size_t i2 = (size_t)((a >> 20) & 0x3FFFu);
    size_t gr = (size_t)((a >> 4) & 0xFFFFu);
    GCL2 *l2 = g_gc_l1[i1];
    if (!l2) {
        l2 = (GCL2 *)calloc(1, sizeof(GCL2));
        if (!l2) return;
        g_gc_l1[i1] = l2;
    }
    GCChunk *ch = l2->chunks[i2];
    if (!ch) {
        ch = (GCChunk *)calloc(1, sizeof(GCChunk));
        if (!ch) return;
        l2->chunks[i2] = ch;
    }
    ch->live_bits[gr >> 6] |= (UINT64_C(1) << (gr & 63u));
    ch->kinds[gr] = kind;
    if (a < g_gc_min_addr) g_gc_min_addr = a;
    if (a > g_gc_max_addr) g_gc_max_addr = a;
}

static inline void gc_radix_remove(void *ptr) {
    uintptr_t a = (uintptr_t)ptr;
    if (!g_gc_l1 || a < g_gc_min_addr || a > g_gc_max_addr) return;
    GCL2 *l2 = g_gc_l1[a >> 34];
    if (!l2) return;
    GCChunk *ch = l2->chunks[(a >> 20) & 0x3FFFu];
    if (!ch) return;
    size_t gr = (size_t)((a >> 4) & 0xFFFFu);
    ch->live_bits[gr >> 6] &= ~(UINT64_C(1) << (gr & 63u));
    ch->kinds[gr] = W_GC_KIND_NONE;
}

static inline uint8_t gc_radix_lookup(uintptr_t a) {
    if ((a & 0xFULL) != 0 || a < g_gc_min_addr || a > g_gc_max_addr || !g_gc_l1)
        return W_GC_KIND_NONE;
    GCL2 *l2 = g_gc_l1[a >> 34];
    if (!l2) return W_GC_KIND_NONE;
    GCChunk *ch = l2->chunks[(a >> 20) & 0x3FFFu];
    if (!ch) return W_GC_KIND_NONE;
    size_t gr = (size_t)((a >> 4) & 0xFFFFu);
    if ((ch->live_bits[gr >> 6] & (UINT64_C(1) << (gr & 63u))) == 0)
        return W_GC_KIND_NONE;
    return ch->kinds[gr];
}

/* ---- Object header gc_flags accessors ---- */

static inline size_t gc_small_array_byte_count(const WSmallArray *sa) {
    int64_t bits = array_storage_bits((int64_t)(int8_t)sa->ebits);
    return ((size_t)bits * (size_t)sa->size + 7u) / 8u;
}

static inline uint8_t *gc_flags_ptr(void *p, uint8_t kind) {
    switch (kind) {
        case W_GC_KIND_OBJECT:      return &((WObject *)p)->gc_flags;
        case W_GC_KIND_ARRAY:       return &((WArray *)p)->gc_flags;
        case W_GC_KIND_HASH:        return &((WHash *)p)->gc_flags;
        case W_GC_KIND_CLOSURE:     return &((WClosure *)p)->gc_flags;
        case W_GC_KIND_CELL:        return &((uint8_t *)p)[16];
        case W_GC_KIND_STRING:      return &((WString *)p)->gc_flags;
        case W_GC_KIND_STRBUF:      return &((WStrBuf *)p)->gc_flags;
        case W_GC_KIND_ROPE:        return &((WRope *)p)->gc_flags;
        case W_GC_KIND_SMALL_ARRAY: {
            WSmallArray *sa = (WSmallArray *)p;
            return &sa->slots[gc_small_array_byte_count(sa)];
        }
        case W_GC_KIND_BIG_ARRAY:   return &((WBigArray *)p)->_pad[0];
        case W_GC_KIND_CHAN:        return NULL;
        default:                    return NULL;
    }
}

static inline int gc_kind_is_leaf(void *p, uint8_t kind) {
    switch (kind) {
        case W_GC_KIND_STRING:
        case W_GC_KIND_STRBUF:
            return 1;
        case W_GC_KIND_ARRAY: {
            WArray *a = (WArray *)p;
            if (a->ebits == 65) return 0;
            if ((a->ebits == 64 || a->ebits == 66) && a->size > 0 && a->size <= 64) return 0;
            return 1;
        }
        case W_GC_KIND_SMALL_ARRAY:
            return ((WSmallArray *)p)->ebits != 65;
        case W_GC_KIND_BIG_ARRAY:
            return ((WBigArray *)p)->ebits != 65;
        default:
            return 0;
    }
}

static inline int gc_kind_needs_old_remembered(void *p, uint8_t kind) {
    switch (kind) {
        case W_GC_KIND_STRING:
        case W_GC_KIND_STRBUF:
            return 0;
        case W_GC_KIND_HASH:
            /* WHash mutations all go through C and set W_GC_DIRTY! */
            return 0;
        case W_GC_KIND_ARRAY: {
            WArray *a = (WArray *)p;
            if (a->ebits != 65 && !((a->ebits == 64 || a->ebits == 66) && a->cap <= 64)) return 0;
            if (a->flags & W_FLAG_FROZEN) return 0;
            return 1;
        }
        case W_GC_KIND_SMALL_ARRAY:
            return ((WSmallArray *)p)->ebits == 65;
        case W_GC_KIND_BIG_ARRAY:
            return ((WBigArray *)p)->ebits == 65;
        case W_GC_KIND_OBJECT: {
            WObject *o = (WObject *)p;
            if (o->flags & W_OBJ_FLAG_FROZEN) return 0;
            return o->ivar_count > 0;
        }
        case W_GC_KIND_ROPE:
            /* Ropes only mutate `flat` via w_rope_flatten, which creates a string;
             * keep ropes remembered so cached `flat` young strings stay live. */
            return 1;
        case W_GC_KIND_CLOSURE:
        case W_GC_KIND_CELL:
        case W_GC_KIND_CHAN:
            return 1;
        default:
            return 0;
    }
}

/* Estimate live dynamic backing bytes for accurate heap accounting. */
static inline size_t gc_estimate_bytes(void *p, uint8_t kind, uint32_t init_bytes) {
    switch (kind) {
        case W_GC_KIND_ARRAY: {
            WArray *a = (WArray *)p;
            size_t slot_bytes = 0;
            if ((a->flags & W_FLAG_OWNED) && !(a->flags & (W_FLAG_VIEW | W_FLAG_INLINE))) {
                slot_bytes = (size_t)array_storage_bits(a->ebits) * (size_t)a->cap / 8u;
            }
            return (init_bytes ? (size_t)init_bytes : sizeof(WArray)) + slot_bytes;
        }
        case W_GC_KIND_HASH: {
            WHash *h = (WHash *)p;
            size_t dense = ((size_t)h->cap * 3u) / 4u;
            return sizeof(WHash) + dense * sizeof(WValue) * 2u + (size_t)h->cap * sizeof(int32_t);
        }
        case W_GC_KIND_STRBUF: {
            WStrBuf *sb = (WStrBuf *)p;
            return sizeof(WStrBuf) + (sb->cap > 0 ? (size_t)sb->cap : 0);
        }
        default:
            return init_bytes ? (size_t)init_bytes : 32u;
    }
}

/* ---- Tracked object list entries ---- */

typedef struct GCEntry {
    void    *ptr;
    uint32_t init_bytes;
    uint8_t  kind;
} GCEntry;

typedef struct GCEntryVec {
    GCEntry *items;
    size_t   count;
    size_t   cap;
} GCEntryVec;

static void gc_vec_push(GCEntryVec *v, GCEntry e) {
    if (v->count == v->cap) {
        size_t ncap = v->cap ? v->cap * 2u : 4096u;
        GCEntry *ni = (GCEntry *)realloc(v->items, ncap * sizeof(GCEntry));
        if (!ni) return;
        v->items = ni;
        v->cap = ncap;
    }
    v->items[v->count++] = e;
}

/* ---- Per-thread GC state (nursery buffer + stack bounds + safepoint state) ---- */

#define GC_NURSERY_LOCAL_MAX 256

enum {
    W_TGC_RUNNING = 0,
    W_TGC_BLOCKED = 1,
    W_TGC_PARKED  = 2,
    W_TGC_DEAD    = 3
};

typedef struct WThreadGC {
#if !defined(__wasm__)
    pthread_t tid;
#endif
    void *stack_top;
    void *saved_sp;
    jmp_buf saved_regs;
    _Atomic int state;
    int internal_no_auto;
    size_t nursery_count;
    size_t nursery_bytes;
    GCEntry nursery[GC_NURSERY_LOCAL_MAX];
    WValue **reuse_slots;
    size_t reuse_count;
    size_t reuse_cap;
    WExceptionFrame **exc_stack_ptr;
    WBlockReturnFrame **br_stack_ptr;
    WCleanupEntry **cleanup_stack_ptr;
    int *cleanup_top_ptr;
    struct WThreadGC *next;
} WThreadGC;

static __thread WThreadGC *tls_gc = NULL;
static __thread int tls_is_gc_worker = 0;

/* ---- Global GC state ---- */

#if !defined(__wasm__)
static pthread_mutex_t g_gc_stw_lock   = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t  g_gc_park_cond  = PTHREAD_COND_INITIALIZER;
static pthread_cond_t  g_gc_resume_cond = PTHREAD_COND_INITIALIZER;
static pthread_mutex_t g_gc_alloc_lock = PTHREAD_MUTEX_INITIALIZER;
#endif

static WThreadGC *g_gc_threads = NULL;
static int g_gc_initialized = 0;
static _Atomic int g_gc_in_collection = 0;

static GCEntryVec g_gc_young        = {0};
static GCEntryVec g_gc_old          = {0};
static GCEntryVec g_gc_old_mutable  = {0};
static GCEntryVec g_gc_keep_all_vec = {0};
static GCEntryVec g_gc_keep_roots   = {0};

static WHash **g_gc_dirty_hashes = NULL;
static size_t  g_gc_dirty_count  = 0;
static size_t  g_gc_dirty_cap    = 0;

static size_t g_gc_young_bytes     = 0;
static size_t g_gc_old_bytes       = 0;
static size_t g_gc_keep_bytes      = 0;
static size_t g_gc_young_threshold = 24u * 1024u * 1024u;  /* 24 MiB nursery */
static size_t g_gc_old_threshold   = 96u * 1024u * 1024u;  /* 96 MiB initial major */

static _Atomic uint64_t g_gc_minor_count   = 0;
static _Atomic uint64_t g_gc_major_count   = 0;
static _Atomic uint64_t g_gc_swept_objects = 0;
static _Atomic uint64_t g_gc_swept_bytes   = 0;

/* ---- Stack high-address discovery ---- */

static void *gc_discover_stack_top(void *fallback_anchor) {
#if defined(__APPLE__)
    void *top = pthread_get_stackaddr_np(pthread_self());
    if (top) return top;
#elif defined(__linux__) && !defined(__wasm__)
    pthread_attr_t attr;
    if (pthread_getattr_np(pthread_self(), &attr) == 0) {
        void *stk = NULL;
        size_t sz = 0;
        if (pthread_attr_getstack(&attr, &stk, &sz) == 0 && stk && sz > 0) {
            pthread_attr_destroy(&attr);
            return (uint8_t *)stk + sz;
        }
        pthread_attr_destroy(&attr);
    }
#endif
    return fallback_anchor;
}

static WThreadGC *gc_get_or_create_tgc(void *anchor) {
    WThreadGC *t = tls_gc;
    if (__builtin_expect(t != NULL, 1)) return t;
    if (tls_is_gc_worker) return NULL;
    t = (WThreadGC *)calloc(1, sizeof(WThreadGC));
    if (!t) return NULL;
#if !defined(__wasm__)
    t->tid = pthread_self();
#endif
    t->stack_top = gc_discover_stack_top(anchor ? anchor : (void *)&t);
    t->exc_stack_ptr     = &w_exception_stack;
    t->br_stack_ptr      = &w_block_return_stack;
    t->cleanup_stack_ptr = &g_cleanup_stack;
    t->cleanup_top_ptr   = &g_cleanup_top;
    atomic_store_explicit(&t->state, W_TGC_RUNNING, memory_order_relaxed);
    tls_gc = t;
#if !defined(__wasm__)
    pthread_mutex_lock(&g_gc_alloc_lock);
#endif
    t->next = g_gc_threads;
    g_gc_threads = t;
#if !defined(__wasm__)
    pthread_mutex_unlock(&g_gc_alloc_lock);
#endif
    return t;
}

static void gc_flush_nursery_locked(WThreadGC *t) {
    if (!t || t->nursery_count == 0) return;
    for (size_t i = 0; i < t->nursery_count; i++) {
        GCEntry e = t->nursery[i];
        gc_radix_insert(e.ptr, e.kind);
        gc_vec_push(&g_gc_young, e);
    }
    g_gc_young_bytes += t->nursery_bytes;
    t->nursery_count = 0;
    t->nursery_bytes = 0;
}

void w_gc_thread_enter(void *stack_anchor) {
    (void)gc_get_or_create_tgc(stack_anchor);
}

void w_gc_thread_leave(void) {
    WThreadGC *t = tls_gc;
    if (!t) return;
#if !defined(__wasm__)
    pthread_mutex_lock(&g_gc_alloc_lock);
    gc_flush_nursery_locked(t);
    pthread_mutex_unlock(&g_gc_alloc_lock);

    pthread_mutex_lock(&g_gc_stw_lock);
    atomic_store_explicit(&t->state, W_TGC_DEAD, memory_order_release);
    pthread_cond_broadcast(&g_gc_park_cond);
    pthread_mutex_unlock(&g_gc_stw_lock);
#else
    gc_flush_nursery_locked(t);
    atomic_store_explicit(&t->state, W_TGC_DEAD, memory_order_release);
#endif
    tls_gc = NULL;
}

/* ---- Safepoint & blocking syscall protocol ---- */

void W_GC_COLD_SLOW w_gc_safepoint_slow(void) {
#if !defined(__wasm__)
    WThreadGC *t = tls_gc;
    if (!t || tls_is_gc_worker) return;
    if (!atomic_load_explicit(&g_gc_safepoint_req, memory_order_acquire)) return;

    jmp_buf jb;
    (void)W_FAST_SETJMP(jb);
    memcpy(&t->saved_regs, &jb, sizeof(jmp_buf));
    t->saved_sp = (void *)&jb;

    pthread_mutex_lock(&g_gc_stw_lock);
    while (atomic_load_explicit(&g_gc_safepoint_req, memory_order_acquire)) {
        atomic_store_explicit(&t->state, W_TGC_PARKED, memory_order_release);
        pthread_cond_broadcast(&g_gc_park_cond);
        pthread_cond_wait(&g_gc_resume_cond, &g_gc_stw_lock);
    }
    atomic_store_explicit(&t->state, W_TGC_RUNNING, memory_order_release);
    pthread_mutex_unlock(&g_gc_stw_lock);
#endif
}

void w_gc_blocking_enter_slow(jmp_buf *jb, void *sp_anchor) {
#if !defined(__wasm__)
    WThreadGC *t = gc_get_or_create_tgc(sp_anchor);
    if (!t) return;
    memcpy(&t->saved_regs, jb, sizeof(jmp_buf));
    t->saved_sp = sp_anchor;
    atomic_store_explicit(&t->state, W_TGC_BLOCKED, memory_order_release);
    if (__builtin_expect(atomic_load_explicit(&g_gc_safepoint_req, memory_order_acquire), 0)) {
        pthread_mutex_lock(&g_gc_stw_lock);
        pthread_cond_broadcast(&g_gc_park_cond);
        pthread_mutex_unlock(&g_gc_stw_lock);
    }
#else
    (void)jb;
    (void)sp_anchor;
#endif
}

void w_gc_blocking_leave_slow(void) {
#if !defined(__wasm__)
    WThreadGC *t = tls_gc;
    if (!t) return;
    /* Fast exit when no safepoint is active; re-check after setting RUNNING
     * with seq_cst ordering so collector and waking thread cannot miss each other. */
    atomic_store_explicit(&t->state, W_TGC_RUNNING, memory_order_seq_cst);
    if (__builtin_expect(atomic_load_explicit(&g_gc_safepoint_req, memory_order_seq_cst), 0)) {
        pthread_mutex_lock(&g_gc_stw_lock);
        while (atomic_load_explicit(&g_gc_safepoint_req, memory_order_acquire)) {
            atomic_store_explicit(&t->state, W_TGC_PARKED, memory_order_release);
            pthread_cond_broadcast(&g_gc_park_cond);
            pthread_cond_wait(&g_gc_resume_cond, &g_gc_stw_lock);
        }
        atomic_store_explicit(&t->state, W_TGC_RUNNING, memory_order_release);
        pthread_mutex_unlock(&g_gc_stw_lock);
    }
#endif
}

/* ---- Parallel Mark Work Queue ---- */

#define GC_GRAY_CHUNK_CAP 64
#define GC_MAX_WORKERS    4

typedef struct GCGrayItem {
    void   *ptr;
    uint8_t kind;
} GCGrayItem;

typedef struct GCGrayChunk {
    struct GCGrayChunk *next;
    uint32_t count;
    GCGrayItem items[GC_GRAY_CHUNK_CAP];
} GCGrayChunk;

#if !defined(__wasm__)
static pthread_mutex_t g_gc_work_lock      = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t  g_gc_work_cond      = PTHREAD_COND_INITIALIZER;
static pthread_cond_t  g_gc_work_done_cond = PTHREAD_COND_INITIALIZER;
static pthread_t       g_gc_workers[GC_MAX_WORKERS];
#endif

static int          g_gc_worker_count   = 0;
static GCGrayChunk *g_gc_gray_head      = NULL;
static GCGrayChunk *g_gc_gray_free      = NULL;
static int          g_gc_active_workers = 0;
static uint64_t     g_gc_mark_epoch     = 0;
static int          g_gc_mark_minor     = 0;

static GCGrayChunk *gc_alloc_gray_chunk_locked(void) {
    GCGrayChunk *c = g_gc_gray_free;
    if (c) {
        g_gc_gray_free = c->next;
        c->next = NULL;
        c->count = 0;
        return c;
    }
    return (GCGrayChunk *)calloc(1, sizeof(GCGrayChunk));
}

static void gc_push_gray_chunk(GCGrayChunk *c) {
    if (!c || c->count == 0) return;
#if !defined(__wasm__)
    pthread_mutex_lock(&g_gc_work_lock);
#endif
    c->next = g_gc_gray_head;
    g_gc_gray_head = c;
#if !defined(__wasm__)
    pthread_cond_signal(&g_gc_work_cond);
    pthread_mutex_unlock(&g_gc_work_lock);
#endif
}

typedef struct GCMarkBuf {
    GCGrayItem items[GC_GRAY_CHUNK_CAP];
    uint32_t   count;
} GCMarkBuf;

static void gc_mark_buf_flush(GCMarkBuf *mb) {
    if (mb->count == 0) return;
#if !defined(__wasm__)
    pthread_mutex_lock(&g_gc_work_lock);
#endif
    GCGrayChunk *c = gc_alloc_gray_chunk_locked();
    if (c) {
        c->count = mb->count;
        memcpy(c->items, mb->items, mb->count * sizeof(GCGrayItem));
        c->next = g_gc_gray_head;
        g_gc_gray_head = c;
#if !defined(__wasm__)
        pthread_cond_signal(&g_gc_work_cond);
#endif
    }
#if !defined(__wasm__)
    pthread_mutex_unlock(&g_gc_work_lock);
#endif
    mb->count = 0;
}

static inline void gc_mark_buf_push(GCMarkBuf *mb, void *ptr, uint8_t kind) {
    if (mb->count == GC_GRAY_CHUNK_CAP) gc_mark_buf_flush(mb);
    mb->items[mb->count].ptr = ptr;
    mb->items[mb->count].kind = kind;
    mb->count++;
}

/* Claim mark bit on known-valid GC object `(ptr, kind)`. */
static inline void gc_mark_known(GCMarkBuf *mb, void *ptr, uint8_t kind) {
    if (!ptr || kind == W_GC_KIND_NONE) return;
    if (kind == W_GC_KIND_CHAN) return;
    uint8_t *fp = gc_flags_ptr(ptr, kind);
    if (!fp) return;
    uint8_t cur = __atomic_load_n(fp, __ATOMIC_RELAXED);
    if (cur & W_GC_MARK) return;
    if (cur & W_GC_KEEP) {
        /* Keep/immortal objects are never swept; remembered mutable keep roots
         * are already scanned directly from g_gc_keep_roots. */
        return;
    }
    if (g_gc_mark_minor && (cur & W_GC_OLD)) {
        /* Minor GC stops at the Old generation boundary: all Old->Young edges
         * are seeded from g_gc_old_mutable and g_gc_dirty_hashes! */
        return;
    }
    uint8_t prev = __atomic_fetch_or(fp, W_GC_MARK, __ATOMIC_ACQ_REL);
    if (prev & W_GC_MARK) return;
    if (!gc_kind_is_leaf(ptr, kind)) {
        gc_mark_buf_push(mb, ptr, kind);
    }
}

/* Extract potential heap pointer from either a boxed WValue or a raw aligned
 * pointer (e.g. unboxed LLVM register or closure cell pointer) and validate
 * via the crash-proof radix bitmap before touching memory. */
static inline void gc_mark_word(GCMarkBuf *mb, uint64_t w) {
    uintptr_t cand = 0;
    uint64_t tag = w & W_TAG_MASK;
    if (tag == W_TAG_ARRAY) {
        cand = (uintptr_t)(w & W_ARRAY_PTR_MASK);
    } else if ((w & (W_TAG_MASK | 0xEULL)) == (W_TAG_STRINGSYM | (7ULL << 1))) {
        cand = (uintptr_t)(w & 0x0000FFFFFFFFFFF0ULL);
    } else if ((w >> 48) == 0 && w >= 0x10ULL) {
        cand = (uintptr_t)(w & ~UINT64_C(0xF));
    } else {
        return;
    }
    uint8_t kind = gc_radix_lookup(cand);
    if (kind != W_GC_KIND_NONE) {
        gc_mark_known(mb, (void *)cand, kind);
    }
}

static void gc_trace_object_children(GCMarkBuf *mb, void *p, uint8_t kind) {
    switch (kind) {
        case W_GC_KIND_OBJECT: {
            WObject *o = (WObject *)p;
            uint8_t n = o->ivar_count;
            for (uint8_t i = 0; i < n; i++) {
                gc_mark_word(mb, o->ivars[i]);
            }
            break;
        }
        case W_GC_KIND_ARRAY: {
            WArray *a = (WArray *)p;
            if ((a->ebits == 65 || ((a->ebits == 64 || a->ebits == 66) && a->size <= 64)) &&
                a->slots != NULL && a->size > 0) {
                int32_t st = a->start;
                int32_t sz = a->size;
                for (int32_t i = 0; i < sz; i++) {
                    gc_mark_word(mb, a->slots[st + i]);
                }
            }
            break;
        }
        case W_GC_KIND_HASH: {
            WHash *h = (WHash *)p;
            if (h->keys != NULL && h->values != NULL) {
                uint32_t u = h->used;
                for (uint32_t i = 0; i < u; i++) {
                    WValue k = h->keys[i];
                    if (k == W_MEMO_MISS) continue;
                    gc_mark_word(mb, k);
                    gc_mark_word(mb, h->values[i]);
                }
            }
            break;
        }
        case W_GC_KIND_CLOSURE: {
            WClosure *cl = (WClosure *)p;
            if (cl->capture_count > 0 && cl->captures != NULL) {
                int cnt = cl->capture_count;
                for (int i = 0; i < cnt; i++) {
                    WValue entry = cl->captures[i];
                    /* w_thread_capture_snapshot allocates [caps(cnt), cells(cnt)] in one block */
                    if (entry == (WValue)(uintptr_t)&cl->captures[cnt + i]) {
                        gc_mark_word(mb, cl->captures[cnt + i]);
                    } else {
                        gc_mark_word(mb, entry);
                    }
                }
            }
            break;
        }
        case W_GC_KIND_CELL: {
            uint64_t *words = (uint64_t *)p;
            gc_mark_word(mb, words[0]);
            gc_mark_word(mb, words[1]);
            break;
        }
        case W_GC_KIND_ROPE: {
            WRope *r = (WRope *)p;
            gc_mark_word(mb, r->left);
            gc_mark_word(mb, r->right);
            if (r->flat != 0) gc_mark_word(mb, r->flat);
            break;
        }
        case W_GC_KIND_CHAN: {
            WChan *ch = (WChan *)p;
            if (ch->buffer != NULL && ch->count > 0) {
                if (ch->cap == 0) {
                    gc_mark_word(mb, ch->buffer[0]);
                } else {
                    int64_t idx = ch->head;
                    for (int64_t k = 0; k < ch->count; k++) {
                        gc_mark_word(mb, ch->buffer[idx]);
                        idx++;
                        if (idx == ch->cap) idx = 0;
                    }
                }
            }
            for (WChanWaiter *w = ch->send_waitq; w; w = w->next) gc_mark_word(mb, w->val);
            for (WChanWaiter *w = ch->recv_waitq; w; w = w->next) gc_mark_word(mb, w->val);
            break;
        }
        case W_GC_KIND_SMALL_ARRAY: {
            WSmallArray *sa = (WSmallArray *)p;
            if (sa->ebits == 65 && sa->size > 0) {
                for (uint8_t i = 0; i < sa->size; i++) {
                    WValue elem;
                    memcpy(&elem, sa->slots + (size_t)i * sizeof(WValue), sizeof(WValue));
                    gc_mark_word(mb, elem);
                }
            }
            break;
        }
        case W_GC_KIND_BIG_ARRAY: {
            WBigArray *ba = (WBigArray *)p;
            if (ba->ebits == 65 && ba->slots != NULL && ba->size > 0) {
                WValue *slots = (WValue *)ba->slots;
                for (int64_t i = 0; i < ba->size; i++) {
                    gc_mark_word(mb, slots[ba->start + i]);
                }
            }
            break;
        }
        default:
            break;
    }
}

static void gc_drain_gray_work(void) {
    GCMarkBuf mb;
    mb.count = 0;

    for (;;) {
        GCGrayChunk *chunk = NULL;
#if !defined(__wasm__)
        pthread_mutex_lock(&g_gc_work_lock);
#endif
        chunk = g_gc_gray_head;
        if (chunk) {
            g_gc_gray_head = chunk->next;
            g_gc_active_workers++;
        }
#if !defined(__wasm__)
        pthread_mutex_unlock(&g_gc_work_lock);
#endif
        if (!chunk) break;

        uint32_t n = chunk->count;
        for (uint32_t i = 0; i < n; i++) {
            gc_trace_object_children(&mb, chunk->items[i].ptr, chunk->items[i].kind);
        }
        gc_mark_buf_flush(&mb);

#if !defined(__wasm__)
        pthread_mutex_lock(&g_gc_work_lock);
#endif
        chunk->next = g_gc_gray_free;
        g_gc_gray_free = chunk;
        g_gc_active_workers--;
        int done = (g_gc_gray_head == NULL && g_gc_active_workers == 0);
#if !defined(__wasm__)
        if (done) pthread_cond_broadcast(&g_gc_work_done_cond);
        pthread_mutex_unlock(&g_gc_work_lock);
#else
        (void)done;
#endif
    }
}

#if !defined(__wasm__)
static void *gc_mark_worker_main(void *arg) {
    (void)arg;
    tls_is_gc_worker = 1;
    uint64_t seen_epoch = 0;

    for (;;) {
        pthread_mutex_lock(&g_gc_work_lock);
        while (g_gc_mark_epoch == seen_epoch && g_gc_gray_head == NULL) {
            pthread_cond_wait(&g_gc_work_cond, &g_gc_work_lock);
        }
        seen_epoch = g_gc_mark_epoch;
        pthread_mutex_unlock(&g_gc_work_lock);

        gc_drain_gray_work();
    }
    return NULL;
}
#endif

static void gc_run_parallel_mark(void) {
#if !defined(__wasm__)
    pthread_mutex_lock(&g_gc_work_lock);
    if (g_gc_gray_head != NULL) {
        g_gc_mark_epoch++;
        pthread_cond_broadcast(&g_gc_work_cond);
    }
    pthread_mutex_unlock(&g_gc_work_lock);
#endif

    gc_drain_gray_work();

#if !defined(__wasm__)
    pthread_mutex_lock(&g_gc_work_lock);
    while (g_gc_gray_head != NULL || g_gc_active_workers > 0) {
        pthread_cond_wait(&g_gc_work_done_cond, &g_gc_work_lock);
    }
    pthread_mutex_unlock(&g_gc_work_lock);
#endif
}

/* ---- Concurrent Background Sweeper ---- */

typedef struct GCSweepBatch {
    struct GCSweepBatch *next;
    GCEntry *items;
    size_t   count;
} GCSweepBatch;

#if !defined(__wasm__)
static pthread_mutex_t g_gc_sweep_lock      = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t  g_gc_sweep_cond      = PTHREAD_COND_INITIALIZER;
static pthread_cond_t  g_gc_sweep_done_cond = PTHREAD_COND_INITIALIZER;
static pthread_t       g_gc_sweep_thread;
#endif
static int           g_gc_sweep_thread_started = 0;
static GCSweepBatch *g_gc_sweep_head = NULL;
static GCSweepBatch *g_gc_sweep_tail = NULL;
static int           g_gc_sweep_busy = 0;

static void gc_free_one_dead(const GCEntry *e) {
    void *p = e->ptr;
    size_t est = gc_estimate_bytes(p, e->kind, e->init_bytes);
    switch (e->kind) {
        case W_GC_KIND_OBJECT:
            free(p);
            break;
        case W_GC_KIND_ARRAY: {
            WArray *a = (WArray *)p;
            w_rt_array_release_slots(a->slots, a->ebits, a->cap, a->flags);
            free(a);
            break;
        }
        case W_GC_KIND_HASH: {
            WHash *h = (WHash *)p;
            free(h->keys);
            free(h);
            break;
        }
        case W_GC_KIND_CLOSURE: {
            WClosure *cl = (WClosure *)p;
            if (cl->capture_count > 0) free(cl->captures);
            free(cl);
            break;
        }
        case W_GC_KIND_CELL:
        case W_GC_KIND_STRING:
        case W_GC_KIND_ROPE:
        case W_GC_KIND_SMALL_ARRAY:
            free(p);
            break;
        case W_GC_KIND_BIG_ARRAY: {
            WBigArray *ba = (WBigArray *)p;
            if ((ba->flags & W_FLAG_OWNED) && !(ba->flags & W_FLAG_VIEW)) {
                free(ba->slots);
            }
            free(ba);
            break;
        }
        case W_GC_KIND_STRBUF: {
            WStrBuf *sb = (WStrBuf *)p;
            free(sb->data);
            free(sb);
            break;
        }
        default:
            break;
    }
    atomic_fetch_add_explicit(&g_gc_swept_objects, 1, memory_order_relaxed);
    atomic_fetch_add_explicit(&g_gc_swept_bytes, est, memory_order_relaxed);
}

static void gc_sweep_batch_now(GCSweepBatch *b) {
    for (size_t i = 0; i < b->count; i++) {
        gc_free_one_dead(&b->items[i]);
    }
    free(b->items);
    free(b);
}

#if !defined(__wasm__)
static void *gc_sweep_worker_main(void *arg) {
    (void)arg;
    tls_is_gc_worker = 1;
    for (;;) {
        pthread_mutex_lock(&g_gc_sweep_lock);
        while (g_gc_sweep_head == NULL) {
            g_gc_sweep_busy = 0;
            pthread_cond_broadcast(&g_gc_sweep_done_cond);
            pthread_cond_wait(&g_gc_sweep_cond, &g_gc_sweep_lock);
        }
        GCSweepBatch *b = g_gc_sweep_head;
        g_gc_sweep_head = b->next;
        if (!g_gc_sweep_head) g_gc_sweep_tail = NULL;
        g_gc_sweep_busy = 1;
        pthread_mutex_unlock(&g_gc_sweep_lock);

        gc_sweep_batch_now(b);
    }
    return NULL;
}
#endif

static void gc_enqueue_concurrent_sweep(GCEntry *items, size_t count) {
    if (count == 0) {
        free(items);
        return;
    }
    GCSweepBatch *b = (GCSweepBatch *)calloc(1, sizeof(GCSweepBatch));
    if (!b) {
        for (size_t i = 0; i < count; i++) gc_free_one_dead(&items[i]);
        free(items);
        return;
    }
    b->items = items;
    b->count = count;
#if !defined(__wasm__)
    if (g_gc_sweep_thread_started) {
        pthread_mutex_lock(&g_gc_sweep_lock);
        if (g_gc_sweep_tail) g_gc_sweep_tail->next = b;
        else g_gc_sweep_head = b;
        g_gc_sweep_tail = b;
        g_gc_sweep_busy = 1;
        pthread_cond_signal(&g_gc_sweep_cond);
        pthread_mutex_unlock(&g_gc_sweep_lock);
        return;
    }
#endif
    gc_sweep_batch_now(b);
}

/* ---- Conservative & Exact Root Scanning ---- */

#if defined(__GNUC__) || defined(__clang__)
__attribute__((no_sanitize("address", "thread", "memory")))
#endif
static void gc_scan_memory_range(GCMarkBuf *mb, const void *lo, const void *hi) {
    if (!lo || !hi) return;
    uintptr_t start = ((uintptr_t)lo + 7u) & ~(uintptr_t)7u;
    uintptr_t end   = (uintptr_t)hi & ~(uintptr_t)7u;
    if (end <= start) return;
    /* Guard against bogus stack range (> 64 MiB). */
    if (end - start > (64ULL << 20)) start = end - (64ULL << 20);
    const uint64_t *p = (const uint64_t *)start;
    const uint64_t *e = (const uint64_t *)end;
    while (p < e) {
        gc_mark_word(mb, *p++);
    }
}

static void gc_root_visitor_cb(WValue val, void *ctx) {
    gc_mark_word((GCMarkBuf *)ctx, val);
}

static void gc_range_visitor_cb(const void *lo, const void *hi, void *ctx) {
    gc_scan_memory_range((GCMarkBuf *)ctx, lo, hi);
}

static void gc_scan_binary_data_sections(GCMarkBuf *mb) {
#if defined(__APPLE__)
    uint32_t count = _dyld_image_count();
    for (uint32_t i = 0; i < count; i++) {
        if (i != 0) {
            const char *name = _dyld_get_image_name(i);
            if (!name) continue;
            /* Skip OS / system framework dylibs; scan main executable (0) and
             * any user/JIT loaded Tungsten dylibs. */
            if (strncmp(name, "/System/", 8) == 0 ||
                strncmp(name, "/usr/lib/", 9) == 0 ||
                strncmp(name, "/Library/Apple/", 15) == 0) {
                continue;
            }
        }
        const struct mach_header_64 *hdr =
            (const struct mach_header_64 *)_dyld_get_image_header(i);
        if (!hdr || hdr->magic != MH_MAGIC_64) continue;
        unsigned long sz = 0;
        uint8_t *sec;
        sec = getsectiondata(hdr, "__DATA", "__data", &sz);
        if (sec && sz >= 8) gc_scan_memory_range(mb, sec, sec + sz);
        sec = getsectiondata(hdr, "__DATA", "__bss", &sz);
        if (sec && sz >= 8) gc_scan_memory_range(mb, sec, sec + sz);
        sec = getsectiondata(hdr, "__DATA", "__common", &sz);
        if (sec && sz >= 8) gc_scan_memory_range(mb, sec, sec + sz);
    }
#elif defined(__linux__) && !defined(__wasm__)
    extern char __data_start[] __attribute__((weak));
    extern char _end[] __attribute__((weak));
    if (__data_start && _end && _end > __data_start) {
        gc_scan_memory_range(mb, __data_start, _end);
    }
#else
    (void)mb;
#endif
}

int w_gc_is_live_marked(WValue v) {
    uintptr_t cand = 0;
    uint64_t tag = v & W_TAG_MASK;
    if (tag == W_TAG_ARRAY) {
        cand = (uintptr_t)(v & W_ARRAY_PTR_MASK);
    } else if ((v & (W_TAG_MASK | 0xEULL)) == (W_TAG_STRINGSYM | (7ULL << 1))) {
        cand = (uintptr_t)(v & 0x0000FFFFFFFFFFF0ULL);
    } else if ((v >> 48) == 0 && v >= 0x10ULL) {
        cand = (uintptr_t)(v & ~UINT64_C(0xF));
    } else {
        return 1;
    }
    uint8_t kind = gc_radix_lookup(cand);
    if (kind == W_GC_KIND_NONE) return 1; /* untracked/immortal */
    uint8_t *fp = gc_flags_ptr((void *)cand, kind);
    if (!fp) return 1;
    uint8_t fl = __atomic_load_n(fp, __ATOMIC_ACQUIRE);
    if (fl & (W_GC_MARK | W_GC_KEEP)) return 1;
    if (g_gc_mark_minor && (fl & W_GC_OLD)) return 1;
    return 0;
}

/* ---- Core Collection Driver ---- */

static void gc_ensure_initialized(void *stack_anchor) {
    if (g_gc_initialized) return;
    g_gc_initialized = 1;
    (void)gc_get_or_create_tgc(stack_anchor);

#if !defined(__wasm__)
    long ncpu = sysconf(_SC_NPROCESSORS_ONLN);
    int nw = (ncpu > 1) ? (int)(ncpu > GC_MAX_WORKERS ? GC_MAX_WORKERS : ncpu - 1) : 0;
    if (nw > GC_MAX_WORKERS) nw = GC_MAX_WORKERS;
    for (int i = 0; i < nw; i++) {
        if (pthread_create(&g_gc_workers[g_gc_worker_count], NULL, gc_mark_worker_main, NULL) == 0) {
            pthread_detach(g_gc_workers[g_gc_worker_count]);
            g_gc_worker_count++;
        }
    }
    if (pthread_create(&g_gc_sweep_thread, NULL, gc_sweep_worker_main, NULL) == 0) {
        pthread_detach(g_gc_sweep_thread);
        g_gc_sweep_thread_started = 1;
    }
#endif
}

static int gc_all_mutators_stopped_locked(WThreadGC *caller) {
    for (WThreadGC *t = g_gc_threads; t; t = t->next) {
        if (t == caller) continue;
        int st = atomic_load_explicit(&t->state, memory_order_acquire);
        if (st == W_TGC_RUNNING) return 0;
    }
    return 1;
}

static void gc_collect_internal(int full_major, void *pinned_new_ptr) {
    if (!g_gc_initialized) return;

    jmp_buf caller_jb;
    (void)W_FAST_SETJMP(caller_jb);
    WThreadGC *caller = gc_get_or_create_tgc((void *)&caller_jb);
    if (caller) {
        memcpy(&caller->saved_regs, &caller_jb, sizeof(jmp_buf));
        caller->saved_sp = (void *)&caller_jb;
    }

#if !defined(__wasm__)
    pthread_mutex_lock(&g_gc_stw_lock);
    if (atomic_load_explicit(&g_gc_in_collection, memory_order_relaxed)) {
        pthread_mutex_unlock(&g_gc_stw_lock);
        w_gc_safepoint_slow();
        return;
    }
    atomic_store_explicit(&g_gc_in_collection, 1, memory_order_release);
    atomic_store_explicit(&g_gc_safepoint_req, 1, memory_order_seq_cst);

    /* Wait for any active running mutator threads to reach a safepoint or block
     * (bounded wait of 50 ms so an uninstrumented C compute thread cannot hang). */
    int waited_rounds = 0;
    while (!gc_all_mutators_stopped_locked(caller) && waited_rounds < 500) {
        struct timespec ts = {0, 100000L}; /* 100 us */
#ifdef __APPLE__
        pthread_cond_timedwait_relative_np(&g_gc_park_cond, &g_gc_stw_lock, &ts);
#else
        struct timespec now;
        clock_gettime(CLOCK_REALTIME, &now);
        now.tv_nsec += ts.tv_nsec;
        if (now.tv_nsec >= 1000000000L) { now.tv_sec++; now.tv_nsec -= 1000000000L; }
        pthread_cond_timedwait(&g_gc_park_cond, &g_gc_stw_lock, &now);
#endif
        waited_rounds++;
    }

    pthread_mutex_lock(&g_gc_alloc_lock);
#else
    atomic_store_explicit(&g_gc_in_collection, 1, memory_order_release);
#endif

    /* 1. Flush all thread-local nursery buffers into g_gc_young + radix map. */
    for (WThreadGC *t = g_gc_threads; t; t = t->next) {
        gc_flush_nursery_locked(t);
    }

    /* Auto-promote to Major GC when Old generation exceeds threshold. */
    if (!full_major && g_gc_old_bytes >= g_gc_old_threshold) {
        full_major = 1;
    }
    g_gc_mark_minor = full_major ? 0 : 1;

    /* 2. Seed roots into gray work queue. */
    GCMarkBuf root_mb;
    root_mb.count = 0;

    if (pinned_new_ptr) {
        uint8_t pk = gc_radix_lookup((uintptr_t)pinned_new_ptr);
        if (pk != W_GC_KIND_NONE) gc_mark_known(&root_mb, pinned_new_ptr, pk);
    }

    /* 2a. Thread stacks, saved register snapshots, and thread-local reuse slots. */
    for (WThreadGC *t = g_gc_threads; t; t = t->next) {
        int st = atomic_load_explicit(&t->state, memory_order_acquire);
        if (st == W_TGC_DEAD) continue;
        gc_scan_memory_range(&root_mb, &t->saved_regs, (const uint8_t *)&t->saved_regs + sizeof(jmp_buf));
        if (t->saved_sp && t->stack_top) {
            if ((uintptr_t)t->saved_sp <= (uintptr_t)t->stack_top) {
                gc_scan_memory_range(&root_mb, t->saved_sp, t->stack_top);
            } else {
                gc_scan_memory_range(&root_mb, t->stack_top, t->saved_sp);
            }
        }
        for (size_t r = 0; r < t->reuse_count; r++) {
            if (t->reuse_slots[r]) gc_mark_word(&root_mb, *t->reuse_slots[r]);
        }
        if (t->exc_stack_ptr) {
            for (WExceptionFrame *ef = *t->exc_stack_ptr; ef; ef = ef->prev) {
                gc_mark_word(&root_mb, ef->error);
            }
        }
        if (t->br_stack_ptr) {
            for (WBlockReturnFrame *bf = *t->br_stack_ptr; bf; bf = bf->prev) {
                gc_mark_word(&root_mb, bf->value);
            }
        }
        if (t->cleanup_stack_ptr && t->cleanup_top_ptr) {
            WCleanupEntry *cs = *t->cleanup_stack_ptr;
            int top = *t->cleanup_top_ptr;
            if (cs && top > 0) {
                for (int c = 0; c < top; c++) gc_mark_word(&root_mb, cs[c].value);
            }
        }
    }

    /* 2b. Binary __DATA / .bss globals (@global.*, @cvar.*, @class.*). */
    gc_scan_binary_data_sections(&root_mb);

    /* 2c. Goroutine stacks/contexts and runtime C globals (memo, signal, classes). */
    w_rt_gc_scan_goroutines(gc_root_visitor_cb, gc_range_visitor_cb, &root_mb);
    w_rt_gc_scan_runtime_globals(gc_root_visitor_cb, &root_mb);
    w_rt_gc_scan_os_thread_roots(gc_root_visitor_cb, &root_mb);

    /* 2d. Mutable Keep roots (immortal boot containers whose slots may reference heap objects). */
    for (size_t i = 0; i < g_gc_keep_roots.count; i++) {
        gc_trace_object_children(&root_mb, g_gc_keep_roots.items[i].ptr, g_gc_keep_roots.items[i].kind);
    }

    /* 2e. For Minor GC, scan remembered Old->Young containers + dirty Old Hashes! */
    if (g_gc_mark_minor) {
        for (size_t i = 0; i < g_gc_old_mutable.count; i++) {
            gc_trace_object_children(&root_mb, g_gc_old_mutable.items[i].ptr, g_gc_old_mutable.items[i].kind);
        }
        for (size_t i = 0; i < g_gc_dirty_count; i++) {
            WHash *dh = g_gc_dirty_hashes[i];
            if ((dh->gc_flags & W_GC_KEEP) == 0) {
                dh->gc_flags &= (uint8_t)~W_GC_DIRTY;
                dh->flags |= W_HASH_FLAG_OLD_CLEAN;
                gc_trace_object_children(&root_mb, dh, W_GC_KIND_HASH);
            }
        }
        g_gc_dirty_count = 0;
    } else {
        /* Major GC clears dirty hash list and traces the full graph from roots. */
        for (size_t i = 0; i < g_gc_dirty_count; i++) {
            g_gc_dirty_hashes[i]->gc_flags &= (uint8_t)~W_GC_DIRTY;
        }
        g_gc_dirty_count = 0;
    }

    gc_mark_buf_flush(&root_mb);

    /* 3. Parallel Mark to fixpoint (including zero-copy view -> parent retention). */
    for (;;) {
        gc_run_parallel_mark();
        GCMarkBuf view_mb = { .count = 0 };
        int added = w_rt_gc_propagate_views(gc_root_visitor_cb, &view_mb);
        gc_mark_buf_flush(&view_mb);
        if (!added) break;
    }

    /* Prune dead views from w_view_table before detaching dead arrays. */
    w_rt_gc_prune_views();

    /* 4. Partition survivors vs dead objects & clear radix bits for dead objects. */
    size_t max_dead = g_gc_young.count + (full_major ? g_gc_old.count : 0);
    GCEntry *dead_items = max_dead ? (GCEntry *)malloc(max_dead * sizeof(GCEntry)) : NULL;
    size_t dead_count = 0;

    if (full_major) {
        /* Compact Old generation first */
        size_t out_old = 0;
        size_t new_old_bytes = 0;
        g_gc_old_mutable.count = 0;

        for (size_t i = 0; i < g_gc_old.count; i++) {
            GCEntry e = g_gc_old.items[i];
            uint8_t *fp = gc_flags_ptr(e.ptr, e.kind);
            uint8_t fl = fp ? *fp : W_GC_MARK;
            if (fl & W_GC_KEEP) {
                continue;
            }
            if (fl & W_GC_MARK) {
                *fp = (uint8_t)((fl & ~(W_GC_MARK | W_GC_DIRTY)) | W_GC_OLD);
                if (e.kind == W_GC_KIND_HASH) ((WHash *)e.ptr)->flags |= W_HASH_FLAG_OLD_CLEAN;
                g_gc_old.items[out_old++] = e;
                new_old_bytes += gc_estimate_bytes(e.ptr, e.kind, e.init_bytes);
                if (gc_kind_needs_old_remembered(e.ptr, e.kind)) {
                    gc_vec_push(&g_gc_old_mutable, e);
                }
            } else {
                gc_radix_remove(e.ptr);
                if (dead_items) dead_items[dead_count++] = e;
                else gc_free_one_dead(&e);
            }
        }
        g_gc_old.count = out_old;
        g_gc_old_bytes = new_old_bytes;
    }

    /* Partition Young nursery: promote survivors to Old, detach unmarked for concurrent sweep */
    for (size_t i = 0; i < g_gc_young.count; i++) {
        GCEntry e = g_gc_young.items[i];
        uint8_t *fp = gc_flags_ptr(e.ptr, e.kind);
        uint8_t fl = fp ? *fp : W_GC_MARK;
        if (fl & W_GC_KEEP) {
            continue;
        }
        if (fl & W_GC_MARK) {
            *fp = (uint8_t)((fl & ~(W_GC_MARK | W_GC_DIRTY)) | W_GC_OLD);
            if (e.kind == W_GC_KIND_HASH) ((WHash *)e.ptr)->flags |= W_HASH_FLAG_OLD_CLEAN;
            gc_vec_push(&g_gc_old, e);
            g_gc_old_bytes += gc_estimate_bytes(e.ptr, e.kind, e.init_bytes);
            if (gc_kind_needs_old_remembered(e.ptr, e.kind)) {
                gc_vec_push(&g_gc_old_mutable, e);
            }
        } else {
            gc_radix_remove(e.ptr);
            if (dead_items) dead_items[dead_count++] = e;
            else gc_free_one_dead(&e);
        }
    }
    g_gc_young.count = 0;
    g_gc_young_bytes = 0;

    if (full_major) {
        size_t next_thresh = g_gc_old_bytes * 2u;
        if (next_thresh < 64u * 1024u * 1024u) next_thresh = 64u * 1024u * 1024u;
        g_gc_old_threshold = next_thresh;
        atomic_fetch_add_explicit(&g_gc_major_count, 1, memory_order_relaxed);
    } else {
        atomic_fetch_add_explicit(&g_gc_minor_count, 1, memory_order_relaxed);
    }

#if !defined(__wasm__)
    pthread_mutex_unlock(&g_gc_alloc_lock);

    /* 5. Resume all mutator threads immediately before concurrent background sweep! */
    atomic_store_explicit(&g_gc_safepoint_req, 0, memory_order_release);
    atomic_store_explicit(&g_gc_in_collection, 0, memory_order_release);
    pthread_cond_broadcast(&g_gc_resume_cond);
    pthread_mutex_unlock(&g_gc_stw_lock);
#else
    atomic_store_explicit(&g_gc_safepoint_req, 0, memory_order_release);
    atomic_store_explicit(&g_gc_in_collection, 0, memory_order_release);
#endif

    /* 6. Hand dead list to the concurrent background sweeper thread. */
    gc_enqueue_concurrent_sweep(dead_items, dead_count);
}

/* ---- Runtime Fast-Path Slow Callbacks ---- */

static inline void gc_set_no_pool_flag(void *p, uint8_t kind) {
    switch (kind) {
        case W_GC_KIND_OBJECT: ((WObject *)p)->flags |= W_FLAG_GC_NO_POOL; break;
        case W_GC_KIND_ARRAY:  ((WArray *)p)->flags  |= W_FLAG_GC_NO_POOL; break;
        case W_GC_KIND_HASH:   ((WHash *)p)->flags   |= W_FLAG_GC_NO_POOL; break;
        case W_GC_KIND_STRBUF: ((WStrBuf *)p)->flags |= W_FLAG_GC_NO_POOL; break;
        default: break;
    }
}

void W_GC_COLD_SLOW w_gc_register_slow(void *ptr, uint8_t kind, size_t bytes) {
    if (!ptr || tls_is_gc_worker) return;
    uint8_t *fp = gc_flags_ptr(ptr, kind);
    if (fp) {
        if (*fp & W_GC_TRACKED) return;
        *fp |= W_GC_TRACKED;
    }
    gc_set_no_pool_flag(ptr, kind);

    WThreadGC *t = gc_get_or_create_tgc(&ptr);
    GCEntry e;
    e.ptr = ptr;
    e.init_bytes = bytes > UINT32_MAX ? UINT32_MAX : (uint32_t)bytes;
    e.kind = kind;

    if (__builtin_expect(t != NULL && t->nursery_count < GC_NURSERY_LOCAL_MAX, 1)) {
        t->nursery[t->nursery_count++] = e;
        t->nursery_bytes += bytes;
        if (__builtin_expect(t->nursery_count < GC_NURSERY_LOCAL_MAX &&
                             t->nursery_bytes < (4u * 1024u * 1024u) &&
                             !atomic_load_explicit(&g_gc_safepoint_req, memory_order_relaxed), 1)) {
            return;
        }
    }

    int trigger_auto = 0;
#if !defined(__wasm__)
    pthread_mutex_lock(&g_gc_alloc_lock);
#endif
    if (t) {
        gc_flush_nursery_locked(t);
    } else {
        gc_radix_insert(e.ptr, e.kind);
        gc_vec_push(&g_gc_young, e);
        g_gc_young_bytes += bytes;
    }
    if (g_gc_auto && (!t || !t->internal_no_auto) &&
        !atomic_load_explicit(&g_gc_in_collection, memory_order_relaxed) &&
        g_gc_young_bytes >= g_gc_young_threshold) {
        trigger_auto = 1;
    }
#if !defined(__wasm__)
    pthread_mutex_unlock(&g_gc_alloc_lock);
#endif

    if (atomic_load_explicit(&g_gc_safepoint_req, memory_order_relaxed)) {
        w_gc_safepoint_slow();
    } else if (trigger_auto) {
        gc_collect_internal(0, ptr);
    }
}

void W_GC_COLD_SLOW w_gc_write_barrier_hash_slow(WHash *h) {
    if (!h) return;
    h->flags &= (uint8_t)~W_HASH_FLAG_OLD_CLEAN;
    if (h->gc_flags & (W_GC_DIRTY | W_GC_KEEP)) return;
#if !defined(__wasm__)
    pthread_mutex_lock(&g_gc_alloc_lock);
#endif
    if ((h->gc_flags & (W_GC_OLD | W_GC_DIRTY | W_GC_KEEP)) == W_GC_OLD) {
        h->gc_flags |= W_GC_DIRTY;
        h->flags &= (uint8_t)~W_HASH_FLAG_OLD_CLEAN;
        if (g_gc_dirty_count == g_gc_dirty_cap) {
            size_t ncap = g_gc_dirty_cap ? g_gc_dirty_cap * 2u : 256u;
            WHash **nh = (WHash **)realloc(g_gc_dirty_hashes, ncap * sizeof(WHash *));
            if (nh) {
                g_gc_dirty_hashes = nh;
                g_gc_dirty_cap = ncap;
            }
        }
        if (g_gc_dirty_count < g_gc_dirty_cap) {
            g_gc_dirty_hashes[g_gc_dirty_count++] = h;
        }
    }
#if !defined(__wasm__)
    pthread_mutex_unlock(&g_gc_alloc_lock);
#endif
}

void W_GC_COLD_SLOW w_gc_register_reuse_slot_slow(WValue *slot) {
    if (!slot) return;
    WThreadGC *t = gc_get_or_create_tgc(&slot);
    if (!t) return;
    for (size_t i = 0; i < t->reuse_count; i++) {
        if (t->reuse_slots[i] == slot) return;
    }
    if (t->reuse_count == t->reuse_cap) {
        size_t ncap = t->reuse_cap ? t->reuse_cap * 2u : 16u;
        WValue **ns = (WValue **)realloc(t->reuse_slots, ncap * sizeof(WValue *));
        if (!ns) return;
        t->reuse_slots = ns;
        t->reuse_cap = ncap;
    }
    t->reuse_slots[t->reuse_count++] = slot;
}

/* ---- Public User-Facing GC API (core/gc.w) ---- */

static void gc_promote_entry_to_keep_locked(GCEntry e);
static void gc_adopt_pre_gc_roots(void *stack_anchor);

WValue w_gc_enable(void) {
    int was_disabled = (g_gc_auto == 0);
    int first_track  = (g_gc_track == 0);
    gc_ensure_initialized(&was_disabled);
    if (first_track) {
        gc_adopt_pre_gc_roots(&was_disabled);
    }
    g_gc_track = 1;
    g_gc_auto  = 1;
    return was_disabled ? W_TRUE : W_FALSE;
}

WValue w_gc_disable(void) {
    int was_disabled = (g_gc_auto == 0);
    g_gc_auto = 0;
    return was_disabled ? W_TRUE : W_FALSE;
}

WValue w_gc_enabled_p(void) {
    return g_gc_auto ? W_TRUE : W_FALSE;
}

WValue w_gc_tracking_p(void) {
    return g_gc_track ? W_TRUE : W_FALSE;
}

WValue w_gc_start(WValue full_mark) {
    if (!g_gc_initialized) return W_NIL;
    int full = (full_mark != W_FALSE && full_mark != W_NIL);
    gc_collect_internal(full, NULL);
    return W_NIL;
}

WValue w_gc_minor(void) {
    if (!g_gc_initialized) return W_NIL;
    gc_collect_internal(0, NULL);
    return W_NIL;
}

WValue w_gc_major(void) {
    if (!g_gc_initialized) return W_NIL;
    gc_collect_internal(1, NULL);
    return W_NIL;
}

WValue w_gc_wait_sweep(void) {
#if !defined(__wasm__)
    if (!g_gc_sweep_thread_started) return W_NIL;
    pthread_mutex_lock(&g_gc_sweep_lock);
    while (g_gc_sweep_head != NULL || g_gc_sweep_busy) {
        pthread_cond_wait(&g_gc_sweep_done_cond, &g_gc_sweep_lock);
    }
    pthread_mutex_unlock(&g_gc_sweep_lock);
#endif
    return W_NIL;
}

static void gc_promote_entry_to_keep_locked(GCEntry e) {
    uint8_t *fp = gc_flags_ptr(e.ptr, e.kind);
    if (!fp) return;
    if (*fp & W_GC_KEEP) return;
    *fp = (uint8_t)((*fp & ~(W_GC_MARK | W_GC_DIRTY)) | W_GC_KEEP | W_GC_TRACKED);
    if (e.kind == W_GC_KIND_HASH) ((WHash *)e.ptr)->flags &= (uint8_t)~W_HASH_FLAG_OLD_CLEAN;
    gc_set_no_pool_flag(e.ptr, e.kind);
    gc_vec_push(&g_gc_keep_all_vec, e);
    g_gc_keep_bytes += gc_estimate_bytes(e.ptr, e.kind, e.init_bytes);
    if (!gc_kind_is_leaf(e.ptr, e.kind)) {
        /* Mutable or pointer-bearing keep containers stay in g_gc_keep_roots so
         * references stored into them later are always walked during mark. */
        gc_vec_push(&g_gc_keep_roots, e);
    }
}

static void gc_adopt_word_locked(uint64_t w, int exact_slot) {
    (void)exact_slot;
    uintptr_t cand = 0;
    uint8_t kind = W_GC_KIND_NONE;
    size_t min_sz = 0;
    uint64_t tag = w & W_TAG_MASK;

    if (tag == W_TAG_ARRAY) {
        cand = (uintptr_t)(w & W_ARRAY_PTR_MASK);
        kind = W_GC_KIND_ARRAY;
        min_sz = sizeof(WArray);
    } else if ((w & (W_TAG_MASK | 0xEULL)) == (W_TAG_STRINGSYM | (7ULL << 1))) {
        cand = (uintptr_t)(w & 0x0000FFFFFFFFFFF0ULL);
        kind = W_GC_KIND_STRING;
        min_sz = sizeof(WString);
    } else if ((w >> 48) == 0 && w >= 0x10000ULL) {
        int sub = (int)(w & 0xFULL);
        cand = (uintptr_t)(w & ~UINT64_C(0xF));
        switch (sub) {
            case W_SUBTAG_INSTANCE:
                kind = W_GC_KIND_OBJECT;
                min_sz = sizeof(WObject);
                break;
            case W_SUBTAG_HASH:
                kind = W_GC_KIND_HASH;
                min_sz = sizeof(WHash);
                break;
            case W_SUBTAG_CLOSURE:
                kind = W_GC_KIND_CLOSURE;
                min_sz = sizeof(WClosure);
                break;
            case W_SUBTAG_STRBUF:
                kind = W_GC_KIND_STRBUF;
                min_sz = sizeof(WStrBuf);
                break;
            case W_SUBTAG_SMALL_ARRAY:
                kind = W_GC_KIND_SMALL_ARRAY;
                min_sz = sizeof(WSmallArray) + 1u;
                break;
            case W_SUBTAG_GENERIC:
                min_sz = 16u;
                break;
            default:
                return;
        }
    } else {
        return;
    }

    if ((cand & 0xFULL) != 0 || cand < 0x10000ULL || (cand >> 48) != 0) return;
    if (gc_radix_lookup(cand) != W_GC_KIND_NONE) return;

#if defined(__APPLE__)
    size_t msz = malloc_size((const void *)cand);
    if (msz < min_sz) return;
#else
    if (!exact_slot && tag != W_TAG_ARRAY && tag != W_TAG_STRINGSYM) return;
#endif

    if (kind == W_GC_KIND_NONE) {
        uint8_t gtype = *(const uint8_t *)cand;
        if (gtype == W_TYPE_ROPE) {
#if defined(__APPLE__)
            if (msz < sizeof(WRope)) return;
#endif
            kind = W_GC_KIND_ROPE;
        } else if (gtype == W_TYPE_BIG_ARRAY) {
#if defined(__APPLE__)
            if (msz < sizeof(WBigArray)) return;
#endif
            kind = W_GC_KIND_BIG_ARRAY;
        } else {
            return;
        }
    }

    if (kind == W_GC_KIND_ARRAY) {
        const WArray *a = (const WArray *)cand;
        if (a->size < 0 || a->cap < 0 || a->start < 0 || a->start + a->size > a->cap) return;
    } else if (kind == W_GC_KIND_HASH) {
        const WHash *h = (const WHash *)cand;
        if (h->used > h->cap || (h->cap != 0 && (h->cap & (h->cap - 1u)) != 0)) return;
    } else if (kind == W_GC_KIND_OBJECT) {
        const WObject *o = (const WObject *)cand;
        if (o->class_id == 0 || o->class_id >= g_next_class_id) return;
    }

    gc_radix_insert((void *)cand, kind);
    GCEntry e = { .ptr = (void *)cand, .init_bytes = 0, .kind = kind };
    gc_promote_entry_to_keep_locked(e);

    /* Recursively adopt exact children inside pre-GC containers. */
    switch (kind) {
        case W_GC_KIND_OBJECT: {
            WObject *o = (WObject *)cand;
            for (uint8_t i = 0; i < o->ivar_count; i++) gc_adopt_word_locked(o->ivars[i], 1);
            break;
        }
        case W_GC_KIND_ARRAY: {
            WArray *a = (WArray *)cand;
            if (a->ebits == 65 && a->slots != NULL && a->size > 0) {
                for (int32_t i = 0; i < a->size; i++) gc_adopt_word_locked(a->slots[a->start + i], 1);
            }
            break;
        }
        case W_GC_KIND_HASH: {
            WHash *h = (WHash *)cand;
            if (h->keys != NULL && h->values != NULL) {
                for (uint32_t i = 0; i < h->used; i++) {
                    if (h->keys[i] == W_MEMO_MISS) continue;
                    gc_adopt_word_locked(h->keys[i], 1);
                    gc_adopt_word_locked(h->values[i], 1);
                }
            }
            break;
        }
        case W_GC_KIND_CLOSURE: {
            WClosure *cl = (WClosure *)cand;
            if (cl->capture_count > 0 && cl->captures != NULL) {
                int cnt = cl->capture_count;
                for (int i = 0; i < cnt; i++) {
                    WValue entry = cl->captures[i];
                    if (entry == (WValue)(uintptr_t)&cl->captures[cnt + i]) {
                        gc_adopt_word_locked(cl->captures[cnt + i], 1);
                    } else {
                        gc_adopt_word_locked(entry, 1);
                    }
                }
            }
            break;
        }
        case W_GC_KIND_ROPE: {
            WRope *r = (WRope *)cand;
            gc_adopt_word_locked(r->left, 1);
            gc_adopt_word_locked(r->right, 1);
            if (r->flat != 0) gc_adopt_word_locked(r->flat, 1);
            break;
        }
        case W_GC_KIND_SMALL_ARRAY: {
            WSmallArray *sa = (WSmallArray *)cand;
            if (sa->ebits == 65 && sa->size > 0) {
                for (uint8_t i = 0; i < sa->size; i++) {
                    WValue elem;
                    memcpy(&elem, sa->slots + (size_t)i * sizeof(WValue), sizeof(WValue));
                    gc_adopt_word_locked(elem, 1);
                }
            }
            break;
        }
        case W_GC_KIND_BIG_ARRAY: {
            WBigArray *ba = (WBigArray *)cand;
            if (ba->ebits == 65 && ba->slots != NULL && ba->size > 0) {
                WValue *slots = (WValue *)ba->slots;
                for (int64_t i = 0; i < ba->size; i++) gc_adopt_word_locked(slots[ba->start + i], 1);
            }
            break;
        }
        default:
            break;
    }
}

#if defined(__GNUC__) || defined(__clang__)
__attribute__((no_sanitize("address", "thread", "memory")))
#endif
static void gc_adopt_range_locked(const void *lo, const void *hi) {
    if (!lo || !hi) return;
    uintptr_t start = ((uintptr_t)lo + 7u) & ~(uintptr_t)7u;
    uintptr_t end   = (uintptr_t)hi & ~(uintptr_t)7u;
    if (end <= start) return;
    if (end - start > (64ULL << 20)) start = end - (64ULL << 20);
    const uint64_t *p = (const uint64_t *)start;
    const uint64_t *e = (const uint64_t *)end;
    while (p < e) {
        gc_adopt_word_locked(*p++, 0);
    }
}

static void gc_adopt_root_cb(WValue val, void *ctx) {
    (void)ctx;
    gc_adopt_word_locked(val, 1);
}

static void gc_adopt_pre_gc_roots(void *stack_anchor) {
    WThreadGC *t = gc_get_or_create_tgc(stack_anchor);
#if !defined(__wasm__)
    pthread_mutex_lock(&g_gc_alloc_lock);
#endif
    if (t && t->stack_top && stack_anchor) {
        if ((uintptr_t)stack_anchor <= (uintptr_t)t->stack_top) {
            gc_adopt_range_locked(stack_anchor, t->stack_top);
        } else {
            gc_adopt_range_locked(t->stack_top, stack_anchor);
        }
    }
#if defined(__APPLE__)
    uint32_t count = _dyld_image_count();
    for (uint32_t i = 0; i < count; i++) {
        if (i != 0) {
            const char *name = _dyld_get_image_name(i);
            if (!name) continue;
            if (strncmp(name, "/System/", 8) == 0 ||
                strncmp(name, "/usr/lib/", 9) == 0 ||
                strncmp(name, "/Library/Apple/", 15) == 0) continue;
        }
        const struct mach_header_64 *hdr =
            (const struct mach_header_64 *)_dyld_get_image_header(i);
        if (!hdr || hdr->magic != MH_MAGIC_64) continue;
        unsigned long sz = 0;
        uint8_t *sec;
        sec = getsectiondata(hdr, "__DATA", "__data", &sz);
        if (sec && sz >= 8) gc_adopt_range_locked(sec, sec + sz);
        sec = getsectiondata(hdr, "__DATA", "__bss", &sz);
        if (sec && sz >= 8) gc_adopt_range_locked(sec, sec + sz);
        sec = getsectiondata(hdr, "__DATA", "__common", &sz);
        if (sec && sz >= 8) gc_adopt_range_locked(sec, sec + sz);
    }
#elif defined(__linux__) && !defined(__wasm__)
    extern char __data_start[] __attribute__((weak));
    extern char _end[] __attribute__((weak));
    if (__data_start && _end && _end > __data_start) {
        gc_adopt_range_locked(__data_start, _end);
    }
#endif
    w_rt_gc_scan_runtime_globals(gc_adopt_root_cb, NULL);
#if !defined(__wasm__)
    pthread_mutex_unlock(&g_gc_alloc_lock);
#endif
}

WValue w_gc_keep(WValue val) {
    uintptr_t cand = 0;
    uint64_t tag = val & W_TAG_MASK;
    if (tag == W_TAG_ARRAY) {
        cand = (uintptr_t)(val & W_ARRAY_PTR_MASK);
    } else if ((val & (W_TAG_MASK | 0xEULL)) == (W_TAG_STRINGSYM | (7ULL << 1))) {
        cand = (uintptr_t)(val & 0x0000FFFFFFFFFFF0ULL);
    } else if ((val >> 48) == 0 && val >= 0x10ULL) {
        cand = (uintptr_t)(val & ~UINT64_C(0xF));
    } else {
        return val;
    }

    WThreadGC *t = tls_gc;
#if !defined(__wasm__)
    pthread_mutex_lock(&g_gc_alloc_lock);
#endif
    if (t) gc_flush_nursery_locked(t);
    uint8_t kind = gc_radix_lookup(cand);
    if (kind != W_GC_KIND_NONE) {
        GCEntry e = { .ptr = (void *)cand, .init_bytes = 0, .kind = kind };
        gc_promote_entry_to_keep_locked(e);
    }
#if !defined(__wasm__)
    pthread_mutex_unlock(&g_gc_alloc_lock);
#endif
    return val;
}

WValue w_gc_keep_all(void) {
    if (!g_gc_initialized) return w_int(0);
    /* Run a major GC first so dead boot temporaries are reclaimed, then pin
     * every surviving object into the immortal Keep space. */
    gc_collect_internal(1, NULL);

    size_t promoted = 0;
#if !defined(__wasm__)
    pthread_mutex_lock(&g_gc_alloc_lock);
#endif
    for (WThreadGC *t = g_gc_threads; t; t = t->next) {
        gc_flush_nursery_locked(t);
    }
    for (size_t i = 0; i < g_gc_old.count; i++) {
        gc_promote_entry_to_keep_locked(g_gc_old.items[i]);
        promoted++;
    }
    g_gc_old.count = 0;
    g_gc_old_bytes = 0;
    g_gc_old_mutable.count = 0;

    for (size_t i = 0; i < g_gc_young.count; i++) {
        gc_promote_entry_to_keep_locked(g_gc_young.items[i]);
        promoted++;
    }
    g_gc_young.count = 0;
    g_gc_young_bytes = 0;
#if !defined(__wasm__)
    pthread_mutex_unlock(&g_gc_alloc_lock);
#endif
    return w_int((int64_t)promoted);
}

WValue w_gc_count(void) {
    uint64_t c = atomic_load_explicit(&g_gc_minor_count, memory_order_relaxed) +
                 atomic_load_explicit(&g_gc_major_count, memory_order_relaxed);
    return w_int((int64_t)c);
}

WValue w_gc_young_threshold_get(void) {
    return w_int((int64_t)g_gc_young_threshold);
}

WValue w_gc_young_threshold_set(WValue bytes) {
    int64_t v = w_to_i64(bytes);
    if (v >= 65536) g_gc_young_threshold = (size_t)v;
    return w_int((int64_t)g_gc_young_threshold);
}

WValue w_gc_old_threshold_get(void) {
    return w_int((int64_t)g_gc_old_threshold);
}

WValue w_gc_old_threshold_set(WValue bytes) {
    int64_t v = w_to_i64(bytes);
    if (v >= 262144) g_gc_old_threshold = (size_t)v;
    return w_int((int64_t)g_gc_old_threshold);
}

WValue w_gc_stats(void) {
    size_t young_objs = 0, old_objs = 0, keep_objs = 0;
    size_t young_b = 0, old_b = 0, keep_b = 0;

#if !defined(__wasm__)
    pthread_mutex_lock(&g_gc_alloc_lock);
#endif
    for (WThreadGC *t = g_gc_threads; t; t = t->next) {
        young_objs += t->nursery_count;
        young_b += t->nursery_bytes;
    }
    young_objs += g_gc_young.count;
    old_objs    = g_gc_old.count;
    keep_objs   = g_gc_keep_all_vec.count;
    young_b    += g_gc_young_bytes;
    old_b       = g_gc_old_bytes;
    keep_b      = g_gc_keep_bytes;
#if !defined(__wasm__)
    pthread_mutex_unlock(&g_gc_alloc_lock);
#endif

    uint64_t minor_c = atomic_load_explicit(&g_gc_minor_count, memory_order_relaxed);
    uint64_t major_c = atomic_load_explicit(&g_gc_major_count, memory_order_relaxed);
    uint64_t swept_o = atomic_load_explicit(&g_gc_swept_objects, memory_order_relaxed);
    uint64_t swept_b = atomic_load_explicit(&g_gc_swept_bytes, memory_order_relaxed);

    WThreadGC *self = tls_gc;
    if (self) self->internal_no_auto = 1;
    WValue h = w_hash_new();
    w_hash_set(h, w_symbol("enabled"),         g_gc_auto ? W_TRUE : W_FALSE);
    w_hash_set(h, w_symbol("tracking"),        g_gc_track ? W_TRUE : W_FALSE);
    w_hash_set(h, w_symbol("count"),           w_int((int64_t)(minor_c + major_c)));
    w_hash_set(h, w_symbol("minor_count"),     w_int((int64_t)minor_c));
    w_hash_set(h, w_symbol("major_count"),     w_int((int64_t)major_c));
    w_hash_set(h, w_symbol("live_objects"),    w_int((int64_t)(young_objs + old_objs + keep_objs)));
    w_hash_set(h, w_symbol("young_objects"),   w_int((int64_t)young_objs));
    w_hash_set(h, w_symbol("old_objects"),     w_int((int64_t)old_objs));
    w_hash_set(h, w_symbol("keep_objects"),    w_int((int64_t)keep_objs));
    w_hash_set(h, w_symbol("live_bytes"),      w_int((int64_t)(young_b + old_b + keep_b)));
    w_hash_set(h, w_symbol("young_bytes"),     w_int((int64_t)young_b));
    w_hash_set(h, w_symbol("old_bytes"),       w_int((int64_t)old_b));
    w_hash_set(h, w_symbol("keep_bytes"),      w_int((int64_t)keep_b));
    w_hash_set(h, w_symbol("swept_objects"),   w_int((int64_t)swept_o));
    w_hash_set(h, w_symbol("swept_bytes"),     w_int((int64_t)swept_b));
    w_hash_set(h, w_symbol("young_threshold"), w_int((int64_t)g_gc_young_threshold));
    w_hash_set(h, w_symbol("old_threshold"),   w_int((int64_t)g_gc_old_threshold));
    w_hash_set(h, w_symbol("worker_threads"),  w_int((int64_t)g_gc_worker_count));
    if (self) self->internal_no_auto = 0;
    return h;
}
