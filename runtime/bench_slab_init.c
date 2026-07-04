/*
 * bench_slab_init.c — Compare static slab init strategies.
 *
 * Uses the existing slab format and measures:
 *   - raw whole-blob memcpy
 *   - raw compact record decode
 *   - zlib/gzip full and compact forms
 *   - zstd full and compact forms
 *   - custom zero-run full and compact forms
 *
 * The destination is a fresh zeroed anonymous mapping each iteration, matching
 * the runtime assumption that untouched padding bytes stay zero.
 */

#include "runtime.h"

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <time.h>
#include <unistd.h>
#include <zlib.h>
#include <zstd.h>

#ifndef MAP_ANON
#define MAP_ANON MAP_ANONYMOUS
#endif

typedef enum {
    LENGTHS_SMALL,
    LENGTHS_MIXED,
    LENGTHS_LARGE
} LengthPattern;

typedef struct {
    uint32_t src_off;
    uint32_t dst_off;
    uint8_t record_bytes;
} CopyPlanOp;

typedef struct {
    const char *name;
    uint8_t *blob;
    uint8_t *compact;
    uint8_t *zlib_blob;
    uint8_t *zlib_compact;
    uint8_t *zstd_blob;
    uint8_t *zstd_compact;
    uint8_t *zerorun_blob;
    uint8_t *zerorun_compact;
    uint32_t entry_count;
    uint32_t total_slots;
    size_t slab_bytes;
    size_t live_bytes;
    size_t compact_bytes;
    size_t zlib_blob_bytes;
    size_t zlib_compact_bytes;
    size_t zstd_blob_bytes;
    size_t zstd_compact_bytes;
    size_t zerorun_blob_bytes;
    size_t zerorun_compact_bytes;
    CopyPlanOp *plan;
    uint32_t plan_len;
} SlabFixture;

static volatile uint64_t g_sink = 0;

static uint64_t pseudo_hash(uint32_t entry_index, uint32_t len) {
    uint64_t x = 0x9e3779b97f4a7c15ULL ^ ((uint64_t)entry_index << 32) ^ len;
    x ^= x >> 30;
    x *= 0xbf58476d1ce4e5b9ULL;
    x ^= x >> 27;
    x *= 0x94d049bb133111ebULL;
    x ^= x >> 31;
    return x;
}

static uint8_t length_for_pattern(LengthPattern pattern, uint32_t i) {
    switch (pattern) {
        case LENGTHS_SMALL:
            return (uint8_t)(6 + (i % 16));   /* 6..21, always 1 slot */
        case LENGTHS_LARGE:
            return (uint8_t)(22 + (i % 32));  /* 22..53, always 2 slots */
        case LENGTHS_MIXED:
        default:
            if ((i % 4) == 3) return (uint8_t)(22 + (i % 32)); /* 25% 2-slot */
            return (uint8_t)(6 + (i % 16));
    }
}

static size_t encode_zero_runs(const uint8_t *src, size_t src_len, uint8_t **out_ptr) {
    size_t cap = src_len * 4 + 1;
    uint8_t *out = malloc(cap);
    if (!out) {
        fprintf(stderr, "failed to allocate %zu-byte zero-run buffer\n", cap);
        exit(1);
    }

    size_t in = 0;
    size_t out_len = 0;
    while (in < src_len) {
        if (src[in] == 0) {
            size_t run = 0;
            while (in + run < src_len && src[in + run] == 0 && run < 65535) {
                run++;
            }
            out[out_len++] = 0;
            out[out_len++] = (uint8_t)(run & 0xFF);
            out[out_len++] = (uint8_t)((run >> 8) & 0xFF);
            in += run;
            continue;
        }

        size_t lit = 0;
        while (in + lit < src_len && src[in + lit] != 0 && lit < 65535) {
            lit++;
        }
        out[out_len++] = 1;
        out[out_len++] = (uint8_t)(lit & 0xFF);
        out[out_len++] = (uint8_t)((lit >> 8) & 0xFF);
        memcpy(out + out_len, src + in, lit);
        out_len += lit;
        in += lit;
    }

    *out_ptr = out;
    return out_len;
}

