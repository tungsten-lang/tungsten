# cinder/ll_parser — Streaming Zero-Split LLVM IR (.ll) Parser & Data Section Builder.
#
# Designed to parse 575,000+ line / 25 MB Tungsten `.ll` modules in < 0.5s:
#   - Uses raw C byte pointers (`ll <<~IR` loops) to scan lines, decode `c"...\00"`
#     static string slabs, and emit multi-thousand-row compact integer/pointer tables
#     without splitting strings or allocating per-token Arrays.
#   - Performs linear-scan intra-block stack slot reuse so even 15,000-line functions
#     keep compact L1-hot stack frames (~2-6 KB instead of 100+ KB).

use ./buf
use ./macho64
use ./elf64

# ---- Fast C-level byte scanning & parsing primitives ----

fn ll_find_nl(ptr, pos, limit) (i64 i64 i64) i64
  ll <<~IR
    %base = inttoptr i64 %ptr to ptr
    br label %loop
  loop:
    %i = phi i64 [ %pos, %0 ], [ %ni, %step ]
    %cmp = icmp slt i64 %i, %limit
    br i1 %cmp, label %body, label %done
  body:
    %p = getelementptr i8, ptr %base, i64 %i
    %b = load i8, ptr %p, align 1
    %is_nl = icmp eq i8 %b, 10
    br i1 %is_nl, label %done, label %step
  step:
    %ni = add i64 %i, 1
    br label %loop
  done:
    ret i64 %i
  IR

# Find end of function body `\n}` starting from `pos` in < 1 us per function!
fn ll_find_fn_end(ptr, pos, limit) (i64 i64 i64) i64
  ll <<~IR
    %base = inttoptr i64 %ptr to ptr
    %lim1 = sub i64 %limit, 1
    br label %loop
  loop:
    %i = phi i64 [ %pos, %0 ], [ %ni, %step ]
    %cmp = icmp slt i64 %i, %lim1
    br i1 %cmp, label %body, label %done
  body:
    %p = getelementptr i8, ptr %base, i64 %i
    %b0 = load i8, ptr %p, align 1
    %is_nl = icmp eq i8 %b0, 10
    br i1 %is_nl, label %chk_brace, label %step
  chk_brace:
    %i1 = add i64 %i, 1
    %p1 = getelementptr i8, ptr %base, i64 %i1
    %b1 = load i8, ptr %p1, align 1
    %is_br = icmp eq i8 %b1, 125
    br i1 %is_br, label %found, label %step
  found:
    %i2 = add i64 %i, 2
    ret i64 %i2
  step:
    %ni = add i64 %i, 1
    br label %loop
  done:
    ret i64 %limit
  IR

# Decode LLVM `c"..."` escaped byte literal starting just after `c"` at `pos`, writing directly
# into `dst_ptr` (up to `max_out` bytes). Returns number of decoded bytes written!
fn ll_decode_cbytes(dst_ptr, src_ptr, pos, limit) (i64 i64 i64 i64) i64
  ll <<~IR
    %dst = inttoptr i64 %dst_ptr to ptr
    %src = inttoptr i64 %src_ptr to ptr
    br label %loop
  loop:
    %si = phi i64 [ %pos, %0 ], [ %nsi, %cont ]
    %di = phi i64 [ 0, %0 ], [ %ndi, %cont ]
    %ok = icmp slt i64 %si, %limit
    br i1 %ok, label %body, label %done
  body:
    %sp = getelementptr i8, ptr %src, i64 %si
    %ch = load i8, ptr %sp, align 1
    %is_q = icmp eq i8 %ch, 34
    br i1 %is_q, label %done, label %chk_esc
  chk_esc:
    %is_bs = icmp eq i8 %ch, 92
    br i1 %is_bs, label %esc, label %plain
  plain:
    %dp0 = getelementptr i8, ptr %dst, i64 %di
    store i8 %ch, ptr %dp0, align 1
    %si_p = add i64 %si, 1
    %di_p = add i64 %di, 1
    br label %cont
  esc:
    %si1 = add i64 %si, 1
    %sp1 = getelementptr i8, ptr %src, i64 %si1
    %c1 = load i8, ptr %sp1, align 1
    %is_bs2 = icmp eq i8 %c1, 92
    br i1 %is_bs2, label %esc_bs, label %esc_hex
  esc_bs:
    %dp1 = getelementptr i8, ptr %dst, i64 %di
    store i8 92, ptr %dp1, align 1
    %si_b = add i64 %si, 2
    %di_b = add i64 %di, 1
    br label %cont
  esc_hex:
    %si2 = add i64 %si, 2
    %sp2 = getelementptr i8, ptr %src, i64 %si2
    %c2 = load i8, ptr %sp2, align 1
    %z1 = zext i8 %c1 to i64
    %z2 = zext i8 %c2 to i64
    %d1a = sub i64 %z1, 48
    %is_af1 = icmp sge i64 %z1, 97
    %d1b = sub i64 %z1, 87
    %is_AF1 = icmp sge i64 %z1, 65
    %d1c = sub i64 %z1, 55
    %h1_u = select i1 %is_AF1, i64 %d1c, i64 %d1a
    %h1 = select i1 %is_af1, i64 %d1b, i64 %h1_u
    %d2a = sub i64 %z2, 48
    %is_af2 = icmp sge i64 %z2, 97
    %d2b = sub i64 %z2, 87
    %is_AF2 = icmp sge i64 %z2, 65
    %d2c = sub i64 %z2, 55
    %h2_u = select i1 %is_AF2, i64 %d2c, i64 %d2a
    %h2 = select i1 %is_af2, i64 %d2b, i64 %h2_u
    %sh = shl i64 %h1, 4
    %bv64 = or i64 %sh, %h2
    %bv8 = trunc i64 %bv64 to i8
    %dp2 = getelementptr i8, ptr %dst, i64 %di
    store i8 %bv8, ptr %dp2, align 1
    %si_h = add i64 %si, 3
    %di_h = add i64 %di, 1
    br label %cont
  cont:
    %nsi = phi i64 [ %si_p, %plain ], [ %si_b, %esc_bs ], [ %si_h, %esc_hex ]
    %ndi = phi i64 [ %di_p, %plain ], [ %di_b, %esc_bs ], [ %di_h, %esc_hex ]
    br label %loop
  done:
    ret i64 %di
  IR

# Parse a full-width 64-bit integer (`u0x...`, `0x...`, `-123`, `456`, `true`/`false`/`null`/`zeroinitializer`)
# directly at byte level without 48-bit Fixnum overflow!
fn ll_parse_i64_raw(src_ptr, pos, len) (i64 i64 i64) i64
  ll <<~IR
    %src = inttoptr i64 %src_ptr to ptr
    %end = add i64 %pos, %len
    %empty = icmp sle i64 %len, 0
    br i1 %empty, label %ret_zero, label %chk0
  chk0:
    %p0 = getelementptr i8, ptr %src, i64 %pos
    %b0 = load i8, ptr %p0, align 1
    ; 't' (true) -> 1
    %is_t = icmp eq i8 %b0, 116
    br i1 %is_t, label %ret_one, label %chk_fzn
  chk_fzn:
    ; 'f' (false), 'n' (null), 'z' (zeroinitializer), 'u' followed by 'n' (undef) -> 0
    %is_f = icmp eq i8 %b0, 102
    %is_n = icmp eq i8 %b0, 110
    %is_z = icmp eq i8 %b0, 122
    %fn1 = or i1 %is_f, %is_n
    %fnz = or i1 %fn1, %is_z
    br i1 %fnz, label %ret_zero, label %chk_u0x
  chk_u0x:
    ; Check u0x / s0x prefix (len >= 3, b0=='u'||'s', b1=='0', b2=='x')
    %ge3 = icmp sge i64 %len, 3
    br i1 %ge3, label %chk_u0x_2, label %chk_0x
  chk_u0x_2:
    %is_u = icmp eq i8 %b0, 117
    %is_s = icmp eq i8 %b0, 115
    %us = or i1 %is_u, %is_s
    %pos1 = add i64 %pos, 1
    %p1 = getelementptr i8, ptr %src, i64 %pos1
    %b1 = load i8, ptr %p1, align 1
    %is_0 = icmp eq i8 %b1, 48
    %us0 = and i1 %us, %is_0
    br i1 %us0, label %hex_from_3, label %chk_0x
  hex_from_3:
    %hstart3 = add i64 %pos, 3
    br label %hex_loop
  chk_0x:
    %ge2 = icmp sge i64 %len, 2
    br i1 %ge2, label %chk_0x_2, label %chk_sign
  chk_0x_2:
    %z0 = icmp eq i8 %b0, 48
    %pos1b = add i64 %pos, 1
    %p1b = getelementptr i8, ptr %src, i64 %pos1b
    %b1b = load i8, ptr %p1b, align 1
    %x1 = icmp eq i8 %b1b, 120
    %zx = and i1 %z0, %x1
    br i1 %zx, label %hex_from_2, label %chk_sign
  hex_from_2:
    %hstart2 = add i64 %pos, 2
    br label %hex_loop
  hex_loop:
    %hi = phi i64 [ %hstart3, %hex_from_3 ], [ %hstart2, %hex_from_2 ], [ %nhi, %hex_step ]
    %hacc = phi i64 [ 0, %hex_from_3 ], [ 0, %hex_from_2 ], [ %nhacc, %hex_step ]
    %hmore = icmp slt i64 %hi, %end
    br i1 %hmore, label %hex_body, label %hex_done
  hex_body:
    %hp = getelementptr i8, ptr %src, i64 %hi
    %hb = load i8, ptr %hp, align 1
    %hz = zext i8 %hb to i64
    %is_d = icmp sle i64 %hz, 57
    %dd = sub i64 %hz, 48
    %is_lo = icmp sge i64 %hz, 97
    %dlo = sub i64 %hz, 87
    %dup = sub i64 %hz, 55
    %d_af = select i1 %is_lo, i64 %dlo, i64 %dup
    %dig = select i1 %is_d, i64 %dd, i64 %d_af
    %valid = icmp sge i64 %hz, 48
    br i1 %valid, label %hex_step, label %hex_done
  hex_step:
    %sh4 = shl i64 %hacc, 4
    %nhacc = or i64 %sh4, %dig
    %nhi = add i64 %hi, 1
    br label %hex_loop
  hex_done:
    ret i64 %hacc
  chk_sign:
    %is_neg = icmp eq i8 %b0, 45
    %dstart = select i1 %is_neg, i64 1, i64 0
    %di0 = add i64 %pos, %dstart
    br label %dec_loop
  dec_loop:
    %di = phi i64 [ %di0, %chk_sign ], [ %ndi, %dec_step ]
    %dacc = phi i64 [ 0, %chk_sign ], [ %ndacc, %dec_step ]
    %dmore = icmp slt i64 %di, %end
    br i1 %dmore, label %dec_body, label %dec_done
  dec_body:
    %dp = getelementptr i8, ptr %src, i64 %di
    %db = load i8, ptr %dp, align 1
    %ge0 = icmp sge i8 %db, 48
    %le9 = icmp sle i8 %db, 57
    %is_dig = and i1 %ge0, %le9
    br i1 %is_dig, label %dec_step, label %dec_done
  dec_step:
    %dz = zext i8 %db to i64
    %dv = sub i64 %dz, 48
    %m10 = mul i64 %dacc, 10
    %ndacc = add i64 %m10, %dv
    %ndi = add i64 %di, 1
    br label %dec_loop
  dec_done:
    %neg_v = sub i64 0, %dacc
    %res = select i1 %is_neg, i64 %neg_v, i64 %dacc
    ret i64 %res
  ret_one:
    ret i64 1
  ret_zero:
    ret i64 0
  IR

