/*
 * Compare today's dynamic String construction with a hypothetical exact-
 * length, seven-character printable-ASCII immediate encoding.
 *
 * The proposed encoding is deliberately kept out of WValue: printable ASCII
 * has 95 symbols, and 95^7 fits in 46 bits.  This benchmark measures the
 * required validation and base-95 packing without assigning an ABI tag.
 *
 * Run from the repository root:
 *
 *   make -C runtime bench-string-encoding
 */

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#include "runtime.c"

#define INPUT_COUNT 4096
#define SAMPLE_COUNT 9

_Static_assert(69833729609375ULL < (1ULL << 46),
               "95^7 must fit in the proposed 46-bit payload");

typedef struct {
    char bytes[INPUT_COUNT][16];
    uint8_t lengths[INPUT_COUNT];
    WValue values[INPUT_COUNT];
    uint64_t packed[INPUT_COUNT];
} StringInputs;

typedef void (*BenchLoop)(void *opaque, int iterations);

static volatile uint64_t bench_sink;

static uint64_t now_ns(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (uint64_t)ts.tv_sec * 1000000000ULL + (uint64_t)ts.tv_nsec;
}

static int compare_double(const void *lhs, const void *rhs) {
    double a = *(const double *)lhs;
    double b = *(const double *)rhs;
    return a < b ? -1 : a > b;
}

static double bench_once(BenchLoop loop, void *context, int iterations) {
    uint64_t start = now_ns();
    loop(context, iterations);
    return (double)(now_ns() - start) / (double)iterations;
}

static void report_pair(const char *label, const char *left_name,
                        BenchLoop left, const char *right_name,
                        BenchLoop right, void *context, int iterations) {
    double lhs[SAMPLE_COUNT], rhs[SAMPLE_COUNT];
    left(context, iterations / 16);
    right(context, iterations / 16);
    for (int sample = 0; sample < SAMPLE_COUNT; sample++) {
        if (sample & 1) {
            rhs[sample] = bench_once(right, context, iterations);
            lhs[sample] = bench_once(left, context, iterations);
        } else {
            lhs[sample] = bench_once(left, context, iterations);
            rhs[sample] = bench_once(right, context, iterations);
        }
    }
    qsort(lhs, SAMPLE_COUNT, sizeof(lhs[0]), compare_double);
    qsort(rhs, SAMPLE_COUNT, sizeof(rhs[0]), compare_double);
    printf("%-34s %-12s %8.2f ns  %-12s %8.2f ns  ratio %6.2fx\n",
           label, left_name, lhs[SAMPLE_COUNT / 2], right_name,
           rhs[SAMPLE_COUNT / 2],
           lhs[SAMPLE_COUNT / 2] / rhs[SAMPLE_COUNT / 2]);
}

static void report_triple(const char *label,
                          const char *first_name, BenchLoop first,
                          void *first_context,
                          const char *second_name, BenchLoop second,
                          void *second_context,
                          const char *third_name, BenchLoop third,
                          void *third_context, int iterations) {
    double one[SAMPLE_COUNT], two[SAMPLE_COUNT], three[SAMPLE_COUNT];
    first(first_context, iterations / 16);
    second(second_context, iterations / 16);
    third(third_context, iterations / 16);
    for (int sample = 0; sample < SAMPLE_COUNT; sample++) {
        switch (sample % 3) {
        case 0:
            one[sample] = bench_once(first, first_context, iterations);
            two[sample] = bench_once(second, second_context, iterations);
            three[sample] = bench_once(third, third_context, iterations);
            break;
        case 1:
            two[sample] = bench_once(second, second_context, iterations);
            three[sample] = bench_once(third, third_context, iterations);
            one[sample] = bench_once(first, first_context, iterations);
            break;
        default:
            three[sample] = bench_once(third, third_context, iterations);
            one[sample] = bench_once(first, first_context, iterations);
            two[sample] = bench_once(second, second_context, iterations);
            break;
        }
    }
    qsort(one, SAMPLE_COUNT, sizeof(one[0]), compare_double);
    qsort(two, SAMPLE_COUNT, sizeof(two[0]), compare_double);
    qsort(three, SAMPLE_COUNT, sizeof(three[0]), compare_double);
    printf("%-34s %-13s %8.2f ns  %-13s %8.2f ns  %-13s %8.2f ns\n",
           label,
           first_name, one[SAMPLE_COUNT / 2],
           second_name, two[SAMPLE_COUNT / 2],
           third_name, three[SAMPLE_COUNT / 2]);
}

