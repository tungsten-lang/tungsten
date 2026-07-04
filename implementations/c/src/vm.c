#include "tc.h"
#include "w_lexchar_cache.c"

#include <ctype.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

/* Forward declarations from node_arena.c — the C VM-side slab-AST
 * helpers that ccall_nobox dispatches to in vm_call_body.inc. */
WValue w_node_alloc(int64_t kind, int64_t sc);
WValue w_node_field_load(WValue wnode, int64_t ivar_offset);
void   w_node_field_store(WValue wnode, int64_t ivar_offset, WValue value);

/* PR #3: sparse-store helpers (defined in runtime.c, linked into the
 * C VM). Mirror the prototype shape ccall_nobox dispatch in
 * vm_call_body.inc needs. */
WValue w_ast_sparse_set(WValue node, int64_t sym, WValue value);
WValue w_ast_sparse_get(WValue node, int64_t sym);
WValue w_ast_sparse_copy(WValue src_node, WValue dst_node);

/* AST string-intern table (inline interned leaf kinds) — node_arena.c.
 * Bytes-based twins of runtime.c's w_ast_intern_node/w_ast_intern_str_of;
 * the ccall_nobox arm extracts string bytes itself. */
uint64_t w_ast_intern_node_bytes(int64_t kind, const char *bytes, size_t len,
                                 uint64_t strval);
uint64_t w_ast_intern_value_of(uint64_t node);

typedef struct {
  const TcChunk *chunk;
  size_t ip;
  TcValue stack[1024];
  size_t sp;
  TcValue *locals;
  TcRuntimeArray *argv;
  // saved_locals_pool: contiguous buffer of 2048 * local_count slots.
  // Slice at depth*local_count is the saved snapshot for that frame.
  // Replaces per-call malloc/free of the save buffer (was ~30% of CPU
  // in profile from libsystem_malloc). Bumped from 256 once we let the
  // C VM run the actual recursive-descent compiler/lib/parser.w —
  // parsing the full compiler/tungsten.w nests deeper than 256.
  TcValue *saved_locals_pool;
  // Per-frame state packed AoS so a single call writes one cache line
  // instead of touching six parallel arrays. 32 bytes per frame; 2048
  // frames = 64KB total.
  struct {
    size_t return_ip;
    const TcFunction *function;
    TcValue return_override;
    uint8_t saved_locals_active;
    uint8_t has_return_override;
    uint8_t discard_return;
    uint8_t _pad[5];
  } frames[2048];
  size_t call_depth;
} TcVm;

static void runtime_array_free(TcRuntimeArray *array);
static TcRuntimeArray *runtime_array_new(size_t count, TcError *err);
static const char *value_type_name(TcValue value);

// GC removed. The bootstrap is short-running (one process, exits in seconds);
// previously the C VM kept linked lists of all live arrays/hashes/objects/
// ints/strings + mark/sweep + heap_bytes accounting + a per-1024-op trigger
// in the dispatch loop. With GC off (the default), all that machinery was
// pure overhead. Allocations now go straight to calloc and live until
// process exit.
//
// Global class-variable storage. Lazy-allocated on first CVAR_SET. See
// TC_OP_CVAR_* in tc.h for the per-class scoping caveat.
static TcRuntimeHash *cvar_table = NULL;

// Pre-interned builtin method names. The L_CALL handler matches on
// these via pointer equality against the call's TC_VAL_SYMBOL name —
// every call name routes through the same global intern table at
// emit-time, so a hit means "this is the canonical pointer for
// `size`/`[]`/whatever". One load + one compare replaces the
// `name_len == N && memcmp(...)` chain.
//
// All NULL until first vm_run, then populated once.
#define BUILTIN_NAMES \
  X(BRACKETS,       "[]")            \
  X(BRACKETS_SET,   "[]=")           \
  X(LSHIFT,         "<<")            \
  X(RSHIFT,         ">>")            \
  X(SIZE,           "size")          \
  X(TYPE,           "type")          \
  X(PUSH,           "push")          \
  X(POP,            "pop")           \
  X(SHIFT,          "shift")         \
  X(TO_S,           "to_s")          \
  X(TO_I,           "to_i")          \
  X(TO_SYM,         "to_sym")        \
  X(ORD,            "ord")           \
  X(CHR,            "chr")           \
  X(CHARS,          "chars")         \
  X(BYTES,          "bytes")         \
  X(SLICE,          "slice")         \
  X(STRIP,          "strip")         \
  X(DOWNCASE,       "downcase")      \
  X(UPCASE,         "upcase")        \
  X(REPLACE,        "replace")       \
  X(GSUB,           "gsub")          \
  X(SPLIT,          "split")         \
  X(JOIN,           "join")          \
  X(INDEX,          "index")         \
  X(RINDEX,         "rindex")        \
  X(STARTS_WITH_Q,  "starts_with?")  \
  X(ENDS_WITH_Q,    "ends_with?")    \
  X(INCLUDE_Q,      "include?")      \
  X(EMPTY_Q,        "empty?")        \
  X(HAS_KEY_Q,      "has_key?")      \
  X(KEY_Q,          "key?")          \
  X(KEYS,           "keys")          \
  X(FIRST,          "first")         \
  X(LAST,           "last")          \
  X(SORT,           "sort")          \
  X(LCHS,           "lchs")          \
  X(APPEND,         "append")        \
  X(CONCAT,         "concat")        \
  X(ARGV,           "argv")          \
  X(EXIT,           "exit")          \
  X(ENV,            "env")           \
  X(CLOCK,          "clock")         \
  X(FILE_Q,         "file?")         \
  X(SYSTEM,         "system")        \
  X(CAPTURE,        "capture")       \
  X(READ_FILE,      "read_file")     \
  X(WRITE_FILE,     "write_file")    \
  X(STRING_BUFFER,  "StringBuffer")  \
  X(RUNTIME_IDENTITY, "runtime_identity") \
  X(WYHASH64_HEX_STRING, "wyhash64_hex_string") \
  X(LOAD_PROGRAM_AST, "load_program_ast")            \
  X(RAISE,          "raise")

#define X(c_name, str) static const char *NAME_##c_name = NULL;
BUILTIN_NAMES
#undef X

static int builtin_names_ready = 0;
static int intern_builtin_names(TcError *err) {
#define X(c_name, str)                                      \
  do {                                                      \
    NAME_##c_name = tc_intern(str, sizeof(str) - 1);        \
    if (!NAME_##c_name) {                                   \
      tc_error_set(err, "builtin name intern failed: " str); \
      return 0;                                             \
    }                                                       \
  } while (0);
  BUILTIN_NAMES
#undef X
  builtin_names_ready = 1;
  return 1;
}
static int value_text_eq(TcValue value, const char *text) {
  size_t len = strlen(text);
  return (tc_kind(value) == TC_VAL_STRING || tc_kind(value) == TC_VAL_SYMBOL) &&
         tc_str_len(value) == len &&
         memcmp(tc_str_bytes_only(value), text, len) == 0;
}

static int hash_has_key_text(TcRuntimeHash *hash, const char *text) {
  for (size_t i = 0; i < hash->cap; i++) {
    TcValue k = hash->keys[i];
    if (k == TC_HASH_EMPTY || k == TC_HASH_TOMBSTONE) continue;
    if (value_text_eq(k, text)) return 1;
  }
  return 0;
}

static int object_is_class(TcRuntimeObject *object, const char *class_name, size_t class_name_len) {
  // class_name on the object is always an interned bytes pointer
  // (see runtime_object_new), so callers passing the matching interned
  // bytes get a single ptr-equality test. Fall back to memcmp for the
  // few sites that pass string literals like "StringBuffer" — the
  // string-literal pointer isn't interned.
  if (!object || object->class_name_len != class_name_len) return 0;
  if (object->class_name == class_name) return 1;
  return memcmp(object->class_name, class_name, class_name_len) == 0;
}

static char *heap_string_alloc(size_t len, TcError *err) {
  return tc_heap_string_alloc(len, 0, err);
}

char *tc_heap_string_alloc(size_t len, int interned, TcError *err) {
  size_t size = sizeof(TcHeapString) + len + 1;
  TcHeapString *string = (TcHeapString *)malloc(size);
  if (!string) {
    tc_error_set(err, "string allocation failed");
    return NULL;
  }
  string->len = len;
  string->cached_hash = 0;
  string->interned = interned ? 1 : 0;
  string->bytes[len] = '\0';
  return string->bytes;
}

TcHeapString *tc_heap_string_header(const char *bytes) {
  return (TcHeapString *)(void *)((char *)bytes - offsetof(TcHeapString, bytes));
}

// No-GC mode: free transients (not interned, never freed); free everything
// else opportunistically when callers explicitly release.
void tc_heap_string_release(const char *bytes) {
  if (!bytes) return;
  TcHeapString *string = tc_heap_string_header(bytes);
  if (string->interned) return;
  free(string);
}

static inline uint32_t read_u32_at(const uint8_t *p) {
  // Unaligned 32-bit read. clang/gcc lower this to a single ldr/movl on
  // arm64/x86_64 — vs the 4-ldrb sequence the byte-OR pattern produced
  // even at -O3 (chunk->code is byte-aligned, so the compiler can't
  // coalesce without the explicit memcpy).
  uint32_t v;
  __builtin_memcpy(&v, p, sizeof(v));
  return v;
}

static uint32_t read_u32(TcVm *vm) {
  uint32_t value = read_u32_at(&vm->chunk->code[vm->ip]);
  vm->ip += 4;
  return value;
}

static int push(TcVm *vm, TcValue value, TcError *err) {
  if (vm->sp >= sizeof(vm->stack) / sizeof(vm->stack[0])) {
    tc_error_set(err, "VM stack overflow");
    return 0;
  }
  vm->stack[vm->sp++] = value;
  return 1;
}

static TcValue pop(TcVm *vm) {
  if (vm->sp == 0) return tc_box_nil();
  return vm->stack[--vm->sp];
}

// Out-of-line so tc_box_int can spill to a TcHeapInt when the value
// doesn't fit in W_TAG_INT's 48-bit signed payload. The compiler's
// runtime_types.w defines NaN-boxing tag constants that exceed this
// range (w_tag_int = 0xFFFA000000000000 etc.); without the spill they
// silently truncate to 0 in w_box_int and the lowering's `v |= w_tag_*`
// produces unboxed payloads that segfault at runtime.
TcValue tc_box_int(int64_t value) {
  if (value >= W_INT48_MIN && value <= W_INT48_MAX) return w_box_int(value);
  TcHeapInt *box = (TcHeapInt *)calloc(1, sizeof(TcHeapInt));
  if (!box) return W_NIL;
  box->value = value;
  return w_box_ptr(box, TC_TAG_HEAP_INT);
}

static TcValue int_value(int64_t value) {
  return tc_box_int(value);
}

// Both inline (W_TAG_INT) and heap-boxed (TC_TAG_HEAP_INT) ints answer
// "yes" to value_is_int — consumers don't care which encoding holds it.
// The accessor in tc.h reads the right one.
static inline int value_is_int(TcValue value) {
  if (w_is_int(value)) return 1;
  return (value & W_TAG_MASK) == 0 && (value & 0xFU) == TC_TAG_HEAP_INT;
}
static inline int64_t value_as_int(TcValue value) { return tc_as_int(value); }

static const char *current_function_name(const TcVm *vm, size_t ip, size_t *len_out) {
  const TcFunction *best = NULL;
  for (size_t i = 0; i < vm->chunk->function_count; i++) {
    const TcFunction *fn = &vm->chunk->functions[i];
    if (fn->entry <= ip && (!best || fn->entry >= best->entry)) best = fn;
  }
  if (!best) {
    *len_out = 5;
    return "<top>";
  }
  *len_out = best->name_len;
  return best->name;
}

static const char *frame_function_name(const TcVm *vm, size_t back, size_t *len_out) {
  if (vm->call_depth <= back) {
    *len_out = 5;
    return "<top>";
  }
  const TcFunction *fn = vm->frames[vm->call_depth - 1 - back].function;
  if (!fn) {
    *len_out = 5;
    return "<top>";
  }
  *len_out = fn->name_len;
  return fn->name;
}

static int falsey(TcValue value) {
  if (tc_kind(value) == TC_VAL_NIL) return 1;
  return tc_kind(value) == TC_VAL_WVALUE && (tc_as_wvalue(value) == W_NIL || tc_as_wvalue(value) == W_FALSE);
}

static int value_equal(TcValue a, TcValue b) {
  // Bit-exact early out: covers nil/bool, integers in W_TAG_INT range,
  // and — crucially for hash probes — interned symbols whose canonical
  // bytes pointer makes the WValue itself identical when the symbols are
  // equal. Skips the per-kind switch + memcmp on the common probe-hit case.
  if (a == b) return 1;
  if (tc_kind(a) != tc_kind(b)) {
    // Post-flip the only mixed-kind equality that matters is string<->symbol
    // (both stringy by tag, distinguished by the sym bit). The pre-flip
    // TC_VAL_NIL/TC_VAL_WVALUE cross-checks were dead code under the new
    // tag dispatch; same for value_is_int(a) && value_is_int(b) (both ints
    // would route to the same kind).
    if ((tc_kind(a) == TC_VAL_STRING || tc_kind(a) == TC_VAL_SYMBOL) &&
        (tc_kind(b) == TC_VAL_STRING || tc_kind(b) == TC_VAL_SYMBOL)) {
      if (tc_str_bytes_only(a) == tc_str_bytes_only(b) && tc_str_len(a) == tc_str_len(b)) return 1;
      return tc_str_len(a) == tc_str_len(b) && memcmp(tc_str_bytes_only(a), tc_str_bytes_only(b), tc_str_len(a)) == 0;
    }
    return 0;
  }
  switch (tc_kind(a)) {
    case TC_VAL_NIL:
      return 1;
    case TC_VAL_INT:
      return tc_as_int(a) == tc_as_int(b);
    case TC_VAL_WVALUE:
      return tc_as_wvalue(a) == tc_as_wvalue(b);
    case TC_VAL_STRING:
    case TC_VAL_SYMBOL:
      if (tc_str_bytes_only(a) == tc_str_bytes_only(b) && tc_str_len(a) == tc_str_len(b)) return 1;
      return tc_str_len(a) == tc_str_len(b) && memcmp(tc_str_bytes_only(a), tc_str_bytes_only(b), tc_str_len(a)) == 0;
    case TC_VAL_ARRAY:
      return tc_as_array(a) == tc_as_array(b);
    case TC_VAL_HASH:
      return tc_as_hash(a) == tc_as_hash(b);
    case TC_VAL_OBJECT:
      return tc_as_object(a) == tc_as_object(b);
    case TC_VAL_AST:
      if (tc_as_ast_ptr(&a)->kind != tc_as_ast_ptr(&b)->kind) return 0;
      switch (tc_as_ast_ptr(&a)->kind) {
        case TC_AST_NIL:
          return 1;
        case TC_AST_BOOL:
          return tc_as_ast_ptr(&a)->as.boolean == tc_as_ast_ptr(&b)->as.boolean;
        case TC_AST_INT:
          return tc_as_ast_ptr(&a)->as.integer == tc_as_ast_ptr(&b)->as.integer;
        case TC_AST_STRING:
        case TC_AST_SYMBOL:
          if (tc_as_ast_ptr(&a)->as.string.bytes == tc_as_ast_ptr(&b)->as.string.bytes &&
              tc_as_ast_ptr(&a)->as.string.len == tc_as_ast_ptr(&b)->as.string.len) return 1;
          return tc_as_ast_ptr(&a)->as.string.len == tc_as_ast_ptr(&b)->as.string.len &&
                 memcmp(tc_as_ast_ptr(&a)->as.string.bytes, tc_as_ast_ptr(&b)->as.string.bytes, tc_as_ast_ptr(&a)->as.string.len) == 0;
        case TC_AST_ARRAY:
          return tc_as_ast_ptr(&a)->as.array == tc_as_ast_ptr(&b)->as.array;
        case TC_AST_HASH:
          return tc_as_ast_ptr(&a)->as.hash == tc_as_ast_ptr(&b)->as.hash;
      }
      return 0;
  }
  return 0;
}

