# DBSCAN specs — density-based clustering, on the tungsten-spec framework.
#
# Run from the repo root (both engines, exit 0 = green):
#   bin/tungsten bits/tungsten-koala/spec/dbscan_spec.w
#   bin/tungsten -o /tmp/dbscan_spec bits/tungsten-koala/spec/dbscan_spec.w && /tmp/dbscan_spec
#
# THE SOURCE OF TRUTH for every reference label in this file is
# scikit-learn 1.9.0's `sklearn.cluster.DBSCAN`, run on the same fixtures
# with the same eps / min_samples / metric / sample_weight. Every
# `labels` and `core_sample_indices` assertion below was produced by
# scikit-learn and reproduced by koala BYTE FOR BYTE, with two
# exceptions, both deliberate and both spec'd as such:
#
#   * the ZERO-WEIGHT rule (see "sample weights" below) — koala refuses to
#     let a row that is not in the sample be a core sample; scikit-learn
#     allows it. The divergence is asserted in both directions.
#   * `predict`, which scikit-learn does not have at all (see
#     "predict" below).
#
# The two headline fixtures are also HAND-VERIFIABLE, which is the point
# of choosing them: two 2x2 unit squares 10 apart plus a point at
# [50, 50], and two concentric square rings. Nobody has to trust a
# reference to know what the answer should be.
#
# House rules (see lib/dbscan.w): arrays are compared via `join` (compiled
# Array `==` is identity), floats are never compared via `==` on a
# computed value, `nil` is asserted with be_nil (nil.to_s differs between
# engines), no float literal appears in a call argument, and `\[ \]` is
# escaped inside string literals.

use spec
use koala

# --- Shared fixtures -------------------------------------------------

+ Fx
  # Two well-separated 2x2 unit squares, plus one point far from both.
  # eps = 2, min_samples = 3: inside a square every point sees all four
  # (the diagonal is sqrt(2)), across squares nothing is within 2, and
  # [50, 50] sees only itself. So both squares are solid blocks of core
  # samples and the last row is noise.
  -> .blobs
    out = [[0, 0], [0, 1], [1, 0], [1, 1], [10, 10], [10, 11], [11, 10], [11, 11], [50, 50]]
    out

  # Rows the fit never saw: one inside the first square's reach, one
  # inside the second's, one in the empty middle, one at the outlier.
  -> .queries
    out = [[1, 2], [9, 10], [5, 5], [50, 50]]
    out

  # A BORDER row: [4, 0] is 3 from [1, 0] and 3 from [7, 0], both core,
  # but has only 3 rows within eps = 3 of itself so it is not core at
  # min_samples = 4. It therefore joins a cluster without extending it.
  -> .border
    out = [[0, 0], [1, 0], [0, 1], [1, 1], [4, 0], [7, 0], [8, 0], [7, 1], [8, 1]]
    out

  # The same nine rows with the two blocks swapped — the border row keeps
  # its position and its geometry, only the ROW ORDER changes.
  -> .border_flipped
    out = [[7, 0], [8, 0], [7, 1], [8, 1], [4, 0], [0, 0], [1, 0], [0, 1], [1, 1]]
    out

  # A zero-weight BRIDGE: [2, 0] at index 3 joins the two triangles into
  # one cluster when it counts, and separates them when it does not.
  -> .bridge
    out = [[0, 0], [0, 1], [1, 0], [2, 0], [4, 0], [4, 1], [5, 0]]
    out

  # The same rows with the bridge DELETED — what weight 0 has to mean.
  -> .bridge_dropped
    out = [[0, 0], [0, 1], [1, 0], [4, 0], [4, 1], [5, 0]]
    out

  # `count` points from (x0, y0) stepping by (dx, dy), appended to pts.
  # A helper rather than eight inline blocks so no two sibling closures in
  # one method body share a captured local.
  -> .row_run(pts, count, x0, dx, y0, dy)
    count.times -> (i)
      pts.push([x0 + i * dx, y0 + i * dy])
    pts

  # TWO CONCENTRIC SQUARE RINGS, the case KMeans provably cannot solve.
  # Rows 0..15 are the perimeter of a 4-wide square (spacing 1); rows
  # 16..39 are the perimeter of a 12-wide square (spacing 2). Neighbours
  # within a ring are 1 or 2 apart; the two rings are 4 apart at the
  # closest. At eps = 3, min_samples = 3, each ring is one density-
  # connected component and they never touch.
  #
  # BOTH RINGS HAVE THE SAME CENTROID (the origin, by symmetry), so no
  # assignment of ring-to-cluster can be a k-means fixed point: the two
  # centroids would coincide and every distance would tie. KMeans has to
  # cut across both rings instead, which is exactly what it does.
  -> .rings
    pts = []
    Fx.row_run(pts, 5, -2, 1, 2, 0)
    Fx.row_run(pts, 5, -2, 1, -2, 0)
    Fx.row_run(pts, 3, -2, 0, -1, 1)
    Fx.row_run(pts, 3, 2, 0, -1, 1)
    Fx.row_run(pts, 7, -6, 2, 6, 0)
    Fx.row_run(pts, 7, -6, 2, -6, 0)
    Fx.row_run(pts, 5, -6, 0, -4, 2)
    Fx.row_run(pts, 5, 6, 0, -4, 2)
    pts

  # Two unit-spaced chains 6 apart, plus ONE row off the axis at [14, 3]
  # (index 22). At eps = 5, min_samples = 6 every chain row is core and
  # the chains stay separate. The last row is not core (it sees only 5
  # rows) and is adjacent to core rows of BOTH chains — 5 away from the
  # first chain's tip and 3.6 away from the second's. It is the row where
  # `fit` and `predict` are supposed to disagree.
  -> .chains
    pts = []
    Fx.row_run(pts, 11, 0, 1, 0, 0)
    Fx.row_run(pts, 11, 16, 1, 0, 0)
    pts.push([14, 3])
    pts

  # Does `labels` put rows 0..n_inner-1 in one cluster and the rest in
  # another, different one? The structural question "did it separate the
  # two groups", asked without naming a cluster id.
  -> .separates?(labels, n_inner)
    first = labels[0]
    last = labels[n_inner]
    ok = first != last
    i = 0
    labels.each -> (v)
      want = first
      want = last if i >= n_inner
      ok = false if v != want
      i += 1
    ok

  # Do rows from..upto-1 carry more than one distinct label — i.e. was
  # that group CUT?
  -> .spread?(labels, from, upto)
    seen = []
    i = 0
    labels.each -> (v)
      seen.push(v) if i >= from && i < upto && !seen.include?(v)
      i += 1
    seen.size > 1

  # Two 3x3-ish blobs 20 apart, with their rows INTERLEAVED so any
  # contiguous k-fold split carries some of both — which is what a
  # cross-validated clustering score needs to be defined at all.
  -> .interleaved
    pts = []
    8.times -> (i)
      pts.push([i % 3, i / 3])
      pts.push([20 + i % 3, 20 + i / 3])
    pts

  # A model dumped and loaded back, in one step.
  -> .cycle(model)
    Persist.loads(Persist.dumps(model))

  -> .fitted_blobs
    m = DBSCAN.new(2, 3)
    m.fit(Fx.blobs)
    m

