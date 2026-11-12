# The independent second exactness gate of the GF(2) toolchain.
#
# packed.w checks a scheme with two formulations (dense and sparse), but both
# run on ONE Packed, filled by ONE reader (Scheme.parse or TensorVerifier.read)
# through ONE limb conversion (Bits.hex_limb / Bits.from_limbs / Bits.to_limbs).
# A fault in any of those is common to both and neither can see it. The fiber
# gate shares none of them:
#
#                    packed gates (packed.w)          fiber gate (this file)
#   reader           Scheme.parse, TensorVerifier     ffpk_parse (canonical MFW1),
#                    .read (raw pointer scans)        read_certificate (other formats)
#   in-memory masks  Bits.to_limbs (x >> 64 walk)     the hexadecimal text of each mask
#   representation   three i64[] of 64-bit limbs,     one i64[] slab of 32-bit limbs,
#                    one per axis, term-major         (term*3+axis)*stride+limb
#   formulation      dense table / sparse hash of     ffpk_exact: one u-fiber at a time,
#                    all coefficients                 target XORed in, all-zero test
#
# The slab and ffpk_parse / ffpk_exact are those of
# lib/metaflip/composition/packed.w, the cold-path gate of the wide walker; the
# hexadecimal and decimal conversions and the reader for the non-canonical
# certificate formats are written here and call nothing in bits.w, packed.w,
# scheme.w or tensor_verifier.w (Bits.release, which only frees memory, aside).
#
# A verdict is an integer:
#
#    1  exact
#    0  not exact (a wrong coefficient, or a factor that is zero or too wide)
#   -1  not applicable: the slab holds factors of at most 1,024 bits and at most
#       16,384 terms (canonical text of at most 12,632,128 bytes). Nothing was
#       checked; the caller is left with the packed gates alone and can ask
#       `applicable?` to say so.
#   -2  the fiber gate's reader does not accept the text, or reads another
#       shape or rank from it than the caller's reader did
#
#   FiberGate.applicable?(n, m, p, rank)
#   FiberGate.masks_verdict(n, m, p, us, vs, ws)         Integer masks, any order, duplicates allowed
#   FiberGate.text_verdict(text, n, m, p, rank)          canonical MFW1 bytes (what Scheme.parse accepts)
#   FiberGate.certificate_verdict(text, n, m, p, rank)   any format TensorVerifier.read accepts
#   FiberGate.require_agreement(found, verdict)          raises unless the verdict agrees with the packed
#                                                        gates' (`found`: their Defect, or nil)
#
# n, m, p and rank are what the caller's own reader found; the text routes
# compare them with what this file's reader finds. Scheme#defect(:both) and
# TensorVerifier.verify_text run the packed gates first and then this one, and
# refuse (raise "gate disagreement") unless the two paths give the same verdict.

use bits
use ../composition/packed

