#ifndef TUNGSTEN_C_TC_H
#define TUNGSTEN_C_TC_H

#include <stddef.h>
#include <stdint.h>
#include <stdio.h>

#include "wvalue.h"

enum {
  TC_T_ID = 1,
  TC_T_NAME = 2,
  TC_T_INT = 3,
  TC_T_DECIMAL = 4,
  TC_T_STRING = 5,
  TC_T_SYMBOL = 6,
  TC_T_TYPE_HINT = 7,
  TC_T_NEWLINE = 8,
  TC_T_INDENT = 9,
  TC_T_DEDENT = 10,
  TC_T_OP = 11,
  TC_T_IVAR = 12,
  TC_T_CVAR = 13,
  TC_T_PARG = 14,
  TC_T_BYTE_ARRAY = 15,
  TC_T_KEY = 16,
  TC_T_COLOR = 17,
  TC_T_CHAR = 18,
  TC_T_CODEPOINT = 19,
  TC_T_WORD_ARRAY = 20,
  TC_T_SYMBOL_ARRAY = 21,
  TC_T_MAGIC = 22,
  TC_T_EOF = 23,
  TC_T_PATH = 24,
};

enum {
  TC_F_NEWLINE = 0x80,
  TC_F_ID_START = 0x40,
  TC_F_ID_CONTINUE = 0x20,
  TC_F_WHITESPACE = 0x10,
  TC_F_HEX = 0x08,
  TC_F_OPERATOR = 0x04,
  TC_F_QUOTE = 0x02,
  TC_F_DIGIT = 0x01,
};

