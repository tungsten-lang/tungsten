# Koala smoke spec — runnable today on BOTH engines:
#
#     bin/tungsten bits/tungsten-koala/spec/smoke.w
#     bin/tungsten -o /tmp/koala_smoke bits/tungsten-koala/spec/smoke.w && /tmp/koala_smoke
#
# Exit code 0 = all checks pass. Framework-free mirror of spec/koala_spec.w
# (which runs on the tungsten-spec runner, also on both engines).
#
# Comparisons go through .to_s / .join — compiled Array == is identity-based,
# and string-array to_s differs between engines (quotes), so string columns
# are compared via join.
#
# Float#to_s now prints the full f64 (%.17g, round-trips) rather than the old
# six-significant-digit %g, so a readable `want` like "0.666667" no longer
# equals the rendered value by string. `check` therefore falls back to a
# NUMERIC comparison (via spec/support.w): when the exact strings differ but
# both render as the same-length list of numeric tokens, they match within a
# relative 1e-5. Non-numeric mismatches still fail exactly.

use koala
use support

# A token is numeric if it holds at least one digit and only the characters
# that make up a decimal or scientific float.
-> smoke_is_num_token(t)
  if t == ""
    return false
  has_digit = false
  i = 0
  n = t.size
  while i < n
    c = t[i]
    if c >= "0" && c <= "9"
      has_digit = true
    else
      if c != "." && c != "-" && c != "+" && c != "e" && c != "E"
        return false
    i += 1
  has_digit

# True when got/want render the same list of numeric values within tolerance.
# Declines (returns false) for anything that is not purely numeric on both
# sides, so a real string/label mismatch still fails.
-> smoke_num_match(g, w)
  gt = koala_num_tokens(g)
  wt = koala_num_tokens(w)
  if gt.size == 0 || gt.size != wt.size
    return false
  i = 0
  while i < gt.size
    if !smoke_is_num_token(gt[i]) || !smoke_is_num_token(wt[i])
      return false
    if !koala_num_close(gt[i].to_f, wt[i].to_f)
      return false
    i += 1
  true

