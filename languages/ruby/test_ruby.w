# languages/ruby/test_ruby.w — Comprehensive test suite for Tungsten's Ruby 3.4 / 4.0 engine.

use core/ruby

PASS = [0]
FAIL = [0]

-> check(name, cond)
  if cond
    PASS[0] += 1
  else
    FAIL[0] += 1
    << "FAIL: " + name

-> check_eval(name, src, want, vm = nil)
  begin
    got = Ruby.eval(src, vm)
    if got == want
      PASS[0] += 1
    else
      FAIL[0] += 1
      << "FAIL " + name + ": got=" + got.to_s + " want=" + want.to_s
  rescue e
    FAIL[0] += 1
    << "ERR  " + name + ": " + e.to_s

# --- 1. Tungsten AST mapping & superset extension detection ---
ast_basic = Ruby.to_tungsten_ast('def add(a, b) = a + b')
check("ast maps to KIND_PROGRAM", ast_basic[:tungsten_kind] == "KIND_PROGRAM")
check("ast basic method maps directly (0 extensions)", Ruby.ast_extensions('def add(a, b) = a + b').size == 0)
check("complex, const_path, lambda, case_in, alias map natively to Tungsten AST (0 extensions)",
      Ruby.ast_extensions('f = ->(x) { A::B; 1 + 2i; case x in [a, *b]; a; end }').size == 0)
exts = Ruby.ast_extensions('class << self; def hi; redo; defined?(x); end; end')
check("ast detects minimal true extensions (EXT_SINGLETON_CLASS, EXT_REDO, EXT_DEFINED)",
      exts.include?("EXT_SINGLETON_CLASS") && exts.include?("EXT_REDO") && exts.include?("EXT_DEFINED"))

# --- 2. Numerics: floor division, modulo, BigInt, Rational, Complex ---
check_eval("int arithmetic", '1 + 2 * 3 ** 2', 19)
check_eval("ruby floor division -7 / 2 == -4", '-7 / 2', -4)
check_eval("ruby modulo -7 % 2 == 1", '-7 % 2', 1)
check_eval("ruby divmod", '(-7).divmod(2)', [-4, 1])
check_eval("bigint 2**100", '(2 ** 100).to_s', "1267650600228229401496703205376")
check_eval("rational 1/3r + 1/6r == 1/2r", '(Rational(1, 3) + Rational(1, 6)).to_s', "1/2")
check_eval("rational literal 1r / 3 + 1r / 6", '(1r / 3 + 1r / 6).to_s', "1/2")
check_eval("complex (2+3i) * (4-5i) == 23+2i", '((2 + 3i) * (4 - 5i)).to_s', "23+2i")
check_eval("integer pow mod", '2.pow(10, 1000)', 24)
check_eval("integer gcd & lcm", '[12.gcd(18), 12.lcm(18)]', [6, 36])

# --- 3. Mutable Strings, Encodings, frozen_string_literal, Interpolation, Heredocs ---
check_eval('mutable string << and []=', 's = "hello"; s << " world"; s[0] = "H"; s', "Hello world")
check_eval("string interpolation", 'x = 6; y = 7; "#{x} * #{y} = #{x * y}"', "6 * 7 = 42")
check_eval("string encoding UTF-8 -> BINARY", 's = "abc"; s.force_encoding("ASCII-8BIT"); s.encoding.to_s', "ASCII-8BIT")
check_eval("frozen_string_literal raises FrozenError", "# frozen_string_literal: true\nbegin\n  s = \"hi\"\n  s << \"!\"\n  \"no\"\nrescue FrozenError\n  \"frozen\"\nend", "frozen")
check_eval("squiggly heredoc", "s = <<~TXT\n    hello\n    world\n  TXT\ns", "hello\nworld\n")
check_eval("printf % formatting", '"%04d %.2f %s" % [42, 3.14159, "ok"]', "0042 3.14 ok")

# --- 4. Regexp, MatchData, Named Captures, $~/$1..$9 ---
check_eval("regex =~ and $1/$2", '"2026-11-25" =~ /(\d{4})-(\d{2})-(\d{2})/; [$1, $2, $3]', ["2026", "11", "25"])
check_eval("regex named captures bind locals on literal =~", '/(?<year>\d{4})-(?<month>\d{2})/ =~ "Date: 2026-11"; [year, month]', ["2026", "11"])
check_eval("MatchData named_captures & pre/post", 'm = "hello 42 world".match(/(?<num>\d+)/); [m[:num], m.pre_match, m.post_match]', ["42", "hello ", " world"])
check_eval("string gsub with backreference", '"foo-bar".gsub(/(\w+)-(\w+)/, "\\2_\\1")', "bar_foo")
check_eval("string scan", '"a1b22c333".scan(/\d+/)', ["1", "22", "333"])

