# Cross-validation splitters + CrossValidation — how koala carves data
# into train/test folds, and the model-evaluation driver that re-fits an
# estimator on each fold and records the held-out score, sklearn-style.
#
#     KFold.new(5).split(10)              # 5 contiguous [train, test] pairs
#     KFold.new(5, 42).split(10)          # ... over a seeded shuffle first
#     StratifiedKFold.new(3).split(y)     # every fold keeps y's class mix
#     LeaveOneOut.new.split(4)            # 4 folds, one held-out row each
#     GroupKFold.new(2).split(groups)     # no group spans train and test
#     TimeSeriesSplit.new(3).split(12)    # expanding window, never the future
#     ShuffleSplit.new(5, 30, 42).split(10)   # 5 random 30% hold-outs
#
#     CrossValidation.cross_val_score(LinearRegression.new, x, y, 5)
#       # => array of 5 per-fold R² (or accuracy for a classifier)
#     CrossValidation.cross_val_mean(KNNClassifier.new(3), x, y, 4)
#       # => the mean fold score (the single number usually reported)
#     CrossValidation.cross_val_mean(KMeans.new(2), x, nil, 2)
#       # => unsupervised: y is nil, folds score -inertia on held-out rows
#     CrossValidation.cross_val_mean(KNNClassifier.new(1), x, y, StratifiedKFold.new(3))
#       # => any splitter in the SAME position as the fold count
#
# ============================================================
# The splitter contract: `folds(n, y)` — and why `split` differs
# ============================================================
#
# Every splitter answers `Splitting`: ONE method, `folds(n, y)`, taking
# the sample count and the (possibly nil) target values and returning an
# array of [train_indices, test_indices] pairs — or nil if it cannot
# split those inputs. That is the whole entry fee for being usable by
# `CrossValidation.cross_val_score`, which never names a concrete
# splitter class.
#
# Each splitter ALSO keeps its own natural `split`, and those signatures
# deliberately DIFFER, because the splitters genuinely need different
# things:
#
#     KFold#split(n)             — the sample COUNT is all it needs
#     LeaveOneOut#split(n)       — likewise
#     TimeSeriesSplit#split(n)   — likewise (row ORDER carries the time)
#     ShuffleSplit#split(n)      — likewise
#     StratifiedKFold#split(y)   — the LABELS: it balances classes
#     GroupKFold#split(groups)   — the GROUP of each row
#
# Hiding that behind one uniform `split(n, y, groups)` would be a lie —
# it would suggest KFold consults the labels (it does not) and that
# stratification is free (it is not: without labels there is nothing to
# stratify). So the natural API stays honest about its inputs, and
# `folds(n, y)` is the thin ADAPTER on top: KFold ignores y, and
# StratifiedKFold refuses (nil) when y is missing or the wrong length.
# GroupKFold's groups are not targets at all, so it takes them at
# CONSTRUCTION — `GroupKFold.new(k, groups)` — and its `folds` uses those.
#
# ============================================================
# Determinism
# ============================================================
#
# Same inputs (and same seed) => byte-identical folds on BOTH engines.
# Three rules make that true, and they are worth stating because each one
# is a bug that was easy to write:
#
#   * NO hash iteration order. Classes (StratifiedKFold) and groups
#     (GroupKFold) are collected in FIRST-APPEARANCE order by scanning the
#     samples — the Encoder / GaussianNB / LogisticRegression convention.
#     A Hash is used only for O(1) LOOKUP (keyed by `label.to_s`, so a
#     symbol and its string form are the same class); `.keys` is never
#     enumerated, because its order differs between engines.
#   * NO `Array#sort`. GroupKFold orders its groups with a hand-rolled
#     STABLE selection sort (largest first, first-appearance breaking
#     ties) — the Stats.sorted / GridSearch.rank convention. Symbol
#     `.sort` is neither documented nor lexicographic.
#   * ONE random source. Shuffling always goes through Splitter.indices —
#     koala's MINSTD Lehmer generator (state * 48271 mod 2^31-1) — so a
#     seed means the same permutation everywhere. ShuffleSplit derives
#     each repetition's seed by ADVANCING that same stream, rather than
#     using seed+1, whose MINSTD orbit would be nearly identical.
#
# ============================================================
# Degenerate input returns nil
# ============================================================
#
# The bit's shape-error convention: no splitter ever raises. nil comes
# back for k < 2, k > n, n <= 0, a y or groups array whose length does
# not match n, a class with fewer than k members (StratifiedKFold — it
# could not put one in every fold), fewer than k distinct groups
# (GroupKFold), too few samples for k+1 time blocks (TimeSeriesSplit),
# and a test percentage that rounds to an empty test or an empty train
# (ShuffleSplit).
#
# NOTE: locals are hoisted from ivars before any `-> (x)` block, methods
# containing closures avoid early `return`, arrays are built with `push`
# (Array `+` and `insert` are unavailable), and no float literals appear
# here — the same conventions as the rest of koala's estimator code.

