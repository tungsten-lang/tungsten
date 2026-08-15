/*
 * Array growth / allocator behavior lab.
 *
 * This is intentionally self-contained: it measures the platform allocator
 * that Tungsten's WArray growth path actually calls, without pulling in the
 * rest of runtime.c.  Besides timing several capacity policies it records
 * realloc moves, the bytes a moving realloc must preserve, logical capacity
 * slack, allocator size-class slack, and immediate reuse of freed small
 * buffers.
 *
 * Run from the repository root with:
 *
 *   make -C runtime bench-array-growth
 */

#include <inttypes.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>

#if defined(__APPLE__)
#include <malloc/malloc.h>
static size_t allocation_size(void *p) { return malloc_size(p); }
static size_t allocator_reserved_bytes(void) {
    malloc_statistics_t stats;
    malloc_zone_statistics(malloc_default_zone(), &stats);
    return stats.size_allocated;
}
#elif defined(__linux__)
#include <malloc.h>
static size_t allocation_size(void *p) { return malloc_usable_size(p); }
static size_t allocator_reserved_bytes(void) {
    struct mallinfo2 stats = mallinfo2();
    return (size_t)stats.arena + (size_t)stats.hblkhd;
}
#else
static size_t allocation_size(void *p) { (void)p; return 0; }
static size_t allocator_reserved_bytes(void) { return 0; }
#endif

typedef enum {
    GROW_DOUBLE,
    GROW_THREE_HALVES,
    GROW_FIVE_QUARTERS,
    GROW_DOUBLE_64_THEN_THREE_HALVES,
    GROW_DOUBLE_256_THEN_THREE_HALVES,
    GROW_DOUBLE_1024_THEN_THREE_HALVES,
    GROW_DOUBLE_4096_THEN_THREE_HALVES,
    GROW_DOUBLE_256_THEN_FIVE_QUARTERS,
    GROW_DOUBLE_1024_THEN_FIVE_QUARTERS,
    GROW_DOUBLE_4096_THEN_FIVE_QUARTERS,
    GROW_DOUBLE_16384_THEN_NINE_EIGHTHS,
    GROW_DOUBLE_16384_THEN_FIVE_QUARTERS,
    GROW_DOUBLE_16384_THEN_FOUR_THIRDS,
    GROW_DOUBLE_16384_THEN_THREE_HALVES,
    GROW_DOUBLE_16384_THEN_GOLDEN,
    GROW_DOUBLE_65536_THEN_FIVE_QUARTERS,
    GROW_GOLDEN
} GrowthPolicy;

typedef struct {
    const char *name;
    GrowthPolicy policy;
} GrowthChoice;

typedef struct {
    uint64_t growths;
    uint64_t moves;
    uint64_t copied_bytes;
    uint64_t logical_elements;
    uint64_t final_capacity;
    uint64_t final_usable_bytes;
} GrowthStats;

typedef struct {
    size_t threshold;
    size_t numerator;
    size_t denominator;
    const char *threshold_name;
    const char *ratio_name;
    double ns_per_push;
    double capacity_slack;
} GridResult;

static volatile uint64_t g_sink;

static uint64_t now_ns(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (uint64_t)ts.tv_sec * 1000000000ULL + (uint64_t)ts.tv_nsec;
}

static size_t grow_ratio(size_t cap, size_t numerator, size_t denominator) {
    size_t increment = (cap + denominator - 1) / denominator;
    if (numerator > denominator + 1)
        increment *= numerator - denominator;
    return cap + increment;
}

