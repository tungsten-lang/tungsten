# Bounded exact GF(2) projection/basis/walk search for multiword rectangles. Port of tools/search_wide_projection_walks.py.
#
# This cold campaign is separate from the live fleet. Public ranks schedule walks only; independent full-tensor checks gate every
# retained result. Shared-factor pairs route rank ties; density is reported, never routed on.
#
#   ProjectionWalks.proposals(shape, terms, public, per_shape)   the distinct projection children of one parent (every coordinate
#                                                                of every axis, in the parent's basis rewrites of modes 6..17 and
#                                                                in its own), at most `per_shape` per child shape, best first
#   ProjectionWalks.select(rows, beam)                           distinct shapes first access to the bounded walk budget
#   ProjectionWalks.project_grid(shape, terms, keep)             the restriction to the kept coordinates, scanning the bit grid
#                                                                (the independent second implementation of the projection)
#   ProjectionWalks.verify_file(path, options)                   [shape, terms, sha256] of an MFW1 file: both gates, and the Ruby
#                                                                verifier when options["verifier"] names tools/verify_tensor.rb
#   ProjectionWalks.public_comparison(path)                      {"NxMxP" (sorted) => rank} of a dated rank table (fmm_sota.json)
#   ProjectionWalks.run(options)                                 one search; prints (or collects in options["lines"]) what the
#                                                                original prints
#
# options of run: seed, digest, walker, output_dir, depth, beam, steps, nonce_base, list_only, verifier (the Ruby script or nil),
# and optionally lines (an Array that collects the printed lines). A parent's rows are rows of Hashes with shape, rank, mode (nil
# for the parent's own basis), axis, coordinate, sha256, public_rank, pair_counts, density, terms and raw (the MFW1 text).
#
# Differences from the original: the exactness of every tensor is checked by both gates of the scheme library (the original's
# `exact` is one); the Ruby verifier is called only when `verifier` is given (the tool passes tools/verify_tensor.rb unless
# --no-ruby); the independent projection and the checks happen on the same terms, as in the original.
use scheme
use derive
use jsonx
use fsx
use procx
use textx

+ ProjectionWalksError < Error

