#ifndef W_RUNTIME_UNITY_INCLUDE
#ifdef __linux__
#define _GNU_SOURCE
#endif
#include "runtime_internal.h"
#include <ctype.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#define w_string_take w_rt_string_take
#endif

/* ---- Algebra source notation -------------------------------------------
 *
 * Algebra declarations are deliberately recognized before the general lexer:
 *
 *   C⊂ℙ²_ℚ(X,Y,Z):16X³Z+48XY²Z-3Y⁴=0
 *
 * The declared coordinates make adjacency unambiguous, so this pass can
 * lower coefficient+symbol spans directly to Polynomial operations without
 * installing global implicit multiplication or numeric reverse dispatch.
 * It also lowers projective point notation P2[1:0:0] to P2.point(1,0,0).
 *
 * The rewrite preserves one input line per output line. Ordinary sources take
 * the zero-allocation return-original fast path.
 */
typedef struct {
    char *data;
    size_t len;
    size_t cap;
} WAlgebraBuf;

static void algebra_buf_need(WAlgebraBuf *b, size_t extra) {
    if (b->len + extra + 1 <= b->cap) return;
    size_t cap = b->cap ? b->cap : 256;
    while (cap < b->len + extra + 1) cap *= 2;
    b->data = realloc(b->data, cap);
    b->cap = cap;
}

static void algebra_buf_bytes(WAlgebraBuf *b, const char *s, size_t n) {
    algebra_buf_need(b, n);
    memcpy(b->data + b->len, s, n);
    b->len += n;
}

static void algebra_buf_c(WAlgebraBuf *b, char c) {
    algebra_buf_need(b, 1);
    b->data[b->len++] = c;
}

static void algebra_buf_s(WAlgebraBuf *b, const char *s) {
    algebra_buf_bytes(b, s, strlen(s));
}

static int algebra_utf8_minus(const char *s, size_t n, size_t i) {
    return i + 3 <= n &&
           (unsigned char)s[i] == 0xe2 &&
           (unsigned char)s[i + 1] == 0x88 &&
           (unsigned char)s[i + 2] == 0x92;
}

static int algebra_superscript_digit(const char *s, size_t n, size_t i,
                                     int *digit, size_t *width) {
    if (i + 2 <= n && (unsigned char)s[i] == 0xc2) {
        unsigned char c = (unsigned char)s[i + 1];
        if (c == 0xb9) { *digit = 1; *width = 2; return 1; }
        if (c == 0xb2) { *digit = 2; *width = 2; return 1; }
        if (c == 0xb3) { *digit = 3; *width = 2; return 1; }
    }
    if (i + 3 <= n &&
        (unsigned char)s[i] == 0xe2 &&
        (unsigned char)s[i + 1] == 0x81) {
        unsigned char c = (unsigned char)s[i + 2];
        if (c == 0xb0) { *digit = 0; *width = 3; return 1; }
        if (c >= 0xb4 && c <= 0xb9) {
            *digit = (int)(c - 0xb0);
            *width = 3;
            return 1;
        }
    }
    return 0;
}

/* Parse ℙⁿ_ℚ (and the ASCII-exponent spelling ℙ^n_ℚ) at `start`.
 * The coefficient field is intentionally explicit here: other fields are
 * accepted by the generic constructors below and rejected by Algebra.field
 * until their implementations exist, but curve declarations currently have
 * a certified ℚ grammar only. */
