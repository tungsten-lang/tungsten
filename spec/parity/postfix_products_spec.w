# Factorial and primorial syntax, exact promotion, and lexical boundaries.
-> check(name, got, want)
  if got != want
    << "FAIL [name]: got=[got] want=[want]"
    exit(1)

check("factorial", 10!, 3628800)
check("hex literal", 0xA!, 3628800)
check("primorial", 10#, 210)
check("zero factorial", 0!, 1)
check("one factorial", 1!, 1)
check("zero primorial", 0#, 1)
check("one primorial", 1#, 1)
check("two primorial", 2#, 2)
check("prime bound", 11#, 2310)
check("composite bound", 12#, 2310)
check("factorial method", 10.factorial, 10!)
check("primorial method", 10.primorial, 10#)
check("sum", 2 + 3!, 8)
check("power left", 3! ** 2, 36)
check("power right", 2 ** 3!, 64)
check("large factorial", 25!.to_s, "15511210043330985984000000")
check("large primorial", 53#.to_s, "32589158477190044730")
check("factorial quotient", 10! / 5!, 30240)
check("factorial quotient equal", 10! / 10!, 1)
check("factorial quotient reverse", 5! / 10!, 0)
check("factorial quotient zero", 0! / 0!, 1)
check("factorial quotient zero one", 0! / 1!, 1)
check("factorial quotient one zero", 1! / 0!, 1)
check("factorial quotient zero denominator bound", 5! / 0!, 120)
check("factorial quotient exact", (25! / 5!).to_s, "129260083694424883200000")
check("factorial method quotient", 10.factorial / 5.factorial, 30240)
N = 10
check("constant factorial", N!, 3628800)
check("constant primorial", N#, 210)
n = 10
check("variable factorial", n!, 3628800)
check("variable primorial", n#, 210)
a = 2
b = 3
check("grouped factorial", (a + b)!, 120)
check("grouped primorial", (a + b)#, 30)
check("grouped variable factorial", (n)!, 3628800)
check("nested grouping", ((a + b))!, 120)
check("nested factorial", (3!)!, 720)
check("grouped index", ([2, 5][1])#, 30)
check("grouped method factorial", ([5].first)!, 120)
check("grouped method primorial", ([5].first)#, 30)
check("grouped power", (a + b)! ** 2, 14400)
check("grouped BigInt result", (20 + 5)!.to_s, "15511210043330985984000000")
check("grouped BigInt primorial", (50 + 3)#.to_s, "32589158477190044730")
check("prefix not of group", !(a + b), false)
check("prefix not of factorial", !(a + b)!, false)
check("negation", !false, true)
check("comparison", 10 != 3, true)
comment = 10 # ordinary comment
product = 10# # comment after primorial
hinted = 10 ## i64
check("comment", comment, 10)
check("product comment", product, 210)
check("type hint", hinted, 10)

-> bang!
  17
check("bang method", bang!(), 17)
check("bare bang method", bang!, 17)

+ ProductReceiver
  -> first!
    19
check("receiver bang method", ProductReceiver.new.first!, 19)

-> dynamic_factorial(value)
  value!
-> dynamic_primorial(value)
  value#
-> dynamic_factorial_ratio(n, m)
  n! / m!
check("dynamic factorial", dynamic_factorial(10), 3628800)
check("dynamic promotion", dynamic_factorial(25).to_s, "15511210043330985984000000")
check("dynamic primorial", dynamic_primorial(10), 210)
check("dynamic factorial quotient", dynamic_factorial_ratio(10, 5), 30240)
check("dynamic exact quotient", dynamic_factorial_ratio(25, 5).to_s, "129260083694424883200000")

negative = -1
failed = false
begin
  negative!
rescue
  failed = true
check("negative factorial", failed, true)
failed = false
begin
  (negative)!
rescue
  failed = true
check("negative grouped factorial", failed, true)
failed = false
begin
  (negative)#
rescue
  failed = true
check("negative grouped primorial", failed, true)
failed = false
begin
  (-1).factorial / 5!
rescue
  failed = true
check("negative factorial quotient", failed, true)
failed = false
begin
  negative#
rescue
  failed = true
check("negative primorial", failed, true)
-> captured_factorial(value)
  f = -> () value!
  f()
check("captured parameter", captured_factorial(5), 120)
check("block parameter", [3, 4].map(-> (item) item!), [6, 24])
implicit = [3, 4].map -> item!
check("implicit block parameter", implicit, [6, 24])
-> positional_factorial/1
  @1!
check("positional parameter", positional_factorial(5), 120)
+ ProductHolder
  -> new(@n)
    nil
  -> factorial
    @n!
  -> primorial
    @n#
holder = ProductHolder.new(10)
check("instance variable factorial", holder.factorial, 3628800)
check("instance variable primorial", holder.primorial, 210)
<< "PASS postfix products"
