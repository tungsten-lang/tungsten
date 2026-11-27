# cinder/lto — Cross-File Link-Time Optimization (LTO) Merger, Fat-Object / Archive
# Extractor, Whole-Program Internalizer, and Hot-Runtime LTO Bridge.
#
# Architecture:
#   1. Fat-LTO Relocatable Objects (`-c -flto` / `-c --lto`):
#      - Embeds a `CNDRLTO1` IR section (`__DWARF,__cinder_lto` with `S_ATTR_DEBUG` on Mach-O 64;
#        non-alloc `.cinder.lto` on ELF64) alongside native `.text`/`.rodata`/`.data`/`.symtab`.
#      - Standard `ar`, `ranlib`, `nm`, `otool`, `readelf`, and non-LTO `ld` work out of the box!
#   2. Binary Object & Static Archive Reader (`cinder_extract_lto_from_file`, `cinder_extract_lto_from_archive`):
#      - Inspects Mach-O 64 `.o`, ELF64 `.o`, standalone `.clto`, and BSD/GNU `!<arch>\n` `.a`
#        static archives (including BSD `#1/<len>` extended member names) in pure Tungsten.
#   3. Multi-Module IR Linker & Interprocedural Optimizer (`cinder_lto_merge_modules`):
#      - Alpha-renames `internal`/`private` functions, globals, constants (`@.str.*`), and TLS
#        variables (`@.ic` -> `@.ic.m<k>`) across secondary modules to eliminate name collisions.
#      - Normalizes per-module `attributes #N` (`alwaysinline` / `noinline`) directly onto
#        `define` headers so `#0` attribute groups from distinct files never collide.
#      - Merges multiple `@__static_slab` interned string slabs into ONE unified 32-byte-aligned
#        OS-`mmap`'d `@__static_slab` in `__TEXT,__const` / `.rodata`, rewriting secondary
#        mode-6 `0xFFF9...C` immediate `WValue` slot indices in-place!
#      - Deduplicates repeated Core seams across multi-`.w` LTO builds and chains secondary
#        module top-level initializers (`@__clto_init_m<k>`) into `@main`.
#      - Performs Whole-Program Internalization (`-flto-internalize`) and Dead Global Data
#        Elimination (`-flto-dce`), unlocking single-caller inline boosts, cross-file constant
#        return folding (`-fipa-sccp`), and 100% dead-function stripping.
#   4. Runtime Hot-Boundary LTO Module (`cinder_runtime_hot_lto_ir`):
#      - Supplies exact `alwaysinline` IR for the thread-local BigInt hot-slot allocator
#        (`w_bigint_alloc_hot*`), swap-form release (`w_bigint_release_dead_raw`), and size
#        finishers (`w_bigint_*_finish_raw`), hoisted by LICM + `reg-promote` in loops!

use ./buf
use ./macho64
use ./elf64
use ./opt_config
use ./ll_parser

# ---- 1. Binary Fat-LTO `.o` & `.a` Archive Readers ----

-> cinder_has_lto_magic?(bb, off)
  return false if bb == nil || off < 0 || off + 16 > bb.len
  bb.read_u8(off) == 67 && bb.read_u8(off + 1) == 78 && bb.read_u8(off + 2) == 68 && bb.read_u8(off + 3) == 82 &&
    bb.read_u8(off + 4) == 76 && bb.read_u8(off + 5) == 84 && bb.read_u8(off + 6) == 79 && bb.read_u8(off + 7) == 49

-> cinder_decode_lto_payload(bb, off, max_len)
  return nil if !cinder_has_lto_magic?(bb, off)
  ir_len = bb.read_u32_le(off + 12)
  return nil if ir_len < 0 || 16 + ir_len > max_len || off + 16 + ir_len > bb.len
  bb.slice_ascii(off + 16, ir_len)

# Read up to `max_n` NUL-padded ASCII bytes from `bb` at `off`
-> cinder_read_fixed_cstr(bb, off, max_n)
  e = 0
  while e < max_n && off + e < bb.len && bb.read_u8(off + e) != 0
    e += 1
  bb.slice_ascii(off, e)

# Extract embedded LTO IR string from `bb[base_off .. base_off + obj_len)` (`Mach-O 64`, `ELF64`, or raw `CNDRLTO1`).
# Returns `ir_str` or `nil` if the object is a plain native non-LTO object.
-> cinder_extract_lto_from_slice(bb, base_off, obj_len)
  return nil if bb == nil || obj_len < 16 || base_off < 0 || base_off + obj_len > bb.len

  # 1. Raw `CNDRLTO1` container
  if cinder_has_lto_magic?(bb, base_off)
    return cinder_decode_lto_payload(bb, base_off, obj_len)

  magic = bb.read_u32_le(base_off)

  # 2. Mach-O 64 `MH_OBJECT` (`0xFEEDFACF`)
  if magic == 0xFEEDFACF && obj_len >= 32
    ncmds = bb.read_u32_le(base_off + 16)
    cmd_off = base_off + 32
    limit = base_off + obj_len
    ci = 0
    while ci < ncmds && cmd_off + 8 <= limit
      cmd = bb.read_u32_le(cmd_off)
      cmdsize = bb.read_u32_le(cmd_off + 4)
      break if cmdsize < 8 || cmd_off + cmdsize > limit
      if cmd == 0x19 && cmdsize >= 72
        nsects = bb.read_u32_le(cmd_off + 64)
        si = 0
        sec_off = cmd_off + 72
        while si < nsects && sec_off + 80 <= cmd_off + cmdsize
          sectname = cinder_read_fixed_cstr(bb, sec_off, 16)
          if sectname == "__cinder_lto" || sectname == "__lto"
            sz = bb.read_u64_le(sec_off + 40)
            foff = bb.read_u32_le(sec_off + 48)
            if sz >= 16 && foff >= 0 && base_off + foff + sz <= limit
              ir = cinder_decode_lto_payload(bb, base_off + foff, sz)
              return ir if ir != nil
          sec_off += 80
          si += 1
      cmd_off += cmdsize
      ci += 1
    return nil

  # 3. ELF64 `ET_REL` (`0x464C457F`)
  if magic == 0x464C457F && obj_len >= 64 && bb.read_u8(base_off + 4) == 2
    shoff = bb.read_u64_le(base_off + 40)
    shentsize = bb.read_u16_le(base_off + 58)
    shnum = bb.read_u16_le(base_off + 60)
    shstrndx = bb.read_u16_le(base_off + 62)
    limit = base_off + obj_len
    if shoff > 0 && shentsize >= 64 && shnum > 0 && shstrndx < shnum && base_off + shoff + shnum * shentsize <= limit
      shstr_hdr = base_off + shoff + shstrndx * shentsize
      shstr_off = bb.read_u64_le(shstr_hdr + 24)
      shstr_sz  = bb.read_u64_le(shstr_hdr + 32)
      si = 0
      while si < shnum
        sh = base_off + shoff + si * shentsize
        nm_idx = bb.read_u32_le(sh)
        s_off  = bb.read_u64_le(sh + 24)
        s_sz   = bb.read_u64_le(sh + 32)
        if s_sz >= 16 && base_off + s_off + s_sz <= limit
          if shstr_off + nm_idx < limit
            snm = cinder_read_fixed_cstr(bb, base_off + shstr_off + nm_idx, 32)
            if snm == ".cinder.lto"
              ir = cinder_decode_lto_payload(bb, base_off + s_off, s_sz)
              return ir if ir != nil
        si += 1
    return nil

  nil