static int value_text_compare(TcValue a, TcValue b, int *cmp_out) {
  if (!((tc_kind(a) == TC_VAL_STRING || tc_kind(a) == TC_VAL_SYMBOL) &&
        (tc_kind(b) == TC_VAL_STRING || tc_kind(b) == TC_VAL_SYMBOL))) {
    return 0;
  }
  size_t min = tc_str_len(a) < tc_str_len(b) ? tc_str_len(a) : tc_str_len(b);
  int cmp = min > 0 ? memcmp(tc_str_bytes_only(a), tc_str_bytes_only(b), min) : 0;
  if (cmp == 0) {
    if (tc_str_len(a) < tc_str_len(b)) cmp = -1;
    else if (tc_str_len(a) > tc_str_len(b)) cmp = 1;
  }
  *cmp_out = cmp;
  return 1;
}

static int make_string_value(const char *bytes, size_t len, TcValue *out, TcError *err) {
  char *copy = heap_string_alloc(len, err);
  if (!copy) return 0;
  if (len > 0) memcpy(copy, bytes, len);
  *out = tc_box_string_bytes(copy, len, 1);
  return 1;
}

static uint64_t tc_wy_read_u32(const unsigned char *bytes, size_t offset) {
  return ((uint64_t)bytes[offset]) |
         ((uint64_t)bytes[offset + 1] << 8) |
         ((uint64_t)bytes[offset + 2] << 16) |
         ((uint64_t)bytes[offset + 3] << 24);
}

static uint64_t tc_wy_read_u64(const unsigned char *bytes, size_t offset) {
  uint64_t value = 0;
  for (size_t i = 0; i < 8; i++) value |= (uint64_t)bytes[offset + i] << (i * 8);
  return value;
}

static uint64_t tc_wy_mix(uint64_t a, uint64_t b) {
  __uint128_t product = (__uint128_t)a * (__uint128_t)b;
  return (uint64_t)product ^ (uint64_t)(product >> 64);
}

static uint64_t tc_wyhash64_bytes(const unsigned char *bytes, size_t len) {
  const uint64_t s1 = 0xe7037ed1a0b428dbULL;
  const uint64_t s2 = 0x8ebc6af09c88c6e3ULL;
  const uint64_t s3 = 0x589965cc75374cc3ULL;
  uint64_t seed = 0x1234567890abcdefULL;
  uint64_t a = 0;
  uint64_t b = 0;

  if (len <= 16) {
    if (len >= 4) {
      size_t head_offset = (len >> 3) << 2;
      size_t tail_offset = len - 4;
      size_t tail_head_offset = len - 4 - head_offset;
      a = (tc_wy_read_u32(bytes, 0) << 32) | tc_wy_read_u32(bytes, head_offset);
      b = (tc_wy_read_u32(bytes, tail_offset) << 32) | tc_wy_read_u32(bytes, tail_head_offset);
    } else if (len > 0) {
      a = ((uint64_t)bytes[0] << 16) |
          ((uint64_t)bytes[len >> 1] << 8) |
          (uint64_t)bytes[len - 1];
    }
  } else {
    size_t i = len;
    size_t offset = 0;
    if (i > 48) {
      uint64_t s0v = seed;
      uint64_t s1v = seed;
      uint64_t s2v = seed;
      while (i > 48) {
        uint64_t d0 = tc_wy_read_u64(bytes, offset);
        uint64_t d1 = tc_wy_read_u64(bytes, offset + 8);
        uint64_t d2 = tc_wy_read_u64(bytes, offset + 16);
        uint64_t d3 = tc_wy_read_u64(bytes, offset + 24);
        uint64_t d4 = tc_wy_read_u64(bytes, offset + 32);
        uint64_t d5 = tc_wy_read_u64(bytes, offset + 40);
        s0v = tc_wy_mix(d0 ^ s1, d1 ^ s0v);
        s1v = tc_wy_mix(d2 ^ s2, d3 ^ s1v);
        s2v = tc_wy_mix(d4 ^ s3, d5 ^ s2v);
        offset += 48;
        i -= 48;
      }
      seed = s0v ^ s1v ^ s2v;
    }
    while (i > 16) {
      uint64_t d0 = tc_wy_read_u64(bytes, offset);
      uint64_t d1 = tc_wy_read_u64(bytes, offset + 8);
      seed = tc_wy_mix(d0 ^ s1, d1 ^ seed);
      offset += 16;
      i -= 16;
    }
    a = tc_wy_read_u64(bytes, offset + i - 16);
    b = tc_wy_read_u64(bytes, offset + i - 8);
  }

  return tc_wy_mix(s1 ^ (uint64_t)len, tc_wy_mix(a ^ s1, b ^ seed));
}

// Per-file line/col lookup tables for FileOffset-mode Location
// reconstruction — the C VM's own copy of runtime.c's w_loc_register_file
// / w_loc_line_for_offset / w_loc_col_for_offset. Not shared with the
// compiled-binary runtime (this is a separate standalone process, so
// there's nothing to share across the process boundary anyway); each
// engine just needs its own consistent registry for its own compile run.
// TcValue is WValue (tc.h), so the array/string access below matches
// runtime.c's shape exactly — see that file's comment on why a
// Tungsten-level global was unreliable for this state in the first place.
typedef struct {
  char *path;
  int32_t *line_at;
  int32_t *col_at;
  uint32_t len;
} TcLocFileTable;

static TcLocFileTable *g_tc_loc_files = NULL;
static uint32_t g_tc_loc_file_count = 0;
static uint32_t g_tc_loc_file_cap = 0;

static int tc_loc_register_file(TcValue path, TcValue line_at_arr, TcValue col_at_arr) {
  char buf[6];
  size_t len;
  const char *s = tc_str_bytes(path, buf, &len);
  for (uint32_t i = 0; i < g_tc_loc_file_count; i++) {
    size_t plen = strlen(g_tc_loc_files[i].path);
    if (plen == len && memcmp(g_tc_loc_files[i].path, s, len) == 0) {
      return (int)(i + 1);
    }
  }
  if (g_tc_loc_file_count == g_tc_loc_file_cap) {
    g_tc_loc_file_cap = g_tc_loc_file_cap == 0 ? 8 : g_tc_loc_file_cap * 2;
    g_tc_loc_files = realloc(g_tc_loc_files, g_tc_loc_file_cap * sizeof(TcLocFileTable));
  }
  TcRuntimeArray *line_a = tc_as_array(line_at_arr);
  TcRuntimeArray *col_a = tc_as_array(col_at_arr);
  uint32_t n = (uint32_t)line_a->size;
  int32_t *line_buf = malloc(sizeof(int32_t) * (n > 0 ? n : 1));
  int32_t *col_buf = malloc(sizeof(int32_t) * (n > 0 ? n : 1));
  for (uint32_t i = 0; i < n; i++) {
    line_buf[i] = (int32_t)tc_as_int(line_a->slots[line_a->start + i]);
    col_buf[i] = (int32_t)tc_as_int(col_a->slots[col_a->start + i]);
  }
  char *path_copy = malloc(len + 1);
  memcpy(path_copy, s, len);
  path_copy[len] = '\0';
  g_tc_loc_files[g_tc_loc_file_count].path = path_copy;
  g_tc_loc_files[g_tc_loc_file_count].line_at = line_buf;
  g_tc_loc_files[g_tc_loc_file_count].col_at = col_buf;
  g_tc_loc_files[g_tc_loc_file_count].len = n;
  g_tc_loc_file_count++;
  return (int)g_tc_loc_file_count;
}

static int tc_loc_line_for_offset(int file_id, int offset) {
  if (file_id < 1 || (uint32_t)file_id > g_tc_loc_file_count) return -1;
  TcLocFileTable *t = &g_tc_loc_files[file_id - 1];
  if (offset < 0 || (uint32_t)offset >= t->len) return -1;
  return t->line_at[offset];
}

static int tc_loc_col_for_offset(int file_id, int offset) {
  if (file_id < 1 || (uint32_t)file_id > g_tc_loc_file_count) return -1;
  TcLocFileTable *t = &g_tc_loc_files[file_id - 1];
  if (offset < 0 || (uint32_t)offset >= t->len) return -1;
  return t->col_at[offset];
}

static int wyhash64_hex_string_value(TcValue text, TcValue *out, TcError *err) {
  if (tc_kind(text) != TC_VAL_STRING && tc_kind(text) != TC_VAL_SYMBOL) {
    tc_error_set(err, "wyhash64_hex_string expects string");
    return 0;
  }
  uint64_t hash = tc_wyhash64_bytes((const unsigned char *)tc_str_bytes_only(text), tc_str_len(text));
  char hex[17];
  static const char digits[] = "0123456789abcdef";
  for (int i = 15; i >= 0; i--) {
    hex[i] = digits[hash & 0xFULL];
    hash >>= 4;
  }
  hex[16] = '\0';
  return make_string_value(hex, 16, out, err);
}

static size_t utf8_sequence_len(const char *bytes, size_t len, size_t at) {
  if (at >= len) return 0;
  unsigned char b = (unsigned char)bytes[at];
  if (b < 0x80) return 1;
  if ((b & 0xE0) == 0xC0 && at + 1 < len) return 2;
  if ((b & 0xF0) == 0xE0 && at + 2 < len) return 3;
  if ((b & 0xF8) == 0xF0 && at + 3 < len) return 4;
  return 1;
}

static int64_t utf8_first_codepoint(const char *bytes, size_t len) {
  if (len == 0) return 0;
  unsigned char b0 = (unsigned char)bytes[0];
  if (b0 < 0x80) return b0;
  if ((b0 & 0xE0) == 0xC0 && len >= 2) {
    return ((int64_t)(b0 & 0x1F) << 6) | ((int64_t)((unsigned char)bytes[1] & 0x3F));
  }
  if ((b0 & 0xF0) == 0xE0 && len >= 3) {
    return ((int64_t)(b0 & 0x0F) << 12) |
           ((int64_t)((unsigned char)bytes[1] & 0x3F) << 6) |
           (int64_t)((unsigned char)bytes[2] & 0x3F);
  }
  if ((b0 & 0xF8) == 0xF0 && len >= 4) {
    return ((int64_t)(b0 & 0x07) << 18) |
           ((int64_t)((unsigned char)bytes[1] & 0x3F) << 12) |
           ((int64_t)((unsigned char)bytes[2] & 0x3F) << 6) |
           (int64_t)((unsigned char)bytes[3] & 0x3F);
  }
  return b0;
}

static int make_codepoint_string_value(int64_t cp, TcValue *out, TcError *err) {
  char buf[5];
  size_t len = 0;
  if (cp < 0x80) {
    buf[0] = (char)cp;
    len = 1;
  } else if (cp < 0x800) {
    buf[0] = (char)(0xC0 | (cp >> 6));
    buf[1] = (char)(0x80 | (cp & 0x3F));
    len = 2;
  } else if (cp < 0x10000) {
    buf[0] = (char)(0xE0 | (cp >> 12));
    buf[1] = (char)(0x80 | ((cp >> 6) & 0x3F));
    buf[2] = (char)(0x80 | (cp & 0x3F));
    len = 3;
  } else {
    buf[0] = (char)(0xF0 | (cp >> 18));
    buf[1] = (char)(0x80 | ((cp >> 12) & 0x3F));
    buf[2] = (char)(0x80 | ((cp >> 6) & 0x3F));
    buf[3] = (char)(0x80 | (cp & 0x3F));
    len = 4;
  }
  return make_string_value(buf, len, out, err);
}

static unsigned char *lex64_flags_cache = NULL;
static size_t lex64_flags_cache_len = 0;

static int ensure_lex64_flags(TcError *err) {
  if (lex64_flags_cache) return 1;
  const char *table_path = getenv("TUNGSTEN_LEX64_TABLE");
  if (!table_path) table_path = "languages/tungsten/tungsten.lex64";
  lex64_flags_cache = tc_load_lex64_table(table_path, &lex64_flags_cache_len, err);
  return lex64_flags_cache != NULL;
}

static int string_lchs_value(TcValue receiver, int use_lang, TcValue *out, TcError *err) {
  if (use_lang && !ensure_lex64_flags(err)) return 0;
  size_t char_count = 0;
  for (size_t i = 0; i < tc_str_len(receiver);) {
    i += utf8_sequence_len(tc_str_bytes_only(receiver), tc_str_len(receiver), i);
    char_count++;
  }

  TcRuntimeArray *array = runtime_array_new(char_count, err);
  if (!array) return 0;

  size_t out_i = 0;
  for (size_t i = 0; i < tc_str_len(receiver);) {
    size_t byte_start = i;
    size_t clen = utf8_sequence_len(tc_str_bytes_only(receiver), tc_str_len(receiver), i);
    uint32_t cp = (uint32_t)utf8_first_codepoint(tc_str_bytes_only(receiver) + byte_start, clen);
    // Match runtime/runtime.c:
    //   .lchs() (no arg):     w_lexchar_cached(cp) | (cp << 18) — preserves
    //                         digit_value (bits 7-10) and other metadata.
    //   .lchs(lang) with arg: w_lexchar_lang() — replaces lower 11 bits with
    //                         the language's flag byte, wiping digit_value.
    uint64_t cached = w_lexchar_cached(cp);
    uint64_t lc = cached | (((uint64_t)cp & 0x1FFFFFULL) << 18);
    if (use_lang) {
      unsigned char flags = cp < lex64_flags_cache_len ? lex64_flags_cache[cp] : 0;
      lc = (lc & ~0x7FFULL) | (uint64_t)flags;
    }
    (void)clen;
    array->slots[out_i++] = int_value((int64_t)lc);
    i += clen;
  }

  *out = tc_box_array(array);
  return 1;
}

static int copy_string_bytes(const char *bytes, size_t len, char **out, size_t *len_out, TcError *err) {
  char *copy = (char *)malloc(len + 1);
  if (!copy) {
    tc_error_set(err, "string conversion allocation failed");
    return 0;
  }
  if (len > 0) memcpy(copy, bytes, len);
  copy[len] = '\0';
  *out = copy;
  *len_out = len;
  return 1;
}

