use algebra

rank = 14
gram = []
basis = []
i = 0
while i < rank
  gram_row = []
  basis_row = []
  j = 0
  while j < rank
    gram_row.push(i == j ? 1 : 0)
    if j == i
      basis_row.push(1)
    elsif j < i
      basis_row.push((i - j) * 17 + 3)
    else
      basis_row.push(0)
    j += 1
  gram.push(gram_row)
  basis.push(basis_row)
  i += 1

warm = ApproximateGramLatticeBasisSearch.new(
  gram, basis, ~0.75, 100000)
raise "approximate LLL did not complete" if !warm.completed?
swap_case = ApproximateGramLatticeBasisSearch.new(
  [[1, 0], [0, 1]], [[4, 1], [1, 0]], ~0.75, 100)
if !swap_case.completed? || swap_case.reduced_basis.to_s != "\[\[1, 0\], \[0, 1\]\]"
  raise "approximate LLL swap parity mismatch"

iterations = 8
t0 = ccall("__w_clock_ms")
k = 0
last = warm
while k < iterations
  last = ApproximateGramLatticeBasisSearch.new(
    gram, basis, ~0.75, 100000)
  raise "approximate LLL did not complete" if !last.completed?
  k += 1
t1 = ccall("__w_clock_ms")

reduced = last.reduced_basis
checksum = 0
i = 0
while i < rank
  j = 0
  while j < rank
    checksum += reduced[i][j] * (i * rank + j + 1)
    j += 1
  i += 1
raise "approximate LLL checksum mismatch" if checksum != 1379
<< "checksum=" + checksum.to_s()
<< "steps=" + last.steps.to_s()
<< "elapsed_ms=" + (t1 - t0).to_s()
