#include "tc.h"

#include <stdlib.h>
#include <string.h>

typedef struct {
  const TcSource *source;
  const TcSyntaxTokens *tokens;
  size_t pos;
  TcAstStats stats;
  // Lex64 flags forwarded into the parser so that string-interpolation
  // splitting can lex+parse [expr] sub-expressions through tc_source_build.
  // Optional — may be NULL when the caller doesn't have flags available
  // (in that case strings stay as plain TC_AST_STRING regardless of `[…]`
  // content; only callers that route through the C VM bootstrap shortcut
  // need interp splitting to match the native compiler's IR shape).
  const unsigned char *flags;
  size_t flags_len;
  /* File-level namespace from an `in Foo:Bar` directive. When set,
   * class declarations in the file get prefixed with the namespace
   * (so `+ Program` inside `in AST` becomes `AST:Program`). NULL =
   * top-level (no prefix). Owned by the parser struct; freed when
   * the namespace is reset or the parse finishes. */
  char  *namespace_prefix;
  size_t namespace_len;
  /* All fully-qualified class names declared in this file, used to
   * resolve an unqualified superclass reference. Lookup walks the
   * namespace chain from the current `in` prefix up to the top
   * level: `+ Foo < Bar` inside `in Tungsten:AST` first looks for
   * `Tungsten:AST:Bar`, then `Tungsten:Bar`, then bare `Bar`. The
   * first declared name wins; an unmatched name passes through
   * bare (so runtime builtins like StandardError still resolve).
   * Owned by the parser struct. */
  char  **declared_classes;
  size_t *declared_class_lens;
  size_t  declared_class_count;
  size_t  declared_class_cap;
} TcAstParser;

static TcSyntaxToken current_ast(TcAstParser *p) {
  if (p->pos >= p->tokens->count) return p->tokens->items[p->tokens->count - 1];
  return p->tokens->items[p->pos];
}

static int at_ast(TcAstParser *p, TcKind kind) {
  return current_ast(p).kind == kind;
}

static int at_keyword_ast(TcAstParser *p, const char *word) {
  TcSyntaxToken tok = current_ast(p);
  return tok.kind == TC_K_KEYWORD && tc_token_text_eq(p->source, tok.packed, word);
}

static void advance_ast(TcAstParser *p) {
  if (p->pos < p->tokens->count) p->pos++;
}

static int match_ast(TcAstParser *p, TcKind kind) {
  if (!at_ast(p, kind)) return 0;
  advance_ast(p);
  return 1;
}

static int token_line_ast(const TcSource *source, WValue token) {
  uint32_t off = tc_token_offset(token);
  uint32_t byte = source->byte_offsets[off];
  // O(1) lookup via the precomputed byte → line table built in
  // tc_source_build. Replaces a per-call O(N) newline scan that made
  // parsing quadratic in source size.
  return (int)source->byte_lines[byte];
}

static void parse_ast_error(TcAstParser *p, TcError *err, const char *message) {
  TcSyntaxToken tok = current_ast(p);
  tc_error_set(err, "AST parse error on line %d near %s: %s", token_line_ast(p->source, tok.packed),
               tc_kind_name(tok.kind), message);
}

static void skip_newlines_ast(TcAstParser *p) {
  while (at_ast(p, TC_K_NEWLINE) || at_ast(p, TC_K_SEMICOLON)) advance_ast(p);
}

static int current_token_text(TcAstParser *p, char **out, size_t *len_out, TcError *err) {
  return tc_token_text_copy(p->source, current_ast(p).packed, out, len_out, err);
}

static int raw_copy(TcAstParser *p, size_t start_pos, size_t end_pos, char **out, size_t *len_out, TcError *err) {
  if (end_pos <= start_pos) {
    *out = (char *)malloc(1);
    if (!*out) {
      tc_error_set(err, "raw AST allocation failed");
      return 0;
    }
    (*out)[0] = '\0';
    *len_out = 0;
    return 1;
  }

  WValue start_tok = p->tokens->items[start_pos].packed;
  WValue end_tok = p->tokens->items[end_pos - 1].packed;
  uint32_t start = p->source->byte_offsets[tc_token_offset(start_tok)];
  uint32_t end = p->source->byte_offsets[tc_token_offset(end_tok) + tc_token_length(end_tok)];
  while (end > start && (p->source->bytes[end - 1] == ' ' || p->source->bytes[end - 1] == '\t')) end--;
  size_t len = (size_t)(end - start);
  char *copy = (char *)malloc(len + 1);
  if (!copy) {
    tc_error_set(err, "raw AST allocation failed");
    return 0;
  }
  memcpy(copy, p->source->bytes + start, len);
  copy[len] = '\0';
  *out = copy;
  *len_out = len;
  return 1;
}

static int consume_to_end_ast(TcAstParser *p, TcError *err) {
  int paren = 0;
  int bracket = 0;
  int brace = 0;
  while (!at_ast(p, TC_K_EOF)) {
    TcKind kind = current_ast(p).kind;
    if (paren == 0 && bracket == 0 && brace == 0 &&
        (kind == TC_K_NEWLINE || kind == TC_K_SEMICOLON || kind == TC_K_DEDENT)) {
      return 1;
    }
    if (kind == TC_K_LPAREN) paren++;
    else if (kind == TC_K_RPAREN) paren--;
    else if (kind == TC_K_LBRACKET) bracket++;
    else if (kind == TC_K_RBRACKET) bracket--;
    else if (kind == TC_K_LBRACE) brace++;
    else if (kind == TC_K_RBRACE) brace--;
    if (paren < 0 || bracket < 0 || brace < 0) {
      parse_ast_error(p, err, "unmatched delimiter");
      return 0;
    }
    advance_ast(p);
  }
  if (paren != 0 || bracket != 0 || brace != 0) {
    parse_ast_error(p, err, "unterminated grouped expression");
    return 0;
  }
  return 1;
}

static int finish_header_ast(TcAstParser *p, TcError *err) {
  if (!consume_to_end_ast(p, err)) return 0;
  while (match_ast(p, TC_K_NEWLINE) || match_ast(p, TC_K_SEMICOLON)) {}
  return 1;
}

static int finish_header_span_ast(TcAstParser *p, size_t *end_pos, TcError *err) {
  if (!consume_to_end_ast(p, err)) return 0;
  if (end_pos) *end_pos = p->pos;
  while (match_ast(p, TC_K_NEWLINE) || match_ast(p, TC_K_SEMICOLON)) {}
  return 1;
}

static int set_node(TcAstValue hash, const char *node, TcError *err) {
  return tc_ast_hash_set(hash, "node", tc_ast_symbol_copy(node, strlen(node), err), err);
}

static TcAstValue *hash_value_ast(TcAstValue hash, const char *key) {
  if (hash.kind != TC_AST_HASH || !hash.as.hash) return NULL;
  for (size_t i = 0; i < hash.as.hash->count; i++) {
    if (strcmp(hash.as.hash->items[i].key, key) == 0) return &hash.as.hash->items[i].value;
  }
  return NULL;
}

static int ast_string_eq(TcAstValue value, const char *text) {
  return (value.kind == TC_AST_STRING || value.kind == TC_AST_SYMBOL) &&
         strlen(text) == value.as.string.len &&
         memcmp(value.as.string.bytes, text, value.as.string.len) == 0;
}

static int ast_node_is(TcAstValue value, const char *node) {
  TcAstValue *node_value = hash_value_ast(value, "node");
  return node_value && ast_string_eq(*node_value, node);
}

static int token_sp_before_ast(TcAstParser *p, size_t pos) {
  /* The packed-token sp_before flag was removed when the type field
   * widened to 8 bits. Bit 0 of flags now means f_line_start. Compute
   * sp_before from source directly: check if the codepoint preceding
   * this token is whitespace. Slightly slower (~one cp_at per query)
   * but only called at a few syntactic disambiguation sites. */
  WValue tok = p->tokens->items[pos].packed;
  uint32_t off = w_unbox_token_offset(tok);
  if (off == 0) return 0;
  uint32_t prev_cp = (uint32_t)((p->source->lc[off - 1] >> 18) & 0x1FFFFF);
  return prev_cp == ' ' || prev_cp == '\t';
}

static TcAstValue node_hash(TcAstParser *p, const char *node, size_t start_pos, TcError *err) {
  TcAstValue h = tc_ast_hash_new(err);
  if (h.kind != TC_AST_HASH) return h;
  p->stats.nodes++;
  if (!set_node(h, node, err) ||
      !tc_ast_hash_set(h, "line", tc_ast_int(token_line_ast(p->source, p->tokens->items[start_pos].packed)), err)) {
    tc_ast_free(h);
    return tc_ast_nil();
  }
  return h;
}

static TcAstValue raw_string(TcAstParser *p, size_t start_pos, size_t end_pos, TcError *err) {
  char *raw = NULL;
  size_t raw_len = 0;
  if (!raw_copy(p, start_pos, end_pos, &raw, &raw_len, err)) return tc_ast_nil();
  TcAstValue value = tc_ast_string_copy(raw, raw_len, err);
  free(raw);
  return value;
}

static TcAstValue unquoted_string_ast(const char *bytes, size_t len, TcError *err) {
  if (len >= 2 && ((bytes[0] == '"' && bytes[len - 1] == '"') || (bytes[0] == '\'' && bytes[len - 1] == '\''))) {
    bytes++;
    len -= 2;
  }
  char *copy = (char *)malloc(len + 1);
  if (!copy) {
    tc_error_set(err, "AST string allocation failed");
    return tc_ast_nil();
  }
  size_t out_len = 0;
  for (size_t i = 0; i < len; i++) {
    if (bytes[i] == '\\' && i + 1 < len) {
      i++;
      switch (bytes[i]) {
        case 'n': copy[out_len++] = '\n'; break;
        case 'r': copy[out_len++] = '\r'; break;
        case 't': copy[out_len++] = '\t'; break;
        case '0': copy[out_len++] = '\0'; break;
        case '"': copy[out_len++] = '"'; break;
        case '\'': copy[out_len++] = '\''; break;
        case '\\': copy[out_len++] = '\\'; break;
        default: copy[out_len++] = bytes[i]; break;
      }
    } else {
      copy[out_len++] = bytes[i];
    }
  }
  copy[out_len] = '\0';
  TcAstValue value = tc_ast_string_copy(copy, out_len, err);
  free(copy);
  return value;
}

// Detect whether a raw quoted-string body (between the surrounding quotes,
// escapes still in source form) contains a `[expr]` interpolation. Mirrors
// compiler/lib/lexer.w:scan_string's rules:
//   - `\[` and `\]` are literal brackets, not interp
//   - `[]` (empty) is literal
//   - `\e[` (ANSI escape prefix) is literal — the `\e` consumes the `[` too
static int string_body_has_interp(const char *bytes, size_t len) {
  for (size_t i = 0; i < len; i++) {
    char ch = bytes[i];
    if (ch == '\\' && i + 1 < len) {
      // \e[ — ANSI escape prefix. The Tungsten lexer consumes both `e`
      // and `[` as a unit so the `[` isn't seen as an interp opener.
      // Match that here so `"\e[m"` stays a plain string.
      if (bytes[i + 1] == 'e' && i + 2 < len && bytes[i + 2] == '[') {
        i += 2;  // skip `\e[`
        continue;
      }
      i++;  // skip generic escape
      continue;
    }
    if (ch == '[') {
      if (i + 1 < len && bytes[i + 1] == ']') continue;  // [] literal pair
      return 1;
    }
  }
  return 0;
}

// Forward decls — needed because parse_string_interp_ast wants to drive
// a fresh parser through the public API to handle the `[expr]` slice.
static TcAstValue parse_interp_subexpression(TcAstParser *p, const char *bytes, size_t len, TcError *err);

// Build a `{node: "string_interp", parts: [...]}` AST from a raw quoted
// string body (escapes still in source form). Each part is a 2-element
// array `[:str, "literal"]` or `[:expr, ast_expr]`, matching the shape
// compiler/lib/parser.w:parse_string_interp emits. The `[expr]` slices
// are recursively lexed+parsed via parse_interp_subexpression.
static TcAstValue parse_string_interp_ast(TcAstParser *p, const char *bytes, size_t len, size_t pos, TcError *err) {
  TcAstValue parts = tc_ast_array_new(err);
  if (parts.kind != TC_AST_ARRAY) return tc_ast_nil();

  // Buffer for a literal segment as we walk the input.
  char *lit = (char *)malloc(len + 1);
  if (!lit) {
    tc_error_set(err, "string_interp lit alloc failed");
    tc_ast_free(parts);
    return tc_ast_nil();
  }
  size_t lit_len = 0;

  // Helper to flush the current literal segment into parts.
  // Inlined as a goto-driven block to avoid another nested function.
  size_t i = 0;
  while (i < len) {
    char ch = bytes[i];
    if (ch == '\\' && i + 1 < len) {
      char esc = bytes[i + 1];
      // \e[ ANSI prefix: consume `\e[` as a unit (same as the lexer
      // does — the `[` is not an interp opener in this context).
      if (esc == 'e' && i + 2 < len && bytes[i + 2] == '[') {
        lit[lit_len++] = 0x1b;  // ESC
        lit[lit_len++] = '[';
        i += 3;
        continue;
      }
      // Resolve escape into the literal segment, same as unquoted_string_ast.
      switch (esc) {
        case 'n': lit[lit_len++] = '\n'; break;
        case 'r': lit[lit_len++] = '\r'; break;
        case 't': lit[lit_len++] = '\t'; break;
        case '0': lit[lit_len++] = '\0'; break;
        case '"': lit[lit_len++] = '"'; break;
        case '\'': lit[lit_len++] = '\''; break;
        case '\\': lit[lit_len++] = '\\'; break;
        case 'e': lit[lit_len++] = 0x1b; break;
        default: lit[lit_len++] = esc; break;
      }
      i += 2;
      continue;
    }
    // [] empty pair is a literal
    if (ch == '[' && i + 1 < len && bytes[i + 1] != ']') {
      // Flush accumulated literal segment, if any.
      if (lit_len > 0) {
        TcAstValue pair = tc_ast_array_new(err);
        TcAstValue tag = tc_ast_symbol_copy("str", 3, err);
        TcAstValue lit_val = tc_ast_string_copy(lit, lit_len, err);
        if (pair.kind != TC_AST_ARRAY || tag.kind != TC_AST_SYMBOL || lit_val.kind != TC_AST_STRING ||
            !tc_ast_array_push(pair, tag, err) || !tc_ast_array_push(pair, lit_val, err) ||
            !tc_ast_array_push(parts, pair, err)) {
          tc_ast_free(pair);
          tc_ast_free(parts);
          free(lit);
          return tc_ast_nil();
        }
        lit_len = 0;
      }
      // Scan to matching `]`. Track bracket depth to allow nesting like
      // `[arr[0]]`, mirroring the Tungsten lexer's depth counter — which
      // treats `\` as a plain character (no escape skip), so `\[` inside
      // the interp body still nests just like an unescaped `[`.
      size_t expr_start = i + 1;
      size_t expr_end = expr_start;
      int depth = 1;
      while (expr_end < len && depth > 0) {
        char c = bytes[expr_end];
        if (c == '[') depth++;
        else if (c == ']') {
          depth--;
          if (depth == 0) break;
        }
        expr_end++;
      }
      // Parse the slice [expr_start..expr_end) as a Tungsten expression.
      TcAstValue expr_ast = parse_interp_subexpression(p, bytes + expr_start, expr_end - expr_start, err);
      if (expr_ast.kind == TC_AST_NIL) {
        tc_ast_free(parts);
        free(lit);
        return tc_ast_nil();
      }
      TcAstValue pair = tc_ast_array_new(err);
      TcAstValue tag = tc_ast_symbol_copy("expr", 4, err);
      if (pair.kind != TC_AST_ARRAY || tag.kind != TC_AST_SYMBOL ||
          !tc_ast_array_push(pair, tag, err) || !tc_ast_array_push(pair, expr_ast, err) ||
          !tc_ast_array_push(parts, pair, err)) {
        tc_ast_free(pair);
        tc_ast_free(parts);
        free(lit);
        return tc_ast_nil();
      }
      i = expr_end + 1;  // skip past closing `]`
      continue;
    }
    lit[lit_len++] = ch;
    i++;
  }
  if (lit_len > 0) {
    TcAstValue pair = tc_ast_array_new(err);
    TcAstValue tag = tc_ast_symbol_copy("str", 3, err);
    TcAstValue lit_val = tc_ast_string_copy(lit, lit_len, err);
    if (pair.kind != TC_AST_ARRAY || tag.kind != TC_AST_SYMBOL || lit_val.kind != TC_AST_STRING ||
        !tc_ast_array_push(pair, tag, err) || !tc_ast_array_push(pair, lit_val, err) ||
        !tc_ast_array_push(parts, pair, err)) {
      tc_ast_free(pair);
      tc_ast_free(parts);
      free(lit);
      return tc_ast_nil();
    }
  }
  free(lit);

  TcAstValue node = node_hash(p, "string_interp", pos, err);
  if (node.kind != TC_AST_HASH || !tc_ast_hash_set(node, "parts", parts, err)) {
    tc_ast_free(node);
    tc_ast_free(parts);
    return tc_ast_nil();
  }
  return node;
}

// Lex+parse a `[expr]` slice as a Tungsten expression. Drives a fresh
// tc_source_build → tc_lex_source → tc_parse_bootstrap_ast pipeline on
// a synthetic source containing just the expression bytes, then peels
// the resulting `program` wrapper down to the first expression.
//
// Requires p->flags to be set; if not, returns nil and sets err. (The
// only callers that ever route into here are bootstrap parses that
// always have flags — main.c's `compile` path and the C VM's
// parse_runtime_ast_file. The --check-* paths don't use string consts
// at runtime, so missing flags there is fine.)
static TcAstValue parse_interp_subexpression(TcAstParser *p, const char *bytes, size_t len, TcError *err) {
  if (!p->flags) {
    tc_error_set(err, "string interpolation needs lex64 flags (parser was built without them)");
    return tc_ast_nil();
  }
  // tc_source_build takes ownership of `bytes` (it stores the pointer
  // and frees it via tc_source_free). Copy into a heap buffer.
  unsigned char *copy = (unsigned char *)malloc(len + 1);
  if (!copy) {
    tc_error_set(err, "string_interp subexpr alloc failed");
    return tc_ast_nil();
  }
  if (len > 0) memcpy(copy, bytes, len);
  copy[len] = '\0';

  TcSource source;
  if (!tc_source_build(&source, copy, len, p->flags, p->flags_len, err)) {
    free(copy);
    return tc_ast_nil();
  }
  TcTokens tokens;
  if (!tc_lex_source(&source, &tokens, err)) {
    tc_source_free(&source);
    return tc_ast_nil();
  }
  TcSyntaxTokens syntax;
  memset(&syntax, 0, sizeof(syntax));
  if (!tc_syntax_tokens_build(&source, &tokens, &syntax, err)) {
    tc_tokens_free(&tokens);
    tc_source_free(&source);
    return tc_ast_nil();
  }
  TcAstValue program;
  TcAstStats stats;
  int ok = tc_parse_bootstrap_ast(&source, &syntax, &program, &stats, p->flags, p->flags_len, err);
  if (!ok) {
    tc_syntax_tokens_free(&syntax);
    tc_tokens_free(&tokens);
    tc_source_free(&source);
    return tc_ast_nil();
  }
  // Extract first expression, deep-clone (the program is freed below).
  TcAstValue result = tc_ast_nil();
  if (program.kind == TC_AST_HASH && program.as.hash) {
    for (size_t i = 0; i < program.as.hash->count; i++) {
      if (strcmp(program.as.hash->items[i].key, "expressions") == 0 &&
          program.as.hash->items[i].value.kind == TC_AST_ARRAY &&
          program.as.hash->items[i].value.as.array &&
          program.as.hash->items[i].value.as.array->count > 0) {
        result = tc_ast_clone(program.as.hash->items[i].value.as.array->items[0], err);
        break;
      }
    }
  }
  tc_ast_free(program);
  tc_syntax_tokens_free(&syntax);
  tc_tokens_free(&tokens);
  tc_source_free(&source);
  return result;
}

