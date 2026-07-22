# PCA — principal component analysis, koala's dimensionality reduction
# (pure Tungsten, CPU-only; a TRANSFORMER, so it slots into a Pipeline
# ahead of any estimator).
#
#     pca = PCA.new(2)                 # keep the top 2 directions
#     out = pca.fit_transform(df)      # a DataFrame of pc0, pc1
#     pca.explained_variance_ratio     # Vector — how much each explains
#     pca.inverse_transform(out)       # back to the original coordinates
#
# fit mean-centres the data and extracts the top-k orthonormal directions
# of greatest variance; transform projects rows onto them. INPUT is a
# DataFrame, or anything Estimator.frame accepts — a Matrix, an array of
# row arrays, or a flat single-feature array, whose columns are then
# named x0, x1, … positionally. NON-NUMERIC columns are dropped (PCA is
# arithmetic on the features), and OUTPUT is always a DataFrame whose
# columns are pc0, pc1, … in descending order of explained variance.
#
# transform before fit returns nil, and so does every learned accessor —
# the bit's shape-error convention, never a raise.
#
# --- The algorithm: ONE-SIDED JACOBI, and why not the covariance ---
#
# The textbook PCA is "form the p×p covariance matrix C = X_c^T X_c /
# (n-1), then eigendecompose it". That is the SAME TRAP the Householder
# least-squares work escaped in lib/linalg.w: forming X^T X squares the
# condition number, so a design with cond(X) = 1e6 hands the
# eigensolver a matrix with cond = 1e12 and burns twelve of f64's
# ~sixteen digits BEFORE the first rotation. The damage lands exactly
# where PCA is most often used — on the small trailing components,
# whose true variances are the ones nearest the noise floor. So the
# covariance route is not taken here.
#
# Instead the ORTHOGONALIZATION IS APPLIED TO X_c ITSELF: one-sided
# Jacobi, which is the SVD X_c = U S V^T computed by sweeping plane
# rotations across PAIRS of COLUMNS until every pair is orthogonal.
# A pair (i, j) needs alpha = |x_i|², beta = |x_j|², gamma = x_i·x_j to
# choose its rotation angle — three entries of the Gram matrix — but the
# rotation is then applied to the COLUMNS OF X_c, never to a formed
# X_c^T X_c, and the singular values come out at the end as the column
# NORMS of the converged matrix. Squaring happens only inside the choice
# of an angle (where a relative error of 1e-16 in gamma perturbs the
# angle, not the answer's magnitude); it never touches the quantities
# that are reported. This is the classical high-relative-accuracy SVD
# (Demmel & Veselić): one-sided Jacobi computes every singular value to
# high RELATIVE accuracy, including the tiny ones, which is precisely the
# property a covariance eigensolver throws away.
#
# THAT IS MEASURED, NOT ASSERTED. spec/pca_spec.w fits a 2-feature design
# whose two variances are 18 decades apart (20/3 and 8e-18/3): forming
# the covariance rounds 10 + 4e-18 back to 10, so the textbook route
# reports the small variance as EXACTLY ZERO, while one-sided Jacobi on
# the same f64 data recovers it to a relative error of 2.4e-8 — eight
# correct digits against none. Both engines agree.
#
# WHY NOT the QR that lib/linalg.w now has: LinAlg.qr is a single
# Householder triangularization, which is one STEP of an eigenvalue
# iteration, not the iteration itself — a QR-algorithm eigensolver would
# still have to run on a symmetric matrix, i.e. on the covariance, and
# LinAlg.qr additionally returns nil for a rank-deficient input (it does
# not pivot). PCA must SURVIVE rank deficiency, not refuse it: a constant
# column, a duplicated feature and a rank-1 cloud are all ordinary
# inputs, and all three make QR return nil. Jacobi handles them without a
# special case — a dependent column simply converges to a zero norm — and
# V stays EXACTLY orthogonal whatever the rank, because it is built as a
# product of plane rotations applied to the identity. That is the same
# argument that chose Householder over Gram-Schmidt in linalg.w, made
# once more.
#
# COST is O(sweeps × n × p²) — a handful of sweeps in practice (the
# convergence is quadratic once the pairs are nearly orthogonal), with
# the sweep count bounded by .max_sweeps so no input can spin forever.
# For the small-to-medium frames koala handles this is cheaper than
# forming the covariance and iterating on it, and it is a great deal
# shorter to read.
#
# --- Sign convention (a DETERMINISM requirement, not a preference) ---
#
# An eigenvector is only defined up to sign: -v spans the same axis as v
# and explains the same variance. Left unpinned, the sign falls out of
# whatever rounding the rotations happened to produce, so results differ
# run to run and engine to engine. koala pins it:
#
#   EVERY COMPONENT IS NEGATED, IF NEEDED, SO THAT ITS LARGEST-MAGNITUDE
#   LOADING IS POSITIVE; ties in magnitude break to the LOWEST FEATURE
#   INDEX.
#
# The rule is total (a unit vector always has a largest entry), cheap,
# and stated on the FEATURE side, so it depends only on `components` —
# not on the sample order, which means a re-fit on shuffled rows keeps
# the same signs. (scikit-learn pins the sign on the SCORES side instead,
# via svd_flip on U; the two conventions agree on most data and are exact
# negations of each other where they differ. spec/pca_spec.w compares
# against scikit-learn's numbers with koala's rule applied, and says so.)
#
# --- Explained variance ---
#
# `explained_variance` is sigma²/(n-1) — the SAMPLE variance along each
# component, the same n-1 denominator Stats.var and scikit-learn use, so
# an axis-aligned dataset reports exactly its own column variances.
# `explained_variance_ratio` divides by the TOTAL variance over ALL
# min(n, p) components (equivalently the trace of the covariance, i.e.
# the sum of the per-feature variances), NOT by the retained ones. So the
# ratios of a full-rank fit sum to 1 and a truncated fit reports the
# fraction of the ORIGINAL variance it kept — again scikit-learn's
# definition. An all-constant dataset has zero total variance; its ratios
# are all 0.0 rather than a division by zero.
#
# --- whiten ---
#
# `whiten = true` divides each score column by sqrt(explained_variance),
# so the output has unit variance on every component and the correlation
# structure is gone — what a downstream estimator that assumes isotropic
# features wants. inverse_transform undoes it exactly. A component with
# zero variance is left alone (its scores are already 0), so whitening
# never divides by zero.
#
# --- Degenerate input: nil, never a raise ---
#
# fit returns nil (and fitted? stays false) when:
#   * x is nil, empty, or has no numeric column;
#   * any kept cell is nil or non-numeric — run an Imputer first;
#   * there are fewer than 2 rows (a sample variance needs two);
#   * n_components is <= 0, or LARGER than min(n_samples, n_features) —
#     there are not that many components to find, and koala answers a
#     shape request it cannot meet with nil rather than by silently
#     giving back fewer than asked (scikit-learn raises here).
# CONSTANT COLUMNS are NOT degenerate: they contribute zero variance and
# their components come back with zero explained variance, which is the
# right answer rather than an error.
#
# transform / inverse_transform return nil before fit, and when the input
# does not present exactly the width the fit learned (n_features for
# transform, n_components for inverse_transform).
#
# --- Tunable (see lib/estimator_base.w) ---
#
#     pca.params                            # => { n_components: 2, whiten: false }
#     pca.with_params({ n_components: 1 })  # => a NEW, UNFITTED PCA
#
# `params` reports the CONSTRUCTOR knobs; `with_params` returns a fresh
# unfitted clone with the overrides applied, leaving the receiver
# untouched. That pair is the whole entry fee for Pipeline's tunable
# surface, so a PCA named :pca inside a chain contributes
# "pca.n_components" / "pca.whiten" and GridSearch tunes the number of
# components alongside the model's own hyperparameters, with no code in
# pipeline.w or grid_search.w aware that PCA exists.
#
# WHAT FIT LEARNED IS `learned_params`, NOT `params` — the mean, the
# components and the two variance vectors answer to their own name,
# because `params` means "what you set" everywhere in koala.
#
# --- Persistence (see lib/persist.w) ---
#
# PCA answers the full persistence contract — persist_name / to_state /
# .load_state / restore_state — so `Persist.dumps(pca)` writes a payload
# whose floats are exact to the bit. NOTE that `Persist.loads` also needs
# ONE line in `Persist.rebuild` ("PCA" -> PCA.load_state) to dispatch the
# class name back; that file is owned elsewhere in this change and is
# left untouched here. Until it is added, decode the state hash and hand
# it to PCA.load_state directly — which is exactly what
# spec/pca_spec.w does, and what proves everything on this side works.
#
# NOTE: no float literal appears in this file (every float derives via
# .to_f), the numeric kernel uses `while` rather than blocks so no
# closure captures a mutating counter, arrays are built with push
# (Array `+` is unavailable), and respond_to? is never needed here.
+ PCA
  is Tunable

  ro :n_components   # components to keep; nil = all min(n_samples, n_features)
  ro :whiten         # scale each score column to unit variance

  -> new(n_components = nil, whiten = false)
    @n_components = n_components
    @whiten = whiten
    @fitted = false
    @feature_names = []
    @mean = []
    @components = []
    @explained_variance = []
    @explained_variance_ratio = []

  -> fitted?
    @fitted

  # --- fit / transform ---

  # Learn the mean and the top-k principal directions from x.
  # self on success, nil for any degenerate input (see the header).
  -> fit(x)
    parts = PCA.numeric_block(x)
    out = nil
    if parts != nil
      rows = parts[:rows]
      names = parts[:names]
      n = rows.size
      p = names.size
      cap = n
      cap = p if p < n
      want = @n_components
      want = cap if want == nil
      if n > 1 && want > 0 && want <= cap
        res = PCA.decompose(rows, n, p)
        @feature_names = names
        @mean = res[:mean]
        @components = PCA.take_first(res[:components], want)
        @explained_variance = PCA.take_first(res[:explained_variance], want)
        @explained_variance_ratio = PCA.take_first(res[:explained_variance_ratio], want)
        @fitted = true
        out = self
    out

  # x projected onto the fitted components, as a DataFrame of pc0, pc1, …
  # nil before fit, and nil when x does not present the fitted number of
  # numeric features.
  -> transform(x)
    out = nil
    if @fitted
      parts = PCA.numeric_block(x)
      if parts != nil
        rows = parts[:rows]
        mu = @mean
        comps = @components
        if parts[:names].size == mu.size
          scales = PCA.scales(@explained_variance, @whiten)
          scores = PCA.project(rows, mu, comps, scales)
          k = comps.size
          n = scores.size
          pairs = []
          j = 0
          while j < k
            vals = []
            i = 0
            while i < n
              vals.push(scores[i][j])
              i += 1
            pairs.push(["pc" + j.to_s, vals])
            j += 1
          out = DataFrame.new(pairs)
    out

  -> fit_transform(x)
    self.fit(x)
    self.transform(x)

  # Scores back in the ORIGINAL feature coordinates, as a DataFrame
  # carrying the feature names the fit saw. Exact (to rounding) when
  # n_components covered the data's full rank; otherwise the projection
  # onto the kept components, which is the closest rank-k approximation.
  # nil before fit, and nil when z is not n_components wide.
  -> inverse_transform(z)
    out = nil
    if @fitted
      parts = PCA.numeric_block(z)
      if parts != nil
        scores = parts[:rows]
        mu = @mean
        comps = @components
        names = @feature_names
        k = comps.size
        p = mu.size
        if parts[:names].size == k
          scales = PCA.scales(@explained_variance, @whiten)
          recon = []
          i = 0
          while i < scores.size
            zr = scores[i]
            row = []
            j = 0
            while j < p
              acc = mu[j]
              t = 0
              while t < k
                acc += (zr[t] / scales[t]) * comps[t][j]
                t += 1
              row.push(acc)
              j += 1
            recon.push(row)
            i += 1
          pairs = []
          j = 0
          while j < p
            vals = []
            i = 0
            while i < recon.size
              vals.push(recon[i][j])
              i += 1
            pairs.push([names[j], vals])
            j += 1
          out = DataFrame.new(pairs)
    out

  # --- Learned state ---

  # The k×p Matrix of principal directions, one component per ROW, in
  # descending order of explained variance (scikit-learn's components_
  # layout). nil before fit.
  -> components
    out = nil
    out = Matrix.new(@components) if @fitted
    out

  # Sample variance along each component, sigma²/(n-1). nil before fit.
  -> explained_variance
    out = nil
    out = Vector.new(@explained_variance) if @fitted
    out

  # Each component's share of the TOTAL variance (see the header).
  # nil before fit.
  -> explained_variance_ratio
    out = nil
    out = Vector.new(@explained_variance_ratio) if @fitted
    out

  # The per-feature mean subtracted before projecting. nil before fit.
  -> mean
    out = nil
    out = Vector.new(@mean) if @fitted
    out

  # How many components the fit actually kept (0 before fit).
  -> component_count
    @components.size

  # How many numeric features the fit saw (0 before fit).
  -> feature_count
    @mean.size

  # The names of those features, in fit order.
  -> feature_names
    @feature_names

  # --- Tunable contract (see lib/estimator_base.w) ---

  -> params
    { n_components: @n_components, whiten: @whiten }

  # A NEW, UNFITTED PCA with `overrides` applied; self is left untouched.
  # Unmentioned keys carry over, so with_params(params) round-trips, and
  # an explicit { n_components: nil } really does widen a truncated PCA
  # back to every component (key presence, not value, decides).
  -> with_params(overrides)
    PCA.new(Estimator.opt(overrides, :n_components, @n_components), Estimator.opt(overrides, :whiten, @whiten))

  # What fit LEARNED — deliberately not `params`, which is what you set.
  -> learned_params
    { mean: @mean, components: @components, explained_variance: @explained_variance, explained_variance_ratio: @explained_variance_ratio, feature_names: @feature_names }

  # --- The numeric kernel (statics: no ivars, callable from anywhere) ---

  # Relative cutoff below which a column pair counts as already
  # orthogonal and its rotation is skipped. 1e-15 sits one decade above
  # f64 epsilon (2.2e-16), which is where the Gram entry gamma stops
  # carrying information: below it the "angle" is rounding noise, and
  # rotating on noise is what stops a Jacobi sweep converging.
  #
  # Built as 1e-9 × 1e-6 rather than 1 / 1e15: the interpreter's integers
  # are 48-bit, so the literal 1000000000000000 becomes a HEAP bignum
  # whose `.to_f` dies ("cannot add object/generic + numeric"). Every
  # integer literal in this file stays under 2^48 for that reason.
  -> .orthogonality_tol
    (1.to_f / 1000000000.to_f) * (1.to_f / 1000000.to_f)

  # Hard bound on Jacobi sweeps. Cyclic Jacobi converges quadratically
  # and needs under a dozen sweeps on any realistic input; 60 is a
  # guarantee of termination, not an expectation. Hitting it leaves a
  # deterministic (merely less orthogonal) answer rather than a hang.
  -> .max_sweeps
    60

  # x as { names:, rows: } — the numeric columns' names and the data as
  # float rows — or nil when there is nothing usable to decompose.
  #
  # This is the one place input shape is decided, so fit, transform and
  # inverse_transform all accept exactly the same things. A cell that is
  # nil or non-numeric rejects the whole frame: PCA is arithmetic on
  # every entry, and silently treating a missing value as 0 would move
  # the mean and tilt every component. Run an Imputer first.
  #
  # WHY THIS USES `while` AND NOT `.each` — every other method in this
  # file is loop-only anyway, but here it was a CORRECTNESS fix. On the
  # interpreter, a method containing BOTH a `-> (x)` closure and a
  # `while` loop leaks its while-counter into the CALLER's scope, so a
  # caller iterating `while i < ...` has its own `i` overwritten and the
  # method restarts its loop from the caller's value. Minimal repro
  # (prints 3, 6, 9 interpreted; correctly 6, 6, 6 compiled):
  #
  #     + H
  #       -> .go(vals)
  #         acc = []
  #         vals.each -> (v)
  #           acc.push(v)
  #         i = 0
  #         total = 0
  #         while i < acc.size
  #           total += acc[i]
  #           i += 1
  #         total
  #     i = 0
  #     while i < 3
  #       << H.go([1, 2, 3]).to_s
  #       i += 1
  #
  # Mixing the two forms here silently corrupted a PCA fitted from
  # inside a top-level loop, so no `-> (x)` block appears anywhere in
  # this file. That removes PCA's OWN exposure; it does not cure the
  # engine bug, which is upstream and hits every koala transformer
  # equally (a bare `Scaler.new(:standard).fit(rows)` inside a top-level
  # `while` fails the same way today, PCA or no PCA — the shared
  # Estimator.frame is closure-bearing). Interpreted callers should
  # iterate with `.times` / `.each`, which is unaffected.
  -> .numeric_block(x)
    frame = Estimator.frame(x)
    out = nil
    if frame != nil
      all_names = frame.column_names
      names = []
      cols = []
      ci = 0
      while ci < all_names.size
        vals = frame.column_values(all_names[ci])
        if Stats.numeric?(vals)
          names.push(all_names[ci])
          cols.push(vals)
        ci += 1
      nr = frame.row_count
      ok = names.size > 0 && nr > 0
      cj = 0
      while cj < cols.size
        cvals = cols[cj]
        cr = 0
        while cr < cvals.size
          ok = false if !PCA.numeric_cell?(cvals[cr])
          cr += 1
        cj += 1
      if ok
        rows = []
        ri = 0
        while ri < nr
          row = []
          rj = 0
          while rj < cols.size
            row.push(cols[rj][ri].to_f)
            rj += 1
          rows.push(row)
          ri += 1
        out = { names: names, rows: rows }
    out

  # A single cell PCA can do arithmetic on. Stats.numeric? only inspects
  # a column's FIRST non-nil value, which is the right rule for deciding
  # whether a column is a feature but not for trusting every entry in it.
  -> .numeric_cell?(v)
    t = type(v)
    out = false
    out = true if t == "Integer"
    out = true if t == "Float"
    out

  # The full decomposition of n float rows of p features:
  # { mean:, components:, explained_variance:, explained_variance_ratio: }
  # with ALL p components, sorted by descending variance and sign-pinned.
  -> .decompose(rows, n, p)
    mu = PCA.column_means(rows, n, p)
    a = PCA.centred(rows, mu, n, p)
    v = PCA.identity_rows(p)
    PCA.jacobi(a, v, n, p)
    sigma2 = PCA.column_sums_of_squares(a, n, p)
    order = PCA.descending_order(sigma2, p)
    denom = (n - 1).to_f
    evar = []
    comps = []
    t = 0
    while t < p
      j = order[t]
      evar.push(sigma2[j] / denom)
      comps.push(PCA.pin_sign(PCA.column_of(v, j, p), p))
      t += 1
    { mean: mu, components: comps, explained_variance: evar, explained_variance_ratio: PCA.shares(evar, p) }

  -> .column_means(rows, n, p)
    out = []
    j = 0
    while j < p
      total = 0.to_f
      i = 0
      while i < n
        total += rows[i][j]
        i += 1
      out.push(total / n.to_f)
      j += 1
    out

  # A fresh mean-centred copy — the matrix the rotations work on. The
  # caller's rows are never touched.
  -> .centred(rows, mu, n, p)
    out = []
    i = 0
    while i < n
      row = []
      j = 0
      while j < p
        row.push(rows[i][j] - mu[j])
        j += 1
      out.push(row)
      i += 1
    out

  -> .identity_rows(p)
    out = []
    i = 0
    while i < p
      row = []
      j = 0
      while j < p
        if i == j
          row.push(1.to_f)
        else
          row.push(0.to_f)
        j += 1
      out.push(row)
      i += 1
    out

  # ONE-SIDED JACOBI, in place: rotate pairs of COLUMNS of `a` (n×p, the
  # centred data) until every pair is orthogonal, accumulating the same
  # rotations into `v` (p×p, starting from the identity). On return the
  # columns of `a` are the scaled left singular vectors — their norms are
  # the singular values — and the columns of `v` are the right singular
  # vectors, i.e. the principal directions.
  #
  # For a pair (i, j) the 2×2 Gram block is [[alpha, gamma], [gamma,
  # beta]]; the rotation that annihilates gamma has tan(theta) = t where
  # t² + 2·zeta·t - 1 = 0 with zeta = (beta - alpha) / (2·gamma). The
  # SMALLER root, t = sign(zeta) / (|zeta| + sqrt(1 + zeta²)), is the one
  # taken — it is the rotation through the smaller angle, and writing it
  # this way avoids the cancellation that -zeta ± sqrt(zeta² + 1) suffers
  # when |zeta| is large. An enormous |zeta| (a pair almost orthogonal
  # already) sends t to 0 through the same expression, which is the
  # identity rotation — so the formula degrades safely instead of needing
  # a guard.
  #
  # Sweeps run in a FIXED cyclic order (i ascending, then j), so the
  # result is a pure function of the input on both engines.
  -> .jacobi(a, v, n, p)
    tol = PCA.orthogonality_tol
    limit = PCA.max_sweeps
    sweep = 0
    busy = true
    while busy && sweep < limit
      busy = false
      i = 0
      while i < p - 1
        j = i + 1
        while j < p
          alpha = 0.to_f
          beta = 0.to_f
          gamma = 0.to_f
          k = 0
          while k < n
            ai = a[k][i]
            aj = a[k][j]
            alpha += ai * ai
            beta += aj * aj
            gamma += ai * aj
            k += 1
          if LinAlg.fabs(gamma) > tol * Math.sqrt(alpha * beta)
            busy = true
            zeta = (beta - alpha) / (gamma + gamma)
            sgn = 1.to_f
            sgn = 0.to_f - 1.to_f if zeta < 0
            t = sgn / (LinAlg.fabs(zeta) + Math.sqrt(1.to_f + zeta * zeta))
            c = 1.to_f / Math.sqrt(1.to_f + t * t)
            s = c * t
            k = 0
            while k < n
              xi = a[k][i]
              xj = a[k][j]
              a[k][i] = c * xi - s * xj
              a[k][j] = s * xi + c * xj
              k += 1
            k = 0
            while k < p
              yi = v[k][i]
              yj = v[k][j]
              v[k][i] = c * yi - s * yj
              v[k][j] = s * yi + c * yj
              k += 1
          j += 1
        i += 1
      sweep += 1
    sweep

  # |column j|² for each of the p columns — the squared singular values.
  -> .column_sums_of_squares(a, n, p)
    out = []
    j = 0
    while j < p
      total = 0.to_f
      k = 0
      while k < n
        total += a[k][j] * a[k][j]
        k += 1
      out.push(total)
      j += 1
    out

  -> .column_of(v, j, p)
    out = []
    k = 0
    while k < p
      out.push(v[k][j])
      k += 1
    out

  # Column indices ordered by DESCENDING value, ties keeping the lower
  # index — an explicit insertion sort with a strict comparison, so the
  # order is stable and identical on both engines (Array#sort's order is
  # not portable here; the Stats.sorted / Persist.sorted_keys convention).
  -> .descending_order(values, p)
    out = []
    j = 0
    while j < p
      out.push(j)
      j += 1
    i = 1
    while i < p
      cur = out[i]
      cv = values[cur]
      k = i - 1
      while k >= 0 && values[out[k]] < cv
        out[k + 1] = out[k]
        k -= 1
      out[k + 1] = cur
      i += 1
    out

  # `col` negated if needed so its largest-magnitude entry is positive,
  # ties breaking to the lowest index (see the header's sign convention).
  -> .pin_sign(col, p)
    best = 0
    k = 1
    while k < p
      best = k if LinAlg.fabs(col[k]) > LinAlg.fabs(col[best])
      k += 1
    out = col
    if col[best] < 0
      flipped = []
      k = 0
      while k < p
        flipped.push(0.to_f - col[k])
        k += 1
      out = flipped
    out

  # Each variance as a share of their total; all zeros when the total is
  # zero (an all-constant dataset), never a division by zero.
  -> .shares(evar, p)
    total = 0.to_f
    t = 0
    while t < p
      total += evar[t]
      t += 1
    out = []
    t = 0
    while t < p
      if total > 0
        out.push(evar[t] / total)
      else
        out.push(0.to_f)
      t += 1
    out

  # The per-component multiplier transform applies: 1 normally,
  # 1/sqrt(variance) when whitening. A zero-variance component keeps 1 —
  # its scores are already exactly 0, so there is nothing to rescale and
  # nothing to divide by zero.
  -> .scales(evar, active)
    out = []
    i = 0
    while i < evar.size
      s = 1.to_f
      if active
        root = Math.sqrt(evar[i])
        s = 1.to_f / root if root > 0
      out.push(s)
      i += 1
    out

  # Rows projected onto the components: z[i][j] = (row_i - mean)·comp_j,
  # times the whitening scale.
  -> .project(rows, mu, comps, scales)
    n = rows.size
    p = mu.size
    k = comps.size
    out = []
    i = 0
    while i < n
      row = rows[i]
      z = []
      j = 0
      while j < k
        cj = comps[j]
        acc = 0.to_f
        c = 0
        while c < p
          acc += (row[c] - mu[c]) * cj[c]
          c += 1
        z.push(acc * scales[j])
        j += 1
      out.push(z)
      i += 1
    out

  # The first k entries of `values`.
  -> .take_first(values, k)
    out = []
    i = 0
    while i < k
      out.push(values[i])
      i += 1
    out

  # --- Persistence (see lib/persist.w) ---

  -> persist_name
    "PCA"

  # Everything a loaded PCA needs to transform IDENTICALLY: the knobs,
  # the feature names, the training mean and the learned components with
  # their variances. Nothing is recomputed on load — a saved PCA replays
  # the TRAINING directions, which is the whole point of saving a
  # transformer rather than re-fitting one.
  -> to_state
    { n_components: @n_components, whiten: @whiten, feature_names: @feature_names, mean: @mean, components: @components, explained_variance: @explained_variance, explained_variance_ratio: @explained_variance_ratio }

  -> .load_state(st)
    out = nil
    ok = st != nil
    ok = st[:mean] != nil && st[:components] != nil if ok
    ok = st[:explained_variance] != nil && st[:explained_variance_ratio] != nil if ok
    ok = st[:feature_names] != nil if ok
    if ok
      model = PCA.new(st[:n_components], st[:whiten])
      out = model.restore_state(st)
    out

  -> restore_state(st)
    @feature_names = st[:feature_names]
    @mean = st[:mean]
    @components = st[:components]
    @explained_variance = st[:explained_variance]
    @explained_variance_ratio = st[:explained_variance_ratio]
    @fitted = true
    self
