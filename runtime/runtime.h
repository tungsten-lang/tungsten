#ifndef TUNGSTEN_RUNTIME_H
#define TUNGSTEN_RUNTIME_H

/* Must be defined before any system headers for ucontext on macOS */
#ifndef _XOPEN_SOURCE
#define _XOPEN_SOURCE 600
#endif
#ifndef _DARWIN_C_SOURCE
#define _DARWIN_C_SOURCE
#endif

#include "wvalue.h"
#include "event_loop.h"
#include <stdbool.h>
#include <stddef.h>      /* offsetof — required for the WArray/WArray static-asserts below */
#include <stdatomic.h>
#include <pthread.h>
#include <unistd.h>

/* ---- Heap string (mode 7: freeable, >=6 bytes) -------------------------
 * Length alone does not distinguish mode 6 from mode 7 in the 6..61-byte
 * overlap. Mode 6 means interned in the slab; mode 7 means heap-backed. */
typedef struct WString {
    uint32_t len;
    char data[];  /* UTF-8 bytes, null-terminated */
} WString;

/* ---- Regex heap object (subtag 0x7) ---- */
typedef struct {
    char *pattern;
    char *options;
    void *compiled;
    WValue name_to_group; /* compiled once; immutable and shared by matches */
} WRegex;

/* Immutable snapshot returned by Regex#match_data (subtag 0xE). */
typedef struct {
    WValue subject;       /* backing UTF-8 string for lazy Slice captures */
    WValue groups;        /* group 0 followed by numbered captures */
    WValue offsets;       /* nil or [codepoint_begin, codepoint_end] */
    WValue name_to_group; /* borrowed immutable Regex name map */
} WRegexMatch;

/* Mutable append — declared in runtime.c */
WValue w_str_append(WValue str, WValue suffix);

/* ---- String slab (mode 6: interned strings, permanent, identity by index) ---- */

#define W_SLAB_SLOT_SIZE     32
#define W_SLAB_MAX_SLOTS     (1 << 24)  /* 16.7M slots, 24-bit index */
#define W_SLAB_TOTAL_SIZE    ((size_t)W_SLAB_SLOT_SIZE * W_SLAB_MAX_SLOTS)  /* 512MB virtual */
#define W_SLAB_HEADER_SIZE       2   /* primary slot: flags(1) + length(1) */
#define W_SLAB_DATA_OFFSET       2   /* primary slot string data starts at byte 2 */
#define W_SLAB_CONT_DATA_OFFSET  0   /* continuation slot is all payload bytes */
#define W_SLAB_INLINE_BYTES      30  /* bytes 2..31 in the primary slot */
#define W_SLAB_CONT_BYTES        32  /* bytes 0..31 in the continuation slot */
#define W_SLAB_SSO_MAX           29  /* max inline bytes in a single slot (30 data bytes - NUL) */
#define W_SLAB_SSO2_MAX          61  /* max inline bytes in two slots (30 + 32 - NUL) */
#define W_SLAB_TMP_SIZE          (W_SLAB_SSO2_MAX + 1)

/* Slab slot flags (byte 0 in each slot) */
#define W_SFLAG_INLINE       (1 << 0)  /* 1 = data stored inline in slot(s) */
#define W_SFLAG_CONTINUATION (1 << 1)  /* 1 = spans 2 contiguous slots */
#define W_SFLAG_SLICE        (1 << 2)  /* 1 = slice (only when !INLINE) */

/* Slab slot layout.
 *
 * Primary slot:
 *   [0]      flags
 *   [1]      length (0-60)
 *   [2..31]  first 30 bytes of string contents
 *
 * Single-slot string (SSO-29, 6-29 bytes):
 *   [2..31] chars, NUL-terminated by zero-fill
 *
 * Two-slot string (SSO-61, 30-61 bytes):
 *   Slot N:   [0] flags  [1] length  [2..31] chars (first 30 bytes)
 *   Slot N+1: [0..31] chars (next 32 bytes, NUL-terminated by zero-fill)
 *
 * Slice (!INLINE, SLICE):
 *   [0] flags  [1] length
 *   [2..5] parent_index  [6..9] offset
 *   [10..17] ptr-to-bytes  [18..31] spare
 */

typedef struct {
    uint8_t *base;          /* mmap'd base address */
    uint32_t next_slot;     /* bump pointer — next free index (starts at 1) */
    uint32_t page_hwm;     /* highest mprotect'd byte offset from base */
    pthread_mutex_t lock;   /* thread safety for concurrent interning */
    int frozen;             /* 1 = no new slab entries; existing entries remain discoverable */
} WStringSlab;

typedef struct {
    uint64_t *hashes;       /* 64-bit wyhash per slot (0 = empty) */
    uint32_t *indices;      /* 24-bit slab index per slot */
    int64_t count;
    int64_t cap;            /* allocated slots (renamed from cap) */
} WInternTable;

/* Global slab + intern table (initialized by w_slab_init) */
extern WStringSlab g_string_slab;
extern WInternTable g_intern;

void w_slab_init(void);
void w_slab_init_static(const uint8_t *data, uint32_t total_slots);
void w_slab_init_static_zstd(const uint8_t *data, uint32_t compressed_bytes, uint32_t total_slots);
void w_slab_rebuild_intern(uint32_t total_slots);
void w_slab_freeze(void);
int64_t w_slab_is_frozen(void);
WValue w_zstd_compress_llvm_escaped(WValue escaped_val);

/* ---- Exact-width AST word arena ----
 *
 * Every allocated node occupies exactly the number of WValue fields declared
 * by its generated schema. Handles store a 32-bit word offset into this one
 * realloc-growing arena. The legacy size-class bits remain descriptive handle
 * metadata during the transition; they no longer choose storage or stride.
 *
 * Lifetime: compile-generation scoped. `w_node_arena_init()` at compile
 * start and `w_node_arena_reset()` between compiles; reset invalidates every
 * handle and rewinds cursors while retaining Store-owned high-water buffers
 * for reuse by the next generation.
 */
typedef struct WNodeArena {
    WValue   *base;
    uint32_t  cursor;     /* next free WValue word; offset 0 is reserved */
    uint32_t  cap;        /* allocated WValue words */
} WNodeArena;

/* Packed WIRE instructions use a separate exact-lifetime word arena. Each
 * record is header + inline (field-symbol, value) pairs; the instruction kind
 * is carried by the handle, so :op never occupies an arena word. */
typedef struct WWireArena {
    WValue   *base;
    uint32_t  cursor;
    uint32_t  cap;
    uint32_t  generation;
} WWireArena;

extern WWireArena g_wire_arena;
WValue  w_wire_alloc(int64_t kind, int64_t field_count);
WValue  w_wire_alloc_reserve(int64_t kind, int64_t field_count, int64_t spare_fields);
WValue  w_wire_function_record_new(WValue field_symbols, WValue name,
                                   WValue params, WValue return_type,
                                   WValue is_toplevel, WValue extra_params);
WValue  w_wire_block_record_new(WValue field_symbols, WValue label);
WValue  w_wire_field_store_at(WValue wire, int64_t index, WValue sym, WValue value);
WValue  w_wire_field_load(WValue wire, WValue sym);
WValue  w_wire_field_load_nil(WValue wire, WValue sym);
int64_t w_wire_field_count(WValue wire);
WValue  w_wire_field_symbol_at(WValue wire, int64_t index);
WValue  w_wire_field_value_at(WValue wire, int64_t index);
WValue  w_wire_field_store(WValue wire, WValue sym, WValue value);
int64_t w_wire_kind_extern(WValue wire);
int64_t w_is_wire_extern(WValue value);
WValue  w_wire_sequence_from_array(WValue value);
int64_t w_wire_sequence_size(WValue sequence);
WValue  w_wire_sequence_get(WValue sequence, int64_t index);
WValue  w_wire_sequence_set(WValue sequence, int64_t index, WValue value);
int64_t w_wire_store_reset(int64_t reserved);
int64_t w_wire_store_mark(void);
WValue  w_wire_clone(WValue wire);

typedef struct WAstSparseRecord {
    int64_t  sym;
    uint32_t next;
    uint32_t _pad;
    WValue   value;
} WAstSparseRecord;

typedef struct WAstSparseNodeMap {
    uint64_t *keys;
    uint32_t *heads;
    uint32_t  cap;
    uint32_t  count;
} WAstSparseNodeMap;

typedef struct WAstValueSidecarMap {
    uint64_t *keys;
    WValue   *values;
    uint32_t  cap;
    uint32_t  count;
} WAstValueSidecarMap;

typedef struct WAstClassLayoutValue {
    WValue  ivar_offsets;
    WValue  ivar_count;
    uint8_t present;
    uint8_t _pad[7];
} WAstClassLayoutValue;

typedef struct WAstClassLayoutMap {
    uint64_t             *keys;
    WAstClassLayoutValue *values;
    uint32_t              cap;
    uint32_t              count;
} WAstClassLayoutMap;

typedef struct WAstInternMap {
    uint64_t *hashes;
    uint32_t *ids;
    uint32_t  cap;
    uint32_t  count;
} WAstInternMap;

typedef struct WAstBodyBuilderSlot {
    WValue   *items;
    uint32_t  size;
    uint32_t  cap;
    uint32_t  next_free;
    uint8_t   active;
    uint8_t   _pad[3];
} WAstBodyBuilderSlot;

/* One explicit owner for every handle-relative AST allocation. The default
 * process store is currently active for all handles; keeping ownership in a
 * value makes reset/reuse and future store selection one coherent operation. */
typedef struct WAstStore {
    WNodeArena       node_arena;
    WValue           bool_nodes[2];
    WAstSparseNodeMap sparse_map;
    WAstSparseRecord *sparse_records;
    uint32_t          sparse_rec_cap;
    uint32_t          sparse_rec_cursor;
    WAstValueSidecarMap analysis_sidecar;
    WAstClassLayoutMap  class_layout_sidecar;
    WAstInternMap     intern_map;
    WValue           *intern_values;
    uint32_t          intern_values_cap;
    uint32_t          intern_next_id;
    WValue           *body_base;
    uint32_t          body_cursor;
    uint32_t          body_cap;
    uint32_t          body_count;
    WAstBodyBuilderSlot *body_builders;
    uint32_t          body_builders_cap;
    uint32_t          body_builders_used;
    uint32_t          body_builder_free;
    uint32_t          generation;
} WAstStore;

extern WAstStore     g_ast_store;
#define g_node_arena (g_ast_store.node_arena)
extern const uint32_t g_node_initial_cap_words;
extern uint64_t       g_ast_schema_hash;       /* hash of (KIND_*, F_*, STRIDE_*); embedded in loader cache */

void     w_node_arena_init(void);
void     w_node_arena_reset(void);
int64_t  w_ast_store_reset(int64_t reserved);
int64_t  w_ast_store_generation(int64_t reserved);
WValue   w_node_alloc(int64_t kind, int64_t size_class);
WValue   w_ast_bool_cached(int64_t truthy_01);
uint64_t w_ast_schema_hash_compute(void);

/* ---- AST sparse-field side-table (PR #3) ----
 * Open-addressed outer map (W_PACKED_NODE → record-chain head) plus a
 * bump-allocated record arena. Replaces the Tungsten Hash-of-Hashes
 * `g_ast_sparse_meta`. Lifetime matches the node arena: w_node_arena_reset
 * calls w_ast_sparse_reset. w_ast_sparse_get returns W_NIL (= 0) for an
 * absent (node, sym) pair, which round-trips to Tungsten nil. */
void     w_ast_sparse_init(void);
void     w_ast_sparse_reset(void);
/* set returns value, copy returns dst_node — both for ccall_nobox's
 * `call i64` calling convention; the value isn't otherwise used. */
WValue   w_ast_sparse_set(WValue node, int64_t sym, WValue value);
WValue   w_ast_sparse_get(WValue node, int64_t sym);
WValue   w_ast_sparse_copy(WValue src_node, WValue dst_node);
WValue   w_ast_analysis_set(WValue node, WValue value);
WValue   w_ast_analysis_get(WValue node);
WValue   w_ast_ivar_offsets_set(WValue node, WValue value);
WValue   w_ast_ivar_offsets_get(WValue node);
WValue   w_ast_ivar_count_set(WValue node, WValue value);
WValue   w_ast_ivar_count_get(WValue node);

/* ---- AST string-intern table (inline interned leaf kinds) ----
 * Content-addressed: string bytes → dense 32-bit id. The id is embedded
 * in the offset bits of the W_PACKED_NODE handle for the interned leaf
 * kinds (var/ivar/cvar/symbol/string — schema sentinel 257), so those
 * kinds allocate no arena slot at all. Unlike the sparse table this is
 * NEVER reset: ids are content-stable, so a later compile re-interns
 * identical names to identical ids and the table amortizes across
 * REPL/JIT evals. The C VM stage 0 carries a bytes-based mirror in
 * implementations/c/src/node_arena.c (w_ast_intern_node_bytes /
 * w_ast_intern_value_of) — change them in lockstep. */
WValue   w_ast_intern_node(int64_t kind, WValue str);
WValue   w_ast_intern_str_of(WValue node);

/* ---- AST body arena (child lists) ----
 * Flat, realloc-doubling arena of WValue slots for AST child-list
 * arrays (:expressions/:args/:body/…) — moves on growth exactly like
 * the active AST store, which is safe because slab slots hold a W_PACKED_BODY
 * reference (offset+length, wvalue.h), not a pointer: every access
 * re-derives the address from a freshly-read base. w_ast_freeze_if_array
 * copies a heap polymorphic array's elements (recursively, for nested
 * arrays) into the arena on first store into a node (w_node_field_store /
 * w_ast_sparse_set / the slab_alloc_init emit intrinsic) and returns
 * the packed reference; already-frozen and non-array values pass
 * through untouched. Frozen bodies are immutable — no push/mutate path
 * exists or is needed (see the "no aligned header" note in wvalue.h).
 * w_node_arena_reset rewinds the arena for the next generation. */
WValue   w_ast_freeze_if_array(WValue v);
WValue   w_ast_body_builder_new(int64_t initial_capacity);
WValue   w_ast_body_builder_push(WValue storage, int64_t size, WValue value);
WValue   w_ast_body_builder_finish(WValue storage, int64_t size);
void     w_ast_extra_reset(void);
WValue   w_body_arena_get(uint32_t offset, uint32_t i);

/* Field access: reads/writes one 8-byte WValue word inside an AST node.
 * `ivar_offset` is the generated field index; handle offset + field index
 * addresses the exact-width arena directly. With LTO these inline into the
 * caller; without LTO they're one call + a handful of ops.
 *
 * i64 parameter types match how Tungsten's `ccall_nobox` emits args
 * (all raw i64 on the call boundary). */
