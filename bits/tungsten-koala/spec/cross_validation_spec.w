# Cross-validation splitter specs — StratifiedKFold, LeaveOneOut,
# GroupKFold, TimeSeriesSplit, ShuffleSplit, the uniform `folds(n, y)`
# contract they share, and CrossValidation's splitter-aware `cv`
# argument, on the tungsten-spec framework.
#
# Run from the repo root (both engines, exit 0 = green):
#   bin/tungsten bits/tungsten-koala/spec/cross_validation_spec.w
#   bin/tungsten -o /tmp/cv_spec bits/tungsten-koala/spec/cross_validation_spec.w && /tmp/cv_spec
#
# (KFold's own folds and the integer-k CrossValidation cases live in
# spec/estimator_spec.w, where they were written; nothing here changes
# them. This file is the SPLITTER file.)
#
# EVERY fold membership below is HAND-COMPUTED from the algorithm
# documented in lib/cross_validation.w, and was independently reproduced
# by a separate reference implementation before being written down —
# these are not recordings of what the code happened to print.
#
# Folds are compared through `join(",")` rather than `to_s`: compiled
# Array `==` is identity, and Array#to_s differs between engines for some
# element types. No float literals appear here; the one float comparison
# derives its operand via .to_f, the convention in the sibling specs.

use spec
use koala

# --- helpers (spec-local; prefixed cv_ to stay out of koala's way) ---

# How many rows on side `side` of `pair` (0 = train, 1 = test) carry the
# label `want`.
-> cv_count(pair, side, labels, want)
  total = 0
  pair[side].each -> (ix)
    total += 1 if labels[ix].to_s == want.to_s
  total

# The distinct group names appearing on side `side` of `pair`.
-> cv_names(pair, side, groups)
  names = []
  pair[side].each -> (ix)
    nm = groups[ix].to_s
    names.push(nm) if !names.include?(nm)
  names

# true when ANY group has rows in both the train and the test side —
# exactly the leak GroupKFold exists to prevent.
-> cv_group_spans(pair, groups)
  train_names = cv_names(pair, 0, groups)
  found = false
  cv_names(pair, 1, groups).each -> (nm)
    found = true if train_names.include?(nm)
  found

# true when train and test together cover 0...n exactly once each.
-> cv_partitions(pair, n)
  seen = []
  n.times -> (i)
    seen.push(0)
  pair[0].each -> (ix)
    seen[ix] = seen[ix] + 1
  pair[1].each -> (ix)
    seen[ix] = seen[ix] + 1
  ok = true
  seen.each -> (c)
    ok = false if c != 1
  ok

# true when every training row precedes every test row — no fold may see
# the future.
-> cv_train_precedes_test(pair)
  latest = 0 - 1
  pair[0].each -> (ix)
    latest = ix if ix > latest
  ok = true
  pair[1].each -> (ix)
    ok = false if ix <= latest
  ok