static size_t next_capacity(GrowthPolicy policy, size_t cap) {
    if (cap == 0) return 8;
    switch (policy) {
        case GROW_DOUBLE:
            return cap * 2;
        case GROW_THREE_HALVES:
            return grow_ratio(cap, 3, 2);
        case GROW_FIVE_QUARTERS:
            return grow_ratio(cap, 5, 4);
        case GROW_DOUBLE_64_THEN_THREE_HALVES:
            return cap < 64 ? cap * 2 : grow_ratio(cap, 3, 2);
        case GROW_DOUBLE_256_THEN_THREE_HALVES:
            return cap < 256 ? cap * 2 : grow_ratio(cap, 3, 2);
        case GROW_DOUBLE_1024_THEN_THREE_HALVES:
            return cap < 1024 ? cap * 2 : grow_ratio(cap, 3, 2);
        case GROW_DOUBLE_4096_THEN_THREE_HALVES:
            return cap < 4096 ? cap * 2 : grow_ratio(cap, 3, 2);
        case GROW_DOUBLE_256_THEN_FIVE_QUARTERS:
            return cap < 256 ? cap * 2 : grow_ratio(cap, 5, 4);
        case GROW_DOUBLE_1024_THEN_FIVE_QUARTERS:
            return cap < 1024 ? cap * 2 : grow_ratio(cap, 5, 4);
        case GROW_DOUBLE_4096_THEN_FIVE_QUARTERS:
            return cap < 4096 ? cap * 2 : grow_ratio(cap, 5, 4);
        case GROW_DOUBLE_16384_THEN_NINE_EIGHTHS:
            return cap < 16384 ? cap * 2 : grow_ratio(cap, 9, 8);
        case GROW_DOUBLE_16384_THEN_FIVE_QUARTERS:
            return cap < 16384 ? cap * 2 : grow_ratio(cap, 5, 4);
        case GROW_DOUBLE_16384_THEN_FOUR_THIRDS:
            return cap < 16384 ? cap * 2 : grow_ratio(cap, 4, 3);
        case GROW_DOUBLE_16384_THEN_THREE_HALVES:
            return cap < 16384 ? cap * 2 : grow_ratio(cap, 3, 2);
        case GROW_DOUBLE_16384_THEN_GOLDEN:
            return cap < 16384 ? cap * 2 : cap + (cap * 5 + 7) / 8;
        case GROW_DOUBLE_65536_THEN_FIVE_QUARTERS:
            return cap < 65536 ? cap * 2 : grow_ratio(cap, 5, 4);
        case GROW_GOLDEN:
            /* Integer approximation to phi: 1.625x. */
            return cap + (cap * 5 + 7) / 8;
    }
    abort();
}

static void *checked_malloc(size_t bytes) {
    void *p = malloc(bytes);
    if (!p) {
        fprintf(stderr, "malloc(%zu) failed\n", bytes);
        exit(1);
    }
    return p;
}

static void *checked_realloc(void *old, size_t bytes) {
    void *p = realloc(old, bytes);
    if (!p) {
        fprintf(stderr, "realloc(%zu) failed\n", bytes);
        exit(1);
    }
    return p;
}

static void run_growth_case(GrowthPolicy policy, size_t target, size_t salt,
                            GrowthStats *stats) {
    size_t cap = 8;
    uint64_t *slots = checked_malloc(cap * sizeof(*slots));
    for (size_t size = 0; size < target; size++) {
        if (size == cap) {
            size_t next = next_capacity(policy, cap);
            if (next <= size) next = size + 1;
            uintptr_t old_address = (uintptr_t)slots;
            slots = checked_realloc(slots, next * sizeof(*slots));
            stats->growths++;
            if ((uintptr_t)slots != old_address) {
                stats->moves++;
                stats->copied_bytes += size * sizeof(*slots);
            }
            cap = next;
        }
        slots[size] = (uint64_t)(size + salt);
    }
    if (target > 0) g_sink ^= slots[target - 1];
    stats->logical_elements += target;
    stats->final_capacity += cap;
    stats->final_usable_bytes += allocation_size(slots);
    free(slots);
}

static double run_growth(GrowthPolicy policy, size_t target, size_t repeats,
                         GrowthStats *stats) {
    uint64_t started = now_ns();
    for (size_t repeat = 0; repeat < repeats; repeat++)
        run_growth_case(policy, target, repeat, stats);
    return (double)(now_ns() - started) / (double)stats->logical_elements;
}

static double run_mixed_growth(GrowthPolicy policy, size_t cases,
                               size_t max_target, GrowthStats *stats) {
    uint32_t random = 0x6a09e667u;
    uint64_t started = now_ns();
    for (size_t i = 0; i < cases; i++) {
        random = random * 1664525u + 1013904223u;
        size_t target = 257 + (size_t)(random % (uint32_t)(max_target - 256));
        run_growth_case(policy, target, i, stats);
    }
    return (double)(now_ns() - started) / (double)stats->logical_elements;
}

