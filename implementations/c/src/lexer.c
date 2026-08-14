#include "tc.h"

#include <ctype.h>
#include <stdlib.h>
#include <string.h>

#include "unit_mixed_case_names.inc"

static const uint64_t TC_LEX64_TAG = 0xFFFC000000000000ULL | (1ULL << 46);
static const uint32_t TC_CP_MASK = 0x1FFFFFu;

static uint32_t decode_utf8(const unsigned char *src, size_t n, size_t *i) {
  unsigned char b0 = src[*i];
  if (b0 < 0x80) {
    (*i)++;
    return b0;
  }
  if ((b0 & 0xE0) == 0xC0 && *i + 1 < n) {
    uint32_t cp = ((uint32_t)(b0 & 0x1F) << 6) | (uint32_t)(src[*i + 1] & 0x3F);
    *i += 2;
    return cp;
  }
  if ((b0 & 0xF0) == 0xE0 && *i + 2 < n) {
    uint32_t cp = ((uint32_t)(b0 & 0x0F) << 12) |
                  ((uint32_t)(src[*i + 1] & 0x3F) << 6) |
                  (uint32_t)(src[*i + 2] & 0x3F);
    *i += 3;
    return cp;
  }
  if ((b0 & 0xF8) == 0xF0 && *i + 3 < n) {
    uint32_t cp = ((uint32_t)(b0 & 0x07) << 18) |
                  ((uint32_t)(src[*i + 1] & 0x3F) << 12) |
                  ((uint32_t)(src[*i + 2] & 0x3F) << 6) |
                  (uint32_t)(src[*i + 3] & 0x3F);
    *i += 4;
    return cp;
  }
  (*i)++;
  return b0;
}

static int token_push(TcTokens *tokens, WValue token, TcError *err) {
  if (tokens->count == tokens->cap) {
    size_t cap = tokens->cap ? tokens->cap * 2 : 256;
    WValue *items = (WValue *)realloc(tokens->items, cap * sizeof(WValue));
    if (!items) {
      tc_error_set(err, "token allocation failed");
      return 0;
    }
    tokens->items = items;
    tokens->cap = cap;
  }
  tokens->items[tokens->count++] = token;
  return 1;
}

static inline uint32_t cp_at(const TcSource *source, size_t pos) {
  return (uint32_t)((source->lc[pos] >> 18) & TC_CP_MASK);
}

static inline WValue token_new(int type, size_t start, size_t end, int flags) {
  return w_box_token(flags, type, (int)(end - start), (int)start);
}

static inline int is_space_cp(uint32_t c) {
  return c == ' ' || c == '\t';
}

static inline int is_newline_cp(uint32_t c) {
  return c == '\n' || c == '\r';
}

static size_t color_literal_end(const TcSource *source, size_t start, size_t count) {
  if (start >= count || cp_at(source, start) != '#') return start;
  size_t pos = start + 1;
  while (pos < count && (source->lc[pos] & TC_F_HEX) != 0) pos++;
  size_t digits = pos - start - 1;
  if (!(digits == 3 || digits == 4 || digits == 6 || digits == 8)) return start;
  if (pos < count && (source->lc[pos] & TC_F_ID_CONTINUE) != 0) return start;
  return pos;
}

static int ascii_digit_at(const TcSource *source, size_t pos, size_t count) {
  return pos < count && cp_at(source, pos) >= '0' && cp_at(source, pos) <= '9';
}

static size_t temporal_literal_end(const TcSource *source, size_t start, size_t count) {
  /* The compact lexer has no dedicated temporal token IDs. Keep the complete
   * spelling in one DECIMAL carrier token; atom_node_ast recovers its kind. */
  if (start + 20 <= count &&
      ascii_digit_at(source, start + 0, count) && ascii_digit_at(source, start + 1, count) &&
      ascii_digit_at(source, start + 2, count) && ascii_digit_at(source, start + 3, count) &&
      cp_at(source, start + 4) == '-' &&
      ascii_digit_at(source, start + 5, count) && ascii_digit_at(source, start + 6, count) &&
      cp_at(source, start + 7) == '-' &&
      ascii_digit_at(source, start + 8, count) && ascii_digit_at(source, start + 9, count) &&
      cp_at(source, start + 10) == 'T' &&
      ascii_digit_at(source, start + 11, count) && ascii_digit_at(source, start + 12, count) &&
      cp_at(source, start + 13) == ':' &&
      ascii_digit_at(source, start + 14, count) && ascii_digit_at(source, start + 15, count) &&
      cp_at(source, start + 16) == ':' &&
      ascii_digit_at(source, start + 17, count) && ascii_digit_at(source, start + 18, count) &&
      cp_at(source, start + 19) == 'Z') {
    return start + 20;
  }
  if (start + 10 <= count &&
      ascii_digit_at(source, start + 0, count) && ascii_digit_at(source, start + 1, count) &&
      ascii_digit_at(source, start + 2, count) && ascii_digit_at(source, start + 3, count) &&
      cp_at(source, start + 4) == '-' &&
      ascii_digit_at(source, start + 5, count) && ascii_digit_at(source, start + 6, count) &&
      cp_at(source, start + 7) == '-' &&
      ascii_digit_at(source, start + 8, count) && ascii_digit_at(source, start + 9, count)) {
    return start + 10;
  }
  if (start + 8 <= count &&
      ascii_digit_at(source, start + 0, count) && ascii_digit_at(source, start + 1, count) &&
      cp_at(source, start + 2) == ':' &&
      ascii_digit_at(source, start + 3, count) && ascii_digit_at(source, start + 4, count) &&
      cp_at(source, start + 5) == ':' &&
      ascii_digit_at(source, start + 6, count) && ascii_digit_at(source, start + 7, count)) {
    return start + 8;
  }
  return start;
}

