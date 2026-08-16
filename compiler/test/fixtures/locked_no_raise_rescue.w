## no_raise
fn promised_increment(value)
  value + 1

fn safe_scc_left()
  if false
    safe_scc_right()
  else
    40

fn safe_scc_right()
  if false
    safe_scc_left()
  else
    42

fn unsafe_divide(value, divisor)
  value = value ## i64
  divisor = divisor ## i64
  value / divisor

+ NoRaiseProof
  -> safe_add(value)
    begin
      promised_increment(value)
    rescue error
      0

  -> safe_int_add()
    value = 40 ## i64
    begin
      value + 2
    rescue error
      0

  -> safe_scc_call()
    begin
      safe_scc_left()
    rescue error
      0

  -> method_scc_left(value)
    value = value ## i64
    if value <= 0
      40
    else
      method_scc_right(value - 1)

  -> method_scc_right(value)
    value = value ## i64
    if value <= 0
      42
    else
      method_scc_left(value - 1)

  -> safe_method_scc_call(value)
    begin
      method_scc_left(value)
    rescue error
      0

  -> risky_div(value, divisor)
    begin
      value / divisor
    rescue error
      0

  -> risky_transitive_div(value, divisor)
    begin
      unsafe_divide(value, divisor)
    rescue error
      0

Tungsten.LOCK_THE_DOORS!

proof = NoRaiseProof.new()
<< proof.safe_add(41)
<< proof.safe_int_add()
<< proof.safe_scc_call()
<< proof.safe_method_scc_call(1)
<< proof.risky_div(84, 2)
<< proof.risky_transitive_div(84, 2)