static SlabFixture build_fixture(const char *name, uint32_t entry_count, LengthPattern pattern) {
    SlabFixture fixture = {0};
    fixture.name = name;
    fixture.entry_count = entry_count;

    uint32_t total_slots = 1; /* slot 0 sentinel */
    size_t live_bytes = 0;
    for (uint32_t i = 0; i < entry_count; i++) {
        uint8_t len = length_for_pattern(pattern, i);
        total_slots += (len <= W_SLAB_SSO_MAX) ? 1u : 2u;
        live_bytes += (size_t)W_SLAB_HEADER_SIZE + len;
    }

    fixture.total_slots = total_slots;
    fixture.slab_bytes = (size_t)total_slots * W_SLAB_SLOT_SIZE;
    fixture.live_bytes = live_bytes;
    fixture.blob = calloc(1, fixture.slab_bytes);
    if (!fixture.blob) {
        fprintf(stderr, "failed to allocate %zu-byte slab fixture\n", fixture.slab_bytes);
        exit(1);
    }

    uint32_t slot_index = 1;
    for (uint32_t i = 0; i < entry_count; i++) {
        uint8_t len = length_for_pattern(pattern, i);
        uint8_t nslots = (len <= W_SLAB_SSO_MAX) ? 1 : 2;
        uint8_t flags = W_SFLAG_INLINE;
        if (nslots == 2) flags |= W_SFLAG_CONTINUATION;

        uint8_t *slot = fixture.blob + ((size_t)slot_index * W_SLAB_SLOT_SIZE);
        uint64_t hash = pseudo_hash(i + 1, len);
        memcpy(slot, &hash, sizeof(hash));
        slot[8] = len;
        slot[9] = flags;

        uint8_t *data = slot + W_SLAB_DATA_OFFSET;
        for (uint8_t j = 0; j < len; j++) {
            data[j] = (uint8_t)('a' + ((i + j) % 26));
        }

        slot_index += nslots;
    }

    fixture.compact_bytes = fixture.live_bytes;
    fixture.compact = malloc(fixture.compact_bytes);
    fixture.plan = malloc((size_t)entry_count * sizeof(CopyPlanOp));
    if (!fixture.compact) {
        fprintf(stderr, "failed to allocate %zu-byte compact slab fixture\n", fixture.compact_bytes);
        exit(1);
    }
    if (!fixture.plan) {
        fprintf(stderr, "failed to allocate compact decode plan\n");
        exit(1);
    }

    size_t compact_off = 0;
    uint32_t plan_len = 0;
    slot_index = 1;
    while (slot_index < fixture.total_slots) {
        const uint8_t *slot = fixture.blob + ((size_t)slot_index * W_SLAB_SLOT_SIZE);
        uint8_t len = slot[8];
        uint8_t flags = slot[9];
        if (len == 0) {
            slot_index++;
            continue;
        }
        size_t record_bytes = (size_t)W_SLAB_HEADER_SIZE + len;
        fixture.plan[plan_len].src_off = (uint32_t)compact_off;
        fixture.plan[plan_len].dst_off = slot_index * W_SLAB_SLOT_SIZE;
        fixture.plan[plan_len].record_bytes = (uint8_t)record_bytes;
        plan_len++;
        memcpy(fixture.compact + compact_off, slot, record_bytes);
        compact_off += record_bytes;
        slot_index += (flags & W_SFLAG_CONTINUATION) ? 2u : 1u;
    }
    fixture.plan_len = plan_len;

    if (compact_off != fixture.compact_bytes) {
        fprintf(stderr, "compact stream size mismatch for %s (%zu vs %zu)\n",
                fixture.name, compact_off, fixture.compact_bytes);
        exit(1);
    }

    {
        z_stream zs;
        memset(&zs, 0, sizeof(zs));
        if (deflateInit2(&zs, Z_BEST_COMPRESSION, Z_DEFLATED, 15 + 16, 8, Z_DEFAULT_STRATEGY) != Z_OK) {
            fprintf(stderr, "deflateInit2 failed for full slab fixture\n");
            exit(1);
        }
        size_t cap = deflateBound(&zs, fixture.slab_bytes);
        fixture.zlib_blob = malloc(cap);
        if (!fixture.zlib_blob) {
            fprintf(stderr, "failed to allocate zlib blob buffer\n");
            exit(1);
        }
        zs.next_in = fixture.blob;
        zs.avail_in = (uInt)fixture.slab_bytes;
        zs.next_out = fixture.zlib_blob;
        zs.avail_out = (uInt)cap;
        if (deflate(&zs, Z_FINISH) != Z_STREAM_END) {
            fprintf(stderr, "deflate failed for full slab fixture\n");
            exit(1);
        }
        fixture.zlib_blob_bytes = zs.total_out;
        deflateEnd(&zs);
    }

    {
        z_stream zs;
        memset(&zs, 0, sizeof(zs));
        if (deflateInit2(&zs, Z_BEST_COMPRESSION, Z_DEFLATED, 15 + 16, 8, Z_DEFAULT_STRATEGY) != Z_OK) {
            fprintf(stderr, "deflateInit2 failed for compact slab fixture\n");
            exit(1);
        }
        size_t cap = deflateBound(&zs, fixture.compact_bytes);
        fixture.zlib_compact = malloc(cap);
        if (!fixture.zlib_compact) {
            fprintf(stderr, "failed to allocate zlib compact buffer\n");
            exit(1);
        }
        zs.next_in = fixture.compact;
        zs.avail_in = (uInt)fixture.compact_bytes;
        zs.next_out = fixture.zlib_compact;
        zs.avail_out = (uInt)cap;
        if (deflate(&zs, Z_FINISH) != Z_STREAM_END) {
            fprintf(stderr, "deflate failed for compact slab fixture\n");
            exit(1);
        }
        fixture.zlib_compact_bytes = zs.total_out;
        deflateEnd(&zs);
    }

    {
        size_t cap = ZSTD_compressBound(fixture.slab_bytes);
        fixture.zstd_blob = malloc(cap);
        if (!fixture.zstd_blob) {
            fprintf(stderr, "failed to allocate zstd blob buffer\n");
            exit(1);
        }
        size_t out = ZSTD_compress(fixture.zstd_blob, cap, fixture.blob, fixture.slab_bytes, 3);
        if (ZSTD_isError(out)) {
            fprintf(stderr, "zstd compress failed for full slab fixture: %s\n", ZSTD_getErrorName(out));
            exit(1);
        }
        fixture.zstd_blob_bytes = out;
    }

    {
        size_t cap = ZSTD_compressBound(fixture.compact_bytes);
        fixture.zstd_compact = malloc(cap);
        if (!fixture.zstd_compact) {
            fprintf(stderr, "failed to allocate zstd compact buffer\n");
            exit(1);
        }
        size_t out = ZSTD_compress(fixture.zstd_compact, cap, fixture.compact, fixture.compact_bytes, 3);
        if (ZSTD_isError(out)) {
            fprintf(stderr, "zstd compress failed for compact slab fixture: %s\n", ZSTD_getErrorName(out));
            exit(1);
        }
        fixture.zstd_compact_bytes = out;
    }

    fixture.zerorun_blob_bytes = encode_zero_runs(fixture.blob, fixture.slab_bytes, &fixture.zerorun_blob);
    fixture.zerorun_compact_bytes = encode_zero_runs(fixture.compact, fixture.compact_bytes, &fixture.zerorun_compact);

    return fixture;
}

