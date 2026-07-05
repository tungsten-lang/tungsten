#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int levenshtein(const char *s, size_t m, const char *t, size_t n) {
    if (m == 0) return (int)n;
    if (n == 0) return (int)m;

    int *prev = malloc((n + 1) * sizeof(int));
    int *curr = malloc((n + 1) * sizeof(int));
    for (size_t j = 0; j <= n; j++) prev[j] = (int)j;

    for (size_t i = 0; i < m; i++) {
        curr[0] = (int)i + 1;
        for (size_t j = 0; j < n; j++) {
            int cost = s[i] == t[j] ? 0 : 1;
            int ins = curr[j] + 1;
            int del = prev[j + 1] + 1;
            int sub = prev[j] + cost;
            int best = ins < del ? ins : del;
            if (sub < best) best = sub;
            curr[j + 1] = best;
        }
        int *tmp = prev; prev = curr; curr = tmp;
    }

    int result = prev[n];
    free(prev); free(curr);
    return result;
}

static char *repeat(const char *src, int times) {
    size_t len = strlen(src);
    char *out = malloc(len * times + 1);
    for (int i = 0; i < times; i++) memcpy(out + i * len, src, len);
    out[len * times] = '\0';
    return out;
}

int main(void) {
    char *s = repeat("the quick brown fox jumps over the lazy dog", 20);
    char *t = repeat("the slow brown fox leaps over the lazy cat", 20);
    printf("%d\n", levenshtein(s, strlen(s), t, strlen(t)));
    free(s); free(t);
    return 0;
}