# --- The headline clustering -----------------------------------------

describe "DBSCAN clustering" ->
  # HAND-VERIFIABLE, and scikit-learn's answer: the two squares are
  # clusters 0 and 1 in row order, and [50, 50] is noise (-1).
  it "labels two well-separated blobs and calls the lone outlier noise" ->
    m = DBSCAN.new(2, 3)
    expect(m.fit(Fx.blobs)).to eq(m)
    expect(m.fitted?).to be_true
    expect(m.labels.join(",")).to eq("0,0,0,0,1,1,1,1,-1")
    expect(m.n_clusters).to eq(2)

  # Every row of a square is core (it sees all four); the outlier is not.
  it "reports the core samples, ascending, without the noise row" ->
    m = Fx.fitted_blobs
    expect(m.core_sample_indices.join(",")).to eq("0,1,2,3,4,5,6,7")
    expect(m.components.size).to eq(8)
    expect(m.components[0].size).to eq(2)
    expect(m.components[4][0] == 10.to_f).to be_true

  # DBSCAN discovers the cluster COUNT — it was never told there were two.
  it "discovers the number of clusters rather than being given it" ->
    expect(Fx.fitted_blobs.n_clusters).to eq(2)
    three = DBSCAN.new(2, 1)
    three.fit(Fx.blobs)
    expect(three.n_clusters).to eq(3)

  # fit_predict is the method scikit-learn offers INSTEAD of a predict; it
  # returns the training labels, which is the real DBSCAN answer.
  it "fit_predict returns the training labels" ->
    expect(DBSCAN.new(2, 3).fit_predict(Fx.blobs).join(",")).to eq("0,0,0,0,1,1,1,1,-1")
    expect(DBSCAN.new(2, 3).fit_predict([])).to be_nil

  # Same input, same answer — twice, and on both engines.
  it "is deterministic across repeated fits" ->
    a = DBSCAN.new(2, 3)
    a.fit(Fx.blobs)
    b = DBSCAN.new(2, 3)
    b.fit(Fx.blobs)
    expect(a.labels.join(",")).to eq(b.labels.join(","))
    expect(a.core_sample_indices.join(",")).to eq(b.core_sample_indices.join(","))

  # A DataFrame is coerced by Estimator.feature_rows exactly like an array
  # of rows, so the clustering is the same object either way.
  it "accepts a DataFrame and a flat single-feature array" ->
    df = DataFrame.new([[:x, [0, 0, 1, 1, 10, 10, 11, 11, 50]], [:y, [0, 1, 0, 1, 10, 11, 10, 11, 50]]])
    m = DBSCAN.new(2, 3)
    m.fit(df)
    expect(m.labels.join(",")).to eq("0,0,0,0,1,1,1,1,-1")
    flat = DBSCAN.new(2, 3)
    flat.fit([0, 1, 2, 20, 21, 22])
    expect(flat.labels.join(",")).to eq("0,0,0,1,1,1")

