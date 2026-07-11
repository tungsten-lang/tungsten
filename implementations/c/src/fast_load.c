/* C-native Loader#load_program_ast for stage-1 bootstrap speed.
 *
 * When TUNGSTEN_C_FAST_PARSE=1, the C VM intercepts load_program_ast and
 * uses parse_ast.c instead of running the Tungsten lexer/parser as
 * bytecode. Measured ~35× faster lex+parse of the compiler sources.
 *
 * NOT used for `tungsten build` stage1/stage2 identity: C AST can drift
 * from the Tungsten parser. Bootstrap only needs a working compiler binary.
 */

#include "tc.h"

#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* ---- path set (same shape as main.c) ---- */

typedef struct {
  char **items;
  size_t count;
  size_t cap;
} FlPathSet;

static void fl_path_set_free(FlPathSet *set) {
  for (size_t i = 0; i < set->count; i++) free(set->items[i]);
  free(set->items);
  memset(set, 0, sizeof(*set));
}

static int fl_path_set_contains(FlPathSet *set, const char *path) {
  for (size_t i = 0; i < set->count; i++) {
    if (strcmp(set->items[i], path) == 0) return 1;
  }
  return 0;
}

static int fl_path_set_add(FlPathSet *set, const char *path, TcError *err) {
  if (fl_path_set_contains(set, path)) return 1;
  if (set->count == set->cap) {
    size_t cap = set->cap ? set->cap * 2 : 16;
    char **items = (char **)realloc(set->items, cap * sizeof(char *));
    if (!items) {
      tc_error_set(err, "fast_load: path set allocation failed");
      return 0;
    }
    set->items = items;
    set->cap = cap;
  }
  size_t len = strlen(path);
  char *copy = (char *)malloc(len + 1);
  if (!copy) {
    tc_error_set(err, "fast_load: path allocation failed");
    return 0;
  }
  memcpy(copy, path, len + 1);
  set->items[set->count++] = copy;
  return 1;
}

static TcAstValue *fl_ast_get(TcAstValue hash, const char *key) {
  if (hash.kind != TC_AST_HASH || !hash.as.hash) return NULL;
  for (size_t i = 0; i < hash.as.hash->count; i++) {
    if (strcmp(hash.as.hash->items[i].key, key) == 0) return &hash.as.hash->items[i].value;
  }
  return NULL;
}

static int fl_ast_text_eq(TcAstValue value, const char *text) {
  return (value.kind == TC_AST_STRING || value.kind == TC_AST_SYMBOL) &&
         strlen(text) == value.as.string.len &&
         memcmp(value.as.string.bytes, text, value.as.string.len) == 0;
}

static int fl_ast_node_is(TcAstValue value, const char *node) {
  TcAstValue *node_value = fl_ast_get(value, "node");
  return node_value && fl_ast_text_eq(*node_value, node);
}

static char *fl_canonicalize_path(const char *path, TcError *err) {
  char *canonical = realpath(path, NULL);
  if (!canonical) {
    tc_error_set(err, "fast_load: cannot resolve %s: %s", path, strerror(errno));
  }
  return canonical;
}

