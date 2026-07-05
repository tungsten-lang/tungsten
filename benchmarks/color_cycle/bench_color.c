#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include "wvalue.h"

/* ---- Competitor representations ---- */

typedef struct { uint8_t r, g, b, a; } SDL_Color;
typedef struct { float r, g, b, a; int colorspace; } CGColor;
typedef uint32_t CSSColor;

#define N (1 << 20)  /* 1M colors */

static inline uint64_t now_ns(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (uint64_t)ts.tv_sec * 1000000000ULL + ts.tv_nsec;
}

volatile uint64_t sink;

int main(void) {
    printf("\n  Color benchmark — %dM colors, real allocation\n\n", N / (1 << 20));

    /* ---- FILL: create N colors into an array ---- */
    printf("  FILL (create 1M colors into array):\n");

    /* Tungsten: 8 bytes each, inline */
    WValue *w_colors = malloc(N * sizeof(WValue));
    uint64_t t0 = now_ns();
    for (int i = 0; i < N; i++)
        w_colors[i] = w_box_color(i & 0xFF, (i >> 8) & 0xFF, (i >> 16) & 0xFF, 0xFF, 0);
    uint64_t dt = now_ns() - t0;
    printf("    tungsten:   %6.2f ns/op  %4zu MB  (8B inline NaN-box)\n",
           (double)dt / N, N * sizeof(WValue) / (1 << 20));

    /* SDL: 4 bytes each, inline */
    SDL_Color *sdl_colors = malloc(N * sizeof(SDL_Color));
    t0 = now_ns();
    for (int i = 0; i < N; i++)
        sdl_colors[i] = (SDL_Color){i & 0xFF, (i >> 8) & 0xFF, (i >> 16) & 0xFF, 0xFF};
    dt = now_ns() - t0;
    printf("    sdl:        %6.2f ns/op  %4zu MB  (4B struct)\n",
           (double)dt / N, N * sizeof(SDL_Color) / (1 << 20));

    /* CSS: 4 bytes each, packed uint32 */
    CSSColor *css_colors = malloc(N * sizeof(CSSColor));
    t0 = now_ns();
    for (int i = 0; i < N; i++)
        css_colors[i] = ((i & 0xFF) << 24) | (((i >> 8) & 0xFF) << 16) |
                        (((i >> 16) & 0xFF) << 8) | 0xFF;
    dt = now_ns() - t0;
    printf("    css:        %6.2f ns/op  %4zu MB  (4B packed uint32)\n",
           (double)dt / N, N * sizeof(CSSColor) / (1 << 20));

    /* Tungsten typed array: u8 buffer, 4 bytes per color (same layout as SDL) */
    uint8_t *w_typed = malloc(N * 4);
    t0 = now_ns();
    for (int i = 0; i < N; i++) {
        w_typed[i * 4]     = i & 0xFF;
        w_typed[i * 4 + 1] = (i >> 8) & 0xFF;
        w_typed[i * 4 + 2] = (i >> 16) & 0xFF;
        w_typed[i * 4 + 3] = 0xFF;
    }
    dt = now_ns() - t0;
    printf("    w typed u8: %6.2f ns/op  %4zu MB  (4B in typed array)\n",
           (double)dt / N, N * 4 / (1 << 20));

    /* CGColor: heap-alloc per color (real cost) */
    CGColor **cg_colors = malloc(N * sizeof(CGColor *));
    t0 = now_ns();
    for (int i = 0; i < N; i++) {
        cg_colors[i] = malloc(sizeof(CGColor));
        cg_colors[i]->r = (i & 0xFF) / 255.0f;
        cg_colors[i]->g = ((i >> 8) & 0xFF) / 255.0f;
        cg_colors[i]->b = ((i >> 16) & 0xFF) / 255.0f;
        cg_colors[i]->a = 1.0f;
        cg_colors[i]->colorspace = 0;
    }
    dt = now_ns() - t0;
    size_t cg_mem = N * (sizeof(CGColor) + sizeof(CGColor *) + 16); /* +16 for malloc overhead */
    printf("    cgcolor:    %6.2f ns/op  %4zu MB  (heap-alloc float struct)\n",
           (double)dt / N, cg_mem / (1 << 20));

    /* ---- SCAN: read R+G from all N colors ---- */
    printf("\n  SCAN (read R+G from 1M colors):\n");

    uint64_t acc;

    acc = 0;
    t0 = now_ns();
    for (int i = 0; i < N; i++)
        acc += w_unbox_color_r(w_colors[i]) + w_unbox_color_g(w_colors[i]);
    dt = now_ns() - t0;
    sink = acc;
    printf("    tungsten:   %6.2f ns/op  (bit shift + mask)\n", (double)dt / N);

    acc = 0;
    t0 = now_ns();
    for (int i = 0; i < N; i++)
        acc += sdl_colors[i].r + sdl_colors[i].g;
    dt = now_ns() - t0;
    sink = acc;
    printf("    sdl:        %6.2f ns/op  (direct field)\n", (double)dt / N);

    acc = 0;
    t0 = now_ns();
    for (int i = 0; i < N; i++)
        acc += w_typed[i * 4] + w_typed[i * 4 + 1];
    dt = now_ns() - t0;
    sink = acc;
    printf("    w typed u8: %6.2f ns/op  (direct byte access)\n", (double)dt / N);

    acc = 0;
    t0 = now_ns();
    for (int i = 0; i < N; i++)
        acc += (css_colors[i] >> 24) + ((css_colors[i] >> 16) & 0xFF);
    dt = now_ns() - t0;
    sink = acc;
    printf("    css:        %6.2f ns/op  (shift + mask)\n", (double)dt / N);

    acc = 0;
    t0 = now_ns();
    for (int i = 0; i < N; i++)
        acc += (uint64_t)(cg_colors[i]->r * 255) + (uint64_t)(cg_colors[i]->g * 255);
    dt = now_ns() - t0;
    sink = acc;
    printf("    cgcolor:    %6.2f ns/op  (deref + float→int)\n", (double)dt / N);

    /* ---- BLEND: alpha-blend pairs of colors ---- */
    printf("\n  BLEND (alpha-blend 1M color pairs):\n");

    t0 = now_ns();
    for (int i = 0; i < N - 1; i++) {
        uint8_t r1 = w_unbox_color_r(w_colors[i]), g1 = w_unbox_color_g(w_colors[i]);
        uint8_t b1 = w_unbox_color_b(w_colors[i]), a1 = w_unbox_color_a(w_colors[i]);
        uint8_t r2 = w_unbox_color_r(w_colors[i+1]), g2 = w_unbox_color_g(w_colors[i+1]);
        uint8_t b2 = w_unbox_color_b(w_colors[i+1]);
        w_colors[i] = w_box_color((r1 * a1 + r2 * (255 - a1)) / 255,
                                   (g1 * a1 + g2 * (255 - a1)) / 255,
                                   (b1 * a1 + b2 * (255 - a1)) / 255, 0xFF, 0);
    }
    dt = now_ns() - t0;
    sink = w_colors[0];
    printf("    tungsten:   %6.2f ns/op  (unbox + blend + rebox)\n", (double)dt / (N - 1));

    t0 = now_ns();
    for (int i = 0; i < N - 1; i++) {
        SDL_Color c1 = sdl_colors[i], c2 = sdl_colors[i+1];
        sdl_colors[i] = (SDL_Color){
            (c1.r * c1.a + c2.r * (255 - c1.a)) / 255,
            (c1.g * c1.a + c2.g * (255 - c1.a)) / 255,
            (c1.b * c1.a + c2.b * (255 - c1.a)) / 255, 0xFF};
    }
    dt = now_ns() - t0;
    sink = *(uint32_t *)&sdl_colors[0];
    printf("    sdl:        %6.2f ns/op  (direct struct blend)\n", (double)dt / (N - 1));

    t0 = now_ns();
    for (int i = 0; i < N - 1; i++) {
        int j = i * 4, k = (i + 1) * 4;
        uint8_t r1 = w_typed[j], g1 = w_typed[j+1], b1 = w_typed[j+2], a1 = w_typed[j+3];
        w_typed[j]   = (r1 * a1 + w_typed[k]   * (255 - a1)) / 255;
        w_typed[j+1] = (g1 * a1 + w_typed[k+1] * (255 - a1)) / 255;
        w_typed[j+2] = (b1 * a1 + w_typed[k+2] * (255 - a1)) / 255;
        w_typed[j+3] = 0xFF;
    }
    dt = now_ns() - t0;
    sink = w_typed[0];
    printf("    w typed u8: %6.2f ns/op  (direct byte blend)\n", (double)dt / (N - 1));

    /* ---- Cleanup ---- */
    free(w_colors);
    free(w_typed);
    free(sdl_colors);
    free(css_colors);
    for (int i = 0; i < N; i++) free(cg_colors[i]);
    free(cg_colors);

    printf("\n");
    return 0;
}
