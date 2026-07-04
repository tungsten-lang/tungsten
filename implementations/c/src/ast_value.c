#include "tc.h"

#include <stdlib.h>
#include <string.h>

// AST bump arena. Every AST allocation (hashes, arrays, string/symbol
// bytes, hash entry keys, items arrays) bumps from a chunked region.
// tc_ast_free becomes a no-op for arena allocations — the AST lives
// for the bootstrap lifetime, which is seconds. Removes ~4 mallocs
// per AST node in the parse hot path (node_hash was 65% of VM-only
// time before this change).
//
// Realloc-style growth (TcAstHash items, TcAstArray items): bump-alloc
// a new larger buffer, copy from old. Old buffer leaks within the
// arena — fine because the arena is freed wholesale at exit.
#define TC_AST_ARENA_CHUNK_SIZE (1u << 20)  // 1 MiB chunks
typedef struct TcAstArenaChunk {
  struct TcAstArenaChunk *next;
  size_t cap;
  size_t used;
  // data[] must be 16-byte aligned: tc_box_ast packs the arena pointer
  // into a WValue with the low nibble used as a sub-tag, and the post-
  // flip w_as_ptr unboxer masks bits 0-3 to recover the pointer. Without
  // _Alignas(16) the flex array sits at offsetof = 24 (8-aligned) and
  // every ast pointer comes back off-by-8, which manifests as
  // ast.kind reading random memory and ast["key"] returning nil.
  _Alignas(16)
  char data[];
} TcAstArenaChunk;

static TcAstArenaChunk *tc_ast_arena_head = NULL;

static void *tc_ast_arena_alloc(size_t bytes, TcError *err) {
  // Round up to 16-byte alignment so allocations are compatible with the
  // post-flip WValue heap-pointer encoding (low nibble used for the
  // sub-tag — pointers must be 16-byte aligned). Pre-flip this just
  // wastes a few bytes per allocation; the arena chunk is 1 MiB so the
  // overhead is in the noise.
  bytes = (bytes + 15u) & ~(size_t)15u;
  TcAstArenaChunk *chunk = tc_ast_arena_head;
  if (!chunk || chunk->used + bytes > chunk->cap) {
    size_t cap = TC_AST_ARENA_CHUNK_SIZE;
    if (bytes > cap) cap = bytes;
    TcAstArenaChunk *fresh = (TcAstArenaChunk *)malloc(sizeof(TcAstArenaChunk) + cap);
    if (!fresh) {
      tc_error_set(err, "AST arena chunk allocation failed");
      return NULL;
    }
    fresh->next = tc_ast_arena_head;
    fresh->cap = cap;
    fresh->used = 0;
    tc_ast_arena_head = fresh;
    chunk = fresh;
  }
  void *p = chunk->data + chunk->used;
  chunk->used += bytes;
  return p;
}

static void *tc_ast_arena_calloc(size_t bytes, TcError *err) {
  void *p = tc_ast_arena_alloc(bytes, err);
  if (p) memset(p, 0, (bytes + 15u) & ~(size_t)15u);
  return p;
}

TcValue tc_box_ast(TcAstValue ast, TcError *err) {
  // Heap-allocate (in the AST arena) a copy of `ast` and tag the pointer
  // with TC_TAG_AST so post-flip TcValue can store it in 8 bytes. The
  // arena chunk's `data` flex array is _Alignas(16), so every alloc
  // returns a 16-byte aligned pointer — the low nibble is free for the
  // sub-tag and w_as_ptr's mask roundtrips cleanly.
  TcAstValue *copy = (TcAstValue *)tc_ast_arena_alloc(sizeof(TcAstValue), err);
  if (!copy) return W_NIL;
  *copy = ast;
  return w_box_ptr(copy, TC_TAG_AST);
}

TcAstValue tc_ast_nil(void) {
  return (TcAstValue){.kind = TC_AST_NIL};
}

TcAstValue tc_ast_bool(int value) {
  return (TcAstValue){.kind = TC_AST_BOOL, .as.boolean = value != 0};
}