describe "StratifiedKFold" ->
  # THE POINT OF THE CLASS, asserted directly. y is 8 zeros then 4 ones —
  # a 2:1 ratio — and k = 4. Each class is dealt round-robin, so class 0's
  # eight members land 0,1,2,3,0,1,2,3 and class 1's four land 0,1,2,3:
  # every fold tests exactly two 0s and one 1, the global ratio, and
  # trains on exactly six 0s and three 1s.
  it "preserves each class's proportion in every fold" ->
    y = [0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1]
    folds = StratifiedKFold.new(4).split(y)
    expect(folds.size).to eq(4)
    expect(folds[0][1].join(",")).to eq("0,4,8")
    expect(folds[1][1].join(",")).to eq("1,5,9")
    expect(folds[2][1].join(",")).to eq("2,6,10")
    expect(folds[3][1].join(",")).to eq("3,7,11")
    ratio_held = true
    folds.each -> (pair)
      ratio_held = false if cv_count(pair, 1, y, 0) != 2
      ratio_held = false if cv_count(pair, 1, y, 1) != 1
      ratio_held = false if cv_count(pair, 0, y, 0) != 6
      ratio_held = false if cv_count(pair, 0, y, 1) != 3
    expect(ratio_held).to be_true

  # THE CASE PLAIN KFold GETS WRONG. y is sorted — six 0s then three 1s —
  # so KFold's contiguous third fold tests ONLY class 1 and trains on
  # ZERO examples of it. StratifiedKFold's folds are 0,3,6 / 1,4,7 /
  # 2,5,8: two 0s and one 1 in each, and both classes always in train.
  it "keeps both classes in every fold where contiguous KFold loses one" ->
    y = [0, 0, 0, 0, 0, 0, 1, 1, 1]
    plain = KFold.new(3).split(9)
    expect(plain[2][1].join(",")).to eq("6,7,8")
    expect(cv_count(plain[2], 1, y, 0)).to eq(0)   # test set is 100% class 1
    expect(cv_count(plain[2], 0, y, 1)).to eq(0)   # trained on NO class 1
    folds = StratifiedKFold.new(3).split(y)
    expect(folds[0][1].join(",")).to eq("0,3,6")
    expect(folds[1][1].join(",")).to eq("1,4,7")
    expect(folds[2][1].join(",")).to eq("2,5,8")
    both_sides = true
    folds.each -> (pair)
      both_sides = false if cv_count(pair, 1, y, 0) != 2
      both_sides = false if cv_count(pair, 1, y, 1) != 1
      both_sides = false if cv_count(pair, 0, y, 0) != 4
      both_sides = false if cv_count(pair, 0, y, 1) != 2
    expect(both_sides).to be_true

  # The deal RESUMES where the last class stopped instead of restarting
  # at fold 0, which is what keeps fold SIZES even: three classes of four
  # into three folds gives 4/4/4. Restarting each class at fold 0 would
  # have given a lopsided 6/3/3 — the reason for the rotation.
  it "balances fold sizes by resuming the deal at the next fold" ->
    y = [:a, :a, :a, :a, :b, :b, :b, :b, :c, :c, :c, :c]
    folds = StratifiedKFold.new(3).split(y)
    expect(folds[0][1].join(",")).to eq("0,3,6,9")
    expect(folds[1][1].join(",")).to eq("1,4,7,10")
    expect(folds[2][1].join(",")).to eq("2,5,8,11")
    even = true
    covered = true
    folds.each -> (pair)
      even = false if pair[1].size != 4
      covered = false if cv_count(pair, 1, y, :a) < 1
      covered = false if cv_count(pair, 1, y, :b) < 1
      covered = false if cv_count(pair, 1, y, :c) < 1
      covered = false if !cv_partitions(pair, 12)
    expect(even).to be_true
    expect(covered).to be_true

  # A seed shuffles through Splitter.indices first — seed 42 permutes
  # 0..9 to 0,1,4,3,8,9,7,5,6,2 — and the classes are then dealt in THAT
  # order, so class 0 is dealt 0,1,4,3,2 and class 1 is dealt 8,9,7,5,6.
  # Folds stay perfectly stratified (one of each class each) and the same
  # seed reproduces them on both engines.
  it "shuffles deterministically with a seed and stays stratified" ->
    y = [0, 0, 0, 0, 0, 1, 1, 1, 1, 1]
    folds = StratifiedKFold.new(5, 42).split(y)
    expect(folds.size).to eq(5)
    expect(folds[0][1].join(",")).to eq("0,8")
    expect(folds[2][1].join(",")).to eq("4,7")
    expect(folds[4][1].join(",")).to eq("6,2")
    balanced = true
    folds.each -> (pair)
      balanced = false if cv_count(pair, 1, y, 0) != 1
      balanced = false if cv_count(pair, 1, y, 1) != 1
    expect(balanced).to be_true
    again = StratifiedKFold.new(5, 42).split(y)
    expect(again[3][1].join(",")).to eq(folds[3][1].join(","))

  # Labels are opaque and compared by to_s, so a symbol and its string
  # form are the SAME class (two classes of two here, not four of one).
  it "compares labels by to_s, so :a and the string a are one class" ->
    folds = StratifiedKFold.new(2).split([:a, "a", :b, "b"])
    expect(folds.size).to eq(2)
    expect(folds[0][1].join(",")).to eq("0,2")
    expect(folds[1][1].join(",")).to eq("1,3")

  # Degenerate input is nil, never an exception — the bit's convention.
  # A class with fewer than k members is the interesting one: it could
  # not appear in every fold, so the split would not be stratified and
  # koala refuses rather than quietly returning something else.
  it "returns nil for degenerate input" ->
    expect(StratifiedKFold.new(3).split([0, 0, 0, 1])).to be_nil    # class 1 has 1 < 3
    expect(StratifiedKFold.new(1).split([0, 0, 1, 1])).to be_nil    # k < 2
    expect(StratifiedKFold.new(5).split([0, 0, 1, 1])).to be_nil    # k > n
    expect(StratifiedKFold.new(2).split([])).to be_nil
    expect(StratifiedKFold.new(2).split(nil)).to be_nil