# The uniform splitter contract: one method, so CrossValidation can take
# ANY splitter without naming a concrete class. Declared, not enforced —
# spec/estimator_spec.w asserts every splitter answers it (respond_to?).
trait Splitting
  -> folds(n, y)

# k contiguous folds over 0...n, optionally over a seeded shuffle:
# scikit-learn's KFold. It consults only the sample COUNT — which is
# exactly its weakness on classification data, and why StratifiedKFold
# exists below.
+ KFold
  is Splitting

  ro :k      # number of folds (2 <= k <= n)
  ro :seed   # shuffle seed; nil keeps input order (contiguous folds)

  -> new(k = 5, seed = nil)
    @k = k
    @seed = seed

  # k [train_indices, test_indices] pairs partitioning 0...n; nil when
  # k is out of range (k < 2 or k > n) or n <= 0.
  #
  # Fold sizes match scikit-learn exactly: the FIRST (n mod k) folds hold
  # ceil(n/k) samples and the rest hold floor(n/k), so every sample lands
  # in exactly one test fold. Fold f's test set is that fold's slice of
  # the index order and its train set is every other index, order
  # preserved.
  -> split(n)
    k = @k
    seed = @seed
    out = nil
    if n > 0 && k >= 2 && k <= n
      order = Splitter.indices(n, seed)
      base = n / k
      rem = n % k
      pairs = []
      start = 0
      k.times -> (f)
        size = base
        size = base + 1 if f < rem
        stop = start + size
        test_idx = []
        train_idx = []
        pos = 0
        order.each -> (ix)
          if pos >= start && pos < stop
            test_idx.push(ix)
          else
            train_idx.push(ix)
          pos += 1
        pair = [train_idx, test_idx]
        pairs.push(pair)
        start = stop
      out = pairs
    out

  # Uniform adapter: KFold needs only the count, so y is ignored.
  -> folds(n, y)
    self.split(n)

