/*
 * Matched A/B benchmarks for the runtime.c optimization tranche.
 *
 * The production runtime is included directly so the benchmark can compare
 * private reference kernels and the optimized implementations in one binary.
 * Each reported value is the median of seven samples; sample order alternates
 * reference/optimized to reduce thermal and allocator-order bias.
 *
 * Run from the repository root:
 *
 *   make -C runtime bench-runtime-hotpaths
 */

#include <assert.h>
#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#include "runtime.c"

typedef void (*BenchLoop)(void *context, int iterations);

static volatile uint64_t bench_sink;

static uint64_t bench_now_ns(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (uint64_t)ts.tv_sec * 1000000000ULL + (uint64_t)ts.tv_nsec;
}

static int bench_double_compare(const void *lhs, const void *rhs) {
    double a = *(const double *)lhs;
    double b = *(const double *)rhs;
    return a < b ? -1 : a > b;
}

static double bench_once(BenchLoop fn, void *context, int iterations) {
    uint64_t start = bench_now_ns();
    fn(context, iterations);
    return (double)(bench_now_ns() - start) / (double)iterations;
}

static void bench_report_ab(const char *label, BenchLoop reference,
                            BenchLoop optimized, void *context,
                            int iterations) {
    double ref[7], opt[7];
    reference(context, iterations / 8 + 1);
    optimized(context, iterations / 8 + 1);
    for (int sample = 0; sample < 7; sample++) {
        if (sample & 1) {
            opt[sample] = bench_once(optimized, context, iterations);
            ref[sample] = bench_once(reference, context, iterations);
        } else {
            ref[sample] = bench_once(reference, context, iterations);
            opt[sample] = bench_once(optimized, context, iterations);
        }
    }
    qsort(ref, 7, sizeof(ref[0]), bench_double_compare);
    qsort(opt, 7, sizeof(opt[0]), bench_double_compare);
    printf("%-38s ref %9.2f ns  opt %9.2f ns  %6.2fx\n",
           label, ref[3], opt[3], ref[3] / opt[3]);
}

/* ---- Array concat/range-copy and fixed-result allocation ---- */

typedef struct {
    WValue lhs;
    WValue rhs;
    int from;
    int to;
} BenchArrayContext;

static WValue bench_array_concat_reference(WValue lhs, WValue rhs) {
    WArray *la = w_as_array(lhs);
    WArray *ra = w_as_array(rhs);
    WValue out = w_array_new_empty();
    for (int64_t i = 0; i < la->size; i++)
        w_array_push(out, w_array_get(lhs, w_int(i)));
    for (int64_t i = 0; i < ra->size; i++)
        w_array_push(out, w_array_get(rhs, w_int(i)));
    return out;
}

static WValue bench_array_copy_range_reference(WValue source, int from,
                                               int to) {
    WArray *array = w_as_array(source);
    if (from < 0) from += array->size;
    if (to < 0) to += array->size;
    if (from < 0) from = 0;
    to += 1;
    if (to > array->size) to = array->size;
    if (from > array->size) from = array->size;
    WValue out = w_array_new_empty();
    for (int64_t i = from; i < to; i++)
        w_array_push(out, w_array_get(source, w_int(i)));
    return out;
}

static void bench_array_concat_ref_loop(void *opaque, int iterations) {
    BenchArrayContext *context = opaque;
    for (int i = 0; i < iterations; i++) {
        WValue out = bench_array_concat_reference(context->lhs, context->rhs);
        bench_sink ^= (uint64_t)w_as_array(out)->size;
        w_value_free(out);
    }
}

static void bench_array_concat_opt_loop(void *opaque, int iterations) {
    BenchArrayContext *context = opaque;
    for (int i = 0; i < iterations; i++) {
        WValue out = w_array_concat(context->lhs, context->rhs);
        bench_sink ^= (uint64_t)w_as_array(out)->size;
        w_value_free(out);
    }
}

static void bench_array_range_ref_loop(void *opaque, int iterations) {
    BenchArrayContext *context = opaque;
    for (int i = 0; i < iterations; i++) {
        WValue out = bench_array_copy_range_reference(
            context->lhs, context->from, context->to);
        bench_sink ^= (uint64_t)w_as_array(out)->size;
        w_value_free(out);
    }
}

static void bench_array_range_opt_loop(void *opaque, int iterations) {
    BenchArrayContext *context = opaque;
    for (int i = 0; i < iterations; i++) {
        WValue out = w_array_copy_range(
            context->lhs, w_int(context->from), w_int(context->to), W_FALSE);
        bench_sink ^= (uint64_t)w_as_array(out)->size;
        w_value_free(out);
    }
}

