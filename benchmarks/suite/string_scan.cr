t0 = Time.monotonic

base = "the quick brown fox jumps over the lazy dog "
text = base * 2500000

# byte_index (byte offsets) is O(n) total. String#index takes a CHARACTER
# offset, and converting that to a byte offset in a 110 MB UTF-8 string is
# O(offset) per call — an O(n^2) trap that hangs for hours on this input.
count = 0
pos = 0
needle = "fox"
while (idx = text.byte_index(needle, pos))
  count += 1
  pos = idx + 3
end

t1 = Time.monotonic
elapsed = (t1 - t0).total_seconds
puts count
puts "elapsed: #{"%.3f" % elapsed}s"
