# RandomForestClassifier / RandomForestRegressor — bootstrap-aggregated
# CART forests (pure Tungsten, CPU-only; koala's first ENSEMBLE learner)
#
#     model = RandomForestClassifier.new(50, :sqrt, nil, 1, 42)
#     model.fit(x, y)                  # self when fitted, nil when unfittable
#     model.predict(x)                 # array of predicted labels
#     model.predict_proba(x)           # mean of the trees' leaf distributions
#     model.predict_proba(x, label)    # flat P(label) column, for ROC / log_loss
#     model.score(x, y)                # accuracy
#     model.oob_score                  # out-of-bag accuracy — a free holdout
#     model.trees                      # the root nodes, one per tree
#     model.tree_count                 # how many actually grew
#
#     RandomForestClassifier.new(n_estimators, max_features, max_depth,
#                                min_samples_leaf, seed, criterion, bootstrap,
#                                ccp_alpha, min_impurity_decrease,
#                                min_samples_split, max_samples,
#                                min_weight_fraction_leaf)
#     RandomForestRegressor.new(...the same twelve...)
#
# Where lib/decision_tree.w grows ONE tree, a forest grows many and
# averages them. That is the whole idea, and it is worth being precise
# about WHY it works: a fully grown CART tree has low bias and enormous
# variance — it will happily carve a box around a single mislabelled row —
# so the error it makes is mostly variance, and variance is exactly what
# averaging destroys. Averaging M *identical* trees destroys nothing, so
# the trees have to DISAGREE, and a forest manufactures disagreement twice:
#
#   * BOOTSTRAP — each tree is grown on n rows drawn WITH REPLACEMENT from
#     the n training rows, so each sees a different ~63% of them.
#   * PER-SPLIT FEATURE SUBSAMPLING — at EVERY node, only a random
#     `max_features`-sized subset of the features is even considered.
#
# The second is what separates a random forest from plain bagging, and it
# is per SPLIT, not per tree, on purpose: bagging alone leaves one dominant
# feature sitting at the root of nearly every tree, so the trees stay
# correlated and the average barely moves. Hiding that feature from a
# random majority of the nodes forces the weaker features to be used, and
# decorrelated errors are what the mean can actually cancel.
#
# --- The bootstrap IS a sample_weight vector ---
#
# Drawing row i exactly n_i times and fitting is, for this tree machinery,
# the identical tree that fitting once with `sample_weight[i] = n_i`
# produces — every weighted term is the unweighted term times an integer
# (see lib/estimator_base.w's definition of correctness). So a resample
# costs ONE float vector rather than a copy of the data, the caller's own
# sample_weight composes by simple multiplication (a row the caller
# weighted 2 and the bootstrap drew 3 times gets 6), and the rows drawn
# ZERO times fall out as that tree's OUT-OF-BAG set for free — which is
# where `oob_score` comes from.
#
# --- oob_score: the holdout you already paid for ---
#
# Each tree leaves out ~37% of the rows (1 - 1/e), and those rows are, for
# that tree, genuine unseen data. Predicting row i with exactly the trees
# that did NOT see it gives a held-out estimate over the WHOLE training set
# with no split, no second fit and no cross-validation loop:
#
#     model.oob_score          # accuracy (classifier) / R² (regressor)
#
# It is computed during fit whenever `bootstrap` is on and at least one row
# was left out by at least one tree — which is nearly always, since each
# tree leaves out about a third of them — and is nil otherwise: with
# `bootstrap = false` nothing is ever out of bag, and the regressor also
# answers nil below two scorable rows, where an R² would be meaningless.
# Rows that EVERY tree happened to bag are skipped rather than scored
# in-sample, which is the whole point of the number. `oob_score` is
# UNWEIGHTED even when the fit was weighted: it reports how often the
# ensemble is right on rows it did not see, and re-weighting that by the
# training importances would answer a different question.
#
# --- Determinism (a hard guarantee, both engines) ---
#
# A forest is random, so "deterministic" has to be earned rather than
# inherited. Every draw comes from ONE seeded MINSTD Lehmer stream — the
# generator lib/splitter.w and KFold already use (state * 48271 mod
# 2^31-1, whose worst-case product stays inside the 48-bit boxed-int
# range), reused rather than reinvented:
#
#     master = seed                    (nil means the fixed default, 1)
#     for each tree t, in order:  bootstrap state = next(master)
#                                 feature   state = next(master)
#
# The bootstrap draws consume their stream in row order; the feature draws
# are consumed by DecisionTree.split_features in the build's depth-first
# order. Both orders are fixed functions of the data, so the same seed and
# the same rows give a byte-identical forest — the same thresholds, the
# same predictions, the same Persist payload — on the interpreter and
# compiled alike. There is no unseeded mode: a nil seed is the fixed
# default stream, not entropy (core Random exposes no seeded PRNG, and a
# forest nobody can reproduce is not a model).
#
# --- Hyperparameters (twelve, all real tunable `params`) ---
#
#     n_estimators       trees in the forest (default 10)
#     max_features       features considered PER SPLIT:
#                          nil       — :sqrt for the classifier, all for the
#                                      regressor (scikit-learn's defaults)
#                          :sqrt     — floor(sqrt(n_features)), at least 1
#                          :log2     — floor(log2(n_features)), at least 1
#                          :all      — every feature (plain bagging)
#                          an Integer — that many, clamped to 1..n_features
#     max_depth          nil = unlimited; 0 = a single leaf, 1 a stump
#     min_samples_leaf   a split leaving a side smaller is inadmissible (>= 1)
#     seed               the MINSTD seed; nil = the fixed default stream
#     criterion          :gini / :entropy (classifier), :mse (regressor)
#     bootstrap          true (default) = resample per tree; false = every
#                        tree sees the whole sample
#     ccp_alpha          minimal cost-complexity pruning strength (>= 0);
#                        0 (default) keeps each fully grown tree
#     min_impurity_decrease
#                        minimum root-weighted impurity decrease required to
#                        grow a split in each tree (>= 0)
#     min_samples_split  a node smaller than this is never split (>= 2)
#     max_samples        nil draws n bootstrap rows per tree; an Integer draws
#                        that many (1..n), reducing fit cost and tree correlation
#     min_weight_fraction_leaf
#                        minimum fraction of each tree's bootstrap weight
#                        required in either child (0..0.5)
#
# `max_features` is a SYMBOL or an INTEGER, never a fraction: a float
# hyperparameter would have to survive `params`, `with_params`, a grid
# search and a Persist payload, and floats do not cross those boundaries
# by decimal text. The rules are the same ones sklearn's strings mean.
#
# They round-trip through `params` / `with_params`, so GridSearch tunes
# them — `GridSearch.new(RandomForestClassifier.new, { max_depth: [2, 4],
# max_features: [:sqrt, :all] }, 3)` — and a Pipeline exposes them as
# "forest.n_estimators".
#
# CLAMPING follows lib/decision_tree.w: `min_samples_leaf` and
# `min_samples_split` are clamped in the CONSTRUCTOR, so `params` reports
# the values actually in force and `m.with_params(m.params)` is the
# identity. `n_estimators` is NOT clamped, deliberately — it is a size,
# not a bound, and "grow me zero trees" is a request that cannot be honoured
# rather than one to quietly round up, so it is checked at fit and makes fit
# return nil. A `max_features` or a `criterion` this forest does not know
# does the same, never a silent fallback.
#
# --- The pinned relationship to a single tree ---
#
# `bootstrap = false` and `max_features = :all` removes BOTH sources of
# randomness, and one tree grown that way is not merely similar to a
# DecisionTreeClassifier — it is the same tree, node for node, because it
# runs the same DecisionTree.build over the same cfg:
#
#     RandomForestClassifier.new(1, :all, nil, 1, 0, nil, false)
#         # ... predicts exactly what DecisionTreeClassifier.new does
#
# spec/random_forest_spec.w asserts that against the RENDERED tree, not
# just the predictions. It is the plumbing test: if bagging, subsampling
# and averaging are wired correctly, switching them all off has to land
# back on the tree they were built from.
#
# Accepted shapes are the estimators' shared ones (Estimator.feature_rows /
# .target_values): x is a DataFrame, a Matrix, an array of row arrays or a
# flat single-feature array; y is a Series, a Vector or a plain array. An
# empty x, a ragged x, a y whose size mismatches, an unusable
# sample_weight, `n_estimators < 1`, an unknown criterion or an unknown
# max_features all make fit return nil and leave fitted? false; predict /
# predict_proba / score return nil before a successful fit and on a width
# mismatch, and predict_proba returns nil for a label the fit never saw.
#
# NOTE: the per-row accumulation loops below are WHILE loops over explicit
# indices. Every float here derives from the data via .to_f — a bare
# decimal literal is a Decimal and does not coerce with Float.