static int value_to_string_copy(TcValue value, char **out, size_t *len_out, TcError *err) {
  if (tc_kind(value) == TC_VAL_STRING || tc_kind(value) == TC_VAL_SYMBOL) {
    return copy_string_bytes(tc_str_bytes_only(value), tc_str_len(value), out, len_out, err);
  }
  if (tc_kind(value) == TC_VAL_NIL || (tc_kind(value) == TC_VAL_WVALUE && tc_as_wvalue(value) == W_NIL)) {
    // Match runtime/runtime.c:w_to_s — nil.to_s() returns "" in the
    // native compiler, not "nil". The C VM previously returned "nil"
    // (more debug-friendly) but that diverged from native and caused
    // the bootstrap's compile to produce different IR under the C VM
    // vs stage 2. Specifically, error-formatter strings like
    //   "expected [foo], got [bar]"
    // where bar can be nil — under the C VM the produced binary's
    // string had "nil" interpolated; native got "". Same divergence
    // surfaces in compiler-internal type-inference when string-
    // concatenated probe values are inserted into hashes keyed by
    // their string form.
    return copy_string_bytes("", 0, out, len_out, err);
  }
  if (tc_kind(value) == TC_VAL_WVALUE && tc_as_wvalue(value) == W_TRUE) {
    return copy_string_bytes("true", 4, out, len_out, err);
  }
  if (tc_kind(value) == TC_VAL_WVALUE && tc_as_wvalue(value) == W_FALSE) {
    return copy_string_bytes("false", 5, out, len_out, err);
  }
  if (value_is_int(value)) {
    char buf[64];
    int len = snprintf(buf, sizeof(buf), "%lld", (long long)value_as_int(value));
    if (len < 0) {
      tc_error_set(err, "integer string conversion failed");
      return 0;
    }
    return copy_string_bytes(buf, (size_t)len, out, len_out, err);
  }
  if (tc_kind(value) == TC_VAL_ARRAY) {
    char buf[64];
    int len = snprintf(buf, sizeof(buf), "[%zu item%s]", tc_as_array(value) ? tc_as_array(value)->size : 0,
                       tc_as_array(value) && tc_as_array(value)->size == 1 ? "" : "s");
    if (len < 0) {
      tc_error_set(err, "array string conversion failed");
      return 0;
    }
    return copy_string_bytes(buf, (size_t)len, out, len_out, err);
  }
  if (tc_kind(value) == TC_VAL_HASH) {
    char buf[64];
    int len = snprintf(buf, sizeof(buf), "{%zu pair%s}", tc_as_hash(value) ? tc_as_hash(value)->count : 0,
                       tc_as_hash(value) && tc_as_hash(value)->count == 1 ? "" : "s");
    if (len < 0) {
      tc_error_set(err, "hash string conversion failed");
      return 0;
    }
    return copy_string_bytes(buf, (size_t)len, out, len_out, err);
  }
  if (tc_kind(value) == TC_VAL_OBJECT) {
    if (!tc_as_object(value)) return copy_string_bytes("#<nil-object>", 13, out, len_out, err);
    if (object_is_class(tc_as_object(value), "StringBuffer", 12)) {
      return copy_string_bytes(tc_as_object(value)->buffer ? tc_as_object(value)->buffer : "",
                               tc_as_object(value)->buffer_len, out, len_out, err);
    }
    size_t len = tc_as_object(value)->class_name_len + 3;
    char *buf = (char *)malloc(len + 1);
    if (!buf) {
      tc_error_set(err, "object string conversion allocation failed");
      return 0;
    }
    memcpy(buf, "#<", 2);
    memcpy(buf + 2, tc_as_object(value)->class_name, tc_as_object(value)->class_name_len);
    buf[len - 1] = '>';
    buf[len] = '\0';
    *out = buf;
    *len_out = len;
    return 1;
  }
  if (tc_kind(value) == TC_VAL_AST) {
    if (tc_as_ast_ptr(&value)->kind == TC_AST_STRING || tc_as_ast_ptr(&value)->kind == TC_AST_SYMBOL) {
      return copy_string_bytes(tc_as_ast_ptr(&value)->as.string.bytes, tc_as_ast_ptr(&value)->as.string.len, out, len_out, err);
    }
    return copy_string_bytes("[ast]", 5, out, len_out, err);
  }
  tc_error_set(err, "unsupported string conversion");
  return 0;
}

static int concat_values(TcValue a, TcValue b, TcValue *out, TcError *err) {
  // Fast path: both operands already carry directly-readable bytes
  // (string, symbol). Skip the two value_to_string_copy temp allocations
  // and write straight into the result buffer.
  TcKind ka = tc_kind(a), kb = tc_kind(b);
  int a_direct = (ka == TC_VAL_STRING || ka == TC_VAL_SYMBOL);
  int b_direct = (kb == TC_VAL_STRING || kb == TC_VAL_SYMBOL);
  if (a_direct && b_direct) {
    size_t la = tc_str_len(a), lb = tc_str_len(b);
    char *joined = heap_string_alloc(la + lb, err);
    if (!joined) return 0;
    if (la > 0) memcpy(joined, tc_str_bytes_only(a), la);
    if (lb > 0) memcpy(joined + la, tc_str_bytes_only(b), lb);
    *out = tc_box_string_bytes(joined, la + lb, 1);
    return 1;
  }
  char *left = NULL;
  char *right = NULL;
  size_t left_len = 0;
  size_t right_len = 0;
  if (!value_to_string_copy(a, &left, &left_len, err) ||
      !value_to_string_copy(b, &right, &right_len, err)) {
    free(left);
    free(right);
    return 0;
  }
  char *joined = heap_string_alloc(left_len + right_len, err);
  if (!joined) {
    free(left);
    free(right);
    return 0;
  }
  memcpy(joined, left, left_len);
  memcpy(joined + left_len, right, right_len);
  free(left);
  free(right);
  *out = tc_box_string_bytes(joined, left_len + right_len, 1);
  return 1;
}

static int string_replace_all(TcValue receiver, TcValue needle, TcValue replacement, TcValue *out, TcError *err) {
  if (tc_kind(receiver) != TC_VAL_STRING || tc_kind(needle) != TC_VAL_STRING || tc_kind(replacement) != TC_VAL_STRING) {
    tc_error_set(err, "replace expects string receiver and arguments");
    return 0;
  }
  if (tc_str_len(needle) == 0) return make_string_value(tc_str_bytes_only(receiver), tc_str_len(receiver), out, err);
  size_t count = 0;
  for (size_t i = 0; i + tc_str_len(needle) <= tc_str_len(receiver);) {
    if (memcmp(tc_str_bytes_only(receiver) + i, tc_str_bytes_only(needle), tc_str_len(needle)) == 0) {
      count++;
      i += tc_str_len(needle);
    } else {
      i++;
    }
  }
  size_t len = tc_str_len(receiver) + count * (tc_str_len(replacement) - tc_str_len(needle));
  char *buf = heap_string_alloc(len, err);
  if (!buf) return 0;
  size_t src = 0;
  size_t dst = 0;
  while (src < tc_str_len(receiver)) {
    if (src + tc_str_len(needle) <= tc_str_len(receiver) && memcmp(tc_str_bytes_only(receiver) + src, tc_str_bytes_only(needle), tc_str_len(needle)) == 0) {
      memcpy(buf + dst, tc_str_bytes_only(replacement), tc_str_len(replacement));
      dst += tc_str_len(replacement);
      src += tc_str_len(needle);
    } else {
      buf[dst++] = tc_str_bytes_only(receiver)[src++];
    }
  }
  *out = tc_box_string_bytes(buf, dst, 1);
  return 1;
}

static int string_index_value(TcValue receiver, TcValue needle, TcValue *out, TcError *err) {
  if (tc_kind(receiver) != TC_VAL_STRING || tc_kind(needle) != TC_VAL_STRING) {
    tc_error_set(err, "index expects string receiver and argument");
    return 0;
  }
  if (tc_str_len(needle) == 0) {
    *out = int_value(0);
    return 1;
  }
  for (size_t i = 0; i + tc_str_len(needle) <= tc_str_len(receiver); i++) {
    if (memcmp(tc_str_bytes_only(receiver) + i, tc_str_bytes_only(needle), tc_str_len(needle)) == 0) {
      *out = int_value((int64_t)i);
      return 1;
    }
  }
  *out = tc_box_nil();
  return 1;
}

static int string_rindex_value(TcValue receiver, TcValue needle, TcValue *out, TcError *err) {
  if (tc_kind(receiver) != TC_VAL_STRING || tc_kind(needle) != TC_VAL_STRING) {
    tc_error_set(err, "rindex expects string receiver and argument");
    return 0;
  }
  if (tc_str_len(needle) == 0) {
    *out = int_value((int64_t)tc_str_len(receiver));
    return 1;
  }
  if (tc_str_len(needle) <= tc_str_len(receiver)) {
    for (size_t i = tc_str_len(receiver) - tc_str_len(needle) + 1; i-- > 0; ) {
      if (memcmp(tc_str_bytes_only(receiver) + i, tc_str_bytes_only(needle), tc_str_len(needle)) == 0) {
        *out = int_value((int64_t)i);
        return 1;
      }
    }
  }
  *out = tc_box_nil();
  return 1;
}

static int string_slice_value(TcValue receiver, TcValue start_value, TcValue len_value, int has_len,
                              TcValue *out, TcError *err) {
  if (tc_kind(receiver) != TC_VAL_STRING || !value_is_int(start_value)) {
    tc_error_set(err, "slice expects string receiver and integer start");
    return 0;
  }
  int64_t start = value_as_int(start_value);
  int64_t len = has_len ? (value_is_int(len_value) ? value_as_int(len_value) : -1) : 1;
  if (start < 0) start += (int64_t)tc_str_len(receiver);
  if (start < 0 || start > (int64_t)tc_str_len(receiver) || len < 0) {
    *out = tc_box_nil();
    return 1;
  }
  if (start + len > (int64_t)tc_str_len(receiver)) len = (int64_t)tc_str_len(receiver) - start;
  return make_string_value(tc_str_bytes_only(receiver) + start, (size_t)len, out, err);
}

static int string_strip_value(TcValue receiver, TcValue *out, TcError *err) {
  if (tc_kind(receiver) != TC_VAL_STRING) {
    tc_error_set(err, "strip expects string receiver");
    return 0;
  }
  size_t start = 0;
  size_t end = tc_str_len(receiver);
  while (start < end && isspace((unsigned char)tc_str_bytes_only(receiver)[start])) start++;
  while (end > start && isspace((unsigned char)tc_str_bytes_only(receiver)[end - 1])) end--;
  return make_string_value(tc_str_bytes_only(receiver) + start, end - start, out, err);
}

static int string_case_value(TcValue receiver, int upper, TcValue *out, TcError *err) {
  if (tc_kind(receiver) != TC_VAL_STRING) {
    tc_error_set(err, "case conversion expects string receiver");
    return 0;
  }
  char *buf = heap_string_alloc(tc_str_len(receiver), err);
  if (!buf) return 0;
  for (size_t i = 0; i < tc_str_len(receiver); i++) {
    unsigned char c = (unsigned char)tc_str_bytes_only(receiver)[i];
    buf[i] = (char)(upper ? toupper(c) : tolower(c));
  }
  *out = tc_box_string_bytes(buf, tc_str_len(receiver), 1);
  return 1;
}

static TcRuntimeArray *runtime_array_new(size_t count, TcError *err) {
  TcRuntimeArray *array = (TcRuntimeArray *)calloc(1, sizeof(TcRuntimeArray));
  if (!array) {
    tc_error_set(err, "array allocation failed");
    return NULL;
  }
  array->ebits = 65;  // polymorphic w64 tier (matches WArray default)
  array->size = (int32_t)count;
  array->cap = (int32_t)count;
  if (count > 0) {
    array->slots = (TcValue *)calloc(count, sizeof(TcValue));
    if (!array->slots) {
      free(array);
      tc_error_set(err, "array item allocation failed");
      return NULL;
    }
  }
  return array;
}

static int runtime_array_ensure_cap(TcRuntimeArray *array, size_t needed, TcError *err) {
  if ((size_t)array->cap >= needed) return 1;
  size_t cap = array->cap ? (size_t)array->cap * 2 : 8;
  while (cap < needed) cap *= 2;
  TcValue *slots = (TcValue *)realloc(array->slots, cap * sizeof(TcValue));
  if (!slots) {
    tc_error_set(err, "array growth failed");
    return 0;
  }
  array->slots = slots;
  array->cap = (int32_t)cap;
  return 1;
}

// Mirror runtime/runtime.c:w_hash_allocate_storage exactly — keys[] gets
// W_UNDEF (empty marker) via a manual loop, values[] gets calloc'd nil.
// Tombstones (W_MEMO_MISS) never appear at allocation time; the probe path
// is the only thing that ever writes one.
static int hash_allocate_storage(TcRuntimeHash *hash, size_t cap, TcError *err) {
  hash->cap = (uint32_t)cap;
  hash->count = 0;
  hash->keys = (WValue *)malloc(cap * sizeof(WValue));
  hash->values = (WValue *)calloc(1, cap * sizeof(WValue));
  if (!hash->keys || !hash->values) {
    free(hash->keys);
    free(hash->values);
    tc_error_set(err, "hash entry allocation failed");
    return 0;
  }
  for (size_t i = 0; i < cap; i++) hash->keys[i] = TC_HASH_EMPTY;
  return 1;
}

// Capacity must be a power of two for `& (cap - 1)`-based slotting.
// Match runtime/runtime.c:w_hash_new — always start at 8 slots; the size
// `hint` is ignored. The compiler creates lots of small AST hashes, so
// matching the initial cap and grow threshold is what keeps slot layouts
// (and iteration order) lined up between C VM and stage 2.
static TcRuntimeHash *runtime_hash_new(size_t hint, TcError *err) {
  TcRuntimeHash *hash = (TcRuntimeHash *)calloc(1, sizeof(TcRuntimeHash));
  if (!hash) {
    tc_error_set(err, "hash allocation failed");
    return NULL;
  }
  // Pre-size so `hint` inserts can complete without grows. Mirrors the
  // load-factor check in hash_set_value (`(count+1)*4 >= cap*3` triggers
  // grow); pre-iterating gets us to the same final cap native would
  // settle at, so slot layout and iteration order match exactly.
  size_t cap = 8;
  while (hint * 4 >= cap * 3) cap *= 2;
  if (!hash_allocate_storage(hash, cap, err)) {
    free(hash);
    return NULL;
  }
  return hash;
}

// Wyhash — bit-exact copy of runtime/runtime.c's w_hash_wyhash.
// Used for string/symbol bytes; with the same input both implementations
// produce the same 64-bit digest, so a key falls in the same slot in both.
static inline uint64_t wymix(uint64_t a, uint64_t b) {
  __uint128_t r = (__uint128_t)a * b;
  return (uint64_t)(r >> 64) ^ (uint64_t)r;
}

static uint64_t wyhash(const uint8_t *data, size_t len) {
  // s0 in the runtime — referenced in the comment, but unused on the
  // short-key fast path so dropped here to avoid -Wunused-variable.
  const uint64_t s1 = 0xe7037ed1a0b428dbULL;
  const uint64_t s2 = 0x8ebc6af09c88c6e3ULL;
  const uint64_t s3 = 0x589965cc75374cc3ULL;
  uint64_t seed = 0x1234567890abcdefULL;
  uint64_t a, b;

  if (len <= 16) {
    if (len >= 4) {
      a = ((uint64_t)(*(const uint32_t *)data) << 32) |
           (uint64_t)(*(const uint32_t *)(data + ((len >> 3) << 2)));
      b = ((uint64_t)(*(const uint32_t *)(data + len - 4)) << 32) |
           (uint64_t)(*(const uint32_t *)(data + len - 4 - ((len >> 3) << 2)));
    } else if (len > 0) {
      a = ((uint64_t)data[0] << 16) | ((uint64_t)data[len >> 1] << 8) | data[len - 1];
      b = 0;
    } else {
      a = b = 0;
    }
  } else {
    size_t i = len;
    if (i > 48) {
      uint64_t s0v = seed, s1v = seed, s2v = seed;
      do {
        uint64_t d0, d1, d2, d3, d4, d5;
        memcpy(&d0, data,      8); memcpy(&d1, data + 8,  8);
        memcpy(&d2, data + 16, 8); memcpy(&d3, data + 24, 8);
        memcpy(&d4, data + 32, 8); memcpy(&d5, data + 40, 8);
        s0v = wymix(d0 ^ s1, d1 ^ s0v);
        s1v = wymix(d2 ^ s2, d3 ^ s1v);
        s2v = wymix(d4 ^ s3, d5 ^ s2v);
        data += 48; i -= 48;
      } while (i > 48);
      seed = s0v ^ s1v ^ s2v;
    }
    while (i > 16) {
      uint64_t d0, d1;
      memcpy(&d0, data, 8); memcpy(&d1, data + 8, 8);
      seed = wymix(d0 ^ s1, d1 ^ seed);
      data += 16; i -= 16;
    }
    uint64_t d0, d1;
    memcpy(&d0, data + i - 16, 8); memcpy(&d1, data + i - 8, 8);
    a = d0; b = d1;
  }
  return wymix(s1 ^ len, wymix(a ^ s1, b ^ seed));
}

