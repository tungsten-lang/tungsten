# Replay of matmulcatalog lineage recipes over GF(2) into explicit tensors. Port of tools/mmc_gf2_replay.py.
#
# matmulcatalog (https://github.com/solven-eu/matmulcatalog, arXiv:2606.13408) keeps many schemes as recipes ("derived" files:
# Recombination, SerendipitousProduct, Kronecker products, concatenations, projections) over atomic schemes with explicit
# coefficients. Its `fields` label is inferred from recorded ranks and can over-claim: a recipe whose rank needs a leaf that is
# valid only over Q or F3 is still stamped F2. Replaying with F2-valid leaves shows what each recipe really reaches over GF(2); the
# result is checked against the complete matrix-multiplication tensor.
#
#   MmcSource.new(clone, revision = "HEAD", cache_dir = "mmc-cache")   a catalogue checkout pinned at one revision (a blob-less
#                                       partial clone is enough: files are read from `cache_dir/<revision[0..12]>/json` or from git)
#     .revision .catalog .by_file .by_key .by_stem .by_h7 .by_sorted .tree .mfw_cache
#     .raw(path) .load(path) .atom_info(path)
#   MmcReplayer.new(source, board: nil, allow_nonf2: false, use_disk_cache: true)
#     .materialize_file(path)           the scheme of one catalogue file (an atom, or a recipe replayed), exact over GF(2)
#     .replay(lineage)                  the scheme of a lineage tree (a parsed JSON Hash)
#     .best_rank(shape) .best(shape)    the cheapest F2-valid scheme of a shape (and orientation) the catalogue holds
#     .deps_file                        path => the dependencies of a materialized file: ["atom", path], a board shape, ["nonf2", ...]
#     .reset_dependencies               what the next materialize_file records starts from nothing (a dependency record per target)
#     .board                            the extra exact leaves, {"NxMxP" (sorted) => [rank, witness path]}
#   Mmc.load_atom_json(d), Mmc.parity(v)  an atom file's tensor over GF(2); a coefficient mod two
#
# Errors: ReplayError for everything the original raises as ReplayError, and for the ValueError, KeyError and the like it
# turns into one (with the original's message); FetchError (the original's RuntimeError) when a file is neither cached nor in git.
# A scheme is a Metaflip:Gf2:Scheme; the replay's results are the original's, term order included (the disk cache holds sorted terms).
#
# Differences from the original: a missing blob is one failed `git show` (no retries with sleeps), and the Python exceptions the
# original lets through (TypeError of malformed JSON and the like) are ReplayErrors here.
use scheme
use mmc_alg
use jsonx
use fsx
use gitx
use textx
use floatx
use record_board

+ ReplayError < Error
+ FetchError < Error

# A Python exception of the original, as the replayer reports it: "<type>: <repr>".
+ MmcFailure < Error
  -> new(@type_name, @message)
  ro :type_name