enum {
  TC_OP_CONST = 1,
  TC_OP_LOAD_LOCAL,
  TC_OP_STORE_LOCAL,
  TC_OP_ADD,
  TC_OP_SUB,
  TC_OP_MUL,
  TC_OP_DIV,
  TC_OP_EQ,
  TC_OP_NEQ,
  TC_OP_LT,
  TC_OP_LTE,
  TC_OP_GT,
  TC_OP_GTE,
  TC_OP_MOD,
  TC_OP_BIT_AND,
  TC_OP_BIT_OR,
  TC_OP_BIT_XOR,
  TC_OP_SHL,
  TC_OP_SHR,
  TC_OP_POW,
  TC_OP_PRINT,
  TC_OP_POP,
  TC_OP_RETURN,
  TC_OP_JUMP,
  TC_OP_JUMP_IF_FALSE,
  TC_OP_CALL,
  TC_OP_ARRAY,
  TC_OP_HASH,
  // Peephole-fused superinstructions emitted by the compiler when the
  // raw sequence is hot. Both are pure rewrites of the prior shape —
  // semantics are identical to the constituent ops.
  //   EQ_CONST_BR <const_id> <jump_target>
  //     pop a; if (a == consts[id]) fallthrough; else jump.
  //     Replaces CONST id; EQ; JUMP_IF_FALSE target — the
  //     case-dispatch backbone (~25% of stage-1 dispatches).
  //   CALL_DISCARD ... (same operands as CALL)
  //     Like CALL but does not push the return value. Replaces CALL
  //     followed by POP for statement-position calls.
  // TC_OP_NOP fills the gap left when a peephole rewrite collapses
  // multiple instructions but the compiler can't shrink the chunk
  // (jump targets are absolute byte offsets).
  TC_OP_EQ_CONST_BR,
  TC_OP_CALL_DISCARD,
  TC_OP_NOP,
  // INDEX: pop subscript + receiver from stack, push receiver[subscript].
  // Promoted from the generic CALL "[]" path (~60% of stage-1 calls,
  // ~33M dispatches). Skips operand decode, arg-buffer setup, name
  // lookup, and the L_CALL matcher chain entirely. Compiler emits
  // this whenever it sees a `receiver[arg]` call shape (one arg, one
  // receiver, name "[]").
  TC_OP_INDEX,
  // SIZE_OF: pop receiver, push receiver.size as int. Promoted from
  // the CALL "size" argc=0 path (~8M dispatches/run, 14% of CALL).
  TC_OP_SIZE_OF,
  // INDEX_LL <recv_slot> <idx_slot>: peephole fusion of
  // LOAD_LOCAL recv ; LOAD_LOCAL idx ; INDEX. Reads both locals
  // directly and pushes recv[idx] in one dispatch. Replaces the
  // 3-op / 11-byte sequence with one 9-byte op + 2 NOP padding.
  TC_OP_INDEX_LL,
  // SIZE_OF_LOCAL <slot>: peephole fusion of LOAD_LOCAL slot ; SIZE_OF.
  // Pushes locals[slot].size as int. Same shape as INDEX_LL but
  // single-operand (the receiver only).
  TC_OP_SIZE_OF_LOCAL,
  // LOAD_EQ_CONST_BR <slot> <const_id> <target>: peephole fusion of
  // LOAD_LOCAL slot ; EQ_CONST_BR const_id target. Reads the local,
  // compares to consts[const_id], jumps on miss. Targets the
  // `case t when :var ...` shape where `t` is a local — the
  // dominant case-dispatch pattern in compiler/lib/lowering.w.
  TC_OP_LOAD_EQ_CONST_BR,
  // CASE_SYM_LINEAR <table_id>
  //   pop scrutinee; linear-scan chunk->case_tables[id].keys for an
  //   interned bytes-pointer match (subject must be TC_VAL_SYMBOL);
  //   jump to the matched target on hit, default_target on miss.
  //   Replaces an N-arm chain of LOAD_LOCAL + EQ_CONST_BR + JUMP for
  //   sym-only case statements (the dominant case-dispatch shape in
  //   compiler/lib/lowering.w's `case t when :var` etc).
  TC_OP_CASE_SYM_LINEAR,
  // IVAR_GET <name_const_id>: read self->fields[name_const_id]. Self comes
  // from the local slot named "self" (bound by vm_call_function on every
  // method call via a TC_VAL_OBJECT receiver). `name_const_id` indexes a
  // chunk-local TC_VAL_SYMBOL const whose interned bytes are the ivar
  // name *without* the leading `@`. Missing field → nil. Outside an
  // object method (no self) → nil.
  TC_OP_IVAR_GET,
  // IVAR_SET <name_const_id>: pop tos, store into self->fields[name].
  // Lazy-allocates the fields hash on first set. Leaves the value on the
  // stack so it composes as an expression (matches compile_assign's
  // "value of an assignment is the assigned value" contract).
  TC_OP_IVAR_SET,
  // CVAR_GET / CVAR_SET <name_const_id>: class variables (`@@name`).
  // Backed by a process-global TcRuntimeHash keyed by the verbatim
  // `@@name` symbol — adequate for bootstrap-scope (the compiler uses
  // only `@@all` and `@@name`, both inside lowering.w). Real per-class
  // scoping would compose the key as "ClassName.@@name"; deferred
  // until a class collision shows up.
  TC_OP_CVAR_GET,
  TC_OP_CVAR_SET,
  // TYPED_ARRAY: pop size from stack, push a fresh runtime array of that
  // size pre-filled with int(0). Backs the `i64[N]` literal syntax used by
  // the lexer to allocate scratch buffers. Was previously stubbed out as
  // emit_nil, which produced nil and caused indexing into the "array" to
  // return nil — manifesting as `operator > expects integer operands`
  // when the lexer compared `lc[pos] > x` against a nil load.
  TC_OP_TYPED_ARRAY,
  // CASE_MATCH: pop pattern, pop subject, push true if `case subject when
  // pattern` would match. Equivalent to native's `===`: ranges check
  // cover, everything else falls back to equality. Replaces TC_OP_EQ in
  // compile_case_value/compile_case so `case 65 when 32..126` matches the
  // way the native-compiled output does (the equality-only path always
  // returned false because 65 != the range-hash sentinel).
  TC_OP_CASE_MATCH,
};

typedef struct {
  char *message;
} TcError;

typedef struct {
  unsigned char *bytes;
  size_t byte_len;
  uint64_t *lc;
  uint32_t *byte_offsets;
  size_t cp_count;
  // Precomputed byte-offset → 1-based line number. Sized byte_len + 1.
  // Replaces the O(N) per-token newline-counting scan in
  // token_line_ast (which made AST construction quadratic in source
  // size and dominated VM-only bootstrap time).
  uint32_t *byte_lines;
} TcSource;

typedef struct {
  WValue *items;
  size_t count;
  size_t cap;
} TcTokens;