WValue w_node_field_load(WValue wnode, int64_t ivar_offset);
WValue w_node_field_store(WValue wnode, int64_t ivar_offset, WValue value);

/* ---- Dynamic array ---- */
/* Pool-flag bit: set when array is currently held in a recycle pool. Prevents
 * double-push when a value is recycled from multiple places (aliased stores
 * in a drain hash). Cleared on pool pop. */
#define W_POOL_FLAG_POOLED  (1u << 0)
/* Unified flag namespace: pooled bit aliased so new BigArray/SmallArray
 * helpers can share W_FLAG_POOLED with the pre-existing W_POOL_FLAG_POOLED. */
#define W_FLAG_POOLED       W_POOL_FLAG_POOLED
#define W_FLAG_OWNED        (1u << 1)
#define W_FLAG_VIEW         (1u << 2)
#define W_FLAG_PAGE_ALIGNED (1u << 3)
/* BigArray tier indicator (size > INT32_MAX). Lives on the same
 * subtag (W_SUBTAG_ARRAY) and same flags byte as standard arrays — the bit
 * tells dispatch to read int64 sizes via WBigArray instead of int32. */
#define W_FLAG_BIG          (1u << 4)
/* Array-level immutability — same place as W_OBJ_FLAG_FROZEN on
 * WObject and W_HASH_FLAG_FROZEN on WHash. Set by `w_freeze`; checked by
 * mutating ops (push, set, fill, …). */
#define W_FLAG_FROZEN       (1u << 5)
/* Header and slots share one allocation. Used by tiny fixed typed literals
 * to avoid a second malloc; growth promotes slots to a standalone buffer. */
#define W_FLAG_INLINE       (1u << 6)

/* WArray subsumes the old WTypedArray — same struct, same subtag
 * (W_SUBTAG_ARRAY = 0xA). The `ebits` byte discriminates the tier:
 *   ebits == 65   → polymorphic w64 (heterogeneous values, the `[1,2,3]` form)
 *   unsigned int: 1,4,8,16,32,64 (=u1/bool,u4,u8,u16,u32,u64)
 *   signed int:   -4,108,116,33,66 (=i4,i8,i16,i32,i64 — see array_storage_bits
 *                 for why i32/i64 use 33/66 rather than the +100 band)
 *   float:        -32,-64,-16,-116,-108,-109,-104 (f32,f64,f16,bf16,fp8 e4m3/e5m2,fp4)
 * `slots` is declared `WValue *` (the dominant polymorphic access pattern).
 * Typed-tier code that does byte/halfword/word arithmetic casts to
 * `(uint8_t *)slots` explicitly — see array_read/array_write etc. */
typedef struct {
    uint8_t flags;        /* W_FLAG_* bits (renamed from pool_flags) */
    int8_t  ebits;        /* element-type code: 65 (w64) for polymorphic arrays */
    uint8_t _pad[2];
    int32_t start;        /* logical start index — O(1) shift via increment */
    int32_t size;         /* number of live elements (renamed from length) */
    int32_t cap;          /* total allocated slots (renamed from cap) */
    WValue *slots;        /* base allocation pointer */
} WArray;

/* v5: arrays ride the top-level W_TAG_ARRAY (see wvalue.h). Bits 46-4
 * carry the 16-byte-aligned pointer; bit 47 and the low nibble are
 * reserved flag bits, masked off here. These are the ONLY legal
 * box/unbox paths for a WArray value. */
static inline WArray *w_as_array(WValue v) {
    return (WArray *)(uintptr_t)(v & W_ARRAY_PTR_MASK);
}
static inline WValue w_box_array(WArray *arr) {
#ifndef NDEBUG
    assert(((uintptr_t)arr & 0xF) == 0 && "w_box_array: pointer must be 16-byte aligned");
    assert(((uintptr_t)arr >> 47) == 0 && "w_box_array: pointer must fit 47 bits");
#endif
    return W_TAG_ARRAY | (uint64_t)(uintptr_t)arr;
}

/* ---- Multi-D dense tensor header (CPU / shared-memory face) ----
 *
 * WArray is 1-D: size/cap/start over a flat element buffer.
 * WTensor is N-D: same ebits + flat storage, plus shape/strides.
 *
 * Layout (all strides in *elements*, not bytes):
 *   flat_index(i0,i1,…,ir-1) = offset + Σ_k i_k * strides[k]
 * C-contiguous rank-2 [M,N]: strides = {N, 1}, offset = 0.
 *
 * offset: element index into `storage` where this view begins — for
 * slices/subtensors without copying (e.g. A[10:20, :] shares storage with
 * offset = 10*N). Not a byte offset; ebits defines element width.
 *
 * shape/strides: either inline for rank ≤ W_TENSOR_INLINE_RANK, or
 * heap arrays pointed by shape_heap/strides_heap when rank is larger.
 * rank == 0 is a scalar tensor (one element at offset).
 *
 * storage: owns or borrows a typed buffer. When borrow==0, free with the
 * tensor; when borrow==1, storage is a view (e.g. onto a WArray or MTLBuffer
 * shared via unified memory). Metal MTLTensor is a separate handle type
 * (WMetalTensor); a Tungsten Tensor object may hold both a WTensor CPU face
 * and a WMetalTensor GPU face over the same bytes.
 */
#define W_TENSOR_INLINE_RANK 4
/* Boxed as W_SUBTAG_GENERIC + type = W_TYPE_WTENSOR (must lead with type). */
#define W_TYPE_WTENSOR 25
typedef struct WTensor {
    uint8_t type;           /* W_TYPE_WTENSOR */
    uint8_t flags;          /* W_FLAG_* (FROZEN, …) */
    int8_t  ebits;          /* same codes as WArray */
    uint8_t rank;           /* 0..255; > INLINE uses heap shape */
    uint8_t borrow;         /* 1 = do not free storage */
    uint8_t _pad[3];
    int32_t offset;         /* element offset into storage */
    int32_t shape_inline[W_TENSOR_INLINE_RANK];
    int32_t strides_inline[W_TENSOR_INLINE_RANK];
    int32_t *shape_heap;    /* non-NULL iff rank > INLINE */
    int32_t *strides_heap;
    void    *storage;       /* element bytes; interpret via ebits */
    int64_t  storage_elems; /* capacity of storage in elements */
} WTensor;

/* CPU f32 tensor helpers (strong in runtime.c). */
WValue w_tensor_zeros_f32(WValue shape_wv);
WValue w_tensor_at_f32(WValue t_wv, WValue indices_wv);
WValue w_tensor_set_f32(WValue t_wv, WValue indices_wv, WValue val_wv);
WValue w_tensor_shape(WValue t_wv);
WValue w_tensor_rank(WValue t_wv);
WValue w_tensor_view_f32(WValue t_wv, WValue offset_wv, WValue shape_wv);
WValue w_tensor_slice0_f32(WValue t_wv, WValue start_wv, WValue stop_wv);

/* ---- Hash table ---- */
#define W_HASH_FLAG_FROZEN  (1u << 0)
#define W_HASH_FLAG_POOLED  (1u << 1)  /* set when hash is in the recycle pool */
#define W_HASH_FLAG_KWARGS  (1u << 2)  /* hash born from a call-site kwargs group */

/* Compact dict (CPython/Ruby-st_table shape): entries live in dense
 * insertion-ordered keys/values arrays sized to 3/4 of cap; a sparse
 * power-of-two index table holds dense offsets and takes the probing.
 * ITERATION ORDER IS INSERTION ORDER — a guaranteed, cross-engine
 * (native / C VM / Ruby host) language semantic. Deletion tombstones the
 * index slot and leaves a W_MEMO_MISS hole in the dense arrays; holes are
 * compacted on rebuild. A deleted-then-reinserted key moves to the end. */
#define W_HASH_SLOT_EMPTY (-1)
#define W_HASH_SLOT_TOMB  (-2)

typedef struct {
    uint32_t count;     /* live entries */
    uint32_t cap;       /* index-table slots (power of 2) */
    uint8_t flags;
    uint8_t iter_depth; /* active each traversals; additions are forbidden */
    uint8_t pad[2];
    uint32_t used;      /* dense entries consumed: live + holes */
    WValue *keys;       /* dense, insertion-ordered; W_MEMO_MISS = hole */
    WValue *values;     /* dense, parallel to keys */
    int32_t *index;     /* sparse probe table: W_HASH_SLOT_EMPTY / _TOMB / dense offset */
} WHash;

/* ---- Domain heap object (overflow for currency/quantity/duration/decimal;
 * Rational shares the domain subtag with its own exact two-WValue layout) ---- */
typedef struct {
    uint8_t domain_type;   /* W_DOMAIN_* discriminator */
    uint8_t domain_flags;  /* quantity point/delta metadata; zero otherwise */
    uint8_t pad[6];        /* Alignment padding */
    int64_t sig;           /* Full-precision significand */
    int32_t scale;         /* Scale */
    int32_t extra;         /* symbol_id (currency), unit_id (quantity), mode (duration) */
    int64_t extra2;        /* Duration mode 1: ms value */
} WDomainHeap;

static inline WDomainHeap *w_as_domain(WValue v) {
    return (WDomainHeap *)w_as_ptr(v);
}

/* ---- Heap-backed Rational (overflow tier for packed Rational) ----
 * The domain discriminator stays at offset zero so this shares the
 * W_SUBTAG_DOMAIN bucket with the other promoted scalar domains. */
typedef struct {
    uint8_t domain_type;   /* W_DOMAIN_RATIONAL */
    uint8_t pad[7];
    WValue numerator;      /* canonical Integer or BigInt */
    WValue denominator;    /* canonical positive Integer or BigInt */
} WBigRational;

static inline WBigRational *w_as_big_rational(WValue v) {
    return (WBigRational *)w_as_ptr(v);
}

/* ---- Network address heap object (shared by IPv6 and MAC) ---- */
/* Demoted to W_SUBTAG_GENERIC. The `type` byte at offset 0
 * (W_TYPE_IPV6 / W_TYPE_MAC) is the dispatch discriminator; `len` is
 * derivable from `type` but kept for ergonomics (no callsite churn). */
typedef struct {
    uint8_t  type;         /* W_TYPE_IPV6 or W_TYPE_MAC */
    uint8_t  len;          /* byte count: 16 = IPv6, 6 = MAC */
    uint8_t  prefix;       /* CIDR prefix (255 = none; /128 stays representable) */
    uint8_t  _pad;         /* keep `bytes` aligned at offset 4 */
    uint8_t  bytes[16];    /* address bytes (16 for IPv6, 6 for MAC) */
    uint8_t  _pad2[12];    /* pad to 32 bytes for 16-byte alignment */
} WNetAddr;

_Static_assert(offsetof(WNetAddr, type)   == 0,  "WNetAddr type offset (drives dispatch_key)");
_Static_assert(offsetof(WNetAddr, len)    == 1,  "WNetAddr len offset");
_Static_assert(offsetof(WNetAddr, prefix) == 2,  "WNetAddr prefix offset");
_Static_assert(offsetof(WNetAddr, bytes)  == 4,  "WNetAddr bytes offset");
_Static_assert(sizeof(WNetAddr)           == 32, "WNetAddr size");

/* ---- Encoded value heap object (Base32/58/64) ---- */
/* Demoted to W_SUBTAG_GENERIC; `type` byte at offset 0 holds
 * W_TYPE_ENCODED. `encoding` (32/58/64) follows. */
typedef struct {
    uint8_t  type;         /* W_TYPE_ENCODED */
    uint8_t  encoding;     /* 32, 58, 64 */
    uint8_t  pad[6];
    uint8_t *decoded;      /* raw decoded bytes */
    int64_t  decoded_len;
    char    *display;      /* original display string */
    int64_t  display_len;
} WEncodedValue;

/* ---- Boxing constructors (runtime functions) ---- */
WValue w_int(int64_t v);
int64_t w_to_i64(WValue v);
int64_t w_numeric_to_i64(WValue v);
int64_t w_range_bound_i64(WValue v);
WValue w_range_bound_i64_w(WValue v);
WValue w_range_imm_try_w(WValue lo, WValue hi, WValue excl);
WValue w_range_make(int64_t from, int64_t to, int64_t exclusive);
WValue w_u64(uint64_t v);
uint64_t w_to_u64(WValue v);
WValue w_i128(__int128 v);
__int128 w_to_i128(WValue v);
WValue w_u128(unsigned __int128 v);
unsigned __int128 w_to_u128(WValue v);
WValue w_bool(int64_t v);
WValue w_nil(void);
WValue w_string(const char *s);
WValue w_string_content_equal(WValue a, WValue b);
WValue w_symbol(const char *s);
WValue w_float(double v);
WValue w_num_to_float(WValue v);
WValue w_str_to_sym(WValue v);
/* Interpreter-only checked rebox for source methods that construct an exact
 * raw String WValue representation. */
WValue w_string_from_bits(WValue bits);
WValue w_bigint_from_bits(WValue bits);
WValue w_bigint_from_dec_str(WValue str);
WValue w_regex_new(WValue pattern_val, WValue options_val);
WValue w_regex_match(WValue regex_val, WValue subject_val);
WValue w_regex_match_data(WValue regex_val, WValue subject_val);
WValue w_regex_capture(WValue index_val);

/* ---- Char boxing (requires lookup table) ---- */
WValue w_box_char(uint32_t codepoint);

/* ---- Decimal constructors ---- */
WValue w_decimal(int64_t sig, int scale);
WValue w_decimal_add(WValue a, WValue b);
WValue w_decimal_sub(WValue a, WValue b);
WValue w_decimal_mul(WValue a, WValue b);
WValue w_decimal_div(WValue a, WValue b);

/* ---- Currency constructors (0xFFFD subtype 01) ---- */
WValue w_currency(int symbol_id, int64_t sig, int scale);
WValue w_currency_add(WValue a, WValue b);
WValue w_currency_sub(WValue a, WValue b);
WValue w_currency_mul_scalar(WValue currency, WValue scalar);

