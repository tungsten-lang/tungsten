# GridSearch — exhaustive hyperparameter search by cross-validated score
# (pure Tungsten, CPU-only; koala's model-SELECTION layer, sitting one
# level above CrossValidation the way sklearn's GridSearchCV sits above
# cross_val_score).
#
#     gs = GridSearch.new(KNNClassifier.new, { k: [1, 3, 5] }, 4)
#     gs.fit(x, y)
#     gs.best_params      # => { k: 1 }
#     gs.best_score       # => the best mean fold score
#     gs.best_estimator   # => a KNNClassifier(k: 1) refit on ALL the data
#     gs.results          # => every combination, ranked best-first
#     gs.size             # => 3 (combinations in the grid)
#
# The search takes a PROTOTYPE estimator, a param grid (a hash of
# `param => [candidate values]`), the fold count k, an optional shuffle
# seed, and a refit flag:
#
#     GridSearch.new(estimator, param_grid, k = 5, seed = nil, refit = true)
#
# For every point in the grid's cartesian product it builds a candidate
# with `estimator.with_params(combination)` — a FRESH, UNFITTED clone, so
# the prototype is never mutated and candidates never alias each other —
# scores it with `CrossValidation.cross_val_mean(candidate, x, y, k, seed)`,
# and keeps the highest. Higher is always better: every koala estimator's
# score follows sklearn's sign convention (R² / accuracy for the
# supervised four, NEGATED inertia for KMeans), so one `>` ranks them all.
#
# CONTRACT-ONLY, NEVER TYPE-TESTED. GridSearch touches its estimator
# through exactly six contract methods — `params`, `with_params`,
# `supervised?`, `fit`, `score` (the last two only via
# Estimator.fit_model / .score_model) and `estimator_name`. It never asks
# what CLASS the estimator is, so anything answering `Estimable` is
# searchable: the five estimators today, and a Pipeline the moment it
# answers the same contract — no change here.
#
# SUPERVISED AND UNSUPERVISED. `fit(x, y)` searches a supervised
# estimator; `fit(x)` searches an unsupervised one (y stays nil and the
# fold score is -inertia on the held-out rows). The arity is chosen by the
# estimator's own `supervised?`, down in CrossValidation, so KMeans needs
# no special case here. NOTE the statistics, though: -inertia falls
# monotonically as k rises, so searching KMeans's `k` by cross-validated
# score will simply elect the LARGEST k offered. That is the honest
# reading of the objective, not a bug — use it to tune `max_iter` or
# `seed`, and choose k by an elbow / silhouette criterion instead.
#
# --- Determinism (a hard guarantee, both engines) ---
#
# Candidate ORDER is a pure function of the grid, never of hash iteration
# order — which is genuinely unstable here: the same literal
# `{ zebra: .., alpha: .., mid: .. }` yields `.keys` in one order on the
# interpreter and another compiled. So:
#
#   * keys are sorted by NAME (`key.to_s`, lexicographic) — `GridSearch.grid_keys`.
#     Symbol `.sort` is NOT used: its order is neither documented nor
#     lexicographic (it sorted `k, max_iter, mid, alpha, zebra`).
#   * each key's value list keeps the order the caller GAVE it.
#   * the product runs odometer-style with the LAST key varying fastest —
#     `{ a: [3, 4], b: [1, 2] }` enumerates a3b1, a3b2, a4b1, a4b2 —
#     matching sklearn's ParameterGrid.
#   * ties break to the FIRST candidate in that enumeration order (the
#     comparison is a strict `>`), and `results` is ranked with a STABLE
#     selection sort, so equal scores stay in enumeration order.
#   * with a seed, KFold's folds are identical run to run and engine to
#     engine, so the whole search reproduces exactly.
#
# --- Degenerate input: nil, never a raise (koala's convention) ---
#
# `fit` returns nil (and `fitted?` stays false) when:
#   * the grid is nil, empty, or has a key with an EMPTY value list;
#   * the grid names a param the estimator does not expose — the keys are
#     checked against `estimator.params`, so a typo is caught loudly-by-nil
#     instead of being silently ignored by `with_params` and reporting a
#     winner that never varied;
#   * x / y cannot be coerced, disagree in length, or k is out of range —
#     every candidate then scores nil;
#   * no candidate produced a score at all.
# A SINGLE candidate scoring nil (e.g. alpha = 0 on collinear features,
# where the fit is singular) is not degenerate: it stays in `results` with
# a nil score, ranked last, and never wins.
#
# `size` and `candidates` are computed at construction, so both read
# correctly BEFORE fit (and `size` is 0 for a rejected grid).
#
# With `refit = false` the winner is not refit and `best_estimator` stays
# nil (sklearn's semantics — the attribute is simply unavailable);
# `best_params`, `best_score` and `results` are unaffected.
#
# NOTE: locals are hoisted from ivars before any `-> (x)` block — the
# interpreter cannot resolve @ivars from a block body — methods
# containing closures avoid early `return`, arrays are built with push
# (Array `+` and `insert` are unavailable), and no float literals appear
# here: every float derives from the data.
+ GridSearch
  ro :estimator      # the prototype every candidate is cloned from
  ro :param_grid     # the searched hash of param => [values]
  ro :k              # CV fold count handed to CrossValidation
  ro :seed           # CV shuffle seed; nil keeps contiguous folds
  ro :refit          # refit the winner on the full data after searching
  ro :candidates     # the enumerated grid points, in search order; nil if rejected
  ro :size           # how many combinations that is (0 for a rejected grid)
  ro :best_params    # the winning combination; nil before a successful fit
  ro :best_score     # its mean fold score; nil before a successful fit
  ro :best_estimator # the winner refit on ALL the data; nil if refit = false
  ro :results        # every candidate as { params:, score:, rank: }, best-first

  -> new(estimator, param_grid, k = 5, seed = nil, refit = true)
    @estimator = estimator
    @param_grid = param_grid
    @k = k
    @seed = seed
    @refit = refit
    @candidates = GridSearch.candidates(param_grid)
    @size = 0
    @size = @candidates.size if @candidates != nil
    @fitted = false
    @best_params = nil
    @best_score = nil
    @best_estimator = nil
    @results = nil

  -> fitted?
    @fitted

  # --- The grid, as pure functions of the grid alone ---

  # The grid's keys in the search's canonical order: sorted by NAME, so
  # the order never depends on the engine's hash iteration. [] for an
  # empty grid, nil for a nil one.
  -> .grid_keys(grid)
    out = nil
    if grid != nil
      keys = grid.keys
      sorted = []
      n = keys.size
      prev = nil
      n.times -> (i)
        best = nil
        bestn = nil
        keys.each -> (kk)
          nm = kk.to_s
          if prev == nil || nm > prev
            if bestn == nil || nm < bestn
              best = kk
              bestn = nm
        if best != nil
          sorted.push(best)
          prev = bestn
      out = sorted
    out
  # Every combination in the grid, as override hashes ready for
  # with_params, in search order: keys sorted by name, each value list in
  # the given order, LAST key varying fastest. A bare (non-array) value is
  # taken as a one-element list. nil for a nil / empty grid or one whose
  # key has an empty value list.
  -> .candidates(grid)
    keys = GridSearch.grid_keys(grid)
    out = nil
    ok = keys != nil
    ok = keys.size > 0 if ok
    if ok
      empty_row = {}
      acc = []
      acc.push(empty_row)
      keys.each -> (kk)
        vals = grid[kk]
        vals = [vals] if type(vals) != "Array"
        ok = false if vals.size == 0
        nxt = []
        acc.each -> (base)
          vals.each -> (v)
            merged = {}
            base.keys.each -> (bk)
              merged[bk] = base[bk]
            merged[kk] = v
            nxt.push(merged)
        acc = nxt
      out = acc if ok
    out

  # `scored` ({ params:, score: } rows in enumeration order) ranked
  # best-first as { params:, score:, rank: } rows, rank starting at 1.
  # The selection sort is STABLE — it replaces the incumbent only on a
  # strict improvement — so equal scores keep enumeration order and nil
  # scores sink to the end.
  -> .rank(scored)
    taken = []
    scored.each -> (r)
      taken.push(false)
    ranked = []
    n = scored.size
    n.times -> (t)
      pick = -1
      j = 0
      scored.each -> (r)
        if !taken[j]
          if pick == -1
            pick = j
          else
            cur = r[:score]
            bestv = scored[pick][:score]
            if cur != nil
              pick = j if bestv == nil || cur > bestv
        j += 1
      if pick >= 0
        taken[pick] = true
        entry = { params: scored[pick][:params], score: scored[pick][:score], rank: t + 1 }
        ranked.push(entry)
    ranked

  # --- The search ---

  # Score every candidate by k-fold CV and keep the best. Returns self, or
  # nil — fitted? stays false — for any of the degenerate cases in the
  # header. y is omitted (nil) for an unsupervised estimator.
  -> fit(x, y = nil)
    est = @estimator
    cands = @candidates
    folds = @k
    sd = @seed
    keys = GridSearch.grid_keys(@param_grid)
    known = nil
    known = est.params if cands != nil
    ok = cands != nil && known != nil
    if ok
      keys.each -> (kk)
        ok = false if !known.key?(kk)
    out = nil
    if ok
      scored = []
      best_i = -1
      best_s = nil
      i = 0
      cands.each -> (c)
        model = est.with_params(c)
        s = CrossValidation.cross_val_mean(model, x, y, folds, sd)
        row = { params: c, score: s }
        scored.push(row)
        if s != nil
          if best_s == nil || s > best_s
            best_s = s
            best_i = i
        i += 1
      if best_i >= 0
        @results = GridSearch.rank(scored)
        @best_params = cands[best_i]
        @best_score = best_s
        @fitted = true
        if @refit
          winner = est.with_params(cands[best_i])
          done = Estimator.fit_model(winner, x, y)
          @best_estimator = winner if done != nil
        out = self
    out

  # --- Delegation to the winner (so a search drops in where the
  #     estimator did) ---

  # best_estimator's predictions for x; nil before a successful fit, or
  # when refit was false.
  -> predict(x)
    out = nil
    out = @best_estimator.predict(x) if @best_estimator != nil
    out

  # best_estimator's score on x / y, through the same arity-safe dispatch
  # the search itself used. nil before a successful fit, or when refit
  # was false.
  -> score(x, y = nil)
    out = nil
    out = Estimator.score_model(@best_estimator, x, y) if @best_estimator != nil
    out

  # "GridSearch(KNNClassifier)" — the search named by what it searches.
  -> estimator_name
    "GridSearch(" + @estimator.estimator_name + ")"
