t0 = Time.monotonic
n = 400000
s = String.build do |sb|
  n.times { sb << "abcdefghijklmnopqrstuvwxyz" }
end
t1 = Time.monotonic
puts s.bytesize
puts "elapsed: #{(t1 - t0).total_seconds.round(6)}s"
