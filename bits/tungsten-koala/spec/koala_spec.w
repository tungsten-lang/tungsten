# Koala specs — Series / DataFrame / GroupBy / Metrics vertical slice.
#
# Follows the bits/tungsten-forge/spec pattern (use spec + describe/it).
# NOTE: tungsten-spec's runner cannot execute yet on either engine — its
# classes live under `in Tungsten:Spec`, and namespaced classes are not
# resolvable from user scripts (forge's specs fail the same way, with
# "Undefined class 'Context'"). Until that lands, run spec/smoke.w, which
# asserts the same behavior and passes today interpreted AND compiled.

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

describe "DataFrame" ->
  it "constructs from ordered column pairs" ->
    df = DataFrame.new([[:a, [1, 2]], [:b, [3, 4]]])
    expect(df.shape.to_s).to eq("\[2, 2\]")
    expect(df[:a].sum).to eq(3)

  it "filters rows with where" ->
    df = DataFrame.new([[:age, [30, 25, 35]]])
    kept = df.where -> (row) row[:age] >= 30
    expect(kept.row_count).to eq(2)

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