# --- The reason the algorithm was worth adding -----------------------

describe "DBSCAN where KMeans cannot follow" ->
  # THE demonstration. Two concentric square rings share a centroid, so
  # centroid-based clustering cannot separate them at any k — it slices
  # both rings instead. Density-connectivity separates them exactly.
  # scikit-learn's DBSCAN agrees row for row.
  it "separates two concentric rings that KMeans provably cannot" ->
    x = Fx.rings
    expect(x.size).to eq(40)
    want = []
    16.times -> (c)
      want.push(0)
    24.times -> (c)
      want.push(1)

    dbs = DBSCAN.new(3, 3)
    dbs.fit(x)
    expect(dbs.labels.join(",")).to eq(want.join(","))
    expect(dbs.n_clusters).to eq(2)
    expect(Fx.separates?(dbs.labels, 16)).to be_true
    # Every row is dense enough to be core: a ring has no outliers.
    expect(dbs.core_sample_indices.size).to eq(40)

    km = KMeans.new(2)
    km.fit(x)
    expect(Fx.separates?(km.labels, 16)).to be_false
    # ... and it fails by CUTTING each ring, not by merging them.
    expect(Fx.spread?(km.labels, 0, 16)).to be_true
    expect(Fx.spread?(km.labels, 16, 40)).to be_true

  # The honest caveat, asserted rather than hidden: the silhouette rewards
  # compact, roughly spherical clusters, so on the rings it PREFERS the
  # wrong answer. `score` is a defensible default objective, not an
  # oracle — which is why the assertion above is structural.
  it "notes that the silhouette prefers the wrong answer on the rings" ->
    x = Fx.rings
    dbs = DBSCAN.new(3, 3)
    dbs.fit(x)
    km = KMeans.new(2)
    km.fit(x)
    right = Metrics.silhouette_score(x, dbs.labels)
    wrong = Metrics.silhouette_score(x, km.labels)
    expect(wrong > right).to be_true

# --- Hyperparameter boundaries ---------------------------------------

describe "DBSCAN hyperparameter boundaries" ->
  # Below the closest pair, every neighbourhood is the row itself.
  it "eps too small makes every row noise" ->
    tiny = 1.to_f / 2.to_f
    m = DBSCAN.new(tiny, 3)
    m.fit(Fx.blobs)
    expect(m.labels.join(",")).to eq("-1,-1,-1,-1,-1,-1,-1,-1,-1")
    expect(m.n_clusters).to eq(0)
    expect(m.core_sample_indices.join(",")).to eq("")
    expect(m.components.size).to eq(0)

  # Above the widest gap, everything is density-connected to everything.
  it "eps large enough collapses the data to one cluster" ->
    m = DBSCAN.new(1000, 3)
    m.fit(Fx.blobs)
    expect(m.labels.join(",")).to eq("0,0,0,0,0,0,0,0,0")
    expect(m.n_clusters).to eq(1)
    expect(m.core_sample_indices.size).to eq(9)

  # A row's own neighbourhood always contains itself, so min_samples = 1
  # makes every row core and NOTHING can be noise — the outlier becomes a
  # singleton cluster of its own. scikit-learn does the same.
  it "min_samples = 1 leaves no noise at all" ->
    m = DBSCAN.new(2, 1)
    m.fit(Fx.blobs)
    expect(m.labels.join(",")).to eq("0,0,0,0,1,1,1,1,2")
    expect(m.n_clusters).to eq(3)
    expect(m.labels.include?(-1)).to be_false

  # `metric` is a real hyperparameter. On these blobs all three agree
  # (the squares are unit-sized and the gaps are wide), which is the
  # point: the metric changes the geometry, not the contract.
  it "supports euclidean, manhattan and chebyshev" ->
    e = DBSCAN.new(2, 3, "euclidean")
    e.fit(Fx.blobs)
    mh = DBSCAN.new(2, 3, "manhattan")
    mh.fit(Fx.blobs)
    cb = DBSCAN.new(2, 3, "chebyshev")
    cb.fit(Fx.blobs)
    expect(e.labels.join(",")).to eq("0,0,0,0,1,1,1,1,-1")
    expect(mh.labels.join(",")).to eq("0,0,0,0,1,1,1,1,-1")
    expect(cb.labels.join(",")).to eq("0,0,0,0,1,1,1,1,-1")

  # ... and where the geometry DOES differ, so does the answer: the
  # diagonal of a unit square is 1.41 euclidean but 2 in manhattan, so at
  # eps = 1 the manhattan fit still reaches the far corner and the
  # euclidean one does not.
  it "the metric changes the clustering when the geometry differs" ->
    x = [[0, 0], [1, 1], [2, 2]]
    e = DBSCAN.new(1, 2, "euclidean")
    e.fit(x)
    mh = DBSCAN.new(2, 2, "manhattan")
    mh.fit(x)
    expect(e.labels.join(",")).to eq("-1,-1,-1")
    expect(mh.labels.join(",")).to eq("0,0,0")

