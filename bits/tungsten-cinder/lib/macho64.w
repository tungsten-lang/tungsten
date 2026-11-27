# cinder/macho64 — Pure-Tungsten 64-bit Mach-O relocatable object (.o) writer (ARM64).
#
# Emits valid Darwin `MH_OBJECT` (`CPU_TYPE_ARM64`) files directly from ByteBufs,
# including:
#   - `__TEXT,__text` (pure executable instructions + branch/page/GOT/TLV relocations)
#   - `__DATA,__const` (read-only constants, string slabs, and relocated pointer tables)
#   - `__DATA,__data` (initialized mutable globals and relocated pointer tables)
#   - `__DATA,__bss` (`S_ZEROFILL` zero-initialized mutable globals)
#   - `__DATA,__thread_bss` (`S_THREAD_LOCAL_ZEROFILL`) & `__DATA,__thread_vars`
#     (`S_THREAD_LOCAL_VARIABLES` 24-byte `_tlv_bootstrap` descriptors for TLS!)
#   - `LC_SEGMENT_64`, `LC_BUILD_VERSION`, `LC_SYMTAB`, `LC_DYSYMTAB` with exact
#     local / external-defined / undefined symbol table partitioning for `ld64`.

use ./buf
use ./a64

# Logical section IDs used by callers before final Mach-O section numbering
MSEC_NONE  = 0
MSEC_TEXT  = 1
MSEC_CONST = 2
MSEC_DATA  = 3
MSEC_BSS   = 4
MSEC_TBSS  = 5
MSEC_TVARS = 6

# Symbol bindings
MSYM_LOCAL  = 0
MSYM_GLOBAL = 1
MSYM_HIDDEN = 2
MSYM_UNDEF  = 3

# Mach-O ARM64 relocation types (<mach-o/arm64/reloc.h>)
MACHO_ARM64_RELOC_UNSIGNED          = 0
MACHO_ARM64_RELOC_BRANCH26          = 2
MACHO_ARM64_RELOC_PAGE21            = 3
MACHO_ARM64_RELOC_PAGEOFF12         = 4
MACHO_ARM64_RELOC_GOT_LOAD_PAGE21   = 5
MACHO_ARM64_RELOC_GOT_LOAD_PAGEOFF12 = 6
MACHO_ARM64_RELOC_TLVP_LOAD_PAGE21  = 8
MACHO_ARM64_RELOC_TLVP_LOAD_PAGEOFF12 = 9
MACHO_ARM64_RELOC_ADDEND            = 10

-> macho_mangle(sym)
  # Prefix `_` as required by Darwin C ABI.
  "_" + sym

-> macho_put_pad16(buf, s)
  n = cinder_blen(s)
  if n >= 16
    buf.put_ascii(s.slice(0, 16))
  else
    buf.put_ascii(s)
    buf.put_zeros(16 - n)
  nil

-> macho_align_up(val, pow2)
  (val + (pow2 - 1)) & (0 - pow2)

