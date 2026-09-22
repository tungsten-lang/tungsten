use core/set

-> math_check(actual, expected)
  if actual != expected
    raise "math operator check failed: [actual] != [expected]"

+ MathTrace
  -> new
    @values = []
  -> mark(value)
    @values.push(value)
    value
  -> values
    @values
  -> receiver
    @values.push(-1)
    self

trace = MathTrace.new
identity = ->(x) x
lazy = trace.mark ∘ identity
math_check(trace.values, [])
math_check(lazy.call(7), 7)
math_check(trace.values, [7])
math_check((trace.mark(0) < trace.mark(2) < trace.mark(4) < trace.mark(6)), true)
math_check(trace.values, [7, 0, 2, 4, 6])
math_check((trace.mark(9) < trace.mark(2) < trace.mark(100)), false)
math_check(trace.values, [7, 0, 2, 4, 6, 9, 2])

# Composition never invokes either operand while it is constructed.
-> math_inner(x)
  << "inner"
  x + 1

-> math_outer(x)
  << "outer"
  x * 2

h = math_outer ∘ math_inner
<< "composed"
<< h.call(3)

f = ->(x) x + 10
g = ->(x) x * 3
<< (f ∘ g).call(4)
<< (math_outer ∘ f ∘ g).call(4)
-> math_compose(first, second)
  first ∘ second
escaped = math_compose(f, g)
math_check(escaped.call(4), 22)
math_check(((f ∘ g) ∘ identity).call(4), 22)
math_check(((->(x) x + 1) ∘ identity).call(8), 9)

+ MathOperatorReceiver
  -> new(@offset)
  -> shift(x)
    x + @offset

receiver = MathOperatorReceiver.new(7)
<< (math_outer ∘ receiver.shift).call(3)

-> math_probe(x)
  << x
  x

# Each shared operand is evaluated once, and later calls are skipped.
<< (math_probe(0) <= math_probe(3) < math_probe(5))
<< (math_probe(9) < math_probe(2) < math_probe(100))
<< (9 > 5 >= 5 > 0)
<< (1 < 2 < 3 < 4)
<< (1 < 2 > 5 < math_probe(100))
<< ((1 < 2) == true)

a = Set.of([1, 2, 3])
b = Set.of([3, 4, 5])
c = Set.of([3, 5])
math_check(Set.of([1, 1, 2]).size, 2)
math_check(Set.empty ⊆ a, true)
math_check((a ∪ b).to_a.sort, [1, 2, 3, 4, 5])
math_check((a ∩ b).to_a, [3])
math_check(a.to_a.sort, [1, 2, 3])
math_check(3 ∈ [1, 2, 3], true)
math_check(4 ∉ [1, 2, 3], true)
<< (2 ∈ a)
<< (4 ∉ a)
<< (a ∪ b).to_a.sort
<< (a ∩ b).to_a.sort
<< (Set.of([1, 2]) ⊆ a)
<< (a ⊆ a)
<< (b ⊆ a)
<< (a ∪ b ∩ c).to_a.sort
<< (2 ∈ a ⊆ (a ∪ b))

-> math_set
  << "set"
  Set.of([1, 2])

<< (math_probe(1) ∈ math_set())

<< (2 ↑↑ 4)
<< (3 ↑↑ 3)
<< (5 ↑↑ 0)
<< (0 ↑↑ 0)
<< (0 ↑↑ 3)
<< (0 ↑↑ 4)
<< (1 ↑↑ 1000000)
<< ((2 ↑↑ 5) == (2 ** 65536))
<< (2 ↑↑ 2 ↑↑ 2)
<< (1 + 2 ↑↑ 3 * 2)
math_check(2 ↑↑ 4, 65536)
math_check(3 ↑↑ 3, 7625597484987)
math_check(5 ↑↑ 0, 1)
math_check(0 ↑↑ 3, 0)
math_check(0 ↑↑ 4, 1)
math_check(2 ↑↑ 5, 2 ** 65536)
math_check(2 ↑↑ 2 ↑↑ 2, 65536)

raised = false
begin
  2 ↑↑ -1
rescue e
  raised = true
  << e
math_check(raised, true)
raised = false
begin
  -2 ↑↑ 3
