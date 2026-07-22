# DecisionTree / DecisionTreeClassifier / DecisionTreeRegressor — CART
# (pure Tungsten, CPU-only; koala's first AXIS-ALIGNED RECURSIVE-PARTITION
# learner, and the reusable machinery a random forest / gradient boosting
# would stand on)
#
#     model = DecisionTreeClassifier.new          # gini, unlimited depth
#     model.fit(x, y)                             # self when fitted, nil when unfittable
#     model.tree                                  # the root node (a hash; see below)
#     model.classes                               # distinct labels, first-seen order
#     model.depth / .node_count / .leaf_count     # realized tree shape
#     model.predict(x)                            # array of predicted labels
#     model.predict_proba(x)                      # per-row leaf class distribution
#     model.predict_proba(x, label)               # flat P(label) column, for ROC / log_loss
#     model.score(x, y)                           # accuracy
#     model.tree_lines                            # the tree as printable lines
#
#     DecisionTreeClassifier.new(max_depth, min_samples_split, min_samples_leaf, criterion)
#     DecisionTreeRegressor.new(max_depth, min_samples_split, min_samples_leaf, criterion)
#
# Where LinearRegression fits ONE global hyperplane, KNNClassifier defers
# everything to query time, LogisticRegression iterates to a single
# boundary and GaussianNB assumes a generative Gaussian per class, a
# decision tree is the NON-PARAMETRIC, PIECEWISE-CONSTANT learner: it
# recursively cuts the feature space with axis-aligned half-planes
# (`x[j] <= t`) and predicts a constant inside each resulting box. It needs
# no scaling, no distance metric and no learning rate, it is multiclass
# from the start, and — unlike every other estimator here — the fitted
# model is READABLE (`tree_lines`).
#
# --- The algorithm (CART, greedy, top-down) ---
#
# At each node, over every feature j and every candidate threshold t, the
# rows split into `x[j] <= t` (left) and `x[j] > t` (right), and the split
# is scored by the IMPURITY DECREASE
#
#     gain = imp(node) - (n_left/n) * imp(left) - (n_right/n) * imp(right)
#
# The best-gaining split is taken and both sides recurse. Impurity is one
# of (`criterion`):
#
#     :gini      1 - sum_c p_c^2          (classification, the default)
#     :entropy   -sum_c p_c * log2(p_c)   (classification; 0*log0 := 0)
#     :mse       population variance      (regression — DecisionTreeRegressor)
#
# CANDIDATE THRESHOLDS are the MIDPOINTS between adjacent DISTINCT sorted
# values of the feature inside that node — scikit-learn's rule. Midpoints
# (not the values themselves) put the boundary in the gap, so a query
# landing between two training values is classified by the nearer side, and
# taking only distinct values means a constant feature offers no threshold
# at all rather than a degenerate empty split.
#
# A node becomes a LEAF when any of these holds:
#   * it is PURE (impurity 0) — nothing left to gain;
#   * `n < min_samples_split` — too small to be worth splitting;
#   * `depth == max_depth` — the cap is reached (nil = no cap; 0 makes the
#     root itself a leaf, 1 a decision STUMP);
#   * NO admissible split exists — every feature is constant inside the
#     node, or every candidate would leave fewer than `min_samples_leaf`
#     rows on a side.
# Its prediction is the MAJORITY class (classifier — ties break to the
# first-seen label) or the MEAN target (regressor).
#
# --- Determinism (a hard guarantee, both engines) ---
#
# Nothing here is random: there is no bootstrap, no feature subsampling and
# no seed, so the fitted tree is a PURE FUNCTION of the training data, and
# fitting the same data twice — on either engine — yields the identical
# tree. The one place a choice could wobble is a TIE in gain, so the rule
# is stated and enforced:
#
#     features are scanned in ASCENDING INDEX order, and each feature's
#     thresholds in ASCENDING VALUE order; a candidate replaces the
#     incumbent only when it is STRICTLY better. Therefore ties break to
#     the LOWEST FEATURE INDEX, and within a feature to the LOWEST
#     THRESHOLD.
#
# "Strictly better" is measured against a RELATIVE tolerance —
# `gain > best + imp(node)/1e12` — so two mathematically equal gains
# reached by different summation orders cannot swap the winner on a last-bit
# difference. The tolerance is scaled by the node's own impurity, so it
# means the same thing for a gini in [0, 1] and for a regression MSE of any
# magnitude.
#
# A ZERO-GAIN split is still taken when it is the best on offer (scikit-learn's
# `min_impurity_decrease = 0.0` behaviour). That is what lets a tree learn
# XOR: no single axis-aligned cut of `[[0,0],[0,1],[1,0],[1,1]]` improves
# gini at all, but splitting anyway lets the two children separate it
# perfectly at depth 2. Only the absence of ANY admissible split makes a
# leaf.
#
# --- Node representation ---
#
# A node is a plain HASH, and an internal node holds its children directly
# (`node[:left]` / `node[:right]` are nodes) — an explicit, inspectable
# structure rather than closures, so a spec can assert the fitted SHAPE:
#
#     leaf:       true for a leaf
#     feature:    split feature index      (nil at a leaf)
#     threshold:  split threshold, an f64  (nil at a leaf)
#     gain:       the impurity decrease it bought (nil at a leaf)
#     left:       the `x[feature] <= threshold` child (nil at a leaf)
#     right:      the `x[feature] >  threshold` child (nil at a leaf)
#     n:          training rows that reached this node
#     depth:      0 at the root
#     impurity:   this node's impurity under `criterion`
#     counts:     rows per class, in `classes` order (nil for a regressor)
#     prediction: what this node alone would predict — set on EVERY node,
#                 so any subtree read as a leaf still answers
#
#     model.tree[:feature]            # => 0
#     model.tree[:threshold]          # => 1.5
#     model.tree[:left][:prediction]  # => the label
#
# --- Hyperparameters (all four are real, tunable `params`) ---
#
#     max_depth          nil = unlimited; 0 = a single leaf, 1 = a stump
#     min_samples_split  a node smaller than this is never split (clamped to >= 2)
#     min_samples_leaf   a split leaving a side smaller than this is inadmissible
#                        (clamped to >= 1)
#     criterion          :gini / :entropy (classifier), :mse (regressor)
#
# They round-trip through `params` / `with_params`, so GridSearch tunes
# them — `GridSearch.new(DecisionTreeClassifier.new, { max_depth: [1, 2, 3] }, 4)`
# — and a Pipeline exposes them as "tree.max_depth". Clamping happens in
# the CONSTRUCTOR, so `params` always reports the value actually in force
# and `m.with_params(m.params)` is the identity. An explicit nil override
# restores the default (2 / 1 / :gini), except for `max_depth`, where nil
# IS the meaningful value "unlimited". A criterion the estimator does not
# know makes `fit` return nil rather than silently falling back.
#
# Accepted shapes are the estimators' shared ones, coerced through the
# neutral Estimator.feature_rows / .target_values: x is a DataFrame
# (numeric columns only), a Matrix, an array of row arrays, or a flat
# single-feature array; y is a Series, a Vector, or a plain array. nil
# cells are NOT handled — run an Imputer first. An empty x, a ragged x, a
# y whose size mismatches, or an unknown criterion makes fit return nil and
# fitted? stay false; predict / predict_proba / score return nil before a
# successful fit and when a query row's width differs from the fitted
# feature count, and predict_proba returns nil for a label the fit never saw.
#
# NOTE: locals are hoisted from ivars before any `-> (x)` block — the
# interpreter cannot resolve @ivars from a block body — and methods
# containing closures avoid early `return`. Arrays are built with push
# (Array `+` and `insert` are unavailable). No float literal appears here:
# every float derives from the data via .to_f. Array#sort is not used
# (its cross-engine order is not guaranteed) — DecisionTree.sorted_copy is
# an explicit insertion sort.