static int append_bytes(char **buf, size_t *len, const char *bytes, size_t bytes_len, TcError *err) {
  char *next = (char *)realloc(*buf, *len + bytes_len + 1);
  if (!next) {
    tc_error_set(err, "AST name allocation failed");
    return 0;
  }
  memcpy(next + *len, bytes, bytes_len);
  *len += bytes_len;
  next[*len] = '\0';
  *buf = next;
  return 1;
}

static int name_token_ast(TcAstParser *p) {
  TcKind kind = current_ast(p).kind;
  return kind == TC_K_ID || kind == TC_K_NAME || kind == TC_K_TYPE || kind == TC_K_KEYWORD ||
         kind == TC_K_GLOBAL;
}

static int name_kind_ast(TcKind kind) {
  return kind == TC_K_ID || kind == TC_K_NAME || kind == TC_K_TYPE || kind == TC_K_KEYWORD ||
         kind == TC_K_GLOBAL;
}

static int parse_name_path_ast(TcAstParser *p, char **out, size_t *len_out, TcError *err) {
  if (!name_token_ast(p)) {
    parse_ast_error(p, err, "expected name");
    return 0;
  }

  char *result = NULL;
  size_t result_len = 0;
  char *part = NULL;
  size_t part_len = 0;
  if (!current_token_text(p, &part, &part_len, err)) return 0;
  if (!append_bytes(&result, &result_len, part, part_len, err)) {
    free(part);
    return 0;
  }
  free(part);
  advance_ast(p);

  while (at_ast(p, TC_K_SYMBOL)) {
    if (!current_token_text(p, &part, &part_len, err)) {
      free(result);
      return 0;
    }
    if (!append_bytes(&result, &result_len, ":", 1, err)) {
      free(part);
      free(result);
      return 0;
    }
    const char *bytes = part;
    if (part_len > 0 && part[0] == ':') {
      bytes++;
      part_len--;
    }
    if (!append_bytes(&result, &result_len, bytes, part_len, err)) {
      free(part);
      free(result);
      return 0;
    }
    free(part);
    advance_ast(p);
  }

  *out = result;
  *len_out = result_len;
  return 1;
}

static void trim_span(const char *text, size_t *start, size_t *len) {
  while (*len > 0 && (text[*start] == ' ' || text[*start] == '\t')) {
    (*start)++;
    (*len)--;
  }
  while (*len > 0 && (text[*start + *len - 1] == ' ' || text[*start + *len - 1] == '\t')) {
    (*len)--;
  }
}

static int add_type_hint_line(TcAstValue *hints, const char *text, size_t text_len, TcError *err) {
  size_t start = 0;
  size_t len = text_len;
  trim_span(text, &start, &len);
  if (len == 0) return 1;

  size_t type_start = start;
  size_t type_len = 0;
  size_t rest_start = start;
  size_t rest_len = 0;
  size_t colon = len;
  for (size_t i = 0; i < len; i++) {
    if (text[start + i] == ':') {
      colon = i;
      break;
    }
  }
  if (colon > 0 && colon < len) {
    type_len = colon;
    rest_start = start + colon + 1;
    rest_len = len - colon - 1;
  } else {
    size_t split = len;
    for (size_t i = 0; i < len; i++) {
      if (text[start + i] == ' ' || text[start + i] == '\t') {
        split = i;
        break;
      }
    }
    if (split == 0 || split == len) return 1;
    type_len = split;
    rest_start = start + split;
    rest_len = len - split;
  }
  trim_span(text, &type_start, &type_len);
  trim_span(text, &rest_start, &rest_len);
  if (type_len == 0 || rest_len == 0) return 1;

  size_t at = 0;
  while (at < rest_len) {
    size_t name_start = rest_start + at;
    size_t name_len = 0;
    while (at < rest_len && text[rest_start + at] != ',') {
      at++;
      name_len++;
    }
    trim_span(text, &name_start, &name_len);
    if (name_len > 0) {
      if (hints->kind == TC_AST_NIL) {
        *hints = tc_ast_hash_new(err);
        if (hints->kind != TC_AST_HASH) return 0;
      }
      char *key = (char *)malloc(name_len + 1);
      if (!key) {
        tc_error_set(err, "type hint key allocation failed");
        return 0;
      }
      memcpy(key, text + name_start, name_len);
      key[name_len] = '\0';
      TcAstValue value = tc_ast_symbol_copy(text + type_start, type_len, err);
      int ok = value.kind == TC_AST_SYMBOL && tc_ast_hash_set(*hints, key, value, err);
      free(key);
      if (!ok) return 0;
    }
    if (at < rest_len && text[rest_start + at] == ',') at++;
  }
  return 1;
}

static int parse_type_hints_ast(TcAstParser *p, TcAstValue *out, TcError *err) {
  TcAstValue hints = tc_ast_nil();
  while (at_ast(p, TC_K_TYPE_HINT)) {
    char *text = NULL;
    size_t text_len = 0;
    if (!current_token_text(p, &text, &text_len, err)) {
      tc_ast_free(hints);
      return 0;
    }
    if (!add_type_hint_line(&hints, text, text_len, err)) {
      free(text);
      tc_ast_free(hints);
      return 0;
    }
    free(text);
    advance_ast(p);
    skip_newlines_ast(p);
  }
  *out = hints;
  return 1;
}

static TcAstValue raw_node(TcAstParser *p, const char *kind, size_t start_pos, size_t end_pos, TcError *err) {
  TcAstValue h = tc_ast_hash_new(err);
  if (h.kind != TC_AST_HASH) return h;
  p->stats.nodes++;
  p->stats.raw_nodes++;

  char *raw = NULL;
  size_t raw_len = 0;
  if (!raw_copy(p, start_pos, end_pos, &raw, &raw_len, err)) {
    tc_ast_free(h);
    return tc_ast_nil();
  }

  if (!set_node(h, "raw", err) ||
      !tc_ast_hash_set(h, "kind", tc_ast_symbol_copy(kind, strlen(kind), err), err) ||
      !tc_ast_hash_set(h, "source", tc_ast_string_copy(raw, raw_len, err), err) ||
      !tc_ast_hash_set(h, "line", tc_ast_int(token_line_ast(p->source, p->tokens->items[start_pos].packed)), err)) {
    free(raw);
    tc_ast_free(h);
    return tc_ast_nil();
  }
  free(raw);
  return h;
}

static int token_text_at_ast(TcAstParser *p, size_t pos, char **out, size_t *len_out, TcError *err) {
  return tc_token_text_copy(p->source, p->tokens->items[pos].packed, out, len_out, err);
}

static int token_is_keyword_at_ast(TcAstParser *p, size_t pos, const char *word) {
  return p->tokens->items[pos].kind == TC_K_KEYWORD && tc_token_text_eq(p->source, p->tokens->items[pos].packed, word);
}

static void trim_expr_span_ast(TcAstParser *p, size_t *start, size_t *end) {
  while (*start < *end && (p->tokens->items[*start].kind == TC_K_NEWLINE ||
                          p->tokens->items[*start].kind == TC_K_SEMICOLON)) {
    (*start)++;
  }
  while (*end > *start && (p->tokens->items[*end - 1].kind == TC_K_NEWLINE ||
                           p->tokens->items[*end - 1].kind == TC_K_SEMICOLON)) {
    (*end)--;
  }
}

static int top_level_token_ast(TcAstParser *p, size_t start, size_t end, TcKind kind, size_t *pos_out,
                               int right_to_left) {
  int paren = 0;
  int bracket = 0;
  int brace = 0;
  if (right_to_left) {
    for (size_t i = end; i > start; i--) {
      size_t pos = i - 1;
      TcKind cur = p->tokens->items[pos].kind;
      if (cur == TC_K_RPAREN) paren++;
      else if (cur == TC_K_LPAREN) paren--;
      else if (cur == TC_K_RBRACKET) bracket++;
      else if (cur == TC_K_LBRACKET) bracket--;
      else if (cur == TC_K_RBRACE) brace++;
      else if (cur == TC_K_LBRACE) brace--;
      if (paren == 0 && bracket == 0 && brace == 0 && cur == kind) {
        *pos_out = pos;
        return 1;
      }
    }
    return 0;
  }

  for (size_t pos = start; pos < end; pos++) {
    TcKind cur = p->tokens->items[pos].kind;
    if (cur == TC_K_LPAREN) paren++;
    else if (cur == TC_K_RPAREN) paren--;
    else if (cur == TC_K_LBRACKET) bracket++;
    else if (cur == TC_K_RBRACKET) bracket--;
    else if (cur == TC_K_LBRACE) brace++;
    else if (cur == TC_K_RBRACE) brace--;
    if (paren == 0 && bracket == 0 && brace == 0 && cur == kind) {
      *pos_out = pos;
      return 1;
    }
  }
  return 0;
}

static int top_level_keyword_ast(TcAstParser *p, size_t start, size_t end, const char *word, size_t *pos_out,
                                 int right_to_left) {
  int paren = 0;
  int bracket = 0;
  int brace = 0;
  if (right_to_left) {
    for (size_t i = end; i > start; i--) {
      size_t pos = i - 1;
      TcKind cur = p->tokens->items[pos].kind;
      if (cur == TC_K_RPAREN) paren++;
      else if (cur == TC_K_LPAREN) paren--;
      else if (cur == TC_K_RBRACKET) bracket++;
      else if (cur == TC_K_LBRACKET) bracket--;
      else if (cur == TC_K_RBRACE) brace++;
      else if (cur == TC_K_LBRACE) brace--;
      if (paren == 0 && bracket == 0 && brace == 0 && token_is_keyword_at_ast(p, pos, word)) {
        *pos_out = pos;
        return 1;
      }
    }
    return 0;
  }

  for (size_t pos = start; pos < end; pos++) {
    TcKind cur = p->tokens->items[pos].kind;
    if (cur == TC_K_LPAREN) paren++;
    else if (cur == TC_K_RPAREN) paren--;
    else if (cur == TC_K_LBRACKET) bracket++;
    else if (cur == TC_K_RBRACKET) bracket--;
    else if (cur == TC_K_LBRACE) brace++;
    else if (cur == TC_K_RBRACE) brace--;
    if (paren == 0 && bracket == 0 && brace == 0 && token_is_keyword_at_ast(p, pos, word)) {
      *pos_out = pos;
      return 1;
    }
  }
  return 0;
}

static int top_level_any_ast(TcAstParser *p, size_t start, size_t end, const TcKind *kinds, size_t kind_count,
                             size_t *pos_out) {
  int paren = 0;
  int bracket = 0;
  int brace = 0;
  for (size_t i = end; i > start; i--) {
    size_t pos = i - 1;
    TcKind cur = p->tokens->items[pos].kind;
    if (cur == TC_K_RPAREN) paren++;
    else if (cur == TC_K_LPAREN) paren--;
    else if (cur == TC_K_RBRACKET) bracket++;
    else if (cur == TC_K_LBRACKET) bracket--;
    else if (cur == TC_K_RBRACE) brace++;
    else if (cur == TC_K_LBRACE) brace--;
    if (paren == 0 && bracket == 0 && brace == 0) {
      for (size_t k = 0; k < kind_count; k++) {
        if (cur == kinds[k]) {
          *pos_out = pos;
          return 1;
        }
      }
    }
  }
  return 0;
}

static int wrapped_span_ast(TcAstParser *p, size_t start, size_t end, TcKind open, TcKind close) {
  if (end <= start + 1 || p->tokens->items[start].kind != open || p->tokens->items[end - 1].kind != close) return 0;
  int depth = 0;
  for (size_t pos = start; pos < end; pos++) {
    TcKind cur = p->tokens->items[pos].kind;
    if (cur == open) depth++;
    else if (cur == close) depth--;
    if (depth == 0 && pos != end - 1) return 0;
  }
  return depth == 0;
}

static TcAstValue parse_expr_span_ast(TcAstParser *p, size_t start, size_t end, TcError *err);

static int parse_expr_list_ast(TcAstParser *p, size_t start, size_t end, TcAstValue *out, TcError *err) {
  TcAstValue args = tc_ast_array_new(err);
  if (args.kind != TC_AST_ARRAY) return 0;
  trim_expr_span_ast(p, &start, &end);
  if (start >= end) {
    *out = args;
    return 1;
  }

  size_t item_start = start;
  int paren = 0;
  int bracket = 0;
  int brace = 0;
  for (size_t pos = start; pos <= end; pos++) {
    TcKind cur = pos < end ? p->tokens->items[pos].kind : TC_K_COMMA;
    int split = 0;
    if (pos == end) split = 1;
    else if (cur == TC_K_LPAREN) paren++;
    else if (cur == TC_K_RPAREN) paren--;
    else if (cur == TC_K_LBRACKET) bracket++;
    else if (cur == TC_K_RBRACKET) bracket--;
    else if (cur == TC_K_LBRACE) brace++;
    else if (cur == TC_K_RBRACE) brace--;
    else if (paren == 0 && bracket == 0 && brace == 0 && cur == TC_K_COMMA) split = 1;

    if (split) {
      TcAstValue arg = parse_expr_span_ast(p, item_start, pos, err);
      if (arg.kind == TC_AST_NIL || !tc_ast_array_push(args, arg, err)) {
        tc_ast_free(arg);
        tc_ast_free(args);
        return 0;
      }
      item_start = pos + 1;
    }
  }
  *out = args;
  return 1;
}

static int parse_call_args_after_name_ast(TcAstParser *p, size_t arg_start, size_t end, TcAstValue *args,
                                          TcError *err) {
  if (arg_start >= end) {
    *args = tc_ast_array_new(err);
    return args->kind == TC_AST_ARRAY;
  }
  if (p->tokens->items[arg_start].kind == TC_K_LPAREN && wrapped_span_ast(p, arg_start, end, TC_K_LPAREN, TC_K_RPAREN)) {
    return parse_expr_list_ast(p, arg_start + 1, end - 1, args, err);
  }
  return parse_expr_list_ast(p, arg_start, end, args, err);
}

static int bare_arg_start_ast(TcAstParser *p, size_t pos) {
  TcKind kind = p->tokens->items[pos].kind;
  switch (kind) {
    case TC_K_ID:
    case TC_K_NAME:
    case TC_K_TYPE:
    case TC_K_GLOBAL:
    case TC_K_IVAR:
    case TC_K_CVAR:
    case TC_K_INT:
    case TC_K_DECIMAL:
    case TC_K_STRING:
    case TC_K_SYMBOL:
    case TC_K_LPAREN:
    case TC_K_LBRACE:
    case TC_K_BANG:
      return 1;
    case TC_K_KEYWORD:
      return token_is_keyword_at_ast(p, pos, "true") || token_is_keyword_at_ast(p, pos, "false") ||
             token_is_keyword_at_ast(p, pos, "nil") || token_is_keyword_at_ast(p, pos, "self");
    default:
      return 0;
  }
}

static int early_bare_arg_start_ast(TcAstParser *p, size_t pos) {
  if (p->tokens->items[pos].kind == TC_K_LPAREN && !token_sp_before_ast(p, pos)) return 0;
  return bare_arg_start_ast(p, pos);
}

static TcAstValue call_node_ast(TcAstParser *p, size_t start, TcAstValue receiver, const char *name, size_t name_len,
                                TcAstValue args, TcError *err) {
  TcAstValue node = node_hash(p, "call", start, err);
  if (node.kind != TC_AST_HASH) return node;
  if (!tc_ast_hash_set(node, "receiver", receiver, err) ||
      !tc_ast_hash_set(node, "name", tc_ast_string_copy(name, name_len, err), err) ||
      !tc_ast_hash_set(node, "args", args, err) ||
      !tc_ast_hash_set(node, "block", tc_ast_nil(), err)) {
    tc_ast_free(node);
    return tc_ast_nil();
  }
  return node;
}

static TcAstValue parse_bare_command_call_ast(TcAstParser *p, size_t start, size_t end, int early, TcError *err) {
  if (!name_kind_ast(p->tokens->items[start].kind) || start + 1 >= end ||
      p->tokens->items[start + 1].kind == TC_K_LBRACKET) {
    return tc_ast_nil();
  }
  /* `UpperName :Foo` with no space between → namespace-qualified
   * name (Tungsten:AST:Program / AST:Foo), not a command call with
   * a symbol arg. Lets the qualified-name detector / dot-call
   * splitter further down handle it. Upper-case-starting identifiers
   * tokenize as TC_K_NAME or (for known type names) TC_K_TYPE;
   * either kind is a candidate for a namespace head. */
  if ((p->tokens->items[start].kind == TC_K_TYPE ||
       p->tokens->items[start].kind == TC_K_NAME) &&
      p->tokens->items[start + 1].kind == TC_K_SYMBOL &&
      !token_sp_before_ast(p, start + 1)) {
    return tc_ast_nil();
  }
  if (early && !early_bare_arg_start_ast(p, start + 1)) return tc_ast_nil();
  if (!early && !bare_arg_start_ast(p, start + 1)) return tc_ast_nil();

  char *name = NULL;
  size_t name_len = 0;
  if (!token_text_at_ast(p, start, &name, &name_len, err)) return tc_ast_nil();
  TcAstValue args;
  if (!parse_expr_list_ast(p, start + 1, end, &args, err)) {
    free(name);
    return tc_ast_nil();
  }
  TcAstValue node = call_node_ast(p, start, tc_ast_nil(), name, name_len, args, err);
  free(name);
  return node;
}

static TcAstValue parse_call_span_ast(TcAstParser *p, size_t start, size_t end, TcError *err) {
  if (name_kind_ast(p->tokens->items[start].kind) &&
      start + 1 < end && p->tokens->items[start + 1].kind == TC_K_LPAREN &&
      wrapped_span_ast(p, start + 1, end, TC_K_LPAREN, TC_K_RPAREN)) {
    char *name = NULL;
    size_t name_len = 0;
    if (!token_text_at_ast(p, start, &name, &name_len, err)) return tc_ast_nil();
    TcAstValue args;
    if (!parse_expr_list_ast(p, start + 2, end - 1, &args, err)) {
      free(name);
      return tc_ast_nil();
    }
    TcAstValue node = call_node_ast(p, start, tc_ast_nil(), name, name_len, args, err);
    free(name);
    return node;
  }

  size_t dot = 0;
  if (top_level_token_ast(p, start, end, TC_K_DOT, &dot, 1) && dot > start && dot + 1 < end) {
    size_t name_pos = dot + 1;
    TcKind name_kind = p->tokens->items[name_pos].kind;
    if (name_kind == TC_K_ID || name_kind == TC_K_NAME || name_kind == TC_K_TYPE || name_kind == TC_K_KEYWORD) {
      TcAstValue receiver = parse_expr_span_ast(p, start, dot, err);
      if (receiver.kind == TC_AST_NIL) return tc_ast_nil();
      char *name = NULL;
      size_t name_len = 0;
      if (!token_text_at_ast(p, name_pos, &name, &name_len, err)) {
        tc_ast_free(receiver);
        return tc_ast_nil();
      }
      TcAstValue args;
      if (!parse_call_args_after_name_ast(p, name_pos + 1, end, &args, err)) {
        free(name);
        tc_ast_free(receiver);
        return tc_ast_nil();
      }
      TcAstValue node = call_node_ast(p, start, receiver, name, name_len, args, err);
      free(name);
      return node;
    }
  }

  return parse_bare_command_call_ast(p, start, end, 0, err);
}

