/*
 * Benchmark-only reference for the current Array#join IC handler.
 *
 * The public runtime function is static, so this file mirrors its two-pass
 * loop and typed-array decoder through exported runtime primitives.  Keep the
 * reference out of production: it is linked only by run_array_join.sh through
 * TUNGSTEN_C_INCLUDES.
 */

#include "runtime.h"

#include <stdint.h>
#include <stdlib.h>
#include <string.h>

static int64_t join_ref_storage_bits(int64_t bits) {
    if (bits == -116) return 16;
    if (bits == -108 || bits == -109) return 8;
    if (bits == -104) return 4;
    if (bits == 108) return 8;
    if (bits == 116) return 16;
    if (bits == 33) return 32;
    if (bits == 66) return 64;
    if (bits < 0) return -bits;
    if (bits == 65) return 64;
    return bits;
}

static uint64_t join_ref_array_read(WArray *array, int64_t index) {
    uint8_t *bytes = (uint8_t *)array->slots;
    switch (join_ref_storage_bits(array->ebits)) {
        case 1:  return (bytes[index >> 3] >> (index & 7)) & 1;
        case 4:  {
            uint8_t byte = bytes[index >> 1];
            return (index & 1) ? (byte >> 4) : (byte & 0xF);
        }
        case 8:  return bytes[index];
        case 16: return ((uint16_t *)bytes)[index];
        case 32: return ((uint32_t *)bytes)[index];
        case 64: return ((uint64_t *)bytes)[index];
        default: return 0;
    }
}

static double join_ref_array_read_float(WArray *array, int64_t index) {
    uint8_t *bytes = (uint8_t *)array->slots;
    if (array->ebits == -32) return (double)((float *)bytes)[index];
    if (array->ebits == -116) {
        uint32_t bits = (uint32_t)((uint16_t *)bytes)[index] << 16;
        float value;
        memcpy(&value, &bits, sizeof(value));
        return (double)value;
    }
    return ((double *)bytes)[index];
}

static WValue join_ref_array_load(WArray *array, int64_t index) {
    int64_t absolute = array->start + index;
    if (array->ebits == 65)
        return (WValue)join_ref_array_read(array, absolute);
    if (array->ebits == -32 || array->ebits == -64 || array->ebits == -116)
        return w_float(join_ref_array_read_float(array, absolute));
    if (array->ebits == -4 || array->ebits == 108 || array->ebits == 116 ||
        array->ebits == 33 || array->ebits == 66) {
        uint64_t raw = join_ref_array_read(array, absolute);
        int64_t bits = join_ref_storage_bits(array->ebits);
        int64_t value;
        if (bits >= 64) {
            value = (int64_t)raw;
        } else {
            uint64_t sign = 1ULL << (bits - 1);
            value = (int64_t)((raw ^ sign) - sign);
        }
        return w_int(value);
    }
    if (array->ebits == 1)
        return join_ref_array_read(array, absolute) ? W_TRUE : W_FALSE;
    return w_int((int64_t)join_ref_array_read(array, absolute));
}

/* as_str is static in runtime.c.  This is the same rotating inline-string
 * extraction contract.  The invalid branch deliberately enters the real
 * StringBuffer/as_str boundary so fatal-vs-catchable error behavior and the
 * message stay aligned with the production handler. */
static const char *join_ref_as_str(WValue value) {
    static __thread char buffers[4][6];
    static __thread int next_buffer = 0;
    if (w_is_rope(value)) value = w_rope_flatten(value);
    if (w_is_stringy(value)) {
        char *buffer = buffers[next_buffer];
        const char *text;
        size_t length;
        next_buffer = (next_buffer + 1) & 3;
        w_str_data(value, buffer, &text, &length);
        (void)length;
        return text;
    }

    WValue validation_buffer = w_strbuf_new(w_int(16));
    (void)w_strbuf_append(validation_buffer, value);
    abort(); /* w_strbuf_append's as_str error never returns */
}

/* Benchmark-only raw validation boundary for v6. This is deliberately the
 * exact operation performed by each sizing-pass term in the original IC:
 * accept String/Symbol/rope storage through as_str, then stop at the first
 * embedded NUL through strlen. It returns an unboxed i64 so the candidate does
 * not pay for an otherwise-unused WValue length. */
int64_t w_bench_as_str_length(WValue value) {
    return (int64_t)strlen(join_ref_as_str(value));
}