/* ---- Quantity constructors (0xFFFD subtype 11) ---- */
WValue w_switch_canonical(WValue v);
void w_register_unit(int id, const char *name);
void w_register_unit_wv(int id, WValue name);
WValue w_quantity(int unit_id, int64_t sig, int scale);
WValue w_decimal_parse(WValue str_v);
WValue w_currency_parse(WValue amount_v, WValue prefix_v, WValue suffix_v);
WValue w_quantity_parse(WValue num_v, WValue unit_v);
WValue w_quantity_unit_name(WValue quantity);
WValue w_quantity_value(WValue quantity);
WValue w_quantity_to_f(WValue quantity);
WValue w_quantity_add(WValue a, WValue b);
WValue w_quantity_sub(WValue a, WValue b);
WValue w_quantity_mul(WValue a, WValue b);
WValue w_quantity_div(WValue a, WValue b);
WValue w_quantity_pipe(WValue q, WValue unit_name_v, WValue digits_v);
WValue w_quantity_mul_scalar(WValue quantity, WValue scalar);
WValue w_quantity_div_scalar(WValue quantity, WValue scalar);
WValue w_quantity_point(WValue quantity, WValue origin);
WValue w_quantity_delta(WValue quantity, WValue origin);
WValue w_quantity_point_p(WValue quantity);
WValue w_quantity_delta_p(WValue quantity);
WValue w_quantity_origin(WValue quantity);
WValue w_quantity_equivalent(WValue quantity, WValue target_unit, WValue equivalence);

/* ---- Duration constructors (0xFFFF tag) ---- */
WValue w_duration_ns(int64_t ns);
WValue w_duration_months_ms(int16_t months, uint32_t ms);
WValue w_duration_add(WValue a, WValue b);
WValue w_duration_sub(WValue a, WValue b);

/* ---- Type class table: maps dispatch keys to Tungsten class_ids ---- */
void w_type_class_register(uint8_t dispatch_key, uint16_t class_id);

/* ---- UUID (subtag 0xD, heap-allocated 16 bytes) ---- */
typedef struct {
    uint8_t bytes[16];
} WUUIDBytes;

_Static_assert(offsetof(WUUIDBytes, bytes) == 0, "WUUIDBytes bytes offset");
_Static_assert(sizeof(WUUIDBytes) == 16, "WUUIDBytes payload size");

WValue w_uuid_from_hex(const char *hex);
WValue w_uuid_parse(WValue text);
WValue w_uuid_byte(WValue uuid, WValue index);
WValue w_uuid_bytes(WValue uuid);
WValue w_uuid_to_s(WValue uuid);
WValue w_uuid_namespace_nil(void);
WValue w_uuid_namespace_dns(void);
WValue w_uuid_namespace_url(void);
WValue w_uuid_namespace_oid(void);
WValue w_uuid_namespace_x500(void);
WValue w_uuid_v1(WValue options);
WValue w_uuid_v2(WValue options);
WValue w_uuid_v3(WValue namespace_uuid, WValue name);
WValue w_uuid_v4(void);
WValue w_uuid_v5(WValue namespace_uuid, WValue name);
WValue w_uuid_v6(void);
WValue w_uuid_v7(void);
WValue w_uuid_v8(WValue custom);

/* ---- SIMD Vector primitives (0xFFF2 simd2d / 0xFFF3 simd3d tags) ---- */
#define WVALUE_TAG_SIMD2D W_TAG_SIMD2D
#define WVALUE_TAG_SIMD3D W_TAG_SIMD3D

WValue w_vec2f(double x, double y);
WValue w_point2d(double x, double y);
WValue w_vec2i(int16_t x, int16_t y);
WValue w_vec3f(double x, double y, double z);

WValue w_vec2f_w(WValue xv, WValue yv);
WValue w_point2d_w(WValue xv, WValue yv);
WValue w_vec3f_w(WValue xv, WValue yv, WValue zv);

WValue w_is_simd2d_w(WValue v);
WValue w_is_simd3d_w(WValue v);
WValue w_simd2d_subtag_w(WValue v);

/* ---- Network Socket Endpoint (0xFFF6 sockaddr tag) ---- */
#define WVALUE_TAG_SOCKADDR W_TAG_SOCKADDR

WValue w_sockaddr(uint8_t a, uint8_t b, uint8_t c, uint8_t d, uint16_t port);
WValue w_sockaddr_w(WValue av, WValue bv, WValue cv, WValue dv, WValue port_v);

WValue w_is_sockaddr_w(WValue v);

uint16_t w_sockaddr_port(WValue v);
WValue w_sockaddr_port_w(WValue v);

void w_sockaddr_ip(WValue v, uint8_t *a, uint8_t *b, uint8_t *c, uint8_t *d);

void w_vec2f_unpack(WValue v, double *x, double *y);
void w_vec3f_unpack(WValue v, double *x, double *y, double *z);

/* ---- Packed types (0xFFFE tag) ---- */
WValue w_color(uint8_t r, uint8_t g, uint8_t b, uint8_t a);
WValue w_date(int year, int month, int day, int hour, int min, int sec, int tz);
WValue w_date_new_w(WValue year, WValue month, WValue day, WValue hour,
                    WValue min, WValue sec, WValue tz);
WValue w_date_today(void);
WValue w_ipv4(uint8_t a, uint8_t b, uint8_t c, uint8_t d, int cidr);
WValue w_ipv4_parse(WValue str_v);
WValue w_ipv4_from_octets(WValue a, WValue b, WValue c, WValue d, WValue prefix_v);
WValue w_ipv4_in_cidr(WValue ip, WValue cidr);
WValue w_ipv6_from_string(const char *s, int cidr);  /* compiled path (ptr, i32) */
WValue w_ipv6_parse(WValue str_v);                   /* interpreter path (boxed string) */
/* Storage-only boundaries used by source-defined IPv6 methods. */
WValue w_ipv6_storage_clone(WValue ip, WValue prefix_v);
WValue w_ipv6_storage_from_words(WValue word0, WValue word1, WValue word2,
                                 WValue word3, WValue raw_prefix_v);
/* Tree-walker mirrors of compiled fixed-inline-field loads. */
WValue w_netaddr_raw_byte(WValue addr, WValue index_v);
WValue w_netaddr_raw_prefix(WValue addr);
WValue w_netaddr_ipv6_p(WValue addr);
WValue w_ipv6_in_cidr(WValue ip, WValue cidr);
WValue w_ip_in_cidr(WValue ip, WValue cidr);
WValue w_mac_parse(WValue str_v);
WValue w_rational(int32_t num, uint32_t den);
WValue w_rational_new(WValue numerator, WValue denominator);
WValue w_rational_numerator(WValue rational);
WValue w_rational_denominator(WValue rational);
uint64_t w_dispatch_key(WValue v);
WValue w_complex(int16_t real_sig, int real_scale, int16_t imag_sig, int imag_scale);
WValue w_location_point(int32_t x, int32_t y);
WValue w_location_file(int file_id, int line, int col);
WValue w_location_file_offset(int file_id, int offset);
WValue w_location_range(int file_id, int start_offset, int length);
WValue w_location_range_w(WValue fid_v, WValue start_v, WValue len_v);
int64_t w_loc_register_file(WValue path, WValue line_at_arr, WValue col_at_arr);
int64_t w_loc_register_source_text(WValue path, WValue source);
int64_t w_loc_line_for_offset(int64_t file_id, int64_t offset);
int64_t w_loc_col_for_offset(int64_t file_id, int64_t offset);
int64_t w_unbox_location_file_id_extern(WValue value);
int64_t w_unbox_location_offset_extern(WValue value);

/* ---- Instant (dedicated 0xFFF8 tag) ---- */
WValue w_instant_now(void);

/* ---- Arithmetic ---- */
WValue w_add(WValue a, WValue b);
WValue w_sub(WValue a, WValue b);
WValue w_mul(WValue a, WValue b);
WValue w_div(WValue a, WValue b);
WValue w_mod(WValue a, WValue b);

static inline WValue w_add_fast(WValue a, WValue b) {
    if (w_both_ints(a, b)) {
        int64_t sum = w_as_int(a) + w_as_int(b);
        if (sum >= W_INT48_MIN && sum <= W_INT48_MAX) return w_box_int(sum);
    }
    return w_add(a, b);
}

static inline WValue w_sub_fast(WValue a, WValue b) {
    if (w_both_ints(a, b)) {
        int64_t diff = w_as_int(a) - w_as_int(b);
        if (diff >= W_INT48_MIN && diff <= W_INT48_MAX) return w_box_int(diff);
    }
    return w_sub(a, b);
}

static inline WValue w_mul_fast(WValue a, WValue b) {
    if (w_both_ints(a, b)) {
        __int128 prod = (__int128)w_as_int(a) * w_as_int(b);
        if (prod >= W_INT48_MIN && prod <= W_INT48_MAX) return w_box_int((int64_t)prod);
    }
    return w_mul(a, b);
}

static inline WValue w_div_fast(WValue a, WValue b) {
    if (w_both_ints(a, b)) {
        int64_t divisor = w_as_int(b);
        if (divisor != 0) {
            int64_t quotient = w_as_int(a) / divisor;
            if (quotient >= W_INT48_MIN && quotient <= W_INT48_MAX)
                return w_box_int(quotient);
        }
    }
    return w_div(a, b);
}

static inline WValue w_mod_fast(WValue a, WValue b) {
    if (w_both_ints(a, b)) {
        int64_t divisor = w_as_int(b);
        if (divisor != 0) return w_box_int(w_as_int(a) % divisor);
    }
    return w_mod(a, b);
}
WValue w_pow(WValue base, WValue exp);
WValue w_bigint_mod_pow2(WValue a, WValue bits);
WValue w_bigint_div_pow2(WValue a, WValue bits);
WValue w_bigint_gcd(WValue a, WValue b);
WValue w_bigint_lcm(WValue a, WValue b);
WValue w_bigint_compare_c(WValue a, WValue b);
WValue w_bigint_compare_source(WValue a, WValue b);
WValue w_bigint_and_c(WValue a, WValue b);
WValue w_bigint_or_c(WValue a, WValue b);
WValue w_bigint_xor_c(WValue a, WValue b);
WValue w_bigint_and_source(WValue a, WValue b);
WValue w_bigint_or_source(WValue a, WValue b);
WValue w_bigint_xor_source(WValue a, WValue b);
WValue w_bigint_prime_q(WValue r);
WValue w_bigint_add(WValue a, WValue b);
WValue w_bigint_sub(WValue a, WValue b);
WValue w_bigint_div(WValue a, WValue b);
WValue w_bigint_mod(WValue a, WValue b);
WValue w_bigint_to_f(WValue r);
WValue w_bigint_to_s(WValue r, WValue base);
WValue w_decimal_from_digits(WValue digits_str, WValue scale, WValue negate);
WValue w_bigint_alloc_boxed(WValue cap);
WValue w_bigint_alloc_hot(int64_t cap);
WValue w_bigint_finish_add(WValue v, WValue signed_size);
WValue w_bigint_finish_add_raw(WValue v, int64_t signed_size);
WValue w_bigint_finish_sub(WValue v, WValue signed_size);
WValue w_bigint_seal(WValue v, WValue signed_size);
WValue w_bigint_seal_raw(WValue v, int64_t signed_size);
WValue w_native_data_elem(WValue recv, WValue field, WValue idx);
WValue w_native_data_elem_set(WValue recv, WValue field, WValue idx, WValue val);
WValue w_neg(WValue v);
WValue w_bit_shl(WValue a, WValue b);
WValue w_bit_shr(WValue a, WValue b);
WValue w_bigint_shl(WValue a, WValue b);
WValue w_bigint_shr(WValue a, WValue b);

/* ---- Comparison ---- */
WValue w_eq(WValue a, WValue b);
WValue w_neq(WValue a, WValue b);
WValue w_approx_eq(WValue a, WValue b);
WValue w_eq_lit(WValue a, WValue b);
WValue w_neq_lit(WValue a, WValue b);
WValue w_lt(WValue a, WValue b);
WValue w_gt(WValue a, WValue b);
WValue w_lte(WValue a, WValue b);
WValue w_gte(WValue a, WValue b);

/* ---- String ---- */
WValue w_str_concat(WValue a, WValue b);
WValue w_string_idx_raw(WValue str, int64_t index);
WValue w_string_slice_raw(WValue str, int64_t start, int64_t len);
int64_t w_parser_chars_equal_ascii(WValue chars, int64_t off, int64_t len, WValue lit);
WValue w_to_s(WValue v);
int64_t w_stringy_c_length(WValue v);
int64_t w_string_byte_length(int64_t str_wval) __attribute__((pure));
int64_t w_string_first_byte(WValue value);
void w_str_data(WValue v, char buf[6], const char **out, size_t *len);
WValue w_algebra_rewrite_source(WValue source);
WValue w_string_from_codepoint(WValue cp_v);
WValue w_string_from_codes(WValue arr_v, WValue start_v, WValue len_v);
WValue w_regex_scan_char(WValue subj, WValue start_v, WValue n_v, WValue ch_v);
WValue w_regex_scan_flag(WValue subj, WValue start_v, WValue n_v, WValue flag_v);
WValue w_string_from_byte(WValue b_v);

/* ---- I/O ---- */
WValue w_puts(WValue v);
WValue w_eputs(WValue v);
WValue w_print(WValue v);
/* Read one line from stdin without the trailing newline; W_NIL on EOF. */
WValue w_read_line_stdin(void);
/* REPL opt-in: route fatal runtime errors (die) through the catchable
 * begin/rescue path when a handler frame is active, instead of aborting. */
WValue w_enable_catchable_die(void);
/* Raw-terminal primitives for the REPL line editor. */
WValue w_term_raw_enable(void);
WValue w_term_raw_disable(void);
WValue w_read_key(void);
WValue w_isatty_stdin(void);
WValue w_isatty_stdout(void);
WValue w_term_cols(void);
/* Unified REPL input: stdin keyboard bytes multiplexed with Stream Deck dial
 * events, returned as a tagged int (see the protocol in terminal_input.c).
 * Used by the scrub loop so a keystroke OR a dial tick wakes one poll().
 * timeout_ms is a RAW machine int (ccall passes numeric args unboxed). */
WValue w_input_poll(int64_t timeout_ms);
/* Dynamic loading (foundation for --jit / --hot). Handles + fn pointers are
 * boxed ints. */
WValue w_dlopen(WValue path);
WValue w_dlsym(WValue handle, WValue name);
WValue w_dlclose(WValue handle);
WValue w_dlcall_i64(WValue fn);
WValue w_dlcall(WValue fn);
WValue w_dlfind_fn(WValue handle, WValue name);
/* Native REPL snippets are separate objects but share the host runtime. Keep
 * session bindings here so compiled lines can preserve mutations. */
WValue w_repl_state_get(WValue name);
WValue w_repl_state_set(WValue name, WValue value);

/* In-memory JIT (macOS/arm64): load a relocatable Mach-O object directly into
 * executable memory and resolve a Tungsten fn by source name — no dlopen, so it
 * skips the ~120ms dyld closure-build floor. Returns the fn address (boxed int)
 * or nil (on any unsupported reloc / failure) so callers fall back to w_dlopen. */
