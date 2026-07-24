t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)

base = "the quick brown fox jumps over the lazy dog "
text = base * 2500000

count = 0
pos = 0
needle = "fox"
needle_len = needle.length
while pos <= text.length - needle_len
  idx = text.index(needle, pos)
  if idx.nil?
    break
  end
  count += 1
  pos = idx + needle_len
end

t1 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
puts count
puts "elapsed: #{'%.3f' % (t1 - t0)}s"