# The shared ensemble machinery, as statics so BOTH forests use one copy
# and a spec can exercise the pieces directly.
+ RandomForest
  # --- The MINSTD stream (lib/splitter.w's generator) ---

  # One step of the Lehmer generator: state * 48271 mod 2^31-1. The
  # worst-case product is ~1.04e14, inside the interpreter's 48-bit ints.
  -> .step(state)
    (state * 48271) % 2147483647

  # `seed` normalized into the stream's valid range (1 .. 2^31-2). nil —
  # and any seed that reduces to 0 — becomes 1: the default stream, so a
  # forest built without a seed is still reproducible.
  -> .seed_state(seed)
    s = 1
    s = seed % 2147483647 if seed != nil
    s = 1 if s <= 0
    s

  # --- max_features, resolved to a COUNT ---

  # floor(sqrt(n)), by integer arithmetic — no float, so no rounding can
  # differ between engines.
  -> .isqrt(n)
    i = 0
    while (i + 1) * (i + 1) <= n
      i += 1
    i

  # floor(log2(n)) for n >= 1, by repeated doubling.
  -> .ilog2(n)
    i = 0
    p = 2
    while p <= n
      p = p * 2
      i += 1
    i

  # How many features each split may consider, given the `max_features`
  # setting and the fitted width. -1 means "a setting this forest does not
  # know" — the caller turns that into a nil fit, never a silent fallback.
  #
  # The nil default differs by task exactly as scikit-learn's does: sqrt
  # for classification (where decorrelation buys the most and the signal
  # survives losing most features at a node), every feature for regression
  # (where a squared-error split needs the informative feature to be on
  # offer more often).
  -> .feature_count(setting, nf, regression)
    m = -1
    if setting == nil
      m = nf
      m = RandomForest.isqrt(nf) if !regression
    else
      if type(setting) == "Int"
        m = setting
        m = 1 if m < 1
        m = nf if m > nf
      else
        name = setting.to_s
        m = nf if name == "all"
        m = RandomForest.isqrt(nf) if name == "sqrt"
        m = RandomForest.ilog2(nf) if name == "log2"
        m = 1 if m == 0
    m

  # --- The bootstrap ---

  # How many times each of n rows was drawn in one bootstrap resample of
  # size `draws` (n by default), drawn WITH REPLACEMENT from `state`. A while
  # loop over explicit indices accumulates the counter, state and counts.
  -> .draw_counts(n, state, draws = nil)
    counts = []
    i = 0
    while i < n
      counts.push(0)
      i += 1
    st = state
    draw_count = draws
    draw_count = n if draw_count == nil
    d = 0
    while d < draw_count
      st = RandomForest.step(st)
      j = st % n
      counts[j] = counts[j] + 1
      d += 1
    counts

  # ONE tree's training sample, as { rows:, ys:, wts:, oob: }.
  #
  # With bootstrap ON the draw counts become SAMPLE WEIGHTS (multiplied
  # into the caller's own weights, so the two compose), the never-drawn
  # rows are dropped through the neutral Estimator.drop_zero_weights, and
  # their indices come back as `oob`. With it OFF every tree gets the whole
  # sample and the caller's weights untouched, and `oob` is empty.
  -> .sample_of(rows, ys, wts, state, bootstrap, max_samples = nil)
    out = { rows: rows, ys: ys, wts: wts, oob: [] }
    if bootstrap
      n = rows.size
      counts = RandomForest.draw_counts(n, state, max_samples)
      w = []
      oob = []
      i = 0
      while i < n
        base = 1.to_f
        base = wts[i] if wts != nil
        w.push(counts[i].to_f * base)
        oob.push(i) if counts[i] == 0
        i += 1
      trimmed = Estimator.drop_zero_weights(rows, ys, w)
      out = { rows: trimmed[:rows], ys: trimmed[:targets], wts: trimmed[:weights], oob: oob }
    out

  # --- Growing the ensemble ---

  # Every tree, as { trees: [root, ...], oob: [[index, ...], ...] }.
  #
  # `plan` carries what the loop needs: k / classes / nf / limit / min_split /
  # min_leaf / crit (the tree cfg), plus m (features per split), n_estimators,
  # bootstrap, max_samples, min_weight_fraction_leaf and seed. Each tree
  # draws TWO states off the master stream —
  # one for its bootstrap, one for its per-split feature draws — so the two
  # sources of randomness cannot alias, and tree t's stream does not depend
  # on how many nodes tree t-1 happened to grow.
  #
  # When m covers every feature the cfg's :max_features is left NIL rather
  # than set to nf. That is not an optimization: it puts the split search
  # on exactly the code path a plain tree takes, consuming no randomness at
  # all, which is what makes a one-tree unbootstrapped forest identical to
  # a DecisionTree rather than merely equivalent.
  -> .grow(rows, ys, wts, plan)
    trees = []
    oob = []
    ne = plan[:n_estimators]
    nf = plan[:nf]
    mf = plan[:m]
    mf = nil if mf >= nf
    st = RandomForest.seed_state(plan[:seed])
    t = 0
    while t < ne
      st = RandomForest.step(st)
      boot_state = st
      st = RandomForest.step(st)
      feat_state = st
      sample = RandomForest.sample_of(
        rows, ys, wts, boot_state, plan[:bootstrap], plan[:max_samples]
      )
      root_weight = Estimator.weight_total(sample[:wts], sample[:rows].size).to_f
      min_leaf_weight = plan[:min_weight_fraction_leaf] * root_weight
      cfg = { k: plan[:k], classes: plan[:classes], nf: nf, limit: plan[:limit], min_split: plan[:min_split], min_leaf: plan[:min_leaf], min_leaf_weight: min_leaf_weight, crit: plan[:crit], max_features: mf, rng: feat_state, min_gain: plan[:min_gain], root_weight: root_weight }
      tree = DecisionTree.build(sample[:rows], sample[:ys], sample[:wts], cfg, 0)
      DecisionTree.prune(tree, plan[:ccp_alpha])
      trees.push(tree)
      oob.push(sample[:oob])
      t += 1
    { trees: trees, oob: oob }

  # --- Reading the ensemble ---

  # The index of the largest entry, ties to the LOWEST index (a later
  # entry must be STRICTLY larger) — the same tie-break rule the trees
  # themselves use for a majority class.
  -> .argmax(vals)
    best = 0
    n = vals.size
    i = 1
    while i < n
      best = i if vals[i] > vals[best]
      i += 1
    best

  # One row's SOFT VOTE: the entry-wise MEAN of every tree's leaf class
  # distribution, in `classes` order. Averaging the distributions rather
  # than counting hard votes is scikit-learn's rule and the better one — a
  # leaf that is 51/49 should not shout as loudly as a pure one.
  #
  # Every tree shares the forest's ONE `classes` array, so the k entries
  # line up across trees with no remapping; a class a bootstrap sample
  # happened to miss simply contributes zeros.
  -> .vote_row(trees, row, k)
    acc = []
    c = 0
    while c < k
      acc.push(0.to_f)
      c += 1
    nt = trees.size
    t = 0
    while t < nt
      leaf = DecisionTree.descend(trees[t], row)
      p = DecisionTree.proba_of(leaf)
      j = 0
      while j < k
        acc[j] = acc[j] + p[j]
        j += 1
      t += 1
    d = nt.to_f
    out = []
    e = 0
    while e < k
      out.push(acc[e] / d)
      e += 1
    out

  # Batch soft voting projects each hash tree once, then walks its parallel
  # arrays for every row. Full probabilities accumulate in one flat row*class
  # buffer; a requested class column uses one scalar per row and per leaf, never
  # constructing the other class values. Passing `labels` emits the winning
  # label directly from those same totals: predict therefore avoids allocating
  # and normalizing a probability row only to scan it again for argmax.
  # Tree order within each row is unchanged, preserving floating-point
  # accumulation and tie behavior exactly. Small batches keep direct hash
  # descent so flattening a large forest cannot dominate one prediction.
  -> .vote_rows(trees, rows, k, missing_possible = true, class_index = nil, labels = nil)
    out = []
    if rows.size < 32
      rows.each -> (row)
        if class_index == nil
          probability = RandomForest.vote_row(trees, row, k)
          if labels == nil
            out.push(probability)
          else
            out.push(labels[RandomForest.argmax(probability)])
        else
          acc = 0.to_f
          trees.each -> (tree)
            leaf = DecisionTree.descend(tree, row)
            acc += leaf[:counts][class_index].to_f / leaf[:weight].to_f
          out.push(acc / trees.size.to_f)
    else
      votes = []
      vote_count = rows.size
      vote_count = rows.size * k if class_index == nil
      vote_count.times -> (i)
        votes.push(0.to_f)
      trees.each -> (tree)
        program = DecisionTree.prediction_program(tree, true, class_index)
        features = program[0]
        thresholds = program[1]
        missing_directions = program[2]
        left_indices = program[3]
        right_indices = program[4]
        probabilities = program[6]
        i = 0
        while i < rows.size
          row = rows[i]
          index = 0
          if missing_possible
            while features[index] >= 0
              value = row[features[index]]
              missing = DecisionTree.missing?(value)
              go_left = missing_directions[index]
              go_left = value <= thresholds[index] if !missing
              if go_left
                index = left_indices[index]
              else
                index = right_indices[index]
          else
            while features[index] >= 0
              value = row[features[index]]
              go_left = value <= thresholds[index]
              if go_left
                index = left_indices[index]
              else
                index = right_indices[index]
          probability = probabilities[index]
          if class_index == nil
            offset = i * k
            c = 0
            while c < k
              votes[offset + c] += probability[c]
              c += 1
          else
            votes[i] += probability
          i += 1
      divisor = trees.size.to_f
      if class_index == nil
        i = 0
        while i < rows.size
          offset = i * k
          if labels == nil
            probability = []
            c = 0
            while c < k
              probability.push(votes[offset + c] / divisor)
              c += 1
            out.push(probability)
          else
            # Compare the normalized values, as predict_proba + argmax did,
            # so even a floating-point near-tie retains the old result.
            best = 0
            best_probability = votes[offset] / divisor
            c = 1
            while c < k
              candidate = votes[offset + c] / divisor
              if candidate > best_probability
                best = c
                best_probability = candidate
              c += 1
            out.push(labels[best])
          i += 1
      else
        i = 0
        while i < votes.size
          out.push(votes[i] / divisor)
          i += 1
    out

  # One row's regression prediction: the plain MEAN of the trees' leaf
  # means.
  -> .mean_row(trees, row)
    acc = 0.to_f
    nt = trees.size
    t = 0
    while t < nt
      leaf = DecisionTree.descend(trees[t], row)
      acc += leaf[:prediction]
      t += 1
    acc / nt.to_f

  -> .mean_rows(trees, rows, missing_possible = true)
    out = []
    if rows.size < 32
      rows.each -> (row)
        out.push(RandomForest.mean_row(trees, row))
    else
      rows.size.times -> (i)
        out.push(0.to_f)
      trees.each -> (tree)
        program = DecisionTree.prediction_program(tree)
        features = program[0]
        thresholds = program[1]
        missing_directions = program[2]
        left_indices = program[3]
        right_indices = program[4]
        predictions = program[5]
        i = 0
        while i < rows.size
          row = rows[i]
          index = 0
          if missing_possible
            while features[index] >= 0
              value = row[features[index]]
              missing = DecisionTree.missing?(value)
              go_left = missing_directions[index]
              go_left = value <= thresholds[index] if !missing
              if go_left
                index = left_indices[index]
              else
                index = right_indices[index]
          else
            while features[index] >= 0
              value = row[features[index]]
              go_left = value <= thresholds[index]
              if go_left
                index = left_indices[index]
              else
                index = right_indices[index]
          out[i] += predictions[index]
          i += 1
      divisor = trees.size.to_f
      i = 0
      while i < out.size
        out[i] = out[i] / divisor
        i += 1
    out

  # One row per sample and one column per fitted tree, containing each
  # reached leaf's zero-based preorder node index. This is the matrix shape
  # and numbering of scikit-learn's forest `apply`. Project each tree once,
  # then transpose its leaf-index column into the public row-major result.
  -> .leaf_index_rows(trees, rows, missing_possible = true)
    out = []
    rows.size.times -> (i)
      out.push([])
    trees.each -> (tree)
      indices = DecisionTree.batch_leaf_indices(
        tree, rows, missing_possible
      )
      i = 0
      while i < indices.size
        out[i].push(indices[i])
        i += 1
    out

  # --- Out-of-bag scoring ---

  # Per-row summed class distributions from ONLY the trees that did not
  # see that row, plus how many trees that was: { votes:, seen: }. A row
  # every tree bagged has seen = 0 and is skipped by the scorers below.
  -> .oob_votes(trees, oob, rows, k)
    n = rows.size
    votes = []
    seen = []
    i = 0
    while i < n
      col = []
      c = 0
      while c < k
        col.push(0.to_f)
        c += 1
      votes.push(col)
      seen.push(0)
      i += 1
    nt = trees.size
    t = 0
    while t < nt
      idx = oob[t]
      m = idx.size
      q = 0
      while q < m
        ix = idx[q]
        leaf = DecisionTree.descend(trees[t], rows[ix])
        p = DecisionTree.proba_of(leaf)
        col = votes[ix]
        j = 0
        while j < k
          col[j] = col[j] + p[j]
          j += 1
        seen[ix] = seen[ix] + 1
        q += 1
      t += 1
    { votes: votes, seen: seen }

  # Out-of-bag ACCURACY over the rows at least one tree left out, or nil
  # when no row was. `ys` are class INDICES, as the build saw them.
  -> .oob_accuracy(trees, oob, rows, ys, k)
    tally = RandomForest.oob_votes(trees, oob, rows, k)
    votes = tally[:votes]
    seen = tally[:seen]
    n = rows.size
    hit = 0
    used = 0
    i = 0
    while i < n
      if seen[i] > 0
        used += 1
        hit += 1 if RandomForest.argmax(votes[i]) == ys[i]
        i += 1
      else
        i += 1
    out = nil
    out = hit.to_f / used.to_f if used > 0
    out

  # Per-row summed regression predictions from the trees that did not see
  # the row, and how many those were: { total:, seen: }.
  -> .oob_totals(trees, oob, rows)
    n = rows.size
    total = []
    seen = []
    i = 0
    while i < n
      total.push(0.to_f)
      seen.push(0)
      i += 1
    nt = trees.size
    t = 0
    while t < nt
      idx = oob[t]
      m = idx.size
      q = 0
      while q < m
        ix = idx[q]
        leaf = DecisionTree.descend(trees[t], rows[ix])
        total[ix] = total[ix] + leaf[:prediction].to_f
        seen[ix] = seen[ix] + 1
        q += 1
      t += 1
    { total: total, seen: seen }

  # Out-of-bag R² over the rows at least one tree left out, or nil when
  # fewer than two rows qualify (R² of one point is meaningless).
  -> .oob_r2(trees, oob, rows, ys)
    tally = RandomForest.oob_totals(trees, oob, rows)
    total = tally[:total]
    seen = tally[:seen]
    n = rows.size
    preds = []
    acts = []
    i = 0
    while i < n
      if seen[i] > 0
        preds.push(total[i] / seen[i].to_f)
        acts.push(ys[i])
        i += 1
      else
        i += 1
    out = nil
    out = Metrics.r2(preds, acts, nil) if preds.size > 1
    out

  # --- Shape validation, shared by both forests ---

  # Are `rows` / `targets` a usable training set — non-empty, rectangular,
  # at least one feature, and the same length? The forests' fit methods
  # differ only in criterion and leaf value, so the shape rules live once.
  -> .shapes_ok?(rows, targets)
    ok = rows != nil && targets != nil
    ok = rows.size > 0 && rows.size == targets.size if ok
    ok = DecisionTree.usable_rows?(rows) if ok
    ok

  # Mean of each tree's normalized impurity importance, normalized once
  # more for numerical stability. This gives every estimator in the ensemble
  # equal influence even when weighted bootstraps have different root totals.
  -> .feature_importances(trees, n_features)
    out = []
    i = 0
    while i < n_features
      out.push(0.to_f)
      i += 1
    trees.each -> (tree)
      one = DecisionTree.feature_importances(tree, n_features)
      i = 0
      while i < out.size
        out[i] += one[i]
        i += 1
    total = 0.to_f
    out.each -> (value)
      total += value
    if total > 0.to_f
      i = 0
      while i < out.size
        out[i] = out[i] / total
        i += 1
    out

