# Linear algebra specs — Vector / Matrix / LinAlg, on the tungsten-spec
# framework.
#
# Run from the repo root (both engines, exit 0 = green):
#   bin/tungsten bits/tungsten-koala/spec/linalg_spec.w
#   bin/tungsten -o /tmp/linalg_spec bits/tungsten-koala/spec/linalg_spec.w && /tmp/linalg_spec
#
# Shape-error convention under test: mismatched dimensions return nil
# (det of a SINGULAR square matrix is 0, not nil). Expected values are
# compared via .to_s / element checks — compiled Array == is identity,
# and nil stringifies differently per engine. No float literals appear
# here (float-literal arithmetic returns nil interpreted); float
# expectations come out of division and print via to_s.

use spec
use koala
use support

describe "Vector" ->
  it "constructs, indexes, and converts" ->
    v = Vector.new([1, 2, 3])
    expect(v.size).to eq(3)
    expect(v[1]).to eq(2)
    expect(v.to_a.to_s).to eq("\[1, 2, 3\]")
    expect(v.empty?).to eq(false)
    expect(v.zero?).to eq(false)
    expect(Vector.new([0, 0]).zero?).to eq(true)
    expect(v.to_row_matrix.shape.to_s).to eq("\[1, 3\]")
    expect(v.to_col_matrix.shape.to_s).to eq("\[3, 1\]")
    expect(v.to_series.sum).to eq(6)

  it "does elementwise arithmetic" ->
    v = Vector.new([1, 2, 3])
    w = Vector.new([4, 5, 6])
    expect(v.add(w).to_a.to_s).to eq("\[5, 7, 9\]")
    expect(v.sub(w).to_a.to_s).to eq("\[-3, -3, -3\]")
    expect(v.mul(w).to_a.to_s).to eq("\[4, 10, 18\]")
    expect(Vector.new([10, 9]).div(Vector.new([4, 3])).to_a.to_s).to eq("\[2.5, 3\]")
    expect(v.scale(3).to_a.to_s).to eq("\[3, 6, 9\]")

  it "computes dot, norms, and geometry" ->
    v = Vector.new([1, 2, 3])
    w = Vector.new([4, 5, 6])
    expect(v.dot(w)).to eq(32)
    expect(Vector.new([3, 4]).norm.to_s).to eq("5")
    expect(Vector.new([1, 0 - 2, 3]).norm_l1.to_s).to eq("6")
    expect(Vector.new([0, 4, 0]).normalize.to_a.to_s).to eq("\[0, 1, 0\]")
    expect(Vector.new([1, 1]).distance(Vector.new([4, 5])).to_s).to eq("5")
    expect(Vector.new([2, 0]).cosine_similarity(Vector.new([6, 0])).to_s).to eq("1")

  it "returns nil on shape errors" ->
    v = Vector.new([1, 2, 3])
    short = Vector.new([1, 2])
    expect(v.add(short)).to be_nil
    expect(v.dot(short)).to be_nil
    expect(v.distance(short)).to be_nil
    expect(Vector.new([0, 0]).normalize).to be_nil
    expect(v.cosine_similarity(Vector.new([0, 0, 0]))).to be_nil