/* Exact seven-byte printable-ASCII encoding.  There is no length field: the
 * hypothetical WValue subtype itself means exactly seven characters. */
static inline uint64_t pack_printable_ascii7(const char *bytes) {
    uint64_t payload = 0;
    for (int i = 0; i < 7; i++) {
        unsigned char byte = (unsigned char)bytes[i];
        if (byte < 0x20 || byte > 0x7e) return UINT64_MAX;
        payload = payload * 95u + (uint64_t)(byte - 0x20);
    }
    return payload;
}

static inline uint64_t unpack_printable_ascii7_sum(uint64_t payload) {
    uint64_t sum = 0;
    for (int i = 0; i < 7; i++) {
        sum += 0x20u + payload % 95u;
        payload /= 95u;
    }
    return sum;
}

static inline void unpack_printable_ascii7(uint64_t payload, char out[7]) {
    for (int i = 6; i >= 0; i--) {
        out[i] = (char)(0x20u + payload % 95u);
        payload /= 95u;
    }
}

static void fill_base95(char *out, int length, uint64_t value) {
    for (int i = length - 1; i >= 0; i--) {
        out[i] = (char)(0x20 + value % 95u);
        value /= 95u;
    }
    out[length] = '\0';
}

static size_t append_utf8_2(char *out, uint32_t codepoint) {
    out[0] = (char)(0xc0u | (codepoint >> 6));
    out[1] = (char)(0x80u | (codepoint & 0x3fu));
    return 2;
}

static uint64_t mix_input(uint64_t value) {
    value += 0x9e3779b97f4a7c15ULL;
    value = (value ^ (value >> 30)) * 0xbf58476d1ce4e5b9ULL;
    value = (value ^ (value >> 27)) * 0x94d049bb133111ebULL;
    return value ^ (value >> 31);
}

static void init_ascii_inputs(StringInputs *inputs, int length,
                              uint64_t first_value, int preintern) {
    memset(inputs, 0, sizeof(*inputs));
    for (int i = 0; i < INPUT_COUNT; i++) {
        fill_base95(inputs->bytes[i], length,
                    mix_input(first_value + (uint64_t)i));
        inputs->lengths[i] = (uint8_t)length;
        if (length == 7)
            inputs->packed[i] = pack_printable_ascii7(inputs->bytes[i]);
        if (preintern)
            inputs->values[i] = w_string_n(inputs->bytes[i], (size_t)length);
    }
}

static void init_unicode_inputs(StringInputs *inputs, int codepoints,
                                uint64_t first_value, int preintern) {
    memset(inputs, 0, sizeof(*inputs));
    for (int i = 0; i < INPUT_COUNT; i++) {
        uint64_t value = mix_input(first_value + (uint64_t)i);
        size_t offset = 0;
        for (int cp = 0; cp < codepoints; cp++) {
            /* U+00A1..U+04A0: all encode in exactly two UTF-8 bytes. */
            uint32_t digit = (uint32_t)(value & 1023u);
            value >>= 10;
            offset += append_utf8_2(inputs->bytes[i] + offset, 0x00a1u + digit);
        }
        inputs->bytes[i][offset] = '\0';
        inputs->lengths[i] = (uint8_t)offset;
        if (preintern)
            inputs->values[i] = w_string_n(inputs->bytes[i], offset);
    }
}

static void loop_string_construct(void *opaque, int iterations) {
    StringInputs *inputs = opaque;
    for (int i = 0; i < iterations; i++) {
        unsigned index = (unsigned)i & (INPUT_COUNT - 1);
        WValue value = w_string_n(inputs->bytes[index], inputs->lengths[index]);
        bench_sink ^= (uint64_t)value + (uint64_t)index;
    }
}

static void loop_string_construct_and_free(void *opaque, int iterations) {
    StringInputs *inputs = opaque;
    for (int i = 0; i < iterations; i++) {
        unsigned index = (unsigned)i & (INPUT_COUNT - 1);
        WValue value = w_string_n(inputs->bytes[index], inputs->lengths[index]);
        bench_sink ^= (uint64_t)value + (uint64_t)index;
        w_value_free(value);
    }
}

