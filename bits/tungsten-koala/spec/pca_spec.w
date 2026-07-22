# PCA specs — principal component analysis, on the tungsten-spec
# framework.
#
# Run from the repo root (both engines, exit 0 = green):
#   bin/tungsten bits/tungsten-koala/spec/pca_spec.w
#   bin/tungsten -o /tmp/pca_spec bits/tungsten-koala/spec/pca_spec.w && /tmp/pca_spec
#
# --- SOURCE OF TRUTH ---
#
# Two independent ones, and both are asserted:
#
#   1. CLOSED FORM. Three of the five fixtures are built so the answer is
#      derivable by hand, exactly:
#        * Fx.rank1 — every point on the line through (3, 4); the only
#          direction with any variance is (0.6, 0.8), so PC1 must be that
#          unit vector and it must carry 100% of the variance.
#        * Fx.axis_aligned — two exactly uncorrelated columns of sample
#          variance 5/2 and 1, so the components are the coordinate axes
#          and the variances are those two numbers.
#        * Fx.symmetric — covariance [[10/3, 2], [2, 10/3]], whose
#          eigenpairs are 16/3 on (1, 1)/sqrt2 and 4/3 on (1, -1)/sqrt2.
#          (It also pins the sign rule's TIE case: both loadings have
#          identical magnitude.)
#      Fx.constant_column is likewise exactly rank 1 — its third column is
#      twice its first — so its single non-zero variance is 25/3.
#
#   2. scikit-learn. Fx.general is a 6x3 integer design with no special
#      structure; its expected components, variances and ratios below are
#      scikit-learn's PCA output, computed as numpy 2.4.4's LAPACK SVD
#      driving sklearn's exact formulation — centre, thin SVD,
#      explained_variance_ = S**2 / (n - 1), ratio = that over its own
#      sum — and then put through KOALA'S SIGN RULE (negate each row whose
#      largest-magnitude entry is negative). sklearn pins signs on the
#      SCORES side (svd_flip with u_based_decision), koala on the loadings
#      side; that is the only difference, it is documented in lib/pca.w,
#      and applying koala's rule to sklearn's numbers is what makes the
#      two directly comparable. Agreement is to 3.6e-16 in practice; the
#      spec asserts 1e-9, which is the precision the literals below carry.
#
# Reference literals are written as integer/integer (no float literal may
# appear in a .w file, and no integer literal may reach 2^48 — the
# interpreter's integers are 48-bit and a bigger one becomes a heap
# bignum whose .to_f dies). Floats are never compared through to_s, which
# prints only six significant digits on both engines; every numeric
# assertion goes through a tolerance.

use spec
use koala