describe "Matrix" ->
  it "constructs from rows and factories" ->
    m = Matrix.new([[1, 2], [3, 4]])
    expect(m.shape.to_s).to eq("\[2, 2\]")
    expect(m.row_count).to eq(2)
    expect(m.col_count).to eq(2)
    expect(m.square?).to eq(true)
    expect(m.at(1, 0)).to eq(3)
    expect(Matrix.identity(2).to_a.to_s).to eq("\[\[1, 0\], \[0, 1\]\]")
    expect(Matrix.zeros(2, 3).shape.to_s).to eq("\[2, 3\]")
    expect(Matrix.zeros(2).to_a.to_s).to eq("\[\[0, 0\], \[0, 0\]\]")
    expect(Matrix.ones(2).to_a.to_s).to eq("\[\[1, 1\], \[1, 1\]\]")
    expect(Matrix.diagonal([7, 8]).to_a.to_s).to eq("\[\[7, 0\], \[0, 8\]\]")

  it "rectangularizes ragged input against the first row" ->
    m = Matrix.new([[1, 2], [3, 4, 5], [6]])
    expect(m.shape.to_s).to eq("\[3, 2\]")
    expect(m.at(1, 1)).to eq(4)
    expect(m.at(2, 1)).to be_nil

  it "accesses rows, columns, and converts" ->
    m = Matrix.new([[1, 2], [3, 4]])
    expect(m.row(1).to_a.to_s).to eq("\[3, 4\]")
    expect(m[0].to_a.to_s).to eq("\[1, 2\]")
    expect(m.col(0).to_a.to_s).to eq("\[1, 3\]")
    expect(m.at(5, 0)).to be_nil
    expect(Matrix.new([[9, 8, 7]]).to_vector.to_a.to_s).to eq("\[9, 8, 7\]")
    expect(Matrix.new([[9], [8]]).to_vector.to_a.to_s).to eq("\[9, 8\]")
    expect(m.to_vector).to be_nil

  it "does elementwise arithmetic and structure ops" ->
    m = Matrix.new([[1, 2], [3, 4]])
    i2 = Matrix.identity(2)
    expect(m.add(i2).to_a.to_s).to eq("\[\[2, 2\], \[3, 5\]\]")
    expect(m.sub(i2).to_a.to_s).to eq("\[\[0, 2\], \[3, 3\]\]")
    expect(m.mul(m).to_a.to_s).to eq("\[\[1, 4\], \[9, 16\]\]")
    expect(m.scale(10).to_a.to_s).to eq("\[\[10, 20\], \[30, 40\]\]")
    expect(m.transpose.to_a.to_s).to eq("\[\[1, 3\], \[2, 4\]\]")
    expect(m.trace).to eq(5)
    expect(Matrix.new([[3, 0], [0, 4]]).norm.to_s).to eq("5")

  it "multiplies matrices (hand-computed)" ->
    a = Matrix.new([[1, 2, 3], [4, 5, 6], [7, 8, 10]])
    b = Matrix.new([[1, 0, 1], [0, 1, 1], [1, 1, 0]])
    expect(a.matmul(b).to_a.to_s).to eq("\[\[4, 5, 3\], \[10, 11, 9\], \[17, 18, 15\]\]")
    a23 = Matrix.new([[1, 2, 3], [4, 5, 6]])
    b32 = Matrix.new([[7, 8], [9, 10], [11, 12]])
    expect(a23.matmul(b32).to_a.to_s).to eq("\[\[58, 64\], \[139, 154\]\]")
    m = Matrix.new([[1, 2], [3, 4]])
    expect(m.matmul(Matrix.identity(2)).to_a.to_s).to eq(m.to_a.to_s)
    expect(m.matvec(Vector.new([5, 6])).to_a.to_s).to eq("\[17, 39\]")

  it "returns nil on shape errors" ->
    m = Matrix.new([[1, 2], [3, 4]])
    a23 = Matrix.new([[1, 2, 3], [4, 5, 6]])
    expect(m.add(a23)).to be_nil
    expect(a23.matmul(a23)).to be_nil
    expect(a23.trace).to be_nil
    expect(m.matvec(Vector.new([1, 2, 3]))).to be_nil
    expect(m.row(9)).to be_nil
    expect(m.col(9)).to be_nil

describe "Koala facade" ->
  it "builds vectors and matrices" ->
    expect(Koala.vector([3, 4]).norm.to_s).to eq("5")
    expect(Koala.matrix([[1, 2], [3, 4]]).trace).to eq(5)

