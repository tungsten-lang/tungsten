#include "tc.h"

#include <stdlib.h>
#include <string.h>

void tc_chunk_init(TcChunk *chunk) {
  memset(chunk, 0, sizeof(*chunk));
  chunk->self_slot_cache = -2;  // "not yet computed"
}

void tc_chunk_free(TcChunk *chunk) {
  if (!chunk) return;
  free(chunk->code);
  for (size_t i = 0; i < chunk->const_count; i++) {
    if (tc_kind(chunk->consts[i]) == TC_VAL_STRING || tc_kind(chunk->consts[i]) == TC_VAL_SYMBOL) tc_heap_string_release(tc_str_bytes_only(chunk->consts[i]));
    else if (tc_kind(chunk->consts[i]) == TC_VAL_ARRAY) {
      free(tc_as_array(chunk->consts[i])->slots);
      free(tc_as_array(chunk->consts[i]));
    }
  }
  free(chunk->consts);
  free(chunk->const_dedup_index);
  for (size_t i = 0; i < chunk->local_count; i++) free(chunk->locals[i].name);
  free(chunk->locals);
  for (size_t i = 0; i < chunk->function_count; i++) {
    free(chunk->functions[i].name);
    free(chunk->functions[i].param_slots);
    free(chunk->functions[i].touched_slots);
    for (uint32_t j = 0; j < chunk->functions[i].param_type_count; j++) {
      free(chunk->functions[i].param_type_names[j]);
    }
    free(chunk->functions[i].param_type_names);
  }
  free(chunk->functions);
  for (size_t i = 0; i < chunk->class_super_count; i++) {
    free(chunk->class_supers[i].name);
    free(chunk->class_supers[i].super);
  }
  free(chunk->class_supers);
  free(chunk->fn_for_const);
  free(chunk->ctor_fn_for_const);
  free(chunk->ctor_is_slab);
  free(chunk->method_ic_class);
  free(chunk->method_ic_class_len);
  free(chunk->method_ic_fn);
  free(chunk->astnode_fn_cache);
  free(chunk->astnode_fn_state);
  for (size_t i = 0; i < chunk->case_table_count; i++) {
    // keys point into the global intern table; do not free.
    free(chunk->case_tables[i].keys);
    free(chunk->case_tables[i].targets);
  }
  free(chunk->case_tables);
  // slab_class_names entries are interned bytes (owned by tc_intern); don't free them
  free(chunk->slab_class_names);
  memset(chunk, 0, sizeof(*chunk));
}

int tc_chunk_register_slab_class(TcChunk *chunk, const char *name, size_t name_len, TcError *err) {
  // Intern the class name so we can compare via pointer equality at
  // .new dispatch time (vm_call_body.inc dispatches by receiver name).
  const char *interned = tc_intern(name, name_len);
  if (!interned) {
    tc_error_set(err, "slab class name interning failed");
    return 0;
  }
  for (size_t i = 0; i < chunk->slab_class_count; i++) {
    if (chunk->slab_class_names[i] == interned) return 1;  // already registered
  }
  if (chunk->slab_class_count == chunk->slab_class_cap) {
    size_t cap = chunk->slab_class_cap ? chunk->slab_class_cap * 2 : 32;
    const char **next = (const char **)realloc(chunk->slab_class_names, cap * sizeof(*next));
    if (!next) {
      tc_error_set(err, "slab class table allocation failed");
      return 0;
    }
    chunk->slab_class_names = next;
    chunk->slab_class_cap = cap;
  }
  chunk->slab_class_names[chunk->slab_class_count++] = interned;
  return 1;
}

int tc_chunk_is_slab_class(const TcChunk *chunk, const char *name, size_t name_len) {
  // Caller passes the receiver name; intern-compare against the
  // registered slab classes. Linear scan is fine — there's a bounded
  // set (~100 in compiler) and this only fires on .new call sites.
  if (chunk->slab_class_count == 0) return 0;
  const char *interned = tc_intern(name, name_len);
  if (!interned) return 0;
  for (size_t i = 0; i < chunk->slab_class_count; i++) {
    if (chunk->slab_class_names[i] == interned) return 1;
  }
  return 0;
}

// ── Typed-overload support ───────────────────────────────────────────────
// Mirrors the self-hosted compiler's typed operator-overload dispatch
// (compiler/lib/lowering/definitions.w, synthesize_overload_dispatchers):
// same-name / same-arity methods that differ only in a declared param
// type are selected at call time by matching the argument values against
// the declared types, most specific first, falling back to the historic
// first-name-match when no typed candidate matches.

static const TcClassSuper *find_class_super(const TcChunk *chunk, const char *name, size_t name_len) {
  for (size_t i = 0; i < chunk->class_super_count; i++) {
    if (chunk->class_supers[i].name_len == name_len &&
        memcmp(chunk->class_supers[i].name, name, name_len) == 0) {
      return &chunk->class_supers[i];
    }
  }
  return NULL;
}

int tc_chunk_has_class(const TcChunk *chunk, const char *name, size_t name_len) {
  return find_class_super(chunk, name, name_len) != NULL;
}

int tc_chunk_register_class_super(TcChunk *chunk, const char *name, size_t name_len,
                                  const char *super, size_t super_len, TcError *err) {
  char *super_copy = NULL;
  if (super && super_len > 0) {
    super_copy = (char *)malloc(super_len + 1);
    if (!super_copy) {
      tc_error_set(err, "class superclass allocation failed");
      return 0;
    }
    memcpy(super_copy, super, super_len);
    super_copy[super_len] = '\0';
  }
  // Re-registration (a class compiled again) updates in place.
  for (size_t i = 0; i < chunk->class_super_count; i++) {
    if (chunk->class_supers[i].name_len == name_len &&
        memcmp(chunk->class_supers[i].name, name, name_len) == 0) {
      free(chunk->class_supers[i].super);
      chunk->class_supers[i].super = super_copy;
      chunk->class_supers[i].super_len = super_copy ? super_len : 0;
      chunk->bigint_scope_state = 0;
      return 1;
    }
  }
  if (chunk->class_super_count == chunk->class_super_cap) {
    size_t cap = chunk->class_super_cap ? chunk->class_super_cap * 2 : 32;
    TcClassSuper *next = (TcClassSuper *)realloc(chunk->class_supers, cap * sizeof(*next));
    if (!next) {
      free(super_copy);
      tc_error_set(err, "class superclass table allocation failed");
      return 0;
    }
    chunk->class_supers = next;
    chunk->class_super_cap = cap;
  }
  char *name_copy = (char *)malloc(name_len + 1);
  if (!name_copy) {
    free(super_copy);
    tc_error_set(err, "class name allocation failed");
    return 0;
  }
  memcpy(name_copy, name, name_len);
  name_copy[name_len] = '\0';
  chunk->class_supers[chunk->class_super_count++] = (TcClassSuper){
      .name = name_copy,
      .name_len = name_len,
      .super = super_copy,
      .super_len = super_copy ? super_len : 0,
  };
  chunk->bigint_scope_state = 0;  // invalidate the lazy BigInt-scope cache
  return 1;
}