# A bagged forest of CART classification trees: bootstrap resampling,
# per-split feature subsampling, and a soft vote over the ensemble. See the
# file header for the algorithm, the determinism guarantee, `oob_score` and
# the hyperparameters.
+ RandomForestClassifier
  is Estimable
  is SupervisedEstimator

  ro :classes            # distinct labels, first-seen order; nil before fit
  ro :trees              # the root nodes, one per tree; nil before fit
  ro :n_features         # features the fit saw; nil before fit
  ro :oob_score          # out-of-bag accuracy; nil when unavailable
  ro :n_estimators       # trees to grow
  ro :max_features       # per-split feature budget (see the header)
  ro :max_depth          # nil = unlimited
  ro :min_samples_leaf   # >= 1
  ro :seed               # MINSTD seed; nil = the default stream
  ro :criterion          # :gini (default) or :entropy
  ro :bootstrap          # true (default) = resample per tree
  ro :ccp_alpha          # >= 0; applied independently to every grown tree
  ro :min_impurity_decrease # >= 0; minimum root-weighted split gain
  ro :min_samples_split  # >= 2; node-size floor for every grown tree
  ro :max_samples        # nil = n bootstrap draws; Integer = 1..n draws
  ro :min_weight_fraction_leaf # 0..0.5 within each bootstrap sample

  -> new(n_estimators = nil, max_features = nil, max_depth = nil, min_samples_leaf = nil, seed = nil, criterion = nil, bootstrap = nil, ccp_alpha = nil, min_impurity_decrease = nil, min_samples_split = nil, max_samples = nil, min_weight_fraction_leaf = nil)
    ne = n_estimators
    ne = 10 if ne == nil
    ml = min_samples_leaf
    ml = 1 if ml == nil
    ml = 1 if ml < 1
    cr = criterion
    cr = :gini if cr == nil
    bs = bootstrap
    bs = true if bs == nil
    alpha = ccp_alpha
    alpha = 0.to_f if alpha == nil
    alpha = alpha.to_f
    min_gain = min_impurity_decrease
    min_gain = 0.to_f if min_gain == nil
    min_gain = min_gain.to_f
    min_split = min_samples_split
    min_split = 2 if min_split == nil
    min_split = 2 if min_split < 2
    min_weight_fraction = min_weight_fraction_leaf
    min_weight_fraction = 0.to_f if min_weight_fraction == nil
    min_weight_fraction = min_weight_fraction.to_f
    @n_estimators = ne
    @max_features = max_features
    @max_depth = max_depth
    @min_samples_leaf = ml
    @seed = seed
    @criterion = cr
    @bootstrap = bs
    @ccp_alpha = alpha
    @min_impurity_decrease = min_gain
    @min_samples_split = min_split
    @max_samples = max_samples
    @min_weight_fraction_leaf = min_weight_fraction
    @fitted = false
    @classes = nil
    @trees = nil
    @n_features = nil
    @oob_score = nil

  -> fitted?
    @fitted

  # How many trees actually grew; nil before fit.
  -> tree_count
    out = nil
    out = @trees.size if @fitted
    out

  # Mean of the trees' normalized impurity importances, normalized once
  # more for numerical stability. A feature unused by every tree is zero;
  # an all-stump forest returns all zeros.
  -> feature_importances
    out = nil
    out = RandomForest.feature_importances(@trees, @n_features) if @fitted
    out

  # --- Estimable contract (see lib/estimator_base.w) ---

  -> estimator_name
    "RandomForestClassifier"

  -> supervised?
    true

  # The caller's weights multiply INTO each tree's bootstrap draw counts,
  # so a weighted forest is the forest of the row-duplicated dataset — see
  # the header and RandomForest.sample_of.
  -> supports_sample_weight?
    true

  # The twelve knobs a search varies — never the grown trees.
  -> params
    { n_estimators: @n_estimators, max_features: @max_features, max_depth: @max_depth, min_samples_leaf: @min_samples_leaf, seed: @seed, criterion: @criterion, bootstrap: @bootstrap, ccp_alpha: @ccp_alpha, min_impurity_decrease: @min_impurity_decrease, min_samples_split: @min_samples_split, max_samples: @max_samples, min_weight_fraction_leaf: @min_weight_fraction_leaf }

  # A NEW, UNFITTED RandomForestClassifier with `overrides` applied; self is
  # left untouched. Unmentioned keys carry over, so with_params(params)
  # round-trips.
  -> with_params(overrides)
    ne = Estimator.opt(overrides, :n_estimators, @n_estimators)
    mf = Estimator.opt(overrides, :max_features, @max_features)
    md = Estimator.opt(overrides, :max_depth, @max_depth)
    ml = Estimator.opt(overrides, :min_samples_leaf, @min_samples_leaf)
    sd = Estimator.opt(overrides, :seed, @seed)
    cr = Estimator.opt(overrides, :criterion, @criterion)
    bs = Estimator.opt(overrides, :bootstrap, @bootstrap)
    alpha = Estimator.opt(overrides, :ccp_alpha, @ccp_alpha)
    min_gain = Estimator.opt(overrides, :min_impurity_decrease, @min_impurity_decrease)
    min_split = Estimator.opt(overrides, :min_samples_split, @min_samples_split)
    max_samples = Estimator.opt(overrides, :max_samples, @max_samples)
    min_weight_fraction = Estimator.opt(overrides, :min_weight_fraction_leaf, @min_weight_fraction_leaf)
    RandomForestClassifier.new(ne, mf, md, ml, sd, cr, bs, alpha, min_gain, min_split, max_samples, min_weight_fraction)

  # --- Fit ---

  # Grow the forest from x/y. Returns self, or nil — fitted? stays false —
  # for an unusable shape, an unusable sample_weight, `n_estimators < 1`,
  # a criterion this tree kind does not know, or a max_features setting
  # that is not one of the documented ones.
  #
  # `classes` is derived ONCE, from the full training labels in first-seen
  # order, and every tree is grown against it. That is what lets the
  # ensemble average leaf distributions entry-wise with no remapping, and
  # it is why the trees are grown from DecisionTree.build directly rather
  # than from DecisionTreeClassifier instances (each of which would derive
  # its own class order from its own bootstrap sample).
  -> fit(x, y, sample_weight = nil)
    rows = Estimator.feature_rows(x)
    labels = Estimator.target_values(y)
    ok = RandomForest.shapes_ok?(rows, labels)
    ok = false if !DecisionTree.criterion_ok?(@criterion, false)
    ok = false if @n_estimators < 1
    ok = false if @ccp_alpha < 0.to_f
    ok = false if @min_impurity_decrease < 0.to_f
    ok = false if @min_weight_fraction_leaf < 0.to_f
    ok = false if @min_weight_fraction_leaf > 1.to_f / 2.to_f
    if @max_samples != nil
      ok = false if !@max_samples.is_a?(Integer)
      ok = false if @max_samples.is_a?(Integer) && @max_samples < 1
      ok = false if !@bootstrap
    wts = nil
    wts = Estimator.weight_values(sample_weight, rows.size) if ok && sample_weight != nil
    ok = false if sample_weight != nil && wts == nil
    if ok && wts != nil
      trimmed = Estimator.drop_zero_weights(rows, labels, wts)
      rows = trimmed[:rows]
      labels = trimmed[:targets]
      wts = trimmed[:weights]
    ok = false if ok && @max_samples != nil && @max_samples > rows.size
    nf = 0
    nf = rows[0].size if ok
    mf = -1
    mf = RandomForest.feature_count(@max_features, nf, false) if ok
    ok = false if mf < 1
    out = nil
    if ok
      classes = []
      labels.each -> (l)
        classes.push(l) if !classes.include?(l)
      ys = []
      labels.each -> (l)
        ys.push(DecisionTree.label_index(classes, l))
      limit = @max_depth
      limit = -1 if limit == nil
      limit = 0 if limit < 0 && @max_depth != nil
      plan = { k: classes.size, classes: classes, nf: nf, limit: limit, min_split: @min_samples_split, min_leaf: @min_samples_leaf, min_weight_fraction_leaf: @min_weight_fraction_leaf, crit: @criterion.to_s, m: mf, n_estimators: @n_estimators, bootstrap: @bootstrap, max_samples: @max_samples, seed: @seed, ccp_alpha: @ccp_alpha, min_gain: @min_impurity_decrease }
      grown = RandomForest.grow(rows, ys, wts, plan)
      @classes = classes
      @n_features = nf
      @trees = grown[:trees]
      @oob_score = RandomForest.oob_accuracy(grown[:trees], grown[:oob], rows, ys, classes.size)
      @fitted = true
      out = self
    out

  # --- Predict ---

  # x coerced to feature rows, or nil before fit and on a width mismatch.
  -> query_rows(x)
    rows = nil
    rows = Estimator.feature_rows(x) if @fitted
    out = nil
    if rows != nil
      status = DecisionTree.row_status(rows, true, @n_features)
      out = rows if status >= 0
    out

  # Zero-based preorder leaf ID for every [sample, tree], matching the shape
  # of scikit-learn's RandomForestClassifier.apply.
  -> leaf_indices(x)
    rows = nil
    rows = Estimator.feature_rows(x) if @fitted
    out = nil
    if rows != nil
      status = DecisionTree.row_status(rows, true, @n_features)
      out = RandomForest.leaf_index_rows(@trees, rows, status > 0) if status >= 0
    out

  # The ensemble's mean class distribution per row. With no label: one
  # array per row, one entry per class in `classes` order, summing to 1.
  # With a label: the flat P(label) column, ready for Metrics.roc_auc /
  # Metrics.log_loss. nil before fit, on a width mismatch, or for a label
  # the fit never saw.
  -> predict_proba(x, pos_label = nil)
    rows = nil
    rows = Estimator.feature_rows(x) if @fitted
    out = nil
    if rows != nil
      status = DecisionTree.row_status(rows, true, @n_features)
      if status >= 0
        trees = @trees
        k = @classes.size
        if pos_label == nil
          out = RandomForest.vote_rows(trees, rows, k, status > 0)
        else
          idx = DecisionTree.label_index(@classes, pos_label)
          if idx >= 0
            out = RandomForest.vote_rows(trees, rows, k, status > 0, idx)
    out

  # Predicted labels for x: the class with the largest mean probability,
  # ties to the first-seen label. The batch voter emits labels directly so
  # this does not materialize a probability matrix that the caller did not
  # request.
  -> predict(x)
    out = nil
    rows = nil
    rows = Estimator.feature_rows(x) if @fitted
    if rows != nil
      status = DecisionTree.row_status(rows, true, @n_features)
      if status >= 0
        out = RandomForest.vote_rows(
          @trees, rows, @classes.size, status > 0, nil, @classes
        )
    out

  # Accuracy (Metrics.accuracy) of self's predictions on x against y,
  # weighted when sample_weight is given; nil before fit, when the shapes
  # do not line up, or when the weights are unusable.
  -> score(x, y, sample_weight = nil)
    preds = self.predict(x)
    yvals = Estimator.target_values(y)
    out = nil
    if preds != nil && yvals != nil
      ok = preds.size == yvals.size && preds.size > 0
      wts = nil
      wts = Estimator.weight_values(sample_weight, preds.size) if ok && sample_weight != nil
      ok = false if sample_weight != nil && wts == nil
      out = Metrics.accuracy(preds, yvals, wts) if ok
    out

  # --- Persistence (see lib/persist.w) ---

  -> persist_name
    "RandomForestClassifier"

  # EVERY tree goes in. Like a single tree's, the ensemble needs no encoder
  # of its own: a node is a plain hash whose children are plain hashes, and
  # the forest is a plain ARRAY of those, so the format's generic array and
  # hash nodes carry the whole recursion for free.
  -> to_state
    { n_estimators: @n_estimators, max_features: @max_features, max_depth: @max_depth, min_samples_leaf: @min_samples_leaf, seed: @seed, criterion: @criterion, bootstrap: @bootstrap, ccp_alpha: @ccp_alpha, min_impurity_decrease: @min_impurity_decrease, min_samples_split: @min_samples_split, max_samples: @max_samples, min_weight_fraction_leaf: @min_weight_fraction_leaf, classes: @classes, trees: @trees, n_features: @n_features, oob_score: @oob_score }

  -> .load_state(st)
    out = nil
    ok = st != nil
    ok = st[:n_estimators] != nil && st[:min_samples_leaf] != nil && st[:criterion] != nil if ok
    ok = st[:classes] != nil && st[:trees] != nil && st[:n_features] != nil if ok
    if ok
      model = RandomForestClassifier.new(st[:n_estimators], st[:max_features], st[:max_depth], st[:min_samples_leaf], st[:seed], st[:criterion], st[:bootstrap], st[:ccp_alpha], st[:min_impurity_decrease], st[:min_samples_split], st[:max_samples], st[:min_weight_fraction_leaf])
      out = model.restore_state(st)
    out

  -> restore_state(st)
    @classes = st[:classes]
    @trees = st[:trees]
    @n_features = st[:n_features]
    @oob_score = st[:oob_score]
    @fitted = true
    self

