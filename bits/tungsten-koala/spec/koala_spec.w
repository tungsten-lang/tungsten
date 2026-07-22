# Koala specs — Series / DataFrame / GroupBy / Metrics / Rolling / Join /
# Pivot, on the tungsten-spec framework.
#
# Run from the repo root (both engines, exit 0 = green):
#   bin/tungsten bits/tungsten-koala/spec/koala_spec.w
#   bin/tungsten -o /tmp/koala_spec bits/tungsten-koala/spec/koala_spec.w && /tmp/koala_spec
#
# spec/smoke.w asserts the same core behavior without the framework.

use spec
use koala

describe "Series" ->
  it "knows its size and aggregations" ->
    s = Series.new([3, 1, 4, 1, 5, 9, 2, 6], "digits")
    expect(s.size).to eq(8)
    expect(s.sum).to eq(31)
    expect(s.mean.to_s).to eq("3.875")
    expect(s.median.to_s).to eq("3.5")
    expect(s.min).to eq(1)
    expect(s.max).to eq(9)

  it "maps and selects with a block" ->
    s = Series.new([3, 1, 4], "d")
    doubled = s.map -> (v) v * 2
    expect(doubled.to_a.to_s).to eq("\[6, 2, 8\]")
    big = s.select -> (v) v > 2
    expect(big.to_a.to_s).to eq("\[3, 4\]")

  it "handles nils" ->
    s = Series.new([1, nil, 3], "gaps")
    expect(s.fillna(0).to_a.to_s).to eq("\[1, 0, 3\]")
    expect(s.dropna.to_a.to_s).to eq("\[1, 3\]")
    expect(s.count).to eq(2)

  it "computes quantiles by linear interpolation" ->
    s = Series.new([1, 2, 3, 4], "q")
    expect(s.quantile(25).to_s).to eq("1.75")
    expect(s.quantile(50).to_s).to eq("2.5")
    expect(s.quantile(75).to_s).to eq("3.25")

describe "DataFrame" ->
  it "constructs from ordered column pairs" ->
    df = DataFrame.new([[:a, [1, 2]], [:b, [3, 4]]])
    expect(df.shape.to_s).to eq("\[2, 2\]")
    expect(df[:a].sum).to eq(3)

  it "filters rows with where" ->
    df = DataFrame.new([[:age, [30, 25, 35]]])
    kept = df.where -> (row) row[:age] >= 30
    expect(kept.row_count).to eq(2)

  it "summarizes numeric columns with describe" ->
    # :name is non-numeric, so describe skips it (pandas' default).
    df = DataFrame.new([
      [:a, [1, 2, 3, 4]],
      [:name, ["x", "y", "z", "w"]],
      [:b, [10, 20, 30, 40]]
    ])
    d = df.describe
    expect(d.column_names.join(",")).to eq("statistic,a,b")
    expect(d.row_count).to eq(8)
    expect(d.column_values(:statistic).join(",")).to eq("count,mean,std,min,25%,50%,75%,max")
    # a = [1,2,3,4]: count 4, mean 2.5, sample std sqrt(5/3)=1.29099,
    # min 1, quartiles 1.75 / 2.5 / 3.25 (numpy 'linear'), max 4.
    expect(d.column_values(:a).join(",")).to eq("4,2.5,1.29099,1,1.75,2.5,3.25,4")
    # b = 10*a, so std scales 10x (12.9099) and the quartiles shift.
    expect(d.column_values(:b).join(",")).to eq("4,25,12.9099,10,17.5,25,32.5,40")

describe "Stats.percentile" ->
  it "interpolates linearly like numpy and pandas" ->
    # 0-based fractional rank p/100*(n-1); [1,2,3,4] -> 1.75/2.5/3.25.
    expect(Stats.percentile([1, 2, 3, 4], 25).to_s).to eq("1.75")
    expect(Stats.percentile([1, 2, 3, 4], 50).to_s).to eq("2.5")
    expect(Stats.percentile([1, 2, 3, 4], 75).to_s).to eq("3.25")
    # odd length lands on exact order statistics
    expect(Stats.percentile([1, 2, 3, 4, 5], 25).to_s).to eq("2")
    expect(Stats.percentile([1, 2, 3, 4, 5], 75).to_s).to eq("4")
    # p = 50 equals the median; p = 0/100 are min/max (unsorted input)
    expect(Stats.percentile([5, 1, 9, 3], 50).to_s).to eq(Stats.median([5, 1, 9, 3]).to_s)
    expect(Stats.percentile([5, 1, 9, 3], 0).to_s).to eq("1")
    expect(Stats.percentile([5, 1, 9, 3], 100).to_s).to eq("9")

  it "drops nils and handles small inputs" ->
    expect(Stats.percentile([1, nil, 2, 3, 4], 25).to_s).to eq("1.75")
    expect(Stats.percentile([7], 25).to_s).to eq("7")
    expect(Stats.percentile([], 50)).to be_nil

describe "GroupBy" ->
  it "counts and aggregates per group" ->
    df = DataFrame.new([
      [:dept, ["eng", "sales", "eng"]],
      [:salary, [80, 65, 95]]
    ])
    g = df.group_by(:dept)
    expect(g.size).to eq(2)
    expect(g.count.column_values(:count).to_s).to eq("\[2, 1\]")
    expect(g.sum(:salary).column_values(:salary).to_s).to eq("\[175, 65\]")

