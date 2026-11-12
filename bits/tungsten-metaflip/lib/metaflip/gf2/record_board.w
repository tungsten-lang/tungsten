# The record scoreboard: the best exactly verified local GF(2) witness per shape
# against the ranks that public tables list. Port of tools/gf2_record_board.py.
#
# Every counted witness is expanded against the full matrix-multiplication tensor
# (a verdict is cached under the SHA-256 of the file's bytes). Public comparisons:
#
#   lille           Sedoglavic fmm_digest `fmm_sota.json` (rank only, any ring)
#   matmulcatalog   solven-eu/matmulcatalog `docs/catalog.json`; commutative entries are
#                   excluded; `fields` separates the F2-valid schemes
#   fmm repo        a clone of a FastMatrixMultiplication-format repository (Perminov); the
#                   ring is the file-name suffix (_ZT, _Z, _Q)
#   extra repos     further directories of FMM-format scheme files (fmm-schemes)
#
# A witness is classified, in this order:
#   below_all        beats every listed rank in any ring
#   gf2_valid_only   beats every listed GF(2)-valid scheme (ZT/Z or catalogue F2) but a listed
#                    Q/C-only rank is lower
#   tie              equals the best listed rank
#   no_public_rank   nothing is listed for the shape
#   above            otherwise
# A listed rank is a comparison, never a certificate; neither class is a novelty or optimality claim.
#
#   RecordBoard.witnesses(roots, cache)     {sorted shape key => [rank, path]}; new verdicts go into cache
#   RecordBoard.public_tables(lille, catalog, fmm_repo, fmm_revision, extra_repos)
#                                           [lille, any_ring, gf2]: {"NxMxP" => rank}
#   RecordBoard.rows(ours, tables)          the classified rows, in numeric shape order
#   RecordBoard.decode(path, text)          [shape, rank] of a verified witness, or nil
#   RecordBoard.shape_hint(path)            the dimensions a file or directory name suggests, or nil
#
# Shapes are keyed by their "NxMxP" text, sorted ascending, which is what the Python tuples key on.
#
# Differences from the original: the witnesses are verified one after the other in this process
# (the compiled gates are fast enough that the original's process pool is not needed, and --jobs
# is accepted and ignored); a witness file that is not readable, or whose gzip/base64 layer is
# damaged, is skipped, where the original stops on a corrupt deflate stream; decimal rows must be
# plain unsigned integers.
use scheme
use jsonx
use fsx
use gitx
use textx
use tensor_verifier