-> cinder_extract_lto_from_file(path)
  bb = cinder_read_raw_file_buf(path)
  return nil if bb == nil
  cinder_extract_lto_from_slice(bb, 0, bb.len)

# Inspect a Unix static archive `.a` (`!<arch>\n`):
# Returns `[lto_ir_list, has_native_non_lto_members_bool]`, or `nil` if not a valid `ar` archive.
-> cinder_extract_lto_from_archive(ar_path)
  bb = cinder_read_raw_file_buf(ar_path)
  return nil if bb == nil || bb.len < 8
  return nil if bb.slice_ascii(0, 8) != "!<arch>\n"

  irs = []
  has_native = false
  pos = 8
  limit = bb.len
  while pos + 60 <= limit
    raw_name = bb.slice_ascii(pos, 16).strip()
    sz_str = bb.slice_ascii(pos + 48, 10).strip()
    mem_sz = sz_str.to_i()
    break if mem_sz < 0
    data_start = pos + 60
    data_len = mem_sz
    next_pos = data_start + mem_sz
    next_pos += 1 if (next_pos & 1) == 1
    break if data_start + mem_sz > limit

    # Handle BSD `#1/<len>` extended member names
    real_name = raw_name
    if raw_name.starts_with?("#1/")
      ext_len = raw_name.slice(3, raw_name.size() - 3).to_i()
      if ext_len > 0 && ext_len <= data_len
        real_name = cinder_read_fixed_cstr(bb, data_start, ext_len)
        data_start += ext_len
        data_len -= ext_len

    # Skip archive symbol-table / string-table pseudo-members
    is_symdef = real_name == "/" || real_name == "//" || real_name == "/SYM64/" ||
                real_name.starts_with?("__.SYMDEF")
    if !is_symdef && data_len >= 16
      ir = cinder_extract_lto_from_slice(bb, data_start, data_len)
      if ir != nil
        irs.push(ir)
      else
        has_native = true
    pos = next_pos
  [irs, has_native]

# ---- 2. Multi-Module IR Rewriter, Slab Merger & Whole-Program Internalizer ----

-> lto_is_ident_tail_byte?(b)
  return true if (b >= 48 && b <= 57) || (b >= 65 && b <= 90) || (b >= 97 && b <= 122)
  b == 95 || b == 46 || b == 36 || b == 58 || b == 45

-> lto_format_sym_ref(nm)
  # Quote identifiers that contain characters outside standard bare LLVM identifier syntax
  need_q = false
  n = cinder_blen(nm)
  i = 0
  while i < n
    b = nm.byte_at(i)
    ok = (b >= 65 && b <= 90) || (b >= 97 && b <= 122) || b == 95 || b == 46 || b == 36 || (i > 0 && b >= 48 && b <= 57)
    if !ok
      need_q = true
      break
    i += 1
  need_q ? ("@\"" + nm + "\"") : ("@" + nm)

# Rewrite `@<sym>` tokens on a single IR line outside `c"..."` string literals according to `rename_map` (`old_nm => new_nm`),
# and optionally shift mode-6 static slab `u0xfff9...c` immediates by `slab_slot_delta`!
-> lto_rewrite_line_syms_and_slab(line, rename_map, slab_slot_delta)
  has_renames = rename_map != nil && rename_map.size() > 0
  return line if !has_renames && slab_slot_delta <= 0
  n = cinder_blen(line)
  return line if n == 0
  # Fast check: if no `@` and (slab_slot_delta == 0 or no `fff9` / `-19703248369745`), nothing to rewrite!
  has_at = line.index("@") != nil
  has_slab_imm = slab_slot_delta > 0 && (line.index("fff9") != nil || line.index("FFF9") != nil)
  return line if (!has_renames || !has_at) && !has_slab_imm

  sb = StringBuffer(n + 32)
  i = 0
  in_cstr = false
  while i < n
    b = line.byte_at(i)
    if in_cstr
      sb << line.slice(i, 1)
      if b == 34
        in_cstr = false
      elsif b == 92 && i + 1 < n
        sb << line.slice(i + 1, 1)
        i += 1
      i += 1
      next

    # Detect start of `c"..."` byte literal (do NOT rewrite `@` inside `c"..."`!)
    if b == 99 && i + 1 < n && line.byte_at(i + 1) == 34
      sb << "c\""
      in_cstr = true
      i += 2
      next

    # Skip `; comment` tail verbatim
    if b == 59
      sb << line.slice(i, n - i)
      break

    # Rewrite `@"..."` or `@ident`
    if has_renames && b == 64 && i + 1 < n
      if line.byte_at(i + 1) == 34
        q_end = i + 2
        while q_end < n && line.byte_at(q_end) != 34
          q_end += (line.byte_at(q_end) == 92 ? 2 : 1)
        if q_end < n
          raw_tok = line.slice(i, q_end - i + 1)
          sym_nm = ll_clean_sym(raw_tok)
          rep = rename_map[sym_nm]
          sb << (rep != nil ? lto_format_sym_ref(rep) : raw_tok)
          i = q_end + 1
          next
      else
        e = i + 1
        while e < n && lto_is_ident_tail_byte?(line.byte_at(e))
          e += 1
        if e > i + 1
          sym_nm = line.slice(i + 1, e - i - 1)
          rep = rename_map[sym_nm]
          sb << (rep != nil ? lto_format_sym_ref(rep) : line.slice(i, e - i))
          i = e
          next

    # Rewrite mode-6 slab `u0xfff9...c` / `0xfff9...c` hex immediates when `slab_slot_delta > 0`
    if has_slab_imm && ((b == 117 && i + 19 <= n && line.slice(i, 7).downcase() == "u0xfff9") || (b == 48 && i + 18 <= n && line.slice(i, 6).downcase() == "0xfff9"))
      pfx_len = b == 117 ? 3 : 2
      he = i + pfx_len
      while he < n
        hb = line.byte_at(he)
        break if !((hb >= 48 && hb <= 57) || (hb >= 65 && hb <= 70) || (hb >= 97 && hb <= 102))
        he += 1
      tok = line.slice(i, he - i)
      imm_v = ll_parse_i64(tok)
      if ((imm_v >> 48) & 0xFFFF) == 0xFFF9 && (imm_v & 0xF) == 0xC
        old_slot = (imm_v >> 4) & 0xFFFFFF
        if old_slot > 0
          new_imm = imm_v + (slab_slot_delta << 4)
          sb << new_imm.to_s()
          i = he
          next

    sb << line.slice(i, 1)
    i += 1
  sb.to_s()

