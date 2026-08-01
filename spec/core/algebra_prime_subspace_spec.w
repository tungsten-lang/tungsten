# Canonical subspace arithmetic over prime fields.

use algebra

u = PrimeFieldSubspace.new(5, 4, [
  [1, 0, 1, 0],
  [0, 1, 0, 1],
  [2, 0, 2, 0]])
v = PrimeFieldSubspace.new(5, 4, [
  [1, 0, 1, 0],
  [0, 0, 1, 1]])

raise "FAIL subspace.u.certified" if !u.certified?
<< "PASS subspace.u.certified"
raise "FAIL subspace.u.dimension" if u.dimension != 2
<< "PASS subspace.u.dimension"
raise "FAIL subspace.u.canonical" if (
  u.basis.to_s != "\[\[1, 0, 1, 0\], \[0, 1, 0, 1\]\]")
<< "PASS subspace.u.canonical"
raise "FAIL subspace.u.contains" if !u.contains_vector?([3, 4, 3, 4])
<< "PASS subspace.u.contains"
raise "FAIL subspace.u.rejects" if u.contains_vector?([0, 0, 1, 0])
<< "PASS subspace.u.rejects"

coordinates = u.coordinates([3, 4, 3, 4])
raise "FAIL subspace.coordinates" if coordinates.to_s != "\[3, 4\]"
<< "PASS subspace.coordinates"
raise "FAIL subspace.linear_combination" if (
  u.linear_combination(coordinates).to_s != "\[3, 4, 3, 4\]")
<< "PASS subspace.linear_combination"

intersection = u.intersection(v)
expected_intersection = PrimeFieldSubspace.new(5, 4, [[1, 0, 1, 0]])
raise "FAIL subspace.intersection" if !intersection.same_subspace?(
  expected_intersection)
<< "PASS subspace.intersection"
sum = u.sum(v)
raise "FAIL subspace.sum.dimension" if sum.dimension != 3
<< "PASS subspace.sum.dimension"
raise "FAIL subspace.sum.contains" if !sum.contains_subspace?(u) || (
  !sum.contains_subspace?(v))
<< "PASS subspace.sum.contains"

orthogonal = u.orthogonal_complement
raise "FAIL subspace.orthogonal.dimension" if orthogonal.dimension != 2
<< "PASS subspace.orthogonal.dimension"
u.basis.each -> (left)
  orthogonal.basis.each -> (right)
    dot = 0
    index = 0
    while index < 4
      dot += left[index]*right[index]
      index += 1
    raise "FAIL subspace.orthogonal.dot" if dot % 5 != 0
<< "PASS subspace.orthogonal.dot"

zero = PrimeFieldSubspace.zero(5, 4)
full = PrimeFieldSubspace.full(5, 4)
raise "FAIL subspace.zero" if !zero.zero? || zero.codimension != 4
<< "PASS subspace.zero"
raise "FAIL subspace.full" if !full.full? || !full.contains_subspace?(sum)
<< "PASS subspace.full"

bad_ambient_failed = false
begin
  u.sum(PrimeFieldSubspace.zero(5, 3))
rescue error
  bad_ambient_failed = error.to_s.include?("ambient dimensions")
raise "FAIL subspace.mismatch_is_loud" if !bad_ambient_failed
<< "PASS subspace.mismatch_is_loud"

<< "algebra_prime_subspace_spec: all checks passed"