typedef enum {
  TC_K_UNKNOWN = 0,
  TC_K_ID,
  TC_K_NAME,
  TC_K_TYPE,
  TC_K_KEYWORD,
  TC_K_GLOBAL,
  TC_K_INT,
  TC_K_DECIMAL,
  TC_K_STRING,
  TC_K_SYMBOL,
  TC_K_TYPE_HINT,
  TC_K_NEWLINE,
  TC_K_INDENT,
  TC_K_DEDENT,
  TC_K_IVAR,
  TC_K_CVAR,
  TC_K_PARG,
  TC_K_BYTE_ARRAY,
  TC_K_KEY,
  TC_K_COLOR,
  TC_K_CHAR,
  TC_K_CODEPOINT,
  TC_K_WORD_ARRAY,
  TC_K_SYMBOL_ARRAY,
  TC_K_MAGIC_FILE,
  TC_K_MAGIC_LINE,
  TC_K_MAGIC_DIR,
  TC_K_PATH,
  TC_K_EOF,
  TC_K_ARROW,
  TC_K_LAMBDA_ARITY,
  TC_K_LSHIFT,
  TC_K_PUTS_OP,
  TC_K_PLUS,
  TC_K_CLASS_DEF,
  TC_K_MAP,
  TC_K_PRINT_OP,
  TC_K_RAISE_OP,
  TC_K_FAT_ARROW,
  TC_K_EQ,
  TC_K_MATCH,
  TC_K_NEQ,
  TC_K_LTE,
  TC_K_RSHIFT,
  TC_K_GTE,
  TC_K_SAFE_NAV,
  TC_K_AND,
  TC_K_OR_ASSIGN,
  TC_K_OR,
  TC_K_PIPE_FWD,
  TC_K_PLUS_PLUS,
  TC_K_PLUS_EQ,
  TC_K_MINUS_MINUS,
  TC_K_MINUS_EQ,
  TC_K_POW,
  TC_K_STAR_EQ,
  TC_K_SLASH_EQ,
  TC_K_PERCENT_EQ,
  TC_K_MINUS,
  TC_K_STAR,
  TC_K_SLASH,
  TC_K_DOT_PRODUCT,
  TC_K_CROSS_PRODUCT,
  TC_K_PERCENT,
  TC_K_LT,
  TC_K_GT,
  TC_K_ASSIGN,
  TC_K_BANG,
  TC_K_DOTDOTDOT,
  TC_K_DOTDOT,
  TC_K_DOT_PLUS,
  TC_K_DOT_MINUS,
  TC_K_DOT_STAR,
  TC_K_DOT_SLASH,
  TC_K_DOT_PIPE,
  TC_K_DOT_AMP,
  TC_K_DOT_CARET,
  TC_K_DOT_LSHIFT,
  TC_K_DOT_RSHIFT,
  TC_K_DOT,
  TC_K_COMMA,
  TC_K_BLOCK_CALL,
  TC_K_AMPERSAND,
  TC_K_PIPE,
  TC_K_CARET,
  TC_K_LPAREN,
  TC_K_RPAREN,
  TC_K_LBRACE,
  TC_K_RBRACE,
  TC_K_LBRACKET,
  TC_K_RBRACKET,
  TC_K_QUESTION,
  TC_K_COLON,
  TC_K_SEMICOLON,
} TcKind;

typedef struct {
  TcKind kind;
  WValue packed;
} TcSyntaxToken;

typedef struct {
  TcSyntaxToken *items;
  size_t count;
  size_t cap;
} TcSyntaxTokens;

typedef enum {
  TC_AST_NIL,
  TC_AST_BOOL,
  TC_AST_INT,
  TC_AST_STRING,
  TC_AST_SYMBOL,
  TC_AST_ARRAY,
  TC_AST_HASH,
} TcAstKind;

typedef struct TcAstArray TcAstArray;
typedef struct TcAstHash TcAstHash;

typedef struct TcAstValue {
  TcAstKind kind;
  union {
    int boolean;
    int64_t integer;
    struct {
      char *bytes;
      size_t len;
    } string;
    TcAstArray *array;
    TcAstHash *hash;
  } as;
} TcAstValue;

struct TcAstArray {
  TcAstValue *items;
  size_t count;
  size_t cap;
};

typedef struct {
  char *key;
  TcAstValue value;
} TcAstEntry;

struct TcAstHash {
  TcAstEntry *items;
  size_t count;
  size_t cap;
};

typedef struct {
  size_t nodes;
  size_t raw_nodes;
  size_t use_nodes;
} TcAstStats;

typedef enum {
  TC_VAL_NIL,
  TC_VAL_WVALUE,
  TC_VAL_INT,
  TC_VAL_STRING,
  TC_VAL_SYMBOL,
  TC_VAL_ARRAY,
  TC_VAL_HASH,
  TC_VAL_OBJECT,
  TC_VAL_AST,
} TcValueKind;

typedef struct TcRuntimeArray TcRuntimeArray;
typedef struct TcRuntimeHash TcRuntimeHash;
typedef struct TcRuntimeObject TcRuntimeObject;
typedef struct TcHeapString TcHeapString;

