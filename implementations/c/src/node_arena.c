/*
 * node_arena.c — slab-AST node arena for the C VM (stage 0 bootstrap).
 *
 * Mirrors the arena implementation in runtime/runtime.c so the C VM
 * can execute `ccall_nobox("w_node_alloc", …)` and the field
 * load/store helpers natively during stage 0 interpretation of ast.w.
 * Without this, stage 0's stub returned nil and the slab side never
 * got populated — which is why PR #2 carried a hash-side fallback.
 *
 * Linked into the C VM binary only. The compiled stages (stage 1+)
 * use runtime/runtime.c's arena via the runtime archive — two
 * separate processes, two separate arenas, no symbol clash.
 *
 * The runtime/wvalue.h header is on the include path (-I../../runtime
 * in implementations/c/Makefile), so W_PACKED_NODE encoding helpers
 * (w_box_node / w_node_size_class / w_node_offset / W_NODE_*) are
 * shared with runtime.c. Bit-identical encoding across the bootstrap
 * boundary is what makes stage1 .ll == stage2 .ll hold when the slab
 * is live in both stages.
 */

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "wvalue.h"

/* Inline copy of runtime.h's WNodeArena. Avoids pulling in the full
 * runtime.h, which redeclares w_truthy with a return type that
 * conflicts with wvalue.h's static inline definition. */
typedef struct WNodeArena {
    uint8_t  *base;
    uint32_t  cursor;
    uint32_t  cap;
} WNodeArena;

WNodeArena g_node_arena[4] = {{0}};

/* Indexed by size_class (the 2-bit field in W_PACKED_NODE):
 *   SC_2  = 0:  16 B (2 slots, leaf kinds)
 *   SC_4  = 1:  32 B (4 slots, 3-slot kinds)
 *   SC_8  = 2:  64 B (8 slots, complex kinds)
 *   SC_16 = 3: 128 B (reserved)
 */
const uint32_t g_node_stride[4] = {16, 32, 64, 128};

const uint32_t g_node_initial_cap[4] = {70000, 30000, 26000, 1000};

uint64_t g_ast_schema_hash = 0;

static void node_arena_fatal(const char *msg) {
    fprintf(stderr, "fatal: %s\n", msg);
    exit(1);
}

void w_node_arena_init(void) {
    for (int sc = 0; sc < 4; sc++) {
        g_node_arena[sc].base = NULL;
        /* Reserve offset=0 for tag-only singletons (AST_NIL etc. in
         * ast.w). Their W_PACKED_NODE has sc=0 + offset=0 — schema is
         * `{}` so the slot is never read, but starting cursor at 1
         * keeps real allocations from colliding. Mirrors the change
         * in runtime/runtime.c. */
        g_node_arena[sc].cursor = 1;
        g_node_arena[sc].cap = 0;
        if (g_node_stride[sc] == 0 || g_node_initial_cap[sc] == 0) continue;
        size_t bytes = (size_t)g_node_initial_cap[sc] * g_node_stride[sc];
        g_node_arena[sc].base = (uint8_t *)malloc(bytes);
        if (!g_node_arena[sc].base) node_arena_fatal("w_node_arena_init: malloc failed");
        g_node_arena[sc].cap = g_node_initial_cap[sc];
    }
}

WValue w_node_alloc(int64_t kind, int64_t sc) {
    if (sc < 0 || sc >= 4 || g_node_stride[sc] == 0) {
        node_arena_fatal("w_node_alloc: invalid size class");
    }
    WNodeArena *a = &g_node_arena[sc];
    if (a->cursor == a->cap) {
        uint32_t new_cap = a->cap ? a->cap * 2 : g_node_initial_cap[sc];
        if (new_cap == 0) new_cap = 4096;
        size_t bytes = (size_t)new_cap * g_node_stride[sc];
        uint8_t *new_base = (uint8_t *)realloc(a->base, bytes);
        if (!new_base) node_arena_fatal("w_node_alloc: realloc failed");
        a->base = new_base;
        a->cap = new_cap;
    }
    uint32_t off = a->cursor++;
    return w_box_node((int)kind, (int)sc, (uint64_t)off);
}

void w_ast_sparse_reset(void);  /* forward decl; defined below */

void w_node_arena_reset(void) {
    for (int sc = 0; sc < 4; sc++) {
        free(g_node_arena[sc].base);
        g_node_arena[sc].base = NULL;
        g_node_arena[sc].cursor = 0;
        g_node_arena[sc].cap = 0;
    }
    /* PR #3: sparse meta lifetime is bound to the node arena —
     * both are scoped to a single compile boundary. */
    w_ast_sparse_reset();
}

uint64_t w_ast_schema_hash_compute(void) {
    return 0;
}