# Fixtures, reference values and the tolerance helpers. Loops live here
# rather than inside an `it` body so no spec closure carries a mutating
# counter.
+ Fx
  # --- tolerances ---

  # Reference-value tolerance: the literals below carry 10 decimals.
  -> .tol
    1.to_f / 1000000000.to_f

  # Structural tolerance, for identities that hold to working precision
  # (orthonormality, a ratio sum, an exact reconstruction).
  -> .tight
    (1.to_f / 1000000.to_f) * (1.to_f / 1000000.to_f)

  # --- fixtures ---

  # Rank 1: every point on the line through the origin-shifted (3, 4)
  # direction. PC1 is exactly (0.6, 0.8) and explains everything.
  -> .rank1
    out = [[0, 0], [3, 4], [6, 8], [0 - 3, 0 - 4]]
    out

  # Two exactly uncorrelated, mean-zero columns: variances 5/2 and 1,
  # covariance 0. The components are the coordinate axes.
  -> .axis_aligned
    out = [[0 - 2, 1], [0 - 1, 0 - 1], [0, 0], [1, 0 - 1], [2, 1]]
    out

  # Covariance [[10/3, 2], [2, 10/3]]: eigenvalues 16/3 and 4/3 on the
  # 45-degree axes. Both loadings of each component tie in magnitude.
  -> .symmetric
    out = [[2, 2], [0 - 2, 0 - 2], [1, 0 - 1], [0 - 1, 1]]
    out

  # A general 6x3 integer design — the scikit-learn comparison.
  -> .general
    out = [[1, 2, 3], [4, 5, 7], [2, 8, 1], [7, 3, 9], [5, 5, 5], [3, 1, 2]]
    out

  # The same rows in a different order — the sign convention and the
  # components must not notice.
  -> .general_shuffled
    out = [[7, 3, 9], [1, 2, 3], [3, 1, 2], [4, 5, 7], [5, 5, 5], [2, 8, 1]]
    out

  # Column 1 is constant and column 2 is twice column 0: rank 1 with a
  # dead feature in the middle. Total variance 25/3.
  -> .constant_column
    out = [[1, 5, 2], [2, 5, 4], [3, 5, 6], [4, 5, 8]]
    out

  # The size of the near-invisible second direction below: 1e-9.
  -> .small_d
    1.to_f / 1000000000.to_f

  # An ILL-CONDITIONED 2-feature design, built to separate the two
  # algorithms. It is t*(1, 1) + d*s*(1, -1) with t = (1, -1, 2, -2) and
  # s = (1, 1, -1, -1) exactly orthogonal, so the sample covariance has
  # eigenvalues 20/3 on (1, 1) and 8*d^2/3 ~ 2.67e-18 on (1, -1) — a
  # spread of 18 decades, far more than f64 can hold in a Gram matrix
  # but well within what the data itself carries.
  -> .ill_conditioned
    d = Fx.small_d
    ts = [1, 0 - 1, 2, 0 - 2]
    ss = [1, 1, 0 - 1, 0 - 1]
    out = []
    i = 0
    while i < 4
      row = []
      row.push(ts[i].to_f + d * ss[i].to_f)
      row.push(ts[i].to_f - d * ss[i].to_f)
      out.push(row)
      i += 1
    out

  # The SMALLER eigenvalue of the 2x2 sample covariance of `design` — by
  # the textbook route PCA deliberately does NOT take: form
  # X_c^T X_c / (n - 1) and eigendecompose it (the closed-form symmetric
  # 2x2 root, so the comparison indicts the FORMING of the covariance and
  # not some eigensolver's own weakness).
  -> .covariance_small_eigenvalue(design)
    n = design.size
    m0 = 0.to_f
    m1 = 0.to_f
    i = 0
    while i < n
      m0 += design[i][0]
      m1 += design[i][1]
      i += 1
    m0 = m0 / n.to_f
    m1 = m1 / n.to_f
    saa = 0.to_f
    sab = 0.to_f
    sbb = 0.to_f
    i = 0
    while i < n
      da = design[i][0] - m0
      db = design[i][1] - m1
      saa += da * da
      sab += da * db
      sbb += db * db
      i += 1
    denom = (n - 1).to_f
    ca = saa / denom
    cb = sab / denom
    cc = sbb / denom
    half = (ca + cc) / 2.to_f
    gap = (ca - cc) / 2.to_f
    half - Math.sqrt(gap * gap + cb * cb)

  # An 8-row named frame for the Pipeline / GridSearch composition specs.
  -> .work_frame
    out = DataFrame.new([
      [:a, [1, 4, 2, 7, 5, 3, 8, 6]],
      [:b, [2, 5, 8, 3, 5, 1, 7, 4]],
      [:c, [3, 7, 1, 9, 5, 2, 6, 8]]
    ])
    out

  -> .work_targets
    out = [10, 22, 18, 31, 25, 14, 33, 27]
    out

  # --- scikit-learn reference values for Fx.general (see the header) ---

  -> .general_components
    out = []
    out.push(Fx.scaled([5408340706, 0 - 1357437523, 8301036934], 10000000000))
    out.push(Fx.scaled([1339689712, 9881953731, 743116364], 10000000000))
    out.push(Fx.scaled([8303919694, 0 - 710178730, 0 - 5526351770], 10000000000))
    out

  -> .general_variance
    Fx.scaled([133120713989, 62976868002, 9569084676], 10000000000)

  -> .general_ratio
    Fx.scaled([6472644116, 3062084344, 465271540], 10000000000)

  # --- helpers ---

  # ints, each divided by denom — reference floats without a float literal.
  -> .scaled(ints, denom)
    out = []
    d = denom.to_f
    i = 0
    while i < ints.size
      out.push(ints[i].to_f / d)
      i += 1
    out

  # max |values[i] - refs[i]|.
  -> .max_diff(values, refs)
    out = 0.to_f
    i = 0
    while i < values.size
      d = LinAlg.fabs(values[i].to_f - refs[i].to_f)
      out = d if d > out
      i += 1
    out

  # The same, one level deeper (a nested-array matrix against a reference).
  -> .max_diff2(rows, refs)
    out = 0.to_f
    i = 0
    while i < rows.size
      d = Fx.max_diff(rows[i], refs[i])
      out = d if d > out
      i += 1
    out

  -> .total(values)
    out = 0.to_f
    i = 0
    while i < values.size
      out += values[i]
      i += 1
    out

  # max |C C^T - I| — zero exactly when the components are mutually
  # orthogonal AND unit-norm, which is the whole orthonormality claim in
  # one number.
  -> .orthonormality_error(comps)
    g = comps.matmul(comps.transpose).to_a
    k = g.size
    out = 0.to_f
    i = 0
    while i < k
      j = 0
      while j < k
        want = 0.to_f
        want = 1.to_f if i == j
        d = LinAlg.fabs(g[i][j] - want)
        out = d if d > out
        j += 1
      i += 1
    out

  # max | |component_i| - 1 | — unit norm asserted on its own, so a
  # failure says which half of orthonormality broke.
  -> .unit_norm_error(comps)
    rows = comps.to_a
    out = 0.to_f
    i = 0
    while i < rows.size
      row = rows[i]
      s = 0.to_f
      j = 0
      while j < row.size
        s += row[j] * row[j]
        j += 1
      d = LinAlg.fabs(Math.sqrt(s) - 1.to_f)
      out = d if d > out
      i += 1
    out

  # max |component_i . component_j| over i != j — orthogonality alone.
  -> .max_off_diagonal(comps)
    g = comps.matmul(comps.transpose).to_a
    k = g.size
    out = 0.to_f
    i = 0
    while i < k
      j = 0
      while j < k
        if i != j
          d = LinAlg.fabs(g[i][j])
          out = d if d > out
        j += 1
      i += 1
    out

  # Is every component's largest-magnitude loading positive (koala's
  # sign rule)? Ties break to the lowest index, which is why the scan
  # uses a strict >.
  -> .signs_pinned?(comps)
    rows = comps.to_a
    out = true
    i = 0
    while i < rows.size
      row = rows[i]
      best = 0
      j = 1
      while j < row.size
        best = j if LinAlg.fabs(row[j]) > LinAlg.fabs(row[best])
        j += 1
      out = false if row[best] < 0
      i += 1
    out

  # max |inverse_transform(transform(rows)) - rows|.
  -> .reconstruction_error(model, rows)
    back = model.inverse_transform(model.transform(rows))
    out = 0.to_f
    if back != nil
      names = back.column_names
      j = 0
      while j < names.size
        vals = back.column_values(names[j])
        i = 0
        while i < vals.size
          d = LinAlg.fabs(vals[i] - rows[i][j].to_f)
          out = d if d > out
          i += 1
        j += 1
    out

  # A PCA fitted on rows, keeping k components (nil = all).
  -> .trained(rows, k)
    model = PCA.new(k)
    model.fit(rows)
    model

  # A fitted PCA through the Persist format and back.
  #
  # NOTE: `Persist.loads` cannot yet dispatch the class name "PCA" — that
  # needs ONE line in Persist.rebuild, and lib/persist.w is owned by a
  # sibling change, so it is deliberately left untouched here. Everything
  # else in the format is exercised: dumps writes the payload, Persist's
  # own reader decodes the state node (line 2, after the header and the
  # `o PCA` tag), and PCA.load_state rebuilds from it. When that one line
  # lands this becomes a plain Persist.loads.
  -> .cycle(model)
    text = Persist.dumps(model)
    out = nil
    if text != nil
      lines = Persist.payload_lines(text)
      res = Persist.decode(lines, 2)
      out = PCA.load_state(res[:v]) if res[:ok]
    out

  # The column of a transformed frame, as a plain array.
  -> .scores(frame, name)
    frame.column_values(name)