static size_t next_grid_capacity(const GridResult *choice, size_t cap) {
    if (cap < choice->threshold) return cap * 2;
    size_t extra_numerator = choice->numerator - choice->denominator;
    return cap + (cap * extra_numerator + choice->denominator - 1) /
                 choice->denominator;
}

static void run_grid_case(const GridResult *choice, size_t target, size_t salt,
                          GrowthStats *stats) {
    size_t cap = 8;
    uint64_t *slots = checked_malloc(cap * sizeof(*slots));
    for (size_t size = 0; size < target; size++) {
        if (size == cap) {
            size_t next = next_grid_capacity(choice, cap);
            if (next <= size) next = size + 1;
            uintptr_t old_address = (uintptr_t)slots;
            slots = checked_realloc(slots, next * sizeof(*slots));
            stats->growths++;
            if ((uintptr_t)slots != old_address) {
                stats->moves++;
                stats->copied_bytes += size * sizeof(*slots);
            }
            cap = next;
        }
        slots[size] = (uint64_t)(size + salt);
    }
    if (target > 0) g_sink ^= slots[target - 1];
    stats->logical_elements += target;
    stats->final_capacity += cap;
    stats->final_usable_bytes += allocation_size(slots);
    free(slots);
}

static double run_mixed_grid(const GridResult *choice, size_t cases,
                             size_t max_target, GrowthStats *stats) {
    uint32_t random = 0x6a09e667u;
    uint64_t started = now_ns();
    for (size_t i = 0; i < cases; i++) {
        random = random * 1664525u + 1013904223u;
        size_t target = 257 + (size_t)(random % (uint32_t)(max_target - 256));
        run_grid_case(choice, target, i, stats);
    }
    return (double)(now_ns() - started) / (double)stats->logical_elements;
}

static const GrowthChoice g_choices[] = {
    {"2x", GROW_DOUBLE},
    {"1.5x", GROW_THREE_HALVES},
    {"1.25x", GROW_FIVE_QUARTERS},
    {"2x<=64,1.5x", GROW_DOUBLE_64_THEN_THREE_HALVES},
    {"2x<=256,1.5x", GROW_DOUBLE_256_THEN_THREE_HALVES},
    {"2x<=1K,1.5x", GROW_DOUBLE_1024_THEN_THREE_HALVES},
    {"2x<=4K,1.5x", GROW_DOUBLE_4096_THEN_THREE_HALVES},
    {"2x<=256,1.25x", GROW_DOUBLE_256_THEN_FIVE_QUARTERS},
    {"2x<=1K,1.25x", GROW_DOUBLE_1024_THEN_FIVE_QUARTERS},
    {"2x<=4K,1.25x", GROW_DOUBLE_4096_THEN_FIVE_QUARTERS},
    {"2x<=16K,1.125x", GROW_DOUBLE_16384_THEN_NINE_EIGHTHS},
    {"2x<=16K,1.25x", GROW_DOUBLE_16384_THEN_FIVE_QUARTERS},
    {"2x<=16K,1.333x", GROW_DOUBLE_16384_THEN_FOUR_THIRDS},
    {"2x<=16K,1.5x", GROW_DOUBLE_16384_THEN_THREE_HALVES},
    {"2x<=16K,1.625x", GROW_DOUBLE_16384_THEN_GOLDEN},
    {"2x<=64K,1.25x", GROW_DOUBLE_65536_THEN_FIVE_QUARTERS},
    {"1.625x", GROW_GOLDEN},
};

static void print_growth_header(void) {
    printf("%-17s %9s %9s %9s %10s %10s %10s %11s\n",
           "policy", "ns/push", "grows", "moves", "move-rate",
           "copy KiB", "cap-slack", "alloc-slack");
}