# --- Determinism and the border rule ---------------------------------

describe "DBSCAN determinism" ->
  # Cluster ids follow the ASCENDING index of the first core sample, so
  # the left block is cluster 0 and the right block is cluster 1.
  it "numbers clusters by ascending first-core-sample index" ->
    m = DBSCAN.new(3, 4)
    m.fit(Fx.border)
    expect(m.labels.join(",")).to eq("0,0,0,0,0,1,1,1,1")
    expect(m.core_sample_indices.join(",")).to eq("0,1,2,3,5,6,7,8")
    # The border row is NOT core: it joins a cluster but never extends it.
    expect(m.core_sample_indices.include?(4)).to be_false

  # THE TIE RULE. [4, 0] is exactly 3 from a core sample of each block, so
  # nothing about the geometry picks a side. koala gives it the
  # LOWEST-NUMBERED adjacent cluster, which is scikit-learn's answer too.
  it "gives an ambiguous border row the lowest-numbered adjacent cluster" ->
    m = DBSCAN.new(3, 4)
    m.fit(Fx.border)
    # index 1 is [1, 0], a core sample of the left block.
    expect(m.labels[4]).to eq(m.labels[1])
    expect(m.labels[4]).to eq(0)

  # ... and the honest consequence, asserted rather than glossed: because
  # cluster numbering follows ROW ORDER, swapping the two blocks moves the
  # border row to the other cluster. The label VECTOR is unchanged; what
  # it means is not. This is scikit-learn's behaviour, not a koala quirk.
  it "moves the border row when the row order changes" ->
    m = DBSCAN.new(3, 4)
    m.fit(Fx.border)
    f = DBSCAN.new(3, 4)
    f.fit(Fx.border_flipped)
    expect(f.labels.join(",")).to eq("0,0,0,0,0,1,1,1,1")
    # Row 0 is now [7, 0] — the block that used to be cluster 1 — and the
    # border row followed it.
    expect(f.labels[4]).to eq(f.labels[0])
    expect(Fx.border_flipped[0].join(",")).to eq("7,0")
    expect(Fx.border[1].join(",")).to eq("1,0")

  # Core samples have NO such ambiguity: density-connectivity is an
  # equivalence relation on them, so their partition is a property of the
  # data alone. Reversing every row leaves the same partition (with the
  # cluster ids swapped, since numbering follows row order).
  it "partitions the core samples independently of row order" ->
    m = DBSCAN.new(2, 3)
    m.fit(Fx.blobs)
    flipped = [[11, 11], [11, 10], [10, 11], [10, 10], [1, 1], [1, 0], [0, 1], [0, 0], [50, 50]]
    r = DBSCAN.new(2, 3)
    r.fit(flipped)
    expect(r.labels.join(",")).to eq("0,0,0,0,1,1,1,1,-1")
    expect(r.core_sample_indices.join(",")).to eq("0,1,2,3,4,5,6,7")

# --- predict: the documented deviation -------------------------------