describe "PCA — hand-verified structure" ->
  it "recovers the exact axis of a rank-1 cloud and gives PC1 all the variance" ->
    model = Fx.trained(Fx.rank1, nil)
    comps = model.components.to_a
    axis = Fx.scaled([6, 8], 10)
    expect(model.component_count).to eq(2)
    expect(Fx.max_diff(comps[0], axis) < Fx.tight).to be_true
    # PC2 is the orthogonal complement, (0.8, -0.6)
    expect(Fx.max_diff(comps[1], Fx.scaled([8, 0 - 6], 10)) < Fx.tight).to be_true
    # variance along the axis: the projections are -2.5, 2.5, 7.5, -7.5,
    # so the sample variance is 125/3 and NONE is left over
    ev = model.explained_variance.to_a
    expect(LinAlg.fabs(ev[0] - 125.to_f / 3.to_f) < Fx.tol).to be_true
    expect(LinAlg.fabs(ev[1]) < Fx.tight).to be_true
    ratio = model.explained_variance_ratio.to_a
    expect(LinAlg.fabs(ratio[0] - 1.to_f) < Fx.tight).to be_true
    expect(LinAlg.fabs(ratio[1]) < Fx.tight).to be_true

  it "subtracts the per-feature mean" ->
    model = Fx.trained(Fx.rank1, nil)
    expect(Fx.max_diff(model.mean.to_a, Fx.scaled([15, 20], 10)) < Fx.tight).to be_true
    expect(model.feature_count).to eq(2)

  it "returns each column's own variance when the covariance is diagonal" ->
    model = Fx.trained(Fx.axis_aligned, nil)
    comps = model.components.to_a
    expect(Fx.max_diff(comps[0], Fx.scaled([1, 0], 1)) < Fx.tight).to be_true
    expect(Fx.max_diff(comps[1], Fx.scaled([0, 1], 1)) < Fx.tight).to be_true
    ev = model.explained_variance.to_a
    expect(LinAlg.fabs(ev[0] - 5.to_f / 2.to_f) < Fx.tol).to be_true
    expect(LinAlg.fabs(ev[1] - 1.to_f) < Fx.tol).to be_true
    ratio = model.explained_variance_ratio.to_a
    expect(LinAlg.fabs(ratio[0] - 5.to_f / 7.to_f) < Fx.tol).to be_true
    expect(LinAlg.fabs(ratio[1] - 2.to_f / 7.to_f) < Fx.tol).to be_true

  it "finds the 45-degree eigenvectors of a symmetric covariance" ->
    model = Fx.trained(Fx.symmetric, nil)
    comps = model.components.to_a
    root = 1.to_f / Math.sqrt(2.to_f)
    expect(LinAlg.fabs(comps[0][0] - root) < Fx.tight).to be_true
    expect(LinAlg.fabs(comps[0][1] - root) < Fx.tight).to be_true
    expect(LinAlg.fabs(comps[1][0] - root) < Fx.tight).to be_true
    expect(LinAlg.fabs(comps[1][1] + root) < Fx.tight).to be_true
    ev = model.explained_variance.to_a
    expect(LinAlg.fabs(ev[0] - 16.to_f / 3.to_f) < Fx.tol).to be_true
    expect(LinAlg.fabs(ev[1] - 4.to_f / 3.to_f) < Fx.tol).to be_true
    ratio = model.explained_variance_ratio.to_a
    expect(LinAlg.fabs(ratio[0] - 8.to_f / 10.to_f) < Fx.tol).to be_true
    expect(LinAlg.fabs(ratio[1] - 2.to_f / 10.to_f) < Fx.tol).to be_true

  it "keeps a rank-1 dataset's dead direction at exactly zero variance" ->
    model = Fx.trained(Fx.constant_column, nil)
    ev = model.explained_variance.to_a
    expect(model.component_count).to eq(3)
    expect(LinAlg.fabs(ev[0] - 25.to_f / 3.to_f) < Fx.tol).to be_true
    expect(LinAlg.fabs(ev[1]) < Fx.tight).to be_true
    expect(LinAlg.fabs(ev[2]) < Fx.tight).to be_true
    # the leading direction is (1, 0, 2)/sqrt5 — the constant feature has
    # no loading on it at all
    root5 = Math.sqrt(5.to_f)
    comps = model.components.to_a
    expect(LinAlg.fabs(comps[0][0] - 1.to_f / root5) < Fx.tol).to be_true
    expect(LinAlg.fabs(comps[0][1]) < Fx.tight).to be_true
    expect(LinAlg.fabs(comps[0][2] - 2.to_f / root5) < Fx.tol).to be_true

