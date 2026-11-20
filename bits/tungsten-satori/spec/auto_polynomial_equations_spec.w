use ../lib/satori
use proof_source

s = Session.new(".")
s.quiet = true
s.load_prelude
path = "bits/tungsten-satori/spec/auto_polynomial_equations.sat"
s.run_file(path)
if s.failures != 0
  raise "polynomial combination proofs failed"
proof_source_blocks(path).each -> (block)
  name = block[0]
  if ["supplied_product", "other_square", "second_moment"].include?(name)
    next
  th = s.theorems[name]
  expected = ["oracle:ring"]
  if name == "named"
    expected = ["axiom:supplied_product", "oracle:ring"]
  elsif name == "marked_moments"
    expected = ["axiom:second_moment", "oracle:ring"]
  elsif name == "natural_product"
    expected = ["oracle:arith", "oracle:ring"]
  elsif ["product_of_sums", "natural_moments", "scaled_moments"].include?(name)
    expected = ["oracle:arith"]
  if th == nil || th.hyps.size != 0 || th.tags != expected
    raise "unexpected polynomial proof or dependency: " + name
path = "bits/tungsten-satori/spec/auto_polynomial_equations_failure.sat"
proof_source_blocks(path).each -> (block)
  before = s.failures
  s.run_source(block[1].join("\n"))
  if s.failures != before+1 || s.theorems[block[0]] != nil
    raise "incorrect polynomial combination: " + block[0]
<< "Polynomial equation inference passed"
