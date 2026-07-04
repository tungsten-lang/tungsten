# ByteArray.slice(start, len) — returns a new ByteArray containing the
# requested byte range. Phase 6i.1 lifted ByteArray to WArray with
# ebits=8; .slice wasn't on the array IC dispatch table, so calling it
# on bytes failed with "undefined method 'slice' for Array".
# (Regular Array uses .copy; .slice errors cleanly there.)

raw = base64_decode("SGVsbG8sIHdvcmxkIQ==")  # "Hello, world!" — 13 bytes

if raw.size != 13
  << "FAIL: setup — expected 13-byte decode"
  exit 1

# Normal slice
head = raw.slice(0, 5)
if head.size != 5
  << "FAIL: head size"
  exit 1
expected_head = base64_decode("SGVsbG8=")
if head != expected_head
  << "FAIL: head content"
  exit 1

# Middle slice
mid = raw.slice(7, 5)
if mid.size != 5
  << "FAIL: mid size"
  exit 1
expected_mid = base64_decode("d29ybGQ=")  # "world"
if mid != expected_mid
  << "FAIL: mid content"
  exit 1

# Slice past end clamps
past = raw.slice(10, 100)
if past.size != 3
  << "FAIL: past-end clamp (got " + past.size.to_s() + ", expected 3)"
  exit 1

# Zero-length slice
zero = raw.slice(5, 0)
if zero.size != 0
  << "FAIL: zero-length size"
  exit 1

# Slice of an empty ByteArray
empty = base64_decode("")
empty_slice = empty.slice(0, 5)
if empty_slice.size != 0
  << "FAIL: empty slice size"
  exit 1

<< "ok"
