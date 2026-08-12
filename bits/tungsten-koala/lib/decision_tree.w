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
#     DecisionTreeClassifier.new(max_depth, min_samples_split, min_samples_leaf,
#                                criterion, ccp_alpha, min_impurity_decrease,
#                                min_weight_fraction_leaf)
#     DecisionTreeRegressor.new(max_depth, min_samples_split, min_samples_leaf,
#                               criterion, ccp_alpha, min_impurity_decrease,
#                               min_weight_fraction_leaf)
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
#     missing_left: whether nil / NaN follows the left child (nil at a leaf)
#     gain:       the impurity decrease it bought (nil at a leaf)
#     left:       the `x[feature] <= threshold` child (nil at a leaf)
#     right:      the `x[feature] >  threshold` child (nil at a leaf)
#     n:          training rows that reached this node
#     weight:     their total sample WEIGHT — equal to `n` (and an
#                 integer) for an unweighted fit; what predict_proba
#                 divides `counts` by
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
# --- Hyperparameters (all seven are real, tunable `params`) ---
#
#     max_depth          nil = unlimited; 0 = a single leaf, 1 = a stump
#     min_samples_split  a node smaller than this is never split (clamped to >= 2)
#     min_samples_leaf   a split leaving a side smaller than this is inadmissible
#                        (clamped to >= 1)
#     criterion          :gini / :entropy (classifier), :mse (regressor)
#     ccp_alpha           weakest-link post-pruning strength (>= 0)
#     min_impurity_decrease
#                        minimum root-weighted impurity decrease required to
#                        grow a split (>= 0)
#     min_weight_fraction_leaf
#                        minimum fraction of fitted sample weight required in
#                        each child (0..0.5)
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
# single-feature array; y is a Series, a Vector, or a plain array. nil and
# IEEE NaN feature cells are missing values: every candidate split scores
# sending all missing rows left and right, and stores the better direction.
# If a fit saw no missing values, an unseen missing query follows the larger
# child (ties right), matching scikit-learn. Infinities and other nonnumeric
# feature cells remain invalid. An empty x, a ragged x, a y whose size
# mismatches, or an unknown criterion makes fit return nil and fitted? stay
# false; predict / predict_proba / score return nil before a successful fit
# and when a query row's width differs from the fitted feature count, and
# predict_proba returns nil for a label the fit never saw.
#
# NOTE: every float here derives from the data via .to_f — a bare decimal
# literal is a Decimal and does not coerce with Float. Scalar helper sorts use
# an explicit insertion sort; feature-index orders use decorated lexicographic
# Array#sort keys that include the row index, making ties deterministic on both
# engines while reaching the native runtime's blockless sort path.

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
#     cfg[:min_gain]  minimum root-weighted impurity decrease
#     cfg[:root_weight] total fitted weight, for min_gain normalization
#     cfg[:min_leaf_weight] absolute child-weight floor derived from the
#                           fitted root weight
#
# Two OPTIONAL keys turn the same machinery into a forest's tree; both
# absent (the default) is the plain tree above, unchanged in every detail:
#
#     cfg[:max_features]  features to consider PER SPLIT; nil = all
#     cfg[:rng]           MINSTD state driving that per-split draw, advanced
#                         IN PLACE as the build consumes it
#
# See DecisionTree.split_features for why the redraw is per SPLIT rather
# than per tree, and lib/random_forest.w for the ensemble that sets them.
+ DecisionTree
  # nil is Koala's ordinary missing cell; an IEEE NaN is the numeric-data
  # spelling of the same fact. Infinities remain invalid training/query data.
  -> .missing?(value)
    out = value == nil
    out = true if !out && type(value) == "Float" && value != value
    out

  -> .usable_feature?(value)
    out = DecisionTree.missing?(value)
    if !out
      kind = type(value)
      out = kind == "Int" || kind == "Float"
      out = value.to_f - value.to_f == 0.to_f if out
    out

  # Validate rectangular numeric rows and summarize whether prediction must
  # consider missing routing: -1 is invalid, 0 is valid with no nil/NaN, and
  # 1 is valid with at least one missing cell. `expected_width` folds query
  # width validation into the same pass.
  -> .row_status(rows, allow_empty = false, expected_width = nil)
    ok = rows != nil
    ok = rows.size > 0 if ok && !allow_empty
    width = 0
    has_missing = false
    if ok && rows.size > 0
      ok = type(rows[0]) == "Array"
      width = rows[0].size if ok
      ok = width > 0 if ok
      ok = width == expected_width if ok && expected_width != nil
    if ok
      rows.each -> (row)
        ok = false if type(row) != "Array"
        if type(row) == "Array"
          ok = false if row.size != width
          row.each -> (value)
            valid = value == nil
            has_missing = true if valid
            if !valid
              kind = type(value)
              valid = kind == "Int"
              if kind == "Float"
                if value != value
                  valid = true
                  has_missing = true
                else
                  valid = value - value == 0.to_f
            ok = false if !valid
    status = -1
    status = 0 if ok
    status = 1 if ok && has_missing
    status

  # Rectangular numeric rows with nil/NaN permitted as missing values.
  -> .usable_rows?(rows, allow_empty = false)
    ok = rows != nil
    ok = rows.size > 0 if ok && !allow_empty
    width = 0
    if ok && rows.size > 0
      ok = type(rows[0]) == "Array"
      width = rows[0].size if ok
      ok = width > 0 if ok
    if ok
      rows.each -> (row)
        ok = false if type(row) != "Array"
        if type(row) == "Array"
          ok = false if row.size != width
          row.each -> (value)
            valid = value == nil
            if !valid
              kind = type(value)
              valid = kind == "Int"
              if kind == "Float"
                valid = value != value || value - value == 0.to_f
            ok = false if !valid
    ok

  -> .numeric_targets?(values)
    ok = values != nil && values.size > 0
    if ok
      values.each -> (value)
        missing = DecisionTree.missing?(value)
        ok = false if missing
        if !missing
          kind = type(value)
          ok = false if kind != "Int" && kind != "Float"
          ok = false if kind == "Float" && value - value != 0.to_f
    ok

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

  # Population variance of the targets, weighted per row: the weighted
  # second moment about the WEIGHTED mean, over sum(w). The regression
  # criterion under sample weights.
  #
  # Written as a separate method rather than a branch inside `variance`
  # so the unweighted path stays on exactly the arithmetic it always
  # used — no hand-computed spec value can shift by a last bit. The two
  # loops keep each counter in its own pass.
  -> .weighted_variance(ys, wts)
    n = ys.size
    out = 0.to_f
    if n > 0
      nd = Estimator.weight_total(wts, n).to_f
      total = 0.to_f
      i = 0
      ys.each -> (v)
        total += v.to_f * wts[i]
        i += 1
      m = total / nd
      acc = 0.to_f
      j = 0
      ys.each -> (v)
        d = v.to_f - m
        acc += (d * d) * wts[j]
        j += 1
      out = acc / nd
    out

  # One node's impurity under cfg's criterion. `counts` is nil for a
  # regression tree, where the raw targets are what matters; `n` is the
  # node's TOTAL WEIGHT (its row count when unweighted, so gini and
  # entropy are unchanged — they already divide counts by a total).
  -> .impurity(ys, counts, n, crit, wts)
    out = 0.to_f
    if crit == "mse"
      if wts == nil
        out = DecisionTree.variance(ys)
      else
        out = DecisionTree.weighted_variance(ys, wts)
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

  # Total WEIGHT per class index, over k classes — counts_of's weighted
  # twin. Entries are floats, and an integer weight vector makes them
  # exactly the counts the row-duplicated dataset would produce.
  -> .weighted_counts_of(ys, k, wts)
    out = []
    k.times -> (i)
      acc = 0.to_f
      c = 0
      ys.each -> (v)
        acc += wts[c] if v == i
        c += 1
      out.push(acc)
    out

  # counts_of (or its weighted twin), or nil for a regression tree (k = 0).
  -> .node_counts(ys, k, wts)
    out = nil
    if k > 0
      if wts == nil
        out = DecisionTree.counts_of(ys, k)
      else
        out = DecisionTree.weighted_counts_of(ys, k, wts)
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

  # vals (integers) ascending — sorted_copy's INTEGER twin, so the result
  # can be used as an array INDEX. sorted_copy coerces to f64 and a float
  # is not an index.
  -> .sorted_ints(vals)
    out = []
    vals.each -> (v)
      out.push(v)
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

  # Row indices sorted by one feature's numeric value, ties by original row
  # index. Decorating each entry as [value, index] makes the ordinary
  # lexicographic Array sort carry the complete deterministic key. On the
  # native engine that reaches the runtime's blockless sort fast path instead
  # of calling a Tungsten comparator O(n log n) times. Numeric-only columns
  # use the smaller [value, index] key; only a column that actually contains
  # missing values pays for the leading observed/missing discriminator. The
  # builder starts compact and widens prior keys once, when the first missing
  # cell appears, avoiding a separate discovery scan.
  -> .sorted_feature_indices(rows, feature)
    has_missing = false
    decorated = []
    n = rows.size
    n.times -> (i)
      value = rows[i][feature]
      missing = DecisionTree.missing?(value)
      if missing && !has_missing
        widened = []
        decorated.each -> (entry)
          widened.push([0, entry[0], entry[1]])
        decorated = widened
        has_missing = true
      if has_missing
        if missing
          decorated.push([1, 0.to_f, i])
        else
          decorated.push([0, value, i])
      else
        decorated.push([value, i])
    sorted = decorated.sort
    order = []
    if has_missing
      sorted.each -> (entry)
        order.push(entry[2])
    else
      sorted.each -> (entry)
        order.push(entry[1])
    order

  # Stable row orders for every feature. A full-feature tree computes these
  # once at the root; child nodes filter and remap them instead of sorting
  # their rows again.
  -> .feature_orders(rows, n_features)
    out = []
    n_features.times -> (feature)
      out.push(DecisionTree.sorted_feature_indices(rows, feature))
    out

  # The feature indices this node's split search will scan, ASCENDING.
  #
  # An ordinary tree scans EVERY feature: `cfg[:max_features]` is absent
  # (or nil) and the answer is 0 … nf-1, exactly the order the search used
  # before this hook existed. Nothing about an existing tree changes — same
  # features, same order, same tie-break (lowest index wins), same tree.
  #
  # A RANDOM FOREST sets `cfg[:max_features] = m` and `cfg[:rng] = a MINSTD
  # state`, and gets a fresh m-of-nf subset drawn WITHOUT replacement at
  # EVERY node. That per-split redraw — not the bootstrap — is what
  # decorrelates the trees; a forest that subsampled features once per tree
  # would still let one dominant feature sit at every root. The subset is
  # returned SORTED so the documented tie-break survives subsampling: among
  # the drawn features, the lowest index still wins.
  #
  # The draw advances `cfg[:rng]` IN PLACE. cfg is one hash shared by the
  # whole build recursion, so the stream is consumed in the build's
  # depth-first order (node, then left subtree, then right) — a fixed order
  # for fixed data, which is what makes the forest a pure function of its
  # seed on both engines. MINSTD is Splitter's generator, reused rather than
  # reinvented; its worst-case product stays inside the 48-bit boxed-int
  # range.
  -> .split_features(cfg)
    nf = cfg[:nf]
    m = cfg[:max_features]
    m = nf if m == nil
    m = nf if m > nf
    m = 1 if m < 1
    idx = []
    nf.times -> (i)
      idx.push(i)
    out = idx
    if m < nf
      state = cfg[:rng]
      m.times -> (k)
        state = (state * 48271) % 2147483647
        j = k + (state % (nf - k))
        tmp = idx[k]
        idx[k] = idx[j]
        idx[j] = tmp
      cfg[:rng] = state
      picked = []
      m.times -> (p)
        picked.push(idx[p])
      out = DecisionTree.sorted_ints(picked)
    out

  # Index of label in classes, or -1 when it is not there.
  -> .label_index(classes, label)
    idx = -1
    i = 0
    classes.each -> (c)
      idx = i if idx < 0 && c == label
      i += 1
    idx

  # Split rows/ys on `x[j] <= thr`, keeping each side's rows, targets AND
  # weights aligned: { lr:, ly:, lws:, rr:, ry:, rws: }. The two weight
  # slices are nil for an unweighted tree, so a whole subtree can be grown
  # without ever allocating one. Parent indices are optional because only a
  # tree carrying root-presorted feature orders consumes them; feature-
  # subsampled forest nodes would otherwise allocate and fill two dead arrays
  # after every winning split.
  -> .partition(rows, ys, wts, j, thr, missing_left = false, keep_indices = true)
    lr = []
    ly = []
    lws = []
    left_indices = nil
    left_indices = [] if keep_indices
    rr = []
    ry = []
    rws = []
    right_indices = nil
    right_indices = [] if keep_indices
    i = 0
    rows.each -> (r)
      value = r[j]
      missing = DecisionTree.missing?(value)
      go_left = missing_left if missing
      go_left = value.to_f <= thr if !missing
      if go_left
        lr.push(r)
        ly.push(ys[i])
        lws.push(wts[i]) if wts != nil
        left_indices.push(i) if keep_indices
      else
        rr.push(r)
        ry.push(ys[i])
        rws.push(wts[i]) if wts != nil
        right_indices.push(i) if keep_indices
      i += 1
    lw = nil
    lw = lws if wts != nil
    rwt = nil
    rwt = rws if wts != nil
    { lr: lr, ly: ly, lws: lw, left_indices: left_indices, rr: rr, ry: ry, rws: rwt, right_indices: right_indices }

  # Filter parent feature orders into child-local feature orders. `left_indices`
  # and `right_indices` are in child row order, so the maps translate a parent
  # row index to its new local index in O(1). Total work is O(features * rows).
  -> .child_orders(orders, left_indices, right_indices, n)
    left_map = []
    right_map = []
    n.times -> (i)
      left_map.push(-1)
      right_map.push(-1)
    left_indices.each_with_index -> (parent_index, child_index)
      left_map[parent_index] = child_index
    right_indices.each_with_index -> (parent_index, child_index)
      right_map[parent_index] = child_index

    left_orders = []
    right_orders = []
    orders.each -> (order)
      left_order = []
      right_order = []
      order.each -> (parent_index)
        mapped = left_map[parent_index]
        left_order.push(mapped) if mapped >= 0
        mapped = right_map[parent_index]
        right_order.push(mapped) if mapped >= 0
      left_orders.push(left_order)
      right_orders.push(right_order)
    { left: left_orders, right: right_orders }

  # --- The greedy split search ---

  # The best admissible split of rows/ys, or nil when there is none. See
  # the header for the tie-break rule this encodes: features ascending,
  # thresholds ascending, replacement only on a STRICTLY better gain
  # (measured against a relative tolerance), so ties keep the lowest
  # feature index and then the lowest threshold.
  # WEIGHTS change only the arithmetic, never the rule: the two sides are
  # weighed by their TOTAL WEIGHT instead of their row count, and their
  # impurities are the weighted ones. `min_samples_leaf` still counts
  # ROWS, matching scikit-learn (which spells the weighted version
  # `min_weight_fraction_leaf`, a separate knob) — so it is the one place
  # a weighted fit and its row-duplicated twin can legitimately differ,
  # and only when that knob is set away from its default.
  # The FEATURES scanned are whatever DecisionTree.split_features answers —
  # all of them for an ordinary tree (unchanged), a fresh random subset per
  # node when the caller asked for one (a random forest). Either way they
  # arrive in ascending index order, so the rule above is untouched.
  #
  # Each feature order is scanned left-to-right while sufficient statistics
  # move across the boundary: squared class counts for gini, c*log(c) for
  # entropy, and weighted Welford moments for regression. Updating and scoring
  # a candidate is O(1), including both missing-value assignments, independent
  # of the number of classes. A full-feature tree sorts all orders once at its
  # root, then filters them into child-local orders in O(features * rows) per
  # node. A feature-subsampled forest sorts only the features drawn at each
  # node. Either path materializes row storage only for the winning threshold.
  # Classification receives the totals already computed for the public node,
  # avoiding a second class-by-row counting pass before the sweep.
  # The former implementation rebuilt both partitions and recomputed both
  # impurities at every candidate, making a node O(features * rows^2).
  -> .best_split(rows, ys, wts, cfg, parent_imp, orders = nil, parent_counts = nil)
    k = cfg[:k]
    min_leaf = cfg[:min_leaf]
    min_leaf_weight = cfg[:min_leaf_weight]
    min_leaf_weight = 0.to_f if min_leaf_weight == nil
    crit = cfg[:crit]
    n = rows.size
    nd = Estimator.weight_total(wts, n).to_f
    tol = parent_imp / 1000000000000.to_f
    entropy_ln2 = 1.to_f
    entropy_ln2 = Math.log(2.to_f) if crit == "entropy"
    best = nil
    bgain = 0.to_f
    total_counts = parent_counts
    total_counts = DecisionTree.node_counts(ys, k, wts) if k > 0 && total_counts == nil

    # Weighted Welford state for regression. Classification does not touch
    # these values; computing them once outside the feature loop makes each
    # feature sweep linear after sorting.
    total_weight = 0.to_f
    total_mean = 0.to_f
    total_m2 = 0.to_f
    if k == 0
      i = 0
      while i < n
        weight = 1.to_f
        weight = wts[i] if wts != nil
        value = ys[i].to_f
        next_weight = total_weight + weight
        delta = value - total_mean
        next_mean = total_mean + (weight / next_weight) * delta
        total_m2 += weight * delta * (value - next_mean)
        total_weight = next_weight
        total_mean = next_mean
        i += 1

    feats = DecisionTree.split_features(cfg)
    feats.each -> (j)
      order = nil
      order = orders[j] if orders != nil
      order = DecisionTree.sorted_feature_indices(rows, j) if order == nil
      observed_n = 0
      while observed_n < n && !DecisionTree.missing?(rows[order[observed_n]][j])
        observed_n += 1
      missing_n = n - observed_n

      left_counts = nil
      right_counts = nil
      missing_counts = nil
      right_observed_counts = nil
      track_gini = k > 0 && crit == "gini"
      track_entropy = k > 0 && crit == "entropy"
      left_square = 0.to_f
      right_square = 0.to_f
      missing_square = 0.to_f
      combined_left_square = 0.to_f
      right_observed_square = 0.to_f
      left_count_log = 0.to_f
      right_count_log = 0.to_f
      missing_count_log = 0.to_f
      combined_left_count_log = 0.to_f
      right_observed_count_log = 0.to_f
      if k > 0
        # These are private sweep statistics, not the node's public counts.
        # Keep every entry Float from initialization onward so the innermost
        # threshold update never pays mixed Integer/Float conversion.
        left_counts = []
        right_counts = []
        if missing_n > 0
          missing_counts = []
          right_observed_counts = []
        total_counts.each -> (count)
          float_count = count.to_f
          left_counts.push(0.to_f)
          right_counts.push(float_count)
          right_square += float_count * float_count if track_gini
          if track_entropy && count > 0
            right_count_log += float_count * Math.log(float_count)
          if missing_n > 0
            missing_counts.push(0.to_f)
            right_observed_counts.push(float_count)
            right_observed_square += float_count * float_count if track_gini
            if track_entropy && count > 0
              right_observed_count_log += float_count * Math.log(float_count)

      left_weight = 0.to_f
      right_weight = nd
      left_mean = 0.to_f
      right_mean = total_mean
      left_m2 = 0.to_f
      right_m2 = total_m2
      missing_weight = 0.to_f
      missing_mean = 0.to_f
      missing_m2 = 0.to_f
      right_observed_weight = nd
      right_observed_mean = total_mean
      right_observed_m2 = total_m2

      if missing_n > 0
        missing_position = observed_n
        while missing_position < n
          missing_index = order[missing_position]
          missing_row_weight = 1.to_f
          missing_row_weight = wts[missing_index] if wts != nil
          if k > 0
            missing_class = ys[missing_index]
            if track_gini
              old_missing = missing_counts[missing_class]
              next_missing = old_missing + missing_row_weight
              missing_square += next_missing * next_missing - old_missing * old_missing
              old_observed = right_observed_counts[missing_class]
              next_observed = old_observed - missing_row_weight
              right_observed_square += next_observed * next_observed - old_observed * old_observed
            if track_entropy
              old_missing = missing_counts[missing_class]
              next_missing = old_missing + missing_row_weight
              old_missing_term = 0.to_f
              old_missing_term = old_missing * Math.log(old_missing) if old_missing > 0.to_f
              next_missing_term = next_missing * Math.log(next_missing)
              missing_count_log += next_missing_term - old_missing_term
              old_observed = right_observed_counts[missing_class]
              next_observed = old_observed - missing_row_weight
              old_observed_term = old_observed * Math.log(old_observed)
              next_observed_term = 0.to_f
              next_observed_term = next_observed * Math.log(next_observed) if next_observed > 0.to_f
              right_observed_count_log += next_observed_term - old_observed_term
            missing_counts[missing_class] += missing_row_weight
            right_observed_counts[missing_class] -= missing_row_weight
            missing_weight += missing_row_weight
          else
            missing_value = ys[missing_index].to_f
            next_missing_weight = missing_weight + missing_row_weight
            missing_delta = missing_value - missing_mean
            next_missing_mean = missing_mean + (missing_row_weight / next_missing_weight) * missing_delta
            missing_m2 += missing_row_weight * missing_delta * (missing_value - next_missing_mean)
            missing_weight = next_missing_weight
            missing_mean = next_missing_mean
          missing_position += 1
        combined_left_square = missing_square if track_gini
        combined_left_count_log = missing_count_log if track_entropy
        right_observed_weight = nd - missing_weight
        if k == 0
          right_observed_weight = 0.to_f
          right_observed_mean = 0.to_f
          right_observed_m2 = 0.to_f
          observed_position = 0
          while observed_position < observed_n
            observed_index = order[observed_position]
            observed_weight = 1.to_f
            observed_weight = wts[observed_index] if wts != nil
            observed_value = ys[observed_index].to_f
            next_observed_weight = right_observed_weight + observed_weight
            observed_delta = observed_value - right_observed_mean
            next_observed_mean = right_observed_mean + (observed_weight / next_observed_weight) * observed_delta
            right_observed_m2 += observed_weight * observed_delta * (observed_value - next_observed_mean)
            right_observed_weight = next_observed_weight
            right_observed_mean = next_observed_mean
            observed_position += 1

      # A suffix is structurally constant only inside the final run of equal
      # targets, so one start index carries the same information as the old
      # per-position Boolean array. The clamp below remains exact without
      # allocating O(rows) storage for every regression feature sweep.
      suffix_constant_start = n
      observed_suffix_constant_start = observed_n
      left_constant = true
      left_first = nil
      if k == 0
        suffix_constant_start = n - 1
        suffix_position = n - 2
        suffix_done = false
        while suffix_position >= 0 && !suffix_done
          current_target = ys[order[suffix_position]]
          next_target = ys[order[suffix_position + 1]]
          if current_target == next_target
            suffix_constant_start = suffix_position
          else
            suffix_done = true
          suffix_position -= 1
        if missing_n > 0
          observed_suffix_constant_start = observed_n - 1
          observed_suffix_position = observed_n - 2
          observed_suffix_done = false
          while observed_suffix_position >= 0 && !observed_suffix_done
            current_target = ys[order[observed_suffix_position]]
            next_target = ys[order[observed_suffix_position + 1]]
            if current_target == next_target
              observed_suffix_constant_start = observed_suffix_position
            else
              observed_suffix_done = true
            observed_suffix_position -= 1
      position = 0
      while position < observed_n - 1
        index = order[position]
        weight = 1.to_f
        weight = wts[index] if wts != nil
        value = ys[index].to_f

        if k > 0
          class_index = ys[index]
          if track_gini || track_entropy
            old_left_count = left_counts[class_index]
            next_left_count = old_left_count + weight
            old_right_count = right_counts[class_index]
            next_right_count = old_right_count - weight
          if track_gini
            left_square += next_left_count * next_left_count - old_left_count * old_left_count
            right_square += next_right_count * next_right_count - old_right_count * old_right_count
            if missing_n > 0
              old_combined_count = old_left_count + missing_counts[class_index]
              next_combined_count = old_combined_count + weight
              combined_left_square += next_combined_count * next_combined_count - old_combined_count * old_combined_count
              old_observed_count = right_observed_counts[class_index]
              next_observed_count = old_observed_count - weight
              right_observed_square += next_observed_count * next_observed_count - old_observed_count * old_observed_count
          if track_entropy
            old_left_term = 0.to_f
            old_left_term = old_left_count * Math.log(old_left_count) if old_left_count > 0.to_f
            next_left_term = next_left_count * Math.log(next_left_count)
            left_count_log += next_left_term - old_left_term
            old_right_term = old_right_count * Math.log(old_right_count)
            next_right_term = 0.to_f
            next_right_term = next_right_count * Math.log(next_right_count) if next_right_count > 0.to_f
            right_count_log += next_right_term - old_right_term
            if missing_n > 0
              old_combined_count = old_left_count + missing_counts[class_index]
              next_combined_count = old_combined_count + weight
              old_combined_term = 0.to_f
              old_combined_term = old_combined_count * Math.log(old_combined_count) if old_combined_count > 0.to_f
              next_combined_term = next_combined_count * Math.log(next_combined_count)
              combined_left_count_log += next_combined_term - old_combined_term
              old_observed_count = right_observed_counts[class_index]
              next_observed_count = old_observed_count - weight
              old_observed_term = old_observed_count * Math.log(old_observed_count)
              next_observed_term = 0.to_f
              next_observed_term = next_observed_count * Math.log(next_observed_count) if next_observed_count > 0.to_f
              right_observed_count_log += next_observed_term - old_observed_term
          left_counts[class_index] += weight
          right_counts[class_index] -= weight
          right_observed_counts[class_index] -= weight if missing_n > 0
          left_weight += weight
          right_weight -= weight
          right_observed_weight -= weight if missing_n > 0
        else
          left_first = value if position == 0
          left_constant = false if value != left_first
          next_left_weight = left_weight + weight
          left_delta = value - left_mean
          next_left_mean = left_mean + (weight / next_left_weight) * left_delta
          left_m2 += weight * left_delta * (value - next_left_mean)
          left_m2 = 0.to_f if left_constant
          left_weight = next_left_weight
          left_mean = next_left_mean

          next_right_weight = right_weight - weight
          if next_right_weight > 0.to_f
            next_right_mean = right_mean - weight * (value - right_mean) / next_right_weight
            right_m2 -= weight * (value - right_mean) * (value - next_right_mean)
            right_m2 = 0.to_f if right_m2 < 0.to_f
            # Removing rows can leave a few ulps instead of mathematical zero.
            # Clamp only when the suffix is structurally constant; a
            # magnitude heuristic would erase real variance around a large
            # target offset.
            right_m2 = 0.to_f if position + 1 >= suffix_constant_start
            right_mean = next_right_mean
          else
            right_mean = 0.to_f
            right_m2 = 0.to_f
          right_weight = next_right_weight
          if missing_n > 0
            next_observed_weight = right_observed_weight - weight
            if next_observed_weight > 0.to_f
              next_observed_mean = right_observed_mean - weight * (value - right_observed_mean) / next_observed_weight
              right_observed_m2 -= weight * (value - right_observed_mean) * (value - next_observed_mean)
              right_observed_m2 = 0.to_f if right_observed_m2 < 0.to_f
              right_observed_m2 = 0.to_f if position + 1 >= observed_suffix_constant_start
              right_observed_mean = next_observed_mean
            else
              right_observed_mean = 0.to_f
              right_observed_m2 = 0.to_f
            right_observed_weight = next_observed_weight

        ln = position + 1
        rn = n - ln
        current_value = rows[index][j].to_f
        next_value = rows[order[position + 1]][j].to_f
        if current_value != next_value
          candidate_gain = nil
          candidate_missing_left = false

          # Missing values on the right. With no missing training values this
          # is the ordinary split, while inference defaults to the larger
          # child as sklearn does.
          if ln >= min_leaf && rn >= min_leaf && left_weight >= min_leaf_weight && right_weight >= min_leaf_weight
            li = 0.to_f
            ri = 0.to_f
            if k > 0
              if track_gini
                li = 1.to_f - left_square / (left_weight * left_weight)
                ri = 1.to_f - right_square / (right_weight * right_weight)
              else
                li = (Math.log(left_weight) - left_count_log / left_weight) / entropy_ln2
                ri = (Math.log(right_weight) - right_count_log / right_weight) / entropy_ln2
                li = 0.to_f if li < 0.to_f
                ri = 0.to_f if ri < 0.to_f
            else
              li = left_m2 / left_weight
              ri = right_m2 / right_weight
            candidate_gain = parent_imp - (left_weight / nd) * li - (right_weight / nd) * ri
            candidate_missing_left = ln > rn if missing_n == 0

          # Missing values on the left. Score this independently and keep
          # missing-right on an exact tie.
          missing_left_n = ln + missing_n
          observed_right_n = observed_n - ln
          if missing_n > 0 && missing_left_n >= min_leaf && observed_right_n >= min_leaf && left_weight + missing_weight >= min_leaf_weight && right_observed_weight >= min_leaf_weight
            combined_left_weight = left_weight + missing_weight
            combined_left_impurity = 0.to_f
            observed_right_impurity = 0.to_f
            if k > 0
              if track_gini
                combined_left_impurity = 1.to_f - combined_left_square / (combined_left_weight * combined_left_weight)
                observed_right_impurity = 1.to_f - right_observed_square / (right_observed_weight * right_observed_weight)
              else
                combined_left_impurity = (Math.log(combined_left_weight) - combined_left_count_log / combined_left_weight) / entropy_ln2
                observed_right_impurity = (Math.log(right_observed_weight) - right_observed_count_log / right_observed_weight) / entropy_ln2
                combined_left_impurity = 0.to_f if combined_left_impurity < 0.to_f
                observed_right_impurity = 0.to_f if observed_right_impurity < 0.to_f
            else
              combined_left_m2 = left_m2 + missing_m2
              mean_delta = missing_mean - left_mean
              combined_left_m2 += mean_delta * mean_delta * left_weight * missing_weight / combined_left_weight
              combined_left_impurity = combined_left_m2 / combined_left_weight
              observed_right_impurity = right_observed_m2 / right_observed_weight
            missing_left_gain = parent_imp
            missing_left_gain -= (combined_left_weight / nd) * combined_left_impurity
            missing_left_gain -= (right_observed_weight / nd) * observed_right_impurity
            if candidate_gain == nil || missing_left_gain > candidate_gain + tol
              candidate_gain = missing_left_gain
              candidate_missing_left = true

          if candidate_gain != nil && (best == nil || candidate_gain > bgain + tol)
            bgain = candidate_gain
            threshold = (current_value + next_value) / 2.to_f
            best = { feature: j, threshold: threshold, missing_left: candidate_missing_left, gain: candidate_gain }
        position += 1

    # min_impurity_decrease uses sklearn's root-weighted definition. Reject
    # here, before partitioning, so regularization avoids both child recursion
    # and the otherwise-dead row/order allocations.
    if best != nil && cfg[:min_gain] != nil && cfg[:min_gain] > 0.to_f
      weighted_gain = bgain * nd / cfg[:root_weight].to_f
      best = nil if weighted_gain < cfg[:min_gain].to_f

    # Materialize aligned child arrays exactly once, after every feature has
    # competed and the split-time floor has accepted the winner. The recursive
    # builder consumes the same best-split shape as before, so no caller or
    # node representation changes.
    if best != nil
      part = DecisionTree.partition(
        rows, ys, wts, best[:feature], best[:threshold],
        best[:missing_left], orders != nil
      )
      best[:lr] = part[:lr]
      best[:ly] = part[:ly]
      best[:lws] = part[:lws]
      best[:rr] = part[:rr]
      best[:ry] = part[:ry]
      best[:rws] = part[:rws]
      if orders != nil
        children = DecisionTree.child_orders(
          orders, part[:left_indices], part[:right_indices], n
        )
        best[:lorders] = children[:left]
        best[:rorders] = children[:right]
    best

  # --- Node construction ---

  # What a node alone would predict: the HEAVIEST class (ties to the
  # first-seen label, since a later class must STRICTLY out-weigh it) for
  # a classification tree, the WEIGHTED mean target for a regression one.
  # Both reduce to the majority class and the plain mean when wts is nil —
  # `counts` is then integer counts and weighted_mean's per-row multiplier
  # is exactly 1.
  -> .node_value(ys, counts, cfg, wts)
    out = nil
    if cfg[:k] > 0
      classes = cfg[:classes]
      best = 0
      k = counts.size
      k.times -> (c)
        best = c if counts[c] > counts[best]
      out = classes[best]
    else
      out = Estimator.weighted_mean(ys, wts)
    out

  # `n` is the node's ROW count and `nw` its total WEIGHT (the same
  # number, an integer, when unweighted). Both are recorded: `n` is what
  # tree_lines prints and what min_samples_* compare against, `weight` is
  # what predict_proba divides its class counts by.
  -> .leaf_node(ys, counts, n, nw, depth, imp, cfg, wts)
    value = DecisionTree.node_value(ys, counts, cfg, wts)
    { leaf: true, feature: nil, threshold: nil, missing_left: nil, gain: nil, left: nil, right: nil, n: n, weight: nw, depth: depth, impurity: imp, counts: counts, prediction: value }

  # Grow the subtree for rows/ys at `depth`, returning its root node. The
  # four stopping rules of the header live here, in order: too small, pure,
  # depth cap, then "no admissible split" (best_split answering nil).
  -> .build(rows, ys, wts, cfg, depth, orders = nil)
    k = cfg[:k]
    limit = cfg[:limit]
    min_split = cfg[:min_split]
    crit = cfg[:crit]
    n = rows.size
    nw = Estimator.weight_total(wts, n)
    counts = DecisionTree.node_counts(ys, k, wts)
    imp = DecisionTree.impurity(ys, counts, nw, crit, wts)
    grow = n >= min_split
    grow = false if imp <= 0.to_f
    grow = false if limit >= 0 && depth >= limit
    best = nil
    active_orders = orders
    if grow && active_orders == nil
      max_features = cfg[:max_features]
      if max_features == nil || max_features >= cfg[:nf]
        active_orders = DecisionTree.feature_orders(rows, cfg[:nf])
    if grow
      best = DecisionTree.best_split(
        rows, ys, wts, cfg, imp, active_orders, counts
      )
    out = nil
    if best == nil
      out = DecisionTree.leaf_node(ys, counts, n, nw, depth, imp, cfg, wts)
    else
      value = DecisionTree.node_value(ys, counts, cfg, wts)
      l = DecisionTree.build(best[:lr], best[:ly], best[:lws], cfg, depth + 1, best[:lorders])
      r = DecisionTree.build(best[:rr], best[:ry], best[:rws], cfg, depth + 1, best[:rorders])
      out = { leaf: false, feature: best[:feature], threshold: best[:threshold], missing_left: best[:missing_left], gain: best[:gain], left: l, right: r, n: n, weight: nw, depth: depth, impurity: imp, counts: counts, prediction: value }
    out

  # --- Reading a fitted tree ---

  # The leaf `row` falls into: left on `x[feature] <= threshold`, right
  # otherwise, until a leaf.
  -> .descend(node, row)
    cur = node
    while !cur[:leaf]
      value = row[cur[:feature]]
      missing_left = cur[:missing_left]
      if missing_left == nil
        missing_left = cur[:left][:weight].to_f > cur[:right][:weight].to_f
      missing = DecisionTree.missing?(value)
      go_left = missing_left if missing
      go_left = value <= cur[:threshold] if !missing
      if go_left
        cur = cur[:left]
      else
        cur = cur[:right]
    cur

  # Preorder parallel-array form used only inside a large predict call. The
  # public fitted tree remains the inspectable hash graph, and this program is
  # rebuilt per batch so even an intentional mutation through `model.tree`
  # takes effect immediately. Slots are feature, threshold, missing-left,
  # left index, right index, prediction, and leaf probability output. The last
  # slot is a vector for full predict_proba, or a scalar for one class column.
  -> .append_prediction_program(node, program, include_probabilities = false, class_index = nil)
    features = program[0]
    thresholds = program[1]
    missing_directions = program[2]
    left_indices = program[3]
    right_indices = program[4]
    predictions = program[5]
    probabilities = program[6]
    index = features.size
    if node[:leaf]
      features.push(-1)
      thresholds.push(0.to_f)
      missing_directions.push(false)
      left_indices.push(-1)
      right_indices.push(-1)
      predictions.push(node[:prediction])
      probability = nil
      if include_probabilities
        if class_index == nil
          probability = DecisionTree.proba_of(node)
        else
          probability = node[:counts][class_index].to_f / node[:weight].to_f
      probabilities.push(probability)
    else
      missing_left = node[:missing_left]
      if missing_left == nil
        missing_left = node[:left][:weight].to_f > node[:right][:weight].to_f
      features.push(node[:feature])
      thresholds.push(node[:threshold])
      missing_directions.push(missing_left)
      left_indices.push(-1)
      right_indices.push(-1)
      predictions.push(node[:prediction])
      probabilities.push(nil)
      left_indices[index] = DecisionTree.append_prediction_program(
        node[:left], program, include_probabilities, class_index
      )
      right_indices[index] = DecisionTree.append_prediction_program(
        node[:right], program, include_probabilities, class_index
      )
    index

  -> .prediction_program(node, include_probabilities = false, class_index = nil)
    program = [[], [], [], [], [], [], []]
    DecisionTree.append_prediction_program(
      node, program, include_probabilities, class_index
    )
    program

  # Hash descent is cheaper for a tiny query; larger batches amortize one
  # flattening pass and avoid several hash lookups at every visited node.
  -> .batch_predictions(node, rows, missing_possible = true)
    predictions = []
    if rows.size < 32
      rows.each -> (row)
        predictions.push(DecisionTree.descend(node, row)[:prediction])
    else
      program = DecisionTree.prediction_program(node)
      features = program[0]
      thresholds = program[1]
      missing_directions = program[2]
      left_indices = program[3]
      right_indices = program[4]
      values = program[5]
      rows.each -> (row)
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
        predictions.push(values[index])
    predictions

  # The zero-based preorder node index of each reached leaf. The prediction
  # program is itself preorder (root, complete left subtree, complete right
  # subtree), which is the node numbering used by scikit-learn's `apply`.
  # Rebuilding it per call keeps the result synchronized with the intentionally
  # public/mutable tree, just like batch prediction.
  -> .batch_leaf_indices(node, rows, missing_possible = true)
    program = DecisionTree.prediction_program(node)
    features = program[0]
    thresholds = program[1]
    missing_directions = program[2]
    left_indices = program[3]
    right_indices = program[4]
    out = []
    rows.each -> (row)
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
          if value <= thresholds[index]
            index = left_indices[index]
          else
            index = right_indices[index]
      out.push(index)
    out

  # Batch class probabilities through the same flat program as labels.
  # Leaf probability vectors are computed once per leaf. Full-matrix output
  # copies each selected vector so callers never receive aliased rows; a
  # requested class column is emitted directly without intermediate leaves or
  # probability rows.
  -> .batch_probabilities(node, rows, k, missing_possible = true, class_index = nil)
    out = []
    if rows.size < 32
      rows.each -> (row)
        leaf = DecisionTree.descend(node, row)
        if class_index == nil
          out.push(DecisionTree.proba_of(leaf))
        else
          out.push(leaf[:counts][class_index].to_f / leaf[:weight].to_f)
    else
      program = DecisionTree.prediction_program(node, true, class_index)
      features = program[0]
      thresholds = program[1]
      missing_directions = program[2]
      left_indices = program[3]
      right_indices = program[4]
      probabilities = program[6]
      rows.each -> (row)
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
          copy = []
          c = 0
          while c < k
            copy.push(probability[c])
            c += 1
          out.push(copy)
        else
          out.push(probability)
    out

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

  # Add this subtree's weighted impurity decreases to `out`, one slot per
  # feature. A node contributes weight(node) * gain(node): the absolute
  # amount of weighted impurity removed by its split. Tiny negative gains
  # from floating-point cancellation buy no importance.
  -> .accumulate_importances(node, out)
    if !node[:leaf]
      contribution = node[:weight].to_f * node[:gain].to_f
      out[node[:feature]] += contribution if contribution > 0.to_f
      DecisionTree.accumulate_importances(node[:left], out)
      DecisionTree.accumulate_importances(node[:right], out)
    out

  # Normalized mean decrease in impurity for one fitted tree. The result
  # always has `n_features` entries and sums to 1 when any split reduced
  # impurity; a stump (or a tree whose gains are all zero) returns zeros.
  -> .feature_importances(node, n_features)
    out = []
    i = 0
    while i < n_features
      out.push(0.to_f)
      i += 1
    DecisionTree.accumulate_importances(node, out)
    total = 0.to_f
    out.each -> (value)
      total += value
    if total > 0.to_f
      i = 0
      while i < out.size
        out[i] = out[i] / total
        i += 1
    out

  # Turn an internal node into the leaf prediction it already carries.
  # Every node stores its own prediction/counts/impurity during growth, so
  # post-pruning never needs the training rows again.
  -> .collapse(node)
    node[:leaf] = true
    node[:feature] = nil
    node[:threshold] = nil
    node[:missing_left] = nil
    node[:gain] = nil
    node[:left] = nil
    node[:right] = nil
    node

  # Post-order minimal cost-complexity pruning. The subtree risk is the sum
  # of leaf weight * impurity. Replacing a subtree by its root costs
  #
  #   (root leaf risk - subtree leaf risk) / (subtree leaves - 1)
  #
  # normalized by the fitted root weight, matching sklearn's ccp_alpha
  # scale. Children are considered first, so one traversal reaches the
  # weakest-link fixed point for the requested alpha.
  -> .prune_node(node, alpha, root_weight)
    leaf_risk = node[:weight].to_f * node[:impurity].to_f
    out = [leaf_risk, 1]
    if !node[:leaf]
      left = DecisionTree.prune_node(node[:left], alpha, root_weight)
      right = DecisionTree.prune_node(node[:right], alpha, root_weight)
      subtree_risk = left[0].to_f + right[0].to_f
      leaves = left[1].to_i + right[1].to_i
      effective = (leaf_risk - subtree_risk) / (leaves - 1).to_f / root_weight
      effective = 0.to_f if effective < 0.to_f
      if effective <= alpha
        DecisionTree.collapse(node)
      else
        out = [subtree_risk, leaves]
    out

  # Prune `node` in place and return it. Alpha zero deliberately preserves
  # the full grown tree, including legitimate zero-gain splits.
  -> .prune(node, alpha)
    if alpha > 0.to_f && !node[:leaf]
      DecisionTree.prune_node(node, alpha.to_f, node[:weight].to_f)
    node

  # Structural copy used by pruning-path analysis. Counts and predictions
  # are immutable fitted values, so only the recursive node hashes need
  # copying.
  -> .clone_node(node)
    out = {
      leaf: node[:leaf], feature: node[:feature],
      threshold: node[:threshold], gain: node[:gain],
      missing_left: node[:missing_left],
      left: nil, right: nil, n: node[:n], weight: node[:weight],
      depth: node[:depth], impurity: node[:impurity],
      counts: node[:counts], prediction: node[:prediction]
    }
    if !node[:leaf]
      out[:left] = DecisionTree.clone_node(node[:left])
      out[:right] = DecisionTree.clone_node(node[:right])
    out

  # Annotate every internal node with its current effective alpha and return
  # [subtree leaf risk, subtree leaf count].
  -> .mark_prune_alphas(node, root_weight)
    leaf_risk = node[:weight].to_f * node[:impurity].to_f
    out = [leaf_risk, 1]
    if !node[:leaf]
      left = DecisionTree.mark_prune_alphas(node[:left], root_weight)
      right = DecisionTree.mark_prune_alphas(node[:right], root_weight)
      risk = left[0].to_f + right[0].to_f
      leaves = left[1].to_i + right[1].to_i
      alpha = (leaf_risk - risk) / (leaves - 1).to_f / root_weight
      alpha = 0.to_f if alpha < 0.to_f
      node[:_ccp_alpha] = alpha
      out = [risk, leaves]
    out

  -> .minimum_prune_alpha(node)
    out = nil
    if !node[:leaf]
      out = node[:_ccp_alpha].to_f
      left = DecisionTree.minimum_prune_alpha(node[:left])
      right = DecisionTree.minimum_prune_alpha(node[:right])
      out = left if left != nil && left < out
      out = right if right != nil && right < out
    out

  # Prune one weakest link in deterministic preorder. Pruning one at a time
  # preserves repeated alpha entries when independent branches tie.
  -> .prune_first_marked(node, alpha)
    done = false
    if !node[:leaf]
      if node[:_ccp_alpha].to_f <= alpha
        DecisionTree.collapse(node)
        done = true
      else
        done = DecisionTree.prune_first_marked(node[:left], alpha)
        done = DecisionTree.prune_first_marked(node[:right], alpha) if !done
    done

  -> .leaf_impurity(node, root_weight)
    out = node[:weight].to_f * node[:impurity].to_f / root_weight
    if !node[:leaf]
      out = DecisionTree.leaf_impurity(node[:left], root_weight)
      out += DecisionTree.leaf_impurity(node[:right], root_weight)
    out

  # Weakest-link regularization path for an already grown tree. The source
  # tree is not changed. The first point is alpha 0 and the full tree's leaf
  # impurity; the final point is the root leaf.
  -> .pruning_path(node)
    tree = DecisionTree.clone_node(node)
    root_weight = tree[:weight].to_f
    alphas = [0.to_f]
    impurities = [DecisionTree.leaf_impurity(tree, root_weight)]
    while !tree[:leaf]
      DecisionTree.mark_prune_alphas(tree, root_weight)
      alpha = DecisionTree.minimum_prune_alpha(tree)
      previous = alphas[alphas.size - 1].to_f
      alpha = previous if alpha < previous
      DecisionTree.prune_first_marked(tree, alpha)
      alphas.push(alpha)
      impurities.push(DecisionTree.leaf_impurity(tree, root_weight))
    { ccp_alphas: alphas, impurities: impurities }

  # A node's class distribution, counts / total weight in `classes` order;
  # nil for a regression node. `weight` is the node's row count exactly
  # when the fit was unweighted, so this is the old counts / n there.
  -> .proba_of(node)
    counts = node[:counts]
    out = nil
    if counts != nil
      nd = node[:weight].to_f
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
  ro :ccp_alpha          # >= 0; 0 keeps the full grown tree
  ro :min_impurity_decrease # >= 0; minimum root-weighted split gain
  ro :min_weight_fraction_leaf # 0..0.5; fitted-root weight floor

  -> new(max_depth = nil, min_samples_split = nil, min_samples_leaf = nil, criterion = nil, ccp_alpha = nil, min_impurity_decrease = nil, min_weight_fraction_leaf = nil)
    ms = min_samples_split
    ms = 2 if ms == nil
    ms = 2 if ms < 2
    ml = min_samples_leaf
    ml = 1 if ml == nil
    ml = 1 if ml < 1
    cr = criterion
    cr = :gini if cr == nil
    alpha = ccp_alpha
    alpha = 0.to_f if alpha == nil
    alpha = alpha.to_f
    min_gain = min_impurity_decrease
    min_gain = 0.to_f if min_gain == nil
    min_gain = min_gain.to_f
    min_weight_fraction = min_weight_fraction_leaf
    min_weight_fraction = 0.to_f if min_weight_fraction == nil
    min_weight_fraction = min_weight_fraction.to_f
    @max_depth = max_depth
    @min_samples_split = ms
    @min_samples_leaf = ml
    @criterion = cr
    @ccp_alpha = alpha
    @min_impurity_decrease = min_gain
    @min_weight_fraction_leaf = min_weight_fraction
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

  # Weighted impurity and weighted leaf votes — see fit. This is what a
  # bootstrap (and therefore a forest) stands on.
  -> supports_sample_weight?
    true

  # The seven knobs a search varies — never the learned tree.
  -> params
    { max_depth: @max_depth, min_samples_split: @min_samples_split, min_samples_leaf: @min_samples_leaf, criterion: @criterion, ccp_alpha: @ccp_alpha, min_impurity_decrease: @min_impurity_decrease, min_weight_fraction_leaf: @min_weight_fraction_leaf }

  # A NEW, UNFITTED DecisionTreeClassifier with `overrides` applied; self is
  # left untouched. Unmentioned keys carry over, so with_params(params)
  # round-trips.
  -> with_params(overrides)
    md = Estimator.opt(overrides, :max_depth, @max_depth)
    ms = Estimator.opt(overrides, :min_samples_split, @min_samples_split)
    ml = Estimator.opt(overrides, :min_samples_leaf, @min_samples_leaf)
    cr = Estimator.opt(overrides, :criterion, @criterion)
    alpha = Estimator.opt(overrides, :ccp_alpha, @ccp_alpha)
    min_gain = Estimator.opt(overrides, :min_impurity_decrease, @min_impurity_decrease)
    min_weight_fraction = Estimator.opt(overrides, :min_weight_fraction_leaf, @min_weight_fraction_leaf)
    DecisionTreeClassifier.new(md, ms, ml, cr, alpha, min_gain, min_weight_fraction)

  # --- Fit ---

  # Grow the tree from x/y. Returns self, or nil — fitted? stays false —
  # when the shapes are unusable (empty x, ragged rows, y size mismatch,
  # an unusable sample_weight) or the criterion is not one this tree knows.
  #
  # SAMPLE WEIGHTS make the impurity, the split scoring and every leaf's
  # prediction weighted (see DecisionTree.best_split / .node_value), which
  # is precisely what a bootstrap resample needs: drawing row i n_i times
  # and fitting is the same tree as fitting once with sample_weight = n.
  # That equivalence is the prerequisite for a random forest, and it is
  # exact — a weight of 2 produces the same doubles as two copies of the
  # row, because every weighted term is the unweighted term times an
  # integer.
  -> fit(x, y, sample_weight = nil)
    rows = Estimator.feature_rows(x)
    labels = Estimator.target_values(y)
    ok = rows != nil && labels != nil
    ok = rows.size > 0 && rows.size == labels.size if ok
    ok = DecisionTree.usable_rows?(rows) if ok
    ok = false if !DecisionTree.criterion_ok?(@criterion, false)
    ok = false if @ccp_alpha < 0.to_f
    ok = false if @min_impurity_decrease < 0.to_f
    ok = false if @min_weight_fraction_leaf < 0.to_f
    ok = false if @min_weight_fraction_leaf > 1.to_f / 2.to_f
    wts = nil
    wts = Estimator.weight_values(sample_weight, rows.size) if ok && sample_weight != nil
    ok = false if sample_weight != nil && wts == nil
    if ok && wts != nil
      trimmed = Estimator.drop_zero_weights(rows, labels, wts)
      rows = trimmed[:rows]
      labels = trimmed[:targets]
      wts = trimmed[:weights]
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
      root_weight = Estimator.weight_total(wts, rows.size).to_f
      min_leaf_weight = @min_weight_fraction_leaf * root_weight
      cfg = { k: classes.size, classes: classes, nf: nf, limit: limit, min_split: @min_samples_split, min_leaf: @min_samples_leaf, min_leaf_weight: min_leaf_weight, crit: @criterion.to_s, min_gain: @min_impurity_decrease, root_weight: root_weight }
      @classes = classes
      @n_features = nf
      @tree = DecisionTree.build(rows, ys, wts, cfg, 0)
      DecisionTree.prune(@tree, @ccp_alpha)
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

  # Normalized mean decrease in impurity, one value per fitted feature;
  # nil before fit. See DecisionTree.feature_importances.
  -> feature_importances
    out = nil
    out = DecisionTree.feature_importances(@tree, @n_features) if @fitted
    out

  # The tree as an array of printable lines (see DecisionTree.render); nil
  # before fit.
  -> tree_lines
    out = nil
    out = DecisionTree.render(@tree, "", []) if @fitted
    out

  # Weakest-link pruning path grown from x/y without changing self.
  -> cost_complexity_pruning_path(x, y, sample_weight = nil)
    model = DecisionTreeClassifier.new(
      @max_depth, @min_samples_split, @min_samples_leaf, @criterion, 0,
      @min_impurity_decrease, @min_weight_fraction_leaf
    )
    out = nil
    out = DecisionTree.pruning_path(model.tree) if model.fit(x, y, sample_weight) != nil
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

  # Stable zero-based preorder leaf IDs, equivalent to scikit-learn's
  # DecisionTreeClassifier.apply. `apply` above remains the older Koala API
  # that returns inspectable leaf hashes.
  -> leaf_indices(x)
    rows = nil
    rows = Estimator.feature_rows(x) if @fitted
    out = nil
    if rows != nil
      status = DecisionTree.row_status(rows, true, @n_features)
      out = DecisionTree.batch_leaf_indices(@tree, rows, status > 0) if status >= 0
    out

  # Predicted labels for x — each row's leaf's majority class.
  -> predict(x)
    rows = nil
    rows = Estimator.feature_rows(x) if @fitted
    out = nil
    if rows != nil
      status = DecisionTree.row_status(rows, true, @n_features)
      out = DecisionTree.batch_predictions(@tree, rows, status > 0) if status >= 0
    out

  # The leaf's class distribution. With no label: one array per row, one
  # entry per class in `classes` order, summing to 1. With a label: the flat
  # P(label) column, ready for Metrics.roc_auc / Metrics.log_loss. nil
  # before fit, on a width mismatch, or for a label the fit never saw.
  -> predict_proba(x, pos_label = nil)
    rows = nil
    rows = Estimator.feature_rows(x) if @fitted
    out = nil
    if rows != nil
      status = DecisionTree.row_status(rows, true, @n_features)
      if status >= 0
        idx = nil
        idx = DecisionTree.label_index(@classes, pos_label) if pos_label != nil
        if pos_label == nil || idx >= 0
          out = DecisionTree.batch_probabilities(
            @tree, rows, @classes.size, status > 0, idx
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
    "DecisionTreeClassifier"

  # The whole fitted TREE goes in. It needs no encoder of its own: a node
  # is a plain hash whose :left / :right are plain hashes, so the generic
  # hash node of the format carries the recursion for free — which is the
  # payoff of representing nodes as data rather than as closures.
  -> to_state
    { max_depth: @max_depth, min_samples_split: @min_samples_split, min_samples_leaf: @min_samples_leaf, criterion: @criterion, ccp_alpha: @ccp_alpha, min_impurity_decrease: @min_impurity_decrease, min_weight_fraction_leaf: @min_weight_fraction_leaf, classes: @classes, tree: @tree, n_features: @n_features }

  -> .load_state(st)
    out = nil
    ok = st != nil
    ok = st[:min_samples_split] != nil && st[:min_samples_leaf] != nil && st[:criterion] != nil if ok
    ok = st[:classes] != nil && st[:tree] != nil && st[:n_features] != nil if ok
    if ok
      model = DecisionTreeClassifier.new(st[:max_depth], st[:min_samples_split], st[:min_samples_leaf], st[:criterion], st[:ccp_alpha], st[:min_impurity_decrease], st[:min_weight_fraction_leaf])
      out = model.restore_state(st)
    out

  -> restore_state(st)
    @classes = st[:classes]
    @tree = st[:tree]
    @n_features = st[:n_features]
    @fitted = true
    self

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
  ro :ccp_alpha          # >= 0; 0 keeps the full grown tree
  ro :min_impurity_decrease # >= 0; minimum root-weighted split gain
  ro :min_weight_fraction_leaf # 0..0.5; fitted-root weight floor

  -> new(max_depth = nil, min_samples_split = nil, min_samples_leaf = nil, criterion = nil, ccp_alpha = nil, min_impurity_decrease = nil, min_weight_fraction_leaf = nil)
    ms = min_samples_split
    ms = 2 if ms == nil
    ms = 2 if ms < 2
    ml = min_samples_leaf
    ml = 1 if ml == nil
    ml = 1 if ml < 1
    cr = criterion
    cr = :mse if cr == nil
    alpha = ccp_alpha
    alpha = 0.to_f if alpha == nil
    alpha = alpha.to_f
    min_gain = min_impurity_decrease
    min_gain = 0.to_f if min_gain == nil
    min_gain = min_gain.to_f
    min_weight_fraction = min_weight_fraction_leaf
    min_weight_fraction = 0.to_f if min_weight_fraction == nil
    min_weight_fraction = min_weight_fraction.to_f
    @max_depth = max_depth
    @min_samples_split = ms
    @min_samples_leaf = ml
    @criterion = cr
    @ccp_alpha = alpha
    @min_impurity_decrease = min_gain
    @min_weight_fraction_leaf = min_weight_fraction
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

  # Weighted MSE and weighted leaf means — see fit.
  -> supports_sample_weight?
    true

  -> params
    { max_depth: @max_depth, min_samples_split: @min_samples_split, min_samples_leaf: @min_samples_leaf, criterion: @criterion, ccp_alpha: @ccp_alpha, min_impurity_decrease: @min_impurity_decrease, min_weight_fraction_leaf: @min_weight_fraction_leaf }

  -> with_params(overrides)
    md = Estimator.opt(overrides, :max_depth, @max_depth)
    ms = Estimator.opt(overrides, :min_samples_split, @min_samples_split)
    ml = Estimator.opt(overrides, :min_samples_leaf, @min_samples_leaf)
    cr = Estimator.opt(overrides, :criterion, @criterion)
    alpha = Estimator.opt(overrides, :ccp_alpha, @ccp_alpha)
    min_gain = Estimator.opt(overrides, :min_impurity_decrease, @min_impurity_decrease)
    min_weight_fraction = Estimator.opt(overrides, :min_weight_fraction_leaf, @min_weight_fraction_leaf)
    DecisionTreeRegressor.new(md, ms, ml, cr, alpha, min_gain, min_weight_fraction)

  # --- Fit ---

  # Weighted exactly like the classifier: weighted MSE as the split
  # criterion and the weighted mean target at every leaf.
  -> fit(x, y, sample_weight = nil)
    rows = Estimator.feature_rows(x)
    targets = Estimator.target_values(y)
    ok = rows != nil && targets != nil
    ok = rows.size > 0 && rows.size == targets.size if ok
    ok = DecisionTree.usable_rows?(rows) if ok
    ok = DecisionTree.numeric_targets?(targets) if ok
    ok = false if !DecisionTree.criterion_ok?(@criterion, true)
    ok = false if @ccp_alpha < 0.to_f
    ok = false if @min_impurity_decrease < 0.to_f
    ok = false if @min_weight_fraction_leaf < 0.to_f
    ok = false if @min_weight_fraction_leaf > 1.to_f / 2.to_f
    wts = nil
    wts = Estimator.weight_values(sample_weight, rows.size) if ok && sample_weight != nil
    ok = false if sample_weight != nil && wts == nil
    if ok && wts != nil
      trimmed = Estimator.drop_zero_weights(rows, targets, wts)
      rows = trimmed[:rows]
      targets = trimmed[:targets]
      wts = trimmed[:weights]
    out = nil
    if ok
      nf = rows[0].size
      ys = []
      targets.each -> (v)
        ys.push(v.to_f)
      limit = @max_depth
      limit = -1 if limit == nil
      limit = 0 if limit < 0 && @max_depth != nil
      root_weight = Estimator.weight_total(wts, rows.size).to_f
      min_leaf_weight = @min_weight_fraction_leaf * root_weight
      cfg = { k: 0, classes: nil, nf: nf, limit: limit, min_split: @min_samples_split, min_leaf: @min_samples_leaf, min_leaf_weight: min_leaf_weight, crit: "mse", min_gain: @min_impurity_decrease, root_weight: root_weight }
      @n_features = nf
      @tree = DecisionTree.build(rows, ys, wts, cfg, 0)
      DecisionTree.prune(@tree, @ccp_alpha)
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

  # Normalized mean decrease in MSE, one value per fitted feature; nil
  # before fit.
  -> feature_importances
    out = nil
    out = DecisionTree.feature_importances(@tree, @n_features) if @fitted
    out

  -> tree_lines
    out = nil
    out = DecisionTree.render(@tree, "", []) if @fitted
    out

  # Weakest-link pruning path grown from x/y without changing self.
  -> cost_complexity_pruning_path(x, y, sample_weight = nil)
    model = DecisionTreeRegressor.new(
      @max_depth, @min_samples_split, @min_samples_leaf, @criterion, 0,
      @min_impurity_decrease, @min_weight_fraction_leaf
    )
    out = nil
    out = DecisionTree.pruning_path(model.tree) if model.fit(x, y, sample_weight) != nil
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

  # Stable zero-based preorder leaf IDs; see the classifier's method.
  -> leaf_indices(x)
    rows = nil
    rows = Estimator.feature_rows(x) if @fitted
    out = nil
    if rows != nil
      status = DecisionTree.row_status(rows, true, @n_features)
      out = DecisionTree.batch_leaf_indices(@tree, rows, status > 0) if status >= 0
    out

  # Predicted values for x — each row's leaf's mean training target.
  -> predict(x)
    rows = nil
    rows = Estimator.feature_rows(x) if @fitted
    out = nil
    if rows != nil
      status = DecisionTree.row_status(rows, true, @n_features)
      out = DecisionTree.batch_predictions(@tree, rows, status > 0) if status >= 0
    out

  # R² (Metrics.r2) of self's predictions on x against y, weighted when
  # sample_weight is given; nil before fit, when the shapes do not line
  # up, or when the weights are unusable.
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
    "DecisionTreeRegressor"

  # As for the classifier, minus `classes` — a regression leaf predicts a
  # mean, so there are no labels to carry.
  -> to_state
    { max_depth: @max_depth, min_samples_split: @min_samples_split, min_samples_leaf: @min_samples_leaf, criterion: @criterion, ccp_alpha: @ccp_alpha, min_impurity_decrease: @min_impurity_decrease, min_weight_fraction_leaf: @min_weight_fraction_leaf, tree: @tree, n_features: @n_features }

  -> .load_state(st)
    out = nil
    ok = st != nil
    ok = st[:min_samples_split] != nil && st[:min_samples_leaf] != nil && st[:criterion] != nil if ok
    ok = st[:tree] != nil && st[:n_features] != nil if ok
    if ok
      model = DecisionTreeRegressor.new(st[:max_depth], st[:min_samples_split], st[:min_samples_leaf], st[:criterion], st[:ccp_alpha], st[:min_impurity_decrease], st[:min_weight_fraction_leaf])
      out = model.restore_state(st)
    out

  -> restore_state(st)
    @tree = st[:tree]
    @n_features = st[:n_features]
    @fitted = true
    self