static void print_growth_row(const GrowthChoice *choice, double ns,
                             size_t cases, const GrowthStats *stats) {
    double grows = (double)stats->growths / (double)cases;
    double moves = (double)stats->moves / (double)cases;
    double move_rate = stats->growths
                     ? 100.0 * (double)stats->moves / (double)stats->growths
                     : 0.0;
    double copy_kib = (double)stats->copied_bytes / (1024.0 * (double)cases);
    double cap_slack = stats->logical_elements
                     ? 100.0 * ((double)stats->final_capacity -
                                (double)stats->logical_elements) /
                       (double)stats->logical_elements
                     : 0.0;
    double capacity_bytes = (double)stats->final_capacity * sizeof(uint64_t);
    double allocator_slack = capacity_bytes > 0.0
                           ? 100.0 * ((double)stats->final_usable_bytes -
                                      capacity_bytes) / capacity_bytes
                           : 0.0;
    printf("%-17s %9.3f %9.2f %9.2f %9.1f%% %10.1f %9.1f%% %10.1f%%\n",
           choice->name, ns, grows, moves, move_rate, copy_kib, cap_slack,
           allocator_slack);
}

static void print_growth_table(size_t target, size_t repeats) {
    printf("\ntarget=%zu elements, repeats=%zu\n", target, repeats);
    print_growth_header();
    for (size_t i = 0; i < sizeof(g_choices) / sizeof(g_choices[0]); i++) {
        GrowthStats stats = {0};
        double ns = run_growth(g_choices[i].policy, target, repeats, &stats);
        print_growth_row(&g_choices[i], ns, repeats, &stats);
    }
}

static void print_mixed_growth_table(size_t cases, size_t max_target) {
    printf("\nmixed final sizes=257..%zu, cases=%zu\n", max_target, cases);
    print_growth_header();
    for (size_t i = 0; i < sizeof(g_choices) / sizeof(g_choices[0]); i++) {
        GrowthStats stats = {0};
        double ns = run_mixed_growth(g_choices[i].policy, cases, max_target,
                                     &stats);
        print_growth_row(&g_choices[i], ns, cases, &stats);
    }
}

static int double_value_compare(const void *lhs, const void *rhs) {
    double a = *(const double *)lhs;
    double b = *(const double *)rhs;
    return a < b ? -1 : a > b;
}

static void print_grid_search(size_t cases, size_t max_target) {
    static const struct { size_t value; const char *name; } thresholds[] = {
        {256, "256"}, {1024, "1K"}, {4096, "4K"}, {8192, "8K"},
        {16384, "16K"}, {65536, "64K"},
    };
    static const struct {
        size_t numerator;
        size_t denominator;
        const char *name;
    } ratios[] = {
        {9, 8, "1.125x"}, {5, 4, "1.25x"}, {4, 3, "1.333x"},
        {3, 2, "1.5x"}, {13, 8, "1.625x"},
    };
    GridResult results[1 + (sizeof(thresholds) / sizeof(thresholds[0])) *
                           (sizeof(ratios) / sizeof(ratios[0]))];
    size_t result_count = 0;

    printf("\ngrid search: mixed final sizes=257..%zu, cases=%zu\n",
           max_target, cases);
    printf("%-8s %-8s %9s %10s %9s %10s\n", "cutover", "growth",
           "ns/push", "cap-slack", "grows", "copy KiB");

    GridResult *baseline = &results[result_count++];
    baseline->threshold = SIZE_MAX;
    baseline->threshold_name = "none";
    baseline->numerator = 2;
    baseline->denominator = 1;
    baseline->ratio_name = "2x";
    GrowthStats baseline_stats = {0};
    double baseline_samples[7];
    for (size_t sample = 0; sample < 7; sample++) {
        GrowthStats sample_stats = {0};
        baseline_samples[sample] = run_mixed_grid(
            baseline, cases, max_target, &sample_stats);
        if (sample == 0) baseline_stats = sample_stats;
    }
    qsort(baseline_samples, 7, sizeof(baseline_samples[0]),
          double_value_compare);
    baseline->ns_per_push = baseline_samples[3];
    baseline->capacity_slack = 100.0 *
        ((double)baseline_stats.final_capacity -
         (double)baseline_stats.logical_elements) /
        (double)baseline_stats.logical_elements;
    printf("%-8s %-8s %9.3f %9.1f%% %9.2f %10.1f\n",
           baseline->threshold_name, baseline->ratio_name,
           baseline->ns_per_push, baseline->capacity_slack,
           (double)baseline_stats.growths / (double)cases,
           (double)baseline_stats.copied_bytes / (1024.0 * (double)cases));

    for (size_t ti = 0; ti < sizeof(thresholds) / sizeof(thresholds[0]); ti++) {
        for (size_t ri = 0; ri < sizeof(ratios) / sizeof(ratios[0]); ri++) {
            GridResult *result = &results[result_count++];
            result->threshold = thresholds[ti].value;
            result->threshold_name = thresholds[ti].name;
            result->numerator = ratios[ri].numerator;
            result->denominator = ratios[ri].denominator;
            result->ratio_name = ratios[ri].name;
            GrowthStats stats = {0};
            double samples[7];
            for (size_t sample = 0; sample < 7; sample++) {
                GrowthStats sample_stats = {0};
                samples[sample] = run_mixed_grid(result, cases, max_target,
                                                 &sample_stats);
                if (sample == 0) stats = sample_stats;
            }
            qsort(samples, 7, sizeof(samples[0]), double_value_compare);
            result->ns_per_push = samples[3];
            result->capacity_slack = 100.0 *
                ((double)stats.final_capacity - (double)stats.logical_elements) /
                (double)stats.logical_elements;
            printf("%-8s %-8s %9.3f %9.1f%% %9.2f %10.1f\n",
                   result->threshold_name, result->ratio_name,
                   result->ns_per_push, result->capacity_slack,
                   (double)stats.growths / (double)cases,
                   (double)stats.copied_bytes / (1024.0 * (double)cases));
        }
    }

    printf("Pareto frontier (lower time and lower slack):\n");
    for (size_t i = 0; i < result_count; i++) {
        int dominated = 0;
        for (size_t j = 0; j < result_count; j++) {
            if (i == j) continue;
            if (results[j].ns_per_push <= results[i].ns_per_push &&
                results[j].capacity_slack <= results[i].capacity_slack &&
                (results[j].ns_per_push < results[i].ns_per_push ||
                 results[j].capacity_slack < results[i].capacity_slack)) {
                dominated = 1;
                break;
            }
        }
        if (!dominated)
            printf("  cutover=%-4s growth=%-7s %.3f ns/push, %.1f%% slack\n",
                   results[i].threshold_name, results[i].ratio_name,
                   results[i].ns_per_push, results[i].capacity_slack);
    }
}