WValue w_jit_load_object(WValue path, WValue fn_name);

/* ---- Foreign function call (compile-time resolved via ccall()) ---- */

/* ---- Truthiness (runtime version — inline version in wvalue.h) ---- */
int64_t w_truthy(WValue v);

/* ---- Array ---- */
WValue w_array_new_empty(void);     /* polymorphic, default cap */
WValue w_array_to_f64(WValue arr);  /* boxed numeric → typed f64 buffer */
WValue w_array_to_f32(WValue arr);  /* boxed numeric → typed f32 buffer */
void   w_array_recycle_public(WValue v);
WValue w_array_push(WValue arr, WValue val);
WValue w_array_pop(WValue arr);
WValue w_array_get(WValue arr, WValue idx);          /* bounds-checked */
WValue w_array_set(WValue arr, WValue idx, WValue val);
WValue w_array_idx(WValue arr, WValue idx);          /* unchecked, WValue idx */
WValue w_array_idxset(WValue arr, WValue idx, WValue val);
void   w_array_set_unchecked(WValue arr, int64_t idx, int64_t raw_val);
int64_t w_array_get_unchecked_raw(WValue arr, int64_t idx);
WValue w_array_size(WValue arr);
WValue w_array_shift(WValue arr);
WValue w_array_unshift(WValue arr, WValue val);
WValue w_array_cap(WValue arr);
WValue w_setenv(WValue name, WValue value);
WValue w_unsetenv(WValue name);
WValue w_env_keys(void);
WValue w_env_to_h(void);
WValue w_native_data_field(WValue recv, WValue name);
WValue w_native_data_field_set(WValue recv, WValue name, WValue value);
WValue w_bigint_mark_shared_value(WValue v);
WValue w_bigint_shared_value(WValue v);
/* preserve_most: these are cold-path callees of the guarded-i48 inline
 * arithmetic — the convention keeps the caller's loop state in registers
 * across the (rarely taken) call. Must stay in sync with the emitter's
 * preserve_mostcc declarations and callsites. */
__attribute__((preserve_most)) WValue w_bigint_add_mut(WValue a, WValue b);
__attribute__((preserve_most)) WValue w_bigint_sub_mut(WValue a, WValue b);
/* Consumed BigInt +/- a positive raw literal magnitude (currently 1 or 2).
 * The second parameter is a raw u64, not a boxed WValue. */
WValue w_bigint_add_small_mut(WValue a, uint64_t magnitude);
WValue w_bigint_sub_small_mut(WValue a, uint64_t magnitude);
__attribute__((preserve_most)) WValue w_bigint_mul_mut(WValue a, WValue b);
__attribute__((preserve_most)) WValue w_bigint_div_mut(WValue a, WValue b);
__attribute__((preserve_most)) WValue w_bigint_mod_mut(WValue a, WValue b);
__attribute__((preserve_most)) WValue w_bigint_and_mut(WValue a, WValue b);
__attribute__((preserve_most)) WValue w_bigint_or_mut(WValue a, WValue b);
__attribute__((preserve_most)) WValue w_bigint_xor_mut(WValue a, WValue b);
__attribute__((preserve_most)) WValue __w_bigint_and_mut_src(WValue a, WValue b);
__attribute__((preserve_most)) WValue __w_bigint_or_mut_src(WValue a, WValue b);
__attribute__((preserve_most)) WValue __w_bigint_xor_mut_src(WValue a, WValue b);
__attribute__((preserve_most)) WValue w_bigint_shl_mut(WValue a, WValue b);
__attribute__((preserve_most)) WValue w_bigint_shr_mut(WValue a, WValue b);
__attribute__((preserve_most)) WValue w_bigint_mod_pow2_mut(
    WValue a, WValue bits);
__attribute__((preserve_most)) WValue w_bigint_add_mod_pow2_mut(
    WValue a, WValue b, WValue bits);
__attribute__((preserve_most)) WValue w_bigint_addmul_mut(
    WValue a, WValue x, WValue word);
__attribute__((preserve_most)) WValue w_bigint_submul_mut(
    WValue a, WValue x, WValue word);
__attribute__((preserve_most)) WValue w_bigint_div_pow2_mut(
    WValue a, WValue bits);
/* Any-width fused linear entries (multi-limb factors included); plain CC
 * spellings of the same body for benches, tests, and direct callers. */
WValue w_bigint_addmul_any(WValue a, WValue x, WValue y);
WValue w_bigint_submul_any(WValue a, WValue x, WValue y);
/* Rotation-shape add into a dying destination buffer (E4 stage 2);
 * called unconditionally in the emitted shape, so plain CC. */
WValue w_bigint_add_dest(WValue dest, WValue x, WValue y);
/* Rotation-shape subtract mirror (E4 stage 4): x - y into the dying
 * destination for the descending triple; same contract as add_dest. */
WValue w_bigint_sub_dest(WValue dest, WValue x, WValue y);
/* Word-overwrite destination entries (E4 stage 3): `r = a op w` whose
 * dying old r arrives as `dead`. Guards inside; fail-open to the
 * polymorphic op with the dead buffer released. */
__attribute__((preserve_most)) WValue w_bigint_add_word_dest(
    WValue dead, WValue a, WValue b);
__attribute__((preserve_most)) WValue w_bigint_sub_word_dest(
    WValue dead, WValue a, WValue b);
__attribute__((preserve_most)) WValue w_bigint_mul_word_dest(
    WValue dead, WValue a, WValue b);

/* ---- Hash ---- */
WValue w_hash_new(void);
WValue w_hash_clear_reuse(WValue hash);
WValue w_hash_reuse_or_new(WValue *slot);
WValue w_hash_reuse_and_drain_or_new(WValue *slot);
WValue w_hash_recycle_or_new(void);
void   w_hash_recycle(WValue v);
WValue w_hash_new_with_fn(int64_t fn_id);
WValue w_hash_set(WValue hash, WValue key, WValue val);
WValue w_hash_get(WValue hash, WValue key);
WValue w_hash_has_key(WValue hash, WValue key);
WValue w_hash_mark_kwargs(WValue h);
WValue w_hash_is_kwargs(WValue v);
WValue w_kwargs_remap12(WValue spec,
                        WValue p0, WValue p1, WValue p2, WValue p3,
                        WValue p4, WValue p5, WValue p6, WValue p7,
                        WValue p8, WValue p9, WValue p10, WValue p11);
WValue w_hash_keys(WValue hash);
WValue w_hash_values(WValue hash);
WValue w_hash_delete(WValue hash, WValue key);
WValue __w_hash_match(WValue subject, WValue pattern);

/* ---- Classes and Objects ---- */
typedef struct WMethod {
    WValue name;
    uint64_t name_hash;
    void *fn_ptr;
    int arity;
    int min_arity;
    /* Zero for a fixed signature; otherwise source `*rest` index + 1.
     * The +1 encoding keeps calloc-zeroed method-table slots non-variadic. */
    int splat_index_plus_one;
} WMethod;

typedef struct WClass {
    const char *name;
    struct WClass *superclass;
    uint16_t class_id;
    WMethod *methods;
    int method_count;
    int method_capacity;
    WMethod *static_methods;
    int static_method_count;
    int static_method_capacity;
    WValue *ivar_names;         /* ivar_names[i] = WValue name at offset i */
    uint64_t *ivar_name_hashes;
    WValue *ivar_lookup_names;
    int *ivar_lookup_indices;
    int ivar_count;
    int ivar_capacity;
    int ivar_lookup_capacity;
} WClass;

typedef struct WObject {
    uint16_t class_id;
    uint8_t  ivar_count;
    uint8_t  flags;             /* bit 0 = frozen */
    uint32_t _reserved;
    WValue   ivars[];
} WObject;

#define W_OBJ_FLAG_FROZEN  (1u << 0)

#define W_MAX_CLASSES 65535
extern WClass *g_class_table[];
extern uint16_t g_next_class_id;

WValue w_class_new(const char *name, WValue superclass);
WValue w_class_new_wv(WValue name, WValue superclass);
WValue w_type_tables_lock_safe(void);
int64_t w_type_tables_are_locked(void);
WValue w_method_tables_lock_safe(void);
int64_t w_method_tables_are_locked(void);
void   w_class_add_method(WValue klass, const char *name, void *fn_ptr, int arity);
void   w_class_add_method_wv(WValue klass, WValue name, void *fn_ptr, int arity);
void   w_class_add_method_range_wv(WValue klass, WValue name, void *fn_ptr,
                                   int arity, int min_arity);
void   w_class_add_method_splat_wv(WValue klass, WValue name, void *fn_ptr,
                                   int arity, int min_arity, int splat_index);
void   w_class_add_static_method(WValue klass, const char *name, void *fn_ptr, int arity);
void   w_class_add_static_method_wv(WValue klass, WValue name, void *fn_ptr, int arity);
void   w_class_add_static_method_range_wv(WValue klass, WValue name, void *fn_ptr,
                                          int arity, int min_arity);
void   w_class_add_static_method_splat_wv(WValue klass, WValue name, void *fn_ptr,
                                          int arity, int min_arity, int splat_index);
int    w_class_add_ivar(WValue klass, const char *name);
int    w_class_add_ivar_wv(WValue klass, WValue name);
int    w_class_ivar_offset(WValue klass, const char *name);
int    w_class_ivar_offset_wv(WValue klass, WValue name);
WValue w_object_new(WValue klass);
WValue w_ivar_get(WValue obj, const char *name);
WValue w_ivar_get_wv(WValue obj, WValue name);
WValue w_ivar_set(WValue obj, const char *name, WValue val);
WValue w_ivar_set_wv(WValue obj, WValue name, WValue val);
WValue w_ivar_get_idx(WValue obj, int idx);
WValue w_ivar_set_idx(WValue obj, int idx, WValue val);

/* ---- Closures ---- */
typedef struct {
    void *fn_ptr;
    WValue *captures;
    int capture_count;
    int arity;              /* declared block params; 0 = unknown (legacy) */
} WClosure;

void *w_closure_cell_new(void);
WValue w_closure_new(void *fn, WValue *captures, int count);
WValue w_closure_new_a(void *fn, WValue *captures, int count, int arity);
WValue w_destructure_index(WValue v, int64_t i);
WValue w_closure_call_0(WValue closure_val);
WValue w_closure_call_1(WValue closure_val, WValue arg);
WValue w_closure_call_2(WValue closure_val, WValue arg1, WValue arg2);
WValue w_closure_call_3(WValue closure_val, WValue arg1, WValue arg2, WValue arg3);
WValue w_closure_call_4(WValue closure_val, WValue arg1, WValue arg2, WValue arg3, WValue arg4);

/* ---- Exceptions ---- */
#include <setjmp.h>

/* Keep each platform's save/restore pair matched. POSIX exposes the explicit
 * signal-mask-free _setjmp/_longjmp pair. MSVC's fast form is the ordinary
 * setjmp/longjmp pair from <setjmp.h> (the SEH-aware form comes from
 * <setjmpex.h>), and MinGW follows that portable spelling. */
#if defined(_WIN32)
#define W_FAST_SETJMP(env) setjmp(env)
#define W_FAST_LONGJMP(env, value) longjmp((env), (value))
#else
#define W_FAST_SETJMP(env) _setjmp(env)
#define W_FAST_LONGJMP(env, value) _longjmp((env), (value))
#endif

typedef struct WExceptionFrame {
    jmp_buf buf;
    struct WExceptionFrame *prev;
    struct WExceptionFrame *pool_next;
    WValue error;
    int32_t cleanup_depth;  /* g_cleanup_top at push time — unwind target */
    uint32_t block_refs;    /* active block-return snapshots of this frame */
    uint8_t heap_owned;     /* compiler push; eligible for TLS pool reuse */
    uint8_t on_stack;       /* still linked from w_exception_stack */
} WExceptionFrame;

extern __thread WExceptionFrame *w_exception_stack;

void *w_exception_push(void);
void w_exception_frame_push(WExceptionFrame *frame);
void w_exception_pop(void);
void w_raise(WValue msg);
WValue w_exception_error(void);

/* ---- Sandbox mode (TUNGSTEN_SANDBOX=1) ----
 * Gate over externs that reach outside the process. w_sandbox_gate logs the
 * attempt and raises when the sandbox is latched (no-op otherwise);
 * w_sandbox_stub logs and returns 1 so the caller can answer with a benign
 * value instead. Defined in runtime.c. */
void w_sandbox_gate(const char *op, const char *detail);
int w_sandbox_stub(const char *op, const char *detail);

/* ---- Recycle cleanup stack ----
 * Thread-local cleanup stack tracks ## recycle allocations that need
 * pool-push on exception unwind. Each compile-time-emitted recycle_or_new
 * is paired with a cleanup_push; scope-exit recycle calls are paired with
 * cleanup_pop (which removes the entry; the normal-path recycle stays).
 * On w_raise, entries above the target frame's cleanup_depth are invoked
 * in LIFO order, then the cleanup stack is truncated to the depth. */
typedef void (*WRecycleFn)(WValue);

void w_cleanup_push(WValue value, WRecycleFn fn);
void w_value_free(WValue value);
WValue w_value_free_w(WValue value);
void w_cleanup_pop(void);

/* ---- Non-local block return ---- */
void *w_block_return_push(void);
void w_block_return_pop(void *buf_ptr);
WValue w_block_return_value(void *buf_ptr);
void w_block_return_signal(uint64_t buf_bits, WValue value);

/* ---- Method dispatch ---- */
WValue w_method_call(WValue recv, WValue method_name, WValue args_arr);
WValue w_method_call_fast(WValue recv, WValue name, WValue *args_ptr, int argc);

/* ---- Monomorphic inline cache (per call site) ----
 *
 * Concurrency contract: caches are process-global and worker threads
 * dispatch through them, so publication must be tear-free. Writers
 * invalidate (type_key = 0, release), fill fn_ptr/arity, then publish
 * type_key (release). Readers acquire-load type_key, read the fields,
 * and acquire-load type_key AGAIN — a mid-flight writer makes one of
 * the two loads miss. This is sound for cold population and for
 * single-writer re-population (the shapes Tungsten threading produces:
 * worker-shared sites are monomorphic). Two threads concurrently
 * publishing DIFFERENT methods through one site can still interleave;
 * that shape implies racing polymorphic dispatch, which the threading
 * model already forbids.
 *
 * History: the previous key-FIRST unordered write let a second arm of
 * wassat's thread race read {key, fn} with a stale arity of 0 and call
 * an arity-1 method with no argument — garbage register, SIGBUS inside
 * Wassat#analyze (13 crash reports, 2026-07-24). */