static void destroy_fixture(SlabFixture *fixture) {
    free(fixture->blob);
    free(fixture->compact);
    free(fixture->zlib_blob);
    free(fixture->zlib_compact);
    free(fixture->zstd_blob);
    free(fixture->zstd_compact);
    free(fixture->zerorun_blob);
    free(fixture->zerorun_compact);
    free(fixture->plan);
    fixture->blob = NULL;
    fixture->compact = NULL;
    fixture->zlib_blob = NULL;
    fixture->zlib_compact = NULL;
    fixture->zstd_blob = NULL;
    fixture->zstd_compact = NULL;
    fixture->zerorun_blob = NULL;
    fixture->zerorun_compact = NULL;
    fixture->plan = NULL;
}

static void copy_whole_blob(uint8_t *dst, const uint8_t *src, uint32_t total_slots) {
    memcpy(dst, src, (size_t)total_slots * W_SLAB_SLOT_SIZE);
}

static void copy_live_bytes(uint8_t *dst, const uint8_t *src, uint32_t total_slots) {
    uint32_t idx = 1;
    while (idx < total_slots) {
        const uint8_t *src_slot = src + ((size_t)idx * W_SLAB_SLOT_SIZE);
        uint8_t len = src_slot[8];
        uint8_t flags = src_slot[9];
        if (len == 0) {
            idx++;
            continue;
        }

        uint8_t *dst_slot = dst + ((size_t)idx * W_SLAB_SLOT_SIZE);
        memcpy(dst_slot, src_slot, (size_t)W_SLAB_HEADER_SIZE + len);

        idx += (flags & W_SFLAG_CONTINUATION) ? 2u : 1u;
    }
}

static void decode_compact_stream(uint8_t *dst, const uint8_t *src, const CopyPlanOp *plan, uint32_t plan_len) {
    for (uint32_t i = 0; i < plan_len; i++) {
        const CopyPlanOp *op = plan + i;
        memcpy(dst + op->dst_off, src + op->src_off, op->record_bytes);
    }
}

typedef struct {
    z_stream zs;
} GunzipCtx;

static void gunzip_ctx_init(GunzipCtx *ctx) {
    memset(ctx, 0, sizeof(*ctx));
    if (inflateInit2(&ctx->zs, 15 + 16) != Z_OK) {
        fprintf(stderr, "inflateInit2 failed\n");
        exit(1);
    }
}