describe "LeaveOneOut" ->
  # n folds, each holding out exactly one row, training on the rest in
  # order — the k = n limit of KFold.
  it "holds out exactly one sample per fold" ->
    folds = LeaveOneOut.new.split(4)
    expect(folds.size).to eq(4)
    expect(folds[0][1].join(",")).to eq("0")
    expect(folds[0][0].join(",")).to eq("1,2,3")
    expect(folds[2][1].join(",")).to eq("2")
    expect(folds[2][0].join(",")).to eq("0,1,3")
    expect(folds[3][0].join(",")).to eq("0,1,2")
    partitioned = true
    folds.each -> (pair)
      partitioned = false if !cv_partitions(pair, 4)
    expect(partitioned).to be_true

  it "returns nil when there is nothing to train on" ->
    expect(LeaveOneOut.new.split(1)).to be_nil
    expect(LeaveOneOut.new.split(0)).to be_nil

describe "GroupKFold" ->
  # THE POINT OF THE CLASS. Groups a and b alternate, so plain KFold's
  # contiguous halves put PART of each group on both sides of the split —
  # the model trains on some of group a and is tested on the rest of it,
  # which measures memorization, not generalization. GroupKFold sends
  # whole groups: 0,2,4 against 1,3,5.
  it "never lets a group span train and test, where KFold does" ->
    groups = [:a, :b, :a, :b, :a, :b]
    plain = KFold.new(2).split(6)
    expect(plain[0][1].join(",")).to eq("0,1,2")
    expect(cv_group_spans(plain[0], groups)).to be_true    # KFold leaks
    folds = GroupKFold.new(2).split(groups)
    expect(folds.size).to eq(2)
    expect(folds[0][1].join(",")).to eq("0,2,4")
    expect(folds[1][1].join(",")).to eq("1,3,5")
    clean = true
    folds.each -> (pair)
      clean = false if cv_group_spans(pair, groups)
      clean = false if !cv_partitions(pair, 6)
    expect(clean).to be_true

  # Groups are placed LARGEST FIRST, each into the fold holding the
  # fewest rows so far: a(4) -> fold 0, b(3) -> fold 1, c(2) -> fold 2,
  # then d(1) joins fold 2 (2 rows, the lightest). Fold sizes 4/3/3.
  it "assigns the largest group first, to the lightest fold" ->
    groups = [:a, :a, :a, :a, :b, :b, :b, :c, :c, :d]
    folds = GroupKFold.new(3).split(groups)
    expect(folds.size).to eq(3)
    expect(folds[0][1].join(",")).to eq("0,1,2,3")
    expect(folds[1][1].join(",")).to eq("4,5,6")
    expect(folds[2][1].join(",")).to eq("7,8,9")
    clean = true
    folds.each -> (pair)
      clean = false if cv_group_spans(pair, groups)
    expect(clean).to be_true

  it "returns nil when there are fewer groups than folds" ->
    expect(GroupKFold.new(3).split([:a, :a, :b, :b])).to be_nil
    expect(GroupKFold.new(1).split([:a, :b, :c])).to be_nil
    expect(GroupKFold.new(2).split([])).to be_nil
    expect(GroupKFold.new(2).split(nil)).to be_nil