static char *fl_resolve_use_path(const char *from_path, const char *use_path, size_t use_len,
                                 TcError *err) {
  int has_ext = use_len >= 2 && use_path[use_len - 2] == '.' && use_path[use_len - 1] == 'w';
  size_t from_len = from_path ? strlen(from_path) : 0;
  size_t dir_len = 0;
  for (size_t i = from_len; i > 0; i--) {
    if (from_path[i - 1] == '/') {
      dir_len = i - 1;
      break;
    }
  }
  /* Absolute / project-relative use paths (start with core/, compiler/, …) */
  int absish = (use_len > 0 && use_path[0] == '/') ||
               (use_len >= 5 && memcmp(use_path, "core/", 5) == 0) ||
               (use_len >= 9 && memcmp(use_path, "compiler/", 9) == 0) ||
               (use_len >= 10 && memcmp(use_path, "languages/", 10) == 0);

  size_t total;
  char *path;
  if (absish || dir_len == 0) {
    /* resolve relative to cwd / as given */
    total = use_len + (has_ext ? 0 : 2);
    path = (char *)malloc(total + 1);
    if (!path) {
      tc_error_set(err, "fast_load: resolved use path allocation failed");
      return NULL;
    }
    memcpy(path, use_path, use_len);
    if (!has_ext) {
      path[use_len] = '.';
      path[use_len + 1] = 'w';
      path[use_len + 2] = '\0';
    } else {
      path[use_len] = '\0';
    }
    return path;
  }

  total = dir_len + 1 + use_len + (has_ext ? 0 : 2);
  path = (char *)malloc(total + 1);
  if (!path) {
    tc_error_set(err, "fast_load: resolved use path allocation failed");
    return NULL;
  }
  size_t at = 0;
  if (dir_len > 0) {
    memcpy(path, from_path, dir_len);
    at = dir_len;
    path[at++] = '/';
  }
  memcpy(path + at, use_path, use_len);
  at += use_len;
  if (!has_ext) {
    path[at++] = '.';
    path[at++] = 'w';
  }
  path[at] = '\0';
  return path;
}

static int fl_parse_file_ast(const char *path, const unsigned char *flags, size_t flags_len,
                             TcAstValue *ast, TcError *err) {
  size_t byte_len = 0;
  unsigned char *bytes = tc_read_file(path, &byte_len, err);
  if (!bytes) return 0;

  TcSource source;
  if (!tc_source_build(&source, bytes, byte_len, flags, flags_len, err)) {
    free(bytes);
    return 0;
  }
  /* tc_source_build takes ownership of bytes on success */

  TcTokens tokens;
  if (!tc_lex_source(&source, &tokens, err)) {
    tc_source_free(&source);
    return 0;
  }
  TcSyntaxTokens syntax_tokens;
  memset(&syntax_tokens, 0, sizeof(syntax_tokens));
  if (!tc_syntax_tokens_build(&source, &tokens, &syntax_tokens, err)) {
    tc_tokens_free(&tokens);
    tc_source_free(&source);
    return 0;
  }
  TcAstStats stats;
  int ok = tc_parse_bootstrap_ast(&source, &syntax_tokens, ast, &stats, flags, flags_len, err);
  tc_syntax_tokens_free(&syntax_tokens);
  tc_tokens_free(&tokens);
  tc_source_free(&source);
  return ok;
}

/* Flatten `use` into a single expressions array (Loader semantics). */
static int fl_flatten_program(const char *path, const unsigned char *flags, size_t flags_len,
                              FlPathSet *seen, TcAstValue *exprs_out, TcError *err) {
  if (!fl_path_set_add(seen, path, err)) return 0;

  TcAstValue file_ast;
  if (!fl_parse_file_ast(path, flags, flags_len, &file_ast, err)) return 0;

  TcAstValue *file_exprs = fl_ast_get(file_ast, "expressions");
  if (!file_exprs || file_exprs->kind != TC_AST_ARRAY) {
    tc_ast_free(file_ast);
    return 1; /* empty */
  }

  for (size_t i = 0; i < file_exprs->as.array->count; i++) {
    TcAstValue expr = file_exprs->as.array->items[i];
    if (fl_ast_node_is(expr, "use")) {
      TcAstValue *use = fl_ast_get(expr, "path");
      if (!use || use->kind != TC_AST_STRING) continue;
      char *use_path = fl_resolve_use_path(path, use->as.string.bytes, use->as.string.len, err);
      if (!use_path) {
        tc_ast_free(file_ast);
        return 0;
      }
      char *canonical = fl_canonicalize_path(use_path, err);
      free(use_path);
      use_path = canonical;
      if (!use_path) {
        tc_ast_free(file_ast);
        return 0;
      }
      if (fl_path_set_contains(seen, use_path)) {
        free(use_path);
        continue;
      }
      int ok = fl_flatten_program(use_path, flags, flags_len, seen, exprs_out, err);
      free(use_path);
      if (!ok) {
        tc_ast_free(file_ast);
        return 0;
      }
    } else {
      /* AST storage is a process-lifetime bump arena and tc_ast_free is a
       * no-op, so the flattened program can retain the parsed node directly.
       * Deep-cloning every expression duplicated the entire compiler AST. */
      if (!tc_ast_array_push(*exprs_out, expr, err)) {
        tc_ast_free(file_ast);
        return 0;
      }
    }
  }
  tc_ast_free(file_ast);
  return 1;
}

