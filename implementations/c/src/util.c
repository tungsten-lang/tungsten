#include "tc.h"

#include <errno.h>
#include <stdarg.h>
#include <stdlib.h>
#include <string.h>

void tc_error_set(TcError *err, const char *fmt, ...) {
  if (!err || err->message) return;

  va_list ap;
  va_start(ap, fmt);
  va_list copy;
  va_copy(copy, ap);
  int n = vsnprintf(NULL, 0, fmt, copy);
  va_end(copy);
  if (n < 0) {
    va_end(ap);
    return;
  }

  err->message = (char *)malloc((size_t)n + 1);
  if (!err->message) {
    va_end(ap);
    return;
  }
  vsnprintf(err->message, (size_t)n + 1, fmt, ap);
  va_end(ap);
}

void tc_error_free(TcError *err) {
  if (!err) return;
  free(err->message);
  err->message = NULL;
}

unsigned char *tc_read_file(const char *path, size_t *len_out, TcError *err) {
  FILE *f = fopen(path, "rb");
  if (!f) {
    tc_error_set(err, "open %s: %s", path, strerror(errno));
    return NULL;
  }

  if (fseek(f, 0, SEEK_END) != 0) {
    tc_error_set(err, "seek %s: %s", path, strerror(errno));
    fclose(f);
    return NULL;
  }

  long n = ftell(f);
  if (n < 0) {
    tc_error_set(err, "tell %s: %s", path, strerror(errno));
    fclose(f);
    return NULL;
  }
  rewind(f);

  unsigned char *buf = (unsigned char *)malloc((size_t)n + 1);
  if (!buf) {
    tc_error_set(err, "malloc failed reading %s", path);
    fclose(f);
    return NULL;
  }

  size_t got = fread(buf, 1, (size_t)n, f);
  fclose(f);
  if (got != (size_t)n) {
    tc_error_set(err, "read %s failed", path);
    free(buf);
    return NULL;
  }

  buf[n] = 0;
  if (len_out) *len_out = (size_t)n;
  return buf;
}

unsigned char *tc_load_lex64_table(const char *path, size_t *len_out, TcError *err) {
  unsigned char *table = tc_read_file(path, len_out, err);
  if (!table) return NULL;
  if (*len_out < 0x110000u) {
    tc_error_set(err, "%s is too small for a Unicode lex64 table", path);
    free(table);
    return NULL;
  }
  return table;
}
