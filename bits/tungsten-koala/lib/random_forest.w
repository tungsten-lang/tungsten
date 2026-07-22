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
#                                min_samples_leaf, seed, criterion, bootstrap)
#     RandomForestRegressor.new(...the same seven...)
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
# --- Hyperparameters (seven, all real tunable `params`) ---
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
# CLAMPING follows lib/decision_tree.w: `min_samples_leaf` is clamped in
# the CONSTRUCTOR, so `params` reports the value actually in force and
# `m.with_params(m.params)` is the identity. `n_estimators` is NOT clamped,
# deliberately — it is a size, not a bound, and "grow me zero trees" is a
# request that cannot be honoured rather than one to quietly round up, so
# it is checked at fit and makes fit return nil. A `max_features` or a
# `criterion` this forest does not know does the same, never a silent
# fallback.
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
# `min_samples_split` is not a forest hyperparameter — the trees use the
# tree default (2). A forest controls complexity with `max_depth` and
# `min_samples_leaf`; a third size knob would add a search dimension that
# does nothing bagging does not already do.
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
# NOTE: the per-row accumulation loops below are WHILE loops, not blocks,
# on purpose — two sibling closures capturing the same accumulator in one
# block miscompiles today (see lib/estimator_base.w), and an ensemble's
# inner loop is exactly that shape. Locals are hoisted from ivars before
# any `-> (x)` block, arrays are built with push, and no float literal
# appears here: every float derives from the data via .to_f.

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
      if type(setting) == "Integer"
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
  # size n, drawn WITH REPLACEMENT from `state`. A while loop rather than
  # a block: the counter, the state and the counts vector would otherwise
  # be three captures of the same accumulator shape.
  -> .draw_counts(n, state)
    counts = []
    i = 0
    while i < n
      counts.push(0)
      i += 1
    st = state
    d = 0
    while d < n
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
  -> .sample_of(rows, ys, wts, state, bootstrap)
    out = { rows: rows, ys: ys, wts: wts, oob: [] }
    if bootstrap
      n = rows.size
      counts = RandomForest.draw_counts(n, state)
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
  # `plan` carries what the loop needs: k / classes / nf / limit / min_leaf
  # / crit (the tree cfg), plus m (features per split), n_estimators,
  # bootstrap and seed. Each tree draws TWO states off the master stream —
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
      sample = RandomForest.sample_of(rows, ys, wts, boot_state, plan[:bootstrap])
      cfg = { k: plan[:k], classes: plan[:classes], nf: nf, limit: plan[:limit], min_split: 2, min_leaf: plan[:min_leaf], crit: plan[:crit], max_features: mf, rng: feat_state }
      trees.push(DecisionTree.build(sample[:rows], sample[:ys], sample[:wts], cfg, 0))
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

  # One row's regression prediction: the plain MEAN of the trees' leaf
  # means.
  -> .mean_row(trees, row)
    acc = 0.to_f
    nt = trees.size
    t = 0
    while t < nt
      leaf = DecisionTree.descend(trees[t], row)
      acc += leaf[:prediction].to_f
      t += 1
    acc / nt.to_f

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
    ok = rows[0].size > 0 if ok
    if ok
      width = rows[0].size
      rows.each -> (r)
        ok = false if r.size != width
    ok

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

  -> new(n_estimators = nil, max_features = nil, max_depth = nil, min_samples_leaf = nil, seed = nil, criterion = nil, bootstrap = nil)
    ne = n_estimators
    ne = 10 if ne == nil
    ml = min_samples_leaf
    ml = 1 if ml == nil
    ml = 1 if ml < 1
    cr = criterion
    cr = :gini if cr == nil
    bs = bootstrap
    bs = true if bs == nil
    @n_estimators = ne
    @max_features = max_features
    @max_depth = max_depth
    @min_samples_leaf = ml
    @seed = seed
    @criterion = cr
    @bootstrap = bs
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

  # The seven knobs a search varies — never the grown trees.
  -> params
    { n_estimators: @n_estimators, max_features: @max_features, max_depth: @max_depth, min_samples_leaf: @min_samples_leaf, seed: @seed, criterion: @criterion, bootstrap: @bootstrap }

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
    RandomForestClassifier.new(ne, mf, md, ml, sd, cr, bs)

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
    wts = nil
    wts = Estimator.weight_values(sample_weight, rows.size) if ok && sample_weight != nil
    ok = false if sample_weight != nil && wts == nil
    if ok && wts != nil
      trimmed = Estimator.drop_zero_weights(rows, labels, wts)
      rows = trimmed[:rows]
      labels = trimmed[:targets]
      wts = trimmed[:weights]
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
      plan = { k: classes.size, classes: classes, nf: nf, limit: limit, min_leaf: @min_samples_leaf, crit: @criterion.to_s, m: mf, n_estimators: @n_estimators, bootstrap: @bootstrap, seed: @seed }
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
      nf = @n_features
      ok = true
      rows.each -> (r)
        ok = false if r.size != nf
      out = rows if ok
    out

  # The ensemble's mean class distribution per row. With no label: one
  # array per row, one entry per class in `classes` order, summing to 1.
  # With a label: the flat P(label) column, ready for Metrics.roc_auc /
  # Metrics.log_loss. nil before fit, on a width mismatch, or for a label
  # the fit never saw.
  -> predict_proba(x, pos_label = nil)
    rows = self.query_rows(x)
    out = nil
    if rows != nil
      trees = @trees
      k = @classes.size
      probs = []
      rows.each -> (r)
        probs.push(RandomForest.vote_row(trees, r, k))
      if pos_label == nil
        out = probs
      else
        idx = DecisionTree.label_index(@classes, pos_label)
        if idx >= 0
          col = []
          probs.each -> (p)
            col.push(p[idx])
          out = col
    out

  # Predicted labels for x: the class with the largest mean probability,
  # ties to the first-seen label.
  -> predict(x)
    probs = self.predict_proba(x)
    out = nil
    if probs != nil
      classes = @classes
      preds = []
      probs.each -> (p)
        preds.push(classes[RandomForest.argmax(p)])
      out = preds
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
    { n_estimators: @n_estimators, max_features: @max_features, max_depth: @max_depth, min_samples_leaf: @min_samples_leaf, seed: @seed, criterion: @criterion, bootstrap: @bootstrap, classes: @classes, trees: @trees, n_features: @n_features, oob_score: @oob_score }

  -> .load_state(st)
    out = nil
    ok = st != nil
    ok = st[:n_estimators] != nil && st[:min_samples_leaf] != nil && st[:criterion] != nil if ok
    ok = st[:classes] != nil && st[:trees] != nil && st[:n_features] != nil if ok
    if ok
      model = RandomForestClassifier.new(st[:n_estimators], st[:max_features], st[:max_depth], st[:min_samples_leaf], st[:seed], st[:criterion], st[:bootstrap])
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

  -> new(n_estimators = nil, max_features = nil, max_depth = nil, min_samples_leaf = nil, seed = nil, criterion = nil, bootstrap = nil)
    ne = n_estimators
    ne = 10 if ne == nil
    ml = min_samples_leaf
    ml = 1 if ml == nil
    ml = 1 if ml < 1
    cr = criterion
    cr = :mse if cr == nil
    bs = bootstrap
    bs = true if bs == nil
    @n_estimators = ne
    @max_features = max_features
    @max_depth = max_depth
    @min_samples_leaf = ml
    @seed = seed
    @criterion = cr
    @bootstrap = bs
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

  # --- Estimable contract (see lib/estimator_base.w) ---

  -> estimator_name
    "RandomForestRegressor"

  -> supervised?
    true

  -> supports_sample_weight?
    true

  -> params
    { n_estimators: @n_estimators, max_features: @max_features, max_depth: @max_depth, min_samples_leaf: @min_samples_leaf, seed: @seed, criterion: @criterion, bootstrap: @bootstrap }

  -> with_params(overrides)
    ne = Estimator.opt(overrides, :n_estimators, @n_estimators)
    mf = Estimator.opt(overrides, :max_features, @max_features)
    md = Estimator.opt(overrides, :max_depth, @max_depth)
    ml = Estimator.opt(overrides, :min_samples_leaf, @min_samples_leaf)
    sd = Estimator.opt(overrides, :seed, @seed)
    cr = Estimator.opt(overrides, :criterion, @criterion)
    bs = Estimator.opt(overrides, :bootstrap, @bootstrap)
    RandomForestRegressor.new(ne, mf, md, ml, sd, cr, bs)

  # --- Fit ---

  # Grow the forest from x/y. The nil list is the classifier's, minus the
  # classes it has none of.
  -> fit(x, y, sample_weight = nil)
    rows = Estimator.feature_rows(x)
    targets = Estimator.target_values(y)
    ok = RandomForest.shapes_ok?(rows, targets)
    ok = false if !DecisionTree.criterion_ok?(@criterion, true)
    ok = false if @n_estimators < 1
    wts = nil
    wts = Estimator.weight_values(sample_weight, rows.size) if ok && sample_weight != nil
    ok = false if sample_weight != nil && wts == nil
    if ok && wts != nil
      trimmed = Estimator.drop_zero_weights(rows, targets, wts)
      rows = trimmed[:rows]
      targets = trimmed[:targets]
      wts = trimmed[:weights]
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
      plan = { k: 0, classes: nil, nf: nf, limit: limit, min_leaf: @min_samples_leaf, crit: "mse", m: mf, n_estimators: @n_estimators, bootstrap: @bootstrap, seed: @seed }
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
      nf = @n_features
      ok = true
      rows.each -> (r)
        ok = false if r.size != nf
      out = rows if ok
    out

  # Predicted values for x — the mean of the trees' leaf means.
  -> predict(x)
    rows = self.query_rows(x)
    out = nil
    if rows != nil
      trees = @trees
      preds = []
      rows.each -> (r)
        preds.push(RandomForest.mean_row(trees, r))
      out = preds
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
    { n_estimators: @n_estimators, max_features: @max_features, max_depth: @max_depth, min_samples_leaf: @min_samples_leaf, seed: @seed, criterion: @criterion, bootstrap: @bootstrap, trees: @trees, n_features: @n_features, oob_score: @oob_score }

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
      model = RandomForestRegressor.new(st[:n_estimators], st[:max_features], st[:max_depth], st[:min_samples_leaf], st[:seed], st[:criterion], st[:bootstrap])
      out = model.restore_state(st)
    out

  -> restore_state(st)
    @trees = st[:trees]
    @n_features = st[:n_features]
    @oob_score = st[:oob_score]
    @fitted = true
    self
