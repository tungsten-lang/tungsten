# EXPERIMENT — Lex16 DIMACS scanner. NOT YET BENCHMARKED; see the blocker at
# the bottom of this header before spending time on it.
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
# STATUS 2026-07-28: compiles and links when the function and its driver are in
# ONE file; via `use ./dimacs_lex16` the native typed signature is dropped and
# the body leaks to top level as calls to `lits`/`offs`/`hdr`. The wider lex16
# path is also bit-rotted -- `languages/json/lexer16.w`, the in-tree reference
# for this technique, fails to parse at HEAD (`Unexpected token INDENT` on the
# bare `=>` default arm of its `case ... assigns` at line 48), so its
# benchmark cannot build either.
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