static TcAstValue binary_node_ast(TcAstParser *p, size_t start, size_t end, size_t op_pos, TcError *err) {
  TcAstValue left = parse_expr_span_ast(p, start, op_pos, err);
  TcAstValue right = parse_expr_span_ast(p, op_pos + 1, end, err);
  if (left.kind == TC_AST_NIL || right.kind == TC_AST_NIL) {
    tc_ast_free(left);
    tc_ast_free(right);
    return tc_ast_nil();
  }
  TcAstValue node = node_hash(p, "binary_op", op_pos, err);
  if (node.kind != TC_AST_HASH) {
    tc_ast_free(left);
    tc_ast_free(right);
    return node;
  }
  const char *op = tc_kind_name(p->tokens->items[op_pos].kind);
  if (!tc_ast_hash_set(node, "left", left, err) ||
      !tc_ast_hash_set(node, "op", tc_ast_symbol_copy(op, strlen(op), err), err) ||
      !tc_ast_hash_set(node, "right", right, err)) {
    tc_ast_free(node);
    return tc_ast_nil();
  }
  return node;
}

static TcAstValue int_node_value_ast(TcAstParser *p, size_t pos, int64_t value, const char *raw, TcError *err) {
  TcAstValue node = node_hash(p, "int", pos, err);
  if (node.kind != TC_AST_HASH) return node;
  if (!tc_ast_hash_set(node, "value", tc_ast_int(value), err) ||
      !tc_ast_hash_set(node, "raw", tc_ast_string_copy(raw, strlen(raw), err), err)) {
    tc_ast_free(node);
    return tc_ast_nil();
  }
  return node;
}

static TcAstValue compound_assign_node_ast(TcAstParser *p, size_t op_pos, TcAstValue target, const char *op,
                                           TcAstValue value, TcError *err) {
  TcAstValue node = node_hash(p, "compound_assign", op_pos, err);
  if (node.kind != TC_AST_HASH) {
    tc_ast_free(target);
    tc_ast_free(value);
    return node;
  }
  if (!tc_ast_hash_set(node, "target", target, err) ||
      !tc_ast_hash_set(node, "op", tc_ast_symbol_copy(op, strlen(op), err), err) ||
      !tc_ast_hash_set(node, "value", value, err)) {
    tc_ast_free(node);
    return tc_ast_nil();
  }
  return node;
}

static TcAstValue or_node_ast(TcAstParser *p, size_t op_pos, TcAstValue left, TcAstValue right, TcError *err) {
  TcAstValue node = node_hash(p, "or", op_pos, err);
  if (node.kind != TC_AST_HASH) {
    tc_ast_free(left);
    tc_ast_free(right);
    return node;
  }
  if (!tc_ast_hash_set(node, "left", left, err) ||
      !tc_ast_hash_set(node, "right", right, err)) {
    tc_ast_free(node);
    return tc_ast_nil();
  }
  return node;
}

static TcAstValue and_node_ast(TcAstParser *p, size_t op_pos, TcAstValue left, TcAstValue right, TcError *err) {
  TcAstValue node = node_hash(p, "and", op_pos, err);
  if (node.kind != TC_AST_HASH) {
    tc_ast_free(left);
    tc_ast_free(right);
    return node;
  }
  if (!tc_ast_hash_set(node, "left", left, err) ||
      !tc_ast_hash_set(node, "right", right, err)) {
    tc_ast_free(node);
    return tc_ast_nil();
  }
  return node;
}

// Build a logical-OR / logical-AND AST node for `||` / `&&` at the
// given op position. Produces `{node: "or" | "and", left, right}` —
// the form lowering.w's `lower_expression` dispatch expects (the
// generic `binary_node_ast` would emit `{node: "binary_op", op: "OR"}`,
// which then falls through to lower_binary_op's op-map lookup, misses
// (the map has no entry for OR/AND), and emits the
// `# fallback, should not happen` w_add — which is exactly the
// `cannot add false + false` bootstrap-stage1 crash this fixes).
static TcAstValue logical_node_ast(TcAstParser *p, size_t start, size_t end, size_t op_pos, TcError *err) {
  TcAstValue left = parse_expr_span_ast(p, start, op_pos, err);
  TcAstValue right = parse_expr_span_ast(p, op_pos + 1, end, err);
  if (left.kind == TC_AST_NIL || right.kind == TC_AST_NIL) {
    tc_ast_free(left);
    tc_ast_free(right);
    return tc_ast_nil();
  }
  TcKind k = p->tokens->items[op_pos].kind;
  return (k == TC_K_AND) ? and_node_ast(p, op_pos, left, right, err)
                         : or_node_ast(p, op_pos, left, right, err);
}

static const char *compound_op_name_ast(TcKind kind) {
  switch (kind) {
    case TC_K_PLUS_EQ:
    case TC_K_PLUS_PLUS:
      return "PLUS";
    case TC_K_MINUS_EQ:
    case TC_K_MINUS_MINUS:
      return "MINUS";
    case TC_K_STAR_EQ:
      return "STAR";
    case TC_K_SLASH_EQ:
      return "SLASH";
    case TC_K_PERCENT_EQ:
      return "PERCENT";
    default:
      return NULL;
  }
}

static TcAstValue parse_compound_assign_ast(TcAstParser *p, size_t start, size_t end, TcError *err) {
  static const TcKind postfix_ops[] = {TC_K_PLUS_PLUS, TC_K_MINUS_MINUS};
  size_t op_pos = 0;
  if (top_level_any_ast(p, start, end, postfix_ops, sizeof(postfix_ops) / sizeof(postfix_ops[0]), &op_pos) &&
      op_pos > start && op_pos == end - 1) {
    TcAstValue target = parse_expr_span_ast(p, start, op_pos, err);
    TcAstValue value = int_node_value_ast(p, op_pos, 1, "1", err);
    if (target.kind == TC_AST_NIL || value.kind == TC_AST_NIL) {
      tc_ast_free(target);
      tc_ast_free(value);
      return tc_ast_nil();
    }
    return compound_assign_node_ast(p, op_pos, target, compound_op_name_ast(p->tokens->items[op_pos].kind), value, err);
  }

  static const TcKind compound_ops[] = {
      TC_K_PLUS_EQ, TC_K_MINUS_EQ, TC_K_STAR_EQ, TC_K_SLASH_EQ, TC_K_PERCENT_EQ, TC_K_OR_ASSIGN};
  if (!top_level_any_ast(p, start, end, compound_ops, sizeof(compound_ops) / sizeof(compound_ops[0]), &op_pos) ||
      op_pos <= start) {
    return tc_ast_nil();
  }

  TcAstValue target = parse_expr_span_ast(p, start, op_pos, err);
  TcAstValue value = parse_expr_span_ast(p, op_pos + 1, end, err);
  if (target.kind == TC_AST_NIL || value.kind == TC_AST_NIL) {
    tc_ast_free(target);
    tc_ast_free(value);
    return tc_ast_nil();
  }

  if (p->tokens->items[op_pos].kind == TC_K_OR_ASSIGN) {
    TcAstValue or_value = or_node_ast(p, op_pos, target, value, err);
    if (or_value.kind == TC_AST_NIL) return tc_ast_nil();
    TcAstValue assign = node_hash(p, "assign", op_pos, err);
    if (assign.kind != TC_AST_HASH) {
      tc_ast_free(or_value);
      return assign;
    }
    TcAstValue assign_target = parse_expr_span_ast(p, start, op_pos, err);
    if (assign_target.kind == TC_AST_NIL) {
      tc_ast_free(or_value);
      tc_ast_free(assign);
      return tc_ast_nil();
    }
    if (!tc_ast_hash_set(assign, "target", assign_target, err) ||
        !tc_ast_hash_set(assign, "value", or_value, err) ||
        !tc_ast_hash_set(assign, "type_hint", tc_ast_nil(), err)) {
      tc_ast_free(assign);
      return tc_ast_nil();
    }
    return assign;
  }

  return compound_assign_node_ast(p, op_pos, target, compound_op_name_ast(p->tokens->items[op_pos].kind), value, err);
}

static TcAstValue atom_node_ast(TcAstParser *p, size_t pos, TcError *err) {
  TcKind kind = p->tokens->items[pos].kind;
  char *text = NULL;
  size_t text_len = 0;
  if (!token_text_at_ast(p, pos, &text, &text_len, err)) return tc_ast_nil();

  TcAstValue node = tc_ast_nil();
  switch (kind) {
    case TC_K_INT: {
      char *clean = (char *)malloc(text_len + 1);
      if (!clean) {
        free(text);
        tc_error_set(err, "AST int allocation failed");
        return tc_ast_nil();
      }
      size_t ci = 0;
      for (size_t i = 0; i < text_len; i++) {
        if (text[i] != '_') clean[ci++] = text[i];
      }
      clean[ci] = '\0';
      node = node_hash(p, "int", pos, err);
      // strtoull (not strtoll) so hex literals with the high bit set —
      // e.g. 0xFFFC000000000002 in compiler/lib/lexer.w's LexChar tag
      // constants — are interpreted by their bit pattern instead of
      // saturating at INT64_MAX. cast lets a 64-bit value flow into
      // tc_ast_int as signed (heap-spill handles the W_TAG_INT overflow).
      if (node.kind == TC_AST_HASH &&
          (!tc_ast_hash_set(node, "value", tc_ast_int((int64_t)strtoull(clean, NULL, 0)), err) ||
           !tc_ast_hash_set(node, "raw", tc_ast_string_copy(text, text_len, err), err))) {
        tc_ast_free(node);
        node = tc_ast_nil();
      }
      free(clean);
      break;
    }
    case TC_K_DECIMAL:
      // The lexer emits a single TC_T_DECIMAL token for both `3.14`
      // (decimal) and `~3.14` (approximate-float, runtime double).
      // Distinguish here by leading `~`. Emitting a {node:"decimal"}
      // for `~0.001` made fmt_elapsed's `seconds < ~0.001` compare a
      // double to a decimal, which `w_lt` doesn't handle and dies as
      // "expected numeric type" — that was the stage-2 verbose-mode bug.
      // Strip the prefix and the optional sign; lower_float in
      // lowering.w just calls .to_s() on the value to drive a raw_f64.
      if (text_len >= 2 && text[0] == '~') {
        node = node_hash(p, "float", pos, err);
        if (node.kind == TC_AST_HASH &&
            !tc_ast_hash_set(node, "value",
                             tc_ast_string_copy(text + 1, text_len - 1, err), err)) {
          tc_ast_free(node);
          node = tc_ast_nil();
        }
      } else {
        node = node_hash(p, "decimal", pos, err);
        if (node.kind == TC_AST_HASH &&
            !tc_ast_hash_set(node, "value", tc_ast_string_copy(text, text_len, err), err)) {
          tc_ast_free(node);
          node = tc_ast_nil();
        }
      }
      break;
    case TC_K_STRING: {
      // Only double-quoted strings interpolate. Single-quoted (`'...'`)
      // strings stay literal — same convention as compiler/lib/lexer.w.
      const char *body = text;
      size_t body_len = text_len;
      int double_quoted = 0;
      if (body_len >= 2 && body[0] == '"' && body[body_len - 1] == '"') {
        double_quoted = 1;
        body++;
        body_len -= 2;
      } else if (body_len >= 2 && body[0] == '\'' && body[body_len - 1] == '\'') {
        body++;
        body_len -= 2;
      }
      if (double_quoted && string_body_has_interp(body, body_len)) {
        node = parse_string_interp_ast(p, body, body_len, pos, err);
      } else {
        node = node_hash(p, "string", pos, err);
        if (node.kind == TC_AST_HASH &&
            !tc_ast_hash_set(node, "value", unquoted_string_ast(text, text_len, err), err)) {
          tc_ast_free(node);
          node = tc_ast_nil();
        }
      }
      break;
    }
    case TC_K_SYMBOL: {
      const char *sym = text;
      size_t sym_len = text_len;
      if (sym_len > 0 && sym[0] == ':') {
        sym++;
        sym_len--;
      }
      node = node_hash(p, "symbol", pos, err);
      if (node.kind == TC_AST_HASH &&
          !tc_ast_hash_set(node, "value", tc_ast_string_copy(sym, sym_len, err), err)) {
        tc_ast_free(node);
        node = tc_ast_nil();
      }
      break;
    }
    case TC_K_CHAR: {
      // `:-X` is the ASCII char literal. The lexer produces a TC_T_CHAR
      // whose text spans `:-X` (3 chars) or, for escapes, `:-\X` (4 chars).
      // Without unescaping, `:-\"` lowered to 92 (`\`) instead of 34 (`"`),
      // making every `c == :-\"` test in compiler/lib/lexer.w's string
      // scanner false — strings tokenized correctly by accident on the
      // happy path but trailing comments and many similar dispatch arms
      // silently broke.
      int64_t value = 0;
      if (text_len >= 4 && text[0] == ':' && text[1] == '-' && text[2] == '\\') {
        switch (text[3]) {
          case 'n':  value = '\n'; break;
          case 't':  value = '\t'; break;
          case 'r':  value = '\r'; break;
          case '0':  value = '\0'; break;
          case '\\': value = '\\'; break;
          case '"':  value = '"';  break;
          case '\'': value = '\''; break;
          default:   value = (unsigned char)text[3]; break;
        }
      } else if (text_len >= 3 && text[0] == ':' && text[1] == '-') {
        value = (unsigned char)text[2];
      }
      node = node_hash(p, "char", pos, err);
      if (node.kind == TC_AST_HASH &&
          !tc_ast_hash_set(node, "value", tc_ast_int(value), err)) {
        tc_ast_free(node);
        node = tc_ast_nil();
      }
      break;
    }
    case TC_K_CODEPOINT:
      node = node_hash(p, "codepoint", pos, err);
      if (node.kind == TC_AST_HASH &&
          !tc_ast_hash_set(node, "value", tc_ast_string_copy(text, text_len, err), err)) {
        tc_ast_free(node);
        node = tc_ast_nil();
      }
      break;
    case TC_K_IVAR:
      node = node_hash(p, "ivar", pos, err);
      if (node.kind == TC_AST_HASH &&
          !tc_ast_hash_set(node, "name", tc_ast_string_copy(text, text_len, err), err)) {
        tc_ast_free(node);
        node = tc_ast_nil();
      }
      break;
    case TC_K_CVAR:
      node = node_hash(p, "cvar", pos, err);
      if (node.kind == TC_AST_HASH &&
          !tc_ast_hash_set(node, "name", tc_ast_string_copy(text, text_len, err), err)) {
        tc_ast_free(node);
        node = tc_ast_nil();
      }
      break;
    case TC_K_ID:
    case TC_K_NAME:
    case TC_K_TYPE:
    case TC_K_GLOBAL:
      node = node_hash(p, "var", pos, err);
      if (node.kind == TC_AST_HASH &&
          !tc_ast_hash_set(node, "name", tc_ast_string_copy(text, text_len, err), err)) {
        tc_ast_free(node);
        node = tc_ast_nil();
      }
      break;
    case TC_K_KEYWORD:
      if (strcmp(text, "true") == 0 || strcmp(text, "false") == 0) {
        node = node_hash(p, "bool", pos, err);
        if (node.kind == TC_AST_HASH &&
            !tc_ast_hash_set(node, "value", tc_ast_bool(strcmp(text, "true") == 0), err)) {
          tc_ast_free(node);
          node = tc_ast_nil();
        }
      } else if (strcmp(text, "nil") == 0) {
        // Match the Tungsten parser's `:nil_lit` tag — compiler/lib/lowering.w
        // sentinel-EQ fast path checks `n[:node] == :nil_lit` to inline a
        // ptr compare against W_NIL. Using `:nil` (the previous tag) caused
        // every `x == nil` in the bootstrap to fall through to a polymorphic
        // w_eq/w_neq runtime call, which is the bulk of the residual stage1
        // vs stage2 .ll diff.
        node = node_hash(p, "nil_lit", pos, err);
      } else if (strcmp(text, "self") == 0) {
        node = node_hash(p, "self", pos, err);
      }
      break;
    default:
      break;
  }

  free(text);
  if (node.kind == TC_AST_NIL) return raw_node(p, "expr", pos, pos + 1, err);
  return node;
}

static int parse_block_params_ast(TcAstParser *p, size_t *pos, size_t end, TcAstValue *params, TcError *err) {
  *params = tc_ast_array_new(err);
  if (params->kind != TC_AST_ARRAY) return 0;
  if (*pos >= end || p->tokens->items[*pos].kind != TC_K_LPAREN) return 1;
  (*pos)++;
  while (*pos < end && p->tokens->items[*pos].kind != TC_K_RPAREN) {
    TcKind kind = p->tokens->items[*pos].kind;
    if (kind == TC_K_COMMA) {
      (*pos)++;
      continue;
    }
    if (kind == TC_K_STAR || kind == TC_K_POW || kind == TC_K_AMPERSAND) {
      (*pos)++;
      continue;
    }
    if (!name_kind_ast(kind)) {
      parse_ast_error(p, err, "expected block parameter name");
      tc_ast_free(*params);
      return 0;
    }
    char *name = NULL;
    size_t name_len = 0;
    if (!token_text_at_ast(p, *pos, &name, &name_len, err)) {
      tc_ast_free(*params);
      return 0;
    }
    if (!tc_ast_array_push(*params, tc_ast_string_copy(name, name_len, err), err)) {
      free(name);
      tc_ast_free(*params);
      return 0;
    }
    free(name);
    (*pos)++;
  }
  if (*pos >= end || p->tokens->items[*pos].kind != TC_K_RPAREN) {
    parse_ast_error(p, err, "expected ')' after block params");
    tc_ast_free(*params);
    return 0;
  }
  (*pos)++;
  return 1;
}

static TcAstValue block_node_ast(TcAstParser *p, size_t start, TcAstValue params, TcAstValue body, TcError *err) {
  TcAstValue block = node_hash(p, "block", start, err);
  if (block.kind != TC_AST_HASH) {
    tc_ast_free(params);
    tc_ast_free(body);
    return block;
  }
  if (!tc_ast_hash_set(block, "params", params, err) ||
      !tc_ast_hash_set(block, "body", body, err)) {
    tc_ast_free(block);
    return tc_ast_nil();
  }
  return block;
}

static TcAstValue parse_lambda_span_ast(TcAstParser *p, size_t arrow_pos, size_t end, TcError *err) {
  size_t pos = arrow_pos + 1;
  TcAstValue params;
  if (!parse_block_params_ast(p, &pos, end, &params, err)) return tc_ast_nil();

  TcAstValue body = tc_ast_array_new(err);
  if (body.kind != TC_AST_ARRAY) {
    tc_ast_free(params);
    return tc_ast_nil();
  }
  trim_expr_span_ast(p, &pos, &end);
  if (pos < end) {
    TcAstValue expr = parse_expr_span_ast(p, pos, end, err);
    if (expr.kind == TC_AST_NIL || !tc_ast_array_push(body, expr, err)) {
      tc_ast_free(expr);
      tc_ast_free(body);
      tc_ast_free(params);
      return tc_ast_nil();
    }
  }
  return block_node_ast(p, arrow_pos, params, body, err);
}