typedef struct {
    int64_t element_bits;
    int64_t size;
} BenchAllocationContext;

static void bench_array_alloc_ref_loop(void *opaque, int iterations) {
    BenchAllocationContext *context = opaque;
    for (int i = 0; i < iterations; i++) {
        WValue out = w_array_new_uninit_sized(context->element_bits,
                                              context->size);
        bench_sink ^= (uint64_t)(uintptr_t)w_as_array(out)->slots;
        w_value_free(out);
    }
}

static void bench_array_alloc_opt_loop(void *opaque, int iterations) {
    BenchAllocationContext *context = opaque;
    for (int i = 0; i < iterations; i++) {
        WValue out = w_array_new_inline(context->element_bits, context->size);
        bench_sink ^= (uint64_t)(uintptr_t)w_as_array(out)->slots;
        w_value_free(out);
    }
}

static WValue bench_boxed_array(int size) {
    WValue value = w_array_new_inline(65, size);
    WArray *array = w_as_array(value);
    for (int i = 0; i < size; i++) array->slots[i] = w_int(i);
    return value;
}

static WValue bench_i32_array(int size) {
    WValue value = w_array_new_inline(32, size);
    WArray *array = w_as_array(value);
    for (int i = 0; i < size; i++) array_write(array, i, (uint32_t)i);
    return value;
}

/* ---- Production boxed-array arithmetic dispatch ---- */

typedef struct {
    WValue array;
} BenchArraySumContext;

__attribute__((noinline))
static WValue bench_array_sum_reference(WValue value) {
    WArray *array = w_as_array(value);
    WValue total = w_box_int(0);
    for (int32_t i = 0; i < array->size; i++)
        total = w_add(total, array_slot_load_decoded(array, i));
    return total;
}

__attribute__((noinline))
static WValue bench_array_sum_production(WValue value) {
    return w_ic_array_sum(value, NULL, 0);
}

static void bench_array_sum_ref_loop(void *opaque, int iterations) {
    BenchArraySumContext *context = opaque;
    for (int i = 0; i < iterations; i++)
        bench_sink ^= bench_array_sum_reference(context->array);
}

static void bench_array_sum_opt_loop(void *opaque, int iterations) {
    BenchArraySumContext *context = opaque;
    for (int i = 0; i < iterations; i++)
        bench_sink ^= bench_array_sum_production(context->array);
}

/* ---- Regex workspace reuse and lazy MatchData ---- */

typedef struct {
    WValue regex;
    WValue subject;
} BenchRegexContext;

static WValue bench_regex_match_fresh_workspace(WValue regex_val,
                                                WValue subject_val) {
    WRegex *rx = (WRegex *)w_as_ptr(regex_val);
    const char *subject = as_str(subject_val);
    w_regex_prepare_captures(0);
#ifdef TUNGSTEN_ONIG
    OnigRegex regex = (OnigRegex)rx->compiled;
    const OnigUChar *start = (const OnigUChar *)subject;
    const OnigUChar *end = start + strlen(subject);
    OnigRegion *region = onig_region_new();
    int rc = onig_search(regex, start, end, start, end, region,
                         ONIG_OPTION_NONE);
    if (rc >= 0) {
        w_regex_prepare_captures(region->num_regs);
        g_regex_capture_state.subject = subject_val;
        for (int i = 0; i < region->num_regs; i++)
            w_regex_store_capture(i, subject, region->beg[i], region->end[i]);
        onig_region_free(region, 1);
        return W_TRUE;
    }
    onig_region_free(region, 1);
    if (rc == ONIG_MISMATCH) return W_FALSE;
    return W_FALSE;
#else
    regex_t *regex = (regex_t *)rx->compiled;
    size_t count = regex->re_nsub + 1;
    regmatch_t *matches = calloc(count, sizeof(regmatch_t));
    int rc = regexec(regex, subject, count, matches, 0);
    if (rc == 0) {
        w_regex_prepare_captures((int)count);
        g_regex_capture_state.subject = subject_val;
        for (size_t i = 0; i < count; i++)
            if (matches[i].rm_so >= 0)
                w_regex_store_capture((int)i, subject,
                                      (int)matches[i].rm_so,
                                      (int)matches[i].rm_eo);
        free(matches);
        return W_TRUE;
    }
    free(matches);
    return W_FALSE;
#endif
}

static void bench_regex_workspace_ref_loop(void *opaque, int iterations) {
    BenchRegexContext *context = opaque;
    for (int i = 0; i < iterations; i++)
        bench_sink ^= bench_regex_match_fresh_workspace(
            context->regex, context->subject);
}

