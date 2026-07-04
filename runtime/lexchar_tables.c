/* SIMD-lexer character tables (348KB of Unicode LexChar metadata), split out
 * of runtime.c so they are linked only when a program's IR references the
 * .lexchars API. runtime.c carries a weak twin of w_lexchar_tables that
 * reports absence; the entry points raise a clear error rather than compute
 * wrong answers if the probe is ever bypassed. */
#include <stdint.h>
#include "w_lexchar_cache.c"

int w_lexchar_tables(const uint64_t (**blocks)[256], const uint16_t **index) {
    *blocks = w_lexchar_block_data;
    *index = w_lexchar_block_index;
    return 1;
}