# k folds that PRESERVE EACH CLASS'S PROPORTION — scikit-learn's
# StratifiedKFold, and the splitter classification should actually use.
#
# WHY IT EXISTS. Plain KFold slices the index order into contiguous
# blocks. On sorted or imbalanced labels that is a trap: with
# y = six 0s then three 1s and k = 3, KFold's third fold tests ONLY class
# 1 while training on ZERO examples of it — the score that comes back is
# meaningless, and nothing warns you. StratifiedKFold's folds for the
# same y are [0,3,6] / [1,4,7] / [2,5,8]: two 0s and one 1 each, the 2:1
# global ratio, in every fold.
#
# HOW. Each class's members are DEALT round-robin across the folds, like
# cards — but the deal for the next class RESUMES where the last one
# stopped instead of restarting at fold 0. That rotation is what keeps
# the fold SIZES balanced when a class does not divide evenly: three
# classes of four into three folds gives 4/4/4, where restarting at fold
# 0 every time would give a lopsided 6/3/3. Fold sizes therefore match
# scikit-learn's.
#
# API NOTE: `split` takes the LABELS, not a count — unlike every other
# splitter here. It cannot be otherwise; stratifying needs to know what
# is being stratified. See the contract section at the top of the file.
+ StratifiedKFold
  is Splitting

  ro :k      # number of folds (2 <= k <= n, and <= every class's size)
  ro :seed   # shuffle seed; nil deals classes in input order

  -> new(k = 5, seed = nil)
    @k = k
    @seed = seed

  # k [train_indices, test_indices] pairs over 0...y.size, each fold
  # holding (as near as integer arithmetic allows) the same class mix as
  # y itself. y is a plain array, Series or Vector of labels — anything
  # Estimator.target_values accepts; labels are opaque and compared by
  # `.to_s`, so integers, strings and symbols all work (and :a and "a"
  # are the SAME class).
  #
  # nil when y is missing or empty, when k < 2 or k > y.size, or when ANY
  # class has fewer than k members — that class could not appear in every
  # fold, so the split would not be stratified and koala will not pretend
  # otherwise.
  -> split(y)
    k = @k
    seed = @seed
    labels = nil
    labels = Estimator.target_values(y) if y != nil
    out = nil
    ok = labels != nil
    ok = labels.size > 0 && k >= 2 && k <= labels.size if ok
    if ok
      n = labels.size
      order = Splitter.indices(n, seed)
      # Classes in FIRST-APPEARANCE order (never hash key order); the
      # hash is a lookup index into the parallel arrays, nothing more.
      class_names = []
      class_members = []
      slot = {}
      order.each -> (ix)
        name = labels[ix].to_s
        if !slot.key?(name)
          slot[name] = class_names.size
          class_names.push(name)
          class_members.push([])
        class_members[slot[name]].push(ix)
      class_members.each -> (mem)
        ok = false if mem.size < k
      if ok
        fold_of = []
        n.times -> (i)
          fold_of.push(0)
        # Deal each class round-robin, RESUMING at the fold the previous
        # class stopped on — that rotation is what balances fold sizes.
        turn = 0
        class_members.each -> (mem)
          j = 0
          mem.each -> (ix)
            fold_of[ix] = (turn + j) % k
            j += 1
          turn = (turn + mem.size) % k
        pairs = []
        k.times -> (f)
          test_idx = []
          train_idx = []
          order.each -> (ix)
            if fold_of[ix] == f
              test_idx.push(ix)
            else
              train_idx.push(ix)
          pair = [train_idx, test_idx]
          pairs.push(pair)
        out = pairs
    out

  # Uniform adapter: stratification REQUIRES the labels, so a missing or
  # mis-sized y is nil rather than a silent fall back to plain KFold —
  # quietly unstratifying a stratified request is the bug this class was
  # written to prevent.
  -> folds(n, y)
    out = nil
    if y != nil
      vals = Estimator.target_values(y)
      out = self.split(vals) if vals != nil && vals.size == n
    out

# n folds, each holding out exactly ONE sample: scikit-learn's
# LeaveOneOut, the k = n limit of KFold. Every sample is tested once
# against a model trained on all the others, which is the least-biased
# estimate available and the one that matters on the small datasets
# koala is usually pointed at. It costs n fits, so it is for small n.
+ LeaveOneOut
  is Splitting

  # n [train_indices, test_indices] pairs; fold i tests [i] and trains on
  # every other index in order. nil for n < 2 (there is nothing to train
  # on). No seed: shuffling cannot change a partition into singletons.
  -> split(n)
    out = nil
    if n >= 2
      pairs = []
      n.times -> (i)
        test_idx = []
        test_idx.push(i)
        train_idx = []
        n.times -> (j)
          train_idx.push(j) if j != i
        pair = [train_idx, test_idx]
        pairs.push(pair)
      out = pairs
    out

  # Uniform adapter: the count is all it needs.
  -> folds(n, y)
    self.split(n)

