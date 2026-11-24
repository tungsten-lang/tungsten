# Covers Tranche 13 (String +/<< fast lowering, StringBuffer/Array <<,
# int_temp_release non-BigInt pruning) and Tranche 14 (register-passing
# w_method_call_cached_{1,2,3}_any across builtin, source, rope, optional-arg,
# and constructor dispatch).

failures = 0

-> check(label, ok)
  if !ok
    << "FAIL: " + label
    failures += 1

+ CustomAdd
  -> new(@prefix)
  -> +(other)
    @prefix + ":" + other
  -> <<(other)
    @prefix = @prefix + "|" + other
    self
  -> value
    @prefix

+ PolyReceiver
  -> new(@base)
  -> add1(a)
    @base + a
  -> add2(a, b)
    @base + a + b
  -> add3(a, b, c)
    @base + a + b + c
  -> add4(a, b, c, d)
    @base + a + b + c + d
  -> opt2(a, b = 10)
    @base + a + b
  -> opt3(a, b = 20, c = 30)
    @base + a + b + c

+ Ctor3
  -> new(@a, @b, @c)
  -> sum
    @a + @b + @c

-> dyn_val(x)
  x

-> append_via_param(buf, s)
  buf << s
  buf

-> concat_rhs(x)
  "pre-" + x + "-post"

-> concat_lhs(x)
  x + "-tail"

-> concat_long_chain(x, y)
  base = "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"
  (base + x) + y + "!"

-> call_1(r, a)
  r.add1(a)

-> call_2(r, a, b)
  r.add2(a, b)

-> call_3(r, a, b, c)
  r.add3(a, b, c)

-> call_4(r, a, b, c, d)
  r.add4(a, b, c, d)

-> call_slice(r, a, b)
  r.slice(a, b)

-> call_index(r, sub)
  r.index(sub)

-> call_opt2_one(r, a)
  r.opt2(a)

-> call_opt3_two(r, a, b)
  r.opt3(a, b)

-> call_ctor3(cls, a, b, c)
  cls.new(a, b, c)

# --- String + unknown / unknown + String ---
check("concat_rhs string", concat_rhs(dyn_val("mid")) == "pre-mid-post")
check("concat_lhs string", concat_lhs(dyn_val("head")) == "head-tail")
check("concat_long_chain", concat_long_chain(dyn_val("-A-"), dyn_val("-B-")) == "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ-A--B-!")
check("custom + string", concat_lhs(dyn_val(CustomAdd.new("K"))) == "K:-tail")

# Strict TypeError preserved on String + non-String
got_err = false
begin
  concat_rhs(dyn_val(42))
rescue e
  got_err = true
check("string + int raises", got_err)

got_err2 = false
begin
  concat_lhs(dyn_val(42))
rescue e
  got_err2 = true
check("int + string raises", got_err2)

# --- StringBuffer << any, Array <<, unknown << String ---
sb = StringBuffer(16)
sb << "a=" << dyn_val(123) << ",b=" << dyn_val("ok")
check("strbuf << any chain", sb.to_s() == "a=123,b=ok")

sb2 = StringBuffer(16)
append_via_param(sb2, "hello")
append_via_param(sb2, " world")
check("unknown param << str on StringBuffer", sb2.to_s() == "hello world")

arr = []
arr << 1 << "two" << 3
check("array << chain", arr.size() == 3 && arr[0] == 1 && arr[1] == "two" && arr[2] == 3)

arr2 = []
append_via_param(arr2, "pushed")
check("unknown param << str on Array", arr2.size() == 1 && arr2[0] == "pushed")

cust = CustomAdd.new("x")
append_via_param(cust, "y")
check("unknown param << str on CustomAdd", cust.value == "x|y")

# --- Register-passing 1/2/3-arg and vector 4-arg cached dispatch ---
p = PolyReceiver.new(100)
check("cached_1_any source", call_1(p, 5) == 105)
check("cached_2_any source", call_2(p, 5, 7) == 112)
check("cached_3_any source", call_3(p, 5, 7, 9) == 121)
check("cached_4 vector source", call_4(p, 1, 2, 3, 4) == 110)
check("cached_1_any optional default", call_opt2_one(p, 5) == 115)
check("cached_2_any optional default", call_opt3_two(p, 5, 6) == 141)
check("cached_3_any constructor", call_ctor3(Ctor3, 10, 20, 30).sum == 60)

# Builtin native wrappers via 1/2-arg register-passing cached dispatch
s_long = "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"
rope = s_long + s_long
check("cached_2_any String#slice", call_slice(dyn_val("abcdef"), 2, 3) == "cde")
check("cached_2_any Rope#slice", call_slice(dyn_val(rope), 60, 4) == "YZ01")
check("cached_1_any String#index", call_index(dyn_val("hello world"), "world") == 6)
check("cached_1_any Rope#index", call_index(dyn_val(rope), "YZ01") == 60)
check("cached_1_any Array#index", call_index(dyn_val([10, 20, 30]), 20) == 1)

# BigInt & small mask (exercises ownership non-BigInt pruning without leak/miscompile)
big = (1 << 100) + 0xab
check("bigint & 0xff", (big & 0xff) == 0xab)

if failures == 0
  << "PASS string_ops_and_register_dispatch"
else
  exit(1)