+ Metaflip:Gf2:RecordBoard
  # ---- name parsing (the regular expressions of the original, by hand) --------------------------

  -> .digit?(byte) (i64) bool
    byte >= 48 && byte <= 57

  # The index just past the run of ASCII digits that starts at `from`.
  -> .digits_end(text, from) (String i64) i64
    i = from ## i64
    n = text.size ## i64
    while i < n && Metaflip:Gf2:RecordBoard.digit?(text.byte_at(i))
      i += 1
    i

  # re.search(r'(\d+)x(\d+)(?:x(\d+))?', text): the two or three numbers of the leftmost match, or nil.
  -> .find_dims(text)
    n = text.size ## i64
    i = 0 ## i64
    while i < n
      if Metaflip:Gf2:RecordBoard.digit?(text.byte_at(i))
        stop = Metaflip:Gf2:RecordBoard.digits_end(text, i) ## i64
        if stop + 1 < n && text.byte_at(stop) == 120 && Metaflip:Gf2:RecordBoard.digit?(text.byte_at(stop + 1))
          second = Metaflip:Gf2:RecordBoard.digits_end(text, stop + 1) ## i64
          dims = [text.slice(i, stop - i).to_i, text.slice(stop + 1, second - stop - 1).to_i]
          if second + 1 < n && text.byte_at(second) == 120 && Metaflip:Gf2:RecordBoard.digit?(text.byte_at(second + 1))
            third = Metaflip:Gf2:RecordBoard.digits_end(text, second + 1) ## i64
            dims.push(text.slice(second + 1, third - second - 1).to_i)
          return dims
        i = stop
      else
        i += 1
    nil

  # The shape a file name, else its directory name, suggests: three dimensions, or two completed
  # with the first again (a square-ish hint `AxB` stands for AxBxA); nil when neither carries one.
  -> .shape_hint(path)
    dims = Metaflip:Gf2:RecordBoard.find_dims(Fsx.basename(path))
    dims = Metaflip:Gf2:RecordBoard.find_dims(Fsx.basename(Fsx.dirname(path))) if dims == nil
    return nil if dims == nil
    dims.size == 3 ? dims : dims + [dims[0]]

  # "NxMxP" of dimensions in ascending order (the key a shape is filed under).
  -> .sorted_key(dims)
    dims.sort.map(-> (d) d.to_s).join("x")

  # The same key with zero-padded numbers, so that string order is numeric tuple order.
  -> .order_key(key)
    key.split("x").map(-> (d) Textx.zero_pad(d.to_i, 9)).join("x")

  # A file name of the FastMatrixMultiplication layout, NxMxP_m<rank>[_anything]_<ZT|Z|Q>.json:
  # [sorted key, ring, rank], or nil. The original's pattern must match the last path component.
  -> .ring_entry(name)
    base = name.split("/").last()
    ring = nil
    tail = ""
    ["ZT", "Z", "Q"].each -> (candidate)
      suffix = "_" + candidate + ".json"
      if ring == nil && base.ends_with?(suffix)
        ring = candidate
        tail = base.slice(0, base.size - suffix.size)
    return nil if ring == nil
    dims = []
    at = 0 ## i64
    i = 0 ## i64
    while i < 3
      stop = Metaflip:Gf2:RecordBoard.digits_end(tail, at) ## i64
      return nil if stop == at
      dims.push(tail.slice(at, stop - at).to_i)
      at = stop
      if i < 2
        return nil if at >= tail.size || tail.byte_at(at) != 120
        at += 1
      i += 1
    return nil if tail.slice(at, 2) != "_m"
    stop = Metaflip:Gf2:RecordBoard.digits_end(tail, at + 2) ## i64
    return nil if stop == at + 2
    rank = tail.slice(at + 2, stop - at - 2).to_i
    rest = tail.slice(stop, tail.size - stop)
    return nil if rest != "" && !rest.starts_with?("_")
    [Metaflip:Gf2:RecordBoard.sorted_key(dims), ring, rank]

  # ---- witnesses ----------------------------------------------------------------------------------

  # The text of a witness file (a `.gz.b64` file is unpacked first); nil when it cannot be read.
  -> .load(path)
    raw = read_file(path)
    return nil if raw == nil
    return raw if !path.ends_with?(".gz.b64")
    begin
      Gzip.decode_b64_text(raw)
    rescue failure
      nil

  # The orderings the shape hint allows, without repeats, in itertools.permutations order.
  -> .orientations(hint)
    shapes = []
    seen = {}
    [[0, 1, 2], [0, 2, 1], [1, 0, 2], [1, 2, 0], [2, 0, 1], [2, 1, 0]].each -> (perm)
      shape = [hint[perm[0]], hint[perm[1]], hint[perm[2]]]
      name = shape.join("x")
      if !seen.key?(name)
        seen[name] = true
        shapes.push(shape)
    shapes

  # Decimal terms: lines `a b c`, each optionally led by `R `, after an optional rank line; comment
  # and blank lines are ignored. nil when a line is not three unsigned decimal numbers or the rank
  # line disagrees with the number of rows.
  -> .decimal_terms(text)
    lines = []
    Textx.splitlines(text).each -> (line)
      kept = line.strip
      lines.push(kept) if kept != "" && !line.starts_with?("#")
    if lines.size > 0 && Metaflip:Gf2:RecordBoard.digits_end(lines[0], 0) == lines[0].size
      count = lines.shift.to_i
      return nil if count != lines.size
    terms = []
    bad = false
    lines.each -> (line)
      row = line.starts_with?("R ") ? line.slice(2, line.size - 2) : line
      words = Textx.words(row)
      if words.size != 3
        bad = true
      else
        terms.push([words[0].to_i, words[1].to_i, words[2].to_i])
        words.each -> (word)
          bad = true if Metaflip:Gf2:RecordBoard.digits_end(word, 0) != word.size
    bad ? nil : terms

  # [shape, rank] of a witness whose terms sum to the matrix-multiplication tensor, or nil. MFW1 text
  # must be the canonical blob of its terms; other text carries no shape, so the orderings of the
  # dimensions in the file or directory name are tried in turn.
  -> .decode(path, text)
    if text.starts_with?("MFW1")
      scheme = nil
      begin
        scheme = Metaflip:Gf2:Scheme.parse(text)
      rescue failure
        return nil
      verdict = scheme.exact?(:both, text) ? [scheme.shape, scheme.rank] : nil
      scheme.release
      return verdict
    hint = Metaflip:Gf2:RecordBoard.shape_hint(path)
    return nil if hint == nil
    terms = Metaflip:Gf2:RecordBoard.decimal_terms(text)
    return nil if terms == nil
    us = terms.map(-> (t) t[0])
    vs = terms.map(-> (t) t[1])
    ws = terms.map(-> (t) t[2])
    verdict = nil
    last = nil
    Metaflip:Gf2:RecordBoard.orientations(hint).each -> (shape)
      if verdict == nil
        last = Metaflip:Gf2:Scheme.new(shape[0], shape[1], shape[2], us, vs, ws)
        verdict = [shape, terms.size] if last.exact?
    last.release if last != nil
    verdict

  # The Scheme of a witness whose terms sum to the matrix-multiplication tensor, or nil: what `decode` accepts, with
  # the terms (in the order the text gives them) for the caller, who releases it.
  -> .decode_scheme(path, text)
    if text.starts_with?("MFW1")
      scheme = nil
      begin
        scheme = Metaflip:Gf2:Scheme.parse(text)
      rescue failure
        return nil
      return scheme if scheme.exact?(:both, text)
      scheme.release
      return nil
    hint = Metaflip:Gf2:RecordBoard.shape_hint(path)
    return nil if hint == nil
    terms = Metaflip:Gf2:RecordBoard.decimal_terms(text)
    return nil if terms == nil
    us = terms.map(-> (t) t[0])
    vs = terms.map(-> (t) t[1])
    ws = terms.map(-> (t) t[2])
    found = nil
    Metaflip:Gf2:RecordBoard.orientations(hint).each -> (shape)
      candidate = Metaflip:Gf2:Scheme.new(shape[0], shape[1], shape[2], us, vs, ws)
      found = candidate if found == nil && candidate.exact?
    found

  # The files a root stands for: itself when it is a file, else everything below it that looks like a witness.
  -> .witness_files(roots)
    found = []
    roots.each -> (root)
      if File.exists?(root) && !File.directory?(root)
        found.push(root)
      elsif File.directory?(root)
        ["*.mfw", "*.mfw.gz.b64", "best.txt", "matmul_*_gf2.txt"].each -> (pattern)
          Fsx.rglob(root, pattern, files_only: true).each -> (path)
            found.push(path)
    # TODO(port): Array#sort orders a long string built by concatenation wrongly against a shorter one
    # (PORT-BLOCKERS.md, "Array#sort and strings built by concatenation"); copying each path with to_s first avoids it.
    found.map(-> (path) path.to_s).uniq.sort

  # The best verified witness per sorted shape, {key => [rank, path]}, the first file in path order
  # winning a tie. `cache` maps the SHA-256 of a file's bytes to its verdict ([shape, rank] or nil)
  # and gains the verdicts computed here. Prints the number of files and of new verdicts on stderr.
  -> .witnesses(roots, cache)
    paths = Metaflip:Gf2:RecordBoard.witness_files(roots)
    best = {}
    fresh = 0
    paths.each -> (path)
      text = Metaflip:Gf2:RecordBoard.load(path)
      if text != nil
        digest = Digest.sha256(text)
        verdict = nil
        if cache.key?(digest)
          verdict = cache[digest]
        else
          verdict = Metaflip:Gf2:RecordBoard.decode(path, text)
          cache[digest] = verdict
          fresh += 1
        if verdict != nil
          key = Metaflip:Gf2:RecordBoard.sorted_key(verdict[0])
          rank = verdict[1]
          best[key] = [rank, path] if !best.key?(key) || rank < best[key][0]
        Metaflip:Gf2:Bits.release(text)
    ccall("w_eputs", paths.size.to_s + " witness files; " + fresh.to_s + " newly verified")
    best

  # ---- public tables --------------------------------------------------------------------------

  # table[key] = min(rank, table[key]).
  -> .offer(table, key, rank)
    table[key] = rank if !table.key?(key) || rank < table[key]

  # {key => {ring => least rank}} from file names of the FMM layout, leaving out anything below a `known/` directory.
  -> .fmm_ranks(names)
    ranks = {}
    names.each -> (name)
      entry = name.include?("/known/") ? nil : Metaflip:Gf2:RecordBoard.ring_entry(name)
      if entry != nil
        ranks[entry[0]] = {} if !ranks.key?(entry[0])
        Metaflip:Gf2:RecordBoard.offer(ranks[entry[0]], entry[1], entry[2])
    ranks

  # [lille, any_ring, gf2]: the Lille rank per format (keyed as listed), and the least listed rank over
  # every ring and over the GF(2)-valid schemes (ZT and Z files, catalogue entries stamped F2).
  -> .public_tables(lille_path, catalog_path, fmm_repo, fmm_revision, extra_repos)
    lille = {}
    Jsonx.load(lille_path)["entries"].each -> (entry)
      lille[entry["format"].map(-> (d) d.to_s).join("x")] = entry["rank"]
    any_ring = {}
    gf2 = {}
    if catalog_path != nil
      Jsonx.load(catalog_path)["schemes"].each -> (scheme)
        if scheme["commutative"] != true
          key = Metaflip:Gf2:RecordBoard.sorted_key(scheme["format"])
          Metaflip:Gf2:RecordBoard.offer(any_ring, key, scheme["rank"])
          Metaflip:Gf2:RecordBoard.offer(gf2, key, scheme["rank"]) if scheme["fields"].include?("F2")
    names = []
    names = names + Gitx.new(fmm_repo).ls_tree(fmm_revision, "schemes") if fmm_repo != nil
    extra_repos.each -> (extra)
      Fsx.rglob(extra, "*.json").each -> (path)
        names.push(Fsx.relative_to(path, extra))
    Metaflip:Gf2:RecordBoard.fmm_ranks(names).each -> (key, rings)
      rings.each -> (ring, rank)
        Metaflip:Gf2:RecordBoard.offer(any_ring, key, rank)
        Metaflip:Gf2:RecordBoard.offer(gf2, key, rank) if ring == "ZT" || ring == "Z"
    lille.each -> (key, rank)
      Metaflip:Gf2:RecordBoard.offer(any_ring, key, rank)
    [lille, any_ring, gf2]

  # ---- classification -------------------------------------------------------------------------

  -> .kind(rank, best_any, best_gf2)
    return "below_all" if best_any != nil && rank < best_any
    return "gf2_valid_only" if best_gf2 != nil && rank < best_gf2
    return "tie" if best_any != nil && rank == best_any
    return "no_public_rank" if best_any == nil
    "above"

  # One Hash per shape with a verified witness, in numeric shape order: shape, rank, kind and the listed
  # ranks that decided it (lille is keyed by the sorted shape too, as the original looks it up).
  -> .rows(ours, tables)
    keys = ours.keys.sort_by(-> (key) Metaflip:Gf2:RecordBoard.order_key(key))
    keys.map -> (key)
      rank = ours[key][0]
      best_any = tables[1][key]
      best_gf2 = tables[2][key]
      {"shape" => key, "rank" => rank, "kind" => Metaflip:Gf2:RecordBoard.kind(rank, best_any, best_gf2), "lille" => tables[0][key], "best_any" => best_any, "best_gf2_valid" => best_gf2, "path" => ours[key][1]}

  # The one-line summary: the number of shapes and the count per class.
  -> .summary(rows)
    counts = {}
    rows.each -> (row)
      current = counts.key?(row["kind"]) ? counts[row["kind"]] : 0
      counts[row["kind"]] = current + 1
    parts = ["below_all", "gf2_valid_only", "tie", "above", "no_public_rank"].map -> (name)
      number = counts.key?(name) ? counts[name] : 0
      name + "=" + number.to_s
    rows.size.to_s + " shapes with verified witnesses: " + parts.join(", ")

  # The records of the two record classes, one line each (-v).
  -> .verbose_lines(rows)
    lines = []
    rows.each -> (row)
      if row["kind"] == "below_all" || row["kind"] == "gf2_valid_only"
        lines.push(Textx.pad_left(row["kind"], 15) + " " + Textx.pad_left(row["shape"], 10) + " " + Textx.pad_left(row["rank"].to_s, 6) + " any=" + Metaflip:Gf2:RecordBoard.none_text(row["best_any"]) + " gf2=" + Metaflip:Gf2:RecordBoard.none_text(row["best_gf2_valid"]) + " lille=" + Metaflip:Gf2:RecordBoard.none_text(row["lille"]))
    lines

  -> .none_text(value)
    value == nil ? "None" : value.to_s