static void bench_regex_workspace_opt_loop(void *opaque, int iterations) {
    BenchRegexContext *context = opaque;
    for (int i = 0; i < iterations; i++)
        bench_sink ^= w_regex_match(context->regex, context->subject);
}

static int bench_utf8_codepoint_offset(const char *subject, int byte_offset) {
    int codepoints = 0;
    for (int i = 0; i < byte_offset; i++)
        if (((unsigned char)subject[i] & 0xC0u) != 0x80u) codepoints++;
    return codepoints;
}

static WValue bench_regex_match_data_reference_from_state(WValue regex_val) {
    WRegexCaptureState *state = &g_regex_capture_state;
    WValue subject_val = state->subject;
    const char *subject = as_str(subject_val);
    WValue groups = w_array_new_empty();
    WValue offsets = w_array_new_empty();
    for (int i = 0; i < state->count; i++) {
        WValue capture = W_NIL;
        if (state->starts[i] >= 0)
            capture = w_string_n(subject + state->starts[i],
                                 (size_t)(state->ends[i] - state->starts[i]));
        w_array_push(groups, capture);
        if (state->starts[i] < 0) {
            w_array_push(offsets, W_NIL);
            continue;
        }
        WValue span = w_array_new_empty();
        w_array_push(span, w_int(bench_utf8_codepoint_offset(
                                    subject, state->starts[i])));
        w_array_push(span, w_int(bench_utf8_codepoint_offset(
                                    subject, state->ends[i])));
        w_array_push(offsets, span);
    }
    WValue names = w_hash_new();
#ifdef TUNGSTEN_ONIG
    WRegex *rx = (WRegex *)w_as_ptr(regex_val);
    onig_foreach_name((OnigRegex)rx->compiled, w_regex_collect_name, &names);
#endif
    WRegexMatch *match = calloc(1, sizeof(WRegexMatch));
    match->subject = subject_val;
    match->groups = groups;
    match->offsets = offsets;
    match->name_to_group = names;
    return w_box_ptr(match, W_SUBTAG_REGEX_MATCH);
}

static void bench_regex_match_reference_free(WValue value) {
    WRegexMatch *match = (WRegexMatch *)w_as_ptr(value);
    WArray *groups = w_as_array(match->groups);
    WArray *offsets = w_as_array(match->offsets);
    for (int i = 0; i < groups->size; i++) w_value_free(groups->slots[i]);
    for (int i = 0; i < offsets->size; i++) w_value_free(offsets->slots[i]);
    w_value_free(match->groups);
    w_value_free(match->offsets);
    w_value_free(match->name_to_group);
    free(match);
}

static void bench_regex_data_ref_loop(void *opaque, int iterations) {
    BenchRegexContext *context = opaque;
    for (int i = 0; i < iterations; i++) {
        assert(w_regex_match(context->regex, context->subject) == W_TRUE);
        WValue match = bench_regex_match_data_reference_from_state(
            context->regex);
        bench_sink ^= (uint64_t)w_as_array(
            ((WRegexMatch *)w_as_ptr(match))->groups)->size;
        bench_regex_match_reference_free(match);
    }
}

static void bench_regex_build_ref_loop(void *opaque, int iterations) {
    BenchRegexContext *context = opaque;
    for (int i = 0; i < iterations; i++) {
        WValue match = bench_regex_match_data_reference_from_state(
            context->regex);
        bench_sink ^= (uint64_t)w_as_array(
            ((WRegexMatch *)w_as_ptr(match))->groups)->size;
        bench_regex_match_reference_free(match);
    }
}

static void bench_regex_build_opt_loop(void *opaque, int iterations) {
    BenchRegexContext *context = opaque;
    for (int i = 0; i < iterations; i++) {
        WValue match = w_regex_match_data_from_state(context->regex);
        bench_sink ^= (uint64_t)w_as_array(
            ((WRegexMatch *)w_as_ptr(match))->groups)->size;
        w_value_free(match);
    }
}

static void bench_regex_data_opt_loop(void *opaque, int iterations) {
    BenchRegexContext *context = opaque;
    for (int i = 0; i < iterations; i++) {
        WValue match = w_regex_match_data(context->regex, context->subject);
        bench_sink ^= (uint64_t)w_as_array(
            ((WRegexMatch *)w_as_ptr(match))->groups)->size;
        w_value_free(match);
    }
}

/* ---- Method-table hash guards ---- */

typedef struct {
    WMethod *table;
    int capacity;
    WValue query;
    uint64_t hash;
} BenchMethodProbeContext;