describe "LinAlg" ->
  it "computes determinants" ->
    expect(Matrix.new([[1, 2], [3, 4]]).det.to_s).to eq("-2")
    d3 = Matrix.new([[6, 1, 1], [4, 0 - 2, 5], [2, 8, 7]])
    expect(d3.det.to_s).to eq("-306")
    expect(Matrix.new([[1, 2], [2, 4]]).det.to_s).to eq("0")
    expect(Matrix.identity(3).det.to_s).to eq("1")
    expect(Matrix.new([[1, 2, 3], [4, 5, 6]]).det).to be_nil

  it "solves linear systems" ->
    x = Matrix.new([[2, 1], [1, 3]]).solve(Vector.new([5, 10]))
    expect(x.to_a.to_s).to eq("\[1, 3\]")
    x3 = Matrix.new([[2, 1, 0], [0, 4, 2], [0, 0, 8]]).solve([8, 20, 32])
    expect(x3.to_a.to_s).to eq("\[2.5, 3, 4\]")
    expect(LinAlg.solve(Matrix.new([[2, 1], [1, 3]]), [5, 10]).to_a.to_s).to eq("\[1, 3\]")
    expect(Matrix.new([[1, 2], [2, 4]]).solve([1, 2])).to be_nil
    expect(Matrix.new([[1, 2], [3, 4]]).solve([1, 2, 3])).to be_nil
    expect(Matrix.new([[1, 2, 3], [4, 5, 6]]).solve([1, 2])).to be_nil

  it "inverts matrices" ->
    a = Matrix.new([[2, 1], [1, 1]])
    expect(a.inv.to_a.to_s).to eq("\[\[1, -1\], \[-1, 2\]\]")
    expect(a.matmul(a.inv).to_a.to_s).to eq("\[\[1, 0\], \[0, 1\]\]")
    t = Matrix.new([[2, 1, 0], [0, 4, 2], [0, 0, 8]])
    expect(t.matmul(t.inv).to_a.to_s).to eq(Matrix.identity(3).to_a.to_s)
    expect(LinAlg.inv(a).to_a.to_s).to eq("\[\[1, -1\], \[-1, 2\]\]")
    expect(Matrix.new([[1, 2], [2, 4]]).inv).to be_nil
    expect(Matrix.new([[1, 2, 3], [4, 5, 6]]).inv).to be_nil