# k folds in which NO GROUP SPANS TRAIN AND TEST — scikit-learn's
# GroupKFold.
#
# WHY IT EXISTS. When rows are not independent — several readings from
# one patient, several frames from one video, several rows per customer —
# a fold that trains on some of a group and tests on the rest is not
# measuring generalization, it is measuring memorization, and the score
# comes back flatteringly high. Grouping is the fix: an entire group is
# either trained on or tested, never both. Interleaved groups make the
# point sharpest — groups [a,b,a,b,a,b] under plain KFold put PART of
# every group on both sides of every fold; GroupKFold splits them cleanly
# into [0,2,4] and [1,3,5].
#
# HOW. Groups are ordered LARGEST FIRST (a stable selection sort;
# first-appearance breaks ties — never Array#sort, whose order is not
# portable) and each is assigned greedily to the fold holding the fewest
# samples so far, ties going to the lowest fold index. That is
# scikit-learn's algorithm, and it keeps fold sizes as even as unequal
# group sizes permit.
+ GroupKFold
  is Splitting

  ro :k        # number of folds (2 <= k <= number of distinct groups)
  ro :groups   # groups for the `folds` adapter; nil to use split directly

  # groups may be given here so the uniform `folds(n, y)` adapter — and
  # therefore cross_val_score — can reach them: a row's GROUP is not its
  # target, so there is nowhere else in that signature for it to live.
  -> new(k = 5, groups = nil)
    @k = k
    @groups = groups

  # k [train_indices, test_indices] pairs over 0...groups.size where every
  # index sharing a group value lands on the SAME side of every fold.
  # groups is a plain array, Series or Vector; values are opaque and
  # compared by `.to_s`. Test indices come back in ascending order.
  #
  # nil when groups is missing or empty, k < 2, or there are fewer than k
  # distinct groups (a group cannot be cut in half to fill a fold).
  -> split(groups)
    k = @k
    vals = nil
    vals = Estimator.target_values(groups) if groups != nil
    out = nil
    ok = vals != nil
    ok = vals.size > 0 && k >= 2 if ok
    if ok
      n = vals.size
      group_names = []
      group_members = []
      slot = {}
      n.times -> (i)
        name = vals[i].to_s
        if !slot.key?(name)
          slot[name] = group_names.size
          group_names.push(name)
          group_members.push([])
        group_members[slot[name]].push(i)
      ok = group_names.size >= k
      if ok
        # Largest group first; equal sizes keep first-appearance order
        # (the replacement test is STRICT, so the sort is stable).
        ng = group_names.size
        taken = []
        group_names.each -> (nm)
          taken.push(false)
        by_size = []
        ng.times -> (t)
          pick = 0 - 1
          gi = 0
          group_members.each -> (mem)
            if !taken[gi]
              if pick < 0
                pick = gi
              else
                pick = gi if mem.size > group_members[pick].size
            gi += 1
          taken[pick] = true
          by_size.push(pick)
        # Greedy: each group joins the fold holding the fewest samples.
        load = []
        k.times -> (f)
          load.push(0)
        fold_of_group = []
        group_names.each -> (nm)
          fold_of_group.push(0)
        by_size.each -> (gi)
          best = 0
          f = 0
          load.each -> (amount)
            best = f if amount < load[best]
            f += 1
          fold_of_group[gi] = best
          load[best] = load[best] + group_members[gi].size
        fold_of = []
        n.times -> (i)
          fold_of.push(0)
        gi = 0
        group_members.each -> (mem)
          assigned = fold_of_group[gi]
          mem.each -> (ix)
            fold_of[ix] = assigned
          gi += 1
        pairs = []
        k.times -> (f)
          test_idx = []
          train_idx = []
          n.times -> (i)
            if fold_of[i] == f
              test_idx.push(i)
            else
              train_idx.push(i)
          pair = [train_idx, test_idx]
          pairs.push(pair)
        out = pairs
    out

  # Uniform adapter: uses the groups handed to the constructor (y is a
  # target, not a group). nil when they are absent or the wrong length.
  -> folds(n, y)
    raw = @groups
    out = nil
    if raw != nil
      vals = Estimator.target_values(raw)
      out = self.split(vals) if vals != nil && vals.size == n
    out