static inline uint64_t splitmix64(uint64_t v) {
  v ^= v >> 30; v *= 0xbf58476d1ce4e5b9ULL;
  v ^= v >> 27; v *= 0x94d049bb133111ebULL;
  v ^= v >> 31; return v;
}

// Match runtime/runtime.c:w_hash_value's per-kind dispatch:
//   strings: wyhash of the bytes
//   symbols: wyhash XOR 0x9e3779b97f4a7c15 (golden ratio)
//   everything else: splitmix64 of the bit pattern
// Stays kind-aligned with native so the same key lands in the same slot
// in both implementations — that's what makes hash iteration order match.
static uint64_t hash_value64(TcValue value) {
  switch (tc_kind(value)) {
    case TC_VAL_STRING: {
      const char *bytes = tc_str_bytes_only(value);
      TcHeapString *hs = tc_heap_string_header(bytes);
      uint64_t h = hs->cached_hash;
      if (h) return h;
      h = wyhash((const uint8_t *)bytes, hs->len);
      hs->cached_hash = h;
      return h;
    }
    case TC_VAL_SYMBOL: {
      const char *bytes = tc_str_bytes_only(value);
      TcHeapString *hs = tc_heap_string_header(bytes);
      uint64_t h = hs->cached_hash;
      if (h) return h;
      h = wyhash((const uint8_t *)bytes, hs->len) ^ 0x9e3779b97f4a7c15ULL;
      hs->cached_hash = h;
      return h;
    }
    case TC_VAL_AST:
      switch (tc_as_ast_ptr(&value)->kind) {
        case TC_AST_STRING:
          return wyhash((const uint8_t *)tc_as_ast_ptr(&value)->as.string.bytes,
                        tc_as_ast_ptr(&value)->as.string.len);
        case TC_AST_SYMBOL:
          return wyhash((const uint8_t *)tc_as_ast_ptr(&value)->as.string.bytes,
                        tc_as_ast_ptr(&value)->as.string.len) ^ 0x9e3779b97f4a7c15ULL;
        case TC_AST_INT:
          return splitmix64((uint64_t)tc_as_ast_ptr(&value)->as.integer);
        default:
          return splitmix64((uintptr_t)tc_as_ast_ptr(&value)->as.array);
      }
    case TC_VAL_INT:
      return splitmix64((uint64_t)tc_as_int(value));
    default:
      return splitmix64((uint64_t)value);
  }
}

// Slot-indexed find: probe from the hashed slot, return either the slot
// holding `key` (`*found = 1`) or the first viable insertion slot
// (`*found = 0`). A tombstone counts as viable for insertion but we keep
// scanning for a real hit past it. Same behaviour as runtime.c:w_hash_find_slot.
static size_t hash_find_slot(TcRuntimeHash *hash, TcValue key, int *found) {
  size_t mask = hash->cap - 1;
  size_t idx = (size_t)hash_value64(key) & mask;
  size_t first_tombstone = SIZE_MAX;
  while (1) {
    TcValue k = hash->keys[idx];
    if (k == TC_HASH_EMPTY) {
      *found = 0;
      return first_tombstone == SIZE_MAX ? idx : first_tombstone;
    }
    if (k == TC_HASH_TOMBSTONE) {
      if (first_tombstone == SIZE_MAX) first_tombstone = idx;
    } else if (k == key || value_equal(k, key)) {
      // Bit-equal short-circuit: interned symbols and inline ints compare
      // equal at the WValue bit level, so the hot probe shape (sym key,
      // sym slot) hits without entering the function.
      *found = 1;
      return idx;
    }
    idx = (idx + 1) & mask;
  }
}

// Grow the slot table to `min_cap` (rounded up to a power of two >= 8) and
// re-probe every live entry into a fresh layout. Tombstones are dropped.
// Mirrors runtime/runtime.c:w_hash_grow.
static int hash_grow(TcRuntimeHash *hash, size_t min_cap, TcError *err) {
  size_t cap = 8;
  while (cap < min_cap) cap *= 2;
  WValue *old_keys = hash->keys;
  WValue *old_values = hash->values;
  size_t old_cap = hash->cap;
  if (!hash_allocate_storage(hash, cap, err)) {
    hash->keys = old_keys;
    hash->values = old_values;
    hash->cap = (uint32_t)old_cap;
    return 0;
  }
  size_t mask = cap - 1;
  for (size_t i = 0; i < old_cap; i++) {
    WValue k = old_keys[i];
    if (k == TC_HASH_EMPTY || k == TC_HASH_TOMBSTONE) continue;
    size_t idx = (size_t)hash_value64(k) & mask;
    while (hash->keys[idx] != TC_HASH_EMPTY) idx = (idx + 1) & mask;
    hash->keys[idx] = k;
    hash->values[idx] = old_values[i];
    hash->count++;
  }
  free(old_keys);
  free(old_values);
  return 1;
}


// Forward declaration: ast_to_runtime is defined alongside ast_to_value
// (later in the file) but hash_set_value is the canonical store boundary
// where AST values must be promoted to mutable runtime equivalents.
static int ast_to_runtime(TcAstValue *ast, TcValue *out, TcError *err);

// Promote AST aggregates to runtime aggregates. The C VM stores parser
// output as TC_VAL_AST (arena-allocated, immutable). User code that puts
// AST nodes into a runtime hash/array and later mutates them via `[]=`
// would silently no-op, so convert at the store boundary.
static int promote_ast_value(TcValue *value, TcError *err) {
  if (tc_kind(*value) != TC_VAL_AST) return 1;
  TcAstValue *ast = tc_as_ast_ptr(value);
  if (ast->kind != TC_AST_HASH && ast->kind != TC_AST_ARRAY) return 1;
  return ast_to_runtime(ast, value, err);
}

static int hash_set_value(TcRuntimeHash *hash, TcValue key, TcValue value, TcError *err) {
  if (!promote_ast_value(&value, err)) return 0;
  if (hash->cap == 0 && !hash_grow(hash, 8, err)) return 0;
  // 75% load factor: grow when (count+1)*4 >= cap*3. Bit-exact match to
  // runtime/runtime.c:w_hash_maybe_grow so the same key insertion sequence
  // triggers grows at the same points and ends with the same slot layout.
  if ((hash->count + 1) * 4 >= hash->cap * 3) {
    if (!hash_grow(hash, hash->cap * 2, err)) return 0;
  }
  int found = 0;
  size_t slot = hash_find_slot(hash, key, &found);
  if (!found) hash->count++;
  hash->keys[slot] = key;
  hash->values[slot] = value;
  return 1;
}

static TcValue hash_get_value(TcRuntimeHash *hash, TcValue key) {
  if (!hash || hash->cap == 0) return tc_box_nil();
  int found = 0;
  size_t slot = hash_find_slot(hash, key, &found);
  return found ? hash->values[slot] : tc_box_nil();
}


static int string_split_value(TcValue receiver, TcValue sep, TcValue *out, TcError *err) {
  if (tc_kind(receiver) != TC_VAL_STRING || tc_kind(sep) != TC_VAL_STRING) {
    tc_error_set(err, "split expects string receiver and separator");
    return 0;
  }
  size_t count = 1;
  if (tc_str_len(sep) > 0) {
    for (size_t i = 0; i + tc_str_len(sep) <= tc_str_len(receiver);) {
      if (memcmp(tc_str_bytes_only(receiver) + i, tc_str_bytes_only(sep), tc_str_len(sep)) == 0) {
        count++;
        i += tc_str_len(sep);
      } else {
        i++;
      }
    }
  }
  TcRuntimeArray *array = runtime_array_new(count, err);
  if (!array) return 0;
  size_t part = 0;
  size_t start = 0;
  if (tc_str_len(sep) == 0) {
    for (size_t i = 0; i < tc_str_len(receiver); i++) {
      if (!make_string_value(tc_str_bytes_only(receiver) + i, 1, &array->slots[part++], err)) {
        runtime_array_free(array);
        return 0;
      }
    }
    array->size = part;
  } else {
    for (size_t i = 0; i <= tc_str_len(receiver);) {
      if (i == tc_str_len(receiver) || (i + tc_str_len(sep) <= tc_str_len(receiver) && memcmp(tc_str_bytes_only(receiver) + i, tc_str_bytes_only(sep), tc_str_len(sep)) == 0)) {
        if (!make_string_value(tc_str_bytes_only(receiver) + start, i - start, &array->slots[part++], err)) {
          runtime_array_free(array);
          return 0;
        }
        i += tc_str_len(sep);
        start = i;
      } else {
        i++;
      }
    }
  }
  *out = tc_box_array(array);
  return 1;
}

static int array_join_value(TcValue receiver, TcValue sep, TcValue *out, TcError *err) {
  if (tc_kind(receiver) != TC_VAL_ARRAY || !tc_as_array(receiver) || tc_kind(sep) != TC_VAL_STRING) {
    tc_error_set(err, "join expects array receiver and string separator (got recv=%s sep=%s)",
                 value_type_name(receiver), value_type_name(sep));
    return 0;
  }
  size_t total = 0;
  char **parts = tc_as_array(receiver)->size ? (char **)calloc(tc_as_array(receiver)->size, sizeof(char *)) : NULL;
  size_t *lens = tc_as_array(receiver)->size ? (size_t *)calloc(tc_as_array(receiver)->size, sizeof(size_t)) : NULL;
  if (tc_as_array(receiver)->size && (!parts || !lens)) {
    free(parts);
    free(lens);
    tc_error_set(err, "join allocation failed");
    return 0;
  }
  for (size_t i = 0; i < tc_as_array(receiver)->size; i++) {
    if (!value_to_string_copy(tc_as_array(receiver)->slots[i], &parts[i], &lens[i], err)) {
      for (size_t j = 0; j < i; j++) free(parts[j]);
      free(parts);
      free(lens);
      return 0;
    }
    total += lens[i];
    if (i + 1 < tc_as_array(receiver)->size) total += tc_str_len(sep);
  }
  char *buf = heap_string_alloc(total, err);
  if (!buf) {
    for (size_t i = 0; i < tc_as_array(receiver)->size; i++) free(parts[i]);
    free(parts);
    free(lens);
    return 0;
  }
  size_t at = 0;
  for (size_t i = 0; i < tc_as_array(receiver)->size; i++) {
    memcpy(buf + at, parts[i], lens[i]);
    at += lens[i];
    if (i + 1 < tc_as_array(receiver)->size) {
      memcpy(buf + at, tc_str_bytes_only(sep), tc_str_len(sep));
      at += tc_str_len(sep);
    }
    free(parts[i]);
  }
  free(parts);
  free(lens);
  buf[at] = '\0';
  *out = tc_box_string_bytes(buf, at, 1);
  return 1;
}

static int compare_values_for_sort(const void *a_ptr, const void *b_ptr) {
  TcValue a = *(const TcValue *)a_ptr;
  TcValue b = *(const TcValue *)b_ptr;
  TcValueKind ak = tc_kind(a);
  TcValueKind bk = tc_kind(b);
  if ((ak == TC_VAL_STRING || ak == TC_VAL_SYMBOL) &&
      (bk == TC_VAL_STRING || bk == TC_VAL_SYMBOL)) {
    size_t a_len = tc_str_len(a);
    size_t b_len = tc_str_len(b);
    size_t min = a_len < b_len ? a_len : b_len;
    int cmp = memcmp(tc_str_bytes_only(a), tc_str_bytes_only(b), min);
    if (cmp != 0) return cmp;
    return (a_len > b_len) - (a_len < b_len);
  }
  return (int)ak - (int)bk;
}

static void runtime_array_free(TcRuntimeArray *array) {
  // No-GC: only error-rollback paths hand-free arrays. Once handed to
  // user code the array lives until process exit.
  if (!array) return;
  free(array->slots);
  free(array);
}

static TcRuntimeArray *runtime_argv_new(int argc, char **argv, TcError *err) {
  TcRuntimeArray *array = runtime_array_new((size_t)argc, err);
  if (!array) return NULL;
  for (int i = 0; i < argc; i++) {
    if (!make_string_value(argv[i], strlen(argv[i]), &array->slots[i], err)) {
      runtime_array_free(array);
      return NULL;
    }
  }
  return array;
}

static TcRuntimeObject *runtime_object_new(const char *class_name, size_t class_name_len, TcError *err) {
  TcRuntimeObject *object = (TcRuntimeObject *)calloc(1, sizeof(TcRuntimeObject));
  if (!object) {
    tc_error_set(err, "object allocation failed");
    return NULL;
  }
  // Intern the class name once and store the canonical pointer. Saves
  // a per-object malloc + memcpy and lets object_is_class hit on
  // ptr-equality (interned bytes are unique per content).
  const char *interned = tc_intern(class_name, class_name_len);
  if (!interned) {
    free(object);
    tc_error_set(err, "object class name interning failed");
    return NULL;
  }
  object->class_name = (char *)interned;  // owned by intern table, never freed
  object->class_name_len = class_name_len;
  return object;
}

static TcRuntimeObject *runtime_string_buffer_new(size_t initial_cap, TcError *err) {
  TcRuntimeObject *object = runtime_object_new("StringBuffer", 12, err);
  if (!object) return NULL;
  size_t cap = initial_cap > 0 ? initial_cap : 16;
  object->buffer = (char *)malloc(cap + 1);
  if (!object->buffer) {
    tc_error_set(err, "StringBuffer allocation failed");
    return NULL;
  }
  object->buffer[0] = '\0';
  object->buffer_len = 0;
  object->buffer_cap = cap;

  return object;
}

// Reserve `needed` bytes total in the buffer, growing if necessary. Buffer
// includes a trailing nul, so cap holds (cap + 1) bytes physically.
static int string_buffer_reserve(TcRuntimeObject *object, size_t needed, TcError *err) {
  if (needed <= object->buffer_cap) return 1;
  size_t cap = object->buffer_cap ? object->buffer_cap * 2 : 16;
  while (cap < needed) cap *= 2;
  char *buffer = (char *)realloc(object->buffer, cap + 1);
  if (!buffer) {
    tc_error_set(err, "StringBuffer growth failed");
    return 0;
  }
  object->buffer = buffer;
  object->buffer_cap = cap;
  return 1;
}

// Direct memcpy into the buffer with no temp allocation.
static int string_buffer_append_bytes(TcRuntimeObject *object, const char *bytes, size_t len, TcError *err) {
  if (!string_buffer_reserve(object, object->buffer_len + len, err)) return 0;
  if (len > 0) memcpy(object->buffer + object->buffer_len, bytes, len);
  object->buffer_len += len;
  object->buffer[object->buffer_len] = '\0';
  return 1;
}

static int runtime_string_buffer_append(TcRuntimeObject *object, TcValue value, TcError *err) {
  // Fast paths: avoid the value_to_string_copy malloc for the dominant
  // shapes (string, symbol, int, nil, bool). Roughly 95% of stage 1
  // StringBuffer appends are strings or symbols.
  TcKind k = tc_kind(value);
  if (k == TC_VAL_STRING || k == TC_VAL_SYMBOL) {
    return string_buffer_append_bytes(object, tc_str_bytes_only(value), tc_str_len(value), err);
  }
  if (value_is_int(value)) {
    char buf[32];
    int n = snprintf(buf, sizeof(buf), "%lld", (long long)value_as_int(value));
    if (n < 0) {
      tc_error_set(err, "integer string conversion failed");
      return 0;
    }
    return string_buffer_append_bytes(object, buf, (size_t)n, err);
  }
  if (k == TC_VAL_NIL || (k == TC_VAL_WVALUE && tc_as_wvalue(value) == W_NIL)) {
    return 1;  // nil → "" (matches w_to_s in runtime/runtime.c)
  }
  if (k == TC_VAL_WVALUE && tc_as_wvalue(value) == W_TRUE) {
    return string_buffer_append_bytes(object, "true", 4, err);
  }
  if (k == TC_VAL_WVALUE && tc_as_wvalue(value) == W_FALSE) {
    return string_buffer_append_bytes(object, "false", 5, err);
  }
  // Fall back to the general copy-then-append path for arrays, hashes,
  // objects, AST nodes — uncommon enough that the extra alloc doesn't
  // show up in profile.
  char *text = NULL;
  size_t len = 0;
  if (!value_to_string_copy(value, &text, &len, err)) return 0;
  int ok = string_buffer_append_bytes(object, text, len, err);
  free(text);
  return ok;
}


