#include "tc.h"

#include <stdlib.h>
#include <string.h>

typedef struct {
  const char *text;
  TcKind kind;
} TcWordKind;

static const TcWordKind KEYWORDS[] = {
  {"begin", TC_K_KEYWORD}, {"break", TC_K_KEYWORD}, {"case", TC_K_KEYWORD},
  {"else", TC_K_KEYWORD}, {"elsif", TC_K_KEYWORD}, {"ensure", TC_K_KEYWORD},
  {"exit", TC_K_KEYWORD}, {"extern", TC_K_KEYWORD}, {"false", TC_K_KEYWORD},
  {"fn", TC_K_KEYWORD}, {"go", TC_K_KEYWORD}, {"if", TC_K_KEYWORD},
  {"in", TC_K_KEYWORD}, {"is", TC_K_KEYWORD}, {"loop", TC_K_KEYWORD},
  {"module", TC_K_KEYWORD}, {"nil", TC_K_KEYWORD}, {"next", TC_K_KEYWORD},
  {"on", TC_K_KEYWORD}, {"parallel", TC_K_KEYWORD}, {"raise", TC_K_KEYWORD},
  {"rescue", TC_K_KEYWORD}, {"return", TC_K_KEYWORD}, {"self", TC_K_KEYWORD},
  {"super", TC_K_KEYWORD}, {"then", TC_K_KEYWORD}, {"trait", TC_K_KEYWORD},
  {"true", TC_K_KEYWORD}, {"unless", TC_K_KEYWORD}, {"until", TC_K_KEYWORD},
  {"use", TC_K_KEYWORD}, {"when", TC_K_KEYWORD}, {"while", TC_K_KEYWORD},
  {"with", TC_K_KEYWORD}, {"yield", TC_K_KEYWORD},
};

static const char *TYPES[] = {
  "bool", "int", "integer", "string", "string_buffer", "i4", "i8", "i16",
  "i32", "i64", "i128", "u4", "u8", "u16", "u32", "u64", "u128", "w64",
  "f16", "f32", "f64", "f80", "f128", "f256", "d128", "c32", "c64",
  "c128", "bigint", "bigdecimal", "bf16", "tf32", "fp8", "fp4", "nf4",
  "mxfp8", "mxfp6", "mxfp4", "mxint8", "posit8", "posit16", "posit32",
  "posit64",
};

static int token_push(TcSyntaxTokens *tokens, TcKind kind, WValue packed, TcError *err) {
  if (tokens->count == tokens->cap) {
    size_t cap = tokens->cap ? tokens->cap * 2 : 256;
    TcSyntaxToken *items = (TcSyntaxToken *)realloc(tokens->items, cap * sizeof(TcSyntaxToken));
    if (!items) {
      tc_error_set(err, "syntax token allocation failed");
      return 0;
    }
    tokens->items = items;
    tokens->cap = cap;
  }
  tokens->items[tokens->count++] = (TcSyntaxToken){.kind = kind, .packed = packed};
  return 1;
}

static int token_text_is(const TcSource *source, WValue token, const char *text) {
  return tc_token_text_eq(source, token, text);
}

static int token_text_starts_with(const TcSource *source, WValue token, const char *prefix) {
  uint32_t off = tc_token_offset(token);
  uint32_t len = tc_token_length(token);
  uint32_t start = source->byte_offsets[off];
  uint32_t end = source->byte_offsets[off + len];
  size_t prefix_len = strlen(prefix);
  return (size_t)(end - start) >= prefix_len && memcmp(source->bytes + start, prefix, prefix_len) == 0;
}

static int token_text_equals_raw(const TcSource *source, WValue token, const char *text) {
  return token_text_is(source, token, text);
}

static int token_text_in_list(const TcSource *source, WValue token, const char *const *items, size_t count) {
  for (size_t i = 0; i < count; i++) {
    if (token_text_equals_raw(source, token, items[i])) return 1;
  }
  return 0;
}

static int is_value_kind(TcKind kind) {
  switch (kind) {
    case TC_K_INT:
    case TC_K_DECIMAL:
    case TC_K_STRING:
    case TC_K_SYMBOL:
    case TC_K_NAME:
    case TC_K_ID:
    case TC_K_IVAR:
    case TC_K_CVAR:
    case TC_K_GLOBAL:
    case TC_K_RPAREN:
    case TC_K_RBRACKET:
    case TC_K_RBRACE:
    case TC_K_MAGIC_FILE:
    case TC_K_MAGIC_LINE:
    case TC_K_MAGIC_DIR:
    case TC_K_BYTE_ARRAY:
    case TC_K_CHAR:
    case TC_K_CODEPOINT:
    case TC_K_KEY:
    case TC_K_WORD_ARRAY:
    case TC_K_SYMBOL_ARRAY:
    case TC_K_PARG:
    case TC_K_COLOR:
      return 1;
    default:
      return 0;
  }
}