describe "PCA — against scikit-learn" ->
  it "matches scikit-learn's components on a general design" ->
    model = Fx.trained(Fx.general, nil)
    expect(model.component_count).to eq(3)
    expect(Fx.max_diff2(model.components.to_a, Fx.general_components) < Fx.tol).to be_true

  it "matches scikit-learn's explained_variance and ratio" ->
    model = Fx.trained(Fx.general, nil)
    expect(Fx.max_diff(model.explained_variance.to_a, Fx.general_variance) < Fx.tol).to be_true
    expect(Fx.max_diff(model.explained_variance_ratio.to_a, Fx.general_ratio) < Fx.tol).to be_true

  it "matches scikit-learn's mean" ->
    model = Fx.trained(Fx.general, nil)
    expect(Fx.max_diff(model.mean.to_a, Fx.scaled([110, 120, 135], 30)) < Fx.tight).to be_true

  it "keeps the same leading components when the fit is truncated" ->
    full = Fx.trained(Fx.general, nil)
    two = Fx.trained(Fx.general, 2)
    expect(two.component_count).to eq(2)
    expect(Fx.max_diff2(two.components.to_a, full.components.to_a) < Fx.tight).to be_true
    expect(Fx.max_diff(two.explained_variance.to_a, Fx.general_variance) < Fx.tol).to be_true

# THE POINT OF ONE-SIDED JACOBI — a head-to-head against the route it
# refuses, exactly as spec/linalg_spec.w pits Householder QR against the
# normal equations.
#
# Fx.ill_conditioned carries two variances 18 decades apart: 20/3 and
# 8e-18/3. Forming the covariance X_c^T X_c SQUARES the condition number,
# and 10 + 4e-18 is just 10 in f64 — so the small direction is rounded
# clean out of the Gram matrix before any eigensolver sees it, and the
# textbook route reports its variance as EXACTLY ZERO. One-sided Jacobi
# rotates X_c itself and never forms that product, so the same f64 data
# still yields the small variance to about eight significant digits.
#
# Measured, identical on both engines:
#   covariance + eigen : 0            (relative error 1.0 — total loss)
#   one-sided Jacobi   : 2.666667e-18 (relative error 2.4e-8)
# The thresholds below are deliberately slack so the spec tracks the
# PHENOMENON rather than the last bit.
describe "PCA — numerical accuracy against the covariance route" ->
  it "agrees with the covariance route on the DOMINANT variance" ->
    model = Fx.trained(Fx.ill_conditioned, nil)
    expect(LinAlg.fabs(model.explained_variance[0] - 20.to_f / 3.to_f) < Fx.tol).to be_true

  it "keeps a tiny variance that forming the covariance destroys" ->
    design = Fx.ill_conditioned
    d = Fx.small_d
    truth = 8.to_f * d * d / 3.to_f
    jacobi_err = LinAlg.fabs(Fx.trained(design, nil).explained_variance[1] - truth) / truth
    covariance_err = LinAlg.fabs(Fx.covariance_small_eigenvalue(design) - truth) / truth
    expect(jacobi_err < 1.to_f / 1000000.to_f).to be_true       # Jacobi is accurate...
    expect(covariance_err > 1.to_f / 2.to_f).to be_true         # ...the covariance is NOT
    expect(jacobi_err * 1000.to_f < covariance_err).to be_true  # by at least three decades

  it "still returns an exactly orthonormal basis for that design" ->
    expect(Fx.orthonormality_error(Fx.trained(Fx.ill_conditioned, nil).components) < Fx.tight).to be_true