describe "DBSCAN predict" ->
  # scikit-learn has no predict at all. koala defines one — nearest CORE
  # sample within eps, else -1 — because `Estimable` requires the method,
  # and states exactly what it means rather than faking `fit`.
  it "assigns an unseen row to the nearest core sample's cluster" ->
    m = Fx.fitted_blobs
    expect(m.predict(Fx.queries).join(",")).to eq("0,1,-1,-1")

  # Rows with no core sample inside eps are noise, which is a real density
  # statement: the row is not in any dense region.
  it "calls a row outside every eps-ball noise" ->
    m = Fx.fitted_blobs
    expect(m.predict([[5, 5]]).join(",")).to eq("-1")
    expect(m.predict([[50, 50]]).join(",")).to eq("-1")

  # On core and noise rows predict ALWAYS agrees with labels: a core
  # sample's nearest core sample is itself at distance 0, and a noise row
  # has none within eps. Every row of the blobs fixture is one or the
  # other, so predict reproduces the fit exactly here.
  it "agrees with labels on every core and noise row" ->
    m = Fx.fitted_blobs
    expect(m.predict(Fx.blobs).join(",")).to eq(m.labels.join(","))
    r = DBSCAN.new(3, 3)
    r.fit(Fx.rings)
    expect(r.predict(Fx.rings).join(",")).to eq(r.labels.join(","))

  # THE DEVIATION, exhibited rather than merely documented. Row 22 of the
  # chains fixture is a border row adjacent to core samples of both
  # chains: 5 away from cluster 0's and 3.6 away from cluster 1's. `fit`
  # gives it the LOWEST-numbered adjacent cluster (0) — scikit-learn's
  # answer, verified — while `predict` gives it the NEAREST one (1).
  # They are different questions and here they have different answers.
  it "can disagree with labels on a border row, by design" ->
    m = DBSCAN.new(5, 6)
    m.fit(Fx.chains)
    expect(m.labels.size).to eq(23)
    expect(m.labels[22]).to eq(0)
    expect(m.core_sample_indices.include?(22)).to be_false
    expect(m.predict(Fx.chains)[22]).to eq(1)
    # ... and they agree on all 22 core rows.
    expect(m.predict(Fx.chains).join(",")).to eq("0,0,0,0,0,0,0,0,0,0,0,1,1,1,1,1,1,1,1,1,1,1,1")

  # Ties in predict break to the LOWEST core sample index, the
  # KNNClassifier / KMeans convention. [4, 0] is 3 from a core sample of
  # each block; the left block owns the lower indices, so it wins.
  it "breaks a distance tie toward the lowest core sample index" ->
    m = DBSCAN.new(3, 4)
    m.fit(Fx.border)
    expect(m.predict([[4, 0]]).join(",")).to eq("0")

  it "returns nil before fit and on a feature-width mismatch" ->
    expect(DBSCAN.new(2, 3).predict(Fx.blobs)).to be_nil
    expect(Fx.fitted_blobs.predict([[1, 2, 3]])).to be_nil

# --- score -----------------------------------------------------------

describe "DBSCAN score" ->
  # A density model has no inertia, so `score` is the SILHOUETTE of
  # predict(x) over the rows that are not noise. scikit-learn's
  # silhouette_score over the eight non-noise rows of this fixture is
  # 0.9195260905673606; Float#to_s prints six significant digits.
  it "is the silhouette over the non-noise rows" ->
    m = Fx.fitted_blobs
    expect(m.score(Fx.blobs).to_s).to eq("0.919526")
    expect(m.score(Fx.blobs) > 9.to_f / 10.to_f).to be_true

  # Noise is EXCLUDED rather than pooled into a pseudo-cluster: -1 is the
  # absence of a cluster. Dropping the outlier from x therefore leaves the
  # score untouched — proof that it never counted.
  it "excludes the noise rows rather than treating them as a cluster" ->
    m = Fx.fitted_blobs
    without = [[0, 0], [0, 1], [1, 0], [1, 1], [10, 10], [10, 11], [11, 10], [11, 11]]
    expect(m.score(Fx.blobs).to_s).to eq(m.score(without).to_s)

  # Greater is better and it is bounded in [-1, 1], so it is a valid
  # search objective — which is what makes eps and min_samples tunable.
  # A too-large eps collapses everything to one cluster, where a
  # silhouette is undefined, so the sweep rejects it.
  it "discriminates between eps settings, so a sweep can pick one" ->
    proto = DBSCAN.new(2, 3)
    good = proto.with_params({ eps: 2 })
    good.fit(Fx.blobs)
    huge = proto.with_params({ eps: 1000 })
    huge.fit(Fx.blobs)
    expect(good.score(Fx.blobs)).to_not be_nil
    expect(huge.n_clusters).to eq(1)
    expect(huge.score(Fx.blobs)).to be_nil

  # nil where the silhouette is undefined — Metrics.silhouette_score's own
  # domain, propagated: fewer than two surviving clusters, or none at all.
  it "returns nil when fewer than two clusters survive" ->
    one = DBSCAN.new(2, 3)
    one.fit([[0, 0], [0, 1], [1, 0], [1, 1]])
    expect(one.n_clusters).to eq(1)
    expect(one.score([[0, 0], [0, 1], [1, 0], [1, 1]])).to be_nil
    tiny = 1.to_f / 2.to_f
    none = DBSCAN.new(tiny, 3)
    none.fit(Fx.blobs)
    expect(none.n_clusters).to eq(0)
    expect(none.score(Fx.blobs)).to be_nil

  it "returns nil before fit and on a feature-width mismatch" ->
    expect(DBSCAN.new(2, 3).score(Fx.blobs)).to be_nil
    expect(Fx.fitted_blobs.score([[1, 2, 3]])).to be_nil

  # THE PAYOFF of returning a number instead of nil: because `score` is a
  # real objective, eps and min_samples become searchable through the
  # estimator contract alone. CrossValidation re-fits DBSCAN on each
  # training fold and scores the held-out one, and GridSearch ranks a
  # param grid by that mean — with no code in cross_validation.w or
  # grid_search.w aware that a density model exists.
  it "is a real cross-validation and grid-search objective" ->
    x = Fx.interleaved
    folds = CrossValidation.cross_val_score(DBSCAN.new(2, 3), x, nil, 2)
    expect(folds.size).to eq(2)
    expect(folds[0] > 9.to_f / 10.to_f).to be_true
    expect(folds[1] > 9.to_f / 10.to_f).to be_true

    gs = GridSearch.new(DBSCAN.new(2, 3), { eps: [1, 2] }, 2)
    expect(gs.fit(x, nil)).to_not be_nil
    expect(gs.best_params[:eps]).to eq(2)
    expect(gs.best_score > 9.to_f / 10.to_f).to be_true