// Heap-allocated string/symbol bytes. The `bytes` field is a flexible-array
// member so the bytes follow the header in one allocation; this lets every
// consumer hold a `const char *` to the bytes and recover the header via
// `(TcHeapString *)((char *)bytes - offsetof(TcHeapString, bytes))`.
//
// The `interned` flag distinguishes two heap-string lifetimes:
//   - interned=1: owned by the global intern table; lives forever, never
//     freed by GC sweep, never freed by chunk teardown.
//   - interned=0: transient; freed by the GC sweep when unreferenced or by
//     chunk teardown if it's a managed const.
//
// Pre-flip, every TcValue.bytes that is TC_VAL_STRING or TC_VAL_SYMBOL
// points into a TcHeapString.bytes flex array; the helpers in vm.c and
// the new tc_heap_string_alloc() guarantee that. Post-flip, the WValue
// heap-string tag mode points directly at TcHeapString*.
// 16-byte header (was 32 with _Alignas(16)). Field order chosen so
// cached_hash naturally aligns at offset 8 and bytes[] starts at the
// next 8-byte boundary — keeping the wyhash unaligned-load fast path
// happy without the explicit alignas. `len` is u32 because no Tungsten
// string ever approaches 4GB; the payoff is room for `interned` to
// share the first word with len, and a smaller per-string footprint.
struct TcHeapString {
  uint32_t len;
  uint8_t interned;        // 1 = owned by intern table, never freed
  // 3 bytes padding; cached_hash naturally aligns at offset 8.
  // Cached hash_value64 result. 0 = not yet computed (real wyhash
  // collisions with 0 occur with probability 2^-64; on those we just
  // recompute and restore the same value).
  uint64_t cached_hash;
  char bytes[];
};

// Allocate a TcHeapString sized for `len` bytes (caller fills bytes[]).
// `interned=0` registers in the GC heap-string list; `interned=1` keeps
// it out of GC bookkeeping (lives until process exit).
char *tc_heap_string_alloc(size_t len, int interned, TcError *err);
// Recover the header from any pointer returned by tc_heap_string_alloc.
TcHeapString *tc_heap_string_header(const char *bytes);
// Free a heap string IF it's not interned. Used by chunk teardown.
void tc_heap_string_release(const char *bytes);

// TcValue is now NaN-boxed: a uint64_t with the encoding from
// runtime/wvalue.h (W_NIL/TRUE/FALSE singletons, biased doubles, tagged
// int/string/symbol/etc., and 0x0000-space heap pointers with a 4-bit
// sub-tag in the low nibble).
//
// Slot size dropped 32B → 8B; that's the cache win the dispatch loop and
// stack/locals/consts arrays were waiting for. The full TcValueKind
// discriminator that the rest of the source switches on is computed from
// the WValue tag in tc_kind() below.
typedef WValue TcValue;

// String/symbol encoding nibble shared between the runtime and this VM.
// Values from runtime/wvalue.h: heap pointer with low nibble = sub-tag.
//   0xA = array        0x5 = hash        0x4 = object (struct)        0x0 = AST (generic)
// We don't use 0x6/0x8/0xC/etc. for now — those tags belong to runtime
// types the bootstrap doesn't reach.
#define TC_TAG_ARRAY  0xAU
#define TC_TAG_HASH   0x5U
#define TC_TAG_OBJECT 0x4U
#define TC_TAG_AST    0x0U
#define TC_TAG_HEAP_INT 0xBU  // matches runtime/wvalue.h's bigint nibble; we
                              // use it for any int that overflows the 48-bit
                              // signed payload of W_TAG_INT.

// ── Constructors ─────────────────────────────────────────────────────────
static inline TcValue tc_box_nil(void)         { return W_NIL; }
static inline TcValue tc_box_bool(int b)       { return b ? W_TRUE : W_FALSE; }
static inline TcValue tc_box_wvalue(WValue w)  { return w; }
// Out-of-line so the heap-int spillover path stays out of the hot path's
// instruction footprint. ~5 literals across the bootstrap exceed 48 bits
// (the NaN-boxing tag constants in compiler/lib/runtime_types.w —
// w_tag_int = 0xFFFA000000000000, etc.). Without this spillover those
// literals silently truncate to 0 in w_box_int, the lowering's `v |=
// w_tag_int` collapses to `v |= 0`, and the bootstrap binary segfaults
// on its first WValue access.
TcValue tc_box_int(int64_t v);
static inline TcValue tc_box_array(TcRuntimeArray *p)   { return w_box_ptr(p, TC_TAG_ARRAY); }
static inline TcValue tc_box_hash(TcRuntimeHash *p)     { return w_box_ptr(p, TC_TAG_HASH); }
static inline TcValue tc_box_object(TcRuntimeObject *p) { return w_box_ptr(p, TC_TAG_OBJECT); }