describe "PCA — explained variance" ->
  it "sums the ratios to 1 over a full-rank fit" ->
    expect(LinAlg.fabs(Fx.total(Fx.trained(Fx.general, nil).explained_variance_ratio.to_a) - 1.to_f) < Fx.tight).to be_true
    expect(LinAlg.fabs(Fx.total(Fx.trained(Fx.axis_aligned, nil).explained_variance_ratio.to_a) - 1.to_f) < Fx.tight).to be_true
    expect(LinAlg.fabs(Fx.total(Fx.trained(Fx.rank1, nil).explained_variance_ratio.to_a) - 1.to_f) < Fx.tight).to be_true
    expect(LinAlg.fabs(Fx.total(Fx.trained(Fx.constant_column, nil).explained_variance_ratio.to_a) - 1.to_f) < Fx.tight).to be_true

  it "reports a truncated fit's share of the ORIGINAL variance, not of itself" ->
    one = Fx.trained(Fx.general, 1)
    expect(one.component_count).to eq(1)
    # 0.6472644116, NOT 1 — the denominator is the whole trace
    expect(LinAlg.fabs(one.explained_variance_ratio[0] - Fx.general_ratio[0]) < Fx.tol).to be_true
    expect(Fx.total(one.explained_variance_ratio.to_a) < 1.to_f).to be_true

  it "explains exactly the variance of the score columns it produces" ->
    model = Fx.trained(Fx.general, nil)
    out = model.transform(Fx.general)
    ev = model.explained_variance.to_a
    expect(LinAlg.fabs(Stats.var(Fx.scores(out, "pc0")) - ev[0]) < Fx.tol).to be_true
    expect(LinAlg.fabs(Stats.var(Fx.scores(out, "pc1")) - ev[1]) < Fx.tol).to be_true
    expect(LinAlg.fabs(Stats.var(Fx.scores(out, "pc2")) - ev[2]) < Fx.tol).to be_true

  it "totals the same variance the features started with" ->
    model = Fx.trained(Fx.general, nil)
    rows = Fx.general
    cols = Estimator.frame(rows)
    trace = Stats.var(cols.column_values("x0")) + Stats.var(cols.column_values("x1")) + Stats.var(cols.column_values("x2"))
    expect(LinAlg.fabs(Fx.total(model.explained_variance.to_a) - trace) < Fx.tol).to be_true

  it "gives an all-constant dataset zero variance and zero ratios" ->
    flat = [[2, 7], [2, 7], [2, 7], [2, 7]]
    model = Fx.trained(flat, nil)
    expect(model).not_to be_nil
    expect(LinAlg.fabs(Fx.total(model.explained_variance.to_a)) < Fx.tight).to be_true
    expect(LinAlg.fabs(Fx.total(model.explained_variance_ratio.to_a)) < Fx.tight).to be_true

describe "PCA — orthonormality" ->
  it "returns unit-norm components" ->
    expect(Fx.unit_norm_error(Fx.trained(Fx.general, nil).components) < Fx.tight).to be_true
    expect(Fx.unit_norm_error(Fx.trained(Fx.symmetric, nil).components) < Fx.tight).to be_true
    expect(Fx.unit_norm_error(Fx.trained(Fx.rank1, nil).components) < Fx.tight).to be_true

  it "returns mutually orthogonal components" ->
    expect(Fx.max_off_diagonal(Fx.trained(Fx.general, nil).components) < Fx.tight).to be_true
    expect(Fx.max_off_diagonal(Fx.trained(Fx.symmetric, nil).components) < Fx.tight).to be_true

  it "satisfies C C^T = I, the two claims in one identity" ->
    expect(Fx.orthonormality_error(Fx.trained(Fx.general, nil).components) < Fx.tight).to be_true
    expect(Fx.orthonormality_error(Fx.trained(Fx.general, 2).components) < Fx.tight).to be_true

  it "stays orthonormal on RANK-DEFICIENT data, where a QR would refuse" ->
    # both fixtures are exactly rank 1; LinAlg.qr returns nil for them
    expect(LinAlg.qr(Matrix.new(Fx.constant_column))).to be_nil
    expect(Fx.orthonormality_error(Fx.trained(Fx.constant_column, nil).components) < Fx.tight).to be_true
    expect(Fx.orthonormality_error(Fx.trained(Fx.rank1, nil).components) < Fx.tight).to be_true

describe "PCA — sign convention" ->
  it "forces every component's largest-magnitude loading positive" ->
    expect(Fx.signs_pinned?(Fx.trained(Fx.general, nil).components)).to be_true
    expect(Fx.signs_pinned?(Fx.trained(Fx.rank1, nil).components)).to be_true
    expect(Fx.signs_pinned?(Fx.trained(Fx.constant_column, nil).components)).to be_true
    expect(Fx.signs_pinned?(Fx.trained(Fx.axis_aligned, nil).components)).to be_true

  it "breaks a magnitude TIE toward the lowest feature index" ->
    # both loadings of both components are 1/sqrt2, so only the tie rule
    # decides: entry 0 is the one forced positive, on BOTH components
    comps = Fx.trained(Fx.symmetric, nil).components.to_a
    expect(comps[0][0] > 0).to be_true
    expect(comps[1][0] > 0).to be_true
    expect(comps[1][1] < 0).to be_true

  it "does not depend on the ROW order, because it is stated on loadings" ->
    a = Fx.trained(Fx.general, nil)
    b = Fx.trained(Fx.general_shuffled, nil)
    expect(Fx.max_diff2(a.components.to_a, b.components.to_a) < Fx.tight).to be_true
    expect(Fx.max_diff(a.explained_variance.to_a, b.explained_variance.to_a) < Fx.tol).to be_true

  it "is reproducible — the same input fits to the same components twice" ->
    a = Fx.trained(Fx.general, nil)
    b = Fx.trained(Fx.general, nil)
    expect(Fx.max_diff2(a.components.to_a, b.components.to_a)).to eq(0)
    expect(Fx.max_diff(a.explained_variance.to_a, b.explained_variance.to_a)).to eq(0)