# The shared tree machinery, as statics so it is callable from inside a
# block and reusable by BOTH estimators below (and by a future forest).
# Everything is driven by a `cfg` hash so no method needs eight arguments:
#
#     cfg[:k]         class count; 0 marks a REGRESSION tree
#     cfg[:classes]   the labels, first-seen order (nil for regression)
#     cfg[:nf]        feature count
#     cfg[:limit]     max depth, or -1 for unlimited
#     cfg[:min_split] min_samples_split
#     cfg[:min_leaf]  min_samples_leaf
#     cfg[:crit]      criterion as a STRING ("gini" / "entropy" / "mse")
+ DecisionTree
  # --- Criteria ---

  # Gini impurity, 1 - sum_c p_c^2. Exactly 0 for a pure node.
  -> .gini(counts, n)
    total = n.to_f
    acc = 1.to_f
    counts.each -> (c)
      p = c.to_f / total
      acc -= p * p
    acc

  # Shannon entropy in BITS, -sum_c p_c log2(p_c), with 0*log0 taken as 0
  # (the empty-class term is skipped, not evaluated). Exactly 0 for a pure
  # node; 1 for a balanced two-class node.
  -> .entropy(counts, n)
    total = n.to_f
    ln2 = Math.log(2.to_f)
    acc = 0.to_f
    counts.each -> (c)
      if c > 0
        p = c.to_f / total
        acc -= p * (Math.log(p) / ln2)
    acc

  # Population (n denominator) variance of the targets — the regression
  # criterion, equal to the mean squared error of predicting their mean.
  -> .variance(ys)
    n = ys.size
    out = 0.to_f
    if n > 0
      nd = n.to_f
      total = 0.to_f
      ys.each -> (v)
        total += v.to_f
      m = total / nd
      acc = 0.to_f
      ys.each -> (v)
        d = v.to_f - m
        acc += d * d
      out = acc / nd
    out

  # One node's impurity under cfg's criterion. `counts` is nil for a
  # regression tree, where the raw targets are what matters.
  -> .impurity(ys, counts, n, crit)
    out = 0.to_f
    if crit == "mse"
      out = DecisionTree.variance(ys)
    else
      if crit == "entropy"
        out = DecisionTree.entropy(counts, n)
      else
        out = DecisionTree.gini(counts, n)
    out

  # Is `crit` one this tree kind understands? An unknown one is a fit
  # error, never a silent fallback.
  -> .criterion_ok?(crit, regression)
    c = crit.to_s
    out = false
    if regression
      out = c == "mse" || c == "variance"
    else
      out = c == "gini" || c == "entropy"
    out

  # --- Small array helpers (no Array#sort: its order is not portable) ---

  # Rows per class index, over k classes. Counted class-by-class rather
  # than by indexed write, which keeps it to plain push.
  -> .counts_of(ys, k)
    out = []
    k.times -> (i)
      cnt = 0
      ys.each -> (c)
        cnt += 1 if c == i
      out.push(cnt)
    out

  # counts_of, or nil for a regression tree (k = 0).
  -> .node_counts(ys, k)
    out = nil
    out = DecisionTree.counts_of(ys, k) if k > 0
    out

  # vals as f64, ascending — an explicit insertion sort, so the order is
  # the same on both engines and for equal keys.
  -> .sorted_copy(vals)
    out = []
    vals.each -> (v)
      out.push(v.to_f)
    n = out.size
    i = 1
    while i < n
      cur = out[i]
      j = i - 1
      while j >= 0 && out[j] > cur
        out[j + 1] = out[j]
        j -= 1
      out[j + 1] = cur
      i += 1
    out

  # The DISTINCT values of vals, ascending — the sorted run with adjacent
  # duplicates dropped. A constant feature yields ONE value, hence no
  # candidate threshold at all.
  -> .sorted_unique(vals)
    sorted = DecisionTree.sorted_copy(vals)
    out = []
    sorted.each -> (v)
      out.push(v) if out.size == 0 || out[out.size - 1] != v
    out

  # Index of label in classes, or -1 when it is not there.
  -> .label_index(classes, label)
    idx = -1
    i = 0
    classes.each -> (c)
      idx = i if idx < 0 && c == label
      i += 1
    idx

  # Split rows/ys on `x[j] <= thr`, keeping each side's rows and targets
  # aligned: { lr:, ly:, rr:, ry: }.
  -> .partition(rows, ys, j, thr)
    lr = []
    ly = []
    rr = []
    ry = []
    i = 0
    rows.each -> (r)
      if r[j].to_f <= thr
        lr.push(r)
        ly.push(ys[i])
      else
        rr.push(r)
        ry.push(ys[i])
      i += 1
    { lr: lr, ly: ly, rr: rr, ry: ry }

  # --- The greedy split search ---

  # The best admissible split of rows/ys, or nil when there is none. See
  # the header for the tie-break rule this encodes: features ascending,
  # thresholds ascending, replacement only on a STRICTLY better gain
  # (measured against a relative tolerance), so ties keep the lowest
  # feature index and then the lowest threshold.
  -> .best_split(rows, ys, cfg, parent_imp)
    nf = cfg[:nf]
    k = cfg[:k]
    min_leaf = cfg[:min_leaf]
    crit = cfg[:crit]
    nd = rows.size.to_f
    tol = parent_imp / 1000000000000.to_f
    best = nil
    bgain = 0.to_f
    nf.times -> (j)
      col = []
      rows.each -> (r)
        col.push(r[j].to_f)
      uniq = DecisionTree.sorted_unique(col)
      span = uniq.size - 1
      span = 0 if span < 0
      span.times -> (c)
        thr = (uniq[c] + uniq[c + 1]) / 2.to_f
        part = DecisionTree.partition(rows, ys, j, thr)
        ln = part[:lr].size
        rn = part[:rr].size
        if ln >= min_leaf && rn >= min_leaf
          li = DecisionTree.impurity(part[:ly], DecisionTree.node_counts(part[:ly], k), ln, crit)
          ri = DecisionTree.impurity(part[:ry], DecisionTree.node_counts(part[:ry], k), rn, crit)
          gain = parent_imp - (ln.to_f / nd) * li - (rn.to_f / nd) * ri
          if best == nil || gain > bgain + tol
            bgain = gain
            best = { feature: j, threshold: thr, gain: gain, lr: part[:lr], ly: part[:ly], rr: part[:rr], ry: part[:ry] }
    best

  # --- Node construction ---

  # What a node alone would predict: the majority class (ties to the
  # first-seen label, since a later class must STRICTLY out-count it) for a
  # classification tree, the mean target for a regression one.
  -> .node_value(ys, counts, n, cfg)
    out = nil
    if cfg[:k] > 0
      classes = cfg[:classes]
      best = 0
      k = counts.size
      k.times -> (c)
        best = c if counts[c] > counts[best]
      out = classes[best]
    else
      total = 0.to_f
      ys.each -> (v)
        total += v.to_f
      out = total / n.to_f
    out

  -> .leaf_node(ys, counts, n, depth, imp, cfg)
    value = DecisionTree.node_value(ys, counts, n, cfg)
    { leaf: true, feature: nil, threshold: nil, gain: nil, left: nil, right: nil, n: n, depth: depth, impurity: imp, counts: counts, prediction: value }

  # Grow the subtree for rows/ys at `depth`, returning its root node. The
  # four stopping rules of the header live here, in order: too small, pure,
  # depth cap, then "no admissible split" (best_split answering nil).
  -> .build(rows, ys, cfg, depth)
    k = cfg[:k]
    limit = cfg[:limit]
    min_split = cfg[:min_split]
    crit = cfg[:crit]
    n = rows.size
    counts = DecisionTree.node_counts(ys, k)
    imp = DecisionTree.impurity(ys, counts, n, crit)
    grow = n >= min_split
    grow = false if imp <= 0.to_f
    grow = false if limit >= 0 && depth >= limit
    best = nil
    best = DecisionTree.best_split(rows, ys, cfg, imp) if grow
    out = nil
    if best == nil
      out = DecisionTree.leaf_node(ys, counts, n, depth, imp, cfg)
    else
      value = DecisionTree.node_value(ys, counts, n, cfg)
      l = DecisionTree.build(best[:lr], best[:ly], cfg, depth + 1)
      r = DecisionTree.build(best[:rr], best[:ry], cfg, depth + 1)
      out = { leaf: false, feature: best[:feature], threshold: best[:threshold], gain: best[:gain], left: l, right: r, n: n, depth: depth, impurity: imp, counts: counts, prediction: value }
    out

  # --- Reading a fitted tree ---

  # The leaf `row` falls into: left on `x[feature] <= threshold`, right
  # otherwise, until a leaf.
  -> .descend(node, row)
    cur = node
    while !cur[:leaf]
      if row[cur[:feature]].to_f <= cur[:threshold]
        cur = cur[:left]
      else
        cur = cur[:right]
    cur

  -> .node_count(node)
    out = 1
    out = 1 + DecisionTree.node_count(node[:left]) + DecisionTree.node_count(node[:right]) if !node[:leaf]
    out

  -> .leaf_count(node)
    out = 1
    out = DecisionTree.leaf_count(node[:left]) + DecisionTree.leaf_count(node[:right]) if !node[:leaf]
    out

  # Edges from the root to the deepest leaf — 0 for a root that is itself
  # a leaf, 1 for a stump.
  -> .tree_depth(node)
    out = 0
    if !node[:leaf]
      l = DecisionTree.tree_depth(node[:left])
      r = DecisionTree.tree_depth(node[:right])
      d = l
      d = r if r > l
      out = 1 + d
    out

  # A node's class distribution, counts / n in `classes` order; nil for a
  # regression node.
  -> .proba_of(node)
    counts = node[:counts]
    out = nil
    if counts != nil
      nd = node[:n].to_f
      col = []
      counts.each -> (c)
        col.push(c.to_f / nd)
      out = col
    out

  # The subtree as printable lines, appended to `lines`: an internal node
  # prints its test, a leaf its prediction and row count, children indented
  # two spaces under their parent, left (the `<=` side) first.
  -> .render(node, prefix, lines)
    if node[:leaf]
      lines.push(prefix + "leaf: " + node[:prediction].to_s + " (n=" + node[:n].to_s + ")")
    else
      lines.push(prefix + "x" + node[:feature].to_s + " <= " + node[:threshold].to_s)
      DecisionTree.render(node[:left], prefix + "  ", lines)
      DecisionTree.render(node[:right], prefix + "  ", lines)
    lines