static void gunzip_ctx_free(GunzipCtx *ctx) {
    inflateEnd(&ctx->zs);
}

static void gunzip_into(GunzipCtx *ctx, uint8_t *dst, size_t dst_len, const uint8_t *src, size_t src_len) {
    if (inflateReset(&ctx->zs) != Z_OK) {
        fprintf(stderr, "inflateReset failed\n");
        exit(1);
    }
    ctx->zs.next_in = (Bytef *)src;
    ctx->zs.avail_in = (uInt)src_len;
    ctx->zs.next_out = dst;
    ctx->zs.avail_out = (uInt)dst_len;
    int status = inflate(&ctx->zs, Z_FINISH);
    if (status != Z_STREAM_END || ctx->zs.total_out != dst_len) {
        fprintf(stderr, "inflate failed (%d), produced %lu of %zu bytes\n",
                status, (unsigned long)ctx->zs.total_out, dst_len);
        exit(1);
    }
}

typedef struct {
    ZSTD_DCtx *ctx;
} ZstdCtx;

static void zstd_ctx_init(ZstdCtx *ctx) {
    ctx->ctx = ZSTD_createDCtx();
    if (!ctx->ctx) {
        fprintf(stderr, "ZSTD_createDCtx failed\n");
        exit(1);
    }
}

static void zstd_ctx_free(ZstdCtx *ctx) {
    ZSTD_freeDCtx(ctx->ctx);
}

static void zstd_into(ZstdCtx *ctx, uint8_t *dst, size_t dst_len, const uint8_t *src, size_t src_len) {
    size_t out = ZSTD_decompressDCtx(ctx->ctx, dst, dst_len, src, src_len);
    if (ZSTD_isError(out) || out != dst_len) {
        fprintf(stderr, "zstd decompress failed: %s (%zu of %zu bytes)\n",
                ZSTD_isError(out) ? ZSTD_getErrorName(out) : "short decode",
                out, dst_len);
        exit(1);
    }
}

static void decode_zero_runs(uint8_t *dst, size_t dst_len, const uint8_t *src, size_t src_len) {
    size_t in = 0;
    size_t out = 0;
    while (in < src_len) {
        if (in + 2 >= src_len) {
            fprintf(stderr, "truncated zero-run stream\n");
            exit(1);
        }
        uint8_t tag = src[in++];
        size_t run = (size_t)src[in] | ((size_t)src[in + 1] << 8);
        in += 2;
        if (tag == 0) {
            if (out + run > dst_len) {
                fprintf(stderr, "zero-run decode overflow\n");
                exit(1);
            }
            memset(dst + out, 0, run);
            out += run;
            continue;
        }
        if (tag != 1 || in + run > src_len || out + run > dst_len) {
            fprintf(stderr, "zero-run decode overflow\n");
            exit(1);
        }
        memcpy(dst + out, src + in, run);
        in += run;
        out += run;
    }
    if (out != dst_len) {
        fprintf(stderr, "zero-run decode underflow (%zu of %zu bytes)\n", out, dst_len);
        exit(1);
    }
}