# Scan all `i32 <signed_dec>` tokens in `[pos, end)` and append 4-byte LE words directly into `dst_buf`!
# Used for `@__w_fn_sym_compact` and `@__w_ic_site_sparse` (~25,000 rows in < 2 ms!).
fn ll_emit_i32_table_raw(dst_ptr, src_ptr, pos, limit) (i64 i64 i64 i64) i64
  ll <<~IR
    %dst = inttoptr i64 %dst_ptr to ptr
    %src = inttoptr i64 %src_ptr to ptr
    %lim4 = sub i64 %limit, 4
    br label %scan
  scan:
    %i = phi i64 [ %pos, %0 ], [ %ni_skip, %skip ], [ %di_end, %emit_word ]
    %out_n = phi i64 [ 0, %0 ], [ %out_n, %skip ], [ %nout_n, %emit_word ]
    %more = icmp slt i64 %i, %lim4
    br i1 %more, label %chk_i, label %done
  chk_i:
    %p0 = getelementptr i8, ptr %src, i64 %i
    %b0 = load i8, ptr %p0, align 1
    %is_i = icmp eq i8 %b0, 105
    br i1 %is_i, label %chk_32, label %skip
  chk_32:
    %i1 = add i64 %i, 1
    %p1 = getelementptr i8, ptr %src, i64 %i1
    %b1 = load i8, ptr %p1, align 1
    %is_3 = icmp eq i8 %b1, 51
    %i2 = add i64 %i, 2
    %p2 = getelementptr i8, ptr %src, i64 %i2
    %b2 = load i8, ptr %p2, align 1
    %is_2 = icmp eq i8 %b2, 50
    %i3 = add i64 %i, 3
    %p3 = getelementptr i8, ptr %src, i64 %i3
    %b3 = load i8, ptr %p3, align 1
    %is_sp = icmp eq i8 %b3, 32
    %m12 = and i1 %is_3, %is_2
    %m123 = and i1 %m12, %is_sp
    br i1 %m123, label %parse_num, label %skip
  parse_num:
    %ns0 = add i64 %i, 4
    %pn0 = getelementptr i8, ptr %src, i64 %ns0
    %bn0 = load i8, ptr %pn0, align 1
    %neg = icmp eq i8 %bn0, 45
    %off_s = select i1 %neg, i64 5, i64 4
    %ns1 = add i64 %i, %off_s
    %pn1 = getelementptr i8, ptr %src, i64 %ns1
    %bn1 = load i8, ptr %pn1, align 1
    %ge0_first = icmp sge i8 %bn1, 48
    %le9_first = icmp sle i8 %bn1, 57
    %ok_first = and i1 %ge0_first, %le9_first
    br i1 %ok_first, label %dloop, label %skip
  dloop:
    %di = phi i64 [ %ns1, %parse_num ], [ %ndi, %dstep ]
    %acc = phi i64 [ 0, %parse_num ], [ %nacc, %dstep ]
    %dmore = icmp slt i64 %di, %limit
    br i1 %dmore, label %dbody, label %emit_word
  dbody:
    %pd = getelementptr i8, ptr %src, i64 %di
    %bd = load i8, ptr %pd, align 1
    %g0 = icmp sge i8 %bd, 48
    %l9 = icmp sle i8 %bd, 57
    %dig_ok = and i1 %g0, %l9
    br i1 %dig_ok, label %dstep, label %emit_word
  dstep:
    %dz = zext i8 %bd to i64
    %dv = sub i64 %dz, 48
    %m10 = mul i64 %acc, 10
    %nacc = add i64 %m10, %dv
    %ndi = add i64 %di, 1
    br label %dloop
  emit_word:
    %di_end = phi i64 [ %di, %dloop ], [ %di, %dbody ]
    %neg_acc = sub i64 0, %acc
    %fval = select i1 %neg, i64 %neg_acc, i64 %acc
    %val32 = trunc i64 %fval to i32
    %byte_off = shl i64 %out_n, 2
    %out_p = getelementptr i8, ptr %dst, i64 %byte_off
    store i32 %val32, ptr %out_p, align 1
    %nout_n = add i64 %out_n, 1
    br label %scan
  skip:
    %ni_skip = add i64 %i, 1
    br label %scan
  done:
    ret i64 %out_n
  IR

LL_SHORT_STR_BUF = u8[64]

