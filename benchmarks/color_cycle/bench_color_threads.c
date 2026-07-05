#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <pthread.h>
#include <time.h>
#include "wvalue.h"

#define N 100000000  /* 100M total */

static inline uint64_t now_ns(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (uint64_t)ts.tv_sec * 1000000000ULL + ts.tv_nsec;
}

typedef struct {
    int start, end;
    uint64_t acc;
} WorkItem;

static void *color_cycle_worker(void *arg) {
    WorkItem *w = (WorkItem *)arg;
    uint64_t acc = 0;
    for (int i = w->start; i < w->end; i++) {
        WValue c = w_box_color(i & 0xFF, (i >> 8) & 0xFF, (i >> 16) & 0xFF, 0xFF, 0);
        acc += w_unbox_color_r(c);
    }
    w->acc = acc;
    return NULL;
}

static void bench(int nthreads) {
    int per_thread = N / nthreads;
    pthread_t *threads = malloc(nthreads * sizeof(pthread_t));
    WorkItem *items = malloc(nthreads * sizeof(WorkItem));

    uint64_t t0 = now_ns();
    for (int t = 0; t < nthreads; t++) {
        items[t].start = t * per_thread;
        items[t].end = (t == nthreads - 1) ? N : (t + 1) * per_thread;
        items[t].acc = 0;
        pthread_create(&threads[t], NULL, color_cycle_worker, &items[t]);
    }
    uint64_t total_acc = 0;
    for (int t = 0; t < nthreads; t++) {
        pthread_join(threads[t], NULL);
        total_acc += items[t].acc;
    }
    uint64_t dt = now_ns() - t0;

    double mops = (double)N / dt * 1e3;
    printf("  %2d threads: %8.1fM colors/sec  (%5.2f ns/color)  %.1fx\n",
           nthreads, mops, (double)dt / N, mops / ((double)N / (now_ns() - now_ns() + 1) * 1e3));

    free(threads);
    free(items);
}

int main(void) {
    /* Single-thread baseline */
    WorkItem single = {0, N, 0};
    color_cycle_worker(&single);  /* warm */
    single.acc = 0;
    uint64_t t0 = now_ns();
    single.start = 0; single.end = N; single.acc = 0;
    color_cycle_worker(&single);
    uint64_t dt = now_ns() - t0;
    volatile uint64_t sink = single.acc;
    (void)sink;
    double base_mops = (double)N / dt * 1e3;

    printf("\n  Color cycle — %dM colors, threaded (inline w_box_color)\n\n", N / 1000000);
    printf("  %2d thread:  %8.1fM colors/sec  (%5.2f ns/color)  1.0x\n", 1, base_mops, (double)dt / N);

    int counts[] = {2, 4, 8, 16, 32, 64};
    for (int c = 0; c < 6; c++) {
        int nt = counts[c];
        WorkItem *items = malloc(nt * sizeof(WorkItem));
        pthread_t *threads = malloc(nt * sizeof(pthread_t));
        int per = N / nt;

        t0 = now_ns();
        for (int t = 0; t < nt; t++) {
            items[t].start = t * per;
            items[t].end = (t == nt - 1) ? N : (t + 1) * per;
            items[t].acc = 0;
            pthread_create(&threads[t], NULL, color_cycle_worker, &items[t]);
        }
        for (int t = 0; t < nt; t++) pthread_join(threads[t], NULL);
        dt = now_ns() - t0;

        double mops = (double)N / dt * 1e3;
        printf("  %2d threads: %8.1fM colors/sec  (%5.2f ns/color)  %.1fx\n",
               nt, mops, (double)dt / N, mops / base_mops);

        free(items);
        free(threads);
    }
    printf("\n");
    return 0;
}