TcAstValue tc_ast_int(int64_t value) {
  return (TcAstValue){.kind = TC_AST_INT, .as.integer = value};
}

static char *copy_bytes(const char *bytes, size_t len, TcError *err) {
  char *copy = (char *)tc_ast_arena_alloc(len + 1, err);
  if (!copy) return NULL;
  memcpy(copy, bytes, len);
  copy[len] = '\0';
  return copy;
}

TcAstValue tc_ast_string_copy(const char *bytes, size_t len, TcError *err) {
  char *copy = copy_bytes(bytes, len, err);
  if (!copy) return tc_ast_nil();
  return (TcAstValue){.kind = TC_AST_STRING, .as.string = {.bytes = copy, .len = len}};
}

TcAstValue tc_ast_symbol_copy(const char *bytes, size_t len, TcError *err) {
  // Intern through the global pool. Lets the runtime VM treat sym==sym
  // as a pointer compare with no memcmp fallback — `node[:type] ==
  // :var` becomes a 1-cycle check.
  const char *interned = tc_intern(bytes, len);
  if (!interned) {
    tc_error_set(err, "symbol intern failed");
    return tc_ast_nil();
  }
  return (TcAstValue){.kind = TC_AST_SYMBOL, .as.string = {.bytes = interned, .len = len}};
}

TcAstValue tc_ast_array_new(TcError *err) {
  TcAstArray *array = (TcAstArray *)tc_ast_arena_calloc(sizeof(TcAstArray), err);
  if (!array) return tc_ast_nil();
  return (TcAstValue){.kind = TC_AST_ARRAY, .as.array = array};
}

TcAstValue tc_ast_hash_new(TcError *err) {
  TcAstHash *hash = (TcAstHash *)tc_ast_arena_calloc(sizeof(TcAstHash), err);
  if (!hash) return tc_ast_nil();
  return (TcAstValue){.kind = TC_AST_HASH, .as.hash = hash};
}

TcAstValue tc_ast_clone(TcAstValue value, TcError *err) {
  switch (value.kind) {
    case TC_AST_NIL:
      return tc_ast_nil();
    case TC_AST_BOOL:
      return tc_ast_bool(value.as.boolean);
    case TC_AST_INT:
      return tc_ast_int(value.as.integer);
    case TC_AST_STRING:
      return tc_ast_string_copy(value.as.string.bytes, value.as.string.len, err);
    case TC_AST_SYMBOL:
      return tc_ast_symbol_copy(value.as.string.bytes, value.as.string.len, err);
    case TC_AST_ARRAY: {
      TcAstValue out = tc_ast_array_new(err);
      if (out.kind != TC_AST_ARRAY) return tc_ast_nil();
      if (!value.as.array) return out;
      for (size_t i = 0; i < value.as.array->count; i++) {
        TcAstValue item = tc_ast_clone(value.as.array->items[i], err);
        if (item.kind == TC_AST_NIL && err && err->message && value.as.array->items[i].kind != TC_AST_NIL) {
          tc_ast_free(out);
          return tc_ast_nil();
        }
        if (!tc_ast_array_push(out, item, err)) {
          tc_ast_free(item);
          tc_ast_free(out);
          return tc_ast_nil();
        }
      }
      return out;
    }
    case TC_AST_HASH: {
      TcAstValue out = tc_ast_hash_new(err);
      if (out.kind != TC_AST_HASH) return tc_ast_nil();
      if (!value.as.hash) return out;
      for (size_t i = 0; i < value.as.hash->count; i++) {
        TcAstValue item = tc_ast_clone(value.as.hash->items[i].value, err);
        if (item.kind == TC_AST_NIL && err && err->message && value.as.hash->items[i].value.kind != TC_AST_NIL) {
          tc_ast_free(out);
          return tc_ast_nil();
        }
        if (!tc_ast_hash_set(out, value.as.hash->items[i].key, item, err)) {
          tc_ast_free(item);
          tc_ast_free(out);
          return tc_ast_nil();
        }
      }
      return out;
    }
  }
  return tc_ast_nil();
}