describe "Metrics" ->
  it "scores classification and regression" ->
    expect(Metrics.accuracy([1, 0, 1], [1, 0, 0]).to_s).to eq("0.666667")
    expect(Metrics.mse([2, 4, 6], [1, 5, 7]).to_s).to eq("1")
    expect(Metrics.r2([2, 4, 6], [1, 5, 7]).to_s).to eq("0.839286")

  it "computes precision, recall and F1 for a binary classifier" ->
    # preds = [1,1,1,0,0,1] vs actual = [1,0,0,0,1,1]:
    # TP=2, FP=2, FN=1 -> P = 2/4 = 0.5, R = 2/3, F1 = 4/7.
    preds = [1, 1, 1, 0, 0, 1]
    act = [1, 0, 0, 0, 1, 1]
    expect(Metrics.precision(preds, act).to_s).to eq("0.5")
    expect(Metrics.recall(preds, act).to_s).to eq("0.666667")
    expect(Metrics.f1(preds, act).to_s).to eq("0.571429")
    # pos_label = 0 flips the positive class: TP=1, FP=1, FN=2.
    expect(Metrics.precision(preds, act, 0).to_s).to eq("0.5")
    expect(Metrics.recall(preds, act, 0).to_s).to eq("0.333333")
    # scikit-learn zero-division convention: 0.0, never a divide error.
    expect(Metrics.precision([0, 0], [1, 0]).to_s).to eq("0")
    expect(Metrics.f1([0, 0], [0, 0]).to_s).to eq("0")

describe "Metrics.fbeta" ->
  # Same binary case as above: P = 0.5, R = 2/3. scikit-learn
  # fbeta_score references for that pair —
  #   beta = 2   -> 0.625               (recall-leaning)
  #   beta = 1   -> 0.5714285714285714  (== f1)
  #   beta = 1/2 -> 0.5263157894736842  (precision-leaning)
  #   beta = 0   -> 0.5                 (== precision)
  # beta is passed as an integer or a derived float — a float literal in
  # a call argument corrupts it on both engines.
  it "generalizes f1 with a beta that weights recall" ->
    preds = [1, 1, 1, 0, 0, 1]
    act = [1, 0, 0, 0, 1, 1]
    expect(Metrics.fbeta(preds, act, 2).to_s).to eq("0.625")
    expect(Metrics.fbeta(preds, act, 1.to_f / 2.to_f).to_s).to eq("0.526316")
    # The two endpoints of the sweep are metrics koala already had.
    expect(Metrics.fbeta(preds, act).to_s).to eq(Metrics.f1(preds, act).to_s)
    expect(Metrics.fbeta(preds, act, 0).to_s).to eq(Metrics.precision(preds, act).to_s)
    # R (2/3) exceeds P (0.5) here, so leaning on recall raises the score
    # and leaning on precision lowers it — beta orders the whole family.
    expect(Metrics.fbeta(preds, act, 2) > Metrics.f1(preds, act)).to be_true
    expect(Metrics.fbeta(preds, act, 1.to_f / 2.to_f) < Metrics.f1(preds, act)).to be_true

  it "honors pos_label and the zero-division convention" ->
    preds = [1, 1, 1, 0, 0, 1]
    act = [1, 0, 0, 0, 1, 1]
    # pos_label 0: P = 0.5, R = 1/3 -> F2 = 0.35714285714285715 (sklearn).
    expect(Metrics.fbeta(preds, act, 2, 0).to_s).to eq("0.357143")
    # Nothing predicted positive and nothing actually positive: 0.0, never
    # a divide error (scikit-learn's zero_division=0 default).
    expect(Metrics.fbeta([0, 0], [0, 0], 2).to_s).to eq("0")

describe "Metrics imbalanced-data scores" ->
  # The motivating case: 8 negatives, 2 positives, and a classifier that
  # always answers the majority class. Accuracy calls that a success at
  # 0.8; balanced accuracy, MCC and kappa each call it what it is.
  # scikit-learn references — balanced_accuracy_score 0.5,
  # matthews_corrcoef 0.0, cohen_kappa_score 0.0, f1_score 0.0.
  it "exposes the majority-class classifier accuracy flatters" ->
    act = [0, 0, 0, 0, 0, 0, 0, 0, 1, 1]
    preds = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
    expect(Metrics.accuracy(preds, act).to_s).to eq("0.8")
    expect(Metrics.balanced_accuracy(preds, act).to_s).to eq("0.5")
    expect(Metrics.matthews_corrcoef(preds, act).to_s).to eq("0")
    expect(Metrics.cohen_kappa(preds, act).to_s).to eq("0")

  # MCC is a correlation, so its range is [-1, 1]. scikit-learn's
  # matthews_corrcoef docstring example — y_true [1,1,1,0] against
  # y_pred [1,0,1,1] — is -0.3333333333333333, here in koala's
  # (predictions, actual) order.
  it "scores MCC 1 perfect, -1 inverted, and the sklearn reference" ->
    truth = [0, 1, 0, 1]
    expect(Metrics.matthews_corrcoef([0, 1, 0, 1], truth).to_s).to eq("1")
    expect(Metrics.matthews_corrcoef([1, 0, 1, 0], truth).to_s).to eq("-1")
    expect(Metrics.matthews_corrcoef([1, 0, 1, 1], [1, 1, 1, 0]).to_s).to eq("-0.333333")

  # scikit-learn's cohen_kappa_score docstring example:
  # y_true [2,0,2,2,0,1] against y_pred [0,0,2,2,0,2] = 0.4285714285714286.
  it "matches the scikit-learn cohen_kappa_score reference" ->
    expect(Metrics.cohen_kappa([0, 0, 2, 2, 0, 2], [2, 0, 2, 2, 0, 1]).to_s).to eq("0.428571")
    expect(Metrics.cohen_kappa([0, 1, 0, 1], [0, 1, 0, 1]).to_s).to eq("1")
    expect(Metrics.cohen_kappa([1, 0], [0, 1]).to_s).to eq("-1")

  # All three generalize to any number of classes. Same 3-class case the
  # ConfusionMatrix / ClassificationReport blocks use. scikit-learn:
  # balanced_accuracy_score 0.5555555555555555, matthews_corrcoef 0.5,
  # cohen_kappa_score 0.4782608695652174 — and balanced accuracy IS the
  # report's macro recall, by definition.
  it "generalizes to multiclass and ties back to the report" ->
    preds = [0, 1, 2, 2, 2, 0]
    act = [0, 0, 2, 2, 1, 0]
    rep = Metrics.classification_report(preds, act)
    tol = 1.to_f / 100000.to_f
    expect(Metrics.balanced_accuracy(preds, act).to_s).to eq("0.555556")
    expect(LinAlg.fabs(Metrics.balanced_accuracy(preds, act) - rep.macro_recall) < tol).to be_true
    expect(Metrics.matthews_corrcoef(preds, act).to_s).to eq("0.5")
    expect(Metrics.cohen_kappa(preds, act).to_s).to eq("0.478261")

  it "returns nil for unusable input and 0 where the score is undefined" ->
    expect(Metrics.balanced_accuracy([1], [1, 0])).to be_nil
    expect(Metrics.matthews_corrcoef([], [])).to be_nil
    expect(Metrics.cohen_kappa([1], [1, 0])).to be_nil
    # One class on both sides: the correlation and the chance correction
    # are both undefined (scikit-learn gives 0.0 and nan respectively) —
    # koala emits no nan, so both answer 0.0.
    expect(Metrics.matthews_corrcoef([1, 1], [1, 1]).to_s).to eq("0")
    expect(Metrics.cohen_kappa([1, 1], [1, 1]).to_s).to eq("0")
    # Balanced accuracy averages only the classes present in `actual`,
    # matching scikit-learn (0.5 here, the recall of the lone class).
    expect(Metrics.balanced_accuracy([1, 0], [1, 1]).to_s).to eq("0.5")