static int type_name_is(const char *name, size_t len, const char *lit) {
  size_t lit_len = strlen(lit);
  return len == lit_len && memcmp(name, lit, lit_len) == 0;
}

// Walk `start`'s class chain (the class itself, then declared
// superclasses) looking for `target`. A chain link with no table entry is
// unresolvable: per the self-hosted rule (definitions.w
// overload_type_is_ancestor?), it matches only when the target is
// "Number", the universal numeric base. Depth-capped like the
// self-hosted guard.
static int class_chain_matches(const TcChunk *chunk, const char *start, size_t start_len,
                               const char *target, size_t target_len) {
  const char *cur = start;
  size_t cur_len = start_len;
  for (int guard = 0; guard < 64; guard++) {
    if (cur_len == target_len && memcmp(cur, target, target_len) == 0) return 1;
    const TcClassSuper *entry = find_class_super(chunk, cur, cur_len);
    if (!entry) return type_name_is(target, target_len, "Number");
    if (!entry->super) return 0;
    cur = entry->super;
    cur_len = entry->super_len;
  }
  return 0;
}

// Does any compiled class live in a BigInt hierarchy (named BigInt or
// with a superclass chain reaching it)? Cached on the chunk; the cast
// mirrors tc_chunk_find_function's const-away pattern.
static int chunk_has_bigint_class(const TcChunk *chunk) {
  TcChunk *m = (TcChunk *)chunk;
  if (m->bigint_scope_state == 0) {
    m->bigint_scope_state = 1;
    for (size_t i = 0; i < m->class_super_count; i++) {
      if (class_chain_matches(chunk, m->class_supers[i].name, m->class_supers[i].name_len,
                              "BigInt", 6)) {
        m->bigint_scope_state = 2;
        break;
      }
    }
  }
  return m->bigint_scope_state == 2;
}

// Mirror of vm.c's value_is_int: inline i48 ints and TC_TAG_HEAP_INT
// heap spillover boxes both count.
static int overload_value_is_int(TcValue v) {
  if (w_is_int(v)) return 1;
  return (v & W_TAG_MASK) == 0 && (v & 0xFU) == TC_TAG_HEAP_INT;
}

// Does runtime value `v` satisfy declared param type `t`? Exact-tag
// mirror of the self-hosted `is_a?` overload gates for the builtin
// kinds; TC_VAL_OBJECT walks the compiled superclass table.
static int typed_value_matches(const TcChunk *chunk, TcValue v, const char *t, size_t tlen) {
  // "BigInt" outside any compiled BigInt class hierarchy is the exact-tag
  // rule: an integer that does not fit the inline i48 payload. With a
  // compiled BigInt hierarchy present, ancestry semantics below apply.
  if (type_name_is(t, tlen, "BigInt") && !chunk_has_bigint_class(chunk)) {
    return overload_value_is_int(v) && !w_is_int(v);
  }
  switch (tc_kind(v)) {
    case TC_VAL_INT:
      if (type_name_is(t, tlen, "Int") || type_name_is(t, tlen, "Integer") ||
          type_name_is(t, tlen, "Real") || type_name_is(t, tlen, "Number")) {
        return 1;
      }
      return !w_is_int(v) && type_name_is(t, tlen, "BigInt");
    case TC_VAL_STRING: return type_name_is(t, tlen, "String");
    case TC_VAL_SYMBOL: return type_name_is(t, tlen, "Symbol");
    case TC_VAL_ARRAY:  return type_name_is(t, tlen, "Array");
    case TC_VAL_HASH:   return type_name_is(t, tlen, "Hash");
    case TC_VAL_OBJECT: {
      TcRuntimeObject *object = tc_as_object(v);
      if (!object || !object->class_name) return 0;
      return class_chain_matches(chunk, object->class_name, object->class_name_len, t, tlen);
    }
    case TC_VAL_WVALUE:
      // tc_kind routes bools and doubles here; everything pointer-tagged
      // was already peeled off above, so w_is_double is alias-safe.
      if (v == W_TRUE || v == W_FALSE) return type_name_is(t, tlen, "Boolean");
      if (w_is_double(v)) {
        return type_name_is(t, tlen, "Float") || type_name_is(t, tlen, "Real") ||
               type_name_is(t, tlen, "Number");
      }
      return 0;
    default: return 0;
  }
}

// subtype(a, b): a == b, or b is the universal "Number" base, or a's
// compiled superclass chain reaches b, or one of the hardcoded numeric
// tower edges (so ordering works without core classes compiled):
// BigInt < Int/Integer/Real/Number; Int/Integer/Float/Decimal <
// Real/Number.
static int type_is_subtype(const TcChunk *chunk, const char *a, size_t alen,
                           const char *b, size_t blen) {
  if (alen == blen && memcmp(a, b, alen) == 0) return 1;
  if (type_name_is(b, blen, "Number")) return 1;
  const TcClassSuper *entry = find_class_super(chunk, a, alen);
  if (entry && class_chain_matches(chunk, a, alen, b, blen)) return 1;
  if (type_name_is(a, alen, "BigInt")) {
    return type_name_is(b, blen, "Int") || type_name_is(b, blen, "Integer") ||
           type_name_is(b, blen, "Real");
  }
  if (type_name_is(a, alen, "Int") || type_name_is(a, alen, "Integer") ||
      type_name_is(a, alen, "Float") || type_name_is(a, alen, "Decimal")) {
    return type_name_is(b, blen, "Real");
  }
  return 0;
}

// Candidate A beats B when every declared type of A is a subtype of B's
// corresponding type.
static int overload_beats(const TcChunk *chunk, const TcFunction *a, const TcFunction *b) {
  for (uint32_t i = 0; i < a->param_type_count; i++) {
    if (!type_is_subtype(chunk, a->param_type_names[i], strlen(a->param_type_names[i]),
                         b->param_type_names[i], strlen(b->param_type_names[i]))) {
      return 0;
    }
  }
  return 1;
}

