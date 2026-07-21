# GaussianNB — Gaussian naive Bayes (pure Tungsten, CPU-only; koala's
# GENERATIVE probabilistic classifier — the third kind of supervised
# learner beside KNNClassifier's lazy/instance-based classification and
# LogisticRegression's discriminative/iterative one: fit / predict /
# predict_proba / score with per-instance fitted state, sklearn-style)
#
#     model = GaussianNB.new     # var_smoothing = 1e-9 (sklearn's default)
#     model.fit(x, y)            # self when fitted, nil when unfittable
#     model.classes              # distinct labels, first-seen order
#     model.class_counts         # rows per class (sklearn class_count_)
#     model.class_priors         # P(class), counts / n (class_prior_)
#     model.means                # per-class per-feature means (theta_)
#     model.variances            # per-class per-feature variances (var_)
#     model.epsilon              # the smoothing added to every variance
#     model.joint_log_likelihood(x)   # per-row [log P(c) + log p(x|c)] per class
#     model.predict_proba(x)          # per-row per-class posteriors, rows sum to 1
#     model.predict_proba(x, label)   # flat P(label) column, for ROC / log_loss
#     model.predict(x)                # array of predicted labels
#     model.score(x, y)               # accuracy of predict(x) against y
#
# Unlike KNNClassifier (which stores the training set and defers all work
# to predict) and LogisticRegression (which iterates gradient descent to a
# decision boundary), GaussianNB models how the data was GENERATED: it
# assumes the features are conditionally independent given the class and
# that each is normally distributed, so fitting is CLOSED FORM — one pass
# for per-class per-feature means and variances plus the class priors. No
# iteration, no learning rate, no seed: the fit is exactly determinate and
# byte-identical on both engines.
#
# Classification is Bayes' rule in log space. For a row x and class c the
# joint log likelihood is (scikit-learn's _joint_log_likelihood):
#
#     jll(c) = log P(c)
#              - 0.5 * sum_j log(2*pi*var[c][j])
#              - 0.5 * sum_j (x[j] - mean[c][j])^2 / var[c][j]
#
# predict takes the argmax over classes; predict_proba normalizes the row
# through a max-shifted softmax (exp(jll - logsumexp(jll)), the overflow-safe
# form), so the posteriors sum to 1 and the shared -0.5*sum_j log(2*pi)
# constant cancels.
#
# VARIANCE SMOOTHING. A feature that never varies inside a class has
# variance 0, which would divide by zero. Following scikit-learn, every
# variance gets epsilon = var_smoothing * (largest per-feature POPULATION
# variance across all training rows) added to it; with the default
# var_smoothing = 1e-9 that is a ~1e-9 relative nudge, invisible at
# printing precision but enough to keep the Gaussian proper. Variances are
# population (n denominator) variances, matching numpy's np.var default —
# NOT Stats.var, which is the sample (n-1) variance. koala adds one thing
# scikit-learn does not: when EVERY feature is constant the reference
# epsilon is itself 0 and sklearn yields nan, so epsilon falls back to
# var_smoothing and the model stays finite (every class ties, and predict
# returns the first-seen label).
#
# Labels are opaque and MULTICLASS — integers, strings, or symbols, any
# number of them — collected in first-seen order (Array#sort is not
# portable across engines; the Encoder / ConfusionMatrix / LogisticRegression
# convention, where scikit-learn sorts instead). predict returns those
# original labels, so a GaussianNB feeds straight into Metrics.accuracy and
# Metrics.classification_report, and predict_proba(x, label) hands a single
# class's posterior column to Metrics.roc_auc / Metrics.log_loss. An argmax
# tie breaks to the first-seen class.
#
# Accepted shapes are exactly LinearRegression's, coerced through the same
# LinearRegression.feature_rows / .target_values (one definition of every
# accepted input shape): x is a DataFrame (numeric columns only), a Matrix,
# an array of row arrays, or a flat single-feature array; y is a Series, a
# Vector, or a plain array of labels. nil cells are NOT handled — run an
# Imputer first. An empty x, a ragged x, or a y whose size mismatches makes
# fit return nil and fitted? stay false; joint_log_likelihood /
# predict_proba / predict / score return nil before a successful fit and
# when a query row's width differs from the fitted feature count, and
# predict_proba returns nil for a label the fit never saw.
#
# NOTE: locals are hoisted from ivars before any `-> (x)` block — the
# interpreter cannot resolve @ivars from a block body — and methods
# containing closures avoid early `return` (see stats.w). Every float
# derives from the data via .to_f with ONE exception: 2*pi, which has no
# integer derivation (Math.atan here is a low-precision polynomial, so
# 4*atan(1) is off by ~1e-5). It is written once, in .two_pi, using `~` —
# Tungsten's explicit f64 literal, the form core/math.w and core/stats.w
# use for the same constant — and is byte-identical on both engines.
+ GaussianNB
  ro :classes        # distinct labels, first-seen order; nil before fit
  ro :class_counts   # rows per class; nil before fit
  ro :class_priors   # P(class) = count / n; nil before fit
  ro :means          # per-class per-feature means; nil before fit
  ro :variances      # per-class per-feature variances (epsilon added); nil before
  ro :epsilon        # the smoothing added to every variance; nil before fit
  ro :var_smoothing  # epsilon's multiplier on the largest column variance

  -> new(var_smoothing = nil)
    vs = var_smoothing
    vs = 1.to_f / 1000000000.to_f if vs == nil
    @var_smoothing = vs
    @fitted = false
    @classes = nil
    @class_counts = nil
    @class_priors = nil
    @means = nil
    @variances = nil
    @epsilon = nil

  -> fitted?
    @fitted

  # 2*pi as an f64 — the bit's single float literal (see the header note).
  -> .two_pi
    ~6.283185307179586

  # Population mean of every column of rows (nf columns).
  -> .column_means(rows, nf)
    nd = rows.size.to_f
    out = []
    nf.times -> (j)
      total = 0.to_f
      rows.each -> (r)
        total += r[j].to_f
      out.push(total / nd)
    out

  # Population (n denominator) variance of every column about means, with
  # eps added to each — numpy's np.var plus scikit-learn's epsilon_.
  -> .column_vars(rows, means, nf, eps)
    nd = rows.size.to_f
    out = []
    nf.times -> (j)
      m = means[j]
      total = 0.to_f
      rows.each -> (r)
        d = r[j].to_f - m
        total += d * d
      out.push(total / nd + eps)
    out

  # The largest per-feature population variance over all rows — the base
  # of epsilon (scikit-learn's np.var(X, axis=0).max()).
  -> .max_column_var(rows, nf)
    zero = 0.to_f
    cvars = GaussianNB.column_vars(rows, GaussianNB.column_means(rows, nf), nf, zero)
    best = zero
    cvars.each -> (v)
      best = v if v > best
    best

  # Index of label in classes, or -1 when the fit never saw it.
  -> .label_index(classes, label)
    idx = -1
    i = 0
    classes.each -> (c)
      idx = i if idx < 0 && c == label
      i += 1
    idx

  # Joint log likelihood of one row under every class (Bayes' rule in log
  # space; see the header formula).
  -> .row_jll(row, priors, means, variances)
    half = 1.to_f / 2.to_f
    tp = GaussianNB.two_pi
    out = []
    k = priors.size
    k.times -> (c)
      m = means[c]
      s = variances[c]
      nf = m.size
      logsum = 0.to_f
      sqsum = 0.to_f
      nf.times -> (j)
        d = row[j].to_f - m[j]
        logsum += Math.log(tp * s[j])
        sqsum += d * d / s[j]
      out.push(Math.log(priors[c]) - half * logsum - half * sqsum)
    out

  # row_jll over many rows.
  -> .jll_rows(rows, priors, means, variances)
    out = []
    rows.each -> (r)
      out.push(GaussianNB.row_jll(r, priors, means, variances))
    out

  # Max-shifted softmax of one row of scores: exp(s - max) normalized, the
  # overflow-safe exp(jll - logsumexp(jll)). Sums to 1.
  -> .softmax(scores)
    top = scores[0]
    scores.each -> (v)
      top = v if v > top
    total = 0.to_f
    ex = []
    scores.each -> (v)
      e = Math.exp(v - top)
      ex.push(e)
      total += e
    out = []
    ex.each -> (e)
      out.push(e / total)
    out

  # Learn class priors, per-class per-feature means and (smoothed)
  # variances from x/y in one closed-form pass. Returns self, or nil —
  # fitted? stays false — when the shapes are unusable (empty x, ragged
  # rows, y size mismatch).
  -> fit(x, y)
    rows = LinearRegression.feature_rows(x)
    labels = LinearRegression.target_values(y)
    ok = rows != nil && labels != nil
    ok = rows.size > 0 && rows.size == labels.size if ok
    ok = rows[0].size > 0 if ok
    if ok
      width = rows[0].size
      rows.each -> (r)
        ok = false if r.size != width
    out = nil
    if ok
      nf = rows[0].size
      nd = rows.size.to_f
      eps = @var_smoothing * GaussianNB.max_column_var(rows, nf)
      eps = @var_smoothing if eps <= 0.to_f
      classes = []
      labels.each -> (l)
        classes.push(l) if !classes.include?(l)
      counts = []
      priors = []
      mus = []
      sigmas = []
      classes.each -> (c)
        crows = []
        i = 0
        labels.each -> (l)
          crows.push(rows[i]) if l == c
          i += 1
        cn = crows.size
        counts.push(cn)
        priors.push(cn.to_f / nd)
        m = GaussianNB.column_means(crows, nf)
        mus.push(m)
        sigmas.push(GaussianNB.column_vars(crows, m, nf, eps))
      @classes = classes
      @class_counts = counts
      @class_priors = priors
      @means = mus
      @variances = sigmas
      @epsilon = eps
      @fitted = true
      out = self
    out

  # x coerced to feature rows, or nil before fit and on a width mismatch.
  -> query_rows(x)
    rows = nil
    rows = LinearRegression.feature_rows(x) if @fitted
    out = nil
    if rows != nil
      nf = @means[0].size
      ok = true
      rows.each -> (r)
        ok = false if r.size != nf
      out = rows if ok
    out

  # Per-row array of per-class joint log likelihoods, classes in `classes`
  # order (scikit-learn's _joint_log_likelihood). nil before fit or on a
  # width mismatch.
  -> joint_log_likelihood(x)
    rows = self.query_rows(x)
    out = nil
    out = GaussianNB.jll_rows(rows, @class_priors, @means, @variances) if rows != nil
    out

  # Posterior probabilities. With no label: one array per row, one entry
  # per class in `classes` order, summing to 1. With a label: the flat
  # P(label) column, ready for Metrics.roc_auc / Metrics.log_loss. nil
  # before fit, on a width mismatch, or for a label the fit never saw.
  -> predict_proba(x, pos_label = nil)
    jll = self.joint_log_likelihood(x)
    out = nil
    if jll != nil
      probs = []
      jll.each -> (s)
        probs.push(GaussianNB.softmax(s))
      if pos_label == nil
        out = probs
      else
        idx = GaussianNB.label_index(@classes, pos_label)
        if idx >= 0
          col = []
          probs.each -> (p)
            col.push(p[idx])
          out = col
    out

  # Predicted labels for x: the class with the highest joint log
  # likelihood, ties breaking to the first-seen class. nil before fit or
  # on a width mismatch.
  -> predict(x)
    jll = self.joint_log_likelihood(x)
    out = nil
    if jll != nil
      classes = @classes
      preds = []
      jll.each -> (s)
        best = 0
        k = s.size
        k.times -> (c)
          best = c if s[c] > s[best]
        preds.push(classes[best])
      out = preds
    out

  # Accuracy (Metrics.accuracy) of self's predictions on x against y; nil
  # before fit or when the shapes do not line up.
  -> score(x, y)
    preds = self.predict(x)
    yvals = LinearRegression.target_values(y)
    out = nil
    if preds != nil && yvals != nil
      out = Metrics.accuracy(preds, yvals) if preds.size == yvals.size && preds.size > 0
    out
