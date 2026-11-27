# cinder/elf64 — Pure-Tungsten 64-bit ELF relocatable object (.o) writer (x86_64 & AArch64).
#
# Emits standards-compliant 64-bit little-endian `ET_REL` ELF objects directly from ByteBufs:
#   - `.text` (`SHT_PROGBITS`, `SHF_ALLOC | SHF_EXECINSTR`)
#   - `.rodata` (`SHT_PROGBITS`, `SHF_ALLOC`)
#   - `.data` (`SHT_PROGBITS`, `SHF_ALLOC | SHF_WRITE`)
#   - `.bss` (`SHT_NOBITS`, `SHF_ALLOC | SHF_WRITE`)
#   - `.tbss` (`SHT_NOBITS`, `SHF_ALLOC | SHF_WRITE | SHF_TLS`)
#   - `.note.GNU-stack` (`SHT_PROGBITS`, non-executable stack marker)
#   - `.symtab` (locals strictly before `sh_info` globals, `STV_HIDDEN` support)
#   - `.strtab`, `.shstrtab`, and `.rela.text` / `.rela.rodata` / `.rela.data` (`Elf64_Rela`).

use ./buf
use ./a64
use ./x64

ELF_EM_X86_64  = 62
ELF_EM_AARCH64 = 183

ESEC_UNDEF  = 0
ESEC_TEXT   = 1
ESEC_RODATA = 2
ESEC_DATA   = 3
ESEC_BSS    = 4
ESEC_TBSS   = 5

ESYM_LOCAL  = 0
ESYM_GLOBAL = 1
ESYM_HIDDEN = 2
ESYM_UNDEF  = 3

ESTT_NOTYPE = 0
ESTT_OBJECT = 1
ESTT_FUNC   = 2
ESTT_TLS    = 6

# ELF64 AArch64 relocation types (when emitting ELF64 for Linux ARM64!)
ELF_R_AARCH64_ABS64               = 257
ELF_R_AARCH64_ADR_PREL_PG_HI21    = 275
ELF_R_AARCH64_ADD_ABS_LO12_NC     = 277
ELF_R_AARCH64_CALL26              = 283
ELF_R_AARCH64_ADR_GOT_PAGE        = 311
ELF_R_AARCH64_LD64_GOT_LO12_NC    = 312

-> elf_align_up(val, pow2)
  (val + (pow2 - 1)) & (0 - pow2)