-> lto_rewrite_text_syms_and_slab(txt, rename_map, slab_slot_delta)
  return lto_rewrite_line_syms_and_slab(txt, rename_map, slab_slot_delta) if txt.index("\n") == nil
  parts = txt.split("\n")
  sb = StringBuffer(cinder_blen(txt) + 32)
  pi = 0
  while pi < parts.size()
    sb << "\n" if pi > 0
    sb << lto_rewrite_line_syms_and_slab(parts[pi], rename_map, slab_slot_delta)
    pi += 1
  sb.to_s()

# Collect all `@<ident>` / `@"..."` symbol references in `txt` into `out_set` (`sym_nm => true`),
# ignoring `c"..."` byte literals and `;` comments. When `skip_lhs_eq` is true, starts after `=`.
-> lto_collect_sym_refs(txt, skip_lhs_eq, out_set)
  n = cinder_blen(txt)
  return nil if n == 0 || txt.index("@") == nil
  i = 0
  if skip_lhs_eq
    eq_i = ll_index_outside_quotes(txt, 61, 0)
    i = eq_i >= 0 ? (eq_i + 1) : 0
  if n > 16
    tp = cinder_heap_str_ptr(wvalue_bits(txt) ## i64)
    has_cstr = txt.index("c\"", i) != nil
    has_semi = txt.index(";", i) != nil
    if !has_cstr && !has_semi
      at_pos = txt.index("@", i)
      while at_pos != nil
        if at_pos + 1 < n
          b1 = ll_load_u8_raw(tp, at_pos + 1)
          if b1 == 34
            q_end = at_pos + 2
            while q_end < n && ll_load_u8_raw(tp, q_end) != 34
              q_end += (ll_load_u8_raw(tp, q_end) == 92 ? 2 : 1)
            if q_end < n
              out_set[ll_clean_sym(txt.slice(at_pos, q_end - at_pos + 1))] = true
              at_pos = txt.index("@", q_end + 1)
              next
          else
            e = at_pos + 1
            while e < n && lto_is_ident_tail_byte?(ll_load_u8_raw(tp, e))
              e += 1
            if e > at_pos + 1
              out_set[txt.slice(at_pos + 1, e - at_pos - 1)] = true
              at_pos = txt.index("@", e)
              next
        at_pos = txt.index("@", at_pos + 1)
      return nil
    in_cstr = false
    while i < n
      b = ll_load_u8_raw(tp, i)
      if in_cstr
        if b == 34
          in_cstr = false
        elsif b == 92 && i + 1 < n
          i += 1
        i += 1
        next
      if b == 99 && i + 1 < n && ll_load_u8_raw(tp, i + 1) == 34
        in_cstr = true
        i += 2
        next
      if b == 59
        i = ll_find_nl(tp, i, n)
        next
      if b == 64 && i + 1 < n
        if ll_load_u8_raw(tp, i + 1) == 34
          q_end = i + 2
          while q_end < n && ll_load_u8_raw(tp, q_end) != 34
            q_end += (ll_load_u8_raw(tp, q_end) == 92 ? 2 : 1)
          if q_end < n
            out_set[ll_clean_sym(txt.slice(i, q_end - i + 1))] = true
            i = q_end + 1
            next
        else
          e = i + 1
          while e < n && lto_is_ident_tail_byte?(ll_load_u8_raw(tp, e))
            e += 1
          if e > i + 1
            out_set[txt.slice(i + 1, e - i - 1)] = true
            i = e
            next
      i += 1
    return nil
  in_cstr = false
  while i < n
    b = txt.byte_at(i)
    if in_cstr
      if b == 34
        in_cstr = false
      elsif b == 92 && i + 1 < n
        i += 1
      i += 1
      next
    if b == 99 && i + 1 < n && txt.byte_at(i + 1) == 34
      in_cstr = true
      i += 2
      next
    if b == 59
      while i < n && txt.byte_at(i) != 10
        i += 1
      next
    if b == 64 && i + 1 < n
      if txt.byte_at(i + 1) == 34
        q_end = i + 2
        while q_end < n && txt.byte_at(q_end) != 34
          q_end += (txt.byte_at(q_end) == 92 ? 2 : 1)
        if q_end < n
          out_set[ll_clean_sym(txt.slice(i, q_end - i + 1))] = true
          i = q_end + 1
          next
      else
        e = i + 1
        while e < n && lto_is_ident_tail_byte?(txt.byte_at(e))
          e += 1
        if e > i + 1
          out_set[txt.slice(i + 1, e - i - 1)] = true
          i = e
          next
    i += 1
  nil

# Encode raw bytes from `ByteBuf` `[off .. off + len)` as LLVM `c"..."` escaped ASCII string
-> lto_encode_llvm_cbytes(bb, off, len)
  hex = "0123456789ABCDEF"
  sb = StringBuffer(len * 2 + 16)
  i = 0
  while i < len
    b = bb.read_u8(off + i)
    if b >= 32 && b <= 126 && b != 34 && b != 92
      sb << b.chr()
    else
      sb << "\\"
      sb << hex.slice((b >> 4) & 15, 1)
      sb << hex.slice(b & 15, 1)
    i += 1
  sb.to_s()

# Replace `#N` attribute group tags after `)` on a `define` header with explicit `alwaysinline` / `noinline`
-> lto_normalize_define_hdr(hdr_line, mod_attrs, force_internal)
  at = ll_index_outside_quotes(hdr_line, 64, 0)
  return hdr_line if at < 0
  lp = ll_index_outside_quotes(hdr_line, 40, at)
  return hdr_line if lp < 0
  rp = ll_matching_rparen(hdr_line, lp)
  pre = hdr_line.slice(0, at)
  sig = hdr_line.slice(at, rp - at + 1)
  post = hdr_line.slice(rp + 1, cinder_blen(hdr_line) - rp - 1)

  # Resolve `#N` attribute groups in `post`
  in_hint = nil
  if post.index("alwaysinline") != nil || pre.index("alwaysinline") != nil
    in_hint = :always
  elsif post.index("noinline") != nil || pre.index("noinline") != nil
    in_hint = :never
  else
    hi = post.index("#")
    while hi != nil
      hend = hi + 1
      while hend < post.size() && post.byte_at(hend) >= 48 && post.byte_at(hend) <= 57
        hend += 1
      if hend > hi + 1
        ag = mod_attrs[post.slice(hi, hend - hi)]
        in_hint = ag if ag != nil
      hi = post.index("#", hend)

  # Strip `#N` tokens and `local_unnamed_addr` / `unnamed_addr` from `post`
  post_clean = StringBuffer(64)
  ptoks = post.split(" ")
  pi = 0
  while pi < ptoks.size()
    tk = ptoks[pi].strip()
    if tk != "" && tk != "{" && !tk.starts_with?("#") && tk != "local_unnamed_addr" && tk != "unnamed_addr" && tk != "ssp" && !tk.starts_with?("uwtable") && !tk.starts_with?("memory(")
      post_clean << " "
      post_clean << tk
    pi += 1
  if in_hint == :always && post.index("alwaysinline") == nil && pre.index("alwaysinline") == nil
    post_clean << " alwaysinline"
  elsif in_hint == :never && post.index("noinline") == nil && pre.index("noinline") == nil
    post_clean << " noinline"
  post_clean << " {"

  # Normalize `pre` linkage (`dso_local`, `weak_odr`, `linkonce_odr`, optional `force_internal`)
  is_already_int = pre.index(" internal ") != nil || pre.index(" private ") != nil
  if force_internal && !is_already_int && pre.index("weak") == nil && pre.index("linkonce") == nil
    # Insert `internal ` right after `define `
    pre = "define internal " + pre.slice(7, pre.size() - 7).strip() + " "
  pre + sig + post_clean.to_s()

-> lto_is_runtime_callback_seam?(sym_nm)
  return true if sym_nm == "main"
  return true if sym_nm.starts_with?("__w_bigint_") && (sym_nm.ends_with?("_src") || sym_nm.ends_with?("_complete"))
  return true if sym_nm == "__w_fn_sym_strtab" || sym_nm == "__w_fn_sym_compact" || sym_nm == "__w_ic_site_sparse" || sym_nm == "__w_call_site_count"
  false

# Check whether secondary module `@main` has user initialization statements beyond standard boilerplate
-> lto_main_has_user_body?(body_str)
  lines = body_str.split("\n")
  i = 0
  while i < lines.size()
    ln = lines[i].strip()
    if ln != "" && !ln.ends_with?(":") && !ln.starts_with?(";") && ln != "}" && !ln.starts_with?("ret ")
      if ln.index("@w_preflight(") == nil && ln.index("@w_slab_init_static(") == nil &&
         ln.index("@w_slab_freeze_safe(") == nil && ln.index("@w_scheduler_run(") == nil &&
         !ln.starts_with?("%t") || ln.index("call ") != nil
        if ln.index("@w_preflight(") == nil && ln.index("@w_slab_init_static(") == nil &&
           ln.index("@w_slab_freeze_safe(") == nil && ln.index("@w_scheduler_run(") == nil
          return true
    i += 1
  false

# Merge `ir_modules` (`Array` of `.ll` strings) into a single whole-program `.ll` module!
# Performs cross-file symbol resolution, local alpha-renaming, `@__static_slab` fusion,
# `#N` attribute group normalization, whole-program internalization (`lto-internalize`),
# and dead private/internal global elimination (`lto-dce`).
-> cinder_lto_merge_modules(ir_modules, is_exe_link = true, opt_cfg = nil, external_refs = nil)
  return "" if ir_modules == nil || ir_modules.size() == 0
  cfg = opt_cfg != nil ? opt_cfg : CinderOptConfig.new(2)
  do_internalize = is_exe_link && !cfg.debug && cfg.pass_enabled?("lto-internalize") && env("TUNGSTEN_DYNAMIC_EXPORTS") != "1"
  do_gdce = !cfg.debug && cfg.pass_enabled?("lto-dce")

  # Single-module non-exe fast path
  if ir_modules.size() == 1 && !do_internalize
    return ir_modules[0]

  n_mods = ir_modules.size()
  merged_slab = ByteBuf.new(1024)
  merged_slab_slots = 0
  mod_slab_delta = Array.new(n_mods, 0)
  mod_attrs_list = []
  mod_renames = []
  used_syms_all = {}
  ext_refs_map = {}
  if external_refs != nil
    external_refs.keys.each ->(ek)
      ext_refs_map[ek] = true
  defined_globals = {}
  defined_fns = {}
  declared_fns = {}

  # Pass 1: Scan each module's `attributes`, `@__static_slab`, `@llvm.used`, and `internal`/`private` symbols!
  mi = 0
  while mi < n_mods
    src = ir_modules[mi]
    src = src + "                        " if cinder_blen(src) <= 16
    src_ptr = cinder_heap_str_ptr(wvalue_bits(src) ## i64)
    limit = cinder_blen(src)
    attrs = {}
    ren = {}
    pos = 0
    while pos < limit
      nl = ll_find_nl(src_ptr, pos, limit)
      llen = nl - pos
      llen -= 1 if llen > 0 && src.byte_at(pos + llen - 1) == 13
      b0 = llen > 0 ? src.byte_at(pos) : 0
      if llen == 0 || b0 == 59 || b0 == 33
        pos = nl + 1
        next
      line = src.slice(pos, llen).strip()
      if line.starts_with?("attributes ")
        eq_a = line.index("=")
        if eq_a != nil
          tag = line.slice(11, eq_a - 11).strip()
          if line.index("alwaysinline") != nil
            attrs[tag] = :always
          elsif line.index("noinline") != nil
            attrs[tag] = :never
        pos = nl + 1
        next
      if line.starts_with?("define ")
        at = ll_index_outside_quotes(line, 64, 0)
        lp = at >= 0 ? ll_index_outside_quotes(line, 40, at) : -1
        fn_nm = ll_clean_sym(line.slice(at, lp - at))
        pre = line.slice(0, at)
        is_loc = pre.index(" internal ") != nil || pre.index(" private ") != nil
        if mi > 0 && is_loc
          ren[fn_nm] = "__clto.m" + mi.to_s() + "." + fn_nm
        body_end = ll_find_fn_end(src_ptr, pos, limit)
        pos = body_end
        next
      if line.starts_with?("@")
        eq = ll_index_outside_quotes(line, 61, 0)
        if eq > 0
          sym_nm = ll_clean_sym(line.slice(0, eq).strip())
          rhs = line.slice(eq + 1, cinder_blen(line) - eq - 1).strip()
          q0_i = rhs.index("\"")
          br0_i = rhs.index("\[")
          hlim = cinder_blen(rhs)
          hlim = q0_i if q0_i != nil && q0_i < hlim
          hlim = br0_i if br0_i != nil && br0_i < hlim
          rhs_hdr = rhs.slice(0, hlim)

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
                  used_syms_all[unm] = true
                ii += 1
          elsif sym_nm == "__static_slab" && rhs.index("] c\"") != nil
            # Decode `@__static_slab` bytes and fuse into `merged_slab`!
            raw_line = src.slice(pos, llen)
            eq_raw = ll_index_outside_quotes(raw_line, 61, 0)
            rc_idx = raw_line.index("] c\"", eq_raw >= 0 ? eq_raw : 0)
            lb = rhs.index("\[")
            xi = rhs.index(" x ")
            n_exp = rhs.slice(lb + 1, xi - lb - 1).strip().to_i()
            tmp_b = ByteBuf.new(n_exp + 16)
            tmp_b.reserve(n_exp + 8)
            ndec = ll_decode_cbytes(tmp_b.raw_ptr(), src_ptr, pos + rc_idx + 4, pos + llen)
            tmp_b.len = ndec
            if ndec < n_exp
              tmp_b.put_zeros(n_exp - ndec)
            slots_here = n_exp / 32
            if slots_here > 1
              if merged_slab_slots == 0
                merged_slab.put_zeros(32)
                merged_slab_slots = 1
              mod_slab_delta[mi] = merged_slab_slots - 1
              payload_bytes = (slots_here - 1) * 32
              merged_slab.reserve(payload_bytes + 8)
              cinder_raw_memcpy(merged_slab.raw_ptr() + merged_slab.len, tmp_b.raw_ptr() + 32, payload_bytes)
              merged_slab.len += payload_bytes
              merged_slab_slots += (slots_here - 1)
          elsif mi > 0 && (rhs_hdr.starts_with?("private ") || rhs_hdr.starts_with?("internal "))
            if sym_nm == ".ic"
              ren[sym_nm] = ".ic.m" + mi.to_s()
            else
              ren[sym_nm] = "__clto.m" + mi.to_s() + "." + sym_nm
          # Handle multiline `[ ... \n]` globals
          if rhs.ends_with?("\[")
            end_br = pos + llen
            while end_br < limit
              nl2 = ll_find_nl(src_ptr, end_br + 1, limit)
              if nl2 > end_br + 1 && src.byte_at(end_br + 1) == 93
                nl = nl2
                break
              end_br = nl2
      pos = nl + 1
    mod_attrs_list.push(attrs)
    mod_renames.push(ren)
    mi += 1

  # Pass 2: Collect top-level declarations, globals (recording private/internal candidates for `lto-dce`),
  # module asm, aliases, and normalized function definitions across all modules!
  type_lines = []
  seen_types = {}
  mod_asm_out = []
  decl_lines = []
  global_entries = []   # [sym_nm, is_local_bool, rendered_text]
  alias_lines = []
  fn_chunks = []        # [fn_nm, rendered_fn_text]
  sec_inits = []        # `@__clto_init_m<k>` names needing invocation from `@main`

  mi = 0
  while mi < n_mods
    src = ir_modules[mi]
    src = src + "                        " if cinder_blen(src) <= 16
    src_ptr = cinder_heap_str_ptr(wvalue_bits(src) ## i64)
    limit = cinder_blen(src)
    attrs = mod_attrs_list[mi]
    ren = mod_renames[mi]
    sdelta = mod_slab_delta[mi]

    pos = 0
    while pos < limit
      nl = ll_find_nl(src_ptr, pos, limit)
      llen = nl - pos
      llen -= 1 if llen > 0 && src.byte_at(pos + llen - 1) == 13
      b0 = llen > 0 ? src.byte_at(pos) : 0
      if llen == 0 || b0 == 59 || b0 == 33
        pos = nl + 1
        next
      raw_line = src.slice(pos, llen)
      line = raw_line.strip()
      if line == "" || line.starts_with?("target ") || line.starts_with?("source_filename") || line.starts_with?("attributes ")
        pos = nl + 1
        next

      if line.starts_with?("%")
        eq_t = line.index(" = type ")
        if eq_t != nil
          tnm = line.slice(0, eq_t).strip()
          if seen_types[tnm] == nil
            seen_types[tnm] = true
            type_lines.push(line)
        pos = nl + 1
        next

      if line.starts_with?("module asm ")
        mod_asm_out.push(line)
        pos = nl + 1
        next

      if line.starts_with?("declare ")
        at = ll_index_outside_quotes(line, 64, 0)
        lp = at >= 0 ? ll_index_outside_quotes(line, 40, at) : -1
        if at >= 0 && lp > at
          dnm = ll_clean_sym(line.slice(at, lp - at))
          if declared_fns[dnm] == nil
            declared_fns[dnm] = line
            decl_lines.push([dnm, line])
        pos = nl + 1
        next

      if line.starts_with?("define ")
        at = ll_index_outside_quotes(line, 64, 0)
        lp = at >= 0 ? ll_index_outside_quotes(line, 40, at) : -1
        orig_fn = ll_clean_sym(line.slice(at, lp - at))
        body_start = nl + 1
        body_end = ll_find_fn_end(src_ptr, pos, limit)
        raw_body = src.slice(body_start, body_end - body_start)

        # Deduplicate secondary `@main` or duplicate Core seams (`@__w_bigint_*_src`)
        emit_this_fn = true
        cur_ren = ren
        target_fn_nm = ren[orig_fn] != nil ? ren[orig_fn] : orig_fn

        if orig_fn == "main" && defined_fns["main"] == true
          if lto_main_has_user_body?(raw_body)
            init_nm = "__clto_init_m" + mi.to_s()
            target_fn_nm = init_nm
            line = "define internal i32 @" + init_nm + "() {"
            sec_inits.push(init_nm)
          else
            emit_this_fn = false
        elsif defined_fns[target_fn_nm] == true
          # Strong definition already emitted in an earlier LTO module (e.g. shared Core seam or weak stub)
          emit_this_fn = false

        if emit_this_fn
          defined_fns[target_fn_nm] = true
          rw_hdr = lto_rewrite_line_syms_and_slab(line, cur_ren, 0)
          force_int = do_internalize && !lto_is_runtime_callback_seam?(target_fn_nm) && used_syms_all[target_fn_nm] == nil && ext_refs_map[target_fn_nm] == nil
          norm_hdr = lto_normalize_define_hdr(rw_hdr, attrs, force_int)

          body_sb = StringBuffer((body_end - body_start) + 64)
          bpos = body_start
          while bpos < body_end
            bnl = ll_find_nl(src_ptr, bpos, body_end)
            bllen = bnl - bpos
            bllen -= 1 if bllen > 0 && src.byte_at(bpos + bllen - 1) == 13
            bln = src.slice(bpos, bllen)
            bstrip = bln.strip()
            # Rewrite `@w_slab_init_static(ptr @__static_slab, i32 <N>)` for fused slab!
            if bstrip.index("@w_slab_init_static(ptr @__static_slab") != nil
              if mi == 0 && merged_slab_slots > 0
                body_sb << "  call void @w_slab_init_static(ptr @__static_slab, i32 " + merged_slab_slots.to_s() + ")\n"
              elsif mi == 0
                body_sb << bln
                body_sb << "\n"
              # Elide duplicate `w_slab_init_static` in secondary modules!
            else
              body_sb << lto_rewrite_line_syms_and_slab(bln, cur_ren, sdelta)
              body_sb << "\n"
            bpos = bnl + 1
          fn_chunks.push([target_fn_nm, norm_hdr + "\n" + body_sb.to_s()])
        pos = body_end
        next

      if line.starts_with?("@")
        eq = ll_index_outside_quotes(line, 61, 0)
        if eq > 0
          orig_sym = ll_clean_sym(line.slice(0, eq).strip())
          rhs = line.slice(eq + 1, cinder_blen(line) - eq - 1).strip()
          q0_i = rhs.index("\"")
          br0_i = rhs.index("\[")
          hlim = cinder_blen(rhs)
          hlim = q0_i if q0_i != nil && q0_i < hlim
          hlim = br0_i if br0_i != nil && br0_i < hlim
          rhs_hdr = rhs.slice(0, hlim)

          # Advance `nl` across multiline `[ ... \n]` global initializers
          full_end = pos + llen
          if rhs.ends_with?("\[")
            end_br = full_end
            while end_br < limit
              nl2 = ll_find_nl(src_ptr, end_br + 1, limit)
              if nl2 > end_br + 1 && src.byte_at(end_br + 1) == 93
                nl = nl2
                full_end = nl2
                break
              end_br = nl2
          full_glob_txt = src.slice(pos, full_end - pos)

          if orig_sym != "llvm.used" && orig_sym != "llvm.compiler.used" && orig_sym != "__static_slab"
            target_sym = ren[orig_sym] != nil ? ren[orig_sym] : orig_sym
            if rhs_hdr.index("alias ") != nil
              if defined_globals[target_sym] == nil && defined_fns[target_sym] == nil
                defined_globals[target_sym] = true
                alias_lines.push(lto_rewrite_text_syms_and_slab(full_glob_txt, ren, 0))
            elsif rhs_hdr.starts_with?("external ")
              if defined_globals[target_sym] == nil
                defined_globals[target_sym] = :ext
                global_entries.push([target_sym, false, full_glob_txt, true])
            else
              if defined_globals[target_sym] != :def
                defined_globals[target_sym] = :def
                is_loc_g = rhs_hdr.starts_with?("private ") || rhs_hdr.starts_with?("internal ")
                rw_glob = lto_rewrite_text_syms_and_slab(full_glob_txt, ren, sdelta)
                global_entries.push([target_sym, is_loc_g, rw_glob, false])
      pos = nl + 1
    mi += 1

  # Inject calls to secondary module initializers (`@__clto_init_m<k>`) into `@main` if any exist!
  if sec_inits.size() > 0
    fi = 0
    while fi < fn_chunks.size()
      if fn_chunks[fi][0] == "main"
        mtxt = fn_chunks[fi][1]
        inj = StringBuffer(128)
        si = 0
        while si < sec_inits.size()
          inj << "  call i32 @" + sec_inits[si] + "()\n"
          si += 1
        fz_idx = mtxt.index("call i64 @w_slab_freeze_safe()")
        if fz_idx != nil
          nl_fz = mtxt.index("\n", fz_idx)
          fn_chunks[fi][1] = mtxt.slice(0, nl_fz + 1) + inj.to_s() + mtxt.slice(nl_fz + 1, mtxt.size() - nl_fz - 1)
        else
          eb_idx = mtxt.index("\n")
          nl_eb = mtxt.index("\n", eb_idx + 1)
          fn_chunks[fi][1] = mtxt.slice(0, nl_eb + 1) + inj.to_s() + mtxt.slice(nl_eb + 1, mtxt.size() - nl_eb - 1)
        break
      fi += 1

  # Build combined function text first so `lto-dce` can check which private/internal globals are referenced!
  fns_sb = StringBuffer(fn_chunks.size() * 256 + 1024)
  fi = 0
  while fi < fn_chunks.size()
    fns_sb << fn_chunks[fi][1]
    fns_sb << "\n"
    fi += 1
  all_fns_text = fns_sb.to_s()

  # Assemble final merged `.ll` module!
  out_sb = StringBuffer(cinder_blen(all_fns_text) + merged_slab.len * 2 + 4096)
  ti = 0
  while ti < type_lines.size()
    out_sb << type_lines[ti]
    out_sb << "\n"
    ti += 1
  mi = 0
  while mi < mod_asm_out.size()
    out_sb << mod_asm_out[mi]
    out_sb << "\n"
    mi += 1

  # Emit `declare` ONLY for symbols not defined in any merged LTO module!
  di = 0
  while di < decl_lines.size()
    dnm = decl_lines[di][0]
    if defined_fns[dnm] == nil && defined_globals[dnm] != :def
      out_sb << decl_lines[di][1]
      out_sb << "\n"
    di += 1

  # Emit unified `@__static_slab` if present!
  if merged_slab_slots > 0
    esc = lto_encode_llvm_cbytes(merged_slab, 0, merged_slab.len)
    out_sb << "@__static_slab = private constant \[" + merged_slab.len.to_s() + " x i8] c\"" + esc + "\", align 32\n"

  if ext_refs_map.size() > 0
    ek_arr = ext_refs_map.keys
    eki = 0
    while eki < ek_arr.size()
      ek = ek_arr[eki]
      used_syms_all[ek] = true if defined_fns[ek] == true || defined_globals[ek] == :def
      eki += 1

  # Compute root-reachable symbols for `lto-dce` across functions, `@llvm.used`, aliases, and exported globals!
  live_sym_refs = {}
  if do_gdce
    lto_collect_sym_refs(all_fns_text, false, live_sym_refs)
    uk = used_syms_all.keys
    uki = 0
    while uki < uk.size()
      live_sym_refs[uk[uki]] = true
      uki += 1
    ai_r = 0
    while ai_r < alias_lines.size()
      lto_collect_sym_refs(alias_lines[ai_r], true, live_sym_refs)
      ai_r += 1
    gi_r = 0
    while gi_r < global_entries.size()
      ge_r = global_entries[gi_r]
      gnm_r = ge_r[0]
      if !ge_r[3] && (!ge_r[1] || gnm_r == ".ic" || gnm_r.starts_with?(".ic.m"))
        lto_collect_sym_refs(ge_r[2], true, live_sym_refs)
      gi_r += 1
    # Propagate transitively through kept local globals (e.g. local table -> private string)
    kept_loc = {}
    changed_loc = true
    while changed_loc
      changed_loc = false
      gi_p = 0
      while gi_p < global_entries.size()
        ge_p = global_entries[gi_p]
        gnm_p = ge_p[0]
        if !ge_p[3] && ge_p[1] && kept_loc[gnm_p] == nil && live_sym_refs[gnm_p] == true
          kept_loc[gnm_p] = true
          lto_collect_sym_refs(ge_p[2], true, live_sym_refs)
          changed_loc = true
        gi_p += 1

  # Emit globals (dropping `external` declarations satisfied by a merged definition, and dead local globals under `lto-dce`)
  gi = 0
  while gi < global_entries.size()
    ge = global_entries[gi]
    gnm = ge[0]
    is_loc_g = ge[1]
    gtxt = ge[2]
    is_ext_decl = ge[3]
    if is_ext_decl && defined_globals[gnm] == :def
      gi += 1
      next
    if do_gdce && is_loc_g && gnm != ".ic" && !gnm.starts_with?(".ic.m") && live_sym_refs[gnm] == nil
      gi += 1
      next
    out_sb << gtxt
    out_sb << "\n"
    gi += 1

  # Emit `@llvm.used` if non-empty
  if used_syms_all.size() > 0
    u_keys = used_syms_all.keys
    u_parts = []
    ui = 0
    while ui < u_keys.size()
      u_parts.push("ptr " + lto_format_sym_ref(u_keys[ui]))
      ui += 1
    out_sb << "@llvm.used = appending global \[" + u_parts.size().to_s() + " x ptr] \[" + u_parts.join(", ") + "]\n"

  ai = 0
  while ai < alias_lines.size()
    out_sb << alias_lines[ai]
    out_sb << "\n"
    ai += 1

  out_sb << all_fns_text
  out_sb.to_s()

# ---- 3. Runtime Hot-Boundary Fat-LTO Module (`cinder-rt-lto-v1`) ----
#
# Provides exact `alwaysinline` LLVM IR definitions for the hot BigInt recycler & size-finisher
# boundary functions in `runtime/runtime.c` so `--cinder --lto` / `cinder compile -flto` inlines
# them directly into `.w` callers AND hoists `&w_bigint_pool_state` out of loops via LICM!

-> cinder_ll_needs_rt_hot_lto?(ll_text)
  return false if ll_text == nil
  return true if ll_text.index("_finish_raw(") != nil
  if cinder_host_os() != "macos"
    return ll_text.index("@w_bigint_alloc_hot") != nil || ll_text.index("@w_bigint_release_dead_raw") != nil
  false

-> cinder_emit_elf_tls_hot_lto_ir(sb)
  sb << "@w_bigint_pool_state = external thread_local global i64, align 8\n"
  sb << "declare i64 @w_bigint_alloc_hot_cold(i64)\n"
  sb << "declare void @w_bigint_release_dead_cold(i64)\n"
  sb << "declare void @w_bigint_displaced_cold(i64, i64)\n\n"

  # 1. `w_bigint_alloc_hot(i64 %cap)`: exact power-of-two hot-slot check `(hot_cap - req) <u req`
  sb << "define i64 @w_bigint_alloc_hot(i64 %cap) alwaysinline {\n"
  sb << "entry:\n"
  sb << "  %le0 = icmp sle i64 %cap, 0\n"
  sb << "  %req = select i1 %le0, i64 1, i64 %cap\n"
  sb << "  %pool = getelementptr i8, ptr @w_bigint_pool_state, i64 0\n"
  sb << "  %hw = load i64, ptr %pool, align 8\n"
  sb << "  %hcap = lshr i64 %hw, 48\n"
  sb << "  %diff = sub i64 %hcap, %req\n"
  sb << "  %hit = icmp ult i64 %diff, %req\n"
  sb << "  br i1 %hit, label %fast, label %slow\n"
  sb << "fast:\n"
  sb << "  store i64 0, ptr %pool, align 8\n"
  sb << "  %ptr = and i64 %hw, 281474976710655\n"
  sb << "  %boxed = or i64 %ptr, -1407374883553280\n"
  sb << "  ret i64 %boxed\n"
  sb << "slow:\n"
  sb << "  %cold = call i64 @w_bigint_alloc_hot_cold(i64 %cap)\n"
  sb << "  ret i64 %cold\n"
  sb << "}\n\n"

  # 2. Exact power-of-two `w_bigint_alloc_hot<N>_raw()` (`4, 8, 16, 32_exact, 64, 128`) + `32_raw`
  exact_caps = [["4_raw", 4], ["8_raw", 8], ["16_raw", 16], ["32_exact_raw", 32], ["64_raw", 64], ["128_raw", 128]]
  ei = 0
  while ei < exact_caps.size()
    nm_suf = exact_caps[ei][0]
    ecap = exact_caps[ei][1]
    cap_hi = ecap << 48
    sb << "define i64 @w_bigint_alloc_hot" + nm_suf + "() alwaysinline {\n"
    sb << "entry:\n"
    sb << "  %pool = getelementptr i8, ptr @w_bigint_pool_state, i64 0\n"
    sb << "  %hw = load i64, ptr %pool, align 8\n"
    sb << "  %dec = xor i64 %hw, " + cap_hi.to_s() + "\n"
    sb << "  %hi = lshr i64 %dec, 48\n"
    sb << "  %hit = icmp eq i64 %hi, 0\n"
    sb << "  br i1 %hit, label %fast, label %slow\n"
    sb << "fast:\n"
    sb << "  store i64 0, ptr %pool, align 8\n"
    sb << "  %boxed = or i64 %dec, -1407374883553280\n"
    sb << "  ret i64 %boxed\n"
    sb << "slow:\n"
    sb << "  %cold = call i64 @w_bigint_alloc_hot_cold(i64 " + ecap.to_s() + ")\n"
    sb << "  ret i64 %cold\n"
    sb << "}\n\n"
    ei += 1

  sb << "define i64 @w_bigint_alloc_hot32_raw() alwaysinline {\n"
  sb << "entry:\n"
  sb << "  %r = call i64 @w_bigint_alloc_hot(i64 32)\n"
  sb << "  ret i64 %r\n"
  sb << "}\n\n"

  # 3. `w_bigint_release_dead_raw(i64 %v)`: swap-form hot-slot handoff matching `bigint_release_if_live`
  sb << "define i64 @w_bigint_release_dead_raw(i64 %v) alwaysinline {\n"
  sb << "entry:\n"
  sb << "  %is_nil = icmp eq i64 %v, 0\n"
  sb << "  br i1 %is_nil, label %done, label %chk_hdr\n"
  sb << "chk_hdr:\n"
  sb << "  %ptr_i = and i64 %v, 140737488355312\n"
  sb << "  %b = inttoptr i64 %ptr_i to ptr\n"
  sb << "  %h64 = load i64, ptr %b, align 8\n"
  sb << "  %h16 = and i64 %h64, 65535\n"
  sb << "  %ok_h = icmp eq i64 %h16, 11\n"
  sb << "  br i1 %ok_h, label %chk_cap, label %cold\n"
  sb << "chk_cap:\n"
  sb << "  %cap_p = getelementptr i8, ptr %b, i64 8\n"
  sb << "  %cap32 = load i32, ptr %cap_p, align 8\n"
  sb << "  %cap64 = zext i32 %cap32 to i64\n"
  sb << "  %ok_c = icmp ule i64 %cap64, 16384\n"
  sb << "  br i1 %ok_c, label %park, label %cold\n"
  sb << "park:\n"
  sb << "  %pool = getelementptr i8, ptr @w_bigint_pool_state, i64 0\n"
  sb << "  %disp = load i64, ptr %pool, align 8\n"
  sb << "  %csh = shl i64 %cap64, 48\n"
  sb << "  %enc = or i64 %ptr_i, %csh\n"
  sb << "  store i64 %enc, ptr %pool, align 8\n"
  sb << "  %has_d = icmp ne i64 %disp, 0\n"
  sb << "  br i1 %has_d, label %rescue, label %done\n"
  sb << "rescue:\n"
  sb << "  call void @w_bigint_displaced_cold(i64 %disp, i64 %ptr_i)\n"
  sb << "  ret i64 0\n"
  sb << "cold:\n"
  sb << "  call void @w_bigint_release_dead_cold(i64 %v)\n"
  sb << "  ret i64 0\n"
  sb << "done:\n"
  sb << "  ret i64 0\n"
  sb << "}\n\n"
  nil

-> cinder_runtime_hot_lto_ir
  sb = StringBuffer(8192)
  cinder_emit_elf_tls_hot_lto_ir(sb) if cinder_host_os() != "macos"

  # 4. Direct 2-arg size-publication finishers `(i64 %v, i64 %size) -> %v`
  two_arg_finishers = [
    "sqr2", "sqr3", "sqr4", "sqr5", "sqr6", "sqr7", "sqr8",
    "mul2", "mul3", "mul4",
    "mul1_2", "mul1_3", "mul1_4", "mul1_5", "mul1_6", "mul1_7", "mul1_8"
  ]
  fi = 0
  while fi < two_arg_finishers.size()
    fnm = "w_bigint_" + two_arg_finishers[fi] + "_finish_raw"
    sb << "define i64 @" + fnm + "(i64 %v, i64 %sz) alwaysinline {\n"
    sb << "entry:\n"
    sb << "  %ptr_i = and i64 %v, 140737488355312\n"
    sb << "  %sp_i = add i64 %ptr_i, 4\n"
    sb << "  %sp = inttoptr i64 %sp_i to ptr\n"
    sb << "  %sz32 = trunc i64 %sz to i32\n"
    sb << "  store i32 %sz32, ptr %sp, align 4\n"
    sb << "  ret i64 %v\n"
    sb << "}\n\n"
    fi += 1

  # 5. Direct 1-arg top-limb normalization finishers `(i64 %v) -> %v` (`size = W - (limbs[W-1] == 0)`)
  one_arg_finishers = [
    ["mul5", 10], ["mul6", 12], ["mul7", 14], ["mul8", 16],
    ["mul12", 24], ["mul15", 30], ["mul16", 32], ["mul17", 34], ["mul21", 42], ["mul24", 48],
    ["sqr16", 32]
  ]
  oi = 0
  while oi < one_arg_finishers.size()
    fnm = "w_bigint_" + one_arg_finishers[oi][0] + "_finish_raw"
    wlen = one_arg_finishers[oi][1]
    top_byte_off = 16 + (wlen - 1) * 8
    sb << "define i64 @" + fnm + "(i64 %v) alwaysinline {\n"
    sb << "entry:\n"
    sb << "  %ptr_i = and i64 %v, 140737488355312\n"
    sb << "  %tp_i = add i64 %ptr_i, " + top_byte_off.to_s() + "\n"
    sb << "  %tp = inttoptr i64 %tp_i to ptr\n"
    sb << "  %top = load i64, ptr %tp, align 8\n"
    sb << "  %isz = icmp eq i64 %top, 0\n"
    sb << "  %dec = zext i1 %isz to i64\n"
    sb << "  %sz = sub i64 " + wlen.to_s() + ", %dec\n"
    sb << "  %sp_i = add i64 %ptr_i, 4\n"
    sb << "  %sp = inttoptr i64 %sp_i to ptr\n"
    sb << "  %sz32 = trunc i64 %sz to i32\n"
    sb << "  store i32 %sz32, ptr %sp, align 4\n"
    sb << "  ret i64 %v\n"
    sb << "}\n\n"
    oi += 1

  # 6. `mul1_<N>_finish_raw(i64 %v, i64 %carry)`: `r->limbs[N] = carry; r->size = N + (carry != 0); return v;`
  mul1_wide = [16, 24, 32, 40, 48, 64]
  mi = 0
  while mi < mul1_wide.size()
    wn = mul1_wide[mi]
    fnm = "w_bigint_mul1_" + wn.to_s() + "_finish_raw"
    c_off = 16 + wn * 8
    sb << "define i64 @" + fnm + "(i64 %v, i64 %carry) alwaysinline {\n"
    sb << "entry:\n"
    sb << "  %ptr_i = and i64 %v, 140737488355312\n"
    sb << "  %cp_i = add i64 %ptr_i, " + c_off.to_s() + "\n"
    sb << "  %cp = inttoptr i64 %cp_i to ptr\n"
    sb << "  store i64 %carry, ptr %cp, align 8\n"
    sb << "  %nz = icmp ne i64 %carry, 0\n"
    sb << "  %inc = zext i1 %nz to i64\n"
    sb << "  %sz = add i64 " + wn.to_s() + ", %inc\n"
    sb << "  %sp_i = add i64 %ptr_i, 4\n"
    sb << "  %sp = inttoptr i64 %sp_i to ptr\n"
    sb << "  %sz32 = trunc i64 %sz to i32\n"
    sb << "  store i32 %sz32, ptr %sp, align 4\n"
    sb << "  ret i64 %v\n"
    sb << "}\n\n"
    mi += 1

  sb.to_s()