static int attach_block_body_ast(TcAstValue node, TcAstValue body, TcError *err) {
  if (ast_node_is(node, "block")) return tc_ast_hash_set(node, "body", body, err);
  if (ast_node_is(node, "assign") || ast_node_is(node, "compound_assign")) {
    TcAstValue *value = hash_value_ast(node, "value");
    if (!value) return 0;
    return attach_block_body_ast(*value, body, err);
  }
  if (!ast_node_is(node, "call")) return 0;
  TcAstValue *block = hash_value_ast(node, "block");
  if (!block || block->kind == TC_AST_NIL) return 0;
  if (!ast_node_is(*block, "block")) return 0;
  return tc_ast_hash_set(*block, "body", body, err);
}

static TcAstValue arrow_call_or_block_ast(TcAstParser *p, size_t start, size_t end, size_t arrow_pos, TcError *err) {
  TcAstValue left = parse_expr_span_ast(p, start, arrow_pos, err);
  TcAstValue block = parse_lambda_span_ast(p, arrow_pos, end, err);
  if (left.kind == TC_AST_NIL || block.kind == TC_AST_NIL) {
    tc_ast_free(left);
    tc_ast_free(block);
    return tc_ast_nil();
  }

  if (ast_node_is(left, "call")) {
    if (!tc_ast_hash_set(left, "block", block, err)) {
      tc_ast_free(left);
      return tc_ast_nil();
    }
    return left;
  }

  if (ast_node_is(left, "var")) {
    TcAstValue *name = hash_value_ast(left, "name");
    if (name && ast_string_eq(*name, "each")) {
      tc_ast_free(left);
      TcAstValue args = tc_ast_array_new(err);
      if (args.kind != TC_AST_ARRAY) {
        tc_ast_free(block);
        return tc_ast_nil();
      }
      TcAstValue call = call_node_ast(p, start, tc_ast_nil(), "each", 4, args, err);
      if (call.kind == TC_AST_HASH && !tc_ast_hash_set(call, "block", block, err)) {
        tc_ast_free(call);
        return tc_ast_nil();
      }
      return call;
    }
  }

  TcAstValue args = tc_ast_array_new(err);
  if (args.kind != TC_AST_ARRAY) {
    tc_ast_free(left);
    tc_ast_free(block);
    return tc_ast_nil();
  }
  TcAstValue call = call_node_ast(p, start, left, "each", 4, args, err);
  if (call.kind == TC_AST_HASH && !tc_ast_hash_set(call, "block", block, err)) {
    tc_ast_free(call);
    return tc_ast_nil();
  }
  return call;
}

static TcAstValue unary_node_ast(TcAstParser *p, const char *op, size_t start, size_t operand_start, size_t end,
                                 TcError *err) {
  TcAstValue operand = parse_expr_span_ast(p, operand_start, end, err);
  if (operand.kind == TC_AST_NIL) return tc_ast_nil();
  TcAstValue node = node_hash(p, strcmp(op, "BANG") == 0 ? "not" : "unary_op", start, err);
  if (node.kind != TC_AST_HASH) {
    tc_ast_free(operand);
    return node;
  }
  if (strcmp(op, "BANG") == 0) {
    if (!tc_ast_hash_set(node, "operand", operand, err)) {
      tc_ast_free(node);
      return tc_ast_nil();
    }
    return node;
  }
  if (!tc_ast_hash_set(node, "op", tc_ast_symbol_copy(op, strlen(op), err), err) ||
      !tc_ast_hash_set(node, "operand", operand, err)) {
    tc_ast_free(node);
    return tc_ast_nil();
  }
  return node;
}

static TcAstValue parse_array_literal_ast(TcAstParser *p, size_t start, size_t end, TcError *err) {
  TcAstValue elements;
  if (!parse_expr_list_ast(p, start + 1, end - 1, &elements, err)) return tc_ast_nil();
  TcAstValue node = node_hash(p, "array", start, err);
  if (node.kind != TC_AST_HASH) {
    tc_ast_free(elements);
    return node;
  }
  if (!tc_ast_hash_set(node, "elements", elements, err)) {
    tc_ast_free(node);
    return tc_ast_nil();
  }
  return node;
}

static int split_hash_entry_ast(TcAstParser *p, size_t start, size_t end, size_t *sep_out) {
  int paren = 0;
  int bracket = 0;
  int brace = 0;
  for (size_t pos = start; pos < end; pos++) {
    TcKind cur = p->tokens->items[pos].kind;
    if (cur == TC_K_LPAREN) paren++;
    else if (cur == TC_K_RPAREN) paren--;
    else if (cur == TC_K_LBRACKET) bracket++;
    else if (cur == TC_K_RBRACKET) bracket--;
    else if (cur == TC_K_LBRACE) brace++;
    else if (cur == TC_K_RBRACE) brace--;
    else if (paren == 0 && bracket == 0 && brace == 0 && (cur == TC_K_FAT_ARROW || cur == TC_K_COLON)) {
      *sep_out = pos;
      return 1;
    }
  }
  return 0;
}

static TcAstValue hash_shorthand_key_ast(TcAstParser *p, size_t start, size_t sep, TcError *err) {
  if (sep == start + 1) {
    TcKind kind = p->tokens->items[start].kind;
    if (kind == TC_K_ID || kind == TC_K_TYPE || kind == TC_K_KEYWORD || kind == TC_K_NAME) {
      char *text = NULL;
      size_t text_len = 0;
      if (!token_text_at_ast(p, start, &text, &text_len, err)) return tc_ast_nil();
      TcAstValue node = node_hash(p, "symbol", start, err);
      if (node.kind == TC_AST_HASH &&
          !tc_ast_hash_set(node, "value", tc_ast_string_copy(text, text_len, err), err)) {
        tc_ast_free(node);
        node = tc_ast_nil();
      }
      free(text);
      return node;
    }
  }
  return parse_expr_span_ast(p, start, sep, err);
}

static TcAstValue hash_shorthand_value_ast(TcAstParser *p, size_t start, TcError *err) {
  char *text = NULL;
  size_t text_len = 0;
  if (!token_text_at_ast(p, start, &text, &text_len, err)) return tc_ast_nil();
  TcAstValue node = node_hash(p, "var", start, err);
  if (node.kind == TC_AST_HASH &&
      !tc_ast_hash_set(node, "name", tc_ast_string_copy(text, text_len, err), err)) {
    tc_ast_free(node);
    node = tc_ast_nil();
  }
  free(text);
  return node;
}

static TcAstValue parse_hash_entry_ast(TcAstParser *p, size_t start, size_t end, TcError *err) {
  trim_expr_span_ast(p, &start, &end);
  size_t sep = 0;
  if (!split_hash_entry_ast(p, start, end, &sep)) return raw_node(p, "hash_entry", start, end, err);
  TcAstValue pair = tc_ast_array_new(err);
  if (pair.kind != TC_AST_ARRAY) return pair;
  TcAstValue key = p->tokens->items[sep].kind == TC_K_COLON ? hash_shorthand_key_ast(p, start, sep, err)
                                                            : parse_expr_span_ast(p, start, sep, err);
  TcAstValue value = tc_ast_nil();
  if (sep + 1 >= end) value = hash_shorthand_value_ast(p, start, err);
  else value = parse_expr_span_ast(p, sep + 1, end, err);
  if (key.kind == TC_AST_NIL || value.kind == TC_AST_NIL ||
      !tc_ast_array_push(pair, key, err) ||
      !tc_ast_array_push(pair, value, err)) {
    tc_ast_free(key);
    tc_ast_free(value);
    tc_ast_free(pair);
    return tc_ast_nil();
  }
  return pair;
}

static TcAstValue parse_hash_literal_ast(TcAstParser *p, size_t start, size_t end, TcError *err) {
  TcAstValue entries = tc_ast_array_new(err);
  if (entries.kind != TC_AST_ARRAY) return entries;

  size_t inner_start = start + 1;
  size_t inner_end = end - 1;
  trim_expr_span_ast(p, &inner_start, &inner_end);
  size_t item_start = inner_start;
  int paren = 0;
  int bracket = 0;
  int brace = 0;
  for (size_t pos = inner_start; pos <= inner_end; pos++) {
    TcKind cur = pos < inner_end ? p->tokens->items[pos].kind : TC_K_COMMA;
    int split = 0;
    if (pos == inner_end) split = item_start < inner_end;
    else if (cur == TC_K_LPAREN) paren++;
    else if (cur == TC_K_RPAREN) paren--;
    else if (cur == TC_K_LBRACKET) bracket++;
    else if (cur == TC_K_RBRACKET) bracket--;
    else if (cur == TC_K_LBRACE) brace++;
    else if (cur == TC_K_RBRACE) brace--;
    else if (paren == 0 && bracket == 0 && brace == 0 && cur == TC_K_COMMA) split = 1;

    if (split) {
      TcAstValue entry = parse_hash_entry_ast(p, item_start, pos, err);
      if (entry.kind == TC_AST_NIL || !tc_ast_array_push(entries, entry, err)) {
        tc_ast_free(entry);
        tc_ast_free(entries);
        return tc_ast_nil();
      }
      item_start = pos + 1;
    }
  }

  TcAstValue node = node_hash(p, "hash_literal", start, err);
  if (node.kind != TC_AST_HASH) {
    tc_ast_free(entries);
    return node;
  }
  if (!tc_ast_hash_set(node, "entries", entries, err)) {
    tc_ast_free(node);
    return tc_ast_nil();
  }
  return node;
}

static TcAstValue single_expr_body_ast(TcAstValue expr, TcError *err) {
  TcAstValue body = tc_ast_array_new(err);
  if (body.kind != TC_AST_ARRAY) {
    tc_ast_free(expr);
    return tc_ast_nil();
  }
  if (!tc_ast_array_push(body, expr, err)) {
    tc_ast_free(expr);
    tc_ast_free(body);
    return tc_ast_nil();
  }
  return body;
}

static TcAstValue not_node_from_operand_ast(TcAstParser *p, size_t start, TcAstValue operand, TcError *err) {
  TcAstValue node = node_hash(p, "not", start, err);
  if (node.kind != TC_AST_HASH) {
    tc_ast_free(operand);
    return node;
  }
  if (!tc_ast_hash_set(node, "operand", operand, err)) {
    tc_ast_free(node);
    return tc_ast_nil();
  }
  return node;
}

static TcAstValue parse_suffix_expr_ast(TcAstParser *p, size_t start, size_t end, TcError *err) {
  size_t suffix_pos = 0;
  const char *suffix = NULL;
  if (top_level_keyword_ast(p, start, end, "if", &suffix_pos, 1) && suffix_pos > start) {
    suffix = "if";
  } else if (top_level_keyword_ast(p, start, end, "unless", &suffix_pos, 1) && suffix_pos > start) {
    suffix = "unless";
  } else if (top_level_keyword_ast(p, start, end, "while", &suffix_pos, 1) && suffix_pos > start) {
    suffix = "while";
  } else if (top_level_keyword_ast(p, start, end, "rescue", &suffix_pos, 1) && suffix_pos > start) {
    suffix = "rescue";
  }
  if (!suffix) return tc_ast_nil();

  TcAstValue expr = parse_expr_span_ast(p, start, suffix_pos, err);
  TcAstValue rhs = parse_expr_span_ast(p, suffix_pos + 1, end, err);
  if (expr.kind == TC_AST_NIL || rhs.kind == TC_AST_NIL) {
    tc_ast_free(expr);
    tc_ast_free(rhs);
    return tc_ast_nil();
  }

  if (strcmp(suffix, "rescue") == 0) {
    TcAstValue node = node_hash(p, "rescue_expr", suffix_pos, err);
    if (node.kind != TC_AST_HASH) {
      tc_ast_free(expr);
      tc_ast_free(rhs);
      return node;
    }
    if (!tc_ast_hash_set(node, "body", expr, err) ||
        !tc_ast_hash_set(node, "fallback", rhs, err)) {
      tc_ast_free(node);
      return tc_ast_nil();
    }
    return node;
  }

  TcAstValue body = single_expr_body_ast(expr, err);
  if (body.kind != TC_AST_ARRAY) {
    tc_ast_free(rhs);
    return tc_ast_nil();
  }
  TcAstValue condition = rhs;
  if (strcmp(suffix, "unless") == 0) {
    condition = not_node_from_operand_ast(p, suffix_pos, rhs, err);
    if (condition.kind == TC_AST_NIL) {
      tc_ast_free(body);
      return tc_ast_nil();
    }
  }

  if (strcmp(suffix, "while") == 0) {
    TcAstValue node = node_hash(p, "while", suffix_pos, err);
    if (node.kind != TC_AST_HASH) {
      tc_ast_free(condition);
      tc_ast_free(body);
      return node;
    }
    if (!tc_ast_hash_set(node, "condition", condition, err) ||
        !tc_ast_hash_set(node, "body", body, err)) {
      tc_ast_free(node);
      return tc_ast_nil();
    }
    return node;
  }

  TcAstValue node = node_hash(p, "if", suffix_pos, err);
  if (node.kind != TC_AST_HASH) {
    tc_ast_free(condition);
    tc_ast_free(body);
    return node;
  }
  TcAstValue elsif_clauses = tc_ast_array_new(err);
  if (elsif_clauses.kind != TC_AST_ARRAY ||
      !tc_ast_hash_set(node, "condition", condition, err) ||
      !tc_ast_hash_set(node, "then_body", body, err) ||
      !tc_ast_hash_set(node, "elsif_clauses", elsif_clauses, err) ||
      !tc_ast_hash_set(node, "else_body", tc_ast_nil(), err)) {
    tc_ast_free(node);
    return tc_ast_nil();
  }
  return node;
}

static TcAstValue parse_index_call_ast(TcAstParser *p, size_t start, size_t end, TcError *err) {
  if (end <= start + 2 || p->tokens->items[end - 1].kind != TC_K_RBRACKET) return tc_ast_nil();

  size_t open = 0;
  if (!top_level_token_ast(p, start, end, TC_K_LBRACKET, &open, 1) || open <= start) return tc_ast_nil();

  TcAstValue receiver = parse_expr_span_ast(p, start, open, err);
  if (receiver.kind == TC_AST_NIL) return tc_ast_nil();
  TcAstValue args;
  if (!parse_expr_list_ast(p, open + 1, end - 1, &args, err)) {
    tc_ast_free(receiver);
    return tc_ast_nil();
  }
  return call_node_ast(p, start, receiver, "[]", 2, args, err);
}

static TcAstValue parse_typed_array_ast(TcAstParser *p, size_t start, size_t end, TcError *err) {
  if (end <= start + 3 || p->tokens->items[start].kind != TC_K_TYPE ||
      p->tokens->items[start + 1].kind != TC_K_LBRACKET || p->tokens->items[end - 1].kind != TC_K_RBRACKET ||
      !wrapped_span_ast(p, start + 1, end, TC_K_LBRACKET, TC_K_RBRACKET)) {
    return tc_ast_nil();
  }

  char *etype = NULL;
  size_t etype_len = 0;
  if (!token_text_at_ast(p, start, &etype, &etype_len, err)) return tc_ast_nil();
  TcAstValue size = parse_expr_span_ast(p, start + 2, end - 1, err);
  if (size.kind == TC_AST_NIL) {
    free(etype);
    return tc_ast_nil();
  }
  TcAstValue node = node_hash(p, "typed_array", start, err);
  if (node.kind != TC_AST_HASH) {
    free(etype);
    tc_ast_free(size);
    return node;
  }
  if (!tc_ast_hash_set(node, "element_type", tc_ast_string_copy(etype, etype_len, err), err) ||
      !tc_ast_hash_set(node, "size", size, err)) {
    free(etype);
    tc_ast_free(node);
    return tc_ast_nil();
  }
  free(etype);
  return node;
}

static int parse_tuple_elements_ast(TcAstParser *p, size_t start, size_t end, TcAstValue *out, TcError *err) {
  trim_expr_span_ast(p, &start, &end);
  if (top_level_token_ast(p, start, end, TC_K_COMMA, &(size_t){0}, 0)) {
    return parse_expr_list_ast(p, start, end, out, err);
  }

  TcAstValue elements = tc_ast_array_new(err);
  if (elements.kind != TC_AST_ARRAY) return 0;
  size_t pos = start;
  while (pos < end) {
    while (pos < end && (p->tokens->items[pos].kind == TC_K_NEWLINE ||
                         p->tokens->items[pos].kind == TC_K_SEMICOLON ||
                         p->tokens->items[pos].kind == TC_K_COMMA)) {
      pos++;
    }
    if (pos >= end) break;
    TcAstValue item = parse_expr_span_ast(p, pos, pos + 1, err);
    if (item.kind == TC_AST_NIL || !tc_ast_array_push(elements, item, err)) {
      tc_ast_free(item);
      tc_ast_free(elements);
      return 0;
    }
    pos++;
  }
  *out = elements;
  return 1;
}

static TcAstValue parse_in_test_ast(TcAstParser *p, size_t start, size_t end, size_t op_pos, TcError *err) {
  TcAstValue lhs = parse_expr_span_ast(p, start, op_pos, err);
  if (lhs.kind == TC_AST_NIL) return tc_ast_nil();

  size_t rhs_start = op_pos + 1;
  size_t rhs_end = end;
  trim_expr_span_ast(p, &rhs_start, &rhs_end);
  TcAstValue elements;
  if (wrapped_span_ast(p, rhs_start, rhs_end, TC_K_LPAREN, TC_K_RPAREN)) {
    if (!parse_tuple_elements_ast(p, rhs_start + 1, rhs_end - 1, &elements, err)) {
      tc_ast_free(lhs);
      return tc_ast_nil();
    }
  } else if (!parse_expr_list_ast(p, rhs_start, rhs_end, &elements, err)) {
    tc_ast_free(lhs);
    return tc_ast_nil();
  }

  TcAstValue node = node_hash(p, "in_test", op_pos, err);
  if (node.kind != TC_AST_HASH) {
    tc_ast_free(lhs);
    tc_ast_free(elements);
    return node;
  }
  if (!tc_ast_hash_set(node, "lhs", lhs, err) ||
      !tc_ast_hash_set(node, "elements", elements, err)) {
    tc_ast_free(node);
    return tc_ast_nil();
  }
  return node;
}

static TcAstValue parse_ternary_ast(TcAstParser *p, size_t start, size_t end, TcError *err) {
  size_t question = 0;
  if (!top_level_token_ast(p, start, end, TC_K_QUESTION, &question, 0) || question <= start) return tc_ast_nil();
  size_t colon = 0;
  if (!top_level_token_ast(p, question + 1, end, TC_K_COLON, &colon, 0) || colon <= question + 1) {
    return tc_ast_nil();
  }

  TcAstValue condition = parse_expr_span_ast(p, start, question, err);
  TcAstValue then_expr = parse_expr_span_ast(p, question + 1, colon, err);
  TcAstValue else_expr = parse_expr_span_ast(p, colon + 1, end, err);
  if (condition.kind == TC_AST_NIL || then_expr.kind == TC_AST_NIL || else_expr.kind == TC_AST_NIL) {
    tc_ast_free(condition);
    tc_ast_free(then_expr);
    tc_ast_free(else_expr);
    return tc_ast_nil();
  }
  TcAstValue then_body = single_expr_body_ast(then_expr, err);
  TcAstValue else_body = single_expr_body_ast(else_expr, err);
  if (then_body.kind != TC_AST_ARRAY || else_body.kind != TC_AST_ARRAY) {
    tc_ast_free(condition);
    tc_ast_free(then_body);
    tc_ast_free(else_body);
    return tc_ast_nil();
  }
  TcAstValue node = node_hash(p, "if", question, err);
  TcAstValue elsif_clauses = tc_ast_array_new(err);
  if (node.kind != TC_AST_HASH || elsif_clauses.kind != TC_AST_ARRAY ||
      !tc_ast_hash_set(node, "condition", condition, err) ||
      !tc_ast_hash_set(node, "then_body", then_body, err) ||
      !tc_ast_hash_set(node, "elsif_clauses", elsif_clauses, err) ||
      !tc_ast_hash_set(node, "else_body", else_body, err)) {
    tc_ast_free(node);
    return tc_ast_nil();
  }
  return node;
}

