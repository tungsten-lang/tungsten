# matmulcatalog recipes -> exact GF(2) seeds, with attribution. Port of tools/mmc_gf2_seeds.py.
#
#   CatalogueSeeds.select_targets(options)   choose catalogue schemes worth replaying: stamped F2, not commutative, rank at most
#                                            (best listed rank in the other sources) + slack, and nothing on our scoreboard at or
#                                            below that rank; writes the targets file; returns the summary line
#   CatalogueSeeds.replay(options)           materialize targets over GF(2), verify each against the complete matrix-multiplication
#                                            tensor, and write MFW1 seeds plus results.jsonl and seeds.json
#
# Each seed row carries the attribution its tensor depends on: the catalogue file (repository, pinned revision, recorded
# source/year), every atomic catalogue scheme the recipe used (Perminov, AlphaTensor, AlphaEvolve, Hopcroft-Kerr, ... as the
# catalogue records them), and any local witnesses used as leaves. seeds.json rows are also valid input for
# `public_ternary.w walk`. matmulcatalog: https://github.com/solven-eu/matmulcatalog (arXiv:2606.13408). Its F2 stamp can
# over-claim (a recipe may need a Q/F3-only leaf); `replay` records such targets as failures with the reason instead of emitting a
# tensor above the catalogue's rank.
#
# options of select_targets: clone, revision, cache_dir, lille, fmm_repo, fmm_revision, extra_repo (Array), board, slack, min_dim, out
# options of replay:         clone, revision, cache_dir, targets, out, board (a scoreboard JSON or nil), allow_nonf2, retry_failed,
#                            only (Array or nil); and optionally lines (an Array that collects the progress lines instead of
#                            printing them)
#
# Differences from the original: the targets are replayed one after the other (the original's `--jobs` is a process pool); the
# reason of a failure that is neither a ReplayError nor an assertion carries no traceback; a file that is neither cached nor in
# the clone is one failed `git show` (the original retries six times with sleeps before it records the RuntimeError).
use catalogue
use record_board
use scheme
use jsonx
use fsx
use textx
use floatx

# What the original's `assert` statements raise: no message.
+ SeedCheck < Error