describe "PCA — transform" ->
  it "produces one pc column per kept component" ->
    out = PCA.new(2).fit_transform(Fx.general)
    expect(out.column_names.join(",")).to eq("pc0,pc1")
    expect(out.row_count).to eq(6)

  it "centres the scores on zero" ->
    out = PCA.new(3).fit_transform(Fx.general)
    expect(LinAlg.fabs(Stats.mean(Fx.scores(out, "pc0"))) < Fx.tol).to be_true
    expect(LinAlg.fabs(Stats.mean(Fx.scores(out, "pc2"))) < Fx.tol).to be_true

  it "replays the TRAINING mean and directions on new rows" ->
    model = Fx.trained(Fx.general, 2)
    one = model.transform([[1, 2, 3]])
    all = model.transform(Fx.general)
    expect(one.row_count).to eq(1)
    expect(LinAlg.fabs(Fx.scores(one, "pc0")[0] - Fx.scores(all, "pc0")[0]) < Fx.tight).to be_true

  it "accepts a DataFrame, a Matrix and plain rows alike" ->
    model = Fx.trained(Fx.general, 2)
    from_rows = Fx.scores(model.transform(Fx.general), "pc0")
    from_matrix = Fx.scores(model.transform(Matrix.new(Fx.general)), "pc0")
    frame = DataFrame.new([[:x0, [1, 4, 2, 7, 5, 3]], [:x1, [2, 5, 8, 3, 5, 1]], [:x2, [3, 7, 1, 9, 5, 2]]])
    from_frame = Fx.scores(model.transform(frame), "pc0")
    expect(Fx.max_diff(from_matrix, from_rows)).to eq(0)
    expect(Fx.max_diff(from_frame, from_rows)).to eq(0)

  it "ignores non-numeric columns and remembers the numeric ones' names" ->
    frame = DataFrame.new([[:a, [1, 4, 2, 7]], [:tag, ["x", "y", "x", "y"]], [:b, [2, 5, 8, 3]]])
    model = PCA.new(2)
    model.fit(frame)
    expect(model.feature_names.join(",")).to eq("a,b")
    expect(model.feature_count).to eq(2)
    expect(model.transform(frame).column_names.join(",")).to eq("pc0,pc1")

describe "PCA — inverse_transform" ->
  it "reconstructs the input exactly at full rank" ->
    model = Fx.trained(Fx.general, 3)
    expect(Fx.reconstruction_error(model, Fx.general) < Fx.tight).to be_true

  it "reconstructs a rank-1 cloud exactly from ONE component" ->
    model = Fx.trained(Fx.rank1, 1)
    expect(model.component_count).to eq(1)
    expect(Fx.reconstruction_error(model, Fx.rank1) < Fx.tight).to be_true

  it "loses information when the fit is truncated below the rank" ->
    # the honest converse: one component cannot carry a rank-3 design
    model = Fx.trained(Fx.general, 1)
    expect(Fx.reconstruction_error(model, Fx.general) > 1.to_f).to be_true

  it "returns the fitted feature names, not pc names" ->
    frame = DataFrame.new([[:a, [1, 4, 2, 7]], [:b, [2, 5, 8, 3]]])
    model = PCA.new(2)
    scores = model.fit_transform(frame)
    back = model.inverse_transform(scores)
    expect(back.column_names.join(",")).to eq("a,b")
    expect(Fx.max_diff(back.column_values(:a), [1, 4, 2, 7]) < Fx.tight).to be_true
    expect(Fx.max_diff(back.column_values(:b), [2, 5, 8, 3]) < Fx.tight).to be_true

describe "PCA — whiten" ->
  it "scales every score column to unit variance" ->
    out = PCA.new(3, true).fit_transform(Fx.general)
    expect(LinAlg.fabs(Stats.var(Fx.scores(out, "pc0")) - 1.to_f) < Fx.tol).to be_true
    expect(LinAlg.fabs(Stats.var(Fx.scores(out, "pc1")) - 1.to_f) < Fx.tol).to be_true
    expect(LinAlg.fabs(Stats.var(Fx.scores(out, "pc2")) - 1.to_f) < Fx.tol).to be_true

  it "leaves the components and variances themselves untouched" ->
    plain = Fx.trained(Fx.general, nil)
    white = PCA.new(nil, true)
    white.fit(Fx.general)
    expect(Fx.max_diff2(white.components.to_a, plain.components.to_a)).to eq(0)
    expect(Fx.max_diff(white.explained_variance.to_a, plain.explained_variance.to_a)).to eq(0)

  it "is undone exactly by inverse_transform" ->
    model = PCA.new(3, true)
    model.fit(Fx.general)
    expect(Fx.reconstruction_error(model, Fx.general) < Fx.tight).to be_true

  it "never divides by a zero variance" ->
    model = PCA.new(3, true)
    model.fit(Fx.constant_column)
    out = model.transform(Fx.constant_column)
    expect(out).not_to be_nil
    # the two dead directions stay at 0 rather than becoming NaN
    expect(LinAlg.fabs(Stats.mean(Fx.scores(out, "pc1"))) < Fx.tight).to be_true
    expect(LinAlg.fabs(Stats.var(Fx.scores(out, "pc2"))) < Fx.tight).to be_true
    expect(Fx.reconstruction_error(model, Fx.constant_column) < Fx.tight).to be_true