static TcAstValue parse_range_ast(TcAstParser *p, size_t start, size_t end, TcError *err) {
  static const TcKind range_ops[] = {TC_K_DOTDOTDOT, TC_K_DOTDOT};
  size_t op_pos = 0;
  if (!top_level_any_ast(p, start, end, range_ops, sizeof(range_ops) / sizeof(range_ops[0]), &op_pos) ||
      op_pos <= start) {
    return tc_ast_nil();
  }
  TcAstValue from = parse_expr_span_ast(p, start, op_pos, err);
  TcAstValue to = parse_expr_span_ast(p, op_pos + 1, end, err);
  if (from.kind == TC_AST_NIL || to.kind == TC_AST_NIL) {
    tc_ast_free(from);
    tc_ast_free(to);
    return tc_ast_nil();
  }
  TcAstValue node = node_hash(p, "range", op_pos, err);
  if (node.kind != TC_AST_HASH) {
    tc_ast_free(from);
    tc_ast_free(to);
    return node;
  }
  if (!tc_ast_hash_set(node, "from", from, err) ||
      !tc_ast_hash_set(node, "to", to, err) ||
      !tc_ast_hash_set(node, "exclusive", tc_ast_bool(p->tokens->items[op_pos].kind == TC_K_DOTDOTDOT), err)) {
    tc_ast_free(node);
    return tc_ast_nil();
  }
  return node;
}

static TcAstValue parse_keyword_arg_ast(TcAstParser *p, size_t start, size_t end, TcError *err) {
  if (end <= start + 2 || !name_kind_ast(p->tokens->items[start].kind) ||
      p->tokens->items[start + 1].kind != TC_K_COLON) {
    return tc_ast_nil();
  }
  char *key = NULL;
  size_t key_len = 0;
  if (!token_text_at_ast(p, start, &key, &key_len, err)) return tc_ast_nil();
  TcAstValue value = parse_expr_span_ast(p, start + 2, end, err);
  if (value.kind == TC_AST_NIL) {
    free(key);
    return tc_ast_nil();
  }
  TcAstValue pair = tc_ast_array_new(err);
  TcAstValue entries = tc_ast_array_new(err);
  TcAstValue node = node_hash(p, "hash_literal", start, err);
  if (pair.kind != TC_AST_ARRAY || entries.kind != TC_AST_ARRAY || node.kind != TC_AST_HASH ||
      !tc_ast_array_push(pair, tc_ast_symbol_copy(key, key_len, err), err) ||
      !tc_ast_array_push(pair, value, err) ||
      !tc_ast_array_push(entries, pair, err) ||
      !tc_ast_hash_set(node, "entries", entries, err) ||
      !tc_ast_hash_set(node, "from_kwargs", tc_ast_bool(1), err)) {
    free(key);
    tc_ast_free(value);
    tc_ast_free(pair);
    tc_ast_free(entries);
    tc_ast_free(node);
    return tc_ast_nil();
  }
  free(key);
  return node;
}

static TcAstValue parse_io_ast(TcAstParser *p, size_t start, size_t end, TcError *err) {
  TcKind kind = p->tokens->items[start].kind;
  if (!(kind == TC_K_PUTS_OP || kind == TC_K_LSHIFT || kind == TC_K_PRINT_OP)) return tc_ast_nil();
  TcAstValue value = start + 1 < end ? parse_expr_span_ast(p, start + 1, end, err) : tc_ast_nil();
  if (start + 1 < end && value.kind == TC_AST_NIL) return tc_ast_nil();
  TcAstValue node = node_hash(p, kind == TC_K_PRINT_OP ? "print" : "puts", start, err);
  if (node.kind != TC_AST_HASH) {
    tc_ast_free(value);
    return node;
  }
  if (!tc_ast_hash_set(node, "value", value, err)) {
    tc_ast_free(node);
    return tc_ast_nil();
  }
  return node;
}

static TcAstValue parse_expr_span_ast(TcAstParser *p, size_t start, size_t end, TcError *err) {
  trim_expr_span_ast(p, &start, &end);
  if (start >= end) return tc_ast_nil();

  TcAstValue suffix = parse_suffix_expr_ast(p, start, end, err);
  if (suffix.kind != TC_AST_NIL) return suffix;

  TcAstValue io = parse_io_ast(p, start, end, err);
  if (io.kind != TC_AST_NIL) return io;

  if (token_is_keyword_at_ast(p, start, "return")) {
    TcAstValue node = node_hash(p, "return", start, err);
    if (node.kind != TC_AST_HASH) return node;
    TcAstValue value = parse_expr_span_ast(p, start + 1, end, err);
    if (!tc_ast_hash_set(node, "value", value, err)) {
      tc_ast_free(node);
      return tc_ast_nil();
    }
    return node;
  }
  if (token_is_keyword_at_ast(p, start, "break") || token_is_keyword_at_ast(p, start, "next")) {
    return node_hash(p, token_is_keyword_at_ast(p, start, "break") ? "break" : "next", start, err);
  }

  TcAstValue compound = parse_compound_assign_ast(p, start, end, err);
  if (compound.kind != TC_AST_NIL) return compound;

  size_t assign_pos = 0;
  if (top_level_token_ast(p, start, end, TC_K_ASSIGN, &assign_pos, 1) && assign_pos > start) {
    TcAstValue target = parse_expr_span_ast(p, start, assign_pos, err);
    size_t value_end = end;
    TcAstValue type_hint = tc_ast_nil();
    size_t hint_pos = 0;
    if (top_level_token_ast(p, assign_pos + 1, end, TC_K_TYPE_HINT, &hint_pos, 1)) {
      value_end = hint_pos;
      char *hint = NULL;
      size_t hint_len = 0;
      if (!token_text_at_ast(p, hint_pos, &hint, &hint_len, err)) {
        tc_ast_free(target);
        return tc_ast_nil();
      }
      type_hint = tc_ast_string_copy(hint, hint_len, err);
      free(hint);
    }
    TcAstValue value = parse_expr_span_ast(p, assign_pos + 1, value_end, err);
    if (target.kind == TC_AST_NIL || value.kind == TC_AST_NIL) {
      tc_ast_free(target);
      tc_ast_free(value);
      tc_ast_free(type_hint);
      return tc_ast_nil();
    }
    if (type_hint.kind == TC_AST_STRING && value.kind == TC_AST_HASH) {
      if (ast_string_eq(type_hint, "reuse")) {
        tc_ast_hash_set(value, "reuse_safe", tc_ast_bool(1), err);
        tc_ast_free(type_hint);
        type_hint = tc_ast_nil();
      } else if (ast_string_eq(type_hint, "recycle")) {
        tc_ast_hash_set(value, "recycle_safe", tc_ast_bool(1), err);
        tc_ast_free(type_hint);
        type_hint = tc_ast_nil();
      } else if (ast_string_eq(type_hint, "reuse_drain")) {
        tc_ast_hash_set(value, "reuse_safe", tc_ast_bool(1), err);
        tc_ast_hash_set(value, "drain_safe", tc_ast_bool(1), err);
        tc_ast_free(type_hint);
        type_hint = tc_ast_nil();
      } else if (ast_string_eq(type_hint, "stack")) {
        tc_ast_hash_set(value, "stack_safe", tc_ast_bool(1), err);
        tc_ast_free(type_hint);
        type_hint = tc_ast_nil();
      }
    }
    if (ast_node_is(target, "call")) {
      TcAstValue *name = hash_value_ast(target, "name");
      TcAstValue *args = hash_value_ast(target, "args");
      if (name && ast_string_eq(*name, "[]") && args && args->kind == TC_AST_ARRAY) {
        if (!tc_ast_array_push(*args, value, err) ||
            !tc_ast_hash_set(target, "name", tc_ast_string_copy("[]=", 3, err), err)) {
          tc_ast_free(type_hint);
          tc_ast_free(target);
          return tc_ast_nil();
        }
        tc_ast_free(type_hint);
        return target;
      }
    }
    TcAstValue node = node_hash(p, "assign", assign_pos, err);
    if (node.kind != TC_AST_HASH) {
      tc_ast_free(target);
      tc_ast_free(value);
      tc_ast_free(type_hint);
      return node;
    }
    if (!tc_ast_hash_set(node, "target", target, err) ||
        !tc_ast_hash_set(node, "value", value, err) ||
        !tc_ast_hash_set(node, "type_hint", type_hint, err)) {
      tc_ast_free(node);
      return tc_ast_nil();
    }
    return node;
  }

  size_t arrow_pos = 0;
  if (top_level_token_ast(p, start, end, TC_K_ARROW, &arrow_pos, 0) && arrow_pos > start) {
    return arrow_call_or_block_ast(p, start, end, arrow_pos, err);
  }

  TcAstValue ternary = parse_ternary_ast(p, start, end, err);
  if (ternary.kind != TC_AST_NIL) return ternary;

  TcAstValue range = parse_range_ast(p, start, end, err);
  if (range.kind != TC_AST_NIL) return range;

  TcAstValue keyword_arg = parse_keyword_arg_ast(p, start, end, err);
  if (keyword_arg.kind != TC_AST_NIL) return keyword_arg;

  /* Qualified-name expression check, BEFORE the bare-command-call
   * path. `AST :Foo` (Type/Name followed by exactly N >= 1 :Symbol
   * tokens, spanning the whole expression) is a namespace-qualified
   * variable reference, not a command call with a symbol arg. The
   * class-declaration path already accepts the same shape via
   * parse_name_path_ast; this brings expression-position parity. */
  if ((p->tokens->items[start].kind == TC_K_TYPE ||
       p->tokens->items[start].kind == TC_K_NAME) &&
      start + 1 < end && p->tokens->items[start + 1].kind == TC_K_SYMBOL) {
    size_t pos = start + 1;
    while (pos < end && p->tokens->items[pos].kind == TC_K_SYMBOL) pos++;
    if (pos == end) {
      char *part = NULL;
      size_t part_len = 0;
      if (!token_text_at_ast(p, start, &part, &part_len, err)) return tc_ast_nil();
      char *qname = NULL;
      size_t qname_len = 0;
      if (!append_bytes(&qname, &qname_len, part, part_len, err)) {
        free(part);
        return tc_ast_nil();
      }
      free(part);
      for (size_t i = start + 1; i < end; i++) {
        if (!token_text_at_ast(p, i, &part, &part_len, err)) {
          free(qname);
          return tc_ast_nil();
        }
        if (!append_bytes(&qname, &qname_len, part, part_len, err)) {
          free(part);
          free(qname);
          return tc_ast_nil();
        }
        free(part);
      }
      TcAstValue node = node_hash(p, "var", start, err);
      if (node.kind == TC_AST_HASH &&
          !tc_ast_hash_set(node, "name", tc_ast_string_copy(qname, qname_len, err), err)) {
        tc_ast_free(node);
        free(qname);
        return tc_ast_nil();
      }
      free(qname);
      return node;
    }
  }

  TcAstValue command_call = parse_bare_command_call_ast(p, start, end, 1, err);
  if (command_call.kind != TC_AST_NIL) return command_call;

  static const TcKind low_ops[] = {TC_K_OR, TC_K_AND};
  // OR/AND must produce {node: "or" | "and"} — see logical_node_ast.
  static const TcKind bitwise_or_ops[] = {TC_K_PIPE, TC_K_DOT_PIPE};
  static const TcKind bitwise_xor_ops[] = {TC_K_CARET, TC_K_DOT_CARET};
  static const TcKind bitwise_and_ops[] = {TC_K_AMPERSAND, TC_K_DOT_AMP};
  static const TcKind cmp_ops[] = {TC_K_EQ, TC_K_NEQ, TC_K_LT, TC_K_LTE, TC_K_GT, TC_K_GTE, TC_K_MATCH};
  static const TcKind add_ops[] = {TC_K_PLUS, TC_K_MINUS, TC_K_DOT_PLUS, TC_K_DOT_MINUS};
  static const TcKind shift_ops[] = {TC_K_LSHIFT, TC_K_RSHIFT, TC_K_DOT_LSHIFT, TC_K_DOT_RSHIFT};
  static const TcKind mul_ops[] = {
      TC_K_STAR, TC_K_SLASH, TC_K_PERCENT, TC_K_DOT_STAR, TC_K_DOT_SLASH, TC_K_DOT_PRODUCT, TC_K_CROSS_PRODUCT};
  static const TcKind pow_ops[] = {TC_K_POW};
  size_t op_pos = 0;
  if (top_level_any_ast(p, start, end, low_ops, sizeof(low_ops) / sizeof(low_ops[0]), &op_pos)) {
    return logical_node_ast(p, start, end, op_pos, err);
  }
  if (top_level_keyword_ast(p, start, end, "in", &op_pos, 1)) {
    return parse_in_test_ast(p, start, end, op_pos, err);
  }
  if (top_level_any_ast(p, start, end, bitwise_or_ops, sizeof(bitwise_or_ops) / sizeof(bitwise_or_ops[0]), &op_pos)) {
    return binary_node_ast(p, start, end, op_pos, err);
  }
  if (top_level_any_ast(p, start, end, bitwise_xor_ops, sizeof(bitwise_xor_ops) / sizeof(bitwise_xor_ops[0]), &op_pos)) {
    return binary_node_ast(p, start, end, op_pos, err);
  }
  if (top_level_any_ast(p, start, end, bitwise_and_ops, sizeof(bitwise_and_ops) / sizeof(bitwise_and_ops[0]), &op_pos)) {
    return binary_node_ast(p, start, end, op_pos, err);
  }
  if (top_level_any_ast(p, start, end, cmp_ops, sizeof(cmp_ops) / sizeof(cmp_ops[0]), &op_pos)) {
    return binary_node_ast(p, start, end, op_pos, err);
  }
  if (top_level_any_ast(p, start, end, add_ops, sizeof(add_ops) / sizeof(add_ops[0]), &op_pos) && op_pos > start) {
    return binary_node_ast(p, start, end, op_pos, err);
  }
  if (top_level_any_ast(p, start, end, shift_ops, sizeof(shift_ops) / sizeof(shift_ops[0]), &op_pos) && op_pos > start) {
    return binary_node_ast(p, start, end, op_pos, err);
  }
  if (top_level_any_ast(p, start, end, mul_ops, sizeof(mul_ops) / sizeof(mul_ops[0]), &op_pos) && op_pos > start) {
    return binary_node_ast(p, start, end, op_pos, err);
  }
  if (top_level_any_ast(p, start, end, pow_ops, sizeof(pow_ops) / sizeof(pow_ops[0]), &op_pos) && op_pos > start) {
    return binary_node_ast(p, start, end, op_pos, err);
  }

  if (p->tokens->items[start].kind == TC_K_BANG && start + 1 < end) return unary_node_ast(p, "BANG", start, start + 1, end, err);
  if (p->tokens->items[start].kind == TC_K_MINUS && start + 1 < end) return unary_node_ast(p, "MINUS", start, start + 1, end, err);
  if (p->tokens->items[start].kind == TC_K_STAR && start + 1 < end) return unary_node_ast(p, "DEREF", start, start + 1, end, err);

  if (wrapped_span_ast(p, start, end, TC_K_LPAREN, TC_K_RPAREN)) {
    return parse_expr_span_ast(p, start + 1, end - 1, err);
  }
  if (wrapped_span_ast(p, start, end, TC_K_LBRACKET, TC_K_RBRACKET)) return parse_array_literal_ast(p, start, end, err);
  if (wrapped_span_ast(p, start, end, TC_K_LBRACE, TC_K_RBRACE)) return parse_hash_literal_ast(p, start, end, err);

  TcAstValue typed_array = parse_typed_array_ast(p, start, end, err);
  if (typed_array.kind != TC_AST_NIL) return typed_array;

  TcAstValue index_call = parse_index_call_ast(p, start, end, err);
  if (index_call.kind != TC_AST_NIL) return index_call;

  TcAstValue call = parse_call_span_ast(p, start, end, err);
  if (call.kind != TC_AST_NIL) return call;

  if (end == start + 1) return atom_node_ast(p, start, err);
  return raw_node(p, "expr", start, end, err);
}

static int parse_ast_body(TcAstParser *p, TcAstValue *out, TcError *err);
static int parse_ast_statement(TcAstParser *p, TcAstValue *out, TcError *err);

static int parse_optional_body_ast(TcAstParser *p, TcAstValue *out, TcError *err) {
  if (at_ast(p, TC_K_INDENT)) return parse_ast_body(p, out, err);
  *out = tc_ast_array_new(err);
  return out->kind == TC_AST_ARRAY;
}

static int parse_use_ast(TcAstParser *p, TcAstValue *out, TcError *err) {
  size_t start = p->pos;
  advance_ast(p);
  TcSyntaxToken path_tok = current_ast(p);
  if (!(path_tok.kind == TC_K_STRING || path_tok.kind == TC_K_ID || path_tok.kind == TC_K_NAME || path_tok.kind == TC_K_GLOBAL)) {
    parse_ast_error(p, err, "expected use path");
    return 0;
  }

  char *path = NULL;
  size_t path_len = 0;
  if (!tc_token_text_copy(p->source, path_tok.packed, &path, &path_len, err)) return 0;
  if (path_len >= 2 && ((path[0] == '"' && path[path_len - 1] == '"') || (path[0] == '\'' && path[path_len - 1] == '\''))) {
    memmove(path, path + 1, path_len - 2);
    path_len -= 2;
    path[path_len] = '\0';
  }
  advance_ast(p);
  if (!finish_header_ast(p, err)) {
    free(path);
    return 0;
  }

  TcAstValue h = tc_ast_hash_new(err);
  if (h.kind != TC_AST_HASH) {
    free(path);
    return 0;
  }
  p->stats.nodes++;
  p->stats.use_nodes++;
  if (!set_node(h, "use", err) ||
      !tc_ast_hash_set(h, "path", tc_ast_string_copy(path, path_len, err), err) ||
      !tc_ast_hash_set(h, "line", tc_ast_int(token_line_ast(p->source, p->tokens->items[start].packed)), err)) {
    free(path);
    tc_ast_free(h);
    return 0;
  }
  free(path);
  *out = h;
  return 1;
}

static int parse_header_block_ast(TcAstParser *p, const char *node_name, const char *header_key, TcAstValue *out,
                                  TcError *err) {
  size_t start = p->pos;
  advance_ast(p);
  size_t header_start = p->pos;
  size_t header_end = header_start;
  if (!finish_header_span_ast(p, &header_end, err)) return 0;

  TcAstValue node = node_hash(p, node_name, start, err);
  if (node.kind != TC_AST_HASH) return 0;
  TcAstValue header = strcmp(header_key, "condition") == 0
                          ? parse_expr_span_ast(p, header_start, header_end, err)
                          : raw_string(p, header_start, header_end, err);
  if (header.kind == TC_AST_NIL && header_start < header_end) {
    tc_ast_free(node);
    return 0;
  }

  TcAstValue body;
  if (!parse_optional_body_ast(p, &body, err)) {
    tc_ast_free(header);
    tc_ast_free(node);
    return 0;
  }

  if (!tc_ast_hash_set(node, header_key, header, err) ||
      !tc_ast_hash_set(node, "body", body, err)) {
    tc_ast_free(node);
    return 0;
  }
  *out = node;
  return 1;
}

