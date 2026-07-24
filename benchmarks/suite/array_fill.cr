t0 = Time.monotonic
n = 1000000
rounds = 200
a = Array(Int64).new(n, 0_i64)
chk = 0_i64
rounds.times do |r|
  i = 0
  while i < n
    a[i] = i.to_i64 * 2654435761_i64 + r.to_i64
    i += 1
  end
  chk ^= a[(r * 7) % n]
end
t1 = Time.monotonic
puts chk
puts "elapsed: #{(t1 - t0).total_seconds.round(6)}s"
