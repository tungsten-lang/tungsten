+ Closure
  - data
    * w64 fn_ptr
    * w64[] captures
    i32 capture_count
    i32 arity

  # Declared parameter count (0 for a legacy closure of unknown arity).
  -> arity
    n = $arity ## i64
    tag = -1_688_849_860_263_936 ## i64  # 0xFFFA000000000000
    wvalue_from_bits((tag | n) ## i64)

  # Explicit currying: `add/2.curry` is `->(a) ->(b) add(a, b)`. Pass `n`
  # for a closure whose arity is unknown. Partial application without
  # currying is spelled with placeholders: `add(1, _)`.
  -> curry(n = nil)
    if n == nil
      n = arity
    f = self
    if n <= 1
      return f
    if n == 2
      return ->(a)
        ->(b)
          f.call(a, b)
    if n == 3
      return ->(a)
        ->(b)
          ->(c)
            f.call(a, b, c)
    if n == 4
      return ->(a)
        ->(b)
          ->(c)
            ->(d)
              f.call(a, b, c, d)
    raise "curry supports closures of arity 1..4, got [n]"
