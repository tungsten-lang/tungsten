#include "tc.h"

#include <errno.h>
#include <limits.h>
#include <stdlib.h>
#include <string.h>

static WValue current(TcParser *p) {
  return p->tokens->items[p->pos];
}

static WValue peek(TcParser *p, size_t ahead) {
  size_t pos = p->pos + ahead;
  if (pos >= p->tokens->count) return p->tokens->items[p->tokens->count - 1];
  return p->tokens->items[pos];
}

static int match_type(TcParser *p, int type) {
  if (tc_token_type(current(p)) != type) return 0;
  p->pos++;
  return 1;
}

static int match_op(TcParser *p, const char *text) {
  WValue token = current(p);
  if (tc_token_type(token) != TC_T_OP || !tc_token_text_eq(p->source, token, text)) return 0;
  p->pos++;
  return 1;
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

static void parse_error(TcParser *p, TcError *err, const char *message) {
  tc_error_set(err, "syntax error on line %d: %s", token_line(p->source, current(p)), message);
}

static int parse_expression(TcParser *p, int min_prec, TcError *err);

static int emit_const(TcParser *p, TcValue value, TcError *err) {
  int id = tc_chunk_add_const(p->chunk, value, err);
  if (id < 0) return 0;
  return tc_emit_op_u32(p->chunk, TC_OP_CONST, (uint32_t)id, err);
}

static int parse_int_token(const TcSource *source, WValue token, int64_t *out, TcError *err) {
  char *text = NULL;
  size_t len = 0;
  if (!tc_token_text_copy(source, token, &text, &len, err)) return 0;

  char *compact = (char *)malloc(len + 1);
  if (!compact) {
    free(text);
    tc_error_set(err, "integer allocation failed");
    return 0;
  }
  size_t j = 0;
  for (size_t i = 0; i < len; i++) {
    if (text[i] != '_') compact[j++] = text[i];
  }
  compact[j] = '\0';

  int base = 10;
  const char *start = compact;
  if (compact[0] == '0' && (compact[1] == 'x' || compact[1] == 'X')) base = 16;
  else if (compact[0] == '0' && (compact[1] == 'b' || compact[1] == 'B')) {
    base = 2;
    start = compact + 2;
  } else if (compact[0] == '0' && (compact[1] == 'o' || compact[1] == 'O')) {
    base = 8;
    start = compact + 2;
  }

  errno = 0;
  char *end = NULL;
  long long value = strtoll(start, &end, base);
  if (errno != 0 || end == start || *end != '\0' || value > W_INT48_MAX || value < W_INT48_MIN) {
    tc_error_set(err, "invalid integer literal");
    free(compact);
    free(text);
    return 0;
  }

  *out = (int64_t)value;
  free(compact);
  free(text);
  return 1;
}

static int parse_string_token(const TcSource *source, WValue token, TcValue *out, TcError *err) {
  char *text = NULL;
  size_t len = 0;
  if (!tc_token_text_copy(source, token, &text, &len, err)) return 0;
  size_t skip = 0;
  if (len >= 2) { skip = 1; len -= 2; }
  // Re-allocate into a TcHeapString so the bytes have a recoverable header
  // post-flip. The token-text malloc was a transient — drop it after copy.
  char *heap = tc_heap_string_alloc(len, 0, err);
  if (!heap) {
    free(text);
    return 0;
  }
  memcpy(heap, text + skip, len);
  free(text);
  *out = tc_box_string_bytes(heap, len, 0);
  return 1;
}

static int primary(TcParser *p, TcError *err) {
  WValue token = current(p);
  int type = tc_token_type(token);

  if (type == TC_T_INT) {
    p->pos++;
    int64_t value = 0;
    if (!parse_int_token(p->source, token, &value, err)) return 0;
    return emit_const(p, tc_box_wvalue(w_box_int(value)), err);
  }

  if (type == TC_T_STRING) {
    p->pos++;
    TcValue value;
    if (!parse_string_token(p->source, token, &value, err)) return 0;
    return emit_const(p, value, err);
  }

  if (type == TC_T_ID || type == TC_T_NAME) {
    p->pos++;
    char *name = NULL;
    size_t len = 0;
    if (!tc_token_text_copy(p->source, token, &name, &len, err)) return 0;
    int slot = tc_chunk_local(p->chunk, name, len, err);
    free(name);
    if (slot < 0) return 0;
    return tc_emit_op_u32(p->chunk, TC_OP_LOAD_LOCAL, (uint32_t)slot, err);
  }

  if (match_op(p, "(")) {
    if (!parse_expression(p, 0, err)) return 0;
    if (!match_op(p, ")")) {
      parse_error(p, err, "expected ')'");
      return 0;
    }
    return 1;
  }

  if (match_op(p, "-")) {
    if (!emit_const(p, tc_box_wvalue(w_box_int(0)), err)) return 0;
    if (!primary(p, err)) return 0;
    return tc_emit_op(p->chunk, TC_OP_SUB, err);
  }

  parse_error(p, err, "expected expression");
  return 0;
}

static int op_prec(const TcSource *source, WValue token, uint8_t *op_out) {
  if (tc_token_type(token) != TC_T_OP) return -1;
  if (tc_token_text_eq(source, token, "*")) {
    *op_out = TC_OP_MUL;
    return 4;
  }
  if (tc_token_text_eq(source, token, "/")) {
    *op_out = TC_OP_DIV;
    return 4;
  }
  if (tc_token_text_eq(source, token, "+")) {
    *op_out = TC_OP_ADD;
    return 3;
  }
  if (tc_token_text_eq(source, token, "-")) {
    *op_out = TC_OP_SUB;
    return 3;
  }
  if (tc_token_text_eq(source, token, "<")) {
    *op_out = TC_OP_LT;
    return 2;
  }
  if (tc_token_text_eq(source, token, "<=")) {
    *op_out = TC_OP_LTE;
    return 2;
  }
  if (tc_token_text_eq(source, token, ">")) {
    *op_out = TC_OP_GT;
    return 2;
  }
  if (tc_token_text_eq(source, token, ">=")) {
    *op_out = TC_OP_GTE;
    return 2;
  }
  if (tc_token_text_eq(source, token, "==")) {
    *op_out = TC_OP_EQ;
    return 1;
  }
  if (tc_token_text_eq(source, token, "!=")) {
    *op_out = TC_OP_NEQ;
    return 1;
  }
  return -1;
}

static int parse_expression(TcParser *p, int min_prec, TcError *err) {
  if (!primary(p, err)) return 0;

  for (;;) {
    uint8_t op = 0;
    int prec = op_prec(p->source, current(p), &op);
    if (prec < min_prec) break;
    p->pos++;
    if (!parse_expression(p, prec + 1, err)) return 0;
    if (!tc_emit_op(p->chunk, op, err)) return 0;
  }

  return 1;
}

static int parse_statement(TcParser *p, TcError *err) {
  WValue token = current(p);
  if (tc_token_type(token) == TC_T_ID && tc_token_text_eq(p->source, token, "puts")) {
    p->pos++;
    if (!parse_expression(p, 0, err)) return 0;
    return tc_emit_op(p->chunk, TC_OP_PRINT, err);
  }

  if ((tc_token_type(token) == TC_T_ID || tc_token_type(token) == TC_T_NAME) &&
      tc_token_type(peek(p, 1)) == TC_T_OP && tc_token_text_eq(p->source, peek(p, 1), "=")) {
    p->pos += 2;
    char *name = NULL;
    size_t len = 0;
    if (!tc_token_text_copy(p->source, token, &name, &len, err)) return 0;
    int slot = tc_chunk_local(p->chunk, name, len, err);
    free(name);
    if (slot < 0) return 0;
    if (!parse_expression(p, 0, err)) return 0;
    return tc_emit_op_u32(p->chunk, TC_OP_STORE_LOCAL, (uint32_t)slot, err);
  }

  return parse_expression(p, 0, err);
}

int tc_compile(const TcSource *source, const TcTokens *tokens, TcChunk *chunk, TcError *err) {
  TcParser parser = {.source = source, .tokens = tokens, .pos = 0, .chunk = chunk};

  while (match_type(&parser, TC_T_NEWLINE)) {}
  while (tc_token_type(current(&parser)) != TC_T_EOF) {
    if (!parse_statement(&parser, err)) return 0;
    if (!tc_emit_op(chunk, TC_OP_POP, err)) return 0;

    if (tc_token_type(current(&parser)) == TC_T_EOF) break;
    if (!(match_type(&parser, TC_T_NEWLINE) || match_op(&parser, ";"))) {
      uint8_t op = 0;
      if (op_prec(source, current(&parser), &op) >= 0) {
        parse_error(&parser, err, "operator without right-hand expression");
      } else {
        parse_error(&parser, err, "unexpected token after statement");
      }
      return 0;
    }
    while (match_type(&parser, TC_T_NEWLINE) || match_op(&parser, ";")) {}
  }

  int nil_id = tc_chunk_add_const(chunk, tc_box_nil(), err);
  if (nil_id < 0) return 0;
  return tc_emit_op_u32(chunk, TC_OP_CONST, (uint32_t)nil_id, err) &&
         tc_emit_op(chunk, TC_OP_RETURN, err);
}
