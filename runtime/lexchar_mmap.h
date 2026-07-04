/*
 * lexchar_mmap.h — mmap-based LexChar lookup table
 *
 * Writes the pre-computed Unicode metadata tables to a binary file,
 * then mmaps it for instant access. Avoids compiling 1MB of static
 * data into every binary.
 *
 * File format:
 *   [4 bytes]  magic "WLCH"
 *   [4 bytes]  version (1)
 *   [4 bytes]  num_blocks (4352)
 *   [4 bytes]  num_data_blocks (173)
 *   [8704 bytes]  block_index[4352] (uint16_t)
 *   [354304 bytes]  block_data[173][256] (uint64_t)
 */

#ifndef LEXCHAR_MMAP_H
#define LEXCHAR_MMAP_H

#include <stdint.h>

#define LEXCHAR_MAGIC "WLCH"
#define LEXCHAR_VERSION 1
#define LEXCHAR_NUM_BLOCKS 4352
#define LEXCHAR_NUM_DATA_BLOCKS 173

typedef struct {
    uint16_t *block_index;  /* [4352] codepoint >> 8 → block id */
    uint64_t *block_data;   /* [173 * 256] flat: block_data[id * 256 + (cp & 0xFF)] */
    void *mmap_base;
    size_t mmap_size;
} LexCharTable;

/* Write compiled tables to binary file. Returns 0 on success. */
int lexchar_table_write(const char *path);

/* Load table via mmap. Returns 0 on success. */
int lexchar_table_load(LexCharTable *table, const char *path);

/* Lookup using mmapped table. Same result as w_lexchar_cached. */
static inline uint64_t lexchar_lookup(const LexCharTable *t, uint32_t cp) {
    if (cp >= 0x110000) return 0xFFFA00000000EF80ULL;
    uint32_t block = cp >> 8;
    uint32_t offset = cp & 0xFF;
    return t->block_data[(uint32_t)t->block_index[block] * 256 + offset];
}

#endif
