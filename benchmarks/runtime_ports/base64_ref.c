/*
 * Benchmark-only copies of the four C codecs removed from runtime.c. The
 * production runtime exposes storage only; these functions let base64_ab.w
 * compare the source loops against the former implementation through sibling
 * Base64 class methods.
 */

#include "runtime.h"

#include <stdint.h>
#include <stdlib.h>
#include <string.h>

static const char ref_b64_chars[] =
    "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
static const char ref_b64url_chars[] =
    "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_";

static void ref_encode_input(WValue data, const uint8_t **input,
                             int64_t *input_len, char inline_buf[6]) {
    if (w_is_bytes(data)) {
        WArray *a = (WArray *)w_as_ptr(data);
        /* Deliberately mirrors the old body, including its start==0
         * assumption; the parity corpus uses owned, unsliced inputs. */
        *input = (const uint8_t *)a->slots;
        *input_len = a->size;
        return;
    }
    const char *str;
    size_t stored_len;
    w_str_data(data, inline_buf, &str, &stored_len);
    (void)stored_len;
    *input = (const uint8_t *)str;
    *input_len = (int64_t)strlen(str); /* former embedded-NUL truncation */
}

static WValue ref_encode(WValue data, const char alphabet[65], int padded) {
    const uint8_t *input;
    int64_t input_len;
    char inline_buf[6];
    ref_encode_input(data, &input, &input_len, inline_buf);

    int64_t cap = ((input_len + 2) / 3) * 4;
    char *out = malloc((size_t)cap + 1);
    int64_t j = 0;
    for (int64_t i = 0; i < input_len; i += 3) {
        uint32_t triple = ((uint32_t)input[i]) << 16;
        if (i + 1 < input_len) triple |= ((uint32_t)input[i + 1]) << 8;
        if (i + 2 < input_len) triple |= (uint32_t)input[i + 2];
        out[j++] = alphabet[(triple >> 18) & 0x3f];
        out[j++] = alphabet[(triple >> 12) & 0x3f];
        if (i + 1 < input_len) out[j++] = alphabet[(triple >> 6) & 0x3f];
        else if (padded) out[j++] = '=';
        if (i + 2 < input_len) out[j++] = alphabet[triple & 0x3f];
        else if (padded) out[j++] = '=';
    }
    out[j] = '\0';
    WValue result = w_string(out);
    free(out);
    return result;
}

static int ref_decode_char(unsigned char c, int url_safe) {
    if (c >= 'A' && c <= 'Z') return c - 'A';
    if (c >= 'a' && c <= 'z') return c - 'a' + 26;
    if (c >= '0' && c <= '9') return c - '0' + 52;
    if (url_safe && c == '-') return 62;
    if (url_safe && c == '_') return 63;
    if (!url_safe && c == '+') return 62;
    if (!url_safe && c == '/') return 63;
    return -1;
}

static WValue ref_decode(WValue text, int url_safe) {
    char inline_buf[6];
    const char *input;
    size_t stored_len;
    w_str_data(text, inline_buf, &input, &stored_len);
    (void)stored_len;
    int64_t input_len = (int64_t)strlen(input);
    while (input_len > 0 && input[input_len - 1] == '=') input_len--;

    int64_t out_len = input_len * 3 / 4;
    uint8_t *out = malloc((size_t)(out_len > 0 ? out_len : 1));
    int64_t j = 0;
    for (int64_t i = 0; i < input_len; i += 4) {
        int a = ref_decode_char((unsigned char)input[i], url_safe);
        int b = i + 1 < input_len ? ref_decode_char((unsigned char)input[i + 1], url_safe) : 0;
        int c = i + 2 < input_len ? ref_decode_char((unsigned char)input[i + 2], url_safe) : 0;
        int d = i + 3 < input_len ? ref_decode_char((unsigned char)input[i + 3], url_safe) : 0;
        if (a < 0 || b < 0 || c < 0 || d < 0)
            w_raise(w_string(url_safe ? "base64url: invalid character"
                                      : "base64: invalid character"));
        uint32_t triple = ((uint32_t)a << 18) | ((uint32_t)b << 12) |
                          ((uint32_t)c << 6) | (uint32_t)d;
        if (j < out_len) out[j++] = (uint8_t)(triple >> 16);
        if (j < out_len) out[j++] = (uint8_t)(triple >> 8);
        if (j < out_len) out[j++] = (uint8_t)triple;
    }
    WValue result = w_bytes_from_data(out, out_len);
    free(out); /* The removed C body leaked this temporary. */
    return result;
}

WValue w_ref_base64_encode(WValue data) {
    return ref_encode(data, ref_b64_chars, 1);
}

WValue w_ref_base64url_encode(WValue data) {
    return ref_encode(data, ref_b64url_chars, 0);
}

WValue w_ref_base64_decode(WValue text) { return ref_decode(text, 0); }
WValue w_ref_base64url_decode(WValue text) { return ref_decode(text, 1); }