# --- 5. Ruby 3.4/4.0 Blocks, it, _1, &:sym, Proc, Lambda, Non-local Return ---
check_eval("Ruby 3.4 `it` block param", '[1, 2, 3, 4].map { it * it }', [1, 4, 9, 16])
check_eval("numbered params _1 _2", '[[1, 2], [3, 4]].map { _1 + _2 }', [3, 7])
check_eval("Symbol#to_proc &:upcase", '%w[a b c].map(&:upcase)', ["A", "B", "C"])
check_eval("stabby lambda & currying", 'add = ->(a, b, c) { a + b + c }; cur = add.curry; cur.(1).(2).(3)', 6)
check("non-local return from block vs local return from lambda", Ruby.eval('
def test_block
  [1, 2, 3].each { |x| return x * 10 if x == 2 }
  99
end
def test_lambda
  f = ->(x) { return x * 10 }
  f.call(2) + 5
end
[test_block, test_lambda]
') == [20, 25])
check("yield & block_given?", Ruby.eval('
def wrap(x)
  block_given? ? yield(x) : x
end
[wrap(5), wrap(5) { |n| n * 3 }]
') == [5, 15])

# --- 6. Classes, Modules, prepend/include/extend, Eigenclasses, super, method_missing, Struct, Data.define ---
check("class, inheritance, super, attr_accessor", Ruby.eval('
class Animal
  attr_accessor :name
  def initialize(name); @name = name; end
  def speak; "#{@name} makes a sound"; end
end
class Dog < Animal
  def speak; super + " (woof!)"; end
end
Dog.new("Rex").speak
') == "Rex makes a sound (woof!)")

check("module prepend overrides class method + super", Ruby.eval('
module Loud
  def greet; super.upcase + "!"; end
end
class Greeter
  prepend Loud
  def greet; "hello"; end
end
Greeter.new.greet
') == "HELLO!")

check("singleton class (class << self) and open class", Ruby.eval('
class Counter
  class << self
    def answer; 42; end
  end
end
class Integer
  def doubled; self * 2; end
end
[Counter.answer, 21.doubled]
') == [42, 42])

check("method_missing", Ruby.eval('
class Ghost
  def method_missing(name, *args)
    "#{name}:#{args.join(",")}"
  end
end
Ghost.new.fly(1, 2)
') == "fly:1,2")

check("Ruby 3.2-4.0 Data.define immutable value class + with", Ruby.eval('
Point = Data.define(:x, :y)
p1 = Point.new(x: 3, y: 4)
p2 = p1.with(y: 10)
[p1.x, p1.y, p2.x, p2.y, p1.frozen?, p1 == Point.new(3, 4)]
') == [3, 4, 3, 10, true, true])

check("Struct.new with block", Ruby.eval('
User = Struct.new(:first, :last) do
  def full; "#{first} #{last}"; end
end
User.new("Ada", "Lovelace").full
') == "Ada Lovelace")

# --- 7. Keyword args, shorthand hash, endless methods, multi-assign, safe nav ---
check("endless method + kwargs + shorthand hash", Ruby.eval('
def make_point(x:, y: 0, **extra) = {x:, y:, **extra}
h = make_point(x: 5, z: 9)
[h[:x], h[:y], h[:z]]
') == [5, 0, 9])

check_eval("multi-assign with splat", 'a, *mid, z = [1, 2, 3, 4, 5]; [a, mid, z]', [1, [2, 3, 4], 5])
check_eval("safe navigation &.", 'x = nil; [x&.upcase, "hi"&.upcase]', [nil, "HI"])

# --- 8. Ruby 3.0-4.0 Pattern Matching (case..in, array/hash/pin/guard/as, in, =>) ---
check("pattern matching array + guard + pin", Ruby.eval('
target = 10
res = case [10, 20, 30, 40]
in [^target, second, *rest] if second > 15
  [second, rest]
else
  :nope
end
res
') == [20, [30, 40]])

check("pattern matching hash + rightward =>", Ruby.eval('
{user: {name: "Erik", role: "admin"}} => {user: {name:, role:}}
"#{name}:#{role}"
') == "Erik:admin")

check_eval("one-line pattern test `in`", '[[1, 2] in [Integer, Integer], [1, "a"] in [Integer, Integer]]', [true, false])

# --- 9. Exceptions: begin/rescue/else/ensure/retry ---
check("rescue + retry + ensure", Ruby.eval('
attempts = 0
cleaned = false
val = begin
  attempts += 1
  raise ZeroDivisionError, "boom" if attempts < 3
  :ok
rescue ZeroDivisionError
  retry
ensure
  cleaned = true
end
[attempts, val, cleaned]
') == [3, "ok", true])

# --- 10. Collections, Enumerable, Enumerator, JSON, Math ---
check_eval("Enumerable pipeline", '(1..10).select(&:even?).map { it * 2 }.sum', 60)
check_eval("Array tally & group_by", 't = %w[a b a c a b].tally; [t["a"], t["b"], t["c"]]', [3, 2, 1])
check_eval("Enumerator next/peek/rewind", 'e = [10, 20].each; a = e.peek; b = e.next; c = e.next; e.rewind; [a, b, c, e.next]', [10, 10, 20, 10])
check_eval("JSON roundtrip", 'JSON.parse(JSON.generate({a: 1, b: [2, 3]}))["b"]', [2, 3])

# --- 11. Zero-copy Ruby <-> Tungsten calling protocol ---
vm = Ruby.vm
vm.register("hypot", ->(a) Math.sqrt(a[0].to_f * a[0].to_f + a[1].to_f * a[1].to_f))
sum_fn = ->(a)
  s = 0
  a[0].each ->(x) s += x
  s
vm.register("sum_all", sum_fn)
check_eval("Tungsten.hypot called directly from Ruby", 'Tungsten.hypot(3.0, 4.0)', ~5.0, vm)
check_eval("Tungsten.call(:sum_all, array) from Ruby", 'Tungsten.call(:sum_all, (1..100).to_a)', 5050, vm)

<< "Ruby 3.4/4.0 tests: " + PASS[0].to_s + " passed, " + FAIL[0].to_s + " failed"
exit(FAIL[0] > 0 ? 1 : 0)