describe "TimeSeriesSplit" ->
  # Expanding window: fold f trains on a PREFIX and tests on the block
  # after it. n = 12, k = 3 gives blocks of 12 / (3 + 1) = 3, and the
  # three tested blocks are the last three. The earliest block is never
  # tested — it is the history every fold needs.
  it "expands the training window and never trains on the future" ->
    folds = TimeSeriesSplit.new(3).split(12)
    expect(folds.size).to eq(3)
    expect(folds[0][0].join(",")).to eq("0,1,2")
    expect(folds[0][1].join(",")).to eq("3,4,5")
    expect(folds[1][0].join(",")).to eq("0,1,2,3,4,5")
    expect(folds[1][1].join(",")).to eq("6,7,8")
    expect(folds[2][0].join(",")).to eq("0,1,2,3,4,5,6,7,8")
    expect(folds[2][1].join(",")).to eq("9,10,11")
    ordered = true
    folds.each -> (pair)
      ordered = false if !cv_train_precedes_test(pair)
    expect(ordered).to be_true

  # Integer division, scikit-learn's rule: n = 10, k = 3 gives blocks of
  # 2 and the first four rows are history only.
  it "sizes blocks by integer division, leaving the remainder as history" ->
    folds = TimeSeriesSplit.new(3).split(10)
    expect(folds[0][0].join(",")).to eq("0,1,2,3")
    expect(folds[0][1].join(",")).to eq("4,5")
    expect(folds[1][1].join(",")).to eq("6,7")
    expect(folds[2][1].join(",")).to eq("8,9")

  # A gap drops rows between the train prefix and the test block — the
  # guard against leaking through autocorrelation. n = 9, k = 2, gap = 1:
  # blocks of 3 starting at 3, so rows 2 and 5 are dropped from training.
  it "drops gap rows between train and test" ->
    folds = TimeSeriesSplit.new(2, 1).split(9)
    expect(folds.size).to eq(2)
    expect(folds[0][0].join(",")).to eq("0,1")
    expect(folds[0][1].join(",")).to eq("3,4,5")
    expect(folds[1][0].join(",")).to eq("0,1,2,3,4")
    expect(folds[1][1].join(",")).to eq("6,7,8")

  it "returns nil when the data cannot fill k + 1 blocks" ->
    expect(TimeSeriesSplit.new(5).split(5)).to be_nil    # 5 / 6 = 0 rows per block
    expect(TimeSeriesSplit.new(1).split(10)).to be_nil   # k < 2
    expect(TimeSeriesSplit.new(2).split(0)).to be_nil
    expect(TimeSeriesSplit.new(2, 3).split(9)).to be_nil # gap eats the first train set

describe "ShuffleSplit" ->
  # Independent random hold-outs, not a partition: repetition r draws the
  # r-th MINSTD state from the seed and takes the last 30% of that
  # permutation. Hand-computed from Splitter.indices with the seeds
  # 42*48271 mod 2^31-1 and its successor.
  it "draws repeated hold-outs deterministically from one seed" ->
    folds = ShuffleSplit.new(2, 30, 42).split(10)
    expect(folds.size).to eq(2)
    expect(folds[0][1].join(",")).to eq("9,2,7")
    expect(folds[1][1].join(",")).to eq("2,5,7")
    sized = true
    folds.each -> (pair)
      sized = false if pair[1].size != 3
      sized = false if pair[0].size != 7
      sized = false if !cv_partitions(pair, 10)
    expect(sized).to be_true

  # Successive repetitions ADVANCE the stream rather than using seed + r,
  # so the draws differ; the same seed still reproduces them exactly.
  it "gives different draws per repetition and repeats on the same seed" ->
    a = ShuffleSplit.new(3, 25, 7).split(8)
    expect(a[0][1].join(",")).to eq("3,6")
    expect(a[1][1].join(",")).to eq("1,6")
    expect(a[2][1].join(",")).to eq("7,1")
    b = ShuffleSplit.new(3, 25, 7).split(8)
    expect(b[2][1].join(",")).to eq(a[2][1].join(","))
    expect(b[0][0].join(",")).to eq(a[0][0].join(","))

  it "returns nil when the percentage leaves no test or no train rows" ->
    expect(ShuffleSplit.new(2, 0, 1).split(10)).to be_nil
    expect(ShuffleSplit.new(2, 100, 1).split(10)).to be_nil
    expect(ShuffleSplit.new(2, 30, 1).split(1)).to be_nil
    expect(ShuffleSplit.new(0, 30, 1).split(10)).to be_nil