static TcAstValue target_designator_node_ast(TcAstParser *p, size_t pos, TcError *err) {
  char *name = NULL;
  size_t name_len = 0;
  if (!token_text_at_ast(p, pos, &name, &name_len, err)) return tc_ast_nil();
  TcAstValue node = node_hash(p, "target_designator", pos, err);
  if (node.kind != TC_AST_HASH || !tc_ast_hash_set(node, "name", tc_ast_string_copy(name, name_len, err), err)) {
    tc_ast_free(node);
    node = tc_ast_nil();
  }
  free(name);
  return node;
}

static TcAstValue target_binary_node_ast(TcAstParser *p, const char *node_name, size_t pos, TcAstValue left,
                                         TcAstValue right, TcError *err) {
  TcAstValue node = node_hash(p, node_name, pos, err);
  if (node.kind != TC_AST_HASH ||
      !tc_ast_hash_set(node, "left", left, err) ||
      !tc_ast_hash_set(node, "right", right, err)) {
    tc_ast_free(node);
    return tc_ast_nil();
  }
  return node;
}

static TcAstValue parse_target_predicate_ast(TcAstParser *p, size_t start, size_t end, TcError *err) {
  trim_expr_span_ast(p, &start, &end);
  if (start >= end) return tc_ast_nil();
  if (wrapped_span_ast(p, start, end, TC_K_LPAREN, TC_K_RPAREN)) {
    return parse_target_predicate_ast(p, start + 1, end - 1, err);
  }

  size_t op_pos = 0;
  if (top_level_token_ast(p, start, end, TC_K_OR, &op_pos, 0)) {
    TcAstValue left = parse_target_predicate_ast(p, start, op_pos, err);
    TcAstValue right = parse_target_predicate_ast(p, op_pos + 1, end, err);
    return target_binary_node_ast(p, "target_or", op_pos, left, right, err);
  }
  if (top_level_token_ast(p, start, end, TC_K_AND, &op_pos, 0)) {
    TcAstValue left = parse_target_predicate_ast(p, start, op_pos, err);
    TcAstValue right = parse_target_predicate_ast(p, op_pos + 1, end, err);
    return target_binary_node_ast(p, "target_and", op_pos, left, right, err);
  }
  if (p->tokens->items[start].kind == TC_K_BANG && start + 1 < end) {
    TcAstValue expression = parse_target_predicate_ast(p, start + 1, end, err);
    TcAstValue node = node_hash(p, "target_not", start, err);
    if (node.kind != TC_AST_HASH || !tc_ast_hash_set(node, "expression", expression, err)) {
      tc_ast_free(node);
      return tc_ast_nil();
    }
    return node;
  }
  TcKind kind = p->tokens->items[start].kind;
  if (start + 1 == end && (kind == TC_K_ID || kind == TC_K_NAME || kind == TC_K_TYPE || kind == TC_K_KEYWORD)) {
    return target_designator_node_ast(p, start, err);
  }
  parse_ast_error(p, err, "invalid on target predicate");
  return tc_ast_nil();
}

static int parse_on_guard_ast(TcAstParser *p, TcAstValue *out, TcError *err) {
  size_t start = p->pos;
  advance_ast(p);
  size_t header_start = p->pos;
  size_t header_end = header_start;
  if (!finish_header_span_ast(p, &header_end, err)) return 0;

  size_t predicate_end = header_end;
  TcAstValue capabilities = tc_ast_array_new(err);
  if (capabilities.kind != TC_AST_ARRAY) return 0;
  for (size_t pos = header_start; pos < header_end; pos++) {
    if (token_is_keyword_at_ast(p, pos, "with")) {
      if (predicate_end == header_end) predicate_end = pos;
      if (pos + 1 >= header_end) {
        tc_ast_free(capabilities);
        parse_ast_error(p, err, "expected capability after with");
        return 0;
      }
      char *cap = NULL;
      size_t cap_len = 0;
      if (!token_text_at_ast(p, pos + 1, &cap, &cap_len, err)) {
        tc_ast_free(capabilities);
        return 0;
      }
      int ok = tc_ast_array_push(capabilities, tc_ast_string_copy(cap, cap_len, err), err);
      free(cap);
      if (!ok) {
        tc_ast_free(capabilities);
        return 0;
      }
      pos++;
    }
  }

  TcAstValue predicate = parse_target_predicate_ast(p, header_start, predicate_end, err);
  if (predicate.kind == TC_AST_NIL) {
    tc_ast_free(capabilities);
    return 0;
  }

  TcAstValue body;
  if (!parse_optional_body_ast(p, &body, err)) {
    tc_ast_free(predicate);
    tc_ast_free(capabilities);
    return 0;
  }

  TcAstValue node = node_hash(p, "on_guard", start, err);
  if (node.kind != TC_AST_HASH ||
      !tc_ast_hash_set(node, "predicate", predicate, err) ||
      !tc_ast_hash_set(node, "capabilities", capabilities, err) ||
      !tc_ast_hash_set(node, "body", body, err)) {
    tc_ast_free(node);
    return 0;
  }
  *out = node;
  return 1;
}

static int parse_if_ast(TcAstParser *p, TcAstValue *out, TcError *err) {
  size_t start = p->pos;
  int negated = at_keyword_ast(p, "unless");
  advance_ast(p);
  size_t condition_start = p->pos;
  size_t condition_end = condition_start;
  if (!finish_header_span_ast(p, &condition_end, err)) return 0;

  TcAstValue node = node_hash(p, "if", start, err);
  if (node.kind != TC_AST_HASH) return 0;

  TcAstValue condition = parse_expr_span_ast(p, condition_start, condition_end, err);
  if (condition.kind == TC_AST_NIL) {
    tc_ast_free(node);
    return 0;
  }
  if (negated) {
    condition = not_node_from_operand_ast(p, start, condition, err);
    if (condition.kind == TC_AST_NIL) {
      tc_ast_free(node);
      return 0;
    }
  }

  TcAstValue then_body;
  if (!parse_optional_body_ast(p, &then_body, err)) {
    tc_ast_free(condition);
    tc_ast_free(node);
    return 0;
  }

  TcAstValue elsif_clauses = tc_ast_array_new(err);
  if (elsif_clauses.kind != TC_AST_ARRAY) {
    tc_ast_free(condition);
    tc_ast_free(then_body);
    tc_ast_free(node);
    return 0;
  }

  while (at_keyword_ast(p, "elsif")) {
    advance_ast(p);
    size_t elsif_cond_start = p->pos;
    size_t elsif_cond_end = elsif_cond_start;
    if (!finish_header_span_ast(p, &elsif_cond_end, err)) {
      tc_ast_free(condition);
      tc_ast_free(elsif_clauses);
      tc_ast_free(then_body);
      tc_ast_free(node);
      return 0;
    }
    TcAstValue elsif_cond = parse_expr_span_ast(p, elsif_cond_start, elsif_cond_end, err);
    if (elsif_cond.kind == TC_AST_NIL) {
      tc_ast_free(condition);
      tc_ast_free(elsif_clauses);
      tc_ast_free(then_body);
      tc_ast_free(node);
      return 0;
    }
    TcAstValue elsif_body;
    if (!parse_optional_body_ast(p, &elsif_body, err)) {
      tc_ast_free(elsif_cond);
      tc_ast_free(condition);
      tc_ast_free(elsif_clauses);
      tc_ast_free(then_body);
      tc_ast_free(node);
      return 0;
    }
    TcAstValue pair = tc_ast_array_new(err);
    if (!tc_ast_array_push(pair, elsif_cond, err) ||
        !tc_ast_array_push(pair, elsif_body, err) ||
        !tc_ast_array_push(elsif_clauses, pair, err)) {
      tc_ast_free(condition);
      tc_ast_free(elsif_clauses);
      tc_ast_free(then_body);
      tc_ast_free(node);
      return 0;
    }
  }

  TcAstValue else_body = tc_ast_nil();
  if (at_keyword_ast(p, "else")) {
    advance_ast(p);
    if (!finish_header_ast(p, err) || !parse_optional_body_ast(p, &else_body, err)) {
      tc_ast_free(condition);
      tc_ast_free(elsif_clauses);
      tc_ast_free(then_body);
      tc_ast_free(node);
      return 0;
    }
  }

  if (!tc_ast_hash_set(node, "condition", condition, err) ||
      !tc_ast_hash_set(node, "then_body", then_body, err) ||
      !tc_ast_hash_set(node, "elsif_clauses", elsif_clauses, err) ||
      !tc_ast_hash_set(node, "else_body", else_body, err)) {
    tc_ast_free(node);
    return 0;
  }

  *out = node;
  return 1;
}

static int parse_loop_ast(TcAstParser *p, TcAstValue *out, TcError *err) {
  size_t start = p->pos;
  advance_ast(p);
  if (!finish_header_ast(p, err)) return 0;
  TcAstValue body;
  if (!parse_optional_body_ast(p, &body, err)) return 0;
  TcAstValue condition = node_hash(p, "bool", start, err);
  TcAstValue node = node_hash(p, "while", start, err);
  if (condition.kind != TC_AST_HASH || node.kind != TC_AST_HASH ||
      !tc_ast_hash_set(condition, "value", tc_ast_bool(1), err) ||
      !tc_ast_hash_set(node, "condition", condition, err) ||
      !tc_ast_hash_set(node, "body", body, err)) {
    tc_ast_free(condition);
    tc_ast_free(body);
    tc_ast_free(node);
    return 0;
  }
  *out = node;
  return 1;
}

static int consume_param_default_ast(TcAstParser *p, TcError *err) {
  int paren = 0;
  int bracket = 0;
  int brace = 0;
  while (!at_ast(p, TC_K_EOF)) {
    TcKind kind = current_ast(p).kind;
    if (paren == 0 && bracket == 0 && brace == 0 && (kind == TC_K_COMMA || kind == TC_K_RPAREN)) return 1;
    switch (kind) {
      case TC_K_LPAREN: paren++; break;
      case TC_K_RPAREN:
        if (paren == 0) return 1;
        paren--;
        break;
      case TC_K_LBRACKET: bracket++; break;
      case TC_K_RBRACKET:
        if (bracket == 0) {
          parse_ast_error(p, err, "unmatched ']'");
          return 0;
        }
        bracket--;
        break;
      case TC_K_LBRACE: brace++; break;
      case TC_K_RBRACE:
        if (brace == 0) {
          parse_ast_error(p, err, "unmatched '}'");
          return 0;
        }
        brace--;
        break;
      default:
        break;
    }
    advance_ast(p);
  }
  parse_ast_error(p, err, "unterminated parameter default");
  return 0;
}

static int parse_param_ast(TcAstParser *p, TcAstValue *out, TcError *err) {
  size_t start = p->pos;
  int block_param = 0;
  int splat = 0;
  int ivar_assign = 0;
  int keyword = 0;

  if (match_ast(p, TC_K_AMPERSAND)) block_param = 1;
  else if (match_ast(p, TC_K_STAR) || match_ast(p, TC_K_POW)) splat = 1;

  size_t name_start = p->pos;
  if (!name_token_ast(p) && !at_ast(p, TC_K_IVAR)) {
    parse_ast_error(p, err, "expected parameter name");
    return 0;
  }

  char *name = NULL;
  size_t name_len = 0;
  if (!current_token_text(p, &name, &name_len, err)) return 0;
  if (at_ast(p, TC_K_IVAR) && name_len > 0 && name[0] == '@') {
    memmove(name, name + 1, name_len - 1);
    name_len--;
    name[name_len] = '\0';
    ivar_assign = 1;
  }
  advance_ast(p);

  size_t default_start = p->pos;
  size_t default_end = default_start;
  int has_default = 0;
  if (match_ast(p, TC_K_COLON)) {
    keyword = 1;
    if (!at_ast(p, TC_K_COMMA) && !at_ast(p, TC_K_RPAREN)) {
      has_default = 1;
      default_start = p->pos;
      if (!consume_param_default_ast(p, err)) {
        free(name);
        return 0;
      }
      default_end = p->pos;
    }
  } else if (match_ast(p, TC_K_ASSIGN)) {
    has_default = 1;
    default_start = p->pos;
    if (!consume_param_default_ast(p, err)) {
      free(name);
      return 0;
    }
    default_end = p->pos;
  }

  TcAstValue node = node_hash(p, "param", name_start, err);
  if (node.kind != TC_AST_HASH) {
    free(name);
    return 0;
  }
  TcAstValue default_value = has_default ? parse_expr_span_ast(p, default_start, default_end, err) : tc_ast_nil();
  if (has_default && default_value.kind == TC_AST_NIL && err && err->message) {
    tc_ast_free(node);
    free(name);
    return 0;
  }
  if (!tc_ast_hash_set(node, "name", tc_ast_string_copy(name, name_len, err), err) ||
      !tc_ast_hash_set(node, "default", default_value, err) ||
      !tc_ast_hash_set(node, "ivar_assign", tc_ast_bool(ivar_assign), err) ||
      !tc_ast_hash_set(node, "keyword", tc_ast_bool(keyword), err) ||
      !tc_ast_hash_set(node, "block_param", tc_ast_bool(block_param), err) ||
      !tc_ast_hash_set(node, "splat", tc_ast_bool(splat), err) ||
      !tc_ast_hash_set(node, "source", raw_string(p, start, p->pos, err), err)) {
    free(name);
    tc_ast_free(node);
    return 0;
  }
  free(name);
  *out = node;
  return 1;
}

static int parse_param_list_ast(TcAstParser *p, TcAstValue *out, TcError *err) {
  TcAstValue params = tc_ast_array_new(err);
  if (params.kind != TC_AST_ARRAY) return 0;
  if (!match_ast(p, TC_K_LPAREN)) {
    *out = params;
    return 1;
  }

  while (!at_ast(p, TC_K_RPAREN) && !at_ast(p, TC_K_EOF)) {
    TcAstValue param;
    if (!parse_param_ast(p, &param, err)) {
      tc_ast_free(params);
      return 0;
    }
    if (!tc_ast_array_push(params, param, err)) {
      tc_ast_free(param);
      tc_ast_free(params);
      return 0;
    }
    if (!match_ast(p, TC_K_COMMA)) break;
  }
  if (!match_ast(p, TC_K_RPAREN)) {
    parse_ast_error(p, err, "expected ')' after parameters");
    tc_ast_free(params);
    return 0;
  }
  *out = params;
  return 1;
}

static void split_method_arity(char *name, size_t *name_len, const char **arity, size_t *arity_len) {
  char *slash = strchr(name, '/');
  if (!slash) {
    *arity = NULL;
    *arity_len = 0;
    return;
  }
  *slash = '\0';
  *arity = slash + 1;
  *arity_len = *name_len - (size_t)(slash - name) - 1;
  *name_len = (size_t)(slash - name);
}

static int method_name_token_ast(TcAstParser *p) {
  TcKind kind = current_ast(p).kind;
  return name_token_ast(p) || kind == TC_K_PLUS || kind == TC_K_MINUS || kind == TC_K_STAR || kind == TC_K_SLASH ||
         kind == TC_K_EQ || kind == TC_K_LT || kind == TC_K_GT || kind == TC_K_LBRACKET;
}

static int looks_like_return_type_ast(TcAstParser *p) {
  if (!at_ast(p, TC_K_TYPE)) return 0;
  size_t pos = p->pos + 1;
  if (pos >= p->tokens->count) return 1;
  TcKind next = p->tokens->items[pos].kind;
  return next == TC_K_COLON || next == TC_K_NEWLINE || next == TC_K_INDENT || next == TC_K_DEDENT ||
         next == TC_K_EOF || next == TC_K_SEMICOLON;
}

static int parse_method_def_ast(TcAstParser *p, TcAstValue type_hints, TcAstValue *out, TcError *err) {
  size_t start = p->pos;
  advance_ast(p);

  int is_class_method = 0;
  if (match_ast(p, TC_K_DOT)) is_class_method = 1;

  if (!method_name_token_ast(p)) {
    parse_ast_error(p, err, "expected method name");
    return 0;
  }

  char *name = NULL;
  size_t name_len = 0;
  if (!current_token_text(p, &name, &name_len, err)) return 0;
  advance_ast(p);
  if (match_ast(p, TC_K_ASSIGN)) {
    if (!append_bytes(&name, &name_len, "=", 1, err)) {
      free(name);
      return 0;
    }
  } else if (at_ast(p, TC_K_RBRACKET) && name_len == 1 && name[0] == '[') {
    advance_ast(p);
    if (!append_bytes(&name, &name_len, "]", 1, err)) {
      free(name);
      return 0;
    }
    if (match_ast(p, TC_K_ASSIGN) && !append_bytes(&name, &name_len, "=", 1, err)) {
      free(name);
      return 0;
    }
  }

  const char *arity = NULL;
  size_t arity_len = 0;
  split_method_arity(name, &name_len, &arity, &arity_len);

  TcAstValue params;
  if (!parse_param_list_ast(p, &params, err)) {
    free(name);
    return 0;
  }

  TcAstValue param_types = tc_ast_nil();
  if (at_ast(p, TC_K_LPAREN) && p->pos + 1 < p->tokens->count && p->tokens->items[p->pos + 1].kind == TC_K_TYPE) {
    size_t type_start = p->pos;
    advance_ast(p);
    while (!at_ast(p, TC_K_RPAREN) && !at_ast(p, TC_K_EOF)) advance_ast(p);
    if (!match_ast(p, TC_K_RPAREN)) {
      parse_ast_error(p, err, "expected ')' after param types");
      free(name);
      tc_ast_free(params);
      return 0;
    }
    param_types = raw_string(p, type_start, p->pos, err);
  }

  TcAstValue return_type = tc_ast_nil();
  if (looks_like_return_type_ast(p)) {
    char *rtype = NULL;
    size_t rtype_len = 0;
    if (!current_token_text(p, &rtype, &rtype_len, err)) {
      free(name);
      tc_ast_free(params);
      tc_ast_free(param_types);
      return 0;
    }
    return_type = tc_ast_symbol_copy(rtype, rtype_len, err);
    free(rtype);
    advance_ast(p);
  }

  size_t inline_start = p->pos;
  int has_inline = 0;
  if (match_ast(p, TC_K_ASSIGN) || match_ast(p, TC_K_COLON)) {
    inline_start = p->pos;
    has_inline = 1;
  } else if (!at_ast(p, TC_K_NEWLINE) && !at_ast(p, TC_K_DEDENT) && !at_ast(p, TC_K_EOF) &&
             !at_ast(p, TC_K_SEMICOLON)) {
    inline_start = p->pos;
    has_inline = 1;
  }

  size_t header_end = p->pos;
  if (!finish_header_span_ast(p, &header_end, err)) {
    free(name);
    tc_ast_free(params);
    tc_ast_free(param_types);
    tc_ast_free(return_type);
    return 0;
  }

  TcAstValue body = tc_ast_array_new(err);
  if (body.kind != TC_AST_ARRAY) {
    free(name);
    tc_ast_free(params);
    tc_ast_free(param_types);
    tc_ast_free(return_type);
    return 0;
  }
  if (has_inline && inline_start < header_end) {
    TcAstValue expr = parse_expr_span_ast(p, inline_start, header_end, err);
    if (expr.kind == TC_AST_NIL || !tc_ast_array_push(body, expr, err)) {
      free(name);
      tc_ast_free(expr);
      tc_ast_free(body);
      tc_ast_free(params);
      tc_ast_free(param_types);
      tc_ast_free(return_type);
      return 0;
    }
  }
  if (at_ast(p, TC_K_INDENT)) {
    TcAstValue block_body;
    if (!parse_ast_body(p, &block_body, err)) {
      free(name);
      tc_ast_free(body);
      tc_ast_free(params);
      tc_ast_free(param_types);
      tc_ast_free(return_type);
      return 0;
    }
    for (size_t i = 0; i < block_body.as.array->count; i++) {
      if (!tc_ast_array_push(body, block_body.as.array->items[i], err)) {
        free(name);
        tc_ast_free(block_body);
        tc_ast_free(body);
        tc_ast_free(params);
        tc_ast_free(param_types);
        tc_ast_free(return_type);
        return 0;
      }
    }
    // block_body.as.array and its items were arena-allocated (see
    // ast_value.c) — no per-node free needed.
  }

  TcAstValue node = node_hash(p, "method_def", start, err);
  if (node.kind != TC_AST_HASH) {
    free(name);
    tc_ast_free(body);
    tc_ast_free(params);
    tc_ast_free(param_types);
    tc_ast_free(return_type);
    return 0;
  }
  if (!tc_ast_hash_set(node, "name", tc_ast_string_copy(name, name_len, err), err) ||
      !tc_ast_hash_set(node, "params", params, err) ||
      !tc_ast_hash_set(node, "body", body, err) ||
      !tc_ast_hash_set(node, "type_hints", type_hints, err) ||
      !tc_ast_hash_set(node, "is_class_method", tc_ast_bool(is_class_method), err) ||
      !tc_ast_hash_set(node, "arity", arity ? tc_ast_string_copy(arity, arity_len, err) : tc_ast_nil(), err) ||
      !tc_ast_hash_set(node, "param_types", param_types, err) ||
      !tc_ast_hash_set(node, "return_type", return_type, err) ||
      !tc_ast_hash_set(node, "signature", raw_string(p, start, header_end, err), err)) {
    free(name);
    tc_ast_free(node);
    return 0;
  }
  free(name);
  *out = node;
  return 1;
}

