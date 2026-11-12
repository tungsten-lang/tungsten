# Composition recipes: a scheme described as a tree of seeds, naive schemes, block splits, Kronecker products and
# coordinate projections, rebuilt from its leaves. Port of the replay half of tools/wide_composition_recipes.py.
#
# A recipe is a Hash (JSON in the lineage bundles):
#   {kind: "seed",       rank, shape, source_shape, state: SHA256}              a scheme held by the caller (`states`)
#   {kind: "seed",       rank, shape, source_shape, source: PATH, source_sha256} a leaf file below `root`
#   {kind: "naive",      rank, shape}                                            the n*m*p terms of the definition
#   {kind: "projection", rank, shape, parent: RECIPE, deletions: [{axis, coordinate}, ...]}
#   {kind: "split",      rank, shape, axis, left: RECIPE, right: RECIPE}        block sum along one axis
#   {kind: "product",    rank, shape, left: RECIPE, right: RECIPE}               Kronecker product
#
#   Recipes.replay(recipe, root, states, leaves)   the terms of the recipe's shape, sorted; every shape, rank, reference
#                                                  and cut is checked, a mismatch raises
#   Recipes.replay_owned(...)                      [terms, owned]: the same, and whether the caller may release the terms
#                                                  (Recipes.release_terms): true for a naive scheme, a block sum or a product in
#                                                  its canonical orientation, whose masks nothing else references
#   Recipes.dependencies(recipe)                   the `state` hashes the recipe needs from the caller
#   Recipes.read_leaf(path)                        [shape, terms, SHA-256 of the file's bytes]
#
# `states` maps a SHA-256 to [shape, terms]; `leaves` caches the leaf files read so far (keyed by path and hash).
# Leaves must be exact over GF(2) (both gates) and carry the recorded hash.
use derive
use record_board
use fsx