describe "Metrics regression family" ->
  # koala takes (predictions, actual); scikit-learn's y_pred / y_true.
  # Shared example: pred = [2,4,6] vs actual = [1,5,7], residuals
  # actual-pred = [-1,1,1].
  it "scores median_absolute_error, max_error and MAPE" ->
    pred = [2, 4, 6]
    act = [1, 5, 7]
    # |residuals| = [1,1,1]: median 1, max 1.
    expect(Metrics.median_absolute_error(pred, act).to_s).to eq("1")
    expect(Metrics.max_error(pred, act).to_s).to eq("1")
    # MAPE = mean(1/1, 1/5, 1/7) = 0.447619 (scikit-learn reference).
    expect(Metrics.mape(pred, act).to_s).to eq("0.447619")

  it "makes the median robust and max_error the worst miss" ->
    # |residuals| = [1,2,3,4,100]: mae is dragged to 22 by the outlier,
    # the median stays at the typical 3, max_error catches the 100.
    pred = [0, 0, 0, 0, 0]
    act = [1, 2, 3, 4, 100]
    expect(Metrics.mae(pred, act).to_s).to eq("22")
    expect(Metrics.median_absolute_error(pred, act).to_s).to eq("3")
    expect(Metrics.max_error(pred, act).to_s).to eq("100")

  it "scores explained_variance as r2's mean-corrected sibling" ->
    # residuals [-1,1,1] have a nonzero mean, so explained variance
    # (0.857143, scikit-learn) exceeds r2 (0.839286): it discounts the
    # constant offset r2's residual sum of squares still charges for.
    expect(Metrics.explained_variance([2, 4, 6], [1, 5, 7]).to_s).to eq("0.857143")
    expect(Metrics.r2([2, 4, 6], [1, 5, 7]).to_s).to eq("0.839286")
    # When residuals are mean-centered ([1,0,-1] here) the two coincide.
    expect(Metrics.explained_variance([1, 4, 7], [2, 4, 6]).to_s).to eq("0.75")
    expect(Metrics.r2([1, 4, 7], [2, 4, 6]).to_s).to eq("0.75")

  it "is exact for a perfect fit" ->
    expect(Metrics.median_absolute_error([1, 2, 3], [1, 2, 3]).to_s).to eq("0")
    expect(Metrics.max_error([1, 2, 3], [1, 2, 3]).to_s).to eq("0")
    expect(Metrics.mape([1, 2, 3], [1, 2, 3]).to_s).to eq("0")
    expect(Metrics.explained_variance([1, 2, 3], [1, 2, 3]).to_s).to eq("1")

describe "ConfusionMatrix" ->
  # pred vs actual, three classes. Rows are ACTUAL, columns PREDICTED,
  # classes in first-seen order over actual (0, 2, 1) then predictions:
  #        p0 p2 p1
  #   a0 [  2  0  1 ]   two 0s hit, one 0 called 1
  #   a2 [  0  2  0 ]   both 2s hit
  #   a1 [  0  1  0 ]   the lone 1 called 2
  it "tabulates actual-vs-predicted counts" ->
    pred = [0, 1, 2, 2, 2, 0]
    actual = [0, 0, 2, 2, 1, 0]
    cm = Metrics.confusion_matrix(pred, actual)
    expect(cm.labels.join(",")).to eq("0,2,1")
    expect(cm.matrix.to_s).to eq("\[\[2, 0, 1\], \[0, 2, 0\], \[0, 1, 0\]\]")
    expect(cm.count(0, 0)).to eq(2)
    expect(cm.count(2, 1)).to eq(0)
    expect(cm.count(1, 2)).to eq(1)
    expect(cm.count(9, 9)).to eq(0)

  it "reads back as a DataFrame keyed by predicted label" ->
    # pred [1,0,1] vs actual [1,1,0]: matrix [[1, 1], [1, 0]] over
    # labels [1, 0]; each predicted-label column is one matrix column.
    cm = Metrics.confusion_matrix([1, 0, 1], [1, 1, 0])
    df = cm.to_df
    expect(df.column_names.join(",")).to eq("actual,1,0")
    expect(df.column_values(:actual).join(",")).to eq("1,0")
    expect(df.column_values(1).to_s).to eq("\[1, 1\]")
    expect(df.column_values(0).to_s).to eq("\[1, 0\]")

