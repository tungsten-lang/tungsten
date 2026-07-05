#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <time.h>
#include <dirent.h>
#include <sys/stat.h>

// ---- FNV-1a 64 ----
static uint64_t fnv1a64(const char *s, size_t len) {
    uint64_t h = 14695981039346656037ull;
    for (size_t i = 0; i < len; i++) h = (h ^ (uint8_t)s[i]) * 1099511628211ull;
    return h;
}

// ---- xxHash64 ----
static uint64_t xxh64(const char *input, size_t len) {
    const uint64_t P1 = 11400714785074694791ull, P2 = 14029467366897019727ull;
    const uint64_t P3 = 1609587929392839161ull,  P4 = 9650029242287828579ull;
    const uint64_t P5 = 2870177450012600261ull;
    const uint8_t *p = (const uint8_t *)input, *end = p + len;
    uint64_t h;
    if (len >= 32) {
        uint64_t v1 = 0 + P1 + P2, v2 = 0 + P2, v3 = 0, v4 = 0 - P1;
        do {
            uint64_t k;
            memcpy(&k, p, 8); v1 += k * P2; v1 = (v1 << 31) | (v1 >> 33); v1 *= P1; p += 8;
            memcpy(&k, p, 8); v2 += k * P2; v2 = (v2 << 31) | (v2 >> 33); v2 *= P1; p += 8;
            memcpy(&k, p, 8); v3 += k * P2; v3 = (v3 << 31) | (v3 >> 33); v3 *= P1; p += 8;
            memcpy(&k, p, 8); v4 += k * P2; v4 = (v4 << 31) | (v4 >> 33); v4 *= P1; p += 8;
        } while (p <= end - 32);
        h = ((v1 << 1) | (v1 >> 63)) + ((v2 << 7) | (v2 >> 57)) +
            ((v3 << 12) | (v3 >> 52)) + ((v4 << 18) | (v4 >> 46));
        v1 *= P2; v1 = (v1 << 31) | (v1 >> 33); v1 *= P1; h ^= v1; h = h * P1 + P4;
        v2 *= P2; v2 = (v2 << 31) | (v2 >> 33); v2 *= P1; h ^= v2; h = h * P1 + P4;
        v3 *= P2; v3 = (v3 << 31) | (v3 >> 33); v3 *= P1; h ^= v3; h = h * P1 + P4;
        v4 *= P2; v4 = (v4 << 31) | (v4 >> 33); v4 *= P1; h ^= v4; h = h * P1 + P4;
    } else {
        h = 0 + P5;
    }
    h += (uint64_t)len;
    while (p + 8 <= end) {
        uint64_t k; memcpy(&k, p, 8);
        k *= P2; k = (k << 31) | (k >> 33); k *= P1;
        h ^= k; h = ((h << 27) | (h >> 37)) * P1 + P4; p += 8;
    }
    while (p + 4 <= end) {
        uint32_t k32; memcpy(&k32, p, 4);
        h ^= (uint64_t)k32 * P1; h = ((h << 23) | (h >> 41)) * P2 + P3; p += 4;
    }
    while (p < end) { h ^= (*p++) * P5; h = ((h << 11) | (h >> 53)) * P1; }
    h ^= h >> 33; h *= P2; h ^= h >> 29; h *= P3; h ^= h >> 32;
    return h;
}