static const char *value_type_name(TcValue value) {
  switch (tc_kind(value)) {
    case TC_VAL_NIL: return "NilClass";
    case TC_VAL_WVALUE:
      if (tc_as_wvalue(value) == W_TRUE || tc_as_wvalue(value) == W_FALSE) return "Boolean";
      if (w_is_int(tc_as_wvalue(value))) return "Integer";
      return "WValue";
    case TC_VAL_INT: return "Integer";
    case TC_VAL_STRING: return "String";
    case TC_VAL_SYMBOL: return "Symbol";
    case TC_VAL_ARRAY: return "Array";
    case TC_VAL_HASH: return "Hash";
    case TC_VAL_OBJECT: return tc_as_object(value) ? tc_as_object(value)->class_name : "Object";
    case TC_VAL_AST:
      if (tc_as_ast_ptr(&value)->kind == TC_AST_ARRAY) return "Array";
      if (tc_as_ast_ptr(&value)->kind == TC_AST_HASH) return "Hash";
      if (tc_as_ast_ptr(&value)->kind == TC_AST_STRING) return "String";
      if (tc_as_ast_ptr(&value)->kind == TC_AST_SYMBOL) return "Symbol";
      if (tc_as_ast_ptr(&value)->kind == TC_AST_INT) return "Integer";
      if (tc_as_ast_ptr(&value)->kind == TC_AST_BOOL) return "Boolean";
      return "NilClass";
  }
  return "Object";
}

static int ast_hash_lookup(TcAstValue ast, TcValue key, TcValue *out, TcError *err);

static int ast_to_value(TcAstValue ast, TcValue *out, TcError *err) {
  switch (ast.kind) {
    case TC_AST_NIL:
      *out = tc_box_nil();
      return 1;
    case TC_AST_BOOL:
      *out = tc_box_wvalue(ast.as.boolean ? W_TRUE : W_FALSE);
      return 1;
    case TC_AST_INT:
      *out = int_value(ast.as.integer);
      return 1;
    case TC_AST_STRING: {
      // AST strings live in the AST arena as raw bytes (no TcHeapString
      // header). tc_box_string_bytes recovers the header via offsetof,
      // so we have to materialize one — copy the bytes into a fresh
      // tc_heap_string_alloc block before boxing. Symbols go through
      // tc_intern which already does this.
      char *copy = tc_heap_string_alloc(ast.as.string.len, 0, err);
      if (!copy) return 0;
      if (ast.as.string.len > 0) memcpy(copy, ast.as.string.bytes, ast.as.string.len);
      *out = tc_box_string_bytes(copy, ast.as.string.len, 0);
      return 1;
    }
    case TC_AST_SYMBOL: {
      const char *interned = tc_intern(ast.as.string.bytes, ast.as.string.len);
      if (!interned) {
        tc_error_set(err, "ast_to_value: symbol intern failed");
        return 0;
      }
      *out = tc_box_symbol_bytes(interned, ast.as.string.len, 0);
      return 1;
    }
    case TC_AST_ARRAY:
    case TC_AST_HASH:
      *out = tc_box_ast(ast, err);
      return tc_kind(*out) == TC_VAL_AST;
  }
  *out = tc_box_nil();
  return 1;
}

// AST → runtime conversion cache. Keys are TcAstHash * / TcAstArray *
// — the underlying aggregate pointers, which live in the AST arena and
// stay stable across the many TcAstValue struct copies that tc_box_ast
// produces while traversing the tree. Values are the runtime
// hashes/arrays we materialised on first conversion.
//
// Caching by the wrapping TcAstValue * doesn't work: each ast_to_value
// of a hash/array allocates a fresh TcAstValue (tc_box_ast in
// ast_value.c), so the same logical AST node has many pointer aliases.
// The .as.hash / .as.array fields are simple pointer copies on struct
// assignment, so they survive boxing identically.
//
// Concrete failure mode this prevents: in compiler/lib/lowering.w, the
// pre-pass and lower_class_def both store the same AST class_def into
// known_classes. Without caching, each store materialises a fresh
// runtime hash, dropping any `:ivar_offsets` mutation between them.
// Native sees one shared hash; the cache reproduces that identity.
//
// Open-addressing hash table with linear probing. Capacity is a power
// of two, kept at <=50% load. The compile of compiler/tungsten.w
// promotes ~130k unique AST aggregates; a linear-scan cache turned
// every lookup into a 65k-comparison scan and accounted for ~49% of
// stage-1 wallclock. Hashing collapses each lookup to ~1 probe.
typedef struct {
  void *key;       // TcAstHash * or TcAstArray *; NULL = empty slot
  TcValue value;
} AstRuntimeCacheEntry;

static AstRuntimeCacheEntry *g_ast_rt_cache = NULL;
static size_t g_ast_rt_cache_count = 0;
static size_t g_ast_rt_cache_cap = 0;  // always power of two

static inline size_t ast_rt_hash(void *key) {
  // Pointer hash: arena allocations are 16-byte aligned (low 4 bits
  // are zero), so shift before mixing. xorshift-ish mix from
  // splitmix64 — cheap and good enough for pointer keys.
  uintptr_t x = (uintptr_t)key >> 4;
  x = (x ^ (x >> 30)) * 0xbf58476d1ce4e5b9ULL;
  x = (x ^ (x >> 27)) * 0x94d049bb133111ebULL;
  x =  x ^ (x >> 31);
  return (size_t)x;
}

static int ast_rt_cache_grow(TcError *err) {
  size_t new_cap = g_ast_rt_cache_cap == 0 ? 256 : g_ast_rt_cache_cap * 2;
  AstRuntimeCacheEntry *grown = (AstRuntimeCacheEntry *)
      calloc(new_cap, sizeof(AstRuntimeCacheEntry));
  if (!grown) {
    tc_error_set(err, "ast_to_runtime: cache calloc failed");
    return 0;
  }
  size_t mask = new_cap - 1;
  for (size_t i = 0; i < g_ast_rt_cache_cap; i++) {
    void *k = g_ast_rt_cache[i].key;
    if (!k) continue;
    size_t slot = ast_rt_hash(k) & mask;
    while (grown[slot].key) slot = (slot + 1) & mask;
    grown[slot] = g_ast_rt_cache[i];
  }
  free(g_ast_rt_cache);
  g_ast_rt_cache = grown;
  g_ast_rt_cache_cap = new_cap;
  return 1;
}

static int ast_rt_cache_lookup(void *key, TcValue *out) {
  if (!key || g_ast_rt_cache_cap == 0) return 0;
  size_t mask = g_ast_rt_cache_cap - 1;
  size_t slot = ast_rt_hash(key) & mask;
  while (g_ast_rt_cache[slot].key) {
    if (g_ast_rt_cache[slot].key == key) {
      *out = g_ast_rt_cache[slot].value;
      return 1;
    }
    slot = (slot + 1) & mask;
  }
  return 0;
}

static int ast_rt_cache_store(void *key, TcValue value, TcError *err) {
  if (!key) return 1;
  // Keep load factor <= 0.5 to bound probe length.
  if ((g_ast_rt_cache_count + 1) * 2 > g_ast_rt_cache_cap) {
    if (!ast_rt_cache_grow(err)) return 0;
  }
  size_t mask = g_ast_rt_cache_cap - 1;
  size_t slot = ast_rt_hash(key) & mask;
  while (g_ast_rt_cache[slot].key) {
    if (g_ast_rt_cache[slot].key == key) {
      // Pre-existing — overwrite (e.g. recursive store-before-recurse).
      g_ast_rt_cache[slot].value = value;
      return 1;
    }
    slot = (slot + 1) & mask;
  }
  g_ast_rt_cache[slot].key = key;
  g_ast_rt_cache[slot].value = value;
  g_ast_rt_cache_count++;
  return 1;
}

// Deep-convert an AST value into runtime equivalents. Unlike ast_to_value,
// composite kinds (ARRAY/HASH) become mutable TcRuntimeArray / TcRuntimeHash
// rather than another TC_VAL_AST wrapping. Used at the TcRuntimeHash store
// boundary so values that cross into mutable storage become mutable.
//
// Without this, the C VM's `[]=` on TC_VAL_AST hashes silently no-ops (the
// dispatch table only handles TC_VAL_HASH and TC_VAL_ARRAY), which broke
// `mod[:known_classes][cname][:ivar_offsets] = ...` in the bootstrap and
// forced the slow string-keyed ivar lookup path on every method body
// (1183 w_ivar_get_wv calls in stage1.ll vs 1 in stage2).
static int ast_to_runtime(TcAstValue *ast, TcValue *out, TcError *err) {
  switch (ast->kind) {
    case TC_AST_NIL:
    case TC_AST_BOOL:
    case TC_AST_INT:
    case TC_AST_STRING:
    case TC_AST_SYMBOL:
      // Scalars match ast_to_value: no aggregate to materialize, no
      // identity to preserve (no caching needed).
      return ast_to_value(*ast, out, err);
    case TC_AST_ARRAY: {
      // Cache by the underlying TcAstArray * — stable across box copies.
      void *cache_key = ast->as.array;
      if (ast_rt_cache_lookup(cache_key, out)) return 1;
      size_t n = ast->as.array ? ast->as.array->count : 0;
      TcRuntimeArray *arr = runtime_array_new(n, err);
      if (!arr) return 0;
      *out = tc_box_array(arr);
      // Store BEFORE recursing so cycles (if any) terminate.
      if (!ast_rt_cache_store(cache_key, *out, err)) return 0;
      for (size_t i = 0; i < n; i++) {
        if (!ast_to_runtime(&ast->as.array->items[i], &arr->slots[i], err)) {
          return 0;
        }
      }
      arr->size = n;
      return 1;
    }
    case TC_AST_HASH: {
      void *cache_key = ast->as.hash;
      if (ast_rt_cache_lookup(cache_key, out)) return 1;
      size_t n = ast->as.hash ? ast->as.hash->count : 0;
      TcRuntimeHash *h = runtime_hash_new(n, err);
      if (!h) return 0;
      *out = tc_box_hash(h);
      if (!ast_rt_cache_store(cache_key, *out, err)) return 0;
      for (size_t i = 0; i < n; i++) {
        // AST hash keys are raw cstrings (e.g. "node", "name"). The compiler
        // builds these hashes with symbol-keyed literals like {node: ...},
        // so promote the cstring to an interned symbol value.
        const char *key_bytes = ast->as.hash->items[i].key;
        size_t key_len = key_bytes ? strlen(key_bytes) : 0;
        const char *interned = tc_intern(key_bytes ? key_bytes : "", key_len);
        if (!interned) {
          tc_error_set(err, "ast_to_runtime: symbol intern failed");
          return 0;
        }
        TcValue key_v = tc_box_symbol_bytes(interned, key_len, 0);
        TcValue val_v;
        if (!ast_to_runtime(&ast->as.hash->items[i].value, &val_v, err)) return 0;
        if (!hash_set_value(h, key_v, val_v, err)) return 0;
      }
      return 1;
    }
  }
  *out = tc_box_nil();
  return 1;
}

static int ast_hash_lookup(TcAstValue ast, TcValue key, TcValue *out, TcError *err) {
  if (ast.kind != TC_AST_HASH || !ast.as.hash) {
    *out = tc_box_nil();
    return 1;
  }
  const char *key_bytes = NULL;
  size_t key_len = 0;
  if (tc_kind(key) == TC_VAL_SYMBOL || tc_kind(key) == TC_VAL_STRING) {
    key_bytes = tc_str_bytes_only(key);
    key_len = tc_str_len(key);
  } else {
    *out = tc_box_nil();
    return 1;
  }
  for (size_t i = 0; i < ast.as.hash->count; i++) {
    if (strlen(ast.as.hash->items[i].key) == key_len &&
        memcmp(ast.as.hash->items[i].key, key_bytes, key_len) == 0) {
      return ast_to_value(ast.as.hash->items[i].value, out, err);
    }
  }
  *out = tc_box_nil();
  return 1;
}

static int find_local_slot(const TcChunk *chunk, const char *name, size_t len) {
  TcLocalName *entries = chunk->locals;
  for (size_t i = 0; i < chunk->local_count; i++) {
    if (entries[i].len == len && memcmp(entries[i].name, name, len) == 0) return (int)i;
  }
  return -1;
}

// Hot-path helper for the canonical "self" slot. Method dispatch (CALL on
// a TC_VAL_OBJECT receiver) and IVAR_GET / IVAR_SET all need to find the
// `self` local on every invocation. The slot is fixed once compile is
// done, so cache the first lookup on the chunk and read it from there.
// -2 means "not yet computed"; -1 means "no self in this chunk".
static inline int find_self_slot(TcChunk *chunk) {
  int cached = chunk->self_slot_cache;
  if (cached != -2) return cached;
  cached = find_local_slot(chunk, "self", 4);
  chunk->self_slot_cache = cached;
  return cached;
}

static int vm_call_function(TcVm *vm, TcFunction *fn, TcValue *args, uint32_t argc, TcValue self,
                            int has_self, TcValue override, int has_override, TcError *err) {
  if (vm->call_depth >= sizeof(vm->frames) / sizeof(vm->frames[0])) {
    tc_error_set(err, "call stack overflow");
    return 0;
  }
  size_t local_count = vm->chunk->local_count;
  size_t depth = vm->call_depth;
  // Save only the slots this fn writes (precomputed at chunk finalize).
  // Storage is depth*local_count slots; we pack {slot, value} into the
  // pool sequentially. Falls back to full-locals memcpy if touched_slots
  // wasn't computed (e.g. main, before finalize).
  if (fn->touched_slots && fn->touched_slot_count > 0) {
    // Combined save + reset: each touched slot is captured into the pool
    // and zeroed in the same iteration. Two passes used to walk the
    // touched_slots array twice — folding them halves the loop overhead
    // and keeps the load/store paired in the cpu's reorder buffer.
    TcValue *slot_base = vm->saved_locals_pool + depth * local_count;
    TcValue nil_v = tc_box_nil();
    for (uint32_t i = 0; i < fn->touched_slot_count; i++) {
      uint32_t slot = fn->touched_slots[i];
      slot_base[i] = vm->locals[slot];
      vm->locals[slot] = nil_v;
    }
    vm->frames[depth].saved_locals_active = 1;
  } else if (local_count > 0) {
    memcpy(vm->saved_locals_pool + depth * local_count, vm->locals,
           local_count * sizeof(TcValue));
    vm->frames[depth].saved_locals_active = 1;
  } else {
    vm->frames[depth].saved_locals_active = 0;
  }
  if (!(fn->touched_slots && fn->touched_slot_count > 0) &&
      vm->chunk->local_count > vm->chunk->global_count) {
    size_t first_local = vm->chunk->global_count;
    if (first_local > vm->chunk->local_count) first_local = vm->chunk->local_count;
    memset(vm->locals + first_local, 0, (vm->chunk->local_count - first_local) * sizeof(TcValue));
  }
  if (has_self) {
    int self_slot = find_self_slot(vm->chunk);
    if (self_slot >= 0) vm->locals[self_slot] = self;
  }
  for (uint32_t i = 0; i < fn->arity; i++) {
    vm->locals[fn->param_slots[i]] = i < argc ? args[i] : tc_box_nil();
  }
  vm->call_depth++;
  vm->frames[depth].return_ip = vm->ip;
  vm->frames[depth].function = fn;
  vm->frames[depth].has_return_override = has_override;
  vm->frames[depth].return_override = override;
  vm->ip = fn->entry;
  return 1;
}

