/*
 * Benchmark-only copies of Array/Hash combinators migrated from runtime.c to
 * core/traits/enumerable.w. Keep the loop bodies equivalent to the removed IC
 * handlers; the local decoder is the old array_slot_load_decoded helper made
 * translation-unit-local so typed arrays exercise the same behavior.
 */

#include "runtime.h"
#include <string.h>

static int64_t ref_storage_bits(int64_t bits) {
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

static uint64_t ref_array_read(WArray *array, int64_t index) {
    uint8_t *bytes = (uint8_t *)array->slots;
    switch (ref_storage_bits(array->ebits)) {
        case 1:  return (bytes[index >> 3] >> (index & 7)) & 1;
        case 4:  { uint8_t byte = bytes[index >> 1];
                   return (index & 1) ? (byte >> 4) : (byte & 0xF); }
        case 8:  return bytes[index];
        case 16: return ((uint16_t *)bytes)[index];
        case 32: return ((uint32_t *)bytes)[index];
        case 64: return ((uint64_t *)bytes)[index];
        default: return 0;
    }
}

static double ref_array_read_float(WArray *array, int64_t index) {
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

static WValue ref_array_load(WArray *array, int64_t index) {
    int64_t absolute = array->start + index;
    if (array->ebits == 65) return (WValue)ref_array_read(array, absolute);
    if (array->ebits == -32 || array->ebits == -64 || array->ebits == -116)
        return w_float(ref_array_read_float(array, absolute));
    if (array->ebits == -4 || array->ebits == 108 || array->ebits == 116 ||
        array->ebits == 33 || array->ebits == 66) {
        uint64_t raw = ref_array_read(array, absolute);
        int64_t bits = ref_storage_bits(array->ebits);
        int64_t value;
        if (bits >= 64) value = (int64_t)raw;
        else {
            uint64_t sign = 1ULL << (bits - 1);
            value = (int64_t)((raw ^ sign) - sign);
        }
        return w_int(value);
    }
    if (array->ebits == 1)
        return ref_array_read(array, absolute) ? W_TRUE : W_FALSE;
    return w_int((int64_t)ref_array_read(array, absolute));
}

WValue w_ref_array_map(WValue receiver, WValue block) {
    WArray *array = (WArray *)w_as_ptr(receiver);
    WValue result = w_array_new_empty();
    for (int32_t i = 0; i < array->size; i++)
        w_array_push(result, w_closure_call_1(block, ref_array_load(array, i)));
    return result;
}

WValue w_ref_array_select(WValue receiver, WValue block) {
    WArray *array = (WArray *)w_as_ptr(receiver);
    WValue result = w_array_new_empty();
    for (int32_t i = 0; i < array->size; i++) {
        WValue value = ref_array_load(array, i);
        if (w_truthy(w_closure_call_1(block, value))) w_array_push(result, value);
    }
    return result;
}

WValue w_ref_array_reject(WValue receiver, WValue block) {
    WArray *array = (WArray *)w_as_ptr(receiver);
    WValue result = w_array_new_empty();
    for (int32_t i = 0; i < array->size; i++) {
        WValue value = ref_array_load(array, i);
        if (!w_truthy(w_closure_call_1(block, value))) w_array_push(result, value);
    }
    return result;
}

WValue w_ref_array_find(WValue receiver, WValue block) {
    WArray *array = (WArray *)w_as_ptr(receiver);
    for (int32_t i = 0; i < array->size; i++) {
        WValue value = ref_array_load(array, i);
        if (w_truthy(w_closure_call_1(block, value))) return value;
    }
    return W_NIL;
}

WValue w_ref_array_reduce(WValue receiver, WValue initial, WValue block) {
    WArray *array = (WArray *)w_as_ptr(receiver);
    WValue accumulator = initial;
    for (int32_t i = 0; i < array->size; i++)
        accumulator = w_closure_call_2(block, accumulator, ref_array_load(array, i));
    return accumulator;
}

WValue w_ref_array_each_with_index(WValue receiver, WValue block) {
    WArray *array = (WArray *)w_as_ptr(receiver);
    for (int32_t i = 0; i < array->size; i++)
        w_closure_call_2(block, ref_array_load(array, i), w_int(i));
    return receiver;
}

WValue w_ref_array_group_by(WValue receiver, WValue block) {
    WArray *array = (WArray *)w_as_ptr(receiver);
    WValue result = w_hash_new();
    for (int32_t i = 0; i < array->size; i++) {
        WValue value = ref_array_load(array, i);
        WValue key = w_closure_call_1(block, value);
        WValue bucket = w_hash_get(result, key);
        if (bucket == W_NIL || !w_is_array(bucket)) {
            bucket = w_array_new_empty();
            w_hash_set(result, key, bucket);
        }
        w_array_push(bucket, value);
    }
    return result;
}

WValue w_ref_array_partition(WValue receiver, WValue block) {
    WArray *array = (WArray *)w_as_ptr(receiver);
    WValue yes = w_array_new_empty();
    WValue no = w_array_new_empty();
    for (int32_t i = 0; i < array->size; i++) {
        WValue value = ref_array_load(array, i);
        if (w_truthy(w_closure_call_1(block, value))) w_array_push(yes, value);
        else w_array_push(no, value);
    }
    WValue result = w_array_new_empty();
    w_array_push(result, yes);
    w_array_push(result, no);
    return result;
}

WValue w_ref_array_tally(WValue receiver) {
    WArray *array = (WArray *)w_as_ptr(receiver);
    WValue result = w_hash_new();
    for (int32_t i = 0; i < array->size; i++) {
        WValue key = ref_array_load(array, i);
        WValue existing = w_hash_get(result, key);
        if (existing == W_NIL) w_hash_set(result, key, w_int(1));
        else w_hash_set(result, key, w_int(w_as_int(existing) + 1));
    }
    return result;
}

WValue w_ref_array_flat_map(WValue receiver, WValue block) {
    WArray *array = (WArray *)w_as_ptr(receiver);
    WValue result = w_array_new_empty();
    for (int32_t i = 0; i < array->size; i++) {
        WValue sub = w_closure_call_1(block, ref_array_load(array, i));
        if (w_is_array(sub)) {
            WArray *subarray = (WArray *)w_as_ptr(sub);
            for (int32_t j = 0; j < subarray->size; j++)
                w_array_push(result, ref_array_load(subarray, j));
        } else {
            w_array_push(result, sub);
        }
    }
    return result;
}

WValue w_ref_hash_map(WValue receiver, WValue block) {
    WHash *hash = (WHash *)w_as_ptr(receiver);
    WValue result = w_array_new_empty();
    for (uint32_t i = 0; i < hash->cap; i++) {
        if (hash->keys[i] != W_UNDEF && hash->keys[i] != W_MEMO_MISS)
            w_array_push(result,
                         w_closure_call_2(block, hash->keys[i], hash->values[i]));
    }
    return result;
}