+ ProjectionWalks
  -> .fail(message)
    raise ProjectionWalksError.new(message)

  -> .check(condition, message)
    ProjectionWalks.fail(message) if !condition

  # A progress line: added to options["lines"] when the caller collects them, else printed.
  -> .say(options, line)
    lines = options["lines"]
    if lines != nil
      lines.push(line)
    else
      << line

  -> .shape_text(shape)
    shape.map(-> (d) d.to_s).join("x")

  -> .sorted_shape_text(shape)
    ProjectionWalks.shape_text(shape.sort)

  -> .exact?(shape, terms)
    Metaflip:Gf2:Scheme.from_terms(shape[0], shape[1], shape[2], terms).exact?

  # Per-axis disjoint-pair capacity (sum over the groups of equal factors of size // 2); a scheduling proxy, not a rank bound.
  -> .shared_pair_counts(terms)
    [0, 1, 2].map -> (axis)
      values = terms.map(-> (term) term[axis]).sort
      pairs = 0
      run = 0
      previous = nil
      values.each -> (value)
        if previous != nil && value == previous
          run += 1
        else
          pairs += run / 2
          run = 1
        previous = value
      pairs + run / 2

  # The text of a term sequence, to tell basis rewrites that returned the same terms in the same order.
  -> .signature(terms)
    text = StringBuffer()
    terms.each -> (term)
      key = Metaflip:Gf2:Derive.key(term)
      text.append(key)
      text.append(";")
      Metaflip:Gf2:Bits.release(key)
    text.to_s

  -> .mode_key(mode)
    mode == nil ? "none" : mode.to_s

  # The restriction of the terms to the kept coordinates of each axis (`keep`: three ascending lists), by remapping the bit grid:
  # terms with a zero factor are dropped and terms that remain equal cancel in pairs; the result is sorted.
  -> .project_grid(shape, terms, keep)
    ProjectionWalks.check(keep.size == 3 && shape.size == 3, "keep must list three axes")
    3.times -> (axis)
      coordinates = keep[axis]
      ProjectionWalks.check(coordinates.size > 0, "no coordinate kept on axis [axis]")
      coordinates.each_with_index -> (coordinate, at)
        ProjectionWalks.check(type(coordinate) == "Int" && coordinate >= 0 && coordinate < shape[axis], "invalid kept coordinate on axis [axis]")
        ProjectionWalks.check(at == 0 || coordinate > coordinates[at - 1], "kept coordinates must be ascending and distinct")
    edges = [[0, 1], [1, 2], [0, 2]]
    tables = edges.map -> (edge)
      rows = edge[0]
      cols = edge[1]
      table = (0...(shape[rows] * shape[cols])).map(-> (bit) 0 - 1)
      keep[rows].each_with_index -> (old_row, row)
        keep[cols].each_with_index -> (old_col, col)
          table[old_row * shape[cols] + old_col] = row * keep[cols].size + col
      table
    kept = []
    terms.each -> (term)
      values = [0, 1, 2].map -> (position)
        Metaflip:Gf2:Bits.remap(term[position], tables[position])
      kept.push(values) if values[0] != 0 && values[1] != 0 && values[2] != 0
    Metaflip:Gf2:Derive.parity(kept).sort

  # [shape, terms, sha256] of an MFW1 file; the independent tensor check of the original is the Ruby verifier.
  -> .verify_file(path, options)
    raw = Fsx.read(path)
    scheme = Metaflip:Gf2:Scheme.parse(raw)
    shape = [scheme.n, scheme.m, scheme.p]
    ProjectionWalks.check(scheme.exact?, "tensor is not exact: [path]")
    digest = Digest.sha256(raw)
    verifier = options["verifier"]
    if verifier != nil
      checked = Jsonx.loads(Procx.check_output(["ruby", verifier, "--shape", ProjectionWalks.shape_text(shape), path]))[0]
      ProjectionWalks.check(checked["exact"] == true && checked["rank"] == scheme.rank && checked["sha256"] == digest, "independent tensor check failed: [path]")
    [shape, scheme.terms, digest]

  # {"NxMxP" (sorted) => rank}; two ranks for one format are an error.
  -> .public_comparison(path)
    table = Jsonx.load(path)
    public = {}
    table["entries"].each -> (entry)
      key = ProjectionWalks.sorted_shape_text(entry["format"])
      ProjectionWalks.check(!public.key?(key) || public[key] == entry["rank"], "conflicting public rank for [key]")
      public[key] = entry["rank"]
    public

  -> .density(terms)
    total = 0
    terms.each -> (term)
      term.each -> (factor)
        total += Metaflip:Gf2:Bits.popcount(factor)
    total

  # The order of a bucket and of the final list: rank first (relative to the public rank in the final list), then the
  # shared-pair capacity, then the hash.
  -> .bucket_key(row)
    [row["rank"], 0 - row["pair_counts"].max, 0 - row["pair_counts"].sum, row["sha256"]]

  -> .row_key(row)
    shape = row["shape"].sort
    [row["rank"] - row["public_rank"], row["rank"], shape[0], shape[1], shape[2], 0 - row["pair_counts"].max, 0 - row["pair_counts"].sum, row["sha256"]]

  # Retain distinct full representations, including rank ties.
  -> .proposals(shape, terms, public, per_shape)
    best = {}
    bases = {}
    seen = {}
    modes = [nil, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17]
    modes.each -> (mode)
      basis = mode == nil ? terms : Metaflip:Gf2:Derive.two_pass(terms, shape, mode)
      signature = ProjectionWalks.signature(basis)
      if !seen.key?(signature)
        seen[signature] = true
        ProjectionWalks.check(ProjectionWalks.exact?(shape, basis), "basis rewrite is not exact")
        bases[ProjectionWalks.mode_key(mode)] = basis
        3.times -> (axis)
          extent = shape[axis]
          child_shape = [shape[0], shape[1], shape[2]]
          child_shape[axis] = extent - 1
          key = ProjectionWalks.sorted_shape_text(child_shape)
          if extent > 1 && public.key?(key)
            extent.times -> (coordinate)
              child = Metaflip:Gf2:Derive.child(shape, basis, axis, coordinate)
              ProjectionWalks.check(child[0] == child_shape, "projection shape mismatch")
              result = child[1]
              raw = Metaflip:Gf2:Scheme.from_terms(child_shape[0], child_shape[1], child_shape[2], result).blob
              pairs = ProjectionWalks.shared_pair_counts(result)
              row = {"shape" => child_shape, "rank" => result.size, "mode" => mode, "axis" => axis, "coordinate" => coordinate, "sha256" => Digest.sha256(raw), "public_rank" => public[key], "pair_counts" => pairs, "density" => ProjectionWalks.density(result), "terms" => result, "raw" => raw}
              best[key] = [] if !best.key?(key)
              known = best[key].select(-> (old) old["sha256"] == row["sha256"])
              if known.size == 0
                ordered = Textx.sort_by(best[key] + [row]) -> (entry) ProjectionWalks.bucket_key(entry)
                best[key] = ordered.slice(0, per_shape)
    collected = []
    best.each -> (key, bucket)
      bucket.each -> (row)
        collected.push(row)
    rows = Textx.sort_by(collected) -> (row) ProjectionWalks.row_key(row)
    rows.each -> (row)
      keep = (0...3).map -> (axis)
        (0...shape[axis]).map(-> (value) value).select(-> (value) axis != row["axis"] || value != row["coordinate"])
      basis = bases[ProjectionWalks.mode_key(row["mode"])]
      projected = Metaflip:Gf2:Derive.project(shape, basis, row["axis"], row["coordinate"])[1]
      ProjectionWalks.check(Metaflip:Gf2:Derive.same_sequence?(projected, ProjectionWalks.project_grid(shape, basis, keep)), "independent projection mismatch")
      ProjectionWalks.check(ProjectionWalks.exact?(row["shape"], row["terms"]), "projection child is not exact")
    rows

  # Give distinct shapes first access to the bounded walk budget.
  -> .select(rows, beam)
    selected = []
    shapes = {}
    chosen = {}
    rows.each -> (row)
      key = ProjectionWalks.sorted_shape_text(row["shape"])
      if selected.size < beam && !shapes.key?(key)
        selected.push(row)
        shapes[key] = true
        chosen[row["sha256"]] = true
    rows.each -> (row)
      if selected.size < beam && !chosen.key?(row["sha256"])
        selected.push(row)
        chosen[row["sha256"]] = true
    selected

  -> .summary(row)
    {"shape" => row["shape"], "rank" => row["rank"], "mode" => row["mode"], "axis" => row["axis"], "coordinate" => row["coordinate"], "sha256" => row["sha256"], "public_rank" => row["public_rank"], "pair_counts" => row["pair_counts"], "density" => row["density"]}

  -> .save(manifest, directory)
    Fsx.atomic_write(Fsx.join(directory, "manifest.json"), Jsonx.dumps(manifest, indent: 2) + "\n")

  -> .run(options)
    seeded = ProjectionWalks.verify_file(options["seed"], options)
    source_shape = seeded[0]
    source_terms = seeded[1]
    source_hash = seeded[2]
    public = ProjectionWalks.public_comparison(options["digest"])
    if options["list_only"] == true
      choices = ProjectionWalks.select(ProjectionWalks.proposals(source_shape, source_terms, public, 2), options["beam"])
      choices.each -> (row)
        ProjectionWalks.check(ProjectionWalks.exact?(row["shape"], row["terms"]), "projection child is not exact")
      ProjectionWalks.say(options, Jsonx.dumps({"seed" => source_hash, "selected" => choices.map(-> (row) ProjectionWalks.summary(row))}, indent: 2))
      return nil
    directory = options["output_dir"]
    Fsx.mkdir(directory, parents: true, exist_ok: false)
    manifest = {"schema" => 1, "field" => "GF(2)", "record_claim" => false, "status" => "running", "source" => options["seed"], "source_sha256" => source_hash, "steps_per_walk" => options["steps"], "beam_per_parent" => options["beam"], "max_depth" => options["depth"], "public_digest_sha256" => Digest.sha256(Fsx.read(options["digest"])), "rows" => []}
    ProjectionWalks.save(manifest, directory)
    frontier = [[source_shape, source_terms, source_hash]]
    visited = {source_hash => true}
    walk_number = 0
    level = 0
    while level < options["depth"] && frontier.size > 0
      next_frontier = []
      frontier.each -> (parent)
        ProjectionWalks.select(ProjectionWalks.proposals(parent[0], parent[1], public, 2), options["beam"]).each -> (row)
          if !visited.key?(row["sha256"])
            visited[row["sha256"]] = true
            ProjectionWalks.check(ProjectionWalks.exact?(row["shape"], row["terms"]), "projection child is not exact")
            name = "d" + level.to_s + "-w" + walk_number.to_s
            seed_path = Fsx.join(directory, name + "-seed.mfw")
            output_path = Fsx.join(directory, name + "-result.mfw")
            Fsx.write(seed_path, row["raw"])
            nonce = options["nonce_base"] + walk_number
            ProjectionWalks.check(nonce <= 2147483647, "walk nonce exceeds native range")
            Procx.check_output([options["walker"], ProjectionWalks.shape_text(row["shape"]), seed_path, output_path, options["steps"].to_s, nonce.to_s])
            result = ProjectionWalks.verify_file(output_path, options)
            ProjectionWalks.check(result[0] == row["shape"], "walker changed the tensor shape")
            admitted = {"depth" => level + 1, "parent_sha256" => parent[2], "proposal" => ProjectionWalks.summary(row), "nonce" => nonce, "result_rank" => result[1].size, "result_sha256" => result[2], "numerical_below_public" => result[1].size < row["public_rank"], "seed_file" => name + "-seed.mfw", "result_file" => name + "-result.mfw"}
            manifest["rows"].push(admitted)
            ProjectionWalks.save(manifest, directory)
            ProjectionWalks.say(options, Jsonx.dumps(admitted))
            if !visited.key?(result[2])
              visited[result[2]] = true
              next_frontier.push([result[0], result[1], result[2]])
            walk_number += 1
      frontier = next_frontier
      level += 1
    manifest["status"] = "complete"
    ProjectionWalks.save(manifest, directory)
    below = manifest["rows"].select(-> (row) row["numerical_below_public"]).size
    ProjectionWalks.say(options, Jsonx.dumps({"status" => "complete", "walks" => walk_number, "numerical_below_public" => below}))
    nil