static int parse_class_def_ast(TcAstParser *p, TcAstValue *out, TcError *err) {
  size_t start = p->pos;
  advance_ast(p);
  char *name = NULL;
  size_t name_len = 0;
  if (!parse_name_path_ast(p, &name, &name_len, err)) return 0;

  TcAstValue class_role = tc_ast_nil();
  if (match_ast(p, TC_K_LBRACKET)) {
    char *role = NULL;
    size_t role_len = 0;
    if (!parse_name_path_ast(p, &role, &role_len, err)) {
      free(name);
      return 0;
    }
    class_role = tc_ast_string_copy(role, role_len, err);
    free(role);
    if (!match_ast(p, TC_K_RBRACKET)) {
      parse_ast_error(p, err, "expected ']' after class role");
      free(name);
      tc_ast_free(class_role);
      return 0;
    }
  }

  TcAstValue superclass = tc_ast_nil();
  if (match_ast(p, TC_K_LT)) {
    char *super = NULL;
    size_t super_len = 0;
    if (!parse_name_path_ast(p, &super, &super_len, err)) {
      free(name);
      tc_ast_free(class_role);
      return 0;
    }
    superclass = tc_ast_string_copy(super, super_len, err);
    free(super);
  }

  /* Second role-marker position: `+ Name < Super [role]`. Reserves
   * `+ Name[Category]` (bracket attached to the class name) for class
   * type/category use, while still letting slab/abstract/trait-like
   * role markers ride on the class declaration. If both positions are
   * supplied, the post-superclass marker wins. */
  if (class_role.kind == TC_AST_NIL && match_ast(p, TC_K_LBRACKET)) {
    char *role = NULL;
    size_t role_len = 0;
    if (!parse_name_path_ast(p, &role, &role_len, err)) {
      free(name);
      tc_ast_free(superclass);
      return 0;
    }
    class_role = tc_ast_string_copy(role, role_len, err);
    free(role);
    if (!match_ast(p, TC_K_RBRACKET)) {
      parse_ast_error(p, err, "expected ']' after class role");
      free(name);
      tc_ast_free(class_role);
      tc_ast_free(superclass);
      return 0;
    }
  }

  if (!finish_header_ast(p, err)) {
    free(name);
    tc_ast_free(class_role);
    tc_ast_free(superclass);
    return 0;
  }

  TcAstValue body;
  if (!parse_optional_body_ast(p, &body, err)) {
    free(name);
    tc_ast_free(class_role);
    tc_ast_free(superclass);
    return 0;
  }
  /* Apply the file-level namespace prefix from `in Foo:Bar`. Both
   * the class name and an unqualified superclass get rewritten —
   * so inside an `in AST` file, `+ Program < Node` becomes
   * `AST:Program < AST:Node`. Names that already contain a `:`
   * stay alone (treated as fully-qualified). */
  char *qualified_name = NULL;
  size_t qualified_name_len = 0;
  int name_has_ns = 0;
  for (size_t i = 0; i < name_len; i++) {
    if (name[i] == ':') { name_has_ns = 1; break; }
  }
  if (p->namespace_prefix && !name_has_ns) {
    qualified_name_len = p->namespace_len + 1 + name_len;
    qualified_name = (char *)malloc(qualified_name_len + 1);
    if (!qualified_name) {
      tc_error_set(err, "qualified class name allocation failed");
      free(name);
      tc_ast_free(body);
      tc_ast_free(class_role);
      tc_ast_free(superclass);
      return 0;
    }
    memcpy(qualified_name, p->namespace_prefix, p->namespace_len);
    qualified_name[p->namespace_len] = ':';
    memcpy(qualified_name + p->namespace_len + 1, name, name_len);
    qualified_name[qualified_name_len] = '\0';
  } else {
    qualified_name = name;
    qualified_name_len = name_len;
    name = NULL;  /* qualified_name now owns the buffer */
  }

  /* Ruby-style constant lookup for the superclass: walk the
   * namespace chain from `in` prefix up to the top level, looking
   * for a declared class at each step. The first match wins; an
   * unmatched name passes through bare so runtime builtins
   * (StandardError, Error, …) still resolve at the top level. */
  TcAstValue qualified_super = tc_ast_nil();
  if (superclass.kind == TC_AST_STRING) {
    const char *s = superclass.as.string.bytes;
    size_t slen = superclass.as.string.len;
    int super_has_ns = 0;
    for (size_t i = 0; i < slen; i++) {
      if (s[i] == ':') { super_has_ns = 1; break; }
    }
    if (!super_has_ns && p->namespace_prefix) {
      /* Walk: <ns>:Name, <parent>:Name, …, Name. */
      size_t cur_len = p->namespace_len;
      while (cur_len > 0 && qualified_super.kind == TC_AST_NIL) {
        size_t cand_len = cur_len + 1 + slen;
        char *cand = (char *)malloc(cand_len + 1);
        if (!cand) break;
        memcpy(cand, p->namespace_prefix, cur_len);
        cand[cur_len] = ':';
        memcpy(cand + cur_len + 1, s, slen);
        cand[cand_len] = '\0';
        for (size_t i = 0; i < p->declared_class_count; i++) {
          if (p->declared_class_lens[i] == cand_len &&
              memcmp(p->declared_classes[i], cand, cand_len) == 0) {
            qualified_super = tc_ast_string_copy(cand, cand_len, err);
            break;
          }
        }
        free(cand);
        if (qualified_super.kind != TC_AST_NIL) break;
        /* Trim one segment off cur_len, looking for the next `:`
         * from the right. cur_len falls to 0 when we've consumed
         * everything; the loop exits and the bare name is used. */
        size_t back = cur_len;
        while (back > 0 && p->namespace_prefix[back - 1] != ':') back--;
        cur_len = back > 0 ? back - 1 : 0;
      }
    }
  }
  if (qualified_super.kind != TC_AST_NIL) {
    tc_ast_free(superclass);
    superclass = qualified_super;
  }

  /* Register the fully-qualified class name we just decided on so
   * later sibling declarations in this file can resolve to it via
   * the same walk. */
  {
    const char *full = qualified_name ? qualified_name : (name ? name : "");
    size_t full_len = qualified_name ? qualified_name_len : (name ? name_len : 0);
    if (full_len > 0) {
      if (p->declared_class_count == p->declared_class_cap) {
        size_t cap = p->declared_class_cap ? p->declared_class_cap * 2 : 32;
        char **next_names = (char **)realloc(p->declared_classes, cap * sizeof(*next_names));
        size_t *next_lens = (size_t *)realloc(p->declared_class_lens, cap * sizeof(*next_lens));
        if (next_names && next_lens) {
          p->declared_classes = next_names;
          p->declared_class_lens = next_lens;
          p->declared_class_cap = cap;
        }
      }
      if (p->declared_class_count < p->declared_class_cap) {
        char *copy = (char *)malloc(full_len + 1);
        if (copy) {
          memcpy(copy, full, full_len);
          copy[full_len] = '\0';
          p->declared_classes[p->declared_class_count] = copy;
          p->declared_class_lens[p->declared_class_count] = full_len;
          p->declared_class_count++;
        }
      }
    }
  }


  TcAstValue node = node_hash(p, "class_def", start, err);
  if (node.kind != TC_AST_HASH) {
    free(name);
    free(qualified_name);
    tc_ast_free(body);
    tc_ast_free(class_role);
    tc_ast_free(superclass);
    return 0;
  }
  if (!tc_ast_hash_set(node, "name", tc_ast_string_copy(qualified_name, qualified_name_len, err), err) ||
      !tc_ast_hash_set(node, "superclass", superclass, err) ||
      !tc_ast_hash_set(node, "body", body, err) ||
      !tc_ast_hash_set(node, "class_role", class_role, err)) {
    free(name);
    free(qualified_name);
    tc_ast_free(node);
    return 0;
  }
  free(name);
  free(qualified_name);
  *out = node;
  return 1;
}

/* Parse a `- ivars` class-body directive — a typed declaration block:
 *
 *   - ivars
 *     @expressions w64[]*
 *     @value       w64
 *     @condition   ast
 *
 * Each line under the indent is `@name` followed by a type spec
 * (currently slurped as a plain string up to the line's end). The
 * emitted AST is `{node: :ivars_decl, entries: [{name, type}, ...]}`
 * so lowering / the slab-class generator can consume it to drive
 * arena selection and accessor generation. */
static int parse_ivars_decl_ast(TcAstParser *p, TcAstValue *out, TcError *err) {
  size_t start = p->pos;
  /* Consume `-` + `ivars` header. */
  advance_ast(p);  /* `-` */
  advance_ast(p);  /* `ivars` */
  if (!finish_header_ast(p, err)) return 0;

  TcAstValue entries = tc_ast_array_new(err);
  if (entries.kind != TC_AST_ARRAY) return 0;

  if (!at_ast(p, TC_K_INDENT)) {
    /* Empty body is fine — just an empty entries array. */
    TcAstValue node = node_hash(p, "ivars_decl", start, err);
    if (node.kind != TC_AST_HASH ||
        !tc_ast_hash_set(node, "entries", entries, err)) {
      tc_ast_free(entries);
      tc_ast_free(node);
      return 0;
    }
    *out = node;
    return 1;
  }
  advance_ast(p);  /* INDENT */

  while (!at_ast(p, TC_K_DEDENT) && !at_ast(p, TC_K_EOF)) {
    skip_newlines_ast(p);
    if (at_ast(p, TC_K_DEDENT) || at_ast(p, TC_K_EOF)) break;
    if (p->tokens->items[p->pos].kind != TC_K_IVAR) {
      parse_ast_error(p, err, "expected @ivar declaration in `- ivars` block");
      tc_ast_free(entries);
      return 0;
    }
    char *name = NULL;
    size_t name_len = 0;
    if (!current_token_text(p, &name, &name_len, err)) {
      tc_ast_free(entries);
      return 0;
    }
    advance_ast(p);
    /* Type span runs to the newline. Reconstruct the text by
     * concatenating the spelling of each token, inserting a single
     * space only when the source had whitespace between them — so
     * `w64[]*` stays joined as `w64[]*` rather than `w64 [ ] *`. */
    char *type_str = NULL;
    size_t type_len = 0;
    int first = 1;
    while (!at_ast(p, TC_K_NEWLINE) && !at_ast(p, TC_K_DEDENT) && !at_ast(p, TC_K_EOF)) {
      char *part = NULL;
      size_t part_len = 0;
      if (!current_token_text(p, &part, &part_len, err)) {
        free(name);
        free(type_str);
        tc_ast_free(entries);
        return 0;
      }
      if (!first && token_sp_before_ast(p, p->pos)) {
        if (!append_bytes(&type_str, &type_len, " ", 1, err)) {
          free(name);
          free(part);
          free(type_str);
          tc_ast_free(entries);
          return 0;
        }
      }
      first = 0;
      if (!append_bytes(&type_str, &type_len, part, part_len, err)) {
        free(name);
        free(part);
        free(type_str);
        tc_ast_free(entries);
        return 0;
      }
      free(part);
      advance_ast(p);
    }
    TcAstValue entry = tc_ast_hash_new(err);
    if (entry.kind != TC_AST_HASH ||
        !tc_ast_hash_set(entry, "name", tc_ast_string_copy(name, name_len, err), err) ||
        !tc_ast_hash_set(entry, "type", tc_ast_string_copy(type_str ? type_str : "", type_len, err), err)) {
      free(name);
      free(type_str);
      tc_ast_free(entry);
      tc_ast_free(entries);
      return 0;
    }
    free(name);
    free(type_str);
    if (!tc_ast_array_push(entries, entry, err)) {
      tc_ast_free(entries);
      return 0;
    }
    skip_newlines_ast(p);
  }
  if (at_ast(p, TC_K_DEDENT)) advance_ast(p);

  TcAstValue node = node_hash(p, "ivars_decl", start, err);
  if (node.kind != TC_AST_HASH ||
      !tc_ast_hash_set(node, "entries", entries, err)) {
    tc_ast_free(entries);
    tc_ast_free(node);
    return 0;
  }
  *out = node;
  return 1;
}

static int parse_named_body_ast(TcAstParser *p, const char *keyword, const char *node_name, TcAstValue *out,
                                TcError *err) {
  size_t start = p->pos;
  if (!at_keyword_ast(p, keyword)) {
    parse_ast_error(p, err, "expected declaration keyword");
    return 0;
  }
  advance_ast(p);
  char *name = NULL;
  size_t name_len = 0;
  if (!parse_name_path_ast(p, &name, &name_len, err)) return 0;
  if (!finish_header_ast(p, err)) {
    free(name);
    return 0;
  }
  TcAstValue body;
  if (!parse_optional_body_ast(p, &body, err)) {
    free(name);
    return 0;
  }
  TcAstValue node = node_hash(p, node_name, start, err);
  if (node.kind != TC_AST_HASH) {
    free(name);
    tc_ast_free(body);
    return 0;
  }
  if (!tc_ast_hash_set(node, "name", tc_ast_string_copy(name, name_len, err), err) ||
      !tc_ast_hash_set(node, "body", body, err)) {
    free(name);
    tc_ast_free(node);
    return 0;
  }
  free(name);
  *out = node;
  return 1;
}

static int parse_trait_include_ast(TcAstParser *p, TcAstValue *out, TcError *err) {
  size_t start = p->pos;
  advance_ast(p);
  char *name = NULL;
  size_t name_len = 0;
  if (!parse_name_path_ast(p, &name, &name_len, err)) return 0;
  if (!finish_header_ast(p, err)) {
    free(name);
    return 0;
  }
  TcAstValue node = node_hash(p, "trait_include", start, err);
  if (node.kind != TC_AST_HASH) {
    free(name);
    return 0;
  }
  if (!tc_ast_hash_set(node, "name", tc_ast_string_copy(name, name_len, err), err)) {
    free(name);
    tc_ast_free(node);
    return 0;
  }
  free(name);
  *out = node;
  return 1;
}

static int parse_begin_ast(TcAstParser *p, TcAstValue *out, TcError *err) {
  size_t start = p->pos;
  advance_ast(p);
  if (!finish_header_ast(p, err)) return 0;
  TcAstValue body;
  if (!parse_optional_body_ast(p, &body, err)) return 0;

  TcAstValue rescue_header = tc_ast_nil();
  TcAstValue rescue_body = tc_ast_nil();
  TcAstValue rescue_var = tc_ast_nil();
  if (at_keyword_ast(p, "rescue")) {
    advance_ast(p);
    // Tungsten parser.w parse_begin: after `rescue`, if not at end-of-line,
    // expect an ID token as the rescue var binding. Optional `: NAME` type
    // annotation is allowed but not stored. Without setting `rescue_var`,
    // lower_begin's `if node[:rescue_var] != nil` branch in lowering.w skips
    // the slot+store, and every read of err in the rescue body resolves to
    // nil.
    if (p->pos < p->tokens->count && p->tokens->items[p->pos].kind == TC_K_ID) {
      char *text = NULL;
      size_t text_len = 0;
      if (!tc_token_text_copy(p->source, p->tokens->items[p->pos].packed, &text, &text_len, err)) {
        tc_ast_free(body);
        return 0;
      }
      rescue_var = tc_ast_string_copy(text, text_len, err);
      free(text);
      advance_ast(p);
      // Skip optional `: NAME` type annotation.
      if (p->pos < p->tokens->count && p->tokens->items[p->pos].kind == TC_K_COLON) {
        advance_ast(p);
        if (p->pos < p->tokens->count && p->tokens->items[p->pos].kind == TC_K_NAME) {
          advance_ast(p);
        }
      }
    }
    size_t header_start = p->pos;
    size_t header_end = header_start;
    if (!finish_header_span_ast(p, &header_end, err)) {
      tc_ast_free(body);
      tc_ast_free(rescue_var);
      return 0;
    }
    rescue_header = raw_string(p, header_start, header_end, err);
    if (!parse_optional_body_ast(p, &rescue_body, err)) {
      tc_ast_free(body);
      tc_ast_free(rescue_header);
      tc_ast_free(rescue_var);
      return 0;
    }
  }

  TcAstValue ensure_body = tc_ast_nil();
  if (at_keyword_ast(p, "ensure")) {
    advance_ast(p);
    if (!finish_header_ast(p, err) || !parse_optional_body_ast(p, &ensure_body, err)) {
      tc_ast_free(body);
      tc_ast_free(rescue_header);
      tc_ast_free(rescue_body);
      return 0;
    }
  }

  TcAstValue node = node_hash(p, "begin", start, err);
  if (node.kind != TC_AST_HASH) {
    tc_ast_free(body);
    tc_ast_free(rescue_header);
    tc_ast_free(rescue_body);
    tc_ast_free(ensure_body);
    return 0;
  }
  if (!tc_ast_hash_set(node, "body", body, err) ||
      !tc_ast_hash_set(node, "rescue_header", rescue_header, err) ||
      !tc_ast_hash_set(node, "rescue_var", rescue_var, err) ||
      !tc_ast_hash_set(node, "rescue_body", rescue_body, err) ||
      !tc_ast_hash_set(node, "ensure_body", ensure_body, err)) {
    tc_ast_free(node);
    return 0;
  }
  *out = node;
  return 1;
}