static int token_is_at_statement_start(const TcSource *source, size_t start) {
  size_t scan = start;
  while (scan > 0) {
    uint32_t c = cp_at(source, scan - 1);
    if (is_space_cp(c)) {
      scan--;
      continue;
    }
    return is_newline_cp(c) || c == ';';
  }
  return 1;
}

static int id_text_is_use(const TcSource *source, size_t start, size_t end) {
  return end - start == 3 &&
         cp_at(source, start) == 'u' &&
         cp_at(source, start + 1) == 's' &&
         cp_at(source, start + 2) == 'e';
}

static int id_continue_or_upper(const TcSource *source, size_t pos) {
  uint32_t c = cp_at(source, pos);
  return (source->lc[pos] & TC_F_ID_CONTINUE) != 0 || (c >= 'A' && c <= 'Z');
}

static int span_is_mixed_case_unit(const TcSource *source, size_t start, size_t end) {
  const unsigned char *bytes = source->bytes + source->byte_offsets[start];
  size_t len = (size_t)(source->byte_offsets[end] - source->byte_offsets[start]);
  size_t lo = 0;
  size_t hi = sizeof(tc_mixed_case_unit_names) / sizeof(tc_mixed_case_unit_names[0]);

  while (lo < hi) {
    size_t mid = lo + (hi - lo) / 2;
    const char *candidate = tc_mixed_case_unit_names[mid];
    size_t candidate_len = strlen(candidate);
    size_t common = len < candidate_len ? len : candidate_len;
    int cmp = memcmp(bytes, candidate, common);
    if (cmp == 0) {
      if (len < candidate_len) cmp = -1;
      else if (len > candidate_len) cmp = 1;
      else return 1;
    }
    if (cmp < 0) hi = mid;
    else lo = mid + 1;
  }
  return 0;
}

static int reject_mixed_case_tail(const TcSource *source, size_t start, size_t pos,
                                  size_t count, int allow_unit, TcError *err) {
  if (pos >= count || cp_at(source, pos) < 'A' || cp_at(source, pos) > 'Z') return 1;

  size_t spelling_end = pos + 1;
  while (spelling_end < count && id_continue_or_upper(source, spelling_end)) spelling_end++;
  if (allow_unit && span_is_mixed_case_unit(source, start, spelling_end)) return 1;

  uint32_t byte_start = source->byte_offsets[start];
  uint32_t byte_end = source->byte_offsets[spelling_end];
  tc_error_set(err,
               "uppercase ASCII is not valid in identifiers: '%.*s' — use snake_case",
               (int)(byte_end - byte_start), source->bytes + byte_start);
  return 0;
}

static int operator_second(uint32_t c, uint32_t c2, uint32_t c3, int have_c3) {
  switch (c) {
    case '-': return c2 == '>' || c2 == '-' || c2 == '=';
    case '<': return c2 == '<' || c2 == '-' || c2 == '!' || c2 == '=';
    case '=': return c2 == '>' || c2 == '=' || c2 == '~';
    case '!': return c2 == '=';
    case '>': return c2 == '>' || c2 == '=';
    case '&': return c2 == '.' || c2 == '&' || c2 == '(' || c2 == '=';
    case '|': return c2 == '|' || c2 == '>' || c2 == '=' || (c2 == '|' && have_c3 && c3 == '=');
    case '^': return c2 == '=';
    case '+': return c2 == '+' || c2 == '=';
    case '*': return c2 == '=' || c2 == '*';
    case '/': return c2 == '=';
    case '%': return c2 == '=';
    case '.': return c2 == '.';
    default: return 0;
  }
}

