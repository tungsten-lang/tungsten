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
    g_string_slab.static_slots = total_slots;
    g_string_slab.is_static_ro = 0;
    g_string_slab.intern_built = 1;
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

/* Zstd.compress (core/zstd.w): bytes (a String) → one zstd frame (ByteArray) with the
 * content size recorded, at level 1..22 (clamped; 3 is zstd's default); nil on failure. */
WValue w_zstd_compress(WValue data_val, WValue level_val) {
    char small[6];
    const char *src;
    size_t src_len;
    w_str_data(data_val, small, &src, &src_len);
    int level = (int)w_as_int(level_val);
    if (level < 1) level = 1;
    if (level > ZSTD_maxCLevel()) level = ZSTD_maxCLevel();
    size_t cap = ZSTD_compressBound(src_len);
    uint8_t *out = malloc(cap == 0 ? 1 : cap);
    if (!out) return W_NIL;
    size_t n = ZSTD_compress(out, cap, src, src_len, level);
    if (ZSTD_isError(n)) { free(out); return W_NIL; }
    WValue res = w_bytes_from_data(out, (int64_t)n);
    free(out);
    return res;
}

/* Zstd.decompress (core/zstd.w): a whole zstd stream (a String of bytes) (one or more frames, content size
 * known or not) → ByteArray; nil when the input is not valid zstd. Used for HTTP
 * Content-Encoding: zstd. Windows are capped at 2^27 bytes (128 MiB, RFC 8878's
 * recommendation for HTTP is 8 MiB; zstd's default limit is 2^27). */
WValue w_zstd_decompress(WValue data_val) {
    char small[6];
    const char *src;
    size_t src_len;
    w_str_data(data_val, small, &src, &src_len);
    ZSTD_DStream *ds = ZSTD_createDStream();
    if (!ds) return W_NIL;
    ZSTD_DCtx_setParameter(ds, ZSTD_d_windowLogMax, 27);
    size_t cap = src_len * 4 + 65536;
    uint8_t *out = malloc(cap);
    if (!out) { ZSTD_freeDStream(ds); return W_NIL; }
    size_t used = 0;
    ZSTD_inBuffer in = { src, src_len, 0 };
    size_t ret = 1;
    while (in.pos < in.size || ret != 0) {
        if (cap - used < 65536) {
            size_t ncap = cap * 2;
            uint8_t *n = realloc(out, ncap);
            if (!n) { free(out); ZSTD_freeDStream(ds); return W_NIL; }
            out = n;
            cap = ncap;
        }
        ZSTD_outBuffer ob = { out + used, cap - used, 0 };
        size_t before = in.pos;
        ret = ZSTD_decompressStream(ds, &ob, &in);
        if (ZSTD_isError(ret)) { free(out); ZSTD_freeDStream(ds); return W_NIL; }
        used += ob.pos;
        if (ob.pos == 0 && in.pos == before && ret != 0) {
            /* truncated input: no progress possible */
            if (in.pos >= in.size) { free(out); ZSTD_freeDStream(ds); return W_NIL; }
        }
        if (in.pos >= in.size && ret == 0) break;
    }
    ZSTD_freeDStream(ds);
    WValue res = w_bytes_from_data(out, (int64_t)used);
    free(out);
    return res;
}