static int int_binary(TcVm *vm, uint8_t op, TcError *err) {
  TcValue b = pop(vm);
  TcValue a = pop(vm);
  if (op == TC_OP_EQ || op == TC_OP_NEQ) {
    int eq = value_equal(a, b);
    return push(vm, tc_box_wvalue((op == TC_OP_EQ ? eq : !eq) ? W_TRUE : W_FALSE), err);
  }
  if (op == TC_OP_ADD && tc_kind(a) == TC_VAL_STRING) {
    TcValue out;
    if (!concat_values(a, b, &out, err)) return 0;
    return push(vm, out, err);
  }
  if (op == TC_OP_ADD && tc_kind(a) == TC_VAL_OBJECT && object_is_class(tc_as_object(a), "StringBuffer", 12)) {
    if (!runtime_string_buffer_append(tc_as_object(a), b, err)) return 0;
    return push(vm, a, err);
  }
  if (op == TC_OP_LT || op == TC_OP_LTE || op == TC_OP_GT || op == TC_OP_GTE) {
    int cmp = 0;
    if (value_text_compare(a, b, &cmp)) {
      int ok = 0;
      switch (op) {
        case TC_OP_LT: ok = cmp < 0; break;
        case TC_OP_LTE: ok = cmp <= 0; break;
        case TC_OP_GT: ok = cmp > 0; break;
        case TC_OP_GTE: ok = cmp >= 0; break;
      }
      return push(vm, tc_box_wvalue(ok ? W_TRUE : W_FALSE), err);
    }
    if ((value_is_int(a) && tc_kind(b) == TC_VAL_STRING) ||
        (tc_kind(a) == TC_VAL_STRING && value_is_int(b))) {
      const char *s = (tc_kind(a) == TC_VAL_STRING) ? tc_str_bytes_only(a) : tc_str_bytes_only(b);
      // Skip leading '~' (approx-number marker — e.g. ~0.001)
      while (*s == '~' || *s == '+') s++;
      char *endp = NULL;
      double dnum = strtod(s, &endp);
      if (endp && endp != s) {
        double da = value_is_int(a) ? (double)value_as_int(a) : dnum;
        double db = value_is_int(b) ? (double)value_as_int(b) : dnum;
        int ok = 0;
        switch (op) {
          case TC_OP_LT: ok = da < db; break;
          case TC_OP_LTE: ok = da <= db; break;
          case TC_OP_GT: ok = da > db; break;
          case TC_OP_GTE: ok = da >= db; break;
        }
        return push(vm, tc_box_wvalue(ok ? W_TRUE : W_FALSE), err);
      }
    }
  }
  if (!value_is_int(a) || !value_is_int(b)) {
    size_t fn_len = 0;
    const char *fn_name = current_function_name(vm, vm->ip > 0 ? vm->ip - 1 : vm->ip, &fn_len);
    tc_error_set(err, "operator %u expects integer operands left=%s right=%s fn=%.*s ip=%zu",
                 op, value_type_name(a), value_type_name(b), (int)fn_len, fn_name, vm->ip > 0 ? vm->ip - 1 : vm->ip);
    return 0;
  }

  int64_t av = value_as_int(a);
  int64_t bv = value_as_int(b);
  int64_t iv = 0;
  TcValue out = tc_box_nil();

  switch (op) {
    case TC_OP_ADD: iv = av + bv; out = int_value(iv); break;
    case TC_OP_SUB: iv = av - bv; out = int_value(iv); break;
    case TC_OP_MUL: iv = av * bv; out = int_value(iv); break;
    case TC_OP_MOD:
      if (bv == 0) {
        tc_error_set(err, "modulo by zero");
        return 0;
      }
      iv = av % bv;
      out = int_value(iv);
      break;
    case TC_OP_BIT_AND: iv = av & bv; out = int_value(iv); break;
    case TC_OP_BIT_OR: iv = av | bv; out = int_value(iv); break;
    case TC_OP_BIT_XOR: iv = av ^ bv; out = int_value(iv); break;
    case TC_OP_SHL: iv = av << bv; out = int_value(iv); break;
    case TC_OP_SHR: iv = av >> bv; out = int_value(iv); break;
    case TC_OP_POW:
      iv = 1;
      if (bv < 0) {
        tc_error_set(err, "integer exponent must be non-negative");
        return 0;
      }
      for (int64_t i = 0; i < bv; i++) iv *= av;
      out = int_value(iv);
      break;
    case TC_OP_DIV:
      if (bv == 0) {
        tc_error_set(err, "division by zero");
        return 0;
      }
      iv = av / bv;
      out = int_value(iv);
      break;
    case TC_OP_EQ: out = tc_box_wvalue(av == bv ? W_TRUE : W_FALSE); break;
    case TC_OP_NEQ: out = tc_box_wvalue(av != bv ? W_TRUE : W_FALSE); break;
    case TC_OP_LT: out = tc_box_wvalue(av < bv ? W_TRUE : W_FALSE); break;
    case TC_OP_LTE: out = tc_box_wvalue(av <= bv ? W_TRUE : W_FALSE); break;
    case TC_OP_GT: out = tc_box_wvalue(av > bv ? W_TRUE : W_FALSE); break;
    case TC_OP_GTE: out = tc_box_wvalue(av >= bv ? W_TRUE : W_FALSE); break;
    default:
      tc_error_set(err, "unknown integer operator");
      return 0;
  }

  return push(vm, out, err);
}

void tc_value_print(TcValue value, FILE *out) {
  switch (tc_kind(value)) {
    case TC_VAL_NIL:
      fputs("nil", out);
      break;
    case TC_VAL_STRING:
      fwrite(tc_str_bytes_only(value), 1, tc_str_len(value), out);
      break;
    case TC_VAL_SYMBOL:
      fputc(':', out);
      fwrite(tc_str_bytes_only(value), 1, tc_str_len(value), out);
      break;
    case TC_VAL_ARRAY:
      fprintf(out, "[%zu item%s]", tc_as_array(value) ? tc_as_array(value)->size : 0, tc_as_array(value) && tc_as_array(value)->size == 1 ? "" : "s");
      break;
    case TC_VAL_HASH:
      fprintf(out, "{%zu pair%s}", tc_as_hash(value) ? tc_as_hash(value)->count : 0, tc_as_hash(value) && tc_as_hash(value)->count == 1 ? "" : "s");
      break;
    case TC_VAL_OBJECT:
      if (tc_as_object(value)) fprintf(out, "#<%.*s>", (int)tc_as_object(value)->class_name_len, tc_as_object(value)->class_name);
      else fputs("#<Object>", out);
      break;
    case TC_VAL_AST:
      tc_ast_print(*tc_as_ast_ptr(&value), out);
      break;
    case TC_VAL_WVALUE:
      if (tc_as_wvalue(value) == W_NIL) fputs("nil", out);
      else if (tc_as_wvalue(value) == W_TRUE) fputs("true", out);
      else if (tc_as_wvalue(value) == W_FALSE) fputs("false", out);
      else if (w_is_int(tc_as_wvalue(value))) fprintf(out, "%lld", (long long)w_as_int(tc_as_wvalue(value)));
      else fprintf(out, "0x%016llx", (unsigned long long)tc_as_wvalue(value));
      break;
    case TC_VAL_INT:
      fprintf(out, "%lld", (long long)tc_as_int(value));
      break;
  }
}

int tc_vm_run_args(const TcChunk *chunk, int argc, char **argv, TcValue *result, TcError *err) {
  if (!builtin_names_ready && !intern_builtin_names(err)) return 0;
  TcVm vm;
  memset(&vm, 0, sizeof(vm));
  vm.chunk = chunk;
  vm.locals = (TcValue *)calloc(chunk->local_count ? chunk->local_count : 1, sizeof(TcValue));
  if (!vm.locals) {
    tc_error_set(err, "local allocation failed");
    return 0;
  }
  vm.argv = runtime_argv_new(argc, argv, err);
  if (!vm.argv) {
    free(vm.saved_locals_pool);
            free(vm.locals);
    return 0;
  }
  size_t pool_slots = chunk->local_count ? chunk->local_count : 1;
  vm.saved_locals_pool = (TcValue *)calloc(2048 * pool_slots, sizeof(TcValue));
  if (!vm.saved_locals_pool) {
    free(vm.saved_locals_pool);
            free(vm.locals);
    runtime_array_free(vm.argv);
    tc_error_set(err, "save-pool allocation failed");
    return 0;
  }

  // Threaded dispatch (computed goto). Each handler ends with NEXT()
  // which dispatches the next instruction directly via a label table —
  // no centralized switch, so each handler gets its own branch-predictor
  // entry. Drops one indirect-branch mispredict per opcode on the hot
  // path of CONST → LOAD_LOCAL → ADD-ish patterns.
  static const void *const targets[256] = {
    [TC_OP_CONST]         = &&L_CONST,
    [TC_OP_LOAD_LOCAL]    = &&L_LOAD_LOCAL,
    [TC_OP_STORE_LOCAL]   = &&L_STORE_LOCAL,
    [TC_OP_ADD]           = &&L_ARITH,
    [TC_OP_SUB]           = &&L_ARITH,
    [TC_OP_MUL]           = &&L_ARITH,
    [TC_OP_DIV]           = &&L_ARITH,
    [TC_OP_EQ]            = &&L_EQ,
    [TC_OP_NEQ]           = &&L_NEQ,
    [TC_OP_LT]            = &&L_ARITH,
    [TC_OP_LTE]           = &&L_ARITH,
    [TC_OP_GT]            = &&L_ARITH,
    [TC_OP_GTE]           = &&L_ARITH,
    [TC_OP_MOD]           = &&L_ARITH,
    [TC_OP_BIT_AND]       = &&L_ARITH,
    [TC_OP_BIT_OR]        = &&L_ARITH,
    [TC_OP_BIT_XOR]       = &&L_ARITH,
    [TC_OP_SHL]           = &&L_ARITH,
    [TC_OP_SHR]           = &&L_ARITH,
    [TC_OP_POW]           = &&L_ARITH,
    [TC_OP_PRINT]         = &&L_PRINT,
    [TC_OP_POP]           = &&L_POP,
    [TC_OP_JUMP]          = &&L_JUMP,
    [TC_OP_JUMP_IF_FALSE] = &&L_JUMP_IF_FALSE,
    [TC_OP_CALL]          = &&L_CALL,
    [TC_OP_CALL_DISCARD]  = &&L_CALL_DISCARD,
    [TC_OP_ARRAY]         = &&L_ARRAY,
    [TC_OP_HASH]          = &&L_HASH,
    [TC_OP_RETURN]        = &&L_RETURN,
    [TC_OP_EQ_CONST_BR]   = &&L_EQ_CONST_BR,
    [TC_OP_NOP]           = &&L_NOP,
    [TC_OP_CASE_SYM_LINEAR] = &&L_CASE_SYM_LINEAR,
    [TC_OP_INDEX]         = &&L_INDEX,
    [TC_OP_SIZE_OF]       = &&L_SIZE_OF,
    [TC_OP_INDEX_LL]      = &&L_INDEX_LL,
    [TC_OP_SIZE_OF_LOCAL] = &&L_SIZE_OF_LOCAL,
    [TC_OP_LOAD_EQ_CONST_BR] = &&L_LOAD_EQ_CONST_BR,
    [TC_OP_IVAR_GET]      = &&L_IVAR_GET,
    [TC_OP_IVAR_SET]      = &&L_IVAR_SET,
    [TC_OP_CVAR_GET]      = &&L_CVAR_GET,
    [TC_OP_CVAR_SET]      = &&L_CVAR_SET,
    [TC_OP_TYPED_ARRAY]   = &&L_TYPED_ARRAY,
    [TC_OP_CASE_MATCH]    = &&L_CASE_MATCH,
  };

  size_t op_ip = 0;
  uint8_t op = 0;
  (void)op_ip; (void)op;
  // GC removed; nothing to pace per opcode any more — dispatch is just
  // read opcode + computed-goto.
  //
  // TOS register cache (write-through). Invariant: tos == vm.stack[vm.sp - 1]
  // whenever vm.sp > 0 at label entry. Tos-aware ops (the inlined hot ones)
  // maintain this themselves and dispatch via NEXT_FAST(); ops that mutate
  // the stack via push/pop helpers leave tos stale and use NEXT(), which
  // refreshes from vm.stack[sp-1] before dispatching. The first NEXT_INIT()
  // skips the refresh because sp == 0 at frame entry.
  register WValue tos = 0;
  (void)tos;
#define NEXT_FAST() do { \
    op_ip = vm.ip; \
    op = chunk->code[vm.ip++]; \
    goto *targets[op]; \
  } while (0)
