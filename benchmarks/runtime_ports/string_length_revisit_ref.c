/* Exact fixtures and raw thread-CPU clock for the String/Symbol public
 * size/length migration revisit. This file is benchmark-only. */

#include "runtime.h"

#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

/* Benchmark-only delayed registration bridge; runtime.c exports this helper
 * for generated class initialization but runtime.h intentionally exposes only
 * the compact class-id registration API. */
void w_type_class_register_wv(int32_t dispatch_key, WValue klass);

enum { W_STRLEN_CASE_COUNT = 17 };

static WValue g_strlen_cases[W_STRLEN_CASE_COUNT];
static int g_strlen_ready;

static WValue strlen_heap_bytes(const uint8_t *bytes, uint32_t len) {
    WString *s = (WString *)calloc(1, sizeof(WString) + (size_t)len + 1);
    if (s == NULL) abort();
    s->len = len;
    memcpy(s->data, bytes, len);
    s->data[len] = '\0';
    return w_box_heap_str(s);
}

static WValue strlen_heap_fill(uint8_t byte, uint32_t len) {
    uint8_t *bytes = (uint8_t *)malloc(len ? len : 1);
    if (bytes == NULL) abort();
    memset(bytes, byte, len);
    WValue out = strlen_heap_bytes(bytes, len);
    free(bytes);
    return out;
}

static void strlen_init_cases(void) {
    if (g_strlen_ready) return;

    static const uint8_t inline_utf8[] = {0xc3, 0xa9};
    static const uint8_t inline_nul[] = {'A', 0, 'B'};
    static const uint8_t symbol_nul[] = {'X', 0, 'Y'};

    g_strlen_cases[0] = w_box_inline_str("", 0);
    g_strlen_cases[1] = w_box_inline_str("abcde", 5);
    g_strlen_cases[2] = w_box_inline_str(inline_utf8, sizeof inline_utf8);
    g_strlen_cases[3] = w_box_inline_str(inline_nul, sizeof inline_nul);

    /* Exactly six stored bytes force mode 6. The UTF-8 case is three
     * codepoints but six bytes, pinning byte length rather than rune length. */
    g_strlen_cases[4] = w_string("abcdef");
    g_strlen_cases[5] = w_box_inline_str("", 0);
    {
        uint8_t utf8_slab[6] = {0xc3, 0xa9, 0xc3, 0xa9, 0xc3, 0xa9};
        WValue bytes = w_array_new_uninit_sized(8, 6);
        WArray *arr = (WArray *)w_as_ptr(bytes);
        memcpy(arr->slots, utf8_slab, sizeof utf8_slab);
        g_strlen_cases[5] = w_string_from_byte_array(bytes);
    }

    g_strlen_cases[6] = strlen_heap_fill('h', 80);
    {
        uint8_t bytes[80];
        memset(bytes, 'n', sizeof bytes);
        bytes[0] = 0;
        bytes[31] = 0;
        bytes[79] = 0;
        g_strlen_cases[7] = strlen_heap_bytes(bytes, sizeof bytes);
    }

    /* >61 bytes retains a rope node until dispatch flattens it. */
    g_strlen_cases[8] = w_str_concat(strlen_heap_fill('l', 40),
                                     strlen_heap_fill('r', 41));

    g_strlen_cases[9] = w_str_to_sym(g_strlen_cases[0]);
    g_strlen_cases[10] = w_str_to_sym(w_box_inline_str("sym", 3));
    g_strlen_cases[11] = w_str_to_sym(w_box_inline_str(symbol_nul, sizeof symbol_nul));
    g_strlen_cases[12] = w_str_to_sym(w_string("symbol"));
    g_strlen_cases[13] = w_str_to_sym(g_strlen_cases[5]);
    g_strlen_cases[14] = w_str_to_sym(strlen_heap_fill('S', 80));
    {
        uint8_t bytes[80];
        memset(bytes, 'Q', sizeof bytes);
        bytes[2] = 0;
        bytes[63] = 0;
        g_strlen_cases[15] = w_str_to_sym(strlen_heap_bytes(bytes, sizeof bytes));
    }
    /* Symbol conversion of a rope occurs after canonical dispatch flattening;
     * preserve that supported path as a distinct heap-Symbol case. */
    {
        WValue rope = w_str_concat(strlen_heap_fill('a', 33),
                                   strlen_heap_fill('b', 34));
        g_strlen_cases[16] = w_str_to_sym(w_rope_flatten(rope));
    }

    g_strlen_ready = 1;
}

static int64_t strlen_expected_for(int64_t index) {
    static const int64_t lengths[W_STRLEN_CASE_COUNT] = {
        0, 5, 2, 3, 6, 6, 80, 80, 81,
        0, 3, 3, 6, 6, 80, 80, 67
    };
    return (index >= 0 && index < W_STRLEN_CASE_COUNT) ? lengths[index] : -1;
}