describe "the splitter contract" ->
  # Every splitter answers ONE method, folds(n, y) — that is the whole
  # entry fee for working with CrossValidation. `is Splitting` is a
  # DECLARATION, not enforcement, so the conformance is asserted here
  # (the estimator-contract convention), via the STRING form of
  # respond_to?, the only one that answers on both engines.
  it "is answered by every splitter" ->
    answers = true
    answers = false if !KFold.new(2).respond_to?("folds")
    answers = false if !StratifiedKFold.new(2).respond_to?("folds")
    answers = false if !LeaveOneOut.new.respond_to?("folds")
    answers = false if !GroupKFold.new(2).respond_to?("folds")
    answers = false if !TimeSeriesSplit.new(2).respond_to?("folds")
    answers = false if !ShuffleSplit.new(2).respond_to?("folds")
    expect(answers).to be_true

  # The adapter forwards to each splitter's natural split. KFold ignores
  # y (it needs only the count); StratifiedKFold requires it.
  it "forwards to each splitter's natural split" ->
    expect(KFold.new(3).folds(9, nil)[1][1].join(",")).to eq(KFold.new(3).split(9)[1][1].join(","))
    expect(LeaveOneOut.new.folds(4, nil).size).to eq(4)
    expect(TimeSeriesSplit.new(3).folds(12, nil)[0][1].join(",")).to eq("3,4,5")
    expect(ShuffleSplit.new(2, 30, 42).folds(10, nil)[0][1].join(",")).to eq("9,2,7")
    y = [0, 0, 0, 0, 0, 0, 1, 1, 1]
    expect(StratifiedKFold.new(3).folds(9, y)[0][1].join(",")).to eq("0,3,6")
    groups = [:a, :b, :a, :b, :a, :b]
    expect(GroupKFold.new(2, groups).folds(6, nil)[0][1].join(",")).to eq("0,2,4")

  # A stratified request without labels is nil, NOT a silent fall back to
  # plain KFold — quietly unstratifying a stratified request is the exact
  # bug StratifiedKFold was written to prevent. GroupKFold is the same
  # for its groups, which live on the constructor because a row's group
  # is not its target.
  it "refuses rather than silently unstratifying or ungrouping" ->
    y = [0, 0, 0, 0, 0, 0, 1, 1, 1]
    expect(StratifiedKFold.new(3).folds(9, nil)).to be_nil
    expect(StratifiedKFold.new(3).folds(8, y)).to be_nil     # length disagrees
    expect(GroupKFold.new(2).folds(6, nil)).to be_nil        # no groups given
    expect(GroupKFold.new(2, [:a, :b]).folds(6, nil)).to be_nil

  # splitter_for is the one place a `cv` argument is interpreted: an
  # integer means KFold, a splitter is itself, nil is nil.
  it "resolves an integer to KFold and a splitter to itself" ->
    expect(CrossValidation.splitter_for(3, nil).k).to eq(3)
    expect(CrossValidation.splitter_for(3, 42).seed).to eq(42)
    expect(CrossValidation.splitter_for(StratifiedKFold.new(4), nil).k).to eq(4)
    expect(CrossValidation.splitter_for(nil, nil)).to be_nil