+ KoalaSmoke
  ro :checks
  ro :failures

  -> new
    @checks = 0
    @failures = 0

  -> check(label, got, want)
    @checks += 1
    g = got.to_s
    w = want.to_s
    if g == w || smoke_num_match(g, w)
      << "  ok - " + label
    else
      @failures += 1
      << "  FAIL - " + label + ": got " + g + ", want " + w

  -> run
    # --- Series ---
    s = Series.new([3, 1, 4, 1, 5, 9, 2, 6], "digits")
    self.check("series size", s.size, 8)
    self.check("series sum", s.sum, 31)
    self.check("series mean", s.mean, "3.875")
    self.check("series median", s.median, "3.5")
    self.check("series min", s.min, 1)
    self.check("series max", s.max, 9)
    self.check("series std", s.std, "2.74838")

    doubled = s.map -> (v) v * 2
    self.check("series map", doubled.to_a, "\[6, 2, 8, 2, 10, 18, 4, 12\]")
    big = s.select -> (v) v > 3
    self.check("series select", big.to_a, "\[4, 5, 9, 6\]")
    self.check("series unique", s.unique.to_a, "\[3, 1, 4, 5, 9, 2, 6\]")

    gaps = Series.new([1, nil, 3], "gaps")
    self.check("fillna", gaps.fillna(0).to_a, "\[1, 0, 3\]")
    self.check("dropna", gaps.dropna.to_a, "\[1, 3\]")
    self.check("count skips nil", gaps.count, 2)

    # --- DataFrame ---
    df = DataFrame.new([
      [:name, ["Alice", "Bob", "Carol", "Dan", "Eve"]],
      [:dept, ["eng", "sales", "eng", "sales", "eng"]],
      [:age, [30, 25, 35, 28, 41]],
      [:salary, [80, 65, 95, 70, 120]]
    ])
    self.check("shape", df.shape, "\[5, 4\]")
    self.check("column order", df.column_names.join(","), "name,dept,age,salary")
    self.check("column sum", df[:age].sum, 159)
    self.check("row access", df.row(1)[:name], "Bob")

    seniors = df.where -> (row) row[:age] >= 30
    self.check("where row_count", seniors.row_count, 3)
    self.check("where names", seniors.column_values(:name).join(","), "Alice,Carol,Eve")

    slim = df.select_columns([:name, :salary])
    self.check("select_columns shape", slim.shape, "\[5, 2\]")
    self.check("head", df.head(2).row_count, 2)

    # describe: numeric columns only (:name and :dept skipped)
    desc = df.describe
    self.check("describe cols", desc.column_names.join(","), "statistic,age,salary")
    self.check("describe rows", desc.row_count, 8)
    self.check("describe stat labels", desc.column_values(:statistic).join(","), "count,mean,std,min,25%,50%,75%,max")
    # age = [30,25,35,28,41]: count 5, mean 31.8, sample std 6.30079,
    # min 25, quartiles 28/30(=median)/35, max 41
    self.check("describe age", desc.column_values(:age).join(","), "5,31.8,6.30079,25,28,30,35,41")

    # --- GroupBy ---
    g = df.group_by(:dept)
    self.check("group count", g.size, 2)
    self.check("group keys", g.keys.join(","), "eng,sales")
    self.check("group sizes", g.count.column_values(:count), "\[3, 2\]")
    self.check("group mean", g.mean(:salary).column_values(:salary).join(","), "98.3333,67.5")
    self.check("group max", g.max(:age).column_values(:age), "\[41, 28\]")
    self.check("group sum", g.sum(:salary).column_values(:salary), "\[295, 135\]")

    # --- Koala facade ---
    kf = Koala.frame([[:x, [1, 2, 3]]])
    self.check("Koala.frame", kf.shape, "\[3, 1\]")

    # --- Stats edge cases ---
    self.check("var of one value", Stats.var([1]), "0")
    self.check("var of pair", Stats.var([1, 3]), "2")

    # --- Rolling ---
    rs = Series.new([1, 2, 3, 4, 5], "v")
    self.check("rolling sum", rs.rolling(3).sum.to_a, "\[1, 3, 6, 9, 12\]")
    self.check("rolling mean", rs.rolling(3).mean.to_a.join(","), "1,1.5,2,3,4")
    self.check("rolling min_periods", rs.rolling(3, 3).sum.to_a[1] == nil, true)

    # --- Join ---
    jl = DataFrame.new([[:id, [1, 2, 3]], [:who, ["a", "b", "c"]]])
    jr = DataFrame.new([[:id, [2, 3, 4]], [:score, [20, 30, 40]]])
    self.check("inner join rows", jl.join(jr, :id).row_count, 2)
    self.check("inner join scores", jl.join(jr, :id).column_values(:score), "\[20, 30\]")
    self.check("left join rows", jl.join(jr, :id, :left).row_count, 3)

    # --- Pivot ---
    pdf = DataFrame.new([
      [:city, ["nyc", "nyc", "sf", "sf", "nyc"]],
      [:product, ["a", "b", "a", "b", "a"]],
      [:sales, [1, 2, 3, 4, 5]]
    ])
    self.check("pivot shape", pdf.pivot(:city, :product, :sales).shape, "\[2, 3\]")
    self.check("pivot cells", pdf.pivot(:city, :product, :sales).column_values("a"), "\[6, 3\]")

    # --- Metrics ---
    self.check("accuracy", Metrics.accuracy([1, 0, 1, 1, 0], [1, 0, 0, 1, 0]), "0.8")
    self.check("mse", Metrics.mse([2, 4, 6], [1, 5, 7]), "1")
    self.check("rmse", Metrics.rmse([2, 4, 6], [1, 5, 7]), "1")
    self.check("mae", Metrics.mae([2, 4, 6], [1, 5, 7]), "1")
    self.check("r2", Metrics.r2([2, 4, 6], [1, 5, 7]), "0.839286")
    self.check("median_absolute_error", Metrics.median_absolute_error([0, 0, 0, 0, 0], [1, 2, 3, 4, 100]), "3")
    self.check("max_error", Metrics.max_error([0, 0, 0, 0, 0], [1, 2, 3, 4, 100]), "100")
    self.check("mape", Metrics.mape([2, 4, 6], [1, 5, 7]), "0.447619")
    self.check("explained_variance", Metrics.explained_variance([2, 4, 6], [1, 5, 7]), "0.857143")
    self.check("explained_variance eq r2 centered", Metrics.explained_variance([1, 4, 7], [2, 4, 6]), "0.75")
    self.check("precision", Metrics.precision([1, 1, 1, 0, 0, 1], [1, 0, 0, 0, 1, 1]), "0.5")
    self.check("recall", Metrics.recall([1, 1, 1, 0, 0, 1], [1, 0, 0, 0, 1, 1]), "0.666667")
    self.check("f1", Metrics.f1([1, 1, 1, 0, 0, 1], [1, 0, 0, 0, 1, 1]), "0.571429")

    # --- KNNClassifier ---
    kx = [[1, 1], [2, 2], [3, 3], [6, 6], [7, 7], [8, 8]]
    ky = [:a, :a, :a, :b, :b, :b]
    knn = KNNClassifier.new(3)
    self.check("knn fit self", knn.fit(kx, ky) != nil, true)
    self.check("knn fitted?", knn.fitted?, true)
    self.check("knn predict", knn.predict([[2, 3], [7, 6]]).join(","), "a,b")
    self.check("knn train score", knn.score(kx, ky), 1)
    self.check("knn default k", KNNClassifier.new.k, 5)
    self.check("knn nil before fit", KNNClassifier.new(3).predict([[1, 1]]) == nil, true)

    # --- LogisticRegression ---
    # First epoch is exact: sigmoid(0) = 0.5 (no exp), so w = [0.25], b = 0.
    lg = LogisticRegression.new(1, 1)
    self.check("logreg fit self", lg.fit([[0], [1]], [0, 1]) != nil, true)
    self.check("logreg fitted?", lg.fitted?, true)
    self.check("logreg coef", lg.coefficients, "\[0.25\]")
    self.check("logreg intercept", lg.intercept, 0)
    self.check("logreg classes", lg.classes.join(","), "0,1")
    self.check("logreg proba half", lg.predict_proba([[0]]), "\[0.5\]")
    # Separable clusters converge to 100% accuracy at the defaults.
    lgx = [[0, 0], [1, 0], [0, 1], [3, 3], [4, 3], [3, 4]]
    lgy = [0, 0, 0, 1, 1, 1]
    lgc = LogisticRegression.new
    lgc.fit(lgx, lgy)
    self.check("logreg sep preds", lgc.predict(lgx).join(","), "0,0,0,1,1,1")
    self.check("logreg sep score", lgc.score(lgx, lgy), 1)
    # Opaque labels map by first-seen order and come back unchanged.
    lgs = LogisticRegression.new
    lgs.fit(lgx, [:a, :a, :a, :b, :b, :b])
    self.check("logreg sym classes", lgs.classes.join(","), "a,b")
    self.check("logreg sym preds", lgs.predict([[0, 0], [4, 4]]).join(","), "a,b")
    self.check("logreg nil before fit", LogisticRegression.new.predict([[1]]) == nil, true)
    self.check("logreg one-class nil", LogisticRegression.new.fit([[1], [2]], [0, 0]) == nil, true)
    self.check("logreg three-class nil", LogisticRegression.new.fit([[1], [2], [3]], [0, 1, 2]) == nil, true)

    # --- GaussianNB (generative: closed-form Gaussian naive Bayes) ---
    # Two classes of two rows: means [2,3] / [12,13], population variances
    # all 1, priors 0.5. epsilon = 1e-9 * 26 (26 = the largest column
    # variance over all four rows), so variances print as "1".
    gx = [[1, 2], [3, 4], [11, 12], [13, 14]]
    gy = [0, 0, 1, 1]
    gnb = GaussianNB.new
    self.check("gnb fit self", gnb.fit(gx, gy) != nil, true)
    self.check("gnb fitted?", gnb.fitted?, true)
    self.check("gnb classes", gnb.classes.join(","), "0,1")
    self.check("gnb counts", gnb.class_counts, "\[2, 2\]")
    self.check("gnb priors", gnb.class_priors, "\[0.5, 0.5\]")
    self.check("gnb means", gnb.means, "\[\[2, 3\], \[12, 13\]\]")
    self.check("gnb variances", gnb.variances, "\[\[1, 1\], \[1, 1\]\]")
    self.check("gnb epsilon", gnb.epsilon, "2.6e-08")
    self.check("gnb var_smoothing", gnb.var_smoothing, "1e-09")
    # jll at the class-0 mean: log(0.5) - log(2*pi) = -2.53102; class 1
    # adds -0.5*(100+100). Row [7,8] is equidistant, so both tie.
    self.check("gnb jll", gnb.joint_log_likelihood([[2, 3]]), "\[\[-2.53102, -102.531\]\]")
    self.check("gnb proba tie", gnb.predict_proba([[7, 8]]), "\[\[0.5, 0.5\]\]")
    self.check("gnb predict", gnb.predict([[2, 3], [12, 13], [7, 8]]), "\[0, 1, 0\]")
    self.check("gnb score", gnb.score(gx, gy), 1)
    # scikit-learn's documentation example: predict([[-0.8, -1]]) -> [1]
    skx = [[0 - 1, 0 - 1], [0 - 2, 0 - 1], [0 - 3, 0 - 2], [1, 1], [2, 1], [3, 2]]
    sknb = GaussianNB.new
    sknb.fit(skx, [1, 1, 1, 2, 2, 2])
    self.check("gnb sklearn means", sknb.means, "\[\[-2, -1.33333\], \[2, 1.33333\]\]")
    self.check("gnb sklearn vars", sknb.variances, "\[\[0.666667, 0.222222\], \[0.666667, 0.222222\]\]")
    self.check("gnb sklearn predict", sknb.predict([[0.to_f - 8.to_f / 10.to_f, 0 - 1]]), "\[1\]")
    # Opaque labels, one feature: class a = [-1,1], class b = [3,5]. Equal
    # variances make the two-class softmax a sigmoid: P(b | x=0) = 1/(1+e^8).
    symnb = GaussianNB.new
    symnb.fit([0 - 1, 1, 3, 5], [:a, :a, :b, :b])
    self.check("gnb sym classes", symnb.classes.join(","), "a,b")
    self.check("gnb sym means", symnb.means, "\[\[0\], \[4\]\]")
    self.check("gnb sym preds", symnb.predict([0, 2, 4]).join(","), "a,a,b")
    self.check("gnb sym proba col", symnb.predict_proba([0, 2, 4], :b), "\[0.00033535, 0.5, 0.999665\]")
    self.check("gnb unknown label nil", symnb.predict_proba([0], :zz) == nil, true)
    # A constant feature would divide by zero; epsilon smooths it instead.
    cnb = GaussianNB.new
    cnb.fit([[0, 5], [2, 5], [10, 5], [12, 5]], [0, 0, 1, 1])
    self.check("gnb const feature vars", cnb.variances, "\[\[1, 2.6e-08\], \[1, 2.6e-08\]\]")
    self.check("gnb const feature predict", cnb.predict([[1, 5], [11, 5]]), "\[0, 1\]")
    # Every feature constant: epsilon falls back to var_smoothing (sklearn
    # yields nan), the classes tie, and predict takes the first-seen label.
    dnb = GaussianNB.new
    dnb.fit([5, 5, 5, 5], [0, 0, 1, 1])
    self.check("gnb degenerate epsilon", dnb.epsilon, "1e-09")
    self.check("gnb degenerate proba", dnb.predict_proba([5, 9]), "\[\[0.5, 0.5\], \[0.5, 0.5\]\]")
    self.check("gnb degenerate predict", dnb.predict([5, 9]), "\[0, 0\]")
    # Multiclass with no wrapper — the argmax just ranges over three classes.
    mx = [[0, 0], [1, 0], [10, 10], [11, 10], [0, 20], [1, 20]]
    my = [0, 0, 1, 1, 2, 2]
    mnb = GaussianNB.new
    mnb.fit(mx, my)
    self.check("gnb multiclass priors", mnb.class_priors, "\[0.333333, 0.333333, 0.333333\]")
    self.check("gnb multiclass predict", mnb.predict([[0, 1], [10, 11], [1, 19]]), "\[0, 1, 2\]")
    self.check("gnb multiclass score", mnb.score(mx, my), 1)
    self.check("gnb multiclass report", Metrics.classification_report(mnb.predict(mx), my).macro_f1, 1)
    # Overlapping 1-D classes: means 0.5 / 2.5, variances 0.25, so P(1) is
    # a sigmoid of 8x - 12 — 1/(1+e^4) = 0.0179862 at x = 1. The ranking is
    # still perfect, so roc_auc is 1 and log_loss small.
    onb = GaussianNB.new
    onb.fit([0, 1, 2, 3], [0, 0, 1, 1])
    self.check("gnb overlap proba", onb.predict_proba([0, 1, 2, 3], 1), "\[6.14417e-06, 0.0179862, 0.982014, 0.999994\]")
    self.check("gnb overlap roc_auc", Metrics.roc_auc(onb.predict_proba([0, 1, 2, 3], 1), [0, 0, 1, 1]), 1)
    self.check("gnb overlap log_loss", Metrics.log_loss(onb.predict_proba([0, 1, 2, 3], 1), [0, 0, 1, 1]), "0.00907804")
    self.check("gnb nil before fit", GaussianNB.new.predict([[1, 2]]) == nil, true)
    self.check("gnb nil ragged fit", GaussianNB.new.fit([[1, 2], [3]], [0, 1]) == nil, true)
    self.check("gnb single class ok", GaussianNB.new.fit([[1], [2]], [0, 0]) != nil, true)

    # --- DecisionTreeClassifier (CART: greedy axis-aligned gini splits) ---
    # Labels follow feature 1 and ignore feature 0. Root gini 0.5; feature 0
    # @ 0.5 leaves both sides mixed (gain 0), feature 1 @ 5 — the midpoint of
    # 0 and 10 — separates them exactly (gain 0.5), so that is the root.
    tx = [[0, 0], [1, 0], [0, 10], [1, 10]]
    ty = [:lo, :lo, :hi, :hi]
    dt = DecisionTreeClassifier.new
    self.check("tree fit self", dt.fit(tx, ty) != nil, true)
    self.check("tree fitted?", dt.fitted?, true)
    self.check("tree classes", dt.classes.join(","), "lo,hi")
    self.check("tree root feature", dt.tree[:feature], 1)
    self.check("tree root threshold", dt.tree[:threshold], "5")
    self.check("tree root impurity", dt.tree[:impurity], "0.5")
    self.check("tree root gain", dt.tree[:gain], "0.5")
    self.check("tree depth", dt.depth, 1)
    self.check("tree nodes", dt.node_count, 3)
    self.check("tree leaves", dt.leaf_count, 2)
    self.check("tree render", dt.tree_lines.join(" | "), "x1 <= 5 |   leaf: lo (n=2) |   leaf: hi (n=2)")
    self.check("tree predict", dt.predict(tx).join(","), "lo,lo,hi,hi")
    self.check("tree unseen rows", dt.predict([[99, 4], [0 - 7, 6]]).join(","), "lo,hi")
    self.check("tree score", dt.score(tx, ty), 1)
    # A stump caps the tree at one test; max_depth 0 makes the root a leaf
    # that predicts the training majority (3 vs 3 ties to the first-seen 0).
    sx = [[0], [1], [2], [10], [11], [12]]
    sy = [0, 0, 0, 1, 1, 1]
    stump = DecisionTreeClassifier.new(1)
    stump.fit(sx, sy)
    self.check("tree stump threshold", stump.tree[:threshold], 6)
    self.check("tree stump depth", stump.depth, 1)
    self.check("tree stump score", stump.score(sx, sy), 1)
    root = DecisionTreeClassifier.new(0)
    root.fit(sx, sy)
    self.check("tree root-only leaf", root.tree[:leaf], true)
    self.check("tree root-only counts", root.tree[:counts], "\[3, 3\]")
    self.check("tree root-only predict", root.predict([[0], [12]]), "\[0, 0\]")
    self.check("tree root-only score", root.score(sx, sy), "0.5")
    # XOR: no single cut improves gini, so every gain is 0 — the best
    # zero-gain split is taken anyway and the children separate it exactly.
    xx = [[0, 0], [0, 1], [1, 0], [1, 1]]
    xy = [0, 1, 1, 0]
    xt = DecisionTreeClassifier.new
    xt.fit(xx, xy)
    self.check("tree xor gain", xt.tree[:gain], 0)
    self.check("tree xor depth", xt.depth, 2)
    self.check("tree xor score", xt.score(xx, xy), 1)
    # Leaf class distribution. Capped at depth 1, x = 0..3 / y = 0,1,0,1
    # ties at gain 1/6 between thresholds 0.5 and 2.5 — the LOWEST wins —
    # leaving a pure left leaf and a {1,0,1} right leaf.
    px = [[0], [1], [2], [3]]
    py = [0, 1, 0, 1]
    pt = DecisionTreeClassifier.new(1)
    pt.fit(px, py)
    self.check("tree tie threshold", pt.tree[:threshold], "0.5")
    self.check("tree tie gain", pt.tree[:gain], "0.166667")
    self.check("tree leaf counts", pt.tree[:right][:counts], "\[1, 2\]")
    self.check("tree proba", pt.predict_proba(px), "\[\[1, 0\], \[0.333333, 0.666667\], \[0.333333, 0.666667\], \[0.333333, 0.666667\]\]")
    self.check("tree proba column", pt.predict_proba(px, 1), "\[0, 0.666667, 0.666667, 0.666667\]")
    self.check("tree proba unknown label", pt.predict_proba(px, 99) == nil, true)
    self.check("tree partial score", pt.score(px, py), "0.75")
    # entropy is a real alternative: on four rows of four classes it takes
    # 1.5 (gain 1 bit) where gini ties and keeps the lower 0.5.
    ex = [[0], [1], [2], [3]]
    ey = [0, 1, 2, 3]
    ent = DecisionTreeClassifier.new(1, nil, nil, :entropy)
    ent.fit(ex, ey)
    self.check("tree entropy impurity", ent.tree[:impurity], 2)
    self.check("tree entropy threshold", ent.tree[:threshold], "1.5")
    self.check("tree entropy gain", ent.tree[:gain], 1)
    gin = DecisionTreeClassifier.new(1, nil, nil, :gini)
    gin.fit(ex, ey)
    self.check("tree gini impurity", gin.tree[:impurity], "0.75")
    self.check("tree gini threshold", gin.tree[:threshold], "0.5")
    self.check("tree bad criterion nil", DecisionTreeClassifier.new(nil, nil, nil, :bogus).fit(ex, ey) == nil, true)
    # Multiclass with no wrapper — the root is a three-way gain tie won by
    # the lowest feature index, and its left child splits on feature 1.
    mtx = [[0, 0], [1, 0], [10, 10], [11, 10], [0, 20], [1, 20]]
    mty = [0, 0, 1, 1, 2, 2]
    mt = DecisionTreeClassifier.new
    mt.fit(mtx, mty)
    self.check("tree multiclass render", mt.tree_lines.join(" | "), "x0 <= 5.5 |   x1 <= 10 |     leaf: 0 (n=2) |     leaf: 2 (n=2) |   leaf: 1 (n=2)")
    self.check("tree multiclass predict", mt.predict([[0, 1], [10, 11], [1, 19]]), "\[0, 1, 2\]")
    self.check("tree multiclass score", mt.score(mtx, mty), 1)
    self.check("tree multiclass report", Metrics.classification_report(mt.predict(mtx), mty).macro_f1, 1)
    # Nodes that cannot be split stay leaves: a single class, and features
    # that are constant (no distinct values, hence no candidate threshold).
    one = DecisionTreeClassifier.new
    one.fit([[1], [2]], [5, 5])
    self.check("tree single class leaf", one.tree[:leaf], true)
    self.check("tree single class predict", one.predict([[9]]), "\[5\]")
    flat = DecisionTreeClassifier.new
    flat.fit([[3], [3]], [0, 1])
    self.check("tree constant feature leaf", flat.tree[:leaf], true)
    self.check("tree constant feature proba", flat.predict_proba([[3]]), "\[\[0.5, 0.5\]\]")
    # min_samples_leaf can make the best-gaining split inadmissible: on
    # y = 0,0,0,1 the perfect 2.5 split leaves one row on the right, so
    # with a floor of 2 the weaker 1.5 split (gain 0.125) is taken instead.
    lx = [[0], [1], [2], [3]]
    ly = [0, 0, 0, 1]
    self.check("tree default threshold", DecisionTreeClassifier.new.fit(lx, ly).tree[:threshold], "2.5")
    leafy = DecisionTreeClassifier.new(nil, nil, 2)
    leafy.fit(lx, ly)
    self.check("tree min_samples_leaf threshold", leafy.tree[:threshold], "1.5")
    self.check("tree min_samples_leaf gain", leafy.tree[:gain], "0.125")
    tight = DecisionTreeClassifier.new(nil, 5)
    tight.fit(lx, ly)
    self.check("tree min_samples_split leaf", tight.tree[:leaf], true)
    self.check("tree param clamp", DecisionTreeClassifier.new(nil, 1, 0).params[:min_samples_split], 2)
    # Determinism: no seed, no sampling — the same data fits the same tree.
    dx = [[0, 0], [1, 0], [0, 1], [1, 1], [10, 10], [11, 10], [10, 11], [11, 11]]
    dy = [0, 0, 0, 0, 1, 1, 1, 1]
    d1 = DecisionTreeClassifier.new
    d1.fit(dx, dy)
    d2 = DecisionTreeClassifier.new
    d2.fit(dx, dy)
    self.check("tree determinism", d1.tree_lines.join(" | "), d2.tree_lines.join(" | "))
    self.check("tree determinism exact", d1.tree_lines.join(" | "), "x0 <= 5.5 |   leaf: 0 (n=4) |   leaf: 1 (n=4)")
    # Shapes and degenerate input, the bit's nil convention throughout.
    tdf = DataFrame.new([[:name, ["p", "q", "r", "s"]], [:f1, [0, 1, 10, 11]], [:f2, [0, 1, 10, 11]]])
    tlab = Series.new([:lo, :lo, :hi, :hi], :cls)
    fdt = DecisionTreeClassifier.new
    fdt.fit(tdf, tlab)
    self.check("tree frame predict", fdt.predict(Matrix.new([[0, 0], [11, 11]])).join(","), "lo,hi")
    self.check("tree frame score", fdt.score(tdf, tlab), 1)
    self.check("tree nil before fit", DecisionTreeClassifier.new.predict([[1, 2]]) == nil, true)
    self.check("tree nil tree before fit", DecisionTreeClassifier.new.tree == nil, true)
    self.check("tree nil empty fit", DecisionTreeClassifier.new.fit([], []) == nil, true)
    self.check("tree nil ragged fit", DecisionTreeClassifier.new.fit([[1, 2], [3]], [0, 1]) == nil, true)
    self.check("tree nil misaligned fit", DecisionTreeClassifier.new.fit([[1], [2]], [0, 1, 1]) == nil, true)
    self.check("tree nil wrong width", fdt.predict([[1, 2, 3]]) == nil, true)
    # Contract + composition: cross-validated, grid-searched and pipelined
    # without any of that machinery naming a tree.
    self.check("tree supervised?", DecisionTreeClassifier.new.supervised?, true)
    self.check("tree name", DecisionTreeClassifier.new.estimator_name, "DecisionTreeClassifier")
    self.check("tree params size", DecisionTreeClassifier.new.params.size, 4)
    self.check("tree cross_val", CrossValidation.cross_val_mean(DecisionTreeClassifier.new, dx, dy, 4), 1)
    tgs = GridSearch.new(DecisionTreeClassifier.new, { max_depth: [1, 2] }, 4)
    tgs.fit(dx, dy)
    self.check("tree grid best", tgs.best_params[:max_depth], 1)
    self.check("tree grid score", tgs.best_score, 1)
    self.check("tree grid refit depth", tgs.best_estimator.depth, 1)
    tpipe = Pipeline.new([[:scale, Scaler.new(:standard)], [:tree, DecisionTreeClassifier.new(2)]])
    tpdf = DataFrame.new([[:f, [0, 1, 10, 11]]])
    tpipe.fit(tpdf, [0, 0, 1, 1])
    self.check("tree pipeline predict", tpipe.predict(tpdf), "\[0, 0, 1, 1\]")
    self.check("tree pipeline score", tpipe.score(tpdf, [0, 0, 1, 1]), 1)
    self.check("tree pipeline param", tpipe.params["tree.max_depth"], 2)

    # --- DecisionTreeRegressor (the same tree, MSE criterion) ---
    # x = 0,1,10,11 / y = 1,1,9,9: root mean 5, variance 16; splitting at
    # 5.5 makes both sides constant, so the gain is the whole 16.
    rtx = [[0], [1], [10], [11]]
    rty = [1, 1, 9, 9]
    rt = DecisionTreeRegressor.new
    self.check("rtree fit self", rt.fit(rtx, rty) != nil, true)
    self.check("rtree impurity", rt.tree[:impurity], 16)
    self.check("rtree threshold", rt.tree[:threshold], "5.5")
    self.check("rtree gain", rt.tree[:gain], 16)
    self.check("rtree render", rt.tree_lines.join(" | "), "x0 <= 5.5 |   leaf: 1 (n=2) |   leaf: 9 (n=2)")
    self.check("rtree piecewise constant", rt.predict([[0], [5], [6], [11]]), "\[1, 1, 9, 9\]")
    self.check("rtree r2", rt.score(rtx, rty), 1)
    # y = 2x: the uncapped tree memorizes all four points; the stump
    # predicts 1 and 5, leaving SS_res 4 of SS_tot 20, so R² = 0.8.
    lrx = [[0], [1], [2], [3]]
    lry = [0, 2, 4, 6]
    lrt = DecisionTreeRegressor.new
    lrt.fit(lrx, lry)
    self.check("rtree linear impurity", lrt.tree[:impurity], 5)
    self.check("rtree linear threshold", lrt.tree[:threshold], "1.5")
    self.check("rtree linear predict", lrt.predict(lrx), "\[0, 2, 4, 6\]")
    self.check("rtree linear leaves", lrt.leaf_count, 4)
    rstump = DecisionTreeRegressor.new(1)
    rstump.fit(lrx, lry)
    self.check("rtree stump predict", rstump.predict(lrx), "\[1, 1, 5, 5\]")
    self.check("rtree stump r2", rstump.score(lrx, lry), "0.8")
    rroot = DecisionTreeRegressor.new(0)
    rroot.fit(lrx, lry)
    self.check("rtree mean-only predict", rroot.tree[:prediction], 3)
    self.check("rtree mean-only r2", rroot.score(lrx, lry), 0)
    self.check("rtree name", DecisionTreeRegressor.new.estimator_name, "DecisionTreeRegressor")
    self.check("rtree criterion", DecisionTreeRegressor.new.params[:criterion], "mse")
    self.check("rtree gini rejected", DecisionTreeRegressor.new(nil, nil, nil, :gini).fit(rtx, rty) == nil, true)
    self.check("rtree variance alias", DecisionTreeRegressor.new(nil, nil, nil, :variance).fit(rtx, rty) != nil, true)
    self.check("rtree nil before fit", DecisionTreeRegressor.new.predict([[1]]) == nil, true)

    # --- Cross-validation (KFold / CrossValidation) ---
    cv5 = KFold.new(5).split(10)
    self.check("kfold count", cv5.size, 5)
    self.check("kfold f0 test", cv5[0][1], "\[0, 1\]")
    self.check("kfold f0 train", cv5[0][0], "\[2, 3, 4, 5, 6, 7, 8, 9\]")
    cv3 = KFold.new(3).split(10)
    self.check("kfold uneven f0", cv3[0][1], "\[0, 1, 2, 3\]")
    self.check("kfold uneven f2", cv3[2][1], "\[7, 8, 9\]")
    seeded = KFold.new(5, 42).split(10)
    self.check("kfold seeded f1", seeded[1][1], "\[4, 3\]")
    self.check("kfold bad k nil", KFold.new(1).split(10) == nil, true)
    cvx = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9]
    cvy = [1, 3, 5, 7, 9, 11, 13, 15, 17, 19]
    self.check("cross_val_score linear", CrossValidation.cross_val_score(LinearRegression.new, cvx, cvy, 5), "\[1, 1, 1, 1, 1\]")
    self.check("cross_val_mean linear", CrossValidation.cross_val_mean(LinearRegression.new, cvx, cvy, 5), 1)
    ckx = [[1, 1], [2, 2], [3, 3], [6, 6], [7, 7], [8, 8]]
    cky = [0, 0, 0, 1, 1, 1]
    self.check("cross_val knn", CrossValidation.cross_val_score(KNNClassifier.new(1), ckx, cky, 3), "\[1, 1, 1\]")
    self.check("cross_val nil mismatch", CrossValidation.cross_val_score(LinearRegression.new, [1, 2, 3], [1, 2]) == nil, true)
    # unsupervised CV: no y; interleaved two-square data, both folds -5
    ukx = [[0, 0], [10, 10], [0, 1], [10, 11], [1, 0], [11, 10], [1, 1], [11, 11]]
    self.check("cross_val unsupervised", CrossValidation.cross_val_score(KMeans.new(2), ukx, nil, 2), "\[-5, -5\]")
    self.check("cross_val supervised needs y", CrossValidation.cross_val_score(LinearRegression.new, cvx, nil, 5) == nil, true)

    # --- GridSearch (hyperparameter search by cross-validated score) ---
    # Two tight clusters: k = 1 / 3 score 1 on every fold, k = 5 scores 0.
    # k = 1 is listed LAST, so electing it proves scores are compared.
    gkx = [0, 1, 2, 3, 10, 11, 12, 13]
    gky = [0, 0, 0, 0, 1, 1, 1, 1]
    gs = GridSearch.new(KNNClassifier.new, { k: [5, 1] }, 4)
    self.check("gridsearch size", gs.size, 2)
    self.check("gridsearch fit self", gs.fit(gkx, gky) != nil, true)
    self.check("gridsearch best k", gs.best_params[:k], 1)
    self.check("gridsearch best score", gs.best_score, 1)
    self.check("gridsearch rank1", gs.results[0][:params][:k], 1)
    self.check("gridsearch rank2 score", gs.results[1][:score], 0)
    self.check("gridsearch refit fitted", gs.best_estimator.fitted?, true)
    self.check("gridsearch predict", gs.predict([0, 13]), "\[0, 1\]")
    # candidate order is a pure function of the grid: keys sorted by name,
    # last key varying fastest
    gcands = GridSearch.candidates({ b: [1, 2], a: [3, 4] })
    self.check("gridsearch product size", gcands.size, 4)
    self.check("gridsearch product order", gcands[1][:a].to_s + "/" + gcands[1][:b].to_s, "3/2")
    self.check("gridsearch key order", GridSearch.grid_keys({ zebra: 1, alpha: 2 }).join(","), "alpha,zebra")
    # ties break to the first candidate enumerated: reversing the list
    # reverses the winner
    gtie = GridSearch.new(KNNClassifier.new, { k: [3, 1, 5] }, 4)
    gtie.fit(gkx, gky)
    self.check("gridsearch tie break", gtie.best_params[:k], 3)
    # unsupervised search, no y at all
    gum = GridSearch.new(KMeans.new(2), { k: [1, 2] }, 2)
    gum.fit(ukx)
    self.check("gridsearch unsupervised", gum.best_params[:k], 2)
    self.check("gridsearch unsupervised score", gum.best_score, -5)
    # degenerate: unknown param, empty grid, misaligned inputs -> nil
    self.check("gridsearch unknown param nil", GridSearch.new(KNNClassifier.new, { bogus: [1] }, 4).fit(gkx, gky) == nil, true)
    self.check("gridsearch empty grid nil", GridSearch.new(KNNClassifier.new, {}, 4).fit(gkx, gky) == nil, true)
    self.check("gridsearch misaligned nil", GridSearch.new(KNNClassifier.new, { k: [1] }, 4).fit(gkx, [0, 1]) == nil, true)

    # --- KMeans (unsupervised: Lloyd's algorithm) ---
    # Two 2x2 boxes; default init = first two distinct rows. Converges in
    # two iterations to centroids [[1,1],[11,11]], labels [0,0,0,0,1,1,1,1],
    # inertia exactly 16 (each point sqrt(2) from its centroid).
    kmx = [[0, 0], [2, 0], [0, 2], [2, 2], [10, 10], [12, 10], [10, 12], [12, 12]]
    km = KMeans.new(2)
    self.check("kmeans fit self", km.fit(kmx) != nil, true)
    self.check("kmeans fitted?", km.fitted?, true)
    self.check("kmeans labels", km.labels, "\[0, 0, 0, 0, 1, 1, 1, 1\]")
    self.check("kmeans centroids", km.centroids, "\[\[1, 1\], \[11, 11\]\]")
    self.check("kmeans inertia", km.inertia, 16)
    self.check("kmeans n_iter", km.n_iter, 2)
    self.check("kmeans predict", km.predict([[1, 1], [11, 11], [0, 0]]), "\[0, 1, 0\]")
    self.check("kmeans score neg inertia", km.score(kmx), "-16")
    self.check("kmeans fit_predict", KMeans.new(2).fit_predict(kmx), "\[0, 0, 0, 0, 1, 1, 1, 1\]")
    self.check("kmeans k=1 global mean", KMeans.new(1).fit_predict(kmx), "\[0, 0, 0, 0, 0, 0, 0, 0\]")
    self.check("kmeans default k", KMeans.new.k, 8)
    # A seed makes the clustering reproducible on both engines.
    kseed = KMeans.new(2, 42)
    kseed.fit(kmx)
    self.check("kmeans seed inertia", kseed.inertia, 16)
    self.check("kmeans k>n nil", KMeans.new(9).fit([[1, 1], [2, 2]]) == nil, true)
    self.check("kmeans empty nil", KMeans.new(2).fit([]) == nil, true)
    self.check("kmeans nil before fit", KMeans.new(2).predict([[1, 1]]) == nil, true)

    # --- Multiclass metrics (ConfusionMatrix / ClassificationReport) ---
    cpred = [0, 1, 2, 2, 2, 0]
    cact = [0, 0, 2, 2, 1, 0]
    cm = Metrics.confusion_matrix(cpred, cact)
    self.check("confusion labels", cm.labels.join(","), "0,2,1")
    self.check("confusion matrix", cm.matrix, "\[\[2, 0, 1\], \[0, 2, 0\], \[0, 1, 0\]\]")
    self.check("confusion count 0,0", cm.count(0, 0), 2)
    self.check("confusion count 1,2", cm.count(1, 2), 1)
    self.check("confusion df cols", cm.to_df.column_names.join(","), "actual,0,2,1")
    rep = Metrics.classification_report(cpred, cact)
    self.check("report accuracy", rep.accuracy, "0.666667")
    self.check("report precision 0", rep.precision(0), "1")
    self.check("report recall 0", rep.recall(0), "0.666667")
    self.check("report f1 0", rep.f1(0), "0.8")
    self.check("report support 0", rep.support(0), 3)
    self.check("report f1 class1 zero", rep.f1(1), "0")
    self.check("report macro f1", rep.macro_f1, "0.533333")
    self.check("report weighted precision", rep.weighted_precision, "0.722222")
    self.check("report total", rep.total, 6)
    self.check("report unknown nil", rep.precision(99) == nil, true)
    self.check("report df labels", rep.to_df.column_values(:label).join(","), "0,2,1,accuracy,macro avg,weighted avg")
    # ROC analysis — scikit-learn roc_curve reference example (pos_label 2)
    rscores = [1.to_f / 10.to_f, 4.to_f / 10.to_f, 35.to_f / 100.to_f, 8.to_f / 10.to_f]
    ract = [1, 1, 2, 2]
    rc = Metrics.roc_curve(rscores, ract, 2)
    self.check("roc fpr", rc.fpr, "\[0, 0, 0.5, 0.5, 1\]")
    self.check("roc tpr", rc.tpr, "\[0, 0.5, 0.5, 1, 1\]")
    self.check("roc auc", rc.auc, "0.75")
    self.check("roc_auc scalar", Metrics.roc_auc(rscores, ract, 2), "0.75")
    # tied cross-class scores get half credit (Mann-Whitney) -> 0.875
    tscores = [8.to_f / 10.to_f, 6.to_f / 10.to_f, 6.to_f / 10.to_f, 3.to_f / 10.to_f]
    self.check("roc auc tie", Metrics.roc_auc(tscores, [1, 1, 0, 0]), "0.875")
    # extremes and the auc(x, y) trapezoid helper
    self.check("roc auc perfect", Metrics.roc_auc([1.to_f, 2.to_f, 8.to_f, 9.to_f], [0, 0, 1, 1]), "1")
    self.check("roc auc inverted", Metrics.roc_auc([9.to_f, 8.to_f, 2.to_f, 1.to_f], [0, 0, 1, 1]), "0")
    self.check("auc helper", Metrics.auc([0.to_f, 1.to_f], [0.to_f, 1.to_f]), "0.5")
    self.check("roc nil one class", Metrics.roc_auc([1.to_f, 9.to_f], [1, 1]) == nil, true)
    self.check("roc nil misaligned", Metrics.roc_curve([1.to_f, 9.to_f], [1]) == nil, true)
    # Log loss — binary cross-entropy, the objective LogisticRegression
    # minimizes (scikit-learn's log_loss); scores first, like roc_auc.
    llscores = [9.to_f / 10.to_f, 1.to_f / 10.to_f, 8.to_f / 10.to_f, 35.to_f / 100.to_f]
    self.check("log_loss reference", Metrics.log_loss(llscores, [1, 0, 1, 0]), "0.216162")
    coin = [5.to_f / 10.to_f, 5.to_f / 10.to_f, 5.to_f / 10.to_f, 5.to_f / 10.to_f]
    self.check("log_loss coin flip ln2", Metrics.log_loss(coin, [1, 0, 1, 0]), "0.693147")
    self.check("log_loss pos_label", Metrics.log_loss(rscores, ract, 2), "0.472288")
    self.check("log_loss single class", Metrics.log_loss([9.to_f / 10.to_f, 8.to_f / 10.to_f], [1, 1]), "0.164252")
    lltol = 1.to_f / 1000000.to_f
    self.check("log_loss perfect ~0", LinAlg.fabs(Metrics.log_loss([1.to_f, 0.to_f], [1, 0])) < lltol, true)
    self.check("log_loss nil misaligned", Metrics.log_loss([9.to_f / 10.to_f, 1.to_f / 10.to_f], [1]) == nil, true)
    self.check("log_loss nil empty", Metrics.log_loss([], []) == nil, true)
    # --- fbeta: f1 with a beta that weights recall (sklearn fbeta_score)
    # Same binary case as above: P = 0.5, R = 2/3.
    fpreds = [1, 1, 1, 0, 0, 1]
    fact = [1, 0, 0, 0, 1, 1]
    self.check("fbeta beta=2", Metrics.fbeta(fpreds, fact, 2), "0.625")
    self.check("fbeta beta=1/2", Metrics.fbeta(fpreds, fact, 1.to_f / 2.to_f), "0.526316")
    self.check("fbeta beta=1 is f1", Metrics.fbeta(fpreds, fact), Metrics.f1(fpreds, fact))
    self.check("fbeta beta=0 is precision", Metrics.fbeta(fpreds, fact, 0), Metrics.precision(fpreds, fact))
    self.check("fbeta pos_label 0", Metrics.fbeta(fpreds, fact, 2, 0), "0.357143")
    self.check("fbeta zero division", Metrics.fbeta([0, 0], [0, 0], 2), "0")
    # --- imbalanced-data scores: the majority-class classifier that
    # accuracy rates 0.8 and every honest metric rates chance-level.
    imb_act = [0, 0, 0, 0, 0, 0, 0, 0, 1, 1]
    imb_preds = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
    self.check("majority accuracy flatters", Metrics.accuracy(imb_preds, imb_act), "0.8")
    self.check("majority balanced_accuracy", Metrics.balanced_accuracy(imb_preds, imb_act), "0.5")
    self.check("majority mcc", Metrics.matthews_corrcoef(imb_preds, imb_act), "0")
    self.check("majority cohen_kappa", Metrics.cohen_kappa(imb_preds, imb_act), "0")
    # sklearn docstring examples, in koala's (predictions, actual) order
    self.check("mcc reference", Metrics.matthews_corrcoef([1, 0, 1, 1], [1, 1, 1, 0]), "-0.333333")
    self.check("mcc perfect", Metrics.matthews_corrcoef([0, 1, 0, 1], [0, 1, 0, 1]), "1")
    self.check("mcc inverted", Metrics.matthews_corrcoef([1, 0, 1, 0], [0, 1, 0, 1]), "-1")
    self.check("kappa reference", Metrics.cohen_kappa([0, 0, 2, 2, 0, 2], [2, 0, 2, 2, 0, 1]), "0.428571")
    self.check("kappa perfect", Metrics.cohen_kappa([0, 1, 0, 1], [0, 1, 0, 1]), "1")
    self.check("kappa antiperfect", Metrics.cohen_kappa([1, 0], [0, 1]), "-1")
    # multiclass — same 3-class case as the ConfusionMatrix block
    self.check("balanced_accuracy multiclass", Metrics.balanced_accuracy(cpred, cact), "0.555556")
    self.check("balanced_accuracy is macro recall", Metrics.balanced_accuracy(cpred, cact), rep.macro_recall)
    self.check("mcc multiclass", Metrics.matthews_corrcoef(cpred, cact), "0.5")
    self.check("kappa multiclass", Metrics.cohen_kappa(cpred, cact), "0.478261")
    # degenerate: one class on both sides -> 0, never nan; nil for unusable input
    self.check("mcc one class", Metrics.matthews_corrcoef([1, 1], [1, 1]), "0")
    self.check("kappa one class", Metrics.cohen_kappa([1, 1], [1, 1]), "0")
    self.check("balanced_accuracy skips absent class", Metrics.balanced_accuracy([1, 0], [1, 1]), "0.5")
    self.check("balanced_accuracy nil misaligned", Metrics.balanced_accuracy([1], [1, 0]) == nil, true)
    self.check("mcc nil empty", Metrics.matthews_corrcoef([], []) == nil, true)
    self.check("kappa nil misaligned", Metrics.cohen_kappa([1], [1, 0]) == nil, true)
    # --- micro averages: pooled TP/FP/FN, equal to accuracy for
    # single-label multiclass (sklearn average="micro")
    self.check("micro counts", rep.micro_counts.join(","), "4,2,2")
    self.check("micro precision", rep.micro_precision, "0.666667")
    self.check("micro recall equals precision", rep.micro_recall, rep.micro_precision)
    self.check("micro f1 equals accuracy", rep.micro_f1, rep.accuracy)
    # --- precision-recall curve / average precision (sklearn reference:
    # y_true [0,0,1,1], scores [0.1,0.4,0.35,0.8] -> AP 0.8333333333333333)
    prc = Metrics.precision_recall_curve(rscores, [0, 0, 1, 1])
    self.check("pr precision", prc.precision.join(","), "0.5,0.666667,0.5,1,1")
    self.check("pr recall", prc.recall.join(","), "1,1,0.5,0.5,0")
    self.check("pr thresholds ascending", prc.thresholds.join(","), "0.1,0.35,0.4,0.8")
    self.check("pr curve one longer", prc.precision.size, prc.thresholds.size + 1)
    self.check("average_precision", prc.average_precision, "0.833333")
    self.check("average_precision scalar", Metrics.average_precision(rscores, [0, 0, 1, 1]), "0.833333")
    self.check("average_precision pos_label", Metrics.average_precision(rscores, ract, 2), "0.833333")
    # one positive of ten, ranked 2nd: ROC hides the false positive, AP does not
    ap_scores = [90.to_f, 80.to_f, 70.to_f, 60.to_f, 50.to_f, 40.to_f, 30.to_f, 20.to_f, 10.to_f, 5.to_f]
    ap_act = [0, 1, 0, 0, 0, 0, 0, 0, 0, 0]
    self.check("imbalanced roc_auc", Metrics.roc_auc(ap_scores, ap_act), "0.888889")
    self.check("imbalanced average_precision", Metrics.average_precision(ap_scores, ap_act), "0.5")
    self.check("ap perfect", Metrics.average_precision([1.to_f, 2.to_f, 8.to_f, 9.to_f], [0, 0, 1, 1]), "1")
    self.check("ap inverted", Metrics.average_precision([9.to_f, 8.to_f, 2.to_f, 1.to_f], [0, 0, 1, 1]), "0.416667")
    self.check("ap all tied is positive rate", Metrics.average_precision([5.to_f, 5.to_f, 5.to_f, 5.to_f], [0, 0, 1, 1]), "0.5")
    # a single class is fine here, where roc_curve is nil
    one_class = [9.to_f / 10.to_f, 8.to_f / 10.to_f]
    self.check("pr all positive", Metrics.precision_recall_curve(one_class, [1, 1]).recall.join(","), "1,0.5,0")
    self.check("ap all positive", Metrics.average_precision(one_class, [1, 1]), "1")
    self.check("pr no positive", Metrics.precision_recall_curve(one_class, [0, 0]).precision.join(","), "0,0,1")
    self.check("ap no positive", Metrics.average_precision(one_class, [0, 0]), "0")
    self.check("pr nil misaligned", Metrics.precision_recall_curve([1.to_f], [1, 0]) == nil, true)
    self.check("ap nil empty", Metrics.average_precision([], []) == nil, true)
    # --- brier score: bounded calibration, log_loss's gentle sibling
    bscores = [1.to_f / 10.to_f, 9.to_f / 10.to_f, 8.to_f / 10.to_f, 3.to_f / 10.to_f]
    self.check("brier reference", Metrics.brier_score(bscores, [0, 1, 1, 0]), "0.0375")
    self.check("brier perfect", Metrics.brier_score([1.to_f, 0.to_f], [1, 0]), "0")
    self.check("brier coin flip", Metrics.brier_score([5.to_f / 10.to_f, 5.to_f / 10.to_f], [1, 0]), "0.25")
    self.check("brier worst", Metrics.brier_score([0.to_f, 1.to_f], [1, 0]), "1")
    self.check("brier pos_label", Metrics.brier_score(rscores, ract, 2), "0.158125")
    # identical ranking (roc_auc 1 both), very different calibration
    confident = [99.to_f / 100.to_f, 98.to_f / 100.to_f, 2.to_f / 100.to_f, 1.to_f / 100.to_f]
    timid = [6.to_f / 10.to_f, 55.to_f / 100.to_f, 45.to_f / 100.to_f, 4.to_f / 10.to_f]
    self.check("brier confident", Metrics.brier_score(confident, [1, 1, 0, 0]), "0.00025")
    self.check("brier timid", Metrics.brier_score(timid, [1, 1, 0, 0]), "0.18125")
    self.check("brier ranks tie on auc", Metrics.roc_auc(confident, [1, 1, 0, 0]), Metrics.roc_auc(timid, [1, 1, 0, 0]))
    self.check("brier nil misaligned", Metrics.brier_score([1.to_f], [1, 0]) == nil, true)
    self.check("brier nil empty", Metrics.brier_score([], []) == nil, true)
    # --- silhouette score: koala's first unsupervised metric
    sil_x = [[0, 0], [0, 1], [10, 0], [10, 1]]
    self.check("silhouette separated", Metrics.silhouette_score(sil_x, [0, 0, 1, 1]), "0.900249")
    self.check("silhouette mislabeled negative", Metrics.silhouette_score(sil_x, [0, 1, 0, 1]), "-0.447506")
    self.check("silhouette 3 clusters", Metrics.silhouette_score([[1], [2], [8], [9], [20], [21]], [0, 0, 1, 1, 2, 2]), "0.876447")
    self.check("silhouette flat rows", Metrics.silhouette_score([1, 2, 8, 9, 20, 21], [0, 0, 1, 1, 2, 2]), "0.876447")
    self.check("silhouette string labels", Metrics.silhouette_score([0, 1, 10, 11], ["a", "a", "b", "b"]), "0.899749")
    self.check("silhouette singleton scores 0", Metrics.silhouette_score([0, 1, 10], [0, 0, 1]), "0.596296")
    km_x = [[0, 0], [2, 0], [0, 2], [2, 2], [10, 10], [12, 10], [10, 12], [12, 12]]
    km = KMeans.new(2)
    km.fit(km_x)
    self.check("silhouette scores a KMeans fit", Metrics.silhouette_score(km_x, km.labels), "0.839049")
    self.check("silhouette ranks the right split higher", Metrics.silhouette_score(km_x, km.labels) > Metrics.silhouette_score(km_x, [0, 1, 0, 1, 0, 1, 0, 1]), true)
    self.check("silhouette nil one cluster", Metrics.silhouette_score([0, 1, 2], [0, 0, 0]) == nil, true)
    self.check("silhouette nil all singletons", Metrics.silhouette_score([0, 1, 2], [0, 1, 2]) == nil, true)
    self.check("silhouette nil misaligned", Metrics.silhouette_score([0, 1], [0]) == nil, true)
    self.check("silhouette nil empty", Metrics.silhouette_score([], []) == nil, true)

    # --- sample weights: the framework-free mirror of
    #     spec/sample_weight_spec.w. The property that matters is that an
    #     INTEGER weight vector is indistinguishable from duplicating each
    #     row that many times, so each estimator below is checked against
    #     its own duplicated dataset.
    self.check("weights nil for wrong length", Estimator.weight_values([1, 1], 3) == nil, true)
    self.check("weights nil for negative", Estimator.weight_values([1, 0 - 1, 1], 3) == nil, true)
    self.check("weights nil for empty", Estimator.weight_values([], 3) == nil, true)
    self.check("weights nil for all-zero", Estimator.weight_values([0, 0, 0], 3) == nil, true)
    self.check("weights keep a single zero", Estimator.weight_values([0, 1, 2], 3).join(","), "0,1,2")
    self.check("weight total falls back to the count", Estimator.weight_total(nil, 4), 4)
    self.check("weighted accuracy", Metrics.accuracy([1, 0, 1], [1, 0, 0], [2, 1, 1]), "0.75")
    self.check("weighted mse", Metrics.mse([1, 2, 3], [1, 2, 4], [2, 1, 1]), "0.25")
    self.check("weighted r2 weights its baseline", Metrics.r2([1, 2, 3], [1, 2, 4], [2, 1, 1]), "0.833333")
    self.check("weighted precision", Metrics.precision([1, 0, 1], [1, 1, 0], 1, [1, 3, 1]), "0.5")
    self.check("weighted recall", Metrics.recall([1, 0, 1], [1, 1, 0], 1, [1, 3, 1]), "0.25")
    self.check("metric nil for bad weights", Metrics.accuracy([1, 0], [1, 0], [1, 1, 1]) == nil, true)

    sw_x = [[0], [1], [2], [3]]
    sw_y = [0, 1, 2, 5]
    sw_dup_x = [[0], [0], [1], [2], [3]]
    sw_dup_y = [0, 0, 1, 2, 5]
    sw_w = LinearRegression.new
    sw_w.fit(sw_x, sw_y, [2, 1, 1, 1])
    sw_d = LinearRegression.new
    sw_d.fit(sw_dup_x, sw_dup_y)
    self.check("WLS == duplication (slope)", LinAlg.fabs(sw_w.coefficients[0] - sw_d.coefficients[0]) < 1.to_f / 1000000000.to_f, true)
    self.check("WLS == duplication (intercept)", LinAlg.fabs(sw_w.intercept - sw_d.intercept) < 1.to_f / 1000000000.to_f, true)
    sw_ones = LinearRegression.new
    sw_ones.fit(sw_x, sw_y, [1, 1, 1, 1])
    sw_plain = LinearRegression.new
    sw_plain.fit(sw_x, sw_y)
    self.check("all-1s weights are a no-op", sw_ones.coefficients, sw_plain.coefficients.to_s)
    self.check("bad weights leave fit nil", LinearRegression.new.fit(sw_x, sw_y, [1, 1]) == nil, true)

    # a leaf takes the HEAVIEST class, not the most numerous
    sw_tree = DecisionTreeClassifier.new(0)
    sw_tree.fit([[0], [1], [2]], [:a, :b, :b], [3, 1, 1])
    self.check("weighted leaf takes the heaviest class", sw_tree.predict([[0]]).join(","), "a")
    self.check("weighted leaf proba over total weight", sw_tree.predict_proba([[0]], :a).join(","), "0.6")

    # a regressor leaf predicts the weighted mean; k-means the weighted centroid
    sw_reg = DecisionTreeRegressor.new(0)
    sw_reg.fit([[0], [1]], [1, 5], [3, 1])
    self.check("weighted leaf mean", sw_reg.predict([[0]]).join(","), "2")
    sw_km = KMeans.new(1)
    sw_km.fit([[0], [10]], [3, 1])
    self.check("weighted centroid", sw_km.centroids[0][0], "2.5")
    self.check("weighted inertia", sw_km.inertia, "75")

    # GaussianNB reports class_counts as total WEIGHT
    sw_nb = GaussianNB.new
    sw_nb.fit([[1], [2], [8], [9]], [:lo, :lo, :hi, :hi], [3, 1, 1, 1])
    self.check("weighted class counts", sw_nb.class_counts.join(","), "4,2")

    # KNNClassifier refuses weights outright — never a silently unweighted fit
    self.check("knn declines weights", KNNClassifier.new(1).supports_sample_weight?, false)
    self.check("knn fit nil with weights", KNNClassifier.new(1).fit(sw_x, sw_y, [1, 1, 1, 1]) == nil, true)
    self.check("linreg accepts weights", LinearRegression.new.supports_sample_weight?, true)

    # cross-validation subsets them per fold
    sw_cv = CrossValidation.cross_val_score(LinearRegression.new, sw_x, sw_y, 2, nil, [2, 1, 1, 1])
    self.check("cv threads weights", sw_cv.size, 2)
    self.check("cv nil for bad weights", CrossValidation.cross_val_score(LinearRegression.new, sw_x, sw_y, 2, nil, [1, 1]) == nil, true)
    self.check("cv nil folds when the estimator refuses", CrossValidation.cross_val_mean(KNNClassifier.new(1), sw_x, sw_y, 2, nil, [2, 1, 1, 1]) == nil, true)

t = KoalaSmoke.new
t.run
if t.failures > 0
  << "KOALA SMOKE: FAIL ([t.failures] of [t.checks] checks)"
  exit(1)
<< "KOALA SMOKE: PASS ([t.checks] checks)"