WValue w_node_field_load(WValue wnode, int64_t ivar_offset) {
    int sc = w_node_size_class(wnode);
    uint64_t off = w_node_offset(wnode);
    uint8_t *base = g_node_arena[sc].base;
    uint64_t byte_offset = off * (uint64_t)g_node_stride[sc] + (uint64_t)ivar_offset * 8u;
    return *(WValue *)(base + byte_offset);
}

void w_node_field_store(WValue wnode, int64_t ivar_offset, WValue value) {
    int sc = w_node_size_class(wnode);
    uint64_t off = w_node_offset(wnode);
    uint8_t *base = g_node_arena[sc].base;
    uint64_t byte_offset = off * (uint64_t)g_node_stride[sc] + (uint64_t)ivar_offset * 8u;
    *(WValue *)(base + byte_offset) = value;
}

/* ---- AST sparse-field side-table (PR #3) ----
 *
 * Mirror of runtime/runtime.c's implementation. Linked into the C VM
 * binary only — compiled stages (1+) use the runtime.c copy. Two
 * separate processes, two separate maps, no symbol clash.
 *
 * Replaces the pre-PR-#3 Tungsten Hash-of-Hashes `g_ast_sparse_meta`.
 * See runtime/runtime.c for the canonical design notes.
 */
typedef struct {
    int64_t  sym;
    uint32_t next;
    uint32_t _pad;
    WValue   value;
} WSparseRecord;

typedef struct {
    uint64_t *keys;
    uint32_t *heads;
    uint32_t  cap;
    uint32_t  count;
} WSparseNodeMap;

static WSparseNodeMap g_sparse_map      = {0};
static WSparseRecord *g_sparse_records  = NULL;
static uint32_t       g_sparse_rec_cap  = 0;
static uint32_t       g_sparse_rec_cur  = 0;

#define W_SPARSE_END UINT32_MAX

static uint64_t w_sparse_hash(uint64_t node) {
    uint64_t x = node;
    x ^= x >> 33;
    x *= 0xff51afd7ed558ccdULL;
    x ^= x >> 33;
    x *= 0xc4ceb9fe1a85ec53ULL;
    x ^= x >> 33;
    return x;
}

static void w_sparse_grow_map(uint32_t new_cap) {
    uint64_t *new_keys  = (uint64_t *)calloc(new_cap, sizeof(uint64_t));
    uint32_t *new_heads = (uint32_t *)malloc(new_cap * sizeof(uint32_t));
    if (!new_keys || !new_heads) node_arena_fatal("w_sparse_grow_map: alloc failed");
    uint32_t mask = new_cap - 1;
    for (uint32_t i = 0; i < g_sparse_map.cap; i++) {
        uint64_t k = g_sparse_map.keys[i];
        if (k == 0) continue;
        uint32_t slot = (uint32_t)(w_sparse_hash(k) & mask);
        while (new_keys[slot] != 0) slot = (slot + 1) & mask;
        new_keys[slot] = k;
        new_heads[slot] = g_sparse_map.heads[i];
    }
    free(g_sparse_map.keys);
    free(g_sparse_map.heads);
    g_sparse_map.keys = new_keys;
    g_sparse_map.heads = new_heads;
    g_sparse_map.cap = new_cap;
}

void w_ast_sparse_init(void) {
    if (g_sparse_map.cap != 0) return;
    g_sparse_map.cap = 1024;
    g_sparse_map.keys = (uint64_t *)calloc(g_sparse_map.cap, sizeof(uint64_t));
    g_sparse_map.heads = (uint32_t *)malloc(g_sparse_map.cap * sizeof(uint32_t));
    if (!g_sparse_map.keys || !g_sparse_map.heads) node_arena_fatal("w_ast_sparse_init: alloc failed");
    g_sparse_map.count = 0;
    g_sparse_rec_cap = 4096;
    g_sparse_records = (WSparseRecord *)malloc(g_sparse_rec_cap * sizeof(WSparseRecord));
    if (!g_sparse_records) node_arena_fatal("w_ast_sparse_init: record arena alloc failed");
    g_sparse_rec_cur = 0;
}

void w_ast_sparse_reset(void) {
    if (g_sparse_map.keys) {
        memset(g_sparse_map.keys, 0, g_sparse_map.cap * sizeof(uint64_t));
    }
    g_sparse_map.count = 0;
    g_sparse_rec_cur = 0;
}

static uint32_t w_sparse_find(uint64_t node) {
    if (g_sparse_map.cap == 0) return W_SPARSE_END;
    uint32_t mask = g_sparse_map.cap - 1;
    uint32_t slot = (uint32_t)(w_sparse_hash(node) & mask);
    while (g_sparse_map.keys[slot] != 0) {
        if (g_sparse_map.keys[slot] == node) return slot;
        slot = (slot + 1) & mask;
    }
    return W_SPARSE_END;
}

