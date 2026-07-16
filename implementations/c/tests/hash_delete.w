# 1, 11, 16, and 23 share their low three splitmix64 bits. In the C VM's
# initial eight-slot table they therefore exercise lookup beyond a tombstone
# and reuse of that tombstone, rather than only the no-collision delete path.
h = {}
h[1] = 11
h[11] = 22
h[16] = 33

puts h.delete(1)
puts h[11]
puts h[16]
puts h[1] == nil
puts h.delete(99) == nil

h[23] = 44
puts h[23]
puts h[11]
puts h[16]
puts h.size()