describe "LinAlg QR (Householder)" ->
  # Hand-computed reduced QR of [[3, 0], [4, 5]]. The first reflection
  # sends column [3, 4] (norm exactly 5) to [-5, 0] — the sign follows
  # the -sign(a_kk)*|x| convention that keeps the reflector away from
  # cancellation — and carries [0, 5] to [-4, -3]. So
  #   R = [[-5, -4], [0, -3]]      Q = [[-0.6, 0.8], [-0.8, -0.6]]
  # Every entry is a ratio of small integers (fifths), and Q R lands
  # back on the input with no rounding at all.
  it "factors a matrix into orthonormal Q and upper-triangular R" ->
    res = Matrix.new([[3, 0], [4, 5]]).qr
    expect(res[:q].shape.to_s).to eq("\[2, 2\]")
    expect(res[:r].shape.to_s).to eq("\[2, 2\]")
    expect(res[:r].to_a.to_s).to eq("\[\[-5, -4\], \[0, -3\]\]")
    expect(res[:q].to_a.to_s).to be_nums("\[\[-0.6, 0.8\], \[-0.8, -0.6\]\]")
    # the defining property: Q R reconstructs the input exactly here
    expect(res[:q].matmul(res[:r]).to_a.to_s).to be_nums("\[\[3, 0\], \[4, 5\]\]")
    # ...and Q's columns are orthonormal: Q^T Q = I to working precision
    # (the off-diagonal lands on 1.1e-16, not a printable zero — this is
    # exactly the property Householder guarantees and Gram-Schmidt does
    # not, so it is asserted numerically rather than by string).
    qtq = res[:q].transpose.matmul(res[:q]).to_a
    tiny = 1.to_f / 1000000000000.to_f
    expect(LinAlg.fabs(qtq[0][0] - 1.to_f) < tiny).to be_true
    expect(LinAlg.fabs(qtq[1][1] - 1.to_f) < tiny).to be_true
    expect(LinAlg.fabs(qtq[0][1]) < tiny).to be_true
    expect(LinAlg.fabs(qtq[1][0]) < tiny).to be_true

  # Thin QR of a TALL matrix: Q keeps the input's 4 rows but only 2
  # columns, R is 2x2. The 4-point design [1, x] for x = 0..3 gives
  # column norms 2 and sqrt(5), both printable.
  it "produces a thin Q for a tall matrix" ->
    res = LinAlg.qr(Matrix.new([[1, 0], [1, 1], [1, 2], [1, 3]]))
    expect(res[:q].shape.to_s).to eq("\[4, 2\]")
    expect(res[:r].shape.to_s).to eq("\[2, 2\]")
    expect(res[:r].to_a.to_s).to be_nums("\[\[-2, -3\], \[0, -2.23607\]\]")
    expect(res[:q].col(0).to_a.to_s).to eq("\[-0.5, -0.5, -0.5, -0.5\]")
    expect(res[:q].transpose.matmul(res[:q]).to_a.to_s).to be_nums("\[\[1, 0\], \[0, 1\]\]")

  it "solves least squares, and agrees with solve on square systems" ->
    # the 4-point fit y = 1.6x - 0.4 (hand-computed in estimator_spec
    # from XtX = [[4,6],[6,14]], Xty = [8,20])
    a = Matrix.new([[1, 0], [1, 1], [1, 2], [1, 3]])
    x = a.lstsq([0, 1, 2, 5])
    tol = 1.to_f / 1000000.to_f
    expect(x.size).to eq(2)
    expect(LinAlg.fabs(x[0] - (0.to_f - 4.to_f / 10.to_f)) < tol).to be_true
    expect(LinAlg.fabs(x[1] - 16.to_f / 10.to_f) < tol).to be_true
    # n = p is just the square case: same answer as the elimination solve
    sq = Matrix.new([[2, 1], [1, 3]])
    expect(LinAlg.lstsq(sq, [5, 10]).to_a.to_s).to eq("\[1, 3\]")
    expect(LinAlg.lstsq(sq, Vector.new([5, 10])).to_a.to_s).to eq("\[1, 3\]")

  it "returns nil for unusable shapes and dependent columns" ->
    # wider than tall: no thin QR, and the system is underdetermined
    expect(LinAlg.qr(Matrix.new([[1, 2, 3], [4, 5, 6]]))).to be_nil
    expect(Matrix.new([[1, 2, 3], [4, 5, 6]]).lstsq([1, 2])).to be_nil
    # col2 = 2*col1 — rank-deficient, and this QR does not pivot
    expect(LinAlg.qr(Matrix.new([[1, 2], [2, 4], [3, 6]]))).to be_nil
    expect(LinAlg.lstsq(Matrix.new([[1, 1, 2], [1, 2, 4], [1, 3, 6]]), [1, 2, 3])).to be_nil
    # b's size must match the row count
    expect(LinAlg.lstsq(Matrix.new([[1, 0], [1, 1]]), [1, 2, 3])).to be_nil

  # THE POINT OF QR — a head-to-head against the route it replaced.
  #
  # A Vandermonde design on clustered nodes: t = 1, 1.001, ..., 1.005
  # with columns [1, t, t^2]. cond(X) is about 1.7e6, so cond(X^T X) is
  # about 2.9e12 — forming the normal equations burns twelve of f64's
  # ~sixteen digits BEFORE the solve even starts. y is placed exactly on
  # the plane 3 + t + 2t^2, so the true answer is known and the residual
  # is zero: every bit of error below is pure arithmetic loss, not fit.
  #
  # Measured, byte-identical on both engines:
  #   normal equations (LinAlg.solve on X^T X):  max error 5.26e-4
  #   Householder QR   (LinAlg.lstsq on X):      max error 6.94e-11
  # Seven orders of magnitude — four correct digits versus eleven. The
  # thresholds are deliberately slack (QR under 1e-8, normal equations
  # over 1e-6, QR at least 1000x closer) so the spec tracks the
  # phenomenon rather than the last bit.
  it "keeps precision on an ill-conditioned design where the normal equations lose it" ->
    d = 1.to_f / 1000.to_f
    rows = []
    ys = []
    6.times -> (i)
      t = 1.to_f + i.to_f * d
      row = []
      row.push(1.to_f)
      row.push(t)
      row.push(t * t)
      rows.push(row)
      ys.push(3.to_f + t + 2.to_f * t * t)
    xm = Matrix.new(rows)
    truth = []
    truth.push(3.to_f)
    truth.push(1.to_f)
    truth.push(2.to_f)

    # QR straight off the design matrix
    qb = LinAlg.lstsq(xm, ys).to_a
    # the normal equations: X^T X beta = X^T y, through Gaussian
    # elimination — the textbook route, and the one that loses
    xt = xm.transpose
    nb = LinAlg.solve(xt.matmul(xm), xt.matvec(Vector.new(ys))).to_a
    expect(qb.size).to eq(3)
    expect(nb.size).to eq(3)

    qerr = 0.to_f
    nerr = 0.to_f
    3.times -> (i)
      qd = LinAlg.fabs(qb[i] - truth[i])
      nd = LinAlg.fabs(nb[i] - truth[i])
      qerr = qd if qd > qerr
      nerr = nd if nd > nerr

    tight = 1.to_f / 100000000.to_f
    loose = 1.to_f / 1000000.to_f
    expect(qerr < tight).to be_true            # QR is accurate...
    expect(nerr > loose).to be_true            # ...the normal equations are NOT
    expect(qerr * 1000.to_f < nerr).to be_true # by at least three decades

spec_summary