// String/symbol constructors — every `bytes` argument MUST point into a
// TcHeapString.bytes flex array (guaranteed by the const-pool migration in
// the prior commit). The `managed` arg is now ignored: ownership lives in
// the TcHeapString.interned flag, not on the value.
static inline TcValue tc_box_string_bytes(const char *bytes, size_t len, int managed) {
  (void)managed;
  TcHeapString *ws = tc_heap_string_header(bytes);
  (void)len;  // the header carries len; checked by w_as_heap_str consumers.
  return w_box_heap_str((struct WString *)ws);
}
static inline TcValue tc_box_symbol_bytes(const char *bytes, size_t len, int managed) {
  (void)managed;
  TcHeapString *ws = tc_heap_string_header(bytes);
  (void)len;
  return w_box_heap_sym((struct WString *)ws);
}

// Heap-allocated int box for values that overflow W_TAG_INT's 48-bit
// payload. Tagged as a 0x0000-space heap pointer with low nibble
// TC_TAG_HEAP_INT. tc_kind treats both inline and heap-boxed ints as
// TC_VAL_INT, so consumers don't have to distinguish.
typedef struct TcHeapInt {
  int64_t value;
} TcHeapInt;

// ── Accessors ────────────────────────────────────────────────────────────
static inline TcValueKind tc_kind(TcValue v) {
  if (v == W_NIL) return TC_VAL_NIL;
  if (v == W_TRUE || v == W_FALSE) return TC_VAL_WVALUE;
  if (w_is_int(v))    return TC_VAL_INT;
  if (w_is_string(v)) return TC_VAL_STRING;
  if (w_is_symbol(v)) return TC_VAL_SYMBOL;
  // 0x0000-space heap pointer with sub-tag in the low nibble.
  if ((v & W_TAG_MASK) == 0) {
    switch (v & 0xFU) {
      case TC_TAG_ARRAY:    return TC_VAL_ARRAY;
      case TC_TAG_HASH:     return TC_VAL_HASH;
      case TC_TAG_OBJECT:   return TC_VAL_OBJECT;
      case TC_TAG_AST:      return TC_VAL_AST;
      case TC_TAG_HEAP_INT: return TC_VAL_INT;
    }
  }
  return TC_VAL_WVALUE;  // doubles, instants, chars, durations, packed types
}

static inline int tc_managed(TcValue v) {
  // Heap-string transient flag. The TcHeapString header tells us; for non-
  // string/sym kinds the answer is 0 (other heap structs live in their own
  // GC lists, not tracked by this flag).
  if (!(w_is_string(v) || w_is_symbol(v))) return 0;
  TcHeapString *ws = (TcHeapString *)w_as_heap_str(v);
  return ws ? !ws->interned : 0;
}

// tc_as_int handles both inline (W_TAG_INT, 48-bit signed payload) and
// heap-boxed (TC_TAG_HEAP_INT, 64-bit) representations. The W_TAG_INT
// fast path is the common case; only the ~5 NaN-boxing tag literals
// from runtime_types.w take the heap path during the bootstrap.
static inline int64_t tc_as_int(TcValue v) {
  if (w_is_int(v)) return w_as_int(v);
  return ((TcHeapInt *)w_as_ptr(v))->value;
}
static inline WValue  tc_as_wvalue(TcValue v)          { return v; }
static inline TcRuntimeArray  *tc_as_array(TcValue v)  { return (TcRuntimeArray *)w_as_ptr(v); }
static inline TcRuntimeHash   *tc_as_hash(TcValue v)   { return (TcRuntimeHash *)w_as_ptr(v); }
static inline TcRuntimeObject *tc_as_object(TcValue v) { return (TcRuntimeObject *)w_as_ptr(v); }
static inline TcAstValue *tc_as_ast_ptr(TcValue *v)    { return (TcAstValue *)w_as_ptr(*v); }

// String access. The `inline_buf` argument on tc_str_bytes() is reserved
// for a future post-flip optimization where ≤5-byte strings are tag-
// packed; today every string is heap-allocated so the buffer goes unused.
static inline const char *tc_str_bytes(TcValue v, char inline_buf[6], size_t *len_out) {
  (void)inline_buf;
  TcHeapString *ws = (TcHeapString *)w_as_heap_str(v);
  if (len_out) *len_out = ws->len;
  return ws->bytes;
}
static inline const char *tc_str_bytes_only(TcValue v) {
  TcHeapString *ws = (TcHeapString *)w_as_heap_str(v);
  return ws->bytes;
}
static inline size_t tc_str_len(TcValue v) {
  TcHeapString *ws = (TcHeapString *)w_as_heap_str(v);
  return ws->len;
}

