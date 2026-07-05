t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)

num_words = 1000
num_iter = 5_000_000

words = Array.new(num_words) { |i| "word#{i}" }

freq = Hash.new(0)
seed = 42
num_iter.times do
  seed = (seed * 1103515245 + 12345) & 0x7FFFFFFF
  word = words[seed % num_words]
  freq[word] += 1
end

max_freq = freq.values.max

t1 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
puts max_freq
puts "elapsed: #{'%.3f' % (t1 - t0)}s"