typedef struct {
    _Atomic uint64_t type_key; /* w_dispatch_key(recv); 0 = empty/mid-write */
    int32_t  arity;        /* -1 = builtin wrapper, >= 0 = user method arity */
    void    *fn_ptr;       /* cached function pointer */
} WInlineCache;

static inline void w_ic_publish(WInlineCache *cache, uint64_t key, void *fn, int32_t arity) {
    atomic_store_explicit(&cache->type_key, 0, memory_order_release);
    cache->fn_ptr = fn;
    cache->arity  = arity;
    atomic_store_explicit(&cache->type_key, key, memory_order_release);
}

WValue w_method_call_cached(WValue recv, WValue name, WValue *args_ptr, int argc, WInlineCache *cache);
WValue w_method_call_cached_0(WValue recv, WValue name, WInlineCache *cache);
WValue w_method_call_cached_1(WValue recv, WValue name, WValue arg, WInlineCache *cache);
WValue w_method_call_cached_2(WValue recv, WValue name, WValue arg0, WValue arg1, WInlineCache *cache);
WValue w_string_chars(WValue r);
WValue w_value_is_a(WValue recv, WValue target);

/* ---- Memoization ---- */
#define MEMO_MAX_ENTRIES 100000
#define MEMO_HT_LOAD_NUM 3
#define MEMO_HT_LOAD_DEN 4
#define MEMO_VERSION 3

typedef struct {
    WValue *keys;       /* W_UNDEF in first key element = empty slot */
    WValue *values;
    int arity;
    int count;
    int cap;       /* allocated slots (renamed from cap) */
    char sha[17];
} WMemoTable;

void *w_memo_init(const char *sha);
WValue w_memo_lookup(void *table, WValue *args, int arity);
void w_memo_store(void *table, WValue *args, int arity, WValue result);
void w_memo_save(void *table, const char *sha);

/* Memoized call wrappers (runtime-side memo for fn) */
WValue __w_memo_call0_i64(void *table, WValue (*fn)(void));
WValue __w_memo_call1_i64(void *table, WValue (*fn)(WValue), WValue arg0);
WValue __w_memo_call2_i64(void *table, WValue (*fn)(WValue, WValue), WValue arg0, WValue arg1);

/* ---- Parallel support (libdispatch / GCD) ---- */
void w_init_parallel(void);
void w_thread_register(void);
void w_thread_unregister(void);

/* ---- Thread primitives ---- */
typedef struct WThread {
    uint8_t type;        /* W_TYPE_THREAD */
    pthread_t handle;
    WValue closure;
    _Atomic int alive;   /* 1 = running, 0 = finished */
    _Atomic int cancel;  /* 1 = cancellation requested */
    int joined;          /* pthread_join completed; closure snapshot released */
    WValue result;
} WThread;

WValue w_thread_spawn(WValue closure);
WValue w_thread_spawn_slots(WValue closure);
WValue w_thread_join(WValue thread);
WValue w_thread_join_release(WValue thread);
WValue w_thread_join_timeout(WValue thread, int64_t ms);
WValue w_thread_sleep_ms(int64_t ms);
WValue w_thread_alive(WValue thread);
WValue w_thread_kill(WValue thread);

/* ---- Signal handling ---- */
WValue w_signal_trap(int signum, WValue closure);

/* ---- Atomic operations ---- */
typedef struct WAtomic {
    /* Type byte removed — WAtomic now lives at its own subtag
     * (W_SUBTAG_ATOMIC), so no in-struct discriminator is needed. */
    _Atomic int64_t value;
} WAtomic;

WValue w_atomic_new(WValue initial);
WValue w_atomic_get(WValue a);
WValue w_atomic_set(WValue a, WValue val);
WValue w_atomic_exchange(WValue a, WValue val);
WValue w_atomic_add(WValue a, WValue delta);
WValue w_atomic_fetch_sub(WValue a, WValue delta);
WValue w_atomic_add_raw(WValue a, int64_t delta);
WValue w_atomic_cas(WValue a, WValue expected, WValue desired);
WValue w_atomic_increment(WValue a);
WValue w_atomic_decrement(WValue a);

/* ---- HID input events (Stream Deck + dials) ----
 * POD events produced by the HID callback thread (runtime/hid_bridge.m on
 * darwin) and consumed by the REPL main thread in w_input_poll. The producer
 * pushes via w_hid_ring_push and must NEVER allocate WValues / intern strings
 * (string-slab mutex); only the main thread boxes. */
typedef enum { HID_ROTATE = 1, HID_PRESS = 2, HID_KEY = 3 } HIDEventKind;

typedef struct HIDEvent {
    uint8_t kind;    /* HIDEventKind */
    uint8_t index;   /* dial 0..3 / LCD key 0..7 */
    int16_t value;   /* ROTATE: signed tick delta; PRESS/KEY: 0/1 */
} HIDEvent;

typedef struct WHIDDevice {
    uint8_t   type;            /* W_TYPE_HID_DEVICE — MUST stay first */
    void     *manager;         /* IOHIDManagerRef (set by hid_bridge.m) */
    pthread_t thread;
    void     *runloop;         /* CFRunLoopRef, published by the reader thread */
    uint8_t  *report_buf;      /* malloc'd input-report buffer */
    pthread_mutex_t lock;      /* guards the started/open_ok handshake */
    pthread_cond_t  ready;
    int       started;         /* reader published runloop + open result */
    int       open_ok;         /* IOHIDManagerOpen succeeded */
    _Atomic int device_count;  /* matched − removed (live presence) */
} WHIDDevice;

/* HID→main self-pipe ([0]=read, [1]=write); both -1 when no device is open.
 * Created by w_hid_streamdeck_open (in hid_bridge.m), polled by w_input_poll
 * (in terminal_input.c) — shared across translation units, hence non-static. */
extern int g_hid_pipe[2];

void   w_hid_ring_push(HIDEvent ev);     /* reader thread → SPSC ring */
WValue w_hid_streamdeck_open(void);      /* boxed WHIDDevice* or W_NIL */
WValue w_hid_streamdeck_close(WValue dev);
WValue w_hid_device_present(WValue dev); /* bool — live connectivity for status */

/* ---- TCP Sockets ---- */
typedef struct WSocket {
    uint8_t type;    /* W_TYPE_SOCKET */
    int fd;
    int listening;   /* 1 = server socket, 0 = connection */
    int closed;
    void *ssl;       /* NULL for plain, SSL* for TLS */
    int ktls;        /* 1 = kernel TLS active, use read/write instead of SSL_* */
    int64_t read_timeout_ms; /* >0: Socket#read deadline from set_timeout; 0 = none */
} WSocket;

WValue w_socket_tcp_listen(const char *host, int port, int backlog);
WValue w_socket_connect_raw(WValue host, int64_t port);
int64_t w_socket_connect_fd(WValue host, int64_t port);
int64_t w_socket_connect_fd_until(WValue host, int64_t port, int64_t deadline_ticks);
WValue w_socket_accept(WValue listener);
WValue w_socket_read(WValue sock, WValue buf_size);
int64_t w_socket_read_ptr(WValue sock, int64_t data_ptr, int64_t len);
WValue w_socket_write(WValue sock, WValue data);
WValue w_socket_write_ptr(WValue sock, int64_t data_ptr, int64_t len);
int64_t w_socket_read_fd(int64_t fd, int64_t data_ptr, int64_t len);
int64_t w_socket_read_fd_until(int64_t fd, int64_t data_ptr, int64_t len, int64_t deadline_ticks);
int64_t w_socket_write_fd(int64_t fd, int64_t data_ptr, int64_t len);
int64_t w_socket_write_fd_until(int64_t fd, int64_t data_ptr, int64_t len, int64_t deadline_ticks);
int64_t w_socket_close_fd(int64_t fd);
WValue w_socket_set_timeout(WValue sock, int64_t ms);
WValue w_socket_shutdown(WValue sock, int how);
WValue w_socket_close(WValue sock);
void w_tls_socket_cleanup(WSocket *sock);
int64_t w_raw_malloc(int64_t size);
int64_t w_raw_free(int64_t ptr);
int64_t w_raw_memmove(int64_t dst, int64_t src, int64_t len);
void   w_socket_park(int fd, int events);
int    w_socket_park_until(int fd, int events, int64_t deadline_ticks);

/* ---- Goroutines ---- */

#include <ucontext.h>

#define W_GOROUTINE_STACK_SIZE   (64 * 1024)
#define W_MAX_GOROUTINES         10000

typedef enum {
    G_IDLE = 0,
    G_RUNNABLE,
    G_RUNNING,
    G_WAITING,
    G_DEAD
} GState;

/* Lightweight context for goroutine switching — replaces ucontext_t.
 * Saves only callee-saved registers per ARM64 AAPCS64 / x86-64 SysV ABI.
 * No signal mask save/restore (eliminates 3-4 syscalls per switch). */
#if defined(__aarch64__)
typedef struct WContext {
    uint64_t x19, x20, x21, x22, x23, x24, x25, x26, x27, x28;
    uint64_t x29; /* frame pointer */
    uint64_t x30; /* link register (return address) */
    uint64_t sp;
    double   d8, d9, d10, d11, d12, d13, d14, d15; /* callee-saved NEON */
} WContext;
#elif defined(__x86_64__)
/* x86_64: stack-based context switch (30ns vs 610ns swapcontext) */
typedef struct WContext {
    uint64_t rsp;
} WContext;
#else
/* Fallback: use ucontext_t (with syscall overhead) */
#define W_CONTEXT_UCONTEXT 1
typedef ucontext_t WContext;
#endif

/* Field order is deliberate: every 4-byte field shares an 8-byte slot with a
 * partner so the struct carries no interior padding (256 B on ARM64 — down a
 * cache line from the naive 264). `ctx` leads because the context switch
 * writes it with a fixed base register; the scheduler's hot reads are
 * state/queued and the wait_* block. */
typedef struct WGoroutine {
    WContext ctx;
    void *stack_base;
    GState state;
    int queued;               /* true while present in any scheduler queue */
    WValue closure;
    WValue result;
    struct WGoroutine *next;  /* run queue link */
    int wait_fd;              /* fd this goroutine is parked on (-1 = none) */
    int wait_events;          /* W_EVENT_READ / W_EVENT_WRITE */
    int wait_timed_out;       /* set when a deadline wakes this goroutine */
    int deadline_linked;      /* lazily-cleared deadline-heap membership */
    int64_t wait_deadline_ticks;
    WEventLoop *wait_loop;
    struct WGoroutine *deadline_next;
    int32_t io_result;        /* io_uring CQE result: bytes transferred or -errno */
    int16_t io_buf_id;        /* provided buffer ID from CQE (-1 = none) */
    uint8_t io_zc_pending;    /* waiting for SEND_ZC notification CQE */
} WGoroutine;

WValue w_goroutine_spawn(WValue closure);
void   w_goroutine_yield(void);
WValue w_goroutine_current(void);
void   w_scheduler_run(void);
WValue w_scheduler_run_w(void);

/* ---- M:P Scheduler ---- */

#define W_MAX_PROCESSORS 64
#define W_LOCAL_QUEUE_MAX 256

/* Metadata first, then the 2 KB queue array on its own cache-line boundary —
 * queue churn (push/pop/steal) no longer evicts the metadata line, and the
 * head/tail CAS words live one line apart from the slot array they index. */
typedef struct WProcessor {
    int id;
    volatile int local_head;  /* steal from head */
    volatile int local_tail;  /* push/pop from tail */
    volatile int spinning;
    volatile int active;
    pthread_t thread;
    WEventLoop *event_loop;   /* per-processor event loop for I/O parking */
    WGoroutine *local_queue[W_LOCAL_QUEUE_MAX] __attribute__((aligned(64)));
} WProcessor;

void w_scheduler_init(void);
void w_scheduler_start(WValue num_procs_wv);
void w_scheduler_stop(void);
WValue w_scheduler_install_debug_signal(void);

/* ---- Capacity metrics (Forge → Hammer handshake) ---- */
int64_t w_goroutine_count(void);
int     w_scheduler_queue_depth(void);

/* ---- Channels ---- */

typedef struct WChanWaiter {
    WGoroutine *g;
    WValue val;
    struct WChanWaiter *next;
} WChanWaiter;

typedef struct WChan {
    uint8_t type;        /* W_TYPE_CHANNEL — MUST stay first: generic-object
                          * dispatch reads the discriminator at byte 0 */
    uint8_t closed;
    uint8_t unbounded;
    uint8_t handoff_committed; /* try/timed unbuffered send already succeeded */
    WValue *buffer;
    int64_t cap;         /* allocated slots */
    int64_t count;
    int64_t head;
    int64_t tail;
    uint64_t handoff_seq; /* unbuffered send ticket */
    uint64_t received_seq;
    int64_t recv_waiters;  /* receivers currently waiting on an empty channel */
    WChanWaiter *send_waitq;
    WChanWaiter *recv_waitq;
    pthread_mutex_t lock;
} WChan;

typedef struct WMutex {
    uint8_t type;        /* W_TYPE_MUTEX — must stay first */
    uint8_t locked;
    uint8_t owner_is_goroutine;
    pthread_mutex_t guard;
    pthread_t owner_thread;
    WGoroutine *owner_goroutine;
    struct WMutex *held_next;
} WMutex;

WValue w_mutex_new(void);
WValue w_mutex_lock(WValue mutex);
WValue w_mutex_try_lock(WValue mutex);
WValue w_mutex_unlock(WValue mutex);
WValue w_mutex_locked(WValue mutex);

WValue w_chan_new(WValue capacity_wv);
WValue w_chan_new_unbounded(void);
WValue w_chan_send(WValue ch, WValue val);
WValue w_chan_try_send(WValue ch, WValue val);
WValue w_chan_try_send_result(WValue ch, WValue val);
WValue w_chan_send_timeout(WValue ch, WValue val, WValue milliseconds);
WValue w_chan_recv(WValue ch);
WValue w_chan_recv_result(WValue ch);
WValue w_chan_try_recv_result(WValue ch);
WValue w_chan_recv_timeout_result(WValue ch, WValue milliseconds);
WValue w_chan_close(WValue ch);

/* Private compiler tree-walker discrimination. Public type()/class_name for
 * synchronization handles intentionally remains "Unknown". */
WValue w_sync_handle_kind_support(WValue value) __attribute__((visibility("hidden")));

/* ---- Freeze / Immutability ---- */
WValue w_freeze(WValue obj);
WValue w_frozen_p(WValue obj);
WValue w_assert_frozen(WValue obj);

