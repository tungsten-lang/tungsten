#include "tc.h"

#include <string.h>

typedef struct {
  const TcSource *source;
  const TcSyntaxTokens *tokens;
  size_t pos;
} TcParseCheck;

static TcSyntaxToken current(TcParseCheck *p) {
  if (p->pos >= p->tokens->count) return p->tokens->items[p->tokens->count - 1];
  return p->tokens->items[p->pos];
}

static TcSyntaxToken peek(TcParseCheck *p, size_t offset) {
  size_t pos = p->pos + offset;
  if (pos >= p->tokens->count) return p->tokens->items[p->tokens->count - 1];
  return p->tokens->items[pos];
}

static int at(TcParseCheck *p, TcKind kind) {
  return current(p).kind == kind;
}

static int at_keyword(TcParseCheck *p, const char *word) {
  TcSyntaxToken tok = current(p);
  return tok.kind == TC_K_KEYWORD && tc_token_text_eq(p->source, tok.packed, word);
}

static int token_line(const TcSource *source, WValue token) {
  uint32_t off = tc_token_offset(token);
  uint32_t byte = source->byte_offsets[off];
  int line = 1;
  for (uint32_t i = 0; i < byte; i++) {
    if (source->bytes[i] == '\n') line++;
  }
  return line;
}

static void parse_error(TcParseCheck *p, TcError *err, const char *message) {
  TcSyntaxToken tok = current(p);
  tc_error_set(err, "parse-check error on line %d near %s: %s", token_line(p->source, tok.packed),
               tc_kind_name(tok.kind), message);
}

static void advance(TcParseCheck *p) {
  if (p->pos < p->tokens->count) p->pos++;
}

static int match(TcParseCheck *p, TcKind kind) {
  if (!at(p, kind)) return 0;
  advance(p);
  return 1;
}

static void skip_newlines(TcParseCheck *p) {
  while (at(p, TC_K_NEWLINE) || at(p, TC_K_SEMICOLON) || at(p, TC_K_TYPE_HINT)) advance(p);
}

static int parse_program(TcParseCheck *p, TcError *err);
static int parse_body(TcParseCheck *p, TcError *err);
static int parse_statement(TcParseCheck *p, TcError *err);

static int consume_to_statement_end(TcParseCheck *p, TcError *err) {
  int paren = 0;
  int bracket = 0;
  int brace = 0;

  while (!at(p, TC_K_EOF)) {
    TcKind kind = current(p).kind;
    if (paren == 0 && bracket == 0 && brace == 0 &&
        (kind == TC_K_NEWLINE || kind == TC_K_SEMICOLON || kind == TC_K_DEDENT)) {
      return 1;
    }

    switch (kind) {
      case TC_K_LPAREN: paren++; break;
      case TC_K_RPAREN:
        if (paren == 0) {
          parse_error(p, err, "unmatched ')'");
          return 0;
        }
        paren--;
        break;
      case TC_K_LBRACKET: bracket++; break;
      case TC_K_RBRACKET:
        if (bracket == 0) {
          parse_error(p, err, "unmatched ']'");
          return 0;
        }
        bracket--;
        break;
      case TC_K_LBRACE: brace++; break;
      case TC_K_RBRACE:
        if (brace == 0) {
          parse_error(p, err, "unmatched '}'");
          return 0;
        }
        brace--;
        break;
      default:
        break;
    }
    advance(p);
  }

  if (paren != 0 || bracket != 0 || brace != 0) {
    parse_error(p, err, "unterminated grouped expression");
    return 0;
  }
  return 1;
}

static int consume_header_line(TcParseCheck *p, TcError *err) {
  if (!consume_to_statement_end(p, err)) return 0;
  while (match(p, TC_K_NEWLINE) || match(p, TC_K_SEMICOLON) || match(p, TC_K_TYPE_HINT)) {}
  return 1;
}

static int parse_optional_body(TcParseCheck *p, TcError *err) {
  if (at(p, TC_K_INDENT)) return parse_body(p, err);
  return 1;
}

static int parse_if_statement(TcParseCheck *p, TcError *err) {
  advance(p);
  if (!consume_header_line(p, err)) return 0;
  if (!parse_optional_body(p, err)) return 0;

  while (at_keyword(p, "elsif")) {
    advance(p);
    if (!consume_header_line(p, err)) return 0;
    if (!parse_optional_body(p, err)) return 0;
  }

  if (at_keyword(p, "else")) {
    advance(p);
    if (!consume_header_line(p, err)) return 0;
    if (!parse_optional_body(p, err)) return 0;
  }

  return 1;
}