static void apply_adjacency_flags(const TcSource *source, TcTokens *tokens) {
  /* Set only the f_line_start flag (bit 0). The old sp_before / sp_after
   * flags were dropped when the SIMD lexer started emitting explicit :SP
   * tokens — and stamping anything into bits 1+ would corrupt the offset
   * field which now starts at bit 2. */
  (void)source;
  for (size_t i = 0; i < tokens->count; i++) {
    WValue tok = tokens->items[i];
    int type_id = tc_token_type(tok);
    if (type_id == TC_T_NEWLINE || type_id == TC_T_INDENT || type_id == TC_T_DEDENT || type_id == TC_T_EOF) {
      continue;
    }

    uint32_t off = tc_token_offset(tok);
    int flags = 0;

    size_t scan = off;
    while (scan > 0) {
      uint32_t c = cp_at(source, scan - 1);
      if (is_space_cp(c)) {
        scan--;
        continue;
      }
      if (is_newline_cp(c)) flags |= 0x1;
      break;
    }
    if (scan == 0) flags |= 0x1;

    tokens->items[i] = tok | (WValue)flags;
  }
}

int tc_source_build(TcSource *source, unsigned char *bytes, size_t len, const unsigned char *flags,
                    size_t flags_len, TcError *err) {
  memset(source, 0, sizeof(*source));
  source->bytes = bytes;
  source->byte_len = len;

  uint64_t *lc = (uint64_t *)malloc((len + 1) * sizeof(uint64_t));
  uint32_t *byte_offsets = (uint32_t *)malloc((len + 1) * sizeof(uint32_t));
  uint32_t *byte_lines = (uint32_t *)malloc((len + 1) * sizeof(uint32_t));
  if (!lc || !byte_offsets || !byte_lines) {
    free(lc);
    free(byte_offsets);
    free(byte_lines);
    tc_error_set(err, "source allocation failed");
    return 0;
  }

  // Build byte → line table in a single pass over the source. Used by
  // token_line_ast in the parse hot path; replaces a per-token O(N)
  // newline count that made parsing quadratic in source size.
  uint32_t line = 1;
  for (size_t b = 0; b < len; b++) {
    byte_lines[b] = line;
    if (bytes[b] == '\n') line++;
  }
  byte_lines[len] = line;

  size_t i = 0;
  size_t count = 0;
  // Per-codepoint column table — the mirror of compiler/lib/lexer.w:
  // build_line_index's @col_at (1-based; resets after '\n'; +1 per
  // codepoint otherwise). Sized like lc: one entry per codepoint plus a
  // trailing entry for the end-of-file position.
  uint32_t *cp_cols = (uint32_t *)malloc((len + 1) * sizeof(uint32_t));
  if (!cp_cols) {
    free(lc);
    free(byte_offsets);
    free(byte_lines);
    tc_error_set(err, "source allocation failed");
    return 0;
  }
  uint32_t col = 1;
  while (i < len) {
    size_t byte_start = i;
    uint32_t cp = decode_utf8(bytes, len, &i);
    unsigned char f = cp < flags_len ? flags[cp] : 0;
    lc[count] = TC_LEX64_TAG | ((uint64_t)cp << 18) | (uint64_t)f;
    byte_offsets[count] = (uint32_t)byte_start;
    cp_cols[count] = col;
    if (cp == '\n') col = 1;
    else col++;
    count++;
  }

  lc[count] = 0;
  byte_offsets[count] = (uint32_t)len;
  cp_cols[count] = col;
  source->lc = lc;
  source->byte_offsets = byte_offsets;
  source->byte_lines = byte_lines;
  source->cp_cols = cp_cols;
  source->cp_count = count;
  return 1;
}

void tc_source_free(TcSource *source) {
  if (!source) return;
  free(source->bytes);
  free(source->lc);
  free(source->byte_offsets);
  free(source->byte_lines);
  free(source->cp_cols);
  memset(source, 0, sizeof(*source));
}