+ Metaflip:Gf2:FiberGate
  # Largest canonical text ffpk_parse reads, in bytes.
  -> .text_limit
    12632128

  # True when the slab can hold a scheme of this shape and rank.
  -> .applicable?(n, m, p, rank)
    rank >= 1 && rank <= 16384 && ffpk_stride(n, m, p) > 0

  # ---- conversions into the slab (typed) ---------------------------------------

  # The lowercase hexadecimal digits text[first, last), leading zeros allowed,
  # into data[base, base + stride) as 32-bit limbs (limb j = bits 32j..32j+31).
  # data must be zero there on entry. 1 = stored; 0 = no digits, another byte,
  # or more digits than the stride holds.
  -> .hex_into(text, first, last, data, base, stride) (String i64 i64 i64[] i64 i64) i64
    if last <= first
      return 0
    while first < last - 1 && text.byte_at(first) == 48
      first += 1
    length = last - first ## i64
    if length > 8 * stride
      return 0
    i = 0 ## i64
    while i < length
      byte = text.byte_at(first + i) ## i64
      digit = byte - 48 ## i64
      if byte >= 97 && byte <= 102
        digit = byte - 87
      elsif byte < 48 || byte > 57
        return 0
      nibble = length - 1 - i ## i64
      slot = base + nibble / 8 ## i64
      data[slot] = data[slot] | (digit << (4 * (nibble % 8)))
      i += 1
    1

  # The decimal digits text[first, last) into data[base, base + stride), same
  # contract as hex_into: one multiply-by-ten-and-add over the limbs per digit.
  -> .decimal_into(text, first, last, data, base, stride) (String i64 i64 i64[] i64 i64) i64
    if last <= first
      return 0
    i = first ## i64
    while i < last
      byte = text.byte_at(i) ## i64
      if byte < 48 || byte > 57
        return 0
      carry = byte - 48 ## i64
      q = 0 ## i64
      while q < stride
        value = data[base + q] * 10 + carry ## i64
        data[base + q] = value & 4294967295
        carry = value >> 32
        q += 1
      if carry != 0
        return 0
      i += 1
    1

  # ---- the certificate reader (typed) -------------------------------------------

  # 1 for the bytes stripped from the ends of a line: NUL, \t, \n, \v, \f, \r, space.
  -> .blank(byte) (i64) i64
    if byte == 0 || byte == 32 || (byte >= 9 && byte <= 13)
      return 1
    0

  # 1 for the bytes that separate the words of a line: \t, \n, \v, \f, \r, space.
  -> .gap(byte) (i64) i64
    if byte == 32 || (byte >= 9 && byte <= 13)
      return 1
    0

  # The next word of text[from, last): its bounds go to span[0], span[1].
  # 1 = found, 0 = only separators are left.
  -> .word(text, from, last, span) (String i64 i64 i64[]) i64
    i = from ## i64
    while i < last && Metaflip:Gf2:FiberGate.gap(text.byte_at(i)) == 1
      i += 1
    if i >= last
      return 0
    span[0] = i
    while i < last && Metaflip:Gf2:FiberGate.gap(text.byte_at(i)) == 0
      i += 1
    span[1] = i
    1

  # The decimal number text[first, last), or -1 when it is empty, holds another
  # byte, or (strict = 1) starts with a zero. Values above 10^9 read as 10^9,
  # which no shape or term count of the slab reaches.
  -> .number(text, first, last, strict) (String i64 i64 i64) i64
    if last <= first
      return 0 - 1
    if strict == 1 && text.byte_at(first) == 48
      return 0 - 1
    value = 0 ## i64
    i = first ## i64
    while i < last
      digit = text.byte_at(i) - 48 ## i64
      if digit < 0 || digit > 9
        return 0 - 1
      if value < 1000000000
        value = value * 10 + digit
      i += 1
    if value > 1000000000
      value = 1000000000
    value

  # Reads a certificate for the shape n x m x p into the slab `data` (`words`
  # entries, zero on entry) and returns its rank, or -1 when it is not one of:
  #
  #   MFW1        a line `MFW1 n m p rank`, then rank rows of three lowercase
  #               hexadecimal words
  #   checkpoint  a line of decimal digits (the rank), then rows of three
  #               decimal words, each row optionally prefixed by the word `R`
  #   corpus rows no header; every row is `R` and three decimal words
  #
  # Lines are separated by LF; blanks (see `blank`) around a line are dropped,
  # as are empty lines and lines starting with `#`; words are separated by any
  # run of `gap` bytes. The factors are only converted here: whether they are
  # nonzero and narrower than their matrices is for ffpk_exact to decide.
  -> .read_certificate(text, n, m, p, data, words)
    span = i64[2]
    rank = Metaflip:Gf2:FiberGate.read_rows(text, n, m, p, data, words, span)
    Metaflip:Gf2:Bits.release(span)
    rank

  # The body of read_certificate; span is scratch for the bounds of one word.
  -> .read_rows(text, n, m, p, data, words, span) (String i64 i64 i64 i64[] i64 i64[]) i64
    stride = ffpk_stride(n, m, p) ## i64
    if stride == 0
      return 0 - 1
    capacity = words / (3 * stride) ## i64
    size = text.size ## i64
    kind = 0 ## i64
    declared = 0 ## i64
    count = 0 ## i64
    pos = 0 ## i64
    while pos < size
      stop = pos ## i64
      while stop < size && text.byte_at(stop) != 10
        stop += 1
      first = pos ## i64
      last = stop ## i64
      while first < last && Metaflip:Gf2:FiberGate.blank(text.byte_at(first)) == 1
        first += 1
      while last > first && Metaflip:Gf2:FiberGate.blank(text.byte_at(last - 1)) == 1
        last -= 1
      pos = stop + 1
      if last > first && text.byte_at(first) != 35
        row = 1 ## i64
        if kind == 0
          # The first kept line decides the format.
          if last - first >= 4 && text.byte_at(first) == 77 && text.byte_at(first + 1) == 70 && text.byte_at(first + 2) == 87 && text.byte_at(first + 3) == 49
            kind = 1
            row = 0
            cursor = first ## i64
            field = 0 ## i64
            while field < 5
              if Metaflip:Gf2:FiberGate.word(text, cursor, last, span) == 0
                return 0 - 1
              if field == 0 && span[1] - span[0] != 4
                return 0 - 1
              if field > 0
                value = Metaflip:Gf2:FiberGate.number(text, span[0], span[1], 1) ## i64
                if value < 1
                  return 0 - 1
                if (field == 1 && value != n) || (field == 2 && value != m) || (field == 3 && value != p)
                  return 0 - 1
                declared = value
              cursor = span[1]
              field += 1
            if Metaflip:Gf2:FiberGate.word(text, cursor, last, span) == 1
              return 0 - 1
          elsif Metaflip:Gf2:FiberGate.number(text, first, last, 0) >= 0
            kind = 2
            row = 0
            declared = Metaflip:Gf2:FiberGate.number(text, first, last, 0)
          else
            kind = 3
        if row == 1
          if count >= capacity
            return 0 - 1
          cursor = first ## i64
          found = Metaflip:Gf2:FiberGate.word(text, cursor, last, span) ## i64
          prefixed = 0 ## i64
          if found == 1 && span[1] - span[0] == 1 && text.byte_at(span[0]) == 82
            prefixed = 1
            cursor = span[1]
            found = Metaflip:Gf2:FiberGate.word(text, cursor, last, span)
          if (kind == 1 && prefixed == 1) || (kind == 3 && prefixed == 0)
            return 0 - 1
          axis = 0 ## i64
          while axis < 3
            if found == 0
              return 0 - 1
            base = (3 * count + axis) * stride ## i64
            stored = 0 ## i64
            if kind == 1
              stored = Metaflip:Gf2:FiberGate.hex_into(text, span[0], span[1], data, base, stride)
            else
              stored = Metaflip:Gf2:FiberGate.decimal_into(text, span[0], span[1], data, base, stride)
            if stored == 0
              return 0 - 1
            cursor = span[1]
            found = Metaflip:Gf2:FiberGate.word(text, cursor, last, span)
            axis += 1
          if found == 1
            return 0 - 1
          count += 1
    if kind == 0 || count < 1 || (kind != 3 && count != declared)
      return 0 - 1
    count

  # ---- verdicts -------------------------------------------------------------------

  # ffpk_exact on a filled slab: 1 exact, 0 not (which includes a zero or
  # too-wide factor, rejected by ffpk_valid before any coefficient is summed).
  -> .slab_verdict(data, words, rank, n, m, p)
    cells = m * p * ((n * p + 31) / 32)
    scratch = i64[cells]
    result = ffpk_exact(data, words, rank, n, m, p, scratch, cells, 0)
    Metaflip:Gf2:Bits.release(scratch)
    result == 1 ? 1 : 0

  # One Integer mask into the slab, through its hexadecimal text.
  -> .store_mask(mask, data, base, stride)
    return false if mask < 0
    hex = mask.to_s(16)
    stored = Metaflip:Gf2:FiberGate.hex_into(hex, 0, hex.size, data, base, stride)
    Metaflip:Gf2:Bits.release(hex)
    stored == 1

  # The verdict for parallel Arrays of Integer masks (file order, duplicates
  # and all: over GF(2) a repeated term cancels in the sum, as in the packed
  # gates). A mask that is negative or wider than the slab's stride is a 0.
  -> .masks_verdict(n, m, p, us, vs, ws)
    rank = us.size
    return -1 if !Metaflip:Gf2:FiberGate.applicable?(n, m, p, rank)
    return 0 if vs.size != rank || ws.size != rank
    stride = ffpk_stride(n, m, p)
    words = 3 * stride * rank
    data = i64[words]
    stored = true
    t = 0
    while stored && t < rank
      stored = Metaflip:Gf2:FiberGate.store_mask(us[t], data, 3 * t * stride, stride)
      stored = Metaflip:Gf2:FiberGate.store_mask(vs[t], data, (3 * t + 1) * stride, stride) if stored
      stored = Metaflip:Gf2:FiberGate.store_mask(ws[t], data, (3 * t + 2) * stride, stride) if stored
      t += 1
    verdict = 0
    verdict = Metaflip:Gf2:FiberGate.slab_verdict(data, words, rank, n, m, p) if stored
    Metaflip:Gf2:Bits.release(data)
    verdict

  # The verdict for canonical MFW1 text, read by ffpk_parse from the bytes
  # themselves. n, m, p, rank: what the caller's reader found in the same text.
  -> .text_verdict(text, n, m, p, rank)
    return -1 if !Metaflip:Gf2:FiberGate.applicable?(n, m, p, rank) || text.size > Metaflip:Gf2:FiberGate.text_limit
    stride = ffpk_stride(n, m, p)
    words = 3 * stride * rank
    data = i64[words]
    meta = i64[4]
    verdict = -2
    if ffpk_parse(text, data, words, meta, 4) == rank && meta[0] == n && meta[1] == m && meta[2] == p
      verdict = Metaflip:Gf2:FiberGate.slab_verdict(data, words, rank, n, m, p)
    Metaflip:Gf2:Bits.release(data)
    Metaflip:Gf2:Bits.release(meta)
    verdict

  # The verdict for a certificate in any format TensorVerifier.read accepts,
  # read by read_certificate from the bytes themselves.
  -> .certificate_verdict(text, n, m, p, rank)
    return -1 if !Metaflip:Gf2:FiberGate.applicable?(n, m, p, rank)
    stride = ffpk_stride(n, m, p)
    words = 3 * stride * rank
    data = i64[words]
    verdict = -2
    if Metaflip:Gf2:FiberGate.read_certificate(text, n, m, p, data, words) == rank
      verdict = Metaflip:Gf2:FiberGate.slab_verdict(data, words, rank, n, m, p)
    Metaflip:Gf2:Bits.release(data)
    verdict

  # Raises unless the fiber verdict agrees with the packed gates, whose result
  # is `found` (nil when they accept, else their Defect). A verdict of -1
  # settles nothing and is let through: the scheme is beyond the slab.
  -> .require_agreement(found, verdict)
    return nil if verdict == -1
    raise "gate disagreement: the fiber gate's reader does not read the scheme the first reader accepted" if verdict == -2
    left = found == nil ? "exact" : found.message
    raise "gate disagreement: the packed gates say [left], the fiber gate says exact" if found != nil && verdict == 1
    raise "gate disagreement: the packed gates say exact, the fiber gate says inexact" if found == nil && verdict != 1
    nil