+ CatalogueSeeds
  -> .repository
    "https://github.com/solven-eu/matmulcatalog"

  # {"NxMxP" (sorted) => [rank, witness path]} from a scoreboard JSON (gf2_record_board --json), for the witnesses that exist
  -> .board_leaves(path)
    board = {}
    Jsonx.load(path).each -> (row)
      key = Metaflip:Gf2:RecordBoard.sorted_key(row["shape"].split("x").map(-> (d) d.to_i))
      board[key] = [row["rank"], row["path"]] if Fsx.regular?(row["path"])
    board

  -> .shape_text(dims)
    dims.map(-> (d) d.to_s).join("x")

  # A progress line: added to options["lines"] when the caller collects them, else printed.
  -> .say(options, line)
    lines = options["lines"]
    if lines != nil
      lines.push(line)
    else
      << line

  # Python truthiness of a catalogue flag (`e.get("commutative")`): absent, null, false and zero are false
  -> .flag?(entry, name)
    return false if !entry.key?(name)
    value = entry[name]
    value != nil && value != false && value != 0 && value != ""

  -> .select_targets(options)
    source = MmcSource.new(options["clone"], options["revision"], options["cache_dir"])
    other = Metaflip:Gf2:RecordBoard.public_tables(options["lille"], nil, options["fmm_repo"], options["fmm_revision"], options["extra_repo"])[1]
    ours = {}
    CatalogueSeeds.board_leaves(options["board"]).each -> (key, entry)
      ours[key] = entry[0]
    best = {}
    source.catalog.each -> (e)
      fields = e.key?("fields") && e["fields"] != nil ? e["fields"] : []
      if !CatalogueSeeds.flag?(e, "commutative") && !CatalogueSeeds.flag?(e, "complex") && fields.include?("F2")
        dims = e["format"].sort
        key = CatalogueSeeds.shape_text(dims)
        listed = 1000000000
        listed = other[key] if other.key?(key)
        limit = listed + options["slack"]
        if dims[0] >= options["min_dim"] && dims[2] <= 32 && e["rank"] <= limit && !(ours.key?(key) && ours[key] <= e["rank"])
          held = best[key]
          if held == nil || e["rank"] < held["rank"] || (e["rank"] == held["rank"] && e["file"] < held["file"])
            best[key] = e
    ordered = Textx.sort_by(best.keys) -> (key)
      dims = key.split("x").map(-> (d) d.to_i)
      [best[key]["rank"], dims[0], dims[1], dims[2]]
    targets = ordered.map -> (key)
      e = best[key]
      {"mmc_file" => e["file"], "canonical" => key, "mmc_rank" => e["rank"], "public" => other[key], "board" => ours[key], "atom" => CatalogueSeeds.flag?(e, "atom"), "lineage_compact" => e["lineage_compact"]}
    Fsx.write(options["out"], Jsonx.dumps({"repository" => CatalogueSeeds.repository, "revision" => source.revision, "targets" => targets}, indent: 1) + "\n")
    below = 0
    targets.each -> (t)
      below += 1 if t["public"] != nil && t["mmc_rank"] < t["public"]
    targets.size.to_s + " targets at " + source.revision.slice(0, 12) + " (" + below.to_s + " below the other sources' best rank)"

  -> .failure_name(failure)
    return "ReplayError" if failure.is_a?(ReplayError)
    return "RuntimeError" if failure.is_a?(FetchError)
    return "AssertionError" if failure.is_a?(SeedCheck)
    "Exception"

  # One target -> a result row; the tensor file is written only after the full gate.
  -> .replay_one(options, source, replayer, target)
    started = ccall("__w_clock_ms")
    f = target["mmc_file"]
    row = {"mmc_file" => f, "mmc_rank" => target["mmc_rank"], "canonical" => target["canonical"]}
    begin
      replayer.reset_dependencies
      a = replayer.materialize_file(f)
      deps = replayer.deps_file.key?(f) ? replayer.deps_file[f] : {}
      atoms = []
      leaves = []
      nonf2 = []
      deps.each -> (key, dep)
        if dep[0] == "atom"
          atoms.push(dep[1])
        elsif dep[0] == "nonf2"
          nonf2.push(dep.slice(1, dep.size - 1).map(-> (d) d.to_s).join("x"))
        else
          leaves.push(dep)
      atoms = Textx.sorted(atoms)
      nonf2 = Textx.sorted(nonf2)
      leaves = Textx.sorted(leaves)
      shape = source.load(f)["n"]
      raise SeedCheck.new("") if !(a.n == shape[0] && a.m == shape[1] && a.p == shape[2])
      terms = a.terms.sort
      raise ReplayError.new("GF(2) rank " + terms.size.to_s + " above catalogue rank " + target["mmc_rank"].to_s) if terms.size > target["mmc_rank"]
      scheme = Metaflip:Gf2:Scheme.from_terms(shape[0], shape[1], shape[2], terms)
      raise SeedCheck.new("") if !scheme.exact?
      raw = scheme.blob
      reread = Metaflip:Gf2:Scheme.parse(raw)
      same = reread.equal_terms?(scheme)
      reread.release
      raise SeedCheck.new("") if !same
      digest = Digest.sha256(raw)
      path = Fsx.join(options["out"], CatalogueSeeds.shape_text(shape) + "_r" + terms.size.to_s + "_mmc_" + digest.slice(0, 8) + ".mfw")
      Fsx.atomic_write(path, raw)
      entry = source.by_file.key?(f) ? source.by_file[f] : {}
      board_info = []
      leaves.each -> (key)
        pair = replayer.board[CatalogueSeeds.shape_text(key)]
        board_info.push({"shape" => CatalogueSeeds.shape_text(key), "rank" => pair[0], "sha256" => Digest.sha256(Metaflip:Gf2:RecordBoard.load(pair[1]))})
      leaf_mode = "pure"
      leaf_mode = "board" if board_info.size > 0
      leaf_mode = "wide" if nonf2.size > 0
      catalogue = {"repository" => CatalogueSeeds.repository, "revision" => source.revision, "file" => f, "source" => entry["source"], "year" => entry["year"], "lineage" => entry["lineage_compact"]}
      row["status"] = "ok"
      row["shape"] = CatalogueSeeds.shape_text(shape)
      row["gf2_rank"] = terms.size
      row["mfw"] = path
      row["mfw_sha256"] = digest
      row["lineage_compact"] = entry["lineage_compact"]
      row["nonf2_leaves"] = nonf2
      row["leaf_mode"] = leaf_mode
      row["attribution"] = {"catalogue" => catalogue, "atoms" => atoms.map(-> (atom_path) source.atom_info(atom_path)), "board_leaves" => board_info}
    rescue failure
      row["status"] = "fail"
      row["reason"] = CatalogueSeeds.failure_name(failure) + ": " + failure.message.to_s.slice(0, 500)
    row["secs"] = Floatx.round((ccall("__w_clock_ms") - started) / 1000.0, 2)
    row

  -> .replay(options)
    Fsx.mkdir(options["out"], parents: true, exist_ok: true)
    doc = Jsonx.load(options["targets"])
    targets = type(doc) == "Hash" ? doc["targets"] : doc
    if options["only"] != nil && options["only"].size > 0
      wanted = {}
      options["only"].each -> (name)
        wanted[name] = true
      targets = targets.select(-> (t) wanted.key?(t["canonical"]) || wanted.key?(t["mmc_file"]))
    results = Fsx.join(options["out"], "results.jsonl")
    done = {}
    if Fsx.regular?(results)
      Textx.splitlines(Fsx.read(results)).each -> (line)
        r = Jsonx.loads(line)
        done[r["mmc_file"]] = r
    todo = targets.select -> (t)
      !done.key?(t["mmc_file"]) || (options["retry_failed"] && done[t["mmc_file"]]["status"] != "ok")
    todo = Textx.sort_by(todo) -> (t) [t["mmc_rank"], t["mmc_file"]]
    CatalogueSeeds.say(options, todo.size.to_s + " targets to replay (" + done.size.to_s + " already recorded)")
    source = MmcSource.new(options["clone"], options["revision"], options["cache_dir"])
    board = options["board"] == nil ? nil : CatalogueSeeds.board_leaves(options["board"])
    replayer = MmcReplayer.new(source, board: board, allow_nonf2: options["allow_nonf2"] == true)
    Fsx.append(results, "") if !Fsx.regular?(results)
    todo.each -> (target)
      row = CatalogueSeeds.replay_one(options, source, replayer, target)
      Fsx.append(results, Jsonx.dumps(row) + "\n")
      done[row["mmc_file"]] = row
      rank = row.key?("gf2_rank") ? row["gf2_rank"].to_s : ""
      reason = row.key?("reason") ? row["reason"].slice(0, 90) : ""
      CatalogueSeeds.say(options, row["status"] + " " + row["canonical"] + " " + rank + " catalogue " + row["mmc_rank"].to_s + " " + reason)
    ok_rows = []
    failed = 0
    done.each -> (file, r)
      if r["status"] == "ok"
        ok_rows.push(r)
      else
        failed += 1
    ok_rows = Textx.sort_by(ok_rows) -> (r) [r["mmc_rank"], r["mmc_file"]]
    seeds = ok_rows.map -> (r)
      {"shape" => r["shape"], "canonical" => r["canonical"], "gf2_rank" => r["gf2_rank"], "mfw" => r["mfw"], "mfw_sha256" => r["mfw_sha256"], "mmc_file" => r["mmc_file"], "mmc_rank" => r["mmc_rank"], "leaf_mode" => r["leaf_mode"], "attribution" => r["attribution"]}
    seeds_path = Fsx.join(options["out"], "seeds.json")
    Fsx.write(seeds_path, Jsonx.dumps(seeds, indent: 1) + "\n")
    CatalogueSeeds.say(options, seeds.size.to_s + " exact GF(2) seeds, " + failed.to_s + " failures -> " + seeds_path)
    nil
