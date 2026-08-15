/* Matched benchmark of the real WArray constructor/push/free path.
 * The Makefile builds runtime.c once with historical 2x growth and once with
 * the proposed 2x-through-256/1.25x-after policy. */

#include "runtime.h"

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>

static volatile uint64_t g_sink;

static uint64_t now_ns(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (uint64_t)ts.tv_sec * 1000000000ULL + (uint64_t)ts.tv_nsec;
}

static int double_compare(const void *lhs, const void *rhs) {
    double a = *(const double *)lhs;
    double b = *(const double *)rhs;
    return a < b ? -1 : a > b;
}

static void push_case(size_t target, size_t salt) {
    WValue array = w_array_new_empty();
    for (size_t i = 0; i < target; i++)
        w_array_push(array, w_int((int64_t)(i + salt)));
    WArray *a = w_as_array(array);
    if (target > 0) g_sink ^= a->slots[target - 1];
    w_value_free(array);
}

static double time_fixed(size_t target, size_t repeats) {
    uint64_t start = now_ns();
    for (size_t i = 0; i < repeats; i++) push_case(target, i);
    return (double)(now_ns() - start) / (double)(target * repeats);
}

static double time_mixed(size_t cases, size_t max_target) {
    uint32_t random = 0x6a09e667u;
    size_t pushes = 0;
    uint64_t start = now_ns();
    for (size_t i = 0; i < cases; i++) {
        random = random * 1664525u + 1013904223u;
        size_t target = 257 + (size_t)(random % (uint32_t)(max_target - 256));
        pushes += target;
        push_case(target, i);
    }
    return (double)(now_ns() - start) / (double)pushes;
}

static void report_fixed(const char *name, size_t target, size_t repeats) {
    double samples[7];
    (void)time_fixed(target, repeats / 4 + 1);
    for (int i = 0; i < 7; i++) samples[i] = time_fixed(target, repeats);
    qsort(samples, 7, sizeof(samples[0]), double_compare);
    printf("%-20s %8.3f ns/push\n", name, samples[3]);
}

static void report_mixed(const char *name, size_t cases, size_t max_target) {
    double samples[7];
    (void)time_mixed(cases / 4 + 1, max_target);
    for (int i = 0; i < 7; i++) samples[i] = time_mixed(cases, max_target);
    qsort(samples, 7, sizeof(samples[0]), double_compare);
    printf("%-20s %8.3f ns/push\n", name, samples[3]);
}

int main(int argc, char **argv) {
    printf("%s\n", argc > 1 ? argv[1] : "array growth");
    report_fixed("64 elements", 64, 20000);
    report_fixed("256 elements", 256, 5000);
    report_fixed("1024 elements", 1024, 1200);
    report_fixed("65536 elements", 65536, 32);
    report_fixed("1048576 elements", 1048576, 2);
    report_mixed("mixed <= 131072", 32, 131072);
    printf("sink=%llu\n", (unsigned long long)g_sink);
    return 0;
}