describe "ClassificationReport" ->
  # Same 3-class case as ConfusionMatrix above. Per-class one-vs-rest:
  #   class 0: P 2/2 = 1,   R 2/3,       F1 0.8,  support 3
  #   class 2: P 2/3,       R 2/2 = 1,   F1 0.8,  support 2
  #   class 1: P 0,         R 0,         F1 0,    support 1
  it "generalizes precision/recall/f1 to every class" ->
    pred = [0, 1, 2, 2, 2, 0]
    actual = [0, 0, 2, 2, 1, 0]
    rep = Metrics.classification_report(pred, actual)
    tol = 1.to_f / 100000.to_f
    expect(rep.labels.join(",")).to eq("0,2,1")
    expect(LinAlg.fabs(rep.accuracy - 2.to_f / 3.to_f) < tol).to be_true
    expect(rep.precision(0).to_s).to eq("1")
    expect(LinAlg.fabs(rep.recall(0) - 2.to_f / 3.to_f) < tol).to be_true
    expect(rep.f1(0).to_s).to eq("0.8")
    expect(rep.support(0)).to eq(3)
    expect(LinAlg.fabs(rep.precision(2) - 2.to_f / 3.to_f) < tol).to be_true
    expect(rep.recall(2).to_s).to eq("1")
    expect(rep.support(2)).to eq(2)
    expect(rep.precision(1).to_s).to eq("0")
    expect(rep.f1(1).to_s).to eq("0")
    expect(rep.support(1)).to eq(1)
    expect(rep.precision(99)).to be_nil

  # macro = unweighted mean over classes; weighted = weighted by support.
  #   macro P/R = (1 + 2/3 + 0)/3 = 5/9;  macro F1 = (0.8+0.8+0)/3 = 8/15
  #   weighted P = (1*3 + 2/3*2 + 0)/6 = 13/18;  weighted R/F1 = 4/6 = 2/3
  it "averages across classes (macro and weighted)" ->
    pred = [0, 1, 2, 2, 2, 0]
    actual = [0, 0, 2, 2, 1, 0]
    rep = Metrics.classification_report(pred, actual)
    tol = 1.to_f / 100000.to_f
    expect(rep.total).to eq(6)
    expect(LinAlg.fabs(rep.macro_precision - 5.to_f / 9.to_f) < tol).to be_true
    expect(LinAlg.fabs(rep.macro_recall - 5.to_f / 9.to_f) < tol).to be_true
    expect(LinAlg.fabs(rep.macro_f1 - 8.to_f / 15.to_f) < tol).to be_true
    expect(LinAlg.fabs(rep.weighted_precision - 13.to_f / 18.to_f) < tol).to be_true
    expect(LinAlg.fabs(rep.weighted_recall - 2.to_f / 3.to_f) < tol).to be_true
    expect(LinAlg.fabs(rep.weighted_f1 - 2.to_f / 3.to_f) < tol).to be_true

  # The report's per-class scores must equal the binary Metrics with that
  # class as pos_label — the very case tested in the Metrics block above.
  it "agrees with the binary Metrics per class" ->
    pred = [1, 1, 1, 0, 0, 1]
    actual = [1, 0, 0, 0, 1, 1]
    rep = Metrics.classification_report(pred, actual)
    tol = 1.to_f / 100000.to_f
    expect(LinAlg.fabs(rep.precision(1) - Metrics.precision(pred, actual, 1)) < tol).to be_true
    expect(LinAlg.fabs(rep.recall(1) - Metrics.recall(pred, actual, 1)) < tol).to be_true
    expect(LinAlg.fabs(rep.f1(1) - Metrics.f1(pred, actual, 1)) < tol).to be_true
    expect(LinAlg.fabs(rep.precision(0) - Metrics.precision(pred, actual, 0)) < tol).to be_true
    expect(LinAlg.fabs(rep.recall(0) - Metrics.recall(pred, actual, 0)) < tol).to be_true
    expect(rep.accuracy.to_s).to eq("0.5")
    expect(rep.to_df.column_values(:label).join(",")).to eq("1,0,accuracy,macro avg,weighted avg")
    expect(rep.to_df.column_values(:support).to_s).to eq("\[3, 3, 6, 6, 6\]")

  # Micro averaging pools every class's TP / FP / FN into ONE table and
  # scores that once, so each SAMPLE weighs equally rather than each
  # class. For single-label multiclass every row contributes one
  # prediction and one truth, so a false positive for one class is a
  # false negative for another and all three micro scores collapse to the
  # accuracy — scikit-learn's precision_score / recall_score / f1_score
  # with average="micro" all return 0.6666666666666666 for this case,
  # exactly accuracy_score's value. macro (5/9, 8/15) differs, because
  # the classes here are uneven.
  it "pools classes into micro averages that equal the accuracy" ->
    preds = [0, 1, 2, 2, 2, 0]
    actual = [0, 0, 2, 2, 1, 0]
    rep = Metrics.classification_report(preds, actual)
    tol = 1.to_f / 100000.to_f
    expect(LinAlg.fabs(rep.micro_precision - 2.to_f / 3.to_f) < tol).to be_true
    expect(rep.micro_recall.to_s).to eq(rep.micro_precision.to_s)
    expect(rep.micro_f1.to_s).to eq(rep.micro_precision.to_s)
    expect(rep.micro_f1.to_s).to eq(rep.accuracy.to_s)
    expect(rep.micro_f1.to_s != rep.macro_f1.to_s).to be_true
    # The pooled contingency itself: 4 correct, and 2 misses that count
    # once as a false positive and once as a false negative.
    expect(rep.micro_counts.join(",")).to eq("4,2,2")

