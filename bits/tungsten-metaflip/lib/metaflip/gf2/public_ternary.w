# Public integer-coefficient schemes reduced modulo two. Port of tools/screen_public_ternary_gf2.py.
#
# Public ternary (ZT) and integer (Z) schemes reduce modulo two to exact GF(2) decompositions of the
# same rank; their authors search over ZT/Z/Q, so a GF(2) walk can find reductions that do not lift.
#
#   PublicTernary.parity(value)                  an exact integer, or an odd-denominator rational "p/q", mod 2
#   PublicTernary.reduce_mod2(data)              a FastMatrixMultiplication scheme (a parsed JSON Hash) ->
#                                                [shape, source rank, exact GF(2) terms], or raises SchemeRejected
#   PublicTernary.integer_files(git, revision, alternatives, rational)
#                                                {"NxMxP" (sorted) => [[rank, path], ...]} within best integer rank + alternatives
#   PublicTernary.seeds(repo, revision, url, out, options)
#                                                converts the schemes into MFW1 seeds below `out` and writes
#                                                `out/seeds.json`; returns the summary line
#   PublicTernary.walk(options)                  runs the compiled walker over a seeds manifest, `jobs` at a time,
#                                                appending one JSON line per walk to the log
#
# The ring comes from the file-name suffix, not the directory (a `serendipitous_base` file can be `_Q`). Rational
# files are skipped unless `rational`; then the exact parity gate keeps only schemes whose denominators are all odd
# (those reduce to GF(2)). Every seed passes the GF(2) tensor expansion (both gates) before it is written. Walks are
# deterministic in (seed, steps, nonce), so each row is replayable. Public ranks are comparison data only; this
# makes no record claim.
#
# A file that cannot be converted is recorded with the message of the original's exception (a ValueError, a
# KeyError, an AssertionError or a JSON error); anything else stops the run, as in the original. The manifest
# and the seed files are byte for byte those of the original. The walker's rows are written as walks finish.
#
# There is no garbage collector: every scheme file's text, tree and masks are released after the file is done.
use scheme
use jsonx
use fsx
use gitx
use procx
use textx
use record_board

# A scheme file the tool rejects; `to_s` is what the original's exception prints.
+ SchemeRejected < Error