-> ll_parse_i64(s)
  t = s.strip()
  n = cinder_blen(t)
  return 0 if n == 0
  if n > 16
    p = cinder_heap_str_ptr(wvalue_bits(t) ## i64)
    return ll_parse_i64_raw(p, 0, n)
  i = 0
  while i < n
    LL_SHORT_STR_BUF[i] = (t.byte_at(i) & 0xFF) ## u8
    i += 1
  bp = cinder_raw_u8_ptr(wvalue_bits(LL_SHORT_STR_BUF) ## i64)
  ll_parse_i64_raw(bp, 0, n)

-> ll_parse_f64_bits(s)
  t = s.strip()
  if t.starts_with?("0x") || t.starts_with?("u0x")
    return ll_parse_i64(t)
  fv = t.to_f()
  (wvalue_bits(fv) ## i64) - 281474976710656

# Scan `s` from byte `start_pos` for `target_byte` outside `"..."` quotes (returns byte index or -1).
# Note: in LLVM IR, literal quotes inside strings/identifiers are always hex-escaped `\22` (never `\"`).
-> ll_index_outside_quotes(s, target_byte, start_pos = 0)
  n = cinder_blen(s)
  in_q = false
  i = 0
  while i < n
    b = s.byte_at(i)
    if b == 34
      in_q = !in_q
    elsif !in_q && i >= start_pos && b == target_byte
      return i
    i += 1
  -1

# Strip trailing `; comment` and trailing `, !metadata` attachments (`!range`, `!tbaa`, `!llvm.loop`, `!prof`, etc.)
# outside `"..."` quotes in a single pass!
-> ll_strip_line_tail(s)
  n = cinder_blen(s)
  in_q = false
  i = 0
  while i < n
    b = s.byte_at(i)
    if b == 34
      in_q = !in_q
    elsif !in_q
      if b == 59
        return s.slice(0, i).strip()
      if b == 44 && i + 2 < n && s.byte_at(i + 1) == 32 && s.byte_at(i + 2) == 33
        return s.slice(0, i).strip()
    i += 1
  s

# Find matching `)` for `(` at `lp_pos`, ignoring parentheses inside `"..."` quotes.
-> ll_matching_rparen(s, lp_pos)
  n = cinder_blen(s)
  in_q = false
  depth = 0
  i = lp_pos
  while i < n
    b = s.byte_at(i)
    if b == 34
      in_q = !in_q
    elsif !in_q
      if b == 40
        depth += 1
      elsif b == 41
        depth -= 1
        return i if depth == 0
    i += 1
  n - 1

# Unquote `@"w:foo"` -> `w:foo`, or strip leading `@` / `%`
-> ll_clean_sym(tok)
  t = tok.strip()
  t = t.slice(1, cinder_blen(t) - 1) if t.starts_with?("@") || t.starts_with?("%")
  if t.starts_with?("\"") && t.ends_with?("\"") && cinder_blen(t) >= 2
    inner = t.slice(1, cinder_blen(t) - 2)
    if inner.index("\\") != nil
      in_arr = cinder_str_to_cstr_u8(inner)
      in_len = cinder_blen(inner)
      buf = ByteBuf.new(in_len + 4)
      buf.reserve(in_len + 4)
      sp = cinder_raw_u8_ptr(wvalue_bits(in_arr) ## i64)
      n = ll_decode_cbytes(buf.raw_ptr(), sp, 0, in_len)
      sb = StringBuffer(n)
      k = 0
      while k < n
        sb << (buf.data[k] ## i64).chr()
        k += 1
      return sb.to_s()
    return inner
  t

# ---- LLVM Type Size & GEP Byte-Offset Calculator ----

-> ll_split_top_commas(s)
  out = []
  d_br = 0; d_cu = 0; d_pa = 0; d_an = 0; in_q = false
  start = 0
  i = 0
  n = cinder_blen(s)
  while i < n
    b = s.byte_at(i)
    if b == 34
      in_q = !in_q
    elsif !in_q
      if b == 91
        d_br += 1
      elsif b == 93
        d_br -= 1
      elsif b == 123
        d_cu += 1
      elsif b == 125
        d_cu -= 1
      elsif b == 40
        d_pa += 1
      elsif b == 41
        d_pa -= 1
      elsif b == 60
        d_an += 1
      elsif b == 62
        d_an -= 1
      elsif b == 44 && d_br == 0 && d_cu == 0 && d_pa == 0 && d_an == 0
        out.push(s.slice(start, i - start).strip())
        start = i + 1
    i += 1
  tail = s.slice(start, n - start).strip()
  out.push(tail) if tail != ""
  out

# Returns [byte_size, byte_align] for any LLVM type in Tungsten's IR
-> ll_type_size_align(ty_str)
  t = ty_str.strip()
  return [1, 1]   if t == "i8" || t == "i1"
  return [2, 2]   if t == "i16" || t == "half"
  return [4, 4]   if t == "i32" || t == "float"
  return [8, 8]   if t == "i64" || t == "ptr" || t == "double"
  return [16, 16] if t == "i128" || t == "<2 x i64>"
  if t.starts_with?("\[") && t.ends_with?("]")
    inner = t.slice(1, t.size() - 2).strip()
    xi = inner.index(" x ")
    cnt = inner.slice(0, xi).strip().to_i()
    ety = inner.slice(xi + 3, inner.size() - xi - 3).strip()
    sa = ll_type_size_align(ety)
    return [cnt * sa[0], sa[1]]
  if t.starts_with?("{") && t.ends_with?("}")
    inner = t.slice(1, t.size() - 2).strip()
    return [0, 1] if inner == ""
    fields = ll_split_top_commas(inner)
    off = 0
    max_al = 1
    fi = 0
    while fi < fields.size()
      sa = ll_type_size_align(fields[fi])
      al = sa[1]
      max_al = al if al > max_al
      rem = off & (al - 1)
      off += (al - rem) if rem != 0
      off += sa[0]
      fi += 1
    rem = off & (max_al - 1)
    off += (max_al - rem) if rem != 0
    return [off, max_al]
  [8, 8]

# Compute struct field `[field_byte_offset, field_type_str]` for `{ T0, T1, ... }` at field `idx`
-> ll_struct_field_offset(ty_str, idx)
  inner = ty_str.strip()
  inner = inner.slice(1, inner.size() - 2).strip()
  fields = ll_split_top_commas(inner)
  off = 0
  fi = 0
  while fi <= idx && fi < fields.size()
    ft = fields[fi]
    sa = ll_type_size_align(ft)
    al = sa[1]
    rem = off & (al - 1)
    off += (al - rem) if rem != 0
    return [off, ft] if fi == idx
    off += sa[0]
    fi += 1
  [off, "i8"]

# Type tag integer for fast instruction dispatch
LLTY_VOID = 0
LLTY_I1   = 1
LLTY_I8   = 8
LLTY_I16  = 16
LLTY_I32  = 32
LLTY_I64  = 64
LLTY_PTR  = 65
LLTY_I128 = 128
LLTY_V2I64 = 129
LLTY_F32  = -32
LLTY_F64  = -64
LLTY_OV64 = 66   # `{ i64, i1 }` overflow pair

-> ll_type_tag(ty_str)
  t = ty_str.strip()
  return LLTY_I64   if t == "i64"
  return LLTY_PTR   if t == "ptr"
  return LLTY_I1    if t == "i1"
  return LLTY_I32   if t == "i32"
  return LLTY_I8    if t == "i8"
  return LLTY_I16   if t == "i16"
  return LLTY_VOID  if t == "void"
  return LLTY_F64   if t == "double"
  return LLTY_F32   if t == "float"
  return LLTY_I128  if t == "i128"
  return LLTY_V2I64 if t == "<2 x i64>"
  return LLTY_OV64  if t.starts_with?("{") && t.index("i1") != nil
  LLTY_I64

# Operand kinds
LLOP_NONE = 0
LLOP_VAL  = 1
LLOP_IMM  = 2
LLOP_SYM  = 3

# Symbol classification in module
LLSYM_EXT_FN   = 0
LLSYM_DEF_FN   = 1
LLSYM_DEF_DATA = 2
LLSYM_EXT_DATA = 3
LLSYM_TLS      = 4

+ LLModuleInfo
  rw :sym_list, :sym_to_id, :sym_kind, :aliases, :used_syms, :mod_asm_lines, :fn_spans
  rw :attr_groups, :fn_span_by_sym_id

  -> new
    @sym_list = []
    @sym_to_id = {}
    @sym_kind = []
    @aliases = []        # [[alias_name, target_name], ...]
    @used_syms = []
    @mod_asm_lines = []
    @fn_spans = []       # [[hdr_line_str, body_start_byte, body_end_byte], ...]
    @attr_groups = {}    # "#0" => :always | :never
    @fn_span_by_sym_id = {}

  -> intern_sym(name, kind = -1)
    id = @sym_to_id[name]
    if id == nil
      id = @sym_list.size()
      @sym_list.push(name)
      @sym_kind.push(kind >= 0 ? kind : LLSYM_EXT_FN)
      @sym_to_id[name] = id
    elsif kind >= 0
      @sym_kind[id] = kind
    id

+ LLInst
  rw :op, :dst, :ty, :ty2, :pred
  rw :k0, :v0, :k1, :v1, :k2, :v2
  rw :extra   # nil, or call args [[ty_tag, op_kind, op_val], ...], or GEP steps, or switch cases, or phi pairs, or inline_asm

  -> new(@op, @dst = -1, @ty = 64)
    @ty2 = 64
    @pred = nil
    @k0 = 0; @v0 = 0
    @k1 = 0; @v1 = 0
    @k2 = 0; @v2 = 0
    @extra = nil

  -> clone
    cp = LLInst.new(@op, @dst, @ty)
    cp.ty2 = @ty2
    cp.pred = @pred
    cp.k0 = @k0; cp.v0 = @v0
    cp.k1 = @k1; cp.v1 = @v1
    cp.k2 = @k2; cp.v2 = @v2
    if @extra != nil
      if @op == :call_asm
        na = []
        i = 0
        while i < @extra[1].size()
          e = @extra[1][i]
          na.push([e[0], e[1], e[2]])
          i += 1
        cp.extra = [@extra[0], na]
      elsif @op == :switch
        na = []
        i = 0
        while i < @extra.size()
          e = @extra[i]
          na.push([e[0], e[1]])
          i += 1
        cp.extra = na
      else
        # `:call`, `:intrinsic`, `:gep`, `:phi` all store 3-element arrays `[a, b, c]`
        na = []
        i = 0
        while i < @extra.size()
          e = @extra[i]
          na.push([e[0], e[1], e[2]])
          i += 1
        cp.extra = na
    cp

+ LLBlock
  rw :id, :name, :phis, :insts

  -> new(@id, @name)
    @phis = []    # Array of LLInst (:phi)
    @insts = []   # Array of LLInst

+ LLFunc
  rw :name, :is_internal, :is_preserve_most, :ret_ty, :inline_hint
  rw :param_tys, :n_params
  rw :val_map, :val_tys, :n_vals, :val_uses
  rw :blocks, :blk_map
  rw :uses_ic, :ic_sym_id
  rw :val_slot, :slot_is_fp, :slot_uses, :n_scalar_slots
  rw :alloca_bytes, :frame_slots_bytes, :phi_stage_off

  -> new(@name, @is_internal, @is_preserve_most, @ret_ty, @param_tys)
    @inline_hint = :default
    @n_params = @param_tys.size()
    @val_map = {}
    @val_tys = []
    @n_vals = 0
    @val_uses = nil
    @blocks = []
    @blk_map = {}
    @uses_ic = false
    @ic_sym_id = -1
    @val_slot = nil
    @slot_is_fp = nil
    @slot_uses = nil
    @n_scalar_slots = 0
    @alloca_bytes = 0
    @frame_slots_bytes = 0
    @phi_stage_off = 0

  -> alloc_anon_val(ty = 64)
    id = @n_vals
    @n_vals += 1
    @val_tys.push(ty)
    id

  -> alloc_anon_block
    id = @blocks.size()
    nm = "__inl_" + id.to_s()
    @blocks.push(LLBlock.new(id, nm))
    @blk_map[nm] = id
    id

  -> get_val(nm, ty = 64)
    id = @val_map[nm]
    if id == nil
      id = @n_vals
      @n_vals += 1
      @val_tys.push(ty)
      @val_map[nm] = id
    elsif ty != 64 && @val_tys[id] == 64
      @val_tys[id] = ty
    id

  -> get_block(nm)
    id = @blk_map[nm]
    if id == nil
      id = @blocks.size()
      @blocks.push(LLBlock.new(id, nm))
      @blk_map[nm] = id
    id

# Parse a single value token (`%x`, `@sym`, `42`, `u0x...`, `0.001`, `true`, `null`) -> [LLOP_*, val]
-> ll_parse_operand(fn_ir, mod_info, tok, ty_tag)
  t = tok.strip()
  return [LLOP_VAL, fn_ir.get_val(ll_clean_sym(t), ty_tag)] if t.starts_with?("%")
  if t.starts_with?("@")
    sn = ll_clean_sym(t)
    sid = mod_info.intern_sym(sn)
    if sn == ".ic"
      fn_ir.uses_ic = true
      fn_ir.ic_sym_id = sid
    return [LLOP_SYM, sid]
  if ty_tag == LLTY_F64 || ty_tag == LLTY_F32
    return [LLOP_IMM, ll_parse_f64_bits(t)]
  [LLOP_IMM, ll_parse_i64(t)]

# Parse `ty val` pair like `i64 %a` or `ptr @"w:foo bar"` -> [ty_tag, op_kind, op_val]
-> ll_parse_typed_operand(fn_ir, mod_info, pair_str)
  s = pair_str.strip()
  # Handle `<2 x i64> %v` or `{ i64, i1 } %v` where type contains spaces!
  ty_s = ""
  val_s = ""
  if s.starts_with?("<")
    gt = s.index(">")
    ty_s = s.slice(0, gt + 1)
    val_s = s.slice(gt + 1, cinder_blen(s) - gt - 1).strip()
  elsif s.starts_with?("{")
    rc = s.index("}")
    ty_s = s.slice(0, rc + 1)
    val_s = s.slice(rc + 1, cinder_blen(s) - rc - 1).strip()
  else
    sp0 = s.index(" ")
    if sp0 == nil
      ty_s = s
      val_s = "0"
    else
      ty_s = s.slice(0, sp0)
      at_p = ll_index_outside_quotes(s, 64, sp0)
      pc_p = ll_index_outside_quotes(s, 37, sp0)
      if at_p >= 0
        val_s = s.slice(at_p, cinder_blen(s) - at_p).strip()
      elsif pc_p >= 0
        val_s = s.slice(pc_p, cinder_blen(s) - pc_p).strip()
      else
        parts = s.split(" ")
        val_s = parts[parts.size() - 1]
  tt = ll_type_tag(ty_s)
  op = ll_parse_operand(fn_ir, mod_info, val_s, tt)
  [tt, op[0], op[1]]

# Pass 1: Scan top-level `.ll` module, emit all globals/constants/slabs/tables into `writer`
# (`MachO64Writer` or `Elf64Writer`, selected by `is_macho`), and record function byte spans!
-> ll_scan_module_and_emit_globals(src, writer, is_macho)
  mod = LLModuleInfo.new()
  src = src + "                        " if cinder_blen(src) <= 16
  src_ptr = cinder_heap_str_ptr(wvalue_bits(src) ## i64)
  limit = cinder_blen(src)
  pos = 0

  while pos < limit
    nl = ll_find_nl(src_ptr, pos, limit)
    # Trim trailing \r if any
    line_len = nl - pos
    if line_len > 0 && src.byte_at(nl - 1) == 13
      line_len -= 1
    b0 = line_len > 0 ? src.byte_at(pos) : 0

    # Skip blank lines, comments (`;`), `target ...`, `source_filename ...`, `attributes #...`, `!0 = ...`
    if line_len == 0 || b0 == 59 || b0 == 33
      pos = nl + 1
      next

    line = src.slice(pos, line_len).strip()
    if line == "" || line.starts_with?("target ") || line.starts_with?("source_filename")
      pos = nl + 1
      next

    if line.starts_with?("attributes ")
      # Record `#N` inline hints (`alwaysinline` / `noinline`)
      eq_a = line.index("=")
      if eq_a != nil
        tag = line.slice(11, eq_a - 11).strip()
        if line.index("alwaysinline") != nil
          mod.attr_groups[tag] = :always
        elsif line.index("noinline") != nil
          mod.attr_groups[tag] = :never
      pos = nl + 1
      next

    if line.starts_with?("module asm ")
      q1 = line.index("\"")
      q2 = line.size() - 1
      if q1 != nil && q2 > q1
        mod.mod_asm_lines.push(line.slice(q1 + 1, q2 - q1 - 1))
      pos = nl + 1
      next

    if line.starts_with?("declare ")
      at = ll_index_outside_quotes(line, 64, 0)
      lp = at >= 0 ? ll_index_outside_quotes(line, 40, at) : -1
      if at >= 0 && lp > at
        fn_nm = ll_clean_sym(line.slice(at, lp - at))
        if !fn_nm.starts_with?("llvm.")
          mod.intern_sym(fn_nm, LLSYM_EXT_FN)
      pos = nl + 1
      next

    if line.starts_with?("define ")
      at = ll_index_outside_quotes(line, 64, 0)
      lp = at >= 0 ? ll_index_outside_quotes(line, 40, at) : -1
      fn_nm = ll_clean_sym(line.slice(at, lp - at))
      sid = mod.intern_sym(fn_nm, LLSYM_DEF_FN)
      body_start = nl + 1
      body_end = ll_find_fn_end(src_ptr, pos, limit)
      mod.fn_span_by_sym_id[sid] = mod.fn_spans.size()
      mod.fn_spans.push([line, body_start, body_end])
      pos = body_end
      next

    if line.starts_with?("@")
      eq = ll_index_outside_quotes(line, 61, 0)
      if eq < 0
        pos = nl + 1
        next
      lhs = line.slice(0, eq).strip()
      sym_nm = ll_clean_sym(lhs)
      rhs = line.slice(eq + 1, cinder_blen(line) - eq - 1).strip()

      # Header prefix before any `[` or `"` so string literals like `c"...alias ..."` never match keywords!
      q0_idx = rhs.index("\"")
      br0_idx = rhs.index("\[")
      hdr_lim = cinder_blen(rhs)
      hdr_lim = q0_idx if q0_idx != nil && q0_idx < hdr_lim
      hdr_lim = br0_idx if br0_idx != nil && br0_idx < hdr_lim
      rhs_hdr = rhs.slice(0, hdr_lim)

      # 1. `@llvm.used = appending global [N x ptr] [...]`
      if sym_nm == "llvm.used" || sym_nm == "llvm.compiler.used"
        lb = ll_index_outside_quotes(rhs, 91, 0)
        lb2 = lb >= 0 ? ll_index_outside_quotes(rhs, 91, lb + 1) : -1
        rb2 = lb2 >= 0 ? ll_index_outside_quotes(rhs, 93, lb2 + 1) : -1
        if lb2 >= 0 && rb2 > lb2
          items = ll_split_top_commas(rhs.slice(lb2 + 1, rb2 - lb2 - 1))
          ii = 0
          while ii < items.size()
            at_i = ll_index_outside_quotes(items[ii], 64, 0)
            if at_i >= 0
              unm = ll_clean_sym(items[ii].slice(at_i, cinder_blen(items[ii]) - at_i))
              mod.used_syms.push(unm)
            ii += 1
        pos = nl + 1
        next

      # 2. Hidden alias: `@"w:..." = hidden alias i8, ptr @target`
      al_kw = rhs_hdr.index("alias ")
      if al_kw != nil
        at_t = ll_index_outside_quotes(rhs, 64, al_kw + 6)
        if at_t >= 0
          tgt_nm = ll_clean_sym(rhs.slice(at_t, cinder_blen(rhs) - at_t))
          mod.aliases.push([sym_nm, tgt_nm])
          mod.intern_sym(sym_nm, LLSYM_DEF_FN)
        pos = nl + 1
        next

      # 3. External global: `@g_ast_store = external global ...`
      if rhs_hdr.starts_with?("external ")
        if rhs_hdr.index("thread_local") != nil
          mod.intern_sym(sym_nm, LLSYM_TLS)
        else
          mod.intern_sym(sym_nm, LLSYM_EXT_DATA)
        pos = nl + 1
        next

      is_local = rhs_hdr.starts_with?("private ") || rhs_hdr.starts_with?("internal ")
      m_bind = is_local ? MSYM_LOCAL : MSYM_GLOBAL
      e_bind = is_local ? ESYM_LOCAL : ESYM_GLOBAL

      # 4. Thread-local global (`@.ic`, `@reuse.site.0`)
      if rhs_hdr.index("thread_local ") != nil
        mod.intern_sym(sym_nm, LLSYM_TLS)
        gi = rhs_hdr.index("global ")
        rest_g = rhs.slice(gi + 7, cinder_blen(rhs) - gi - 7).strip()
        ty_end = rest_g.index(" zeroinitializer")
        if ty_end != nil
          ty_s = rest_g.slice(0, ty_end).strip()
          sa = ll_type_size_align(ty_s)
          is_macho ? writer.alloc_tls_bss(sym_nm, sa[0], 8, m_bind) : writer.alloc_tls_bss(sym_nm, sa[0], 8, e_bind)
        else
          is_macho ? writer.alloc_tls_bss(sym_nm, 8, 8, m_bind) : writer.alloc_tls_bss(sym_nm, 8, 8, e_bind)
        pos = nl + 1
        next

      mod.intern_sym(sym_nm, LLSYM_DEF_DATA)
      c_kw = rhs_hdr.index("constant ")
      g_kw = rhs_hdr.index("global ")
      is_const = c_kw != nil
      kw_pos = is_const ? (c_kw + 9) : (g_kw != nil ? (g_kw + 7) : 0)
      spec = rhs.slice(kw_pos, cinder_blen(rhs) - kw_pos).strip()
      target_buf = is_const ? writer.rodata : writer.data

      # Case A: `c"..."` byte array (`[N x i8] c"..."`) — check BEFORE align-stripping so `c"..."` contents are untouched!
      rb_c = spec.index("]")
      if spec.starts_with?("\[") && rb_c != nil && cinder_blen(spec) >= rb_c + 4 && spec.slice(rb_c, 4) == "] c\""
        raw_line_str = src.slice(pos, line_len)
        eq_raw = ll_index_outside_quotes(raw_line_str, 61, 0)
        rc_idx = raw_line_str.index("] c\"", eq_raw >= 0 ? eq_raw : 0)
        c_byte_start = pos + rc_idx + 4
        lb = spec.index("\[")
        xi = spec.index(" x ")
        n_expected = spec.slice(lb + 1, xi - lb - 1).strip().to_i()
        target_buf.align_to(8, 0)
        sec_off = target_buf.len
        target_buf.reserve(n_expected + 8)
        n_dec = ll_decode_cbytes(target_buf.raw_ptr() + sec_off, src_ptr, c_byte_start, pos + line_len)
        target_buf.len = sec_off + n_dec
        if n_dec < n_expected
          target_buf.put_zeros(n_expected - n_dec)
        if is_macho
          writer.define_sym(sym_nm, is_const ? MSEC_CONST : MSEC_DATA, sec_off, m_bind)
        else
          writer.define_sym(sym_nm, is_const ? ESEC_RODATA : ESEC_DATA, sec_off, n_expected, e_bind, ESTT_OBJECT)
        pos = nl + 1
        next

      # Strip trailing `, align N` if NOT multiline (`[` without `]`)
      if !spec.ends_with?("\[")
        # Scan backward for `, align ` outside quotes
        ap = -1
        sc_pos = 0
        while sc_pos >= 0
          cm_i = ll_index_outside_quotes(spec, 44, sc_pos)
          if cm_i < 0
            sc_pos = -1
          else
            if cinder_blen(spec) >= cm_i + 8 && spec.slice(cm_i, 8) == ", align "
              ap = cm_i
            sc_pos = cm_i + 1
        spec = spec.slice(0, ap).strip() if ap >= 0

      # Case B: `zeroinitializer`
      zi_pos = spec.index(" zeroinitializer")
      if zi_pos != nil
        ty_s = spec.slice(0, zi_pos).strip()
        sa = ll_type_size_align(ty_s)
        sz = sa[0] > 0 ? sa[0] : 8
        if !is_const
          is_macho ? writer.alloc_bss(sym_nm, sz, 8, m_bind) : writer.alloc_bss(sym_nm, sz, 8, e_bind)
        else
          target_buf.align_to(8, 0)
          sec_off = target_buf.len
          target_buf.put_zeros(sz)
          if is_macho
            writer.define_sym(sym_nm, MSEC_CONST, sec_off, m_bind)
          else
            writer.define_sym(sym_nm, ESEC_RODATA, sec_off, sz, e_bind, ESTT_OBJECT)
        pos = nl + 1
        next

      # Case C: Scalar `i64 <val>` or `i32 <val>`
      if spec.starts_with?("i64 ")
        val = ll_parse_i64(spec.slice(4, spec.size() - 4))
        if !is_const && val == 0
          is_macho ? writer.alloc_bss(sym_nm, 8, 8, m_bind) : writer.alloc_bss(sym_nm, 8, 8, e_bind)
        else
          target_buf.align_to(8, 0)
          sec_off = target_buf.len
          target_buf.put_u64_le(val)
          if is_macho
            writer.define_sym(sym_nm, is_const ? MSEC_CONST : MSEC_DATA, sec_off, m_bind)
          else
            writer.define_sym(sym_nm, is_const ? ESEC_RODATA : ESEC_DATA, sec_off, 8, e_bind, ESTT_OBJECT)
        pos = nl + 1
        next

      if spec.starts_with?("i32 ")
        val = ll_parse_i64(spec.slice(4, spec.size() - 4))
        target_buf.align_to(4, 0)
        sec_off = target_buf.len
        target_buf.put_u32_le(val)
        if is_macho
          writer.define_sym(sym_nm, is_const ? MSEC_CONST : MSEC_DATA, sec_off, m_bind)
        else
          writer.define_sym(sym_nm, is_const ? ESEC_RODATA : ESEC_DATA, sec_off, 4, e_bind, ESTT_OBJECT)
        pos = nl + 1
        next

      # Case D: Multi-line `{ i32, ... }` compact struct array (`[N x { i32, ... }] [`)
      if spec.ends_with?("\[") && spec.index("{ i32") != nil
        # Find closing `\n]` line!
        end_br = pos + line_len
        found_end = false
        while end_br < limit && !found_end
          nl2 = ll_find_nl(src_ptr, end_br + 1, limit)
          if nl2 > end_br + 1 && src.byte_at(end_br + 1) == 93
            found_end = true
            nl = nl2
          else
            end_br = nl2
        sa = ll_type_size_align(spec.slice(0, spec.size() - 1).strip())
        total_bytes = sa[0]
        target_buf.align_to(8, 0)
        sec_off = target_buf.len
        target_buf.reserve(total_bytes + 16)
        # Skip the header `[N x { i32, ... }] [` line so we don't match `i32` in the type signature!
        rows_start = pos + line_len + 1
        n_words = ll_emit_i32_table_raw(target_buf.raw_ptr() + sec_off, src_ptr, rows_start, nl)
        target_buf.len = sec_off + n_words * 4
        if is_macho
          writer.define_sym(sym_nm, is_const ? MSEC_CONST : MSEC_DATA, sec_off, m_bind)
        else
          writer.define_sym(sym_nm, is_const ? ESEC_RODATA : ESEC_DATA, sec_off, n_words * 4, e_bind, ESTT_OBJECT)
        pos = nl + 1
        next

      # Case E: Single-line `[N x i64] [i64 ..., i64 ...]` OR `[N x ptr] [ptr @..., ...]`
      lb1 = ll_index_outside_quotes(spec, 91, 0)
      rb1 = lb1 >= 0 ? ll_index_outside_quotes(spec, 93, lb1 + 1) : -1
      lb2 = rb1 >= 0 ? ll_index_outside_quotes(spec, 91, rb1 + 1) : -1
      rb2 = lb2 >= 0 ? ll_index_outside_quotes(spec, 93, lb2 + 1) : -1
      if lb2 >= 0 && rb2 > lb2
        arr_ty = spec.slice(lb1, rb1 - lb1 + 1)
        has_ptr_relocs = arr_ty.index(" x ptr]") != nil
        # On ELF64 PIE (`ld.lld -pie`), relocated pointer tables need writable `.data` (`.data.rel.ro` semantics)
        # rather than strictly read-only `.rodata`!
        use_ro = is_const && (is_macho || !has_ptr_relocs)
        arr_buf = use_ro ? writer.rodata : writer.data
        elems = ll_split_top_commas(spec.slice(lb2 + 1, rb2 - lb2 - 1))
        arr_buf.align_to(8, 0)
        sec_off = arr_buf.len
        if has_ptr_relocs
          ei = 0
          while ei < elems.size()
            el = elems[ei]
            at_e = ll_index_outside_quotes(el, 64, 0)
            elem_off = arr_buf.len
            arr_buf.put_u64_le(0)
            if at_e >= 0
              psym = ll_clean_sym(el.slice(at_e, cinder_blen(el) - at_e))
              mod.intern_sym(psym)
              if is_macho
                use_ro ? writer.add_const_ptr_reloc(elem_off, psym, 0) : writer.add_data_ptr_reloc(elem_off, psym, 0)
              else
                use_ro ? writer.add_const_ptr_reloc(elem_off, psym, 0) : writer.add_data_ptr_reloc(elem_off, psym, 0)
            ei += 1
        else
          ei = 0
          while ei < elems.size()
            el = elems[ei]
            sp_e = el.index(" ")
            v_str = sp_e != nil ? el.slice(sp_e + 1, el.size() - sp_e - 1) : el
            arr_buf.put_u64_le(ll_parse_i64(v_str))
            ei += 1
        byte_sz = arr_buf.len - sec_off
        if is_macho
          writer.define_sym(sym_nm, use_ro ? MSEC_CONST : MSEC_DATA, sec_off, m_bind)
        else
          writer.define_sym(sym_nm, use_ro ? ESEC_RODATA : ESEC_DATA, sec_off, byte_sz, e_bind, ESTT_OBJECT)
        pos = nl + 1
        next

    pos = nl + 1

  # Mark `@llvm.used` symbols with N_NO_DEAD_STRIP on Mach-O
  if is_macho
    ui = 0
    while ui < mod.used_syms.size()
      writer.mark_no_dead_strip(mod.used_syms[ui])
      ui += 1

  mod

# Parse a single function from its byte span `[hdr_line, body_start, body_end]` into `LLFunc`,
# and optionally compute compact linear-scan stack slot assignments (`assign_slots = true`).
-> ll_parse_function(src, src_ptr, mod_info, span, assign_slots = true)
  hdr = span[0]
  b_start = span[1]
  b_end = span[2]

  # Parse header: `define [internal|private] [preserve_mostcc] <ret_ty> @<name>(<params>) [attrs] {`
  at = ll_index_outside_quotes(hdr, 64, 0)
  pre_at = hdr.slice(0, at).strip()
  is_int = pre_at.index(" internal") != nil || pre_at.index(" private") != nil
  is_pm  = pre_at.index(" preserve_mostcc") != nil
  lp = ll_index_outside_quotes(hdr, 40, at)
  rp = ll_matching_rparen(hdr, lp)
  fn_name = ll_clean_sym(hdr.slice(at, lp - at))
  post_rp = hdr.slice(rp + 1, cinder_blen(hdr) - rp - 1)
  ih = :default
  if post_rp.index("alwaysinline") != nil || pre_at.index("alwaysinline") != nil
    ih = :always
  elsif post_rp.index("noinline") != nil || pre_at.index("noinline") != nil
    ih = :never
  else
    hi = post_rp.index("#")
    while hi != nil
      hend = hi + 1
      while hend < post_rp.size() && post_rp.byte_at(hend) >= 48 && post_rp.byte_at(hend) <= 57
        hend += 1
      if hend > hi + 1
        ag = mod_info.attr_groups[post_rp.slice(hi, hend - hi)]
        ih = ag if ag != nil
      hi = post_rp.index("#", hend)
  # Return type is the token immediately preceding `@`
  pre_parts = pre_at.split(" ")
  ret_ty = ll_type_tag(pre_parts[pre_parts.size() - 1])

  p_str = hdr.slice(lp + 1, rp - lp - 1).strip()
  param_tys = []
  param_names = []
  if p_str != ""
    p_items = ll_split_top_commas(p_str)
    pi = 0
    while pi < p_items.size()
      it = p_items[pi]
      pc_i = ll_index_outside_quotes(it, 37, 0)
      it_parts = it.split(" ")
      pty = ll_type_tag(it_parts[0])
      pnm = pc_i >= 0 ? ll_clean_sym(it.slice(pc_i, cinder_blen(it) - pc_i)) : ("arg." + pi.to_s())
      param_tys.push(pty)
      param_names.push(pnm)
      pi += 1

  fn_ir = LLFunc.new(fn_name, is_int, is_pm, ret_ty, param_tys)
  fn_ir.inline_hint = ih
  pi = 0
  while pi < param_names.size()
    fn_ir.get_val(param_names[pi], param_tys[pi])
    pi += 1

  cur_blk_id = fn_ir.get_block("__entry")
  cur_blk = fn_ir.blocks[cur_blk_id]
  has_explicit_first_label = false

  pos = b_start
  while pos < b_end
    nl = ll_find_nl(src_ptr, pos, b_end)
    llen = nl - pos
    llen -= 1 if llen > 0 && src.byte_at(pos + llen - 1) == 13
    pos_next = nl + 1
    if llen == 0
      pos = pos_next
      next
    s = src.slice(pos, llen).strip()
    pos = pos_next
    if s == "; tungsten:alwaysinline"
      fn_ir.inline_hint = :always
      next
    if s == "; tungsten:noinline"
      fn_ir.inline_hint = :never
      next
    if s == "" || s.starts_with?(";") || s == "}"
      next
    # Strip trailing `; comment` and `, !metadata` (`!llvm.loop`, `!prof`, `!range`, `!tbaa`, etc.) outside quotes
    s = ll_strip_line_tail(s)
    if s == ""
      next

    # Block label line: `name:`
    if s.ends_with?(":") && !s.starts_with?("\[")
      lbl_nm = ll_clean_sym(s.slice(0, cinder_blen(s) - 1).strip())
      if !has_explicit_first_label && cur_blk.insts.size() == 0 && cur_blk.phis.size() == 0
        has_explicit_first_label = true
        fn_ir.blk_map[lbl_nm] = 0
        cur_blk.name = lbl_nm
      else
        has_explicit_first_label = true
        cur_blk_id = fn_ir.get_block(lbl_nm)
        cur_blk = fn_ir.blocks[cur_blk_id]
      next
    has_explicit_first_label = true

    dst_id = -1
    rhs = s
    if s.starts_with?("%")
      eq = ll_index_outside_quotes(s, 61, 0)
      if eq > 0 && s.byte_at(eq - 1) == 32
        dst_nm = ll_clean_sym(s.slice(0, eq).strip())
        dst_id = fn_ir.get_val(dst_nm, 64)
        rhs = s.slice(eq + 1, cinder_blen(s) - eq - 1).strip()

    # Strip `tail ` / `notail ` / `musttail `
    if rhs.starts_with?("tail ")
      rhs = rhs.slice(5, rhs.size() - 5).strip()
    elsif rhs.starts_with?("notail ")
      rhs = rhs.slice(7, rhs.size() - 7).strip()
    elsif rhs.starts_with?("musttail ")
      rhs = rhs.slice(9, rhs.size() - 9).strip()

    sp0 = rhs.index(" ")
    op_str = sp0 == nil ? rhs : rhs.slice(0, sp0)
    rest = sp0 == nil ? "" : rhs.slice(sp0 + 1, rhs.size() - sp0 - 1).strip()

    if op_str == "alloca"
      # Forms: `alloca i64, align 8`, `alloca [3 x i64], align 8`, `alloca i64, i32 4, align 8`
      parts = ll_split_top_commas(rest)
      sa = ll_type_size_align(parts[0])
      elem_sz = sa[0]
      count = 1
      if parts.size() >= 2 && !parts[1].starts_with?("align ")
        p1_sp = parts[1].index(" ")
        count = p1_sp != nil ? parts[1].slice(p1_sp + 1, parts[1].size() - p1_sp - 1).to_i() : 1
      tot = ((elem_sz * count + 7) / 8) * 8
      tot = 8 if tot < 8
      off = fn_ir.alloca_bytes
      fn_ir.alloca_bytes += tot
      fn_ir.val_tys[dst_id] = LLTY_PTR
      ins = LLInst.new(:alloca, dst_id, LLTY_PTR)
      ins.v0 = off
      cur_blk.insts.push(ins)
    elsif op_str == "load"
      rest = rest.slice(9, rest.size() - 9).strip() if rest.starts_with?("volatile ")
      parts = ll_split_top_commas(rest)
      l_ty = ll_type_tag(parts[0])
      fn_ir.val_tys[dst_id] = l_ty
      pop = ll_parse_typed_operand(fn_ir, mod_info, parts[1])
      ins = LLInst.new(:load, dst_id, l_ty)
      ins.k0 = pop[1]; ins.v0 = pop[2]
      cur_blk.insts.push(ins)
    elsif op_str == "store"
      rest = rest.slice(9, rest.size() - 9).strip() if rest.starts_with?("volatile ")
      parts = ll_split_top_commas(rest)
      vop = ll_parse_typed_operand(fn_ir, mod_info, parts[0])
      pop = ll_parse_typed_operand(fn_ir, mod_info, parts[1])
      ins = LLInst.new(:store, -1, vop[0])
      ins.k0 = vop[1]; ins.v0 = vop[2]
      ins.k1 = pop[1]; ins.v1 = pop[2]
      cur_blk.insts.push(ins)
    elsif op_str == "getelementptr"
      rest = rest.slice(9, rest.size() - 9).strip() if rest.starts_with?("inbounds ")
      parts = ll_split_top_commas(rest)
      cur_ty = parts[0]
      base_op = ll_parse_typed_operand(fn_ir, mod_info, parts[1])
      # Build GEP offset steps: const_addend (i64) + dynamic `[[op_kind, op_val, byte_stride], ...]`
      const_off = 0
      dyn_steps = []
      ki = 2
      while ki < parts.size()
        iop = ll_parse_typed_operand(fn_ir, mod_info, parts[ki])
        if ki == 2
          sa0 = ll_type_size_align(cur_ty)
          stride0 = sa0[0]
          if iop[1] == LLOP_IMM
            const_off += iop[2] * stride0
          else
            dyn_steps.push([iop[1], iop[2], stride0])
        else
          if cur_ty.starts_with?("{")
            f_info = ll_struct_field_offset(cur_ty, iop[2])
            const_off += f_info[0]
            cur_ty = f_info[1]
          elsif cur_ty.starts_with?("\[")
            inner = cur_ty.slice(1, cur_ty.size() - 2).strip()
            xi = inner.index(" x ")
            ety = inner.slice(xi + 3, inner.size() - xi - 3).strip()
            esa = ll_type_size_align(ety)
            if iop[1] == LLOP_IMM
              const_off += iop[2] * esa[0]
            else
              dyn_steps.push([iop[1], iop[2], esa[0]])
            cur_ty = ety
        ki += 1
      fn_ir.val_tys[dst_id] = LLTY_PTR
      ins = LLInst.new(:gep, dst_id, LLTY_PTR)
      ins.k0 = base_op[1]; ins.v0 = base_op[2]
      ins.v1 = const_off
      ins.extra = dyn_steps.size() > 0 ? dyn_steps : nil
      cur_blk.insts.push(ins)
    elsif op_str == "br"
      if rest.starts_with?("label ")
        lbl_nm = ll_clean_sym(rest.slice(6, cinder_blen(rest) - 6).strip())
        ins = LLInst.new(:br, -1, LLTY_VOID)
        ins.v0 = fn_ir.get_block(lbl_nm)
        cur_blk.insts.push(ins)
      else
        parts = ll_split_top_commas(rest)
        cop = ll_parse_typed_operand(fn_ir, mod_info, parts[0])
        tl = parts[1].strip(); tl = ll_clean_sym(tl.slice(6, cinder_blen(tl) - 6).strip())
        fl = parts[2].strip(); fl = ll_clean_sym(fl.slice(6, cinder_blen(fl) - 6).strip())
        ins = LLInst.new(:cond_br, -1, LLTY_I1)
        ins.k0 = cop[1]; ins.v0 = cop[2]
        ins.v1 = fn_ir.get_block(tl)
        ins.v2 = fn_ir.get_block(fl)
        cur_blk.insts.push(ins)
    elsif op_str == "switch"
      # `switch i64 %val, label %def [` followed by `i64 CONST, label %TGT` lines until `]`
      lb = ll_index_outside_quotes(rest, 91, 0)
      head = rest.slice(0, lb).strip()
      hparts = ll_split_top_commas(head)
      vop = ll_parse_typed_operand(fn_ir, mod_info, hparts[0])
      dl = hparts[1].strip(); dl = ll_clean_sym(dl.slice(6, cinder_blen(dl) - 6).strip())
      def_bid = fn_ir.get_block(dl)
      cases = []
      in_sw = true
      while pos < b_end && in_sw
        nl2 = ll_find_nl(src_ptr, pos, b_end)
        cl = src.slice(pos, nl2 - pos).strip()
        pos = nl2 + 1
        if cl == "]" || cl.starts_with?("]")
          in_sw = false
        elsif cl != "" && !cl.starts_with?(";")
          cparts = ll_split_top_commas(cl)
          cv_op = ll_parse_typed_operand(fn_ir, mod_info, cparts[0])
          ctl = cparts[1].strip(); ctl = ll_clean_sym(ctl.slice(6, cinder_blen(ctl) - 6).strip())
          cases.push([cv_op[2], fn_ir.get_block(ctl)])
      ins = LLInst.new(:switch, -1, vop[0])
      ins.k0 = vop[1]; ins.v0 = vop[2]
      ins.v1 = def_bid
      ins.extra = cases
      cur_blk.insts.push(ins)
    elsif op_str == "ret"
      if rest == "void"
        cur_blk.insts.push(LLInst.new(:ret_void, -1, LLTY_VOID))
      else
        rop = ll_parse_typed_operand(fn_ir, mod_info, rest)
        ins = LLInst.new(:ret, -1, rop[0])
        ins.k0 = rop[1]; ins.v0 = rop[2]
        cur_blk.insts.push(ins)
    elsif op_str == "unreachable"
      cur_blk.insts.push(LLInst.new(:unreachable, -1, LLTY_VOID))
    elsif op_str == "phi"
      # `phi <ty> [ v0, %b0 ], [ v1, %b1 ], ...`
      lb = ll_index_outside_quotes(rest, 91, 0)
      pty = ll_type_tag(rest.slice(0, lb).strip())
      fn_ir.val_tys[dst_id] = pty
      pairs = []
      p_cursor = lb
      rn = cinder_blen(rest)
      while p_cursor >= 0 && p_cursor < rn
        rb = ll_index_outside_quotes(rest, 93, p_cursor + 1)
        if rb < 0
          p_cursor = -1
        else
          inside = rest.slice(p_cursor + 1, rb - p_cursor - 1)
          cm = ll_index_outside_quotes(inside, 44, 0)
          v_tok = inside.slice(0, cm).strip()
          b_tok = inside.slice(cm + 1, cinder_blen(inside) - cm - 1).strip()
          b_nm = ll_clean_sym(b_tok)
          v_op = ll_parse_operand(fn_ir, mod_info, v_tok, pty)
          pairs.push([fn_ir.get_block(b_nm), v_op[0], v_op[1]])
          p_cursor = ll_index_outside_quotes(rest, 91, rb + 1)
      ins = LLInst.new(:phi, dst_id, pty)
      ins.extra = pairs
      cur_blk.phis.push(ins)
    elsif op_str == "select"
      parts = ll_split_top_commas(rest)
      cop = ll_parse_typed_operand(fn_ir, mod_info, parts[0])
      top = ll_parse_typed_operand(fn_ir, mod_info, parts[1])
      fop = ll_parse_typed_operand(fn_ir, mod_info, parts[2])
      fn_ir.val_tys[dst_id] = top[0]
      ins = LLInst.new(:select, dst_id, top[0])
      ins.k0 = cop[1]; ins.v0 = cop[2]
      ins.k1 = top[1]; ins.v1 = top[2]
      ins.k2 = fop[1]; ins.v2 = fop[2]
      cur_blk.insts.push(ins)
    elsif op_str == "icmp" || op_str == "fcmp"
      sp1 = rest.index(" ")
      pred_s = rest.slice(0, sp1).strip().to_sym()
      rem_s = rest.slice(sp1 + 1, rest.size() - sp1 - 1).strip()
      parts = ll_split_top_commas(rem_s)
      aop = ll_parse_typed_operand(fn_ir, mod_info, parts[0])
      bop = ll_parse_operand(fn_ir, mod_info, parts[1], aop[0])
      fn_ir.val_tys[dst_id] = LLTY_I1
      ins = LLInst.new(op_str == "icmp" ? :icmp : :fcmp, dst_id, aop[0])
      ins.pred = pred_s
      ins.k0 = aop[1]; ins.v0 = aop[2]
      ins.k1 = bop[0]; ins.v1 = bop[1]
      cur_blk.insts.push(ins)
    elsif op_str == "sext" || op_str == "zext" || op_str == "trunc" || op_str == "inttoptr" || op_str == "ptrtoint" || op_str == "bitcast" || op_str == "sitofp" || op_str == "uitofp" || op_str == "fptosi" || op_str == "fptoui" || op_str == "fptrunc" || op_str == "fpext"
      # Find ` to ` outside quotes (in case operand is `@"w:... to ..."`)
      to_idx = -1
      sp_scan = 0
      while sp_scan >= 0
        si = ll_index_outside_quotes(rest, 32, sp_scan)
        if si < 0
          sp_scan = -1
        else
          if cinder_blen(rest) >= si + 4 && rest.slice(si, 4) == " to "
            to_idx = si
          sp_scan = si + 1
      src_part = rest.slice(0, to_idx).strip()
      dst_ty = ll_type_tag(rest.slice(to_idx + 4, cinder_blen(rest) - to_idx - 4).strip())
      sop = ll_parse_typed_operand(fn_ir, mod_info, src_part)
      fn_ir.val_tys[dst_id] = dst_ty
      ins = LLInst.new(op_str.to_sym(), dst_id, dst_ty)
      ins.ty2 = sop[0]
      ins.k0 = sop[1]; ins.v0 = sop[2]
      cur_blk.insts.push(ins)
    elsif op_str == "extractvalue"
      parts = ll_split_top_commas(rest)
      sop = ll_parse_typed_operand(fn_ir, mod_info, parts[0])
      idx = parts[1].to_i()
      out_ty = idx == 1 ? LLTY_I1 : LLTY_I64
      fn_ir.val_tys[dst_id] = out_ty
      ins = LLInst.new(:extractvalue, dst_id, out_ty)
      ins.k0 = sop[1]; ins.v0 = sop[2]
      ins.v1 = idx
      cur_blk.insts.push(ins)
    elsif op_str == "extractelement"
      parts = ll_split_top_commas(rest)
      sop = ll_parse_typed_operand(fn_ir, mod_info, parts[0])
      iop = ll_parse_typed_operand(fn_ir, mod_info, parts[1])
      fn_ir.val_tys[dst_id] = LLTY_I64
      ins = LLInst.new(:extractelement, dst_id, LLTY_I64)
      ins.k0 = sop[1]; ins.v0 = sop[2]
      ins.v1 = iop[2]
      cur_blk.insts.push(ins)
    elsif op_str == "call"
      # Check inline asm BEFORE quotes: `call i64 asm [sideeffect] "TEMPLATE", "CONSTRAINTS"(args)`
      q1_chk = rest.index("\"")
      pre_q = q1_chk != nil ? rest.slice(0, q1_chk) : rest
      if pre_q.index(" asm ") != nil || pre_q.starts_with?("i64 asm")
        q1 = q1_chk
        q2 = rest.index("\"", q1 + 1)
        tmpl = rest.slice(q1 + 1, q2 - q1 - 1)
        q3 = rest.index("\"", q2 + 1)
        q4 = rest.index("\"", q3 + 1)
        lp_a = ll_index_outside_quotes(rest, 40, q4 + 1)
        rp_a = ll_matching_rparen(rest, lp_a)
        arg_s = rest.slice(lp_a + 1, rp_a - lp_a - 1).strip()
        asm_args = []
        if arg_s != ""
          aitems = ll_split_top_commas(arg_s)
          ai = 0
          while ai < aitems.size()
            asm_args.push(ll_parse_typed_operand(fn_ir, mod_info, aitems[ai]))
            ai += 1
        fn_ir.val_tys[dst_id] = LLTY_I64 if dst_id >= 0
        ins = LLInst.new(:call_asm, dst_id, LLTY_I64)
        ins.extra = [tmpl, asm_args]
        cur_blk.insts.push(ins)
      else
        # Normal or indirect call: `[preserve_mostcc] <ret_ty> [@callee | %fptr](<args>) [attrs]`
        if rest.starts_with?("preserve_mostcc ")
          rest = rest.slice(16, cinder_blen(rest) - 16).strip()
        cal_pos = ll_index_outside_quotes(rest, 64, 0)
        pc_pos  = ll_index_outside_quotes(rest, 37, 0)
        if cal_pos < 0 || (pc_pos >= 0 && pc_pos < cal_pos)
          cal_pos = pc_pos
        lp_c = ll_index_outside_quotes(rest, 40, cal_pos)
        rp_c = ll_matching_rparen(rest, lp_c)
        c_ret_ty = ll_type_tag(rest.slice(0, cal_pos).strip())
        cal_tok = rest.slice(cal_pos, lp_c - cal_pos).strip()
        fn_ir.val_tys[dst_id] = c_ret_ty if dst_id >= 0

        arg_s = rest.slice(lp_c + 1, rp_c - lp_c - 1).strip()
        c_args = []
        if arg_s != ""
          aitems = ll_split_top_commas(arg_s)
          ai = 0
          while ai < aitems.size()
            c_args.push(ll_parse_typed_operand(fn_ir, mod_info, aitems[ai]))
            ai += 1

        if cal_tok.starts_with?("@llvm.")
          # Intrinsic call!
          intr = cal_tok.slice(6, cal_tok.size() - 6)
          ins = LLInst.new(:intrinsic, dst_id, c_ret_ty)
          ins.pred = intr
          ins.extra = c_args
          cur_blk.insts.push(ins)
        else
          cop = ll_parse_operand(fn_ir, mod_info, cal_tok, LLTY_PTR)
          ins = LLInst.new(:call, dst_id, c_ret_ty)
          ins.k0 = cop[0]; ins.v0 = cop[1]
          ins.extra = c_args
          cur_blk.insts.push(ins)
    else
      # Binary ALU / FP op: `<op> [nsw] [nuw] [exact] <ty> <a_val>, <b_val>`
      if rest.starts_with?("nsw ")
        rest = rest.slice(4, rest.size() - 4).strip()
      if rest.starts_with?("nuw ")
        rest = rest.slice(4, rest.size() - 4).strip()
      if rest.starts_with?("exact ")
        rest = rest.slice(6, rest.size() - 6).strip()
      if rest.starts_with?("disjoint ")
        rest = rest.slice(9, rest.size() - 9).strip()
      parts = ll_split_top_commas(rest)
      aop = ll_parse_typed_operand(fn_ir, mod_info, parts[0])
      bop = ll_parse_operand(fn_ir, mod_info, parts[1], aop[0])
      fn_ir.val_tys[dst_id] = aop[0] if dst_id >= 0
      ins = LLInst.new(op_str.to_sym(), dst_id, aop[0])
      ins.k0 = aop[1]; ins.v0 = aop[2]
      ins.k1 = bop[0]; ins.v1 = bop[1]
      cur_blk.insts.push(ins)

  ll_assign_stack_slots(fn_ir) if assign_slots
  fn_ir

# Compact linear-scan stack & virtual-slot allocator:
#   - Allocates static `alloca` buffers at `[0 .. alloca_bytes)`.
#   - Separates 64-bit integer/ptr vs 64-bit floating-point intra-block pool slots (`pool_slots_g` / `pool_slots_f`),
#     tracking exact per-slot dynamic/static use counts so backends can promote the hottest scalar slots
#     directly into hardware registers (`R_X19..R_X26` / `R_D8..R_D15` on ARM64, `RBX, R12..R14` on x86_64)!
-> ll_assign_stack_slots(fn_ir)
  nv = fn_ir.n_vals
  def_blk = Array.new(nv, -1)
  last_use = Array.new(nv, -1)
  pinned = Array.new(nv, false)
  uses = Array.new(nv, 0)

  i = 0
  while i < fn_ir.n_params
    def_blk[i] = 0
    pinned[i] = true
    i += 1

  max_phis_in_blk = 0
  bi = 0
  while bi < fn_ir.blocks.size()
    blk = fn_ir.blocks[bi]
    np = blk.phis.size()
    max_phis_in_blk = np if np > max_phis_in_blk
    pi = 0
    while pi < np
      ph = blk.phis[pi]
      pinned[ph.dst] = true
      def_blk[ph.dst] = bi
      prs = ph.extra
      k = 0
      while k < prs.size()
        if prs[k][1] == LLOP_VAL
          u = prs[k][2]
          pinned[u] = true
          uses[u] = uses[u] + 1
        k += 1
      pi += 1

    ii = 0
    while ii < blk.insts.size()
      ins = blk.insts[ii]
      d = ins.dst
      if d >= 0
        def_blk[d] = bi
        vt = fn_ir.val_tys[d]
        if vt == LLTY_I128 || vt == LLTY_V2I64 || vt == LLTY_OV64 || ins.op == :alloca
          pinned[d] = true
      if ins.k0 == LLOP_VAL
        u = ins.v0
        uses[u] = uses[u] + 1
        if def_blk[u] != bi
          pinned[u] = true
        else
          last_use[u] = ii
      if ins.k1 == LLOP_VAL
        u = ins.v1
        uses[u] = uses[u] + 1
        if def_blk[u] != bi
          pinned[u] = true
        else
          last_use[u] = ii
      if ins.k2 == LLOP_VAL
        u = ins.v2
        uses[u] = uses[u] + 1
        if def_blk[u] != bi
          pinned[u] = true
        else
          last_use[u] = ii
      if ins.extra != nil
        op = ins.op
        if op == :call || op == :intrinsic
          ai = 0
          while ai < ins.extra.size()
            ca = ins.extra[ai]
            if ca[1] == LLOP_VAL
              u = ca[2]
              uses[u] = uses[u] + 1
              if def_blk[u] != bi
                pinned[u] = true
              else
                last_use[u] = ii
            ai += 1
        elsif op == :call_asm
          aargs = ins.extra[1]
          ai = 0
          while ai < aargs.size()
            ca = aargs[ai]
            if ca[1] == LLOP_VAL
              u = ca[2]
              uses[u] = uses[u] + 1
              if def_blk[u] != bi
                pinned[u] = true
              else
                last_use[u] = ii
            ai += 1
        elsif op == :gep
          ai = 0
          while ai < ins.extra.size()
            st = ins.extra[ai]
            if st[0] == LLOP_VAL
              u = st[1]
              uses[u] = uses[u] + 1
              if def_blk[u] != bi
                pinned[u] = true
              else
                last_use[u] = ii
            ai += 1
      ii += 1
    bi += 1

  fn_ir.val_uses = uses
  slots = Array.new(nv, -1)
  cur_off = ((fn_ir.alloca_bytes + 15) / 16) * 16
  slot_is_fp = {}     # byte_offset -> bool (`true` = f64/f32 scalar, `false` = 64-bit GPR scalar; nil = 16-byte wide)
  slot_uses = {}      # byte_offset -> weighted score (1 + uses)

  # 1. Assign pinned slots
  vi = 0
  while vi < nv
    if pinned[vi]
      vt = fn_ir.val_tys[vi]
      sz = (vt == LLTY_I128 || vt == LLTY_V2I64 || vt == LLTY_OV64) ? 16 : 8
      cur_off = ((cur_off + 15) / 16) * 16 if sz == 16
      slots[vi] = cur_off
      if sz == 8
        slot_is_fp[cur_off] = (vt == LLTY_F64 || vt == LLTY_F32)
        slot_uses[cur_off] = 1 + uses[vi]
      cur_off += sz
    vi += 1

  # 2. Separate linear-scan reuse for intra-block 8-byte GPR and FP temporaries!
  pool_slots_g = []
  pool_slots_f = []
  bi = 0
  while bi < fn_ir.blocks.size()
    blk = fn_ir.blocks[bi]
    free_g = []
    pi = pool_slots_g.size() - 1
    while pi >= 0
      free_g.push(pool_slots_g[pi])
      pi -= 1
    free_f = []
    pi = pool_slots_f.size() - 1
    while pi >= 0
      free_f.push(pool_slots_f[pi])
      pi -= 1
    release_g = {}
    release_f = {}
    ii = 0
    while ii < blk.insts.size()
      ins = blk.insts[ii]
      d = ins.dst
      if d >= 0 && !pinned[d]
        vt = fn_ir.val_tys[d]
        is_f = (vt == LLTY_F64 || vt == LLTY_F32)
        sl = 0
        if is_f
          if free_f.size() > 0
            sl = free_f.pop()
          else
            sl = cur_off
            cur_off += 8
            pool_slots_f.push(sl)
            slot_is_fp[sl] = true
            slot_uses[sl] = 0
          slot_uses[sl] = slot_uses[sl] + 1 + uses[d]
          slots[d] = sl
          lu = last_use[d]
          if lu < 0 || lu <= ii
            free_f.push(sl)
          else
            arr = release_f[lu]
            if arr == nil
              arr = []; release_f[lu] = arr
            arr.push(sl)
        else
          if free_g.size() > 0
            sl = free_g.pop()
          else
            sl = cur_off
            cur_off += 8
            pool_slots_g.push(sl)
            slot_is_fp[sl] = false
            slot_uses[sl] = 0
          slot_uses[sl] = slot_uses[sl] + 1 + uses[d]
          slots[d] = sl
          lu = last_use[d]
          if lu < 0 || lu <= ii
            free_g.push(sl)
          else
            arr = release_g[lu]
            if arr == nil
              arr = []; release_g[lu] = arr
            arr.push(sl)
      rel_g = release_g[ii]
      if rel_g != nil
        ri = 0
        while ri < rel_g.size()
          free_g.push(rel_g[ri])
          ri += 1
      rel_f = release_f[ii]
      if rel_f != nil
        ri = 0
        while ri < rel_f.size()
          free_f.push(rel_f[ri])
          ri += 1
      ii += 1
    bi += 1

  # 3. Reserve PHI parallel-copy staging area (16 bytes per PHI in largest PHI block)
  cur_off = ((cur_off + 15) / 16) * 16
  fn_ir.phi_stage_off = cur_off
  cur_off += max_phis_in_blk * 16
  fn_ir.val_slot = slots
  fn_ir.slot_is_fp = slot_is_fp
  fn_ir.slot_uses = slot_uses
  fn_ir.n_scalar_slots = slot_uses.size()
  fn_ir.frame_slots_bytes = ((cur_off + 15) / 16) * 16
  nil