static void verify_fixture(const SlabFixture *fixture) {
    uint8_t *whole = mmap(NULL, fixture->slab_bytes, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANON, -1, 0);
    uint8_t *live = mmap(NULL, fixture->slab_bytes, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANON, -1, 0);
    uint8_t *zlib_whole = mmap(NULL, fixture->slab_bytes, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANON, -1, 0);
    uint8_t *zlib_compact = mmap(NULL, fixture->slab_bytes, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANON, -1, 0);
    uint8_t *zstd_whole = mmap(NULL, fixture->slab_bytes, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANON, -1, 0);
    uint8_t *zstd_compact = mmap(NULL, fixture->slab_bytes, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANON, -1, 0);
    uint8_t *zr_whole = mmap(NULL, fixture->slab_bytes, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANON, -1, 0);
    uint8_t *zr_compact = mmap(NULL, fixture->slab_bytes, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANON, -1, 0);
    uint8_t *scratch_zlib = malloc(fixture->compact_bytes);
    uint8_t *scratch_zstd = malloc(fixture->compact_bytes);
    uint8_t *scratch_zr = malloc(fixture->compact_bytes);
    GunzipCtx gz_full_ctx, gz_compact_ctx;
    ZstdCtx zstd_full_ctx, zstd_compact_ctx;

    if (whole == MAP_FAILED || live == MAP_FAILED ||
        zlib_whole == MAP_FAILED || zlib_compact == MAP_FAILED ||
        zstd_whole == MAP_FAILED || zstd_compact == MAP_FAILED ||
        zr_whole == MAP_FAILED || zr_compact == MAP_FAILED ||
        !scratch_zlib || !scratch_zstd || !scratch_zr) {
        fprintf(stderr, "mmap failed during verification\n");
        exit(1);
    }
    gunzip_ctx_init(&gz_full_ctx);
    gunzip_ctx_init(&gz_compact_ctx);
    zstd_ctx_init(&zstd_full_ctx);
    zstd_ctx_init(&zstd_compact_ctx);

    copy_whole_blob(whole, fixture->blob, fixture->total_slots);
    decode_compact_stream(live, fixture->compact, fixture->plan, fixture->plan_len);
    gunzip_into(&gz_full_ctx, zlib_whole, fixture->slab_bytes, fixture->zlib_blob, fixture->zlib_blob_bytes);
    gunzip_into(&gz_compact_ctx, scratch_zlib, fixture->compact_bytes, fixture->zlib_compact, fixture->zlib_compact_bytes);
    decode_compact_stream(zlib_compact, scratch_zlib, fixture->plan, fixture->plan_len);
    zstd_into(&zstd_full_ctx, zstd_whole, fixture->slab_bytes, fixture->zstd_blob, fixture->zstd_blob_bytes);
    zstd_into(&zstd_compact_ctx, scratch_zstd, fixture->compact_bytes, fixture->zstd_compact, fixture->zstd_compact_bytes);
    decode_compact_stream(zstd_compact, scratch_zstd, fixture->plan, fixture->plan_len);
    decode_zero_runs(zr_whole, fixture->slab_bytes, fixture->zerorun_blob, fixture->zerorun_blob_bytes);
    decode_zero_runs(scratch_zr, fixture->compact_bytes, fixture->zerorun_compact, fixture->zerorun_compact_bytes);
    decode_compact_stream(zr_compact, scratch_zr, fixture->plan, fixture->plan_len);

    if (memcmp(whole, live, fixture->slab_bytes) != 0 ||
        memcmp(whole, zlib_whole, fixture->slab_bytes) != 0 ||
        memcmp(whole, zlib_compact, fixture->slab_bytes) != 0 ||
        memcmp(whole, zstd_whole, fixture->slab_bytes) != 0 ||
        memcmp(whole, zstd_compact, fixture->slab_bytes) != 0 ||
        memcmp(whole, zr_whole, fixture->slab_bytes) != 0 ||
        memcmp(whole, zr_compact, fixture->slab_bytes) != 0) {
        fprintf(stderr, "copy strategies produced different slab bytes for %s\n", fixture->name);
        exit(1);
    }

    munmap(whole, fixture->slab_bytes);
    munmap(live, fixture->slab_bytes);
    munmap(zlib_whole, fixture->slab_bytes);
    munmap(zlib_compact, fixture->slab_bytes);
    munmap(zstd_whole, fixture->slab_bytes);
    munmap(zstd_compact, fixture->slab_bytes);
    munmap(zr_whole, fixture->slab_bytes);
    munmap(zr_compact, fixture->slab_bytes);
    gunzip_ctx_free(&gz_full_ctx);
    gunzip_ctx_free(&gz_compact_ctx);
    zstd_ctx_free(&zstd_full_ctx);
    zstd_ctx_free(&zstd_compact_ctx);
    free(scratch_zlib);
    free(scratch_zstd);
    free(scratch_zr);
}

static double bench_whole_blob_memcpy(const SlabFixture *fixture, int64_t iters) {
    struct timespec start, end;
    clock_gettime(CLOCK_MONOTONIC, &start);

    for (int64_t i = 0; i < iters; i++) {
        uint8_t *dst = mmap(NULL, fixture->slab_bytes, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANON, -1, 0);
        if (dst == MAP_FAILED) {
            fprintf(stderr, "mmap failed during benchmark\n");
            exit(1);
        }

        copy_whole_blob(dst, fixture->blob, fixture->total_slots);
        g_sink += dst[W_SLAB_SLOT_SIZE + 8];
        g_sink += dst[fixture->slab_bytes - 1];
        munmap(dst, fixture->slab_bytes);
    }

    clock_gettime(CLOCK_MONOTONIC, &end);
    double elapsed = (end.tv_sec - start.tv_sec) + (end.tv_nsec - start.tv_nsec) / 1e9;
    return iters / elapsed;
}