static WMethod *bench_method_probe_reference(WMethod *table, int capacity,
                                             WValue name, uint64_t hash) {
    uint64_t mask = (uint64_t)capacity - 1;
    uint64_t index = hash & mask;
    while (table[index].name != 0) {
        if (w_hash_key_eq(table[index].name, name)) return &table[index];
        index = (index + 1) & mask;
    }
    return NULL;
}

static void bench_method_probe_ref_loop(void *opaque, int iterations) {
    BenchMethodProbeContext *context = opaque;
    for (int i = 0; i < iterations; i++)
        bench_sink ^= (uintptr_t)bench_method_probe_reference(
            context->table, context->capacity, context->query, context->hash);
}

static void bench_method_probe_opt_loop(void *opaque, int iterations) {
    BenchMethodProbeContext *context = opaque;
    for (int i = 0; i < iterations; i++)
        bench_sink ^= (uintptr_t)w_method_table_probe(
            context->table, context->capacity, context->query, context->hash);
}

static WValue bench_heap_string(const char *text) {
    size_t length = strlen(text);
    WString *string = malloc(sizeof(WString) + length + 1);
    string->len = (uint32_t)length;
    memcpy(string->data, text, length + 1);
    return w_box_heap_str(string);
}

/* ---- Exact argc-two cached dispatch ---- */

typedef struct {
    WValue receiver;
    WValue name;
    WValue arg0;
    WValue arg1;
    WInlineCache generic_cache;
    WInlineCache exact_cache;
} BenchDispatchContext;

static WValue bench_dispatch_target(WValue receiver, WValue arg0,
                                    WValue arg1) {
    (void)receiver;
    return w_box_int(w_as_int(arg0) + w_as_int(arg1));
}

static void bench_dispatch_generic_loop(void *opaque, int iterations) {
    BenchDispatchContext *context = opaque;
    WValue args[2] = {context->arg0, context->arg1};
    for (int i = 0; i < iterations; i++)
        bench_sink ^= w_method_call_cached(
            context->receiver, context->name, args, 2,
            &context->generic_cache);
}

static void bench_dispatch_exact_loop(void *opaque, int iterations) {
    BenchDispatchContext *context = opaque;
    for (int i = 0; i < iterations; i++)
        bench_sink ^= w_method_call_cached_2(
            context->receiver, context->name, context->arg0, context->arg1,
            &context->exact_cache);
}

/* ---- Inline Int division/modulo ---- */

static void bench_div_reference_loop(void *opaque, int iterations) {
    (void)opaque;
    for (int i = 0; i < iterations; i++) {
        WValue a = w_box_int(1000003 + (i & 1023));
        WValue b = w_box_int(3 + (i & 7));
        bench_sink ^= w_div(a, b);
    }
}

static void bench_div_optimized_loop(void *opaque, int iterations) {
    (void)opaque;
    for (int i = 0; i < iterations; i++) {
        WValue a = w_box_int(1000003 + (i & 1023));
        WValue b = w_box_int(3 + (i & 7));
        bench_sink ^= w_div_fast(a, b);
    }
}

static void bench_mod_reference_loop(void *opaque, int iterations) {
    (void)opaque;
    for (int i = 0; i < iterations; i++) {
        WValue a = w_box_int(1000003 + (i & 1023));
        WValue b = w_box_int(3 + (i & 7));
        bench_sink ^= w_mod(a, b);
    }
}

static void bench_mod_optimized_loop(void *opaque, int iterations) {
    (void)opaque;
    for (int i = 0; i < iterations; i++) {
        WValue a = w_box_int(1000003 + (i & 1023));
        WValue b = w_box_int(3 + (i & 7));
        bench_sink ^= w_mod_fast(a, b);
    }
}

/* ---- Vector transcendental map ---- */

typedef struct {
    WValue input;
    ArrayMapOp operation;
} BenchVectorContext;

static WValue bench_array_map_scalar(WValue value, ArrayMapOp operation) {
    WArray *source = w_as_array(value);
    WValue result = w_array_new_inline(-64, source->size);
    double *output = (double *)w_as_array(result)->slots;
    for (int i = 0; i < source->size; i++) {
        double input = array_read_numeric(source, source->start + i, 0);
        switch (operation) {
            case ARRAY_MAP_COS: output[i] = cos(input); break;
            case ARRAY_MAP_SIN: output[i] = sin(input); break;
            case ARRAY_MAP_SQRT: output[i] = sqrt(input); break;
            case ARRAY_MAP_EXP: output[i] = exp(input); break;
            case ARRAY_MAP_LOG: output[i] = log(input); break;
            case ARRAY_MAP_TAN: output[i] = tan(input); break;
        }
    }
    return result;
}