int tc_vm_fast_load_program_ast(const char *path, const char *from_file, TcValue *out, TcError *err) {
  /* Resolve relative path against from_file if needed. */
  char *resolved = NULL;
  const char *load_path = path;
  if (from_file && path && path[0] != '/' &&
      !(strlen(path) >= 5 && memcmp(path, "core/", 5) == 0) &&
      !(strlen(path) >= 9 && memcmp(path, "compiler/", 9) == 0)) {
    resolved = fl_resolve_use_path(from_file, path, strlen(path), err);
    if (!resolved) return 0;
    load_path = resolved;
  }
  char *canonical = fl_canonicalize_path(load_path, err);
  if (!canonical) {
    free(resolved);
    return 0;
  }
  free(resolved);
  resolved = canonical;
  load_path = resolved;

  const char *table_path = getenv("TUNGSTEN_LEX64_TABLE");
  if (!table_path || !table_path[0]) {
    /* Default relative to repo when unset — matches C VM main.c convention. */
    table_path = "languages/tungsten/tungsten.lex64";
  }
  size_t flags_len = 0;
  unsigned char *flags = tc_load_lex64_table(table_path, &flags_len, err);
  if (!flags) {
    free(resolved);
    return 0;
  }

  FlPathSet seen = {0};
  TcAstValue exprs = tc_ast_array_new(err);
  if (exprs.kind != TC_AST_ARRAY) {
    free(flags);
    free(resolved);
    fl_path_set_free(&seen);
    return 0;
  }

  if (!fl_flatten_program(load_path, flags, flags_len, &seen, &exprs, err)) {
    tc_ast_free(exprs);
    free(flags);
    free(resolved);
    fl_path_set_free(&seen);
    return 0;
  }

  TcAstValue program = tc_ast_hash_new(err);
  if (program.kind != TC_AST_HASH) {
    tc_ast_free(exprs);
    free(flags);
    free(resolved);
    fl_path_set_free(&seen);
    return 0;
  }
  if (!tc_ast_hash_set(program, "node", tc_ast_symbol_copy("program", 7, err), err) ||
      !tc_ast_hash_set(program, "expressions", exprs, err)) {
    tc_ast_free(program);
    free(flags);
    free(resolved);
    fl_path_set_free(&seen);
    return 0;
  }

  int ok = tc_vm_ast_to_runtime(&program, out, err);
  /* program owns exprs; free top-level hash structure only if convert failed? */
  /* ast_to_runtime deep-converts; we can free the AST tree. */
  tc_ast_free(program);
  free(flags);
  free(resolved);
  fl_path_set_free(&seen);
  return ok;
}

int tc_c_fast_parse_enabled(void) {
  /* The CALL handler probes this hook for every method call. getenv() showed
   * up as ~9% of canonical stage-1 CPU when the flag was disabled, so resolve
   * the process-wide bootstrap option once. The C VM never mutates its env. */
  static int initialized = 0;
  static int enabled = 0;
  if (!initialized) {
    const char *v = getenv("TUNGSTEN_C_FAST_PARSE");
    enabled = v && v[0] && v[0] != '0';
    initialized = 1;
  }
  return enabled;
}