static double bench_compact_decode(const SlabFixture *fixture, int64_t iters) {
    struct timespec start, end;
    clock_gettime(CLOCK_MONOTONIC, &start);

    for (int64_t i = 0; i < iters; i++) {
        uint8_t *dst = mmap(NULL, fixture->slab_bytes, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANON, -1, 0);
        if (dst == MAP_FAILED) {
            fprintf(stderr, "mmap failed during benchmark\n");
            exit(1);
        }

        decode_compact_stream(dst, fixture->compact, fixture->plan, fixture->plan_len);
        g_sink += dst[W_SLAB_SLOT_SIZE + 8];
        g_sink += dst[fixture->slab_bytes - 1];
        munmap(dst, fixture->slab_bytes);
    }

    clock_gettime(CLOCK_MONOTONIC, &end);
    double elapsed = (end.tv_sec - start.tv_sec) + (end.tv_nsec - start.tv_nsec) / 1e9;
    return iters / elapsed;
}

static double bench_zlib_whole_blob(const SlabFixture *fixture, int64_t iters) {
    GunzipCtx ctx;
    gunzip_ctx_init(&ctx);
    struct timespec start, end;
    clock_gettime(CLOCK_MONOTONIC, &start);

    for (int64_t i = 0; i < iters; i++) {
        uint8_t *dst = mmap(NULL, fixture->slab_bytes, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANON, -1, 0);
        if (dst == MAP_FAILED) {
            fprintf(stderr, "mmap failed during benchmark\n");
            exit(1);
        }

        gunzip_into(&ctx, dst, fixture->slab_bytes, fixture->zlib_blob, fixture->zlib_blob_bytes);
        g_sink += dst[W_SLAB_SLOT_SIZE + 8];
        g_sink += dst[fixture->slab_bytes - 1];
        munmap(dst, fixture->slab_bytes);
    }

    clock_gettime(CLOCK_MONOTONIC, &end);
    gunzip_ctx_free(&ctx);
    double elapsed = (end.tv_sec - start.tv_sec) + (end.tv_nsec - start.tv_nsec) / 1e9;
    return iters / elapsed;
}

static double bench_zlib_compact_decode(const SlabFixture *fixture, int64_t iters) {
    uint8_t *scratch = malloc(fixture->compact_bytes);
    GunzipCtx ctx;
    if (!scratch) {
        fprintf(stderr, "failed to allocate zlib compact scratch buffer\n");
        exit(1);
    }
    gunzip_ctx_init(&ctx);

    struct timespec start, end;
    clock_gettime(CLOCK_MONOTONIC, &start);

    for (int64_t i = 0; i < iters; i++) {
        uint8_t *dst = mmap(NULL, fixture->slab_bytes, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANON, -1, 0);
        if (dst == MAP_FAILED) {
            fprintf(stderr, "mmap failed during benchmark\n");
            exit(1);
        }

        gunzip_into(&ctx, scratch, fixture->compact_bytes, fixture->zlib_compact, fixture->zlib_compact_bytes);
        decode_compact_stream(dst, scratch, fixture->plan, fixture->plan_len);
        g_sink += dst[W_SLAB_SLOT_SIZE + 8];
        g_sink += dst[fixture->slab_bytes - 1];
        munmap(dst, fixture->slab_bytes);
    }

    clock_gettime(CLOCK_MONOTONIC, &end);
    gunzip_ctx_free(&ctx);
    free(scratch);
    double elapsed = (end.tv_sec - start.tv_sec) + (end.tv_nsec - start.tv_nsec) / 1e9;
    return iters / elapsed;
}

static double bench_zstd_whole_blob(const SlabFixture *fixture, int64_t iters) {
    ZstdCtx ctx;
    zstd_ctx_init(&ctx);
    struct timespec start, end;
    clock_gettime(CLOCK_MONOTONIC, &start);

    for (int64_t i = 0; i < iters; i++) {
        uint8_t *dst = mmap(NULL, fixture->slab_bytes, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANON, -1, 0);
        if (dst == MAP_FAILED) {
            fprintf(stderr, "mmap failed during benchmark\n");
            exit(1);
        }

        zstd_into(&ctx, dst, fixture->slab_bytes, fixture->zstd_blob, fixture->zstd_blob_bytes);
        g_sink += dst[W_SLAB_SLOT_SIZE + 8];
        g_sink += dst[fixture->slab_bytes - 1];
        munmap(dst, fixture->slab_bytes);
    }

    clock_gettime(CLOCK_MONOTONIC, &end);
    zstd_ctx_free(&ctx);
    double elapsed = (end.tv_sec - start.tv_sec) + (end.tv_nsec - start.tv_nsec) / 1e9;
    return iters / elapsed;
}

