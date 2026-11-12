# A GF(2) matrix-multiplication scheme <n,m,p> as Integer masks: the foundation
# library of the metaflip GF(2) toolchain port (Ruby/Python -> Tungsten).
#
# A scheme of rank r is r terms (u, v, w) with
#
#     u: n x m mask, bit i*m+j = A[i][j]
#     v: m x p mask, bit j*p+k = B[j][k]
#     w: n x p mask, bit i*p+k = C[i][k]          (C in its public, untransposed layout)
#
# and is EXACT when sum_t u_t (x) v_t (x) w_t equals the <n,m,p> matrix
# multiplication tensor over GF(2). This is the Alg of tools/mmc_gf2_alg.py and
# the (shape, terms) pair of the MFW1 tooling (read_blob / blob / exact).
#
# The public API is in Integer masks, so ported algorithms read like the Python
# originals; the heavy lifting (the two gates) converts to the limb arrays of
# packed.w and never builds a BigInt on the hot path.
#
#   Scheme.new(n, m, p, us, vs, ws)      parallel Arrays of masks (not copied, not
#                                        validated beyond lengths: intermediate
#                                        constructions may hold zero factors)
#   Scheme.from_terms(n, m, p, terms)    terms: Array of [u, v, w]
#   Scheme.naive(n, m, p)                the n*m*p rank-one terms, (i, j, k) order
#   Scheme.parse(text, expect = nil)     strict MFW1 (see below); expect = [n, m, p]
#   Scheme.read(path, expect = nil)      parse of a file
#   (checkpoints, R-prefixed rows and the other certificate formats of verify_tensor.rb
#   come in through TensorVerifier.read_scheme in tensor_verifier.w)
#
#   s.n s.m s.p s.us s.vs s.ws           fields; treat the Arrays as immutable
#   s.rank  s.shape  s.sorted_shape      rank; [n, m, p]; the sorted-shape key
#   s.shape_key  s.sorted_shape_key      "NxMxP" strings of the same (Hash keys, manifests)
#   s.terms  s.term(i)                   [[u, v, w], ...]; [u, v, w]
#   s.density                            total number of set bits
#   s.sorted                             same terms in canonical (u, v, w) order
#   s.cleaned                            no zero-factor terms, identical pairs cancelled
#   s.blob  s.sha256                     canonical MFW1 text; its SHA-256 (hex)
#   s.cyclic_shift  s.transpose          the S3 moves of mmc_gf2_alg.py
#   s.oriented(perm)                     the orientation for one of the six permutations
#   s.oriented_to(target)                verify_cofactor_mergers.orient: first permutation,
#                                        in lexicographic order, that yields target
#   s.orient_as(shape)                   mmc_gf2_alg.orient_as; nil if unreachable
#   Scheme.orient_perms                  the six permutations, ORIENT_PERMS order
#   Scheme.permuted_shape(shape, perm)   [shape[perm[0]], shape[perm[1]], shape[perm[2]]]
#   s.equal_terms?(other)                same shape and same terms in the same order
#   s.release                            frees the masks (no GC; see the note on sharing
#                                        at the method and Bits.release in bits.w)
#
# Exactness (a gate returns nil or the first failing coefficient as a
# Metaflip:Gf2:Defect with .message/.a/.b/.expected/.actual). There are two
# paths that share no reader, no limb conversion and no formulation:
#
#   packed gates   packed.w: the masks go through Bits.to_limbs into a Packed,
#                  which the dense and the sparse gate each check in full
#   fiber gate     fiber_gate.w: the scheme is read a second time, by another
#                  reader into another representation (32-bit limbs), and
#                  checked by ffpk_exact, the cold-path gate of the wide walker
#
#   s.defect(gate = :both, text = nil)   :dense or :sparse: that packed gate alone. :both: the
#                                        two packed gates, which must name the same coefficient,
#                                        and then the fiber gate, which must give the same
#                                        verdict ("gate disagreement" is raised otherwise)
#   s.exact?(gate = :both, text = nil)   true when defect is nil
#   s.verify(gate = :both, text = nil)   self, or raises the defect message
#   s.pack                               the Packed limb-array form
#
# `text` is for a scheme that came from Scheme.parse: pass the very text it was
# parsed from and the fiber gate reads those bytes with its own parser
# (ffpk_parse), so that nothing downstream of the file is common to the two
# paths. Without it the fiber gate converts the Integer masks itself, through
# their hexadecimal text. A scheme beyond the fiber gate's slab (a factor wider
# than 1,024 bits, more than 16,384 terms) is checked by the packed gates alone;
# Metaflip:Gf2:FiberGate.applicable?(n, m, p, rank) tells which case it is.
#
# Scheme.parse is the strict MFW1 reader, exactly the acceptance rule of
# read_blob in the Python tooling: the text must BE the canonical blob of its
# own terms (header `MFW1 n m p rank`, one `u v w` row per term in lowercase hex
# without leading zeros, single spaces, LF line ends, rows strictly increasing
# as (u, v, w) integer triples, so no duplicates, nothing after the last row).
# Blank lines, comments, CRLF, uppercase hex, leading zeros, wrong row counts
# and unsorted or repeated terms are all rejected with a message naming the
# cause. Three deliberate deviations, all invisible to any accept/reject decision
# that also requires exactness: negative numbers, non-positive dimensions and
# rows whose field count is not three are rejected at parse time (read_blob
# returns such rows as tuples of some other length, and `exact` refuses them
# later). Range and exactness of the factors are NOT checked by parse; that is
# the gates' job.