# --- sample weights --------------------------------------------------

describe "DBSCAN sample weights" ->
  # A weight is how many times a row counts toward a neighbourhood, so an
  # INTEGER weight vector is exactly the row-duplicated dataset — this
  # bit's definition of correctness (lib/estimator_base.w). Unweighted,
  # nothing here is dense enough; with [0, 0] counting twice, the pair
  # reaches min_samples and becomes a cluster. scikit-learn agrees.
  it "an integer weight vector equals the row-duplicated dataset" ->
    x = [[0, 0], [0, 1], [9, 9]]
    plain = DBSCAN.new(2, 3)
    plain.fit(x)
    expect(plain.labels.join(",")).to eq("-1,-1,-1")

    weighted = DBSCAN.new(2, 3)
    weighted.fit(x, [2, 1, 1])
    expect(weighted.labels.join(",")).to eq("0,0,-1")
    expect(weighted.core_sample_indices.join(",")).to eq("0,1")

    duplicated = DBSCAN.new(2, 3)
    duplicated.fit([[0, 0], [0, 0], [0, 1], [9, 9]])
    expect(duplicated.labels.join(",")).to eq("0,0,0,-1")

  # All-ones is a no-op, byte for byte.
  it "a vector of all ones changes nothing" ->
    plain = Fx.fitted_blobs
    ones = DBSCAN.new(2, 3)
    ones.fit(Fx.blobs, [1, 1, 1, 1, 1, 1, 1, 1, 1])
    expect(ones.labels.join(",")).to eq(plain.labels.join(","))
    expect(ones.core_sample_indices.join(",")).to eq(plain.core_sample_indices.join(","))

  # THE ONE DELIBERATE DEVIATION FROM scikit-learn. Row 3 ([2, 0]) is the
  # only thing joining the two triangles. Unweighted they are one cluster.
  # At weight 0 the row is NOT IN THE SAMPLE, so koala refuses to let it
  # be a core sample and the triangles come apart — which is exactly what
  # DELETING the row does. scikit-learn 1.9.0 returns ONE cluster here,
  # because it derives core-ness from the weighted sum alone and lets a
  # weightless row bridge; that breaks "weight 0 drops the row", so koala
  # does not follow it.
  it "a zero-weight row can never be a core sample" ->
    joined = DBSCAN.new(2, 3)
    joined.fit(Fx.bridge)
    expect(joined.labels.join(",")).to eq("0,0,0,0,0,0,0")
    expect(joined.n_clusters).to eq(1)

    zeroed = DBSCAN.new(2, 3)
    zeroed.fit(Fx.bridge, [1, 1, 1, 0, 1, 1, 1])
    expect(zeroed.n_clusters).to eq(2)
    expect(zeroed.core_sample_indices.join(",")).to eq("0,1,2,4,5,6")

    dropped = DBSCAN.new(2, 3)
    dropped.fit(Fx.bridge_dropped)
    expect(dropped.labels.join(",")).to eq("0,0,0,1,1,1")
    # The six weighted rows that ARE in the sample carry the dropped
    # dataset's labels exactly; the weightless row is still LABELLED
    # (labels is one entry per input row) as the border row it would be.
    expect(zeroed.labels.join(",")).to eq("0,0,0,0,1,1,1")

  # Weights are validated in ONE place (Estimator.weight_values) and an
  # unusable vector makes fit return nil, leaving fitted? false — the
  # bit's shape-error convention, never a raise.
  it "returns nil for an unusable weight vector" ->
    short = DBSCAN.new(2, 3)
    expect(short.fit(Fx.blobs, [1, 1])).to be_nil
    expect(short.fitted?).to be_false
    expect(DBSCAN.new(2, 3).fit(Fx.blobs, [1, 1, 1, 1, 1, 1, 1, 1, -1])).to be_nil
    expect(DBSCAN.new(2, 3).fit(Fx.blobs, [0, 0, 0, 0, 0, 0, 0, 0, 0])).to be_nil

  # score validates them too, and drops the rows that are not in the
  # sample. Zeroing the outlier cannot change a score the outlier was
  # already excluded from — it was noise.
  it "score validates weights and drops the rows not in the sample" ->
    m = Fx.fitted_blobs
    expect(m.score(Fx.blobs, [1, 1, 1, 1, 1, 1, 1, 1, 0]).to_s).to eq(m.score(Fx.blobs).to_s)
    expect(m.score(Fx.blobs, [1, 1])).to be_nil