static int statement_end_pos_ast(TcAstParser *p, size_t start, size_t *end_out, TcError *err) {
  int paren = 0;
  int bracket = 0;
  int brace = 0;
  size_t pos = start;
  while (pos < p->tokens->count) {
    TcKind kind = p->tokens->items[pos].kind;
    if (paren == 0 && bracket == 0 && brace == 0 &&
        (kind == TC_K_NEWLINE || kind == TC_K_SEMICOLON || kind == TC_K_DEDENT || kind == TC_K_EOF)) {
      *end_out = pos;
      return 1;
    }
    switch (kind) {
      case TC_K_LPAREN: paren++; break;
      case TC_K_RPAREN: paren--; break;
      case TC_K_LBRACKET: bracket++; break;
      case TC_K_RBRACKET: bracket--; break;
      case TC_K_LBRACE: brace++; break;
      case TC_K_RBRACE: brace--; break;
      default: break;
    }
    if (paren < 0 || bracket < 0 || brace < 0) {
      parse_ast_error(p, err, "unmatched delimiter");
      return 0;
    }
    pos++;
  }
  *end_out = pos;
  return 1;
}

static void skip_statement_end_ast(TcAstParser *p) {
  while (match_ast(p, TC_K_NEWLINE) || match_ast(p, TC_K_SEMICOLON)) {}
}

static int parse_inline_or_block_body_ast(TcAstParser *p, size_t start, size_t end, TcAstValue *out, TcError *err) {
  trim_expr_span_ast(p, &start, &end);
  if (start < end) {
    TcAstValue expr = parse_expr_span_ast(p, start, end, err);
    if (expr.kind == TC_AST_NIL) return 0;
    *out = single_expr_body_ast(expr, err);
    return out->kind == TC_AST_ARRAY;
  }
  skip_statement_end_ast(p);
  return parse_optional_body_ast(p, out, err);
}

static TcAstValue case_arm_node_ast(TcAstParser *p, size_t start, TcAstValue pattern, TcAstValue body,
                                    TcError *err) {
  TcAstValue arm = node_hash(p, "case_arm", start, err);
  if (arm.kind != TC_AST_HASH) {
    tc_ast_free(pattern);
    tc_ast_free(body);
    return arm;
  }
  if (!tc_ast_hash_set(arm, "pattern", pattern, err) ||
      !tc_ast_hash_set(arm, "guard", tc_ast_nil(), err) ||
      !tc_ast_hash_set(arm, "body", body, err)) {
    tc_ast_free(arm);
    return tc_ast_nil();
  }
  return arm;
}

static int parse_case_when_clause_ast(TcAstParser *p, TcAstValue whens, TcError *err) {
  size_t when_start = p->pos;
  advance_ast(p);

  size_t line_end = p->pos;
  if (!statement_end_pos_ast(p, p->pos, &line_end, err)) return 0;

  size_t then_pos = 0;
  int has_then = top_level_keyword_ast(p, p->pos, line_end, "then", &then_pos, 0);
  size_t cond_end = has_then ? then_pos : line_end;
  TcAstValue conditions;
  if (!parse_expr_list_ast(p, p->pos, cond_end, &conditions, err)) return 0;

  TcAstValue body;
  p->pos = line_end;
  skip_statement_end_ast(p);
  if (has_then) {
    if (!parse_inline_or_block_body_ast(p, then_pos + 1, line_end, &body, err)) {
      tc_ast_free(conditions);
      return 0;
    }
  } else if (!parse_optional_body_ast(p, &body, err)) {
    tc_ast_free(conditions);
    return 0;
  }

  TcAstValue clause = node_hash(p, "when", when_start, err);
  if (clause.kind != TC_AST_HASH ||
      !tc_ast_hash_set(clause, "conditions", conditions, err) ||
      !tc_ast_hash_set(clause, "body", body, err) ||
      !tc_ast_array_push(whens, clause, err)) {
    tc_ast_free(clause);
    return 0;
  }
  return 1;
}

static int parse_case_else_ast(TcAstParser *p, TcAstValue *else_body, TcError *err) {
  advance_ast(p);
  size_t body_start = p->pos;
  size_t line_end = p->pos;
  if (!statement_end_pos_ast(p, p->pos, &line_end, err)) return 0;
  p->pos = line_end;
  skip_statement_end_ast(p);
  return parse_inline_or_block_body_ast(p, body_start, line_end, else_body, err);
}

static int parse_case_arrow_arm_ast(TcAstParser *p, TcAstValue arms, TcAstValue *else_body, TcError *err) {
  size_t start = p->pos;
  size_t line_end = start;
  if (!statement_end_pos_ast(p, start, &line_end, err)) return 0;

  size_t arrow = 0;
  if (!top_level_token_ast(p, start, line_end, TC_K_FAT_ARROW, &arrow, 0)) return 0;

  TcAstValue body;
  p->pos = line_end;
  skip_statement_end_ast(p);
  if (!parse_inline_or_block_body_ast(p, arrow + 1, line_end, &body, err)) return 0;

  if (arrow == start) {
    *else_body = body;
    return 1;
  }

  TcAstValue pattern = parse_expr_span_ast(p, start, arrow, err);
  if (pattern.kind == TC_AST_NIL) {
    tc_ast_free(body);
    return 0;
  }
  TcAstValue arm = case_arm_node_ast(p, start, pattern, body, err);
  if (arm.kind == TC_AST_NIL || !tc_ast_array_push(arms, arm, err)) {
    tc_ast_free(arm);
    return 0;
  }
  return 1;
}

static int parse_case_ast(TcAstParser *p, TcAstValue *out, TcError *err) {
  size_t start = p->pos;
  advance_ast(p);
  size_t subject_start = p->pos;
  size_t subject_end = subject_start;
  if (!finish_header_span_ast(p, &subject_end, err)) return 0;

  TcAstValue whens = tc_ast_array_new(err);
  if (whens.kind != TC_AST_ARRAY) return 0;
  TcAstValue arms = tc_ast_array_new(err);
  if (arms.kind != TC_AST_ARRAY) {
    tc_ast_free(whens);
    return 0;
  }
  TcAstValue else_body = tc_ast_nil();

  int had_indent = match_ast(p, TC_K_INDENT);
  if (had_indent || at_keyword_ast(p, "when") || at_keyword_ast(p, "else")) {
    skip_newlines_ast(p);
    while (!at_ast(p, TC_K_DEDENT) && !at_ast(p, TC_K_EOF)) {
      if (at_keyword_ast(p, "when")) {
        if (!parse_case_when_clause_ast(p, whens, err)) {
          tc_ast_free(whens);
          tc_ast_free(arms);
          return 0;
        }
      } else if (at_keyword_ast(p, "else")) {
        if (!parse_case_else_ast(p, &else_body, err)) {
          tc_ast_free(whens);
          tc_ast_free(arms);
          return 0;
        }
      } else {
        int parsed_arrow = parse_case_arrow_arm_ast(p, arms, &else_body, err);
        if (!parsed_arrow) break;
      }
      skip_newlines_ast(p);
    }
    if (had_indent && !match_ast(p, TC_K_DEDENT)) {
      parse_ast_error(p, err, "expected DEDENT after case body");
      tc_ast_free(whens);
      tc_ast_free(arms);
      return 0;
    }
  }

  if (!had_indent && !at_ast(p, TC_K_DEDENT) && !at_ast(p, TC_K_EOF)) {
    while (!at_ast(p, TC_K_DEDENT) && !at_ast(p, TC_K_EOF)) {
      if (at_keyword_ast(p, "when")) {
        if (!parse_case_when_clause_ast(p, whens, err)) {
          tc_ast_free(whens);
          tc_ast_free(arms);
          return 0;
        }
      } else if (at_keyword_ast(p, "else")) {
        if (!parse_case_else_ast(p, &else_body, err)) {
          tc_ast_free(whens);
          tc_ast_free(arms);
          return 0;
        }
      } else if (!parse_case_arrow_arm_ast(p, arms, &else_body, err)) {
        break;
      }
      skip_newlines_ast(p);
    }
  }

  int has_subject = subject_start < subject_end;
  TcAstValue node = node_hash(p, has_subject ? "case_value" : "case", start, err);
  if (node.kind != TC_AST_HASH) {
    tc_ast_free(whens);
    tc_ast_free(arms);
    tc_ast_free(else_body);
    return 0;
  }
  TcAstValue subject = has_subject ? parse_expr_span_ast(p, subject_start, subject_end, err) : tc_ast_nil();
  if (has_subject && subject.kind == TC_AST_NIL) {
    tc_ast_free(node);
    tc_ast_free(whens);
    tc_ast_free(arms);
    tc_ast_free(else_body);
    return 0;
  }
  if (has_subject && whens.as.array->count > 0) {
    for (size_t wi = 0; wi < whens.as.array->count; wi++) {
      TcAstValue *conditions = hash_value_ast(whens.as.array->items[wi], "conditions");
      TcAstValue *body = hash_value_ast(whens.as.array->items[wi], "body");
      if (!conditions || conditions->kind != TC_AST_ARRAY || !body) continue;
      for (size_t ci = 0; ci < conditions->as.array->count; ci++) {
        TcAstValue pattern = tc_ast_clone(conditions->as.array->items[ci], err);
        TcAstValue arm_body = tc_ast_clone(*body, err);
        if ((pattern.kind == TC_AST_NIL && err && err->message && conditions->as.array->items[ci].kind != TC_AST_NIL) ||
            (arm_body.kind == TC_AST_NIL && err && err->message && body->kind != TC_AST_NIL)) {
          tc_ast_free(pattern);
          tc_ast_free(arm_body);
          tc_ast_free(node);
          tc_ast_free(whens);
          tc_ast_free(arms);
          tc_ast_free(else_body);
          return 0;
        }
        TcAstValue arm = case_arm_node_ast(p, start, pattern, arm_body, err);
        if (arm.kind == TC_AST_NIL || !tc_ast_array_push(arms, arm, err)) {
          tc_ast_free(arm);
          tc_ast_free(node);
          tc_ast_free(whens);
          tc_ast_free(arms);
          tc_ast_free(else_body);
          return 0;
        }
      }
    }
  }
  int ok = has_subject
               ? (tc_ast_hash_set(node, "subject", subject, err) &&
                  tc_ast_hash_set(node, "arms", arms, err) &&
                  tc_ast_hash_set(node, "else_body", else_body, err))
               : (tc_ast_hash_set(node, "whens", whens, err) &&
                  tc_ast_hash_set(node, "else_body", else_body, err));
  if (!ok) {
    tc_ast_free(node);
    return 0;
  }
  if (has_subject) tc_ast_free(whens);
  *out = node;
  return 1;
}

static int parse_ast_statement(TcAstParser *p, TcAstValue *out, TcError *err) {
  skip_newlines_ast(p);
  TcAstValue type_hints = tc_ast_nil();
  if (!parse_type_hints_ast(p, &type_hints, err)) return 0;

  if (at_ast(p, TC_K_EOF) || at_ast(p, TC_K_DEDENT)) {
    tc_ast_free(type_hints);
    *out = tc_ast_nil();
    return 1;
  }
  if (at_keyword_ast(p, "use")) {
    tc_ast_free(type_hints);
    return parse_use_ast(p, out, err);
  }
  /* `in NAMESPACE` file-level directive — sets the parser's
   * namespace prefix so subsequent `+ Foo` declarations land at
   * `NAMESPACE:Foo`. Lets compiler/lib/ast.w drop the per-class
   * `AST:` prefix on every declaration. */
  if (at_keyword_ast(p, "in") && p->pos + 1 < p->tokens->count &&
      (p->tokens->items[p->pos + 1].kind == TC_K_TYPE ||
       p->tokens->items[p->pos + 1].kind == TC_K_NAME)) {
    size_t start = p->pos;
    advance_ast(p);
    char *ns = NULL;
    size_t ns_len = 0;
    if (!parse_name_path_ast(p, &ns, &ns_len, err)) {
      tc_ast_free(type_hints);
      return 0;
    }
    if (!finish_header_ast(p, err)) {
      free(ns);
      tc_ast_free(type_hints);
      return 0;
    }
    free(p->namespace_prefix);
    p->namespace_prefix = ns;
    p->namespace_len = ns_len;
    tc_ast_free(type_hints);
    /* Emit a namespace_decl node onto the program AST so consumers
     * (lowering, tools) can see the directive. */
    TcAstValue node = node_hash(p, "namespace_decl", start, err);
    if (node.kind != TC_AST_HASH ||
        !tc_ast_hash_set(node, "namespace", tc_ast_string_copy(ns, ns_len, err), err)) {
      tc_ast_free(node);
      return 0;
    }
    *out = node;
    return 1;
  }
  if (at_keyword_ast(p, "if") || at_keyword_ast(p, "unless")) {
    tc_ast_free(type_hints);
    return parse_if_ast(p, out, err);
  }
  if (at_keyword_ast(p, "while")) {
    tc_ast_free(type_hints);
    return parse_header_block_ast(p, "while", "condition", out, err);
  }
  if (at_keyword_ast(p, "until")) {
    tc_ast_free(type_hints);
    return parse_header_block_ast(p, "until", "condition", out, err);
  }
  if (at_keyword_ast(p, "loop")) {
    tc_ast_free(type_hints);
    return parse_loop_ast(p, out, err);
  }
  if (at_keyword_ast(p, "case")) {
    tc_ast_free(type_hints);
    return parse_case_ast(p, out, err);
  }
  if (at_keyword_ast(p, "begin")) {
    tc_ast_free(type_hints);
    return parse_begin_ast(p, out, err);
  }
  if (at_keyword_ast(p, "with")) {
    tc_ast_free(type_hints);
    return parse_header_block_ast(p, "with", "bindings", out, err);
  }
  if (at_keyword_ast(p, "parallel")) {
    tc_ast_free(type_hints);
    return parse_header_block_ast(p, "parallel", "bindings", out, err);
  }
  if (at_keyword_ast(p, "on")) {
    tc_ast_free(type_hints);
    return parse_on_guard_ast(p, out, err);
  }
  if (at_keyword_ast(p, "module")) {
    tc_ast_free(type_hints);
    return parse_named_body_ast(p, "module", "module_def", out, err);
  }
  if (at_keyword_ast(p, "trait")) {
    tc_ast_free(type_hints);
    return parse_named_body_ast(p, "trait", "trait_def", out, err);
  }
  if (at_keyword_ast(p, "is")) {
    tc_ast_free(type_hints);
    return parse_trait_include_ast(p, out, err);
  }
  if (at_keyword_ast(p, "go")) {
    tc_ast_free(type_hints);
    return parse_header_block_ast(p, "go", "header", out, err);
  }
  if (at_ast(p, TC_K_CLASS_DEF)) {
    tc_ast_free(type_hints);
    return parse_class_def_ast(p, out, err);
  }
  /* `- ivars` class-body directive — typed slab-layout declaration. */
  if (p->tokens->items[p->pos].kind == TC_K_MINUS &&
      p->pos + 1 < p->tokens->count &&
      p->tokens->items[p->pos + 1].kind == TC_K_ID) {
    char *next_text = NULL;
    size_t next_text_len = 0;
    if (token_text_at_ast(p, p->pos + 1, &next_text, &next_text_len, err) &&
        next_text_len == 5 && memcmp(next_text, "ivars", 5) == 0) {
      free(next_text);
      tc_ast_free(type_hints);
      return parse_ivars_decl_ast(p, out, err);
    }
    free(next_text);
  }
  if (at_ast(p, TC_K_ARROW)) return parse_method_def_ast(p, type_hints, out, err);

  size_t start = p->pos;
  size_t end = start;
  if (!finish_header_span_ast(p, &end, err)) {
    tc_ast_free(type_hints);
    return 0;
  }
  TcAstValue node = parse_expr_span_ast(p, start, end, err);
  if (node.kind != TC_AST_HASH) {
    tc_ast_free(type_hints);
    return 0;
  }
  if (type_hints.kind != TC_AST_NIL && !tc_ast_hash_set(node, "type_hints", type_hints, err)) {
    tc_ast_free(type_hints);
    tc_ast_free(node);
    return 0;
  }
  if (at_ast(p, TC_K_INDENT)) {
    TcAstValue body;
    if (!parse_ast_body(p, &body, err)) {
      tc_ast_free(node);
      return 0;
    }
    int attached = attach_block_body_ast(node, body, err);
    if (!attached && !tc_ast_hash_set(node, "body", body, err)) {
      tc_ast_free(node);
      return 0;
    }
  }
  *out = node;
  return 1;
}

static int parse_ast_body(TcAstParser *p, TcAstValue *out, TcError *err) {
  if (!match_ast(p, TC_K_INDENT)) {
    parse_ast_error(p, err, "expected INDENT");
    return 0;
  }

  TcAstValue body = tc_ast_array_new(err);
  if (body.kind != TC_AST_ARRAY) return 0;

  skip_newlines_ast(p);
  while (!at_ast(p, TC_K_DEDENT) && !at_ast(p, TC_K_EOF)) {
    TcAstValue stmt;
    if (!parse_ast_statement(p, &stmt, err)) {
      tc_ast_free(body);
      return 0;
    }
    if (stmt.kind != TC_AST_NIL && !tc_ast_array_push(body, stmt, err)) {
      tc_ast_free(stmt);
      tc_ast_free(body);
      return 0;
    }
    skip_newlines_ast(p);
  }
  if (!match_ast(p, TC_K_DEDENT)) {
    parse_ast_error(p, err, "expected DEDENT");
    tc_ast_free(body);
    return 0;
  }
  *out = body;
  return 1;
}

int tc_parse_bootstrap_ast(const TcSource *source, const TcSyntaxTokens *tokens, TcAstValue *out,
                           TcAstStats *stats, const unsigned char *flags, size_t flags_len,
                           TcError *err) {
  TcAstParser parser = {
      .source = source, .tokens = tokens, .pos = 0, .stats = {0, 0, 0},
      .flags = flags, .flags_len = flags_len,
      .namespace_prefix = NULL, .namespace_len = 0,
      .declared_classes = NULL, .declared_class_lens = NULL,
      .declared_class_count = 0, .declared_class_cap = 0,
  };
  TcAstValue expressions = tc_ast_array_new(err);
  if (expressions.kind != TC_AST_ARRAY) return 0;

  skip_newlines_ast(&parser);
  while (!at_ast(&parser, TC_K_EOF)) {
    TcAstValue stmt;
    if (!parse_ast_statement(&parser, &stmt, err)) {
      tc_ast_free(expressions);
      return 0;
    }
    if (stmt.kind != TC_AST_NIL && !tc_ast_array_push(expressions, stmt, err)) {
      tc_ast_free(stmt);
      tc_ast_free(expressions);
      return 0;
    }
    skip_newlines_ast(&parser);
  }

  TcAstValue program = tc_ast_hash_new(err);
  if (program.kind != TC_AST_HASH) {
    tc_ast_free(expressions);
    return 0;
  }
  parser.stats.nodes++;
  if (!set_node(program, "program", err) || !tc_ast_hash_set(program, "expressions", expressions, err)) {
    tc_ast_free(program);
    return 0;
  }
  *out = program;
  if (stats) *stats = parser.stats;
  free(parser.namespace_prefix);
  for (size_t i = 0; i < parser.declared_class_count; i++) free(parser.declared_classes[i]);
  free(parser.declared_classes);
  free(parser.declared_class_lens);
  return 1;
}