describe "Rolling" ->
  it "computes trailing-window aggregations" ->
    s = Series.new([1, 2, 3, 4, 5], "v")
    r = s.rolling(3)
    expect(r.sum.to_a.to_s).to eq("\[1, 3, 6, 9, 12\]")
    expect(r.mean.to_a.join(",")).to eq("1,1.5,2,3,4")
    expect(r.median.to_a.join(",")).to eq("1,1.5,2,3,4")
    expect(r.min.to_a.to_s).to eq("\[1, 1, 1, 2, 3\]")
    expect(r.max.to_a.to_s).to eq("\[1, 2, 3, 4, 5\]")
    expect(r.count.to_a.to_s).to eq("\[1, 2, 3, 3, 3\]")
    expect(r.var.to_a.join(",")).to eq("0,0.5,1,1,1")
    expect(r.std.to_a[2].to_s).to eq("1")

  it "respects min_periods" ->
    s = Series.new([1, 2, 3, 4, 5], "v")
    out = s.rolling(3, 3).sum.to_a
    expect(out[0]).to be_nil
    expect(out[1]).to be_nil
    expect(out[2]).to eq(6)
    expect(out[4]).to eq(12)

  it "drops nils from windows" ->
    s = Series.new([1, nil, 3], "gaps")
    r = s.rolling(2)
    expect(r.sum.to_a.to_s).to eq("\[1, 1, 3\]")
    expect(r.count.to_a.to_s).to eq("\[1, 1, 1\]")

describe "Join" ->
  it "inner joins on a key column" ->
    left = DataFrame.new([[:id, [1, 2, 3]], [:name, ["a", "b", "c"]]])
    right = DataFrame.new([[:id, [2, 3, 4]], [:score, [20, 30, 40]]])
    j = left.join(right, :id)
    expect(j.row_count).to eq(2)
    expect(j.column_names.join(",")).to eq("id,name,score")
    expect(j.column_values(:id).to_s).to eq("\[2, 3\]")
    expect(j.column_values(:name).join(",")).to eq("b,c")
    expect(j.column_values(:score).to_s).to eq("\[20, 30\]")
    expect(Join.inner(left, right, :id).row_count).to eq(2)

  it "left joins keep unmatched rows with nil cells" ->
    left = DataFrame.new([[:id, [1, 2, 3]], [:name, ["a", "b", "c"]]])
    right = DataFrame.new([[:id, [2, 3, 4]], [:score, [20, 30, 40]]])
    j = left.join(right, :id, :left)
    expect(j.row_count).to eq(3)
    expect(j.column_values(:id).to_s).to eq("\[1, 2, 3\]")
    scores = j.column_values(:score)
    expect(scores[0]).to be_nil
    expect(scores[1]).to eq(20)
    expect(scores[2]).to eq(30)
    expect(Join.left(left, right, :id).row_count).to eq(3)

  it "emits one row per duplicate right match" ->
    left = DataFrame.new([[:id, [2]], [:name, ["b"]]])
    right = DataFrame.new([[:id, [2, 2]], [:score, [7, 8]]])
    j = left.join(right, :id)
    expect(j.row_count).to eq(2)
    expect(j.column_values(:score).to_s).to eq("\[7, 8\]")

  it "suffixes colliding right column names" ->
    left = DataFrame.new([[:id, [1]], [:v, [10]]])
    right = DataFrame.new([[:id, [1]], [:v, [99]]])
    j = left.join(right, :id)
    expect(j.column_names.join(",")).to eq("id,v,v_right")
    expect(j.column_values("v_right").to_s).to eq("\[99\]")

describe "Pivot" ->
  it "builds a sum pivot table" ->
    df = DataFrame.new([
      [:city, ["nyc", "nyc", "sf", "sf", "nyc"]],
      [:product, ["a", "b", "a", "b", "a"]],
      [:sales, [1, 2, 3, 4, 5]]
    ])
    pt = df.pivot(:city, :product, :sales)
    expect(pt.shape.to_s).to eq("\[2, 3\]")
    expect(pt.column_names.join(",")).to eq("city,a,b")
    expect(pt.column_values(:city).join(",")).to eq("nyc,sf")
    expect(pt.column_values("a").to_s).to eq("\[6, 3\]")
    expect(pt.column_values("b").to_s).to eq("\[2, 4\]")

  it "supports the other aggregations" ->
    df = DataFrame.new([
      [:city, ["nyc", "nyc", "sf", "sf", "nyc"]],
      [:product, ["a", "b", "a", "b", "a"]],
      [:sales, [1, 2, 3, 4, 5]]
    ])
    expect(df.pivot(:city, :product, :sales, :mean).column_values("a").join(",")).to eq("3,3")
    expect(df.pivot(:city, :product, :sales, :median).column_values("a").join(",")).to eq("3,3")
    expect(df.pivot(:city, :product, :sales, :count).column_values("a").to_s).to eq("\[2, 1\]")
    expect(df.pivot(:city, :product, :sales, :min).column_values("a").to_s).to eq("\[1, 3\]")
    expect(df.pivot(:city, :product, :sales, :max).column_values("a").to_s).to eq("\[5, 3\]")
    expect(df.pivot(:city, :product, :sales, :first).column_values("a").to_s).to eq("\[1, 3\]")
    expect(df.pivot(:city, :product, :sales, :last).column_values("a").to_s).to eq("\[5, 3\]")

  it "leaves missing cells nil" ->
    df = DataFrame.new([
      [:k, ["x", "y"]],
      [:c, ["p", "q"]],
      [:v, [1, 2]]
    ])
    pt = Pivot.table(df, :k, :c, :v)
    q = pt.column_values("q")
    expect(q[0]).to be_nil
    expect(q[1]).to eq(2)