static TcKind classify_id(const TcSource *source, WValue token) {
  if (token_text_starts_with(source, token, "$")) return TC_K_GLOBAL;

  for (size_t i = 0; i < sizeof(KEYWORDS) / sizeof(KEYWORDS[0]); i++) {
    if (token_text_equals_raw(source, token, KEYWORDS[i].text)) return KEYWORDS[i].kind;
  }

  if (token_text_in_list(source, token, TYPES, sizeof(TYPES) / sizeof(TYPES[0]))) return TC_K_TYPE;
  return TC_K_ID;
}

static TcKind classify_magic(const TcSource *source, WValue token) {
  if (token_text_is(source, token, "__FILE__")) return TC_K_MAGIC_FILE;
  if (token_text_is(source, token, "__LINE__")) return TC_K_MAGIC_LINE;
  return TC_K_MAGIC_DIR;
}

static TcKind classify_op(const TcSource *source, WValue token, TcKind last_kind) {
  if (token_text_is(source, token, "->")) return TC_K_ARROW;
  if (token_text_starts_with(source, token, "->/")) return TC_K_LAMBDA_ARITY;
  if (token_text_is(source, token, "<<")) return is_value_kind(last_kind) ? TC_K_LSHIFT : TC_K_PUTS_OP;
  if (token_text_is(source, token, "+")) return is_value_kind(last_kind) ? TC_K_PLUS : TC_K_CLASS_DEF;

  if (token_text_is(source, token, "/") && !is_value_kind(last_kind)) {
    uint32_t off = tc_token_offset(token);
    if (off + 1 < source->cp_count && (source->lc[off + 1] & TC_F_ID_START) != 0) return TC_K_MAP;
  }

  if (token_text_is(source, token, "<-")) return TC_K_PRINT_OP;
  if (token_text_is(source, token, "<!")) return TC_K_RAISE_OP;
  if (token_text_is(source, token, "=>")) return TC_K_FAT_ARROW;
  if (token_text_is(source, token, "==")) return TC_K_EQ;
  if (token_text_is(source, token, "=~")) return TC_K_MATCH;
  if (token_text_is(source, token, "!=")) return TC_K_NEQ;
  if (token_text_is(source, token, "<=")) return TC_K_LTE;
  if (token_text_is(source, token, ">>")) return TC_K_RSHIFT;
  if (token_text_is(source, token, ">=")) return TC_K_GTE;
  if (token_text_is(source, token, "&.")) return TC_K_SAFE_NAV;
  if (token_text_is(source, token, "&&")) return TC_K_AND;
  if (token_text_is(source, token, "||=")) return TC_K_OR_ASSIGN;
  if (token_text_is(source, token, "||")) return TC_K_OR;
  if (token_text_is(source, token, "|>")) return TC_K_PIPE_FWD;
  if (token_text_is(source, token, "++")) return TC_K_PLUS_PLUS;
  if (token_text_is(source, token, "+=")) return TC_K_PLUS_EQ;
  if (token_text_is(source, token, "--")) return TC_K_MINUS_MINUS;
  if (token_text_is(source, token, "-=")) return TC_K_MINUS_EQ;
  if (token_text_is(source, token, "**")) return TC_K_POW;
  if (token_text_is(source, token, "*=")) return TC_K_STAR_EQ;
  if (token_text_is(source, token, "/=")) return TC_K_SLASH_EQ;
  if (token_text_is(source, token, "%=")) return TC_K_PERCENT_EQ;
  if (token_text_is(source, token, "-")) return TC_K_MINUS;
  if (token_text_is(source, token, "*")) return TC_K_STAR;
  if (token_text_is(source, token, "/")) return TC_K_SLASH;
  if (token_text_is(source, token, "·") || token_text_is(source, token, "⋅")) return TC_K_DOT_PRODUCT;
  if (token_text_is(source, token, "×")) return TC_K_CROSS_PRODUCT;
  if (token_text_is(source, token, "%")) return TC_K_PERCENT;
  if (token_text_is(source, token, "<")) return TC_K_LT;
  if (token_text_is(source, token, ">")) return TC_K_GT;
  if (token_text_is(source, token, "=")) return TC_K_ASSIGN;
  if (token_text_is(source, token, "!")) return TC_K_BANG;
  if (token_text_is(source, token, "...")) return TC_K_DOTDOTDOT;
  if (token_text_is(source, token, "..")) return TC_K_DOTDOT;
  if (token_text_is(source, token, ".+")) return TC_K_DOT_PLUS;
  if (token_text_is(source, token, ".-")) return TC_K_DOT_MINUS;
  if (token_text_is(source, token, ".*")) return TC_K_DOT_STAR;
  if (token_text_is(source, token, "./")) return TC_K_DOT_SLASH;
  if (token_text_is(source, token, ".|")) return TC_K_DOT_PIPE;
  if (token_text_is(source, token, ".&")) return TC_K_DOT_AMP;
  if (token_text_is(source, token, ".^")) return TC_K_DOT_CARET;
  if (token_text_is(source, token, ".<<")) return TC_K_DOT_LSHIFT;
  if (token_text_is(source, token, ".>>")) return TC_K_DOT_RSHIFT;
  if (token_text_is(source, token, ".")) return TC_K_DOT;
  if (token_text_is(source, token, ",")) return TC_K_COMMA;
  if (token_text_is(source, token, "&(")) return TC_K_BLOCK_CALL;
  if (token_text_is(source, token, "&")) return TC_K_AMPERSAND;
  if (token_text_is(source, token, "|")) return TC_K_PIPE;
  if (token_text_is(source, token, "^")) return TC_K_CARET;
  if (token_text_is(source, token, "(")) return TC_K_LPAREN;
  if (token_text_is(source, token, ")")) return TC_K_RPAREN;
  if (token_text_is(source, token, "{")) return TC_K_LBRACE;
  if (token_text_is(source, token, "}")) return TC_K_RBRACE;
  if (token_text_is(source, token, "[")) return TC_K_LBRACKET;
  if (token_text_is(source, token, "]")) return TC_K_RBRACKET;
  if (token_text_is(source, token, "?")) return TC_K_QUESTION;
  if (token_text_is(source, token, ":")) return TC_K_COLON;
  if (token_text_is(source, token, ";")) return TC_K_SEMICOLON;
  return TC_K_UNKNOWN;
}

