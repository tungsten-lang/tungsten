# Koala/Core sparse integration. SparseFrame is deliberately only a data
# adapter: algebra and iterative solves remain owned by core SparseMatrix.
#
# Run both engines:
#   BIT_HOME=bits bin/tungsten bits/tungsten-koala/spec/sparse_frame_spec.w
#   BIT_HOME=bits bin/tungsten -o /tmp/koala_sparse bits/tungsten-koala/spec/sparse_frame_spec.w && /tmp/koala_sparse

use spec
use koala
use support

describe "SparseFrame" ->
  it "round trips rows through canonical Core CSR" ->
    sparse = SparseFrame.from_rows([[0, 2, 0], [3, 0, 4]])
    expect(sparse.format).to eq(:csr)
    expect(sparse.shape.to_s).to eq("\[2, 3\]")
    expect(sparse.nnz).to eq(3)
    expect(SparseFrame.to_rows(sparse).to_s).to be_nums("\[\[0, 2, 0\], \[3, 0, 4\]\]")

  it "keeps sparse algebra in Core" ->
    diagonal = SparseFrame.from_rows([[4, 0], [0, 5]])
    result = diagonal.cg([8.to_f, 15.to_f])
    expect(result.converged?).to be_true
    expect(result.x.to_s).to be_nums("\[2, 3\]")

  it "bridges numeric DataFrame columns without reimplementing storage" ->
    frame = DataFrame.new([[:a, [0, 2]], [:b, [3, 0]]])
    sparse = SparseFrame.from_frame(frame)
    expect(sparse.nnz).to eq(2)
    roundtrip = SparseFrame.to_frame(sparse, ["a", "b"])
    expect(roundtrip.column_names.join(",")).to eq("a,b")
    expect(roundtrip.column_values("a").to_s).to be_nums("\[0, 2\]")
    expect(roundtrip.column_values("b").to_s).to be_nums("\[3, 0\]")