static void loop_pack_ascii7(void *opaque, int iterations) {
    StringInputs *inputs = opaque;
    for (int i = 0; i < iterations; i++) {
        unsigned index = (unsigned)i & (INPUT_COUNT - 1);
        bench_sink ^= pack_printable_ascii7(inputs->bytes[index]) + index;
    }
}

static void loop_read_slab_ascii7(void *opaque, int iterations) {
    StringInputs *inputs = opaque;
    for (int i = 0; i < iterations; i++) {
        unsigned index = (unsigned)i & (INPUT_COUNT - 1);
        char inline_buf[6];
        const char *bytes;
        size_t len;
        w_str_data(inputs->values[index], inline_buf, &bytes, &len);
        uint64_t sum = len;
        for (int byte = 0; byte < 7; byte++)
            sum += (unsigned char)bytes[byte];
        bench_sink ^= sum + index;
    }
}

static void loop_decode_ascii7(void *opaque, int iterations) {
    StringInputs *inputs = opaque;
    for (int i = 0; i < iterations; i++) {
        unsigned index = (unsigned)i & (INPUT_COUNT - 1);
        bench_sink ^= unpack_printable_ascii7_sum(inputs->packed[index]) + index;
    }
}

/* A puts-like sink without stdio locking, buffering, or terminal I/O. Each
 * lane constructs its representation, materializes the exact output bytes
 * plus newline, and pays this identical byte-consumption cost. */
__attribute__((noinline))
static void puts_like_consume(const char *bytes, size_t length) {
    uint64_t sum = length;
    for (size_t i = 0; i < length; i++)
        sum = (sum * 257u) ^ (unsigned char)bytes[i];
    bench_sink ^= sum;
}

static void loop_pack_render_ascii7(void *opaque, int iterations) {
    StringInputs *inputs = opaque;
    for (int i = 0; i < iterations; i++) {
        unsigned index = (unsigned)i & (INPUT_COUNT - 1);
        uint64_t packed = pack_printable_ascii7(inputs->bytes[index]);
        char rendered[8];
        unpack_printable_ascii7(packed, rendered);
        rendered[7] = '\n';
        puts_like_consume(rendered, sizeof(rendered));
    }
}

static void loop_copy_render_ascii7(void *opaque, int iterations) {
    StringInputs *inputs = opaque;
    for (int i = 0; i < iterations; i++) {
        unsigned index = (unsigned)i & (INPUT_COUNT - 1);
        char rendered[8];
        memcpy(rendered, inputs->bytes[index], 7);
        rendered[7] = '\n';
        puts_like_consume(rendered, sizeof(rendered));
    }
}

static void loop_copy_render_unicode7(void *opaque, int iterations) {
    StringInputs *inputs = opaque;
    for (int i = 0; i < iterations; i++) {
        unsigned index = (unsigned)i & (INPUT_COUNT - 1);
        char rendered[16];
        size_t length = inputs->lengths[index];
        memcpy(rendered, inputs->bytes[index], length);
        rendered[length] = '\n';
        puts_like_consume(rendered, length + 1);
    }
}

typedef struct {
    StringInputs *left;
    StringInputs *right;
} InputPair;

static void loop_pair_left(void *opaque, int iterations) {
    InputPair *pair = opaque;
    loop_string_construct(pair->left, iterations);
}

static void loop_pair_right(void *opaque, int iterations) {
    InputPair *pair = opaque;
    loop_string_construct(pair->right, iterations);
}

static void loop_pair_left_free(void *opaque, int iterations) {
    InputPair *pair = opaque;
    loop_string_construct_and_free(pair->left, iterations);
}

static void loop_pair_right_free(void *opaque, int iterations) {
    InputPair *pair = opaque;
    loop_string_construct_and_free(pair->right, iterations);
}

static void report_probe_stats(const char *label, const StringInputs *inputs) {
    uint64_t total = 0;
    uint64_t maximum = 0;
    uint64_t mask = (uint64_t)g_intern.cap - 1;
    for (int i = 0; i < INPUT_COUNT; i++) {
        size_t len = inputs->lengths[i];
        uint64_t hash = w_hash_wyhash((const uint8_t *)inputs->bytes[i], len);
        uint64_t position = hash & mask;
        uint64_t probes = 1;
        while (g_intern.indices[position] != 0) {
            if (g_intern.hashes[position] == hash &&
                w_slab_equals_bytes(g_intern.indices[position],
                                    inputs->bytes[i], len))
                break;
            position = (position + 1) & mask;
            probes++;
        }
        total += probes;
        if (probes > maximum) maximum = probes;
    }
    printf("  %-31s average probes %.3f, max %llu\n", label,
           (double)total / INPUT_COUNT, (unsigned long long)maximum);
}

