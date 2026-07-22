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

use koala

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
    if g == w
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

t = KoalaSmoke.new
t.run
if t.failures > 0
  << "KOALA SMOKE: FAIL ([t.failures] of [t.checks] checks)"
  exit(1)
<< "KOALA SMOKE: PASS ([t.checks] checks)"
