# Postfix `rescue` inside an assignment binds tighter than the assignment
# operator: `x = e rescue f` is `x = (e rescue f)`, so x is bound to f when
# e raises (Ruby's `lhs = arg rescue arg`). Covers plain, compound, ivar,
# index and attribute targets, multi-assignment, method bodies, rescue
# values that are expressions, statement-level `stmt rescue handler`, the
# `x = a rescue b if cond` modifier interplay, typed targets (`x ## i64 = e`),
# `$global` targets and chained assignment.
#
# Cross-engine parity spec (scripts/parity.sh).

-> boom
  raise "kaboom"

-> pair_boom
  raise "no pair"

# raising e binds f; non-raising binds e
a = boom() rescue "fallback"
<< "assign.raises [a]"
b = 7 rescue "unused"
<< "assign.ok [b]"

# the rescue value is an expression
c = boom() rescue 40 + 2
<< "assign.expr [c]"
d = boom() rescue "x" + "y"
<< "assign.expr.str [d]"

# compound assignment
e = 10
e += boom() rescue 5
<< "compound.raises [e]"
f = 10
f += 1 rescue 100
<< "compound.ok [f]"
g = 3
g *= boom() rescue 2
<< "compound.mul [g]"

# ||= keeps the short-circuit
h = nil
h ||= boom() rescue "or-fallback"
<< "or_assign.raises [h]"
k = "set"
k ||= boom() rescue "never"
<< "or_assign.ok [k]"

# ivar, index and attribute targets
+ Box
  rw :attr

  -> new
    @slot = nil
    @attr = nil

  -> fill
    @slot = boom() rescue "ivar-fallback"
    @slot

box = Box.new
<< "ivar.raises [box.fill]"
arr = [1, 2, 3]
arr[1] = boom() rescue 99
<< "index.raises [arr[1]]"
hash = {}
hash["key"] = boom() rescue "hash-fallback"
hk = hash["key"]
<< "index.hash [hk]"
box.attr = boom() rescue "attr-fallback"
<< "attr.raises [box.attr]"

# multiple assignment
m, n = pair_boom() rescue [8, 9]
<< "multi.raises [m] [n]"
p, q = [1, 2] rescue [8, 9]
<< "multi.ok [p] [q]"

# inside a method body
-> guarded
  v = boom() rescue "method-fallback"
  v
<< "method.raises [guarded()]"

# statement-level `stmt rescue handler` still guards the whole statement
log = []
boom() rescue log.push("handled")
<< "statement.rescue [log.size]"
+ Closer
  -> close
    boom() rescue nil
    "closed"
closer = Closer.new
<< "statement.method [closer.close]"

# modifier interplay: `x = a rescue b if cond`
r = "untouched"
r = boom() rescue "if-true" if true
<< "modifier.if.true [r]"
s = "untouched"
s = boom() rescue "if-false" if false
<< "modifier.if.false [s]"
t = "untouched"
t = boom() rescue "unless" unless false
<< "modifier.unless [t]"

# nested: the fallback itself can rescue
u = boom() rescue (boom() rescue "inner")
<< "nested.paren [u]"

# typed targets and `## type` hints: the hint still attaches to the assign
ta ## i64 = boom() rescue 5
<< "typed.target [ta]"
tb = boom() rescue 7 ## i64
<< "typed.trailing [tb]"

# $global, indexed compound and declared (`rw`) setter compound targets
$pra_global = boom() rescue 3
<< "gvar.raises [$pra_global]"
cells = [10]
cells[0] += boom() rescue 9
<< "index.compound [cells[0]]"
slots = {}
slots[:k] ||= boom() rescue 4
<< "index.or_assign [slots[:k]]"
box.attr = 12
box.attr += boom() rescue 1
<< "attr.compound [box.attr]"

# chained assignment: the rescue belongs to the innermost value
v1 = v2 = boom() rescue 30
<< "chained [v1] [v2]"