#define NEXT() do { tos = vm.stack[vm.sp - 1]; NEXT_FAST(); } while (0)
#define NEXT_INIT() NEXT_FAST()

  NEXT_INIT();

  {
      // Hot opcodes — inlined push/store and dropped per-op bounds checks.
      // The compiler only emits valid slot/const ids, so the checks were
      // unreachable on conformant bytecode (the stack is sized 1024,
      // bigger than any reachable depth). Together these three opcodes
      // run on ~50% of bootstrap dispatches.
      L_CONST: {
        uint32_t id = read_u32_at(&chunk->code[vm.ip]);
        vm.ip += 4;
        vm.stack[vm.sp++] = (tos = chunk->consts[id]);
        NEXT_FAST();
      }
      L_LOAD_LOCAL: {
        uint32_t id = read_u32_at(&chunk->code[vm.ip]);
        vm.ip += 4;
        vm.stack[vm.sp++] = (tos = vm.locals[id]);
        NEXT_FAST();
      }
      L_STORE_LOCAL: {
        uint32_t id = read_u32_at(&chunk->code[vm.ip]);
        vm.ip += 4;
        vm.locals[id] = tos;
        NEXT_FAST();
      }
      // Inlined EQ/NEQ — int==int and sym==sym (ptr-equal) are the
      // overwhelmingly common cases (16% of bootstrap dispatches).
      // Fall back to the generic int_binary → value_equal path for
      // mixed-kind, AST, hash, etc.
      // Inlined EQ/NEQ.
      // sym==sym is the dominant pattern (75% of bootstrap EQs), almost
      // all from hash-key probes. With const-pool deduping we know
      // every TC_VAL_SYMBOL came from a unique-per-content bytes
      // buffer, so ptr-equality is the WHOLE answer for sym-vs-sym —
      // skip the memcmp fallback even on mismatch. If a runtime path
      // ever creates a non-interned symbol, this would over-report
      // inequality; that case currently doesn't exist (parser AST
      // syms come from const-pool literals).
      L_EQ: {
        TcValue b = tos;
        TcValue a = vm.stack[vm.sp - 2];
        vm.sp--;
        TcValue r;
        // Hot fast paths inlined to skip the value_equal call:
        //   int==int  : 64-bit compare
        //   sym==sym  : ptr equality (interned bytes — see header comment)
        if (tc_kind(a) == TC_VAL_INT && tc_kind(b) == TC_VAL_INT) {
          r = tc_box_wvalue(tc_as_int(a) == tc_as_int(b) ? W_TRUE : W_FALSE);
        } else if (tc_kind(a) == TC_VAL_SYMBOL && tc_kind(b) == TC_VAL_SYMBOL) {
          r = tc_box_wvalue(tc_str_bytes_only(a) == tc_str_bytes_only(b) ? W_TRUE : W_FALSE);
        } else {
          int eq = value_equal(a, b);
          r = tc_box_wvalue(eq ? W_TRUE : W_FALSE);
        }
        vm.stack[vm.sp - 1] = (tos = r);
        NEXT_FAST();
      }
      L_NEQ: {
        TcValue b = tos;
        TcValue a = vm.stack[vm.sp - 2];
        vm.sp--;
        TcValue r;
        if (tc_kind(a) == TC_VAL_INT && tc_kind(b) == TC_VAL_INT) {
          r = tc_box_wvalue(tc_as_int(a) != tc_as_int(b) ? W_TRUE : W_FALSE);
        } else if (tc_kind(a) == TC_VAL_SYMBOL && tc_kind(b) == TC_VAL_SYMBOL) {
          r = tc_box_wvalue(tc_str_bytes_only(a) != tc_str_bytes_only(b) ? W_TRUE : W_FALSE);
        } else {
          int eq = value_equal(a, b);
          r = tc_box_wvalue(eq ? W_FALSE : W_TRUE);
        }
        vm.stack[vm.sp - 1] = (tos = r);
        NEXT_FAST();
      }
      // Fused CONST id ; EQ ; JUMP_IF_FALSE target. Pops the comparand
      // (the case scrutinee), compares to the const, falls through on
      // match or jumps on mismatch. Replaces three opcodes / three
      // dispatches with one. Skips the intermediate push-of-true/false
      // and re-pop entirely. ~25% of stage-1 dispatches were this triple
      // (case-arm sym-dispatch in lower_*/parse_*).
      L_EQ_CONST_BR: {
        // Operand layout: [u32 const_id][u32 target][NOP][NOP].
        // The two trailing NOP bytes are padding so that the rewrite
        // leaves chunk-relative byte offsets stable for absolute jump
        // targets. Both fall-through and mismatch paths land past
        // them — no NOP dispatches.
        uint32_t cid = read_u32_at(&chunk->code[vm.ip]);
        uint32_t target = read_u32_at(&chunk->code[vm.ip + 4]);
        vm.ip += 10;  // skip operands + 2 NOP padding bytes
        TcValue a = tos;
        vm.sp--;
        TcValue b = chunk->consts[cid];
        int eq;
        if (tc_kind(a) == TC_VAL_INT && tc_kind(b) == TC_VAL_INT) eq = (tc_as_int(a) == tc_as_int(b));
        else if (tc_kind(a) == TC_VAL_SYMBOL && tc_kind(b) == TC_VAL_SYMBOL) eq = (tc_str_bytes_only(a) == tc_str_bytes_only(b));
        else eq = value_equal(a, b);
        if (!eq) vm.ip = target;
        NEXT();  // pop-only — refresh tos from new top
      }
      L_NOP:
        NEXT_FAST();  // no stack mutation
      L_IVAR_GET: {
        // self is bound by vm_call_function on every method call into a
        // local slot named "self". The slot index is stable across the
        // chunk (local-name table is shared) so a single per-chunk
        // lookup amortizes; we do the find_local_slot scan inline since
        // it's a short linear walk and IVAR ops aren't on the dispatch
        // hot path.
        uint32_t name_id = read_u32_at(&chunk->code[vm.ip]);
        vm.ip += 4;
        TcValue out = tc_box_nil();
        int self_slot = find_self_slot(chunk);
        if (self_slot >= 0 && tc_kind(vm.locals[self_slot]) == TC_VAL_OBJECT) {
          TcRuntimeObject *self = tc_as_object(vm.locals[self_slot]);
          if (self && self->fields) {
            out = hash_get_value(self->fields, chunk->consts[name_id]);
          }
        }
        vm.stack[vm.sp++] = (tos = out);
        NEXT_FAST();
      }
      L_IVAR_SET: {
        uint32_t name_id = read_u32_at(&chunk->code[vm.ip]);
        vm.ip += 4;
        // Leave value on stack — assignment expressions evaluate to the
        // assigned value. tos already holds it (write-through invariant).
        TcValue value = tos;
        int self_slot = find_self_slot(chunk);
        if (self_slot < 0 || tc_kind(vm.locals[self_slot]) != TC_VAL_OBJECT || !tc_as_object(vm.locals[self_slot])) {
          tc_error_set(err, "ivar set outside of an instance method (no self)");
          goto cleanup_fail;
        }
        TcRuntimeObject *self = tc_as_object(vm.locals[self_slot]);
        if (!self->fields) {
          self->fields = runtime_hash_new(0, err);
          if (!self->fields) goto cleanup_fail;
        }
        if (!hash_set_value(self->fields, chunk->consts[name_id], value, err)) goto cleanup_fail;
        NEXT_FAST();
      }
      L_CVAR_GET: {
        uint32_t name_id = read_u32_at(&chunk->code[vm.ip]);
        vm.ip += 4;
        TcValue out = cvar_table ? hash_get_value(cvar_table, chunk->consts[name_id]) : tc_box_nil();
        vm.stack[vm.sp++] = (tos = out);
        NEXT_FAST();
      }
      L_CVAR_SET: {
        uint32_t name_id = read_u32_at(&chunk->code[vm.ip]);
        vm.ip += 4;
        TcValue value = tos;
        if (!cvar_table) {
          cvar_table = runtime_hash_new(0, err);
          if (!cvar_table) goto cleanup_fail;
        }
        if (!hash_set_value(cvar_table, chunk->consts[name_id], value, err)) goto cleanup_fail;
        NEXT_FAST();
      }
      // Sym-only case dispatch. Pops the scrutinee; if it's a sym,
      // linear-scans the off-band table by interned-bytes pointer
      // (1-cycle compare per entry). On match, jumps directly to the
      // arm body's start; otherwise (or when scrutinee isn't a sym)
      // jumps to default_target. Replaces an N-arm chain of
      // LOAD_LOCAL + EQ_CONST_BR + JUMP — three dispatches per arm
      // collapse to one. The dominant case-dispatch shape in
      // compiler/lib/lowering.w (`case t when :var ...`) post-EQ_CONST_BR
      // fusion was 12.7% of bootstrap dispatches; this folds the body
      // of that slice down to ~1/N of its prior dispatch count.
      L_CASE_SYM_LINEAR: {
        uint32_t tid = read_u32_at(&chunk->code[vm.ip]);
        vm.ip += 4;
        const TcCaseTable *table = &chunk->case_tables[tid];
        TcValue subject = tos;
        vm.sp--;
        uint32_t target = table->default_target;
        if (tc_kind(subject) == TC_VAL_SYMBOL) {
          const char *bytes = tc_str_bytes_only(subject);
          for (uint32_t i = 0; i < table->count; i++) {
            if (table->keys[i] == bytes) {
              target = table->targets[i];
              break;
            }
          }
        }
        vm.ip = target;
        NEXT();  // pop-only — refresh tos
      }
      // Specialised `receiver[arg]` dispatch. Pops arg + receiver,
      // pushes receiver[arg]. Replaces a CALL "[]" argc=1 has_recv=1
      // (which, post-emit_call_op + matcher reorder, was already 1 op
      // + 12 operand bytes + arg-buffer setup + name-ptr compare +
      // pop receiver/args). On the BRACKETS hot path (~33M dispatches/run)
      // this collapses ~50-100 cycles per call to a single direct
      // kind-switch.
      L_INDEX: {
        TcValue arg = tos;
        TcValue receiver = vm.stack[vm.sp - 2];
        vm.sp -= 2;
        TcValue out;
        switch (tc_kind(receiver)) {
          case TC_VAL_AST: {
            if (tc_as_ast_ptr(&receiver)->kind == TC_AST_HASH) {
              if (!ast_hash_lookup(*tc_as_ast_ptr(&receiver), arg, &out, err)) goto cleanup_fail;
            } else if (tc_as_ast_ptr(&receiver)->kind == TC_AST_ARRAY && tc_as_ast_ptr(&receiver)->as.array && value_is_int(arg)) {
              int64_t idx = value_as_int(arg);
              if (idx >= 0 && (size_t)idx < tc_as_ast_ptr(&receiver)->as.array->count) {
                if (!ast_to_value(tc_as_ast_ptr(&receiver)->as.array->items[idx], &out, err)) goto cleanup_fail;
              } else {
                out = tc_box_nil();
              }
            } else {
              out = tc_box_nil();
            }
            break;
          }
          case TC_VAL_HASH:
            out = tc_as_hash(receiver) ? hash_get_value(tc_as_hash(receiver), arg) : tc_box_nil();
            break;
          case TC_VAL_ARRAY: {
            if (!tc_as_array(receiver)) {
              out = tc_box_nil();
            } else if (value_is_int(arg)) {
              int64_t idx = value_as_int(arg);
              size_t n = tc_as_array(receiver)->size;
              if (idx < 0) idx += (int64_t)n;
              out = (idx >= 0 && (size_t)idx < n)
                        ? tc_as_array(receiver)->slots[idx]
                        : tc_box_nil();
            } else if (tc_kind(arg) == TC_VAL_HASH && tc_as_hash(arg)) {
              // Range slice: ast_compile.c lowers `:range` to a tagged hash
              // {__range__: true, from:, to:, exclusive:}. Recognize the tag
              // and produce a sub-array. Negative indices end-relative.
              TcRuntimeHash *rh = tc_as_hash(arg);
              int is_range = 0;
              TcValue from_v = tc_box_nil();
              TcValue to_v = tc_box_nil();
              int excl = 0;
              for (size_t k = 0; k < rh->cap; k++) {
                TcValue key = rh->keys[k];
                if (key == TC_HASH_EMPTY || key == TC_HASH_TOMBSTONE) continue;
                if (tc_kind(key) != TC_VAL_SYMBOL) continue;
                const char *kb = tc_str_bytes_only(key);
                size_t kl = tc_str_len(key);
                if (kl == 9 && memcmp(kb, "__range__", 9) == 0) is_range = 1;
                else if (kl == 4 && memcmp(kb, "from", 4) == 0) from_v = rh->values[k];
                else if (kl == 2 && memcmp(kb, "to", 2) == 0) to_v = rh->values[k];
                else if (kl == 9 && memcmp(kb, "exclusive", 9) == 0) {
                  excl = (tc_kind(rh->values[k]) == TC_VAL_WVALUE && tc_as_wvalue(rh->values[k]) == W_TRUE);
                }
              }
              if (is_range && value_is_int(from_v) && (value_is_int(to_v) || tc_kind(to_v) == TC_VAL_NIL)) {
                size_t n = tc_as_array(receiver)->size;
                int64_t lo = value_as_int(from_v);
                int64_t hi = (tc_kind(to_v) == TC_VAL_NIL) ? (int64_t)n - 1 : value_as_int(to_v);
                if (lo < 0) lo += (int64_t)n;
                if (hi < 0) hi += (int64_t)n;
                if (excl) hi -= 1;
                if (lo < 0) lo = 0;
                if (hi >= (int64_t)n) hi = (int64_t)n - 1;
                size_t result_n = (lo > hi) ? 0 : (size_t)(hi - lo + 1);
                TcRuntimeArray *sub = runtime_array_new(result_n, err);
                if (!sub) goto cleanup_fail;
                for (size_t k = 0; k < result_n; k++) {
                  sub->slots[k] = tc_as_array(receiver)->slots[lo + k];
                }
                out = tc_box_array(sub);
              } else {
                out = tc_box_nil();
              }
            } else {
              out = tc_box_nil();
            }
            break;
          }
          case TC_VAL_STRING: {
            out = tc_box_nil();
            if (value_is_int(arg)) {
              int64_t idx = value_as_int(arg);
              if (idx >= 0 && (size_t)idx < tc_str_len(receiver) &&
                  !make_string_value(tc_str_bytes_only(receiver) + idx, 1, &out, err)) {
                goto cleanup_fail;
              }
            }
            break;
          }
          default:
            out = tc_box_nil();
            break;
        }
        vm.stack[vm.sp++] = (tos = out);
        NEXT_FAST();
      }
      // Specialised `receiver.size` dispatch. Promoted from
      // CALL "size" argc=0 (~8M dispatches/run, 14% of CALL).
      L_SIZE_OF: {
        // Pop receiver, push size. Net sp unchanged — tos stays a valid
        // top after we update vm.stack[sp-1] in place.
        TcValue receiver = tos;
        int64_t size = 0;
        switch (tc_kind(receiver)) {
          case TC_VAL_STRING: size = (int64_t)tc_str_len(receiver); break;
          case TC_VAL_ARRAY:  size = tc_as_array(receiver) ? (int64_t)tc_as_array(receiver)->size : 0; break;
          case TC_VAL_HASH:   size = tc_as_hash(receiver) ? (int64_t)tc_as_hash(receiver)->count : 0; break;
          case TC_VAL_AST:
            if (tc_as_ast_ptr(&receiver)->kind == TC_AST_ARRAY && tc_as_ast_ptr(&receiver)->as.array) size = (int64_t)tc_as_ast_ptr(&receiver)->as.array->count;
            else if (tc_as_ast_ptr(&receiver)->kind == TC_AST_HASH && tc_as_ast_ptr(&receiver)->as.hash) size = (int64_t)tc_as_ast_ptr(&receiver)->as.hash->count;
            break;
          default: break;
        }
        vm.stack[vm.sp - 1] = (tos = int_value(size));
        NEXT_FAST();
      }
      // INDEX_LL <recv_slot> <idx_slot>: peephole fusion of
      // LOAD_LOCAL recv ; LOAD_LOCAL idx ; INDEX. Skips two pushes
      // and one pop on the stack — both operands come straight from
      // the locals slot file.
      // Operand layout: [u32 recv_slot][u32 idx_slot][NOP][NOP].
      // The two trailing NOPs are padding so chunk byte offsets stay
      // stable for absolute jump targets.
      L_INDEX_LL: {
        uint32_t recv_slot = read_u32_at(&chunk->code[vm.ip]);
        uint32_t idx_slot = read_u32_at(&chunk->code[vm.ip + 4]);
        vm.ip += 10;  // skip operands + 2 NOP padding bytes
        TcValue receiver = vm.locals[recv_slot];
        TcValue arg = vm.locals[idx_slot];
        TcValue out;
        switch (tc_kind(receiver)) {
          case TC_VAL_AST: {
            if (tc_as_ast_ptr(&receiver)->kind == TC_AST_HASH) {
              if (!ast_hash_lookup(*tc_as_ast_ptr(&receiver), arg, &out, err)) goto cleanup_fail;
            } else if (tc_as_ast_ptr(&receiver)->kind == TC_AST_ARRAY && tc_as_ast_ptr(&receiver)->as.array && value_is_int(arg)) {
              int64_t idx = value_as_int(arg);
              if (idx >= 0 && (size_t)idx < tc_as_ast_ptr(&receiver)->as.array->count) {
                if (!ast_to_value(tc_as_ast_ptr(&receiver)->as.array->items[idx], &out, err)) goto cleanup_fail;
              } else {
                out = tc_box_nil();
              }
            } else {
              out = tc_box_nil();
            }
            break;
          }
          case TC_VAL_HASH:
            out = tc_as_hash(receiver) ? hash_get_value(tc_as_hash(receiver), arg) : tc_box_nil();
            break;
          case TC_VAL_ARRAY: {
            if (!tc_as_array(receiver)) {
              out = tc_box_nil();
            } else if (value_is_int(arg)) {
              int64_t idx = value_as_int(arg);
              size_t n = tc_as_array(receiver)->size;
              if (idx < 0) idx += (int64_t)n;
              out = (idx >= 0 && (size_t)idx < n)
                        ? tc_as_array(receiver)->slots[idx]
                        : tc_box_nil();
            } else if (tc_kind(arg) == TC_VAL_HASH && tc_as_hash(arg)) {
              // Range slice: ast_compile.c lowers `:range` to a tagged hash
              // {__range__: true, from:, to:, exclusive:}. Recognize the tag
              // and produce a sub-array. Negative indices end-relative.
              TcRuntimeHash *rh = tc_as_hash(arg);
              int is_range = 0;
              TcValue from_v = tc_box_nil();
              TcValue to_v = tc_box_nil();
              int excl = 0;
              for (size_t k = 0; k < rh->cap; k++) {
                TcValue key = rh->keys[k];
                if (key == TC_HASH_EMPTY || key == TC_HASH_TOMBSTONE) continue;
                if (tc_kind(key) != TC_VAL_SYMBOL) continue;
                const char *kb = tc_str_bytes_only(key);
                size_t kl = tc_str_len(key);
                if (kl == 9 && memcmp(kb, "__range__", 9) == 0) is_range = 1;
                else if (kl == 4 && memcmp(kb, "from", 4) == 0) from_v = rh->values[k];
                else if (kl == 2 && memcmp(kb, "to", 2) == 0) to_v = rh->values[k];
                else if (kl == 9 && memcmp(kb, "exclusive", 9) == 0) {
                  excl = (tc_kind(rh->values[k]) == TC_VAL_WVALUE && tc_as_wvalue(rh->values[k]) == W_TRUE);
                }
              }
              if (is_range && value_is_int(from_v) && (value_is_int(to_v) || tc_kind(to_v) == TC_VAL_NIL)) {
                size_t n = tc_as_array(receiver)->size;
                int64_t lo = value_as_int(from_v);
                int64_t hi = (tc_kind(to_v) == TC_VAL_NIL) ? (int64_t)n - 1 : value_as_int(to_v);
                if (lo < 0) lo += (int64_t)n;
                if (hi < 0) hi += (int64_t)n;
                if (excl) hi -= 1;
                if (lo < 0) lo = 0;
                if (hi >= (int64_t)n) hi = (int64_t)n - 1;
                size_t result_n = (lo > hi) ? 0 : (size_t)(hi - lo + 1);
                TcRuntimeArray *sub = runtime_array_new(result_n, err);
                if (!sub) goto cleanup_fail;
                for (size_t k = 0; k < result_n; k++) {
                  sub->slots[k] = tc_as_array(receiver)->slots[lo + k];
                }
                out = tc_box_array(sub);
              } else {
                out = tc_box_nil();
              }
            } else {
              out = tc_box_nil();
            }
            break;
          }
          case TC_VAL_STRING: {
            out = tc_box_nil();
            if (value_is_int(arg)) {
              int64_t idx = value_as_int(arg);
              if (idx >= 0 && (size_t)idx < tc_str_len(receiver) &&
                  !make_string_value(tc_str_bytes_only(receiver) + idx, 1, &out, err)) {
                goto cleanup_fail;
              }
            }
            break;
          }
          default:
            out = tc_box_nil();
            break;
        }
        vm.stack[vm.sp++] = (tos = out);
        NEXT_FAST();
      }
      // SIZE_OF_LOCAL <slot>: peephole fusion of LOAD_LOCAL + SIZE_OF.
      // Operand layout: [u32 slot][NOP].
      L_SIZE_OF_LOCAL: {
        uint32_t slot = read_u32_at(&chunk->code[vm.ip]);
        vm.ip += 5;  // 4 operand bytes + 1 NOP padding
        TcValue receiver = vm.locals[slot];
        int64_t size = 0;
        switch (tc_kind(receiver)) {
          case TC_VAL_STRING: size = (int64_t)tc_str_len(receiver); break;
          case TC_VAL_ARRAY:  size = tc_as_array(receiver) ? (int64_t)tc_as_array(receiver)->size : 0; break;
          case TC_VAL_HASH:   size = tc_as_hash(receiver) ? (int64_t)tc_as_hash(receiver)->count : 0; break;
          case TC_VAL_AST:
            if (tc_as_ast_ptr(&receiver)->kind == TC_AST_ARRAY && tc_as_ast_ptr(&receiver)->as.array) size = (int64_t)tc_as_ast_ptr(&receiver)->as.array->count;
            else if (tc_as_ast_ptr(&receiver)->kind == TC_AST_HASH && tc_as_ast_ptr(&receiver)->as.hash) size = (int64_t)tc_as_ast_ptr(&receiver)->as.hash->count;
            break;
          default: break;
        }
        vm.stack[vm.sp++] = (tos = int_value(size));
        NEXT_FAST();
      }
      // LOAD_EQ_CONST_BR <slot> <const_id> <target>: peephole fusion
      // of LOAD_LOCAL + EQ_CONST_BR. Operand layout:
      // [u32 slot][u32 const_id][u32 target][NOP][NOP][NOP].
      // The 3 trailing NOPs come from the original 14-byte sequence
      // (5-byte LOAD_LOCAL + 9-byte EQ_CONST_BR + 2-byte EQ_CONST_BR
      // padding); the 13-byte fused op leaves 3 bytes of padding.
      L_LOAD_EQ_CONST_BR: {
        uint32_t slot = read_u32_at(&chunk->code[vm.ip]);
        uint32_t cid = read_u32_at(&chunk->code[vm.ip + 4]);
        uint32_t target = read_u32_at(&chunk->code[vm.ip + 8]);
        vm.ip += 15;  // 12 operand bytes + 3 NOP padding bytes
        TcValue a = vm.locals[slot];
        TcValue b = chunk->consts[cid];
        int eq;
        if (tc_kind(a) == TC_VAL_INT && tc_kind(b) == TC_VAL_INT) eq = (tc_as_int(a) == tc_as_int(b));
        else if (tc_kind(a) == TC_VAL_SYMBOL && tc_kind(b) == TC_VAL_SYMBOL) eq = (tc_str_bytes_only(a) == tc_str_bytes_only(b));
        else eq = value_equal(a, b);
        if (!eq) vm.ip = target;
        NEXT_FAST();  // no stack mutation
      }
      L_ARITH: {
        // Inline int+int fast path for the most common arithmetic shapes
        // (ADD/SUB/MUL/LT/LTE/GT/GTE/BIT_*/MOD/DIV/SHL/SHR). Skips the
        // value_equal/string-concat/StringBuffer guards in int_binary
        // and the function call boundary itself. Falls through to
        // int_binary for non-int operands and POW.
        TcValue b = vm.stack[vm.sp - 1];
        TcValue a = vm.stack[vm.sp - 2];
        if (w_is_int(a) && w_is_int(b)) {
          int64_t av = w_as_int(a);
          int64_t bv = w_as_int(b);
          int64_t r = 0;
          int is_bool = 0;
          int handled = 1;
          switch (op) {
            case TC_OP_ADD: r = av + bv; break;
            case TC_OP_SUB: r = av - bv; break;
            case TC_OP_MUL: r = av * bv; break;
            case TC_OP_LT:  r = (av <  bv); is_bool = 1; break;
            case TC_OP_LTE: r = (av <= bv); is_bool = 1; break;
            case TC_OP_GT:  r = (av >  bv); is_bool = 1; break;
            case TC_OP_GTE: r = (av >= bv); is_bool = 1; break;
            case TC_OP_BIT_AND: r = av & bv; break;
            case TC_OP_BIT_OR:  r = av | bv; break;
            case TC_OP_BIT_XOR: r = av ^ bv; break;
            case TC_OP_SHL: r = av << bv; break;
            case TC_OP_SHR: r = av >> bv; break;
            case TC_OP_MOD: if (bv == 0) { handled = 0; break; } r = av % bv; break;
            case TC_OP_DIV: if (bv == 0) { handled = 0; break; } r = av / bv; break;
            default: handled = 0; break;  // POW
          }
          if (handled) {
            vm.sp--;
            TcValue result = is_bool
              ? tc_box_wvalue(r ? W_TRUE : W_FALSE)
              : (r >= W_INT48_MIN && r <= W_INT48_MAX ? w_box_int(r) : tc_box_int(r));
            vm.stack[vm.sp - 1] = (tos = result);
            NEXT_FAST();
          }
        }
        if (!int_binary(&vm, op, err)) {
          goto cleanup_fail;
        }
        NEXT();
      }
      L_PRINT: {
        TcValue value = pop(&vm);
        tc_value_print(value, stdout);
        fputc('\n', stdout);
        if (!push(&vm, tc_box_nil(), err)) {
          goto cleanup_fail;
        }
        NEXT();
      }
      L_POP:
        --vm.sp;
        NEXT();
      L_JUMP: {
        uint32_t target = read_u32_at(&chunk->code[vm.ip]);
        vm.ip = target;
        NEXT_FAST();  // no stack mutation
      }
      L_JUMP_IF_FALSE: {
        uint32_t target = read_u32_at(&chunk->code[vm.ip]);
        TcValue value = vm.stack[--vm.sp];
        vm.ip = falsey(value) ? target : vm.ip + 4;
        NEXT();
      }
      // L_CALL and L_CALL_DISCARD share their implementation via
      // vm_call_body.inc, but the dispatch table points each opcode at
      // its own label so the indirect-branch predictor sees two distinct
      // targets. CNEXT is the one variant point: CALL pushes a return
      // value onto the stack, CALL_DISCARD's caller doesn't want it, so
      // the discard variant pops it (or — for the user-fn dispatch path
      // — sets discard_return[depth] so L_RETURN drops the result after
      // the called frame returns). The compiler inlines two specialised
      // copies of the ~900-line body, with the unused branch dead-code
      // eliminated in each.
      L_CALL: {
        vm.frames[vm.call_depth].discard_return = 0;
#define CNEXT() NEXT()
#define DISCARD_NOP_BYTES 0
#include "vm_call_body.inc"
#undef DISCARD_NOP_BYTES
#undef CNEXT
      }
      L_CALL_DISCARD: {
        vm.frames[vm.call_depth].discard_return = 1;
#define CNEXT() do { vm.sp--; NEXT(); } while (0)
#define DISCARD_NOP_BYTES 1
#include "vm_call_body.inc"
#undef DISCARD_NOP_BYTES
#undef CNEXT
      }
      L_ARRAY: {
        uint32_t count = read_u32(&vm);
        TcRuntimeArray *array = runtime_array_new(count, err);
        if (!array) {
          goto cleanup_fail;
        }
        for (uint32_t i = count; i > 0; i--) array->slots[i - 1] = pop(&vm);
        if (!push(&vm, tc_box_array(array), err)) {
          runtime_array_free(array);
          goto cleanup_fail;
        }
        NEXT();
      }
      L_TYPED_ARRAY: {
        TcValue size_v = pop(&vm);
        if (!value_is_int(size_v)) {
          tc_error_set(err, "typed array size must be integer");
          goto cleanup_fail;
        }
        int64_t n = value_as_int(size_v);
        if (n < 0) n = 0;
        TcRuntimeArray *array = runtime_array_new((size_t)n, err);
        if (!array) {
          goto cleanup_fail;
        }
        TcValue zero = w_box_int(0);
        for (size_t i = 0; i < (size_t)n; i++) array->slots[i] = zero;
        if (!push(&vm, tc_box_array(array), err)) {
          runtime_array_free(array);
          goto cleanup_fail;
        }
        NEXT();
      }
      L_CASE_MATCH: {
        // case `subject` when `pattern`: ranges check cover, others fall
        // back to value_equal. Pattern arrives on TOS, subject below it.
        TcValue pattern = pop(&vm);
        TcValue subject = pop(&vm);
        int matched = 0;
        if (tc_kind(pattern) == TC_VAL_HASH && tc_as_hash(pattern)) {
          // Tagged-range hash from ast_compile.c's :range lowering.
          TcRuntimeHash *rh = tc_as_hash(pattern);
          int is_range = 0;
          TcValue from_v = tc_box_nil();
          TcValue to_v = tc_box_nil();
          int excl = 0;
          for (size_t k = 0; k < rh->cap; k++) {
            TcValue key = rh->keys[k];
            if (key == TC_HASH_EMPTY || key == TC_HASH_TOMBSTONE) continue;
            if (tc_kind(key) != TC_VAL_SYMBOL) continue;
            const char *kb = tc_str_bytes_only(key);
            size_t kl = tc_str_len(key);
            if (kl == 9 && memcmp(kb, "__range__", 9) == 0) is_range = 1;
            else if (kl == 4 && memcmp(kb, "from", 4) == 0) from_v = rh->values[k];
            else if (kl == 2 && memcmp(kb, "to", 2) == 0) to_v = rh->values[k];
            else if (kl == 9 && memcmp(kb, "exclusive", 9) == 0) {
              excl = (tc_kind(rh->values[k]) == TC_VAL_WVALUE && tc_as_wvalue(rh->values[k]) == W_TRUE);
            }
          }
          if (is_range && value_is_int(subject) && value_is_int(from_v) &&
              (value_is_int(to_v) || tc_kind(to_v) == TC_VAL_NIL)) {
            int64_t s = value_as_int(subject);
            int64_t lo = value_as_int(from_v);
            int64_t hi = (tc_kind(to_v) == TC_VAL_NIL) ? INT64_MAX : value_as_int(to_v);
            if (excl) hi -= 1;
            matched = (s >= lo && s <= hi);
          } else {
            matched = value_equal(subject, pattern);
          }
        } else {
          matched = value_equal(subject, pattern);
        }
        if (!push(&vm, tc_box_wvalue(matched ? W_TRUE : W_FALSE), err)) goto cleanup_fail;
        NEXT();
      }
      L_HASH: {
        uint32_t count = read_u32(&vm);
        TcRuntimeHash *hash = runtime_hash_new(count, err);
        if (!hash) {
          goto cleanup_fail;
        }
        for (uint32_t i = count; i > 0; i--) {
          TcValue value = pop(&vm);
          TcValue key = pop(&vm);
          if (!hash_set_value(hash, key, value, err)) {
            goto cleanup_fail;
          }
        }
        if (!push(&vm, tc_box_hash(hash), err)) {
          goto cleanup_fail;
        }
        NEXT();
      }
      L_RETURN:
        if (vm.call_depth > 0) {
          TcValue returned = pop(&vm);
          size_t depth = --vm.call_depth;
          TcValue value = vm.frames[depth].has_return_override ? vm.frames[depth].return_override : returned;
          vm.ip = vm.frames[depth].return_ip;
          if (vm.frames[depth].saved_locals_active) {
            const TcFunction *returning = vm.frames[depth].function;
            if (returning && returning->touched_slots && returning->touched_slot_count > 0) {
              const TcValue *slot_base = vm.saved_locals_pool + depth * vm.chunk->local_count;
              for (uint32_t i = 0; i < returning->touched_slot_count; i++) {
                vm.locals[returning->touched_slots[i]] = slot_base[i];
              }
            } else {
              memcpy(vm.locals, vm.saved_locals_pool + depth * vm.chunk->local_count,
                     vm.chunk->local_count * sizeof(TcValue));
            }
            vm.frames[depth].saved_locals_active = 0;
          }
          if (!push(&vm, value, err)) {
            goto cleanup_fail;
          }
          // CALL_DISCARD: the caller did not want this return value.
          // The flag was stashed at the caller's depth (== `depth`
          // here, after the post-decrement). Clear it so a later
          // non-discard call doesn't reuse the slot.
          if (vm.frames[depth].discard_return) {
            vm.sp--;
            vm.frames[depth].discard_return = 0;
          }
          NEXT();
        }
        *result = pop(&vm);
        goto cleanup_ok;
  }
#undef NEXT
cleanup_ok:
  runtime_array_free(vm.argv);
  free(vm.saved_locals_pool);
  free(vm.locals);
  return 1;
cleanup_fail:
  runtime_array_free(vm.argv);
  free(vm.saved_locals_pool);
  free(vm.locals);
  return 0;
}

int tc_vm_run(const TcChunk *chunk, TcValue *result, TcError *err) {
  return tc_vm_run_args(chunk, 0, NULL, result, err);
}
