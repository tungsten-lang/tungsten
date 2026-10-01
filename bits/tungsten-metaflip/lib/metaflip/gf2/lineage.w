# Verification of a GF(2) lineage bundle: exact tensors, parent links, replayable steps, provenance.
# Port of tools/verify_gf2_lineage.py.
#
# A bundle directory holds `manifest.json` and one `<shape>-r<rank>-<sha8>.mfw.gz.b64` per row. Rows form chains
# (`parent` is the parent row's SHA-256). What is checked, by row kind:
#
#   public-mod2    upstream repository, revision and path recorded; with a source (NAME=CLONE) the tensor is
#                  re-derived from the pinned upstream file (coefficients mod two)
#   recipe-replay  catalogue repository, revision, file and lineage recorded (the replay of the catalogue's recipe
#                  is not part of this port: a row with a source is noted as not re-derived)
#   closure        block-sum/Kronecker recipe with consistent rank arithmetic
#   retained       a tensor already kept in a committed certificate; with a repo root the recorded repo-relative
#                  file must decode to the same tensor
#   archived       a certificate recovered from git history (repository, revision, path, source_sha256); with a
#                  source it is re-read at that revision and must decode to the same tensor
#   basis          two-pass basis rewrite of the parent reproduces the row
#   projection     basis rewrite (optional), coordinate deletion and shared-factor compression of the parent
#                  reproduce the row
#   walk           same shape as the parent, rank never above it; with a walker binary the deterministic native
#                  walk (steps, nonce) reproduces the row byte for byte (replay_max_rank limits the replays to
#                  walks whose result has at most that rank)
#
# Every tensor is expanded against the complete matrix-multiplication tensor by both gates of the scheme
# library (dense and sparse, which must agree); the original's second opinion, an independent Ruby
# reconstruction, is tools/verify_tensor.rb and is not called from here. `sources` matches a row when NAME
# occurs in its recorded repository URL.
#
#   Lineage.verify(bundle, options)     {"summary" => line, "notes" => [...], "finals" => [...]}, or raises LineageError
#       options: "sources" (Hash NAME => CLONE), "repo_root", "replay_walk" (binary), "replay_max_rank"
#   Lineage.recipe_rank(recipe)         the rank a composition recipe implies; split and product must add or multiply exactly
#   Lineage.lines(result)               what the tool prints
#   Lineage.build(spec, out)            writes a bundle (port of tools/build_gf2_lineage_bundle.py) from chain descriptions:
#                                       {"walker" => PATH (optional), "chains" => [[STEP, ...], ...]}, each STEP
#                                       {"kind", "file" (MFW1 text, a decimal certificate or .mfw.gz.b64), "details"}; the
#                                       shape, rank and SHA-256 come from the tensor, a step's parent is the previous step of
#                                       its chain, identical tensors are stored once, and a tensor reached with different
#                                       provenance is refused
#
# Memory: a parent's terms are kept until its last child has been checked.
use scheme
use jsonx
use fsx
use gitx
use procx
use textx
use derive
use record_board
use public_ternary

# A bundle that does not verify; `to_s` names the row and the check.
+ LineageError < Error