static TcKind classify_one(const TcSource *source, WValue token, TcKind last_kind) {
  switch (tc_token_type(token)) {
    case TC_T_ID: return classify_id(source, token);
    case TC_T_NAME: return TC_K_NAME;
    case TC_T_INT: return TC_K_INT;
    case TC_T_DECIMAL: return TC_K_DECIMAL;
    case TC_T_STRING: return TC_K_STRING;
    case TC_T_SYMBOL: return TC_K_SYMBOL;
    case TC_T_TYPE_HINT: return TC_K_TYPE_HINT;
    case TC_T_NEWLINE: return TC_K_NEWLINE;
    case TC_T_INDENT: return TC_K_INDENT;
    case TC_T_DEDENT: return TC_K_DEDENT;
    case TC_T_OP: return classify_op(source, token, last_kind);
    case TC_T_IVAR: return TC_K_IVAR;
    case TC_T_CVAR: return TC_K_CVAR;
    case TC_T_PARG: return TC_K_PARG;
    case TC_T_BYTE_ARRAY: return TC_K_BYTE_ARRAY;
    case TC_T_KEY: return TC_K_KEY;
    case TC_T_COLOR: return TC_K_COLOR;
    case TC_T_CHAR: return TC_K_CHAR;
    case TC_T_CODEPOINT: return TC_K_CODEPOINT;
    case TC_T_WORD_ARRAY: return TC_K_WORD_ARRAY;
    case TC_T_SYMBOL_ARRAY: return TC_K_SYMBOL_ARRAY;
    case TC_T_MAGIC: return classify_magic(source, token);
    case TC_T_EOF: return TC_K_EOF;
    case TC_T_PATH: return TC_K_STRING;
    default: return TC_K_UNKNOWN;
  }
}

