# Regression: view stays correct after parent realloc.
#
# Before the view registry, taking a view + pushing into the parent
# past capacity reallocated the parent's slots buffer, leaving the
# view's slots pointer dangling into freed memory. Now the registry
# walks all views of the parent and rewrites their slots to track
# the new buffer at the same byte offset.

# Start small with "ABC" — base64_decode returns a fresh ByteArray.
parent = base64_decode("QUJD")
if parent.size != 3
  << "FAIL: setup — parent size " + parent.size.to_s()
  exit 1

# Snapshot via a zero-copy view.
view = parent.slice(0, 3)
expected = base64_decode("QUJD")
if view != expected
  << "FAIL: view pre-push (got mismatch — registry not registering?)"
  exit 1

# Push past capacity many times to force at least one realloc cycle.
parent.push(68)
parent.push(69)
parent.push(70)
parent.push(71)
parent.push(72)
parent.push(73)
parent.push(74)
parent.push(75)

# Sanity: parent grew.
if parent.size != 11
  << "FAIL: parent did not grow to 11 (got " + parent.size.to_s() + ")"
  exit 1

# The view should STILL be backed by the same 3 bytes (A, B, C).
# Pre-fix this would either segfault or return garbage from a
# freed buffer.
if view != expected
  << "FAIL: view bytes drifted after parent realloc"
  exit 1

<< "ok"
