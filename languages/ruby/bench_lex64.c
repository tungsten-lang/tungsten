// Ruby Lex64 benchmark harness.
//
// This mirrors languages/ruby/lexer.w closely enough to measure the Ruby
// LexChar table + broad-token scanner without depending on the self-hosted
// compiler being healthy.

#include <errno.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

enum {
  F_NEWLINE = 0x80,
  F_ID_START = 0x40,
  F_ID_CONTINUE = 0x20,
  F_WHITESPACE = 0x10,
  F_HEX = 0x08,
  F_OPERATOR = 0x04,
  F_QUOTE = 0x02,
  F_DIGIT = 0x01,
};

static const uint64_t LEX64_TAG = 0xFFFC000000000000ULL | (1ULL << 46);
static const uint64_t TOKEN_TAG = 0xFFFC000000000000ULL;
static const uint64_t CP_MASK = 0x1FFFFFULL;

static double now_ms(void) {
  struct timespec ts;
  clock_gettime(CLOCK_MONOTONIC, &ts);
  return (double)ts.tv_sec * 1000.0 + (double)ts.tv_nsec / 1000000.0;
}

static unsigned char *read_file(const char *path, size_t *len_out) {
  FILE *f = fopen(path, "rb");
  if (!f) {
    fprintf(stderr, "open %s: %s\n", path, strerror(errno));
    exit(1);
  }
  if (fseek(f, 0, SEEK_END) != 0) {
    fprintf(stderr, "seek %s: %s\n", path, strerror(errno));
    exit(1);
  }
  long n = ftell(f);
  if (n < 0) {
    fprintf(stderr, "tell %s: %s\n", path, strerror(errno));
    exit(1);
  }
  rewind(f);
  unsigned char *buf = (unsigned char *)malloc((size_t)n + 1);
  if (!buf) {
    fprintf(stderr, "malloc failed\n");
    exit(1);
  }
  if (fread(buf, 1, (size_t)n, f) != (size_t)n) {
    fprintf(stderr, "read %s failed\n", path);
    exit(1);
  }
  fclose(f);
  buf[n] = 0;
  *len_out = (size_t)n;
  return buf;
}

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

static size_t build_lc64(const unsigned char *src, size_t n, const unsigned char *flags, uint64_t *lc) {
  size_t i = 0;
  size_t count = 0;
  while (i < n) {
    uint32_t cp = decode_utf8(src, n, &i);
    unsigned char f = cp < 0x110000 ? flags[cp] : 0;
    lc[count++] = LEX64_TAG | ((uint64_t)cp << 18) | (uint64_t)f;
  }
  lc[count] = 0;
  return count;
}

static inline uint32_t cp_at(const uint64_t *lc, size_t pos) {
  return (uint32_t)((lc[pos] >> 18) & CP_MASK);
}