static int algebra_projective_q_at(const char *s, size_t n, size_t start,
                                   unsigned long long *dimension,
                                   size_t *end) {
    static const unsigned char projective[] = {0xe2, 0x84, 0x99};
    static const unsigned char rational[] = {0xe2, 0x84, 0x9a};
    if (start + sizeof(projective) > n ||
        memcmp(s + start, projective, sizeof(projective)) != 0)
        return 0;

    size_t p = start + sizeof(projective);
    unsigned long long value = 0;
    int have_dimension = 0;
    if (p < n && s[p] == '^') {
        p++;
        while (p < n && isdigit((unsigned char)s[p])) {
            have_dimension = 1;
            value = value * 10ULL + (unsigned)(s[p] - '0');
            p++;
        }
    } else {
        int digit;
        size_t width;
        while (algebra_superscript_digit(s, n, p, &digit, &width)) {
            have_dimension = 1;
            value = value * 10ULL + (unsigned)digit;
            p += width;
        }
    }
    if (!have_dimension || p >= n || s[p] != '_')
        return 0;
    p++;
    if (p + sizeof(rational) > n ||
        memcmp(s + p, rational, sizeof(rational)) != 0)
        return 0;
    p += sizeof(rational);
    *dimension = value;
    *end = p;
    return 1;
}

typedef struct {
    const char *ptr;
    size_t len;
} WAlgebraName;

static int algebra_name_at(const char *s, size_t n, size_t pos,
                           const WAlgebraName *names, int count) {
    int best = -1;
    for (int i = 0; i < count; i++) {
        if (pos + names[i].len <= n &&
            memcmp(s + pos, names[i].ptr, names[i].len) == 0 &&
            (best < 0 || names[i].len > names[best].len))
            best = i;
    }
    return best;
}

static void algebra_emit_uint(WAlgebraBuf *out, unsigned long long value) {
    char buf[32];
    int n = snprintf(buf, sizeof(buf), "%llu", value);
    algebra_buf_bytes(out, buf, (size_t)n);
}

/* Rewrite the intentionally local polynomial grammar used after `:`:
 * signed sums of rational coefficients and adjacent declared coordinates with
 * Unicode superscript or ASCII ^ powers. This grammar is never installed as
 * global implicit multiplication. */
