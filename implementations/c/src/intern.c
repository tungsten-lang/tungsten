// Global byte-content intern table. Returns a canonical pointer so any
// two equal-content interned strings share the same bytes buffer.
//
// Used for TC_VAL_SYMBOL (and TC_AST_SYMBOL) so the bytecode VM's
// sym==sym path can be a 1-cycle pointer compare with no memcmp
// fallback. Allocations are owned by this table for the lifetime of
// the process — bootstrap is short-lived, so leak is fine.
//
// Open-addressing linear-probe hash table; doubles when load > 50%.
//
// Not thread-safe — the C VM is single-threaded.

#include "tc.h"

#include <stdlib.h>
#include <string.h>

typedef struct {
  const char *bytes;  // owned by this table
  uint32_t len;
  uint64_t hash;
} TcInternEntry;

static TcInternEntry *g_table = NULL;
static size_t g_cap = 0;
static size_t g_count = 0;

static uint64_t intern_hash(const char *bytes, size_t len) {
  // FNV-1a — short keys, low collision rate, no surprises.
  uint64_t h = 0xcbf29ce484222325ULL;
  for (size_t i = 0; i < len; i++) {
    h ^= (uint8_t)bytes[i];
    h *= 0x100000001b3ULL;
  }
  return h;
}

static int intern_grow(void) {
  size_t new_cap = g_cap == 0 ? 1024 : g_cap * 2;
  TcInternEntry *new_table = (TcInternEntry *)calloc(new_cap, sizeof(TcInternEntry));
  if (!new_table) return 0;
  size_t mask = new_cap - 1;
  for (size_t i = 0; i < g_cap; i++) {
    if (!g_table[i].bytes) continue;
    size_t slot = (size_t)g_table[i].hash & mask;
    while (new_table[slot].bytes) slot = (slot + 1) & mask;
    new_table[slot] = g_table[i];
  }
  free(g_table);
  g_table = new_table;
  g_cap = new_cap;
  return 1;
}

const char *tc_intern(const char *bytes, size_t len) {
  if (g_cap == 0 || g_count * 2 >= g_cap) {
    if (!intern_grow()) return NULL;
  }
  uint64_t h = intern_hash(bytes, len);
  size_t mask = g_cap - 1;
  size_t slot = (size_t)h & mask;
  while (g_table[slot].bytes) {
    if (g_table[slot].hash == h && g_table[slot].len == len &&
        memcmp(g_table[slot].bytes, bytes, len) == 0) {
      return g_table[slot].bytes;
    }
    slot = (slot + 1) & mask;
  }
  // Insert. Bytes go into a TcHeapString (interned=1) so post-flip the
  // WValue heap-string tag mode can reach the header via offsetof. The
  // header itself is never visited by GC sweep (the `interned` flag in
  // its header tells tc_heap_string_release to skip free too).
  char *copy = tc_heap_string_alloc(len, 1, NULL);
  if (!copy) return NULL;
  memcpy(copy, bytes, len);
  g_table[slot].bytes = copy;
  g_table[slot].len = (uint32_t)len;
  g_table[slot].hash = h;
  g_count++;
  return copy;
}
