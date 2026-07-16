# Candidate tree-walker smoke. No explicit core imports: primitive runtime-class
# lookup must autoload Float and BigInt after their native identity ICs vanish.

-> fail(name, got, expected)
  << "FAIL interpreter [name] got=[got] expected=[expected]"
  exit(1)

-> check_bits(name, got, expected)
  got_bits = wvalue_bits(got)
  expected_bits = wvalue_bits(expected)
  if got_bits != expected_bits
    fail(name, got_bits, expected_bits)

float_value = ~1.5
check_bits("Float plain", float_value.to_f, float_value)
check_bits("Float surplus", float_value.to_f(1, 2, 3), float_value)

bigint_value = 18_446_744_073_709_551_617
check_bits("BigInt plain", bigint_value.to_i, bigint_value)
check_bits("BigInt surplus", bigint_value.to_i(1, 2, 3), bigint_value)

# The tree walker passes a trailing block to the callee (native lowering uses
# its separate implicit-result-each rewrite). These identity bodies declare no
# block and therefore ignore it, exactly as the old C handlers did here.
float_hits = 0
float_block_result = float_value.to_f -> (ignored)
  float_hits += 1
check_bits("Float trailing-block result", float_block_result, float_value)
if float_hits != 0
  fail("Float trailing-block hits", float_hits, 0)

bigint_hits = 0
bigint_block_result = bigint_value.to_i -> (ignored)
  bigint_hits += 1
check_bits("BigInt trailing-block result", bigint_block_result, bigint_value)
if bigint_hits != 0
  fail("BigInt trailing-block hits", bigint_hits, 0)

<< "PASS identity leaves: no-use interpreter autoload, receiver identity, surplus args, and block handling"