# --- degenerate input ------------------------------------------------

describe "DBSCAN degenerate input" ->
  # Every unusable shape is a clean nil with fitted? left false. Nothing
  # in this block may raise on either engine.
  it "returns nil for empty, ragged and out-of-range input" ->
    empty = DBSCAN.new(2, 3)
    expect(empty.fit([])).to be_nil
    expect(empty.fitted?).to be_false
    expect(DBSCAN.new(2, 3).fit([[0, 0], [1]])).to be_nil
    expect(DBSCAN.new(0, 3).fit(Fx.blobs)).to be_nil
    expect(DBSCAN.new(-1, 3).fit(Fx.blobs)).to be_nil
    expect(DBSCAN.new(2, 0).fit(Fx.blobs)).to be_nil
    expect(DBSCAN.new(2, 3, "cosine").fit(Fx.blobs)).to be_nil

  # One row is noise at min_samples = 3 and its own cluster at 1 — its
  # neighbourhood contains itself and nothing else, either way.
  it "handles a single row" ->
    lonely = DBSCAN.new(2, 3)
    lonely.fit([[0, 0]])
    expect(lonely.labels.join(",")).to eq("-1")
    expect(lonely.n_clusters).to eq(0)
    expect(lonely.core_sample_indices.join(",")).to eq("")

    solo = DBSCAN.new(2, 1)
    solo.fit([[0, 0]])
    expect(solo.labels.join(",")).to eq("0")
    expect(solo.n_clusters).to eq(1)

  # Coincident rows are the densest possible neighbourhood — three copies
  # of one point are three mutual neighbours, so all three are core.
  it "handles duplicate rows" ->
    dup = DBSCAN.new(1, 3)
    dup.fit([[1, 1], [1, 1], [1, 1]])
    expect(dup.labels.join(",")).to eq("0,0,0")
    expect(dup.core_sample_indices.join(",")).to eq("0,1,2")
    expect(dup.n_clusters).to eq(1)
    # ... and two copies are not enough at min_samples = 3.
    pair = DBSCAN.new(1, 3)
    pair.fit([[1, 1], [1, 1]])
    expect(pair.labels.join(",")).to eq("-1,-1")

  # Before fit everything learned reads nil (n_clusters reads 0, the
  # KMeans n_iter convention) and every consumer answers nil.
  it "answers nil for everything it has not learned yet" ->
    fresh = DBSCAN.new(2, 3)
    expect(fresh.fitted?).to be_false
    expect(fresh.labels).to be_nil
    expect(fresh.core_sample_indices).to be_nil
    expect(fresh.components).to be_nil
    expect(fresh.n_clusters).to eq(0)
    expect(fresh.predict(Fx.blobs)).to be_nil
    expect(fresh.score(Fx.blobs)).to be_nil

  # A failed fit must not leave a half-built model behind.
  it "leaves a failed fit completely unfitted" ->
    m = DBSCAN.new(2, 3)
    expect(m.fit([[0, 0], [1]])).to be_nil
    expect(m.fitted?).to be_false
    expect(m.labels).to be_nil
    expect(m.predict(Fx.blobs)).to be_nil

# --- the estimator contract ------------------------------------------