static void algebra_rewrite_polynomial(WAlgebraBuf *out,
                                       const char *s, size_t n,
                                       const WAlgebraName *names, int count,
                                       const char *coords_temp) {
    size_t p = 0;
    int first = 1;
    while (p < n) {
        while (p < n && (s[p] == ' ' || s[p] == '\t')) p++;
        int negative = 0;
        if (p < n && s[p] == '+') {
            p++;
        } else if (p < n && s[p] == '-') {
            negative = 1; p++;
        } else if (algebra_utf8_minus(s, n, p)) {
            negative = 1; p += 3;
        }
        while (p < n && (s[p] == ' ' || s[p] == '\t')) p++;

        size_t term_end = p;
        while (term_end < n &&
               s[term_end] != '+' && s[term_end] != '-' &&
               !algebra_utf8_minus(s, n, term_end))
            term_end++;
        while (term_end > p &&
               (s[term_end - 1] == ' ' || s[term_end - 1] == '\t'))
            term_end--;

        if (!first) algebra_buf_s(out, negative ? " - " : " + ");
        else if (negative) algebra_buf_c(out, '-');
        first = 0;
        size_t term_out_start = out->len;

        size_t q = p;
        int coefficient_parenthesized = 0;
        if (q < term_end && s[q] == '(') {
            coefficient_parenthesized = 1;
            q++;
        }
        unsigned long long coefficient_num = 0;
        unsigned long long coefficient_den = 1;
        int have_coefficient = 0;
        while (q < term_end && s[q] >= '0' && s[q] <= '9') {
            have_coefficient = 1;
            coefficient_num = coefficient_num * 10ULL + (unsigned)(s[q] - '0');
            q++;
            if (q < term_end && s[q] == '_') q++;
        }
        if (have_coefficient && q < term_end && s[q] == '/') {
            q++;
            coefficient_den = 0;
            int have_denominator = 0;
            while (q < term_end && s[q] >= '0' && s[q] <= '9') {
                have_denominator = 1;
                coefficient_den = coefficient_den * 10ULL +
                                  (unsigned)(s[q] - '0');
                q++;
                if (q < term_end && s[q] == '_') q++;
            }
            if (!have_denominator || coefficient_den == 0) {
                algebra_buf_bytes(out, s + p, term_end - p);
                p = term_end;
                continue;
            }
        }
        if (coefficient_parenthesized) {
            if (q >= term_end || s[q] != ')') {
                algebra_buf_bytes(out, s + p, term_end - p);
                p = term_end;
                continue;
            }
            q++;
        }
        while (q < term_end && (s[q] == ' ' || s[q] == '\t')) q++;

        int factors = 0;
        while (q < term_end) {
            int ni = algebra_name_at(s, term_end, q, names, count);
            if (ni < 0) break;
            if (factors++) algebra_buf_c(out, '*');
            algebra_buf_s(out, coords_temp);
            algebra_buf_c(out, '[');
            algebra_emit_uint(out, (unsigned long long)ni);
            algebra_buf_c(out, ']');
            q += names[ni].len;

            unsigned long long exponent = 0;
            int have_exponent = 0;
            if (q < term_end && s[q] == '^') {
                q++;
                if (q < term_end && s[q] == '*') q++;
                while (q < term_end && isdigit((unsigned char)s[q])) {
                    have_exponent = 1;
                    exponent = exponent * 10ULL + (unsigned)(s[q] - '0');
                    q++;
                }
            } else {
                int digit;
                size_t width;
                while (algebra_superscript_digit(s, term_end, q, &digit, &width)) {
                    have_exponent = 1;
                    exponent = exponent * 10ULL + (unsigned)digit;
                    q += width;
                }
            }
            if (have_exponent && exponent != 1) {
                algebra_buf_s(out, "**");
                algebra_emit_uint(out, exponent);
            }
            while (q < term_end && (s[q] == ' ' || s[q] == '\t')) q++;
        }

        if (q != term_end) {
            /* Keep unsupported structure visible to the ordinary parser. */
            out->len = term_out_start;
            algebra_buf_bytes(out, s + p, term_end - p);
        } else if (factors) {
            if (have_coefficient &&
                (coefficient_num != 1 || coefficient_den != 1)) {
                algebra_buf_c(out, '*');
                if (coefficient_den == 1) {
                    algebra_emit_uint(out, coefficient_num);
                } else {
                    algebra_buf_s(out, "Rational.new(");
                    algebra_emit_uint(out, coefficient_num);
                    algebra_buf_c(out, ',');
                    algebra_emit_uint(out, coefficient_den);
                    algebra_buf_c(out, ')');
                }
            }
        } else if (have_coefficient) {
            if (coefficient_den == 1) {
                algebra_emit_uint(out, coefficient_num);
            } else {
                algebra_buf_s(out, "Rational.new(");
                algebra_emit_uint(out, coefficient_num);
                algebra_buf_c(out, ',');
                algebra_emit_uint(out, coefficient_den);
                algebra_buf_c(out, ')');
            }
        } else {
            /* Keep unsupported structure visible to the ordinary parser,
             * which will report the source error instead of silently changing
             * the equation. */
            algebra_buf_bytes(out, s + p, term_end - p);
        }
        p = term_end;
    }
}

static size_t algebra_trim_left(const char *s, size_t a, size_t b) {
    while (a < b && (s[a] == ' ' || s[a] == '\t')) a++;
    return a;
}

static size_t algebra_trim_right(const char *s, size_t a, size_t b) {
    while (b > a && (s[b - 1] == ' ' || s[b - 1] == '\t')) b--;
    return b;
}

