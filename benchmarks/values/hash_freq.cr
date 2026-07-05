t0 = Time.monotonic

num_words = 1000
num_iter = 5_000_000

words = Array.new(num_words) { |i| "word#{i}" }

freq = Hash(String, Int32).new(0)
seed = 42_u32
num_iter.times do
  seed = (seed &* 1103515245_u32 &+ 12345_u32) & 0x7FFFFFFF_u32
  word = words[seed % num_words]
  freq[word] = freq[word] + 1
end

max_freq = freq.values.max

t1 = Time.monotonic
elapsed = (t1 - t0).total_seconds
puts max_freq
puts "elapsed: #{"%.3f" % elapsed}s"