int tc_lex_source(const TcSource *source, TcTokens *tokens, TcError *err) {
  memset(tokens, 0, sizeof(*tokens));
  size_t pos = 0;
  size_t count = source->cp_count;
  int at_line_start = 1;
  int paren_depth = 0;
  int indents[1024];
  size_t indent_top = 0;
  indents[0] = 0;

  while (pos < count) {
    if (at_line_start) {
      at_line_start = 0;
      int indent = 0;
      while (pos < count && is_space_cp(cp_at(source, pos))) {
        indent++;
        pos++;
      }

      if (pos >= count) break;

      uint32_t c0 = cp_at(source, pos);
      if (is_newline_cp(c0)) {
        pos++;
        if (c0 == '\r' && pos < count && cp_at(source, pos) == '\n') pos++;
        at_line_start = 1;
        continue;
      }

      if (c0 == '#' && pos + 1 < count && cp_at(source, pos + 1) == '!') {
        while (pos < count && !is_newline_cp(cp_at(source, pos))) pos++;
        if (pos < count) {
          uint32_t c2 = cp_at(source, pos++);
          if (c2 == '\r' && pos < count && cp_at(source, pos) == '\n') pos++;
        }
        at_line_start = 1;
        continue;
      }

      if (c0 == '#' && color_literal_end(source, pos, count) == pos &&
          !(pos + 1 < count && cp_at(source, pos + 1) == '#')) {
        while (pos < count && !is_newline_cp(cp_at(source, pos))) pos++;
        if (pos < count) {
          uint32_t c2 = cp_at(source, pos++);
          if (c2 == '\r' && pos < count && cp_at(source, pos) == '\n') pos++;
        }
        at_line_start = 1;
        continue;
      }

      if (paren_depth == 0) {
        int current_indent = indents[indent_top];
        if (indent > current_indent) {
          if (indent_top + 1 >= sizeof(indents) / sizeof(indents[0])) {
            tc_error_set(err, "indent stack overflow");
            return 0;
          }
          indents[++indent_top] = indent;
          if (!token_push(tokens, token_new(TC_T_INDENT, pos, pos, 0), err)) return 0;
        } else if (indent < current_indent) {
          while (indent_top > 0 && indents[indent_top] > indent) {
            indent_top--;
            if (!token_push(tokens, token_new(TC_T_DEDENT, pos, pos, 0), err)) return 0;
          }
        }
      }
    }

    uint64_t v = source->lc[pos];
    uint32_t c = (uint32_t)((v >> 18) & TC_CP_MASK);
    int f = (int)(v & 0xFF);

    if ((f & TC_F_WHITESPACE) && c != '\n' && c != '\r') {
      pos++;
      while (pos < count) {
        uint32_t c2 = cp_at(source, pos);
        int f2 = (int)(source->lc[pos] & 0xFF);
        if ((f2 & TC_F_WHITESPACE) && c2 != '\n' && c2 != '\r') pos++;
        else break;
      }
      continue;
    }

    if (c == '\n' || c == '\r' || (f & TC_F_NEWLINE)) {
      size_t start = pos++;
      if (c == '\r' && pos < count && cp_at(source, pos) == '\n') pos++;
      if (paren_depth == 0 && !token_push(tokens, token_new(TC_T_NEWLINE, start, pos, 0), err)) return 0;
      at_line_start = 1;
      continue;
    }

    if (c == '#') {
      size_t color_end = color_literal_end(source, pos, count);
      if (color_end > pos) {
        size_t start = pos;
        pos = color_end;
        if (!token_push(tokens, token_new(TC_T_COLOR, start, pos, 0), err)) return 0;
        continue;
      }
      if (pos + 1 < count && cp_at(source, pos + 1) == '#') {
        pos += 2;
        while (pos < count && is_space_cp(cp_at(source, pos))) pos++;
        size_t start = pos;
        int type_bracket_depth = 0;
        while (pos < count && !is_newline_cp(cp_at(source, pos))) {
          uint32_t c2 = cp_at(source, pos);
          if (c2 == '[') {
            type_bracket_depth++;
          } else if (c2 == ']') {
            if (type_bracket_depth == 0 && paren_depth > 0) break;
            type_bracket_depth--;
          } else if (c2 == '=') {
            /* `x ## i64 = 0` is a typed assignment: the hint ends at `=`
             * (any depth) so the initializer lexes normally. Mirrors the
             * self-hosted lexer's rule. */
            break;
          } else if (paren_depth > 0 &&
                     (c2 == ')' || c2 == ',' || c2 == ';' || c2 == ':' || c2 == '?')) {
            break;
          }
          pos++;
        }
        if (!token_push(tokens, token_new(TC_T_TYPE_HINT, start, pos, 0), err)) return 0;
        continue;
      }

      while (pos < count) {
        uint32_t c2 = cp_at(source, pos);
        if (c2 == '\n' || c2 == '\r') break;
        pos++;
      }
      continue;
    }

    if (f & TC_F_ID_START) {
      size_t start = pos++;

      if (c == '_' && pos < count && cp_at(source, pos) == '_') {
        if (start + 7 < count &&
            cp_at(source, start + 2) == 'F' && cp_at(source, start + 3) == 'I' &&
            cp_at(source, start + 4) == 'L' && cp_at(source, start + 5) == 'E' &&
            cp_at(source, start + 6) == '_' && cp_at(source, start + 7) == '_') {
          pos = start + 8;
          if (!token_push(tokens, token_new(TC_T_MAGIC, start, pos, 0), err)) return 0;
          continue;
        }
        if (start + 7 < count &&
            cp_at(source, start + 2) == 'L' && cp_at(source, start + 3) == 'I' &&
            cp_at(source, start + 4) == 'N' && cp_at(source, start + 5) == 'E' &&
            cp_at(source, start + 6) == '_' && cp_at(source, start + 7) == '_') {
          pos = start + 8;
          if (!token_push(tokens, token_new(TC_T_MAGIC, start, pos, 0), err)) return 0;
          continue;
        }
        if (start + 6 < count &&
            cp_at(source, start + 2) == 'D' && cp_at(source, start + 3) == 'I' &&
            cp_at(source, start + 4) == 'R' && cp_at(source, start + 5) == '_' &&
            cp_at(source, start + 6) == '_') {
          pos = start + 7;
          if (!token_push(tokens, token_new(TC_T_MAGIC, start, pos, 0), err)) return 0;
          continue;
        }
      }

      while (pos < count && ((source->lc[pos] & TC_F_ID_CONTINUE) != 0)) pos++;
      if ((c == '_' || (c >= 'a' && c <= 'z')) &&
          !reject_mixed_case_tail(source, start, pos, count, 1, err)) return 0;
      if (pos < count) {
        uint32_t c2 = cp_at(source, pos);
        if (c2 == '?' || c2 == '!') pos++;
      }
      if (pos < count && cp_at(source, pos) == '/') {
        if (pos + 1 < count) {
          uint32_t c2 = cp_at(source, pos + 1);
          if (c2 == '*' || c2 == '&') {
            pos += 2;
          } else if ((source->lc[pos + 1] & TC_F_DIGIT) != 0) {
            pos += 1;
            while (pos < count && (source->lc[pos] & TC_F_DIGIT) != 0) pos++;
          }
        }
      }
      int type = (c >= 'A' && c <= 'Z') ? TC_T_NAME : TC_T_ID;
      if (!token_push(tokens, token_new(type, start, pos, 0), err)) return 0;

      if (id_text_is_use(source, start, pos) && token_is_at_statement_start(source, start)) {
        while (pos < count && is_space_cp(cp_at(source, pos))) pos++;
        if (pos < count && cp_at(source, pos) != '"') {
          size_t path_start = pos;
          while (pos < count) {
            uint32_t c2 = cp_at(source, pos);
            if (is_space_cp(c2) || is_newline_cp(c2) || c2 == ';' || c2 == '#') break;
            pos++;
          }
          if (pos > path_start && !token_push(tokens, token_new(TC_T_PATH, path_start, pos, 0), err)) return 0;
        }
      }
      continue;
    }

    if (f & TC_F_DIGIT) {
      size_t start = pos;
      int is_decimal = 0;
      size_t temporal_end = temporal_literal_end(source, start, count);
      if (temporal_end > start) {
        pos = temporal_end;
        if (!token_push(tokens, token_new(TC_T_DECIMAL, start, pos, 0), err)) return 0;
        continue;
      }
      size_t rational_scan = start;
      while (rational_scan < count &&
             ((source->lc[rational_scan] & TC_F_DIGIT) != 0 || cp_at(source, rational_scan) == '_')) {
        rational_scan++;
      }
      if (rational_scan + 1 < count && cp_at(source, rational_scan) == '/' &&
          (source->lc[rational_scan + 1] & TC_F_DIGIT) != 0) {
        rational_scan += 2;
        while (rational_scan < count &&
               ((source->lc[rational_scan] & TC_F_DIGIT) != 0 || cp_at(source, rational_scan) == '_')) {
          rational_scan++;
        }
        pos = rational_scan;
        if (!token_push(tokens, token_new(TC_T_DECIMAL, start, pos, 0), err)) return 0;
        continue;
      }
      if (c == '0' && pos + 1 < count) {
        uint32_t c2 = cp_at(source, pos + 1);
        if (c2 == 'x' || c2 == 'X') {
          pos += 2;
          while (pos < count && (((source->lc[pos] & TC_F_HEX) != 0) || cp_at(source, pos) == '_')) pos++;
          if (!token_push(tokens, token_new(TC_T_INT, start, pos, 0), err)) return 0;
          continue;
        }
        if (c2 == 'b' || c2 == 'B') {
          pos += 2;
          while (pos < count) {
            c2 = cp_at(source, pos);
            if (c2 == '0' || c2 == '1' || c2 == '_') pos++;
            else break;
          }
          if (!token_push(tokens, token_new(TC_T_INT, start, pos, 0), err)) return 0;
          continue;
        }
        if (c2 == 'o' || c2 == 'O') {
          pos += 2;
          while (pos < count) {
            c2 = cp_at(source, pos);
            if ((c2 >= '0' && c2 <= '7') || c2 == '_') pos++;
            else break;
          }
          if (!token_push(tokens, token_new(TC_T_INT, start, pos, 0), err)) return 0;
          continue;
        }
      }

      pos++;
      while (pos < count && (((source->lc[pos] & TC_F_DIGIT) != 0) || cp_at(source, pos) == '_')) pos++;
      if (pos + 1 < count && cp_at(source, pos) == '.' && (source->lc[pos + 1] & TC_F_DIGIT) != 0) {
        is_decimal = 1;
        pos += 2;
        while (pos < count && (((source->lc[pos] & TC_F_DIGIT) != 0) || cp_at(source, pos) == '_')) pos++;
      }
      if (pos < count) {
        uint32_t c2 = cp_at(source, pos);
        if (c2 == 'e' || c2 == 'E') {
          size_t exp = pos + 1;
          if (exp < count && (cp_at(source, exp) == '+' || cp_at(source, exp) == '-')) exp++;
          if (exp < count && (source->lc[exp] & TC_F_DIGIT) != 0) {
            is_decimal = 1;
            pos = exp + 1;
            while (pos < count && (source->lc[pos] & TC_F_DIGIT) != 0) pos++;
          }
        }
      }
      if (pos < count && cp_at(source, pos) == '%') {
        is_decimal = 1;
        pos++;
      } else if (pos < count && id_continue_or_upper(source, pos)) {
        is_decimal = 1;
        pos++;
        while (pos < count && (id_continue_or_upper(source, pos) || (source->lc[pos] & TC_F_DIGIT) != 0 ||
                               cp_at(source, pos) == '/')) {
          pos++;
        }
      }
      if (!token_push(tokens, token_new(is_decimal ? TC_T_DECIMAL : TC_T_INT, start, pos, 0), err)) return 0;
      continue;
    }

    if (c == '"') {
      // Mirror compiler/lib/lexer.w:tungsten_tokenize_fast64's double-quote
      // span rules exactly (the canonical tokenize path; scan_string only
      // re-derives the VALUE from this span at materialize time):
      //   \e[  → consumed as a unit (ANSI CSI prefix — the `[` can never
      //          open interpolation),
      //   \x   → generic two-char escape skip,
      //   [    → with a following char that isn't `]`: quote-blind,
      //          newline-blind bracket-depth scan to the matching `]`.
      //          A `"` inside that scan does NOT end the string, so e.g.
      //          `x = "table[" … y = "]…"` spans both lines as ONE token.
      //   "    → end of string.
      size_t start = pos++;
      while (pos < count) {
        uint32_t c2 = cp_at(source, pos);
        if (c2 == '\\') {
          if (pos + 2 < count && cp_at(source, pos + 1) == 'e' &&
              cp_at(source, pos + 2) == '[') {
            pos += 3;
          } else {
            pos += 2;
          }
          continue;
        }
        if (c2 == '"') {
          pos++;
          break;
        }
        if (c2 == '[' && pos + 1 < count && cp_at(source, pos + 1) != ']') {
          pos++;
          int depth = 1;
          while (pos < count && depth > 0) {
            uint32_t ic = cp_at(source, pos);
            if (ic == '[') depth++;
            else if (ic == ']') depth--;
            pos++;
          }
          continue;
        }
        pos++;
      }
      if (!token_push(tokens, token_new(TC_T_STRING, start, pos, 0), err)) return 0;
      continue;
    }

    if (c == '\'') {
      size_t start = pos++;
      while (pos < count) {
        uint32_t c2 = cp_at(source, pos);
        pos++;
        if (c2 == '\\' && pos < count) {
          pos++;
          continue;
        }
        if (c2 == '\'') break;
      }
      if (!token_push(tokens, token_new(TC_T_STRING, start, pos, 0), err)) return 0;
      continue;
    }

    if (c == ':') {
      size_t start = pos;
      if (pos + 2 < count && cp_at(source, pos + 1) == '-' && !is_space_cp(cp_at(source, pos + 2)) &&
          !is_newline_cp(cp_at(source, pos + 2))) {
        pos += 3;
        if (cp_at(source, pos - 1) == '\\' && pos < count) pos++;
        if (!token_push(tokens, token_new(TC_T_CHAR, start, pos, 0), err)) return 0;
        continue;
      }
      if (pos + 1 < count && ((source->lc[pos + 1] & TC_F_ID_START) != 0 || cp_at(source, pos + 1) >= 'A')) {
        pos += 2;
        while (pos < count && id_continue_or_upper(source, pos)) pos++;
        if (pos < count && (cp_at(source, pos) == '?' || cp_at(source, pos) == '!')) pos++;
        if (!token_push(tokens, token_new(TC_T_SYMBOL, start, pos, 0), err)) return 0;
        continue;
      }
      if (pos + 1 < count && strchr("+-*/~!%^&<|=>", (int)cp_at(source, pos + 1)) != NULL) {
        pos += 2;
        if (pos < count && strchr("=~<>@", (int)cp_at(source, pos)) != NULL) pos++;
        if (!token_push(tokens, token_new(TC_T_SYMBOL, start, pos, 0), err)) return 0;
        continue;
      }
    }

    if (c == '%' && pos + 2 < count && (cp_at(source, pos + 1) == 'w' || cp_at(source, pos + 1) == 'i') &&
        cp_at(source, pos + 2) == '[') {
      size_t start = pos;
      uint32_t kind = cp_at(source, pos + 1);
      pos += 3;
      while (pos < count && cp_at(source, pos) != ']') pos++;
      if (pos < count) pos++;
      if (!token_push(tokens, token_new(kind == 'w' ? TC_T_WORD_ARRAY : TC_T_SYMBOL_ARRAY, start, pos, 0), err)) {
        return 0;
      }
      continue;
    }

    if (c == '~') {
      size_t start = pos;
      size_t scan = pos + 1;
      if (scan < count && (cp_at(source, scan) == '+' || cp_at(source, scan) == '-')) scan++;
      if (scan < count && (source->lc[scan] & TC_F_DIGIT) != 0) {
        scan++;
        while (scan < count && (((source->lc[scan] & TC_F_DIGIT) != 0) || cp_at(source, scan) == '_')) scan++;
        if (scan + 1 < count && cp_at(source, scan) == '.' && (source->lc[scan + 1] & TC_F_DIGIT) != 0) {
          scan += 2;
          while (scan < count && (((source->lc[scan] & TC_F_DIGIT) != 0) || cp_at(source, scan) == '_')) scan++;
        }
        if (scan < count && (cp_at(source, scan) == 'e' || cp_at(source, scan) == 'E')) {
          size_t exp = scan + 1;
          if (exp < count && (cp_at(source, exp) == '+' || cp_at(source, exp) == '-')) exp++;
          if (exp < count && (source->lc[exp] & TC_F_DIGIT) != 0) {
            scan = exp + 1;
            while (scan < count && (source->lc[scan] & TC_F_DIGIT) != 0) scan++;
          }
        }
        pos = scan;
        if (!token_push(tokens, token_new(TC_T_DECIMAL, start, pos, 0), err)) return 0;
        continue;
      }
    }

    if (c == '@') {
      size_t start = pos++;
      int type = TC_T_OP;
      if (pos < count && cp_at(source, pos) == '@' && pos + 1 < count && (source->lc[pos + 1] & TC_F_ID_START) != 0) {
        pos++;
        while (pos < count && (source->lc[pos] & TC_F_ID_CONTINUE) != 0) pos++;
        type = TC_T_CVAR;
      } else if (pos < count && (source->lc[pos] & TC_F_DIGIT) != 0) {
        while (pos < count && (source->lc[pos] & TC_F_DIGIT) != 0) pos++;
        type = TC_T_PARG;
      } else if (pos < count && (source->lc[pos] & TC_F_ID_START) != 0) {
        while (pos < count && (source->lc[pos] & TC_F_ID_CONTINUE) != 0) pos++;
        type = TC_T_IVAR;
      }
      if ((type == TC_T_IVAR || type == TC_T_CVAR) &&
          !reject_mixed_case_tail(source, start, pos, count, 0, err)) return 0;
      if (!token_push(tokens, token_new(type, start, pos, 0), err)) return 0;
      continue;
    }

    if (c == '$') {
      size_t start = pos++;
      if (pos < count && (source->lc[pos] & TC_F_DIGIT) != 0) {
        while (pos < count && ((source->lc[pos] & TC_F_DIGIT) != 0 || cp_at(source, pos) == '_')) pos++;
        if (pos + 1 < count && cp_at(source, pos) == '.' && (source->lc[pos + 1] & TC_F_DIGIT) != 0) {
          pos++;
          while (pos < count && ((source->lc[pos] & TC_F_DIGIT) != 0 || cp_at(source, pos) == '_')) pos++;
        }
        if (!token_push(tokens, token_new(TC_T_DECIMAL, start, pos, 0), err)) return 0;
      } else if (pos < count && (source->lc[pos] & TC_F_ID_START) != 0) {
        while (pos < count && (source->lc[pos] & TC_F_ID_CONTINUE) != 0) pos++;
        if (!reject_mixed_case_tail(source, start, pos, count, 0, err)) return 0;
        if (!token_push(tokens, token_new(TC_T_ID, start, pos, 0), err)) return 0;
      } else {
        if (!token_push(tokens, token_new(TC_T_OP, start, pos, 0), err)) return 0;
      }
      continue;
    }

    if (c == 0xAB) {
      size_t start = pos++;
      while (pos < count && cp_at(source, pos) != 0xBB) pos++;
      if (pos < count) pos++;
      if (!token_push(tokens, token_new(TC_T_BYTE_ARRAY, start, pos, 0), err)) return 0;
      continue;
    }

    if (c == 'U' && pos + 2 < count && cp_at(source, pos + 1) == '+' && (source->lc[pos + 2] & TC_F_HEX) != 0) {
      size_t start = pos;
      pos += 2;
      while (pos < count && (source->lc[pos] & TC_F_HEX) != 0) pos++;
      if (!token_push(tokens, token_new(TC_T_CODEPOINT, start, pos, 0), err)) return 0;
      continue;
    }

    if (c >= 'A' && c <= 'Z') {
      size_t start = pos++;
      while (pos < count && id_continue_or_upper(source, pos)) pos++;
      if (!token_push(tokens, token_new(TC_T_NAME, start, pos, 0), err)) return 0;
      continue;
    }

    size_t start = pos++;
    if (c == '(' || c == '[' || c == '{') {
      paren_depth++;
    } else if (c == ')' || c == ']' || c == '}') {
      if (paren_depth > 0) paren_depth--;
    }
    if (pos < count) {
      uint32_t c2 = cp_at(source, pos);
      uint32_t c3 = pos + 1 < count ? cp_at(source, pos + 1) : 0;
      if (c == '.' && c2 == '.' && pos + 1 < count && c3 == '.') {
        pos += 2;
      } else if (c == '|' && c2 == '|' && pos + 1 < count && c3 == '=') {
        pos += 2;
      } else if (pos + 1 < count && c3 == '=' &&
                 ((c == '*' && c2 == '*') ||
                  (c == '<' && c2 == '<') ||
                  (c == '>' && c2 == '>'))) {
        pos += 2;
      } else if (c == '.' && start > 0 && cp_at(source, start - 1) == ' ' &&
                 (c2 == '+' || c2 == '-' || c2 == '*' || c2 == '/' || c2 == '|' || c2 == '&' || c2 == '^')) {
        pos++;
      } else if (c == '.' && start > 0 && cp_at(source, start - 1) == ' ' &&
                 (c2 == '<' || c2 == '>') && pos + 1 < count && c3 == c2) {
        pos += 2;
      } else if (operator_second(c, c2, c3, pos + 1 < count)) {
        pos++;
      }
    }
    if (!token_push(tokens, token_new(TC_T_OP, start, pos, 0), err)) return 0;
  }

  while (indent_top > 0) {
    indent_top--;
    if (!token_push(tokens, token_new(TC_T_DEDENT, pos, pos, 0), err)) return 0;
  }
  if (!token_push(tokens, token_new(TC_T_EOF, count, count, 0), err)) return 0;
  apply_adjacency_flags(source, tokens);
  return 1;
}