+ Mmc
  # ---- small parsers (the regular expressions of the original, by hand) -----------------------------------

  -> .digit?(byte) (i64) bool
    byte >= 48 && byte <= 57

  # The index just past the run of ASCII digits starting at `from` (from itself when there is none).
  -> .digits_end(text, from) (String i64) i64
    i = from ## i64
    n = text.size ## i64
    while i < n && Mmc.digit?(text.byte_at(i))
      i += 1
    i

  -> .all_digits?(text)
    text.size > 0 && Mmc.digits_end(text, 0) == text.size

  # `A` x `B` x `C` (digits) at `from`: [a, b, c, end] or nil
  -> .dims_at(text, from)
    stop = Mmc.digits_end(text, from)
    return nil if stop == from || stop >= text.size || text.byte_at(stop) != 120
    first = text.slice(from, stop - from).to_i
    second_start = stop + 1
    second_stop = Mmc.digits_end(text, second_start)
    return nil if second_stop == second_start || second_stop >= text.size || text.byte_at(second_stop) != 120
    second = text.slice(second_start, second_stop - second_start).to_i
    third_start = second_stop + 1
    third_stop = Mmc.digits_end(text, third_start)
    return nil if third_stop == third_start
    [first, second, text.slice(third_start, third_stop - third_start).to_i, third_stop]

  # SHAPE_REF.fullmatch: (?:(naive|direct)-)?(\d+)x(\d+)x(\d+)(?:-(direct|naive))? -> [shape, naive?] or nil; naive? is
  # whether the reference asks for the naive scheme (a prefix, or the suffix `naive`)
  -> .shape_ref(text)
    start = 0
    ["naive-", "direct-"].each -> (prefix)
      start = prefix.size if start == 0 && text.starts_with?(prefix)
    found = Mmc.dims_at(text, start)
    return nil if found == nil
    rest = text.slice(found[3], text.size - found[3])
    return nil if rest != "" && rest != "-naive" && rest != "-direct"
    [[found[0], found[1], found[2]], start > 0 || rest == "-naive"]

  -> .shape_key(shape)
    shape.sort.map(-> (d) d.to_s).join("x")

  # \w
  -> .word_byte?(byte) (i64) bool
    (byte >= 48 && byte <= 57) || (byte >= 65 && byte <= 90) || (byte >= 97 && byte <= 122) || byte == 95

  # `count` comma-separated numbers at `from`: [numbers, end] or nil
  -> .int_list_at(text, from, count)
    pos = from
    numbers = []
    count.times -> (i)
      stop = Mmc.digits_end(text, pos)
      pos = -1 if stop == pos || pos < 0
      if pos >= 0
        numbers.push(text.slice(pos, stop - pos).to_i)
        pos = stop
        if i < count - 1
          pos = text.slice(pos, 1) == "," ? pos + 1 : -1
    return nil if pos < 0
    [numbers, pos]

  # ` / <a,b,c>=r` at the start of `text`: [[a, b, c], rest of the text] or nil
  -> .orbit_at(text)
    return nil if !text.starts_with?(" / <")
    parsed = Mmc.int_list_at(text, 4, 3)
    return nil if parsed == nil || text.slice(parsed[1], 2) != ">="
    stop = Mmc.digits_end(text, parsed[1] + 2)
    return nil if stop == parsed[1] + 2
    [parsed[0], text.slice(stop, text.size - stop)]

  # (DIS09Lemma4|TA_lita|TA_sz)\(n=(\d+)\)
  -> .parametric?(ref)
    found = false
    ["DIS09Lemma4", "TA_lita", "TA_sz"].each -> (name)
      head = name + "(n="
      if ref.starts_with?(head) && ref.ends_with?(")")
        found = true if Mmc.all_digits?(ref.slice(head.size, ref.size - head.size - 1))
    found

  # re.search(r"(\d+)x(\d+)x(\d+)", ref) or re.search(r"<\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*>", ref): [a, b, c] or nil
  -> .search_dims(ref)
    i = 0
    while i < ref.size
      found = Mmc.dims_at(ref, i)
      return [found[0], found[1], found[2]] if found != nil
      i += 1
    i = 0
    while i < ref.size
      if ref.byte_at(i) == 60
        numbers = []
        pos = i + 1
        ok = true
        3.times -> (k)
          if ok
            while pos < ref.size && Mmc.space_byte?(ref.byte_at(pos))
              pos += 1
            stop = Mmc.digits_end(ref, pos)
            if stop == pos
              ok = false
            else
              numbers.push(ref.slice(pos, stop - pos).to_i)
              pos = stop
              while pos < ref.size && Mmc.space_byte?(ref.byte_at(pos))
                pos += 1
              if k < 2
                if ref.slice(pos, 1) == ","
                  pos += 1
                else
                  ok = false
              elsif ref.slice(pos, 1) != ">"
                ok = false
        return numbers if ok
      i += 1
    nil

  -> .space_byte?(byte) (i64) bool
    byte == 32 || (byte >= 9 && byte <= 13)

  # ---- coefficients --------------------------------------------------------------------------------------------

  # Fraction(float).limit_denominator(10**6): [numerator, denominator]
  -> .limited_fraction(value)
    parts = Floatx.magnitude(value)
    mantissa = parts[0]
    exponent = parts[1]
    negative = Floatx.negative?(value)
    numerator = mantissa
    denominator = 1
    if exponent >= 0
      numerator = mantissa << exponent
    else
      denominator = 1 << (0 - exponent)
      divisor = numerator.gcd(denominator)
      numerator = numerator / divisor
      denominator = denominator / divisor
    numerator = 0 - numerator if negative
    limit = 1000000
    return [numerator, denominator] if denominator <= limit
    p0 = 0
    q0 = 1
    p1 = 1
    q1 = 0
    n = numerator
    d = denominator
    while true
      a = Mmc.floor_div(n, d)
      q2 = q0 + a * q1
      break if q2 > limit
      next_p = p0 + a * p1
      p0 = p1
      q0 = q1
      p1 = next_p
      q1 = q2
      remainder = n - a * d
      n = d
      d = remainder
    k = (limit - q0) / q1
    if 2 * d * (q0 + k * q1) <= denominator
      [p1, q1]
    else
      [p0 + k * p1, q0 + k * q1]

  # Python's n // d for a positive d
  -> .floor_div(n, d)
    quotient = n / d
    quotient -= 1 if n % d != 0 && n < 0
    quotient

  # Fraction(text): [numerator, denominator] (reduced) of a decimal, a rational "a/b" or a number with an exponent, else nil
  -> .parse_fraction(raw)
    text = raw.strip
    return nil if text == ""
    sign = 1
    if text.starts_with?("-")
      sign = 0 - 1
      text = text.slice(1, text.size - 1)
    elsif text.starts_with?("+")
      text = text.slice(1, text.size - 1)
    return nil if text == ""
    numerator = nil
    denominator = 1
    slash = text.index("/")
    if slash != nil
      top = text.slice(0, slash)
      bottom = text.slice(slash + 1, text.size - slash - 1)
      return nil if !Mmc.all_digits?(top) || !Mmc.all_digits?(bottom)
      numerator = top.to_i
      denominator = bottom.to_i
      raise MmcFailure.new("ZeroDivisionError", "Fraction(" + (sign * numerator).to_s + ", 0)") if denominator == 0
    else
      mantissa = text
      exponent = 0
      marker = text.index("e")
      marker = text.index("E") if marker == nil
      if marker != nil
        mantissa = text.slice(0, marker)
        tail = text.slice(marker + 1, text.size - marker - 1)
        negative_exponent = false
        if tail.starts_with?("-")
          negative_exponent = true
          tail = tail.slice(1, tail.size - 1)
        elsif tail.starts_with?("+")
          tail = tail.slice(1, tail.size - 1)
        return nil if !Mmc.all_digits?(tail)
        exponent = tail.to_i
        exponent = 0 - exponent if negative_exponent
      point = mantissa.index(".")
      whole = mantissa
      fraction = ""
      if point != nil
        whole = mantissa.slice(0, point)
        fraction = mantissa.slice(point + 1, mantissa.size - point - 1)
      return nil if whole == "" && fraction == ""
      return nil if (whole != "" && !Mmc.all_digits?(whole)) || (fraction != "" && !Mmc.all_digits?(fraction))
      digits = whole + fraction
      numerator = digits.to_i
      exponent -= fraction.size
      if exponent >= 0
        numerator = numerator * (10 ** exponent)
      else
        denominator = 10 ** (0 - exponent)
    divisor = numerator.gcd(denominator)
    divisor = 1 if divisor == 0
    [sign * (numerator / divisor), denominator / divisor]

  # a coefficient mod two (the replay's parity: bool, int, float and anything that reads as a Fraction)
  -> .parity(v)
    kind = type(v)
    raise ReplayError.new("bool coefficient") if kind == "Boolean"
    return v & 1 if kind == "Int" || kind == "BigInt"
    fraction = nil
    if kind == "Float" || kind == "Decimal"
      x = Floatx.of(v)
      whole = Floatx.fixed(x, 0)
      integral = Floatx.fixed(x, 20).ends_with?("." + ("0" * 20))
      if integral
        return whole.to_i & 1
      fraction = Mmc.limited_fraction(x)
      approx = Floatx.ratio(fraction[0], fraction[1])
      difference = approx - x
      difference = 0.0 - difference if difference < 0.0
      raise ReplayError.new("non-rational coefficient " + Floatx.repr(x)) if difference > ~1e-9
    else
      text = v == nil ? "None" : v.to_s
      fraction = Mmc.parse_fraction(text)
      raise MmcFailure.new("ValueError", "Invalid literal for Fraction: " + Textx.repr_str(text.strip)) if fraction == nil
    raise ReplayError.new("even denominator coefficient " + Mmc.python_repr(v)) if fraction[1] % 2 == 0
    fraction[0] & 1

  # repr() of the JSON values a coefficient can be: str, int, float, None
  -> .python_repr(v)
    kind = type(v)
    return Textx.repr_str(v) if kind == "String"
    return Floatx.repr(v) if kind == "Float"
    return "None" if v == nil
    v.to_s

  # ---- atom files -----------------------------------------------------------------------------------------------

  # rows of [position, value] pairs from the sparse formats
  -> .sparse_rows(node, rank)
    out = []
    kind = type(node)
    if kind == "Array"
      raise ReplayError.new("sparse rows " + node.size.to_s + " != rank " + rank.to_s) if node.size != rank
      node.each -> (obj)
        row = []
        obj.each -> (key, value)
          row.push([key.to_i, value])
        out.push(row)
    elsif kind == "Hash"
      rank.times -> (k)
        row = node[k.to_s]
        raise ReplayError.new("row-map missing " + k.to_s) if row == nil
        raise ReplayError.new("row-map i/c mismatch") if row["i"].size != row["c"].size
        pairs = []
        row["i"].each_with_index -> (position, j)
          pairs.push([position, row["c"][j]])
        out.push(pairs)
    else
      raise ReplayError.new("bad sparse node")
    out

  # the mask of the coefficients of one factor row that are odd, toggling bit position(pos)
  -> .toggle_mask(pairs, dim, public_w, n1, n3, label)
    words = Metaflip:Gf2:Bits.limbs_for(dim)
    limbs = i64[words]
    pairs.each -> (pair)
      pos = pair[0].to_i
      raise ReplayError.new(label + " pos range") if pos < 0 || pos >= dim
      if Mmc.parity(pair[1]) == 1
        at = pos
        at = (pos % n1) * n3 + pos / n1 if public_w
        limbs[at >> 6] = limbs[at >> 6] ^ Metaflip:Gf2:Bits.bit_mask(at)
    mask = Metaflip:Gf2:Bits.from_limbs(limbs, 0, words)
    Metaflip:Gf2:Bits.release(limbs)
    mask

  -> .nonzero_entries(row)
    pairs = []
    row.each_with_index -> (v, i)
      keep = true
      keep = false if v == 0 || v == "0"
      pairs.push([i, v]) if keep
    pairs

  # an atom file's tensor over GF(2)
  -> .load_atom_json(d)
    dims = d["n"]
    n1 = dims[0]
    n2 = dims[1]
    n3 = dims[2]
    rank = d["m"]
    dim_u = n1 * n2
    dim_v = n2 * n3
    dim_w = n1 * n3
    u_rows = nil
    v_rows = nil
    w_rows = nil
    if d.key?("u_sparse")
      u_rows = Mmc.sparse_rows(d["u_sparse"], rank)
      v_rows = Mmc.sparse_rows(d["v_sparse"], rank)
      w_rows = Mmc.sparse_rows(d["w_sparse"], rank)
    elsif d.key?("u")
      first = d["u"].size > 0 ? d["u"][0] : []
      if first.size > 0 && type(first[0]) == "Hash"
        raise ReplayError.new("reduced format with fresh intermediates unsupported") if d.key?("u_fresh") || d.key?("v_fresh") || d.key?("w_fresh")
        u_rows = d["u"].map -> (row)
          row.map(-> (o) [o["index"], o["value"]])
        v_rows = d["v"].map -> (row)
          row.map(-> (o) [o["index"], o["value"]])
        w_rows = []
        rank.times -> (k)
          w_rows.push([])
        raise ReplayError.new("reduced w rows") if d["w"].size != dim_w
        d["w"].each_with_index -> (row, pd)
          row.each -> (o)
            w_rows[o["index"]].push([pd, o["value"]])
      else
        [["u", dim_u], ["v", dim_v], ["w", dim_w]].each -> (spec)
          rows = d[spec[0]]
          bad = rows.size != rank
          rows.each -> (row)
            bad = true if row.size != spec[1]
          raise ReplayError.new("dense " + spec[0] + " wrong size") if bad
        u_rows = d["u"].map(-> (row) Mmc.nonzero_entries(row))
        v_rows = d["v"].map(-> (row) Mmc.nonzero_entries(row))
        w_rows = d["w"].map(-> (row) Mmc.nonzero_entries(row))
    else
      raise ReplayError.new("no factor matrices")
    raise ReplayError.new("rank mismatch") if u_rows.size != rank || v_rows.size != rank || w_rows.size != rank
    terms = []
    rank.times -> (k)
      a = Mmc.toggle_mask(u_rows[k], dim_u, false, n1, n3, "u")
      b = Mmc.toggle_mask(v_rows[k], dim_v, false, n1, n3, "v")
      c = Mmc.toggle_mask(w_rows[k], dim_w, true, n1, n3, "w")
      terms.push([a, b, c])
    Metaflip:Gf2:Scheme.from_terms(n1, n2, n3, terms)

  # a catalogue file without factor matrices is a recipe (a stub)
  -> .stub?(d)
    !d.key?("u") && !d.key?("u_sparse")

  # ---- the MFW1 cache --------------------------------------------------------------------------------------------

  -> .write_mfw(path, a)
    text = Metaflip:Gf2:Scheme.from_terms(a.n, a.m, a.p, a.terms.sort).blob
    Fsx.atomic_write(path, text)

  # The terms in the order the file lists them (no re-sorting: the writer sorted them).
  -> .read_mfw(path)
    lines = Textx.splitlines(Fsx.read(path))
    head = lines[0].split(" ")
    raise ReplayError.new("bad MFW1 cache file " + path) if head.size != 5 || head[0] != "MFW1"
    terms = []
    lines.each_with_index -> (line, i)
      if i > 0
        words = line.split(" ")
        terms.push([Metaflip:Gf2:Bits.from_hex(words[0]), Metaflip:Gf2:Bits.from_hex(words[1]), Metaflip:Gf2:Bits.from_hex(words[2])])
    raise ReplayError.new("bad MFW1 cache file " + path) if terms.size != head[4].to_i
    Metaflip:Gf2:Scheme.from_terms(head[1].to_i, head[2].to_i, head[3].to_i, terms)

