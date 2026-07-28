# EXPERIMENT — Lex16 DIMACS scanner. MEASURED 2026-07-28: the approach cannot
# win, and the reason is structural rather than a tuning gap. See VERDICT.
#
# The question: does the Tungsten lexer's machinery (a packed LexChar array
# plus the NEON `w_lex16_scan_flag` run-skipper) beat the runtime's scalar
# byte loop for DIMACS?
#
# LexChar model, same as languages/json/lexer16.w: one u16 per source byte,
# codepoint in the high byte, language flag byte in the low byte. Extract is
# `v >> 8`, classify is `v & flags`. Tungsten's own flag table happens to be
# exactly right for DIMACS:
#     0x10 IS_WHITESPACE (space, tab)   0x01 IS_DIGIT (0-9)
#     0x80 IS_NEWLINE                   0x04 IS_OPERATOR (covers '-')
#
# Output is the SAME slab the C parser fills — lits/offs/lens as i64[], a
# clause being the slice (offs[k], lens[k]) of lits. No boxed anything, and
# literals are raw i64 leaf values, so this is the slab/leaf model end to end.
#
#   hdr: [0] nvars  [1] declared clauses  [2] clauses  [3] literals  [4] err
#
# Errors are deliberately coarse (this is a speed probe, not a replacement):
#   1 no header   3 bad token   7 buffer overflow
#
# VERDICT (measured). The Lex16 model needs a mandatory preprocessing pass:
# string -> u16[] LexChar, one element per source byte. That pass ALONE costs
# essentially the whole C parse:
#
#     instance              C parse   lex16 pack   ratio
#     Large-result_b23        117ms        114ms   0.97x
#     sembuster_4200           45ms         45ms   1.00x
#     dspam_dump_vc972         12ms         12ms   1.00x
#     bmc-ibm-12                2ms          2ms   1.00x
#
# So even a FREE scan loses: the lex16 route pays ~1x the existing parser
# before it looks at a single token, then still has to scan the u16 array and
# emit the same output. It is structurally >=2x the memory traffic, because
# `__w_parse_dimacs` is already bandwidth-bound in ONE pass over the bytes,
# while this makes two passes and materialises a 2-bytes-per-input-byte
# intermediate (200MB for a 100MB file).
#
# The NEON run-skipping in w_lex16_scan_flag is real and does help skip the
# ~50% of a CNF that is whitespace -- but it can only speed up the second
# pass, which is not where the cost is.
#
# What the C scanner already has: `w_dimacs_cls` is a 256-entry
# character-class table with DC_SPACE/DC_NL/DC_DIGIT bits -- the lexchar idea
# minus the Unicode machinery DIMACS has no use for. And wassat's clause
# database is already the slab model: flat arena + (offset,length) handles +
# raw i64 leaf literals. Two of the three ideas were already in place; the
# third is the one measured dead here.
#
# If anyone revisits: the only remaining lever on parse is SIMD-ising
# `__w_parse_dimacs` itself (it is a scalar byte loop; runtime/SIMD_LEXER.md
# is the precedent), NOT re-expressing it in the Lex16 idiom.
#
# BUILD NOTES if you do run it: the scanner still has a bug (err=3 at pos=2 on
# a `p cnf` header), it only links when function and driver are in ONE file
# (via `use` the native signature is dropped and the body leaks to top level),
# and the IR must mention "lchs"/"lexchars" or the driver will not link
# runtime/lexchar_tables.c (bin/commands/compile.rb:242). The wider lex16 path
# is bit-rotted too: languages/json/lexer16.w does not parse at HEAD.
#
# Worth knowing before reviving it: the C scanner it would replace already
# uses this design. `w_dimacs_cls` (runtime.c) is a 256-entry character-class
# table with DC_SPACE/DC_NL/DC_DIGIT bits -- the same idea as lexchar, minus
# the Unicode machinery DIMACS has no use for. The plausible win is not the
# table, it is `w_lex16_scan_flag`'s NEON run-skipping over the ~50% of a CNF
# that is whitespace; against that stands one full pass writing 2 bytes per
# input byte to build the LexChar array. That trade is exactly what this file
# was written to measure and what remains unmeasured.

## i64: pos, ncl, nlits, cur, nvars, declared, sign, val, seen, v, c, data_ptr
-> wassat_dimacs_lex16(lc, count, lits, offs, lens, hdr, lcap, ccap) (u16[] i64 i64[] i64[] i64[] i64[] i64 i64) i64
  pos = 0
  ncl = 0
  nlits = 0
  cur = 0
  nvars = 0
  declared = 0
  data_ptr = ccall_nobox("w_typed_array_data_ptr", lc)

  loop
    # SIMD run-skip over whitespace and newlines in one mask.
    v = lc[pos]
    if (v & 0x90) != 0
      pos = ccall_nobox("w_lex16_scan_flag", data_ptr, count, pos, 0x90)
      v = lc[pos]
    break if pos >= count || v == 0
    c = v >> 8

    if c == 99
      # 'c' comment — skip to newline
      pos = ccall_nobox("w_lex16_scan_flag", data_ptr, count, pos, 0x80)
    elsif c == 37
      # '%' terminator
      break
    elsif c == 112
      # 'p cnf <nvars> <ncl>'
      pos += 1
      pos = ccall_nobox("w_lex16_scan_flag", data_ptr, count, pos, 0x90)
      pos += 3                                    # 'cnf'
      pos = ccall_nobox("w_lex16_scan_flag", data_ptr, count, pos, 0x90)
      val = 0
      while (lc[pos] & 0x01) != 0
        val = val * 10 + ((lc[pos] >> 8) - 48)
        pos += 1
      nvars = val
      pos = ccall_nobox("w_lex16_scan_flag", data_ptr, count, pos, 0x90)
      val = 0
      while (lc[pos] & 0x01) != 0
        val = val * 10 + ((lc[pos] >> 8) - 48)
        pos += 1
      declared = val
    else
      # a literal: optional '-', then digits
      sign = 1
      if c == 45
        sign = 0 - 1
        pos += 1
      seen = 0
      val = 0
      while (lc[pos] & 0x01) != 0
        val = val * 10 + ((lc[pos] >> 8) - 48)
        pos += 1
        seen = 1
      if seen == 0
        hdr[4] = 3
        return 0
      if val == 0
        # clause terminator
        if ncl >= ccap
          hdr[4] = 7
          return 0
        offs[ncl] = nlits - cur
        lens[ncl] = cur
        ncl += 1
        cur = 0
      else
        if nlits >= lcap
          hdr[4] = 7
          return 0
        lits[nlits] = sign * val
        nlits += 1
        cur += 1

  hdr[0] = nvars
  hdr[1] = declared
  hdr[2] = ncl
  hdr[3] = nlits
  if nvars == 0
    hdr[4] = 1
  else
    hdr[4] = 0
  ncl