describe "CrossValidation with a splitter" ->
  # BACK-COMPAT: an integer cv is exactly the old behaviour — KFold with
  # that many folds, optionally seeded. y = 2x + 1 is exactly linear, so
  # every fold recovers it and scores 1.
  it "still takes a plain fold count" ->
    x = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9]
    y = [1, 3, 5, 7, 9, 11, 13, 15, 17, 19]
    expect(CrossValidation.cross_val_score(LinearRegression.new, x, y, 5).to_s).to eq("\[1, 1, 1, 1, 1\]")
    expect(CrossValidation.cross_val_score(LinearRegression.new, x, y, 5, 42).to_s).to eq("\[1, 1, 1, 1, 1\]")
    expect(CrossValidation.cross_val_mean(LinearRegression.new, x, y, 5).to_s).to eq("1")

  # THE PAYOFF, end to end. Six class-0 points around the origin, three
  # class-1 points around (10, 10), labels sorted. Under plain 3-fold
  # KFold the last fold trains only on class 0 and is tested only on
  # class 1, so 1-NN gets every one of them wrong: fold scores 1, 1, 0.
  # The same data under StratifiedKFold scores 1, 1, 1 — and the
  # difference is entirely the splitter.
  it "rescues a classification score that plain KFold gets wrong" ->
    x = [[0, 0], [1, 0], [0, 1], [1, 1], [2, 0], [0, 2], [10, 10], [11, 10], [10, 11]]
    y = [0, 0, 0, 0, 0, 0, 1, 1, 1]
    plain = CrossValidation.cross_val_score(KNNClassifier.new(1), x, y, 3)
    expect(plain.to_s).to eq("\[1, 1, 0\]")
    strat = CrossValidation.cross_val_score(KNNClassifier.new(1), x, y, StratifiedKFold.new(3))
    expect(strat.to_s).to eq("\[1, 1, 1\]")
    expect(CrossValidation.cross_val_mean(KNNClassifier.new(1), x, y, StratifiedKFold.new(3)).to_s).to eq("1")
    expect(CrossValidation.cross_val_mean(KNNClassifier.new(1), x, y, 3) < 1.to_f).to be_true

  # Any splitter, same position. LeaveOneOut gives one fold per row;
  # TimeSeriesSplit gives k; ShuffleSplit gives its repetition count;
  # GroupKFold gives its fold count. The line is exactly linear, so every
  # fold that can be fitted scores 1.
  it "accepts any splitter in the fold-count position" ->
    x = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9]
    y = [1, 3, 5, 7, 9, 11, 13, 15, 17, 19]
    expect(CrossValidation.cross_val_score(LinearRegression.new, x, y, LeaveOneOut.new).size).to eq(10)
    expect(CrossValidation.cross_val_score(LinearRegression.new, x, y, TimeSeriesSplit.new(3)).to_s).to eq("\[1, 1, 1\]")
    expect(CrossValidation.cross_val_score(LinearRegression.new, x, y, ShuffleSplit.new(4, 30, 42)).size).to eq(4)
    groups = [0, 0, 0, 0, 0, 1, 1, 1, 1, 1]
    expect(CrossValidation.cross_val_score(LinearRegression.new, x, y, GroupKFold.new(2, groups)).size).to eq(2)
    expect(CrossValidation.cross_val_mean(LinearRegression.new, x, y, LeaveOneOut.new).to_s).to eq("1")

  # An UNSUPERVISED model may still be handed a y: KMeans never sees it
  # (fit_model passes fit(rows) on its own arity), but the SPLITTER does,
  # which is what lets a clustering run be stratified by a label it is
  # not allowed to learn from. Same two-cluster data and same -5 per fold
  # as the integer-k case.
  it "stratifies an unsupervised run by a label the model never sees" ->
    x = [[0, 0], [10, 10], [0, 1], [10, 11], [1, 0], [11, 10], [1, 1], [11, 11]]
    y = [0, 1, 0, 1, 0, 1, 0, 1]
    expect(CrossValidation.cross_val_score(KMeans.new(2), x, nil, 2).to_s).to eq("\[-5, -5\]")
    expect(CrossValidation.cross_val_score(KMeans.new(2), x, y, StratifiedKFold.new(2)).to_s).to eq("\[-5, -5\]")

  # A splitter that rejects the data rejects the whole run — nil, never
  # a raise, and never a quiet downgrade to unstratified folds.
  it "returns nil when the splitter rejects the data" ->
    x = [[0, 0], [1, 1], [10, 10], [11, 11]]
    y = [0, 0, 1, 1]
    expect(CrossValidation.cross_val_score(KMeans.new(2), x, nil, StratifiedKFold.new(2))).to be_nil
    expect(CrossValidation.cross_val_score(KNNClassifier.new(1), x, y, StratifiedKFold.new(3))).to be_nil
    expect(CrossValidation.cross_val_score(KNNClassifier.new(1), x, y, GroupKFold.new(2))).to be_nil
    expect(CrossValidation.cross_val_mean(KNNClassifier.new(1), x, y, TimeSeriesSplit.new(9))).to be_nil

  # GridSearch hands its `k` straight through to cross_val_mean, so it
  # searches on stratified folds with NO change to lib/grid_search.w —
  # the payoff of putting the choice behind one duck-typed argument.
  it "reaches GridSearch for free, through the same argument" ->
    x = [[0, 0], [1, 0], [0, 1], [1, 1], [2, 0], [0, 2], [10, 10], [11, 10], [10, 11]]
    y = [0, 0, 0, 0, 0, 0, 1, 1, 1]
    search = GridSearch.new(KNNClassifier.new(1), { k: [1, 3] }, StratifiedKFold.new(3))
    expect(search.fit(x, y) != nil).to be_true
    expect(search.best_score.to_s).to eq("1")
    expect(search.best_params[:k]).to eq(1)

spec_summary