/* WBytes struct removed — ByteArray is now a WArray with
 * ebits=8 (see w_is_bytes below + the w_bytes_* wrappers in runtime.c).
 * Kept the function signatures for internal callers. */

/* ---- Metal compute primitives ----
 * Implemented in runtime/metal.m on darwin (links -framework Metal),
 * stubbed in runtime.c on other platforms (raises a Tungsten error
 * when called). The Tungsten facade is core/metal.w. The opaque
 * `handle` field stores the retained Obj-C `id` cast to void*; metal.m
 * owns the lifetime — for v1 we leak (single-process tools). */
typedef struct WMetalDevice {
    uint8_t type;    /* W_TYPE_METAL_DEVICE */
    void *handle;    /* id<MTLDevice> */
} WMetalDevice;

typedef struct WMetalLibrary {
    uint8_t type;    /* W_TYPE_METAL_LIBRARY */
    void *handle;    /* id<MTLLibrary> */
} WMetalLibrary;

typedef struct WMetalPipeline {
    uint8_t type;    /* W_TYPE_METAL_PIPELINE */
    void *handle;    /* id<MTLComputePipelineState> */
} WMetalPipeline;

typedef struct WMetalBuffer {
    uint8_t type;    /* W_TYPE_METAL_BUFFER */
    void *handle;    /* id<MTLBuffer> */
    int64_t size;    /* byte length, cached for bounds checks (renamed from length) */
    int64_t offset;  /* byte offset bound within handle; zero for owned buffers */
} WMetalBuffer;

typedef struct WMetalQueue {
    uint8_t type;    /* W_TYPE_METAL_QUEUE */
    void *handle;    /* id<MTLCommandQueue> */
    void *batch_cmd;     /* in deferred mode: id<MTLCommandBuffer> currently
                            being built. NULL → eager mode (commit per dispatch). */
    void *batch_encoder; /* current id<MTLComputeCommandEncoder> for the batch
                            (one per pipeline change — same dispatches reuse it). */
    void *batch_pipeline;/* last bound pipeline (id<MTLComputePipelineState>) so
                            we can skip setComputePipelineState when the next
                            dispatch reuses the same pipeline. */
} WMetalQueue;

WValue w_metal_device_default(void);
WValue w_metal_compile_source(WValue device, WValue source);
WValue w_metal_compile_source_opts(WValue device, WValue source, WValue math_mode);
WValue w_metal_library_from_file(WValue device, WValue path);
WValue w_metal_pipeline_for(WValue library, WValue name);
WValue w_metal_buffer_new(WValue device, WValue byte_length);
WValue w_metal_buffer_length(WValue buffer);
/* (#12) zero-copy WArray → MTLBuffer wrap on unified memory. */
WValue w_array_as_metal_buffer(WValue device, WValue arr);
/* Zero-copy read-only mmap region -> MTLBuffer view with a binding offset. */
WValue w_metal_buffer_for_mmap(WValue device, WValue mmap, WValue byte_offset,
                               WValue byte_length);
/* (#68) page-aligned typed-array allocator. Returns a
 * fixed-size (size=cap=N) WArray whose slots are mmap-allocated at a
 * page boundary, enabling the noCopy MTLBuffer path. ccall-callable:
 * args arrive as NaN-boxed WValues. */
WValue w_array_new_aligned(WValue element_bits, WValue size);
/* Typed-array parameter guard emitted by lowering at native-fn call sites
 * whose argument element width could not be resolved statically. Raises when
 * the incoming array's element storage width does not match the callee's
 * declared width (or mixes polymorphic w64 with a typed tier); returns `arr`
 * unchanged otherwise. See the definition in runtime.c for the rationale. */
WValue w_check_array_ebits(WValue arr, int64_t want_bits, int64_t want_poly,
                           WValue site);
WValue w_metal_buffer_write_f32(WValue buffer, WValue index, WValue value);
WValue w_metal_buffer_read_f32(WValue buffer, WValue index);
WValue w_metal_buffer_write_f16(WValue buffer, WValue index, WValue value);
WValue w_metal_buffer_read_f16(WValue buffer, WValue index);
WValue w_metal_buffer_write_i32(WValue buffer, WValue index, WValue value);
WValue w_metal_buffer_read_i32(WValue buffer, WValue index);
WValue w_metal_buffer_write_i64(WValue buffer, WValue index, WValue value);
WValue w_metal_buffer_read_i64(WValue buffer, WValue index);
WValue w_metal_buffer_write_bf16(WValue buffer, WValue index, WValue value);
WValue w_metal_buffer_read_bf16(WValue buffer, WValue index);
/* Storage width in bits for a typed-array ebits code (e.g. -32→32, -116→16,
 * -104→4). Exported so metal.m can bounds-check buffer views. */
int64_t w_array_storage_bits(int64_t bits);
/* Zero-copy Array view over a buffer's shared contents (ebits encoding, element
 * count). Aliases the GPU-visible bytes — used by Tensor.matmul. */
WValue w_metal_buffer_view(WValue buffer, WValue ebits, WValue length);
WValue w_metal_queue_new(WValue device);
WValue w_metal_capture_begin(WValue device, WValue path);
WValue w_metal_capture_end(void);
WValue w_metal_dispatch1(WValue queue, WValue pipeline, WValue buf0, WValue buf1, WValue buf2, WValue threads);
WValue w_metal_dispatch_groups_3d(WValue queue, WValue pipeline, WValue bufs,
                                  WValue n_tg_x, WValue n_tg_y, WValue n_tg_z,
                                  WValue threads_x, WValue threads_y, WValue threads_z);
WValue w_metal_batch_begin(WValue queue);
WValue w_metal_batch_begin_concurrent(WValue queue);
WValue w_metal_batch_barrier(WValue queue);
WValue w_metal_batch_barrier_resources(WValue queue, WValue bufs);
WValue w_metal_set_threadgroup_memory(WValue queue, WValue length, WValue index);
WValue w_metal_pipeline_for_with_int_constants(WValue library, WValue name, WValue values);
WValue w_metal_binary_archive_new(WValue device);
WValue w_metal_batch_commit(WValue queue);
WValue w_metal_batch_commit_ms(WValue queue);

/* ---- Metal 4 tensor + MTL4 command path (macOS 26+) ----
 * Parallel command stack (queue + allocator + cmdbuffer + encoder) that
 * supports MTL4ArgumentTable, required for binding tensor parameters in
 * matmul2d cooperative-tensor kernels. The legacy MTLComputeCommandEncoder
 * has no setTensor / argument-table API. Existing buffer-only kernels keep
 * using the legacy path; MTL4 is opt-in per-kernel.
 *
 * Lifetime: same as v1 Metal types — handles are retained at creation,
 * leaked at process exit. */
typedef struct WMetalTensor {
    uint8_t type;       /* W_TYPE_METAL_TENSOR */
    void *handle;       /* id<MTLTensor> */
} WMetalTensor;

typedef struct WMetal4Queue {
    uint8_t type;       /* W_TYPE_METAL4_QUEUE */
    void *handle;       /* id<MTL4CommandQueue> */
} WMetal4Queue;

typedef struct WMetal4Allocator {
    uint8_t type;       /* W_TYPE_METAL4_ALLOCATOR */
    void *handle;       /* id<MTL4CommandAllocator> */
} WMetal4Allocator;

typedef struct WMetal4ArgTable {
    uint8_t type;       /* W_TYPE_METAL4_ARGTABLE */
    void *handle;       /* id<MTL4ArgumentTable> */
    int32_t max_buffers;/* cached for bounds checks */
} WMetal4ArgTable;

typedef struct WMetal4Compiler {
    uint8_t type;       /* W_TYPE_METAL4_COMPILER */
    void *handle;       /* id<MTL4Compiler> */
} WMetal4Compiler;

/* Tensor creation: descriptor is constructed inline from primitive args.
 * dtype is MTLTensorDataType (Float16=25, Float32=3, BFloat16=121,
 * Int8=45, UInt8=49, Int32=29, Int4=143, UInt4=144). For 2D tensors
 * pass stride0=row_stride (in elements), stride1=1. Pass stride0=0 for
 * tightly-packed default. */
WValue w_metal_tensor_2d(WValue buffer, WValue dtype,
                         WValue dim_rows, WValue dim_cols,
                         WValue stride_rows, WValue byte_offset);

/* Rank-N tensor: shape/strides are Tungsten Arrays (row-major, outer→inner);
 * strides may be empty/nil for the tightly-packed default. Aliases the
 * buffer's bytes (no copy), like the 2-D form. */
WValue w_metal_tensor_nd(WValue buffer, WValue dtype,
                         WValue shape, WValue strides, WValue byte_offset);

/* MTL4 compiler — required when the kernel uses cooperative tensors
 * (matmul2d) so we can set MTL4ComputePipelineDescriptor.requiredThreadsPerThreadgroup. */
WValue w_metal4_compiler_new(WValue device);
WValue w_metal4_pipeline_for(WValue compiler, WValue library, WValue function_name,
                             WValue threads_x, WValue threads_y, WValue threads_z);

/* MTL4 command path. */
WValue w_metal4_queue_new(WValue device);
WValue w_metal4_allocator_new(WValue device);
WValue w_metal4_argtable_new(WValue device, WValue max_buffers);
WValue w_metal4_argtable_set_buffer(WValue argtable, WValue index, WValue buffer);
WValue w_metal4_argtable_set_buffer_offset(WValue argtable, WValue index, WValue buffer, WValue byte_offset);
WValue w_metal4_argtable_set_tensor(WValue argtable, WValue index, WValue tensor);

/* All-in-one dispatch: begins cmdbuffer, encodes one dispatch with the
 * given pipeline + argtable, ends, commits, waits. Simpler than exposing
 * the full encoder lifecycle — fine for benchmarks and v1 integration.
 * Returns nil. */
WValue w_metal4_dispatch_groups_3d(WValue queue, WValue allocator,
                                   WValue pipeline, WValue argtable,
                                   WValue resources,
                                   WValue tg_mem_bytes,
                                   WValue n_tg_x, WValue n_tg_y, WValue n_tg_z,
                                   WValue threads_x, WValue threads_y, WValue threads_z);

/* ---- Memory-mapped file ----
 * Read-only mmap of a file. Pointer is borrowed; close() releases the
 * mapping (fd is closed at mmap time so only munmap is needed on close).
 * Used by tungsten-llama for zero-copy GGUF loading. */
typedef struct WMmap {
    uint8_t  type;     /* W_TYPE_MMAP */
    uint8_t  closed;   /* 1 once close() has run, 0 otherwise */
    uint8_t  pad[6];
    uint8_t *data;     /* mmap'd base */
    int64_t  size;     /* byte length (renamed from length) */
} WMmap;

_Static_assert(offsetof(WMmap, type) == 0, "WMmap type offset");
_Static_assert(offsetof(WMmap, closed) == 1, "WMmap closed offset");
_Static_assert(offsetof(WMmap, pad) == 2, "WMmap pad offset");
_Static_assert(offsetof(WMmap, data) == 8, "WMmap data offset");
_Static_assert(offsetof(WMmap, size) == 16, "WMmap size offset");
_Static_assert(sizeof(WMmap) == 24, "WMmap header size");

WValue __w_file_mmap(WValue path);
WValue __w_mmap_length(WValue mmap);
WValue __w_mmap_byte_at(WValue mmap, WValue index);
WValue __w_mmap_close(WValue mmap);
WValue __w_mmap_as_typed(WValue mmap, int64_t element_bits);

/* ---- Math.* libm wrappers ----
 * Each accepts any numeric WValue (int or float), returns a WValue
 * float. Direct libm passthroughs — the Tungsten static-dispatch path
 * lowers `Math.exp(x)` → `w_math_exp(x)`. Used by tungsten-llama
 * kernels for softmax, RoPE, RMSNorm, etc. */
WValue w_math_exp(WValue x);
WValue w_math_log(WValue x);
WValue w_math_expm1(WValue x);
WValue w_math_log1p(WValue x);
WValue w_math_sin(WValue x);
WValue w_math_cos(WValue x);
WValue w_math_tan(WValue x);
WValue w_math_asin(WValue x);
WValue w_math_acos(WValue x);
WValue w_math_atan(WValue x);
WValue w_math_cbrt(WValue x);
WValue w_math_sqrt(WValue x);
WValue w_math_pow(WValue base, WValue exp);
WValue w_math_ldexp(WValue mant, WValue e);
WValue w_math_atan2(WValue y, WValue x);
WValue w_math_hypot(WValue x, WValue y);
WValue w_math_fma(WValue x, WValue y, WValue z);
WValue w_math_floor(WValue x);
WValue w_math_ceil(WValue x);
WValue w_math_round(WValue x);
WValue w_math_abs(WValue x);

/* ---- Float bit-cast ----
 * Reinterpret an integer as IEEE-754 bits and vice versa. Needed for
 * GGUF Q8_0 dequant (scale field is f16/f32 stored as raw bits) and
 * for any other binary-format work. The IEEE layout is the standard
 * little-endian bit pattern. */
WValue w_float_from_u32_bits(WValue bits);
WValue w_float_to_u32_bits(WValue f);
WValue w_float_from_u64_bits(WValue bits);
WValue w_float_to_u64_bits(WValue f);

static inline int w_is_mmap(WValue v) {
    return w_is_obj(v) && w_subtag(v) == W_SUBTAG_GENERIC &&
           ((WMmap *)w_as_ptr(v))->type == W_TYPE_MMAP;
}

WValue w_bytes_new(int64_t length);
WValue w_bytes_from_data(const uint8_t *data, int64_t length);
WValue w_bytes_get(WValue bytes, WValue index);
WValue w_bytes_set(WValue bytes, WValue index, WValue val);
WValue w_bytes_length(WValue bytes);
WValue w_bytes_slice(WValue bytes, WValue start, WValue len);
WValue w_bytes_concat(WValue a, WValue b);

/* ---- Bool Array (thin wrappers over WArray<u1>) ----
 * The dedicated WBoolArray struct was folded into WArray with
 * ebits=1 (bit-packed). The C API is preserved for internal callers;
 * each function is a thin shim over w_array_* primitives. The dispatch
 * boundary handles 0/1 ↔ W_FALSE/W_TRUE conversion so user-facing
 * truthiness still matches Tungsten convention. */

WValue w_bool_array_new(int64_t length);
WValue w_bool_array_get(WValue arr, WValue index);
WValue w_bool_array_set(WValue arr, WValue index, WValue val);
WValue w_bool_array_size(WValue arr);

/* WTypedArray typedef removed — use WArray everywhere. The two
 * structs were declared byte-identical and the user-facing
 * subtag merge finished the unification. Layout asserts moved
 * to the WArray definition site; helper functions take WArray *. */

