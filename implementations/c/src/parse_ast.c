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
  /* Mirrors Parser#@in_class_body for the `fn` alias: class-scoped `fn`
   * produces method_def + from_fn, while a top-level one produces fn_def. */
  int class_depth;
  /* 1-based id in the VM's location registry (tc_vm_loc_register_source)
   * for this parse's source file. When nonzero, call/raise nodes are
   * stamped with `loc_bits` — a FileOffset-mode W_PACKED_LOCATION —
   * mirroring parser.w's `call.loc = name_loc` etc. 0 = no stamping
   * (VM-execution parses). */
  int loc_file_id;
} TcAstParser;

/* Sticky file id consumed by tc_parse_bootstrap_ast — set by the fast-load
 * path right before parsing each file. See tc_parse_set_loc_file_id (tc.h). */
static int g_tc_parse_loc_file_id = 0;
void tc_parse_set_loc_file_id(int file_id) { g_tc_parse_loc_file_id = file_id; }

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

static const char *pa_detect_acc(TcAstValue v);
static TcAstValue parse_expr_span_ast(TcAstParser *p, size_t start, size_t end, TcError *err);

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
  int single_quoted = len >= 2 && bytes[0] == '\'' && bytes[len - 1] == '\'';
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
  if (single_quoted) {
    /* Mirror compiler/lib/lexer.w:unquote_single — only \n \r \t decode;
     * any other escape drops the backslash and keeps the char. */
    for (size_t i = 0; i < len; i++) {
      if (bytes[i] == '\\' && i + 1 < len) {
        i++;
        switch (bytes[i]) {
          case 'n': copy[out_len++] = '\n'; break;
          case 'r': copy[out_len++] = '\r'; break;
          case 't': copy[out_len++] = '\t'; break;
          default: copy[out_len++] = bytes[i]; break;
        }
      } else {
        copy[out_len++] = bytes[i];
      }
    }
  } else {
    /* Mirror compiler/lib/lexer.w:scan_string's escape decode exactly:
     * n r t \\ " [ ] 0 e decode; \e[ is consumed as a unit (ESC + '[');
     * \uXXXX decodes the codepoint (to_i(16) prefix semantics, UTF-8
     * encoded); anything ELSE keeps the BACKSLASH and reprocesses the
     * next char — `"\x00"` is the four chars \ x 0 0, not `x00`. */
    size_t i = 0;
    while (i < len) {
      char ch = bytes[i];
      if (ch == '\\' && i + 1 < len) {
        char esc = bytes[i + 1];
        if (esc == 'e' && i + 2 < len && bytes[i + 2] == '[') {
          copy[out_len++] = 0x1b;
          copy[out_len++] = '[';
          i += 3;
          continue;
        }
        if (esc == 'u' && i + 5 < len) {
          uint32_t cpv = 0;
          for (size_t h = i + 2; h < i + 6; h++) {
            unsigned char hc = (unsigned char)bytes[h];
            uint32_t d;
            if (hc >= '0' && hc <= '9') d = hc - '0';
            else if (hc >= 'a' && hc <= 'f') d = hc - 'a' + 10;
            else if (hc >= 'A' && hc <= 'F') d = hc - 'A' + 10;
            else break;
            cpv = cpv * 16 + d;
          }
          if (cpv < 0x80) {
            copy[out_len++] = (char)cpv;
          } else if (cpv < 0x800) {
            copy[out_len++] = (char)(0xC0 | (cpv >> 6));
            copy[out_len++] = (char)(0x80 | (cpv & 0x3F));
          } else if (cpv < 0x10000) {
            copy[out_len++] = (char)(0xE0 | (cpv >> 12));
            copy[out_len++] = (char)(0x80 | ((cpv >> 6) & 0x3F));
            copy[out_len++] = (char)(0x80 | (cpv & 0x3F));
          } else {
            copy[out_len++] = (char)(0xF0 | (cpv >> 18));
            copy[out_len++] = (char)(0x80 | ((cpv >> 12) & 0x3F));
            copy[out_len++] = (char)(0x80 | ((cpv >> 6) & 0x3F));
            copy[out_len++] = (char)(0x80 | (cpv & 0x3F));
          }
          i += 6;
          continue;
        }
        switch (esc) {
          case 'n': copy[out_len++] = '\n'; i += 2; continue;
          case 'r': copy[out_len++] = '\r'; i += 2; continue;
          case 't': copy[out_len++] = '\t'; i += 2; continue;
          case '0': copy[out_len++] = '\0'; i += 2; continue;
          case '"': copy[out_len++] = '"'; i += 2; continue;
          case '\\': copy[out_len++] = '\\'; i += 2; continue;
          case '[': copy[out_len++] = '['; i += 2; continue;
          case ']': copy[out_len++] = ']'; i += 2; continue;
          case 'e': copy[out_len++] = 0x1b; i += 2; continue;
          default: break;
        }
        copy[out_len++] = '\\';
        i += 1;
        continue;
      }
      copy[out_len++] = ch;
      i++;
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
  size_t i = 0;
  size_t seg_len = 0; /* decoded chars since body start / last interp */
  int prev_esc = 0;   /* last decoded char was ESC (0x1B) */
  while (i < len) {
    unsigned char ch = (unsigned char)bytes[i];
    if (ch == '\\' && i + 1 < len) {
      unsigned char e = (unsigned char)bytes[i + 1];
      if (e == 'n' || e == 'r' || e == 't' || e == '\\' || e == '"' ||
          e == '[' || e == ']' || e == '0') {
        i += 2;
        seg_len++;
        prev_esc = 0;
        continue;
      }
      if (e == 'e') {
        // \e[ — ANSI escape prefix. The Tungsten lexer consumes both `e`
        // and `[` as a unit so the `[` isn't seen as an interp opener.
        if (i + 2 < len && bytes[i + 2] == '[') {
          i += 3;
          seg_len += 2;
          prev_esc = 0;
        } else {
          i += 2;
          seg_len++;
          prev_esc = 1; /* decoded ESC */
        }
        continue;
      }
      if (e == 'u' && i + 5 < len) {
        uint32_t cpv = 0;
        for (size_t h = i + 2; h < i + 6; h++) {
          unsigned char hc = (unsigned char)bytes[h];
          uint32_t d;
          if (hc >= '0' && hc <= '9') d = hc - '0';
          else if (hc >= 'a' && hc <= 'f') d = hc - 'a' + 10;
          else if (hc >= 'A' && hc <= 'F') d = hc - 'A' + 10;
          else break; /* to_i(16) prefix semantics */
          cpv = cpv * 16 + d;
        }
        i += 6;
        seg_len++;
        prev_esc = (cpv == 27);
        continue;
      }
      // Unrecognized escape — the canonical lexer consumes ONLY the
      // backslash and reprocesses the next char as a regular character.
      i += 1;
      seg_len++;
      prev_esc = 0;
      continue;
    }
    if (ch == '[' && i + 1 < len && bytes[i + 1] != ']' &&
        !(seg_len > 0 && prev_esc)) {
      return 1;
    }
    if (ch == '[') {
      // literal `[]` pair or ESC-guarded `[` — plain character
      i++;
      seg_len++;
      prev_esc = 0;
      continue;
    }
    i++;
    seg_len++;
    prev_esc = (ch == 27);
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
      // \uXXXX — canonical scan_string consumes 6 chars and appends the
      // decoded codepoint (UTF-8 encoded). to_i(16) prefix semantics on
      // the 4 hex chars.
      if (esc == 'u' && i + 5 < len) {
        uint32_t cpv = 0;
        for (size_t h = i + 2; h < i + 6; h++) {
          unsigned char hc = (unsigned char)bytes[h];
          uint32_t d;
          if (hc >= '0' && hc <= '9') d = hc - '0';
          else if (hc >= 'a' && hc <= 'f') d = hc - 'a' + 10;
          else if (hc >= 'A' && hc <= 'F') d = hc - 'A' + 10;
          else break;
          cpv = cpv * 16 + d;
        }
        if (cpv < 0x80) {
          lit[lit_len++] = (char)cpv;
        } else if (cpv < 0x800) {
          lit[lit_len++] = (char)(0xC0 | (cpv >> 6));
          lit[lit_len++] = (char)(0x80 | (cpv & 0x3F));
        } else if (cpv < 0x10000) {
          lit[lit_len++] = (char)(0xE0 | (cpv >> 12));
          lit[lit_len++] = (char)(0x80 | ((cpv >> 6) & 0x3F));
          lit[lit_len++] = (char)(0x80 | (cpv & 0x3F));
        } else {
          lit[lit_len++] = (char)(0xF0 | (cpv >> 18));
          lit[lit_len++] = (char)(0x80 | ((cpv >> 12) & 0x3F));
          lit[lit_len++] = (char)(0x80 | ((cpv >> 6) & 0x3F));
          lit[lit_len++] = (char)(0x80 | (cpv & 0x3F));
        }
        i += 6;
        continue;
      }
      // Recognized escapes, mirroring compiler/lib/lexer.w:scan_string.
      switch (esc) {
        case 'n': lit[lit_len++] = '\n'; i += 2; continue;
        case 'r': lit[lit_len++] = '\r'; i += 2; continue;
        case 't': lit[lit_len++] = '\t'; i += 2; continue;
        case '0': lit[lit_len++] = '\0'; i += 2; continue;
        case '"': lit[lit_len++] = '"'; i += 2; continue;
        case '\\': lit[lit_len++] = '\\'; i += 2; continue;
        case '[': lit[lit_len++] = '['; i += 2; continue;
        case ']': lit[lit_len++] = ']'; i += 2; continue;
        case 'e': lit[lit_len++] = 0x1b; i += 2; continue;
        default: break;
      }
      // Unrecognized escape: canonical lexer appends ONLY the backslash
      // and reprocesses the next char as a regular character.
      lit[lit_len++] = '\\';
      i += 1;
      continue;
    }
    // [] empty pair is a literal; a `[` immediately after a decoded ESC
    // is also literal (ANSI CSI guard — matches scan_string). The ESC
    // check inspects the *decoded* segment accumulated so far.
    if (ch == '[' && i + 1 < len && bytes[i + 1] != ']' &&
        !(lit_len > 0 && (unsigned char)lit[lit_len - 1] == 27)) {
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
      // The canonical lexer pushes `expr.strip()` — trim ASCII whitespace
      // from both ends before the sub-parse (String#strip's byte set).
      size_t es = expr_start;
      size_t ee = expr_end;
      while (es < ee && (bytes[es] == ' ' || bytes[es] == '\t' || bytes[es] == '\n' ||
                         bytes[es] == '\r' || bytes[es] == '\f' || bytes[es] == '\v'))
        es++;
      while (ee > es && (bytes[ee - 1] == ' ' || bytes[ee - 1] == '\t' || bytes[ee - 1] == '\n' ||
                         bytes[ee - 1] == '\r' || bytes[ee - 1] == '\f' || bytes[ee - 1] == '\v'))
        ee--;
      TcAstValue expr_ast = parse_interp_subexpression(p, bytes + es, ee - es, err);
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

// True when an AST subtree contains a `raw` fallback node anywhere. Used
// by parse_interp_subexpression to detect that a span attempt needed the
// unparseable-span fallback (the canonical parser would instead have
// stopped its expression parse earlier and discarded the tail).
static int ast_contains_raw(TcAstValue v) {
  if (v.kind == TC_AST_HASH && v.as.hash) {
    for (size_t i = 0; i < v.as.hash->count; i++) {
      TcAstEntry *e = &v.as.hash->items[i];
      if (strcmp(e->key, "node") == 0 &&
          (e->value.kind == TC_AST_STRING || e->value.kind == TC_AST_SYMBOL) &&
          e->value.as.string.len == 3 &&
          memcmp(e->value.as.string.bytes, "raw", 3) == 0) {
        return 1;
      }
      if (ast_contains_raw(e->value)) return 1;
    }
  } else if (v.kind == TC_AST_ARRAY && v.as.array) {
    for (size_t i = 0; i < v.as.array->count; i++) {
      if (ast_contains_raw(v.as.array->items[i])) return 1;
    }
  }
  return 0;
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
  // Mirror parser.w:parse_string_interp exactly: a fresh parser on the
  // segment, skip_newlines(), then parse ONE expression — anything after
  // it in the segment is silently DISCARDED. Parsing the segment as a
  // whole program (the old shape) errored on the discardable tail: the
  // canonical lexer's quote-blind bracket scan can swallow lines of
  // real code into a segment (an unmatched `[` at the end of a string),
  // and the canonical parser never looks past the first expression.
  TcAstParser sub = {
      .source = &source, .tokens = &syntax, .pos = 0, .stats = {0, 0, 0},
      .flags = p->flags, .flags_len = p->flags_len,
      .namespace_prefix = NULL, .namespace_len = 0,
      .declared_classes = NULL, .declared_class_lens = NULL,
      .declared_class_count = 0, .declared_class_cap = 0,
      .class_depth = 0,
      /* parser.w's parse_string_interp spins up Parser.new(..., "<interp>"),
       * which registers "<interp>" tables (first snippet wins, per the
       * registry's path dedupe). Mirror that — but only when the outer
       * parse is a location-bearing one (compiler fast-load); the VM's
       * execution parses never register. */
      .loc_file_id = p->loc_file_id > 0 ? tc_vm_loc_register_source("<interp>", &source) : 0,
  };
  // skip_newlines (+ leading layout tokens a fresh mid-indent segment
  // lexes to; canonical's expression parse never treats them as content).
  while (!at_ast(&sub, TC_K_EOF)) {
    TcKind k = current_ast(&sub).kind;
    if (k == TC_K_NEWLINE || k == TC_K_INDENT || k == TC_K_DEDENT) {
      advance_ast(&sub);
      continue;
    }
    break;
  }
  // Expression span: up to the first top-level NEWLINE (expressions do
  // not cross bare newlines in the canonical grammar).
  size_t expr_start = sub.pos;
  size_t expr_end = expr_start;
  long depth = 0;
  while (expr_end < sub.tokens->count) {
    TcKind k = sub.tokens->items[expr_end].kind;
    if (k == TC_K_EOF) break;
    if (k == TC_K_LPAREN || k == TC_K_LBRACKET || k == TC_K_LBRACE ||
        k == TC_K_BLOCK_CALL) {
      depth++;
    } else if (k == TC_K_RPAREN || k == TC_K_RBRACKET || k == TC_K_RBRACE) {
      if (depth > 0) depth--;
    } else if (depth == 0 &&
               (k == TC_K_NEWLINE || k == TC_K_INDENT || k == TC_K_DEDENT)) {
      break;
    }
    expr_end++;
  }
  TcAstValue result = tc_ast_nil();
  if (expr_end > expr_start) {
    // The canonical parse_expression is recursive descent: it consumes the
    // longest leading expression and leaves the rest of the segment
    // unconsumed (then discarded). The span parser must consume its whole
    // span, so approximate that with the longest token-prefix that parses
    // WITHOUT the raw fallback: a swallowed segment like `"…" x i8`
    // (quote-blind bracket scan over real code) parses as just the leading
    // string, exactly as the canonical parser stops after the string.
    for (size_t end_try = expr_end; end_try > expr_start; end_try--) {
      TcError attempt_err = {0};
      TcAstValue expr = parse_expr_span_ast(&sub, expr_start, end_try, &attempt_err);
      if (expr.kind != TC_AST_NIL && !ast_contains_raw(expr)) {
        result = tc_ast_clone(expr, err);
        tc_error_free(&attempt_err);
        break;
      }
      if (end_try == expr_start + 1) {
        // No prefix parsed raw-free. Keep the shortest attempt's tree (or
        // its error) so downstream reporting matches the old behavior.
        if (expr.kind != TC_AST_NIL) {
          result = tc_ast_clone(expr, err);
        } else if (attempt_err.message && err && !err->message) {
          tc_error_set(err, "%s", attempt_err.message);
        }
      }
      tc_error_free(&attempt_err);
    }
    if (result.kind == TC_AST_NIL && err && err->message) {
      tc_syntax_tokens_free(&syntax);
      tc_tokens_free(&tokens);
      tc_source_free(&source);
      return tc_ast_nil();
    }
  }
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

/* Stamp a node with the canonical location triple derived from the anchor
 * token: `line`/`col` ints (the values @line_at/@col_at would give) plus
 * `loc_bits` — a FileOffset-mode W_PACKED_LOCATION whose file_id/offset
 * resolve through the VM's registered tables, exactly like parser.w's
 * `node.loc = make_loc_here()`. The wcs call-site table reads node.col,
 * and lowering's setter-dispatch synthesis copies ast_get(node, :loc), so
 * both representations must be present. */
static int stamp_node_loc(TcAstParser *p, TcAstValue node, size_t anchor_pos, TcError *err) {
  WValue tok = p->tokens->items[anchor_pos].packed;
  uint32_t off = tc_token_offset(tok);
  if (!tc_ast_hash_set(node, "line", tc_ast_int(token_line_ast(p->source, tok)), err) ||
      !tc_ast_hash_set(node, "col", tc_ast_int((int64_t)p->source->cp_cols[off]), err)) {
    return 0;
  }
  if (p->loc_file_id > 0) {
    WValue loc = w_box_location_file_offset(p->loc_file_id, off);
    if (!tc_ast_hash_set(node, "loc_bits", tc_ast_int((int64_t)loc), err)) return 0;
  }
  return 1;
}

/* anchor_pos: the token the canonical parser derives this call's `:loc`
 * from (method-name token for tight dot-calls and bare calls, the dot for
 * space-separated chains, the `[` for index calls, the arrow for the
 * implicit-each synthesis). SIZE_MAX = no location (the canonical parser
 * leaves `.loc` unset on this synthesized call). */
static TcAstValue call_node_ast(TcAstParser *p, size_t start, size_t anchor_pos, TcAstValue receiver,
                                const char *name, size_t name_len, TcAstValue args, TcError *err) {
  TcAstValue node = node_hash(p, "call", start, err);
  if (node.kind != TC_AST_HASH) return node;
  if (!tc_ast_hash_set(node, "receiver", receiver, err) ||
      !tc_ast_hash_set(node, "name", tc_ast_string_copy(name, name_len, err), err) ||
      !tc_ast_hash_set(node, "args", args, err) ||
      !tc_ast_hash_set(node, "block", tc_ast_nil(), err)) {
    tc_ast_free(node);
    return tc_ast_nil();
  }
  if (anchor_pos != (size_t)-1) {
    if (!stamp_node_loc(p, node, anchor_pos, err)) {
      tc_ast_free(node);
      return tc_ast_nil();
    }
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
  /* A tight `$field` (no space before the `$`) is the postfix view-decl
   * field read `expr$field` (parser.w parse_postfix_from), NEVER a bare
   * command argument — `other$value` as a command call turned a raw
   * NaN-box bits read into a closure invocation of `other`. A spaced
   * `cmd $global` stays a command call, exactly like canon (@sp_before). */
  if (p->tokens->items[start + 1].kind == TC_K_GLOBAL && !token_sp_before_ast(p, start + 1)) {
    return tc_ast_nil();
  }

  char *name = NULL;
  size_t name_len = 0;
  if (!token_text_at_ast(p, start, &name, &name_len, err)) return tc_ast_nil();
  TcAstValue args;
  if (!parse_expr_list_ast(p, start + 1, end, &args, err)) {
    free(name);
    return tc_ast_nil();
  }
  TcAstValue node = call_node_ast(p, start, start, tc_ast_nil(), name, name_len, args, err);
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
    TcAstValue node = call_node_ast(p, start, start, tc_ast_nil(), name, name_len, args, err);
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
      /* Anchor mirrors parser.w: tight `.name` chains use the NAME
       * token (parse_postfix_from's name_loc), space-separated chains
       * use the DOT (parse_message_chain's dot_loc). */
      size_t anchor = token_sp_before_ast(p, dot) ? dot : name_pos;
      TcAstValue node = call_node_ast(p, start, anchor, receiver, name, name_len, args, err);
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
    if (err->message) return tc_ast_nil();
    /* An empty or unparseable operand span is not an error at this layer.
     * Embedded-`ll` heredoc bodies are lexed as ordinary tokens by the
     * bootstrap lexer, so a line ending in an inline vector constant —
     * e.g. `shufflevector ... <2 x i32> <i32 1, i32 2>` — matches its
     * trailing `>` as a top-level comparison whose right side is empty.
     * Returning bare nil here killed the whole parse (and the VM) with
     * no message. Fall back to the parser's raw-node contract instead:
     * if the expression is ever actually compiled, ast_compile.c reports
     * `unsupported AST node` with the source text and line. */
    return raw_node(p, "expr", start, end, err);
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

/* A decimal literal whose value exceeds i64. Mirrors compiler/lib/
 * parser.w's int_literal_format: the classification must be made from the
 * token text at PARSE time on both hosts and carried in the node's
 * `format` field, so magnitude-sensitive type inference (infer_type's
 * :dec_big -> :int rule) answers identically for stage 1 and stage 2. */
static int dec_literal_beyond_i64(const char *raw) {
  if (raw[0] == '0' && (raw[1] == 'x' || raw[1] == 'X' || raw[1] == 'b' ||
                        raw[1] == 'B' || raw[1] == 'o' || raw[1] == 'O'))
    return 0;
  char digits[24];
  size_t n = 0;
  for (const char *q = raw; *q; q++) {
    if (*q == '_') continue;
    if (n < 20) digits[n] = *q;
    n++;
  }
  if (n > 19) return 1;
  if (n < 19) return 0;
  digits[19] = '\0';
  return strcmp(digits, "9223372036854775807") > 0;
}

/* Mirror parser.w:int_literal_format — classify an int literal's spelling
 * from its token text. The :hex/:bin/:oct marker matters beyond metadata:
 * inference types hex literals as machine i64 (bit-pattern semantics) and
 * the emitter prints them as `u0x…` immediates, so omitting it flipped
 * whole functions (e.g. Integer#prev) from raw ops to boxed helper calls
 * and changed the emitted constant spelling. Returns NULL for plain
 * decimals (canonical format nil). */
/* Mirror parser.w's type-hint text cleanup: cut at a trailing `#` comment,
 * then strip ASCII whitespace from both ends (String#strip's byte set). */
static void clean_type_hint_text(const char *text, size_t len, size_t *out_start, size_t *out_len) {
  size_t s = 0, e = len;
  for (size_t i = 0; i < len; i++) {
    if (text[i] == '#') {
      e = i;
      break;
    }
  }
  while (s < e && (text[s] == ' ' || text[s] == '\t' || text[s] == '\n' ||
                   text[s] == '\r' || text[s] == '\f' || text[s] == '\v'))
    s++;
  while (e > s && (text[e - 1] == ' ' || text[e - 1] == '\t' || text[e - 1] == '\n' ||
                   text[e - 1] == '\r' || text[e - 1] == '\f' || text[e - 1] == '\v'))
    e--;
  *out_start = s;
  *out_len = e - s;
}

static const char *int_literal_format_ast(const char *raw) {
  if (raw[0] == '0' && (raw[1] == 'x' || raw[1] == 'X')) return "hex";
  if (raw[0] == '0' && (raw[1] == 'b' || raw[1] == 'B')) return "bin";
  if (raw[0] == '0' && (raw[1] == 'o' || raw[1] == 'O')) return "oct";
  if (dec_literal_beyond_i64(raw)) return "dec_big";
  return NULL;
}

static TcAstValue int_node_value_ast(TcAstParser *p, size_t pos, int64_t value, const char *raw, TcError *err) {
  TcAstValue node = node_hash(p, "int", pos, err);
  if (node.kind != TC_AST_HASH) return node;
  if (!tc_ast_hash_set(node, "value", tc_ast_int(value), err) ||
      !tc_ast_hash_set(node, "raw", tc_ast_string_copy(raw, strlen(raw), err), err)) {
    tc_ast_free(node);
    return tc_ast_nil();
  }
  const char *fmt = int_literal_format_ast(raw);
  if (fmt && !tc_ast_hash_set(node, "format", tc_ast_symbol_copy(fmt, strlen(fmt), err), err)) {
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
    case TC_K_POW_EQ:
      return "POW";
    case TC_K_AMP_EQ:
      return "AMPERSAND";
    case TC_K_PIPE_EQ:
      return "PIPE";
    case TC_K_CARET_EQ:
      return "CARET";
    case TC_K_LSHIFT_EQ:
      return "LSHIFT";
    case TC_K_RSHIFT_EQ:
      return "RSHIFT";
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
      TC_K_PLUS_EQ, TC_K_MINUS_EQ, TC_K_STAR_EQ, TC_K_SLASH_EQ, TC_K_PERCENT_EQ,
      TC_K_POW_EQ, TC_K_AMP_EQ, TC_K_PIPE_EQ, TC_K_CARET_EQ,
      TC_K_LSHIFT_EQ, TC_K_RSHIFT_EQ, TC_K_OR_ASSIGN};
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
      /* Spelling format marker (:hex/:bin/:oct/:dec_big) mirrors
       * parser.w:int_literal_format — inference and the emitter both key
       * on it (machine-i64 typing, u0x immediates). */
      if (node.kind == TC_AST_HASH) {
        const char *fmt = int_literal_format_ast(text);
        if (fmt && !tc_ast_hash_set(node, "format", tc_ast_symbol_copy(fmt, strlen(fmt), err), err)) {
          tc_ast_free(node);
          node = tc_ast_nil();
        }
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
          case 'e':  value = 0x1b; break;
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
    case TC_K_PARG: {
      int64_t index = 0;
      if (text_len > 1 && text[0] == '@') index = strtoll(text + 1, NULL, 10);
      node = node_hash(p, "parg", pos, err);
      if (node.kind == TC_AST_HASH &&
          !tc_ast_hash_set(node, "index", tc_ast_int(index), err)) {
        tc_ast_free(node);
        node = tc_ast_nil();
      }
      break;
    }
    case TC_K_NAME:
      /* The compact syntax table folds PascalCase names and
       * SCREAMING_SNAKE constants into TC_K_NAME. Recover the canonical AST
       * distinction from the spelling: any lowercase ASCII makes this a
       * class reference; all-uppercase/digit/underscore spellings stay vars. */
      {
        int has_lower = 0;
        for (size_t i = 0; i < text_len; i++) {
          if (text[i] >= 'a' && text[i] <= 'z') {
            has_lower = 1;
            break;
          }
        }
        node = node_hash(p, has_lower ? "class_ref" : "var", pos, err);
      }
      if (node.kind == TC_AST_HASH &&
          !tc_ast_hash_set(node, "name", tc_ast_string_copy(text, text_len, err), err)) {
        tc_ast_free(node);
        node = tc_ast_nil();
      }
      break;
    case TC_K_ID:
    case TC_K_TYPE:
    case TC_K_GLOBAL:
      /* `$name` globals are GVar nodes in the canonical parser (parser.w:
       * `Tungsten:AST:GVar.new(...)`). The kind matters for inference:
       * `$value` as :gvar infers :raw_i64 (the receiver's raw NaN-box
       * bits), so `$value & MASK` lowers to a native `and` — as a plain
       * :var it typed nil and every Integer tag test went through boxed
       * __w_band_fast/__w_int_fast chains. */
      node = node_hash(p, kind == TC_K_GLOBAL ? "gvar" : "var", pos, err);
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
        // Match Tungsten parser's `:self_ref` (Tungsten:AST:Self.new).
        // Using `:self` left every method ending in bare `self` (e.g.
        // Parser#set_chars) returning nil after lowering — stage1 then
        // crashed with `undefined method 'parse' for nil`.
        node = node_hash(p, "self_ref", pos, err);
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
  /* The canonical parser never sets :loc on Block nodes (parser.w builds
   * `Tungsten:AST:Block.new(params, body)` bare), so block.line is nil and
   * the wfm function-metadata rows for block fns carry line 0. Mirror that:
   * a real line here diverged every `block in …` wfm row. */
  if (!tc_ast_hash_set(block, "line", tc_ast_nil(), err) ||
      !tc_ast_hash_set(block, "params", params, err) ||
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
  /* The canonical lambda parse consumes its indented body wherever the
   * arrow sits in the statement, so the body belongs to the LAST lambda
   * down the right-hand spine. Recurse through the statement wrappers
   * that carry a trailing expression: `return x.map -> (e)` + INDENT
   * body silently LOST the block body without this (the block compiled
   * to `ret 0` — the interpreter's :array arm mapped every element to
   * zero under fast parse). */
  if (ast_node_is(node, "return") || ast_node_is(node, "print")) {
    TcAstValue *value = hash_value_ast(node, "value");
    if (!value) return 0;
    return attach_block_body_ast(*value, body, err);
  }
  if (ast_node_is(node, "puts")) {
    TcAstValue *value = hash_value_ast(node, "value");
    if (value && value->kind == TC_AST_ARRAY && value->as.array && value->as.array->count > 0)
      return attach_block_body_ast(value->as.array->items[value->as.array->count - 1], body, err);
    return 0;
  }
  if (ast_node_is(node, "binary_op")) {
    TcAstValue *right = hash_value_ast(node, "right");
    if (!right) return 0;
    return attach_block_body_ast(*right, body, err);
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
      TcAstValue call = call_node_ast(p, start, arrow_pos, tc_ast_nil(), "each", 4, args, err);
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
  TcAstValue call = call_node_ast(p, start, arrow_pos, left, "each", 4, args, err);
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
  return call_node_ast(p, start, open, receiver, "[]", 2, args, err);
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
  /* `<-` print: the canonical Print node (parser.w: `Tungsten:AST:
   * Print.new(parse_assignment())`) carries a SINGLE value expression —
   * NOT the Puts list shape. lower_print does lower_expression(node.value)
   * directly, so an array here lowered to garbage (w_print(0)) and
   * silently dropped the printed call. */
  if (kind == TC_K_PRINT_OP) {
    TcAstValue value = parse_expr_span_ast(p, start + 1, end, err);
    if (value.kind == TC_AST_NIL && err && err->message) return tc_ast_nil();
    TcAstValue node = node_hash(p, "print", start, err);
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
  /* Canonical Puts nodes carry a LIST of value expressions
   * (ast.w `+ Puts`: @value is a list, length 1 for the common `<< x`;
   * `<< a, b` prints one line per value). The hosted compiler's
   * lower_puts iterates node.value, so a bare single node here made
   * every fast-parsed `<<` print nils (values.size() saw the hash's
   * entry count). Split the span on top-level commas. */
  TcAstValue values = tc_ast_array_new(err);
  if (values.kind != TC_AST_ARRAY) return tc_ast_nil();
  size_t seg_start = start + 1;
  while (seg_start < end) {
    size_t seg_end = end;
    size_t comma = 0;
    if (top_level_token_ast(p, seg_start, end, TC_K_COMMA, &comma, 1) && comma > seg_start &&
        comma < end) {
      seg_end = comma;
    }
    TcAstValue v = parse_expr_span_ast(p, seg_start, seg_end, err);
    if (v.kind == TC_AST_NIL) {
      tc_ast_free(values);
      return tc_ast_nil();
    }
    if (!tc_ast_array_push(values, v, err)) {
      tc_ast_free(v);
      tc_ast_free(values);
      return tc_ast_nil();
    }
    if (seg_end == end) break;
    seg_start = seg_end + 1;
  }
  TcAstValue node = node_hash(p, "puts", start, err);
  if (node.kind != TC_AST_HASH) {
    tc_ast_free(values);
    return node;
  }
  if (!tc_ast_hash_set(node, "value", values, err)) {
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
  if (token_is_keyword_at_ast(p, start, "raise") ||
      p->tokens->items[start].kind == TC_K_RAISE_OP) {
    /* parser.w:parse_raise — a Raise node carrying ONE value; the
     * two-arg `raise ExceptionClass, "msg"` form becomes
     * `ExceptionClass.new(msg)`. Previously fast parsed `raise x` as a
     * receiverless CALL named "raise", which lowered through the generic
     * call path (call i64 @w_raise) instead of lower_raise's
     * loc_set_col + noreturn + unreachable shape. The `<!` shorthand
     * (TC_K_RAISE_OP) builds the same node but with NO location —
     * parser.w never sets loc on it. */
    int is_op_form = p->tokens->items[start].kind == TC_K_RAISE_OP;
    TcAstValue node = node_hash(p, "raise", start, err);
    if (node.kind != TC_AST_HASH) return node;
    if (is_op_form && !tc_ast_hash_set(node, "line", tc_ast_nil(), err)) {
      tc_ast_free(node);
      return tc_ast_nil();
    }
    /* Keyword form carries raise_loc (the `raise` token) — line, col and
     * the packed :loc, like every canon Raise node. */
    if (!is_op_form && !stamp_node_loc(p, node, start, err)) {
      tc_ast_free(node);
      return tc_ast_nil();
    }
    TcAstValue value = tc_ast_nil();
    size_t comma = 0;
    if (!is_op_form && top_level_token_ast(p, start + 1, end, TC_K_COMMA, &comma, 1) &&
        comma > start + 1 && comma < end) {
      TcAstValue cls = parse_expr_span_ast(p, start + 1, comma, err);
      TcAstValue msg = parse_expr_span_ast(p, comma + 1, end, err);
      TcAstValue args = tc_ast_array_new(err);
      if (cls.kind == TC_AST_NIL || msg.kind == TC_AST_NIL || args.kind != TC_AST_ARRAY ||
          !tc_ast_array_push(args, msg, err)) {
        tc_ast_free(cls);
        tc_ast_free(msg);
        tc_ast_free(args);
        tc_ast_free(node);
        return tc_ast_nil();
      }
      value = call_node_ast(p, start, (size_t)-1, cls, "new", 3, args, err);
      /* The synthesized Call in parser.w carries no loc. */
      if (value.kind != TC_AST_HASH ||
          !tc_ast_hash_set(value, "line", tc_ast_nil(), err)) {
        tc_ast_free(value);
        tc_ast_free(node);
        return tc_ast_nil();
      }
    } else {
      value = parse_expr_span_ast(p, start + 1, end, err);
      if (value.kind == TC_AST_NIL && err && err->message) {
        tc_ast_free(node);
        return tc_ast_nil();
      }
    }
    if (!tc_ast_hash_set(node, "value", value, err)) {
      tc_ast_free(node);
      return tc_ast_nil();
    }
    return node;
  }
  if (token_is_keyword_at_ast(p, start, "yield")) {
    TcAstValue args;
    if (!parse_call_args_after_name_ast(p, start + 1, end, &args, err)) {
      return tc_ast_nil();
    }
    TcAstValue node = node_hash(p, "yield", start, err);
    if (node.kind != TC_AST_HASH) {
      tc_ast_free(args);
      return node;
    }
    if (!tc_ast_hash_set(node, "args", args, err)) {
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
    /* Type-hint text cleanup shared with the ascription path below —
     * parser.w cuts the hint at a trailing comment (`## i64  # note`)
     * and strips whitespace (parse_assignment / consume_trailing_
     * type_ascription). Without this, `x = -1 ## i64  # tag` stored the
     * whole "i64  # tag" text, no lowering rule matched, and the local
     * silently fell back to boxed ops. */
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
      size_t hs = 0, hl = 0;
      clean_type_hint_text(hint, hint_len, &hs, &hl);
      type_hint = tc_ast_string_copy(hint + hs, hl, err);
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

  /* Expression-local type ascription, mirroring Parser#parse_expression.
   * Assignment handles its own trailing hint above so allocation hints keep
   * their special semantics. The ascription must be an occurrence-local
   * wrapper: Var nodes may be interned by name after this hash AST is imported
   * into the slab arena, so metadata on the leaf would contaminate every
   * occurrence of that variable. */
  if (end > start && p->tokens->items[end - 1].kind == TC_K_TYPE_HINT) {
    TcAstValue value = parse_expr_span_ast(p, start, end - 1, err);
    if (value.kind == TC_AST_NIL) return value;
    char *hint = NULL;
    size_t hint_len = 0;
    if (!token_text_at_ast(p, end - 1, &hint, &hint_len, err)) {
      tc_ast_free(value);
      return tc_ast_nil();
    }
    size_t hs = 0, hl = 0;
    clean_type_hint_text(hint, hint_len, &hs, &hl);
    TcAstValue hint_value = tc_ast_string_copy(hint + hs, hl, err);
    free(hint);
    if (hint_value.kind == TC_AST_NIL) {
      tc_ast_free(value);
      return tc_ast_nil();
    }
    TcAstValue node = node_hash(p, "type_ascription", end - 1, err);
    if (node.kind != TC_AST_HASH) {
      tc_ast_free(value);
      tc_ast_free(hint_value);
      return node;
    }
    if (!tc_ast_hash_set(node, "expression", value, err) ||
        !tc_ast_hash_set(node, "type_hint", hint_value, err)) {
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
  // Precedence mirrors parser.w's descent chain (loosest to tightest):
  // or/and -> in -> comparison (< <= > >=) -> equality (== != =~) ->
  // bit-or -> bit-xor -> bit-and -> add -> shift -> mul -> pow. Bitwise
  // ops bind TIGHTER than comparisons (the 2025 precedence ruling), so
  // `(x >> 48) & 65535 == 65530` is `((x >> 48) & 65535) == 65530` —
  // the old merged/reversed order compared the two literals instead.
  static const TcKind rel_ops[] = {TC_K_LT, TC_K_LTE, TC_K_GT, TC_K_GTE};
  static const TcKind eq_ops[] = {TC_K_EQ, TC_K_NEQ, TC_K_MATCH};
  static const TcKind bitwise_or_ops[] = {TC_K_PIPE, TC_K_DOT_PIPE};
  static const TcKind bitwise_xor_ops[] = {TC_K_CARET, TC_K_DOT_CARET};
  static const TcKind bitwise_and_ops[] = {TC_K_AMPERSAND, TC_K_DOT_AMP};
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
  if (top_level_any_ast(p, start, end, rel_ops, sizeof(rel_ops) / sizeof(rel_ops[0]), &op_pos)) {
    return binary_node_ast(p, start, end, op_pos, err);
  }
  if (top_level_any_ast(p, start, end, eq_ops, sizeof(eq_ops) / sizeof(eq_ops[0]), &op_pos)) {
    return binary_node_ast(p, start, end, op_pos, err);
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

  /* `expr$field` — postfix view-decl field read on an explicit receiver
   * (parser.w parse_postfix_from's T_GLOBAL arm: tight binding, no space
   * before the `$`). The lexer hands `$field` as one GLOBAL token whose
   * text includes the `$`; strip it for the field name. Without this,
   * `other$value` split into a juxtaposition call — `other($value)` —
   * which lowered `(other$value >> 48) & 0xFFFF == 0xFFFA` through a
   * closure invocation instead of a raw NaN-box tag check. */
  if (end > start + 1 && p->tokens->items[end - 1].kind == TC_K_GLOBAL &&
      !token_sp_before_ast(p, end - 1)) {
    size_t gpos = end - 1;
    char *gtext = NULL;
    size_t gtext_len = 0;
    if (!token_text_at_ast(p, gpos, &gtext, &gtext_len, err)) return tc_ast_nil();
    if (gtext_len > 1 && gtext[0] == '$') {
      TcAstValue receiver = parse_expr_span_ast(p, start, gpos, err);
      if (receiver.kind == TC_AST_NIL) {
        free(gtext);
        return tc_ast_nil();
      }
      TcAstValue node = node_hash(p, "view_field_var", gpos, err);
      if (node.kind != TC_AST_HASH ||
          !tc_ast_hash_set(node, "receiver", receiver, err) ||
          !tc_ast_hash_set(node, "field", tc_ast_string_copy(gtext + 1, gtext_len - 1, err), err) ||
          !stamp_node_loc(p, node, gpos, err)) {
        free(gtext);
        tc_ast_free(node);
        return tc_ast_nil();
      }
      free(gtext);
      return node;
    }
    free(gtext);
  }

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

static int parse_param_list_ast(TcAstParser *p, int paren_open, TcAstValue *out, TcError *err) {
  TcAstValue params = tc_ast_array_new(err);
  if (params.kind != TC_AST_ARRAY) return 0;
  /* paren_open: the caller consumed a fused name+LPAREN token
   * (BLOCK_CALL `&(`), so the list is already open. */
  if (!paren_open && !match_ast(p, TC_K_LPAREN)) {
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
  /* A leading '/' IS the method name (`-> /(other)` — the division
   * operator overload); the arity suffix can only follow it. Splitting at
   * position 0 registered the method under an EMPTY symbol. */
  char *slash = strchr(name[0] == '/' ? name + 1 : name, '/');
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
         kind == TC_K_EQ || kind == TC_K_LT || kind == TC_K_GT || kind == TC_K_LBRACKET ||
         kind == TC_K_PUTS_OP || kind == TC_K_CLASS_DEF ||
         kind == TC_K_AMPERSAND || kind == TC_K_PIPE || kind == TC_K_CARET || kind == TC_K_PERCENT ||
         kind == TC_K_LSHIFT || kind == TC_K_RSHIFT;
}

/* Lookahead: does the paren group at p->pos hold only type-name tokens
 * (builtin lowercase TC_K_TYPE or capitalized TC_K_NAME class names,
 * each with an optional `[]` suffix) up to the closing paren? Mirrors
 * compiler/lib/parser.w's looks_like_param_types? so `-> +/1(BigInt)`
 * and `-> combine(other)(BigInt)` read the group as a param-type
 * annotation while `(a + b)` / `(Foo.bar)` trailing expressions fall
 * through untouched. Empty parens are not a type list. */
static int paren_is_type_list_ast(const TcAstParser *p) {
  if (p->pos >= p->tokens->count || p->tokens->items[p->pos].kind != TC_K_LPAREN) return 0;
  size_t pos = p->pos + 1;
  size_t limit = pos + 256;  /* safety cap, same spirit as the self-hosted walk */
  int saw_type = 0;
  while (pos < p->tokens->count && pos < limit) {
    TcKind kind = p->tokens->items[pos].kind;
    if (kind == TC_K_RPAREN) return saw_type;
    if (kind != TC_K_TYPE && kind != TC_K_NAME) return 0;
    saw_type = 1;
    pos++;
    if (pos + 1 < p->tokens->count && p->tokens->items[pos].kind == TC_K_LBRACKET &&
        p->tokens->items[pos + 1].kind == TC_K_RBRACKET) {
      pos += 2;
    }
  }
  return 0;
}

/* Capture a param-type paren group as the canonical array-of-symbols
 * shape the self-hosted parser produces (parser.w
 * parse_type_name_with_array_suffix + to_sym): one symbol per TYPE/NAME
 * token, a "[]" suffix folded in when an empty bracket pair follows,
 * commas tolerated as separators. p->pos must sit on the LPAREN; on
 * success it sits past the RPAREN. The hosted compiler's lowering walks
 * node.param_types as an array (definitions.w populate_definition_var_types),
 * so a raw-string shape here silently unypes every annotated param — fatal
 * for embedded ll/asm fns whose gate requires machine-int params. */
static TcAstValue capture_param_types_ast(TcAstParser *p, TcError *err) {
  TcAstValue arr = tc_ast_array_new(err);
  if (arr.kind != TC_AST_ARRAY) return tc_ast_nil();
  advance_ast(p);
  while (!at_ast(p, TC_K_RPAREN) && !at_ast(p, TC_K_EOF)) {
    TcKind kind = current_ast(p).kind;
    if (kind == TC_K_COMMA) {
      advance_ast(p);
      continue;
    }
    if (kind != TC_K_TYPE && kind != TC_K_NAME) {
      parse_ast_error(p, err, "expected type name in param type list");
      tc_ast_free(arr);
      return tc_ast_nil();
    }
    char *tname = NULL;
    size_t tname_len = 0;
    if (!current_token_text(p, &tname, &tname_len, err)) {
      tc_ast_free(arr);
      return tc_ast_nil();
    }
    advance_ast(p);
    if (p->pos + 1 < p->tokens->count && at_ast(p, TC_K_LBRACKET) &&
        p->tokens->items[p->pos + 1].kind == TC_K_RBRACKET) {
      if (!append_bytes(&tname, &tname_len, "[]", 2, err)) {
        free(tname);
        tc_ast_free(arr);
        return tc_ast_nil();
      }
      advance_ast(p);
      advance_ast(p);
    }
    TcAstValue sym = tc_ast_symbol_copy(tname, tname_len, err);
    free(tname);
    if (sym.kind != TC_AST_SYMBOL || !tc_ast_array_push(arr, sym, err)) {
      tc_ast_free(sym);
      tc_ast_free(arr);
      return tc_ast_nil();
    }
  }
  if (!match_ast(p, TC_K_RPAREN)) {
    parse_ast_error(p, err, "expected ')' after param types");
    tc_ast_free(arr);
    return tc_ast_nil();
  }
  return arr;
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

  /* `-> &(other)` — the lexer fuses `&(` into one BLOCK_CALL token, so
   * the method name is `&` and the param list's LPAREN is already
   * consumed; parse_param_list_ast is told the list is open. */
  int fused_amp_paren = at_ast(p, TC_K_BLOCK_CALL);

  if (!fused_amp_paren && !method_name_token_ast(p)) {
    parse_ast_error(p, err, "expected method name");
    return 0;
  }

  char *name = NULL;
  size_t name_len = 0;
  if (fused_amp_paren) {
    name = malloc(2);
    if (!name) {
      parse_ast_error(p, err, "out of memory");
      return 0;
    }
    name[0] = '&';
    name[1] = '\0';
    name_len = 1;
  } else if (!current_token_text(p, &name, &name_len, err)) {
    return 0;
  }
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

  /* Current lexers leave method arity as separate `/` + suffix tokens so
   * ordinary `value/10` remains expression division. Reconstruct the legacy
   * bundled spelling here, then reuse split_method_arity below. */
  if (match_ast(p, TC_K_SLASH)) {
    TcKind suffix_kind = current_ast(p).kind;
    if (suffix_kind == TC_K_INT || suffix_kind == TC_K_STAR || suffix_kind == TC_K_AMPERSAND) {
      char *suffix = NULL;
      size_t suffix_len = 0;
      if (!current_token_text(p, &suffix, &suffix_len, err) ||
          !append_bytes(&name, &name_len, "/", 1, err) ||
          !append_bytes(&name, &name_len, suffix, suffix_len, err)) {
        free(suffix);
        free(name);
        return 0;
      }
      free(suffix);
      advance_ast(p);
    } else {
      free(name);
      parse_ast_error(p, err, "expected method arity after '/'");
      return 0;
    }
  }

  const char *arity = NULL;
  size_t arity_len = 0;
  split_method_arity(name, &name_len, &arity, &arity_len);

  TcAstValue params;
  TcAstValue param_types = tc_ast_nil();
  if (arity && paren_is_type_list_ast(p)) {
    /* Arity-suffix form (`-> +/1(BigInt)`): a paren group holding only
     * type names annotates the positional @N args — it must NOT be
     * swallowed as the param list. Mirrors compiler/lib/parser.w's
     * signature-annotation handling: params stay empty (compile_function_def
     * synthesizes the __argN slots from the arity) and the group is
     * captured as param_types. */
    params = tc_ast_array_new(err);
    if (params.kind != TC_AST_ARRAY) {
      free(name);
      return 0;
    }
    param_types = capture_param_types_ast(p, err);
    if (param_types.kind != TC_AST_ARRAY) {
      free(name);
      tc_ast_free(params);
      return 0;
    }
  } else if (!parse_param_list_ast(p, fused_amp_paren, &params, err)) {
    free(name);
    return 0;
  }

  if (param_types.kind == TC_AST_NIL && at_ast(p, TC_K_LPAREN) && p->pos + 1 < p->tokens->count) {
    /* Param-type annotation after the param list. Lowercase machine
     * types (`(i64 i64)`) keep the historical first-token gate;
     * capitalized class names (`(BigInt)`, TC_K_NAME) additionally need
     * the full type-list walk so a trailing parenthesized expression is
     * never mis-captured. */
    TcKind first_kind = p->tokens->items[p->pos + 1].kind;
    if (first_kind == TC_K_TYPE ||
        (first_kind == TC_K_NAME && paren_is_type_list_ast(p))) {
      param_types = capture_param_types_ast(p, err);
      if (param_types.kind != TC_AST_ARRAY) {
        free(name);
        tc_ast_free(params);
        return 0;
      }
    }
  }

  /* Digit arity suffix (`-> >>/1(Int)`, `-> foo/2`): the canonical
   * parser synthesizes the positional `__argN` params in the AST, so
   * the hosted compiler sees a complete signature. Without them the
   * fn lowers with the wrong LLVM arity and `@1` in the body degrades
   * to a slab-string read. The C VM's own compile_function_def fills
   * missing slots identically, so pre-filled params stay in lockstep. */
  if (arity && arity_len > 0 && params.kind == TC_AST_ARRAY &&
      (!params.as.array || params.as.array->count == 0)) {
    long long synth_n = 0;
    int all_digits = 1;
    for (size_t di = 0; di < arity_len; di++) {
      if (arity[di] < '0' || arity[di] > '9') {
        all_digits = 0;
        break;
      }
      synth_n = synth_n * 10 + (arity[di] - '0');
    }
    if (all_digits && synth_n > 0 && synth_n <= 64) {
      for (long long ai = 1; ai <= synth_n; ai++) {
        char synth[32];
        int slen = snprintf(synth, sizeof(synth), "__arg%lld", ai);
        TcAstValue pnode = node_hash(p, "param", start, err);
        if (pnode.kind != TC_AST_HASH ||
            !tc_ast_hash_set(pnode, "name", tc_ast_string_copy(synth, (size_t)slen, err), err) ||
            !tc_ast_hash_set(pnode, "default", tc_ast_nil(), err) ||
            !tc_ast_hash_set(pnode, "ivar_assign", tc_ast_bool(0), err) ||
            !tc_ast_hash_set(pnode, "keyword", tc_ast_bool(0), err) ||
            !tc_ast_hash_set(pnode, "block_param", tc_ast_bool(0), err) ||
            !tc_ast_hash_set(pnode, "splat", tc_ast_bool(0), err) ||
            !tc_ast_array_push(params, pnode, err)) {
          tc_ast_free(pnode);
          free(name);
          tc_ast_free(params);
          tc_ast_free(param_types);
          return 0;
        }
      }
    }
    /* `-> name/&` — block arity. The canonical parser synthesizes
     * Param("&", …, block_param: true), whose runtime name is
     * "__yield_block" (definitions.w param_runtime_name). Without it the
     * fn's block slot fell back to the implicit-yield "__block" name and
     * every such define diverged on the parameter spelling. */
    if (arity_len == 1 && arity[0] == '&') {
      TcAstValue pnode = node_hash(p, "param", start, err);
      if (pnode.kind != TC_AST_HASH ||
          !tc_ast_hash_set(pnode, "name", tc_ast_string_copy("&", 1, err), err) ||
          !tc_ast_hash_set(pnode, "default", tc_ast_nil(), err) ||
          !tc_ast_hash_set(pnode, "ivar_assign", tc_ast_bool(0), err) ||
          !tc_ast_hash_set(pnode, "keyword", tc_ast_bool(0), err) ||
          !tc_ast_hash_set(pnode, "block_param", tc_ast_bool(1), err) ||
          !tc_ast_hash_set(pnode, "splat", tc_ast_bool(0), err) ||
          !tc_ast_array_push(params, pnode, err)) {
        tc_ast_free(pnode);
        free(name);
        tc_ast_free(params);
        tc_ast_free(param_types);
        return 0;
      }
    }
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
  TcAstValue trailing = tc_ast_nil();
  if (has_inline && inline_start < header_end) {
    trailing = parse_expr_span_ast(p, inline_start, header_end, err);
    if (trailing.kind == TC_AST_NIL) {
      free(name);
      tc_ast_free(body);
      tc_ast_free(params);
      tc_ast_free(param_types);
      tc_ast_free(return_type);
      return 0;
    }
  }
  int accumulator_form = trailing.kind != TC_AST_NIL && at_ast(p, TC_K_INDENT);
  if (!accumulator_form && trailing.kind != TC_AST_NIL) {
    if (!tc_ast_array_push(body, trailing, err)) {
      free(name);
      tc_ast_free(trailing);
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
    /* Trailing expr + indented body = accumulator form (parser.w): seed
     * `<acc> = <trailing>` (or keep an explicit `<acc> = seed` assign),
     * run the body, and return the accumulator. Without this rewrite the
     * seed becomes a dead statement, `out.push` reads an undefined name,
     * and the method returns its last statement instead. */
    const char *acc_name = NULL;
    size_t acc_name_len = 0;
    if (accumulator_form) {
      if (ast_node_is(trailing, "assign")) {
        TcAstValue *tgt = hash_value_ast(trailing, "target");
        if (tgt && ast_node_is(*tgt, "var")) {
          TcAstValue *nm = hash_value_ast(*tgt, "name");
          if (nm && nm->kind == TC_AST_STRING) {
            acc_name = nm->as.string.bytes;
            acc_name_len = nm->as.string.len;
            if (!tc_ast_array_push(body, trailing, err)) {
              free(name);
              tc_ast_free(body);
              tc_ast_free(params);
              tc_ast_free(param_types);
              tc_ast_free(return_type);
              return 0;
            }
          }
        }
      }
      if (!acc_name) {
        const char *det = pa_detect_acc(block_body);
        acc_name = det ? det : "out";
        acc_name_len = strlen(acc_name);
        TcAstValue acc_var = node_hash(p, "var", start, err);
        TcAstValue init = node_hash(p, "assign", start, err);
        if (acc_var.kind != TC_AST_HASH || init.kind != TC_AST_HASH ||
            !tc_ast_hash_set(acc_var, "name", tc_ast_string_copy(acc_name, acc_name_len, err), err) ||
            !tc_ast_hash_set(init, "target", acc_var, err) ||
            !tc_ast_hash_set(init, "value", trailing, err) ||
            !tc_ast_hash_set(init, "type_hint", tc_ast_nil(), err) ||
            !tc_ast_array_push(body, init, err)) {
          free(name);
          tc_ast_free(body);
          tc_ast_free(params);
          tc_ast_free(param_types);
          tc_ast_free(return_type);
          return 0;
        }
      }
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
    if (accumulator_form) {
      TcAstValue ret_var = node_hash(p, "var", start, err);
      if (ret_var.kind != TC_AST_HASH ||
          !tc_ast_hash_set(ret_var, "name", tc_ast_string_copy(acc_name, acc_name_len, err), err) ||
          !tc_ast_array_push(body, ret_var, err)) {
        free(name);
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

/* `fn name(args) (types) return_type` has the same concrete signature/body
 * grammar as `-> name(args) ...`. The native parser makes it a top-level
 * fn_def, but inside a class it is a method_def carrying from_fn=true so
 * method registration and memo/raw-ABI behavior match source semantics. */
static int parse_fn_def_ast(TcAstParser *p, TcAstValue type_hints,
                            TcAstValue *out, TcError *err) {
  if (!parse_method_def_ast(p, type_hints, out, err)) return 0;
  if (p->class_depth > 0) {
    if (!tc_ast_hash_set(*out, "from_fn", tc_ast_bool(1), err)) {
      tc_ast_free(*out);
      *out = tc_ast_nil();
      return 0;
    }
    return 1;
  }
  TcAstValue kind = tc_ast_symbol_copy("fn_def", 6, err);
  if (kind.kind != TC_AST_SYMBOL || !tc_ast_hash_set(*out, "node", kind, err)) {
    tc_ast_free(*out);
    *out = tc_ast_nil();
    return 0;
  }
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
  p->class_depth++;
  int body_ok = parse_optional_body_ast(p, &body, err);
  p->class_depth--;
  if (!body_ok) {
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

/* `- data` memory-layout block (canonical parser.w "Data declaration"):
 *
 *   - data (WArray)          ← optional backing C-struct name
 *     u8    flags
 *     u8[2] _pad
 *     T components[4]        ← bracket may follow the field name too
 *   * u8[]  slots            ← `*` marks a base-pointer field; such lines
 *                              may sit at the OUTER indent after a dedent
 *
 * or `- data` + `raw N`. Emits the canonical shape lowering's
 * collect_view_fields consumes:
 *   {node: :view_decl, name: "data", kind: "struct"|"raw",
 *    count: {fields: [{name, type}, ...], struct_name: <str|nil>} | <int>}
 * Without this, fast-parsed classes carry NO view layout and every
 * `$field` access degrades to dynamic dispatch — the compiled BigInt's
 * `$size` reads crashed with "undefined method '$size'". */
/* First `out`/`acc` variable use in a subtree — mirrors parser.w
 * detect_accumulator_name for the trailing-expression accumulator form
 * (`-> dup() []` seeds `out = []`, runs the body, returns `out`). */
static const char *pa_detect_acc(TcAstValue v) {
  if (v.kind == TC_AST_ARRAY && v.as.array) {
    for (size_t i = 0; i < v.as.array->count; i++) {
      const char *r = pa_detect_acc(v.as.array->items[i]);
      if (r) return r;
    }
    return NULL;
  }
  if (v.kind != TC_AST_HASH || !v.as.hash) return NULL;
  if (ast_node_is(v, "var")) {
    TcAstValue *nm = hash_value_ast(v, "name");
    if (nm && nm->kind == TC_AST_STRING) {
      if (nm->as.string.len == 3 && memcmp(nm->as.string.bytes, "out", 3) == 0) return "out";
      if (nm->as.string.len == 3 && memcmp(nm->as.string.bytes, "acc", 3) == 0) return "acc";
    }
    return NULL;
  }
  for (size_t i = 0; i < v.as.hash->count; i++) {
    const char *r = pa_detect_acc(v.as.hash->items[i].value);
    if (r) return r;
  }
  return NULL;
}

static int parse_view_data_field_bracket(TcAstParser *p, char **ftype, size_t *ftype_len,
                                         TcError *err) {
  /* p->pos sits on '['; append the verbatim "[...]" suffix to ftype. */
  advance_ast(p);
  if (!append_bytes(ftype, ftype_len, "[", 1, err)) return 0;
  while (!at_ast(p, TC_K_RBRACKET) && !at_ast(p, TC_K_EOF) &&
         !at_ast(p, TC_K_NEWLINE)) {
    char *part = NULL;
    size_t part_len = 0;
    if (!current_token_text(p, &part, &part_len, err)) return 0;
    int ok = append_bytes(ftype, ftype_len, part, part_len, err);
    free(part);
    if (!ok) return 0;
    advance_ast(p);
  }
  if (!match_ast(p, TC_K_RBRACKET)) {
    parse_ast_error(p, err, "expected ']' in data-field array suffix");
    return 0;
  }
  return append_bytes(ftype, ftype_len, "]", 1, err);
}

static int parse_view_data_field(TcAstParser *p, TcAstValue *out, TcError *err) {
  int pointer = 0;
  if (at_ast(p, TC_K_STAR)) {
    pointer = 1;
    advance_ast(p);
  }
  TcKind kind = current_ast(p).kind;
  if (kind != TC_K_ID && kind != TC_K_TYPE && kind != TC_K_NAME) {
    parse_ast_error(p, err, "expected data field type");
    return 0;
  }
  char *ftype = NULL;
  size_t ftype_len = 0;
  if (!current_token_text(p, &ftype, &ftype_len, err)) return 0;
  advance_ast(p);
  if (at_ast(p, TC_K_LBRACKET) &&
      !parse_view_data_field_bracket(p, &ftype, &ftype_len, err)) {
    free(ftype);
    return 0;
  }
  kind = current_ast(p).kind;
  if (kind != TC_K_ID && kind != TC_K_TYPE && kind != TC_K_NAME) {
    parse_ast_error(p, err, "expected data field name");
    free(ftype);
    return 0;
  }
  char *fname = NULL;
  size_t fname_len = 0;
  if (!current_token_text(p, &fname, &fname_len, err)) {
    free(ftype);
    return 0;
  }
  advance_ast(p);
  if (at_ast(p, TC_K_LBRACKET) &&
      !parse_view_data_field_bracket(p, &ftype, &ftype_len, err)) {
    free(ftype);
    free(fname);
    return 0;
  }
  if (pointer) {
    char *starred = (char *)malloc(ftype_len + 2);
    if (!starred) {
      tc_error_set(err, "data field type allocation failed");
      free(ftype);
      free(fname);
      return 0;
    }
    starred[0] = '*';
    memcpy(starred + 1, ftype, ftype_len);
    starred[ftype_len + 1] = '\0';
    free(ftype);
    ftype = starred;
    ftype_len += 1;
  }
  TcAstValue entry = tc_ast_hash_new(err);
  if (entry.kind != TC_AST_HASH ||
      !tc_ast_hash_set(entry, "name", tc_ast_string_copy(fname, fname_len, err), err) ||
      !tc_ast_hash_set(entry, "type", tc_ast_string_copy(ftype, ftype_len, err), err)) {
    free(ftype);
    free(fname);
    tc_ast_free(entry);
    return 0;
  }
  free(ftype);
  free(fname);
  *out = entry;
  return 1;
}

static int parse_view_decl_ast(TcAstParser *p, TcAstValue *out, TcError *err) {
  size_t start = p->pos;
  advance_ast(p);  /* `-` */
  advance_ast(p);  /* `data` */

  TcAstValue struct_name = tc_ast_nil();
  if (at_ast(p, TC_K_LPAREN)) {
    advance_ast(p);
    TcKind kind = current_ast(p).kind;
    if (kind == TC_K_ID || kind == TC_K_TYPE || kind == TC_K_NAME) {
      char *sname = NULL;
      size_t sname_len = 0;
      if (!current_token_text(p, &sname, &sname_len, err)) return 0;
      struct_name = tc_ast_string_copy(sname, sname_len, err);
      free(sname);
      if (struct_name.kind != TC_AST_STRING) return 0;
      advance_ast(p);
    }
    if (!match_ast(p, TC_K_RPAREN)) {
      parse_ast_error(p, err, "expected ')' after data struct name");
      tc_ast_free(struct_name);
      return 0;
    }
  }
  skip_newlines_ast(p);

  TcAstValue node = node_hash(p, "view_decl", start, err);
  if (node.kind != TC_AST_HASH ||
      !tc_ast_hash_set(node, "name", tc_ast_string_copy("data", 4, err), err)) {
    tc_ast_free(struct_name);
    tc_ast_free(node);
    return 0;
  }

  if (!at_ast(p, TC_K_INDENT)) {
    /* Empty block: struct kind with no fields. */
    TcAstValue layout = tc_ast_hash_new(err);
    if (layout.kind != TC_AST_HASH ||
        !tc_ast_hash_set(layout, "fields", tc_ast_array_new(err), err) ||
        !tc_ast_hash_set(layout, "struct_name", struct_name, err) ||
        !tc_ast_hash_set(node, "kind", tc_ast_string_copy("struct", 6, err), err) ||
        !tc_ast_hash_set(node, "count", layout, err)) {
      tc_ast_free(layout);
      tc_ast_free(node);
      return 0;
    }
    *out = node;
    return 1;
  }
  advance_ast(p);  /* INDENT */
  skip_newlines_ast(p);

  /* `raw N` byte layout. */
  if (at_ast(p, TC_K_ID)) {
    char *maybe_raw = NULL;
    size_t maybe_raw_len = 0;
    if (!token_text_at_ast(p, p->pos, &maybe_raw, &maybe_raw_len, err)) {
      tc_ast_free(struct_name);
      tc_ast_free(node);
      return 0;
    }
    int is_raw = maybe_raw_len == 3 && memcmp(maybe_raw, "raw", 3) == 0;
    free(maybe_raw);
    if (is_raw) {
      advance_ast(p);
      if (current_ast(p).kind != TC_K_INT) {
        parse_ast_error(p, err, "expected byte count after `raw`");
        tc_ast_free(struct_name);
        tc_ast_free(node);
        return 0;
      }
      char *count_text = NULL;
      size_t count_text_len = 0;
      if (!current_token_text(p, &count_text, &count_text_len, err)) {
        tc_ast_free(struct_name);
        tc_ast_free(node);
        return 0;
      }
      long long count_value = strtoll(count_text, NULL, 10);
      free(count_text);
      advance_ast(p);
      skip_newlines_ast(p);
      if (at_ast(p, TC_K_DEDENT)) advance_ast(p);
      tc_ast_free(struct_name);
      if (!tc_ast_hash_set(node, "kind", tc_ast_string_copy("raw", 3, err), err) ||
          !tc_ast_hash_set(node, "count", tc_ast_int(count_value), err)) {
        tc_ast_free(node);
        return 0;
      }
      *out = node;
      return 1;
    }
  }

  /* Structured layout: typed fields, with the canonical parser's depth
   * walk — `*` base-pointer lines may continue at the OUTER indent
   * after a dedent (core/array.w's `* u8[] slots`). */
  TcAstValue fields = tc_ast_array_new(err);
  if (fields.kind != TC_AST_ARRAY) {
    tc_ast_free(struct_name);
    tc_ast_free(node);
    return 0;
  }
  int depth = 1;
  int base_pointer_line = 0;
  while (depth > 0 && !at_ast(p, TC_K_EOF)) {
    TcKind kind = current_ast(p).kind;
    if (kind == TC_K_INDENT) {
      depth += 1;
      advance_ast(p);
    } else if (kind == TC_K_DEDENT) {
      depth -= 1;
      advance_ast(p);
      if (depth == 0 && at_ast(p, TC_K_STAR)) {
        depth = 1;
        base_pointer_line = 1;
      }
    } else if (kind == TC_K_NEWLINE) {
      advance_ast(p);
      if (base_pointer_line && !at_ast(p, TC_K_STAR)) break;
    } else if (kind == TC_K_STAR || kind == TC_K_ID || kind == TC_K_TYPE ||
               kind == TC_K_NAME) {
      TcAstValue entry;
      if (!parse_view_data_field(p, &entry, err)) {
        tc_ast_free(fields);
        tc_ast_free(struct_name);
        tc_ast_free(node);
        return 0;
      }
      if (!tc_ast_array_push(fields, entry, err)) {
        tc_ast_free(fields);
        tc_ast_free(struct_name);
        tc_ast_free(node);
        return 0;
      }
    } else {
      advance_ast(p);
    }
  }
  TcAstValue layout = tc_ast_hash_new(err);
  if (layout.kind != TC_AST_HASH ||
      !tc_ast_hash_set(layout, "fields", fields, err) ||
      !tc_ast_hash_set(layout, "struct_name", struct_name, err) ||
      !tc_ast_hash_set(node, "kind", tc_ast_string_copy("struct", 6, err), err) ||
      !tc_ast_hash_set(node, "count", layout, err)) {
    tc_ast_free(layout);
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
  int method_scope = strcmp(node_name, "trait_def") == 0;
  if (method_scope) p->class_depth++;
  int body_ok = parse_optional_body_ast(p, &body, err);
  if (method_scope) p->class_depth--;
  if (!body_ok) {
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

/* The lex64 bootstrap lexer intentionally stays context-free and therefore
 * tokenizes `ll <<~IR ... IR` as ordinary operators/names plus the tokens in
 * the heredoc body. Reconstruct the heredoc here, from the original source,
 * into the same AST shape the self-hosted lexer/parser produces:
 *
 *   {node: :call, name: "ll", args: [{node: :string, value: "..."}]}
 *
 * This is a general bare-command heredoc parse, rather than an ll-specific
 * skip: stage0 must preserve the embedded source text for downstream
 * definition lowering. The body dedent mirrors Lexer#scan_heredoc.
 * `matched` distinguishes an ordinary shift expression from an error while
 * parsing a recognized `<<~` header. */
static int parse_heredoc_command_ast(TcAstParser *p, TcAstValue *out,
                                     int *matched, TcError *err) {
  *matched = 0;
  size_t start = p->pos;
  if (start + 3 >= p->tokens->count ||
      !name_kind_ast(p->tokens->items[start].kind) ||
      p->tokens->items[start + 1].kind != TC_K_LSHIFT ||
      p->tokens->items[start + 2].kind != TC_K_UNKNOWN ||
      !name_kind_ast(p->tokens->items[start + 3].kind) ||
      !tc_token_text_eq(p->source, p->tokens->items[start + 2].packed, "~")) {
    return 1;
  }

  WValue shift_tok = p->tokens->items[start + 1].packed;
  WValue tilde_tok = p->tokens->items[start + 2].packed;
  uint32_t shift_end_cp = tc_token_offset(shift_tok) + tc_token_length(shift_tok);
  uint32_t shift_end = p->source->byte_offsets[shift_end_cp];
  uint32_t tilde_start = p->source->byte_offsets[tc_token_offset(tilde_tok)];
  if (shift_end != tilde_start) return 1; /* `x << ~y`, not `<<~DELIM`. */

  *matched = 1;
  char *command = NULL;
  size_t command_len = 0;
  char *delimiter = NULL;
  size_t delimiter_len = 0;
  if (!token_text_at_ast(p, start, &command, &command_len, err) ||
      !token_text_at_ast(p, start + 3, &delimiter, &delimiter_len, err)) {
    free(command);
    free(delimiter);
    return 0;
  }

  WValue delimiter_tok = p->tokens->items[start + 3].packed;
  size_t delimiter_end =
      p->source->byte_offsets[tc_token_offset(delimiter_tok) + tc_token_length(delimiter_tok)];
  size_t header_end = delimiter_end;
  while (header_end < p->source->byte_len && p->source->bytes[header_end] != '\n') header_end++;
  if (header_end >= p->source->byte_len) {
    tc_error_set(err, "Unterminated heredoc (expected %.*s) on line %d",
                 (int)delimiter_len, delimiter,
                 token_line_ast(p->source, p->tokens->items[start].packed));
    free(command);
    free(delimiter);
    return 0;
  }

  size_t body_start = header_end + 1;
  size_t close_start = p->source->byte_len;
  size_t close_end = p->source->byte_len;
  size_t min_indent = (size_t)-1;
  size_t line_start = body_start;
  while (line_start <= p->source->byte_len) {
    size_t line_end = line_start;
    while (line_end < p->source->byte_len && p->source->bytes[line_end] != '\n') line_end++;

    size_t indent = 0;
    while (line_start + indent < line_end &&
           (p->source->bytes[line_start + indent] == ' ' ||
            p->source->bytes[line_start + indent] == '\t')) {
      indent++;
    }
    size_t after_delimiter = line_start + indent + delimiter_len;
    int closes = after_delimiter <= line_end &&
                 memcmp(p->source->bytes + line_start + indent,
                        delimiter, delimiter_len) == 0;
    if (closes) {
      size_t rest = after_delimiter;
      while (rest < line_end &&
             (p->source->bytes[rest] == ' ' || p->source->bytes[rest] == '\t')) {
        rest++;
      }
      closes = rest == line_end;
    }
    if (closes) {
      close_start = line_start;
      close_end = line_end;
      break;
    }

    int nonblank = 0;
    for (size_t i = line_start; i < line_end; i++) {
      if (p->source->bytes[i] != ' ' && p->source->bytes[i] != '\t') {
        nonblank = 1;
        break;
      }
    }
    if (nonblank && indent < min_indent) min_indent = indent;
    if (line_end >= p->source->byte_len) break;
    line_start = line_end + 1;
  }

  if (close_start == p->source->byte_len) {
    tc_error_set(err, "Unterminated heredoc (expected %.*s) on line %d",
                 (int)delimiter_len, delimiter,
                 token_line_ast(p->source, p->tokens->items[start].packed));
    free(command);
    free(delimiter);
    return 0;
  }

  size_t body_cap = close_start >= body_start ? close_start - body_start + 1 : 1;
  char *body_text = (char *)malloc(body_cap);
  if (!body_text) {
    tc_error_set(err, "heredoc AST allocation failed");
    free(command);
    free(delimiter);
    return 0;
  }
  size_t body_len = 0;
  line_start = body_start;
  while (line_start < close_start) {
    size_t line_end = line_start;
    while (line_end < close_start && p->source->bytes[line_end] != '\n') line_end++;
    size_t line_len = line_end - line_start;
    if (line_len > 0 && min_indent != (size_t)-1 && line_len > min_indent) {
      size_t copy_len = line_len - min_indent;
      memcpy(body_text + body_len, p->source->bytes + line_start + min_indent, copy_len);
      body_len += copy_len;
    } else if (line_len > 0 && min_indent == (size_t)-1) {
      memcpy(body_text + body_len, p->source->bytes + line_start, line_len);
      body_len += line_len;
    }
    if (line_end < close_start && line_end + 1 < close_start) body_text[body_len++] = '\n';
    line_start = line_end < close_start ? line_end + 1 : close_start;
  }
  body_text[body_len] = '\0';

  TcAstValue string_node = node_hash(p, "string", start + 3, err);
  TcAstValue args = tc_ast_array_new(err);
  TcAstValue body_value = tc_ast_string_copy(body_text, body_len, err);
  free(body_text);
  if (string_node.kind != TC_AST_HASH || args.kind != TC_AST_ARRAY ||
      body_value.kind != TC_AST_STRING ||
      !tc_ast_hash_set(string_node, "value", body_value, err) ||
      !tc_ast_array_push(args, string_node, err)) {
    tc_ast_free(string_node);
    tc_ast_free(args);
    free(command);
    free(delimiter);
    return 0;
  }

  TcAstValue call = call_node_ast(p, start, start, tc_ast_nil(), command, command_len, args, err);
  free(command);
  free(delimiter);
  if (call.kind != TC_AST_HASH) {
    tc_ast_free(call);
    return 0;
  }

  size_t after_close = close_end < p->source->byte_len ? close_end + 1 : close_end;
  while (p->pos < p->tokens->count) {
    WValue tok = p->tokens->items[p->pos].packed;
    size_t tok_start = p->source->byte_offsets[tc_token_offset(tok)];
    if (tok_start >= after_close) break;
    p->pos++;
  }
  *out = call;
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
  /* `- ivars` / `- data` class-body directives — typed layout blocks. */
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
    if (next_text && next_text_len == 4 && memcmp(next_text, "data", 4) == 0) {
      free(next_text);
      tc_ast_free(type_hints);
      return parse_view_decl_ast(p, out, err);
    }
    free(next_text);
  }
  int heredoc_matched = 0;
  TcAstValue heredoc = tc_ast_nil();
  if (!parse_heredoc_command_ast(p, &heredoc, &heredoc_matched, err)) {
    tc_ast_free(type_hints);
    return 0;
  }
  if (heredoc_matched) {
    if (type_hints.kind != TC_AST_NIL &&
        !tc_ast_hash_set(heredoc, "type_hints", type_hints, err)) {
      tc_ast_free(type_hints);
      tc_ast_free(heredoc);
      return 0;
    }
    *out = heredoc;
    return 1;
  }
  if (at_keyword_ast(p, "fn")) return parse_fn_def_ast(p, type_hints, out, err);
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
      .class_depth = 0,
      .loc_file_id = g_tc_parse_loc_file_id,
  };
  TcAstValue expressions = tc_ast_array_new(err);
  if (expressions.kind != TC_AST_ARRAY) return 0;

  skip_newlines_ast(&parser);
  while (!at_ast(&parser, TC_K_EOF)) {
    if (at_ast(&parser, TC_K_DEDENT)) {
      parse_ast_error(&parser, err, "unexpected DEDENT at top level");
      tc_ast_free(expressions);
      return 0;
    }
    size_t statement_start = parser.pos;
    TcAstValue stmt;
    if (!parse_ast_statement(&parser, &stmt, err)) {
      tc_ast_free(expressions);
      return 0;
    }
    if (parser.pos == statement_start) {
      parse_ast_error(&parser, err, "parser made no progress");
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