TcFunction *tc_select_overload(const TcChunk *chunk, const TcFunction *resolved,
                               const TcValue *args, uint32_t argc) {
  TcFunction *best = NULL;
  for (size_t i = 0; i < chunk->function_count; i++) {
    TcFunction *f = &((TcChunk *)chunk)->functions[i];
    if (f->name_len != resolved->name_len ||
        memcmp(f->name, resolved->name, resolved->name_len) != 0) {
      continue;
    }
    if (f->arity != argc || f->param_type_count != argc || !f->param_type_names) continue;
    int matches = 1;
    for (uint32_t a = 0; a < argc && matches; a++) {
      matches = typed_value_matches(chunk, args[a], f->param_type_names[a],
                                    strlen(f->param_type_names[a]));
    }
    if (!matches) continue;
    // Most-specific wins; first-declared wins ties (strict replacement).
    if (!best || (overload_beats(chunk, f, best) && !overload_beats(chunk, best, f))) best = f;
  }
  if (best) return best;
  // No typed candidate: exactly today's behavior — first name match.
  return tc_chunk_find_function(chunk, resolved->name, resolved->name_len);
}

int tc_chunk_alloc_case_table(TcChunk *chunk, uint32_t count, TcError *err) {
  if (chunk->case_table_count == chunk->case_table_cap) {
    size_t cap = chunk->case_table_cap ? chunk->case_table_cap * 2 : 8;
    TcCaseTable *t = (TcCaseTable *)realloc(chunk->case_tables, cap * sizeof(TcCaseTable));
    if (!t) {
      tc_error_set(err, "case table allocation failed");
      return -1;
    }
    chunk->case_tables = t;
    chunk->case_table_cap = cap;
  }
  TcCaseTable *table = &chunk->case_tables[chunk->case_table_count];
  table->keys = (const char **)calloc(count, sizeof(const char *));
  table->targets = (uint32_t *)calloc(count, sizeof(uint32_t));
  if ((!table->keys || !table->targets) && count > 0) {
    free(table->keys);
    free(table->targets);
    tc_error_set(err, "case table entry allocation failed");
    return -1;
  }
  table->count = count;
  table->default_target = 0;
  return (int)chunk->case_table_count++;
}

static int reserve_code(TcChunk *chunk, size_t extra, TcError *err) {
  if (chunk->count + extra <= chunk->cap) return 1;
  size_t cap = chunk->cap ? chunk->cap * 2 : 256;
  while (cap < chunk->count + extra) cap *= 2;
  uint8_t *code = (uint8_t *)realloc(chunk->code, cap);
  if (!code) {
    tc_error_set(err, "bytecode allocation failed");
    return 0;
  }
  chunk->code = code;
  chunk->cap = cap;
  return 1;
}

// FNV-1a over (kind, bytes, len). Used as a stable hash for the dedup
// index — same bytes+len+kind always hashes the same.
static uint64_t const_dedup_hash(int kind, const char *bytes, size_t len) {
  uint64_t h = 0xcbf29ce484222325ULL;
  h ^= (uint64_t)kind;
  h *= 0x100000001b3ULL;
  for (size_t i = 0; i < len; i++) {
    h ^= (uint8_t)bytes[i];
    h *= 0x100000001b3ULL;
  }
  return h;
}

// Open-addressing linear probe. Returns 1-based const_id of an existing
// matching string/symbol, or 0 if none. cap must be power of two.
static uint32_t const_dedup_lookup(const TcChunk *chunk, int kind, const char *bytes,
                                   size_t len, size_t *slot_out) {
  size_t cap = chunk->const_dedup_cap;
  if (cap == 0) {
    if (slot_out) *slot_out = 0;
    return 0;
  }
  size_t mask = cap - 1;
  size_t slot = (size_t)const_dedup_hash(kind, bytes, len) & mask;
  while (1) {
    uint32_t entry = chunk->const_dedup_index[slot];
    if (entry == 0) {
      if (slot_out) *slot_out = slot;
      return 0;
    }
    TcValue existing = chunk->consts[entry - 1];
    if ((int)tc_kind(existing) == kind && tc_str_len(existing) == len &&
        memcmp(tc_str_bytes_only(existing), bytes, len) == 0) {
      if (slot_out) *slot_out = slot;
      return entry;
    }
    slot = (slot + 1) & mask;
  }
}

static int const_dedup_grow(TcChunk *chunk, TcError *err) {
  size_t old_cap = chunk->const_dedup_cap;
  size_t new_cap = old_cap == 0 ? 64 : old_cap * 2;
  uint32_t *new_index = (uint32_t *)calloc(new_cap, sizeof(uint32_t));
  if (!new_index) {
    tc_error_set(err, "const dedup index allocation failed");
    return 0;
  }
  uint32_t *old_index = chunk->const_dedup_index;
  chunk->const_dedup_index = new_index;
  chunk->const_dedup_cap = new_cap;
  if (old_index) {
    size_t mask = new_cap - 1;
    for (size_t i = 0; i < old_cap; i++) {
      uint32_t entry = old_index[i];
      if (entry == 0) continue;
      TcValue v = chunk->consts[entry - 1];
      size_t slot = (size_t)const_dedup_hash((int)tc_kind(v), tc_str_bytes_only(v), tc_str_len(v)) & mask;
      while (chunk->const_dedup_index[slot]) slot = (slot + 1) & mask;
      chunk->const_dedup_index[slot] = entry;
    }
    free(old_index);
  }
  return 1;
}