/* Static-assert wall: catches drift between Tungsten data-block
 * layouts (core/array.w, core/big_array.w, core/small_array.w) and the C
 * structs the runtime actually allocates. Both lowering.w and the inline
 * codegen in emitter.w bake these offsets into IR — the IR breaks silently
 * if a struct field moves. */
_Static_assert(offsetof(WArray, flags) == 0,  "WArray flags offset");
_Static_assert(offsetof(WArray, ebits) == 1,  "WArray ebits offset (added for the array unification)");
_Static_assert(offsetof(WArray, start) == 4,  "WArray start offset");
_Static_assert(offsetof(WArray, size)  == 8,  "WArray size offset (was length)");
_Static_assert(offsetof(WArray, cap)   == 12, "WArray cap offset (was cap)");
_Static_assert(offsetof(WArray, slots) == 16, "WArray slots offset (was items)");
_Static_assert(sizeof(WArray)          == 24, "WArray header size locked at 24 bytes (i32 demote — was 40)");

/* ---- Big Array ---- *
 * Same shape as WArray but with i64 start/size/cap so the runtime can
 * back >2^32-element collections (mmap'd weights, KV cache, datasets too
 * large to address with 32-bit indices). Subtag space is exhausted, so
 * BigArray boxes as W_SUBTAG_GENERIC with a `type` byte at offset 0 — that
 * makes w_dispatch_key (0x80 | type) stable for type-class dispatch. The
 * .w `core/big_array.w` data block keeps `flags` first; the .w model is
 * reconciled with the C struct when inline ops and view-field loads are
 * wired. */
typedef struct WBigArray {
    uint8_t  type;           /* W_TYPE_BIG_ARRAY — drives w_dispatch_key */
    uint8_t  ebits;          /* element-type code (matches WArray.ebits) */
    uint8_t  flags;          /* W_FLAG_* — pooled/owned/view/page_aligned */
    uint8_t  _pad[5];        /* align start to 8 */
    int64_t  start;          /* logical start index */
    int64_t  size;           /* number of live elements */
    int64_t  cap;            /* total allocated element slots */
    uint8_t *slots;          /* packed storage */
} WBigArray;

_Static_assert(offsetof(WBigArray, type)  == 0,  "WBigArray type offset (drives dispatch_key)");
_Static_assert(offsetof(WBigArray, ebits) == 1,  "WBigArray ebits offset");
_Static_assert(offsetof(WBigArray, flags) == 2,  "WBigArray flags offset");
_Static_assert(offsetof(WBigArray, start) == 8,  "WBigArray start offset");
_Static_assert(offsetof(WBigArray, size)  == 16, "WBigArray size offset");
_Static_assert(offsetof(WBigArray, cap)   == 24, "WBigArray cap offset");
_Static_assert(offsetof(WBigArray, slots) == 32, "WBigArray slots offset");
_Static_assert(sizeof(WBigArray) == 40, "WBigArray header size locked at 40 bytes");

/* ---- Small Array ---- *
 * Frozen, stack-allocatable, packed. Up to 255 elements. Header is
 * {type, ebits, size}; the rest of the allocation is inline element bytes
 * pointed at by `slots`. Size==cap (no shift, no resize). Never aliased,
 * so no owned/pooled/view bits. Use cases: tensor shapes/strides, top-k
 * indices, scalar arg packs for kernel dispatch, memoization keys. The
 * type byte at offset 0 keeps SmallArray's dispatch_key stable across
 * instances (same rationale as WBigArray). */
/* SmallArray promoted to its own subtag (W_SUBTAG_SMALL_ARRAY = 9).
 * No type-byte discriminator needed — the subtag itself identifies the kind.
 * Header drops to 2 bytes (just ebits + size); slots[] starts at offset 2. */
typedef struct WSmallArray {
    uint8_t ebits;           /* element-type code, including extended signed/float sentinels */
    uint8_t size;            /* element count, 0..255 */
    /* inline element bytes follow, sized at allocation time */
    uint8_t slots[];
} WSmallArray;

_Static_assert(offsetof(WSmallArray, ebits) == 0, "WSmallArray ebits offset");
_Static_assert(offsetof(WSmallArray, size)  == 1, "WSmallArray size offset");
_Static_assert(offsetof(WSmallArray, slots) == 2, "WSmallArray slots offset");
_Static_assert(sizeof(WSmallArray) == 2, "WSmallArray header size locked at 2 bytes");

WValue w_big_array_new(int64_t ebits, int64_t cap);
WValue w_big_array_view(uint8_t *data, int64_t ebits, int64_t length);
WValue w_big_array_get(WValue arr, WValue index);    /* bounds-checked */
WValue w_big_array_set(WValue arr, WValue index, WValue val);
WValue w_big_array_idx(WValue arr, WValue index);    /* unchecked */
WValue w_big_array_idxset(WValue arr, WValue index, WValue val);
void   w_big_array_set_unchecked(WValue arr, int64_t idx, int64_t raw_val);
int64_t w_big_array_get_unchecked_raw(WValue arr, int64_t idx);
WValue w_big_array_size(WValue arr);
WValue w_big_array_push(WValue arr, WValue val);

/* `bytes_ptr` is an integer-encoded pointer (or 0 for NULL); accepting it
 * as int64_t lets the lowering call this through the regular i64-arg path
 * without needing a dedicated ptr-arg call op. NULL skips the memcpy and
 * leaves the calloc-zeroed payload. */
WValue w_small_array_new(int64_t ebits, int64_t size, int64_t bytes_ptr);
/* Boxed constructor boundary for SmallArray.new(:element_type, size), used by
 * dynamic class receivers and the interpreters. */
WValue w_small_array_new_value(WValue ebits, WValue size);
/* In-place initialize at a caller-allocated buffer (typically
 * an LLVM `alloca` on the stack). `mem` is an integer-encoded pointer.
 * Caller is responsible for sizing the buffer to fit the WSmallArray
 * header + payload; this fn just stamps the header and returns the
 * boxed WValue. Slots are NOT zeroed — caller's lowering is expected
 * to write every element immediately after construction. */
WValue w_small_array_init(int64_t mem, int64_t ebits, int64_t size);
WValue w_small_array_get(WValue arr, WValue index);  /* bounds-checked */
WValue w_small_array_set(WValue arr, WValue index, WValue val);
WValue w_small_array_idx(WValue arr, WValue index);  /* unchecked */
WValue w_small_array_idxset(WValue arr, WValue index, WValue val);
void   w_small_array_set_unchecked(WValue arr, int64_t idx, int64_t raw_val);
int64_t w_small_array_get_unchecked(WValue arr, int64_t idx);
WValue w_small_array_size(WValue arr);

WValue w_array_new(int64_t element_bits, int64_t cap);
WValue w_array_new_uninit(int64_t element_bits, int64_t cap);
/* Fused elementwise lowering (compiler): uninit buffer with size = cap = n —
 * the fused loop writes every element. */
WValue w_array_new_uninit_sized(int64_t element_bits, int64_t n);
WValue w_array_new_inline(int64_t element_bits, int64_t n);
WValue w_array_new_inline_uninit_sized(int64_t element_bits, int64_t n);
/* Fused elementwise lowering: rhs/lhs size-parity guard, same raise text as
 * array_elementwise_into. */
WValue w_elementwise_size_check(WValue lhs, WValue rhs);
/* Fused elementwise auto-parallelization: size gate + thread partitioner
 * (thresholds from the measured sweep; TUNGSTEN_FUSED_* env overrides). */
int64_t w_fused_should_mt(int64_t n);
int64_t w_fused_parallel_run(int64_t fn_addr, int64_t blk, int64_t n);
/* ## reuse fused-output slot (per-site persistent buffer). */
WValue w_fused_out_reuse_or_new(WValue *slot, int64_t element_bits, int64_t n);
/* T[N] constructor — size==cap, calloc-zeroed slots ready to
 * read. Callers that want the legacy "cap N, push to fill" semantics use
 * Array.new(ebits, cap: N) (lowers to w_array_new). */
WValue w_array_zeros(int64_t element_bits, int64_t length);
/* Public Array.new(size, fill) constructor. Repeating the same fill WValue is
 * intentional: mutable fill objects alias. */
WValue w_array_new_filled(WValue size, WValue fill);
/* Non-owning view over a raw pre-existing memory pointer (mmap, ccall, …).
 * `data` must outlive the array. push/grow on a view raises. */
WValue w_array_view_raw(uint8_t *data, int64_t element_bits, int64_t length);
WValue w_array_reuse_or_new(WValue *slot, int64_t element_bits, int64_t cap);
WValue w_array_reuse_or_new_empty(WValue *slot);
WValue w_array_recycle_or_new(int64_t element_bits, int64_t cap);
WValue w_array_recycle_or_new_empty(void);
void   w_array_recycle(WValue v);
WValue w_array_fill(WValue arr, WValue val);
/* arr.view(other_ebits) — zero-copy reinterpret view over the
 * same `slots` buffer with a new element type. Raises on partial element. */
WValue w_array_reinterpret(WValue arr, int64_t target_ebits);
/* arr.slice_view(start, len) — zero-copy slice view sharing the
 * parent's `slots`. Caller's responsibility: parent must outlive each view. */
WValue w_array_view(WValue arr, WValue lo_v, WValue len_v);
/* arr[from..to] / arr[from...to] — wraps the slice form above
 * with Range-arg resolution (inclusive vs exclusive end + neg-index wrap). */
WValue w_array_view_range(WValue arr, WValue from_v, WValue to_v, WValue exclusive_v);
/* Dot-prefix elementwise operators — `lhs .+ rhs` etc. lift
 * scalar arithmetic over a typed array. Lhs is the array; rhs is either
 * another array (elementwise pair) or a scalar (broadcast). Returns a
 * fresh array with same ebits and size as lhs. */
WValue w_array_add_elem(WValue lhs, WValue rhs);
/* `array + array` is CONCATENATION (elementwise pairwise ops are the `.op`
 * forms). Returns a fresh boxed array holding lhs's elements then rhs's. */
WValue w_array_concat(WValue lhs, WValue rhs);
WValue w_array_copy_range(WValue arr, WValue from, WValue to, WValue exclusive);
WValue w_array_sub_elem(WValue lhs, WValue rhs);
WValue w_array_mul_elem(WValue lhs, WValue rhs);
WValue w_array_div_elem(WValue lhs, WValue rhs);
WValue w_array_add_elem_reuse(WValue *slot, WValue lhs, WValue rhs);
WValue w_array_sub_elem_reuse(WValue *slot, WValue lhs, WValue rhs);
WValue w_array_mul_elem_reuse(WValue *slot, WValue lhs, WValue rhs);
WValue w_array_div_elem_reuse(WValue *slot, WValue lhs, WValue rhs);
WValue w_array_bor_elem_reuse(WValue *slot, WValue lhs, WValue rhs);
WValue w_array_band_elem_reuse(WValue *slot, WValue lhs, WValue rhs);
WValue w_array_bxor_elem_reuse(WValue *slot, WValue lhs, WValue rhs);
WValue w_array_shl_elem_reuse(WValue *slot, WValue lhs, WValue rhs);
WValue w_array_shr_elem_reuse(WValue *slot, WValue lhs, WValue rhs);
WValue w_array_bor_elem(WValue lhs, WValue rhs);
WValue w_array_band_elem(WValue lhs, WValue rhs);
WValue w_array_bxor_elem(WValue lhs, WValue rhs);
WValue w_array_shl_elem(WValue lhs, WValue rhs);
WValue w_array_shr_elem(WValue lhs, WValue rhs);
WValue w_array_shift(WValue arr);
WValue w_array_get(WValue arr, WValue index);
WValue w_array_set(WValue arr, WValue index, WValue val);
WValue w_array_size(WValue arr);
WValue w_array_sort(WValue arr);
WValue w_array_stable_sort(WValue arr);
WValue w_array_sort_block(WValue arr, WValue block);
WValue w_array_csort(WValue arr);
WValue w_array_csort_range(WValue arr, WValue lo, WValue hi);
WValue w_array_tsort(WValue arr);
WValue w_array_skasort(WValue arr);
WValue w_array_wolfsort(WValue arr);
WValue w_array_ipnsort(WValue arr);
WValue w_array_shuffle(WValue arr);
WValue w_array_min_signed(WValue arr);
WValue w_array_min_unsigned(WValue arr);
WValue w_array_min_float(WValue arr);
WValue w_array_max_signed(WValue arr);
WValue w_array_max_unsigned(WValue arr);
WValue w_array_max_float(WValue arr);
WValue w_array_sum_signed(WValue arr);
WValue w_array_sum_unsigned(WValue arr);
WValue w_array_sum_float(WValue arr);
WValue w_array_fastsum_float(WValue arr);
WValue w_array_sumsq_float(WValue arr);
WValue w_array_dot_i8(WValue lhs, WValue rhs);
WValue w_array_dot_float(WValue lhs, WValue rhs);
WValue w_array_matvec_i8(WValue weights, WValue x, WValue rows, WValue cols);
WValue w_array_matmul_i8(WValue lhs, WValue rhs, WValue m, WValue k, WValue n);
WValue w_array_cross_float(WValue lhs, WValue rhs);
WValue w_array_scale_float(WValue arr, WValue scalar);
WValue w_array_scale_float_bang(WValue arr, WValue scalar);
WValue w_array_cos_signed(WValue arr);
WValue w_array_cos_unsigned(WValue arr);
WValue w_array_cos_float(WValue arr);
WValue w_array_sin_signed(WValue arr);
WValue w_array_sin_unsigned(WValue arr);
WValue w_array_sin_float(WValue arr);
WValue w_array_sqrt_signed(WValue arr);
WValue w_array_sqrt_unsigned(WValue arr);
WValue w_array_sqrt_float(WValue arr);
WValue w_array_exp_signed(WValue arr);
WValue w_array_exp_unsigned(WValue arr);
WValue w_array_exp_float(WValue arr);
WValue w_array_log_signed(WValue arr);
WValue w_array_log_unsigned(WValue arr);
WValue w_array_log_float(WValue arr);
WValue w_array_tan_signed(WValue arr);
WValue w_array_tan_unsigned(WValue arr);
WValue w_array_tan_float(WValue arr);
WValue w_blas_vsin_f64(WValue input, WValue output, WValue size);
WValue w_blas_vcos_f64(WValue input, WValue output, WValue size);
WValue w_blas_vexp_f64(WValue input, WValue output, WValue size);
WValue w_blas_vlog_f64(WValue input, WValue output, WValue size);
WValue w_blas_vsqrt_f64(WValue input, WValue output, WValue size);
WValue w_blas_vtan_f64(WValue input, WValue output, WValue size);
WValue w_socket_read_exact(WValue sock, WValue n);
WValue w_socket_write_bytes(WValue sock, WValue bytes);
WValue w_socket_read_into(WValue sock, WValue buf, WValue offset, WValue n);
WValue w_socket_write_slice(WValue sock, WValue bytes, WValue offset, WValue len);