+ Metaflip:Gf2:Recipes
  -> .check(condition, message)
    raise message if !condition

  -> .product(shape)
    shape[0] * shape[1] * shape[2]

  # Three integers, each 1..maximum, as [n, m, p].
  -> .dimensions(shape, maximum)
    ok = shape.size == 3
    if ok
      shape.each -> (d)
        ok = false if d < 1 || d > maximum
    raise "invalid composition shape" if !ok
    [shape[0], shape[1], shape[2]]

  -> .sorted_shape(shape)
    shape.sort

  -> .same_shape?(a, b)
    a.size == 3 && b.size == 3 && a[0] == b[0] && a[1] == b[1] && a[2] == b[2]

  # The shape a leaf's file name gives: matmul_<n>x<m>[x<p>]_rank..., a pair meaning a square <n,n,n>.
  -> .name_shape(name)
    prefix = "matmul_"
    raise "missing composition leaf shape" if !name.starts_with?(prefix)
    rest = name.slice(prefix.size, name.size - prefix.size)
    dims = Metaflip:Gf2:RecordBoard.find_dims(rest)
    raise "missing composition leaf shape" if dims == nil
    # the dimensions must be followed by `_rank`
    text = dims.map(-> (d) d.to_s).join("x")
    raise "missing composition leaf shape" if rest.slice(0, text.size) != text || rest.slice(text.size, 5) != "_rank"
    if dims.size == 2
      raise "invalid square leaf name" if dims[0] != dims[1]
      dims.push(dims[0])
    dims

  # [shape, terms (sorted), SHA-256 of the file's bytes] of an MFW1 leaf (plain or gzip+base64) or a decimal seed.
  -> .read_leaf(path)
    raw = read_file(path)
    raise "cannot read [path]" if raw == nil
    digest = Digest.sha256(raw)
    body = raw
    body = Gzip.decode_b64_text(raw) if path.ends_with?(".mfw.gz.b64")
    shape = nil
    terms = nil
    if body.starts_with?("MFW1 ")
      scheme = Metaflip:Gf2:Scheme.parse(body)
      shape = [scheme.n, scheme.m, scheme.p]
      terms = scheme.terms
    else
      shape = Metaflip:Gf2:Recipes.name_shape(Fsx.basename(path))
      parsed = Metaflip:Gf2:RecordBoard.decimal_terms(body)
      raise "malformed decimal leaf" if parsed == nil
      terms = parsed
    [Metaflip:Gf2:Recipes.dimensions(shape, 1024), terms.sort, digest]

  # The `state` hashes a recipe depends on, each once.
  -> .dependencies(recipe)
    found = {}
    Metaflip:Gf2:Recipes.collect(recipe, found)
    found.keys

  -> .collect(recipe, found)
    kind = recipe["kind"]
    if kind == "seed"
      found[recipe["state"]] = true if recipe.key?("state")
    elsif kind == "projection"
      Metaflip:Gf2:Recipes.collect(recipe["parent"], found)
    elsif kind == "naive"
      nil
    else
      Metaflip:Gf2:Recipes.check(kind == "split" || kind == "product", "unknown composition recipe")
      Metaflip:Gf2:Recipes.collect(recipe["left"], found)
      Metaflip:Gf2:Recipes.collect(recipe["right"], found)

  # The terms of the leaf file a seed recipe names, verified once (hash, both exactness gates).
  -> .leaf_terms(recipe, root, leaves)
    source = recipe["source"]
    Metaflip:Gf2:Recipes.check(!Fsx.absolute?(source) && !Fsx.parts(source).include?(".."), "unsafe composition source")
    path = Fsx.resolve(Fsx.join(root, source))
    Metaflip:Gf2:Recipes.check(Fsx.relative?(path, Fsx.resolve(root)), "composition source outside root")
    pin = path + "\t" + recipe["source_sha256"]
    if !leaves.key?(pin)
      leaf = Metaflip:Gf2:Recipes.read_leaf(path)
      Metaflip:Gf2:Recipes.check(leaf[2] == recipe["source_sha256"], "composition source hash mismatch")
      scheme = Metaflip:Gf2:Scheme.from_terms(leaf[0][0], leaf[0][1], leaf[0][2], leaf[1])
      Metaflip:Gf2:Recipes.check(scheme.exact?, "independent composition leaf mismatch")
      leaves[pin] = [leaf[0], leaf[1]]
    leaves[pin]

  # The scheme's terms in another orientation of its axes (verify_cofactor_mergers.orient).
  -> .orient(shape, terms, target)
    return terms if shape[0] == target[0] && shape[1] == target[1] && shape[2] == target[2]
    Metaflip:Gf2:Scheme.from_terms(shape[0], shape[1], shape[2], terms).oriented_to(target).terms

  # Frees the masks, rows and outer Array of a terms list that nothing else references (compiled Tungsten has no
  # garbage collector; see bits.w).
  -> .release_terms(terms)
    terms.each -> (row)
      Metaflip:Gf2:Bits.release(row[0])
      Metaflip:Gf2:Bits.release(row[1])
      Metaflip:Gf2:Bits.release(row[2])
      Metaflip:Gf2:Bits.release(row)
    Metaflip:Gf2:Bits.release(terms)

  -> .replay(recipe, root, states, leaves)
    Metaflip:Gf2:Recipes.replay_owned(recipe, root, states, leaves)[0]

  # Reconstructs a recipe; a mutated shape, rank, reference or cut raises. Returns [terms, owned].
  -> .replay_owned(recipe, root, states, leaves)
    target = Metaflip:Gf2:Recipes.dimensions(recipe["shape"], 32)
    canonical = Metaflip:Gf2:Recipes.sorted_shape(target)
    kind = recipe["kind"]
    rank = recipe["rank"]
    Metaflip:Gf2:Recipes.check(rank >= 1 && rank <= 16384, "invalid composition rank")
    terms = nil
    owned = false
    if kind == "seed"
      held = nil
      if recipe.key?("state")
        Metaflip:Gf2:Recipes.check(!recipe.key?("source") && states.key?(recipe["state"]), "missing composition state")
        held = states[recipe["state"]]
      else
        held = Metaflip:Gf2:Recipes.leaf_terms(recipe, root, leaves)
      shape = held[0]
      source_shape = recipe["source_shape"]
      Metaflip:Gf2:Recipes.check(Metaflip:Gf2:Recipes.same_shape?(shape, source_shape) && Metaflip:Gf2:Recipes.same_shape?(Metaflip:Gf2:Recipes.sorted_shape(shape), canonical) && held[1].size == rank, "composition leaf metadata mismatch")
      terms = Metaflip:Gf2:Recipes.orient(shape, held[1], canonical)
    elsif kind == "projection"
      parent = recipe["parent"]
      source_shape = Metaflip:Gf2:Recipes.dimensions(parent["shape"], 32)
      Metaflip:Gf2:Recipes.check(Metaflip:Gf2:Recipes.product(source_shape) > Metaflip:Gf2:Recipes.product(canonical), "non-decreasing projection dependency")
      steps = recipe["deletions"]
      Metaflip:Gf2:Recipes.check(steps.size >= 1 && steps.size <= 93, "invalid composition projection")
      terms = Metaflip:Gf2:Recipes.replay_owned(parent, root, states, leaves)[0]
      steps.each -> (step)
        projected = Metaflip:Gf2:Derive.project(source_shape, terms, step["axis"], step["coordinate"])
        source_shape = projected[0]
        terms = projected[1]
      Metaflip:Gf2:Recipes.check(Metaflip:Gf2:Recipes.same_shape?(source_shape, canonical), "composition projection shape mismatch")
    elsif kind == "naive"
      Metaflip:Gf2:Recipes.check(rank == Metaflip:Gf2:Recipes.product(canonical), "naive composition rank mismatch")
      terms = Metaflip:Gf2:Scheme.naive(canonical[0], canonical[1], canonical[2]).terms
      owned = Metaflip:Gf2:Recipes.same_shape?(canonical, target)
    else
      Metaflip:Gf2:Recipes.check(kind == "split" || kind == "product", "unknown composition recipe")
      left = recipe["left"]
      right = recipe["right"]
      a = Metaflip:Gf2:Recipes.dimensions(left["shape"], 32)
      b = Metaflip:Gf2:Recipes.dimensions(right["shape"], 32)
      # strictly smaller children keep replay finite, even for mutated plans
      Metaflip:Gf2:Recipes.check(Metaflip:Gf2:Recipes.product(a) < Metaflip:Gf2:Recipes.product(canonical) && Metaflip:Gf2:Recipes.product(b) < Metaflip:Gf2:Recipes.product(canonical), "non-decreasing composition dependency")
      axis = 0
      if kind == "split"
        axis = recipe["axis"]
        ok = axis >= 0 && axis <= 2 && rank == left["rank"] + right["rank"]
        i = 0
        while ok && i < 3
          if i == axis
            ok = a[i] + b[i] == canonical[i]
          else
            ok = a[i] == canonical[i] && b[i] == canonical[i]
          i += 1
        Metaflip:Gf2:Recipes.check(ok, "composition split mismatch")
      else
        Metaflip:Gf2:Recipes.check(a[0] * b[0] == canonical[0] && a[1] * b[1] == canonical[1] && a[2] * b[2] == canonical[2] && rank == left["rank"] * right["rank"], "composition product mismatch")
      left_result = Metaflip:Gf2:Recipes.replay_owned(left, root, states, leaves)
      right_result = Metaflip:Gf2:Recipes.replay_owned(right, root, states, leaves)
      lterms = left_result[0]
      rterms = right_result[0]
      if kind == "split"
        offsets = [0, 0, 0]
        offsets[axis] = a[axis]
        terms = Metaflip:Gf2:Derive.block(a, lterms, canonical, [0, 0, 0]) + Metaflip:Gf2:Derive.block(b, rterms, canonical, offsets)
      else
        terms = Metaflip:Gf2:Derive.kronecker(a, lterms, b, rterms)
      Metaflip:Gf2:Recipes.release_terms(lterms) if left_result[1]
      Metaflip:Gf2:Recipes.release_terms(rterms) if right_result[1]
      owned = Metaflip:Gf2:Recipes.same_shape?(canonical, target)
    # an orientation shares some masks with its source: only a result that needed none is exclusively ours
    terms = Metaflip:Gf2:Recipes.orient(canonical, terms, target)
    Metaflip:Gf2:Recipes.check(terms.size == rank, "materialized composition rank mismatch")
    [terms.sort, owned]