# A bagged forest of CART regression trees on the SAME machinery: the same
# bootstrap, the same per-split feature subsampling, MSE as the criterion
# and the plain MEAN of the trees' leaf means as the prediction. `score` is
# R² (Metrics.r2), matching LinearRegression and DecisionTreeRegressor, so
# CrossValidation and GridSearch rank it the same way.
#
# `max_features` defaults to ALL features here rather than to :sqrt — the
# classifier's default — following scikit-learn: a squared-error split
# needs the informative feature on offer more often than a vote does, and
# the bootstrap alone already decorrelates a regression ensemble usefully.
+ RandomForestRegressor
  is Estimable
  is SupervisedEstimator

  ro :trees              # the root nodes, one per tree; nil before fit
  ro :n_features         # features the fit saw; nil before fit
  ro :oob_score          # out-of-bag R²; nil when unavailable
  ro :n_estimators       # trees to grow
  ro :max_features       # per-split feature budget (see the header)
  ro :max_depth          # nil = unlimited
  ro :min_samples_leaf   # >= 1
  ro :seed               # MINSTD seed; nil = the default stream
  ro :criterion          # :mse (default; :variance is accepted as an alias)
  ro :bootstrap          # true (default) = resample per tree
  ro :ccp_alpha          # >= 0; applied independently to every grown tree
  ro :min_impurity_decrease # >= 0; minimum root-weighted split gain
  ro :min_samples_split  # >= 2; node-size floor for every grown tree
  ro :max_samples        # nil = n bootstrap draws; Integer = 1..n draws
  ro :min_weight_fraction_leaf # 0..0.5 within each bootstrap sample

  -> new(n_estimators = nil, max_features = nil, max_depth = nil, min_samples_leaf = nil, seed = nil, criterion = nil, bootstrap = nil, ccp_alpha = nil, min_impurity_decrease = nil, min_samples_split = nil, max_samples = nil, min_weight_fraction_leaf = nil)
    ne = n_estimators
    ne = 10 if ne == nil
    ml = min_samples_leaf
    ml = 1 if ml == nil
    cr = criterion
    cr = :mse if cr == nil
    bs = bootstrap
    bs = true if bs == nil
    alpha = ccp_alpha
    alpha = 0.to_f if alpha == nil
    alpha = alpha.to_f
    min_gain = min_impurity_decrease
    min_gain = 0.to_f if min_gain == nil
    min_gain = min_gain.to_f
    min_split = min_samples_split
    min_split = 2 if min_split == nil
    min_split = 2 if min_split < 2
    min_weight_fraction = min_weight_fraction_leaf
    min_weight_fraction = 0.to_f if min_weight_fraction == nil
    min_weight_fraction = min_weight_fraction.to_f
    @n_estimators = ne
    @max_features = max_features
    @max_depth = max_depth
    @min_samples_leaf = ml
    @seed = seed
    @criterion = cr
    @bootstrap = bs
    @ccp_alpha = alpha
    @min_impurity_decrease = min_gain
    @min_samples_split = min_split
    @max_samples = max_samples
    @min_weight_fraction_leaf = min_weight_fraction
    @fitted = false
    @trees = nil
    @n_features = nil
    @oob_score = nil

  -> fitted?
    @fitted

  -> tree_count
    out = nil
    out = @trees.size if @fitted
    out

  # Mean normalized MSE decrease across the fitted trees; nil before fit.
  -> feature_importances
    out = nil
    out = RandomForest.feature_importances(@trees, @n_features) if @fitted
    out

  # --- Estimable contract (see lib/estimator_base.w) ---

  -> estimator_name
    "RandomForestRegressor"

  -> supervised?
    true

  -> supports_sample_weight?
    true

  -> params
    { n_estimators: @n_estimators, max_features: @max_features, max_depth: @max_depth, min_samples_leaf: @min_samples_leaf, seed: @seed, criterion: @criterion, bootstrap: @bootstrap, ccp_alpha: @ccp_alpha, min_impurity_decrease: @min_impurity_decrease, min_samples_split: @min_samples_split, max_samples: @max_samples, min_weight_fraction_leaf: @min_weight_fraction_leaf }

  -> with_params(overrides)
    ne = Estimator.opt(overrides, :n_estimators, @n_estimators)
    mf = Estimator.opt(overrides, :max_features, @max_features)
    md = Estimator.opt(overrides, :max_depth, @max_depth)
    ml = Estimator.opt(overrides, :min_samples_leaf, @min_samples_leaf)
    sd = Estimator.opt(overrides, :seed, @seed)
    cr = Estimator.opt(overrides, :criterion, @criterion)
    bs = Estimator.opt(overrides, :bootstrap, @bootstrap)
    alpha = Estimator.opt(overrides, :ccp_alpha, @ccp_alpha)
    min_gain = Estimator.opt(overrides, :min_impurity_decrease, @min_impurity_decrease)
    min_split = Estimator.opt(overrides, :min_samples_split, @min_samples_split)
    max_samples = Estimator.opt(overrides, :max_samples, @max_samples)
    min_weight_fraction = Estimator.opt(overrides, :min_weight_fraction_leaf, @min_weight_fraction_leaf)
    RandomForestRegressor.new(ne, mf, md, ml, sd, cr, bs, alpha, min_gain, min_split, max_samples, min_weight_fraction)

  # --- Fit ---

  # Grow the forest from x/y. The nil list is the classifier's, minus the
  # classes it has none of.
  -> fit(x, y, sample_weight = nil)
    rows = Estimator.feature_rows(x)
    targets = Estimator.target_values(y)
    ok = RandomForest.shapes_ok?(rows, targets)
    ok = DecisionTree.numeric_targets?(targets) if ok
    ok = false if !DecisionTree.criterion_ok?(@criterion, true)
    ok = false if @n_estimators < 1
    ok = false if @ccp_alpha < 0.to_f
    ok = false if @min_impurity_decrease < 0.to_f
    ok = false if @min_weight_fraction_leaf < 0.to_f
    ok = false if @min_weight_fraction_leaf > 1.to_f / 2.to_f
    if @max_samples != nil
      ok = false if !@max_samples.is_a?(Integer)
      ok = false if @max_samples.is_a?(Integer) && @max_samples < 1
      ok = false if !@bootstrap
    wts = nil
    wts = Estimator.weight_values(sample_weight, rows.size) if ok && sample_weight != nil
    ok = false if sample_weight != nil && wts == nil
    if ok && wts != nil
      trimmed = Estimator.drop_zero_weights(rows, targets, wts)
      rows = trimmed[:rows]
      targets = trimmed[:targets]
      wts = trimmed[:weights]
    ok = false if ok && @max_samples != nil && @max_samples > rows.size
    nf = 0
    nf = rows[0].size if ok
    mf = -1
    mf = RandomForest.feature_count(@max_features, nf, true) if ok
    ok = false if mf < 1
    out = nil
    if ok
      ys = []
      targets.each -> (v)
        ys.push(v.to_f)
      limit = @max_depth
      limit = -1 if limit == nil
      limit = 0 if limit < 0 && @max_depth != nil
      plan = { k: 0, classes: nil, nf: nf, limit: limit, min_split: @min_samples_split, min_leaf: @min_samples_leaf, min_weight_fraction_leaf: @min_weight_fraction_leaf, crit: "mse", m: mf, n_estimators: @n_estimators, bootstrap: @bootstrap, max_samples: @max_samples, seed: @seed, ccp_alpha: @ccp_alpha, min_gain: @min_impurity_decrease }
      grown = RandomForest.grow(rows, ys, wts, plan)
      @n_features = nf
      @trees = grown[:trees]
      @oob_score = RandomForest.oob_r2(grown[:trees], grown[:oob], rows, ys)
      @fitted = true
      out = self
    out

  # --- Predict ---

  -> query_rows(x)
    rows = nil
    rows = Estimator.feature_rows(x) if @fitted
    out = nil
    if rows != nil
      status = DecisionTree.row_status(rows, true, @n_features)
      out = rows if status >= 0
    out

  # Zero-based preorder leaf ID for every [sample, tree].
  -> leaf_indices(x)
    rows = nil
    rows = Estimator.feature_rows(x) if @fitted
    out = nil
    if rows != nil
      status = DecisionTree.row_status(rows, true, @n_features)
      out = RandomForest.leaf_index_rows(@trees, rows, status > 0) if status >= 0
    out

  # Predicted values for x — the mean of the trees' leaf means.
  -> predict(x)
    rows = nil
    rows = Estimator.feature_rows(x) if @fitted
    out = nil
    if rows != nil
      status = DecisionTree.row_status(rows, true, @n_features)
      out = RandomForest.mean_rows(@trees, rows, status > 0) if status >= 0
    out

  # R² (Metrics.r2) of self's predictions on x against y, weighted when
  # sample_weight is given; nil before fit, when the shapes do not line up,
  # or when the weights are unusable.
  -> score(x, y, sample_weight = nil)
    preds = self.predict(x)
    yvals = Estimator.target_values(y)
    out = nil
    if preds != nil && yvals != nil
      ok = preds.size == yvals.size && preds.size > 0
      wts = nil
      wts = Estimator.weight_values(sample_weight, preds.size) if ok && sample_weight != nil
      ok = false if sample_weight != nil && wts == nil
      out = Metrics.r2(preds, yvals, wts) if ok
    out

  # --- Persistence (see lib/persist.w) ---

  -> persist_name
    "RandomForestRegressor"

  # As for the classifier, minus `classes` — a regression leaf predicts a
  # mean, so there are no labels to carry.
  -> to_state
    { n_estimators: @n_estimators, max_features: @max_features, max_depth: @max_depth, min_samples_leaf: @min_samples_leaf, seed: @seed, criterion: @criterion, bootstrap: @bootstrap, ccp_alpha: @ccp_alpha, min_impurity_decrease: @min_impurity_decrease, min_samples_split: @min_samples_split, max_samples: @max_samples, min_weight_fraction_leaf: @min_weight_fraction_leaf, trees: @trees, n_features: @n_features, oob_score: @oob_score }

  -> .load_state(st)
    out = nil
    ok = st != nil
    ok = st[:n_estimators] != nil && st[:min_samples_leaf] != nil && st[:criterion] != nil if ok
    ok = st[:trees] != nil && st[:n_features] != nil if ok
    # A CLASSIFIER payload carries `classes` and leaves that predict
    # LABELS; loading one here would average strings. The classifier's own
    # loader already refuses a regressor payload (it requires `classes`),
    # so this closes the other direction.
    ok = st[:classes] == nil if ok
    if ok
      model = RandomForestRegressor.new(st[:n_estimators], st[:max_features], st[:max_depth], st[:min_samples_leaf], st[:seed], st[:criterion], st[:bootstrap], st[:ccp_alpha], st[:min_impurity_decrease], st[:min_samples_split], st[:max_samples], st[:min_weight_fraction_leaf])
      out = model.restore_state(st)
    out

  -> restore_state(st)
    @trees = st[:trees]
    @n_features = st[:n_features]
    @oob_score = st[:oob_score]
    @fitted = true
    self