void tc_tokens_free(TcTokens *tokens) {
  if (!tokens) return;
  free(tokens->items);
  memset(tokens, 0, sizeof(*tokens));
}

int tc_token_type(WValue token) {
  return w_unbox_token_type(token);
}

uint32_t tc_token_offset(WValue token) {
  return (uint32_t)w_unbox_token_offset(token);
}

uint32_t tc_token_length(WValue token) {
  return (uint32_t)w_unbox_token_length(token);
}

int tc_token_text_eq(const TcSource *source, WValue token, const char *text) {
  uint32_t off = tc_token_offset(token);
  uint32_t len = tc_token_length(token);
  uint32_t start = source->byte_offsets[off];
  uint32_t end = source->byte_offsets[off + len];
  size_t text_len = strlen(text);
  return text_len == (size_t)(end - start) && memcmp(source->bytes + start, text, text_len) == 0;
}

int tc_token_text_copy(const TcSource *source, WValue token, char **out, size_t *len_out, TcError *err) {
  uint32_t off = tc_token_offset(token);
  uint32_t len = tc_token_length(token);
  uint32_t start = source->byte_offsets[off];
  uint32_t end = source->byte_offsets[off + len];
  char *copy = (char *)malloc((size_t)(end - start) + 1);
  if (!copy) {
    tc_error_set(err, "token text allocation failed");
    return 0;
  }
  memcpy(copy, source->bytes + start, (size_t)(end - start));
  copy[end - start] = '\0';
  *out = copy;
  if (len_out) *len_out = (size_t)(end - start);
  return 1;
}

void tc_dump_tokens(const TcSource *source, const TcTokens *tokens) {
  for (size_t i = 0; i < tokens->count; i++) {
    WValue token = tokens->items[i];
    uint32_t off = tc_token_offset(token);
    uint32_t len = tc_token_length(token);
    uint32_t start = source->byte_offsets[off];
    uint32_t end = source->byte_offsets[off + len];
    printf("%4zu type=%2d off=%u len=%u text=\"%.*s\"\n", i, tc_token_type(token), off, len,
           (int)(end - start), source->bytes + start);
  }
}