# ---- a pinned catalogue checkout ----------------------------------------------------------------------------------
+ MmcSource
  ro :clone, :revision, :catalog, :by_file, :by_key, :by_stem, :by_h7, :by_sorted, :tree, :mfw_cache, :json_cache

  -> prefix
    "src/main/resources/schemes/"

  -> new(@clone, revision = "HEAD", cache_dir = "mmc-cache")
    @git = Gitx.new(@clone.to_s)
    @revision = @git.rev_parse(revision).strip
    root = Fsx.join(cache_dir, @revision.slice(0, 12))
    @json_cache = Fsx.join(root, "json")
    @mfw_cache = Fsx.join(root, "mfw")
    Fsx.mkdir_p(@mfw_cache)
    names = @git.ls_tree(@revision, prefix)
    @tree = []
    names.each -> (name)
      @tree.push(name.slice(prefix.size, name.size - prefix.size)) if name.starts_with?(prefix)
    @by_stem = {}
    @by_h7 = {}
    @by_sorted = {}
    @tree.each -> (file)
      base = Fsx.basename(file)
      stem = base.ends_with?(".json") ? base.slice(0, base.size - 5) : base
      Textx.push_to(@by_stem, stem, file)
      parsed = filename_parts(base)
      if parsed != nil
        Textx.push_to(@by_h7, parsed[5], file)
        Textx.push_to(@by_sorted, Mmc.shape_key([parsed[0], parsed[1], parsed[2]]), [parsed[3], file])
    @by_sorted.each -> (key, entries)
      @by_sorted[key] = Textx.sort_by(entries) -> (entry) [entry[0], entry[1]]
    catalog_text = @git.show(@revision, "docs/catalog.json")
    raise FetchError.new("docs/catalog.json is not in " + @clone.to_s) if catalog_text == nil
    @catalog = Jsonx.loads(catalog_text)["schemes"]
    @by_file = {}
    @by_key = {}
    @catalog.each -> (entry)
      @by_file[entry["file"]] = entry
    @catalog.each -> (entry)
      if !(entry.key?("complex") && entry["complex"] != nil && entry["complex"] != false && entry["complex"] != 0)
        Textx.push_to(@by_key, Mmc.shape_key(entry["format"]), entry)

  # FNAME: ^(\d+)x(\d+)x(\d+)-r(\d+)-(.*)-([0-9a-f]{7})\.json$ -> [n, m, p, rank, middle, hash7] or nil
  -> filename_parts(base)
    return nil if !base.ends_with?(".json")
    core = base.slice(0, base.size - 5)
    return nil if core.size < 9 || core.slice(core.size - 8, 1) != "-"
    hash = core.slice(core.size - 7, 7)
    ok = true
    hash.bytes.each -> (byte)
      ok = false if !((byte >= 48 && byte <= 57) || (byte >= 97 && byte <= 102))
    return nil if !ok
    head = core.slice(0, core.size - 8)
    dims = Mmc.dims_at(head, 0)
    return nil if dims == nil
    at = dims[3]
    return nil if head.slice(at, 2) != "-r"
    stop = Mmc.digits_end(head, at + 2)
    return nil if stop == at + 2 || head.slice(stop, 1) != "-"
    [dims[0], dims[1], dims[2], head.slice(at + 2, stop - at - 2).to_i, head.slice(stop + 1, head.size - stop - 1), hash]

  # The text of schemes/<path> at the pinned revision (from the cache, else from git; a file read from git is cached).
  -> raw(path)
    cached = Fsx.join(@json_cache, path)
    return Fsx.read(cached) if Fsx.regular?(cached)
    shown = @git.show(@revision, prefix + path)
    raise FetchError.new("fetch failed " + path + ": the blob is not in the clone") if shown == nil || shown == ""
    Fsx.mkdir_p(Fsx.dirname(cached))
    Fsx.atomic_write(cached, shown)
    shown

  -> load(path)
    Jsonx.loads(raw(path))

  # The catalogue's own attribution fields for one scheme file.
  -> atom_info(path)
    entry = @by_file.key?(path) ? @by_file[path] : {}
    format = entry.key?("format") ? entry["format"] : []
    {"file" => path, "shape" => format.map(-> (d) d.to_s).join("x"), "rank" => entry["rank"], "source" => entry["source"], "year" => entry["year"], "fields" => entry["fields"], "source_scheme_url" => entry["source_scheme_url"], "source_paper_url" => entry["source_paper_url"]}