# A CART classification tree: greedy axis-aligned splits by gini (or
# entropy), a majority-class prediction at every leaf, multiclass with no
# wrapper. See the file header for the algorithm, the determinism guarantee
# and the hyperparameters.
+ DecisionTreeClassifier
  is Estimable
  is SupervisedEstimator

  ro :classes            # distinct labels, first-seen order; nil before fit
  ro :tree               # the root node; nil before fit
  ro :n_features         # features the fit saw; nil before fit
  ro :max_depth          # nil = unlimited
  ro :min_samples_split  # >= 2
  ro :min_samples_leaf   # >= 1
  ro :criterion          # :gini (default) or :entropy

  -> new(max_depth = nil, min_samples_split = nil, min_samples_leaf = nil, criterion = nil)
    ms = min_samples_split
    ms = 2 if ms == nil
    ms = 2 if ms < 2
    ml = min_samples_leaf
    ml = 1 if ml == nil
    ml = 1 if ml < 1
    cr = criterion
    cr = :gini if cr == nil
    @max_depth = max_depth
    @min_samples_split = ms
    @min_samples_leaf = ml
    @criterion = cr
    @fitted = false
    @classes = nil
    @tree = nil
    @n_features = nil

  -> fitted?
    @fitted

  # --- Estimable contract (see lib/estimator_base.w) ---

  -> estimator_name
    "DecisionTreeClassifier"

  # Learns from features AND labels: fit(x, y) / score(x, y).
  -> supervised?
    true

  # The four knobs a search varies — never the learned tree.
  -> params
    { max_depth: @max_depth, min_samples_split: @min_samples_split, min_samples_leaf: @min_samples_leaf, criterion: @criterion }

  # A NEW, UNFITTED DecisionTreeClassifier with `overrides` applied; self is
  # left untouched. Unmentioned keys carry over, so with_params(params)
  # round-trips.
  -> with_params(overrides)
    md = Estimator.opt(overrides, :max_depth, @max_depth)
    ms = Estimator.opt(overrides, :min_samples_split, @min_samples_split)
    ml = Estimator.opt(overrides, :min_samples_leaf, @min_samples_leaf)
    cr = Estimator.opt(overrides, :criterion, @criterion)
    DecisionTreeClassifier.new(md, ms, ml, cr)

  # --- Fit ---

  # Grow the tree from x/y. Returns self, or nil — fitted? stays false —
  # when the shapes are unusable (empty x, ragged rows, y size mismatch) or
  # the criterion is not one this tree knows.
  -> fit(x, y)
    rows = Estimator.feature_rows(x)
    labels = Estimator.target_values(y)
    ok = rows != nil && labels != nil
    ok = rows.size > 0 && rows.size == labels.size if ok
    ok = rows[0].size > 0 if ok
    if ok
      width = rows[0].size
      rows.each -> (r)
        ok = false if r.size != width
    ok = false if !DecisionTree.criterion_ok?(@criterion, false)
    out = nil
    if ok
      nf = rows[0].size
      classes = []
      labels.each -> (l)
        classes.push(l) if !classes.include?(l)
      ys = []
      labels.each -> (l)
        ys.push(DecisionTree.label_index(classes, l))
      limit = @max_depth
      limit = -1 if limit == nil
      limit = 0 if limit < 0 && @max_depth != nil
      cfg = { k: classes.size, classes: classes, nf: nf, limit: limit, min_split: @min_samples_split, min_leaf: @min_samples_leaf, crit: @criterion.to_s }
      @classes = classes
      @n_features = nf
      @tree = DecisionTree.build(rows, ys, cfg, 0)
      @fitted = true
      out = self
    out

  # --- The fitted tree's shape ---

  # Edges from the root to the deepest leaf: 0 when the root is a leaf, 1
  # for a stump. nil before fit.
  -> depth
    out = nil
    out = DecisionTree.tree_depth(@tree) if @fitted
    out

  -> node_count
    out = nil
    out = DecisionTree.node_count(@tree) if @fitted
    out

  -> leaf_count
    out = nil
    out = DecisionTree.leaf_count(@tree) if @fitted
    out

  # The tree as an array of printable lines (see DecisionTree.render); nil
  # before fit.
  -> tree_lines
    out = nil
    out = DecisionTree.render(@tree, "", []) if @fitted
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

  # The leaf each row of x lands in; nil before fit or on a width mismatch.
  -> apply(x)
    rows = self.query_rows(x)
    out = nil
    if rows != nil
      tree = @tree
      leaves = []
      rows.each -> (r)
        leaves.push(DecisionTree.descend(tree, r))
      out = leaves
    out

  # Predicted labels for x — each row's leaf's majority class.
  -> predict(x)
    leaves = self.apply(x)
    out = nil
    if leaves != nil
      preds = []
      leaves.each -> (node)
        preds.push(node[:prediction])
      out = preds
    out

  # The leaf's class distribution. With no label: one array per row, one
  # entry per class in `classes` order, summing to 1. With a label: the flat
  # P(label) column, ready for Metrics.roc_auc / Metrics.log_loss. nil
  # before fit, on a width mismatch, or for a label the fit never saw.
  -> predict_proba(x, pos_label = nil)
    leaves = self.apply(x)
    out = nil
    if leaves != nil
      probs = []
      leaves.each -> (node)
        probs.push(DecisionTree.proba_of(node))
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

  # Accuracy (Metrics.accuracy) of self's predictions on x against y; nil
  # before fit or when the shapes do not line up.
  -> score(x, y)
    preds = self.predict(x)
    yvals = Estimator.target_values(y)
    out = nil
    if preds != nil && yvals != nil
      out = Metrics.accuracy(preds, yvals) if preds.size == yvals.size && preds.size > 0
    out

