// C Lexer (Lex16 variant) — tokenizes C source using a 16-bit LexChar array.
//
// Equivalent C translation of languages/c/lexer16.w for syntax comparison.
//
// Lex16 LexChar bit layout:
//
//   15────────8 7────────0
//  ┌───────────┬─────────┐
//  │ codepoint │  flags  │
//  │ (8 bits)  │ (8 bits)│
//  └───────────┴─────────┘

#include <stdint.h>

// NEON helpers (defined in runtime)
extern int64_t w_lex16_scan_until_flag(uint16_t *data, int64_t count, int64_t pos, int64_t flag);
extern int64_t w_lex16_scan_flag(uint16_t *data, int64_t count, int64_t pos, int64_t flag);
extern int64_t w_lex16_scan_to_cp_or(uint16_t *data, int64_t count, int64_t pos, int64_t cp1, int64_t cp2);
extern int64_t w_lex16_scan_to_cp2(uint16_t *data, int64_t count, int64_t pos, int64_t cp1, int64_t cp2);

int64_t c_tokenize_fast16(uint16_t *lc, int64_t count, int64_t *tokens) {
    int64_t pos = 0, tc = 0;
    int64_t v, w, c, c2, ec, sc, start, is_float, len;

    int64_t tag           = (int64_t)0xFFFC << 48;
    int64_t t_ident       = tag | ((int64_t)0x1 << 38);
    int64_t t_int         = tag | ((int64_t)0x3 << 38);
    int64_t t_float       = tag | ((int64_t)0x4 << 38);
    int64_t t_string      = tag | ((int64_t)0x5 << 38);
    int64_t t_char        = tag | ((int64_t)0x6 << 38);
    int64_t t_op          = tag | ((int64_t)0x7 << 38);
    int64_t t_preproc     = tag | ((int64_t)0x8 << 38);
    int64_t t_comment     = tag | ((int64_t)0x9 << 38);
    int64_t t_ws          = tag | ((int64_t)0xA << 38);
    int64_t t_nl          = tag | ((int64_t)0xB << 38);
    int64_t len_1_shifted = (int64_t)0x1 << 24;

    for (;;) {
        v = lc[pos];
        if (v == 0) break;                                       // sentinel
        c = v >> 8;                                              // extract codepoint

        switch (v & 0xD7) {

        // ── 1. IS_OPERATOR ──────────────────────────────────────────────
        case 0x04:
            // Single-char operators (58% of ops)
            if (c == '(' || c == ')' || c == ';' || c == ',' ||
                c == '{' || c == '}' || c == '[' || c == ']' ||
                c == ':' || c == '?') {
                tokens[tc] = t_op | len_1_shifted | pos;
                tc++;
                pos++;
                break;
            }

            // Preprocessor '#'
            if (c == '#') {
                start = pos;
                pos++;
                for (;;) {
                    pos = w_lex16_scan_until_flag(lc, count, pos, 0x80);
                    w = lc[pos];
                    if (w == 0) break;                           // sentinel
                    if (pos > start + 1 && (lc[pos - 1] >> 8) == '\\') {
                        pos++;                                   // '\' + newline → skip
                        continue;
                    }
                    break;                                       // real end of directive
                }
                tokens[tc] = t_preproc | ((pos - start) << 24) | start;
                tc++;
                break;
            }

            // Comments
            if (c == '/') {
                c2 = lc[pos + 1] >> 8;
                if (c2 == '/') {                                 // '//'
                    start = pos;
                    pos += 2;
                    pos = w_lex16_scan_until_flag(lc, count, pos, 0x80);
                    tokens[tc] = t_comment | ((pos - start) << 24) | start;
                    tc++;
                    break;
                }
                if (c2 == '*') {                                 // '/*'
                    start = pos;
                    pos += 2;
                    pos = w_lex16_scan_to_cp2(lc, count, pos, '*', '/');
                    w = lc[pos];
                    if (w != 0) pos += 2;                        // found '*/', skip past it
                    tokens[tc] = t_comment | ((pos - start) << 24) | start;
                    tc++;
                    break;
                }
            }

            // Compound operators
            start = pos;
            pos++;
            c2 = lc[pos] >> 8;
            switch (c) {
            case '-':                                            // -> -- -=
                if      (c2 == '>') pos++;
                else if (c2 == '-') pos++;
                else if (c2 == '=') pos++;
                break;
            case '=':                                            // ==
                if (c2 == '=') pos++;
                break;
            case '&':                                            // && &=
                if      (c2 == '&') pos++;
                else if (c2 == '=') pos++;
                break;
            case '!':                                            // !=
                if (c2 == '=') pos++;
                break;
            case '|':                                            // || |=
                if      (c2 == '|') pos++;
                else if (c2 == '=') pos++;
                break;
            case '+':                                            // ++ +=
                if      (c2 == '+') pos++;
                else if (c2 == '=') pos++;
                break;
            case '>':                                            // >= >> >>=
                if (c2 == '=') {
                    pos++;
                } else if (c2 == '>') {
                    pos++;
                    if ((lc[pos] >> 8) == '=') pos++;
                }
                break;
            case '<':                                            // <= << <<=
                if (c2 == '=') {
                    pos++;
                } else if (c2 == '<') {
                    pos++;
                    if ((lc[pos] >> 8) == '=') pos++;
                }
                break;
            case '*':                                            // *=
                if (c2 == '=') pos++;
                break;
            case '.':                                            // ...
                if (c2 == '.' && (lc[pos] >> 8) == '.') pos += 2;
                break;
            case '^':                                            // ^=
                if (c2 == '=') pos++;
                break;
            case '/':                                            // /=
                if (c2 == '=') pos++;
                break;
            case '%':                                            // %=
                if (c2 == '=') pos++;
                break;
            case '#':                                            // ##
                if (c2 == '#') pos++;
                break;
            }
            tokens[tc] = t_op | ((pos - start) << 24) | start;
            tc++;
            break;

        // ── 2. IS_ID_START ──────────────────────────────────────────────
        case 0x40:
            start = pos;
            pos++;
            // Hybrid scalar/SIMD
            if (lc[pos] & 0x20) {
                pos++;
                if (lc[pos] & 0x20) {
                    pos++;
                    if (lc[pos] & 0x20) {
                        pos++;
                        pos = w_lex16_scan_flag(lc, count, pos, 0x20);
                    }
                }
            }
            tokens[tc] = t_ident | ((pos - start) << 24) | start;
            tc++;
            break;

        // ── 3. IS_WHITESPACE ────────────────────────────────────────────
        case 0x10:
            start = pos;
            pos++;
            while (lc[pos] & 0x10) pos++;
            tokens[tc] = t_ws | ((pos - start) << 24) | start;
            tc++;
            break;

        // ── 4. IS_NEWLINE ───────────────────────────────────────────────
        case 0x80:
            tokens[tc] = t_nl | len_1_shifted | pos;
            tc++;
            pos++;
            break;

        // ── 5. IS_QUOTE ─────────────────────────────────────────────────
        case 0x02:
            start = pos;
            pos++;
            if (c == '"') {                                      // string literal
                for (;;) {
                    pos = w_lex16_scan_to_cp_or(lc, count, pos, '"', '\\');
                    w = lc[pos];
                    if (w == 0) break;                           // sentinel
                    c2 = w >> 8;
                    if (c2 == '"') { pos++; break; }             // closing '"'
                    pos += 2;                                    // backslash escape
                }
                tokens[tc] = t_string | ((pos - start) << 24) | start;
            } else {                                             // character literal
                for (;;) {
                    pos = w_lex16_scan_to_cp_or(lc, count, pos, '\'', '\\');
                    w = lc[pos];
                    if (w == 0) break;
                    c2 = w >> 8;
                    if (c2 == '\'') { pos++; break; }
                    pos += 2;
                }
                tokens[tc] = t_char | ((pos - start) << 24) | start;
            }
            tc++;
            break;

        // ── 6. IS_DIGIT ─────────────────────────────────────────────────
        case 0x01:
            start = pos;
            is_float = 0;
            if (c == '0') {                                      // '0' prefix
                c2 = lc[pos + 1] >> 8;
                if (c2 == 'x' || c2 == 'X') {                   // hex
                    pos += 2;
                    while (lc[pos] & 0x8) pos++;
                } else if (c2 == 'b' || c2 == 'B') {            // binary
                    pos += 2;
                    while ((lc[pos] >> 8) == '0' || (lc[pos] >> 8) == '1') pos++;
                } else {
                    pos++;
                    while (lc[pos] & 0x1) pos++;
                }
            } else {
                pos++;
                while (lc[pos] & 0x1) pos++;
            }

            // Decimal point '.'
            if ((lc[pos] >> 8) == '.') {
                pos++;
                is_float = 1;
                while (lc[pos] & 0x1) pos++;
            }

            // Exponent 'e' or 'E'
            ec = lc[pos] >> 8;
            if (ec == 'e' || ec == 'E') {
                pos++;
                is_float = 1;
                c2 = lc[pos] >> 8;
                if (c2 == '+' || c2 == '-') pos++;
                while (lc[pos] & 0x1) pos++;
            }

            // Suffixes: u U l L f F
            for (;;) {
                sc = lc[pos] >> 8;
                if (sc == 'u' || sc == 'U' || sc == 'l' || sc == 'L' ||
                    sc == 'f' || sc == 'F') {
                    pos++;
                } else {
                    break;
                }
            }

            len = pos - start;
            if (is_float != 0)
                tokens[tc] = t_float | (len << 24) | start;
            else
                tokens[tc] = t_int | (len << 24) | start;
            tc++;
            break;

        // ── 7. Unknown character ────────────────────────────────────────
        default:
            tokens[tc] = t_op | len_1_shifted | pos;
            tc++;
            pos++;
            break;
        }
    }

    return tc;
}