# ---- the replayer ---------------------------------------------------------------------------------------------------
+ MmcReplayer
  ro :deps_file, :log, :src, :board

  # `board`: {"NxMxP" (sorted) => [rank, witness path]} of extra exact GF(2) leaves (optional). `allow_nonf2` also replays
  # catalogue schemes that are not stamped F2 (diagnostics).
  -> new(@src, board: nil, allow_nonf2: false, use_disk_cache: true)
    @file_memo = {}
    @file_error = {}
    @best_memo = {}
    @active = []
    @disk = use_disk_cache
    @board = board == nil ? {} : board
    @use_board = @board.size > 0
    @allow_nonf2 = allow_nonf2
    suffix = ""
    if allow_nonf2
      suffix = "_wide"
    elsif @use_board
      suffix = "_board"
    @cachedir = @src.mfw_cache + suffix
    Fsx.mkdir_p(@cachedir)
    # Dependencies of a materialized file: board leaves (sorted shape), ["nonf2", *shape] for a Q/F3-only leaf, and
    # ["atom", path] for every atomic catalogue file used; each as a value of a Hash keyed by its JSON text.
    @deps_file = {}
    @deps_best = {}
    @dep_stack = [{}]
    @log = []
    @verbose = env("MMC_VERBOSE") != nil && env("MMC_VERBOSE") != ""

  # The dependencies the next materialize_file reports are only its own (the original assigns a fresh `dep_stack`).
  -> reset_dependencies
    @dep_stack = [{}]

  -> note_log(line)
    @log.push(line)
    ccall("w_eputs", line) if @verbose

  -> note(deps)
    top = @dep_stack.last
    deps.each -> (key, dep)
      top[key] = dep

  -> dep_key(dep)
    Jsonx.dumps(dep)

  -> need(node, key)
    raise MmcFailure.new("KeyError", key) if type(node) != "Hash" || !node.key?(key)
    node[key]

  # "path: Type: repr" of a Python exception that is not a ReplayError (what the original files it under)
  -> describe(failure)
    return "ValueError: ValueError(" + Textx.repr_str(failure.message.to_s) + ")" if failure.is_a?(MmcError)
    return "JSONDecodeError: JSONDecodeError(" + Textx.repr_str(failure.message.to_s) + ")" if failure.is_a?(JsonError)
    return failure.type_name + ": " + failure.type_name + "(" + Textx.repr_str(failure.message.to_s) + ")" if failure.is_a?(MmcFailure)
    "TypeError: " + failure.message.to_s

  # ---- files
  -> materialize_file(path)
    if @file_memo.key?(path)
      note(@deps_file.key?(path) ? @deps_file[path] : {})
      return @file_memo[path]
    raise @file_error[path] if @file_error.key?(path)
    raise ReplayError.new("lineage cycle: " + (@active + [path]).join(" -> ")) if @active.include?(path)
    board_file = path.starts_with?("BOARD:")
    atomic = board_file || !Mmc.stub?(@src.load(path))
    cp = Fsx.join(atomic ? @src.mfw_cache : @cachedir, path.replace("/", "__") + ".mfw")
    depf = cp + ".deps.json"
    if @disk && Fsx.regular?(cp) && (atomic || Fsx.regular?(depf))
      a = Mmc.read_mfw(cp)
      deps = {}
      if board_file
        dep = Jsonx.loads(path.split(":")[1])
        deps[dep_key(dep)] = dep
      elsif atomic
        dep = ["atom", path]
        deps[dep_key(dep)] = dep
      else
        Jsonx.load(depf).each -> (dep)
          deps[dep_key(dep)] = dep
      @file_memo[path] = a
      @deps_file[path] = deps
      note(deps)
      return a
    @active.push(path)
    @dep_stack.push({})
    ok = false
    begin
      declared = nil
      a = nil
      if board_file
        pieces = path.split(":")
        key = Jsonx.loads(pieces[1])
        bpath = pieces.slice(2, pieces.size - 2).join(":")
        text = Metaflip:Gf2:RecordBoard.load(bpath)
        loaded = text == nil ? nil : Metaflip:Gf2:RecordBoard.decode_scheme(bpath, text)
        raise ReplayError.new("board witness shape mismatch " + path) if loaded == nil || loaded.sorted_shape != key
        a = Metaflip:Gf2:MmcAlg.clean(loaded)
        @dep_stack.last[dep_key(key)] = key
        declared = @board.key?(Mmc.shape_key(key)) ? @board[Mmc.shape_key(key)][0] : nil
      elsif Mmc.stub?(@src.load(path))
        d = @src.load(path)
        raise ReplayError.new("stub without lineage " + path) if !d.key?("lineage") || d["lineage"] == nil
        a = replay(d["lineage"])
        want = need(d, "n")
        if !a.same_shape?(want)
          o = a.orient_as(want)
          raise ReplayError.new(path + " replayed to " + Metaflip:Gf2:MmcAlg.tuple_repr([a.n, a.m, a.p]) + ", declared " + Metaflip:Gf2:MmcAlg.tuple_repr(want)) if o == nil
          a = o
        a = Metaflip:Gf2:MmcAlg.clean(a)
        declared = d["m"]
      else
        d = @src.load(path)
        a = Metaflip:Gf2:MmcAlg.clean(Mmc.load_atom_json(d))
        dep = ["atom", path]
        @dep_stack.last[dep_key(dep)] = dep
        declared = d["m"]
      raise ReplayError.new("GF(2) verification failed for " + path) if !a.exact?
      # The disk cache stores sorted terms and the constructions here index terms by position, so a freshly computed scheme must
      # carry the same order a cache hit would: otherwise a result depends on which files an earlier replay had already materialized.
      a = Metaflip:Gf2:Scheme.from_terms(a.n, a.m, a.p, a.terms.sort)
      note_log(["materialized", path, Metaflip:Gf2:MmcAlg.repr(a), "declared", declared].map(-> (part) part.to_s).join(" "))
      @file_memo[path] = a
      deps = @dep_stack.last
      copy = {}
      deps.each -> (key, dep)
        copy[key] = dep
      @deps_file[path] = copy
      if @disk
        Mmc.write_mfw(cp, a)
        if !atomic
          ordered = Textx.sorted(deps.keys)
          Fsx.atomic_write(depf, Jsonx.dumps(ordered.map(-> (key) deps[key])))
      ok = true
      return a
    rescue failure
      raise failure if failure.is_a?(FetchError)
      err = failure
      if !failure.is_a?(ReplayError)
        err = ReplayError.new(path + ": " + describe(failure))
      @file_error[path] = err
      raise err
    ensure
      @active.pop
      finished = @dep_stack.pop
      note(finished) if ok

  # ---- best at a shape
  -> candidates(key)
    found = []
    (@src.by_key.key?(key) ? @src.by_key[key] : []).each -> (e)
      fields = e["fields"]
      include_f2 = fields.include?("F2")
      commutative = e.key?("commutative") && e["commutative"] != nil && e["commutative"] != false
      other = @allow_nonf2 && !commutative && fields.size > 0
      found.push(e) if include_f2 || other
    if @use_board && @board.key?(key)
      entry = @board[key]
      found.push({"rank" => entry[0], "atom" => true, "file" => "BOARD:" + Jsonx.dumps(key.split("x").map(-> (d) d.to_i)) + ":" + entry[1]})
    Textx.sort_by(found) -> (e) [e["rank"], e["file"].starts_with?("BOARD:") ? 1 : 0, e["atom"] ? 0 : 1, e["file"]]

  -> best_rank(shape)
    dims = shape.sort
    return 0 if dims[0] == 0
    key = dims.map(-> (d) d.to_s).join("x")
    return @best_memo[key].rank if @best_memo.key?(key)
    naive_rank = dims[0] * dims[1] * dims[2]
    return naive_rank if dims[0] == 1
    ranks = [naive_rank]
    candidates(key).each -> (e)
      ranks.push(e["rank"])
    ranks.min

  -> best(shape)
    dims = shape.sort
    key = dims.map(-> (d) d.to_s).join("x")
    if @best_memo.key?(key)
      note(@deps_best.key?(key) ? @deps_best[key] : {})
      return @best_memo[key].orient_as(shape)
    naive_rank = dims[0] * dims[1] * dims[2]
    if dims[0] == 1
      a = Metaflip:Gf2:Scheme.naive(dims[0], dims[1], dims[2])
      @best_memo[key] = a
      return a.orient_as(shape)
    found = nil
    found_deps = {}
    stop = false
    candidates(key).each -> (e)
      stop = true if found != nil && found.rank <= e["rank"]
      stop = true if e["rank"] >= naive_rank
      if !stop
        @dep_stack.push({})
        a = nil
        deps = nil
        begin
          a = materialize_file(e["file"])
        rescue failure
          raise failure if failure.is_a?(FetchError)
          note_log(["best", key, "candidate failed", e["file"], failure.message.to_s.slice(0, 300)].map(-> (part) part.to_s).join(" "))
          a = nil
        ensure
          deps = @dep_stack.pop
        if a != nil && (found == nil || a.rank < found.rank)
          found = a
          found_deps = {}
          deps.each -> (k, dep)
            found_deps[k] = dep
          if !e["file"].starts_with?("BOARD:") && !e["fields"].include?("F2")
            nonf2 = ["nonf2"] + dims
            found_deps[dep_key(nonf2)] = nonf2
    if found == nil || found.rank > naive_rank
      found = Metaflip:Gf2:Scheme.naive(dims[0], dims[1], dims[2])
      found_deps = {}
    @best_memo[key] = found
    @deps_best[key] = found_deps
    note(found_deps)
    found.orient_as(shape)

  # ---- leaf references
  -> file_by_basename(base)
    stem = base.ends_with?(".json") ? base.slice(0, base.size - 5) : base
    files = @src.by_stem[stem]
    raise ReplayError.new("no file for " + base) if files == nil || files.size == 0
    files[0]

  # the dimensions of a catalogue path's file name, `.*/(\d+)x(\d+)x(\d+)-`: [a, b, c] or nil
  -> path_dims(file)
    slash = file.rindex("/")
    return nil if slash == nil
    found = Mmc.dims_at(file, slash + 1)
    return nil if found == nil || file.slice(found[3], 1) != "-"
    [found[0], found[1], found[2]]

  # ext[NAME] / <a,b,c>=r :: MODE  ->  [name, [a, b, c] or nil, mode or nil], or nil when the text is not of that form
  -> ext_ref(ref)
    return nil if !ref.starts_with?("ext\[")
    close = ref.index("]", 4)
    return nil if close == nil || close == 4
    name = ref.slice(4, close - 4)
    rest = ref.slice(close + 1, ref.size - close - 1)
    orbit = nil
    parsed = Mmc.orbit_at(rest)
    if parsed != nil
      orbit = parsed[0]
      rest = parsed[1]
    mode = nil
    if rest.starts_with?(" :: ")
      mode = rest.slice(4, rest.size - 4)
      return nil if mode == "" || mode.index(" ") != nil
      rest = ""
    return nil if rest != ""
    [name, orbit, mode]

  # `NAME<a,b,c>=r / <a2,b2,c2>=r2 :: MODE` -> [name, shape, rank, orbit or nil, mode or nil], or nil
  -> named_ref(ref)
    stop = 0
    while stop < ref.size && Mmc.word_byte?(ref.byte_at(stop))
      stop += 1
    return nil if stop == 0 || ref.slice(stop, 1) != "<"
    first = Mmc.int_list_at(ref, stop + 1, 3)
    return nil if first == nil || ref.slice(first[1], 2) != ">="
    digits_stop = Mmc.digits_end(ref, first[1] + 2)
    return nil if digits_stop == first[1] + 2
    rank = ref.slice(first[1] + 2, digits_stop - first[1] - 2).to_i
    rest = ref.slice(digits_stop, ref.size - digits_stop)
    orbit = nil
    parsed = Mmc.orbit_at(rest)
    if parsed != nil
      orbit = parsed[0]
      rest = parsed[1]
    mode = nil
    if rest.starts_with?(" :: ")
      mode = rest.slice(4, rest.size - 4)
      return nil if mode == "" || mode.index(" ") != nil
      rest = ""
    return nil if rest != ""
    [ref.slice(0, stop), first[0], rank, orbit, mode]

  -> orient_to_orbit(a, want, ref, label)
    found = nil
    Metaflip:Gf2:MmcAlg.s3_orbit_with_perms(a).each -> (pair)
      found = pair[0] if found == nil && pair[0].same_shape?(want)
    raise ReplayError.new(label + " " + ref) if found == nil
    found

  -> resolve_leaf(ref)
    at = ref.index("@")
    if at != nil && at > 0
      shp = ref.slice(0, at)
      h = ref.slice(at + 1, ref.size - at - 1)
      m = Mmc.shape_ref(shp)
      if m != nil
        shape = m[0]
        key = Mmc.shape_key(shape)
        cands = []
        (@src.by_h7.key?(h.slice(0, 7)) ? @src.by_h7[h.slice(0, 7)] : []).each -> (f)
          dims = path_dims(f)
          cands.push(f) if dims != nil && Mmc.shape_key(dims) == key
        raise ReplayError.new("pinned ref " + ref + " does not resolve") if cands.size == 0
        a = materialize_file(cands[0])
        o = a.orient_as(shape)
        raise ReplayError.new("cannot orient " + ref) if o == nil
        return o
    ext = ext_ref(ref)
    if ext != nil
      a = materialize_file(file_by_basename(ext[0]))
      a = orient_to_orbit(a, ext[1], ref, "ext orient failed") if ext[1] != nil
      raise ReplayError.new("unsupported pool orbit mode " + ref) if ext[2] != nil && ext[2] != "CANONICAL"
      return a
    named = named_ref(ref)
    if named != nil
      name = named[0]
      shape = named[1]
      rank = named[2]
      raise ReplayError.new("unsupported pool orbit mode " + ref) if named[4] != nil && named[4] != "CANONICAL"
      a = nil
      if name == "AxisSplit" || name == "Naive"
        a = Metaflip:Gf2:Scheme.naive(shape[0], shape[1], shape[2])
      else
        tokens = {"AE" => "alphaevolve", "AT" => "alphatensor", "Strassen" => "strassen", "Winograd" => "winograd", "Laderman" => "laderman", "Smirnov" => "smirnov", "Sedoglavic" => "perminov"}
        token = tokens.key?(name) ? tokens[name] : name.downcase
        key = Mmc.shape_key(shape)
        files = []
        (@src.by_sorted.key?(key) ? @src.by_sorted[key] : []).each -> (entry)
          files.push(entry[1]) if entry[0] == rank
        files = Textx.sort_by(files) -> (f) [Fsx.basename(f).downcase.index(token) == nil ? 1 : 0, f]
        raise ReplayError.new("named base not found " + ref) if files.size == 0
        files.each -> (f)
          if a == nil
            begin
              a = materialize_file(f)
            rescue failure
              raise failure if failure.is_a?(FetchError)
              raise failure if !failure.is_a?(ReplayError)
        raise ReplayError.new("named base unusable " + ref) if a == nil
        a = a.orient_as(shape)
      a = orient_to_orbit(a, named[3], ref, "named orient failed") if named[3] != nil
      return a
    stem = ref.ends_with?(".json") ? ref.slice(0, ref.size - 5) : ref
    return materialize_file(@src.by_stem[stem][0]) if @src.by_stem.key?(stem)
    m = Mmc.shape_ref(ref)
    if m != nil
      shape = m[0]
      return Metaflip:Gf2:Scheme.naive(shape[0], shape[1], shape[2]) if m[1] || shape.include?(1)
      b = best(shape)
      raise ReplayError.new("no scheme for " + ref) if b == nil
      return b
    parametric = Mmc.parametric?(ref)
    raise ReplayError.new("parametric constructor leaf unsupported: " + ref) if parametric
    found = Mmc.search_dims(ref)
    if found != nil
      return Metaflip:Gf2:Scheme.naive(found[0], found[1], found[2]) if found.include?(1)
      b = best(found)
      raise ReplayError.new("no scheme for " + ref) if b == nil
      note_log(["fallback shape resolution for ref", ref].map(-> (part) part.to_s).join(" "))
      return b
    raise ReplayError.new("cannot resolve leaf ref " + ref)

  # ---- lineage
  # ids in document order, like SchemeIO.parseLineageNode: @ref nodes become the registered node itself
  -> register(node, ids, counter)
    kind = type(node)
    if kind == "Hash"
      if node["op"] == "@ref"
        target = ids[node["id"]]
        raise ReplayError.new("dangling @ref " + node["id"].to_s) if target == nil
        return target
      out = {}
      node.each -> (k, v)
        out[k] = register(v, ids, counter)
      counter[0] += 1
      out["\u0000serial"] = counter[0]
      ids[node["id"]] = out if node.key?("id") && node["id"] != nil && node["id"] != "" && node["id"] != 0 && node["id"] != false
      return out
    return node.map(-> (v) register(v, ids, counter)) if kind == "Array"
    node

  -> replay(root)
    tree = register(root, {}, [0])
    rep(tree, {})

  -> rep(node, memo)
    key = node["\u0000serial"]
    return memo[key] if memo.key?(key)
    out = rep_op(node, memo)
    memo[key] = out
    out

  -> rep_op(nd, memo)
    op = nd["op"]
    if op == "Atom" || op == "Leaf"
      return resolve_leaf(need(nd, "ref"))
    return Metaflip:Gf2:MmcAlg.kron(rep(need(nd, "outer"), memo), rep(need(nd, "inner"), memo)) if op == "KronProduct"
    if op == "KronChain"
      factors = need(nd, "factors")
      acc = rep(factors[0], memo)
      (1...factors.size).each -> (i)
        acc = Metaflip:Gf2:MmcAlg.kron(acc, rep(factors[i], memo))
      return acc
    return Metaflip:Gf2:MmcAlg.concat_cols(rep(need(nd, "left"), memo), rep(need(nd, "right"), memo)) if op == "ConcatCols" || op == "ConcatRight"
    return Metaflip:Gf2:MmcAlg.concat_rows(rep(need(nd, "top"), memo), rep(need(nd, "bottom"), memo)) if op == "ConcatRows" || op == "ConcatBelow"
    return Metaflip:Gf2:MmcAlg.concat_inner_r(rep(need(nd, "left"), memo), rep(need(nd, "right"), memo)) if op == "SumInner"
    if op == "Transpose"
      child = rep(need(nd, "child"), memo)
      perm = nd.key?("perm") ? nd["perm"] : ""
      exact = Metaflip:Gf2:MmcAlg.permute_axes(child, perm)
      return exact if exact != nil
      arrow = perm.index("->")
      return child if arrow == nil
      source = {"N" => child.n, "M" => child.m, "P" => child.p, "A" => child.n, "B" => child.m, "C" => child.p}
      target = perm.slice(arrow + 2, perm.size - arrow - 2)
      return child if target.size < 3 || !source.key?(target.slice(0, 1)) || !source.key?(target.slice(1, 1)) || !source.key?(target.slice(2, 1))
      oriented = child.orient_as([source[target.slice(0, 1)], source[target.slice(1, 1)], source[target.slice(2, 1)]])
      return oriented == nil ? child : oriented
    if op == "OrientAs"
      child = rep(need(nd, "child"), memo)
      if nd.key?("axisMap") && nd["axisMap"] != nil && nd["axisMap"] != ""
        perm = nd["axisMap"].bytes.map(-> (byte) "nmp".index(byte.chr))
        valid = false
        Metaflip:Gf2:Scheme.orient_perms.each -> (candidate)
          valid = true if candidate[0] == perm[0] && candidate[1] == perm[1] && candidate[2] == perm[2]
        raise MmcError.new("tuple.index(x): x not in tuple") if !valid
        return Metaflip:Gf2:MmcAlg.orient_by_perm(child, perm)
      o = child.orient_as([need(nd, "n"), need(nd, "m"), need(nd, "p")])
      raise ReplayError.new("OrientAs failed") if o == nil
      return o
    return Metaflip:Gf2:MmcAlg.axis_permute(rep(need(nd, "child"), memo), need(nd, "permA"), need(nd, "permB"), need(nd, "permC")) if op == "AxisPermute"
    return Metaflip:Gf2:MmcAlg.clean(rep(need(nd, "child"), memo)) if op == "DCE"
    return Metaflip:Gf2:MmcAlg.project(rep(need(nd, "child"), memo), need(nd, "keepN"), need(nd, "keepM"), need(nd, "keepP")) if op == "Project"
    if op == "SerendipitousProduct"
      base = Metaflip:Gf2:MmcAlg.clean(rep(need(nd, "base"), memo))
      owner = self
      resolve = -> (shape) owner.resolve_inner(shape)
      rank_of = -> (shape) owner.best_rank(shape)
      return Metaflip:Gf2:MmcAlg.serendipitous(base, need(nd, "n2"), need(nd, "m2"), need(nd, "p2"), resolve, rank_of)
    return recombine(nd, memo) if op == "Recombination" || op == "RecombinationN"
    raise ReplayError.new("unsupported op " + op.to_s)

  -> resolve_inner(shape)
    return Metaflip:Gf2:Scheme.naive(shape[0], shape[1], shape[2]) if shape.include?(1)
    best(shape)

  -> recombine(nd, memo)
    base = Metaflip:Gf2:MmcAlg.clean(rep(need(nd, "base"), memo))
    alloc_a = need(nd, "allocA")
    alloc_b = need(nd, "allocB")
    alloc_c = need(nd, "allocC")
    want = [alloc_a.size, alloc_b.size, alloc_c.size]
    if !base.same_shape?(want)
      oriented = base.orient_as(want)
      base = oriented if oriented != nil
    leaves = nd.key?("leaves") && nd["leaves"] != nil ? nd["leaves"] : []
    leaf_cache = {}
    recorded = env("MMC_RECORDED_LEAVES") != nil && env("MMC_RECORDED_LEAVES") != ""
    leaf_for = -> (key)
      if !leaf_cache.key?(key)
        found = nil
        leaves.each -> (leaf)
          a = nil
          begin
            a = rep(leaf, memo)
          rescue failure
            raise failure if failure.is_a?(FetchError) || !failure.is_a?(ReplayError)
            note_log(["recomb leaf failed", failure.message.to_s.slice(0, 200)].map(-> (part) part.to_s).join(" "))
            a = nil
          if a != nil && Mmc.shape_key([a.n, a.m, a.p]) == key && (found == nil || a.rank < found.rank)
            found = a
        leaf_cache[key] = found
      leaf_cache[key]
    sub_lookup = -> (size)
      if size.include?(1)
        Metaflip:Gf2:Scheme.naive(size[0], size[1], size[2])
      else
        key = Mmc.shape_key(size)
        dims = size.sort
        b = best(size)
        lf = nil
        lf = leaf_for.call(key) if b == nil || b.rank >= dims[0] * dims[1] * dims[2] || recorded
        if lf != nil && (b == nil || lf.rank < b.rank)
          Metaflip:Gf2:Scheme.from_terms(lf.n, lf.m, lf.p, Metaflip:Gf2:MmcAlg.clean(lf).terms).orient_as(size)
        else
          b
    Metaflip:Gf2:MmcAlg.recombination(base, alloc_a, alloc_b, alloc_c, sub_lookup)