static size_t ruby_tokenize_fast64_c(const uint64_t *lc, size_t count, uint64_t *tokens) {
  size_t pos = 0;
  size_t tc = 0;

  const uint64_t t_ident   = TOKEN_TAG | (0x01ULL << 40);
  const uint64_t t_const   = TOKEN_TAG | (0x02ULL << 40);
  const uint64_t t_int     = TOKEN_TAG | (0x03ULL << 40);
  const uint64_t t_float   = TOKEN_TAG | (0x04ULL << 40);
  const uint64_t t_string  = TOKEN_TAG | (0x05ULL << 40);
  const uint64_t t_symbol  = TOKEN_TAG | (0x06ULL << 40);
  const uint64_t t_op      = TOKEN_TAG | (0x07ULL << 40);
  const uint64_t t_comment = TOKEN_TAG | (0x08ULL << 40);
  const uint64_t t_nl      = TOKEN_TAG | (0x09ULL << 40);
  const uint64_t t_ivar    = TOKEN_TAG | (0x0AULL << 40);
  const uint64_t t_cvar    = TOKEN_TAG | (0x0BULL << 40);
  const uint64_t t_gvar    = TOKEN_TAG | (0x0CULL << 40);
  const uint64_t t_error   = TOKEN_TAG | (0x0DULL << 40);

  while (pos < count) {
    uint64_t v = lc[pos];
    uint32_t c = (uint32_t)((v >> 18) & CP_MASK);
    if (c == 0) break;

    switch (v & 0xD7) {
      case F_WHITESPACE:
        pos++;
        while (pos < count && (lc[pos] & F_WHITESPACE) != 0) pos++;
        break;

      case F_NEWLINE: {
        size_t start = pos++;
        if (c == '\r' && pos < count && cp_at(lc, pos) == '\n') pos++;
        tokens[tc++] = t_nl | ((uint64_t)(pos - start) << 28) | ((uint64_t)start << 4);
        break;
      }

      case F_ID_START: {
        size_t start = pos++;
        while (pos < count && (lc[pos] & F_ID_CONTINUE) != 0) pos++;
        if (pos < count) {
          uint32_t c2 = cp_at(lc, pos);
          if (c2 == '?' || c2 == '!') pos++;
        }
        uint64_t len = (uint64_t)(pos - start);
        tokens[tc++] = ((c >= 'A' && c <= 'Z') ? t_const : t_ident) | (len << 28) | ((uint64_t)start << 4);
        break;
      }

      case F_DIGIT: {
        size_t start = pos;
        int is_float = 0;

        if (c == '0' && pos + 1 < count) {
          uint32_t c2 = cp_at(lc, pos + 1);
          if (c2 == 'x' || c2 == 'X') {
            pos += 2;
            while (pos < count && ((lc[pos] & F_HEX) != 0 || cp_at(lc, pos) == '_')) pos++;
            tokens[tc++] = t_int | ((uint64_t)(pos - start) << 28) | ((uint64_t)start << 4);
            break;
          }
          if (c2 == 'b' || c2 == 'B') {
            pos += 2;
            for (;;) {
              c2 = cp_at(lc, pos);
              if (c2 == '0' || c2 == '1' || c2 == '_') pos++;
              else break;
            }
            tokens[tc++] = t_int | ((uint64_t)(pos - start) << 28) | ((uint64_t)start << 4);
            break;
          }
          if (c2 == 'o' || c2 == 'O') {
            pos += 2;
            for (;;) {
              c2 = cp_at(lc, pos);
              if ((c2 >= '0' && c2 <= '7') || c2 == '_') pos++;
              else break;
            }
            tokens[tc++] = t_int | ((uint64_t)(pos - start) << 28) | ((uint64_t)start << 4);
            break;
          }
        }

        pos++;
        while (pos < count && ((lc[pos] & F_DIGIT) != 0 || cp_at(lc, pos) == '_')) pos++;

        if (pos + 1 < count && cp_at(lc, pos) == '.' && (lc[pos + 1] & F_DIGIT) != 0) {
          is_float = 1;
          pos += 2;
          while (pos < count && ((lc[pos] & F_DIGIT) != 0 || cp_at(lc, pos) == '_')) pos++;
        }

        if (pos < count) {
          uint32_t c2 = cp_at(lc, pos);
          if (c2 == 'e' || c2 == 'E') {
            is_float = 1;
            pos++;
            c2 = cp_at(lc, pos);
            if (c2 == '+' || c2 == '-') pos++;
            while (pos < count && ((lc[pos] & F_DIGIT) != 0 || cp_at(lc, pos) == '_')) pos++;
          }
        }

        tokens[tc++] = (is_float ? t_float : t_int) | ((uint64_t)(pos - start) << 28) |
                       ((uint64_t)start << 4);
        break;
      }

      case F_QUOTE: {
        size_t start = pos;
        uint32_t quote = c;
        pos++;
        while (pos < count) {
          uint32_t c2 = cp_at(lc, pos);
          if (c2 == 0) break;
          if (c2 == '\\') pos += 2;
          else if (c2 == quote) {
            pos++;
            break;
          } else {
            pos++;
          }
        }
        tokens[tc++] = t_string | ((uint64_t)(pos - start) << 28) | ((uint64_t)start << 4);
        break;
      }

      case F_OPERATOR: {
        size_t start = pos;

        if (c == '#') {
          pos++;
          while (pos < count && (lc[pos] & F_NEWLINE) == 0) pos++;
          tokens[tc++] = t_comment | ((uint64_t)(pos - start) << 28) | ((uint64_t)start << 4);
          break;
        }

        if (c == '@' && pos + 1 < count) {
          if (cp_at(lc, pos + 1) == '@') {
            pos += 2;
            while (pos < count && (lc[pos] & F_ID_CONTINUE) != 0) pos++;
            tokens[tc++] = t_cvar | ((uint64_t)(pos - start) << 28) | ((uint64_t)start << 4);
            break;
          }
          if ((lc[pos + 1] & F_ID_START) != 0) {
            pos++;
            while (pos < count && (lc[pos] & F_ID_CONTINUE) != 0) pos++;
            tokens[tc++] = t_ivar | ((uint64_t)(pos - start) << 28) | ((uint64_t)start << 4);
            break;
          }
        }

        if (c == '$' && pos + 1 < count) {
          pos++;
          if ((lc[pos] & F_ID_START) != 0) {
            pos++;
            while (pos < count && (lc[pos] & F_ID_CONTINUE) != 0) pos++;
          } else if ((lc[pos] & F_DIGIT) != 0) {
            while (pos < count && (lc[pos] & F_DIGIT) != 0) pos++;
          } else {
            pos++;
          }
          tokens[tc++] = t_gvar | ((uint64_t)(pos - start) << 28) | ((uint64_t)start << 4);
          break;
        }

        if (c == ':' && pos + 1 < count) {
          uint32_t c2 = cp_at(lc, pos + 1);
          if (c2 != ':' && ((lc[pos + 1] & F_ID_START) != 0 || (lc[pos + 1] & F_QUOTE) != 0)) {
            pos++;
            if ((lc[pos] & F_QUOTE) != 0) {
              uint32_t quote = cp_at(lc, pos++);
              while (pos < count) {
                c2 = cp_at(lc, pos);
                if (c2 == '\\') pos += 2;
                else if (c2 == quote) {
                  pos++;
                  break;
                } else {
                  pos++;
                }
              }
            } else {
              while (pos < count && (lc[pos] & F_ID_CONTINUE) != 0) pos++;
              c2 = cp_at(lc, pos);
              if (c2 == '?' || c2 == '!') pos++;
            }
            tokens[tc++] = t_symbol | ((uint64_t)(pos - start) << 28) | ((uint64_t)start << 4);
            break;
          }
        }

        pos++;
        while (pos < count) {
          uint32_t c2 = cp_at(lc, pos);
          if (c2 == '#' || c2 == '@' || c2 == '$' || c2 == '"' || c2 == '\'' || c2 == '`') break;
          if ((lc[pos] & F_OPERATOR) != 0) pos++;
          else break;
        }
        tokens[tc++] = t_op | ((uint64_t)(pos - start) << 28) | ((uint64_t)start << 4);
        break;
      }

      default:
        tokens[tc++] = t_error | (1ULL << 28) | ((uint64_t)pos << 4);
        pos++;
        break;
    }
  }

  return tc;
}