int tc_ast_array_push(TcAstValue array, TcAstValue value, TcError *err) {
  if (array.kind != TC_AST_ARRAY) {
    tc_error_set(err, "AST value is not an array");
    return 0;
  }
  TcAstArray *a = array.as.array;
  if (a->count == a->cap) {
    size_t cap = a->cap ? a->cap * 2 : 8;
    TcAstValue *items = (TcAstValue *)tc_ast_arena_alloc(cap * sizeof(TcAstValue), err);
    if (!items) return 0;
    if (a->count) memcpy(items, a->items, a->count * sizeof(TcAstValue));
    a->items = items;
    a->cap = cap;
  }
  a->items[a->count++] = value;
  return 1;
}

int tc_ast_hash_set(TcAstValue hash, const char *key, TcAstValue value, TcError *err) {
  if (hash.kind != TC_AST_HASH) {
    tc_error_set(err, "AST value is not a hash");
    return 0;
  }
  TcAstHash *h = hash.as.hash;
  for (size_t i = 0; i < h->count; i++) {
    if (strcmp(h->items[i].key, key) == 0) {
      h->items[i].value = value;  // arena: old value leaks within arena
      return 1;
    }
  }
  if (h->count == h->cap) {
    size_t cap = h->cap ? h->cap * 2 : 8;
    TcAstEntry *items = (TcAstEntry *)tc_ast_arena_alloc(cap * sizeof(TcAstEntry), err);
    if (!items) return 0;
    if (h->count) memcpy(items, h->items, h->count * sizeof(TcAstEntry));
    h->items = items;
    h->cap = cap;
  }
  size_t key_len = strlen(key);
  char *key_copy = copy_bytes(key, key_len, err);
  if (!key_copy) return 0;
  h->items[h->count++] = (TcAstEntry){.key = key_copy, .value = value};
  return 1;
}

// AST values now live in a bump arena (see top of file). Per-node free
// is a no-op; the arena is owned for the bootstrap lifetime and freed
// (or not) at process exit. Removes ~4 mallocs + 4 frees per AST node.
void tc_ast_free(TcAstValue value) {
  (void)value;
}

static void print_escaped(const char *bytes, size_t len, FILE *out) {
  fputc('"', out);
  for (size_t i = 0; i < len; i++) {
    unsigned char c = (unsigned char)bytes[i];
    switch (c) {
      case '\\': fputs("\\\\", out); break;
      case '"': fputs("\\\"", out); break;
      case '\n': fputs("\\n", out); break;
      case '\r': fputs("\\r", out); break;
      case '\t': fputs("\\t", out); break;
      default:
        if (c < 32) fprintf(out, "\\u%04x", c);
        else fputc(c, out);
        break;
    }
  }
  fputc('"', out);
}

void tc_ast_print(TcAstValue value, FILE *out) {
  switch (value.kind) {
    case TC_AST_NIL:
      fputs("nil", out);
      break;
    case TC_AST_BOOL:
      fputs(value.as.boolean ? "true" : "false", out);
      break;
    case TC_AST_INT:
      fprintf(out, "%lld", (long long)value.as.integer);
      break;
    case TC_AST_STRING:
      print_escaped(value.as.string.bytes, value.as.string.len, out);
      break;
    case TC_AST_SYMBOL:
      fputc(':', out);
      fwrite(value.as.string.bytes, 1, value.as.string.len, out);
      break;
    case TC_AST_ARRAY:
      fputc('[', out);
      for (size_t i = 0; i < value.as.array->count; i++) {
        if (i) fputs(", ", out);
        tc_ast_print(value.as.array->items[i], out);
      }
      fputc(']', out);
      break;
    case TC_AST_HASH:
      fputc('{', out);
      for (size_t i = 0; i < value.as.hash->count; i++) {
        if (i) fputs(", ", out);
        fputc(':', out);
        fputs(value.as.hash->items[i].key, out);
        fputs(" => ", out);
        tc_ast_print(value.as.hash->items[i].value, out);
      }
      fputc('}', out);
      break;
  }
}
