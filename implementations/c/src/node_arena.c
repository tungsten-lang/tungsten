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
#include "ast_schema_generated.h"

/* Inline copy of runtime.h's WNodeArena. Avoids pulling in the full
 * runtime.h, which redeclares w_truthy with a return type that
 * conflicts with wvalue.h's static inline definition. */
typedef struct WNodeArena {
    WValue   *base;
    uint32_t  cursor;
    uint32_t  cap;
} WNodeArena;

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

typedef struct {
    uint64_t *keys;
    WValue   *values;
    uint32_t  cap;
    uint32_t  count;
} WValueSidecarMap;

typedef struct {
    WValue  ivar_offsets;
    WValue  ivar_count;
    uint8_t present;
    uint8_t _pad[7];
} WClassLayoutValue;

typedef struct {
    uint64_t          *keys;
    WClassLayoutValue *values;
    uint32_t           cap;
    uint32_t           count;
} WClassLayoutMap;

typedef struct {
    uint64_t *hashes;
    uint32_t *ids;
    uint32_t  cap;
    uint32_t  count;
} WInternMap;

typedef struct {
    char    *bytes;
    uint32_t len;
    uint64_t strval;
} WInternEntry;

typedef struct {
    WNodeArena     node_arena;
    WValue         bool_nodes[2];
    WSparseNodeMap sparse_map;
    WSparseRecord *sparse_records;
    uint32_t       sparse_rec_cap;
    uint32_t       sparse_rec_cursor;
    WValueSidecarMap analysis_sidecar;
    WClassLayoutMap  class_layout_sidecar;
    WInternMap     intern_map;
    WInternEntry  *intern_entries;
    uint32_t       intern_entries_cap;
    uint32_t       intern_next_id;
    uint32_t       generation;
} WAstStore;

WAstStore g_ast_store = {
    .intern_next_id = 1,
    .generation = 1,
};

#define g_node_arena        (g_ast_store.node_arena)
#define g_ast_bool_node     (g_ast_store.bool_nodes)
#define g_sparse_map        (g_ast_store.sparse_map)
#define g_sparse_records    (g_ast_store.sparse_records)
#define g_sparse_rec_cap    (g_ast_store.sparse_rec_cap)
#define g_sparse_rec_cur    (g_ast_store.sparse_rec_cursor)
#define g_analysis_sidecar  (g_ast_store.analysis_sidecar)
#define g_class_layout_sidecar (g_ast_store.class_layout_sidecar)
#define g_intern_map        (g_ast_store.intern_map)
#define g_intern_entries    (g_ast_store.intern_entries)
#define g_intern_entries_cap (g_ast_store.intern_entries_cap)
#define g_intern_next_id    (g_ast_store.intern_next_id)

const uint32_t g_node_initial_cap_words = 500000;

uint64_t g_ast_schema_hash = W_AST_SCHEMA_HASH;

static void node_arena_fatal(const char *msg) {
    fprintf(stderr, "fatal: %s\n", msg);
    exit(1);
}

/* ---- C-VM mirror of the packed WIRE arena ---- */
typedef struct {
    WValue *base;
    uint32_t cursor;
    uint32_t cap;
    uint32_t generation;
} WWireArena;

static WWireArena g_wire_arena = { .generation = 1 };
static const uint32_t g_wire_initial_cap_words = 262144;

#define W_WIRE_FIELD_CACHE_SIZE 8192u
typedef struct {
    uint32_t off;
    uint16_t index;
    uint16_t reserved;
    WValue sym;
} WWireFieldCacheEntry;
static WWireFieldCacheEntry g_wire_field_cache[W_WIRE_FIELD_CACHE_SIZE];

static inline WWireFieldCacheEntry *wire_field_cache_entry(uint32_t off,
                                                            WValue sym) {
    uint64_t mixed = (uint64_t)off * 2654435761u;
    mixed ^= (uint64_t)sym ^ ((uint64_t)sym >> 32);
    return &g_wire_field_cache[mixed & (W_WIRE_FIELD_CACHE_SIZE - 1u)];
}