int tc_chunk_add_const(TcChunk *chunk, TcValue value, TcError *err) {
  // String/symbol consts are deduped by content so every literal site
  // shares one bytes buffer. Lets value_equal hit ptr-equality on
  // every literal-vs-literal compare. The dedup uses an open-addressing
  // hash table so it's O(1) amortized; a previous attempt with linear
  // scan added more compile time than it saved at runtime.
  if (tc_kind(value) == TC_VAL_STRING || tc_kind(value) == TC_VAL_SYMBOL) {
    // Symbols go through the global intern pool so every TC_VAL_SYMBOL
    // produced anywhere — chunk consts, AST values, runtime conversions —
    // shares one canonical bytes buffer. Strings stay as-is here (the
    // chunk-local dedup index still merges duplicate string literals).
    if (tc_kind(value) == TC_VAL_SYMBOL) {
      const char *interned = tc_intern(tc_str_bytes_only(value), tc_str_len(value));
      if (!interned) {
        tc_error_set(err, "symbol intern failed");
        return -1;
      }
      if (tc_managed(value) && interned != tc_str_bytes_only(value)) {
        tc_heap_string_release(tc_str_bytes_only(value));
      }
      // Replace the value with one that owns the interned bytes (managed=0).
      // Post-flip the (managed) flag moves into the TcHeapString header,
      // so this rewrite naturally drops it.
      value = tc_box_symbol_bytes(interned, tc_str_len(value), 0);
    }
    if (chunk->const_dedup_cap == 0 ||
        chunk->const_count * 2 >= chunk->const_dedup_cap) {
      if (!const_dedup_grow(chunk, err)) return -1;
    }
    size_t slot;
    uint32_t found = const_dedup_lookup(chunk, (int)tc_kind(value), tc_str_bytes_only(value), tc_str_len(value), &slot);
    if (found) {
      // Caller's bytes buffer is now redundant — free if it owned the copy.
      if (tc_managed(value)) tc_heap_string_release(tc_str_bytes_only(value));
      return (int)(found - 1);
    }
    if (chunk->const_count == chunk->const_cap) {
      size_t cap = chunk->const_cap ? chunk->const_cap * 2 : 32;
      TcValue *consts = (TcValue *)realloc(chunk->consts, cap * sizeof(TcValue));
      if (!consts) {
        tc_error_set(err, "constant allocation failed");
        return -1;
      }
      chunk->consts = consts;
      chunk->const_cap = cap;
    }
    int id = (int)chunk->const_count;
    chunk->consts[chunk->const_count++] = value;
    chunk->const_dedup_index[slot] = (uint32_t)(id + 1);
    return id;
  }
  if (chunk->const_count == chunk->const_cap) {
    size_t cap = chunk->const_cap ? chunk->const_cap * 2 : 32;
    TcValue *consts = (TcValue *)realloc(chunk->consts, cap * sizeof(TcValue));
    if (!consts) {
      tc_error_set(err, "constant allocation failed");
      return -1;
    }
    chunk->consts = consts;
    chunk->const_cap = cap;
  }
  chunk->consts[chunk->const_count] = value;
  return (int)chunk->const_count++;
}

int tc_chunk_local(TcChunk *chunk, const char *name, size_t len, TcError *err) {
  // Cached length compare beats the prior strlen-per-entry scan.
  TcLocalName *entries = chunk->locals;
  for (size_t i = 0; i < chunk->local_count; i++) {
    if (entries[i].len == len && memcmp(entries[i].name, name, len) == 0) return (int)i;
  }

  if (chunk->local_count == chunk->local_cap) {
    size_t cap = chunk->local_cap ? chunk->local_cap * 2 : 16;
    TcLocalName *locals = (TcLocalName *)realloc(chunk->locals, cap * sizeof(TcLocalName));
    if (!locals) {
      tc_error_set(err, "local table allocation failed");
      return -1;
    }
    chunk->locals = locals;
    chunk->local_cap = cap;
  }

  char *copy = (char *)malloc(len + 1);
  if (!copy) {
    tc_error_set(err, "local name allocation failed");
    return -1;
  }
  memcpy(copy, name, len);
  copy[len] = '\0';
  chunk->locals[chunk->local_count].name = copy;
  chunk->locals[chunk->local_count].len = len;
  return (int)chunk->local_count++;
}

// Split a raw param-types annotation ("(BigInt)", "(i64 i64)",
// "(Vector, Number)") into owned NUL-terminated name copies. Parens,
// whitespace, and commas separate; everything else is type-name bytes.
static int split_param_types(const char *raw, size_t raw_len, char ***names_out,
                             uint32_t *count_out, TcError *err) {
  char **names = NULL;
  uint32_t count = 0;
  uint32_t cap = 0;
  size_t i = 0;
  while (i < raw_len) {
    char c = raw[i];
    if (c == '(' || c == ')' || c == ',' || c == ' ' || c == '\t' || c == '\n' || c == '\r') {
      i++;
      continue;
    }
    size_t start = i;
    while (i < raw_len && raw[i] != '(' && raw[i] != ')' && raw[i] != ',' &&
           raw[i] != ' ' && raw[i] != '\t' && raw[i] != '\n' && raw[i] != '\r') {
      i++;
    }
    if (count == cap) {
      uint32_t next_cap = cap ? cap * 2 : 4;
      char **next = (char **)realloc(names, next_cap * sizeof(*next));
      if (!next) goto fail;
      names = next;
      cap = next_cap;
    }
    char *copy = (char *)malloc(i - start + 1);
    if (!copy) goto fail;
    memcpy(copy, raw + start, i - start);
    copy[i - start] = '\0';
    names[count++] = copy;
  }
  *names_out = names;
  *count_out = count;
  return 1;
fail:
  for (uint32_t j = 0; j < count; j++) free(names[j]);
  free(names);
  tc_error_set(err, "param type list allocation failed");
  return 0;
}

