#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

int main(void) {
    struct timespec t0, t1;
    clock_gettime(CLOCK_MONOTONIC, &t0);

    const char *base = "the quick brown fox jumps over the lazy dog ";
    int base_len = (int)strlen(base);
    int repeats = 2500000;
    int text_len = base_len * repeats;

    char *text = malloc(text_len + 1);
    for (int i = 0; i < repeats; i++) {
        memcpy(text + i * base_len, base, base_len);
    }
    text[text_len] = '\0';

    int count = 0;
    const char *pos = text;
    while ((pos = strstr(pos, "fox")) != NULL) {
        count++;
        pos += 3;
    }

    clock_gettime(CLOCK_MONOTONIC, &t1);
    double elapsed = (t1.tv_sec - t0.tv_sec) + (t1.tv_nsec - t0.tv_nsec) / 1e9;
    printf("%d\n", count);
    printf("elapsed: %.3fs\n", elapsed);
    free(text);
    return 0;
}