static inline uint32_t wire_count(uint64_t off) {
    return (uint32_t)g_wire_arena.base[off];
}
static inline uint32_t wire_capacity(uint64_t off) {
    return (uint32_t)(g_wire_arena.base[off] >> 32);
}
static inline void wire_header(uint64_t off, uint32_t count, uint32_t cap) {
    g_wire_arena.base[off] = (WValue)(((uint64_t)cap << 32) | count);
}

WValue w_wire_alloc_reserve(int64_t kind, int64_t field_count, int64_t spare_fields) {
    if (kind <= 0 || kind > 511 || field_count < 0 || field_count > 1024 ||
        spare_fields < 0 || spare_fields > 1024)
        node_arena_fatal("w_wire_alloc: invalid kind or field count");
    uint32_t count = (uint32_t)field_count;
    uint32_t cap = count + (uint32_t)spare_fields;
    if (cap < 2) cap = 2;
    uint64_t words = 1u + (uint64_t)cap * 2u;
    if (g_wire_arena.cursor == 0) g_wire_arena.cursor = 1;
    uint64_t required = (uint64_t)g_wire_arena.cursor + words;
    if (required > W_WIRE_OFFSET_MASK)
        node_arena_fatal("w_wire_alloc: 29-bit arena offset exhausted");
    if (required > g_wire_arena.cap) {
        uint32_t new_cap = g_wire_arena.cap ? g_wire_arena.cap * 2 : g_wire_initial_cap_words;
        while ((uint64_t)new_cap < required) new_cap *= 2;
        WValue *new_base = (WValue *)realloc(g_wire_arena.base,
                                             (size_t)new_cap * sizeof(WValue));
        if (!new_base) node_arena_fatal("w_wire_alloc: realloc failed");
        g_wire_arena.base = new_base;
        g_wire_arena.cap = new_cap;
    }
    uint32_t off = g_wire_arena.cursor;
    g_wire_arena.cursor += (uint32_t)words;
    wire_header(off, 0, cap);
    return w_box_wire((int)kind, off);
}

WValue w_wire_alloc(int64_t kind, int64_t field_count) {
    return w_wire_alloc_reserve(kind, field_count, 6);
}

static uint64_t wire_checked_offset(WValue wire) {
    if (!w_is_wire(wire)) node_arena_fatal("WIRE field access: not a WIRE handle");
    uint64_t off = w_wire_offset(wire);
    if (off == 0 || off >= g_wire_arena.cursor)
        node_arena_fatal("WIRE field access: stale handle");
    uint32_t cap = wire_capacity(off);
    if (off + 1u + (uint64_t)cap * 2u > g_wire_arena.cursor)
        node_arena_fatal("WIRE field access: corrupt record bounds");
    return off;
}

WValue w_wire_field_store_at(WValue wire, int64_t index, WValue sym, WValue value) {
    uint64_t off = wire_checked_offset(wire);
    uint32_t cap = wire_capacity(off);
    if (index < 0 || (uint64_t)index >= cap)
        node_arena_fatal("w_wire_field_store_at: index exceeds capacity");
    uint32_t idx = (uint32_t)index;
    g_wire_arena.base[off + 1 + idx * 2] = sym;
    g_wire_arena.base[off + 2 + idx * 2] = value;
    uint32_t count = wire_count(off);
    if (idx >= count) wire_header(off, idx + 1, cap);
    WWireFieldCacheEntry *cached = wire_field_cache_entry((uint32_t)off, sym);
    cached->off = (uint32_t)off;
    cached->index = (uint16_t)idx;
    cached->sym = sym;
    return wire;
}

WValue w_wire_field_load(WValue wire, WValue sym) {
    uint64_t off = wire_checked_offset(wire);
    uint32_t count = wire_count(off);
    WWireFieldCacheEntry *cached = wire_field_cache_entry((uint32_t)off, sym);
    if (cached->off == (uint32_t)off && cached->sym == sym &&
        cached->index < count &&
        g_wire_arena.base[off + 1 + (uint32_t)cached->index * 2] == sym) {
        return g_wire_arena.base[off + 2 + (uint32_t)cached->index * 2];
    }
    for (uint32_t i = 0; i < count; i++) {
        if (g_wire_arena.base[off + 1 + i * 2] == sym) {
            cached->off = (uint32_t)off;
            cached->index = (uint16_t)i;
            cached->sym = sym;
            return g_wire_arena.base[off + 2 + i * 2];
        }
    }
    return W_UNDEF;
}