int tc_chunk_add_function(TcChunk *chunk, const char *name, size_t name_len, uint32_t entry,
                          const uint32_t *param_slots, uint32_t arity,
                          const char *param_types, size_t param_types_len, TcError *err) {
  if (chunk->function_count == chunk->function_cap) {
    size_t cap = chunk->function_cap ? chunk->function_cap * 2 : 16;
    TcFunction *functions = (TcFunction *)realloc(chunk->functions, cap * sizeof(TcFunction));
    if (!functions) {
      tc_error_set(err, "function table allocation failed");
      return 0;
    }
    chunk->functions = functions;
    chunk->function_cap = cap;
  }

  char *name_copy = (char *)malloc(name_len + 1);
  if (!name_copy) {
    tc_error_set(err, "function name allocation failed");
    return 0;
  }
  memcpy(name_copy, name, name_len);
  name_copy[name_len] = '\0';

  uint32_t *slots = NULL;
  if (arity > 0) {
    slots = (uint32_t *)malloc((size_t)arity * sizeof(uint32_t));
    if (!slots) {
      free(name_copy);
      tc_error_set(err, "function param allocation failed");
      return 0;
    }
    memcpy(slots, param_slots, (size_t)arity * sizeof(uint32_t));
  }

  char **type_names = NULL;
  uint32_t type_count = 0;
  if (param_types && param_types_len > 0 &&
      !split_param_types(param_types, param_types_len, &type_names, &type_count, err)) {
    free(name_copy);
    free(slots);
    return 0;
  }

  chunk->functions[chunk->function_count++] = (TcFunction){
      .name = name_copy,
      .name_len = name_len,
      .entry = entry,
      .arity = arity,
      .param_slots = slots,
      .touched_slots = NULL,
      .touched_slot_count = 0,
      .touched_slots_analyzed = 0,
      .param_type_names = type_names,
      .param_type_count = type_count,
      .overloaded = 0,
  };

  // Overload-group detection: a redefinition of an existing full name
  // marks both entries so dispatch knows to run typed selection. Any
  // earlier duplicates were already flagged when the second was added,
  // so flagging the first match plus the new entry keeps the whole
  // group marked. Linear scan is compile-time-only and bounded by the
  // ~1,400-function bootstrap table.
  TcFunction *added = &chunk->functions[chunk->function_count - 1];
  for (size_t i = 0; i + 1 < chunk->function_count; i++) {
    if (chunk->functions[i].name_len == name_len &&
        memcmp(chunk->functions[i].name, name, name_len) == 0) {
      chunk->functions[i].overloaded = 1;
      added->overloaded = 1;
      break;
    }
  }
  return 1;
}

// Decode a single bytecode instruction's length so we can advance over
// instructions without executing them. Mirrors the dispatch in vm.c.
// Used by tc_chunk_compute_touched.
static size_t opcode_size(uint8_t op) {
  switch (op) {
    case TC_OP_CONST: return 5;          // op + u32 const id
    case TC_OP_LOAD_LOCAL: return 5;     // op + u32 slot
    case TC_OP_STORE_LOCAL: return 5;    // op + u32 slot
    case TC_OP_JUMP: return 5;           // op + u32 target
    case TC_OP_JUMP_IF_FALSE: return 5;  // op + u32 target
    case TC_OP_CALL:
    case TC_OP_CALL_DISCARD: return 13;  // op + u32 name_id + u32 argc + u32 has_recv
    case TC_OP_ARRAY: return 5;          // op + u32 count
    case TC_OP_HASH: return 5;           // op + u32 count
    case TC_OP_EQ_CONST_BR: return 9;    // op + u32 const_id + u32 jump_target
    case TC_OP_INDEX_LL: return 9;       // op + u32 recv_slot + u32 idx_slot
    case TC_OP_SIZE_OF_LOCAL: return 5;  // op + u32 slot
    case TC_OP_LOAD_EQ_CONST_BR: return 13; // op + u32 slot + u32 const_id + u32 target
    case TC_OP_CASE_SYM_LINEAR: return 5; // op + u32 table_id
    case TC_OP_IVAR_GET:                 // op + u32 name_id
    case TC_OP_IVAR_SET:                 // op + u32 name_id
    case TC_OP_CVAR_GET:                 // op + u32 name_id
    case TC_OP_CVAR_SET: return 5;       // op + u32 name_id
    default: return 1;                   // single-byte ops (ADD/SUB/.../RETURN/POP/NOP/TYPED_ARRAY/CASE_MATCH/...)
  }
}

