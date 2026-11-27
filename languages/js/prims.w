# runtime/prims — raw NaN-box primitives for compiled JavaScript.
#
# Each fn takes and returns raw i64 WValue bits: callers convert with
# `wvalue_bits(v) ## i64` and `wvalue_from_bits(b)`. The bodies are LLVM IR, so clang
# inlines them into the compiled JS and a number test is one subtract and compare.
#
# Encoding (runtime/wvalue.h): nil 0, false 1, true 2; doubles are the IEEE bits plus
# 2^48 and fill [2^48, 0xFFF1 << 48]; an object instance is a 16-byte aligned pointer
# with sub-tag 4 in the low nibble and zero top bits; an Array is tag 0xFFF4 with the
# pointer in bits 4-46; strings are tag 0xFFF9 with bit 0 clear.
#
# Never pass a heap value through these to *store* it: the compiler's escape analysis
# does not see a pointer that travels as bits, and would free it. Loads and tests only.

in JS

# 1 when a is a number (a biased double).
fn jsr_num(a) (i64) i64
  ll <<~IR
    %x = sub i64 %a, 281474976710656
    %c = icmp ult i64 %x, u0xFFF0000000000001
    %r = zext i1 %c to i64
    ret i64 %r
  IR

# 1 when both a and b are numbers.
fn jsr_nn(a, b) (i64 i64) i64
  ll <<~IR
    %x = sub i64 %a, 281474976710656
    %y = sub i64 %b, 281474976710656
    %cx = icmp ult i64 %x, u0xFFF0000000000001
    %cy = icmp ult i64 %y, u0xFFF0000000000001
    %c = and i1 %cx, %cy
    %r = zext i1 %c to i64
    ret i64 %r
  IR

# Arithmetic on two numbers; NaN results are canonicalized before boxing.
fn jsr_fadd(a, b) (i64 i64) i64
  ll <<~IR
    %x = sub i64 %a, 281474976710656
    %y = sub i64 %b, 281474976710656
    %dx = bitcast i64 %x to double
    %dy = bitcast i64 %y to double
    %s = fadd double %dx, %dy
    %n = fcmp uno double %s, %s
    %s2 = select i1 %n, double 0x7FF8000000000000, double %s
    %si = bitcast double %s2 to i64
    %r = add i64 %si, 281474976710656
    ret i64 %r
  IR

fn jsr_fsub(a, b) (i64 i64) i64
  ll <<~IR
    %x = sub i64 %a, 281474976710656
    %y = sub i64 %b, 281474976710656
    %dx = bitcast i64 %x to double
    %dy = bitcast i64 %y to double
    %s = fsub double %dx, %dy
    %n = fcmp uno double %s, %s
    %s2 = select i1 %n, double 0x7FF8000000000000, double %s
    %si = bitcast double %s2 to i64
    %r = add i64 %si, 281474976710656
    ret i64 %r
  IR

fn jsr_fmul(a, b) (i64 i64) i64
  ll <<~IR
    %x = sub i64 %a, 281474976710656
    %y = sub i64 %b, 281474976710656
    %dx = bitcast i64 %x to double
    %dy = bitcast i64 %y to double
    %s = fmul double %dx, %dy
    %n = fcmp uno double %s, %s
    %s2 = select i1 %n, double 0x7FF8000000000000, double %s
    %si = bitcast double %s2 to i64
    %r = add i64 %si, 281474976710656
    ret i64 %r
  IR

fn jsr_fdiv(a, b) (i64 i64) i64
  ll <<~IR
    %x = sub i64 %a, 281474976710656
    %y = sub i64 %b, 281474976710656
    %dx = bitcast i64 %x to double
    %dy = bitcast i64 %y to double
    %s = fdiv double %dx, %dy
    %n = fcmp uno double %s, %s
    %s2 = select i1 %n, double 0x7FF8000000000000, double %s
    %si = bitcast double %s2 to i64
    %r = add i64 %si, 281474976710656
    ret i64 %r
  IR