WValue w_wire_field_load_nil(WValue wire, WValue sym) {
    WValue value = w_wire_field_load(wire, sym);
    return value == W_UNDEF ? W_NIL : value;
}

WValue w_wire_field_store(WValue wire, WValue sym, WValue value) {
    uint64_t off = wire_checked_offset(wire);
    uint32_t count = wire_count(off), cap = wire_capacity(off);
    WWireFieldCacheEntry *cached = wire_field_cache_entry((uint32_t)off, sym);
    if (cached->off == (uint32_t)off && cached->sym == sym &&
        cached->index < count &&
        g_wire_arena.base[off + 1 + (uint32_t)cached->index * 2] == sym) {
        g_wire_arena.base[off + 2 + (uint32_t)cached->index * 2] = value;
        return value;
    }
    for (uint32_t i = 0; i < count; i++) {
        if (g_wire_arena.base[off + 1 + i * 2] == sym) {
            g_wire_arena.base[off + 2 + i * 2] = value;
            cached->off = (uint32_t)off;
            cached->index = (uint16_t)i;
            cached->sym = sym;
            return value;
        }
    }
    if (count >= cap)
        node_arena_fatal("w_wire_field_store: spare fields exhausted");
    g_wire_arena.base[off + 1 + count * 2] = sym;
    g_wire_arena.base[off + 2 + count * 2] = value;
    wire_header(off, count + 1, cap);
    cached->off = (uint32_t)off;
    cached->index = (uint16_t)count;
    cached->sym = sym;
    return value;
}

int64_t w_wire_kind_extern(WValue wire) {
    return w_is_wire(wire) ? (int64_t)w_wire_kind(wire) : 0;
}
int64_t w_is_wire_extern(WValue value) { return w_is_wire(value) ? 1 : 0; }

int64_t w_wire_store_reset(int64_t reserved) {
    (void)reserved;
#ifndef NDEBUG
    if (g_wire_arena.base && g_wire_arena.cursor > 1) {
        for (uint32_t i = 1; i < g_wire_arena.cursor; i++)
            g_wire_arena.base[i] = W_UNDEF;
    }
#endif
    g_wire_arena.cursor = 1;
    g_wire_arena.generation++;
    if (g_wire_arena.generation == 0) g_wire_arena.generation = 1;
    memset(g_wire_field_cache, 0, sizeof(g_wire_field_cache));
    return 0;
}

WValue w_wire_clone(WValue wire) {
    uint64_t src = wire_checked_offset(wire);
    uint32_t count = wire_count(src);
    uint32_t capacity = wire_capacity(src);
    WValue clone = w_wire_alloc_reserve(w_wire_kind(wire), count, capacity - count);
    for (uint32_t i = 0; i < count; i++) {
        w_wire_field_store_at(clone, i,
            g_wire_arena.base[src + 1 + i * 2],
            g_wire_arena.base[src + 2 + i * 2]);
    }
    return clone;
}

void w_node_field_store(WValue wnode, int64_t ivar_offset, WValue value);

void w_node_arena_init(void) {
    /* Lazy first touch in w_node_alloc. */
}

WValue w_node_alloc(int64_t kind, int64_t sc) {
    int kid = (int)((uint64_t)kind & W_NODE_KIND_MASK);
    if (kid < 1 || kid > (int)W_AST_KIND_MAX || sc < 0 || sc >= 4) {
        node_arena_fatal("w_node_alloc: invalid kind or layout class");
    }
    uint32_t width = W_AST_KIND_WIDTH[kid];
    if (width == 0) node_arena_fatal("w_node_alloc: kind has no arena fields");
#ifndef NDEBUG
    int expected_sc = width <= 2 ? 0 : (width == 3 ? 1 : 2);
    if (sc != expected_sc) {
        node_arena_fatal("w_node_alloc: layout class disagrees with generated width");
    }
#endif
    WNodeArena *a = &g_node_arena;
    if (a->cursor == 0) a->cursor = 1;
    uint64_t required = (uint64_t)a->cursor + width;
    if (required > a->cap) {
        uint32_t new_cap = a->cap ? a->cap * 2 : g_node_initial_cap_words;
        while ((uint64_t)new_cap < required) new_cap *= 2;
        WValue *new_base = (WValue *)realloc(
            a->base, (size_t)new_cap * sizeof(WValue));
        if (!new_base) node_arena_fatal("w_node_alloc: realloc failed");
        a->base = new_base;
        a->cap = new_cap;
    }
    uint32_t off = a->cursor;
    a->cursor += width;
    return w_box_node(kid, (int)sc, (uint64_t)off);
}