void tc_chunk_compute_touched(TcChunk *chunk) {
  // Sort functions by entry so we can bound each fn's body by the next fn's
  // entry (or chunk end). Uses an index array — TcFunction itself is left
  // in place because callers / find_function may already hold pointers.
  uint32_t fn_count = (uint32_t)chunk->function_count;
  if (fn_count == 0) return;
  uint32_t *order = (uint32_t *)malloc(fn_count * sizeof(uint32_t));
  if (!order) return;
  for (uint32_t i = 0; i < fn_count; i++) order[i] = i;
  // Simple insertion sort by entry.
  for (uint32_t i = 1; i < fn_count; i++) {
    uint32_t j = i;
    while (j > 0 && chunk->functions[order[j - 1]].entry > chunk->functions[order[j]].entry) {
      uint32_t tmp = order[j - 1];
      order[j - 1] = order[j];
      order[j] = tmp;
      j--;
    }
  }

  // Scratch bitmap to dedupe touched slots per fn.
  uint8_t *bitmap = (uint8_t *)calloc((chunk->local_count + 7) / 8 + 1, 1);
  if (!bitmap) {
    free(order);
    return;
  }
  size_t bm_bytes = (chunk->local_count + 7) / 8;
  // All functions share the chunk's local-name table, so resolve the
  // implicit method receiver slot once rather than scanning for every fn.
  int self_slot = -1;
  for (size_t i = 0; i < chunk->local_count; i++) {
    if (chunk->locals[i].len == 4 && memcmp(chunk->locals[i].name, "self", 4) == 0) {
      self_slot = (int)i;
      break;
    }
  }

  for (uint32_t k = 0; k < fn_count; k++) {
    TcFunction *fn = &chunk->functions[order[k]];
    uint32_t end = (k + 1 < fn_count) ? chunk->functions[order[k + 1]].entry : (uint32_t)chunk->count;
    if (end < fn->entry) end = fn->entry;
    memset(bitmap, 0, bm_bytes);

    // Collect store-target slot ids by walking the body.
    size_t ip = fn->entry;
    while (ip < end) {
      uint8_t op = chunk->code[ip];
      if (op == TC_OP_STORE_LOCAL) {
        uint32_t slot = (uint32_t)chunk->code[ip + 1] | ((uint32_t)chunk->code[ip + 2] << 8) |
                        ((uint32_t)chunk->code[ip + 3] << 16) | ((uint32_t)chunk->code[ip + 4] << 24);
        if (slot < chunk->local_count) bitmap[slot >> 3] |= (uint8_t)(1u << (slot & 7));
      }
      ip += opcode_size(op);
      if (ip == 0) break;  // paranoia
    }

    // Add params.
    for (uint32_t i = 0; i < fn->arity; i++) {
      uint32_t s = fn->param_slots[i];
      if (s < chunk->local_count) bitmap[s >> 3] |= (uint8_t)(1u << (s & 7));
    }
    // Add `self` slot — methods read it implicitly even if they never STORE.
    if (self_slot >= 0) bitmap[self_slot >> 3] |= (uint8_t)(1u << (self_slot & 7));

    // Materialize into fn->touched_slots, sorted ascending for predictable
    // memory access during the per-call save loop.
    uint32_t count = 0;
    for (uint32_t s = 0; s < (uint32_t)chunk->local_count; s++) {
      if (bitmap[s >> 3] & (1u << (s & 7))) count++;
    }
    if (count == 0) {
      fn->touched_slots_analyzed = 1;
      continue;
    }
    uint32_t *list = (uint32_t *)malloc(count * sizeof(uint32_t));
    if (!list) continue;  // best-effort; caller can fall back to full save
    uint32_t idx = 0;
    for (uint32_t s = 0; s < (uint32_t)chunk->local_count; s++) {
      if (bitmap[s >> 3] & (1u << (s & 7))) list[idx++] = s;
    }
    // The ascending slot scan already materializes a sorted list.
    fn->touched_slots = list;
    fn->touched_slot_count = count;
    fn->touched_slots_analyzed = 1;
  }

  free(bitmap);
  free(order);

  // CALL fast path: precompute name_id → TcFunction*. Each chunk const
  // that's a SYMBOL gets matched against the function name table; on
  // hit, fn_for_const[id] is the resolved function. The L_CALL handler
  // can then skip the per-call O(N) tc_chunk_find_function walk for
  // receiverless plain calls (the dominant user-fn dispatch shape —
  // `lower_var(ctx, node)` style — in compiler/lib/lowering.w).
  if (chunk->const_count > 0) {
    chunk->fn_for_const = (TcFunction **)calloc(chunk->const_count, sizeof(TcFunction *));
    chunk->ctor_fn_for_const = (TcFunction **)calloc(chunk->const_count, sizeof(TcFunction *));
    chunk->ctor_is_slab = (uint8_t *)calloc(chunk->const_count, sizeof(uint8_t));
    for (size_t i = 0; i < chunk->const_count; i++) {
      TcValue v = chunk->consts[i];
      // Call names are TC_VAL_SYMBOL post-emit_call_op refactor.
      // String consts (literal strings) aren't function names. Skip.
      if (tc_kind(v) != TC_VAL_SYMBOL) continue;
      const char *call_name = tc_str_bytes_only(v);
      size_t call_name_len = tc_str_len(v);
      if (call_name_len > 4 && memcmp(call_name + call_name_len - 4, ".new", 4) == 0) {
        size_t class_len = call_name_len - 4;
        if (chunk->ctor_fn_for_const) {
          chunk->ctor_fn_for_const[i] = tc_chunk_find_method(
              chunk, call_name, class_len, "new", 3);
        }
        if (chunk->ctor_is_slab) {
          chunk->ctor_is_slab[i] = (uint8_t)tc_chunk_is_slab_class(
              chunk, call_name, class_len);
        }
        continue;
      }
      if (!chunk->fn_for_const) continue;
      // Linear walk over functions is O(NxM); only happens once per
      // chunk, so it's fine. Breaking out of the inner loop on first
      // match is the only reason this is even tolerable.
      for (size_t j = 0; j < chunk->function_count; j++) {
        if (chunk->functions[j].name_len == call_name_len &&
            memcmp(chunk->functions[j].name, call_name, call_name_len) == 0) {
          chunk->fn_for_const[i] = &chunk->functions[j];
          break;
        }
      }
    }
    // Implicit-self method dispatch IC. One slot per name_id, populated
    // on first call. Class pointer of NULL means "empty / never hit".
    chunk->method_ic_class = (const char **)calloc(chunk->const_count, sizeof(const char *));
    chunk->method_ic_class_len = (size_t *)calloc(chunk->const_count, sizeof(size_t));
    chunk->method_ic_fn = (TcFunction **)calloc(chunk->const_count, sizeof(TcFunction *));
  }
}

