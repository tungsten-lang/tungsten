# Canonical COO/CSR semantics and ownership, in both engines.
use core/sparse

-> sparse_check(name, condition)
  raise "FAIL " + name if !condition
  << "PASS " + name

ri = [1, 0, 0, 1, 0, 0]
ci = [1, 1, 0, 1, 0, 1]
values = [~7.0, ~4.0, ~2.0, ~-7.0, ~3.0, ~-1.0]
coo = SparseMatrix.coo(2, 2, ri, ci, values)
csr = coo.to_csr
want = [[~5.0, ~3.0], [~0.0, ~0.0]]
sparse_check("coo.canonical", coo.nnz == 2 && coo.format == :coo && coo.to_dense == want)
sparse_check("csr.sorted", csr.nnz == 2 && csr.indices_at(0) == 0 && csr.indices_at(1) == 1 &&
             csr.indptr_at(0) == 0 && csr.indptr_at(1) == 2 && csr.indptr_at(2) == 2)
sparse_check("duplicate.matvec_dense_parity", coo.matvec([~2.0, ~3.0]) == [~19.0, ~0.0] &&
             csr.matvec([~2.0, ~3.0]) == [~19.0, ~0.0] && csr.to_dense == want)
ri[0] = 99
ci[0] = 99
values[0] = ~99.0
sparse_check("coo.owned", coo.to_dense == want && csr.to_dense == want)

pointers = [0, 4, 4]
columns = [1, 0, 1, 0]
data = [~2.0, ~1.0, ~-2.0, ~4.0]
direct = SparseMatrix.csr(2, 2, pointers, columns, data)
sparse_check("csr.constructor_coalesces", direct.nnz == 1 && direct.to_dense == [[~5.0, ~0.0], [~0.0, ~0.0]])
pointers[1] = 0
columns[0] = 99
data[0] = ~99.0
sparse_check("csr.owned", direct.matvec([~1.0, ~1.0]) == [~5.0, ~0.0])
sparse_check("empty.rectangular", SparseMatrix.coo(2, 0, [], [], []).to_dense == [[], []] &&
             SparseMatrix.csr(0, 3, [0], [], []).to_dense == [])
sparse_check("dense.numeric_conversion", SparseMatrix.from_dense([[1, Rational.new(1, 2)], [0.25, 0]]).to_dense ==
             [[~1.0, ~0.5], [~0.25, ~0.0]])
[[[1, 2], [3]], [1, 2], [[Float.new]]].each -> (rows)
  rejected = false
  begin
    SparseMatrix.from_dense(rows)
  rescue error
    rejected = error.to_s.include?("SparseMatrix")
  sparse_check("dense.reject_invalid", rejected)
rejected = false
begin
  SparseMatrix.eye(Int.new)
rescue error
  rejected = error.to_s.include?("dimensions")
sparse_check("identity.dimension_guard", rejected)

bad_cases = [
  [-1, 2, [], [], []], [Integer.new, 2, [], [], []],
  [2, 2, [0], [], [~1.0]], [2, 2, [2], [0], [~1.0]],
  [2, 2, [-1], [0], [~1.0]], [2, 2, [0], [2], [~1.0]],
  [2, 2, [~0.0], [0], [~1.0]], [2, 2, [Int.new], [0], [~1.0]],
  [2, 2, [0], [0], [Math.sqrt(~-1.0)]],
  [2, 2, [0], [0], [Math.exp(~10000.0)]],
  [2, 2, [0], [0], [Float.new]], [2, 2, [0], [0], [Integer.new]],
  [2, 2, [0], [0], ["1"]],
  [2, 2, [0, 0], [0, 0], [~1.0e308, ~1.0e308]]
]
bad_cases.each -> (args)
  rejected = false
  begin
    SparseMatrix.coo(args[0], args[1], args[2], args[3], args[4])
  rescue error
    rejected = error.to_s.include?("SparseMatrix")
  sparse_check("coo.reject_invalid", rejected)

[[1, 1, 1], [0, 2, 1], [0, 0, 0], [0, ~1.0, 1], [0, Int.new, 1], [0, 1]].each -> (pointers)
  rejected = false
  begin
    SparseMatrix.csr(2, 2, pointers, [0], [~1.0])
  rescue error
    rejected = error.to_s.include?("SparseMatrix")
  sparse_check("csr.reject_invalid", rejected)
<< "sparse_canonical_spec: all checks passed"