static int algebra_rewrite_curve_line(WAlgebraBuf *out,
                                      const char *line, size_t n,
                                      unsigned long long declaration_id) {
    static const unsigned char subset[] = {0xe2, 0x8a, 0x82};
    size_t lead = 0;
    while (lead < n && (line[lead] == ' ' || line[lead] == '\t')) lead++;
    if (lead >= n || line[lead] == '#') return 0;

    size_t sub = lead;
    while (sub + sizeof(subset) <= n &&
           memcmp(line + sub, subset, sizeof(subset)) != 0)
        sub++;
    if (sub + sizeof(subset) > n) return 0;

    size_t curve_a = lead;
    size_t curve_b = algebra_trim_right(line, curve_a, sub);
    if (curve_b <= curve_a) return 0;
    for (size_t i = curve_a; i < curve_b; i++) {
        unsigned char c = (unsigned char)line[i];
        if (!(isalnum(c) || c == '_')) return 0;
    }

    size_t p = algebra_trim_left(line, sub + sizeof(subset), n);
    unsigned long long dimension = 0;
    size_t projective_end = 0;
    if (!algebra_projective_q_at(line, n, p, &dimension, &projective_end))
        return 0;
    p = algebra_trim_left(line, projective_end, n);
    if (p >= n || line[p] != '(') return 0;
    size_t coords_a = ++p;
    while (p < n && line[p] != ')') p++;
    if (p >= n) return 0;
    size_t coords_b = p++;
    p = algebra_trim_left(line, p, n);
    if (p >= n || line[p] != ':') return 0;
    size_t poly_a = algebra_trim_left(line, p + 1, n);
    size_t eq = poly_a;
    while (eq < n && line[eq] != '=') eq++;
    if (eq >= n) return 0;
    size_t poly_b = algebra_trim_right(line, poly_a, eq);
    size_t rhs_a = algebra_trim_left(line, eq + 1, n);
    size_t rhs_b = algebra_trim_right(line, rhs_a, n);

    WAlgebraName names[32];
    int name_count = 0;
    size_t ca = coords_a;
    while (ca < coords_b && name_count < 32) {
        ca = algebra_trim_left(line, ca, coords_b);
        size_t cb = ca;
        while (cb < coords_b && line[cb] != ',') cb++;
        size_t end = algebra_trim_right(line, ca, cb);
        if (end <= ca || end - ca >= 32) return 0;
        names[name_count].ptr = line + ca;
        names[name_count].len = end - ca;
        name_count++;
        ca = cb < coords_b ? cb + 1 : cb;
    }
    if (ca < coords_b || name_count < 1) return 0;
    int affine = name_count == (int)dimension;
    if (!affine && name_count != (int)dimension + 1) return 0;

    char space_temp[64];
    char coords_temp[64];
    snprintf(space_temp, sizeof(space_temp), "__algebra_space_%llu",
             declaration_id);
    snprintf(coords_temp, sizeof(coords_temp), "__algebra_coords_%llu",
             declaration_id);

    algebra_buf_bytes(out, line, lead);
    algebra_buf_s(out, space_temp);
    algebra_buf_s(out, "=ProjectiveSpace<ℚ,");
    algebra_emit_uint(out, dimension);
    algebra_buf_s(out, ">.new(Algebra.rational_field(),");
    algebra_emit_uint(out, dimension);
    algebra_buf_s(out, ",[");
    for (int i = 0; i < name_count; i++) {
        if (i > 0) algebra_buf_c(out, ',');
        algebra_buf_c(out, ':');
        algebra_buf_bytes(out, names[i].ptr, names[i].len);
    }
    if (affine) {
        if (name_count > 0) algebra_buf_c(out, ',');
        algebra_buf_s(out, dimension == 2 ? ":Z" : ":H");
    }
    algebra_buf_s(out, "]);");
    algebra_buf_s(out, coords_temp);
    algebra_buf_c(out, '=');
    algebra_buf_s(out, space_temp);
    algebra_buf_s(out, ".coords;");
    algebra_buf_bytes(out, line + curve_a, curve_b - curve_a);
    algebra_buf_s(out, affine ? "=Curve.affine(" : "=Curve.new(");
    algebra_buf_s(out, space_temp);
    algebra_buf_s(out, ",(");
    algebra_rewrite_polynomial(out, line + poly_a, poly_b - poly_a,
                               names, name_count, coords_temp);
    algebra_buf_s(out, ")-(");
    algebra_rewrite_polynomial(out, line + rhs_a, rhs_b - rhs_a,
                               names, name_count, coords_temp);
    algebra_buf_s(out, "))");
    return 1;
}