// Peephole rewrite of two hot patterns into superinstructions. Runs
// once after compile, before touched-slot computation.
//
//   CONST id; EQ; JUMP_IF_FALSE target  →  EQ_CONST_BR id target ; NOP ; NOP
//   CALL ...; POP                       →  CALL_DISCARD ...     ; NOP
//
// Constraints: chunk size is fixed (jump targets are absolute), so the
// rewrites pad with NOPs. We only fuse when the inner bytes are not
// jump targets — otherwise a jump landing on EQ would skip the const
// load and read garbage.
//
// Profile (stage 1 self-compile, before fusion): 710 M dispatches, of
// which ~25% are CONST/EQ/JIF case-dispatch and ~8% are CALL/POP.
void tc_chunk_peephole(TcChunk *chunk) {
  if (chunk->count == 0 || !chunk->code) return;

  // Pass 1: collect all jump targets. JIF and JUMP encode absolute byte
  // offsets in the chunk. We need this to avoid fusing a sequence whose
  // interior is a jump target.
  uint8_t *is_target = (uint8_t *)calloc(chunk->count + 1, 1);
  if (!is_target) return;
  // Function entries are also "jump targets" (entered via CALL).
  for (size_t i = 0; i < chunk->function_count; i++) {
    uint32_t e = chunk->functions[i].entry;
    if (e <= chunk->count) is_target[e] = 1;
  }
  size_t ip = 0;
  while (ip < chunk->count) {
    uint8_t op = chunk->code[ip];
    if (op == TC_OP_JUMP || op == TC_OP_JUMP_IF_FALSE) {
      uint32_t t = (uint32_t)chunk->code[ip + 1] | ((uint32_t)chunk->code[ip + 2] << 8) |
                   ((uint32_t)chunk->code[ip + 3] << 16) | ((uint32_t)chunk->code[ip + 4] << 24);
      if (t <= chunk->count) is_target[t] = 1;
    }
    size_t sz = opcode_size(op);
    if (sz == 0) break;
    ip += sz;
  }

  // Pass 2: rewrite. Two iterations because some patterns layer on
  // top of others — Pattern E (LOAD_LOCAL+EQ_CONST_BR) can only see
  // EQ_CONST_BR after Pattern A has run. The second iteration picks
  // up the now-rewritten EQ_CONST_BR sites.
  for (int iter = 0; iter < 2; iter++) {
  ip = 0;
  while (ip < chunk->count) {
    uint8_t op = chunk->code[ip];
    size_t sz = opcode_size(op);

    // Pattern A: CONST id (5) ; EQ (1) ; JUMP_IF_FALSE target (5)  → 11 bytes
    if (op == TC_OP_CONST && ip + 11 <= chunk->count &&
        chunk->code[ip + 5] == TC_OP_EQ &&
        chunk->code[ip + 6] == TC_OP_JUMP_IF_FALSE &&
        !is_target[ip + 5] && !is_target[ip + 6]) {
      uint32_t const_id = (uint32_t)chunk->code[ip + 1] | ((uint32_t)chunk->code[ip + 2] << 8) |
                          ((uint32_t)chunk->code[ip + 3] << 16) | ((uint32_t)chunk->code[ip + 4] << 24);
      uint32_t target = (uint32_t)chunk->code[ip + 7] | ((uint32_t)chunk->code[ip + 8] << 8) |
                        ((uint32_t)chunk->code[ip + 9] << 16) | ((uint32_t)chunk->code[ip + 10] << 24);
      chunk->code[ip] = TC_OP_EQ_CONST_BR;
      chunk->code[ip + 1] = (uint8_t)(const_id);
      chunk->code[ip + 2] = (uint8_t)(const_id >> 8);
      chunk->code[ip + 3] = (uint8_t)(const_id >> 16);
      chunk->code[ip + 4] = (uint8_t)(const_id >> 24);
      chunk->code[ip + 5] = (uint8_t)(target);
      chunk->code[ip + 6] = (uint8_t)(target >> 8);
      chunk->code[ip + 7] = (uint8_t)(target >> 16);
      chunk->code[ip + 8] = (uint8_t)(target >> 24);
      chunk->code[ip + 9] = TC_OP_NOP;
      chunk->code[ip + 10] = TC_OP_NOP;
      ip += 11;
      continue;
    }

    // Pattern B: CALL ... (13) ; POP (1)  → 14 bytes
    if (op == TC_OP_CALL && ip + 14 <= chunk->count &&
        chunk->code[ip + 13] == TC_OP_POP &&
        !is_target[ip + 13]) {
      chunk->code[ip] = TC_OP_CALL_DISCARD;
      chunk->code[ip + 13] = TC_OP_NOP;
      ip += 14;
      continue;
    }

    // Pattern C: LOAD_LOCAL recv (5) ; LOAD_LOCAL idx (5) ; INDEX (1)  → 11 bytes
    // The receiver-LOAD-LOCAL position is the byte we're rewriting in
    // place; the second LOAD_LOCAL slot becomes the inline operand.
    // Hits whenever `arr[i]` lowers to two var-loads followed by INDEX,
    // which is the dominant `[]` shape in the compiler's AST traversal.
    if (op == TC_OP_LOAD_LOCAL && ip + 11 <= chunk->count &&
        chunk->code[ip + 5] == TC_OP_LOAD_LOCAL &&
        chunk->code[ip + 10] == TC_OP_INDEX &&
        !is_target[ip + 5] && !is_target[ip + 10]) {
      // recv slot bytes are already at ip+1..ip+4 (kept).
      // idx slot bytes are at ip+6..ip+9 — copy down one byte.
      chunk->code[ip] = TC_OP_INDEX_LL;
      chunk->code[ip + 5] = chunk->code[ip + 6];
      chunk->code[ip + 6] = chunk->code[ip + 7];
      chunk->code[ip + 7] = chunk->code[ip + 8];
      chunk->code[ip + 8] = chunk->code[ip + 9];
      chunk->code[ip + 9] = TC_OP_NOP;
      chunk->code[ip + 10] = TC_OP_NOP;
      ip += 11;
      continue;
    }

    // Pattern D: LOAD_LOCAL slot (5) ; SIZE_OF (1)  → 6 bytes
    // Common shape for `arr.size`, `entries.size`, etc.
    if (op == TC_OP_LOAD_LOCAL && ip + 6 <= chunk->count &&
        chunk->code[ip + 5] == TC_OP_SIZE_OF &&
        !is_target[ip + 5]) {
      chunk->code[ip] = TC_OP_SIZE_OF_LOCAL;
      chunk->code[ip + 5] = TC_OP_NOP;
      ip += 6;
      continue;
    }

    // Pattern E: LOAD_LOCAL slot (5) ; EQ_CONST_BR const target (9) → 14 bytes
    // The case-dispatch backbone — every `case t when :var ...` arm
    // post EQ_CONST_BR fusion. Lifts the local-load into the same
    // dispatch, eliminating a push/pop round-trip per arm.
    if (op == TC_OP_LOAD_LOCAL && ip + 14 <= chunk->count &&
        chunk->code[ip + 5] == TC_OP_EQ_CONST_BR &&
        !is_target[ip + 5]) {
      chunk->code[ip] = TC_OP_LOAD_EQ_CONST_BR;
      // slot bytes already at ip+1..ip+4 (kept).
      // const_id bytes at ip+6..ip+9 → ip+5..ip+8 (shift down by 1)
      // target bytes at ip+10..ip+13 → ip+9..ip+12 (shift down by 1)
      chunk->code[ip + 5] = chunk->code[ip + 6];
      chunk->code[ip + 6] = chunk->code[ip + 7];
      chunk->code[ip + 7] = chunk->code[ip + 8];
      chunk->code[ip + 8] = chunk->code[ip + 9];
      chunk->code[ip + 9] = chunk->code[ip + 10];
      chunk->code[ip + 10] = chunk->code[ip + 11];
      chunk->code[ip + 11] = chunk->code[ip + 12];
      chunk->code[ip + 12] = chunk->code[ip + 13];
      chunk->code[ip + 13] = TC_OP_NOP;
      // The original EQ_CONST_BR also has 2 NOP padding bytes after
      // it (offsets ip+14, ip+15). Those become "after our 14 bytes"
      // which means the next iteration sees 2 stray NOPs — harmless,
      // but we don't need to advance over them here.
      ip += 14;
      continue;
    }

    if (sz == 0) break;
    ip += sz;
  }
  }  // end iter loop

  free(is_target);
}

TcFunction *tc_chunk_find_function(const TcChunk *chunk, const char *name, size_t name_len) {
  for (size_t i = 0; i < chunk->function_count; i++) {
    if (chunk->functions[i].name_len == name_len && memcmp(chunk->functions[i].name, name, name_len) == 0) {
      return &((TcChunk *)chunk)->functions[i];
    }
  }
  return NULL;
}

// Find a method named "Class#method" without building the temp string. Used
// on the implicit-self CALL hot path.
TcFunction *tc_chunk_find_method(const TcChunk *chunk,
                                 const char *class_name, size_t class_len,
                                 const char *method_name, size_t method_len) {
  size_t full_len = class_len + 1 + method_len;
  for (size_t i = 0; i < chunk->function_count; i++) {
    TcFunction *f = &((TcChunk *)chunk)->functions[i];
    if (f->name_len != full_len) continue;
    if (f->name[class_len] != '#') continue;
    if (memcmp(f->name, class_name, class_len) != 0) continue;
    if (memcmp(f->name + class_len + 1, method_name, method_len) != 0) continue;
    return f;
  }
  return NULL;
}