use packed
use fiber_gate

+ Metaflip:Gf2:Scheme
  ro :n, :m, :p, :us, :vs, :ws

  -> new(@n, @m, @p, @us, @vs, @ws)
    raise "Scheme dimensions must be positive" if !@n.is_a?(Integer) || !@m.is_a?(Integer) || !@p.is_a?(Integer) || @n < 1 || @m < 1 || @p < 1
    raise "Scheme term arrays must have equal lengths" if @us.size != @vs.size || @us.size != @ws.size

  -> .from_terms(n, m, p, terms)
    us = terms.map -> (t) t[0]
    vs = terms.map -> (t) t[1]
    ws = terms.map -> (t) t[2]
    Metaflip:Gf2:Scheme.new(n, m, p, us, vs, ws)

  # The n*m*p rank-one terms of the definition, in (i, j, k) row-major order.
  -> .naive(n, m, p)
    us = []
    vs = []
    ws = []
    (0...n).each -> (i)
      (0...m).each -> (j)
        (0...p).each -> (k)
          us.push(1 << (i * m + j))
          vs.push(1 << (j * p + k))
          ws.push(1 << (i * p + k))
    Metaflip:Gf2:Scheme.new(n, m, p, us, vs, ws)

  # ---- shape helpers -----------------------------------------------------------

  # The six axis permutations in mmc_gf2_alg.ORIENT_PERMS order: index c < 3 is
  # c cyclic shifts, index c >= 3 a transpose followed by c - 3 cyclic shifts.
  -> .orient_perms
    [[0, 1, 2], [1, 2, 0], [2, 0, 1], [2, 1, 0], [1, 0, 2], [0, 2, 1]]

  -> .permuted_shape(shape, perm)
    [shape[perm[0]], shape[perm[1]], shape[perm[2]]]

  -> shape
    [@n, @m, @p]

  # The shape sorted ascending: the key under which all six orientations meet.
  -> sorted_shape
    shape.sort

  # "NxMxP" (the spelling of certificates, manifests and hash keys) of the shape
  # and of the sorted shape.
  -> shape_key
    "[@n]x[@m]x[@p]"

  -> sorted_shape_key
    sorted_shape.join("x")

  -> rank
    @us.size

  -> terms
    (0...rank).map -> (t) [@us[t], @vs[t], @ws[t]]

  -> term(i)
    [@us[i], @vs[i], @ws[i]]

  -> density
    masks = [@us, @vs, @ws]
    masks.reduce(0) -> (total, column)
      column.reduce(total) -> (sum, mask) sum + Metaflip:Gf2:Bits.popcount(mask)

  -> equal_terms?(other)
    return false if @n != other.n || @m != other.m || @p != other.p || rank != other.rank
    (0...rank).all? -> (t) @us[t] == other.us[t] && @vs[t] == other.vs[t] && @ws[t] == other.ws[t]

  -> to_s
    "Scheme<[@n],[@m],[@p]>=[rank]"

  # ---- orientation (the S3 action on the three axes) ----------------------------

  # <n,m,p> -> <m,p,n>: (u, v, w) -> (v, w^T, u^T), as mmc_gf2_alg.cyclic_shift.
  -> cyclic_shift
    us = @vs.map -> (v) v
    vs = @ws.map -> (w) Metaflip:Gf2:Bits.transpose(w, @n, @p)
    ws = @us.map -> (u) Metaflip:Gf2:Bits.transpose(u, @n, @m)
    Metaflip:Gf2:Scheme.new(@m, @p, @n, us, vs, ws)

  # <n,m,p> -> <p,m,n>: (u, v, w) -> (v^T, u^T, w^T), as mmc_gf2_alg.transpose.
  -> transpose
    us = @vs.map -> (v) Metaflip:Gf2:Bits.transpose(v, @m, @p)
    vs = @us.map -> (u) Metaflip:Gf2:Bits.transpose(u, @n, @m)
    ws = @ws.map -> (w) Metaflip:Gf2:Bits.transpose(w, @n, @p)
    Metaflip:Gf2:Scheme.new(@p, @m, @n, us, vs, ws)

  # The orientation with permutation perm (an entry of orient_perms): the shape
  # of the result is permuted_shape(shape, perm).
  -> oriented(perm)
    code = -1
    perms = Metaflip:Gf2:Scheme.orient_perms
    (0...6).each -> (c)
      code = c if perms[c][0] == perm[0] && perms[c][1] == perm[1] && perms[c][2] == perm[2]
    raise "not an orientation permutation: [perm]" if code < 0
    x = self
    x = transpose if code >= 3
    shifts = code % 3
    while shifts > 0
      x = x.cyclic_shift
      shifts -= 1
    x

  # verify_cofactor_mergers.orient(shape, terms, target): the orientation for the
  # first permutation, in lexicographic order, whose permuted shape is `target`.
  # (orient_as walks the moves in a different order, which only matters when the
  # shape repeats a dimension: the two then pick different but equally valid
  # orientations.) Raises when target is not a permutation of the shape.
  -> oriented_to(target)
    perms = [[0, 1, 2], [0, 2, 1], [1, 0, 2], [1, 2, 0], [2, 0, 1], [2, 1, 0]]
    found = nil
    perms.each -> (perm)
      permuted = Metaflip:Gf2:Scheme.permuted_shape(shape, perm)
      found = perm if found == nil && permuted[0] == target[0] && permuted[1] == target[1] && permuted[2] == target[2]
    raise "no orientation of [self] has shape [target]" if found == nil
    oriented(found)

  # The first orientation whose shape is `shape` (searching the cyclic shifts of
  # the scheme, then of its transpose, as mmc_gf2_alg.orient_as), or nil.
  -> orient_as(shape)
    current = self
    step = 0
    while step < 3
      return current if current.same_shape?(shape)
      current = current.cyclic_shift
      step += 1
    current = transpose
    step = 0
    while step < 3
      return current if current.same_shape?(shape)
      current = current.cyclic_shift
      step += 1
    nil

  -> same_shape?(shape)
    @n == shape[0] && @m == shape[1] && @p == shape[2]

  # ---- canonical form ----------------------------------------------------------

  # The same terms in canonical order: ascending as (u, v, w) integer triples.
  # Duplicates and zero factors are kept (this is `sorted`, not a cleanup).
  -> sorted
    rows = terms
    ordered = rows.sort
    result = Metaflip:Gf2:Scheme.from_terms(@n, @m, @p, ordered)
    Metaflip:Gf2:Bits.release(ordered)
    rows.each -> (row)
      Metaflip:Gf2:Bits.release(row)
    Metaflip:Gf2:Bits.release(rows)
    result

  # Drops the terms with a zero factor and cancels identical terms in pairs
  # (their sum is 0 over GF(2)); the survivors keep the order of their first
  # occurrence. This is `clean` of mmc_gf2_alg.py.
  -> cleaned
    entries = []
    t = 0
    while t < rank
      entries.push([@us[t], @vs[t], @ws[t], t]) if @us[t] != 0 && @vs[t] != 0 && @ws[t] != 0
      t += 1
    entries = entries.sort
    survivors = []
    i = 0
    while i < entries.size
      j = i
      while j < entries.size && entries[j][0] == entries[i][0] && entries[j][1] == entries[i][1] && entries[j][2] == entries[i][2]
        j += 1
      survivors.push(entries[i]) if (j - i) % 2 == 1
      i = j
    kept = survivors.sort_by -> (entry) entry[3]
    result = Metaflip:Gf2:Scheme.from_terms(@n, @m, @p, kept)
    entries.each -> (entry)
      Metaflip:Gf2:Bits.release(entry)
    Metaflip:Gf2:Bits.release(entries)
    Metaflip:Gf2:Bits.release(survivors)
    Metaflip:Gf2:Bits.release(kept)
    result

  # The canonical MFW1 text, byte for byte the `blob` of the Python tooling.
  -> blob
    text = StringBuffer()
    text.append("MFW1 [@n] [@m] [@p] [rank]\n")
    rows = terms
    ordered = rows.sort
    ordered.each -> (row)
      pieces = [Metaflip:Gf2:Bits.to_hex(row[0]), Metaflip:Gf2:Bits.to_hex(row[1]), Metaflip:Gf2:Bits.to_hex(row[2])]
      text.append(pieces[0])
      text.append(" ")
      text.append(pieces[1])
      text.append(" ")
      text.append(pieces[2])
      text.append("\n")
      pieces.each -> (piece)
        Metaflip:Gf2:Bits.release(piece)
      Metaflip:Gf2:Bits.release(pieces)
    result = text.to_s
    Metaflip:Gf2:Bits.release(text)
    Metaflip:Gf2:Bits.release(ordered)
    rows.each -> (row)
      Metaflip:Gf2:Bits.release(row)
    Metaflip:Gf2:Bits.release(rows)
    result

  -> sha256
    text = blob
    digest = Digest.sha256(text)
    Metaflip:Gf2:Bits.release(text)
    digest

  # ---- exactness ---------------------------------------------------------------

  # The first :range Defect (a zero, negative or too-wide factor), or nil. Works
  # on masks too wide to pack.
  -> range_defect
    limit_u = 1 << (@n * @m)
    limit_v = 1 << (@m * @p)
    limit_w = 1 << (@n * @p)
    found = nil
    t = 0
    while found == nil && t < rank
      found = Metaflip:Gf2:Defect.new(:range, t, 0) if @us[t] <= 0 || @us[t] >= limit_u
      found = Metaflip:Gf2:Defect.new(:range, t, 1) if found == nil && (@vs[t] <= 0 || @vs[t] >= limit_v)
      found = Metaflip:Gf2:Defect.new(:range, t, 2) if found == nil && (@ws[t] <= 0 || @ws[t] >= limit_w)
      t += 1
    Metaflip:Gf2:Bits.release(limit_u)
    Metaflip:Gf2:Bits.release(limit_v)
    Metaflip:Gf2:Bits.release(limit_w)
    found

  # The limb-array form. Raises if a factor is negative or wider than its matrix
  # allows; call range_defect first for a diagnosis.
  -> pack
    Metaflip:Gf2:Packed.from_masks(@n, @m, @p, @us, @vs, @ws)

  # nil when exact, else the first Defect. gate: :dense, :sparse or :both
  # (both packed gates, then the independent fiber gate, which must agree).
  # text: the canonical MFW1 text this scheme was parsed from, if any; the
  # fiber gate then parses it itself instead of converting the masks.
  -> defect(gate = :both, text = nil)
    bad = range_defect
    return bad if bad != nil
    packed = pack
    found = packed.defect(gate)
    packed.release
    return found if gate != :both
    verdict = nil
    if text == nil
      verdict = Metaflip:Gf2:FiberGate.masks_verdict(@n, @m, @p, @us, @vs, @ws)
    else
      verdict = Metaflip:Gf2:FiberGate.text_verdict(text, @n, @m, @p, rank)
    Metaflip:Gf2:FiberGate.require_agreement(found, verdict)
    found

  # Frees the mask Arrays and every BigInt mask in them (compiled Tungsten has no
  # garbage collector; see bits.w). Only for a scheme whose masks nothing else
  # references: true of Scheme.parse, .read and .naive results and of schemes
  # built from masks you made yourself, FALSE for anything derived by sorted,
  # cyclic_shift, transpose, oriented, orient_as or cleaned from another scheme
  # (they share mask objects with their source). Nothing taken from a released
  # scheme may be used afterwards.
  -> release
    [@us, @vs, @ws].each -> (column)
      column.each -> (mask)
        Metaflip:Gf2:Bits.release(mask)
      Metaflip:Gf2:Bits.release(column)
    nil

  -> exact?(gate = :both, text = nil)
    defect(gate, text) == nil

  -> verify(gate = :both, text = nil)
    bad = defect(gate, text)
    raise bad.message if bad != nil
    self

  # ---- strict MFW1 reader --------------------------------------------------------

  # Index of the first `byte` at or after `from`, or -1.
  -> .find_byte(text, from, byte) (String i64 i64) i64
    size = text.size ## i64
    ptr = Metaflip:Gf2:Bits.text_ptr(text) ## i64
    i = from ## i64
    while i < size
      if Metaflip:Gf2:Bits.byte(text, ptr, i) == byte
        return i
      i += 1
    -1

  # Canonical unsigned decimal ("0" or no leading zero, 1..9 digits) or -1.
  -> .decimal(text) (String) i64
    size = text.size ## i64
    if size < 1 || size > 9
      return -1
    if size > 1 && text.byte_at(0) == 48
      return -1
    value = 0 ## i64
    i = 0 ## i64
    while i < size
      digit = text.byte_at(i) - 48 ## i64
      if digit < 0 || digit > 9
        return -1
      value = value * 10 + digit
      i += 1
    value

  # Scans one canonical row (three lowercase hex tokens, single spaces, LF) at
  # pos of text (ptr from Bits.text_ptr). Fills spans[0..5] with the token bounds
  # and returns the offset just past the LF, or a negative cause: -1 empty token
  # (blank line, comment, stray separator), -2 uppercase hex, -3 leading zero,
  # -4 other byte where a separator belongs, -5 carriage return, -6 text ends
  # inside the row.
  -> .scan_row(text, ptr, pos, spans) (String i64 i64 i64[]) i64
    size = text.size ## i64
    cursor = pos ## i64
    field = 0 ## i64
    while field < 3
      start = cursor ## i64
      stop = Metaflip:Gf2:Bits.hex_run(text, ptr, start, size) ## i64
      if stop == start
        if start >= size
          return -6
        first = Metaflip:Gf2:Bits.byte(text, ptr, start) ## i64
        if first >= 65 && first <= 70
          return -2
        return -1
      if Metaflip:Gf2:Bits.byte(text, ptr, start) == 48 && stop - start > 1
        return -3
      if stop >= size
        return -6
      sep = Metaflip:Gf2:Bits.byte(text, ptr, stop) ## i64
      want = 32 ## i64
      if field == 2
        want = 10
      if sep != want
        if sep >= 65 && sep <= 70
          return -2
        if sep == 13
          return -5
        return -4
      spans[2 * field] = start
      spans[2 * field + 1] = stop
      cursor = stop + 1
      field += 1
    cursor

  -> .row_error(code, t)
    return "non-canonical MFW1 text: empty field, blank line or comment at term [t]" if code == -1
    return "non-canonical MFW1 text: uppercase hexadecimal at term [t]" if code == -2
    return "non-canonical MFW1 text: leading zero at term [t]" if code == -3
    return "non-canonical MFW1 text: unexpected byte at term [t]" if code == -4
    return "non-canonical MFW1 text: carriage return (CRLF line ending) at term [t]" if code == -5
    "wrong term count"

  -> .parse(text, expect = nil)
    size = text.size
    newline = Metaflip:Gf2:Scheme.find_byte(text, 0, 10)
    raise "malformed MFW1 header" if newline < 0 || newline > 80
    header = text.slice(0, newline)
    raise "non-canonical MFW1 text: carriage return (CRLF line ending) in the header" if newline > 0 && header.byte_at(newline - 1) == 13
    fields = header.split(" ")
    raise "malformed MFW1 header" if fields.size != 5 || fields[0] != "MFW1"
    n = Metaflip:Gf2:Scheme.decimal(fields[1])
    m = Metaflip:Gf2:Scheme.decimal(fields[2])
    p = Metaflip:Gf2:Scheme.decimal(fields[3])
    rank = Metaflip:Gf2:Scheme.decimal(fields[4])
    raise "malformed MFW1 header" if n < 1 || m < 1 || p < 1 || rank < 0
    raise "malformed MFW1 header" if header != "MFW1 [n] [m] [p] [rank]"
    raise "MFW1 shape mismatch" if expect != nil && (expect[0] != n || expect[1] != m || expect[2] != p)
    us = []
    vs = []
    ws = []
    spans = i64[6]
    ptr = Metaflip:Gf2:Bits.text_ptr(text)
    pos = newline + 1
    begin
      t = 0
      while t < rank
        raise "wrong term count" if pos >= size
        after = Metaflip:Gf2:Scheme.scan_row(text, ptr, pos, spans)
        raise Metaflip:Gf2:Scheme.row_error(after, t) if after < 0
        u = Metaflip:Gf2:Bits.hex_value(text, ptr, spans[0], spans[1])
        v = Metaflip:Gf2:Bits.hex_value(text, ptr, spans[2], spans[3])
        w = Metaflip:Gf2:Bits.hex_value(text, ptr, spans[4], spans[5])
        us.push(u)
        vs.push(v)
        ws.push(w)
        if t > 0
          order = u <=> us[t - 1]
          order = v <=> vs[t - 1] if order == 0
          order = w <=> ws[t - 1] if order == 0
          raise "duplicate term at term [t]" if order == 0
          raise "terms out of canonical order at term [t]" if order < 0
        pos = after
        t += 1
      raise "wrong term count" if pos != size
    rescue failure
      [us, vs, ws].each -> (column)
        column.each -> (mask)
          Metaflip:Gf2:Bits.release(mask)
        Metaflip:Gf2:Bits.release(column)
      raise failure
    Metaflip:Gf2:Bits.release(spans)
    Metaflip:Gf2:Scheme.new(n, m, p, us, vs, ws)

  -> .read(path, expect = nil)
    text = read_file(path)
    raise "cannot read [path]" if text == nil
    begin
      Metaflip:Gf2:Scheme.parse(text, expect)
    ensure
      Metaflip:Gf2:Bits.release(text)
