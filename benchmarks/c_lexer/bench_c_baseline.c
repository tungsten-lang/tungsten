/*
 * Pure C lexer benchmark — raw byte scanning, no Unicode.
 * This is the "tcc equivalent" baseline: scan ASCII bytes,
 * classify with table lookup, count tokens.
 *
 * cc -O3 -o bench_c_baseline bench_c_baseline.c && ./bench_c_baseline <file.c> [rounds]
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

static int char_class[256];

enum { C_OTHER=0, C_WS=1, C_NL=2, C_ALPHA=3, C_DIGIT=4, C_QUOTE=5, C_SLASH=6, C_HASH=7, C_OP=8 };

static void init_classes(void) {
    memset(char_class, C_OTHER, sizeof(char_class));
    char_class[' '] = C_WS; char_class['\t'] = C_WS; char_class['\r'] = C_WS;
    char_class['\n'] = C_NL;
    for (int c = 'a'; c <= 'z'; c++) char_class[c] = C_ALPHA;
    for (int c = 'A'; c <= 'Z'; c++) char_class[c] = C_ALPHA;
    char_class['_'] = C_ALPHA;
    for (int c = '0'; c <= '9'; c++) char_class[c] = C_DIGIT;
    char_class['"'] = C_QUOTE; char_class['\''] = C_QUOTE;
    char_class['/'] = C_SLASH;
    char_class['#'] = C_HASH;
    const char *ops = "+-*%=<>&|^~!.,;:?()[]{}@";
    for (int i = 0; ops[i]; i++) char_class[(unsigned char)ops[i]] = C_OP;
}

static long tokenize(const unsigned char *src, long len) {
    long pos = 0, tc = 0;
    while (pos < len) {
        int cls = char_class[src[pos]];
        switch (cls) {
        case C_WS:
            pos++; while (pos < len && char_class[src[pos]] == C_WS) pos++;
            tc++; break;
        case C_NL:
            pos++; tc++; break;
        case C_ALPHA:
            pos++; while (pos < len && (char_class[src[pos]] == C_ALPHA || char_class[src[pos]] == C_DIGIT)) pos++;
            tc++; break;
        case C_DIGIT:
            pos++; while (pos < len && char_class[src[pos]] == C_DIGIT) pos++;
            tc++; break;
        case C_QUOTE: {
            int q = src[pos]; pos++;
            while (pos < len && src[pos] != q) { if (src[pos] == '\\') pos++; pos++; }
            if (pos < len) pos++;
            tc++; break;
        }
        case C_SLASH:
            if (pos+1 < len && src[pos+1] == '/') {
                pos += 2; while (pos < len && src[pos] != '\n') pos++;
                tc++; break;
            }
            if (pos+1 < len && src[pos+1] == '*') {
                pos += 2; while (pos < len) { if (src[pos] == '*' && pos+1 < len && src[pos+1] == '/') { pos += 2; break; } pos++; }
                tc++; break;
            }
            pos++; tc++; break;
        case C_HASH:
            pos++; while (pos < len && src[pos] != '\n') { if (src[pos] == '\\' && pos+1 < len && src[pos+1] == '\n') pos += 2; else pos++; }
            tc++; break;
        default:
            pos++; tc++; break;
        }
    }
    return tc;
}

int main(int argc, char **argv) {
    if (argc < 2) { fprintf(stderr, "Usage: bench_c_baseline <file.c> [rounds]\n"); return 1; }
    int rounds = argc > 2 ? atoi(argv[2]) : 20;

    FILE *f = fopen(argv[1], "rb");
    if (!f) { perror(argv[1]); return 1; }
    fseek(f, 0, SEEK_END); long len = ftell(f); fseek(f, 0, SEEK_SET);
    unsigned char *src = malloc(len);
    fread(src, 1, len, f); fclose(f);

    init_classes();
    long tokens = tokenize(src, len); /* warmup */

    struct timespec t0, t1;
    clock_gettime(CLOCK_MONOTONIC, &t0);
    long total = 0;
    for (int r = 0; r < rounds; r++) total += tokenize(src, len);
    clock_gettime(CLOCK_MONOTONIC, &t1);

    double ms = (t1.tv_sec - t0.tv_sec) * 1000.0 + (t1.tv_nsec - t0.tv_nsec) / 1e6;
    double mbs = (double)len * rounds / ms / 1000.0;
    printf("Pure C lexer (raw bytes, no Unicode)\n");
    printf("  File:   %s (%ld bytes)\n", argv[1], len);
    printf("  Rounds: %d\n", rounds);
    printf("  Time:   %.0fms\n", ms);
    printf("  Tokens: %ld/round\n", total / rounds);
    printf("  Speed:  %.0f MB/sec\n", mbs);

    free(src);
    return 0;
}