# k EXPANDING-WINDOW folds that never train on the future —
# scikit-learn's TimeSeriesSplit.
#
# WHY IT EXISTS. Rows in time order are the one case where shuffling is
# not merely unhelpful but WRONG: any fold that trains on row 90 and
# tests on row 10 has read tomorrow's newspaper, and the backtest it
# reports is fiction. Here fold f trains on a PREFIX and tests on the
# block immediately after it, so train indices are always strictly
# earlier than test indices.
#
# HOW. With n samples and k splits the test block is n / (k + 1) rows
# (integer division, scikit-learn's rule) and the k test blocks are the
# LAST k blocks: n = 12, k = 3 gives train [0,1,2] test [3,4,5], then
# train [0..5] test [6,7,8], then train [0..8] test [9,10,11]. The
# earliest block is never tested — it is the seed history every fold
# needs. `gap` drops that many rows between train and test, the guard
# against leaking through autocorrelation (or through a label that is
# only observable some steps later).
+ TimeSeriesSplit
  is Splitting

  ro :k     # number of splits (>= 2)
  ro :gap   # rows dropped between each train prefix and its test block

  -> new(k = 5, gap = 0)
    @k = k
    @gap = gap

  # k [train_indices, test_indices] pairs, both ascending, with every
  # train index < every test index. No seed and no shuffle — reordering
  # would destroy the only thing this splitter is protecting.
  #
  # nil when k < 2, gap < 0, n is too small to give each of the k + 1
  # blocks a row, or the gap would leave the first fold with no training
  # rows at all.
  -> split(n)
    k = @k
    gap = @gap
    out = nil
    ok = n > 0 && k >= 2 && gap >= 0
    size = 0
    size = n / (k + 1) if ok
    ok = false if ok && size < 1
    first = 0
    first = n - k * size if ok
    ok = false if ok && first - gap < 1
    if ok
      pairs = []
      k.times -> (f)
        test_start = first + f * size
        test_stop = test_start + size
        train_stop = test_start - gap
        train_idx = []
        test_idx = []
        n.times -> (i)
          if i < train_stop
            train_idx.push(i)
          else
            test_idx.push(i) if i >= test_start && i < test_stop
        pair = [train_idx, test_idx]
        pairs.push(pair)
      out = pairs
    out

  # Uniform adapter: row ORDER carries the time, so the count is enough.
  -> folds(n, y)
    self.split(n)

# n_splits INDEPENDENT random hold-outs — scikit-learn's ShuffleSplit.
#
# WHY IT EXISTS. KFold's folds are a partition: k of them and no more,
# and every test set is a rigid n/k of the data. ShuffleSplit decouples
# the two — draw as many hold-outs as you can afford, each any size you
# like — which is what you want when you need a tighter estimate than 5
# folds give (more draws) or when n is large enough that a 10% test set
# is plenty (smaller tests, cheaper fits). Test sets may overlap between
# repetitions; that is the trade for the freedom.
#
# test_pct is an INTEGER percent, Splitter.train_test's convention —
# float parameters do not cross engine boundaries reliably. The test size
# is (n * test_pct) / 100, and each repetition takes the LAST test_size
# entries of its own MINSTD permutation.
#
# SEED. Repetition r uses the r-th state of the MINSTD stream started
# from `seed`, so the draws are decorrelated and reproducible; seed + r
# would have given nearly the same permutation each time. With seed = nil
# there is no shuffle at all, so every repetition is the SAME trailing
# hold-out — deterministic, and deliberately useless: pass a seed.
+ ShuffleSplit
  is Splitting

  ro :n_splits   # how many hold-outs to draw (>= 1) — repeats, not a partition
  ro :test_pct   # integer percent of rows held out in each
  ro :seed       # MINSTD seed; nil means no shuffle (identical repetitions)

  -> new(n_splits = 5, test_pct = 25, seed = nil)
    @n_splits = n_splits
    @test_pct = test_pct
    @seed = seed

  # n_splits [train_indices, test_indices] pairs, each a fresh draw. nil
  # when n < 2, n_splits < 1, or test_pct rounds the test set down to
  # nothing or up to everything.
  -> split(n)
    reps = @n_splits
    pct = @test_pct
    seed = @seed
    out = nil
    ok = n > 1 && reps >= 1 && pct != nil
    test_n = 0
    test_n = (n * pct) / 100 if ok
    ok = false if ok && test_n < 1
    ok = false if ok && test_n >= n
    if ok
      train_n = n - test_n
      state = 1
      if seed != nil
        state = seed % 2147483647
        state = 1 if state <= 0
      pairs = []
      reps.times -> (r)
        draw = nil
        if seed != nil
          state = (state * 48271) % 2147483647
          draw = state
        order = Splitter.indices(n, draw)
        train_idx = []
        test_idx = []
        pos = 0
        order.each -> (ix)
          if pos < train_n
            train_idx.push(ix)
          else
            test_idx.push(ix)
          pos += 1
        pair = [train_idx, test_idx]
        pairs.push(pair)
      out = pairs
    out

  # Uniform adapter: the count is all it needs.
  -> folds(n, y)
    self.split(n)

