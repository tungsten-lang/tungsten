# Slice-of-slice flattening: v2 = v1.slice(...) registers v2 against
# v1's root parent, not against v1. All views are siblings, never
# children of one another. After a parent realloc, every sibling
# view's slots pointer is updated to track the new buffer.

parent = base64_decode("QUJDREVGR0g=")    # 8 bytes: ABCDEFGH
v1 = parent.slice(0, 6)                   # ABCDEF
v2 = v1.slice(2, 3)                       # CDE — flattens to parent.slice(2, 3)

if v2 != base64_decode("Q0RF")
  << "FAIL: slice-of-slice content"
  exit 1

# Realloc the parent. Both v1 and v2 must remain valid because both
# were registered against the same root parent.
parent.push(73)
parent.push(74)
parent.push(75)
parent.push(76)
parent.push(77)
parent.push(78)
parent.push(79)
parent.push(80)

if v1 != base64_decode("QUJDREVG")
  << "FAIL: v1 drifted after realloc"
  exit 1
if v2 != base64_decode("Q0RF")
  << "FAIL: v2 drifted after realloc"
  exit 1

<< "ok"
