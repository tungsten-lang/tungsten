/* tostr@1 decomposition probe: where do the ~18ns of one-limb decimal
 * formatting go?  Stages:
 *
 *   full      w_int_to_s + observe data[0] + w_value_free (the lane shape)
 *   tos       bigint_to_s_boxed + free (minus the w_int_to_s dispatch)
 *   digits    the backwards pair-table digit write into a stack buffer only
 *   hash      w_hash_wyhash over the 20-byte result
 *   hashprobe hash + frozen-slab intern lookup (the guaranteed miss)
 *   mcpyfree  malloc(WString+21)+len+memcpy+free (the raw heap arm)
 *   strmk     w_string_n(buf,20) + w_value_free (hash+probe+heap composed)
 *
 * Build/run: see run_surround.sh for the link line; this file replaces
 * surround_probe.c in it.
 */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>
#include <libproc.h>
#include <sys/resource.h>

#ifndef TUNGSTEN_RUNTIME_SOURCE
#define TUNGSTEN_RUNTIME_SOURCE "../../runtime/runtime.c"
#endif
#include TUNGSTEN_RUNTIME_SOURCE

static volatile uint64_t sink;

static double now_ns(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (double)ts.tv_sec * 1e9 + (double)ts.tv_nsec;
}

static void counters(uint64_t *insts, uint64_t *cycles) {
    struct rusage_info_v4 ri;
    if (proc_pid_rusage(getpid(), RUSAGE_INFO_V4, (rusage_info_t *)&ri) == 0) {
        *insts = ri.ri_instructions;
        *cycles = ri.ri_cycles;
    } else {
        *insts = 0;
        *cycles = 0;
    }
}

#define STAGE(label, iters, reps, BODY) do {                               \
    double best = 1e30; uint64_t bi = 0, bc = 0;                           \
    for (int rep = 0; rep < (reps); rep++) {                               \
        uint64_t i0, c0, i1, c1;                                           \
        counters(&i0, &c0);                                                \
        double t0 = now_ns();                                              \
        for (int it = 0; it < (iters); it++) { BODY; }                     \
        double el = now_ns() - t0;                                         \
        counters(&i1, &c1);                                                \
        if (el < best) { best = el; bi = i1 - i0; bc = c1 - c0; }          \
    }                                                                      \
    printf("%-22s %10.2f ns/op %10.1f inst/op %9.1f cyc/op\n", (label),    \
           best / (iters), (double)bi / (iters), (double)bc / (iters));    \
    fflush(stdout);                                                        \
} while (0)

int main(int argc, char **argv) {
    (void)argc; (void)argv;

    /* Reproduce the compiled-program lifecycle exactly as bench_big_math.c
     * does: init slab, seed one literal, freeze. */
    if (!g_string_slab.base) w_slab_init();
    (void)w_string("bignum-bench");
    w_slab_freeze();

    printf("== tostr_probe: one-limb to_s decomposition ==\n");

    /* The documented bench operand(1, kSeedA^1): 20 digits, top bit set. */
    WBigint *ab = bigint_alloc(1);
    ab->limbs[0] = 10535676081691261443ULL;
    ab->size = 1;
    WValue a = bigint_box(ab);

    int I = 2000000, R = 9;

    STAGE("full lane", I, R, {
        WValue av = a;
        __asm__ volatile("" : "+r"(av));
        WValue text = w_int_to_s(av);
        sink ^= (uint64_t)(unsigned char)w_as_heap_str(text)->data[0];
        w_value_free(text);
    });

    STAGE("tos boxed", I, R, {
        WValue av = a;
        __asm__ volatile("" : "+r"(av));
        WValue text = bigint_to_s_boxed(av);
        sink ^= (uint64_t)(unsigned char)w_as_heap_str(text)->data[0];
        w_value_free(text);
    });

    STAGE("digits only", I, R, {
        uint64_t u = ab->limbs[0];
        __asm__ volatile("" : "+r"(u));
        char buf[21];
        char *end = buf + sizeof(buf);
        char *p = end;
        while (u >= 100) {
            unsigned r2 = (unsigned)(u % 100);
            u /= 100;
            *--p = w_dec_2dig[r2 * 2 + 1];
            *--p = w_dec_2dig[r2 * 2];
        }
        if (u >= 10) {
            *--p = w_dec_2dig[u * 2 + 1];
            *--p = w_dec_2dig[u * 2];
        } else {
            *--p = (char)('0' + u);
        }
        sink ^= (uint64_t)(unsigned char)p[0] ^ (uint64_t)(end - p);
    });

    /* Fixed 20-byte decimal image of the operand for the string-side stages. */
    char img[32];
    snprintf(img, sizeof img, "%llu", (unsigned long long)ab->limbs[0]);
    size_t img_len = strlen(img);
    printf("(operand has %zu digits)\n", img_len);

    STAGE("hash only", I, R, {
        const char *s = img;
        __asm__ volatile("" : "+r"(s));
        sink ^= w_hash_wyhash((const uint8_t *)s, img_len);
    });

    STAGE("hash+probe", I, R, {
        const char *s = img;
        __asm__ volatile("" : "+r"(s));
        uint64_t h = w_hash_wyhash((const uint8_t *)s, img_len);
        sink ^= (uint64_t)w_slab_lookup_existing(s, img_len, h);
    });

    STAGE("malloc+cpy+free", I, R, {
        const char *s = img;
        __asm__ volatile("" : "+r"(s));
        WString *ws = malloc(sizeof(WString) + img_len + 1);
        ws->len = (uint32_t)img_len;
        memcpy(ws->data, s, img_len);
        ws->data[img_len] = '\0';
        WValue v = w_box_heap_str(ws);
        sink ^= (uint64_t)(unsigned char)w_as_heap_str(v)->data[0];
        free(w_as_heap_str(v));
    });

    STAGE("w_string_n+free", I, R, {
        const char *s = img;
        __asm__ volatile("" : "+r"(s));
        WValue v = w_string_n(s, img_len);
        sink ^= (uint64_t)(unsigned char)w_as_heap_str(v)->data[0];
        w_value_free(v);
    });

    bigint_release_if_live(w_as_bigint(a));
    printf("sink=%llu\n", (unsigned long long)sink);
    return 0;
}