+ Elf64Writer
  rw :machine, :text, :rodata, :data, :lto_payload
  rw :bss_size, :tbss_size
  rw :sym_names, :sym_bind, :sym_type, :sym_sec, :sym_off, :sym_size, :sym_map
  rw :text_rel_off, :text_rel_sym, :text_rel_kind, :text_rel_add
  rw :ro_rel_off, :ro_rel_sym, :ro_rel_add
  rw :data_rel_off, :data_rel_sym, :data_rel_add

  -> new(@machine = 62)
    @text = ByteBuf.new(65536)
    @rodata = ByteBuf.new(65536)
    @data = ByteBuf.new(4096)
    @lto_payload = ByteBuf.new(0)
    @bss_size = 0
    @tbss_size = 0

    @sym_names = []
    @sym_bind = []
    @sym_type = []
    @sym_sec = []
    @sym_off = []
    @sym_size = []
    @sym_map = {}

    @text_rel_off = []
    @text_rel_sym = []
    @text_rel_kind = []
    @text_rel_add = []

    @ro_rel_off = []
    @ro_rel_sym = []
    @ro_rel_add = []

    @data_rel_off = []
    @data_rel_sym = []
    @data_rel_add = []

  -> ensure_sym(name)
    idx = @sym_map[name]
    return idx if idx != nil
    idx = @sym_names.size()
    @sym_names.push(name)
    @sym_bind.push(ESYM_UNDEF)
    @sym_type.push(ESTT_NOTYPE)
    @sym_sec.push(ESEC_UNDEF)
    @sym_off.push(0)
    @sym_size.push(0)
    @sym_map[name] = idx
    idx

  -> define_sym(name, sec_id, off, size = 0, binding = ESYM_LOCAL, st_type = ESTT_OBJECT)
    idx = ensure_sym(name)
    @sym_bind[idx] = binding
    @sym_type[idx] = st_type
    @sym_sec[idx] = sec_id
    @sym_off[idx] = off
    @sym_size[idx] = size
    idx

  -> alloc_bss(name, size, align_pow2 = 8, binding = ESYM_LOCAL)
    @bss_size = elf_align_up(@bss_size, align_pow2)
    off = @bss_size
    sz = size > 0 ? size : 1
    @bss_size += sz
    define_sym(name, ESEC_BSS, off, sz, binding, ESTT_OBJECT)
    off

  -> alloc_tls_bss(name, size, align_pow2 = 8, binding = ESYM_LOCAL)
    @tbss_size = elf_align_up(@tbss_size, align_pow2)
    off = @tbss_size
    sz = size > 0 ? size : 1
    @tbss_size += sz
    define_sym(name, ESEC_TBSS, off, sz, binding, ESTT_TLS)
    off

  -> add_text_reloc(off, sym, kind, addend = 0)
    ensure_sym(sym)
    # Any symbol referenced by R_X86_64_TPOFF32 must have STT_TLS type if undefined/external!
    if kind == CREL_X64_TPOFF32
      idx = @sym_map[sym]
      @sym_type[idx] = ESTT_TLS if @sym_type[idx] == ESTT_NOTYPE
    @text_rel_off.push(off)
    @text_rel_sym.push(sym)
    @text_rel_kind.push(kind)
    @text_rel_add.push(addend)
    nil

  -> add_const_ptr_reloc(off, sym, addend = 0)
    ensure_sym(sym)
    @ro_rel_off.push(off)
    @ro_rel_sym.push(sym)
    @ro_rel_add.push(addend)
    nil

  -> add_data_ptr_reloc(off, sym, addend = 0)
    ensure_sym(sym)
    @data_rel_off.push(off)
    @data_rel_sym.push(sym)
    @data_rel_add.push(addend)
    nil

  -> map_text_rel_type(kind)
    if @machine == ELF_EM_X86_64
      return kind
    return ELF_R_AARCH64_CALL26           if kind == CREL_A64_BRANCH26
    return ELF_R_AARCH64_ADR_PREL_PG_HI21 if kind == CREL_A64_PAGE21
    return ELF_R_AARCH64_ADD_ABS_LO12_NC  if kind == CREL_A64_PAGEOFF12
    return ELF_R_AARCH64_ADR_GOT_PAGE     if kind == CREL_A64_GOT_PAGE21
    return ELF_R_AARCH64_LD64_GOT_LO12_NC if kind == CREL_A64_GOT_PAGEOFF12
    ELF_R_AARCH64_ABS64

  -> emit_shdr(out, sh_name, sh_type, sh_flags, sh_addr, sh_offset, sh_size, sh_link, sh_info, sh_addralign, sh_entsize)
    out.put_u32_le(sh_name)
    out.put_u32_le(sh_type)
    out.put_u64_le(sh_flags)
    out.put_u64_le(sh_addr)
    out.put_u64_le(sh_offset)
    out.put_u64_le(sh_size)
    out.put_u32_le(sh_link)
    out.put_u32_le(sh_info)
    out.put_u64_le(sh_addralign)
    out.put_u64_le(sh_entsize)
    nil

  -> set_lto_ir(ir_str)
    return nil if ir_str == nil
    ir_len = cinder_blen(ir_str)
    @lto_payload = ByteBuf.new(ir_len + 24)
    @lto_payload.put_ascii("CNDRLTO1")
    @lto_payload.put_u32_le(0)
    @lto_payload.put_u32_le(ir_len)
    @lto_payload.put_ascii(ir_str)
    @lto_payload.align_to(8, 0)
    nil

  -> build_bytes
    @text.align_to(16, 0x90)
    @rodata.align_to(32, 0)
    @data.align_to(16, 0)
    @bss_size = elf_align_up(@bss_size, 16)
    @tbss_size = elf_align_up(@tbss_size, 16)

    # Fixed ELF section indices:
    #   0: "" (SHT_NULL)
    #   1: .text
    #   2: .rodata
    #   3: .data
    #   4: .bss
    #   5: .tbss
    #   6: .note.GNU-stack
    #   7: .symtab
    #   8: .strtab
    #   9: .shstrtab
    #  10: .rela.text
    #  11: .rela.rodata
    #  12: .rela.data

    # Partition symbols: Entry 0 = NULL local symbol, then all MSYM_LOCAL, then globals/undefs!
    locals = []
    globals = []
    ns = @sym_names.size()
    i = 0
    while i < ns
      b = @sym_bind[i]
      if @sym_sec[i] != ESEC_UNDEF && b == ESYM_LOCAL
        locals.push(i)
      else
        globals.push(i)
      i += 1

    strtab = ByteBuf.new(ns * 24 + 16)
    strtab.put_u8(0)
    symtab = ByteBuf.new((1 + ns) * 24 + 16)

    # Symbol 0: STN_UNDEF (24 zero bytes)
    symtab.put_zeros(24)

    final_idx = {}
    cur_sym_idx = 1

    li = 0
    while li < locals.size()
      orig = locals[li]
      nm = @sym_names[orig]
      final_idx[nm] = cur_sym_idx
      cur_sym_idx += 1
      strx = strtab.put_cstr(nm)
      st_info = @sym_type[orig] & 0xF   # STB_LOCAL = 0
      symtab.put_u32_le(strx)
      symtab.put_u8(st_info)
      symtab.put_u8(0)
      symtab.put_u16_le(@sym_sec[orig])
      symtab.put_u64_le(@sym_off[orig])
      symtab.put_u64_le(@sym_size[orig])
      li += 1

    first_global_sym = cur_sym_idx

    gi = 0
    while gi < globals.size()
      orig = globals[gi]
      nm = @sym_names[orig]
      final_idx[nm] = cur_sym_idx
      cur_sym_idx += 1
      strx = strtab.put_cstr(nm)
      b = @sym_bind[orig]
      st_info = (1 << 4) | (@sym_type[orig] & 0xF)   # STB_GLOBAL = 1
      st_other = (b == ESYM_HIDDEN) ? 2 : 0          # STV_HIDDEN = 2
      shndx = (b == ESYM_UNDEF || @sym_sec[orig] == ESEC_UNDEF) ? 0 : @sym_sec[orig]
      sval = shndx == 0 ? 0 : @sym_off[orig]
      symtab.put_u32_le(strx)
      symtab.put_u8(st_info)
      symtab.put_u8(st_other)
      symtab.put_u16_le(shndx)
      symtab.put_u64_le(sval)
      symtab.put_u64_le(@sym_size[orig])
      gi += 1

    strtab.align_to(8, 0)

    # Encode .rela.text, .rela.rodata, .rela.data (each entry = 24 bytes: r_offset, r_info, r_addend)
    abs64_type = @machine == ELF_EM_X86_64 ? CREL_X64_64 : ELF_R_AARCH64_ABS64

    rela_text = ByteBuf.new(@text_rel_off.size() * 24 + 16)
    ri = 0
    while ri < @text_rel_off.size()
      sidx = final_idx[@text_rel_sym[ri]]
      rtype = map_text_rel_type(@text_rel_kind[ri])
      rela_text.put_u64_le(@text_rel_off[ri])
      rela_text.put_u64_le((sidx << 32) | (rtype & 0xFFFFFFFF))
      rela_text.put_u64_le(@text_rel_add[ri])
      ri += 1

    rela_ro = ByteBuf.new(@ro_rel_off.size() * 24 + 16)
    ri = 0
    while ri < @ro_rel_off.size()
      sidx = final_idx[@ro_rel_sym[ri]]
      rela_ro.put_u64_le(@ro_rel_off[ri])
      rela_ro.put_u64_le((sidx << 32) | abs64_type)
      rela_ro.put_u64_le(@ro_rel_add[ri])
      ri += 1

    rela_data = ByteBuf.new(@data_rel_off.size() * 24 + 16)
    ri = 0
    while ri < @data_rel_off.size()
      sidx = final_idx[@data_rel_sym[ri]]
      rela_data.put_u64_le(@data_rel_off[ri])
      rela_data.put_u64_le((sidx << 32) | abs64_type)
      rela_data.put_u64_le(@data_rel_add[ri])
      ri += 1

    has_lto = @lto_payload.len > 0

    # Section header string table (.shstrtab)
    shstr = ByteBuf.new(256)
    shstr.put_u8(0)
    nm_text      = shstr.put_cstr(".text")
    nm_rodata    = shstr.put_cstr(".rodata")
    nm_data      = shstr.put_cstr(".data")
    nm_bss       = shstr.put_cstr(".bss")
    nm_tbss      = shstr.put_cstr(".tbss")
    nm_gnustack  = shstr.put_cstr(".note.GNU-stack")
    nm_symtab    = shstr.put_cstr(".symtab")
    nm_strtab    = shstr.put_cstr(".strtab")
    nm_shstrtab  = shstr.put_cstr(".shstrtab")
    nm_rela_text = shstr.put_cstr(".rela.text")
    nm_rela_ro   = shstr.put_cstr(".rela.rodata")
    nm_rela_data = shstr.put_cstr(".rela.data")
    nm_lto       = has_lto ? shstr.put_cstr(".cinder.lto") : 0
    shstr.align_to(8, 0)

    # Assemble ELF64 file: 64-byte Elf64_Ehdr -> sections -> (13 or 14) * 64-byte Elf64_Shdr
    out = ByteBuf.new(64 + @text.len + @rodata.len + @data.len + @lto_payload.len + symtab.len + strtab.len + rela_text.len + rela_ro.len + rela_data.len + 1024)

    # Elf64_Ehdr (64 bytes; patch e_shoff at offset 40 once sections are written)
    out.put_u8(0x7F); out.put_u8(0x45); out.put_u8(0x4C); out.put_u8(0x46)
    out.put_u8(2)     # ELFCLASS64
    out.put_u8(1)     # ELFDATA2LSB
    out.put_u8(1)     # EV_CURRENT
    out.put_u8(0)     # ELFOSABI_NONE
    out.put_zeros(8)
    out.put_u16_le(1) # ET_REL
    out.put_u16_le(@machine)
    out.put_u32_le(1) # EV_CURRENT
    out.put_u64_le(0) # e_entry
    out.put_u64_le(0) # e_phoff
    out.put_u64_le(0) # e_shoff (patched below at byte 40)
    out.put_u32_le(0) # e_flags
    out.put_u16_le(64) # e_ehsize
    out.put_u16_le(0)  # e_phentsize
    out.put_u16_le(0)  # e_phnum
    out.put_u16_le(64) # e_shentsize
    out.put_u16_le(has_lto ? 14 : 13) # e_shnum
    out.put_u16_le(9)  # e_shstrndx = 9

    out.align_to(64, 0)
    off_text = out.len
    out.put_buf(@text)

    out.align_to(32, 0)
    off_rodata = out.len
    out.put_buf(@rodata)

    out.align_to(16, 0)
    off_data = out.len
    out.put_buf(@data)

    off_bss = out.len
    off_tbss = out.len
    off_gnustack = out.len

    out.align_to(8, 0)
    off_symtab = out.len
    out.put_buf(symtab)

    off_strtab = out.len
    out.put_buf(strtab)

    off_shstrtab = out.len
    out.put_buf(shstr)

    out.align_to(8, 0)
    off_rela_text = out.len
    out.put_buf(rela_text)

    off_rela_ro = out.len
    out.put_buf(rela_ro)

    off_rela_data = out.len
    out.put_buf(rela_data)

    off_lto = 0
    if has_lto
      out.align_to(8, 0)
      off_lto = out.len
      out.put_buf(@lto_payload)

    out.align_to(8, 0)
    shoff = out.len
    out.patch_u64_le(40, shoff)

    # Emit all 13 (or 14 with .cinder.lto) Elf64_Shdr entries (64 bytes each):
    # SHT_NULL=0, SHT_PROGBITS=1, SHT_SYMTAB=2, SHT_STRTAB=3, SHT_RELA=4, SHT_NOBITS=8
    # SHF_WRITE=0x1, SHF_ALLOC=0x2, SHF_EXECINSTR=0x4, SHF_INFO_LINK=0x40, SHF_TLS=0x400
    emit_shdr(out, 0,            0, 0,       0, 0,             0,              0, 0,                0,  0)
    emit_shdr(out, nm_text,      1, 0x6,     0, off_text,      @text.len,      0, 0,                64, 0)
    emit_shdr(out, nm_rodata,    1, 0x2,     0, off_rodata,    @rodata.len,    0, 0,                32, 0)
    emit_shdr(out, nm_data,      1, 0x3,     0, off_data,      @data.len,      0, 0,                16, 0)
    emit_shdr(out, nm_bss,       8, 0x3,     0, off_bss,       @bss_size,      0, 0,                16, 0)
    emit_shdr(out, nm_tbss,      8, 0x403,   0, off_tbss,      @tbss_size,     0, 0,                16, 0)
    emit_shdr(out, nm_gnustack,  1, 0x0,     0, off_gnustack,  0,              0, 0,                1,  0)
    emit_shdr(out, nm_symtab,    2, 0x0,     0, off_symtab,    symtab.len,     8, first_global_sym, 8,  24)
    emit_shdr(out, nm_strtab,    3, 0x0,     0, off_strtab,    strtab.len,     0, 0,                1,  0)
    emit_shdr(out, nm_shstrtab,  3, 0x0,     0, off_shstrtab,  shstr.len,      0, 0,                1,  0)
    emit_shdr(out, nm_rela_text, 4, 0x40,    0, off_rela_text, rela_text.len,  7, 1,                8,  24)
    emit_shdr(out, nm_rela_ro,   4, 0x40,    0, off_rela_ro,   rela_ro.len,    7, 2,                8,  24)
    emit_shdr(out, nm_rela_data, 4, 0x40,    0, off_rela_data, rela_data.len,  7, 3,                8,  24)
    if has_lto
      emit_shdr(out, nm_lto,     1, 0x0,     0, off_lto,       @lto_payload.len, 0, 0,              8,  0)

    out

  -> write_file(path)
    build_bytes().write_file(path)