static int algebra_point_content(const char *s, size_t a, size_t b) {
    int colons = 0;
    for (size_t i = a; i < b; i++) {
        unsigned char c = (unsigned char)s[i];
        if (c == ':') { colons++; continue; }
        if (isdigit(c) || c == ' ' || c == '\t' || c == '+' || c == '-' ||
            c == '/' || c == '_')
            continue;
        return 0;
    }
    return colons >= 1;
}

static int algebra_generic_new_at(const char *s, size_t n, size_t start,
                                  const char *class_name, int needs_dimension,
                                  size_t *field_a, size_t *field_b,
                                  unsigned long long *dimension,
                                  size_t *after_open) {
    size_t class_len = strlen(class_name);
    if (start + class_len >= n ||
        memcmp(s + start, class_name, class_len) != 0)
        return 0;
    size_t p = start + class_len;
    if (p >= n || s[p] != '<') return 0;
    p++;
    p = algebra_trim_left(s, p, n);
    *field_a = p;
    while (p < n && s[p] != ',' && s[p] != '>') p++;
    *field_b = algebra_trim_right(s, *field_a, p);
    if (*field_b <= *field_a) return 0;

    *dimension = 0;
    if (needs_dimension) {
        if (p >= n || s[p] != ',') return 0;
        p = algebra_trim_left(s, p + 1, n);
        int have_dimension = 0;
        while (p < n && isdigit((unsigned char)s[p])) {
            have_dimension = 1;
            *dimension = *dimension * 10ULL + (unsigned)(s[p] - '0');
            p++;
        }
        p = algebra_trim_left(s, p, n);
        if (!have_dimension) return 0;
    }
    if (p >= n || s[p] != '>') return 0;
    p++;
    if (p + 5 > n || memcmp(s + p, ".new(", 5) != 0) return 0;
    *after_open = p + 5;
    return 1;
}

/* Find the ')' paired with a generic constructor's `.new(`. Constructor
 * rewrites pack user arguments into one Array because native rest-parameter
 * binding is not yet reliable for arbitrary arity. Keeping this scanner local
 * to one line also prevents algebra syntax from changing unrelated grouping. */
static int algebra_matching_paren(const char *s, size_t n, size_t after_open,
                                  size_t *close) {
    int depth = 1;
    int quote = 0;
    for (size_t i = after_open; i < n; i++) {
        unsigned char c = (unsigned char)s[i];
        if (quote) {
            if (c == (unsigned char)quote &&
                (i == 0 || s[i - 1] != '\\'))
                quote = 0;
            continue;
        }
        if (c == '"' || c == '\'') {
            quote = c;
            continue;
        }
        if (c == '(') {
            depth++;
        } else if (c == ')') {
            depth--;
            if (depth == 0) {
                *close = i;
                return 1;
            }
        }
    }
    return 0;
}

/* Generated constructors already carry their runtime field metadata. Leaving
 * them untouched makes the source transformation idempotent and also permits
 * callers inside the algebra implementation to use the lowered object API
 * explicitly. */
static int algebra_constructor_arguments_lowered(const char *s, size_t a,
                                                 size_t b) {
    static const char field[] = "Algebra.field(";
    static const char rational_field[] = "Algebra.rational_field(";
    a = algebra_trim_left(s, a, b);
    if (a + sizeof(field) - 1 <= b &&
        memcmp(s + a, field, sizeof(field) - 1) == 0)
        return 1;
    if (a + sizeof(rational_field) - 1 <= b &&
        memcmp(s + a, rational_field, sizeof(rational_field) - 1) == 0)
        return 1;
    return 0;
}