describe "RocCurve" ->
  # scikit-learn's own roc_curve docstring example:
  #   y = [1, 1, 2, 2], scores = [0.1, 0.4, 0.35, 0.8], pos_label = 2
  #   -> fpr = [0, 0, 0.5, 0.5, 1], tpr = [0, 0.5, 0.5, 1, 1], AUC = 0.75.
  # Every float derives from integers via .to_f (float literals corrupt
  # call arguments); 0.75 is exactly representable, so an exact string.
  it "matches the scikit-learn roc_curve reference example" ->
    scores = [1.to_f / 10.to_f, 4.to_f / 10.to_f, 35.to_f / 100.to_f, 8.to_f / 10.to_f]
    actual = [1, 1, 2, 2]
    c = Metrics.roc_curve(scores, actual, 2)
    expect(c != nil).to be_true
    expect(c.fpr.to_s).to eq("\[0, 0, 0.5, 0.5, 1\]")
    expect(c.tpr.to_s).to eq("\[0, 0.5, 0.5, 1, 1\]")
    expect(c.auc.to_s).to eq("0.75")
    expect(Metrics.roc_auc(scores, actual, 2).to_s).to eq("0.75")

  # The curve carries one point per distinct score plus a leading
  # reject-all point at the origin, so all three arrays share a length,
  # the first fpr/tpr are 0, and the leading threshold is max(score) + 1.
  it "prepends a reject-all point and aligns fpr / tpr / thresholds" ->
    scores = [8.to_f / 10.to_f, 6.to_f / 10.to_f, 3.to_f / 10.to_f]
    actual = [1, 0, 0]
    c = Metrics.roc_curve(scores, actual)
    expect(c.fpr.size).to eq(c.tpr.size)
    expect(c.fpr.size).to eq(c.thresholds.size)
    expect(c.fpr[0].to_s).to eq("0")
    expect(c.tpr[0].to_s).to eq("0")
    expect(c.thresholds[0].to_s).to eq("1.8")

  # AUC is the probability a random positive outranks a random negative,
  # crediting ties half (Mann-Whitney U). scores = [0.8, 0.6, 0.6, 0.3]
  # with actual = [1, 1, 0, 0] has one cross-class tie at 0.6, so of the
  # 4 positive/negative pairs 3 are ordered and 1 is a half -> 3.5/4 =
  # 0.875, and it equals the trapezoidal auc(fpr, tpr).
  it "credits tied scores half, matching auc(fpr, tpr)" ->
    scores = [8.to_f / 10.to_f, 6.to_f / 10.to_f, 6.to_f / 10.to_f, 3.to_f / 10.to_f]
    actual = [1, 1, 0, 0]
    c = Metrics.roc_curve(scores, actual)
    expect(c.auc.to_s).to eq("0.875")
    tol = 1.to_f / 1000000.to_f
    expect(LinAlg.fabs(c.auc - Metrics.auc(c.fpr, c.tpr)) < tol).to be_true

  # A perfect ranking scores 1, a perfectly inverted one 0, and all-tied
  # scores 0.5 (the chance diagonal) — the AUC extremes.
  it "scores perfect 1, inverted 0, all-tied 0.5" ->
    perfect = [1.to_f / 10.to_f, 2.to_f / 10.to_f, 8.to_f / 10.to_f, 9.to_f / 10.to_f]
    inverted = [9.to_f / 10.to_f, 8.to_f / 10.to_f, 2.to_f / 10.to_f, 1.to_f / 10.to_f]
    tied = [5.to_f / 10.to_f, 5.to_f / 10.to_f, 5.to_f / 10.to_f, 5.to_f / 10.to_f]
    labels = [0, 0, 1, 1]
    expect(Metrics.roc_auc(perfect, labels).to_s).to eq("1")
    expect(Metrics.roc_auc(inverted, labels).to_s).to eq("0")
    expect(Metrics.roc_auc(tied, labels).to_s).to eq("0.5")

  # nil (koala's requirement-not-met convention) when a class is absent —
  # AUC is undefined with no positives or no negatives — or when scores
  # and actual do not line up, or are empty.
  it "returns nil when a class is absent or inputs are misaligned" ->
    scores = [1.to_f / 10.to_f, 9.to_f / 10.to_f]
    expect(Metrics.roc_auc(scores, [1, 1])).to be_nil
    expect(Metrics.roc_auc(scores, [0, 0])).to be_nil
    expect(Metrics.roc_curve(scores, [1, 1])).to be_nil
    expect(Metrics.roc_auc(scores, [1])).to be_nil
    expect(Metrics.roc_auc([], [])).to be_nil

describe "Metrics.log_loss" ->
  # scikit-learn reference: log_loss([1, 0, 1, 0], [0.9, 0.1, 0.8, 0.35])
  # = 0.21616187468057912. koala takes scores first (the roc_auc order):
  # L = -mean(y*ln p + (1-y)*ln(1-p)). Every float derives from integers
  # via .to_f — a float literal corrupts call arguments on both engines.
  it "matches the scikit-learn log_loss reference example" ->
    scores = [9.to_f / 10.to_f, 1.to_f / 10.to_f, 8.to_f / 10.to_f, 35.to_f / 100.to_f]
    actual = [1, 0, 1, 0]
    expect(Metrics.log_loss(scores, actual).to_s).to eq("0.216162")

  # All probabilities at 0.5 is a coin flip: L = -ln(0.5) = ln 2 for any
  # labels, log loss's natural chance baseline.
  it "scores a coin flip as ln 2" ->
    half = [5.to_f / 10.to_f, 5.to_f / 10.to_f, 5.to_f / 10.to_f, 5.to_f / 10.to_f]
    expect(Metrics.log_loss(half, [1, 0, 1, 0]).to_s).to eq("0.693147")

  # A perfectly confident, perfectly correct classifier scores ~0: the
  # p = 1 / p = 0 extremes clip to [eps, 1 - eps] (eps = 1e-15) so the
  # loss is a hair above 0, not -inf, matching scikit-learn's clipping.
  it "scores a perfect confident classifier at ~0 via clipping" ->
    tol = 1.to_f / 1000000.to_f
    loss = Metrics.log_loss([1.to_f, 0.to_f], [1, 0])
    expect(LinAlg.fabs(loss) < tol).to be_true

  # pos_label selects the positive class, mirroring roc_auc: the scikit-learn
  # roc example (actual [1,1,2,2], pos_label 2, scores [0.1,0.4,0.35,0.8])
  # gives L = -mean(ln 0.9 + ln 0.6 + ln 0.35 + ln 0.8) = 0.472288.
  it "honors pos_label" ->
    scores = [1.to_f / 10.to_f, 4.to_f / 10.to_f, 35.to_f / 100.to_f, 8.to_f / 10.to_f]
    expect(Metrics.log_loss(scores, [1, 1, 2, 2], 2).to_s).to eq("0.472288")

  # Unlike roc_auc, a single present class is well-defined — log loss needs
  # no negatives to normalize. Two positives at 0.9 / 0.8:
  # L = -(ln 0.9 + ln 0.8) / 2 = 0.164252 (where roc_auc returns nil).
  it "is defined for a single class, where roc_auc is nil" ->
    scores = [9.to_f / 10.to_f, 8.to_f / 10.to_f]
    expect(Metrics.log_loss(scores, [1, 1]).to_s).to eq("0.164252")
    expect(Metrics.roc_auc(scores, [1, 1])).to be_nil

  # nil (koala's requirement-not-met convention) only when scores and
  # actual are misaligned or empty — never merely for a missing class.
  it "returns nil for misaligned or empty inputs" ->
    expect(Metrics.log_loss([9.to_f / 10.to_f, 1.to_f / 10.to_f], [1])).to be_nil
    expect(Metrics.log_loss([], [])).to be_nil