/* ---- View registry ---- */
void w_register_view(WValue parent, WValue view);
void w_views_after_realloc(WValue parent, WValue *old_slots, WValue *new_slots);

/* ---- Base64 storage boundaries (algorithms live in core/base64.w) ---- */
WValue w_base64_encode_input(WValue data);
WValue w_base64_decode_input(WValue text);
WValue w_string_from_byte_array(WValue bytes);
int64_t w_u8_live_data_ptr(int64_t arr_wval);
int64_t w_raw_load_u8(int64_t ptr, int64_t index);
int64_t w_raw_store_u8(int64_t ptr, int64_t index, int64_t value);

/* ---- Crypto digests and secure randomness ---- */
WValue w_crypto_random_bytes(WValue length);
WValue w_crypto_md5_bytes(WValue data);
WValue w_crypto_md5_hex(WValue data);
WValue w_crypto_sha1_bytes(WValue data);
WValue w_crypto_sha1_hex(WValue data);
WValue w_crypto_sha224_bytes(WValue data);
WValue w_crypto_sha224_hex(WValue data);
WValue w_crypto_sha256_bytes(WValue data);
WValue w_crypto_sha256_hex(WValue data);
WValue w_crypto_sha384_bytes(WValue data);
WValue w_crypto_sha384_hex(WValue data);
WValue w_crypto_sha512_bytes(WValue data);
WValue w_crypto_sha512_hex(WValue data);
WValue w_crypto_sha512_224_bytes(WValue data);
WValue w_crypto_sha512_224_hex(WValue data);
WValue w_crypto_sha512_256_bytes(WValue data);
WValue w_crypto_sha512_256_hex(WValue data);
WValue w_crypto_sha3_bytes(WValue data, WValue bits);
WValue w_crypto_sha3_hex(WValue data, WValue bits);
WValue w_carr_mul_f64(WValue a, WValue b);
WValue w_carr_conj_dot_f64(WValue a, WValue b);
WValue w_carr_scale_f64(WValue a, WValue re, WValue im);
WValue w_crypto_shake_bytes(WValue data, WValue bits, WValue outlen);
WValue w_crypto_shake_hex(WValue data, WValue bits, WValue outlen);
WValue w_crypto_crc32(WValue data);
WValue w_crypto_crc32c(WValue data);
WValue w_crypto_aes_gcm_seal(WValue key, WValue nonce, WValue plaintext, WValue aad);
WValue w_crypto_aes_gcm_open(WValue key, WValue nonce, WValue sealed, WValue aad);

/* Hardware SHA-256 (also consumed by bits/tungsten-crypto miner). */
int64_t w_sha256_hw_available(void);
void w_sha256_hw_compress(uint32_t *state, const uint8_t *data, size_t nblocks);
int64_t w_sha256_hw_mine(const uint32_t *midstate, const uint8_t *tail, const uint32_t *target_be,
                         uint32_t start, int64_t count, uint32_t *out_hash, uint32_t *out_best,
                         uint32_t *out_best_hash);
void w_sha256_sw_compress(uint32_t *state, const uint8_t *data, size_t nblocks);
int64_t w_sha256_sw_mine(const uint32_t *midstate, const uint8_t *tail, const uint32_t *target_be,
                         uint32_t start, int64_t count, uint32_t *out_hash, uint32_t *out_best,
                         uint32_t *out_best_hash);

/* ---- Outbound TCP connect ---- */
WValue w_socket_tcp_connect(const char *host, int port);

/* ---- TLS ---- */
WValue w_tls_init(void);
WValue w_tls_load_cert(const char *cert_path, const char *key_path);
WValue w_tls_wrap(WValue sock);
WValue w_tls_client_wrap(WValue sock, const char *hostname);
int w_tls_server_configured(void);
const char *w_tls_get_cert_path(void);
const char *w_tls_get_key_path(void);

/* ---- ALPN ---- */
WValue w_socket_alpn_protocol(WValue sock);

/* ---- RSA Crypto ---- */
WValue w_crypto_generate_rsa_key(int64_t bits);
WValue w_crypto_rsa_public_jwk(WValue key);
WValue w_crypto_rsa_sign_sha256(WValue key, WValue data);
WValue w_crypto_rsa_thumbprint(WValue key);
WValue w_crypto_generate_csr(WValue key, WValue domains);

/* ---- HTTP Response ---- */
#define W_BODY_PTR     0
#define W_BODY_INLINE  1
#define W_BODY_ROPE    2
#define W_BODY_STRBUF  3

typedef struct WResponse {
    uint8_t type;    /* W_TYPE_RESPONSE */
    uint8_t body_kind;
    uint8_t pad[2];
    int status;
    const char *body;
    size_t body_len;
    WValue body_val; /* optional original rope/strbuf body for non-flattening writes */
    char body_inline[6];
} WResponse;

WValue w_response_new(int status, const char *body, size_t body_len);
WValue w_response_new_wv(WValue status_val, WValue body_val);

/* ---- HTTP serve ---- */
WValue w_socket_serve_http(WValue listener, WValue handler, int workers);

/* ---- HTTP benchmark (Hammer) — see bit/tungsten-hammer/lib/hammer.c ---- */

/* ---- Command-line arguments ---- */
void w_argv_init(int argc, char **argv);
WValue __w_argv_count(void);
WValue __w_argv_at(WValue index);
WValue __w_system(WValue command);

/* ---- Process paths ---- */
WValue w_executable_path(void);
WValue w_executable_dir(void);
WValue w_cpu_count(void);
WValue w_physical_memory_bytes(void);

/* ---- Monotonic clock ---- */
WValue __w_clock_ms(void);
WValue __w_sleep_ms(int64_t milliseconds);
WValue __w_clock(void);
int64_t __w_clock_ticks_raw(void);
int64_t __w_deadline_ticks_after_seconds(int64_t seconds);
int64_t __w_clock_ns_raw(void);
WValue __w_elapsed_seconds_since_ns(int64_t start_ns);
WValue __w_elapsed_seconds_since_ticks(int64_t start_ticks);
WValue __w_read_file(WValue path_val);
WValue __w_read_file_bytes(WValue path_val);
WValue __w_write_file(WValue path_val, WValue content_val);
WValue __w_file_exists(WValue path_val);
WValue __w_file_directory(WValue path_val);
WValue __w_file_read_dir(WValue path_val);
WValue __w_file_size(WValue path_val);
WValue __w_file_mtime_ns(WValue path_val);
WValue __w_file_expand_path(WValue path_val);
WValue __w_file_expand_path_base(WValue path_val, WValue base_val);
WValue __w_file_join(WValue left, WValue right);
WValue __w_file_stat_data(WValue path_val, WValue follow_val);
WValue __w_tempfile_create(WValue prefix_val, WValue directory_val);
WValue __w_file_link(WValue target_val, WValue link_val);
WValue __w_file_chmod(WValue path_val, WValue mode_val);
WValue __w_rename(WValue old_val, WValue new_val);
WValue __w_temp_file_for(WValue destination_val);
WValue __w_fsync_path(WValue path_val);
WValue __w_fsync_parent(WValue path_val);
WValue __w_unlink(WValue path_val);
WValue __w_file_unlink_strict(WValue path_val);
WValue __w_digest_bytes64(WValue bytes_val);
WValue __w_digest_file64(WValue path_val);
WValue __w_digest_string64(WValue string_val);
WValue __w_cache_read(WValue path_val);
WValue __w_cache_write(WValue path_val, WValue value);
/* Compiler-internal persistent graph cache.  Unlike the bootstrap cache
 * builtins, this format understands packed WIRE records and preserves shared
 * Array/Hash/WIRE references.  Unsupported heap values fail closed. */
WValue w_core_cache_read(WValue path_val);
WValue w_core_cache_read_rebase_locations(WValue path_val, WValue old_file_id,
                                          WValue new_file_id);
WValue w_core_cache_write(WValue path_val, WValue value);
WValue __w_runtime_identity(void);

/* ---- Primality (optional, linked from aks.c) ---- */
extern int __w_prime_aks_u64(uint64_t n) __attribute__((weak));
WValue __w_prime_aks(WValue n);

/* ---- Symbol table ---- */
const char *w_symbol_name(uint64_t id);

/* ---- Value inspector (debugging) ---- */
void w_inspect(WValue v);
WValue w_inspect_s(WValue v);

/* ---- Generic object type checks (sub-tag 0, type from header byte) ---- */
static inline int w_is_thread(WValue v) {
    return w_is_obj(v) && w_subtag(v) == W_SUBTAG_GENERIC &&
           ((WThread *)w_as_ptr(v))->type == W_TYPE_THREAD;
}
/* WAtomic promoted to its own subtag — single compare. */
static inline int w_is_atomic(WValue v) {
    return w_is_obj(v) && w_subtag(v) == W_SUBTAG_ATOMIC;
}
static inline int w_is_channel(WValue v) {
    return w_is_obj(v) && w_subtag(v) == W_SUBTAG_GENERIC &&
           ((WChan *)w_as_ptr(v))->type == W_TYPE_CHANNEL;
}
static inline int w_is_mutex(WValue v) {
    return w_is_obj(v) && w_subtag(v) == W_SUBTAG_GENERIC &&
           ((WMutex *)w_as_ptr(v))->type == W_TYPE_MUTEX;
}
/* ByteArray (was Bytes) is now a WArray with ebits=8.
 * Same predicate as `w_is_array && ebits == 8`. */
static inline int w_is_bytes(WValue v) {
    return w_is_array(v) && w_as_array(v)->ebits == 8;
}
static inline int w_is_response(WValue v) {
    return w_is_obj(v) && w_subtag(v) == W_SUBTAG_GENERIC &&
           ((WResponse *)w_as_ptr(v))->type == W_TYPE_RESPONSE;
}
/* BoolArray is now a WArray with ebits=1 (bit-packed). */
static inline int w_is_bool_array(WValue v) {
    return w_is_array(v) && w_as_array(v)->ebits == 1;
}
/* BigArray lives on W_SUBTAG_GENERIC because the 4-bit subtag
 * space was exhausted at the time; it's distinguished by the type byte at
 * offset 0 (W_TYPE_BIG_ARRAY). w_dispatch_key returns `0x80 | type`,
 * which keeps Tungsten-side type_class registration stable. SmallArray
 * was reclaimed as a dedicated subtag (see w_is_small_array
 * below); only BigArray still uses the generic-bucket pattern. */
static inline int w_is_big_array(WValue v) {
    return w_is_obj(v) && w_subtag(v) == W_SUBTAG_GENERIC &&
           ((WBigArray *)w_as_ptr(v))->type == W_TYPE_BIG_ARRAY;
}
/* SmallArray has its own dedicated subtag — single compare,
 * no struct read needed. */
static inline int w_is_small_array(WValue v) {
    return w_is_obj(v) && w_subtag(v) == W_SUBTAG_SMALL_ARRAY;
}

/* Generic-bucket predicates read the type byte at offset 0 of the
 * heap struct.  BigInt was subsequently promoted into its own free subtag. */
static inline int w_is_ipv6(WValue v) {
    return w_is_obj(v) && w_subtag(v) == W_SUBTAG_GENERIC &&
           ((WNetAddr *)w_as_ptr(v))->type == W_TYPE_IPV6;
}
static inline int w_is_mac(WValue v) {
    return w_is_obj(v) && w_subtag(v) == W_SUBTAG_GENERIC &&
           ((WNetAddr *)w_as_ptr(v))->type == W_TYPE_MAC;
}
static inline int w_is_encoded(WValue v) {
    return w_is_obj(v) && w_subtag(v) == W_SUBTAG_GENERIC &&
           ((WEncodedValue *)w_as_ptr(v))->type == W_TYPE_ENCODED;
}
static inline int w_is_bigint(WValue v) {
    /* Dedicated top-level tag 0xFFFB — one compare, no object-range test. */
    return (v & W_TAG_MASK) == W_TAG_BIGINT;
}
/* True if v is an inline i48 int OR a heap-allocated BigInt.
 * Because W_TAG_INT (0xFFFA) and W_TAG_BIGINT (0xFFFB) are power-of-2 adjacent,
 * bits 63..49 are identical. A single 15-bit mask classifies all integers branchlessly. */
static inline int w_is_integer_any(WValue v) {
    return (v & 0xFFFE000000000000ULL) == 0xFFFA000000000000ULL;
}
static inline int w_both_integers_any(WValue a, WValue b) {
    return (((a ^ W_TAG_INT) | (b ^ W_TAG_INT)) & 0xFFFE000000000000ULL) == 0;
}

/* ---- StringBuffer (mutable growable byte buffer) ----
 * Promoted to W_SUBTAG_STRBUF (subtag 0xB). Type byte removed
 * from offset 0 — the subtag now identifies StringBuffer. */
typedef struct WStrBuf {
    uint8_t flags;       /* W_FLAG_* bits */
    uint8_t _pad[7];     /* keep `data` ptr at offset 8 for natural alignment */
    char   *data;
    int64_t size;        /* renamed from length */
    int64_t cap;
} WStrBuf;

WValue w_strbuf_new(WValue cap);
WValue w_strbuf_reuse_or_new(WValue *slot, int64_t cap);
WValue w_strbuf_recycle_or_new(int64_t cap);
void   w_strbuf_recycle(WValue v);
WValue w_strbuf_append(WValue buf, WValue str);
WValue w_strbuf_to_s(WValue buf);

/* WStrBuf promoted to its own subtag (W_SUBTAG_STRBUF). */
static inline int w_is_strbuf(WValue v) {
    return w_is_obj(v) && w_subtag(v) == W_SUBTAG_STRBUF;
}

/* ---- Rope (lazy concatenation of strings) ---- */
typedef struct {
    uint8_t type;       /* W_TYPE_ROPE */
    WValue left;        /* string or rope */
    WValue right;       /* string or rope */
    uint32_t total_len; /* cached byte length */
    WValue flat;        /* cached flattened WValue string, 0 = not yet */
} WRope;

static inline int w_is_rope(WValue v) {
    return w_is_obj(v) && w_subtag(v) == W_SUBTAG_GENERIC &&
           ((WRope *)w_as_ptr(v))->type == W_TYPE_ROPE;
}

WValue w_rope_flatten(WValue v);

#endif /* TUNGSTEN_RUNTIME_H */