static void algebra_rewrite_ordinary_line(WAlgebraBuf *out,
                                          const char *line, size_t n,
                                          int *changed) {
    int quote = 0;
    for (size_t i = 0; i < n;) {
        if (!quote && line[i] == '#') {
            algebra_buf_bytes(out, line + i, n - i);
            return;
        }
        if (line[i] == '"' || line[i] == '\'') {
            if (!quote) quote = line[i];
            else if (quote == line[i] && (i == 0 || line[i - 1] != '\\')) quote = 0;
            algebra_buf_c(out, line[i++]);
            continue;
        }
        unsigned long long projective_dimension = 0;
        size_t projective_end = 0;
        if (!quote &&
            algebra_projective_q_at(line, n, i, &projective_dimension,
                                    &projective_end)) {
            algebra_buf_s(out, "ProjectiveSpace<ℚ,");
            algebra_emit_uint(out, projective_dimension);
            algebra_buf_s(out, ">.new(Algebra.rational_field(),");
            algebra_emit_uint(out, projective_dimension);
            algebra_buf_s(out, ",[])");
            i = projective_end;
            *changed = 1;
            continue;
        }
        size_t field_a = 0, field_b = 0, after_open = 0;
        unsigned long long dimension = 0;
        if (!quote &&
            algebra_generic_new_at(line, n, i, "ProjectiveSpace", 1,
                                   &field_a, &field_b, &dimension,
                                   &after_open)) {
            size_t close = 0;
            if (!algebra_matching_paren(line, n, after_open, &close)) {
                algebra_buf_c(out, line[i++]);
                continue;
            }
            if (algebra_constructor_arguments_lowered(
                    line, after_open, close)) {
                algebra_buf_bytes(out, line + i, close + 1 - i);
                i = close + 1;
                continue;
            }
            algebra_buf_bytes(out, line + i, field_a - i);
            algebra_buf_bytes(out, line + field_a, field_b - field_a);
            algebra_buf_c(out, ',');
            algebra_emit_uint(out, dimension);
            algebra_buf_s(out, ">.new(Algebra.field(\"");
            algebra_buf_bytes(out, line + field_a, field_b - field_a);
            algebra_buf_s(out, "\"),");
            algebra_emit_uint(out, dimension);
            algebra_buf_s(out, ",[");
            algebra_buf_bytes(out, line + after_open, close - after_open);
            algebra_buf_s(out, "])");
            i = close + 1;
            *changed = 1;
            continue;
        }
        if (!quote &&
            algebra_generic_new_at(line, n, i, "Poly", 0,
                                   &field_a, &field_b, &dimension,
                                   &after_open)) {
            size_t close = 0;
            if (!algebra_matching_paren(line, n, after_open, &close)) {
                algebra_buf_c(out, line[i++]);
                continue;
            }
            if (algebra_constructor_arguments_lowered(
                    line, after_open, close)) {
                algebra_buf_bytes(out, line + i, close + 1 - i);
                i = close + 1;
                continue;
            }
            algebra_buf_bytes(out, line + i, field_a - i);
            algebra_buf_bytes(out, line + field_a, field_b - field_a);
            algebra_buf_s(out, ">.new(Algebra.field(\"");
            algebra_buf_bytes(out, line + field_a, field_b - field_a);
            algebra_buf_s(out, "\"),[");
            algebra_buf_bytes(out, line + after_open, close - after_open);
            algebra_buf_s(out, "])");
            i = close + 1;
            *changed = 1;
            continue;
        }
        if (!quote && line[i] == '[' && i > 0 &&
            (isalnum((unsigned char)line[i - 1]) || line[i - 1] == '_' ||
             line[i - 1] == ')')) {
            size_t close = i + 1;
            while (close < n && line[close] != ']') close++;
            if (close < n && algebra_point_content(line, i + 1, close)) {
                algebra_buf_s(out, ".point([");
                for (size_t j = i + 1; j < close; j++)
                    algebra_buf_c(out, line[j] == ':' ? ',' : line[j]);
                algebra_buf_s(out, "])");
                i = close + 1;
                *changed = 1;
                continue;
            }
        }
        algebra_buf_c(out, line[i++]);
    }
}

