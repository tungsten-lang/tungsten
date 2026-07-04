#include "runtime.h"

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <zstd.h>

#ifndef MAP_ANON
#define MAP_ANON MAP_ANONYMOUS
#endif

static void slab_zstd_die(const char *msg) {
    fprintf(stderr, "%s\n", msg);
    abort();
}

void w_slab_init_static_zstd(const uint8_t *data, uint32_t compressed_bytes, uint32_t total_slots) {
    if (g_string_slab.base) return;

    size_t data_size = (size_t)total_slots * W_SLAB_SLOT_SIZE;
    g_string_slab.base = mmap(NULL, W_SLAB_TOTAL_SIZE,
                              PROT_NONE, MAP_PRIVATE | MAP_ANON, -1, 0);
    if (g_string_slab.base == MAP_FAILED) slab_zstd_die("string slab: mmap failed");

    size_t page_size = (size_t)sysconf(_SC_PAGESIZE);
    size_t needed = (data_size + page_size - 1) & ~(page_size - 1);
    if (mprotect(g_string_slab.base, needed, PROT_READ | PROT_WRITE) != 0) {
        slab_zstd_die("string slab: mprotect failed");
    }

    size_t out = ZSTD_decompress(g_string_slab.base, data_size, data, compressed_bytes);
    if (ZSTD_isError(out) || out != data_size) {
        slab_zstd_die("string slab: zstd decompress failed");
    }

    g_string_slab.next_slot = total_slots;
    g_string_slab.page_hwm = (uint32_t)needed;
    g_string_slab.frozen = 0;
    pthread_mutex_init(&g_string_slab.lock, NULL);
    w_slab_rebuild_intern(total_slots);
}

static int hex_nibble(char ch) {
    if (ch >= '0' && ch <= '9') return ch - '0';
    if (ch >= 'a' && ch <= 'f') return 10 + (ch - 'a');
    if (ch >= 'A' && ch <= 'F') return 10 + (ch - 'A');
    return -1;
}

WValue w_zstd_compress_llvm_escaped(WValue escaped_val) {
    char small[6];
    const char *escaped;
    size_t escaped_len;
    w_str_data(escaped_val, small, &escaped, &escaped_len);

    uint8_t *raw = malloc(escaped_len == 0 ? 1 : escaped_len);
    if (!raw) slab_zstd_die("zstd helper: raw buffer allocation failed");

    size_t raw_len = 0;
    for (size_t i = 0; i < escaped_len; i++) {
        if (escaped[i] == '\\') {
            if (i + 2 >= escaped_len) slab_zstd_die("zstd helper: truncated llvm escape");
            int hi = hex_nibble(escaped[i + 1]);
            int lo = hex_nibble(escaped[i + 2]);
            if (hi < 0 || lo < 0) slab_zstd_die("zstd helper: invalid llvm escape");
            raw[raw_len++] = (uint8_t)((hi << 4) | lo);
            i += 2;
        } else {
            raw[raw_len++] = (uint8_t)escaped[i];
        }
    }

    size_t compressed_cap = ZSTD_compressBound(raw_len);
    uint8_t *compressed = malloc(compressed_cap == 0 ? 1 : compressed_cap);
    if (!compressed) slab_zstd_die("zstd helper: compressed buffer allocation failed");

    size_t compressed_len = ZSTD_compress(compressed, compressed_cap, raw, raw_len, 3);
    if (ZSTD_isError(compressed_len)) slab_zstd_die("zstd helper: compress failed");

    static const char hex[] = "0123456789abcdef";
    size_t escaped_out_len = compressed_len * 3;
    char *escaped_out = malloc(escaped_out_len + 1);
    if (!escaped_out) slab_zstd_die("zstd helper: escaped buffer allocation failed");

    size_t out = 0;
    for (size_t i = 0; i < compressed_len; i++) {
        uint8_t b = compressed[i];
        escaped_out[out++] = '\\';
        escaped_out[out++] = hex[b >> 4];
        escaped_out[out++] = hex[b & 15];
    }
    escaped_out[out] = '\0';

    WValue result = w_array_new_empty();
    w_array_push(result, w_string(escaped_out));
    w_array_push(result, w_int((int64_t)compressed_len));

    free(raw);
    free(compressed);
    free(escaped_out);
    return result;
}