describe "PrecisionRecallCurve" ->
  # scikit-learn's own precision_recall_curve docstring example:
  #   y_true = [0, 0, 1, 1], probas_pred = [0.1, 0.4, 0.35, 0.8]
  #   -> precision  [0.5, 0.66666667, 0.5, 1, 1]
  #      recall     [1, 1, 0.5, 0.5, 0]
  #      thresholds [0.1, 0.35, 0.4, 0.8]
  #   average_precision_score = 0.8333333333333333.
  # Scores first, the roc_curve / log_loss order.
  it "matches the scikit-learn precision_recall_curve reference" ->
    scores = [1.to_f / 10.to_f, 4.to_f / 10.to_f, 35.to_f / 100.to_f, 8.to_f / 10.to_f]
    act = [0, 0, 1, 1]
    c = Metrics.precision_recall_curve(scores, act)
    expect(c != nil).to be_true
    expect(c.precision.join(",")).to eq("0.5,0.666667,0.5,1,1")
    expect(c.recall.join(",")).to eq("1,1,0.5,0.5,0")
    expect(c.thresholds.join(",")).to eq("0.1,0.35,0.4,0.8")
    expect(c.average_precision.to_s).to eq("0.833333")
    expect(Metrics.average_precision(scores, act).to_s).to eq("0.833333")
    # Points run in ASCENDING threshold order (recall falls from 1 to 0)
    # and the closing (recall 0, precision 1) point has no threshold, so
    # the curve arrays run one longer — scikit-learn's layout, and NOT
    # RocCurve's (descending, leading reject-all, all arrays equal).
    expect(c.precision.size).to eq(c.thresholds.size + 1)
    expect(c.recall.size).to eq(c.precision.size)

  # Why the PR curve exists. One positive among ten, ranked second: ROC
  # divides that single false positive by the eight negatives and reports
  # a confident 0.8888888888888888, while average precision divides by
  # what the model actually flagged and reports 0.5 (both scikit-learn).
  it "sees the imbalance ROC-AUC hides" ->
    scores = [90.to_f, 80.to_f, 70.to_f, 60.to_f, 50.to_f, 40.to_f, 30.to_f, 20.to_f, 10.to_f, 5.to_f]
    act = [0, 1, 0, 0, 0, 0, 0, 0, 0, 0]
    expect(Metrics.roc_auc(scores, act).to_s).to eq("0.888889")
    expect(Metrics.average_precision(scores, act).to_s).to eq("0.5")

  # AP extremes (scikit-learn): a perfect ranking 1, an inverted one
  # 0.41666666666666663, all-tied scores the POSITIVE RATE (0.5 here) —
  # AP's chance baseline is that rate, not roc_auc's flat 0.5.
  it "scores perfect 1, inverted 0.416667, all-tied at the positive rate" ->
    labels = [0, 0, 1, 1]
    expect(Metrics.average_precision([1.to_f, 2.to_f, 8.to_f, 9.to_f], labels).to_s).to eq("1")
    expect(Metrics.average_precision([9.to_f, 8.to_f, 2.to_f, 1.to_f], labels).to_s).to eq("0.416667")
    tied = [5.to_f, 5.to_f, 5.to_f, 5.to_f]
    expect(Metrics.average_precision(tied, labels).to_s).to eq("0.5")

  # Unlike roc_curve, a single present class still yields a curve — the
  # PR curve needs no negatives to normalize by. With no positives recall
  # is pinned at 1 and AP is 0; with no negatives precision is 1
  # throughout and AP is 1. Both are scikit-learn's conventions.
  it "is defined for a single class, where roc_curve is nil" ->
    scores = [9.to_f / 10.to_f, 8.to_f / 10.to_f]
    allpos = Metrics.precision_recall_curve(scores, [1, 1])
    expect(allpos.precision.join(",")).to eq("1,1,1")
    expect(allpos.recall.join(",")).to eq("1,0.5,0")
    expect(Metrics.average_precision(scores, [1, 1]).to_s).to eq("1")
    nopos = Metrics.precision_recall_curve(scores, [0, 0])
    expect(nopos.precision.join(",")).to eq("0,0,1")
    expect(nopos.recall.join(",")).to eq("1,1,0")
    expect(Metrics.average_precision(scores, [0, 0]).to_s).to eq("0")
    expect(Metrics.roc_curve(scores, [1, 1])).to be_nil

  it "returns nil only for misaligned or empty inputs" ->
    expect(Metrics.precision_recall_curve([1.to_f], [1, 0])).to be_nil
    expect(Metrics.average_precision([], [])).to be_nil