static double bench_zstd_compact_decode(const SlabFixture *fixture, int64_t iters) {
    uint8_t *scratch = malloc(fixture->compact_bytes);
    ZstdCtx ctx;
    if (!scratch) {
        fprintf(stderr, "failed to allocate zstd compact scratch buffer\n");
        exit(1);
    }
    zstd_ctx_init(&ctx);

    struct timespec start, end;
    clock_gettime(CLOCK_MONOTONIC, &start);

    for (int64_t i = 0; i < iters; i++) {
        uint8_t *dst = mmap(NULL, fixture->slab_bytes, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANON, -1, 0);
        if (dst == MAP_FAILED) {
            fprintf(stderr, "mmap failed during benchmark\n");
            exit(1);
        }

        zstd_into(&ctx, scratch, fixture->compact_bytes, fixture->zstd_compact, fixture->zstd_compact_bytes);
        decode_compact_stream(dst, scratch, fixture->plan, fixture->plan_len);
        g_sink += dst[W_SLAB_SLOT_SIZE + 8];
        g_sink += dst[fixture->slab_bytes - 1];
        munmap(dst, fixture->slab_bytes);
    }

    clock_gettime(CLOCK_MONOTONIC, &end);
    zstd_ctx_free(&ctx);
    free(scratch);
    double elapsed = (end.tv_sec - start.tv_sec) + (end.tv_nsec - start.tv_nsec) / 1e9;
    return iters / elapsed;
}

static double bench_zerorun_whole_blob(const SlabFixture *fixture, int64_t iters) {
    struct timespec start, end;
    clock_gettime(CLOCK_MONOTONIC, &start);

    for (int64_t i = 0; i < iters; i++) {
        uint8_t *dst = mmap(NULL, fixture->slab_bytes, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANON, -1, 0);
        if (dst == MAP_FAILED) {
            fprintf(stderr, "mmap failed during benchmark\n");
            exit(1);
        }

        decode_zero_runs(dst, fixture->slab_bytes, fixture->zerorun_blob, fixture->zerorun_blob_bytes);
        g_sink += dst[W_SLAB_SLOT_SIZE + 8];
        g_sink += dst[fixture->slab_bytes - 1];
        munmap(dst, fixture->slab_bytes);
    }

    clock_gettime(CLOCK_MONOTONIC, &end);
    double elapsed = (end.tv_sec - start.tv_sec) + (end.tv_nsec - start.tv_nsec) / 1e9;
    return iters / elapsed;
}

static double bench_zerorun_compact_decode(const SlabFixture *fixture, int64_t iters) {
    uint8_t *scratch = malloc(fixture->compact_bytes);
    if (!scratch) {
        fprintf(stderr, "failed to allocate zero-run compact scratch buffer\n");
        exit(1);
    }

    struct timespec start, end;
    clock_gettime(CLOCK_MONOTONIC, &start);

    for (int64_t i = 0; i < iters; i++) {
        uint8_t *dst = mmap(NULL, fixture->slab_bytes, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANON, -1, 0);
        if (dst == MAP_FAILED) {
            fprintf(stderr, "mmap failed during benchmark\n");
            exit(1);
        }

        decode_zero_runs(scratch, fixture->compact_bytes, fixture->zerorun_compact, fixture->zerorun_compact_bytes);
        decode_compact_stream(dst, scratch, fixture->plan, fixture->plan_len);
        g_sink += dst[W_SLAB_SLOT_SIZE + 8];
        g_sink += dst[fixture->slab_bytes - 1];
        munmap(dst, fixture->slab_bytes);
    }

    clock_gettime(CLOCK_MONOTONIC, &end);
    free(scratch);
    double elapsed = (end.tv_sec - start.tv_sec) + (end.tv_nsec - start.tv_nsec) / 1e9;
    return iters / elapsed;
}

static void print_result(const char *label, double inits_per_sec, int64_t iters) {
    double elapsed_ms = (double)iters * 1000.0 / inits_per_sec;
    printf("  %-24s %12.0f init/s  (%7.3f ms)\n", label, inits_per_sec, elapsed_ms);
}

