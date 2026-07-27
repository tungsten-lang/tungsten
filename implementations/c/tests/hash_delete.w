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

# These keys cover all eight initial home buckets in both engines. Repeated
# insert/delete used to leave no empty slot, so the following miss never
# terminated.
saturated = {}
keys = [0, 1, 2, 6, 10, 17, 61, 64]
keys.each -> (key)
  saturated[key] = key
  saturated.delete(key)

puts saturated.size()
puts saturated[999] == nil
puts saturated.has_key?(999) == false
puts saturated.delete(999) == nil
saturated[999] = 55
puts saturated[999]
puts saturated.size()