+ Metaflip:Gf2:Lineage
  -> .fail(message)
    raise LineageError.new(message)

  -> .check(condition, message)
    Metaflip:Gf2:Lineage.fail(message) if !condition

  # The fields a row of each kind must carry in its details.
  -> .provenance(kind)
    return ["repository", "revision", "path", "source_sha256", "source_rank"] if kind == "public-mod2"
    return ["repository", "revision", "file", "lineage"] if kind == "recipe-replay"
    return ["path"] if kind == "retained"
    return ["repository", "revision", "path", "source_sha256"] if kind == "archived"
    []

  # Kinds whose rows have no parent.
  -> .seed_kind?(kind)
    kind == "public-mod2" || kind == "recipe-replay" || kind == "closure" || kind == "retained" || kind == "archived"

  # The bytes of one row's file.
  -> .decode(bundle, name)
    text = Fsx.read(Fsx.join(bundle, name))
    raw = Gzip.decode_b64_text(text)
    Metaflip:Gf2:Bits.release(text)
    raw

  # The rank a composition recipe implies: split adds and product multiplies, exactly.
  -> .recipe_rank(node)
    kind = node["kind"]
    if kind == "naive"
      return node["shape"][0] * node["shape"][1] * node["shape"][2]
    return node["rank"] if kind == "seed" || kind == "projection"
    left = Metaflip:Gf2:Lineage.recipe_rank(node["left"])
    right = Metaflip:Gf2:Lineage.recipe_rank(node["right"])
    implied = left * right
    implied = left + right if kind == "split"
    Metaflip:Gf2:Lineage.check((kind == "split" || kind == "product") && implied == node["rank"], "inconsistent " + kind.to_s + " rank")
    implied

  # The bytes of the pinned upstream file: from git when the revision is present, else from the tree.
  -> .upstream_file(clone, details)
    path = details["path"]
    path = details["file"] if path == nil || path == ""
    revision = details["revision"]
    if File.exists?(Fsx.join(clone, ".git"))
      shown = Gitx.new(clone).show(revision, path)
      return shown if shown != nil
    Fsx.read(Fsx.join(clone, path))

  # The clone of the first source whose name occurs in the row's repository URL, or nil.
  -> .find_source(sources, details)
    found = nil
    sources.each -> (name, clone)
      found = clone if found == nil && details["repository"].index(name) != nil
    found

  # The value of a details field: nil for a missing or empty one.
  -> .present?(details, key)
    value = details[key]
    value != nil && value != ""

  # Replays one walk with the native walker: the bytes it writes.
  -> .replay_walk(binary, row, parent_blob, details)
    Fsx.with_tempdir(prefix: "gf2-lineage-") -> (temp)
      seed = temp + "/seed.mfw"
      out = temp + "/out.mfw"
      Fsx.write(seed, parent_blob)
      result = Procx.run([binary, row["shape"], seed, out, details["steps"].to_s, details["nonce"].to_s])
      Metaflip:Gf2:Lineage.check(result.ok?, "walk replay failed: " + row["file"])
      Fsx.read(out)

  # The canonical text of a scheme.
  -> .blob(shape, terms)
    Metaflip:Gf2:Scheme.from_terms(shape[0], shape[1], shape[2], terms).blob

  # True when the canonical text of the terms is `raw`; the text is freed.
  -> .same_blob?(shape, terms, raw)
    text = Metaflip:Gf2:Lineage.blob(shape, terms)
    same = text == raw
    Metaflip:Gf2:Bits.release(text)
    same

  -> .verify(bundle, options)
    sources = options["sources"] == nil ? {} : options["sources"]
    repo_root = options["repo_root"]
    replay = options["replay_walk"]
    replay_max = options["replay_max_rank"] == nil ? 1000000000 : options["replay_max_rank"]
    manifest = Jsonx.load(Fsx.join(bundle, "manifest.json"))
    Metaflip:Gf2:Lineage.check(manifest["schema"] == 1 && manifest["field"] == "GF(2)" && manifest["record_claim"] == false, "unsupported manifest header")
    rows = manifest["rows"]
    # how many rows still need each state
    pending = {}
    rows.each -> (row)
      if row["parent"] != nil
        before = pending.key?(row["parent"]) ? pending[row["parent"]] : 0
        pending[row["parent"]] = before + 1
    states = {}
    distinct = {}
    counts = {}
    notes = []
    rows.each -> (row)
      file = row["file"]
      raw = Metaflip:Gf2:Lineage.decode(bundle, file)
      Metaflip:Gf2:Lineage.check(Digest.sha256(raw) == row["sha256"], file)
      scheme = nil
      begin
        scheme = Metaflip:Gf2:Scheme.parse(raw)
      rescue failure
        Metaflip:Gf2:Lineage.fail(file + ": " + failure.to_s)
      shape = scheme.shape
      terms = scheme.terms
      Metaflip:Gf2:Lineage.check(shape.join("x") == row["shape"] && terms.size == row["rank"], file)
      Metaflip:Gf2:Lineage.check(scheme.exact?, file + ": the terms do not sum to the matrix-multiplication tensor")
      kind = row["kind"]
      details = row["details"] == nil ? {} : row["details"]
      Metaflip:Gf2:Lineage.provenance(kind).each -> (key)
        Metaflip:Gf2:Lineage.check(Metaflip:Gf2:Lineage.present?(details, key), file + ": missing provenance " + key)
      checked = kind
      Metaflip:Gf2:Lineage.check((row["parent"] == nil) == Metaflip:Gf2:Lineage.seed_kind?(kind), file + ": parent link disagrees with kind")
      if kind == "retained" || kind == "archived"
        if kind == "retained" && repo_root == nil
          notes.push(file + ": not checked against the committed certificate (no --repo-root)")
        elsif kind == "retained"
          kept = Fsx.join(repo_root, details["path"])
          text = Metaflip:Gf2:RecordBoard.load(kept)
          decoded = text == nil ? nil : Metaflip:Gf2:RecordBoard.decode_scheme(kept, text)
          Metaflip:Gf2:Lineage.check(decoded != nil && Metaflip:Gf2:Lineage.same_blob?(decoded.shape, decoded.terms, raw), "retained tensor differs: " + details["path"])
          decoded.release
          Metaflip:Gf2:Bits.release(text)
          checked += "+matched"
        else
          clone = Metaflip:Gf2:Lineage.find_source(sources, details)
          if clone == nil
            notes.push(file + ": not re-read from history (no --source for " + details["repository"] + ")")
          else
            original = Metaflip:Gf2:Lineage.upstream_file(clone, details)
            Metaflip:Gf2:Lineage.check(Digest.sha256(original) == details["source_sha256"], file + ": the upstream file changed")
            decoded = Metaflip:Gf2:RecordBoard.decode_scheme(details["path"], original)
            Metaflip:Gf2:Lineage.check(decoded != nil && Metaflip:Gf2:Lineage.same_blob?(decoded.shape, decoded.terms, raw), "archived tensor differs: " + details["path"])
            decoded.release
            Metaflip:Gf2:Bits.release(original)
            checked += "+rederived"
      elsif kind == "public-mod2" || kind == "recipe-replay"
        clone = Metaflip:Gf2:Lineage.find_source(sources, details)
        if clone == nil
          notes.push(file + ": not re-derived (no --source for " + details["repository"] + ")")
        elsif kind == "public-mod2"
          source = Metaflip:Gf2:Lineage.upstream_file(clone, details)
          Metaflip:Gf2:Lineage.check(Digest.sha256(source) == details["source_sha256"], file + ": the upstream file changed")
          derived = nil
          begin
            derived = Metaflip:Gf2:PublicTernary.reduce_mod2(Jsonx.loads(source))
          rescue failure
            Metaflip:Gf2:Lineage.fail(file + ": " + failure.to_s)
          Metaflip:Gf2:Lineage.check(derived[1] == details["source_rank"], file + ": the source rank differs")
          Metaflip:Gf2:Lineage.check(Metaflip:Gf2:Lineage.same_blob?(derived[0], derived[2], raw), file + ": the tensor is not the reduction of the source")
          Metaflip:Gf2:Scheme.from_terms(derived[0][0], derived[0][1], derived[0][2], derived[2]).release
          Metaflip:Gf2:Bits.release(source)
          checked += "+rederived"
        elsif details.key?("rederivable") && !details["rederivable"]
          notes.push(file + ": recipe-replay seed is an equal-rank variant; not re-derived")
        else
          notes.push(file + ": recipe replay is not part of this verifier; not re-derived")
      elsif kind == "closure"
        Metaflip:Gf2:Lineage.check(Metaflip:Gf2:Lineage.recipe_rank(details["recipe"]) == row["rank"], file + ": the recipe's rank differs from the row's")
      else
        parent = states[row["parent"]]
        Metaflip:Gf2:Lineage.check(parent != nil, file + ": parent row not found before it")
        parent_shape = parent[0]
        parent_terms = parent[1]
        if kind == "basis"
          rewritten = Metaflip:Gf2:Derive.two_pass(parent_terms, parent_shape, details["mode"])
          Metaflip:Gf2:Lineage.check(Metaflip:Gf2:Lineage.same_blob?(parent_shape, rewritten, raw), file + ": the basis rewrite of the parent differs")
        elsif kind == "projection"
          basis = parent_terms
          basis = Metaflip:Gf2:Derive.two_pass(parent_terms, parent_shape, details["mode"]) if details["mode"] != nil
          child = Metaflip:Gf2:Derive.child(parent_shape, basis, details["axis"], details["coordinate"])
          Metaflip:Gf2:Lineage.check(Metaflip:Gf2:Lineage.same_blob?(child[0], child[1], raw), file + ": the projection of the parent differs")
        elsif kind == "walk"
          Metaflip:Gf2:Lineage.check(shape == parent_shape && terms.size <= parent_terms.size, file + ": a walk keeps its parent's shape and never raises the rank")
          if replay != nil && terms.size <= replay_max
            parent_blob = Metaflip:Gf2:Lineage.blob(parent_shape, parent_terms)
            replayed = Metaflip:Gf2:Lineage.replay_walk(replay, row, parent_blob, details)
            Metaflip:Gf2:Lineage.check(replayed == raw, "walk replay differs: " + file)
            Metaflip:Gf2:Bits.release(parent_blob)
            Metaflip:Gf2:Bits.release(replayed)
            checked += "+replayed"
        else
          Metaflip:Gf2:Lineage.fail("unknown row kind " + kind.to_s)
        # this child has been checked: its parent is needed once less
        waiting = pending[row["parent"]] - 1
        pending[row["parent"]] = waiting
        if waiting == 0
          Metaflip:Gf2:Lineage.drop(states, row["parent"])
      seen_before = counts.key?(checked) ? counts[checked] : 0
      counts[checked] = seen_before + 1
      Metaflip:Gf2:Lineage.drop(states, row["sha256"])
      distinct[row["sha256"]] = true
      if pending.key?(row["sha256"])
        states[row["sha256"]] = [shape, terms, scheme]
      else
        scheme.release
      Metaflip:Gf2:Bits.release(raw)
    finals = {}
    rows.each -> (row)
      best = finals.key?(row["shape"]) ? finals[row["shape"]] : row["rank"]
      best = row["rank"] if row["rank"] < best
      finals[row["shape"]] = best
    kinds = Textx.sorted(counts.keys)
    summary = "PASS " + distinct.size.to_s + " exact GF(2) tensors (Tungsten, two gates); rows: " + kinds.map(-> (kind) counts[kind].to_s + " " + kind).join(", ")
    ordered = Textx.sort_by(finals.keys) -> (shape) shape.split("x").map(-> (d) d.to_i)
    {"summary" => summary, "notes" => notes, "finals" => ordered.map(-> (shape) "  " + shape + " rank " + finals[shape].to_s)}

  # Forgets the state of a row and frees its masks.
  -> .drop(states, sha)
    held = states[sha]
    if held != nil
      held[2].release
      states.delete(sha)

  # Writes a lineage bundle below the new directory `out` and returns its manifest.
  -> .build(spec, out)
    Fsx.mkdir(out, parents: true, exist_ok: false)
    rows = []
    by_sha = {}
    spec["chains"].each -> (chain)
      parent = nil
      chain.each_with_index -> (step, index)
        path = step["file"]
        text = Metaflip:Gf2:RecordBoard.load(path)
        scheme = text == nil ? nil : Metaflip:Gf2:RecordBoard.decode_scheme(path, text)
        Metaflip:Gf2:Lineage.check(scheme != nil, path + ": not an exact tensor")
        raw = scheme.blob
        digest = Digest.sha256(raw)
        Metaflip:Gf2:Lineage.check((index == 0) == Metaflip:Gf2:Lineage.seed_kind?(step["kind"]), path + ": seed kinds start a chain")
        details = step["details"] == nil ? {} : step["details"]
        row = {"kind" => step["kind"], "parent" => parent, "shape" => scheme.shape.join("x"), "rank" => scheme.rank, "sha256" => digest, "details" => details}
        if by_sha.key?(digest)
          old = by_sha[digest]
          Metaflip:Gf2:Lineage.check(old["kind"] == row["kind"] && old["parent"] == row["parent"] && old["details"] == row["details"], path + ": same tensor reached with different provenance")
        else
          row["file"] = row["shape"] + "-r" + row["rank"].to_s + "-" + digest.slice(0, 8) + ".mfw.gz.b64"
          Fsx.write(Fsx.join(out, row["file"]), Gzip.encode_b64(raw, 9, 76))
          by_sha[digest] = row
          rows.push(row)
        parent = digest
    manifest = {"schema" => 1, "field" => "GF(2)", "record_claim" => false, "rows" => rows}
    manifest["walker"] = spec["walker"] if spec["walker"] != nil && spec["walker"] != ""
    Fsx.write(Fsx.join(out, "manifest.json"), Jsonx.dumps(manifest, indent: 1) + "\n")
    manifest

  # The lines the tool prints: the summary, a note per unchecked row, the final rank per shape.
  -> .lines(result)
    lines = [result["summary"]]
    result["notes"].each -> (note)
      lines.push("  note: " + note)
    result["finals"].each -> (line)
      lines.push(line)
    lines