WValue w_ast_bool_cached(int64_t truthy_01) {
    int idx = truthy_01 ? 1 : 0;
    if (g_ast_bool_node[idx] == 0) {
        WValue node = w_node_alloc(/*KIND_BOOL=*/39, /*SC_2=*/0);
        w_node_field_store(node, 0, truthy_01 ? /*W_TRUE=*/2 : /*W_FALSE=*/1);
        g_ast_bool_node[idx] = node;
    }
    return g_ast_bool_node[idx];
}

void w_ast_sparse_reset(void);  /* forward decl; defined below */

void w_node_arena_reset(void) {
    /* Retain the high-water allocation across compile generations; exact
     * constructors overwrite every live field before a handle escapes. */
#ifndef NDEBUG
    if (g_node_arena.base && g_node_arena.cursor > 1) {
        for (uint32_t i = 1; i < g_node_arena.cursor; i++) {
            g_node_arena.base[i] = W_UNDEF;
        }
    }
#endif
    g_node_arena.cursor = 1;
    g_ast_bool_node[0] = 0;
    g_ast_bool_node[1] = 0;
    g_ast_store.generation++;
    if (g_ast_store.generation == 0) g_ast_store.generation = 1;
    /* PR #3: sparse meta lifetime is bound to the node arena —
     * both are scoped to a single compile boundary. */
    w_ast_sparse_reset();
}

uint64_t w_ast_schema_hash_compute(void) {
    return W_AST_SCHEMA_HASH;
}

WValue w_node_field_load(WValue wnode, int64_t ivar_offset) {
#ifndef NDEBUG
    if (!w_is_node(wnode)) node_arena_fatal("w_node_field_load: value is not an AST node");
    int kid = w_node_kind(wnode);
    uint32_t width = (kid >= 1 && kid <= (int)W_AST_KIND_MAX)
                         ? W_AST_KIND_WIDTH[kid] : 0;
    uint64_t checked_off = w_node_offset(wnode);
    if (width == 0 || ivar_offset < 0 || (uint64_t)ivar_offset >= width ||
        checked_off == 0 || checked_off + width > g_node_arena.cursor) {
        node_arena_fatal("w_node_field_load: field is outside the active node allocation");
    }
#endif
    uint64_t off = w_node_offset(wnode);
    return g_node_arena.base[off + (uint64_t)ivar_offset];
}