/* w_string_take is static too.  Reproduce its representation rule exactly:
 * <=5 bytes inline; 6..61 bytes interned while the slab is open; otherwise a
 * fresh mode-7 heap string.  In particular, a frozen slab must NOT return an
 * already-interned mode-6 value, unlike w_string(). */
static WValue join_ref_string_take(char *text, size_t length) {
    if (length <= 5) {
        WValue result = w_string(text);
        free(text);
        return result;
    }

    if (w_slab_is_frozen() || length > W_SLAB_SSO2_MAX) {
        WString *string = malloc(sizeof(WString) + length + 1);
        string->len = (uint32_t)length;
        memcpy(string->data, text, length + 1);
        free(text);
        return w_box_heap_str(string);
    }

    WValue result = w_string(text);
    free(text);
    return result;
}

static WValue join_ref_array_join(WValue receiver, WValue separator_value,
                                  int has_separator) {
    if (!w_is_array(receiver)) {
        /* Enter the runtime's exact Array validation path. */
        (void)w_array_size(receiver);
        abort();
    }
    WArray *array = (WArray *)w_as_ptr(receiver);

    const char *separator_tmp = "";
    if (has_separator) separator_tmp = join_ref_as_str(separator_value);
    size_t separator_length = strlen(separator_tmp);
    char *separator = malloc(separator_length + 1);
    memcpy(separator, separator_tmp, separator_length + 1);

    size_t total = 0;
    for (int32_t i = 0; i < array->size; i++) {
        WValue text = w_to_s(join_ref_array_load(array, i));
        total += strlen(join_ref_as_str(text));
        if (i > 0) total += separator_length;
    }

    char *result = malloc(total + 1);
    result[0] = '\0';
    for (int32_t i = 0; i < array->size; i++) {
        if (i > 0) strcat(result, separator);
        WValue text = w_to_s(join_ref_array_load(array, i));
        strcat(result, join_ref_as_str(text));
    }

    free(separator);
    return join_ref_string_take(result, strlen(result));
}

WValue w_ref_array_join0(WValue receiver) {
    return join_ref_array_join(receiver, W_NIL, 0);
}

WValue w_ref_array_join1(WValue receiver, WValue separator) {
    return join_ref_array_join(receiver, separator, 1);
}

/* Benchmark-only storage boundary for v3. Explicit-receiver view fields are
 * read-only in today's parser/lowering (`buf$length` can load but cannot be an
 * assignment target), and StringBuffer#clear has no runtime/lowering helper.
 * Keep this reset out of production until the candidate clears its gate. */
WValue w_bench_strbuf_reset(WValue buffer) {
    WStrBuf *strbuf = (WStrBuf *)w_as_ptr(buffer);
    strbuf->size = 0;
    strbuf->data[0] = '\0';
    return buffer;
}

WValue w_bench_strbuf_size(WValue buffer) {
    WStrBuf *strbuf = (WStrBuf *)w_as_ptr(buffer);
    return w_int(strbuf->size);
}

WValue w_bench_strbuf_capacity(WValue buffer) {
    WStrBuf *strbuf = (WStrBuf *)w_as_ptr(buffer);
    return w_int(strbuf->cap);
}

/* Release only fresh mode-7 String results.  Inline and slab strings are
 * values/permanent intern entries and must not be freed.  Cleanup is called
 * between bounded batches, outside every timed interval. */
WValue w_ref_array_join_release_batch(WValue batch_value, WValue count_value) {
    if (!w_is_array(batch_value)) {
        w_raise(w_string("Array#join benchmark batch is not an Array"));
        return W_NIL;
    }
    WArray *batch = (WArray *)w_as_ptr(batch_value);
    int64_t count = w_as_int(count_value);
    if (batch->ebits != 65 || count < 0 || count > batch->size) {
        w_raise(w_string("Array#join benchmark batch shape is invalid"));
        return W_NIL;
    }

    for (int64_t i = 0; i < count; i++) {
        int64_t slot = (int64_t)batch->start + i;
        WValue value = batch->slots[slot];
        if (!w_is_string(value)) {
            w_raise(w_string("Array#join benchmark result is not a String"));
            return W_NIL;
        }
        if (w_is_heap_str(value)) free(w_as_heap_str(value));
        batch->slots[slot] = W_NIL;
    }
    return W_NIL;
}