WValue w_strlen_fixture(WValue index_value) {
    int64_t index = w_as_int(index_value);
    strlen_init_cases();
    if (index < 0 || index >= W_STRLEN_CASE_COUNT) return W_NIL;
    return g_strlen_cases[index];
}

WValue w_strlen_case_count(void) {
    return w_int(W_STRLEN_CASE_COUNT);
}

/* Build the generated-name autoload fixtures without an Array literal or a
 * loader-known WArray-producing ccall. The helper name is intentionally local
 * to this benchmark; its implementation still exercises the canonical native
 * constructor + push pair. */
WValue w_strlen_one_string_array(void) {
    WValue values = w_array_new_empty();
    w_array_push(values, w_string("a"));
    return values;
}

/* Delay a source-facade registration until after a regression has observed a
 * handle's public class. This benchmark-only bridge makes it possible to pin
 * same-process class stability; normal source class registrations happen in
 * generated main before top-level expressions execute. */
WValue w_class_identity_register_facade(WValue key_value, WValue klass) {
    /* ccall preserves a boxed dynamic argument but emits a compile-time raw
     * i64 for an integer literal. Accept those two exact benchmark spellings. */
    int64_t key;
    if (w_is_int(key_value)) key = w_as_int(key_value);
    else if (key_value <= UINT8_MAX) key = (int64_t)key_value;
    else abort();
    if (!w_is_class(klass)) abort();
    w_type_class_register_wv((int32_t)key, klass);
    return klass;
}

WValue w_class_identity_declare_unknown(void) {
    return w_class_new("Unknown", W_NIL);
}

/* Exercise a cold public Hash lookup without giving the source loader a
 * recognized Hash-producing call name. The late declaration intentionally
 * allocates a distinct same-name class and installs it under Hash's key. */
WValue w_class_identity_native_hash(void) {
    return w_hash_new();
}

WValue w_class_identity_declare_hash(void) {
    WValue klass = w_class_new("Hash", W_NIL);
    w_type_class_register_wv(W_SUBTAG_HASH, klass);
    return klass;
}

WValue w_class_identity_class_label(WValue klass) {
    if (klass == W_NIL) return w_string("nil");
    if (!w_is_class(klass)) abort();
    return w_string(((WClass *)w_as_ptr(klass))->name);
}

WValue w_strlen_fresh_rope(void) {
    return w_str_concat(strlen_heap_fill('l', 40),
                        strlen_heap_fill('r', 41));
}

WValue w_strlen_rope_flat_cached(WValue value) {
    if (!w_is_rope(value)) return W_FALSE;
    WRope *rope = (WRope *)w_as_ptr(value);
    return w_bool(rope->flat != W_NIL && rope->total_len == 81);
}

WValue w_strlen_expected(WValue index_value) {
    return w_int(strlen_expected_for(w_as_int(index_value)));
}

WValue w_strlen_reference(WValue value) {
    char inline_buf[6];
    const char *bytes;
    size_t len;
    w_str_data(value, inline_buf, &bytes, &len);
    (void)bytes;
    return w_int((int64_t)len);
}

WValue w_strlen_storage_mode(WValue value) {
    if (w_is_rope(value)) return w_int(8);
    if (!w_is_stringy(value)) return w_int(-1);
    return w_int((int64_t)((value >> 1) & 7));
}

WValue w_strlen_is_symbol(WValue value) {
    return w_bool(w_is_symbol(value));
}

WValue w_strlen_fixture_valid(WValue value, WValue index_value) {
    int64_t index = w_as_int(index_value);
    strlen_init_cases();
    if (index < 0 || index >= W_STRLEN_CASE_COUNT) return W_FALSE;
    if (value != g_strlen_cases[index]) return W_FALSE;
    if (index == 8) {
        if (!w_is_rope(value)) return W_FALSE;
        WRope *rope = (WRope *)w_as_ptr(value);
        return w_bool(rope->total_len == (uint32_t)strlen_expected_for(index));
    } else if (!w_is_stringy(value)) {
        return W_FALSE;
    }
    if ((index >= 9) != !!w_is_symbol(value)) return W_FALSE;
    char inline_buf[6];
    const char *bytes;
    size_t len;
    w_str_data(value, inline_buf, &bytes, &len);
    (void)bytes;
    return w_bool((int64_t)len == strlen_expected_for(index));
}

int64_t w_strlen_thread_cpu_ns(void) {
    struct timespec ts;
    if (clock_gettime(CLOCK_THREAD_CPUTIME_ID, &ts) != 0) abort();
    return (int64_t)ts.tv_sec * INT64_C(1000000000) + (int64_t)ts.tv_nsec;
}