static uint32_t w_sparse_find_or_insert(uint64_t node) {
    if (g_sparse_map.cap == 0) w_ast_sparse_init();
    if ((g_sparse_map.count + 1) * 10 >= g_sparse_map.cap * 7) {
        w_sparse_grow_map(g_sparse_map.cap * 2);
    }
    uint32_t mask = g_sparse_map.cap - 1;
    uint32_t slot = (uint32_t)(w_sparse_hash(node) & mask);
    while (g_sparse_map.keys[slot] != 0 && g_sparse_map.keys[slot] != node) {
        slot = (slot + 1) & mask;
    }
    if (g_sparse_map.keys[slot] == 0) {
        g_sparse_map.keys[slot] = node;
        g_sparse_map.heads[slot] = W_SPARSE_END;
        g_sparse_map.count++;
    }
    return slot;
}

static uint32_t w_sparse_alloc_record(void) {
    if (g_sparse_rec_cur >= g_sparse_rec_cap) {
        uint32_t new_cap = g_sparse_rec_cap * 2;
        WSparseRecord *new_buf = (WSparseRecord *)realloc(
            g_sparse_records, new_cap * sizeof(WSparseRecord));
        if (!new_buf) node_arena_fatal("w_sparse_alloc_record: realloc failed");
        g_sparse_records = new_buf;
        g_sparse_rec_cap = new_cap;
    }
    return g_sparse_rec_cur++;
}

WValue w_ast_sparse_set(WValue node, int64_t sym, WValue value) {
    uint32_t slot = w_sparse_find_or_insert((uint64_t)node);
    uint32_t rec_idx = g_sparse_map.heads[slot];
    while (rec_idx != W_SPARSE_END) {
        if (g_sparse_records[rec_idx].sym == sym) {
            g_sparse_records[rec_idx].value = value;
            return value;
        }
        rec_idx = g_sparse_records[rec_idx].next;
    }
    uint32_t new_idx = w_sparse_alloc_record();
    g_sparse_records[new_idx].sym = sym;
    g_sparse_records[new_idx].next = g_sparse_map.heads[slot];
    g_sparse_records[new_idx].value = value;
    g_sparse_map.heads[slot] = new_idx;
    return value;
}

WValue w_ast_sparse_get(WValue node, int64_t sym) {
    uint32_t slot = w_sparse_find((uint64_t)node);
    if (slot == W_SPARSE_END) return W_NIL;
    uint32_t rec_idx = g_sparse_map.heads[slot];
    while (rec_idx != W_SPARSE_END) {
        if (g_sparse_records[rec_idx].sym == sym) {
            return g_sparse_records[rec_idx].value;
        }
        rec_idx = g_sparse_records[rec_idx].next;
    }
    return W_NIL;
}

WValue w_ast_sparse_copy(WValue src_node, WValue dst_node) {
    uint32_t src_slot = w_sparse_find((uint64_t)src_node);
    if (src_slot == W_SPARSE_END) return dst_node;
    uint32_t rec_idx = g_sparse_map.heads[src_slot];
    while (rec_idx != W_SPARSE_END) {
        WSparseRecord rec = g_sparse_records[rec_idx];
        w_ast_sparse_set(dst_node, rec.sym, rec.value);
        rec_idx = rec.next;
    }
    return dst_node;
}

/* ---- AST string-intern table (inline interned leaf kinds) ----
 *
 * Mirror of runtime/runtime.c's intern table for stage 0. The VM's
 * string layout is opaque to this file, so the interface is
 * bytes-based: the ccall_nobox arm in vm_call_body.inc extracts
 * (bytes, len) via tc_str_bytes_only/tc_str_len and passes the VM
 * string value alongside; this table keeps its own private byte copy
 * for content equality and returns the FIRST VM string value seen for
 * each distinct content. Content-addressed FNV-1a map, id 0 unused,
 * never reset (ids are content-stable across compiles). Change in
 * lockstep with runtime.c — stage-1==stage-2 byte-identity
 * cross-checks the two. */
typedef struct {
    uint64_t *hashes;
    uint32_t *ids;       /* bucket -> dense id; 0 = empty bucket */
    uint32_t  cap;       /* power of two */
    uint32_t  count;
} WInternMap;

typedef struct {
    char    *bytes;      /* private copy, owned by the table */
    uint32_t len;
    uint64_t strval;     /* the VM's string value for this content */
} WInternEntry;

static WInternMap    g_intern_map     = {0};
static WInternEntry *g_intern_entries = NULL;   /* dense id -> entry; [0] unused */
static uint32_t      g_intern_entries_cap = 0;
static uint32_t      g_intern_next_id     = 1;