/* Recognize an actual source-level feature import, not the same words inside
 * a comment or string. `use algebra/...` and `use core/algebra/...` are
 * included because the orchestrator and focused layer specs import algebra
 * submodules directly. */
static int algebra_source_uses_algebra(const char *s, size_t n) {
    static const char public_use[] = "use algebra";
    static const char core_use[] = "use core/algebra";
    size_t line_a = 0;
    while (line_a < n) {
        size_t line_b = line_a;
        while (line_b < n && s[line_b] != '\n') line_b++;
        size_t p = line_a;
        while (p < line_b && (s[p] == ' ' || s[p] == '\t')) p++;

        if (p + sizeof(public_use) - 1 <= line_b &&
            memcmp(s + p, public_use, sizeof(public_use) - 1) == 0) {
            size_t after = p + sizeof(public_use) - 1;
            if (after == line_b || s[after] == '/' || s[after] == ' ' ||
                s[after] == '\t' || s[after] == '\r' || s[after] == '#' ||
                s[after] == ';')
                return 1;
        }
        if (p + sizeof(core_use) - 1 <= line_b &&
            memcmp(s + p, core_use, sizeof(core_use) - 1) == 0) {
            size_t after = p + sizeof(core_use) - 1;
            if (after == line_b || s[after] == '/' || s[after] == ' ' ||
                s[after] == '\t' || s[after] == '\r' || s[after] == '#' ||
                s[after] == ';')
                return 1;
        }
        line_a = line_b + (line_b < n ? 1 : 0);
    }
    return 0;
}

WValue w_algebra_rewrite_source(WValue source) {
    char inline_buf[6];
    const char *s;
    size_t n;
    w_str_data(source, inline_buf, &s, &n);
    /* Opt-in gate: algebra surface notation is enabled by `use algebra`
     * (core/algebra.w itself opts in through its `use core/algebra/...`
     * submodule directives). Every other source takes the zero-copy path
     * untouched, whatever it contains — in particular the bracket-point
     * rewrite below must never fire in a file that did not opt in. */
    if (!algebra_source_uses_algebra(s, n))
        return source;
    static const unsigned char subset[] = {0xe2, 0x8a, 0x82};
    static const unsigned char projective[] = {0xe2, 0x84, 0x99};
    if (!memmem(s, n, subset, sizeof(subset)) &&
        !memmem(s, n, projective, sizeof(projective)) &&
        !memmem(s, n, "ProjectiveSpace<", 16) &&
        !memmem(s, n, "Poly<", 5) &&
        !memchr(s, ':', n))
        return source;

    WAlgebraBuf out = {0};
    int changed = 0;
    unsigned long long declaration_id = 0;
    size_t line_a = 0;
    while (line_a < n) {
        size_t line_b = line_a;
        while (line_b < n && s[line_b] != '\n') line_b++;
        if (algebra_rewrite_curve_line(&out, s + line_a, line_b - line_a,
                                       declaration_id)) {
            changed = 1;
            declaration_id++;
        } else {
            algebra_rewrite_ordinary_line(&out, s + line_a, line_b - line_a,
                                          &changed);
        }
        if (line_b < n) algebra_buf_c(&out, '\n');
        line_a = line_b + (line_b < n ? 1 : 0);
    }
    if (!changed) {
        free(out.data);
        return source;
    }
    algebra_buf_need(&out, 0);
    out.data[out.len] = '\0';
    return w_string_take(out.data, out.len);
}

#ifndef W_RUNTIME_UNITY_INCLUDE
#undef w_string_take
#endif