static int parse_case_statement(TcParseCheck *p, TcError *err) {
  advance(p);
  if (!consume_header_line(p, err)) return 0;
  if (!match(p, TC_K_INDENT)) return 1;

  skip_newlines(p);
  while (!at(p, TC_K_DEDENT) && !at(p, TC_K_EOF)) {
    if (at_keyword(p, "when")) {
      advance(p);
      if (!consume_header_line(p, err)) return 0;
      if (at(p, TC_K_INDENT)) {
        if (!parse_body(p, err)) return 0;
      }
    } else if (at_keyword(p, "else")) {
      advance(p);
      if (!consume_header_line(p, err)) return 0;
      if (at(p, TC_K_INDENT)) {
        if (!parse_body(p, err)) return 0;
      }
    } else if (!parse_statement(p, err)) {
      return 0;
    }
    skip_newlines(p);
  }

  if (!match(p, TC_K_DEDENT)) {
    parse_error(p, err, "expected DEDENT after case body");
    return 0;
  }
  return 1;
}

static int parse_begin_statement(TcParseCheck *p, TcError *err) {
  advance(p);
  if (!consume_header_line(p, err)) return 0;
  if (!parse_optional_body(p, err)) return 0;

  while (at_keyword(p, "rescue") || at_keyword(p, "ensure")) {
    advance(p);
    if (!consume_header_line(p, err)) return 0;
    if (!parse_optional_body(p, err)) return 0;
  }

  return 1;
}

static int parse_header_body_statement(TcParseCheck *p, TcError *err) {
  advance(p);
  if (!consume_header_line(p, err)) return 0;
  return parse_optional_body(p, err);
}

static int parse_use_statement(TcParseCheck *p, TcError *err) {
  advance(p);
  if (!(current(p).kind == TC_K_STRING || current(p).kind == TC_K_ID || current(p).kind == TC_K_NAME ||
        current(p).kind == TC_K_GLOBAL)) {
    parse_error(p, err, "expected use path");
    return 0;
  }
  advance(p);
  if (!consume_to_statement_end(p, err)) return 0;
  while (match(p, TC_K_NEWLINE) || match(p, TC_K_SEMICOLON) || match(p, TC_K_TYPE_HINT)) {}
  return 1;
}

static int parse_definition_statement(TcParseCheck *p, TcError *err) {
  advance(p);
  if (!consume_header_line(p, err)) return 0;
  return parse_optional_body(p, err);
}

static int parse_statement(TcParseCheck *p, TcError *err) {
  skip_newlines(p);

  if (at(p, TC_K_EOF) || at(p, TC_K_DEDENT)) return 1;
  if (at_keyword(p, "use")) return parse_use_statement(p, err);
  if (at_keyword(p, "if") || at_keyword(p, "unless")) return parse_if_statement(p, err);
  if (at_keyword(p, "case")) return parse_case_statement(p, err);
  if (at_keyword(p, "begin")) return parse_begin_statement(p, err);
  if (at_keyword(p, "while") || at_keyword(p, "until") || at_keyword(p, "with") ||
      at_keyword(p, "parallel") || at_keyword(p, "on") || at_keyword(p, "module") ||
      at_keyword(p, "trait") || at_keyword(p, "go")) {
    return parse_header_body_statement(p, err);
  }
  if (at(p, TC_K_CLASS_DEF) || at(p, TC_K_ARROW)) return parse_definition_statement(p, err);

  if (!consume_header_line(p, err)) return 0;

  /* Compiler subset shorthand: receiver.each -> NEWLINE INDENT ... */
  if (at(p, TC_K_INDENT) && peek(p, 1).kind != TC_K_DOT) {
    if (!parse_body(p, err)) return 0;
  }
  return 1;
}

static int parse_body(TcParseCheck *p, TcError *err) {
  if (!match(p, TC_K_INDENT)) {
    parse_error(p, err, "expected INDENT");
    return 0;
  }

  skip_newlines(p);
  while (!at(p, TC_K_DEDENT) && !at(p, TC_K_EOF)) {
    if (!parse_statement(p, err)) return 0;
    skip_newlines(p);
  }

  if (!match(p, TC_K_DEDENT)) {
    parse_error(p, err, "expected DEDENT");
    return 0;
  }
  return 1;
}

static int parse_program(TcParseCheck *p, TcError *err) {
  skip_newlines(p);
  while (!at(p, TC_K_EOF)) {
    if (at(p, TC_K_DEDENT)) {
      parse_error(p, err, "unexpected DEDENT");
      return 0;
    }
    if (!parse_statement(p, err)) return 0;
    skip_newlines(p);
  }
  return 1;
}

int tc_parse_check(const TcSource *source, const TcSyntaxTokens *tokens, TcError *err) {
  if (tokens->count == 0) {
    tc_error_set(err, "parse-check received no tokens");
    return 0;
  }
  TcParseCheck parser = {.source = source, .tokens = tokens, .pos = 0};
  return parse_program(&parser, err);
}