+ CrossValidation
  # The splitter a `cv` argument means: a splitter object is returned
  # as-is, an integer k becomes KFold.new(k, seed). nil for a nil cv.
  #
  # The test is BEHAVIOURAL — respond_to? "folds", the string form, the
  # only one that answers on both engines — because type(obj) on an
  # instance returns "Hash" interpreted and could not tell a splitter
  # from a hash. It is the same duck-typing Estimator.frame uses for
  # "column_names", and it means a splitter written OUTSIDE koala works
  # here with no registration: answer `folds(n, y)` and you are a
  # splitter.
  -> .splitter_for(cv, seed)
    out = nil
    if cv != nil
      if cv.respond_to?("folds")
        out = cv
      else
        out = KFold.new(cv, seed)
    out

  # Per-fold scores (one per fold) from re-fitting `model` on each fold's
  # training rows and scoring the held-out rows. nil when the inputs
  # cannot be coerced, their lengths disagree, or the splitter rejects
  # them. A fold whose fit fails contributes a nil score.
  #
  # `cv` IS EITHER A FOLD COUNT OR A SPLITTER. An integer is the original
  # behaviour, unchanged — KFold with that many folds, shuffled by `seed`
  # when one is given. Any object answering `folds(n, y)` is used
  # instead, and `seed` is then ignored: a splitter carries its own
  # seeding, and a second one here could only contradict it.
  #
  #     cross_val_score(model, x, y, 5)                     # 5-fold KFold
  #     cross_val_score(model, x, y, 5, 42)                 # ... seeded
  #     cross_val_score(model, x, y, StratifiedKFold.new(5))
  #     cross_val_score(model, x, y, GroupKFold.new(3, gs))
  #     cross_val_score(model, x, y, TimeSeriesSplit.new(4))
  #
  # Works for SUPERVISED and UNSUPERVISED estimators alike: `model` is
  # fitted and scored through Estimator.fit_model / .score_model, which
  # read model.supervised? and pass the right arity. y is therefore
  # OPTIONAL — omit it (or pass nil) for an unsupervised model like
  # KMeans, whose folds score -inertia on the held-out rows. A supervised
  # model still requires a y whose length matches x. An UNSUPERVISED
  # model may still be given a y: the estimator never sees it, but the
  # SPLITTER does, which is what lets a clustering run be stratified by a
  # label it is not allowed to learn from.
  -> .cross_val_score(model, x, y = nil, cv = 5, seed = nil)
    rows = Estimator.feature_rows(x)
    supervised = model.supervised?
    yvals = nil
    yvals = Estimator.target_values(y) if y != nil
    out = nil
    ok = rows != nil
    ok = yvals != nil && rows.size == yvals.size if ok && supervised
    ok = rows.size == yvals.size if ok && yvals != nil
    ok = rows.size > 0 if ok
    if ok
      splitter = CrossValidation.splitter_for(cv, seed)
      folds = nil
      folds = splitter.folds(rows.size, yvals) if splitter != nil
      if folds != nil
        scores = []
        folds.each -> (fold)
          tr_idx = fold[0]
          te_idx = fold[1]
          tr_rows = []
          tr_y = []
          tr_idx.each -> (ix)
            tr_rows.push(rows[ix])
            tr_y.push(yvals[ix]) if yvals != nil
          te_rows = []
          te_y = []
          te_idx.each -> (ix)
            te_rows.push(rows[ix])
            te_y.push(yvals[ix]) if yvals != nil
          f = Estimator.fit_model(model, tr_rows, tr_y)
          s = nil
          s = Estimator.score_model(model, te_rows, te_y) if f != nil
          scores.push(s)
        out = scores
    out

  # The mean of cross_val_score (the single headline number). nil when
  # cross_val_score is nil; nil-scoring folds are dropped by Stats.mean,
  # and an all-nil set of folds means nil overall. This is the number
  # GridSearch ranks candidates by — and because GridSearch hands its `k`
  # straight through, a GridSearch built with `GridSearch.new(est, grid,
  # StratifiedKFold.new(3))` searches on stratified folds with no change
  # to lib/grid_search.w.
  -> .cross_val_mean(model, x, y = nil, cv = 5, seed = nil)
    scores = self.cross_val_score(model, x, y, cv, seed)
    out = nil
    out = Stats.mean(scores) if scores != nil
    out