const char *tc_kind_name(TcKind kind) {
  switch (kind) {
#define TC_KIND_CASE(name) case TC_K_##name: return #name
    TC_KIND_CASE(UNKNOWN); TC_KIND_CASE(ID); TC_KIND_CASE(NAME); TC_KIND_CASE(TYPE);
    TC_KIND_CASE(KEYWORD); TC_KIND_CASE(GLOBAL); TC_KIND_CASE(INT); TC_KIND_CASE(DECIMAL);
    TC_KIND_CASE(STRING); TC_KIND_CASE(SYMBOL); TC_KIND_CASE(TYPE_HINT); TC_KIND_CASE(NEWLINE);
    TC_KIND_CASE(INDENT); TC_KIND_CASE(DEDENT); TC_KIND_CASE(IVAR); TC_KIND_CASE(CVAR);
    TC_KIND_CASE(PARG); TC_KIND_CASE(BYTE_ARRAY); TC_KIND_CASE(KEY); TC_KIND_CASE(COLOR);
    TC_KIND_CASE(CHAR); TC_KIND_CASE(CODEPOINT); TC_KIND_CASE(WORD_ARRAY); TC_KIND_CASE(SYMBOL_ARRAY);
    TC_KIND_CASE(MAGIC_FILE); TC_KIND_CASE(MAGIC_LINE); TC_KIND_CASE(MAGIC_DIR); TC_KIND_CASE(PATH);
    TC_KIND_CASE(EOF); TC_KIND_CASE(ARROW); TC_KIND_CASE(LAMBDA_ARITY); TC_KIND_CASE(LSHIFT);
    TC_KIND_CASE(PUTS_OP); TC_KIND_CASE(PLUS); TC_KIND_CASE(CLASS_DEF); TC_KIND_CASE(MAP);
    TC_KIND_CASE(PRINT_OP); TC_KIND_CASE(RAISE_OP); TC_KIND_CASE(FAT_ARROW); TC_KIND_CASE(EQ);
    TC_KIND_CASE(MATCH); TC_KIND_CASE(NEQ); TC_KIND_CASE(LTE); TC_KIND_CASE(RSHIFT);
    TC_KIND_CASE(GTE); TC_KIND_CASE(SAFE_NAV); TC_KIND_CASE(AND); TC_KIND_CASE(OR_ASSIGN);
    TC_KIND_CASE(OR); TC_KIND_CASE(PIPE_FWD); TC_KIND_CASE(PLUS_PLUS); TC_KIND_CASE(PLUS_EQ);
    TC_KIND_CASE(MINUS_MINUS); TC_KIND_CASE(MINUS_EQ); TC_KIND_CASE(POW); TC_KIND_CASE(STAR_EQ);
    TC_KIND_CASE(SLASH_EQ); TC_KIND_CASE(PERCENT_EQ); TC_KIND_CASE(MINUS); TC_KIND_CASE(STAR);
    TC_KIND_CASE(SLASH); TC_KIND_CASE(DOT_PRODUCT); TC_KIND_CASE(CROSS_PRODUCT); TC_KIND_CASE(PERCENT);
    TC_KIND_CASE(LT); TC_KIND_CASE(GT); TC_KIND_CASE(ASSIGN); TC_KIND_CASE(BANG);
    TC_KIND_CASE(DOTDOTDOT); TC_KIND_CASE(DOTDOT); TC_KIND_CASE(DOT_PLUS); TC_KIND_CASE(DOT_MINUS);
    TC_KIND_CASE(DOT_STAR); TC_KIND_CASE(DOT_SLASH); TC_KIND_CASE(DOT_PIPE); TC_KIND_CASE(DOT_AMP);
    TC_KIND_CASE(DOT_CARET); TC_KIND_CASE(DOT_LSHIFT); TC_KIND_CASE(DOT_RSHIFT); TC_KIND_CASE(DOT);
    TC_KIND_CASE(COMMA); TC_KIND_CASE(BLOCK_CALL); TC_KIND_CASE(AMPERSAND); TC_KIND_CASE(PIPE);
    TC_KIND_CASE(CARET); TC_KIND_CASE(LPAREN); TC_KIND_CASE(RPAREN); TC_KIND_CASE(LBRACE);
    TC_KIND_CASE(RBRACE); TC_KIND_CASE(LBRACKET); TC_KIND_CASE(RBRACKET); TC_KIND_CASE(QUESTION);
    TC_KIND_CASE(COLON); TC_KIND_CASE(SEMICOLON);
#undef TC_KIND_CASE
  }
  return "UNKNOWN";
}

int tc_syntax_tokens_build(const TcSource *source, const TcTokens *tokens, TcSyntaxTokens *out, TcError *err) {
  memset(out, 0, sizeof(*out));
  TcKind last_kind = TC_K_UNKNOWN;

  for (size_t i = 0; i < tokens->count; i++) {
    WValue packed = tokens->items[i];
    TcKind kind = classify_one(source, packed, last_kind);
    if (!token_push(out, kind, packed, err)) return 0;
    last_kind = kind;
  }

  return 1;
}

void tc_syntax_tokens_free(TcSyntaxTokens *tokens) {
  if (!tokens) return;
  free(tokens->items);
  memset(tokens, 0, sizeof(*tokens));
}

void tc_dump_syntax_tokens(const TcSource *source, const TcSyntaxTokens *tokens) {
  for (size_t i = 0; i < tokens->count; i++) {
    WValue token = tokens->items[i].packed;
    uint32_t off = tc_token_offset(token);
    uint32_t len = tc_token_length(token);
    uint32_t start = source->byte_offsets[off];
    uint32_t end = source->byte_offsets[off + len];
    printf("%4zu %-14s off=%u len=%u text=\"%.*s\"\n", i, tc_kind_name(tokens->items[i].kind), off, len,
           (int)(end - start), source->bytes + start);
  }
}