// ---- wyhash 64 ----
static inline uint64_t wy_read64(const uint8_t *p) { uint64_t v; memcpy(&v, p, 8); return v; }
static inline uint64_t wy_read32(const uint8_t *p) { uint32_t v; memcpy(&v, p, 4); return v; }
static inline uint64_t wy_mum(uint64_t a, uint64_t b) {
    __uint128_t r = (__uint128_t)a * b;
    return (uint64_t)(r >> 64) ^ (uint64_t)r;
}
static uint64_t wyhash64(const char *input, size_t len) {
    const uint8_t *p = (const uint8_t *)input;
    uint64_t seed = 0x74756e677374656eull;  // "tungsten"
    uint64_t a, b;
    if (len <= 8) {
        if (len >= 4) { a = wy_read32(p); b = wy_read32(p + len - 4); }
        else if (len > 0) { a = (p[0] << 16) | (p[len >> 1] << 8) | p[len - 1]; b = 0; }
        else { a = b = 0; }
    } else if (len <= 16) {
        a = wy_read64(p); b = wy_read64(p + len - 8);
    } else {
        uint64_t s0 = seed, s1 = seed;
        size_t i = 0;
        for (; i + 16 <= len; i += 16) {
            s0 = wy_mum(wy_read64(p + i) ^ 0xa0761d6478bd642full, wy_read64(p + i + 8) ^ s0);
            s1 = wy_mum(wy_read64(p + i) ^ 0xe7037ed1a0b428dbull, wy_read64(p + i + 8) ^ s1);
        }
        a = s0; b = s1;
        if (i < len) { a ^= wy_read64(p + len - 16); b ^= wy_read64(p + len - 8); }
    }
    return wy_mum(a ^ 0xa0761d6478bd642full, b ^ seed ^ (uint64_t)len);
}

// ---- SipHash-2-4 64 ----
#define SIP_ROTL(x, b) (((x) << (b)) | ((x) >> (64 - (b))))
#define SIP_ROUND \
    v0 += v1; v1 = SIP_ROTL(v1, 13); v1 ^= v0; v0 = SIP_ROTL(v0, 32); \
    v2 += v3; v3 = SIP_ROTL(v3, 16); v3 ^= v2; \
    v0 += v3; v3 = SIP_ROTL(v3, 21); v3 ^= v0; \
    v2 += v1; v1 = SIP_ROTL(v1, 17); v1 ^= v2; v2 = SIP_ROTL(v2, 32);

static uint64_t siphash24(const char *input, size_t len) {
    const uint8_t *p = (const uint8_t *)input;
    uint64_t k0 = 0x74756e677374656eull, k1 = 0x6e657473676e7574ull;  // "tungsten" + reversed
    uint64_t v0 = k0 ^ 0x736f6d6570736575ull;
    uint64_t v1 = k1 ^ 0x646f72616e646f6dull;
    uint64_t v2 = k0 ^ 0x6c7967656e657261ull;
    uint64_t v3 = k1 ^ 0x7465646279746573ull;
    size_t left = len & 7;
    const uint8_t *end = p + len - left;
    while (p < end) {
        uint64_t m; memcpy(&m, p, 8);
        v3 ^= m; SIP_ROUND; SIP_ROUND; v0 ^= m;
        p += 8;
    }
    uint64_t b = (uint64_t)len << 56;
    switch (left) {
        case 7: b |= (uint64_t)p[6] << 48; /* fall through */
        case 6: b |= (uint64_t)p[5] << 40; /* fall through */
        case 5: b |= (uint64_t)p[4] << 32; /* fall through */
        case 4: b |= (uint64_t)p[3] << 24; /* fall through */
        case 3: b |= (uint64_t)p[2] << 16; /* fall through */
        case 2: b |= (uint64_t)p[1] << 8;  /* fall through */
        case 1: b |= (uint64_t)p[0]; break;
    }
    v3 ^= b; SIP_ROUND; SIP_ROUND; v0 ^= b;
    v2 ^= 0xff; SIP_ROUND; SIP_ROUND; SIP_ROUND; SIP_ROUND;
    return v0 ^ v1 ^ v2 ^ v3;
}

