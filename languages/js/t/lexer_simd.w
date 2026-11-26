# blade/jsn_t/lexer_simd — SIMD-accelerated ECMAScript 2024 Lexer using
# Tungsten LexChar & Token WValue subtags.
#
# Architecture:
#   Input:
#     - Lex16 path: u16[] LexChar array (high byte = ASCII cp or 0x80, low byte = JS flags)
#       produced either via `source.lchs("js", bits: 16)` OR our NEON 16-byte SIMD packer
#       `js_pack_lex16_simd(source)`.
#     - Lex64 path: full 64-bit LexChar WValue array (W_TAG_CHAR=0xFFFC, subtype=01)
#       produced via `source.lchs("js", bits: 64)`.
#   Output:
#     - i64[] buffer of authentic Tungsten Token WValues (W_TAG_CHAR=0xFFFC, subtype=00),
#       matching `~/.tungsten/core/token.w` bit-for-bit:
#         bits 63..48: 0xFFFC (W_TAG_CHAR)
#         bits 47..46: 00     (Token subtype)
#         bits 45..38: type   (8 bits: exact T_* JS token ID 0..125!)
#         bits 37..26: length (12 bits: byte/char length & 0xFFF)
#         bits 25..2 : offset (24 bits: start offset in source, max 16 MB)
#         bit  1     : flag1  (escaped for T_NAME, tail for T_TEMPLATE)
#         bit  0     : nl     (f_line_start: preceded by LineTerminator, for ASI)
#
# SIMD acceleration (ARM64 NEON):
#   - Uses Tungsten runtime NEON scanners:
#       w_lex16_scan_flag        (8 lanes/iter identifier scan)
#       w_lex16_scan_until_flag  (8 lanes/iter line-comment newline scan)
#       w_lex16_scan_to_cp_or    (8 lanes/iter string literal scan for quote or '\')
#       w_lex16_scan_to_cp2      (8 lanes/iter block comment scan for '*/')
#   - Plus inline LLVM SIMD helpers:
#       js_pack_lex16_neon_16    (16-byte ASCII fast-path pack into u16[] LexChars)
#       js_lex16_scan_tpl_simd   (8-lane NEON scan for '`', '$', or '\' in templates)
#       js_lex16_scan_ws_simd    (8-lane NEON scan over whitespace runs)
#   - Zero-allocation O(1) keyword classifier directly over LexChar elements (no substring
#     allocation, no Hash lookup during lexing).

# ---- Token type constants (identical to blade/jsn/lexer.w) ----
use core/token

JT_EOF             = 0
JT_NAME            = 1
JT_NUM             = 2
JT_BIGINT          = 3
JT_STRING          = 4
JT_TEMPLATE        = 5
JT_REGEX           = 6
JT_PRIVATE         = 7

JT_BREAK           = 10
JT_CASE            = 11
JT_CATCH           = 12
JT_CLASS           = 13
JT_CONST           = 14
JT_CONTINUE        = 15
JT_DEBUGGER        = 16
JT_DEFAULT         = 17
JT_DELETE          = 18
JT_DO              = 19
JT_ELSE            = 20
JT_EXPORT          = 21
JT_EXTENDS         = 22
JT_FINALLY         = 23
JT_FOR             = 24
JT_FUNCTION        = 25
JT_IF              = 26
JT_IMPORT          = 27
JT_IN              = 28
JT_INSTANCEOF      = 29
JT_NEW             = 30
JT_RETURN          = 31
JT_SUPER           = 32
JT_SWITCH          = 33
JT_THIS            = 34
JT_THROW           = 35
JT_TRY             = 36
JT_TYPEOF          = 37
JT_VAR             = 38
JT_VOID            = 39
JT_WHILE           = 40
JT_WITH            = 41
JT_NULL            = 42
JT_TRUE            = 43
JT_FALSE           = 44
JT_ENUM            = 45

JT_LBRACE          = 60
JT_RBRACE          = 61
JT_LPAREN          = 62
JT_RPAREN          = 63
JT_LBRACK          = 64
JT_RBRACK          = 65
JT_SEMI            = 66
JT_COMMA           = 67
JT_DOT             = 68
JT_ELLIPSIS        = 69
JT_QUESTION        = 70
JT_QDOT            = 71
JT_COLON           = 72
JT_ARROW           = 73
JT_TILDE           = 74
JT_BANG            = 75
JT_INC             = 76
JT_DEC             = 77
JT_AT              = 78

JT_NULLISH         = 80
JT_OROR            = 81
JT_ANDAND          = 82
JT_BITOR           = 83
JT_BITXOR          = 84
JT_BITAND          = 85
JT_EQ              = 86
JT_NE              = 87
JT_SEQ             = 88
JT_SNE             = 89
JT_LT              = 90
JT_GT              = 91
JT_LE              = 92
JT_GE              = 93
JT_SHL             = 94
JT_SHR             = 95
JT_USHR            = 96
JT_PLUS            = 97
JT_MINUS           = 98
JT_STAR            = 99
JT_SLASH           = 100
JT_PERCENT         = 101
JT_STARSTAR        = 102

JT_ASSIGN          = 110
JT_PLUS_ASSIGN     = 111
JT_MINUS_ASSIGN    = 112
JT_STAR_ASSIGN     = 113
JT_SLASH_ASSIGN    = 114
JT_PERCENT_ASSIGN  = 115
JT_STARSTAR_ASSIGN = 116
JT_SHL_ASSIGN      = 117
JT_SHR_ASSIGN      = 118
JT_USHR_ASSIGN     = 119
JT_BITAND_ASSIGN   = 120
JT_BITOR_ASSIGN    = 121
JT_BITXOR_ASSIGN   = 122
JT_ANDAND_ASSIGN   = 123
JT_OROR_ASSIGN     = 124
JT_NULLISH_ASSIGN  = 125

# ---- Token WValue packing / unpacking helpers (matching core/token.w) ----
# Token WValue layout: (0xFFFC << 48) | (tt << 38) | (jt_clen(len) << 26) | (off << 2) | flags
JT_TAG = 0xFFFC << 48

fn jt_clen(n) (i64) i64
  n >= 4095 ? 4095 : n

fn jt_pack(tt, off, len, flags) (i64 i64 i64 i64) i64
  (0xFFFC << 48) | (tt << 38) | (jt_clen(len) << 26) | (off << 2) | flags

fn jt_type(tok) (i64) i64
  (tok >> 38) & 0xFF

fn jt_len(tok) (i64) i64
  (tok >> 26) & 0xFFF

fn jt_off(tok) (i64) i64
  (tok >> 2) & 0xFFFFFF

fn jt_nl(tok) (i64) i64
  tok & 1

fn jt_flag1(tok) (i64) i64
  (tok >> 1) & 1

# Zero-allocation 46-bit payload extractor (strips the 0xFFFC Token WValue tag so
# untyped callers like JsLexer#next_token receive a 48-bit Fixnum with ZERO BigInt allocation!)
fn jt_payload(toks, idx) (i64[] i64) i64
  toks[idx] & 0x3FFFFFFFFFFF