# A CART regression tree on the SAME machinery: identical greedy split
# search, with variance (MSE) as the criterion and the MEAN target as every
# leaf's prediction. `score` is R² (Metrics.r2), matching LinearRegression's
# sign convention, so CrossValidation and GridSearch rank it the same way.
# Predictions are piecewise constant — a fully grown tree interpolates
# nothing, it memorizes the training means of its boxes — which is exactly
# why `max_depth` matters here and is worth searching.
+ DecisionTreeRegressor
  is Estimable
  is SupervisedEstimator

  ro :tree               # the root node; nil before fit
  ro :n_features         # features the fit saw; nil before fit
  ro :max_depth          # nil = unlimited
  ro :min_samples_split  # >= 2
  ro :min_samples_leaf   # >= 1
  ro :criterion          # :mse (default; :variance is accepted as an alias)

  -> new(max_depth = nil, min_samples_split = nil, min_samples_leaf = nil, criterion = nil)
    ms = min_samples_split
    ms = 2 if ms == nil
    ms = 2 if ms < 2
    ml = min_samples_leaf
    ml = 1 if ml == nil
    ml = 1 if ml < 1
    cr = criterion
    cr = :mse if cr == nil
    @max_depth = max_depth
    @min_samples_split = ms
    @min_samples_leaf = ml
    @criterion = cr
    @fitted = false
    @tree = nil
    @n_features = nil

  -> fitted?
    @fitted

  # --- Estimable contract (see lib/estimator_base.w) ---

  -> estimator_name
    "DecisionTreeRegressor"

  -> supervised?
    true

  -> params
    { max_depth: @max_depth, min_samples_split: @min_samples_split, min_samples_leaf: @min_samples_leaf, criterion: @criterion }

  -> with_params(overrides)
    md = Estimator.opt(overrides, :max_depth, @max_depth)
    ms = Estimator.opt(overrides, :min_samples_split, @min_samples_split)
    ml = Estimator.opt(overrides, :min_samples_leaf, @min_samples_leaf)
    cr = Estimator.opt(overrides, :criterion, @criterion)
    DecisionTreeRegressor.new(md, ms, ml, cr)

  # --- Fit ---

  -> fit(x, y)
    rows = Estimator.feature_rows(x)
    targets = Estimator.target_values(y)
    ok = rows != nil && targets != nil
    ok = rows.size > 0 && rows.size == targets.size if ok
    ok = rows[0].size > 0 if ok
    if ok
      width = rows[0].size
      rows.each -> (r)
        ok = false if r.size != width
    ok = false if !DecisionTree.criterion_ok?(@criterion, true)
    out = nil
    if ok
      nf = rows[0].size
      ys = []
      targets.each -> (v)
        ys.push(v.to_f)
      limit = @max_depth
      limit = -1 if limit == nil
      limit = 0 if limit < 0 && @max_depth != nil
      cfg = { k: 0, classes: nil, nf: nf, limit: limit, min_split: @min_samples_split, min_leaf: @min_samples_leaf, crit: "mse" }
      @n_features = nf
      @tree = DecisionTree.build(rows, ys, cfg, 0)
      @fitted = true
      out = self
    out

  # --- The fitted tree's shape ---

  -> depth
    out = nil
    out = DecisionTree.tree_depth(@tree) if @fitted
    out

  -> node_count
    out = nil
    out = DecisionTree.node_count(@tree) if @fitted
    out

  -> leaf_count
    out = nil
    out = DecisionTree.leaf_count(@tree) if @fitted
    out

  -> tree_lines
    out = nil
    out = DecisionTree.render(@tree, "", []) if @fitted
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

  -> apply(x)
    rows = self.query_rows(x)
    out = nil
    if rows != nil
      tree = @tree
      leaves = []
      rows.each -> (r)
        leaves.push(DecisionTree.descend(tree, r))
      out = leaves
    out

  # Predicted values for x — each row's leaf's mean training target.
  -> predict(x)
    leaves = self.apply(x)
    out = nil
    if leaves != nil
      preds = []
      leaves.each -> (node)
        preds.push(node[:prediction])
      out = preds
    out

  # R² (Metrics.r2) of self's predictions on x against y; nil before fit or
  # when the shapes do not line up.
  -> score(x, y)
    preds = self.predict(x)
    yvals = Estimator.target_values(y)
    out = nil
    if preds != nil && yvals != nil
      out = Metrics.r2(preds, yvals) if preds.size == yvals.size && preds.size > 0
    out