void w_node_field_store(WValue wnode, int64_t ivar_offset, WValue value) {
#ifndef NDEBUG
    if (!w_is_node(wnode)) node_arena_fatal("w_node_field_store: value is not an AST node");
    int kid = w_node_kind(wnode);
    uint32_t width = (kid >= 1 && kid <= (int)W_AST_KIND_MAX)
                         ? W_AST_KIND_WIDTH[kid] : 0;
    uint64_t checked_off = w_node_offset(wnode);
    if (width == 0 || ivar_offset < 0 || (uint64_t)ivar_offset >= width ||
        checked_off == 0 || checked_off + width > g_node_arena.cursor) {
        node_arena_fatal("w_node_field_store: field is outside the active node allocation");
    }
#endif
    uint64_t off = w_node_offset(wnode);
    g_node_arena.base[off + (uint64_t)ivar_offset] = value;
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

static uint32_t w_sidecar_find(const uint64_t *keys, uint32_t cap,
                               uint64_t node) {
    if (cap == 0) return W_SPARSE_END;
    uint32_t mask = cap - 1;
    uint32_t slot = (uint32_t)(w_sparse_hash(node) & mask);
    while (keys[slot] != 0) {
        if (keys[slot] == node) return slot;
        slot = (slot + 1) & mask;
    }
    return W_SPARSE_END;
}

static void w_analysis_grow(uint32_t new_cap) {
    uint64_t *keys = (uint64_t *)calloc(new_cap, sizeof(uint64_t));
    WValue *values = (WValue *)calloc(new_cap, sizeof(WValue));
    if (!keys || !values) node_arena_fatal("w_analysis_grow: alloc failed");
    uint32_t mask = new_cap - 1;
    for (uint32_t i = 0; i < g_analysis_sidecar.cap; i++) {
        uint64_t key = g_analysis_sidecar.keys[i];
        if (!key) continue;
        uint32_t slot = (uint32_t)(w_sparse_hash(key) & mask);
        while (keys[slot]) slot = (slot + 1) & mask;
        keys[slot] = key;
        values[slot] = g_analysis_sidecar.values[i];
    }
    free(g_analysis_sidecar.keys);
    free(g_analysis_sidecar.values);
    g_analysis_sidecar.keys = keys;
    g_analysis_sidecar.values = values;
    g_analysis_sidecar.cap = new_cap;
}

static uint32_t w_analysis_find_or_insert(uint64_t node) {
    if (g_analysis_sidecar.cap == 0) w_analysis_grow(1024);
    if ((g_analysis_sidecar.count + 1) * 10 >= g_analysis_sidecar.cap * 7) {
        w_analysis_grow(g_analysis_sidecar.cap * 2);
    }
    uint32_t mask = g_analysis_sidecar.cap - 1;
    uint32_t slot = (uint32_t)(w_sparse_hash(node) & mask);
    while (g_analysis_sidecar.keys[slot] && g_analysis_sidecar.keys[slot] != node) {
        slot = (slot + 1) & mask;
    }
    if (!g_analysis_sidecar.keys[slot]) {
        g_analysis_sidecar.keys[slot] = node;
        g_analysis_sidecar.count++;
    }
    return slot;
}

static void w_class_layout_grow(uint32_t new_cap) {
    uint64_t *keys = (uint64_t *)calloc(new_cap, sizeof(uint64_t));
    WClassLayoutValue *values = (WClassLayoutValue *)calloc(
        new_cap, sizeof(WClassLayoutValue));
    if (!keys || !values) node_arena_fatal("w_class_layout_grow: alloc failed");
    uint32_t mask = new_cap - 1;
    for (uint32_t i = 0; i < g_class_layout_sidecar.cap; i++) {
        uint64_t key = g_class_layout_sidecar.keys[i];
        if (!key) continue;
        uint32_t slot = (uint32_t)(w_sparse_hash(key) & mask);
        while (keys[slot]) slot = (slot + 1) & mask;
        keys[slot] = key;
        values[slot] = g_class_layout_sidecar.values[i];
    }
    free(g_class_layout_sidecar.keys);
    free(g_class_layout_sidecar.values);
    g_class_layout_sidecar.keys = keys;
    g_class_layout_sidecar.values = values;
    g_class_layout_sidecar.cap = new_cap;
}

static uint32_t w_class_layout_find_or_insert(uint64_t node) {
    if (g_class_layout_sidecar.cap == 0) w_class_layout_grow(256);
    if ((g_class_layout_sidecar.count + 1) * 10 >= g_class_layout_sidecar.cap * 7) {
        w_class_layout_grow(g_class_layout_sidecar.cap * 2);
    }
    uint32_t mask = g_class_layout_sidecar.cap - 1;
    uint32_t slot = (uint32_t)(w_sparse_hash(node) & mask);
    while (g_class_layout_sidecar.keys[slot] &&
           g_class_layout_sidecar.keys[slot] != node) {
        slot = (slot + 1) & mask;
    }
    if (!g_class_layout_sidecar.keys[slot]) {
        g_class_layout_sidecar.keys[slot] = node;
        g_class_layout_sidecar.count++;
    }
    return slot;
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
    g_sparse_map.cap = 128;
    g_sparse_map.keys = (uint64_t *)calloc(g_sparse_map.cap, sizeof(uint64_t));
    g_sparse_map.heads = (uint32_t *)malloc(g_sparse_map.cap * sizeof(uint32_t));
    if (!g_sparse_map.keys || !g_sparse_map.heads) node_arena_fatal("w_ast_sparse_init: alloc failed");
    g_sparse_map.count = 0;
    g_sparse_rec_cap = 128;
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
    if (g_analysis_sidecar.keys) {
        memset(g_analysis_sidecar.keys, 0,
               (size_t)g_analysis_sidecar.cap * sizeof(uint64_t));
        memset(g_analysis_sidecar.values, 0,
               (size_t)g_analysis_sidecar.cap * sizeof(WValue));
    }
    g_analysis_sidecar.count = 0;
    if (g_class_layout_sidecar.keys) {
        memset(g_class_layout_sidecar.keys, 0,
               (size_t)g_class_layout_sidecar.cap * sizeof(uint64_t));
        memset(g_class_layout_sidecar.values, 0,
               (size_t)g_class_layout_sidecar.cap * sizeof(WClassLayoutValue));
    }
    g_class_layout_sidecar.count = 0;
}

WValue w_ast_analysis_set(WValue node, WValue value) {
    uint32_t slot = w_analysis_find_or_insert((uint64_t)node);
    g_analysis_sidecar.values[slot] = value;
    return value;
}

WValue w_ast_analysis_get(WValue node) {
    uint32_t slot = w_sidecar_find(g_analysis_sidecar.keys,
                                   g_analysis_sidecar.cap, (uint64_t)node);
    return slot == W_SPARSE_END ? W_NIL : g_analysis_sidecar.values[slot];
}

WValue w_ast_ivar_offsets_set(WValue node, WValue value) {
    uint32_t slot = w_class_layout_find_or_insert((uint64_t)node);
    g_class_layout_sidecar.values[slot].ivar_offsets = value;
    g_class_layout_sidecar.values[slot].present |= 1u;
    return value;
}

WValue w_ast_ivar_offsets_get(WValue node) {
    uint32_t slot = w_sidecar_find(g_class_layout_sidecar.keys,
                                   g_class_layout_sidecar.cap, (uint64_t)node);
    if (slot == W_SPARSE_END || !(g_class_layout_sidecar.values[slot].present & 1u)) {
        return W_NIL;
    }
    return g_class_layout_sidecar.values[slot].ivar_offsets;
}

WValue w_ast_ivar_count_set(WValue node, WValue value) {
    uint32_t slot = w_class_layout_find_or_insert((uint64_t)node);
    g_class_layout_sidecar.values[slot].ivar_count = value;
    g_class_layout_sidecar.values[slot].present |= 2u;
    return value;
}

WValue w_ast_ivar_count_get(WValue node) {
    uint32_t slot = w_sidecar_find(g_class_layout_sidecar.keys,
                                   g_class_layout_sidecar.cap, (uint64_t)node);
    if (slot == W_SPARSE_END || !(g_class_layout_sidecar.values[slot].present & 2u)) {
        return W_NIL;
    }
    return g_class_layout_sidecar.values[slot].ivar_count;
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
#ifndef NDEBUG
        if (rec_idx >= g_sparse_rec_cur) node_arena_fatal("w_ast_sparse_set: corrupt record chain");
#endif
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
#ifndef NDEBUG
        if (rec_idx >= g_sparse_rec_cur) node_arena_fatal("w_ast_sparse_get: corrupt record chain");
#endif
        if (g_sparse_records[rec_idx].sym == sym) {
            return g_sparse_records[rec_idx].value;
        }
        rec_idx = g_sparse_records[rec_idx].next;
    }
    return W_NIL;
}

WValue w_ast_sparse_copy(WValue src_node, WValue dst_node) {
    WValue value = w_ast_analysis_get(src_node);
    if (value != W_NIL) w_ast_analysis_set(dst_node, value);
    value = w_ast_ivar_offsets_get(src_node);
    if (value != W_NIL) w_ast_ivar_offsets_set(dst_node, value);
    value = w_ast_ivar_count_get(src_node);
    if (value != W_NIL) w_ast_ivar_count_set(dst_node, value);
    uint32_t src_slot = w_sparse_find((uint64_t)src_node);
    if (src_slot == W_SPARSE_END) return dst_node;
    uint32_t rec_idx = g_sparse_map.heads[src_slot];
    while (rec_idx != W_SPARSE_END) {
#ifndef NDEBUG
        if (rec_idx >= g_sparse_rec_cur) node_arena_fatal("w_ast_sparse_copy: corrupt record chain");
#endif
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
