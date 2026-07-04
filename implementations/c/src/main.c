#include "tc.h"

#include <stdlib.h>
#include <string.h>

typedef struct {
  char **items;
  size_t count;
  size_t cap;
} PathSet;

static void usage(FILE *out) {
  fputs("usage: tungsten-c [--tokens] [--syntax-tokens] [--dump-ast] [--dump-bytecode] [-e source | file]\n", out);
}

static TcAstValue *main_ast_get(TcAstValue hash, const char *key) {
  if (hash.kind != TC_AST_HASH || !hash.as.hash) return NULL;
  for (size_t i = 0; i < hash.as.hash->count; i++) {
    if (strcmp(hash.as.hash->items[i].key, key) == 0) return &hash.as.hash->items[i].value;
  }
  return NULL;
}

static int main_ast_text_eq(TcAstValue value, const char *text) {
  return (value.kind == TC_AST_STRING || value.kind == TC_AST_SYMBOL) &&
         strlen(text) == value.as.string.len &&
         memcmp(value.as.string.bytes, text, value.as.string.len) == 0;
}

static int main_ast_node_is(TcAstValue value, const char *node) {
  TcAstValue *node_value = main_ast_get(value, "node");
  return node_value && main_ast_text_eq(*node_value, node);
}

static void path_set_free(PathSet *set) {
  for (size_t i = 0; i < set->count; i++) free(set->items[i]);
  free(set->items);
  memset(set, 0, sizeof(*set));
}

static int path_set_contains(PathSet *set, const char *path) {
  for (size_t i = 0; i < set->count; i++) {
    if (strcmp(set->items[i], path) == 0) return 1;
  }
  return 0;
}

static int path_set_add(PathSet *set, const char *path, TcError *err) {
  if (path_set_contains(set, path)) return 1;
  if (set->count == set->cap) {
    size_t cap = set->cap ? set->cap * 2 : 16;
    char **items = (char **)realloc(set->items, cap * sizeof(char *));
    if (!items) {
      tc_error_set(err, "use path set allocation failed");
      return 0;
    }
    set->items = items;
    set->cap = cap;
  }
  size_t len = strlen(path);
  char *copy = (char *)malloc(len + 1);
  if (!copy) {
    tc_error_set(err, "use path allocation failed");
    return 0;
  }
  memcpy(copy, path, len + 1);
  set->items[set->count++] = copy;
  return 1;
}