+ Metaflip:Gf2:PublicTernary
  -> .reject(message)
    raise SchemeRejected.new(message)

  # ---- parity --------------------------------------------------------------------------------------

  # True when text[from, upto) is one or more ASCII digits.
  -> .digits?(text, from, upto)
    return false if upto <= from
    i = from
    while i < upto
      byte = text.byte_at(i)
      return false if byte < 48 || byte > 57
      i += 1
    true

  # re.fullmatch(r'-?\d+/[1-9]\d*', text): the position of the slash, or nil.
  -> .rational_slash(text)
    slash = text.index("/")
    return nil if slash == nil
    start = text.starts_with?("-") ? 1 : 0
    return nil if !Metaflip:Gf2:PublicTernary.digits?(text, start, slash)
    last = text.size
    return nil if slash + 1 >= last || !Metaflip:Gf2:PublicTernary.digits?(text, slash + 1, last)
    return nil if text.byte_at(slash + 1) == 48
    slash

  # Reduces an exact integer or an odd-denominator rational modulo two: Fraction(value).numerator & 1.
  -> .parity(value)
    kind = type(value)
    if kind == "Int" || kind == "BigInt"
      return value & 1
    slash = kind == "String" ? Metaflip:Gf2:PublicTernary.rational_slash(value) : nil
    Metaflip:Gf2:PublicTernary.reject("coefficient must be an exact integer or rational") if slash == nil
    numerator = value.slice(0, slash).to_i
    denominator = value.slice(slash + 1, value.size - slash - 1).to_i
    divisor = numerator.abs.gcd(denominator)
    Metaflip:Gf2:PublicTernary.reject("even denominator: scheme does not reduce to GF(2)") if (denominator / divisor) % 2 == 0
    (numerator / divisor) & 1

  # ---- one scheme ----------------------------------------------------------------------------------

  -> .fetch(data, key)
    Metaflip:Gf2:PublicTernary.reject("'" + key + "'") if !data.key?(key)
    data[key]

  # The mask of one row of coefficients: bit j is the parity of row[j], moved to bit (j % n) * p + j / n when
  # `public_w` (the public W row is indexed C[k][i]; MFW1 indexes C[i][k]).
  -> .row_mask(row, n, p, public_w)
    width = row.size
    words = Metaflip:Gf2:Bits.limbs_for(width)
    limbs = i64[words]
    j = 0 ## i64
    while j < width
      value = row[j]
      kind = type(value)
      bit = 0
      if kind == "Int" || kind == "BigInt"
        bit = value & 1
      else
        bit = Metaflip:Gf2:PublicTernary.parity(value)
      if bit == 1
        at = j ## i64
        at = (j % n) * p + j / n if public_w
        Metaflip:Gf2:Bits.set_bit(limbs, at)
      j += 1
    mask = Metaflip:Gf2:Bits.from_limbs(limbs, 0, words)
    Metaflip:Gf2:Bits.release(limbs)
    mask

  # FastMatrixMultiplication JSON -> [shape, source rank, exact GF(2) terms (sorted)].
  -> .reduce_mod2(data)
    # TODO(port): `data.is_a?(Hash)` is false for every Hash (w_value_is_a has no Hash branch; PORT-BLOCKERS.md)
    Metaflip:Gf2:PublicTernary.reject("unsupported scheme header") if type(data) != "Hash"
    dims = Metaflip:Gf2:PublicTernary.fetch(data, "n")
    ok = dims.is_a?(Array) && dims.size == 3
    if ok
      dims.each -> (d)
        ok = false if !d.is_a?(Integer) || d < 1
    z2 = data["z2"]
    ok = false if !(z2 == nil || z2 == false || z2 == 0)
    Metaflip:Gf2:PublicTernary.reject("unsupported scheme header") if !ok
    n = dims[0]
    m = dims[1]
    p = dims[2]
    rank = Metaflip:Gf2:PublicTernary.fetch(data, "m")
    banks = []
    [["u", n * m], ["v", m * p], ["w", p * n]].each -> (spec)
      rows = Metaflip:Gf2:PublicTernary.fetch(data, spec[0])
      good = rows.size == rank
      rows.each -> (row)
        good = false if row.size != spec[1]
      Metaflip:Gf2:PublicTernary.reject(spec[0] + " has the wrong size") if !good
      banks.push(rows.map(-> (row) Metaflip:Gf2:PublicTernary.row_mask(row, n, p, spec[0] == "w")))
    # mod two, equal terms cancel in pairs; a term with a zero factor is no term
    rows = []
    t = 0
    while t < rank
      rows.push([banks[0][t], banks[1][t], banks[2][t], t])
      t += 1
    rows = rows.sort
    terms = []
    i = 0
    while i < rows.size
      j = i
      while j < rows.size && rows[j][0] == rows[i][0] && rows[j][1] == rows[i][1] && rows[j][2] == rows[i][2]
        j += 1
      first = rows[i]
      if (j - i) % 2 == 1 && first[0] != 0 && first[1] != 0 && first[2] != 0
        terms.push([first[0], first[1], first[2]])
        i += 1
      # the masks of the rows that cancelled, and of the copies of a kept row, are ours to free
      while i < j
        Metaflip:Gf2:Bits.release(rows[i][0])
        Metaflip:Gf2:Bits.release(rows[i][1])
        Metaflip:Gf2:Bits.release(rows[i][2])
        i += 1
    rows.each -> (row)
      Metaflip:Gf2:Bits.release(row)
    Metaflip:Gf2:Bits.release(rows)
    banks.each -> (bank)
      Metaflip:Gf2:Bits.release(bank)
    # exactness: both gates of the tensor expansion (the original asserts it inside reduce_mod2)
    Metaflip:Gf2:PublicTernary.reject("") if !Metaflip:Gf2:Scheme.from_terms(n, m, p, terms).exact?
    [[n, m, p], rank, terms]

  # ---- which files ---------------------------------------------------------------------------------

  # {"NxMxP" => [[rank, path], ...]}: per sorted shape, the scheme files of the repository's tree `schemes/`
  # within the best integer rank (+ alternatives). The window is anchored on ZT/Z files: a lower `_Q` file usually
  # has even denominators and must not crowd out the shape's GF(2)-valid seeds. `known/` files are skipped.
  -> .integer_files(git, revision, alternatives, rational)
    found = {}
    git.ls_tree(revision, "schemes").each -> (name)
      entry = Metaflip:Gf2:RecordBoard.ring_entry(name)
      if entry != nil && name.index("/known/") == nil && !(entry[1] == "Q" && !rational)
        Textx.push_to(found, entry[0], [entry[2], entry[1] != "Q", name])
    result = {}
    found.each -> (key, files)
      limit = nil
      files.each -> (file)
        limit = file[0] if file[1] && (limit == nil || file[0] < limit)
      if limit == nil
        limit = 0
        files.each -> (file)
          limit = file[0] if file[0] > limit
      else
        limit += alternatives
      kept = files.select(-> (file) file[0] <= limit).map(-> (file) [file[0], file[2]])
      result[key] = Textx.sort_by(kept) -> (pair) [pair[0], pair[1]]
    result

  # ---- seeds ---------------------------------------------------------------------------------------

  # The shape, source rank and terms of one scheme file, or the message of the rejection.
  -> .convert(raw, rank)
    tree = nil
    reduced = nil
    message = nil
    begin
      tree = Jsonx.loads(raw)
      reduced = Metaflip:Gf2:PublicTernary.reduce_mod2(tree)
      if reduced[1] != rank
        Metaflip:Gf2:Scheme.from_terms(reduced[0][0], reduced[0][1], reduced[0][2], reduced[2]).release
        reduced = nil
        Metaflip:Gf2:PublicTernary.reject("file-name rank disagrees with the scheme")
    rescue e: SchemeRejected
      message = e.message
    rescue e: JsonError
      message = e.message
    Jsonx.release(tree) if tree != nil
    [reduced, message]

  # Converts every distinct integer scheme at each shape's best integer rank (or within best + alternatives) of a
  # FastMatrixMultiplication-format repository into an MFW1 seed below `out` (a new directory) and writes
  # `out/seeds.json`. `options`: min_dim, min_max_dim, max_dim, rational, alternatives. Returns the summary line.
  -> .seeds(repo, revision_spec, url, out, options)
    Fsx.mkdir(out, parents: true, exist_ok: false)
    git = Gitx.new(repo)
    revision = git.rev_parse(revision_spec)
    files = Metaflip:Gf2:PublicTernary.integer_files(git, revision, options["alternatives"], options["rational"])
    order = []
    files.each -> (key, items)
      items.each -> (item)
        order.push([key.split("x").map(-> (d) d.to_i), item[0], item[1], key])
    order = Textx.sort_by(order) -> (entry) entry[0] + [entry[1], entry[2]]
    rows = []
    errors = []
    seen = {}
    order.each -> (entry)
      dims = entry[0]
      rank = entry[1]
      name = entry[2]
      if options["min_dim"] <= dims[0] && options["min_max_dim"] <= dims[2] && dims[2] <= options["max_dim"]
        # a partial clone would fetch the blob on demand; ours has it or this fails
        raw = git.show!(revision, name)
        converted = Metaflip:Gf2:PublicTernary.convert(raw, rank)
        if converted[1] != nil
          errors.push({"source" => name, "error" => converted[1]})
        else
          shape = converted[0][0]
          terms = converted[0][2]
          scheme = Metaflip:Gf2:Scheme.from_terms(shape[0], shape[1], shape[2], terms)
          blob = scheme.blob
          digest = Digest.sha256(blob)
          # an addition-reduced copy with identical GF(2) terms is the same seed
          if !seen.key?(digest)
            seen[digest] = true
            shape_text = shape.map(-> (d) d.to_s).join("x")
            path = Fsx.join(out, shape_text + "_r" + terms.size.to_s + "_" + digest.slice(0, 8) + ".mfw")
            Fsx.write(path, blob)
            rows.push({"shape" => shape_text, "canonical" => entry[3], "source" => name, "source_rank" => rank, "source_sha256" => Digest.sha256(raw), "gf2_rank" => terms.size, "mfw" => path, "mfw_sha256" => digest})
          scheme.release
          terms.each -> (row)
            Metaflip:Gf2:Bits.release(row)
          Metaflip:Gf2:Bits.release(terms)
          Metaflip:Gf2:Bits.release(blob)
        Metaflip:Gf2:Bits.release(raw)
    manifest = {"schema" => 1, "field" => "GF(2)", "record_claim" => false, "repository" => (url == nil || url == "" ? repo : url), "revision" => revision, "seeds" => rows, "errors" => errors}
    Fsx.write(Fsx.join(out, "seeds.json"), Jsonx.dumps(manifest, indent: 1) + "\n")
    cancelled = 0
    rows.each -> (row)
      cancelled += 1 if row["gf2_rank"] < row["source_rank"]
    rows.size.to_s + " exact GF(2) seeds at " + revision.slice(0, 12) + "; " + cancelled.to_s + " with mod-2 cancellations; " + errors.size.to_s + " rejected"

  # ---- walks ---------------------------------------------------------------------------------------

  # re.search(r'seed_rank=(\d+) rank=(\d+) moves=(\d+) accepted=(\d+) no_pair=(\d+) escapes=(\d+)', text):
  # [seed_rank, rank, moves, accepted, no_pair, escapes] of the leftmost match, or nil.
  -> .parse_result(text)
    labels = ["seed_rank=", " rank=", " moves=", " accepted=", " no_pair=", " escapes="]
    from = 0
    while true
      at = text.index("seed_rank=", from)
      return nil if at == nil
      pos = at
      numbers = []
      ok = true
      labels.each -> (label)
        if ok && text.slice(pos, label.size) == label
          start = pos + label.size
          stop = start
          while stop < text.size && text.byte_at(stop) >= 48 && text.byte_at(stop) <= 57
            stop += 1
          if stop == start
            ok = false
          else
            numbers.push(text.slice(start, stop - start).to_i)
            pos = stop
        else
          ok = false
      return numbers if ok
      from = at + 1

  # `sha or path`: a seed's content hash, else the fallback (Python's `a or b` on a missing or empty string).
  -> .identity(sha, fallback)
    return fallback if sha == nil || sha == ""
    sha

  # The finished walk's row; `result` is the walker's ProcResult.
  -> .walk_row(seed, steps, nonce, out, result)
    row = {"shape" => seed["shape"], "canonical" => seed["canonical"], "seed" => seed["mfw"], "seed_sha256" => seed["mfw_sha256"], "steps" => steps, "nonce" => nonce, "returncode" => result.status}
    parsed = Metaflip:Gf2:PublicTernary.parse_result(result.out)
    if result.status == 0 && parsed != nil
      raw = Fsx.read(out)
      row["seed_rank"] = parsed[0]
      row["rank"] = parsed[1]
      row["moves"] = parsed[2]
      row["output"] = out
      row["sha256"] = Digest.sha256(raw)
    else
      text = result.out + result.err
      row["error"] = text.size > 400 ? text.slice(text.size - 400, 400) : text
    row

  # A progress line: added to options["lines"] when the caller collects them, else printed.
  -> .say(options, line)
    lines = options["lines"]
    if lines != nil
      lines.push(line)
    else
      << line

  # Runs the walker over the seeds of a manifest, `jobs` at a time, and appends one JSON line per walk to the log
  # (finished walks, by seed content, nonce and steps, are not repeated). `options`: walker, out, steps, jobs,
  # repeats, nonce_base, min_rank, largest_first, and optionally lines (an Array that collects the progress lines
  # instead of printing them).
  -> .walk(seeds_path, options)
    manifest = Jsonx.load(seeds_path)
    # TODO(port): `is_a?(Hash)` is false for every Hash (PORT-BLOCKERS.md)
    rows = type(manifest) == "Hash" ? manifest["seeds"] : manifest
    rows = rows.select(-> (row) row["gf2_rank"] >= options["min_rank"])
    log = options["out"]
    outdir = Fsx.join(Fsx.dirname(log), Fsx.stem(log) + "_mfw")
    Fsx.mkdir(outdir, parents: true, exist_ok: true)
    done = {}
    if File.exists?(log)
      Textx.splitlines(Fsx.read(log)).each -> (line)
        logged = Jsonx.loads(line)
        identity = Metaflip:Gf2:PublicTernary.identity(logged["seed_sha256"], logged["seed"])
        done[identity + "|" + logged["nonce"].to_s + "|" + logged["steps"].to_s] = true
    else
      Fsx.write(log, "")
    work = []
    queue = Textx.sort_by(rows, reverse: options["largest_first"]) -> (seed) seed["gf2_rank"]
    (0...options["repeats"]).each -> (repeat)
      queue.each -> (seed)
        nonce = options["nonce_base"] + 7919 * repeat + Textx.crc32(seed["shape"]) % 1000003
        identity = Metaflip:Gf2:PublicTernary.identity(seed["mfw_sha256"], seed["mfw"])
        key = identity + "|" + nonce.to_s + "|" + options["steps"].to_s
        work.push([seed, nonce]) if !done.key?(key)
    Metaflip:Gf2:PublicTernary.say(options, work.size.to_s + " walks queued")
    jobs = []
    work.each -> (item)
      seed = item[0]
      tag = Metaflip:Gf2:PublicTernary.identity(seed["mfw_sha256"], Digest.sha256(seed["mfw"])).slice(0, 8)
      out = Fsx.join(outdir, seed["shape"] + "_r" + seed["gf2_rank"].to_s + "_" + tag + "_n" + item[1].to_s + "_s" + options["steps"].to_s + ".mfw")
      jobs.push([seed, item[1], out])
    results = jobs.map(-> (job) nil)
    handled = jobs.map(-> (job) false)
    running = []
    started = 0
    while started < jobs.size || running.size > 0
      while started < jobs.size && running.size < options["jobs"]
        job = jobs[started]
        Fsx.unlink(job[2], missing_ok: true)
        argv = [options["walker"], job[0]["shape"], job[0]["mfw"], job[2], options["steps"].to_s, job[1].to_s]
        running.push(Procx.launch(started, argv, nil, nil))
        started += 1
      indices = running.map(-> (entry) entry[0])
      running = Procx.reap(running, results)
      indices.each -> (index)
        if results[index] != nil && !handled[index]
          handled[index] = true
          job = jobs[index]
          row = Metaflip:Gf2:PublicTernary.walk_row(job[0], options["steps"], job[1], job[2], results[index])
          Fsx.append(log, Jsonx.dumps(row) + "\n")
          if row.key?("error")
            text = row["error"]
            tail = text.size > 200 ? text.slice(text.size - 200, 200) : text
            Metaflip:Gf2:PublicTernary.say(options, "ERROR " + row["shape"] + " " + tail)
          elsif row["rank"] < row["seed_rank"]
            Metaflip:Gf2:PublicTernary.say(options, "DROP " + row["shape"] + " " + row["seed_rank"].to_s + " -> " + row["rank"].to_s)
    nil