rescue e
  raised = true
  << e
math_check(raised, true)
raised = false
begin
  2 ↑↑ ~1.5
rescue e
  raised = true
  << e
math_check(raised, true)

# Composition order, repeat calls, and capture after the factory returns.
math_check((g ∘ f).call(4), 42)
math_check((f ∘ g ∘ f).call(4), 52)
math_check((f ∘ (g ∘ f)).call(4), 52)
math_check(((f ∘ g) ∘ f).call(4), 52)
math_check(escaped.call(0), 10)
math_check(escaped.call(5), 25)
math_check((identity ∘ receiver.shift).call(3), 10)

# A shared operand is evaluated once even in long/mixed set chains.
chain_trace = MathTrace.new
math_check((chain_trace.mark(0) <= chain_trace.mark(1) < chain_trace.mark(2) <= chain_trace.mark(2) < chain_trace.mark(3)), true)
math_check(chain_trace.values, [0, 1, 2, 2, 3])
math_check((chain_trace.mark(8) < chain_trace.mark(3) <= chain_trace.mark(99)), false)
math_check(chain_trace.values, [0, 1, 2, 2, 3, 8, 3])
math_check((0 < 2 ∈ a ⊆ (a ∪ b)), true)
math_check((4 ∉ a ⊆ (a ∪ b)), true)
math_check((Set.empty ⊆ c ⊆ b), true)
math_check((Set.of([9]) ⊆ a ⊆ chain_trace.mark(b)), false)
math_check(chain_trace.values, [0, 1, 2, 2, 3, 8, 3])
math_check((1 < 2) == true, true)
math_check(2 < 1 < 3, false)
math_check(3 >= 3 >= 2 > 1, true)

# Set notation matches named operations without mutating either operand.
math_check(a ∪ b, a.union(b))
math_check(a ∩ b, a.intersect(b))
math_check((a ∪ b ∩ c), a.union(b.intersect(c)))
math_check(((a ∪ b) ∩ c), Set.of([3, 5]))
math_check(a | b, a ∪ b)
math_check(a & b, a ∩ b)
math_check(a - b, Set.of([1, 2]))
math_check(a ^ b, Set.of([1, 2, 4, 5]))
math_check(a, Set.of([1, 2, 3]))
math_check(b, Set.of([3, 4, 5]))
math_check(2 ∈ [], false)
math_check(2 ∉ [], true)

# Power precedence and the empty tower convention also cover BigInt bases.
math_check(2 ** 2 ↑↑ 2, 16)
math_check(2 ↑↑ 2 ** 2, 65536)
math_check((2 ↑↑ 2) ** 2, 16)
math_check(4 ↑↑ 3, 4 ** 256)
math_check((2 ** 80) ↑↑ 0, 1)
math_check((2 ** 80) ↑↑ 1, 2 ** 80)
math_check(0 ↑↑ 1000000, 1)
math_check(0 ↑↑ 1000001, 0)
math_check(1 ↑↑ (2 ** 80), 1)

# Integer bitwise paths still work alongside Set operator dispatch.
math_check(6 & 3, 2)
math_check(6 | 3, 7)
math_check(6 ^ 3, 5)
math_check((2 ** 80) | 3, (2 ** 80) + 3)
math_check(((2 ** 80) + 3) & 7, 3)
math_check(((2 ** 80) + 3) ^ (2 ** 80), 3)

# A composed receiver expression stays lazy too, as in an ordinary closure.
receiver_trace = MathTrace.new
delayed = receiver_trace.receiver.mark ∘ identity
math_check(receiver_trace.values, [])
math_check(delayed.call(8), 8)
math_check(receiver_trace.values, [-1, 8])
math_check((f∘g).call(4), 22)
math_check(2↑↑3, 16)
math_check(2∈a, true)
math_check(4∉a, true)
math_check(a∪b, a.union(b))
math_check(a∩b, a.intersect(b))
math_check(a⊆a, true)
text_set = Set.of(["red", "blue", "red"])
math_check(text_set.size, 2)
math_check("red" ∈ text_set, true)
math_check("green" ∉ text_set, true)
math_check(text_set ∩ Set.of(["red"]), Set.of(["red"]))