# JS % is C fmod (truncating, the sign of the dividend).
fn jsr_fmod(a, b) (i64 i64) i64
  ll <<~IR
    %x = sub i64 %a, 281474976710656
    %y = sub i64 %b, 281474976710656
    %dx = bitcast i64 %x to double
    %dy = bitcast i64 %y to double
    %s = frem double %dx, %dy
    %n = fcmp uno double %s, %s
    %s2 = select i1 %n, double 0x7FF8000000000000, double %s
    %si = bitcast double %s2 to i64
    %r = add i64 %si, 281474976710656
    ret i64 %r
  IR

fn jsr_fneg(a) (i64) i64
  ll <<~IR
    %x = sub i64 %a, 281474976710656
    %dx = bitcast i64 %x to double
    %s = fneg double %dx
    %si = bitcast double %s to i64
    %nan = fcmp uno double %s, %s
    %sc = select i1 %nan, i64 9221120237041090560, i64 %si
    %r = add i64 %sc, 281474976710656
    ret i64 %r
  IR

# Comparisons of two numbers: the bits of true (2) or false (1). NaN compares false.
fn jsr_flt(a, b) (i64 i64) i64
  ll <<~IR
    %x = sub i64 %a, 281474976710656
    %y = sub i64 %b, 281474976710656
    %dx = bitcast i64 %x to double
    %dy = bitcast i64 %y to double
    %c = fcmp olt double %dx, %dy
    %r = select i1 %c, i64 2, i64 1
    ret i64 %r
  IR

fn jsr_fle(a, b) (i64 i64) i64
  ll <<~IR
    %x = sub i64 %a, 281474976710656
    %y = sub i64 %b, 281474976710656
    %dx = bitcast i64 %x to double
    %dy = bitcast i64 %y to double
    %c = fcmp ole double %dx, %dy
    %r = select i1 %c, i64 2, i64 1
    ret i64 %r
  IR

fn jsr_feq(a, b) (i64 i64) i64
  ll <<~IR
    %x = sub i64 %a, 281474976710656
    %y = sub i64 %b, 281474976710656
    %dx = bitcast i64 %x to double
    %dy = bitcast i64 %y to double
    %c = fcmp oeq double %dx, %dy
    %r = select i1 %c, i64 2, i64 1
    ret i64 %r
  IR

# Sentinels returned by the fns below. Both are small enough to be immediate Ints, so
# untyped code can compare against them without boxing: JSR_SLOW is a reserved WValue
# bit pattern (never a JS value), JSR_NOI32 lies outside the int32 range.
JSR_SLOW = 6
JSR_NOI32 = 1099511627776

# ToInt32 of a number, sign-extended, when |x| < 2^63 (exact truncation, then wrap);
# JSR_NOI32 otherwise (NaN, infinities, huge values take the generic path).

fn jsr_i32(a) (i64) i64
  ll <<~IR
    %x = sub i64 %a, 281474976710656
    %d = bitcast i64 %x to double
    %xa = and i64 %x, 9223372036854775807
    %ab = bitcast i64 %xa to double
    %ok = fcmp olt double %ab, 0x43E0000000000000
    %t = fptosi double %d to i64
    %l = shl i64 %t, 32
    %w = ashr i64 %l, 32
    %r = select i1 %ok, i64 %w, i64 1099511627776
    ret i64 %r
  IR

# ToUint32 under the same rule (zero-extended), or JSR_NOI32.
fn jsr_u32(a) (i64) i64
  ll <<~IR
    %x = sub i64 %a, 281474976710656
    %d = bitcast i64 %x to double
    %xa = and i64 %x, 9223372036854775807
    %ab = bitcast i64 %xa to double
    %ok = fcmp olt double %ab, 0x43E0000000000000
    %t = fptosi double %d to i64
    %w = and i64 %t, 4294967295
    %r = select i1 %ok, i64 %w, i64 1099511627776
    ret i64 %r
  IR

# A machine integer as a number.
fn jsr_box_int(i) (i64) i64
  ll <<~IR
    %d = sitofp i64 %i to double
    %b = bitcast double %d to i64
    %r = add i64 %b, 281474976710656
    ret i64 %r
  IR

