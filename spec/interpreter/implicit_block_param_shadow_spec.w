# Implicit block parameters must shadow same-named variables in OUTER frames,
# and the per-node inference cache must not freeze one caller's answer.
#
# core/array.w's `-> each/&` is `$size -> &(self[i]) : self` — a paramless
# block whose `i` is an implicit index parameter. Free-variable inference used
# to ask Environment#defined?, which reads straight past the method barrier, so
# an `i` anywhere up the chain (a caller frame, or top level) made `i` look
# already-bound: nothing was bound into the block env, the body's `i` resolved
# to the caller's value, and every iteration saw the same element. `each` over
# [10, 20, 30] returned 3 * rows[caller_i] instead of 60.
#
# Order matters: the answer was cached on the block node, so whichever caller
# ran FIRST decided it for the whole process. The checks below deliberately
# prime one block from a contaminated frame and another from a clean one.

-> check(name, got, want)
  if got != want
    << "FAIL [name]: got=[got] want=[want]"
    exit(1)

+ Thing
  -> .compute(rows)
    total = 0
    rows.each -> (r)
      total = total + r
    total

  # A paramless block must still CAPTURE the enclosing frame's own locals
  # rather than rebinding them as implicit parameters...
  -> .scaled(rows)
    factor = 10
    out = []
    rows.each ->
      out.push(item * factor)
    out

  # ...including when the captured name is read before the element name.
  -> .offset(rows)
    base = 100
    out = []
    rows.each ->
      out.push(base + item)
    out

+ Loop
  # Primed from a frame that already has `k` in scope.
  -> .doubles(n)
    out = []
    n.each ->
      out.push(k * 2)
    out

  # Primed from a clean frame, then re-run once `m` exists.
  -> .triples(n)
    out = []
    n.each ->
      out.push(m * 3)
    out

# core/array.w's shared `each` block node, primed by a caller that owns `i`.
i = 0
check("caller i = 0", Thing.compute([10, 20, 30]), 60)
i = 2
check("caller i = 2", Thing.compute([10, 20, 30]), 60)
check("caller i untouched", i, 2)

check("captures frame locals", Thing.scaled([1, 2, 3]).join(","), "10,20,30")
check("captures before element", Thing.offset([1, 2, 3]).join(","), "101,102,103")

k = 99
check("implicit index primed dirty", Loop.doubles(4).join(","), "0,2,4,6")
check("implicit index primed clean", Loop.triples(3).join(","), "0,3,6")
m = 99
check("clean priming stays correct", Loop.triples(3).join(","), "0,3,6")

<< "PASS interpreter implicit block parameter shadowing"