+ MachO64Writer
  rw :text, :rodata, :data
  rw :bss_size, :tbss_size
  rw :sym_names, :sym_bind, :sym_sec, :sym_off, :sym_no_dead_strip, :sym_map
  rw :tls_names, :tls_tbss_off, :tls_sizes
  rw :text_rel_off, :text_rel_sym, :text_rel_kind, :text_rel_add
  rw :const_rel_off, :const_rel_sym, :const_rel_add
  rw :data_rel_off, :data_rel_sym, :data_rel_add

  -> new
    @text = ByteBuf.new(65536)
    @rodata = ByteBuf.new(65536)
    @data = ByteBuf.new(4096)
    @bss_size = 0
    @tbss_size = 0

    @sym_names = []
    @sym_bind = []
    @sym_sec = []
    @sym_off = []
    @sym_no_dead_strip = []
    @sym_map = {}

    @tls_names = []
    @tls_tbss_off = []
    @tls_sizes = []

    @text_rel_off = []
    @text_rel_sym = []
    @text_rel_kind = []
    @text_rel_add = []

    @const_rel_off = []
    @const_rel_sym = []
    @const_rel_add = []

    @data_rel_off = []
    @data_rel_sym = []
    @data_rel_add = []

  -> ensure_sym(mangled_name)
    idx = @sym_map[mangled_name]
    return idx if idx != nil
    idx = @sym_names.size()
    @sym_names.push(mangled_name)
    @sym_bind.push(MSYM_UNDEF)
    @sym_sec.push(MSEC_NONE)
    @sym_off.push(0)
    @sym_no_dead_strip.push(false)
    @sym_map[mangled_name] = idx
    idx

  -> define_sym_raw(mangled_name, sec_id, off, binding = MSYM_LOCAL, no_dead_strip = false)
    idx = ensure_sym(mangled_name)
    @sym_bind[idx] = binding
    @sym_sec[idx] = sec_id
    @sym_off[idx] = off
    @sym_no_dead_strip[idx] = true if no_dead_strip
    idx

  -> define_sym(ir_name, sec_id, off, binding = MSYM_LOCAL, no_dead_strip = false)
    define_sym_raw(macho_mangle(ir_name), sec_id, off, binding, no_dead_strip)

  -> mark_no_dead_strip(ir_name)
    idx = ensure_sym(macho_mangle(ir_name))
    @sym_no_dead_strip[idx] = true
    nil

  -> alloc_bss(ir_name, size, align_pow2 = 8, binding = MSYM_LOCAL)
    @bss_size = macho_align_up(@bss_size, align_pow2)
    off = @bss_size
    sz = size > 0 ? size : 1
    @bss_size += sz
    define_sym(ir_name, MSEC_BSS, off, binding)
    off

  # Define a zero-initialized thread-local variable: reserves `size` bytes in `__thread_bss`
  # and registers a 24-byte descriptor `{ __tlv_bootstrap, 0, sym$tlv$init }` in `__thread_vars`!
  -> alloc_tls_bss(ir_name, size, align_pow2 = 8, binding = MSYM_LOCAL)
    @tbss_size = macho_align_up(@tbss_size, align_pow2)
    tb_off = @tbss_size
    sz = size > 0 ? size : 1
    @tbss_size += sz
    mangled = macho_mangle(ir_name)
    init_sym = mangled + "$tlv$init"
    define_sym_raw(init_sym, MSEC_TBSS, tb_off, MSYM_LOCAL)
    tv_off = @tls_names.size() * 24
    define_sym_raw(mangled, MSEC_TVARS, tv_off, binding)
    @tls_names.push(mangled)
    @tls_tbss_off.push(tb_off)
    @tls_sizes.push(sz)
    ensure_sym("__tlv_bootstrap")
    tv_off

  -> add_text_reloc_raw(off, mangled_sym, kind, addend = 0)
    ensure_sym(mangled_sym)
    @text_rel_off.push(off)
    @text_rel_sym.push(mangled_sym)
    @text_rel_kind.push(kind)
    @text_rel_add.push(addend)
    nil

  -> add_text_reloc(off, ir_sym, kind, addend = 0)
    add_text_reloc_raw(off, macho_mangle(ir_sym), kind, addend)

  -> add_const_ptr_reloc(off, ir_sym, addend = 0)
    m = macho_mangle(ir_sym)
    ensure_sym(m)
    @const_rel_off.push(off)
    @const_rel_sym.push(m)
    @const_rel_add.push(addend)
    nil

  -> add_data_ptr_reloc(off, ir_sym, addend = 0)
    m = macho_mangle(ir_sym)
    ensure_sym(m)
    @data_rel_off.push(off)
    @data_rel_sym.push(m)
    @data_rel_add.push(addend)
    nil

  -> emit_reloc_entry(out, r_addr, sym_num, pcrel, length_log2, is_ext, r_type)
    out.put_u32_le(r_addr)
    info = (sym_num & 0x00FFFFFF) | ((pcrel & 1) << 24) | ((length_log2 & 3) << 25) | ((is_ext & 1) << 27) | ((r_type & 15) << 28)
    out.put_u32_le(info)
    nil

  -> map_crel_type(kind)
    return [MACHO_ARM64_RELOC_BRANCH26, 1, 2]           if kind == CREL_A64_BRANCH26
    return [MACHO_ARM64_RELOC_PAGE21, 1, 2]             if kind == CREL_A64_PAGE21
    return [MACHO_ARM64_RELOC_PAGEOFF12, 0, 2]          if kind == CREL_A64_PAGEOFF12
    return [MACHO_ARM64_RELOC_GOT_LOAD_PAGE21, 1, 2]    if kind == CREL_A64_GOT_PAGE21
    return [MACHO_ARM64_RELOC_GOT_LOAD_PAGEOFF12, 0, 2] if kind == CREL_A64_GOT_PAGEOFF12
    return [MACHO_ARM64_RELOC_TLVP_LOAD_PAGE21, 1, 2]   if kind == CREL_A64_TLVP_PAGE21
    return [MACHO_ARM64_RELOC_TLVP_LOAD_PAGEOFF12, 0, 2] if kind == CREL_A64_TLVP_PAGEOFF12
    [MACHO_ARM64_RELOC_UNSIGNED, 0, 3]

  -> build_bytes
    # Align section payloads cleanly
    @text.align_to(8, 0)
    @rodata.align_to(8, 0)
    @data.align_to(8, 0)
    @bss_size = macho_align_up(@bss_size, 8)
    @tbss_size = macho_align_up(@tbss_size, 8)

    # Synthesize `__thread_vars` payload (24 zero bytes per TLS var; relocs point to __tlv_bootstrap & init)
    tvars_buf = ByteBuf.new(@tls_names.size() * 24 + 16)
    tvars_buf.put_zeros(@tls_names.size() * 24)

    has_tls = @tls_names.size() > 0

    # Assign 1-based Mach-O section indices & virtual section addresses:
    #   1: __TEXT,__text
    #   2: __DATA,__const
    #   3: __DATA,__data
    #   4: __DATA,__bss          (zerofill)
    #   5: __DATA,__thread_bss   (optional zerofill)
    #   6: __DATA,__thread_vars  (optional file-backed)
    nsects = has_tls ? 6 : 4
    sec_num = Array.new(7, 0)
    sec_num[MSEC_TEXT]  = 1
    sec_num[MSEC_CONST] = 2
    sec_num[MSEC_DATA]  = 3
    sec_num[MSEC_BSS]   = 4
    if has_tls
      sec_num[MSEC_TBSS]  = 5
      sec_num[MSEC_TVARS] = 6

    # Header (32) + LC_SEGMENT_64 (72 + nsects*80) + LC_BUILD_VERSION (24) + LC_SYMTAB (24) + LC_DYSYMTAB (80)
    seg_cmd_size = 72 + nsects * 80
    sizeofcmds = seg_cmd_size + 24 + 24 + 80
    hdr_end = macho_align_up(32 + sizeofcmds, 64)

    # Compute virtual addresses (`addr` in MH_OBJECT is cumulative across sections; file-backed first, zerofill after!)
    cur_vaddr = 0
    cur_foff = hdr_end

    text_vaddr = cur_vaddr
    text_foff = cur_foff
    cur_vaddr = macho_align_up(cur_vaddr + @text.len, 16)
    cur_foff = macho_align_up(cur_foff + @text.len, 16)

    const_vaddr = cur_vaddr
    const_foff = cur_foff
    cur_vaddr = macho_align_up(cur_vaddr + @rodata.len, 16)
    cur_foff = macho_align_up(cur_foff + @rodata.len, 16)

    data_vaddr = cur_vaddr
    data_foff = cur_foff
    cur_vaddr = macho_align_up(cur_vaddr + @data.len, 16)
    cur_foff = macho_align_up(cur_foff + @data.len, 16)

    tvars_vaddr = cur_vaddr
    tvars_foff = cur_foff
    if has_tls
      cur_vaddr = macho_align_up(cur_vaddr + tvars_buf.len, 16)
      cur_foff = macho_align_up(cur_foff + tvars_buf.len, 16)

    seg_filesize = cur_foff - hdr_end

    bss_vaddr = cur_vaddr
    cur_vaddr = macho_align_up(cur_vaddr + @bss_size, 16)

    tbss_vaddr = cur_vaddr
    if has_tls
      cur_vaddr = macho_align_up(cur_vaddr + @tbss_size, 16)

    seg_vmsize = cur_vaddr

    sec_vaddr = Array.new(7, 0)
    sec_vaddr[MSEC_TEXT]  = text_vaddr
    sec_vaddr[MSEC_CONST] = const_vaddr
    sec_vaddr[MSEC_DATA]  = data_vaddr
    sec_vaddr[MSEC_BSS]   = bss_vaddr
    sec_vaddr[MSEC_TBSS]  = tbss_vaddr
    sec_vaddr[MSEC_TVARS] = tvars_vaddr

    # Partition symbols into [locals, extdefs, undefs] and build final mangled_name -> final_sym_index map!
    locals = []
    extdefs = []
    undefs = []
    ns = @sym_names.size()
    i = 0
    while i < ns
      b = @sym_bind[i]
      if @sym_sec[i] == MSEC_NONE || b == MSYM_UNDEF
        undefs.push(i)
      elsif b == MSYM_LOCAL
        locals.push(i)
      else
        extdefs.push(i)
      i += 1

    ordered = []
    i = 0
    while i < locals.size()
      ordered.push(locals[i]); i += 1
    i = 0
    while i < extdefs.size()
      ordered.push(extdefs[i]); i += 1
    i = 0
    while i < undefs.size()
      ordered.push(undefs[i]); i += 1

    final_idx = {}
    strtab = ByteBuf.new(ns * 24 + 16)
    strtab.put_u8(0)
    symtab_buf = ByteBuf.new(ns * 16 + 16)

    i = 0
    while i < ordered.size()
      orig = ordered[i]
      nm = @sym_names[orig]
      final_idx[nm] = i
      strx = strtab.put_cstr(nm)
      b = @sym_bind[orig]
      sid = @sym_sec[orig]
      ntype = 0x01
      nsect = 0
      nval = 0
      if sid != MSEC_NONE && b != MSYM_UNDEF
        nsect = sec_num[sid]
        nval = sec_vaddr[sid] + @sym_off[orig]
        if b == MSYM_LOCAL
          ntype = 0x0E
        elsif b == MSYM_HIDDEN
          ntype = 0x1F
        else
          ntype = 0x0F
      ndesc = @sym_no_dead_strip[orig] ? 0x0020 : 0
      symtab_buf.put_u32_le(strx)
      symtab_buf.put_u8(ntype)
      symtab_buf.put_u8(nsect)
      symtab_buf.put_u16_le(ndesc)
      symtab_buf.put_u64_le(nval)
      i += 1

    strtab.align_to(8, 0)

    # Encode section relocation buffers (Mach-O ld64 convention: reverse or forward order both valid; emit reverse like clang)
    text_rel_buf = ByteBuf.new(@text_rel_off.size() * 8 + 16)
    ri = @text_rel_off.size() - 1
    while ri >= 0
      roff = @text_rel_off[ri]
      snum = final_idx[@text_rel_sym[ri]]
      addv = @text_rel_add[ri]
      rk = map_crel_type(@text_rel_kind[ri])
      if addv != 0
        emit_reloc_entry(text_rel_buf, roff, addv & 0x00FFFFFF, 0, 2, 0, MACHO_ARM64_RELOC_ADDEND)
      emit_reloc_entry(text_rel_buf, roff, snum, rk[1], rk[2], 1, rk[0])
      ri -= 1
    n_text_rel = text_rel_buf.len >> 3

    const_rel_buf = ByteBuf.new(@const_rel_off.size() * 8 + 16)
    ri = @const_rel_off.size() - 1
    while ri >= 0
      roff = @const_rel_off[ri]
      snum = final_idx[@const_rel_sym[ri]]
      @rodata.patch_u64_le(roff, @const_rel_add[ri])
      emit_reloc_entry(const_rel_buf, roff, snum, 0, 3, 1, MACHO_ARM64_RELOC_UNSIGNED)
      ri -= 1
    n_const_rel = const_rel_buf.len >> 3

    data_rel_buf = ByteBuf.new(@data_rel_off.size() * 8 + 16)
    ri = @data_rel_off.size() - 1
    while ri >= 0
      roff = @data_rel_off[ri]
      snum = final_idx[@data_rel_sym[ri]]
      @data.patch_u64_le(roff, @data_rel_add[ri])
      emit_reloc_entry(data_rel_buf, roff, snum, 0, 3, 1, MACHO_ARM64_RELOC_UNSIGNED)
      ri -= 1
    n_data_rel = data_rel_buf.len >> 3

    tvars_rel_buf = ByteBuf.new(@tls_names.size() * 16 + 16)
    if has_tls
      boot_idx = final_idx["__tlv_bootstrap"]
      ti = @tls_names.size() - 1
      while ti >= 0
        base_off = ti * 24
        init_idx = final_idx[@tls_names[ti] + "$tlv$init"]
        emit_reloc_entry(tvars_rel_buf, base_off + 16, init_idx, 0, 3, 1, MACHO_ARM64_RELOC_UNSIGNED)
        emit_reloc_entry(tvars_rel_buf, base_off, boot_idx, 0, 3, 1, MACHO_ARM64_RELOC_UNSIGNED)
        ti -= 1
    n_tvars_rel = tvars_rel_buf.len >> 3

    # Compute file offsets for relocations, symtab, and strtab
    rel_cursor = cur_foff
    text_reloff = n_text_rel > 0 ? rel_cursor : 0
    rel_cursor += text_rel_buf.len
    const_reloff = n_const_rel > 0 ? rel_cursor : 0
    rel_cursor += const_rel_buf.len
    data_reloff = n_data_rel > 0 ? rel_cursor : 0
    rel_cursor += data_rel_buf.len
    tvars_reloff = n_tvars_rel > 0 ? rel_cursor : 0
    rel_cursor += tvars_rel_buf.len

    symoff = rel_cursor
    stroff = symoff + symtab_buf.len

    # Assemble complete Mach-O binary!
    out = ByteBuf.new(stroff + strtab.len + 64)

    # 1. mach_header_64 (32 bytes)
    out.put_u32_le(0xFEEDFACF)
    out.put_u32_le(0x0100000C)
    out.put_u32_le(0)
    out.put_u32_le(1)             # MH_OBJECT
    out.put_u32_le(4)             # ncmds
    out.put_u32_le(sizeofcmds)
    out.put_u32_le(0)             # flags
    out.put_u32_le(0)             # reserved

    # 2. LC_SEGMENT_64
    out.put_u32_le(0x19)
    out.put_u32_le(seg_cmd_size)
    macho_put_pad16(out, "")
    out.put_u64_le(0)             # vmaddr
    out.put_u64_le(seg_vmsize)
    out.put_u64_le(hdr_end)       # fileoff
    out.put_u64_le(seg_filesize)
    out.put_u32_le(7)             # maxprot
    out.put_u32_le(7)             # initprot
    out.put_u32_le(nsects)
    out.put_u32_le(0)

    # Section 1: __TEXT,__text (align 2^6 = 64 bytes for limb_kernels .balign 64!)
    macho_put_pad16(out, "__text")
    macho_put_pad16(out, "__TEXT")
    out.put_u64_le(text_vaddr)
    out.put_u64_le(@text.len)
    out.put_u32_le(text_foff)
    out.put_u32_le(6)
    out.put_u32_le(text_reloff)
    out.put_u32_le(n_text_rel)
    out.put_u32_le(0x80000400)
    out.put_u32_le(0); out.put_u32_le(0); out.put_u32_le(0)

    # Section 2: __DATA,__const
    macho_put_pad16(out, "__const")
    macho_put_pad16(out, "__DATA")
    out.put_u64_le(const_vaddr)
    out.put_u64_le(@rodata.len)
    out.put_u32_le(const_foff)
    out.put_u32_le(4)
    out.put_u32_le(const_reloff)
    out.put_u32_le(n_const_rel)
    out.put_u32_le(0)
    out.put_u32_le(0); out.put_u32_le(0); out.put_u32_le(0)

    # Section 3: __DATA,__data
    macho_put_pad16(out, "__data")
    macho_put_pad16(out, "__DATA")
    out.put_u64_le(data_vaddr)
    out.put_u64_le(@data.len)
    out.put_u32_le(data_foff)
    out.put_u32_le(4)
    out.put_u32_le(data_reloff)
    out.put_u32_le(n_data_rel)
    out.put_u32_le(0)
    out.put_u32_le(0); out.put_u32_le(0); out.put_u32_le(0)

    # Section 4: __DATA,__bss (S_ZEROFILL = 0x1)
    macho_put_pad16(out, "__bss")
    macho_put_pad16(out, "__DATA")
    out.put_u64_le(bss_vaddr)
    out.put_u64_le(@bss_size)
    out.put_u32_le(0)
    out.put_u32_le(4)
    out.put_u32_le(0)
    out.put_u32_le(0)
    out.put_u32_le(0x1)
    out.put_u32_le(0); out.put_u32_le(0); out.put_u32_le(0)

    if has_tls
      # Section 5: __DATA,__thread_bss (S_THREAD_LOCAL_ZEROFILL = 0x12)
      macho_put_pad16(out, "__thread_bss")
      macho_put_pad16(out, "__DATA")
      out.put_u64_le(tbss_vaddr)
      out.put_u64_le(@tbss_size)
      out.put_u32_le(0)
      out.put_u32_le(4)
      out.put_u32_le(0)
      out.put_u32_le(0)
      out.put_u32_le(0x12)
      out.put_u32_le(0); out.put_u32_le(0); out.put_u32_le(0)

      # Section 6: __DATA,__thread_vars (S_THREAD_LOCAL_VARIABLES = 0x13)
      macho_put_pad16(out, "__thread_vars")
      macho_put_pad16(out, "__DATA")
      out.put_u64_le(tvars_vaddr)
      out.put_u64_le(tvars_buf.len)
      out.put_u32_le(tvars_foff)
      out.put_u32_le(3)
      out.put_u32_le(tvars_reloff)
      out.put_u32_le(n_tvars_rel)
      out.put_u32_le(0x13)
      out.put_u32_le(0); out.put_u32_le(0); out.put_u32_le(0)

    # 3. LC_BUILD_VERSION (24 bytes, macOS 14.0)
    out.put_u32_le(0x32)
    out.put_u32_le(24)
    out.put_u32_le(1)
    out.put_u32_le(0x000E0000)
    out.put_u32_le(0x000E0000)
    out.put_u32_le(0)

    # 4. LC_SYMTAB (24 bytes)
    out.put_u32_le(0x02)
    out.put_u32_le(24)
    out.put_u32_le(symoff)
    out.put_u32_le(ordered.size())
    out.put_u32_le(stroff)
    out.put_u32_le(strtab.len)

    # 5. LC_DYSYMTAB (80 bytes)
    out.put_u32_le(0x0B)
    out.put_u32_le(80)
    out.put_u32_le(0)
    out.put_u32_le(locals.size())
    out.put_u32_le(locals.size())
    out.put_u32_le(extdefs.size())
    out.put_u32_le(locals.size() + extdefs.size())
    out.put_u32_le(undefs.size())
    zi = 0
    while zi < 12
      out.put_u32_le(0)
      zi += 1

    # Pad to hdr_end and emit section contents
    out.align_to(64, 0)
    out.put_buf(@text)
    out.align_to(16, 0)
    out.put_buf(@rodata)
    out.align_to(16, 0)
    out.put_buf(@data)
    out.align_to(16, 0)
    if has_tls
      out.put_buf(tvars_buf)
      out.align_to(16, 0)

    # Emit relocations, symtab, strtab
    out.put_buf(text_rel_buf)
    out.put_buf(const_rel_buf)
    out.put_buf(data_rel_buf)
    out.put_buf(tvars_rel_buf) if has_tls
    out.put_buf(symtab_buf)
    out.put_buf(strtab)
    out

  -> write_file(path)
    build_bytes().write_file(path)