int main(int argc, char **argv) {
    (void)argc;
    (void)argv;
    StringInputs ascii7_hot, ascii7_miss, ascii8_miss;
    StringInputs ascii8_hot, unicode7_hot, unicode4_hot;
    StringInputs unicode7_miss, unicode4_miss;

    /* Populate all hit sets before freezing the slab.  Rotate insertion order
     * so no character set gets systematically better linear-probe slots. */
    init_ascii_inputs(&ascii7_hot, 7, 100000, 0);
    init_ascii_inputs(&ascii8_hot, 8, 300000, 0);
    init_unicode_inputs(&unicode7_hot, 7, 100000, 0);
    init_unicode_inputs(&unicode4_hot, 4, 300000, 0);
    StringInputs *sets[] = {
        &ascii7_hot, &unicode7_hot, &ascii8_hot, &unicode4_hot
    };
    for (int i = 0; i < INPUT_COUNT; i++) {
        for (int step = 0; step < 4; step++) {
            StringInputs *inputs = sets[(i + step) & 3];
            inputs->values[i] = w_string_n(inputs->bytes[i], inputs->lengths[i]);
        }
    }

    report_probe_stats("ASCII 7 bytes", &ascii7_hot);
    report_probe_stats("Unicode 7 codepoints/14 bytes", &unicode7_hot);
    report_probe_stats("ASCII 8 bytes", &ascii8_hot);
    report_probe_stats("Unicode 4 codepoints/8 bytes", &unicode4_hot);

    puts("Dynamic construction (median of 9; -O3 -mcpu=native)");
    report_pair("7 printable ASCII, intern hit", "slab", loop_string_construct,
                "base95 SSO", loop_pack_ascii7, &ascii7_hot, 2000000);
    report_pair("7 printable ASCII, read bytes", "slab view", loop_read_slab_ascii7,
                "base95 decode", loop_decode_ascii7, &ascii7_hot, 2000000);
    report_triple("construct + puts-like render",
                  "base95/7cp", loop_pack_render_ascii7, &ascii7_hot,
                  "ASCII/7B", loop_copy_render_ascii7, &ascii7_hot,
                  "UTF-8/14B", loop_copy_render_unicode7, &unicode7_hot,
                  2000000);

    InputPair codepoint_pair = {&ascii7_hot, &unicode7_hot};
    report_pair("equal codepoints (7)", "ASCII/7B", loop_pair_left,
                "Unicode/14B", loop_pair_right, &codepoint_pair, 2000000);

    InputPair byte_pair = {&ascii8_hot, &unicode4_hot};
    report_pair("equal UTF-8 bytes (8)", "ASCII/8cp", loop_pair_left,
                "Unicode/4cp", loop_pair_right, &byte_pair, 2000000);

    /* These strings were not interned.  After freeze, every construction is
     * an intern-table miss followed by a transient heap allocation. */
    init_ascii_inputs(&ascii7_miss, 7, 9000000, 0);
    init_ascii_inputs(&ascii8_miss, 8, 9100000, 0);
    init_unicode_inputs(&unicode7_miss, 7, 9000000, 0);
    init_unicode_inputs(&unicode4_miss, 4, 9100000, 0);
    w_slab_freeze();
    report_pair("7 printable ASCII, frozen miss", "heap", loop_string_construct_and_free,
                "base95 SSO", loop_pack_ascii7, &ascii7_miss, 500000);

    InputPair miss_codepoint_pair = {&ascii7_miss, &unicode7_miss};
    report_pair("frozen, equal codepoints (7)", "ASCII/7B", loop_pair_left_free,
                "Unicode/14B", loop_pair_right_free, &miss_codepoint_pair, 500000);

    InputPair miss_byte_pair = {&ascii8_miss, &unicode4_miss};
    report_pair("frozen, equal UTF-8 bytes (8)", "ASCII/8cp", loop_pair_left_free,
                "Unicode/4cp", loop_pair_right_free, &miss_byte_pair, 500000);

    printf("sink: %llu\n", (unsigned long long)bench_sink);
    return 0;
}