static uint64_t w_intern_hash_bytes(const char *p, size_t n) {
    uint64_t h = 1469598103934665603ULL;
    for (size_t i = 0; i < n; i++) {
        h ^= (uint8_t)p[i];
        h *= 1099511628211ULL;
    }
    return h ? h : 1;
}

static void w_intern_grow_map(uint32_t new_cap) {
    uint64_t *new_hashes = (uint64_t *)calloc(new_cap, sizeof(uint64_t));
    uint32_t *new_ids    = (uint32_t *)calloc(new_cap, sizeof(uint32_t));
    if (!new_hashes || !new_ids) node_arena_fatal("w_intern_grow_map: alloc failed");
    uint32_t mask = new_cap - 1;
    for (uint32_t i = 0; i < g_intern_map.cap; i++) {
        if (g_intern_map.ids[i] == 0) continue;
        uint32_t slot = (uint32_t)(g_intern_map.hashes[i] & mask);
        while (new_ids[slot] != 0) slot = (slot + 1) & mask;
        new_hashes[slot] = g_intern_map.hashes[i];
        new_ids[slot]    = g_intern_map.ids[i];
    }
    free(g_intern_map.hashes);
    free(g_intern_map.ids);
    g_intern_map.hashes = new_hashes;
    g_intern_map.ids    = new_ids;
    g_intern_map.cap    = new_cap;
}

static uint32_t w_intern_id_for(const char *bytes, size_t len, uint64_t strval) {
    if (g_intern_map.cap == 0) {
        g_intern_map.cap    = 4096;
        g_intern_map.hashes = (uint64_t *)calloc(g_intern_map.cap, sizeof(uint64_t));
        g_intern_map.ids    = (uint32_t *)calloc(g_intern_map.cap, sizeof(uint32_t));
        if (!g_intern_map.hashes || !g_intern_map.ids) node_arena_fatal("w_intern: alloc failed");
        g_intern_entries_cap = 4096;
        g_intern_entries = (WInternEntry *)calloc(g_intern_entries_cap, sizeof(WInternEntry));
        if (!g_intern_entries) node_arena_fatal("w_intern: entries alloc failed");
    }
    if ((g_intern_map.count + 1) * 10 >= g_intern_map.cap * 7) {
        w_intern_grow_map(g_intern_map.cap * 2);
    }
    uint64_t h = w_intern_hash_bytes(bytes, len);
    uint32_t mask = g_intern_map.cap - 1;
    uint32_t slot = (uint32_t)(h & mask);
    while (g_intern_map.ids[slot] != 0) {
        if (g_intern_map.hashes[slot] == h) {
            WInternEntry *e = &g_intern_entries[g_intern_map.ids[slot]];
            if (e->len == len && memcmp(e->bytes, bytes, len) == 0) {
                return g_intern_map.ids[slot];
            }
        }
        slot = (slot + 1) & mask;
    }
    uint32_t id = g_intern_next_id++;
    if (id >= g_intern_entries_cap) {
        uint32_t new_cap = g_intern_entries_cap * 2;
        WInternEntry *nb = (WInternEntry *)realloc(
            g_intern_entries, new_cap * sizeof(WInternEntry));
        if (!nb) node_arena_fatal("w_intern: entries realloc failed");
        g_intern_entries = nb;
        g_intern_entries_cap = new_cap;
    }
    char *copy = (char *)malloc(len ? len : 1);
    if (!copy) node_arena_fatal("w_intern: bytes alloc failed");
    memcpy(copy, bytes, len);
    g_intern_entries[id].bytes  = copy;
    g_intern_entries[id].len    = (uint32_t)len;
    g_intern_entries[id].strval = strval;
    g_intern_map.hashes[slot] = h;
    g_intern_map.ids[slot]    = id;
    g_intern_map.count++;
    return id;
}

/* VM-side constructor: kind + string bytes + the VM string value.
 * Returns the full-tier W_PACKED_NODE with the intern id in the
 * offset bits — no arena bump. Twin of runtime.c's w_ast_intern_node. */
uint64_t w_ast_intern_node_bytes(int64_t kind, const char *bytes, size_t len,
                                 uint64_t strval) {
    uint32_t id = w_intern_id_for(bytes, len, strval);
    return (uint64_t)w_box_node((int)(kind & W_NODE_KIND_MASK), /*sc*/ 0,
                                (uint64_t)id);
}

/* VM-side sentinel-257 read: offset bits → the stored VM string value.
 * Twin of runtime.c's w_ast_intern_str_of. Returns 0 (VM nil handling
 * is up to the caller) for an out-of-range id. */
uint64_t w_ast_intern_value_of(uint64_t node) {
    uint32_t id = (uint32_t)w_node_offset((WValue)node);
    if (id == 0 || id >= g_intern_next_id) return 0;
    return g_intern_entries[id].strval;
}
