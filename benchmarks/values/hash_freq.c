#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#define NUM_WORDS 1000
#define NUM_ITER  5000000

int main(void) {
    struct timespec t0, t1;
    clock_gettime(CLOCK_MONOTONIC, &t0);

    /* Build vocabulary */
    char words[NUM_WORDS][16];
    for (int i = 0; i < NUM_WORDS; i++) {
        sprintf(words[i], "word%d", i);
    }

    /* Frequency counts — keys are word0..word999, so index directly */
    int freq[NUM_WORDS];
    memset(freq, 0, sizeof(freq));

    unsigned int seed = 42;
    for (int i = 0; i < NUM_ITER; i++) {
        seed = (seed * 1103515245 + 12345) & 0x7FFFFFFF;
        int idx = seed % NUM_WORDS;
        freq[idx]++;
    }

    int max_freq = 0;
    for (int i = 0; i < NUM_WORDS; i++) {
        if (freq[i] > max_freq) max_freq = freq[i];
    }

    clock_gettime(CLOCK_MONOTONIC, &t1);
    double elapsed = (t1.tv_sec - t0.tv_sec) + (t1.tv_nsec - t0.tv_nsec) / 1e9;
    printf("%d\n", max_freq);
    printf("elapsed: %.3fs\n", elapsed);
    return 0;
}
