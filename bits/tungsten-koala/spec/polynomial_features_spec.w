# PolynomialFeatures specs and nonlinear pipeline reference problems.

use spec
use koala

describe "PolynomialFeatures" ->
  it "matches scikit-learn's degree-2 feature order and values" ->
    poly = PolynomialFeatures.new(2)
    out = poly.fit_transform([[2, 3], [4, 5]])
    expect(out.column_names.join(",")).to eq("x0,x1,x0^2,x0*x1,x1^2")
    expect(out.to_matrix.to_a.to_s).to eq("\[\[2, 3, 4, 6, 9\], \[4, 5, 16, 20, 25\]\]")
    expect(poly.feature_names_out.join(",")).to eq("x0,x1,x0^2,x0*x1,x1^2")

  it "supports a bias column and interaction-only expansion" ->
    poly = PolynomialFeatures.new(3, true, true)
    out = poly.fit_transform([[2, 3, 5]])
    expect(out.column_names.join(",")).to eq("1,x0,x1,x2,x0*x1,x0*x2,x1*x2,x0*x1*x2")
    expect(out.to_matrix.to_a.to_s).to eq("\[\[1, 2, 3, 5, 6, 10, 15, 30\]\]")

  it "preserves DataFrame feature names" ->
    df = DataFrame.new([[:width, [2]], [:height, [3]]])
    out = PolynomialFeatures.new(2).fit_transform(df)
    expect(out.column_names.join(",")).to eq("width,height,width^2,width*height,height^2")

  it "rejects unusable input and schema drift" ->
    expect(PolynomialFeatures.new(0).fit([[1, 2]])).to be_nil
    expect(PolynomialFeatures.new(2).fit([])).to be_nil
    expect(PolynomialFeatures.new(2).fit([[1, nil]])).to be_nil
    expect(PolynomialFeatures.new(2).fit([["x", 1]])).to be_nil
    poly = PolynomialFeatures.new(2)
    poly.fit(DataFrame.new([[:a, [1, 2]], [:b, [3, 4]]]))
    expect(poly.transform(DataFrame.new([[:b, [3]], [:a, [1]]]))).to be_nil

  it "is tunable and persists exact learned behavior" ->
    poly = PolynomialFeatures.new(2)
    expect(poly.params[:degree]).to eq(2)
    cube = poly.with_params({ degree: 3, include_bias: true })
    expect(cube.degree).to eq(3)
    expect(cube.include_bias).to be_true
    expect(cube.fitted?).to be_false
    poly.fit([[2, 3]])
    again = Persist.loads(Persist.dumps(poly))
    expect(again.feature_names_out.join(",")).to eq(poly.feature_names_out.join(","))
    expect(again.transform([[4, 5]]).to_matrix.to_a.to_s).to eq(poly.transform([[4, 5]]).to_matrix.to_a.to_s)

describe "nonlinear reference pipeline" ->
  # XOR is not linearly separable in the raw x0/x1 plane. Degree-2
  # expansion adds x0*x1, after which ordinary logistic regression can
  # represent the decision boundary.
  it "solves XOR with polynomial expansion and logistic regression" ->
    x = [[0, 0], [0, 1], [1, 0], [1, 1]]
    y = [0, 1, 1, 0]
    raw = LogisticRegression.new(1, 2000)
    raw.fit(x, y)
    pipe = Pipeline.new([
      [:poly, PolynomialFeatures.new(2)],
      [:model, LogisticRegression.new(1, 2000)]
    ])
    expect(pipe.fit(x, y) != nil).to be_true
    expect(raw.score(x, y) < 1.to_f).to be_true
    expect(pipe.score(x, y).to_s).to eq("1")

spec_summary