describe "Metrics.brier_score" ->
  # scikit-learn: brier_score_loss([0, 1, 1, 0], [0.1, 0.9, 0.8, 0.3])
  # = 0.0375. Scores first, the log_loss / roc_auc order.
  it "matches the scikit-learn brier_score_loss reference" ->
    scores = [1.to_f / 10.to_f, 9.to_f / 10.to_f, 8.to_f / 10.to_f, 3.to_f / 10.to_f]
    expect(Metrics.brier_score(scores, [0, 1, 1, 0]).to_s).to eq("0.0375")
    # Bounded, unlike log loss: 0 perfect, 0.25 a constant coin flip,
    # 1 the worst possible — confident and wrong on every row.
    expect(Metrics.brier_score([1.to_f, 0.to_f], [1, 0]).to_s).to eq("0")
    expect(Metrics.brier_score([5.to_f / 10.to_f, 5.to_f / 10.to_f], [1, 0]).to_s).to eq("0.25")
    expect(Metrics.brier_score([0.to_f, 1.to_f], [1, 0]).to_s).to eq("1")

  # Calibration, not ranking. Two models rank these rows identically —
  # roc_auc says 1 for both — but one commits and one hedges, and the
  # Brier score separates them: 0.00025 against 0.18125 (scikit-learn).
  it "measures calibration where roc_auc measures only ranking" ->
    confident = [99.to_f / 100.to_f, 98.to_f / 100.to_f, 2.to_f / 100.to_f, 1.to_f / 100.to_f]
    timid = [6.to_f / 10.to_f, 55.to_f / 100.to_f, 45.to_f / 100.to_f, 4.to_f / 10.to_f]
    act = [1, 1, 0, 0]
    expect(Metrics.roc_auc(confident, act).to_s).to eq("1")
    expect(Metrics.roc_auc(timid, act).to_s).to eq("1")
    expect(Metrics.brier_score(confident, act).to_s).to eq("0.00025")
    expect(Metrics.brier_score(timid, act).to_s).to eq("0.18125")

  # pos_label mirrors log_loss / roc_auc: the roc reference example with
  # actual [1,1,2,2] and pos_label 2 scores 0.158125 (scikit-learn).
  it "honors pos_label and returns nil for unusable input" ->
    scores = [1.to_f / 10.to_f, 4.to_f / 10.to_f, 35.to_f / 100.to_f, 8.to_f / 10.to_f]
    expect(Metrics.brier_score(scores, [1, 1, 2, 2], 2).to_s).to eq("0.158125")
    expect(Metrics.brier_score([1.to_f], [1, 0])).to be_nil
    expect(Metrics.brier_score([], [])).to be_nil

describe "Metrics.silhouette_score" ->
  # Two tight clusters, far apart. scikit-learn's silhouette_score for
  # x = [[0,0],[0,1],[10,0],[10,1]] with labels [0,0,1,1] is
  # 0.9002487577582194. Mislabel the same points [0,1,0,1] and it goes
  # NEGATIVE, -0.4475062189439555 — a negative silhouette means rows sit
  # closer to another cluster than to their own.
  it "matches the scikit-learn silhouette_score reference" ->
    x = [[0, 0], [0, 1], [10, 0], [10, 1]]
    expect(Metrics.silhouette_score(x, [0, 0, 1, 1]).to_s).to eq("0.900249")
    expect(Metrics.silhouette_score(x, [0, 1, 0, 1]).to_s).to eq("-0.447506")

  # Three clusters on a line, given as rows and as a FLAT array (one
  # feature per row) — both 0.8764474173169825 in scikit-learn. Labels
  # are opaque: strings cluster exactly as integers do (the string case
  # is 0.899749373433584).
  it "handles many clusters, single-feature rows and opaque labels" ->
    rows = [[1], [2], [8], [9], [20], [21]]
    flat = [1, 2, 8, 9, 20, 21]
    labels = [0, 0, 1, 1, 2, 2]
    expect(Metrics.silhouette_score(rows, labels).to_s).to eq("0.876447")
    expect(Metrics.silhouette_score(flat, labels).to_s).to eq("0.876447")
    expect(Metrics.silhouette_score([0, 1, 10, 11], ["a", "a", "b", "b"]).to_s).to eq("0.899749")

  # A row alone in its cluster scores 0, not 1 — scikit-learn's rule,
  # since there is no within-cluster distance to compare against. Here
  # x = [0, 1, 10] with labels [0, 0, 1] gives
  # (0.9 + 0.888889 + 0) / 3 = 0.5962962962962962.
  it "scores a singleton cluster 0" ->
    expect(Metrics.silhouette_score([0, 1, 10], [0, 0, 1]).to_s).to eq("0.596296")

  # The measurement KMeans was missing. KMeans reports `inertia`, which
  # falls monotonically as k grows and so can only rank fits at the SAME
  # k — it can never say whether a clustering is good. The silhouette
  # normalizes cohesion by separation, so it is comparable across k and
  # is how k gets chosen. The estimator spec's separable 8-point case
  # (inertia exactly 16) scores 0.8390486223330011 in scikit-learn.
  it "scores a fitted KMeans clustering, which inertia cannot" ->
    x = [[0, 0], [2, 0], [0, 2], [2, 2], [10, 10], [12, 10], [10, 12], [12, 12]]
    model = KMeans.new(2)
    model.fit(x)
    expect(model.inertia.to_s).to eq("16")
    expect(model.labels.join(",")).to eq("0,0,0,0,1,1,1,1")
    expect(Metrics.silhouette_score(x, model.labels).to_s).to eq("0.839049")
    # The silhouette also RANKS clusterings inertia cannot compare: the
    # correct 2-cluster split beats a split that cuts across both blobs.
    wrong = [0, 1, 0, 1, 0, 1, 0, 1]
    expect(Metrics.silhouette_score(x, model.labels) > Metrics.silhouette_score(x, wrong)).to be_true

  # nil where the score is undefined: one cluster has nothing to separate
  # from, and n clusters over n rows leaves every row a singleton
  # (scikit-learn raises ValueError for both — valid counts are 2 to
  # n - 1), or the inputs simply do not line up.
  it "returns nil when the clustering is degenerate or misaligned" ->
    expect(Metrics.silhouette_score([0, 1, 2], [0, 0, 0])).to be_nil
    expect(Metrics.silhouette_score([0, 1, 2], [0, 1, 2])).to be_nil
    expect(Metrics.silhouette_score([0, 1], [0])).to be_nil
    expect(Metrics.silhouette_score([], [])).to be_nil

spec_summary