// AST construction. Pre-flip stored inline in the union; post-flip arena-
// allocates a TcAstValue copy and tags the pointer. The arena is the same
// one parse_ast.c uses for AST nodes — lives until process exit, no GC.
TcValue tc_box_ast(TcAstValue ast, TcError *err);

// All four heap struct types get 16-byte alignment so a post-flip WValue
// (NaN-boxed uint64_t) can stash them directly via w_box_ptr — that tag
// scheme requires a 16-byte-aligned pointer so the low nibble is free for
// the kind-tag. macOS malloc happens to return 16B-aligned blocks today,
// but `_Alignas(16)` makes the contract explicit and lets the compiler
// catch any future change.
// Layout matches runtime/runtime.h's WArray exactly (24 bytes, same field
// order). Lets cross-runtime sharing stay layout-compatible and keeps the
// header cache-friendly. Was 48 bytes pre-flip with int32 marked/managed
// + heap_next + size_t count/cap; the GC fields are gone (no GC in C VM)
// and count/cap demote to int32 to match WArray. Capacity ceiling is
// INT32_MAX (~2 billion slots), well above any realistic array size.
//
// Fields:
//   flags  — W_FLAG_* bits (mirrors runtime/runtime.h)
//   ebits  — element-type code; 65 (w64) for the polymorphic-WValue tier,
//            which is the only tier the C VM uses today. Future typed-tier
//            support (i8/i16/i32/i64/f32/f64) would slot in here.
//   start  — logical start index for O(1) shift; iteration accesses
//            slots[start + i]. Stays 0 until shift opt is wired up.
//   size   — number of live elements (was `count`).
//   cap    — total allocated slot count (was `cap`).
//   slots  — base allocation pointer (was `items`).
struct TcRuntimeArray {
  uint8_t flags;
  int8_t  ebits;
  uint8_t _pad[2];
  int32_t start;
  int32_t size;
  int32_t cap;
  WValue *slots;
};

// Layout matches runtime/runtime.h's WHash exactly: same field order, same
// sizes, same sentinels. Iteration walks 0..cap-1 and skips W_UNDEF /
// W_MEMO_MISS slots — bit-exact with native's slot order so hash iteration
// produces identical IR ordering across C VM and stage 2.
struct TcRuntimeHash {
  uint32_t count;
  uint32_t cap;
  uint8_t flags;
  uint8_t pad[7];
  WValue *keys;
  WValue *values;
};

// Hash sentinels — same as runtime/wvalue.h's W_UNDEF (empty slot) and
// W_MEMO_MISS (tombstone). Sub-tag-mask values that no real boxed kind can
// take. The hash machinery always checks for them explicitly before any
// tc_kind / value_equal call, so the type-tag overlap (W_MEMO_MISS shares
// a low nibble with TC_TAG_OBJECT) is never observed in practice.
#define TC_HASH_EMPTY     W_UNDEF
#define TC_HASH_TOMBSTONE W_MEMO_MISS

struct TcRuntimeObject {
  _Alignas(16)
  char *class_name;
  size_t class_name_len;
  char *buffer;
  size_t buffer_len;
  size_t buffer_cap;
  // Instance variables. Lazy-allocated on first IVAR_SET; reads against
  // a NULL fields return nil. Keys are interned symbols (class compiles
  // `@name` to a TcValue symbol const), values are arbitrary TcValues.
  TcRuntimeHash *fields;
};

typedef struct {
  char *name;
  size_t name_len;
  uint32_t entry;
  uint32_t arity;
  uint32_t *param_slots;
  // Slots this function writes (STORE_LOCAL targets + params + self).
  // Computed once at chunk finalize. vm_call_function saves only these
  // from the caller's locals — reduces per-call memcpy from 64KB to
  // a few hundred bytes.
  uint32_t *touched_slots;
  uint32_t touched_slot_count;
} TcFunction;

typedef struct {
  char *name;
  size_t len;
} TcLocalName;

// CASE_SYM_LINEAR jump table. Sized once at compile time. Keys are
// interned sym bytes pointers (compared via ptr-equality, no memcmp).
// targets[i] is the bytecode offset for keys[i]; default_target is the
// offset to jump to on a miss (or when the scrutinee isn't a sym).
typedef struct {
  const char **keys;
  uint32_t *targets;
  uint32_t count;
  uint32_t default_target;
} TcCaseTable;