static WValue bench_array_map_optimized(WValue value, ArrayMapOp operation) {
    switch (operation) {
        case ARRAY_MAP_COS: return w_array_cos_float(value);
        case ARRAY_MAP_SIN: return w_array_sin_float(value);
        case ARRAY_MAP_SQRT: return w_array_sqrt_float(value);
        case ARRAY_MAP_EXP: return w_array_exp_float(value);
        case ARRAY_MAP_LOG: return w_array_log_float(value);
        case ARRAY_MAP_TAN: return w_array_tan_float(value);
    }
    abort();
}

static void bench_vector_ref_loop(void *opaque, int iterations) {
    BenchVectorContext *context = opaque;
    for (int i = 0; i < iterations; i++) {
        WValue result = bench_array_map_scalar(context->input,
                                               context->operation);
        bench_sink ^= ((uint64_t *)w_as_array(result)->slots)[i & 1];
        w_value_free(result);
    }
}

static void bench_vector_opt_loop(void *opaque, int iterations) {
    BenchVectorContext *context = opaque;
    for (int i = 0; i < iterations; i++) {
        WValue result = bench_array_map_optimized(context->input,
                                                  context->operation);
        bench_sink ^= ((uint64_t *)w_as_array(result)->slots)[i & 1];
        w_value_free(result);
    }
}

/* ---- i8 matmul RHS packing ---- */

typedef struct {
    WValue lhs;
    WValue rhs;
    WValue m;
    WValue k;
    WValue n;
} BenchMatmulContext;

static void bench_matmul_gather_loop(void *opaque, int iterations) {
    BenchMatmulContext *context = opaque;
    for (int i = 0; i < iterations; i++) {
        WValue result = array_matmul_i8_impl(
            context->lhs, context->rhs, context->m, context->k, context->n, 0);
        bench_sink ^= (uint64_t)array_read(w_as_array(result), 0);
        w_value_free(result);
    }
}

static void bench_matmul_pack_loop(void *opaque, int iterations) {
    BenchMatmulContext *context = opaque;
    for (int i = 0; i < iterations; i++) {
        WValue result = array_matmul_i8_impl(
            context->lhs, context->rhs, context->m, context->k, context->n, 2);
        bench_sink ^= (uint64_t)array_read(w_as_array(result), 0);
        w_value_free(result);
    }
}

static void bench_matmul_production_loop(void *opaque, int iterations) {
    BenchMatmulContext *context = opaque;
    for (int i = 0; i < iterations; i++) {
        WValue result = array_matmul_i8_impl(
            context->lhs, context->rhs, context->m, context->k, context->n, 1);
        bench_sink ^= (uint64_t)array_read(w_as_array(result), 0);
        w_value_free(result);
    }
}

static void bench_matmul_case(int m, int k, int n) {
    WValue lhs = w_array_new_inline(108, (int64_t)m * k);
    WValue rhs = w_array_new_inline(108, (int64_t)k * n);
    int8_t *a = (int8_t *)w_as_array(lhs)->slots;
    int8_t *b = (int8_t *)w_as_array(rhs)->slots;
    for (int i = 0; i < m * k; i++) a[i] = (int8_t)((i * 17 + 3) % 31 - 15);
    for (int i = 0; i < k * n; i++) b[i] = (int8_t)((i * 11 + 5) % 29 - 14);
    BenchMatmulContext context = {
        lhs, rhs, w_int(m), w_int(k), w_int(n)
    };

    WValue gathered = array_matmul_i8_impl(
        lhs, rhs, context.m, context.k, context.n, 0);
    WValue packed = array_matmul_i8_impl(
        lhs, rhs, context.m, context.k, context.n, 2);
    assert(w_as_array(gathered)->size == w_as_array(packed)->size);
    assert(memcmp(w_as_array(gathered)->slots, w_as_array(packed)->slots,
                  (size_t)m * n * sizeof(uint32_t)) == 0);
    w_value_free(gathered);
    w_value_free(packed);

    char label[64];
    snprintf(label, sizeof(label), "i8 matmul %dx%dx%d", m, k, n);
    int64_t work = (int64_t)m * k * n;
    int iterations = (int)(30000000 / (work > 0 ? work : 1));
    if (iterations < 20) iterations = 20;
    if (iterations > 200000) iterations = 200000;
    bench_report_ab(label, bench_matmul_gather_loop, bench_matmul_pack_loop,
                    &context, iterations);
    w_value_free(lhs);
    w_value_free(rhs);
}

static const char *bench_vector_name(ArrayMapOp operation) {
    switch (operation) {
        case ARRAY_MAP_COS: return "cos";
        case ARRAY_MAP_SIN: return "sin";
        case ARRAY_MAP_SQRT: return "sqrt";
        case ARRAY_MAP_EXP: return "exp";
        case ARRAY_MAP_LOG: return "log";
        case ARRAY_MAP_TAN: return "tan";
    }
    return "?";
}