describe "DBSCAN estimator contract" ->
  # `is Estimable` / `is UnsupervisedEstimator` is a DECLARATION, so the
  # conformance is asserted directly, by behaviour (respond_to? takes a
  # STRING — the only form that answers on both engines).
  it "answers every method the contract requires" ->
    m = DBSCAN.new(2, 3)
    expect(m.respond_to?("fitted?")).to be_true
    expect(m.respond_to?("predict")).to be_true
    expect(m.respond_to?("supervised?")).to be_true
    expect(m.respond_to?("supports_sample_weight?")).to be_true
    expect(m.respond_to?("params")).to be_true
    expect(m.respond_to?("with_params")).to be_true
    expect(m.respond_to?("estimator_name")).to be_true
    expect(m.respond_to?("fit")).to be_true
    expect(m.respond_to?("score")).to be_true
    expect(m.respond_to?("fit_predict")).to be_true

  it "declares itself unsupervised and weight-capable" ->
    m = DBSCAN.new(2, 3)
    expect(m.estimator_name).to eq("DBSCAN")
    expect(m.supervised?).to be_false
    expect(m.supports_sample_weight?).to be_true

  # `params` reports the knobs you SET — never the learned labels.
  it "reports its hyperparameters and nothing learned" ->
    m = Fx.fitted_blobs
    expect(m.params[:eps]).to eq(2)
    expect(m.params[:min_samples]).to eq(3)
    expect(m.params[:metric]).to eq("euclidean")
    expect(m.params.key?(:labels)).to be_false
    expect(m.params.key?(:components)).to be_false

  # with_params CLONES: a NEW, UNFITTED instance, the receiver untouched,
  # and unmentioned keys carried over so with_params(params) round-trips.
  it "with_params clones without touching the receiver" ->
    m = Fx.fitted_blobs
    tweaked = m.with_params({ eps: 5, metric: "manhattan" })
    expect(tweaked.fitted?).to be_false
    expect(tweaked.params[:eps]).to eq(5)
    expect(tweaked.params[:metric]).to eq("manhattan")
    expect(tweaked.params[:min_samples]).to eq(3)
    expect(m.fitted?).to be_true
    expect(m.params[:eps]).to eq(2)

    same = m.with_params(m.params)
    expect(same.params[:eps]).to eq(2)
    expect(same.params[:min_samples]).to eq(3)
    expect(same.params[:metric]).to eq("euclidean")

  # What `supervised?` is FOR: generic tooling fits and scores it without
  # naming the class or knowing fit's arity.
  it "dispatches through Estimator.fit_model and score_model" ->
    m = DBSCAN.new(2, 3)
    expect(Estimator.fit_model(m, Fx.blobs, nil)).to eq(m)
    expect(m.labels.join(",")).to eq("0,0,0,0,1,1,1,1,-1")
    expect(Estimator.score_model(m, Fx.blobs, nil).to_s).to eq("0.919526")

# --- persistence -----------------------------------------------------

describe "DBSCAN persistence" ->
  # The property under test is that a LOADED MODEL IS THE SAVED ONE: same
  # labels, same core samples, same hyperparameters, same predictions.
  it "round-trips through Persist.dumps and Persist.loads" ->
    m = Fx.fitted_blobs
    text = Persist.dumps(m)
    expect(text).to_not be_nil
    expect(text.starts_with?("koala-model ")).to be_true
    expect(text.include?("o DBSCAN")).to be_true

    again = Fx.cycle(m)
    expect(again).to_not be_nil
    expect(again.fitted?).to be_true
    expect(again.estimator_name).to eq("DBSCAN")
    expect(again.labels.join(",")).to eq(m.labels.join(","))
    expect(again.core_sample_indices.join(",")).to eq(m.core_sample_indices.join(","))
    expect(again.n_clusters).to eq(m.n_clusters)
    expect(again.params[:eps]).to eq(2)
    expect(again.params[:min_samples]).to eq(3)
    expect(again.params[:metric]).to eq("euclidean")

  it "a loaded model predicts and scores identically" ->
    m = Fx.fitted_blobs
    again = Fx.cycle(m)
    expect(again.predict(Fx.queries).join(",")).to eq(m.predict(Fx.queries).join(","))
    expect(again.score(Fx.blobs).to_s).to eq(m.score(Fx.blobs).to_s)

  # A non-default metric has to survive too, or a loaded model would
  # silently measure distance a different way.
  it "carries a non-default metric and eps through the format" ->
    tiny = 3.to_f / 2.to_f
    m = DBSCAN.new(tiny, 4, "chebyshev")
    m.fit(Fx.blobs)
    again = Fx.cycle(m)
    expect(again.params[:metric]).to eq("chebyshev")
    expect(again.params[:eps] == tiny).to be_true
    expect(again.params[:min_samples]).to eq(4)
    expect(again.labels.join(",")).to eq(m.labels.join(","))

  # Two cycles, unchanged — the format is a fixed point, not merely
  # lossless once.
  it "survives two full cycles unchanged" ->
    m = Fx.fitted_blobs
    twice = Fx.cycle(Fx.cycle(m))
    expect(twice.labels.join(",")).to eq(m.labels.join(","))
    expect(twice.predict(Fx.queries).join(",")).to eq(m.predict(Fx.queries).join(","))

  # An unfitted model has nothing to save.
  it "refuses to dump an unfitted model" ->
    expect(Persist.dumps(DBSCAN.new(2, 3))).to be_nil

spec_summary