typedef struct {
  uint8_t *code;
  size_t count;
  size_t cap;
  TcValue *consts;
  size_t const_count;
  size_t const_cap;
  // Open-addressing dedup index for string/symbol consts. Each slot
  // is a const_id+1 (0 means empty). Probing on (hash & mask). Lets
  // tc_chunk_add_const dedupe by content in O(1), so every literal
  // `:foo` site shares one bytes buffer; the runtime ptr-equality
  // path in value_equal then hits on every literal-vs-literal sym
  // compare (~80% of bootstrap sym EQs by measurement).
  uint32_t *const_dedup_index;
  size_t const_dedup_cap;  // power-of-two slot count
  // Local names indexed by slot. The name plus its precomputed length
  // (avoid the per-lookup strlen scan that showed up in profile).
  TcLocalName *locals;
  size_t local_count;
  size_t local_cap;
  size_t global_count;
  TcFunction *functions;
  size_t function_count;
  size_t function_cap;
  // CASE_SYM_LINEAR jump tables. Each table is a flat (keys, targets)
  // pair sized to the case statement's arm count. Keys are interned
  // sym bytes pointers (compared via ptr-equality). Lives off-band
  // because the opcode stream is too tight to inline a variable-size
  // table.
  TcCaseTable *case_tables;
  size_t case_table_count;
  size_t case_table_cap;
  // CALL fast path: name_id (chunk const id of the function name) →
  // resolved TcFunction*. Indexed by name_id directly so the lookup
  // is one array load. Populated once at chunk finalize. NULL means
  // either the const is not a function name, or it's a method name
  // that resolves through `class#method` (which needs the dynamic
  // full-name construction in L_CALL — fast path doesn't apply).
  TcFunction **fn_for_const;
  // Implicit-self method dispatch IC: for each name_id, cache the last
  // resolved (class_name pointer, TcFunction*). Class names are interned
  // C strings so pointer equality is sufficient. Hit rate is near 100%
  // for compiler/tungsten.w, where a method call site is monomorphic.
  // Skips the malloc + memcpy + O(N) linear name scan in
  // tc_chunk_find_function. Both arrays are NULL/unset before the first
  // hit; allocated lazily at finalize.
  const char **method_ic_class;
  size_t      *method_ic_class_len;
  TcFunction **method_ic_fn;
  // Cached `self` slot index. find_local_slot(chunk, "self", 4) showed up
  // in profile as ~5% of stage 1 — every method dispatch (CALL with a
  // TC_VAL_OBJECT in the self slot) and every IVAR_GET/SET ran the linear
  // scan. The slot is fixed once the chunk finishes compiling; cache the
  // first lookup so subsequent calls collapse to a load. -2 = "not yet
  // computed", -1 = "no self in this chunk".
  int self_slot_cache;
  // Per-name_id cache for AstNode (W_PACKED_NODE) method dispatch.
  // Every `node.method` used to malloc "Tungsten:AST:Node#"+name and
  // linear-scan the ~1,400-entry function table — and a method_missing-
  // bound `node.field` access was a guaranteed full-miss scan, ~20% of
  // stage-1 self time after the slab-AST migration. Resolution depends
  // only on the chunk const, and the function table is frozen by VM-run
  // time (same assumption method_ic_* and fn_for_const make), so cache
  // per name_id. state: 0 = unknown, 1 = fn (cache holds it),
  // 2 = miss (dispatch via method_missing). Allocated lazily on the
  // first AstNode dispatch.
  TcFunction **astnode_fn_cache;
  uint8_t *astnode_fn_state;
  // Class names registered with class_role == "slab". The .new dispatch
  // on these classes skips the auto-allocated TcRuntimeObject and
  // instead calls the body as a static fn, returning whatever the body
  // produces (typically a W_PACKED_NODE from slab_alloc_init). Stored
  // as interned bytes pointers so the .new dispatch path can compare
  // via ptr equality after interning the receiver name.
  const char **slab_class_names;
  size_t slab_class_count;
  size_t slab_class_cap;
} TcChunk;

typedef struct {
  const TcSource *source;
  const TcTokens *tokens;
  size_t pos;
  TcChunk *chunk;
} TcParser;

void tc_error_set(TcError *err, const char *fmt, ...);
void tc_error_free(TcError *err);

// Returns a canonical pointer for the given byte sequence. Two calls
// with equal content share the same returned pointer for the life of
// the process. Used for TC_AST_SYMBOL and TC_VAL_SYMBOL bytes so the
// runtime sym==sym path is a 1-cycle pointer compare.
const char *tc_intern(const char *bytes, size_t len);
unsigned char *tc_read_file(const char *path, size_t *len_out, TcError *err);
unsigned char *tc_load_lex64_table(const char *path, size_t *len_out, TcError *err);

int tc_source_build(TcSource *source, unsigned char *bytes, size_t len, const unsigned char *flags,
                    size_t flags_len, TcError *err);