# A number that is a non-negative integer below 2^31, as that integer; -1 otherwise
# (array indices on the fast path).
fn jsr_index(a) (i64) i64
  ll <<~IR
    %x = sub i64 %a, 281474976710656
    %isn = icmp ult i64 %x, u0xFFF0000000000001
    %d = bitcast i64 %x to double
    %ge = fcmp oge double %d, 0.0
    %lt = fcmp olt double %d, 2147483648.0
    %r1 = and i1 %ge, %lt
    %ok0 = and i1 %isn, %r1
    %t = fptosi double %d to i64
    %back = sitofp i64 %t to double
    %ex = fcmp oeq double %back, %d
    %ok = and i1 %ok0, %ex
    %r = select i1 %ok, i64 %t, i64 -1
    ret i64 %r
  IR

# ---- heap objects ----

# 1 when v is a Tungsten object instance (JS objects are).
fn jsr_inst(v) (i64) i64
  ll <<~IR
    %lo = and i64 %v, u0xFFFF00000000000F
    %c1 = icmp eq i64 %lo, 4
    %c2 = icmp uge i64 %v, 16
    %c = and i1 %c1, %c2
    %r = zext i1 %c to i64
    ret i64 %r
  IR

# The shape of a JS object (ivar 0), or 0 when v is not an instance. Every JS object
# class keeps @shape first; other instances never hold a JS:Shape there, so comparing
# the result with a cached shape is a complete type and layout check.
fn jsr_shape(v) (i64) i64
  ll <<~IR
    %lo = and i64 %v, u0xFFFF00000000000F
    %c1 = icmp eq i64 %lo, 4
    %c2 = icmp uge i64 %v, 16
    %c = and i1 %c1, %c2
    br i1 %c, label %yes, label %no
  yes:
    %p = and i64 %v, 140737488355312
    %q = inttoptr i64 %p to ptr
    %a = getelementptr i8, ptr %q, i64 8
    %s = load i64, ptr %a, align 8
    ret i64 %s
  no:
    ret i64 0
  IR

# Instance ivar i (the caller has checked the class or the shape).
fn jsr_ivar(v, i) (i64 i64) i64
  ll <<~IR
    %p = and i64 %v, 140737488355312
    %q = inttoptr i64 %p to ptr
    %o = shl i64 %i, 3
    %o2 = add i64 %o, 8
    %a = getelementptr i8, ptr %q, i64 %o2
    %s = load i64, ptr %a, align 8
    ret i64 %s
  IR

# The JS kind byte in the instance header's spare word (0 for anything that is not a
# JS object). Set once at construction by js_set_kind.
fn jsr_kind(v) (i64) i64
  ll <<~IR
    %lo = and i64 %v, u0xFFFF00000000000F
    %c1 = icmp eq i64 %lo, 4
    %c2 = icmp uge i64 %v, 16
    %c = and i1 %c1, %c2
    br i1 %c, label %yes, label %no
  yes:
    %p = and i64 %v, 140737488355312
    %q = inttoptr i64 %p to ptr
    %a = getelementptr i8, ptr %q, i64 4
    %k = load i8, ptr %a, align 4
    %r = zext i8 %k to i64
    ret i64 %r
  no:
    ret i64 0
  IR

fn jsr_set_kind(v, k) (i64 i64) i64
  ll <<~IR
    %p = and i64 %v, 140737488355312
    %q = inttoptr i64 %p to ptr
    %a = getelementptr i8, ptr %q, i64 4
    %b = trunc i64 %k to i8
    store i8 %b, ptr %a, align 4
    ret i64 0
  IR

# Store a shape (a long-lived object the shape tree keeps alive) into ivar 0.
fn jsr_set_shape(v, s) (i64 i64) i64
  ll <<~IR
    %p = and i64 %v, 140737488355312
    %q = inttoptr i64 %p to ptr
    %a = getelementptr i8, ptr %q, i64 8
    store i64 %s, ptr %a, align 8
    ret i64 0
  IR

# ---- arrays (core WArrays marked as JS arrays in the spare header byte) ----

# The JS array flags byte (WArray._pad[0]) when v is an Array, else 0.
fn jsr_aflags(v) (i64) i64
  ll <<~IR
    %t = and i64 %v, u0xFFFF000000000000
    %c = icmp eq i64 %t, u0xFFF4000000000000
    br i1 %c, label %yes, label %no
  yes:
    %p = and i64 %v, 140737488355312
    %q = inttoptr i64 %p to ptr
    %a = getelementptr i8, ptr %q, i64 2
    %k = load i8, ptr %a, align 2
    %r = zext i8 %k to i64
    ret i64 %r
  no:
    ret i64 0
  IR