# Convert a packed i64 token bit pattern to a genuine Tungsten Token WValue
# so `.token_type`, `.offset`, `.length`, `.text(src)`, `.line_start?` work natively.
-> jt_as_token_wvalue(bits)
  wvalue_from_bits(bits ## i64)

# ---- Inline LLVM SIMD helpers (ARM64 NEON auto-lowered by LLVM) ----

# Check if 16 bytes at src_ptr+pos are all ASCII (< 0x80) using a single <16 x i8> vector test.
fn js_ascii16_check(src_ptr, pos) (i64 i64) i64
  ll <<~IR
    %base = inttoptr i64 %src_ptr to ptr
    %p = getelementptr i8, ptr %base, i64 %pos
    %v = load <16 x i8>, ptr %p, align 1
    %hi = icmp slt <16 x i8> %v, zeroinitializer
    %bits = bitcast <16 x i1> %hi to i16
    %z = icmp eq i16 %bits, 0
    %r = zext i1 %z to i64
    ret i64 %r
  IR

# Pack 16 ASCII bytes from src_ptr+pos into 16 u16 LexChars at dst_ptr+dst_pos using
# lookup table tbl_ptr (256 bytes of JS LexChar flags) + vector shift/or (<16 x i16>).
fn js_pack16_ascii_block(src_ptr, pos, dst_ptr, dst_pos, tbl_ptr) (i64 i64 i64 i64 i64) i64
  ll <<~IR
    %sbase = inttoptr i64 %src_ptr to ptr
    %sp = getelementptr i8, ptr %sbase, i64 %pos
    %dbase = inttoptr i64 %dst_ptr to ptr
    %dp = getelementptr i16, ptr %dbase, i64 %dst_pos
    %tbase = inttoptr i64 %tbl_ptr to ptr

    %v8 = load <16 x i8>, ptr %sp, align 1
    %v16 = zext <16 x i8> %v8 to <16 x i16>
    %hi = shl <16 x i16> %v16, <i16 8, i16 8, i16 8, i16 8, i16 8, i16 8, i16 8, i16 8, i16 8, i16 8, i16 8, i16 8, i16 8, i16 8, i16 8, i16 8>

    %b0  = extractelement <16 x i8> %v8, i32 0
    %b1  = extractelement <16 x i8> %v8, i32 1
    %b2  = extractelement <16 x i8> %v8, i32 2
    %b3  = extractelement <16 x i8> %v8, i32 3
    %b4  = extractelement <16 x i8> %v8, i32 4
    %b5  = extractelement <16 x i8> %v8, i32 5
    %b6  = extractelement <16 x i8> %v8, i32 6
    %b7  = extractelement <16 x i8> %v8, i32 7
    %b8  = extractelement <16 x i8> %v8, i32 8
    %b9  = extractelement <16 x i8> %v8, i32 9
    %b10 = extractelement <16 x i8> %v8, i32 10
    %b11 = extractelement <16 x i8> %v8, i32 11
    %b12 = extractelement <16 x i8> %v8, i32 12
    %b13 = extractelement <16 x i8> %v8, i32 13
    %b14 = extractelement <16 x i8> %v8, i32 14
    %b15 = extractelement <16 x i8> %v8, i32 15

    %i0  = zext i8 %b0  to i64
    %i1  = zext i8 %b1  to i64
    %i2  = zext i8 %b2  to i64
    %i3  = zext i8 %b3  to i64
    %i4  = zext i8 %b4  to i64
    %i5  = zext i8 %b5  to i64
    %i6  = zext i8 %b6  to i64
    %i7  = zext i8 %b7  to i64
    %i8  = zext i8 %b8  to i64
    %i9  = zext i8 %b9  to i64
    %i10 = zext i8 %b10 to i64
    %i11 = zext i8 %b11 to i64
    %i12 = zext i8 %b12 to i64
    %i13 = zext i8 %b13 to i64
    %i14 = zext i8 %b14 to i64
    %i15 = zext i8 %b15 to i64

    %p0  = getelementptr i8, ptr %tbase, i64 %i0
    %p1  = getelementptr i8, ptr %tbase, i64 %i1
    %p2  = getelementptr i8, ptr %tbase, i64 %i2
    %p3  = getelementptr i8, ptr %tbase, i64 %i3
    %p4  = getelementptr i8, ptr %tbase, i64 %i4
    %p5  = getelementptr i8, ptr %tbase, i64 %i5
    %p6  = getelementptr i8, ptr %tbase, i64 %i6
    %p7  = getelementptr i8, ptr %tbase, i64 %i7
    %p8  = getelementptr i8, ptr %tbase, i64 %i8
    %p9  = getelementptr i8, ptr %tbase, i64 %i9
    %p10 = getelementptr i8, ptr %tbase, i64 %i10
    %p11 = getelementptr i8, ptr %tbase, i64 %i11
    %p12 = getelementptr i8, ptr %tbase, i64 %i12
    %p13 = getelementptr i8, ptr %tbase, i64 %i13
    %p14 = getelementptr i8, ptr %tbase, i64 %i14
    %p15 = getelementptr i8, ptr %tbase, i64 %i15

    %f0  = load i8, ptr %p0
    %f1  = load i8, ptr %p1
    %f2  = load i8, ptr %p2
    %f3  = load i8, ptr %p3
    %f4  = load i8, ptr %p4
    %f5  = load i8, ptr %p5
    %f6  = load i8, ptr %p6
    %f7  = load i8, ptr %p7
    %f8  = load i8, ptr %p8
    %f9  = load i8, ptr %p9
    %f10 = load i8, ptr %p10
    %f11 = load i8, ptr %p11
    %f12 = load i8, ptr %p12
    %f13 = load i8, ptr %p13
    %f14 = load i8, ptr %p14
    %f15 = load i8, ptr %p15

    %fv0  = insertelement <16 x i8> undef, i8 %f0,  i32 0
    %fv1  = insertelement <16 x i8> %fv0,  i8 %f1,  i32 1
    %fv2  = insertelement <16 x i8> %fv1,  i8 %f2,  i32 2
    %fv3  = insertelement <16 x i8> %fv2,  i8 %f3,  i32 3
    %fv4  = insertelement <16 x i8> %fv3,  i8 %f4,  i32 4
    %fv5  = insertelement <16 x i8> %fv4,  i8 %f5,  i32 5
    %fv6  = insertelement <16 x i8> %fv5,  i8 %f6,  i32 6
    %fv7  = insertelement <16 x i8> %fv6,  i8 %f7,  i32 7
    %fv8  = insertelement <16 x i8> %fv7,  i8 %f8,  i32 8
    %fv9  = insertelement <16 x i8> %fv8,  i8 %f9,  i32 9
    %fv10 = insertelement <16 x i8> %fv9,  i8 %f10, i32 10
    %fv11 = insertelement <16 x i8> %fv10, i8 %f11, i32 11
    %fv12 = insertelement <16 x i8> %fv11, i8 %f12, i32 12
    %fv13 = insertelement <16 x i8> %fv12, i8 %f13, i32 13
    %fv14 = insertelement <16 x i8> %fv13, i8 %f14, i32 14
    %fv15 = insertelement <16 x i8> %fv14, i8 %f15, i32 15

    %lo = zext <16 x i8> %fv15 to <16 x i16>
    %packed = or <16 x i16> %hi, %lo
    store <16 x i16> %packed, ptr %dp, align 2
    ret i64 16
  IR

# 8-lane NEON scanner for single/double-quoted strings: stops at quote, '\', newline (0x80), or sentinel (0).
fn js_lex16_scan_str_simd(data_ptr, pos, quote) (i64 i64 i64) i64
  ll <<~IR
    %base = inttoptr i64 %data_ptr to ptr
    %q16 = trunc i64 %quote to i16
    %vq = insertelement <8 x i16> undef, i16 %q16, i32 0
    %vqv = shufflevector <8 x i16> %vq, <8 x i16> undef, <8 x i32> zeroinitializer
    br label %loop
  loop:
    %cur = phi i64 [ %pos, %0 ], [ %next, %cont ]
    %p = getelementptr i16, ptr %base, i64 %cur
    %v = load <8 x i16>, ptr %p, align 2
    %hi = lshr <8 x i16> %v, <i16 8, i16 8, i16 8, i16 8, i16 8, i16 8, i16 8, i16 8>
    %c0 = icmp eq <8 x i16> %v, zeroinitializer
    %c1 = icmp eq <8 x i16> %hi, %vqv
    %c2 = icmp eq <8 x i16> %hi, <i16 92, i16 92, i16 92, i16 92, i16 92, i16 92, i16 92, i16 92>
    %nlb = and <8 x i16> %v, <i16 128, i16 128, i16 128, i16 128, i16 128, i16 128, i16 128, i16 128>
    %c3 = icmp ne <8 x i16> %nlb, zeroinitializer
    %m01 = or <8 x i1> %c0, %c1
    %m23 = or <8 x i1> %c2, %c3
    %m = or <8 x i1> %m01, %m23
    %mb = bitcast <8 x i1> %m to i8
    %any = icmp ne i8 %mb, 0
    br i1 %any, label %found, label %cont
  cont:
    %next = add i64 %cur, 8
    br label %loop
  found:
    %tz = call i8 @llvm.cttz.i8(i8 %mb, i1 true)
    %off = zext i8 %tz to i64
    %res = add i64 %cur, %off
    ret i64 %res
  IR

# 8-lane NEON scanner for template literal chunks: stops at '`', '$', '\', or sentinel (0).
# Returns index of first matching element in u16[] Lex16 buffer.
fn js_lex16_scan_tpl_simd(data_ptr, pos) (i64 i64) i64
  ll <<~IR
    %base = inttoptr i64 %data_ptr to ptr
    br label %start
  start:
    br label %loop
  loop:
    %cur = phi i64 [ %pos, %start ], [ %next, %cont ]
    %p = getelementptr i16, ptr %base, i64 %cur
    %v = load <8 x i16>, ptr %p, align 2
    %cp = lshr <8 x i16> %v, <i16 8, i16 8, i16 8, i16 8, i16 8, i16 8, i16 8, i16 8>
    %c0 = icmp eq <8 x i16> %v, zeroinitializer
    %c1 = icmp eq <8 x i16> %cp, <i16 96, i16 96, i16 96, i16 96, i16 96, i16 96, i16 96, i16 96>
    %c2 = icmp eq <8 x i16> %cp, <i16 36, i16 36, i16 36, i16 36, i16 36, i16 36, i16 36, i16 36>
    %c3 = icmp eq <8 x i16> %cp, <i16 92, i16 92, i16 92, i16 92, i16 92, i16 92, i16 92, i16 92>
    %m01 = or <8 x i1> %c0, %c1
    %m23 = or <8 x i1> %c2, %c3
    %mall = or <8 x i1> %m01, %m23
    %mask = bitcast <8 x i1> %mall to i8
    %hit = icmp ne i8 %mask, 0
    br i1 %hit, label %found, label %cont
  cont:
    %next = add i64 %cur, 8
    br label %loop
  found:
    %m64 = zext i8 %mask to i64
    %neg = sub i64 0, %m64
    %lsb = and i64 %m64, %neg
    %b0a = and i64 %lsb, 170
    %b0c = icmp ne i64 %b0a, 0
    %b0  = select i1 %b0c, i64 1, i64 0
    %b1a = and i64 %lsb, 204
    %b1c = icmp ne i64 %b1a, 0
    %b1  = select i1 %b1c, i64 2, i64 0
    %b2a = and i64 %lsb, 240
    %b2c = icmp ne i64 %b2a, 0
    %b2  = select i1 %b2c, i64 4, i64 0
    %t01 = or i64 %b0, %b1
    %tz  = or i64 %t01, %b2
    %res = add i64 %cur, %tz
    ret i64 %res
  IR

# 8-lane NEON scanner for regex bodies: stops at '/', '\', '[', ']', newline (flag 0x80), or sentinel (0).
fn js_lex16_scan_regex_simd(data_ptr, pos) (i64 i64) i64
  ll <<~IR
    %base = inttoptr i64 %data_ptr to ptr
    br label %start
  start:
    br label %loop
  loop:
    %cur = phi i64 [ %pos, %start ], [ %next, %cont ]
    %p = getelementptr i16, ptr %base, i64 %cur
    %v = load <8 x i16>, ptr %p, align 2
    %cp = lshr <8 x i16> %v, <i16 8, i16 8, i16 8, i16 8, i16 8, i16 8, i16 8, i16 8>
    %nlb = and <8 x i16> %v, <i16 128, i16 128, i16 128, i16 128, i16 128, i16 128, i16 128, i16 128>
    %c0 = icmp eq <8 x i16> %v, zeroinitializer
    %c1 = icmp ne <8 x i16> %nlb, zeroinitializer
    %c2 = icmp eq <8 x i16> %cp, <i16 47, i16 47, i16 47, i16 47, i16 47, i16 47, i16 47, i16 47>
    %c3 = icmp eq <8 x i16> %cp, <i16 92, i16 92, i16 92, i16 92, i16 92, i16 92, i16 92, i16 92>
    %c4 = icmp eq <8 x i16> %cp, <i16 91, i16 91, i16 91, i16 91, i16 91, i16 91, i16 91, i16 91>
    %c5 = icmp eq <8 x i16> %cp, <i16 93, i16 93, i16 93, i16 93, i16 93, i16 93, i16 93, i16 93>
    %m01 = or <8 x i1> %c0, %c1
    %m23 = or <8 x i1> %c2, %c3
    %m45 = or <8 x i1> %c4, %c5
    %m03 = or <8 x i1> %m01, %m23
    %mall = or <8 x i1> %m03, %m45
    %mask = bitcast <8 x i1> %mall to i8
    %hit = icmp ne i8 %mask, 0
    br i1 %hit, label %found, label %cont
  cont:
    %next = add i64 %cur, 8
    br label %loop
  found:
    %m64 = zext i8 %mask to i64
    %neg = sub i64 0, %m64
    %lsb = and i64 %m64, %neg
    %b0a = and i64 %lsb, 170
    %b0c = icmp ne i64 %b0a, 0
    %b0  = select i1 %b0c, i64 1, i64 0
    %b1a = and i64 %lsb, 204
    %b1c = icmp ne i64 %b1a, 0
    %b1  = select i1 %b1c, i64 2, i64 0
    %b2a = and i64 %lsb, 240
    %b2c = icmp ne i64 %b2a, 0
    %b2  = select i1 %b2c, i64 4, i64 0
    %t01 = or i64 %b0, %b1
    %tz  = or i64 %t01, %b2
    %res = add i64 %cur, %tz
    ret i64 %res
  IR

# 8-lane NEON scanner for block comments: stops at '*', newline (0x80), or sentinel (0)
# so we simultaneously accelerate scanning AND accurately track newlines inside /*...*/ for ASI!
fn js_lex16_scan_bcomment_simd(data_ptr, pos) (i64 i64) i64
  ll <<~IR
    %base = inttoptr i64 %data_ptr to ptr
    br label %start
  start:
    br label %loop
  loop:
    %cur = phi i64 [ %pos, %start ], [ %next, %cont ]
    %p = getelementptr i16, ptr %base, i64 %cur
    %v = load <8 x i16>, ptr %p, align 2
    %cp = lshr <8 x i16> %v, <i16 8, i16 8, i16 8, i16 8, i16 8, i16 8, i16 8, i16 8>
    %nlb = and <8 x i16> %v, <i16 128, i16 128, i16 128, i16 128, i16 128, i16 128, i16 128, i16 128>
    %c0 = icmp eq <8 x i16> %v, zeroinitializer
    %c1 = icmp ne <8 x i16> %nlb, zeroinitializer
    %c2 = icmp eq <8 x i16> %cp, <i16 42, i16 42, i16 42, i16 42, i16 42, i16 42, i16 42, i16 42>
    %m01 = or <8 x i1> %c0, %c1
    %mall = or <8 x i1> %m01, %c2
    %mask = bitcast <8 x i1> %mall to i8
    %hit = icmp ne i8 %mask, 0
    br i1 %hit, label %found, label %cont
  cont:
    %next = add i64 %cur, 8
    br label %loop
  found:
    %m64 = zext i8 %mask to i64
    %neg = sub i64 0, %m64
    %lsb = and i64 %m64, %neg
    %b0a = and i64 %lsb, 170
    %b0c = icmp ne i64 %b0a, 0
    %b0  = select i1 %b0c, i64 1, i64 0
    %b1a = and i64 %lsb, 204
    %b1c = icmp ne i64 %b1a, 0
    %b1  = select i1 %b1c, i64 2, i64 0
    %b2a = and i64 %lsb, 240
    %b2c = icmp ne i64 %b2a, 0
    %b2  = select i1 %b2c, i64 4, i64 0
    %t01 = or i64 %b0, %b1
    %tz  = or i64 %t01, %b2
    %res = add i64 %cur, %tz
    ret i64 %res
  IR

# Build 256-byte JS ASCII flag table in memory (used by js_pack_lex16_simd).
-> js_make_ascii_flag_table
  tbl = ByteArray.new(256)
  i = 0
  while i < 256
    tbl[i] = 0
    i += 1
  tbl[10] = 0x80
  tbl[13] = 0x80
  tbl[9]  = 0x10
  tbl[11] = 0x10
  tbl[12] = 0x10
  tbl[32] = 0x10
  c = 48
  while c <= 57
    tbl[c] = 0x01 | 0x08 | 0x20
    c += 1
  c = 65
  while c <= 90
    tbl[c] = (c <= 70) ? (0x40 | 0x20 | 0x08) : (0x40 | 0x20)
    c += 1
  c = 97
  while c <= 122
    tbl[c] = (c <= 102) ? (0x40 | 0x20 | 0x08) : (0x40 | 0x20)
    c += 1
  tbl[95] = 0x40 | 0x20
  tbl[36] = 0x40 | 0x20
  tbl[34] = 0x02
  tbl[39] = 0x02
  tbl[96] = 0x02
  ops = [43, 45, 42, 47, 37, 94, 38, 124, 60, 62, 61, 33, 126, 63, 46, 58, 59, 44, 40, 41, 91, 93, 123, 125, 35, 64]
  i = 0
  while i < ops.size
    tbl[ops[i]] = 0x04
    i += 1
  tbl

JS_ASCII_FLAGS = js_make_ascii_flag_table()
JS_SIMD_LC_SCRATCH = [nil]
JS_SIMD_TOKS_SCRATCH = [nil]
JS_SIMD_TOKS_LEASED = [false]

# Acquire a reusable i64[] token buffer (avoids 87 MB per-parse alloc on 10 MB files).
# Falls back to a fresh allocation if already leased (e.g., nested JsLexer instances).
-> js_simd_acquire_toks(need)
  if !JS_SIMD_TOKS_LEASED[0]
    buf = JS_SIMD_TOKS_SCRATCH[0]
    if buf == nil || buf.size < need
      buf = i64[need]
      JS_SIMD_TOKS_SCRATCH[0] = buf
    JS_SIMD_TOKS_LEASED[0] = true
    return buf
  i64[need]

-> js_simd_release_toks(buf)
  if buf != nil
    if buf == JS_SIMD_TOKS_SCRATCH[0]
      JS_SIMD_TOKS_LEASED[0] = false
      if buf.size > 262144
        JS_SIMD_TOKS_SCRATCH[0] = nil
        ccall("w_value_free_w", buf)
    else
      ccall("w_value_free_w", buf)
  nil

-> js_simd_trim_lc
  lc = JS_SIMD_LC_SCRATCH[0]
  if lc != nil && lc.size > 524288
    JS_SIMD_LC_SCRATCH[0] = nil
    ccall("w_value_free_w", lc)
  nil

# Single-pass UTF-8 byte-indexed SIMD Lex16 packer (1 u16 entry per UTF-8 byte so byte
# offsets stay 1:1 with `src.slice(off, len)`!).
# - Pure-ASCII 16-byte runs pack at full NEON speed via `js_pack16_ascii_block`.
# - Non-ASCII UTF-8 sequences preserve exact byte offsets:
#     U+2028 / U+2029 (LS/PS): byte 0 = 0x8080 (newline), bytes 1..2 = 0x8010 (ws tail)
#     Unicode whitespace (NBSP, BOM, OGHAM, 2000..200A, 202F, 205F, 3000): all bytes = 0x8010
#     All other non-ASCII bytes: 0x8000 (flags=0 -> NEON scans over UTF-8 inside strings/comments/
#     templates/regex at full speed, while top-level/ident hits cleanly delegate that single token
#     to `next_token_pull` for full ECMAScript Unicode validation and re-sync immediately!).
## i64: n, pos, b, b1, b2, src_ptr, dst_ptr, tbl_ptr, i
## u16[]: lc
-> js_pack_lex16_utf8(src)
  n = src.size
  return nil if n < 16
  lc = JS_SIMD_LC_SCRATCH[0]
  if lc == nil || lc.size < n + 16
    lc = u16[n + 16]
    JS_SIMD_LC_SCRATCH[0] = lc
  src_ptr = ccall_nobox("w_string_data_ptr", src)
  dst_ptr = ccall_nobox("w_array_data_ptr", lc)
  tbl_ptr = ccall_nobox("w_array_data_ptr", JS_ASCII_FLAGS)
  pos = 0
  while pos + 16 <= n
    if js_ascii16_check(src_ptr, pos) != 0
      js_pack16_ascii_block(src_ptr, pos, dst_ptr, pos, tbl_ptr)
      pos += 16
    else
      b = raw_load_u8(src_ptr, pos)
      if b < 128
        lc[pos] = (b << 8) | JS_ASCII_FLAGS[b]
        pos += 1
      elsif b == 0xC2 && raw_load_u8(src_ptr, pos + 1) == 0xA0
        lc[pos] = 0x8010
        lc[pos + 1] = 0x8010
        pos += 2
      elsif b == 0xE2
        b1 = raw_load_u8(src_ptr, pos + 1)
        b2 = raw_load_u8(src_ptr, pos + 2)
        if b1 == 0x80 && (b2 == 0xA8 || b2 == 0xA9)
          lc[pos] = 0x8080
          lc[pos + 1] = 0x8010
          lc[pos + 2] = 0x8010
          pos += 3
        elsif (b1 == 0x80 && ((b2 >= 0x80 && b2 <= 0x8A) || b2 == 0xAF)) || (b1 == 0x81 && b2 == 0x9F)
          lc[pos] = 0x8010
          lc[pos + 1] = 0x8010
          lc[pos + 2] = 0x8010
          pos += 3
        else
          lc[pos] = 0x8000
          pos += 1
      elsif (b == 0xEF && raw_load_u8(src_ptr, pos + 1) == 0xBB && raw_load_u8(src_ptr, pos + 2) == 0xBF) || (b == 0xE1 && raw_load_u8(src_ptr, pos + 1) == 0x9A && raw_load_u8(src_ptr, pos + 2) == 0x80) || (b == 0xE3 && raw_load_u8(src_ptr, pos + 1) == 0x80 && raw_load_u8(src_ptr, pos + 2) == 0x80)
        lc[pos] = 0x8010
        lc[pos + 1] = 0x8010
        lc[pos + 2] = 0x8010
        pos += 3
      else
        lc[pos] = 0x8000
        pos += 1
  while pos < n
    b = raw_load_u8(src_ptr, pos)
    if b < 128
      lc[pos] = (b << 8) | JS_ASCII_FLAGS[b]
      pos += 1
    elsif b == 0xC2 && pos + 1 < n && raw_load_u8(src_ptr, pos + 1) == 0xA0
      lc[pos] = 0x8010
      lc[pos + 1] = 0x8010
      pos += 2
    elsif b == 0xE2 && pos + 2 < n
      b1 = raw_load_u8(src_ptr, pos + 1)
      b2 = raw_load_u8(src_ptr, pos + 2)
      if b1 == 0x80 && (b2 == 0xA8 || b2 == 0xA9)
        lc[pos] = 0x8080
        lc[pos + 1] = 0x8010
        lc[pos + 2] = 0x8010
        pos += 3
      elsif (b1 == 0x80 && ((b2 >= 0x80 && b2 <= 0x8A) || b2 == 0xAF)) || (b1 == 0x81 && b2 == 0x9F)
        lc[pos] = 0x8010
        lc[pos + 1] = 0x8010
        lc[pos + 2] = 0x8010
        pos += 3
      else
        lc[pos] = 0x8000
        pos += 1
    elsif pos + 2 < n && ((b == 0xEF && raw_load_u8(src_ptr, pos + 1) == 0xBB && raw_load_u8(src_ptr, pos + 2) == 0xBF) || (b == 0xE1 && raw_load_u8(src_ptr, pos + 1) == 0x9A && raw_load_u8(src_ptr, pos + 2) == 0x80) || (b == 0xE3 && raw_load_u8(src_ptr, pos + 1) == 0x80 && raw_load_u8(src_ptr, pos + 2) == 0x80))
      lc[pos] = 0x8010
      lc[pos + 1] = 0x8010
      lc[pos + 2] = 0x8010
      pos += 3
    else
      lc[pos] = 0x8000
      pos += 1
  i = 0
  while i < 16
    lc[n + i] = 0
    i += 1
  lc

# Single-pass ASCII-only SIMD Lex16 packer (kept for ASCII-only microbenchmarks).
## i64: n, pos, b, src_ptr, dst_ptr, tbl_ptr, i
## u16[]: lc
-> js_pack_lex16_ascii_only(src)
  n = src.size
  return nil if n < 16
  lc = JS_SIMD_LC_SCRATCH[0]
  if lc == nil || lc.size < n + 16
    lc = u16[n + 16]
    JS_SIMD_LC_SCRATCH[0] = lc
  src_ptr = ccall_nobox("w_string_data_ptr", src)
  dst_ptr = ccall_nobox("w_array_data_ptr", lc)
  tbl_ptr = ccall_nobox("w_array_data_ptr", JS_ASCII_FLAGS)
  pos = 0
  while pos + 16 <= n
    return nil if js_ascii16_check(src_ptr, pos) == 0
    js_pack16_ascii_block(src_ptr, pos, dst_ptr, pos, tbl_ptr)
    pos += 16
  while pos < n
    b = raw_load_u8(src_ptr, pos)
    return nil if b >= 128
    lc[pos] = (b << 8) | JS_ASCII_FLAGS[b]
    pos += 1
  i = 0
  while i < 16
    lc[n + i] = 0
    i += 1
  lc

# Fast SIMD UTF-8 -> u16[] Lex16 packer (works standalone without .lex16 disk files).
# Reads directly from the String's raw UTF-8 buffer via `w_string_data_ptr` (zero copy!).
# Returns [lc_u16_array, char_count]. Appends 16 zero sentinels for safe NEON tail loads.
## i64: n, pos, out, b, cp, fl, clen, src_ptr, dst_ptr, tbl_ptr, i
## u16[]: lc
-> js_pack_lex16_simd(src)
  n = src.size
  lc = u16[n + 16]
  dst_ptr = ccall_nobox("w_array_data_ptr", lc)
  tbl_ptr = ccall_nobox("w_array_data_ptr", JS_ASCII_FLAGS)
  pos = 0
  out = 0
  if n >= 16
    src_ptr = ccall_nobox("w_string_data_ptr", src)
    while pos + 16 <= n
      if js_ascii16_check(src_ptr, pos) != 0
        js_pack16_ascii_block(src_ptr, pos, dst_ptr, out, tbl_ptr)
        pos += 16
        out += 16
      else
        b = raw_load_u8(src_ptr, pos)
        if b < 128
          lc[out] = (b << 8) | JS_ASCII_FLAGS[b]
          pos += 1
          out += 1
        else
          cp = 0
          clen = 1
          if b < 0xE0 && pos + 1 < n
            cp = ((b & 0x1F) << 6) | (raw_load_u8(src_ptr, pos + 1) & 0x3F)
            clen = 2
          elsif b < 0xF0 && pos + 2 < n
            cp = ((b & 0x0F) << 12) | ((raw_load_u8(src_ptr, pos + 1) & 0x3F) << 6) | (raw_load_u8(src_ptr, pos + 2) & 0x3F)
            clen = 3
          elsif pos + 3 < n
            cp = ((b & 0x07) << 18) | ((raw_load_u8(src_ptr, pos + 1) & 0x3F) << 12) | ((raw_load_u8(src_ptr, pos + 2) & 0x3F) << 6) | (raw_load_u8(src_ptr, pos + 3) & 0x3F)
            clen = 4
          fl = 0x60
          if cp == 0x2028 || cp == 0x2029
            fl = 0x80
          elsif cp == 0x00A0 || cp == 0xFEFF || cp == 0x1680 || cp == 0x202F || cp == 0x205F || cp == 0x3000 || (cp >= 0x2000 && cp <= 0x200A)
            fl = 0x10
          elsif cp == 0x200C || cp == 0x200D
            fl = 0x20
          lc[out] = 0x8000 | fl
          pos += clen
          out += 1
    while pos < n
      b = raw_load_u8(src_ptr, pos)
      if b < 128
        lc[out] = (b << 8) | JS_ASCII_FLAGS[b]
        pos += 1
        out += 1
      else
        cp = 0
        clen = 1
        if b < 0xE0 && pos + 1 < n
          cp = ((b & 0x1F) << 6) | (raw_load_u8(src_ptr, pos + 1) & 0x3F)
          clen = 2
        elsif b < 0xF0 && pos + 2 < n
          cp = ((b & 0x0F) << 12) | ((raw_load_u8(src_ptr, pos + 1) & 0x3F) << 6) | (raw_load_u8(src_ptr, pos + 2) & 0x3F)
          clen = 3
        elsif pos + 3 < n
          cp = ((b & 0x07) << 18) | ((raw_load_u8(src_ptr, pos + 1) & 0x3F) << 12) | ((raw_load_u8(src_ptr, pos + 2) & 0x3F) << 6) | (raw_load_u8(src_ptr, pos + 3) & 0x3F)
          clen = 4
        fl = 0x60
        if cp == 0x2028 || cp == 0x2029
          fl = 0x80
        elsif cp == 0x00A0 || cp == 0xFEFF || cp == 0x1680 || cp == 0x202F || cp == 0x205F || cp == 0x3000 || (cp >= 0x2000 && cp <= 0x200A)
          fl = 0x10
        elsif cp == 0x200C || cp == 0x200D
          fl = 0x20
        lc[out] = 0x8000 | fl
        pos += clen
        out += 1
  else
    while pos < n
      b = src.byte_at(pos)
      if b < 128
        lc[out] = (b << 8) | JS_ASCII_FLAGS[b]
        pos += 1
        out += 1
      else
        lc[out] = 0x8060
        pos += 1
        out += 1
  # Zero sentinel pad (16 entries)
  i = 0
  while i < 16
    lc[out + i] = 0
    i += 1
  [lc, out]

# ---- Regex-after-token heuristic (identical to jsn/lexer.w) ----
# Returns 1 if a '/' following `prev_tt` starts a RegExp literal, 0 if division.
fn js_regex_after(prev_tt) (i64) i64
  return 0 if prev_tt == 1 || prev_tt == 2 || prev_tt == 3 || prev_tt == 4 || prev_tt == 5 || prev_tt == 6 || prev_tt == 7
  return 0 if prev_tt == 34 || prev_tt == 32 || prev_tt == 42 || prev_tt == 43 || prev_tt == 44
  return 0 if prev_tt == 61 || prev_tt == 63 || prev_tt == 65 || prev_tt == 76 || prev_tt == 77
  1

# Direct zero-bounds-check u16 load from Lex16 data_ptr (1 ARM64 `ldrh` instruction).
# Safe at `pos == count` because both `lchs("js", bits: 16)` and `js_pack_lex16_simd`
# allocate LEX_SENTINEL_PAD = 16 zero entries immediately after `slots[0..count-1]`.
fn lc16_at(data_ptr, idx) (i64 i64) i64
  ll <<~IR
    %base = inttoptr i64 %data_ptr to ptr
    %p = getelementptr i16, ptr %base, i64 %idx
    %v = load i16, ptr %p, align 2
    %r = zext i16 %v to i64
    ret i64 %r
  IR

# ---- Zero-allocation O(1) keyword classifier on u16[] Lex16 (via raw ptr) ----
## i64: data_ptr, start, len, c0, c1, c2, c3, cl
fn js16_classify_kw(data_ptr, start, len) (i64 i64 i64) i64
  return 1 if len < 2 || len > 10
  c0 = lc16_at(data_ptr, start) >> 8
  c1 = lc16_at(data_ptr, start + 1) >> 8
  case len
  when 2
    if c0 == :-i
      return 26 if c1 == :-f
      return 28 if c1 == :-n
    elsif c0 == :-d && c1 == :-o
      return 19
    return 1
  when 3
    c2 = lc16_at(data_ptr, start + 2) >> 8
    case c0
    when :-f
      return 24 if c1 == :-o && c2 == :-r
    when :-n
      return 30 if c1 == :-e && c2 == :-w
    when :-t
      return 36 if c1 == :-r && c2 == :-y
    when :-v
      return 38 if c1 == :-a && c2 == :-r
    return 1
  when 4
    c2 = lc16_at(data_ptr, start + 2) >> 8
    c3 = lc16_at(data_ptr, start + 3) >> 8
    case c0
    when :-c
      return 11 if c1 == :-a && c2 == :-s && c3 == :-e
    when :-e
      return 20 if c1 == :-l && c2 == :-s && c3 == :-e
      return 45 if c1 == :-n && c2 == :-u && c3 == :-m
    when :-n
      return 42 if c1 == :-u && c2 == :-l && c3 == :-l
    when :-t
      return 34 if c1 == :-h && c2 == :-i && c3 == :-s
      return 43 if c1 == :-r && c2 == :-u && c3 == :-e
    when :-v
      return 39 if c1 == :-o && c2 == :-i && c3 == :-d
    when :-w
      return 41 if c1 == :-i && c2 == :-t && c3 == :-h
    return 1
  when 5
    c2 = lc16_at(data_ptr, start + 2) >> 8
    c3 = lc16_at(data_ptr, start + 3) >> 8
    cl = lc16_at(data_ptr, start + 4) >> 8
    case c0
    when :-b
      return 10 if c1 == :-r && c2 == :-e && c3 == :-a && cl == :-k
    when :-c
      return 12 if c1 == :-a && c2 == :-t && c3 == :-c && cl == :-h
      return 13 if c1 == :-l && c2 == :-a && c3 == :-s && cl == :-s
      return 14 if c1 == :-o && c2 == :-n && c3 == :-s && cl == :-t
    when :-f
      return 44 if c1 == :-a && c2 == :-l && c3 == :-s && cl == :-e
    when :-s
      return 32 if c1 == :-u && c2 == :-p && c3 == :-e && cl == :-r
    when :-t
      return 35 if c1 == :-h && c2 == :-r && c3 == :-o && cl == :-w
    when :-w
      return 40 if c1 == :-h && c2 == :-i && c3 == :-l && cl == :-e
    return 1
  when 6
    c2 = lc16_at(data_ptr, start + 2) >> 8
    c3 = lc16_at(data_ptr, start + 3) >> 8
    cl = lc16_at(data_ptr, start + 5) >> 8
    case c0
    when :-d
      return 18 if c1 == :-e && c2 == :-l && c3 == :-e && (lc16_at(data_ptr, start + 4) >> 8) == :-t && cl == :-e
    when :-e
      return 21 if c1 == :-x && c2 == :-p && c3 == :-o && (lc16_at(data_ptr, start + 4) >> 8) == :-r && cl == :-t
    when :-i
      return 27 if c1 == :-m && c2 == :-p && c3 == :-o && (lc16_at(data_ptr, start + 4) >> 8) == :-r && cl == :-t
    when :-r
      return 31 if c1 == :-e && c2 == :-t && c3 == :-u && (lc16_at(data_ptr, start + 4) >> 8) == :-r && cl == :-n
    when :-s
      return 33 if c1 == :-w && c2 == :-i && c3 == :-t && (lc16_at(data_ptr, start + 4) >> 8) == :-c && cl == :-h
    when :-t
      return 37 if c1 == :-y && c2 == :-p && c3 == :-e && (lc16_at(data_ptr, start + 4) >> 8) == :-o && cl == :-f
    return 1
  when 7
    case c0
    when :-d
      return 17 if c1 == :-e && (lc16_at(data_ptr, start + 2) >> 8) == :-f && (lc16_at(data_ptr, start + 3) >> 8) == :-a && (lc16_at(data_ptr, start + 4) >> 8) == :-u && (lc16_at(data_ptr, start + 5) >> 8) == :-l && (lc16_at(data_ptr, start + 6) >> 8) == :-t
    when :-e
      return 22 if c1 == :-x && (lc16_at(data_ptr, start + 2) >> 8) == :-t && (lc16_at(data_ptr, start + 3) >> 8) == :-e && (lc16_at(data_ptr, start + 4) >> 8) == :-n && (lc16_at(data_ptr, start + 5) >> 8) == :-d && (lc16_at(data_ptr, start + 6) >> 8) == :-s
    when :-f
      return 23 if c1 == :-i && (lc16_at(data_ptr, start + 2) >> 8) == :-n && (lc16_at(data_ptr, start + 3) >> 8) == :-a && (lc16_at(data_ptr, start + 4) >> 8) == :-l && (lc16_at(data_ptr, start + 5) >> 8) == :-l && (lc16_at(data_ptr, start + 6) >> 8) == :-y
    return 1
  when 8
    case c0
    when :-c
      return 15 if c1 == :-o && (lc16_at(data_ptr, start + 2) >> 8) == :-n && (lc16_at(data_ptr, start + 3) >> 8) == :-t && (lc16_at(data_ptr, start + 4) >> 8) == :-i && (lc16_at(data_ptr, start + 5) >> 8) == :-n && (lc16_at(data_ptr, start + 6) >> 8) == :-u && (lc16_at(data_ptr, start + 7) >> 8) == :-e
    when :-d
      return 16 if c1 == :-e && (lc16_at(data_ptr, start + 2) >> 8) == :-b && (lc16_at(data_ptr, start + 3) >> 8) == :-u && (lc16_at(data_ptr, start + 4) >> 8) == :-g && (lc16_at(data_ptr, start + 5) >> 8) == :-g && (lc16_at(data_ptr, start + 6) >> 8) == :-e && (lc16_at(data_ptr, start + 7) >> 8) == :-r
    when :-f
      return 25 if c1 == :-u && (lc16_at(data_ptr, start + 2) >> 8) == :-n && (lc16_at(data_ptr, start + 3) >> 8) == :-c && (lc16_at(data_ptr, start + 4) >> 8) == :-t && (lc16_at(data_ptr, start + 5) >> 8) == :-i && (lc16_at(data_ptr, start + 6) >> 8) == :-o && (lc16_at(data_ptr, start + 7) >> 8) == :-n
    return 1
  when 10
    if c0 == :-i && c1 == :-n && (lc16_at(data_ptr, start + 2) >> 8) == :-s && (lc16_at(data_ptr, start + 3) >> 8) == :-t && (lc16_at(data_ptr, start + 4) >> 8) == :-a && (lc16_at(data_ptr, start + 5) >> 8) == :-n && (lc16_at(data_ptr, start + 6) >> 8) == :-c && (lc16_at(data_ptr, start + 7) >> 8) == :-e && (lc16_at(data_ptr, start + 8) >> 8) == :-o && (lc16_at(data_ptr, start + 9) >> 8) == :-f
      return 29
    return 1
  1

# ---- Lex16 + ARM64 NEON SIMD JavaScript Tokenizer ----
# Input:
#   lc     : u16[] Lex16 array (with 16-entry zero sentinel pad)
#   count  : number of LexChar elements
#   tokens : i64[] output buffer (at least count + 1 entries), receives Token WValues
# Returns: number of emitted tokens (including trailing JT_EOF)
## i64: count, pos, tc, v, w, c, c2, c3, start, len, tt, prev_tt, nl, escaped, data_ptr, tag, sp, in_class, quote, is_big
## u16[]: lc
## i64[]: tokens, tpl_stack
-> js_tokenize_lex16(lc, count, tokens)
  pos = 0
  tc = 0
  nl = 0
  prev_tt = -1
  sp = 0
  tpl_stack = i64[256]
  data_ptr = ccall_nobox("w_array_data_ptr", lc)
  tag = 0xFFFC << 48

  # Hashbang comment (#!...) at offset 0
  if count >= 2 && (lc16_at(data_ptr, 0) >> 8) == :-# && (lc16_at(data_ptr, 1) >> 8) == :-!
    pos = ccall_nobox("w_lex16_scan_until_flag", data_ptr, count, 2, 0x80)

  loop
    v = lc16_at(data_ptr, pos)
    if v == 0
      break
    c = v >> 8

    case v & 0xD7

    # ---- 1. WHITESPACE (0x10) ----
    when 0x10
      pos++
      while (lc16_at(data_ptr, pos) & 0x10) != 0
        pos++

    # ---- 2. NEWLINE (0x80) ----
    when 0x80
      nl = 1
      pos++
      while (lc16_at(data_ptr, pos) & 0x90) != 0
        pos++

    # ---- 3. IDENTIFIER / KEYWORD (0x40) ----
    when 0x40
      start = pos
      pos++
      escaped = 0
      # Hybrid 4-char scalar -> 8-lane NEON scan (matches c/lexer16.w optimal crossover)
      if (lc16_at(data_ptr, pos) & 0x20) != 0
        pos++
        if (lc16_at(data_ptr, pos) & 0x20) != 0
          pos++
          if (lc16_at(data_ptr, pos) & 0x20) != 0
            pos++
            pos = ccall_nobox("w_lex16_scan_flag", data_ptr, count, pos, 0x20)
      # Rare unicode escape (\uXXXX) OR non-ASCII UTF-8 bytes inside identifier
      while ((lc16_at(data_ptr, pos) >> 8) == :-\\ && (lc16_at(data_ptr, pos + 1) >> 8) == :-u) || ((lc16_at(data_ptr, pos) >> 8) == 0x80 && (lc16_at(data_ptr, pos) & 0x90) == 0)
        escaped = 2
        if (lc16_at(data_ptr, pos) >> 8) == 0x80
          pos++
        else
          pos += 2
          if (lc16_at(data_ptr, pos) >> 8) == :-{
            pos++
            while lc16_at(data_ptr, pos) != 0 && (lc16_at(data_ptr, pos) >> 8) != :-}
              pos++
            pos++ if (lc16_at(data_ptr, pos) >> 8) == :-}
          else
            pos += 4
        while (lc16_at(data_ptr, pos) & 0x20) != 0
          pos++
      len = pos - start
      tt = escaped == 0 ? js16_classify_kw(data_ptr, start, len) : 1
      tokens[tc] = tag | (tt << 38) | (jt_clen(len) << 26) | (start << 2) | escaped | nl
      tc++
      prev_tt = tt
      nl = 0

    # ---- 4. OPERATOR / PUNCTUATOR / COMMENT / REGEX / PRIVATE (0x04) ----
    when 0x04
      start = pos

      # Fast path for single-char delimiters: ( ) [ ] ; , : ~ @
      if c == :-(
        tokens[tc] = tag | (62 << 38) | (1 << 26) | (pos << 2) | nl
        tc++; pos++; prev_tt = 62; nl = 0; next
      elsif c == :-)
        tokens[tc] = tag | (63 << 38) | (1 << 26) | (pos << 2) | nl
        tc++; pos++; prev_tt = 63; nl = 0; next
      elsif c == :-;
        tokens[tc] = tag | (66 << 38) | (1 << 26) | (pos << 2) | nl
        tc++; pos++; prev_tt = 66; nl = 0; next
      elsif c == :-,
        tokens[tc] = tag | (67 << 38) | (1 << 26) | (pos << 2) | nl
        tc++; pos++; prev_tt = 67; nl = 0; next
      elsif c == :-[
        tokens[tc] = tag | (64 << 38) | (1 << 26) | (pos << 2) | nl
        tc++; pos++; prev_tt = 64; nl = 0; next
      elsif c == :-]
        tokens[tc] = tag | (65 << 38) | (1 << 26) | (pos << 2) | nl
        tc++; pos++; prev_tt = 65; nl = 0; next
      elsif c == :-:
        tokens[tc] = tag | (72 << 38) | (1 << 26) | (pos << 2) | nl
        tc++; pos++; prev_tt = 72; nl = 0; next
      elsif c == :-~
        tokens[tc] = tag | (74 << 38) | (1 << 26) | (pos << 2) | nl
        tc++; pos++; prev_tt = 74; nl = 0; next
      elsif c == :-@
        tokens[tc] = tag | (78 << 38) | (1 << 26) | (pos << 2) | nl
        tc++; pos++; prev_tt = 78; nl = 0; next
      elsif c == :-{
        if sp < 256
          tpl_stack[sp] = 0
          sp++
        tokens[tc] = tag | (60 << 38) | (1 << 26) | (pos << 2) | nl
        tc++; pos++; prev_tt = 60; nl = 0; next
      elsif c == :-}
        if sp > 0 && tpl_stack[sp - 1] == 1
          # Resume template literal scanning!
          sp--
          pos++
          loop
            pos = js_lex16_scan_tpl_simd(data_ptr, pos)
            w = lc16_at(data_ptr, pos)
            if w == 0
              return -1
            c2 = w >> 8
            if c2 == :-`
              pos++
              tokens[tc] = tag | (5 << 38) | (jt_clen(pos - start) << 26) | (start << 2) | 2 | nl
              tc++; prev_tt = 5; nl = 0
              break
            elsif c2 == :-$
              if (lc16_at(data_ptr, pos + 1) >> 8) == :-{
                pos += 2
                if sp < 256
                  tpl_stack[sp] = 1
                  sp++
                tokens[tc] = tag | (5 << 38) | (jt_clen(pos - start) << 26) | (start << 2) | nl
                tc++; prev_tt = 60; nl = 0
                break
              pos++
            else
              # '\' escape
              if (lc16_at(data_ptr, pos + 1) >> 8) == 0x80 && (lc16_at(data_ptr, pos + 1) & 0x80) != 0
                pos += 4
              else
                pos += 2
              return -1 if pos >= count
          next
        sp-- if sp > 0
        tokens[tc] = tag | (61 << 38) | (1 << 26) | (pos << 2) | nl
        tc++; pos++; prev_tt = 61; nl = 0; next

      c2 = lc16_at(data_ptr, pos + 1) >> 8

      # Slash: // comment, /* comment */, /regex/flags, /=, /
      if c == :-/
        if c2 == :-/
          pos = ccall_nobox("w_lex16_scan_until_flag", data_ptr, count, pos + 2, 0x80)
          next
        elsif c2 == :-*
          pos += 2
          loop
            pos = js_lex16_scan_bcomment_simd(data_ptr, pos)
            w = lc16_at(data_ptr, pos)
            if w == 0
              return -1
            if (w & 0x80) != 0
              nl = 1
              pos++
            elsif (w >> 8) == :-* && (lc16_at(data_ptr, pos + 1) >> 8) == :-/
              pos += 2
              break
            else
              pos++
          next
        elsif js_regex_after(prev_tt) != 0
          pos++
          in_class = 0
          loop
            pos = js_lex16_scan_regex_simd(data_ptr, pos)
            w = lc16_at(data_ptr, pos)
            if w == 0 || (w & 0x80) != 0
              break
            c3 = w >> 8
            if c3 == :-\\
              if lc16_at(data_ptr, pos + 1) == 0 || (lc16_at(data_ptr, pos + 1) & 0x80) != 0
                break
              pos += 2
            elsif c3 == :-[
              in_class = 1
              pos++
            elsif c3 == :-]
              in_class = 0
              pos++
            elsif c3 == :-/ && in_class == 0
              pos++
              while (lc16_at(data_ptr, pos) & 0x20) != 0
                pos++
              break
            else
              pos++
          tokens[tc] = tag | (6 << 38) | (jt_clen(pos - start) << 26) | (start << 2) | nl
          tc++; prev_tt = 6; nl = 0; next
        elsif c2 == :-=
          tokens[tc] = tag | (114 << 38) | (2 << 26) | (pos << 2) | nl
          tc++; pos += 2; prev_tt = 114; nl = 0; next
        else
          tokens[tc] = tag | (100 << 38) | (1 << 26) | (pos << 2) | nl
          tc++; pos++; prev_tt = 100; nl = 0; next

      # Dot: .5 float, ... ellipsis, . member
      if c == :-.
        if (lc16_at(data_ptr, pos + 1) & 0x01) != 0
          pos += 2
          while (lc16_at(data_ptr, pos) & 0x01) != 0 || (lc16_at(data_ptr, pos) >> 8) == :-_
            pos++
          c3 = lc16_at(data_ptr, pos) >> 8
          if c3 == :-e || c3 == :-E
            pos++
            c3 = lc16_at(data_ptr, pos) >> 8
            pos++ if c3 == :-+ || c3 == :--
            while (lc16_at(data_ptr, pos) & 0x01) != 0 || (lc16_at(data_ptr, pos) >> 8) == :-_
              pos++
          tokens[tc] = tag | (2 << 38) | (jt_clen(pos - start) << 26) | (start << 2) | nl
          tc++; prev_tt = 2; nl = 0; next
        elsif c2 == :-. && (lc16_at(data_ptr, pos + 2) >> 8) == :-.
          tokens[tc] = tag | (69 << 38) | (3 << 26) | (pos << 2) | nl
          tc++; pos += 3; prev_tt = 69; nl = 0; next
        else
          tokens[tc] = tag | (68 << 38) | (1 << 26) | (pos << 2) | nl
          tc++; pos++; prev_tt = 68; nl = 0; next

      # Private identifier (#foo)
      if c == :-#
        pos++
        while (lc16_at(data_ptr, pos) & 0x20) != 0 || ((lc16_at(data_ptr, pos) >> 8) == 0x80 && (lc16_at(data_ptr, pos) & 0x90) == 0)
          pos++
        tokens[tc] = tag | (7 << 38) | (jt_clen(pos - start) << 26) | (start << 2) | nl
        tc++; prev_tt = 7; nl = 0; next

      # Remaining multi-char operators
      tt = 0
      len = 1
      case c
      when :-=
        if c2 == :-=
          if (lc16_at(data_ptr, pos + 2) >> 8) == :-=
            tt = 88; len = 3
          else
            tt = 86; len = 2
        elsif c2 == :->
          tt = 73; len = 2
        else
          tt = 110; len = 1
      when :-!
        if c2 == :-=
          if (lc16_at(data_ptr, pos + 2) >> 8) == :-=
            tt = 89; len = 3
          else
            tt = 87; len = 2
        else
          tt = 75; len = 1
      when :-+
        if c2 == :-+
          tt = 76; len = 2
        elsif c2 == :-=
          tt = 111; len = 2
        else
          tt = 97; len = 1
      when :--
        if c2 == :--
          # Annex-B HTML close comment `-->` at start of line -> fall back to pull lexer
          return -1 if (lc16_at(data_ptr, pos + 2) >> 8) == :-> && (nl != 0 || prev_tt < 0)
          tt = 77; len = 2
        elsif c2 == :-=
          tt = 112; len = 2
        else
          tt = 98; len = 1
      when :-*
        if c2 == :-*
          if (lc16_at(data_ptr, pos + 2) >> 8) == :-=
            tt = 116; len = 3
          else
            tt = 102; len = 2
        elsif c2 == :-=
          tt = 113; len = 2
        else
          tt = 99; len = 1
      when :-%
        if c2 == :-=
          tt = 115; len = 2
        else
          tt = 101; len = 1
      when :-<
        if c2 == :-<
          if (lc16_at(data_ptr, pos + 2) >> 8) == :-=
            tt = 117; len = 3
          else
            tt = 94; len = 2
        elsif c2 == :-=
          tt = 92; len = 2
        elsif c2 == :-! && (lc16_at(data_ptr, pos + 2) >> 8) == :-- && (lc16_at(data_ptr, pos + 3) >> 8) == :--
          # Annex-B HTML open comment `<!--` -> fall back to pull lexer (which knows @module)
          return -1
        else
          tt = 90; len = 1
      when :->
        if c2 == :->
          if (lc16_at(data_ptr, pos + 2) >> 8) == :->
            if (lc16_at(data_ptr, pos + 3) >> 8) == :-=
              tt = 119; len = 4
            else
              tt = 96; len = 3
          elsif (lc16_at(data_ptr, pos + 2) >> 8) == :-=
            tt = 118; len = 3
          else
            tt = 95; len = 2
        elsif c2 == :-=
          tt = 93; len = 2
        else
          tt = 91; len = 1
      when :-&
        if c2 == :-&
          if (lc16_at(data_ptr, pos + 2) >> 8) == :-=
            tt = 123; len = 3
          else
            tt = 82; len = 2
        elsif c2 == :-=
          tt = 120; len = 2
        else
          tt = 85; len = 1
      when :-|
        if c2 == :-|
          if (lc16_at(data_ptr, pos + 2) >> 8) == :-=
            tt = 124; len = 3
          else
            tt = 81; len = 2
        elsif c2 == :-=
          tt = 121; len = 2
        else
          tt = 83; len = 1
      when :-^
        if c2 == :-=
          tt = 122; len = 2
        else
          tt = 84; len = 1
      when :-?
        if c2 == :-?
          if (lc16_at(data_ptr, pos + 2) >> 8) == :-=
            tt = 125; len = 3
          else
            tt = 80; len = 2
        elsif c2 == :-. && (lc16_at(data_ptr, pos + 2) & 0x01) == 0
          tt = 71; len = 2
        else
          tt = 70; len = 1
      tokens[tc] = tag | (tt << 38) | (len << 26) | (pos << 2) | nl
      tc++; pos += len; prev_tt = tt; nl = 0

    # ---- 5. STRING / TEMPLATE LITERALS (0x02) ----
    when 0x02
      start = pos
      pos++
      if c == :-`
        # Template literal: NEON 8-lane scan for '`', '$', or '\'
        loop
          pos = js_lex16_scan_tpl_simd(data_ptr, pos)
          w = lc16_at(data_ptr, pos)
          if w == 0
            return -1
          c2 = w >> 8
          if c2 == :-`
            pos++
            tokens[tc] = tag | (5 << 38) | (jt_clen(pos - start) << 26) | (start << 2) | 2 | nl
            tc++; prev_tt = 5; nl = 0
            break
          elsif c2 == :-$
            if (lc16_at(data_ptr, pos + 1) >> 8) == :-{
              pos += 2
              if sp < 256
                tpl_stack[sp] = 1
                sp++
              tokens[tc] = tag | (5 << 38) | (jt_clen(pos - start) << 26) | (start << 2) | nl
              tc++; prev_tt = 60; nl = 0
              break
            pos++
          else
            if (lc16_at(data_ptr, pos + 1) >> 8) == 0x80 && (lc16_at(data_ptr, pos + 1) & 0x80) != 0
              pos += 4
            else
              pos += 2
            return -1 if pos >= count
      else
        # Single or double quoted string: NEON js_lex16_scan_str_simd (stops on quote, '\', newline, or EOF)
        quote = c
        escaped = 0
        loop
          pos = js_lex16_scan_str_simd(data_ptr, pos, quote)
          w = lc16_at(data_ptr, pos)
          if w == 0
            escaped = 2
            break
          c2 = w >> 8
          if (w & 0x80) != 0
            if c2 == 0x80
              # ES2019: unescaped U+2028 / U+2029 are legal inside string literals
              pos += 3
              next
            escaped = 2
            break
          if c2 == quote
            pos++
            break
          # backslash escape
          escaped = 2
          if (lc16_at(data_ptr, pos + 1) >> 8) == 13 && (lc16_at(data_ptr, pos + 2) >> 8) == 10
            pos += 3
          elsif (lc16_at(data_ptr, pos + 1) >> 8) == 0x80 && (lc16_at(data_ptr, pos + 1) & 0x80) != 0
            pos += 4
          else
            pos += 2
        tokens[tc] = tag | (4 << 38) | (jt_clen(pos - start) << 26) | (start << 2) | escaped | nl
        tc++; prev_tt = 4; nl = 0

    # ---- 6. NUMBERS & BIGINTS (0x01) ----
    when 0x01
      start = pos
      is_big = 0
      if c == :-0
        c2 = lc16_at(data_ptr, pos + 1) >> 8
        if c2 == :-x || c2 == :-X
          pos += 2
          while (lc16_at(data_ptr, pos) & 0x08) != 0 || (lc16_at(data_ptr, pos) >> 8) == :-_
            pos++
        elsif c2 == :-b || c2 == :-B
          pos += 2
          while (lc16_at(data_ptr, pos) >> 8) == :-0 || (lc16_at(data_ptr, pos) >> 8) == :-1 || (lc16_at(data_ptr, pos) >> 8) == :-_
            pos++
        elsif c2 == :-o || c2 == :-O
          pos += 2
          while ((lc16_at(data_ptr, pos) >> 8) >= 48 && (lc16_at(data_ptr, pos) >> 8) <= 55) || (lc16_at(data_ptr, pos) >> 8) == :-_
            pos++
        else
          pos++
          while (lc16_at(data_ptr, pos) & 0x01) != 0 || (lc16_at(data_ptr, pos) >> 8) == :-_
            pos++
      else
        pos++
        while (lc16_at(data_ptr, pos) & 0x01) != 0 || (lc16_at(data_ptr, pos) >> 8) == :-_
          pos++

      # Fractional part
      if (lc16_at(data_ptr, pos) >> 8) == :-.
        pos++
        while (lc16_at(data_ptr, pos) & 0x01) != 0 || (lc16_at(data_ptr, pos) >> 8) == :-_
          pos++

      # Exponent part
      c2 = lc16_at(data_ptr, pos) >> 8
      if c2 == :-e || c2 == :-E
        pos++
        c2 = lc16_at(data_ptr, pos) >> 8
        pos++ if c2 == :-+ || c2 == :--
        while (lc16_at(data_ptr, pos) & 0x01) != 0 || (lc16_at(data_ptr, pos) >> 8) == :-_
          pos++

      # BigInt suffix 'n'
      if (lc16_at(data_ptr, pos) >> 8) == :-n
        pos++
        is_big = 1

      tt = is_big != 0 ? 3 : 2
      tokens[tc] = tag | (tt << 38) | (jt_clen(pos - start) << 26) | (start << 2) | nl
      tc++; prev_tt = tt; nl = 0

    # ---- 7. Escape-starting (\uXXXX) or non-ASCII identifier, else illegal char -> fallback ----
    else
      if (c == :-\\ && (lc16_at(data_ptr, pos + 1) >> 8) == :-u) || c == 0x80
        start = pos
        loop
          w = lc16_at(data_ptr, pos)
          if (w >> 8) == :-\\ && (lc16_at(data_ptr, pos + 1) >> 8) == :-u
            pos += 2
            if (lc16_at(data_ptr, pos) >> 8) == :-{
              pos++
              while lc16_at(data_ptr, pos) != 0 && (lc16_at(data_ptr, pos) >> 8) != :-}
                pos++
              pos++ if (lc16_at(data_ptr, pos) >> 8) == :-}
            else
              pos += 4
          elsif (w & 0x20) != 0 || ((w >> 8) == 0x80 && (w & 0x90) == 0)
            pos++
          else
            break
        tokens[tc] = tag | (1 << 38) | (jt_clen(pos - start) << 26) | (start << 2) | 2 | nl
        tc++; prev_tt = 1; nl = 0
      else
        return -1

  # Trailing EOF token
  tokens[tc] = tag | (0 << 38) | (pos << 2) | nl
  tc + 1

# ---- Full 64-bit LexChar WValue (W_TAG_CHAR subtype 01) Tokenizer ----
# Operates directly on `source.lchs("js", bits: 64)` (true 64-bit LexChar WValues)
# and emits identical 64-bit Token WValues (W_TAG_CHAR subtype 00).
## i64: start, len, c0, c1, c2, c3, cl, m
## i64[]: lc
fn js64_classify_kw(lc, start, len) (i64[] i64 i64) i64
  return 1 if len < 2 || len > 10
  m = 0x1FFFFF
  c0 = (lc[start] >> 18) & m
  c1 = (lc[start + 1] >> 18) & m
  case len
  when 2
    if c0 == :-i
      return 26 if c1 == :-f
      return 28 if c1 == :-n
    elsif c0 == :-d && c1 == :-o
      return 19
    return 1
  when 3
    c2 = (lc[start + 2] >> 18) & m
    case c0
    when :-f
      return 24 if c1 == :-o && c2 == :-r
    when :-n
      return 30 if c1 == :-e && c2 == :-w
    when :-t
      return 36 if c1 == :-r && c2 == :-y
    when :-v
      return 38 if c1 == :-a && c2 == :-r
    return 1
  when 4
    c2 = (lc[start + 2] >> 18) & m
    c3 = (lc[start + 3] >> 18) & m
    case c0
    when :-c
      return 11 if c1 == :-a && c2 == :-s && c3 == :-e
    when :-e
      return 20 if c1 == :-l && c2 == :-s && c3 == :-e
      return 45 if c1 == :-n && c2 == :-u && c3 == :-m
    when :-n
      return 42 if c1 == :-u && c2 == :-l && c3 == :-l
    when :-t
      return 34 if c1 == :-h && c2 == :-i && c3 == :-s
      return 43 if c1 == :-r && c2 == :-u && c3 == :-e
    when :-v
      return 39 if c1 == :-o && c2 == :-i && c3 == :-d
    when :-w
      return 41 if c1 == :-i && c2 == :-t && c3 == :-h
    return 1
  when 5
    c2 = (lc[start + 2] >> 18) & m
    c3 = (lc[start + 3] >> 18) & m
    cl = (lc[start + 4] >> 18) & m
    case c0
    when :-b
      return 10 if c1 == :-r && c2 == :-e && c3 == :-a && cl == :-k
    when :-c
      return 12 if c1 == :-a && c2 == :-t && c3 == :-c && cl == :-h
      return 13 if c1 == :-l && c2 == :-a && c3 == :-s && cl == :-s
      return 14 if c1 == :-o && c2 == :-n && c3 == :-s && cl == :-t
    when :-f
      return 44 if c1 == :-a && c2 == :-l && c3 == :-s && cl == :-e
    when :-s
      return 32 if c1 == :-u && c2 == :-p && c3 == :-e && cl == :-r
    when :-t
      return 35 if c1 == :-h && c2 == :-r && c3 == :-o && cl == :-w
    when :-w
      return 40 if c1 == :-h && c2 == :-i && c3 == :-l && cl == :-e
    return 1
  when 6
    c2 = (lc[start + 2] >> 18) & m
    c3 = (lc[start + 3] >> 18) & m
    cl = (lc[start + 5] >> 18) & m
    case c0
    when :-d
      return 18 if c1 == :-e && c2 == :-l && c3 == :-e && ((lc[start + 4] >> 18) & m) == :-t && cl == :-e
    when :-e
      return 21 if c1 == :-x && c2 == :-p && c3 == :-o && ((lc[start + 4] >> 18) & m) == :-r && cl == :-t
    when :-i
      return 27 if c1 == :-m && c2 == :-p && c3 == :-o && ((lc[start + 4] >> 18) & m) == :-r && cl == :-t
    when :-r
      return 31 if c1 == :-e && c2 == :-t && c3 == :-u && ((lc[start + 4] >> 18) & m) == :-r && cl == :-n
    when :-s
      return 33 if c1 == :-w && c2 == :-i && c3 == :-t && ((lc[start + 4] >> 18) & m) == :-c && cl == :-h
    when :-t
      return 37 if c1 == :-y && c2 == :-p && c3 == :-e && ((lc[start + 4] >> 18) & m) == :-o && cl == :-f
    return 1
  when 7
    case c0
    when :-d
      return 17 if c1 == :-e && ((lc[start + 2] >> 18) & m) == :-f && ((lc[start + 3] >> 18) & m) == :-a && ((lc[start + 4] >> 18) & m) == :-u && ((lc[start + 5] >> 18) & m) == :-l && ((lc[start + 6] >> 18) & m) == :-t
    when :-e
      return 22 if c1 == :-x && ((lc[start + 2] >> 18) & m) == :-t && ((lc[start + 3] >> 18) & m) == :-e && ((lc[start + 4] >> 18) & m) == :-n && ((lc[start + 5] >> 18) & m) == :-d && ((lc[start + 6] >> 18) & m) == :-s
    when :-f
      return 23 if c1 == :-i && ((lc[start + 2] >> 18) & m) == :-n && ((lc[start + 3] >> 18) & m) == :-a && ((lc[start + 4] >> 18) & m) == :-l && ((lc[start + 5] >> 18) & m) == :-l && ((lc[start + 6] >> 18) & m) == :-y
    return 1
  when 8
    case c0
    when :-c
      return 15 if c1 == :-o && ((lc[start + 2] >> 18) & m) == :-n && ((lc[start + 3] >> 18) & m) == :-t && ((lc[start + 4] >> 18) & m) == :-i && ((lc[start + 5] >> 18) & m) == :-n && ((lc[start + 6] >> 18) & m) == :-u && ((lc[start + 7] >> 18) & m) == :-e
    when :-d
      return 16 if c1 == :-e && ((lc[start + 2] >> 18) & m) == :-b && ((lc[start + 3] >> 18) & m) == :-u && ((lc[start + 4] >> 18) & m) == :-g && ((lc[start + 5] >> 18) & m) == :-g && ((lc[start + 6] >> 18) & m) == :-e && ((lc[start + 7] >> 18) & m) == :-r
    when :-f
      return 25 if c1 == :-u && ((lc[start + 2] >> 18) & m) == :-n && ((lc[start + 3] >> 18) & m) == :-c && ((lc[start + 4] >> 18) & m) == :-t && ((lc[start + 5] >> 18) & m) == :-i && ((lc[start + 6] >> 18) & m) == :-o && ((lc[start + 7] >> 18) & m) == :-n
    return 1
  when 10
    if c0 == :-i && c1 == :-n && ((lc[start + 2] >> 18) & m) == :-s && ((lc[start + 3] >> 18) & m) == :-t && ((lc[start + 4] >> 18) & m) == :-a && ((lc[start + 5] >> 18) & m) == :-n && ((lc[start + 6] >> 18) & m) == :-c && ((lc[start + 7] >> 18) & m) == :-e && ((lc[start + 8] >> 18) & m) == :-o && ((lc[start + 9] >> 18) & m) == :-f
      return 29
    return 1
  1

## i64: count, pos, tc, v, c, c2, c3, start, len, tt, prev_tt, nl, escaped, tag, sp, in_class, quote, is_big, m
## i64[]: lc, tokens, tpl_stack
-> js_tokenize_lex64(lc, count, tokens)
  pos = 0
  tc = 0
  nl = 0
  prev_tt = -1
  sp = 0
  tpl_stack = i64[256]
  tag = 0xFFFC << 48
  m = 0x1FFFFF

  if count >= 2 && ((lc[0] >> 18) & m) == :-# && ((lc[1] >> 18) & m) == :-!
    pos = 2
    while pos < count && (lc[pos] & 0x80) == 0
      pos++

  while pos < count
    v = lc[pos]
    c = (v >> 18) & m

    case v & 0xD7
    when 0x10
      pos++
      while pos < count && (lc[pos] & 0x10) != 0
        pos++
    when 0x80
      nl = 1
      pos++
      while pos < count && (lc[pos] & 0x90) != 0
        pos++
    when 0x40
      start = pos
      pos++
      escaped = 0
      while pos < count && (lc[pos] & 0x20) != 0
        pos++
      while pos + 1 < count && ((lc[pos] >> 18) & m) == :-\\ && ((lc[pos + 1] >> 18) & m) == :-u
        escaped = 2
        pos += 2
        if pos < count && ((lc[pos] >> 18) & m) == :-{
          pos++
          while pos < count && ((lc[pos] >> 18) & m) != :-}
            pos++
          pos++ if pos < count
        else
          pos += 4
        while pos < count && (lc[pos] & 0x20) != 0
          pos++
      len = pos - start
      tt = escaped == 0 ? js64_classify_kw(lc, start, len) : 1
      tokens[tc] = tag | (tt << 38) | (jt_clen(len) << 26) | (start << 2) | escaped | nl
      tc++; prev_tt = tt; nl = 0
    when 0x04
      start = pos
      if c == :-(
        tokens[tc] = tag | (62 << 38) | (1 << 26) | (pos << 2) | nl
        tc++; pos++; prev_tt = 62; nl = 0; next
      elsif c == :-)
        tokens[tc] = tag | (63 << 38) | (1 << 26) | (pos << 2) | nl
        tc++; pos++; prev_tt = 63; nl = 0; next
      elsif c == :-;
        tokens[tc] = tag | (66 << 38) | (1 << 26) | (pos << 2) | nl
        tc++; pos++; prev_tt = 66; nl = 0; next
      elsif c == :-,
        tokens[tc] = tag | (67 << 38) | (1 << 26) | (pos << 2) | nl
        tc++; pos++; prev_tt = 67; nl = 0; next
      elsif c == :-[
        tokens[tc] = tag | (64 << 38) | (1 << 26) | (pos << 2) | nl
        tc++; pos++; prev_tt = 64; nl = 0; next
      elsif c == :-]
        tokens[tc] = tag | (65 << 38) | (1 << 26) | (pos << 2) | nl
        tc++; pos++; prev_tt = 65; nl = 0; next
      elsif c == :-:
        tokens[tc] = tag | (72 << 38) | (1 << 26) | (pos << 2) | nl
        tc++; pos++; prev_tt = 72; nl = 0; next
      elsif c == :-~
        tokens[tc] = tag | (74 << 38) | (1 << 26) | (pos << 2) | nl
        tc++; pos++; prev_tt = 74; nl = 0; next
      elsif c == :-@
        tokens[tc] = tag | (78 << 38) | (1 << 26) | (pos << 2) | nl
        tc++; pos++; prev_tt = 78; nl = 0; next
      elsif c == :-{
        if sp < 256
          tpl_stack[sp] = 0
          sp++
        tokens[tc] = tag | (60 << 38) | (1 << 26) | (pos << 2) | nl
        tc++; pos++; prev_tt = 60; nl = 0; next
      elsif c == :-}
        if sp > 0 && tpl_stack[sp - 1] == 1
          sp--
          pos++
          while pos < count
            c2 = (lc[pos] >> 18) & m
            if c2 == :-`
              pos++
              tokens[tc] = tag | (5 << 38) | (jt_clen(pos - start) << 26) | (start << 2) | 2 | nl
              tc++; prev_tt = 5; nl = 0
              break
            elsif c2 == :-$ && pos + 1 < count && ((lc[pos + 1] >> 18) & m) == :-{
              pos += 2
              if sp < 256
                tpl_stack[sp] = 1
                sp++
              tokens[tc] = tag | (5 << 38) | (jt_clen(pos - start) << 26) | (start << 2) | nl
              tc++; prev_tt = 5; nl = 0
              break
            elsif c2 == :-\\
              pos += 2
            else
              pos++
          next
        sp-- if sp > 0
        tokens[tc] = tag | (61 << 38) | (1 << 26) | (pos << 2) | nl
        tc++; pos++; prev_tt = 61; nl = 0; next

      c2 = pos + 1 < count ? ((lc[pos + 1] >> 18) & m) : 0
      if c == :-/
        if c2 == :-/
          pos += 2
          while pos < count && (lc[pos] & 0x80) == 0
            pos++
          next
        elsif c2 == :-*
          pos += 2
          while pos < count
            if (lc[pos] & 0x80) != 0
              nl = 1
              pos++
            elsif ((lc[pos] >> 18) & m) == :-* && pos + 1 < count && ((lc[pos + 1] >> 18) & m) == :-/
              pos += 2
              break
            else
              pos++
          next
        elsif js_regex_after(prev_tt) != 0
          pos++
          in_class = 0
          while pos < count && (lc[pos] & 0x80) == 0
            c3 = (lc[pos] >> 18) & m
            if c3 == :-\\
              break if pos + 1 >= count || (lc[pos + 1] & 0x80) != 0
              pos += 2
            elsif c3 == :-[
              in_class = 1
              pos++
            elsif c3 == :-]
              in_class = 0
              pos++
            elsif c3 == :-/ && in_class == 0
              pos++
              while pos < count && (lc[pos] & 0x20) != 0
                pos++
              break
            else
              pos++
          tokens[tc] = tag | (6 << 38) | (jt_clen(pos - start) << 26) | (start << 2) | nl
          tc++; prev_tt = 6; nl = 0; next
        elsif c2 == :-=
          tokens[tc] = tag | (114 << 38) | (2 << 26) | (pos << 2) | nl
          tc++; pos += 2; prev_tt = 114; nl = 0; next
        else
          tokens[tc] = tag | (100 << 38) | (1 << 26) | (pos << 2) | nl
          tc++; pos++; prev_tt = 100; nl = 0; next

      if c == :-.
        if pos + 1 < count && (lc[pos + 1] & 0x01) != 0
          pos += 2
          while pos < count && ((lc[pos] & 0x01) != 0 || ((lc[pos] >> 18) & m) == :-_)
            pos++
          c3 = pos < count ? ((lc[pos] >> 18) & m) : 0
          if c3 == :-e || c3 == :-E
            pos++
            c3 = pos < count ? ((lc[pos] >> 18) & m) : 0
            pos++ if c3 == :-+ || c3 == :--
            while pos < count && ((lc[pos] & 0x01) != 0 || ((lc[pos] >> 18) & m) == :-_)
              pos++
          tokens[tc] = tag | (2 << 38) | (jt_clen(pos - start) << 26) | (start << 2) | nl
          tc++; prev_tt = 2; nl = 0; next
        elsif c2 == :-. && pos + 2 < count && ((lc[pos + 2] >> 18) & m) == :-.
          tokens[tc] = tag | (69 << 38) | (3 << 26) | (pos << 2) | nl
          tc++; pos += 3; prev_tt = 69; nl = 0; next
        else
          tokens[tc] = tag | (68 << 38) | (1 << 26) | (pos << 2) | nl
          tc++; pos++; prev_tt = 68; nl = 0; next

      if c == :-#
        pos++
        while pos < count && (lc[pos] & 0x20) != 0
          pos++
        tokens[tc] = tag | (7 << 38) | (jt_clen(pos - start) << 26) | (start << 2) | nl
        tc++; prev_tt = 7; nl = 0; next

      tt = 0; len = 1
      c3 = pos + 2 < count ? ((lc[pos + 2] >> 18) & m) : 0
      case c
      when :-=
        if c2 == :-=
          tt = c3 == :-= ? 88 : 86
          len = c3 == :-= ? 3 : 2
        elsif c2 == :->
          tt = 73; len = 2
        else
          tt = 110; len = 1
      when :-!
        if c2 == :-=
          tt = c3 == :-= ? 89 : 87
          len = c3 == :-= ? 3 : 2
        else
          tt = 75; len = 1
      when :-+
        if c2 == :-+
          tt = 76; len = 2
        elsif c2 == :-=
          tt = 111; len = 2
        else
          tt = 97; len = 1
      when :--
        if c2 == :--
          tt = 77; len = 2
        elsif c2 == :-=
          tt = 112; len = 2
        else
          tt = 98; len = 1
      when :-*
        if c2 == :-*
          tt = c3 == :-= ? 116 : 102
          len = c3 == :-= ? 3 : 2
        elsif c2 == :-=
          tt = 113; len = 2
        else
          tt = 99; len = 1
      when :-%
        tt = c2 == :-= ? 115 : 101
        len = c2 == :-= ? 2 : 1
      when :-<
        if c2 == :-<
          tt = c3 == :-= ? 117 : 94
          len = c3 == :-= ? 3 : 2
        elsif c2 == :-=
          tt = 92; len = 2
        else
          tt = 90; len = 1
      when :->
        if c2 == :->
          if c3 == :->
            if pos + 3 < count && ((lc[pos + 3] >> 18) & m) == :-=
              tt = 119; len = 4
            else
              tt = 96; len = 3
          elsif c3 == :-=
            tt = 118; len = 3
          else
            tt = 95; len = 2
        elsif c2 == :-=
          tt = 93; len = 2
        else
          tt = 91; len = 1
      when :-&
        if c2 == :-&
          tt = c3 == :-= ? 123 : 82
          len = c3 == :-= ? 3 : 2
        elsif c2 == :-=
          tt = 120; len = 2
        else
          tt = 85; len = 1
      when :-|
        if c2 == :-|
          tt = c3 == :-= ? 124 : 81
          len = c3 == :-= ? 3 : 2
        elsif c2 == :-=
          tt = 121; len = 2
        else
          tt = 83; len = 1
      when :-^
        tt = c2 == :-= ? 122 : 84
        len = c2 == :-= ? 2 : 1
      when :-?
        if c2 == :-?
          tt = c3 == :-= ? 125 : 80
          len = c3 == :-= ? 3 : 2
        elsif c2 == :-. && !(pos + 2 < count && (lc[pos + 2] & 0x01) != 0)
          tt = 71; len = 2
        else
          tt = 70; len = 1
      tokens[tc] = tag | (tt << 38) | (len << 26) | (pos << 2) | nl
      tc++; pos += len; prev_tt = tt; nl = 0
    when 0x02
      start = pos
      pos++
      if c == :-`
        while pos < count
          c2 = (lc[pos] >> 18) & m
          if c2 == :-`
            pos++
            tokens[tc] = tag | (5 << 38) | (jt_clen(pos - start) << 26) | (start << 2) | 2 | nl
            tc++; prev_tt = 5; nl = 0
            break
          elsif c2 == :-$ && pos + 1 < count && ((lc[pos + 1] >> 18) & m) == :-{
            pos += 2
            if sp < 256
              tpl_stack[sp] = 1
              sp++
            tokens[tc] = tag | (5 << 38) | (jt_clen(pos - start) << 26) | (start << 2) | nl
            tc++; prev_tt = 5; nl = 0
            break
          elsif c2 == :-\\
            pos += 2
          else
            pos++
      else
        quote = c
        while pos < count && (lc[pos] & 0x80) == 0
          c2 = (lc[pos] >> 18) & m
          if c2 == quote
            pos++
            break
          elsif c2 == :-\\
            pos += 2
          else
            pos++
        tokens[tc] = tag | (4 << 38) | (jt_clen(pos - start) << 26) | (start << 2) | nl
        tc++; prev_tt = 4; nl = 0
    when 0x01
      start = pos
      is_big = 0
      c2 = pos + 1 < count ? ((lc[pos + 1] >> 18) & m) : 0
      if c == :-0 && (c2 == :-x || c2 == :-X)
        pos += 2
        while pos < count && ((lc[pos] & 0x08) != 0 || ((lc[pos] >> 18) & m) == :-_)
          pos++
      elsif c == :-0 && (c2 == :-b || c2 == :-B)
        pos += 2
        while pos < count && (((lc[pos] >> 18) & m) == :-0 || ((lc[pos] >> 18) & m) == :-1 || ((lc[pos] >> 18) & m) == :-_)
          pos++
      elsif c == :-0 && (c2 == :-o || c2 == :-O)
        pos += 2
        while pos < count && ((((lc[pos] >> 18) & m) >= 48 && ((lc[pos] >> 18) & m) <= 55) || ((lc[pos] >> 18) & m) == :-_)
          pos++
      else
        pos++
        while pos < count && ((lc[pos] & 0x01) != 0 || ((lc[pos] >> 18) & m) == :-_)
          pos++
      if pos < count && ((lc[pos] >> 18) & m) == :-.
        pos++
        while pos < count && ((lc[pos] & 0x01) != 0 || ((lc[pos] >> 18) & m) == :-_)
          pos++
      c2 = pos < count ? ((lc[pos] >> 18) & m) : 0
      if c2 == :-e || c2 == :-E
        pos++
        c2 = pos < count ? ((lc[pos] >> 18) & m) : 0
        pos++ if c2 == :-+ || c2 == :--
        while pos < count && ((lc[pos] & 0x01) != 0 || ((lc[pos] >> 18) & m) == :-_)
          pos++
      if pos < count && ((lc[pos] >> 18) & m) == :-n
        pos++
        is_big = 1
      tt = is_big != 0 ? 3 : 2
      tokens[tc] = tag | (tt << 38) | (jt_clen(pos - start) << 26) | (start << 2) | nl
      tc++; prev_tt = tt; nl = 0
    else
      pos++

  tokens[tc] = tag | (0 << 38) | (pos << 2) | nl
  tc + 1