// ---- AES-based hash (hardware AES-NI / ARM Crypto Extensions) ----
#if defined(__aarch64__)
#include <arm_neon.h>
__attribute__((target("+crypto")))
static uint64_t aeshash64(const char *input, size_t len) {
    const uint8_t *p = (const uint8_t *)input;
    uint8x16_t state = vdupq_n_u8(0);
    uint8x16_t seed = vreinterpretq_u8_u64(vmovq_n_u64(0x74756e677374656eull));
    state = veorq_u8(state, seed);
    // Process 16-byte blocks
    while (len >= 16) {
        uint8x16_t block = vld1q_u8(p);
        state = vaesmcq_u8(vaeseq_u8(state, block));
        p += 16; len -= 16;
    }
    // Handle tail
    if (len > 0) {
        uint8_t tail[16] = {0};
        memcpy(tail, p, len);
        tail[15] = (uint8_t)len;  // encode length in padding
        uint8x16_t block = vld1q_u8(tail);
        state = vaesmcq_u8(vaeseq_u8(state, block));
    }
    // Finalize: two more AES rounds for avalanche
    state = vaesmcq_u8(vaeseq_u8(state, seed));
    state = vaesmcq_u8(vaeseq_u8(state, seed));
    uint64_t result;
    vst1_u8((uint8_t *)&result, vget_low_u64(vreinterpretq_u64_u8(state)));
    return result;
}
#elif defined(__x86_64__)
#include <wmmintrin.h>
static uint64_t aeshash64(const char *input, size_t len) {
    const uint8_t *p = (const uint8_t *)input;
    __m128i state = _mm_setzero_si128();
    __m128i seed = _mm_set_epi64x(0, 0x74756e677374656eull);
    state = _mm_xor_si128(state, seed);
    while (len >= 16) {
        __m128i block = _mm_loadu_si128((const __m128i *)p);
        state = _mm_aesenc_si128(state, block);
        p += 16; len -= 16;
    }
    if (len > 0) {
        uint8_t tail[16] = {0};
        memcpy(tail, p, len);
        tail[15] = (uint8_t)len;
        __m128i block = _mm_loadu_si128((const __m128i *)tail);
        state = _mm_aesenc_si128(state, block);
    }
    state = _mm_aesenc_si128(state, seed);
    state = _mm_aesenc_si128(state, seed);
    uint64_t result;
    _mm_storel_epi64((__m128i *)&result, state);
    return result;
}
#endif

// ---- SHA-256 truncated to 64 bits (via CommonCrypto on macOS) ----
#ifdef __APPLE__
#include <CommonCrypto/CommonDigest.h>
static uint64_t sha256_64(const char *s, size_t len) {
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(s, (CC_LONG)len, digest);
    uint64_t h; memcpy(&h, digest, 8);
    return h;
}
#else
// Stub for non-Apple — just return 0
static uint64_t sha256_64(const char *s, size_t len) { (void)s; (void)len; return 0; }
#endif

// ---- Benchmark ----

#define ITERS 10000000

typedef uint64_t (*hash_fn)(const char *, size_t);

static double now_sec(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return ts.tv_sec + ts.tv_nsec * 1e-9;
}

static void bench(const char *name, hash_fn fn, const char *data, size_t len, int iters) {
    volatile uint64_t sink = 0;
    double t0 = now_sec();
    for (int i = 0; i < iters; i++) sink = fn(data, len);
    double t1 = now_sec();
    double ns = (t1 - t0) * 1e9 / iters;
    double gbps = (double)len * iters / (t1 - t0) / 1e9;
    printf("  %-12s %8.1f ns/call  %6.1f GB/s  (0x%016llx)\n", name, ns, gbps, (unsigned long long)sink);
}

static char *read_file(const char *path, size_t *out_len) {
    FILE *f = fopen(path, "rb");
    if (!f) return NULL;
    fseek(f, 0, SEEK_END); long sz = ftell(f); fseek(f, 0, SEEK_SET);
    char *buf = malloc(sz + 1); fread(buf, 1, sz, f); buf[sz] = '\0'; fclose(f);
    *out_len = (size_t)sz;
    return buf;
}