static int uintptr_compare(const void *lhs, const void *rhs) {
    uintptr_t a = *(const uintptr_t *)lhs;
    uintptr_t b = *(const uintptr_t *)rhs;
    return a < b ? -1 : a > b;
}

static int address_was_freed(uintptr_t address, const uintptr_t *freed,
                             size_t count) {
    return bsearch(&address, freed, count, sizeof(*freed), uintptr_compare) != NULL;
}

/* A single free/malloc pair can intentionally miss because modern allocators
 * quarantine recently freed memory. This batch probe answers the more useful
 * question: does the same size class come back after enough intervening frees? */
static double batch_free_reuse(size_t bytes, size_t count,
                               double *refill_vm_growth) {
    void **first = checked_malloc(count * sizeof(*first));
    void **second = checked_malloc(count * sizeof(*second));
    uintptr_t *freed = checked_malloc(count * sizeof(*freed));
    for (size_t i = 0; i < count; i++) {
        first[i] = checked_malloc(bytes);
        freed[i] = (uintptr_t)first[i];
    }
    qsort(freed, count, sizeof(*freed), uintptr_compare);
    for (size_t i = 0; i < count; i++) free(first[i]);
    size_t reserved_before_refill = allocator_reserved_bytes();
    size_t reused = 0;
    for (size_t i = 0; i < count; i++) {
        second[i] = checked_malloc(bytes);
        reused += address_was_freed((uintptr_t)second[i], freed, count);
    }
    size_t reserved_after_refill = allocator_reserved_bytes();
    for (size_t i = 0; i < count; i++) free(second[i]);
    free(freed);
    free(second);
    free(first);
    if (reserved_before_refill == 0 || reserved_after_refill <= reserved_before_refill)
        *refill_vm_growth = 0.0;
    else
        *refill_vm_growth = 100.0 *
            (double)(reserved_after_refill - reserved_before_refill) /
            (double)(bytes * count);
    return 100.0 * (double)reused / (double)count;
}

