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

spec_summary