static char *resolve_use_path(const char *from_path, const char *use_path, size_t use_len, TcError *err) {
  int has_ext = use_len >= 2 && use_path[use_len - 2] == '.' && use_path[use_len - 1] == 'w';
  size_t from_len = strlen(from_path);
  size_t dir_len = 0;
  for (size_t i = from_len; i > 0; i--) {
    if (from_path[i - 1] == '/') {
      dir_len = i - 1;
      break;
    }
  }
  size_t total = dir_len + 1 + use_len + (has_ext ? 0 : 2);
  char *path = (char *)malloc(total + 1);
  if (!path) {
    tc_error_set(err, "resolved use path allocation failed");
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

static int parse_file_ast(const char *path, const unsigned char *flags, size_t flags_len, TcAstValue *ast,
                          TcError *err) {
  size_t byte_len = 0;
  unsigned char *bytes = tc_read_file(path, &byte_len, err);
  if (!bytes) return 0;

  TcSource source;
  if (!tc_source_build(&source, bytes, byte_len, flags, flags_len, err)) return 0;
  bytes = NULL;

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

static int compile_use_definitions(TcAstValue ast, const char *path, const unsigned char *flags, size_t flags_len,
                                   PathSet *seen, TcChunk *chunk, TcError *err) {
  TcAstValue *exprs = main_ast_get(ast, "expressions");
  if (!exprs || exprs->kind != TC_AST_ARRAY) return 1;

  for (size_t i = 0; i < exprs->as.array->count; i++) {
    TcAstValue expr = exprs->as.array->items[i];
    if (!main_ast_node_is(expr, "use")) continue;
    TcAstValue *use = main_ast_get(expr, "path");
    if (!use || use->kind != TC_AST_STRING) continue;
    char *use_path = resolve_use_path(path, use->as.string.bytes, use->as.string.len, err);
    if (!use_path) return 0;
    if (path_set_contains(seen, use_path)) {
      free(use_path);
      continue;
    }
    if (!path_set_add(seen, use_path, err)) {
      free(use_path);
      return 0;
    }
    TcAstValue use_ast;
    if (!parse_file_ast(use_path, flags, flags_len, &use_ast, err)) {
      free(use_path);
      return 0;
    }
    if (!compile_use_definitions(use_ast, use_path, flags, flags_len, seen, chunk, err) ||
        !tc_compile_ast_definitions(use_ast, chunk, err)) {
      tc_ast_free(use_ast);
      free(use_path);
      return 0;
    }
    tc_ast_free(use_ast);
    free(use_path);
  }
  return 1;
}

static int compile_use_initializers(TcAstValue ast, const char *path, const unsigned char *flags, size_t flags_len,
                                    PathSet *seen, TcChunk *chunk, TcError *err) {
  TcAstValue *exprs = main_ast_get(ast, "expressions");
  if (!exprs || exprs->kind != TC_AST_ARRAY) return 1;

  for (size_t i = 0; i < exprs->as.array->count; i++) {
    TcAstValue expr = exprs->as.array->items[i];
    if (!main_ast_node_is(expr, "use")) continue;
    TcAstValue *use = main_ast_get(expr, "path");
    if (!use || use->kind != TC_AST_STRING) continue;
    char *use_path = resolve_use_path(path, use->as.string.bytes, use->as.string.len, err);
    if (!use_path) return 0;
    if (path_set_contains(seen, use_path)) {
      free(use_path);
      continue;
    }
    if (!path_set_add(seen, use_path, err)) {
      free(use_path);
      return 0;
    }
    TcAstValue use_ast;
    if (!parse_file_ast(use_path, flags, flags_len, &use_ast, err)) {
      free(use_path);
      return 0;
    }
    if (!compile_use_initializers(use_ast, use_path, flags, flags_len, seen, chunk, err) ||
        !tc_compile_ast_initializers(use_ast, chunk, err)) {
      tc_ast_free(use_ast);
      free(use_path);
      return 0;
    }
    tc_ast_free(use_ast);
    free(use_path);
  }
  return 1;
}

int main(int argc, char **argv) {
  int dump_tokens = 0;
  int dump_syntax_tokens = 0;
  int dump_bytecode = 0;
  int tokens_only = 0;
  int check_lex = 0;
  int check_syntax_tokens = 0;
  int check_parse = 0;
  int dump_ast = 0;
  int check_ast = 0;
  const char *eval = NULL;
  const char *path = NULL;
  int script_argc = 0;
  char **script_argv = NULL;

  for (int i = 1; i < argc; i++) {
    if (path) {
      script_argc = argc - i;
      script_argv = &argv[i];
      break;
    }
    if (strcmp(argv[i], "--tokens") == 0) dump_tokens = 1;
    else if (strcmp(argv[i], "--syntax-tokens") == 0) dump_syntax_tokens = 1;
    else if (strcmp(argv[i], "--syntax-tokens-only") == 0) {
      dump_syntax_tokens = 1;
      tokens_only = 1;
    }
    else if (strcmp(argv[i], "--tokens-only") == 0) {
      dump_tokens = 1;
      tokens_only = 1;
    } else if (strcmp(argv[i], "--check-lex") == 0) {
      check_lex = 1;
    } else if (strcmp(argv[i], "--check-syntax-tokens") == 0) {
      check_syntax_tokens = 1;
    } else if (strcmp(argv[i], "--check-parse") == 0) {
      check_parse = 1;
    }
    else if (strcmp(argv[i], "--dump-ast") == 0) dump_ast = 1;
    else if (strcmp(argv[i], "--check-ast") == 0) check_ast = 1;
    else if (strcmp(argv[i], "--dump-bytecode") == 0) dump_bytecode = 1;
    else if (strcmp(argv[i], "-e") == 0) {
      if (++i >= argc) {
        usage(stderr);
        return 2;
      }
      eval = argv[i];
    } else if (strcmp(argv[i], "-h") == 0 || strcmp(argv[i], "--help") == 0) {
      usage(stdout);
      return 0;
    } else {
      path = argv[i];
    }
  }

  if ((eval && path) || (!eval && !path)) {
    usage(stderr);
    return 2;
  }

  TcError err = {0};
  unsigned char *bytes = NULL;
  const char *table_path = getenv("TUNGSTEN_LEX64_TABLE");
  if (!table_path) table_path = "languages/tungsten/tungsten.lex64";

  size_t flags_len = 0;
  unsigned char *flags = tc_load_lex64_table(table_path, &flags_len, &err);
  if (!flags) goto fail;

  size_t byte_len = 0;
  if (eval) {
    byte_len = strlen(eval);
    bytes = (unsigned char *)malloc(byte_len + 1);
    if (!bytes) {
      tc_error_set(&err, "eval source allocation failed");
      goto fail;
    }
    memcpy(bytes, eval, byte_len + 1);
  } else {
    bytes = tc_read_file(path, &byte_len, &err);
    if (!bytes) goto fail;
  }

  TcSource source;
  if (!tc_source_build(&source, bytes, byte_len, flags, flags_len, &err)) goto fail;
  bytes = NULL;

  TcTokens tokens;
  if (!tc_lex_source(&source, &tokens, &err)) {
    tc_source_free(&source);
    goto fail;
  }
  if (dump_tokens) tc_dump_tokens(&source, &tokens);
  TcSyntaxTokens syntax_tokens;
  memset(&syntax_tokens, 0, sizeof(syntax_tokens));
  if (!tc_syntax_tokens_build(&source, &tokens, &syntax_tokens, &err)) {
    tc_tokens_free(&tokens);
    tc_source_free(&source);
    goto fail;
  }
  if (dump_syntax_tokens) tc_dump_syntax_tokens(&source, &syntax_tokens);
  if (tokens_only || check_lex || check_syntax_tokens || check_parse || dump_ast || check_ast) {
    if (check_lex) printf("tokens=%zu\n", tokens.count);
    if (check_syntax_tokens) {
      size_t unknown = 0;
      for (size_t i = 0; i < syntax_tokens.count; i++) {
        if (syntax_tokens.items[i].kind == TC_K_UNKNOWN) unknown++;
      }
      printf("syntax_tokens=%zu unknown=%zu\n", syntax_tokens.count, unknown);
      if (unknown != 0) {
        tc_syntax_tokens_free(&syntax_tokens);
        tc_tokens_free(&tokens);
        tc_source_free(&source);
        free(flags);
        return 1;
      }
    }
    if (check_parse) {
      if (!tc_parse_check(&source, &syntax_tokens, &err)) {
        tc_syntax_tokens_free(&syntax_tokens);
        tc_tokens_free(&tokens);
        tc_source_free(&source);
        goto fail;
      }
      printf("parse=ok syntax_tokens=%zu\n", syntax_tokens.count);
    }
    if (dump_ast || check_ast) {
      TcAstValue ast;
      TcAstStats stats;
      if (!tc_parse_bootstrap_ast(&source, &syntax_tokens, &ast, &stats, flags, flags_len, &err)) {
        tc_syntax_tokens_free(&syntax_tokens);
        tc_tokens_free(&tokens);
        tc_source_free(&source);
        goto fail;
      }
      if (dump_ast) {
        tc_ast_print(ast, stdout);
        fputc('\n', stdout);
      }
      if (check_ast) {
        printf("ast=ok nodes=%zu raw=%zu use=%zu\n", stats.nodes, stats.raw_nodes, stats.use_nodes);
      }
      tc_ast_free(ast);
    }
    tc_syntax_tokens_free(&syntax_tokens);
    tc_tokens_free(&tokens);
    tc_source_free(&source);
    free(flags);
    return 0;
  }

  TcChunk chunk;
  tc_chunk_init(&chunk);
  TcAstValue ast;
  TcAstStats stats;
  if (!tc_parse_bootstrap_ast(&source, &syntax_tokens, &ast, &stats, flags, flags_len, &err)) {
    tc_chunk_free(&chunk);
    tc_syntax_tokens_free(&syntax_tokens);
    tc_tokens_free(&tokens);
    tc_source_free(&source);
    goto fail;
  }
  if (path) {
    PathSet seen = {0};
    if (!path_set_add(&seen, path, &err) ||
        !compile_use_initializers(ast, path, flags, flags_len, &seen, &chunk, &err)) {
      path_set_free(&seen);
      tc_ast_free(ast);
      tc_chunk_free(&chunk);
      tc_syntax_tokens_free(&syntax_tokens);
      tc_tokens_free(&tokens);
      tc_source_free(&source);
      goto fail;
    }
    path_set_free(&seen);
  }
  if (!tc_compile_ast(ast, &chunk, &err)) {
    tc_ast_free(ast);
    tc_chunk_free(&chunk);
    tc_syntax_tokens_free(&syntax_tokens);
    tc_tokens_free(&tokens);
    tc_source_free(&source);
    goto fail;
  }
  if (path) {
    PathSet seen = {0};
    if (!path_set_add(&seen, path, &err) ||
        !compile_use_definitions(ast, path, flags, flags_len, &seen, &chunk, &err)) {
      path_set_free(&seen);
      tc_ast_free(ast);
      tc_chunk_free(&chunk);
      tc_syntax_tokens_free(&syntax_tokens);
      tc_tokens_free(&tokens);
      tc_source_free(&source);
      goto fail;
    }
    path_set_free(&seen);
  }
  tc_ast_free(ast);
  tc_chunk_peephole(&chunk);
  tc_chunk_compute_touched(&chunk);
  if (dump_bytecode) tc_dump_bytecode(&chunk);

  TcValue result;
  int ok = tc_vm_run_args(&chunk, script_argc, script_argv, &result, &err);

  tc_chunk_free(&chunk);
  tc_syntax_tokens_free(&syntax_tokens);
  tc_tokens_free(&tokens);
  tc_source_free(&source);
  free(flags);
  if (!ok) goto fail_no_flags;
  return 0;

fail:
  free(flags);
fail_no_flags:
  free(bytes);
  if (err.message) {
    fprintf(stderr, "error: %s\n", err.message);
    tc_error_free(&err);
  }
  return 1;
}