describe "PCA — degenerate input, nil and never a raise" ->
  it "answers nil for everything before fit" ->
    model = PCA.new(2)
    expect(model.fitted?).to be_false
    expect(model.transform(Fx.general)).to be_nil
    expect(model.inverse_transform(Fx.general)).to be_nil
    expect(model.components).to be_nil
    expect(model.explained_variance).to be_nil
    expect(model.explained_variance_ratio).to be_nil
    expect(model.mean).to be_nil
    expect(model.component_count).to eq(0)
    expect(model.feature_count).to eq(0)

  it "refuses more components than min(n_samples, n_features)" ->
    # 4 rows, 2 features: 3 is more than the 2 that exist
    expect(PCA.new(3).fit(Fx.rank1)).to be_nil
    expect(PCA.new(3).fit(Fx.rank1) == nil).to be_true
    # 2 rows, 3 features: capped by the SAMPLE count
    expect(PCA.new(3).fit([[1, 2, 3], [4, 5, 6]])).to be_nil
    expect(PCA.new(2).fit([[1, 2, 3], [4, 5, 6]])).not_to be_nil
    # and a request for none, or a negative one
    expect(PCA.new(0).fit(Fx.general)).to be_nil
    expect(PCA.new(0 - 1).fit(Fx.general)).to be_nil

  it "leaves fitted? false after a refused fit" ->
    model = PCA.new(9)
    model.fit(Fx.general)
    expect(model.fitted?).to be_false
    expect(model.transform(Fx.general)).to be_nil

  it "refuses empty, single-row and non-numeric input" ->
    expect(PCA.new.fit([])).to be_nil
    expect(PCA.new.fit(nil)).to be_nil
    expect(PCA.new.fit([[1, 2]])).to be_nil
    expect(PCA.new.fit(DataFrame.new([[:tag, ["a", "b", "c"]]]))).to be_nil

  it "refuses a nil cell rather than treating it as zero" ->
    expect(PCA.new.fit([[1, 2], [3, nil], [5, 6]])).to be_nil
    frame = DataFrame.new([[:a, [1, nil, 5]], [:b, [2, 4, 6]]])
    expect(PCA.new.fit(frame)).to be_nil
    # ... which an Imputer ahead of it fixes
    filled = Imputer.new(:mean).fit_transform(frame)
    expect(PCA.new(1).fit(filled)).not_to be_nil

  it "accepts CONSTANT columns — they are data, not an error" ->
    model = PCA.new(2)
    expect(model.fit(Fx.constant_column)).not_to be_nil
    expect(model.transform(Fx.constant_column)).not_to be_nil

  it "refuses a transform whose width does not match the fit" ->
    model = Fx.trained(Fx.general, 2)
    expect(model.transform([[1, 2], [3, 4]])).to be_nil
    expect(model.transform([])).to be_nil
    expect(model.transform(nil)).to be_nil

  it "refuses an inverse_transform that is not n_components wide" ->
    model = Fx.trained(Fx.general, 2)
    expect(model.inverse_transform(Fx.general)).to be_nil
    expect(model.inverse_transform(nil)).to be_nil

  it "handles a single feature — one component, all the variance" ->
    model = PCA.new
    model.fit([[1], [3], [5], [9]])
    expect(model.component_count).to eq(1)
    expect(LinAlg.fabs(model.components.at(0, 0) - 1.to_f) < Fx.tight).to be_true
    expect(LinAlg.fabs(model.explained_variance_ratio[0] - 1.to_f) < Fx.tight).to be_true

describe "PCA — Tunable contract" ->
  it "reports its constructor knobs as params" ->
    p = PCA.new(2, true).params
    expect(p[:n_components]).to eq(2)
    expect(p[:whiten]).to be_true
    expect(PCA.new.params[:n_components]).to be_nil
    expect(PCA.new.params[:whiten]).to be_false

  it "keeps learned state OUT of params and in learned_params" ->
    model = Fx.trained(Fx.general, 2)
    expect(model.params.key?(:mean)).to be_false
    expect(model.params.key?(:components)).to be_false
    learned = model.learned_params
    expect(learned[:mean].size).to eq(3)
    expect(learned[:components].size).to eq(2)
    expect(learned[:explained_variance].size).to eq(2)
    expect(learned[:explained_variance_ratio].size).to eq(2)
    expect(learned[:feature_names].join(",")).to eq("x0,x1,x2")

  it "clones through with_params, unfitted, leaving the receiver alone" ->
    model = Fx.trained(Fx.general, 2)
    clone = model.with_params({ n_components: 1 })
    expect(clone.params[:n_components]).to eq(1)
    expect(clone.fitted?).to be_false
    expect(model.fitted?).to be_true
    expect(model.params[:n_components]).to eq(2)

  it "carries unmentioned keys over, so with_params(params) round-trips" ->
    model = PCA.new(2, true)
    same = model.with_params(model.params)
    expect(same.params[:n_components]).to eq(2)
    expect(same.params[:whiten]).to be_true
    only_one = model.with_params({ n_components: 1 })
    expect(only_one.params[:whiten]).to be_true

  it "applies an explicit nil, widening a truncated PCA back to all" ->
    widened = PCA.new(1).with_params({ n_components: nil })
    expect(widened.params[:n_components]).to be_nil
    widened.fit(Fx.general)
    expect(widened.component_count).to eq(3)

