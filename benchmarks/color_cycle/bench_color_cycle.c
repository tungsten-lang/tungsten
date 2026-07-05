#include <stdio.h>
#include <stdint.h>
#include <time.h>
#include "wvalue.h"

static inline uint64_t now_ns(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (uint64_t)ts.tv_sec * 1000000000ULL + ts.tv_nsec;
}

volatile uint64_t sink;

/* forward-declare runtime function */
WValue w_color(uint8_t r, uint8_t g, uint8_t b, uint8_t a);

int main(void) {
    int n = 10000000;

    /* 1. Cycle via w_box_color (function call — same path as compiled Tungsten) */
    uint64_t acc = 0;
    uint64_t t0 = now_ns();
    for (int i = 0; i < n; i++) {
        WValue c = w_color(i & 0xFF, (i >> 8) & 0xFF, (i >> 16) & 0xFF, 0xFF);
        acc += w_unbox_color_r(c);
    }
    uint64_t dt = now_ns() - t0;
    sink = acc;
    printf("C w_color call: %8.1fM colors/sec  (%5.2f ns/color)\n",
           (double)n / dt * 1e3, (double)dt / n);

    /* 2. Cycle via inline w_box_color (inlined — best possible C) */
    acc = 0;
    t0 = now_ns();
    for (int i = 0; i < n; i++) {
        WValue c = w_box_color(i & 0xFF, (i >> 8) & 0xFF, (i >> 16) & 0xFF, 0xFF, 0);
        acc += w_unbox_color_r(c);
    }
    dt = now_ns() - t0;
    sink = acc;
    printf("C inline box:   %8.1fM colors/sec  (%5.2f ns/color)\n",
           (double)n / dt * 1e3, (double)dt / n);

    /* 3. Cycle via raw uint32 (no NaN-box — absolute floor) */
    acc = 0;
    t0 = now_ns();
    for (int i = 0; i < n; i++) {
        uint32_t c = ((uint32_t)(i & 0xFF) << 24) | ((uint32_t)((i >> 8) & 0xFF) << 16) |
                     ((uint32_t)((i >> 16) & 0xFF) << 8) | 0xFF;
        acc += (c >> 24) & 0xFF;
    }
    dt = now_ns() - t0;
    sink = acc;
    printf("C raw uint32:   %8.1fM colors/sec  (%5.2f ns/color)\n",
           (double)n / dt * 1e3, (double)dt / n);

    return 0;
}

