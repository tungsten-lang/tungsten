# DBSCAN — density-based spatial clustering of applications with noise
# (pure Tungsten, CPU-only; koala's second UNSUPERVISED learner and the
# complement to KMeans)
#
#     model = DBSCAN.new(2, 3)      # eps = 2, min_samples = 3
#     model.fit(x)                  # self when fitted, nil when unfittable
#     model.labels                  # cluster id per training row, -1 = NOISE
#     model.core_sample_indices     # indices of the core samples, ascending
#     model.components              # the core sample rows themselves
#     model.n_clusters              # clusters discovered (noise is not one)
#     model.fit_predict(x)          # fit, then return the training labels
#     model.predict(x)              # nearest-CORE assignment — see below
#     model.score(x)                # silhouette over the non-noise rows
#
# --- Why DBSCAN, given KMeans ---
#
# KMeans answers a different question than it appears to. It needs `k` up
# front, it minimizes a sum of squared distances to k centroids — so it
# can only ever carve space into k CONVEX cells — and every row is forced
# into some cluster, so a single far-away point drags a centroid toward
# it and there is no way to say "this one is noise".
#
# DBSCAN drops all three assumptions. It grows clusters by DENSITY: a
# region is a cluster when points are packed closely enough, whatever
# SHAPE that region has, the number of clusters falls out of the data
# rather than being supplied, and anything not dense enough to belong is
# labelled -1. The price is a different pair of knobs — `eps` (how close
# counts as close) and `min_samples` (how many neighbours make a region
# dense) — and no notion of a cluster CENTRE at all.
#
# The canonical demonstration is two concentric rings (spec/dbscan_spec.w
# builds them): both rings share the same centroid, so no assignment of
# ring-to-centroid is a k-means fixed point and KMeans provably cannot
# recover them — it slices both rings in half. DBSCAN separates them
# exactly, because each ring is density-connected to itself and to
# nothing else.
#
# --- The algorithm ---
#
# Fix a radius `eps` and a count `min_samples`. For each row i let
# N(i) = { j : distance(i, j) <= eps }, which INCLUDES i itself.
#
#   * i is a CORE sample when |N(i)| >= min_samples.
#   * Two core samples are density-connected when a chain of core samples,
#     each within eps of the next, joins them. Every connected component
#     of core samples is one cluster.
#   * A non-core row inside some core sample's eps-ball is a BORDER row:
#     it joins that core sample's cluster but never extends it.
#   * Everything else is NOISE, labelled -1 (scikit-learn's convention).
#
# The expansion is an explicit LIFO stack, never recursion — a deep
# recursive expansion over a long density chain would be a stack depth
# proportional to the data. Neighbourhoods are precomputed once, so fit is
# O(n^2) in distance evaluations, the same all-pairs cost scikit-learn
# pays with `algorithm="brute"`.
#
# --- DETERMINISM, and the border-point tie rule ---
#
# DBSCAN's output is famously order-sensitive: a border row may sit inside
# the eps-ball of core samples belonging to two DIFFERENT clusters, and
# which one claims it depends on the order the clusters are grown in.
# (Core samples have no such ambiguity — density-connectivity is an
# equivalence relation on them, so their partition is a property of the
# data alone.) koala pins the ambiguity down with two rules, so a fit is a
# pure function of the input rows and is byte-identical across runs and
# across both engines:
#
#   1. CLUSTER NUMBERING follows the ASCENDING INDEX of the first core
#      sample encountered. Rows are scanned 0, 1, 2, …; the first
#      unlabelled core sample seeds cluster 0, the next seeds cluster 1,
#      and so on. Since a core sample can only ever be labelled by its own
#      component, cluster c is exactly the component whose LOWEST-INDEX
#      core sample is the (c+1)-th such minimum.
#   2. A BORDER ROW JOINS THE LOWEST-NUMBERED CLUSTER whose core samples
#      it is adjacent to. This is the same answer scikit-learn's
#      `dbscan_inner` produces (it grows cluster 0 to completion before
#      cluster 1 begins, and a labelled row is never relabelled), stated
#      as a rule about the OUTPUT instead of about the traversal — which
#      means it holds no matter how the expansion stack is ordered.
#
# Rule 1 is what makes the labels reproducible; rule 2 is what makes them
# reproducible for the awkward rows. Both are properties of the ROW ORDER
# of x, and that is the honest caveat: permute the input rows and border
# rows may change cluster, exactly as in scikit-learn. Nothing else moves.
#
# Distance ties in `predict` break to the LOWEST core sample index
# (strict `<`, the KNNClassifier / KMeans convention).
#
# --- predict: an explicit, documented deviation ---
#
# DBSCAN HAS NO NATURAL OUT-OF-SAMPLE PREDICT, and scikit-learn says so by
# omission: its DBSCAN offers `fit_predict` and no `predict` at all,
# because a new row cannot change the density structure that was already
# learned, and there is no centroid to compare it against.
#
# koala must still answer `predict` — it is part of the `Estimable`
# contract every estimator conforms to — so rather than fake it, this
# class DEFINES it as one specific, stated thing:
#
#     predict(x) assigns each row of x to the cluster of the NEAREST CORE
#     SAMPLE, provided that core sample is within eps; otherwise -1.
#
# That is the standard hand-rolled DBSCAN extension, and it is a genuine
# density statement: a query row is in a cluster only if it lands inside
# the dense region that cluster is made of. What it is NOT is a
# reproduction of `fit`:
#
#   * a training CORE sample predicts its own cluster — its nearest core
#     sample is itself, at distance 0 — so it always agrees with `labels`;
#   * a training NOISE row has no core sample within eps, so it predicts
#     -1 and always agrees;
#   * a training BORDER row can DISAGREE. `fit` gives it the
#     lowest-numbered adjacent cluster (rule 2 above); `predict` gives it
#     the nearest one. When those differ, they differ — and that is the
#     deviation, called out here rather than hidden.
#
# So `fit_predict(x)` is the method to use for the training set (it returns
# `labels`, the real DBSCAN answer) and `predict` is for rows the fit never
# saw. `fit_predict` is not `fit` + `predict`; it never claims to be.
#
# --- score: silhouette over the non-noise rows ---
#
# A density model has no inertia. There is no centroid to measure to, and
# the objective DBSCAN optimizes — density-connectivity — is a yes/no
# structural property with no numeric value to report, so the honest
# choices were a real internal validation index or nil.
#
# `score(x)` is the SILHOUETTE (Metrics.silhouette_score) of `predict(x)`
# over the rows that are NOT noise. Greater is better and it is bounded in
# [-1, 1], so it is a valid CrossValidation / GridSearch objective, which
# is what makes `eps` and `min_samples` tunable by search at all — the
# reason for choosing a number over nil.
#
# Noise rows are EXCLUDED rather than treated as a cluster: -1 is not a
# cluster, it is the absence of one, and pooling every outlier into a
# pseudo-cluster would punish DBSCAN for doing the one thing KMeans
# cannot. nil comes back when the score is undefined — before fit, on a
# feature-width mismatch, on an unusable weight vector, or when the
# surviving rows do not carry between 2 and n-1 distinct clusters (one
# cluster has nothing to separate from; n clusters leaves every row a
# singleton). That is Metrics.silhouette_score's own domain, propagated.
#
# HONEST CAVEAT, because it matters for exactly the case this class was
# added for: the silhouette rewards compact, roughly spherical clusters,
# so on the concentric rings it PREFERS the wrong answer — scikit-learn
# scores KMeans's ring-slicing split 0.296 and DBSCAN's correct
# inner/outer split 0.083. `score` is a defensible default objective, not
# an oracle; it is not a proof that a clustering is right, and
# spec/dbscan_spec.w asserts the ring result structurally instead.
#
# --- Sample weights ---
#
# Supported, as scikit-learn supports them: a row's weight is how many
# times it counts toward a neighbourhood, so |N(i)| becomes the SUM of the
# weights in N(i) and "core" means that sum reaches min_samples. An
# integer weight vector is then exactly the row-duplicated dataset, which
# is this bit's definition of correctness (see lib/estimator_base.w).
#
# ONE DELIBERATE DEVIATION FROM scikit-learn, at weight 0. scikit-learn
# derives core-ness from the weighted sum alone, so a row weighing 0 can
# still BE a core sample if its neighbours are heavy enough — and can
# therefore bridge two clusters into one, which the dataset with that row
# deleted would never do. Verified against scikit-learn 1.9.0 on
#   x = [[0,0],[0,1],[1,0],[2,0],[4,0],[4,1],[5,0]], eps=2, min_samples=3,
#   sample_weight = [1,1,1,0,1,1,1]
# it returns ONE cluster; deleting row 3 returns TWO. koala returns two,
# because a zero-weight row is not in the sample and must not be able to
# change the answer. Concretely: a zero-weight row can never be a core
# sample. It contributes 0 to every neighbourhood sum automatically, so
# nothing else needs a special case.
#
# The row is still LABELLED — `labels` is documented as one entry per input
# row, and silently shortening it would be a worse surprise than carrying a
# row that contributes nothing — so it comes back as the border row or the
# noise row it would be. That is exactly the choice KMeans makes for its
# zero-weight rows. With all-positive weights koala and scikit-learn agree
# byte for byte.
#
# --- Metrics ---
#
# `metric` is "euclidean" (the default), "manhattan" or "chebyshev", and
# it is a real hyperparameter — `params` reports it and a grid search can
# vary it. Euclidean comparisons are done on SQUARED distances against a
# squared eps, so integer inputs stay exact and no square root is ever
# taken; the other two need no root at all. An unrecognized metric makes
# fit return nil, the bit's shape-error convention.
#
# --- Shapes and failure ---
#
# x is coerced by the neutral Estimator.feature_rows: a DataFrame (numeric
# columns only), a Matrix, an array of row arrays, or a flat
# single-feature array. nil cells are NOT handled — run an Imputer first.
# fit returns nil, and fitted? stays false, for an empty x, ragged rows,
# eps <= 0, min_samples < 1, an unknown metric, or an unusable
# sample_weight. predict / score return nil before a successful fit and on
# a feature-width mismatch. Nothing here raises.
#
# `eps` has NO DEFAULT on purpose. scikit-learn's 0.5 is a placeholder
# that is wrong for almost every dataset, and eps is the one number
# DBSCAN's entire behaviour turns on; a default would be an invitation to
# not think about it. `min_samples` defaults to 5 and `metric` to
# "euclidean", both scikit-learn's.
#
# NOTE: every float here derives via .to_f — a bare decimal literal is a
# Decimal and does not coerce with Float.
+ DBSCAN
  is Estimable
  is UnsupervisedEstimator

  ro :eps                  # neighbourhood radius (inclusive)
  ro :min_samples          # neighbourhood size that makes a row core
  ro :metric               # "euclidean" | "manhattan" | "chebyshev"
  ro :labels               # cluster id per training row (-1 = noise); nil before fit
  ro :core_sample_indices  # ascending indices of the core samples; nil before fit
  ro :components           # the core sample rows (floats); nil before fit
  ro :n_clusters           # clusters found, noise excluded; 0 before fit

  -> new(eps, min_samples = 5, metric = "euclidean")
    @eps = eps
    @min_samples = min_samples
    @metric = metric
    @fitted = false
    @labels = nil
    @core_sample_indices = nil
    @components = nil
    @n_clusters = 0
    @n_features = 0

  -> fitted?
    @fitted

  # --- Estimable contract (see lib/estimator_base.w) ---

  -> estimator_name
    "DBSCAN"

  # Density clustering learns from features alone — fit(x) / score(x).
  -> supervised?
    false

  # A weight is how many times a row counts toward a neighbourhood; see
  # the header for the exact semantics and the weight-0 deviation.
  -> supports_sample_weight?
    true

  # The hyperparameters a search varies — never the learned labels.
  -> params
    { eps: @eps, min_samples: @min_samples, metric: @metric }

  # A NEW, UNFITTED DBSCAN with `overrides` applied; self is untouched.
  # Unmentioned keys carry over, so with_params(params) round-trips.
  -> with_params(overrides)
    DBSCAN.new(Estimator.opt(overrides, :eps, @eps), Estimator.opt(overrides, :min_samples, @min_samples), Estimator.opt(overrides, :metric, @metric))

  # Discover the density structure of x. Returns self, or nil — fitted?
  # stays false — for an empty or ragged x, eps <= 0, min_samples < 1, an
  # unknown metric, or an unusable sample_weight.
  -> fit(x, sample_weight = nil)
    rows = Estimator.feature_rows(x)
    ok = rows != nil
    ok = rows.size > 0 if ok
    ok = DBSCAN.metric_code(@metric) >= 0 if ok
    ok = @eps != nil && @eps.to_f > 0.to_f if ok
    ok = @min_samples != nil && @min_samples >= 1 if ok
    ok = rows[0].size > 0 if ok
    if ok
      width0 = rows[0].size
      rows.each -> (r)
        ok = false if r.size != width0
    wts = nil
    wts = Estimator.weight_values(sample_weight, rows.size) if ok && sample_weight != nil
    ok = false if sample_weight != nil && wts == nil
    out = nil
    if ok
      code = DBSCAN.metric_code(@metric)
      rad = DBSCAN.radius(@eps, code)
      near = DBSCAN.neighbor_lists(rows, rad, code)
      cores = DBSCAN.core_flags(near, @min_samples, wts)
      labs = DBSCAN.expand(near, cores)
      picked = DBSCAN.core_rows(rows, cores)
      @labels = labs
      @core_sample_indices = picked[:idx]
      @components = picked[:rows]
      @n_clusters = DBSCAN.cluster_count(labs)
      @n_features = rows[0].size
      @fitted = true
      out = self
    out

  # Fit, then return the training-row labels — the real DBSCAN answer for
  # the training set, and what scikit-learn offers INSTEAD of a predict.
  # nil when x is unfittable.
  -> fit_predict(x, sample_weight = nil)
    r = self.fit(x, sample_weight)
    out = nil
    out = @labels if r != nil
    out

  # Cluster id for each row of x by NEAREST CORE SAMPLE within eps, else
  # -1. This is a documented extension, NOT a replay of fit — see the
  # header. nil before fit and on a feature-width mismatch.
  -> predict(x)
    rows = nil
    rows = Estimator.feature_rows(x) if @fitted
    out = nil
    if rows != nil
      nf = @n_features
      ok = true
      rows.each -> (r)
        ok = false if r.size != nf
      if ok
        comps = @components
        owners = DBSCAN.core_labels(@labels, @core_sample_indices)
        code = DBSCAN.metric_code(@metric)
        rad = DBSCAN.radius(@eps, code)
        preds = []
        rows.each -> (q)
          preds.push(DBSCAN.assign_one(q, comps, owners, code, rad))
        out = preds
    out

  # The silhouette of predict(x) over the rows that are not noise — see
  # the header for why this, and for the caveat. nil where undefined.
  #
  # `sample_weight` is validated (an unusable vector scores nil) and a
  # ZERO-weight row is dropped, since it is not in the sample. Positive
  # weights do not otherwise scale the score: a silhouette is a mean of
  # per-row ratios of MEAN distances, and scikit-learn's silhouette_score
  # has no weighted form either, so pretending to weight it would be
  # inventing a statistic.
  -> score(x, sample_weight = nil)
    labs = self.predict(x)
    out = nil
    if labs != nil
      rows = Estimator.feature_rows(x)
      wts = nil
      wts = Estimator.weight_values(sample_weight, rows.size) if sample_weight != nil
      ok = true
      ok = false if sample_weight != nil && wts == nil
      if ok
        kept_rows = []
        kept_labels = []
        i = 0
        labs.each -> (v)
          live = true
          live = wts[i] > 0.to_f if wts != nil
          if v >= 0 && live
            kept_rows.push(rows[i])
            kept_labels.push(v)
          i += 1
        out = Metrics.silhouette_score(kept_rows, kept_labels)
    out

  # --- static helpers (no @ivars, so they are safe inside blocks) ---

  # A metric name as a small integer, or -1 when it is not one this build
  # knows. Distances are dispatched on the CODE, not the name: fit does
  # n^2 distance evaluations and a string compare in that loop is pure
  # overhead.
  -> .metric_code(metric)
    out = 0 - 1
    out = 0 if metric == "euclidean"
    out = 1 if metric == "manhattan"
    out = 2 if metric == "chebyshev"
    out

  # The threshold `distance` is compared against. Euclidean distances are
  # kept SQUARED — no square root is ever taken, so integer inputs stay
  # exact — which means the radius has to be squared to match.
  -> .radius(eps, code)
    e = eps.to_f
    out = e
    out = e * e if code == 0
    out

  # Distance between two equal-width rows under `code`: SQUARED euclidean
  # (0), manhattan (1) or chebyshev (2). Each metric lives in its own
  # small method.
  -> .distance(a, b, code)
    out = 0.to_f
    out = DBSCAN.sq_euclidean(a, b) if code == 0
    out = DBSCAN.manhattan(a, b) if code == 1
    out = DBSCAN.chebyshev(a, b) if code == 2
    out

  -> .sq_euclidean(a, b)
    total = 0.to_f
    n = a.size
    n.times -> (i)
      d = a[i].to_f - b[i].to_f
      total += d * d
    total

  -> .manhattan(a, b)
    total = 0.to_f
    n = a.size
    n.times -> (i)
      d = a[i].to_f - b[i].to_f
      d = 0.to_f - d if d < 0.to_f
      total += d
    total

  -> .chebyshev(a, b)
    top = 0.to_f
    n = a.size
    n.times -> (i)
      d = a[i].to_f - b[i].to_f
      d = 0.to_f - d if d < 0.to_f
      top = d if d > top
    top

  # N(i) for every row, as ascending index arrays — each one INCLUDES i
  # itself, which is what makes min_samples count the way scikit-learn
  # counts it.
  -> .neighbor_lists(rows, rad, code)
    n = rows.size
    out = []
    n.times -> (i)
      found = []
      n.times -> (j)
        found.push(j) if DBSCAN.distance(rows[i], rows[j], code) <= rad
      out.push(found)
    out

  # Core-sample flag per row: the total WEIGHT inside N(i) reaches
  # min_samples (the plain count when `wts` is nil). A zero-weight row is
  # never core — it is not in the sample, so it must not be able to seed
  # or bridge a cluster (see the header's scikit-learn deviation).
  -> .core_flags(near, min_samples, wts)
    n = near.size
    floor = min_samples.to_f
    out = []
    n.times -> (i)
      total = 0.to_f
      near[i].each -> (j)
        wt = 1.to_f
        wt = wts[j] if wts != nil
        total += wt
      live = true
      live = wts[i] > 0.to_f if wts != nil
      hit = false
      hit = true if live && total >= floor
      out.push(hit)
    out

  # The labelling loop: scan rows ascending, and grow a fresh cluster from
  # every unlabelled core sample. The frontier is an explicit LIFO stack —
  # a recursive expansion would be as deep as the longest density chain.
  # A row is labelled once and never relabelled, which is precisely the
  # border-point tie rule stated in the header.
  -> .expand(near, cores)
    n = near.size
    labels = []
    n.times -> (c)
      labels.push(0 - 1)
    label_num = 0
    seed = 0
    while seed < n
      if labels[seed] == 0 - 1 && cores[seed]
        stack = []
        stack.push(seed)
        while stack.size > 0
          cur = stack.pop
          if labels[cur] == 0 - 1
            labels[cur] = label_num
            if cores[cur]
              ring = near[cur]
              m = ring.size
              k = 0
              while k < m
                v = ring[k]
                stack.push(v) if labels[v] == 0 - 1
                k += 1
        label_num += 1
      seed += 1
    labels

  # The core samples as { idx:, rows: } — ascending indices and the rows
  # themselves, copied to floats.
  -> .core_rows(rows, cores)
    n = cores.size
    idx = []
    picked = []
    n.times -> (i)
      if cores[i]
        idx.push(i)
        picked.push(DBSCAN.to_floats(rows[i]))
    { idx: idx, rows: picked }

  # The cluster each core sample belongs to, aligned with `components`.
  -> .core_labels(labels, idx)
    out = []
    idx.each -> (ix)
      out.push(labels[ix])
    out

  # The cluster of the nearest core sample within `rad`, or -1. Labels are
  # a dense 0..k-1 range, so the count is one past the largest.
  -> .assign_one(q, comps, owners, code, rad)
    best = 0 - 1
    bestd = 0.to_f
    found = false
    i = 0
    comps.each -> (c)
      d = DBSCAN.distance(q, c, code)
      if d <= rad
        if !found || d < bestd
          bestd = d
          best = owners[i]
          found = true
      i += 1
    best

  -> .cluster_count(labels)
    top = 0 - 1
    labels.each -> (v)
      top = v if v > top
    top + 1

  # A row copied to floats.
  -> .to_floats(row)
    out = []
    row.each -> (v)
      out.push(v.to_f)
    out

  # --- Persistence (see lib/persist.w) ---

  -> persist_name
    "DBSCAN"

  # `labels` and `n_clusters` describe the TRAINING run and are kept so a
  # loaded model reports what it discovered, not merely what it predicts;
  # `components` + `core_sample_indices` + `n_features` are what predict
  # needs, and core_sample_indices is what maps a component back to its
  # cluster.
  -> to_state
    { eps: @eps, min_samples: @min_samples, metric: @metric, labels: @labels, core_sample_indices: @core_sample_indices, components: @components, n_clusters: @n_clusters, n_features: @n_features }

  -> .load_state(st)
    out = nil
    ok = st != nil
    ok = st[:eps] != nil && st[:min_samples] != nil && st[:metric] != nil if ok
    ok = st[:labels] != nil && st[:core_sample_indices] != nil if ok
    ok = st[:components] != nil && st[:n_clusters] != nil && st[:n_features] != nil if ok
    if ok
      model = DBSCAN.new(st[:eps], st[:min_samples], st[:metric])
      out = model.restore_state(st)
    out

  -> restore_state(st)
    @labels = st[:labels]
    @core_sample_indices = st[:core_sample_indices]
    @components = st[:components]
    @n_clusters = st[:n_clusters]
    @n_features = st[:n_features]
    @fitted = true
    self