int main(int argc, char **argv) {
    puts("runtime hot-path matched A/B (median of 7; >1.00x is faster)");

    /* Keep individual production-path measurements cheap to repeat while a
     * tranche is being tuned; the no-argument form still runs every section. */
    if (argc == 2 && strcmp(argv[1], "--array-sum") == 0) {
        WValue values = bench_boxed_array(1024);
        BenchArraySumContext context = {values};
        assert(bench_array_sum_reference(values) ==
               bench_array_sum_production(values));
        bench_report_ab("Array#sum 1024 inline Ints",
                        bench_array_sum_ref_loop, bench_array_sum_opt_loop,
                        &context, 50000);
        w_value_free(values);
        return 0;
    }

    puts("\n[2] exact allocation + bulk-copy concat/range");
    for (int kind = 0; kind < 2; kind++) {
        int size = 1024;
        WValue lhs = kind == 0 ? bench_boxed_array(size)
                               : bench_i32_array(size);
        WValue rhs = kind == 0 ? bench_boxed_array(size)
                               : bench_i32_array(size);
        BenchArrayContext context = {lhs, rhs, size / 4, size * 3 / 4};
        char label[64];
        snprintf(label, sizeof(label), "concat %s 1024+1024",
                 kind == 0 ? "w64" : "i32");
        bench_report_ab(label, bench_array_concat_ref_loop,
                        bench_array_concat_opt_loop, &context, 20000);
        snprintf(label, sizeof(label), "range %s 513/1024",
                 kind == 0 ? "w64" : "i32");
        bench_report_ab(label, bench_array_range_ref_loop,
                        bench_array_range_opt_loop, &context, 30000);
        w_value_free(lhs);
        w_value_free(rhs);
    }

    puts("\n[3] one-allocation fixed result constructor");
    const int allocation_sizes[] = {8, 64, 256, 512, 1024, 2048, 4096};
    for (size_t i = 0; i < sizeof(allocation_sizes) / sizeof(allocation_sizes[0]); i++) {
        BenchAllocationContext context = {65, allocation_sizes[i]};
        char label[64];
        snprintf(label, sizeof(label), "fixed w64[%d]", allocation_sizes[i]);
        int iterations = allocation_sizes[i] < 100 ? 1000000
                       : allocation_sizes[i] < 1000 ? 300000 : 30000;
        bench_report_ab(label, bench_array_alloc_ref_loop,
                        bench_array_alloc_opt_loop, &context, iterations);
    }

    puts("\n[3b] production boxed-array arithmetic");
    WValue sum_values = bench_boxed_array(1024);
    BenchArraySumContext sum_context = {sum_values};
    assert(bench_array_sum_reference(sum_values) ==
           bench_array_sum_production(sum_values));
    bench_report_ab("Array#sum 1024 inline Ints", bench_array_sum_ref_loop,
                    bench_array_sum_opt_loop, &sum_context, 50000);
    w_value_free(sum_values);

    puts("\n[4,5] regex workspace and lazy captures");
    enum { REGEX_GROUPS = 12, REGEX_RUN = 128 };
    char pattern[1024];
    char subject[REGEX_GROUPS * REGEX_RUN + 1];
    size_t pattern_size = 0;
    for (int group = 0; group < REGEX_GROUPS; group++) {
        char ch = (char)('a' + group);
#ifdef TUNGSTEN_ONIG
        pattern_size += (size_t)snprintf(pattern + pattern_size,
                         sizeof(pattern) - pattern_size,
                         "(?<g%02d>%c{%d})", group, ch, REGEX_RUN);
#else
        pattern_size += (size_t)snprintf(pattern + pattern_size,
                         sizeof(pattern) - pattern_size,
                         "(%c{%d})", ch, REGEX_RUN);
#endif
        memset(subject + group * REGEX_RUN, ch, REGEX_RUN);
    }
    subject[sizeof(subject) - 1] = '\0';
    BenchRegexContext regex_context = {
        w_regex_new(w_string(pattern), w_string("")), w_string(subject)
    };
    assert(w_regex_match(regex_context.regex, regex_context.subject) == W_TRUE);
    BenchRegexContext short_regex_context = {
        w_regex_new(w_string("(a+)"), w_string("")),
        w_string("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa")
    };
    bench_report_ab("regex match 1 short group",
                    bench_regex_workspace_ref_loop,
                    bench_regex_workspace_opt_loop, &short_regex_context,
                    200000);
    bench_report_ab("regex match 12 groups", bench_regex_workspace_ref_loop,
                    bench_regex_workspace_opt_loop, &regex_context, 20000);
    assert(w_regex_match(regex_context.regex, regex_context.subject) == W_TRUE);
    bench_report_ab("MatchData build 12 groups", bench_regex_build_ref_loop,
                    bench_regex_build_opt_loop, &regex_context, 20000);
    bench_report_ab("regex match_data 12 groups", bench_regex_data_ref_loop,
                    bench_regex_data_opt_loop, &regex_context, 5000);

    puts("\n[6] stored method-name hash guard");
    WMethod canonical_table[8] = {0};
    WValue canonical_name = w_string("canonical_method");
    uint64_t canonical_hash = w_method_name_hash(canonical_name);
    WMethod *canonical_slot = w_method_table_insert_slot(
        canonical_table, 8, canonical_name, canonical_hash);
    canonical_slot->name = canonical_name;
    canonical_slot->name_hash = canonical_hash;
    BenchMethodProbeContext canonical_context = {
        canonical_table, 8, canonical_name, canonical_hash
    };
    bench_report_ab("method probe canonical hit", bench_method_probe_ref_loop,
                    bench_method_probe_opt_loop, &canonical_context, 10000000);

    enum { PROBE_CAPACITY = 64, PROBE_CHAIN = 24 };
    WMethod collision_table[PROBE_CAPACITY];
    memset(collision_table, 0, sizeof(collision_table));
    int found = 0;
    for (int candidate = 0; found < PROBE_CHAIN; candidate++) {
        char text[128];
        snprintf(text, sizeof(text),
                 "method_collision_candidate_%06d_abcdefghijklmnopqrstuvwxyz_ABCDEFGHIJKLMNOPQRSTUVWXYZ",
                 candidate);
        WValue name = bench_heap_string(text);
        uint64_t hash = w_method_name_hash(name);
        if ((hash & (PROBE_CAPACITY - 1)) != 0) {
            w_value_free(name);
            continue;
        }
        WMethod *slot = w_method_table_insert_slot(
            collision_table, PROBE_CAPACITY, name, hash);
        slot->name = name;
        slot->name_hash = hash;
        found++;
    }
    WValue missing_name = W_NIL;
    uint64_t missing_hash = 0;
    for (int candidate = 100000; missing_name == W_NIL; candidate++) {
        char text[128];
        snprintf(text, sizeof(text),
                 "missing_collision_candidate_%06d_abcdefghijklmnopqrstuvwxyz_ABCDEFGHIJKLMNOPQRSTUVWXYZ",
                 candidate);
        WValue name = bench_heap_string(text);
        uint64_t hash = w_method_name_hash(name);
        if ((hash & (PROBE_CAPACITY - 1)) == 0) {
            missing_name = name;
            missing_hash = hash;
        } else {
            w_value_free(name);
        }
    }
    BenchMethodProbeContext collision_context = {
        collision_table, PROBE_CAPACITY, missing_name, missing_hash
    };
    assert(bench_method_probe_reference(collision_table, PROBE_CAPACITY,
                                        missing_name, missing_hash) == NULL);
    assert(w_method_table_probe(collision_table, PROBE_CAPACITY,
                                missing_name, missing_hash) == NULL);
    bench_report_ab("method probe 24-collision miss",
                    bench_method_probe_ref_loop, bench_method_probe_opt_loop,
                    &collision_context, 1000000);

    puts("\n[7] exact two-argument cached dispatch");
    WValue klass = w_class_new("BenchDispatch", W_NIL);
    WValue dispatch_name = w_string("combine");
    w_class_add_method_wv(klass, dispatch_name,
                          (void *)bench_dispatch_target, 3);
    BenchDispatchContext dispatch_context = {
        .receiver = w_object_new(klass),
        .name = dispatch_name,
        .arg0 = w_int(11),
        .arg1 = w_int(31),
        .generic_cache = {0},
        .exact_cache = {0}
    };
    WValue dispatch_args[2] = {dispatch_context.arg0, dispatch_context.arg1};
    assert(w_as_int(w_method_call_cached(
        dispatch_context.receiver, dispatch_context.name, dispatch_args, 2,
        &dispatch_context.generic_cache)) == 42);
    assert(w_as_int(w_method_call_cached(
        dispatch_context.receiver, dispatch_context.name, dispatch_args, 2,
        &dispatch_context.exact_cache)) == 42);
    bench_report_ab("cached source method argc=2",
                    bench_dispatch_generic_loop, bench_dispatch_exact_loop,
                    &dispatch_context, 20000000);

    puts("\n[8] inline Int division/modulo");
    bench_report_ab("Int division", bench_div_reference_loop,
                    bench_div_optimized_loop, NULL, 10000000);
    bench_report_ab("Int modulo", bench_mod_reference_loop,
                    bench_mod_optimized_loop, NULL, 10000000);

    puts("\n[9] vector transcendental map");
    const int vector_sizes[] = {16, 32, 64, 256, 4096};
    for (int operation = ARRAY_MAP_COS; operation <= ARRAY_MAP_TAN; operation++) {
        for (size_t size_index = 0;
             size_index < sizeof(vector_sizes) / sizeof(vector_sizes[0]);
             size_index++) {
            int size = vector_sizes[size_index];
            WValue input = w_array_new_inline(-64, size);
            double *values = (double *)w_as_array(input)->slots;
            for (int i = 0; i < size; i++)
                values[i] = 1.0 + (double)(i % 1000) / 1000.0;
            BenchVectorContext context = {input, (ArrayMapOp)operation};
            WValue reference = bench_array_map_scalar(input, context.operation);
            WValue optimized = bench_array_map_optimized(input, context.operation);
            double *a = (double *)w_as_array(reference)->slots;
            double *b = (double *)w_as_array(optimized)->slots;
            for (int i = 0; i < size; i++) {
                double scale = fabs(a[i]) > 1.0 ? fabs(a[i]) : 1.0;
                assert(fabs(a[i] - b[i]) <= scale * 2.0e-12);
            }
            w_value_free(reference);
            w_value_free(optimized);
            char label[64];
            snprintf(label, sizeof(label), "%s f64[%d]",
                     bench_vector_name(context.operation), size);
            int iterations = 1000000 / size;
            if (iterations < 200) iterations = 200;
            if (iterations > 50000) iterations = 50000;
            bench_report_ab(label, bench_vector_ref_loop,
                            bench_vector_opt_loop, &context, iterations);
            w_value_free(input);
        }
    }

    puts("\n[10] i8 matmul RHS gather vs forced pack (threshold sweep)");
    const int matmul_shapes[][3] = {
        {2, 64, 8}, {4, 64, 8}, {8, 64, 8}, {16, 64, 8},
        {12, 64, 8}, {16, 64, 2}, {16, 64, 4}, {16, 64, 16},
        {8, 64, 2}, {8, 64, 4}, {8, 64, 16},
        {16, 8, 8}, {16, 16, 8}, {16, 32, 8}, {16, 128, 8},
        {8, 8, 8}, {8, 16, 8}, {8, 32, 8}, {8, 128, 8},
        {4, 16, 4}, {16, 64, 16}, {32, 128, 32}
    };
    for (size_t i = 0; i < sizeof(matmul_shapes) / sizeof(matmul_shapes[0]); i++)
        bench_matmul_case(matmul_shapes[i][0], matmul_shapes[i][1],
                          matmul_shapes[i][2]);

    puts("\n[10] i8 matmul gather vs selected production policy");
    const int production_shapes[][3] = {
        {4, 16, 4}, {8, 64, 8}, {16, 16, 8}, {16, 64, 8},
        {32, 128, 32}
    };
    for (size_t i = 0;
         i < sizeof(production_shapes) / sizeof(production_shapes[0]); i++) {
        int m = production_shapes[i][0];
        int k = production_shapes[i][1];
        int n = production_shapes[i][2];
        WValue lhs = w_array_new_inline(108, (int64_t)m * k);
        WValue rhs = w_array_new_inline(108, (int64_t)k * n);
        int8_t *a = (int8_t *)w_as_array(lhs)->slots;
        int8_t *b = (int8_t *)w_as_array(rhs)->slots;
        for (int j = 0; j < m * k; j++)
            a[j] = (int8_t)((j * 17 + 3) % 31 - 15);
        for (int j = 0; j < k * n; j++)
            b[j] = (int8_t)((j * 11 + 5) % 29 - 14);
        BenchMatmulContext context = {
            lhs, rhs, w_int(m), w_int(k), w_int(n)
        };
        char label[64];
        snprintf(label, sizeof(label), "i8 policy %dx%dx%d", m, k, n);
        int64_t work = (int64_t)m * k * n;
        int iterations = (int)(30000000 / work);
        if (iterations < 20) iterations = 20;
        if (iterations > 200000) iterations = 200000;
        bench_report_ab(label, bench_matmul_gather_loop,
                        bench_matmul_production_loop, &context, iterations);
        w_value_free(lhs);
        w_value_free(rhs);
    }

    printf("\nsink=%llu\n", (unsigned long long)bench_sink);
    return 0;
}