int main(int argc, char **argv) {
  if (argc < 2) {
    fprintf(stderr, "usage: bench_lex64 <file.rb> [rounds]\n");
    return 1;
  }

  int rounds = argc > 2 ? atoi(argv[2]) : 50;
  if (rounds <= 0) rounds = 50;

  size_t source_len = 0;
  unsigned char *source = read_file(argv[1], &source_len);

  size_t flags_len = 0;
  unsigned char *flags = read_file("languages/ruby/ruby.lex64", &flags_len);
  if (flags_len < 0x110000) {
    fprintf(stderr, "languages/ruby/ruby.lex64 is too small\n");
    return 1;
  }

  uint64_t *lc = (uint64_t *)calloc(source_len + 1, sizeof(uint64_t));
  uint64_t *tokens = (uint64_t *)calloc(source_len + 1, sizeof(uint64_t));
  if (!lc || !tokens) {
    fprintf(stderr, "calloc failed\n");
    return 1;
  }

  size_t count = build_lc64(source, source_len, flags, lc);
  size_t warm_tokens = ruby_tokenize_fast64_c(lc, count, tokens);

  double t0 = now_ms();
  volatile size_t total_tokens = 0;
  for (int r = 0; r < rounds; r++) {
    total_tokens += ruby_tokenize_fast64_c(lc, count, tokens);
  }
  double t1 = now_ms();

  double scan_ms = t1 - t0;
  double scan_mbps = ((double)source_len * (double)rounds / 1000000.0) / (scan_ms / 1000.0);

  t0 = now_ms();
  volatile size_t total_e2e_tokens = 0;
  for (int r = 0; r < rounds; r++) {
    count = build_lc64(source, source_len, flags, lc);
    total_e2e_tokens += ruby_tokenize_fast64_c(lc, count, tokens);
  }
  t1 = now_ms();

  double e2e_ms = t1 - t0;
  double e2e_mbps = ((double)source_len * (double)rounds / 1000000.0) / (e2e_ms / 1000.0);

  printf("Ruby Lexer Benchmark (Lex64 C harness)\n");
  printf("  file: %s\n", argv[1]);
  printf("  chars: %zu  bytes: %zu  rounds: %d\n", count, source_len, rounds);
  printf("  tokens/round: %zu\n", warm_tokens);
  printf("  tokenize only: %.3fms, %.1f MB/s\n", scan_ms, scan_mbps);
  printf("  lchs + tokenize: %.3fms, %.1f MB/s\n", e2e_ms, e2e_mbps);

  free(tokens);
  free(lc);
  free(flags);
  free(source);
  return total_tokens == 0 || total_e2e_tokens == 0;
}