static void collect_w_files(const char *dir, char ***files, size_t *count, size_t *cap) {
    DIR *d = opendir(dir);
    if (!d) return;
    struct dirent *ent;
    while ((ent = readdir(d))) {
        if (ent->d_name[0] == '.') continue;
        char path[4096];
        snprintf(path, sizeof(path), "%s/%s", dir, ent->d_name);
        struct stat st;
        if (stat(path, &st) != 0) continue;
        if (S_ISDIR(st.st_mode)) { collect_w_files(path, files, count, cap); }
        else {
            size_t nlen = strlen(ent->d_name);
            if (nlen > 2 && strcmp(ent->d_name + nlen - 2, ".w") == 0) {
                if (*count >= *cap) { *cap *= 2; *files = realloc(*files, *cap * sizeof(char *)); }
                (*files)[(*count)++] = strdup(path);
            }
        }
    }
    closedir(d);
}

#define N_ALGOS 6

int main(void) {
    const char *names[N_ALGOS] = {"fnv-1a64", "xxhash64", "wyhash64", "siphash24", "aeshash", "sha256-64"};
    hash_fn fns[N_ALGOS] = {fnv1a64, xxh64, wyhash64, siphash24, aeshash64, sha256_64};

    struct { const char *label; const char *data; size_t len; int iters; } tests[128];
    int ntests = 0;

    tests[ntests++] = (typeof(tests[0])){"4B \"push\"",  "push", 4, ITERS};
    tests[ntests++] = (typeof(tests[0])){"8B \"tungsten\"", "tungsten", 8, ITERS};
    tests[ntests++] = (typeof(tests[0])){"11B \"hello world\"", "hello world", 11, ITERS};
    tests[ntests++] = (typeof(tests[0])){"43B sentence", "the quick brown fox jumps over the lazy dog", 43, ITERS};

    // Collect source files
    char **files = malloc(256 * sizeof(char *));
    size_t nfiles = 0, fcap = 256;
    collect_w_files("stages/tungsten/lib", &files, &nfiles, &fcap);
    collect_w_files("core", &files, &nfiles, &fcap);
    collect_w_files("lib", &files, &nfiles, &fcap);

    size_t total_src = 0;
    for (size_t i = 0; i < nfiles && ntests < 128; i++) {
        size_t flen; char *data = read_file(files[i], &flen);
        if (!data) continue;
        total_src += flen;
        int iters = flen > 100000 ? 10000 : flen > 10000 ? 100000 : 1000000;
        char label[128];
        const char *bn = strrchr(files[i], '/'); bn = bn ? bn + 1 : files[i];
        snprintf(label, sizeof(label), "%zuB %s", flen, bn);
        tests[ntests].label = strdup(label); tests[ntests].data = data;
        tests[ntests].len = flen; tests[ntests].iters = iters; ntests++;
    }

    printf("64-bit hash benchmark: %d tests (%zu source files, %zu total bytes)\n\n", ntests, nfiles, total_src);

    for (int t = 0; t < ntests; t++) {
        printf("%-40s\n", tests[t].label);
        for (int a = 0; a < N_ALGOS; a++)
            bench(names[a], fns[a], tests[t].data, tests[t].len, tests[t].iters);
        printf("\n");
    }

    // Bulk
    printf("--- Bulk: hash all %zu source files (%zu bytes) ---\n", nfiles, total_src);
    int bulk_iters = 10000;
    for (int a = 0; a < N_ALGOS; a++) {
        volatile uint64_t sink = 0;
        double t0 = now_sec();
        for (int iter = 0; iter < bulk_iters; iter++)
            for (int j = 4; j < ntests; j++)  // skip inline strings
                sink = fns[a](tests[j].data, tests[j].len);
        double t1 = now_sec();
        printf("  %-12s %7.1f ms  %5.1f GB/s\n", names[a], (t1 - t0) * 1000,
               (double)total_src * bulk_iters / (t1 - t0) / 1e9);
    }
    return 0;
}