fn jsr_set_aflags(v, f) (i64 i64) i64
  ll <<~IR
    %p = and i64 %v, 140737488355312
    %q = inttoptr i64 %p to ptr
    %a = getelementptr i8, ptr %q, i64 2
    %b = trunc i64 %f to i8
    store i8 %b, ptr %a, align 2
    ret i64 0
  IR

# Element i of a polymorphic Array when 0 <= i < size, else JSR_SLOW.
fn jsr_aget(v, i) (i64 i64) i64
  ll <<~IR
    %p = and i64 %v, 140737488355312
    %q = inttoptr i64 %p to ptr
    %sp = getelementptr i8, ptr %q, i64 8
    %size32 = load i32, ptr %sp, align 4
    %size = sext i32 %size32 to i64
    %in = icmp ult i64 %i, %size
    br i1 %in, label %ok, label %out
  ok:
    %stp = getelementptr i8, ptr %q, i64 4
    %st32 = load i32, ptr %stp, align 4
    %st = sext i32 %st32 to i64
    %slp = getelementptr i8, ptr %q, i64 16
    %sl = load ptr, ptr %slp, align 8
    %ix = add i64 %st, %i
    %ep = getelementptr i64, ptr %sl, i64 %ix
    %e = load i64, ptr %ep, align 8
    ret i64 %e
  out:
    ret i64 6
  IR

fn jsr_asize(v) (i64) i64
  ll <<~IR
    %p = and i64 %v, 140737488355312
    %q = inttoptr i64 %p to ptr
    %sp = getelementptr i8, ptr %q, i64 8
    %size32 = load i32, ptr %sp, align 4
    %size = sext i32 %size32 to i64
    ret i64 %size
  IR

# 1 when v is a string (not a symbol): a tagged string, or a rope (a core string built
# by concatenation: a generic heap object whose type byte is W_TYPE_ROPE, 9).
fn jsr_str(v) (i64) i64
  ll <<~IR
    %t = and i64 %v, u0xFFFF000000000001
    %c = icmp eq i64 %t, u0xFFF9000000000000
    br i1 %c, label %yes, label %rope
  rope:
    %lo = and i64 %v, u0xFFFF00000000000F
    %g = icmp eq i64 %lo, 0
    %big = icmp uge i64 %v, 16
    %h = and i1 %g, %big
    br i1 %h, label %hdr, label %no
  hdr:
    %q = inttoptr i64 %v to ptr
    %ty = load i8, ptr %q, align 8
    %isr = icmp eq i8 %ty, 9
    %r = zext i1 %isr to i64
    ret i64 %r
  yes:
    ret i64 1
  no:
    ret i64 0
  IR

# Immediate 8-byte WValue DOM handle using free top-level tag slot 0xFFF5:
#   bits 63..48 = 0xFFF5 (DOM handle tag — not a double, string, array, or heap ptr)
#   bits 47..32 = doc_id:16  (up to 65,536 live arenas/documents)
#   bits 31..0  = node_id:32 (up to 4B nodes per arena)
fn jsr_is_dom(v) (i64) i64
  ll <<~IR
    %t = and i64 %v, u0xFFFF000000000000
    %c = icmp eq i64 %t, u0xFFF5000000000000
    %r = zext i1 %c to i64
    ret i64 %r
  IR

fn jsr_pack_dom(doc_id, node_id) (i64 i64) i64
  ll <<~IR
    %d = and i64 %doc_id, 65535
    %ds = shl i64 %d, 32
    %n = and i64 %node_id, 4294967295
    %p = or i64 %ds, %n
    %r = or i64 %p, u0xFFF5000000000000
    ret i64 %r
  IR

fn jsr_dom_doc(v) (i64) i64
  ll <<~IR
    %s = lshr i64 %v, 32
    %r = and i64 %s, 65535
    ret i64 %r
  IR

fn jsr_dom_node(v) (i64) i64
  ll <<~IR
    %r = and i64 %v, 4294967295
    ret i64 %r
  IR