int tc_emit_op(TcChunk *chunk, uint8_t op, TcError *err) {
  if (!reserve_code(chunk, 1, err)) return 0;
  chunk->code[chunk->count++] = op;
  return 1;
}

int tc_emit_u32(TcChunk *chunk, uint32_t value, TcError *err) {
  if (!reserve_code(chunk, 4, err)) return 0;
  chunk->code[chunk->count++] = (uint8_t)(value & 0xFF);
  chunk->code[chunk->count++] = (uint8_t)((value >> 8) & 0xFF);
  chunk->code[chunk->count++] = (uint8_t)((value >> 16) & 0xFF);
  chunk->code[chunk->count++] = (uint8_t)((value >> 24) & 0xFF);
  return 1;
}

int tc_emit_op_u32(TcChunk *chunk, uint8_t op, uint32_t value, TcError *err) {
  return tc_emit_op(chunk, op, err) && tc_emit_u32(chunk, value, err);
}

static const char *op_name(uint8_t op) {
  switch (op) {
    case TC_OP_CONST: return "CONST";
    case TC_OP_LOAD_LOCAL: return "LOAD_LOCAL";
    case TC_OP_STORE_LOCAL: return "STORE_LOCAL";
    case TC_OP_ADD: return "ADD";
    case TC_OP_SUB: return "SUB";
    case TC_OP_MUL: return "MUL";
    case TC_OP_DIV: return "DIV";
    case TC_OP_EQ: return "EQ";
    case TC_OP_NEQ: return "NEQ";
    case TC_OP_LT: return "LT";
    case TC_OP_LTE: return "LTE";
    case TC_OP_GT: return "GT";
    case TC_OP_GTE: return "GTE";
    case TC_OP_MOD: return "MOD";
    case TC_OP_BIT_AND: return "BIT_AND";
    case TC_OP_BIT_OR: return "BIT_OR";
    case TC_OP_BIT_XOR: return "BIT_XOR";
    case TC_OP_SHL: return "SHL";
    case TC_OP_SHR: return "SHR";
    case TC_OP_POW: return "POW";
    case TC_OP_PRINT: return "PRINT";
    case TC_OP_POP: return "POP";
    case TC_OP_RETURN: return "RETURN";
    case TC_OP_JUMP: return "JUMP";
    case TC_OP_JUMP_IF_FALSE: return "JUMP_IF_FALSE";
    case TC_OP_CALL: return "CALL";
    case TC_OP_CALL_DISCARD: return "CALL_DISCARD";
    case TC_OP_ARRAY: return "ARRAY";
    case TC_OP_HASH: return "HASH";
    case TC_OP_EQ_CONST_BR: return "EQ_CONST_BR";
    case TC_OP_NOP: return "NOP";
    case TC_OP_CASE_SYM_LINEAR: return "CASE_SYM_LINEAR";
    case TC_OP_INDEX: return "INDEX";
    case TC_OP_SIZE_OF: return "SIZE_OF";
    case TC_OP_INDEX_LL: return "INDEX_LL";
    case TC_OP_SIZE_OF_LOCAL: return "SIZE_OF_LOCAL";
    case TC_OP_LOAD_EQ_CONST_BR: return "LOAD_EQ_CONST_BR";
    default: return "?";
  }
}

static uint32_t read_u32(const uint8_t *code, size_t *ip) {
  uint32_t value = (uint32_t)code[*ip] |
                   ((uint32_t)code[*ip + 1] << 8) |
                   ((uint32_t)code[*ip + 2] << 16) |
                   ((uint32_t)code[*ip + 3] << 24);
  *ip += 4;
  return value;
}

void tc_dump_bytecode(const TcChunk *chunk) {
  size_t ip = 0;
  while (ip < chunk->count) {
    size_t at = ip;
    uint8_t op = chunk->code[ip++];
    printf("%04zu %-12s", at, op_name(op));
    if (op == TC_OP_CONST) {
      uint32_t id = read_u32(chunk->code, &ip);
      printf(" %u", id);
      if (id < chunk->const_count) {
        printf(" ; ");
        tc_value_print(chunk->consts[id], stdout);
      }
    } else if (op == TC_OP_LOAD_LOCAL || op == TC_OP_STORE_LOCAL) {
      uint32_t id = read_u32(chunk->code, &ip);
      printf(" %u", id);
      if (id < chunk->local_count) printf(" ; %s", chunk->locals[id].name);
    } else if (op == TC_OP_JUMP || op == TC_OP_JUMP_IF_FALSE) {
      printf(" %u", read_u32(chunk->code, &ip));
    } else if (op == TC_OP_CALL || op == TC_OP_CALL_DISCARD) {
      uint32_t name = read_u32(chunk->code, &ip);
      uint32_t argc = read_u32(chunk->code, &ip);
      uint32_t has_receiver = read_u32(chunk->code, &ip);
      printf(" name=%u argc=%u recv=%u", name, argc, has_receiver);
      if (name < chunk->const_count && tc_kind(chunk->consts[name]) == TC_VAL_STRING) {
        printf(" ; %.*s", (int)tc_str_len(chunk->consts[name]), tc_str_bytes_only(chunk->consts[name]));
      }
    } else if (op == TC_OP_EQ_CONST_BR) {
      uint32_t cid = read_u32(chunk->code, &ip);
      uint32_t target = read_u32(chunk->code, &ip);
      printf(" const=%u target=%u", cid, target);
      if (cid < chunk->const_count) {
        printf(" ; ");
        tc_value_print(chunk->consts[cid], stdout);
      }
    } else if (op == TC_OP_CASE_SYM_LINEAR) {
      uint32_t tid = read_u32(chunk->code, &ip);
      printf(" table=%u", tid);
      if (tid < chunk->case_table_count) {
        const TcCaseTable *t = &chunk->case_tables[tid];
        printf(" ; %u arms, default=%u", t->count, t->default_target);
      }
    } else if (op == TC_OP_ARRAY || op == TC_OP_HASH) {
      printf(" %u", read_u32(chunk->code, &ip));
    }
    printf("\n");
  }
}
