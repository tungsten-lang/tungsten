# Lexer & parser correctness fixes:
# - bare calls to methods/functions named after type keywords (string/int/bool/integer)
# - bare `return if cond` / `return unless cond` followed by statements (and value forms)
# - `@p+@q` / `@p-@q` / `-@p` without spaces while keeping `-> +@` / `-> -@`
# - non-collection pipeline `(expr)/name` raises cleanly instead of segfaulting

-> check(name, cond)
  if cond
    << "PASS " + name
  else
    << "FAIL " + name
    exit 1

# 1. Methods/functions named after type keywords
+ Writer
  -> string(text)
    text.size

  -> int(n)
    n * 2

  -> bool(v)
    !v

  -> run(key)
    string(key.to_s) + int(5) + (bool(false) ? 1 : 0)

check("type-named instance methods bare call", Writer.new.run("abc") == 14)

-> integer(x)
  x + 100

check("type-named top-level function call", integer(23) == 123)

arr_u8 = u8[4]
arr_u8[0] = 7
check("u8 typed array still works", arr_u8.size == 4 && arr_u8[0] == 7)

# 2. Bare return if / unless followed by statements, plus value forms
-> early_if(x)
  return if x == 0
  x + 1

-> early_unless(x)
  return unless x > 0
  x * 10

-> value_if_block(x)
  return if x == 0
    100
  else
    200

check("bare return if (taken)", early_if(0) == nil)
check("bare return if (not taken)", early_if(5) == 6)
check("bare return unless (taken)", early_unless(0) == nil)
check("bare return unless (not taken)", early_unless(3) == 30)
check("return if indented expression (true)", value_if_block(0) == 100)
check("return if indented expression (false)", value_if_block(1) == 200)

# 3. @p+@q, @p-@q, -@p without spaces, plus -> -@ / -> +@ unary definitions
+ Pair
  -> new(@p, @q)

  -> sum_nospace
    @p+@q

  -> diff_nospace
    @p-@q

  -> neg_p
    -@p

  -> -@
    Pair.new(-@p, -@q)

  -> +@
    Pair.new(@p, @q)

  ro :p, :q

pr = Pair.new(10, 3)
check("@p+@q without spaces", pr.sum_nospace == 13)
check("@p-@q without spaces", pr.diff_nospace == 7)
check("-@p without spaces", pr.neg_p == -10)
npr = -pr
check("unary -@ method still works", npr.p == -10 && npr.q == -3)

# 4. Non-collection pipeline base raises cleanly instead of segfaulting
period = 3
check("spaced division works", ((10 + period - 1) / period) * period == 12)
pipe_raised = false
begin
  ((10 + period - 1)/period) * period
rescue err
  pipe_raised = true
check("non-collection /ident pipeline raises cleanly", pipe_raised)