describe "PCA — Pipeline and GridSearch composition" ->
  it "runs as a transformer-only Pipeline step" ->
    pipe = Pipeline.new([[:pca, PCA.new(2)]])
    out = pipe.fit_transform(Fx.work_frame)
    expect(out.column_names.join(",")).to eq("pc0,pc1")
    expect(out.row_count).to eq(8)
    expect(pipe.step(:pca).fitted?).to be_true

  it "sits ahead of an estimator and is scored through the chain" ->
    pipe = Pipeline.new([[:pca, PCA.new(3)], [:model, LinearRegression.new]])
    expect(pipe.fit(Fx.work_frame, Fx.work_targets)).not_to be_nil
    expect(pipe.supervised?).to be_true
    # a full-rank PCA is a rotation, so it cannot change what OLS can fit
    bare = LinearRegression.new
    bare.fit(Fx.work_frame, Fx.work_targets)
    expect(LinAlg.fabs(pipe.score(Fx.work_frame, Fx.work_targets) - bare.score(Fx.work_frame, Fx.work_targets)) < Fx.tol).to be_true

  it "chains after a Scaler in the same pipeline" ->
    pipe = Pipeline.new([[:scale, Scaler.new(:standard)], [:pca, PCA.new(2)], [:model, LinearRegression.new]])
    expect(pipe.fit(Fx.work_frame, Fx.work_targets)).not_to be_nil
    expect(pipe.predict(Fx.work_frame).size).to eq(8)

  it "contributes its knobs to the pipeline's tunable surface" ->
    pipe = Pipeline.new([[:pca, PCA.new(2)], [:model, LinearRegression.new]])
    p = pipe.params
    expect(p.key?("pca.n_components")).to be_true
    expect(p.key?("pca.whiten")).to be_true
    expect(p["pca.n_components"]).to eq(2)
    tuned = pipe.with_params({ "pca.n_components" => 1 })
    expect(tuned.params["pca.n_components"]).to eq(1)
    expect(tuned.fitted?).to be_false
    expect(pipe.params["pca.n_components"]).to eq(2)

  it "is tunable by GridSearch over n_components" ->
    pipe = Pipeline.new([[:pca, PCA.new(1)], [:model, LinearRegression.new]])
    search = GridSearch.new(pipe, { "pca.n_components" => [1, 2, 3] }, 4)
    expect(search.size).to eq(3)
    expect(search.fit(Fx.work_frame, Fx.work_targets)).not_to be_nil
    expect(search.best_params.key?("pca.n_components")).to be_true
    expect(search.best_score).not_to be_nil
    expect(search.results.size).to eq(3)
    expect(search.best_estimator.fitted?).to be_true

  it "is tunable over whiten alongside a model hyperparameter" ->
    pipe = Pipeline.new([[:pca, PCA.new(2)], [:model, LinearRegression.new]])
    search = GridSearch.new(pipe, { "pca.whiten" => [false, true], "model.alpha" => [0, 1] }, 4)
    expect(search.size).to eq(4)
    expect(search.fit(Fx.work_frame, Fx.work_targets)).not_to be_nil
    expect(search.best_params.key?("pca.whiten")).to be_true
    expect(search.best_params.key?("model.alpha")).to be_true

  it "cross-validates through the generic estimator contract" ->
    pipe = Pipeline.new([[:pca, PCA.new(2)], [:model, LinearRegression.new]])
    mean_score = CrossValidation.cross_val_mean(pipe, Fx.work_frame, Fx.work_targets, 4)
    expect(mean_score).not_to be_nil

describe "PCA — persistence" ->
  it "dumps a fitted PCA and rebuilds identical learned state" ->
    model = Fx.trained(Fx.general, 2)
    back = Fx.cycle(model)
    expect(back).not_to be_nil
    expect(back.fitted?).to be_true
    expect(back.component_count).to eq(2)
    expect(Fx.max_diff2(back.components.to_a, model.components.to_a)).to eq(0)
    expect(Fx.max_diff(back.explained_variance.to_a, model.explained_variance.to_a)).to eq(0)
    expect(Fx.max_diff(back.explained_variance_ratio.to_a, model.explained_variance_ratio.to_a)).to eq(0)
    expect(Fx.max_diff(back.mean.to_a, model.mean.to_a)).to eq(0)

  it "projects new rows IDENTICALLY after a reload — bit for bit" ->
    model = Fx.trained(Fx.general, 2)
    back = Fx.cycle(model)
    a = Fx.scores(model.transform(Fx.general), "pc0")
    b = Fx.scores(back.transform(Fx.general), "pc0")
    expect(Fx.max_diff(a, b)).to eq(0)
    expect(Fx.max_diff(Fx.scores(model.transform(Fx.general), "pc1"), Fx.scores(back.transform(Fx.general), "pc1"))).to eq(0)

  it "carries the knobs and the feature names across" ->
    frame = DataFrame.new([[:a, [1, 4, 2, 7]], [:b, [2, 5, 8, 3]]])
    model = PCA.new(2, true)
    model.fit(frame)
    back = Fx.cycle(model)
    expect(back.params[:n_components]).to eq(2)
    expect(back.params[:whiten]).to be_true
    expect(back.feature_names.join(",")).to eq("a,b")
    expect(back.inverse_transform(back.transform(frame)).column_names.join(",")).to eq("a,b")

  it "answers persist_name and is recognized by Persist as persistable" ->
    model = Fx.trained(Fx.general, 2)
    expect(model.persist_name).to eq("PCA")
    expect(Persist.persistable?(model)).to be_true
    lines = Persist.payload_lines(Persist.dumps(model))
    expect(lines[0]).to eq(Persist.header)
    expect(lines[1]).to eq("o PCA")

  it "refuses to dump an UNFITTED PCA" ->
    expect(Persist.dumps(PCA.new(2))).to be_nil

  it "survives two full cycles unchanged" ->
    model = Fx.trained(Fx.general, 3)
    twice = Fx.cycle(Fx.cycle(model))
    expect(twice).not_to be_nil
    expect(Fx.max_diff2(twice.components.to_a, model.components.to_a)).to eq(0)
    expect(Fx.reconstruction_error(twice, Fx.general) < Fx.tight).to be_true

spec_summary