static void run_case(const SlabFixture *fixture, int64_t iters) {
    double used_pct = fixture->slab_bytes == 0 ? 0.0 : (100.0 * (double)fixture->live_bytes / (double)fixture->slab_bytes);
    printf("\n%s\n", fixture->name);
    printf("  entries: %-6u  slots: %-6u  slab: %7zu B  compact: %7zu B (%.1f%%)\n",
           fixture->entry_count,
           fixture->total_slots,
           fixture->slab_bytes,
           fixture->compact_bytes,
           used_pct);
    printf("  zlib(full):   %7zu B (%.1f%% of slab)\n",
           fixture->zlib_blob_bytes,
           100.0 * (double)fixture->zlib_blob_bytes / (double)fixture->slab_bytes);
    printf("  zlib(compact):%7zu B (%.1f%% of slab, %.1f%% of compact)\n",
           fixture->zlib_compact_bytes,
           100.0 * (double)fixture->zlib_compact_bytes / (double)fixture->slab_bytes,
           100.0 * (double)fixture->zlib_compact_bytes / (double)fixture->compact_bytes);
    printf("  zstd(full):   %7zu B (%.1f%% of slab)\n",
           fixture->zstd_blob_bytes,
           100.0 * (double)fixture->zstd_blob_bytes / (double)fixture->slab_bytes);
    printf("  zstd(compact):%7zu B (%.1f%% of slab, %.1f%% of compact)\n",
           fixture->zstd_compact_bytes,
           100.0 * (double)fixture->zstd_compact_bytes / (double)fixture->slab_bytes,
           100.0 * (double)fixture->zstd_compact_bytes / (double)fixture->compact_bytes);
    printf("  zr(full):     %7zu B (%.1f%% of slab)\n",
           fixture->zerorun_blob_bytes,
           100.0 * (double)fixture->zerorun_blob_bytes / (double)fixture->slab_bytes);
    printf("  zr(compact):  %7zu B (%.1f%% of slab, %.1f%% of compact)\n",
           fixture->zerorun_compact_bytes,
           100.0 * (double)fixture->zerorun_compact_bytes / (double)fixture->slab_bytes,
           100.0 * (double)fixture->zerorun_compact_bytes / (double)fixture->compact_bytes);

    verify_fixture(fixture);

    double raw_full = bench_whole_blob_memcpy(fixture, iters);
    double raw_compact = bench_compact_decode(fixture, iters);
    double zlib_full = bench_zlib_whole_blob(fixture, iters);
    double zlib_compact = bench_zlib_compact_decode(fixture, iters);
    double zstd_full = bench_zstd_whole_blob(fixture, iters);
    double zstd_compact = bench_zstd_compact_decode(fixture, iters);
    double zr_full = bench_zerorun_whole_blob(fixture, iters);
    double zr_compact = bench_zerorun_compact_decode(fixture, iters);

    print_result("whole-blob memcpy", raw_full, iters);
    print_result("compact decode", raw_compact, iters);
    print_result("zlib(full) inflate", zlib_full, iters);
    print_result("zlib(compact) decode", zlib_compact, iters);
    print_result("zstd(full) inflate", zstd_full, iters);
    print_result("zstd(compact) decode", zstd_compact, iters);
    print_result("zr(full) decode", zr_full, iters);
    print_result("zr(compact) decode", zr_compact, iters);

    double best = raw_full;
    const char *winner = "whole-blob memcpy";
    if (raw_compact > best) { best = raw_compact; winner = "compact decode"; }
    if (zlib_full > best) { best = zlib_full; winner = "zlib(full) inflate"; }
    if (zlib_compact > best) { best = zlib_compact; winner = "zlib(compact) decode"; }
    if (zstd_full > best) { best = zstd_full; winner = "zstd(full) inflate"; }
    if (zstd_compact > best) { best = zstd_compact; winner = "zstd(compact) decode"; }
    if (zr_full > best) { best = zr_full; winner = "zr(full) decode"; }
    if (zr_compact > best) { best = zr_compact; winner = "zr(compact) decode"; }

    printf("  winner: %s\n", winner);
}

int main(int argc, char **argv) {
    uint32_t entry_count = 1356;
    int64_t iters = 5000;

    if (argc >= 2) iters = atoll(argv[1]);
    if (argc >= 3) entry_count = (uint32_t)strtoul(argv[2], NULL, 10);

    printf("String slab init benchmark (existing slab format)\n");
    printf("  iters: %lld  entries: %u\n", (long long)iters, entry_count);

    SlabFixture small = build_fixture("SSO-21 heavy (all 1-slot)", entry_count, LENGTHS_SMALL);
    SlabFixture mixed = build_fixture("Mixed (75% 1-slot, 25% 2-slot)", entry_count, LENGTHS_MIXED);
    SlabFixture large = build_fixture("SSO-53 heavy (all 2-slot)", entry_count, LENGTHS_LARGE);

    run_case(&small, iters);
    run_case(&mixed, iters);
    run_case(&large, iters);

    destroy_fixture(&small);
    destroy_fixture(&mixed);
    destroy_fixture(&large);

    if (g_sink == 0xdeadbeefULL) {
        printf("sink=%llu\n", (unsigned long long)g_sink);
    }

    return 0;
}