void tc_source_free(TcSource *source);

int tc_lex_source(const TcSource *source, TcTokens *tokens, TcError *err);
void tc_tokens_free(TcTokens *tokens);
int tc_token_type(WValue token);
uint32_t tc_token_offset(WValue token);
uint32_t tc_token_length(WValue token);
int tc_token_text_eq(const TcSource *source, WValue token, const char *text);
int tc_token_text_copy(const TcSource *source, WValue token, char **out, size_t *len_out, TcError *err);
void tc_dump_tokens(const TcSource *source, const TcTokens *tokens);

const char *tc_kind_name(TcKind kind);
int tc_syntax_tokens_build(const TcSource *source, const TcTokens *tokens, TcSyntaxTokens *out, TcError *err);
void tc_syntax_tokens_free(TcSyntaxTokens *tokens);
void tc_dump_syntax_tokens(const TcSource *source, const TcSyntaxTokens *tokens);
int tc_parse_check(const TcSource *source, const TcSyntaxTokens *tokens, TcError *err);

TcAstValue tc_ast_nil(void);
TcAstValue tc_ast_bool(int value);
TcAstValue tc_ast_int(int64_t value);
TcAstValue tc_ast_string_copy(const char *bytes, size_t len, TcError *err);
TcAstValue tc_ast_symbol_copy(const char *bytes, size_t len, TcError *err);
TcAstValue tc_ast_array_new(TcError *err);
TcAstValue tc_ast_hash_new(TcError *err);
TcAstValue tc_ast_clone(TcAstValue value, TcError *err);
int tc_ast_array_push(TcAstValue array, TcAstValue value, TcError *err);
int tc_ast_hash_set(TcAstValue hash, const char *key, TcAstValue value, TcError *err);
void tc_ast_free(TcAstValue value);
void tc_ast_print(TcAstValue value, FILE *out);
// `flags` and `flags_len` are the same lex64 table used by the outer
// tc_source_build/tc_lex_source pipeline. They're forwarded into the
// parser so that string-interpolation handling can lex+parse `[expr]`
// sub-expressions on the fly. Callers that don't care about interp
// splitting (or don't have the table at hand) may pass NULL/0 — strings
// then stay as plain TC_AST_STRING regardless of `[…]` content.
int tc_parse_bootstrap_ast(const TcSource *source, const TcSyntaxTokens *tokens, TcAstValue *out,
                           TcAstStats *stats, const unsigned char *flags, size_t flags_len,
                           TcError *err);

void tc_chunk_init(TcChunk *chunk);
void tc_chunk_free(TcChunk *chunk);
int  tc_chunk_register_slab_class(TcChunk *chunk, const char *name, size_t name_len, TcError *err);
int  tc_chunk_is_slab_class(const TcChunk *chunk, const char *name, size_t name_len);
int tc_chunk_add_const(TcChunk *chunk, TcValue value, TcError *err);
int tc_chunk_local(TcChunk *chunk, const char *name, size_t len, TcError *err);
int tc_chunk_add_function(TcChunk *chunk, const char *name, size_t name_len, uint32_t entry,
                          const uint32_t *param_slots, uint32_t arity, TcError *err);
TcFunction *tc_chunk_find_function(const TcChunk *chunk, const char *name, size_t name_len);
TcFunction *tc_chunk_find_method(const TcChunk *chunk,
                                 const char *class_name, size_t class_len,
                                 const char *method_name, size_t method_len);
void tc_chunk_compute_touched(TcChunk *chunk);
void tc_chunk_peephole(TcChunk *chunk);
int tc_chunk_alloc_case_table(TcChunk *chunk, uint32_t count, TcError *err);
int tc_emit_op(TcChunk *chunk, uint8_t op, TcError *err);
int tc_emit_u32(TcChunk *chunk, uint32_t value, TcError *err);
int tc_emit_op_u32(TcChunk *chunk, uint8_t op, uint32_t value, TcError *err);
void tc_dump_bytecode(const TcChunk *chunk);

int tc_compile(const TcSource *source, const TcTokens *tokens, TcChunk *chunk, TcError *err);
int tc_compile_ast(TcAstValue ast, TcChunk *chunk, TcError *err);
int tc_compile_ast_definitions(TcAstValue ast, TcChunk *chunk, TcError *err);
int tc_compile_ast_initializers(TcAstValue ast, TcChunk *chunk, TcError *err);
int tc_vm_run(const TcChunk *chunk, TcValue *result, TcError *err);
int tc_vm_run_args(const TcChunk *chunk, int argc, char **argv, TcValue *result, TcError *err);
void tc_value_print(TcValue value, FILE *out);

#endif