static double batch_outgrown_reuse(size_t bytes, size_t count,
                                   double *move_rate) {
    void **grown = checked_malloc(count * sizeof(*grown));
    void **guards = checked_malloc(count * sizeof(*guards));
    void **replacements = checked_malloc(count * sizeof(*replacements));
    uintptr_t *freed = checked_malloc(count * sizeof(*freed));
    size_t moved = 0;
    for (size_t i = 0; i < count; i++) {
        void *p = checked_malloc(bytes);
        guards[i] = checked_malloc(bytes);
        uintptr_t old = (uintptr_t)p;
        grown[i] = checked_realloc(p, bytes * 2);
        if ((uintptr_t)grown[i] != old) freed[moved++] = old;
    }
    qsort(freed, moved, sizeof(*freed), uintptr_compare);
    size_t reused = 0;
    for (size_t i = 0; i < count; i++) {
        replacements[i] = checked_malloc(bytes);
        reused += address_was_freed((uintptr_t)replacements[i], freed, moved);
    }
    for (size_t i = 0; i < count; i++) {
        free(replacements[i]);
        free(guards[i]);
        free(grown[i]);
    }
    free(freed);
    free(replacements);
    free(guards);
    free(grown);
    *move_rate = 100.0 * (double)moved / (double)count;
    return moved ? 100.0 * (double)reused / (double)moved : 0.0;
}

static void print_allocator_reuse(void) {
    static const size_t sizes[] = {32, 64, 128, 256, 512, 1024, 2048};
    const size_t rounds = 20000;
    printf("\nsmall-buffer allocator probe, %zu rounds per size\n", rounds);
    printf("%-8s %12s %14s %13s %12s %13s %10s %16s\n", "bytes", "usable",
           "free->malloc", "realloc moved", "old reused", "batch reused",
           "refill VM", "outgrown reused");
    for (size_t i = 0; i < sizeof(sizes) / sizeof(sizes[0]); i++) {
        size_t bytes = sizes[i];
        uint64_t direct_reuse = 0;
        uint64_t moved = 0;
        uint64_t moved_old_reused = 0;
        size_t usable = 0;
        for (size_t round = 0; round < rounds; round++) {
            void *p = checked_malloc(bytes);
            if (round == 0) usable = allocation_size(p);
            uintptr_t address = (uintptr_t)p;
            free(p);
            p = checked_malloc(bytes);
            if ((uintptr_t)p == address) direct_reuse++;
            free(p);

            p = checked_malloc(bytes);
            void *guard = checked_malloc(bytes);
            address = (uintptr_t)p;
            p = checked_realloc(p, bytes * 2);
            if ((uintptr_t)p != address) {
                moved++;
                void *replacement = checked_malloc(bytes);
                if ((uintptr_t)replacement == address) moved_old_reused++;
                free(replacement);
            }
            free(guard);
            free(p);
        }
        /* Prime the size class once so the reported batch is not measuring
         * only a cold zone that has never accumulated reusable blocks. */
        double ignored_vm_growth = 0.0;
        (void)batch_free_reuse(bytes, 16384, &ignored_vm_growth);
        double refill_vm_growth = 0.0;
        double batch = batch_free_reuse(bytes, 16384, &refill_vm_growth);
        double batch_move_rate = 0.0;
        double outgrown = batch_outgrown_reuse(bytes, 16384, &batch_move_rate);
        (void)batch_move_rate;
        printf("%-8zu %12zu %13.1f%% %12.1f%% %11.1f%% %12.1f%% %9.1f%% %15.1f%%\n",
               bytes, usable,
               100.0 * (double)direct_reuse / (double)rounds,
               100.0 * (double)moved / (double)rounds,
               moved ? 100.0 * (double)moved_old_reused / (double)moved : 0.0,
               batch, refill_vm_growth, outgrown);
    }
}

int main(void) {
    print_growth_table(64, 100000);
    print_growth_table(256, 40000);
    print_growth_table(1024, 10000);
    print_growth_table(65536, 128);
    print_growth_table(1048576, 8);
    print_mixed_growth_table(256, 131072);
    print_grid_search(256, 131072);
    print_allocator_reuse();
    printf("\nsink=%" PRIu64 "\n", g_sink);
    return 0;
}
