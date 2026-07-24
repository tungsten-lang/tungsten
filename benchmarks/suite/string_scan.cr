t0 = Time.instant

base = "the quick brown fox jumps over the lazy dog "
text = base * 2500000

count = 0
pos = 0
needle = "fox"
needle_len = needle.size
while pos <= text.size - needle_len
  idx = text.index(needle, pos)
  if idx.nil?
    break
  end
  count += 1
  pos = idx + needle_len
end

t1 = Time.instant
elapsed = (t1 - t0).total_seconds
puts count
puts "elapsed: #{"%.3f" % elapsed}s"
