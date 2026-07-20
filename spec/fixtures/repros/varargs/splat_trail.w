# splat + trailing fixed param: `-> m(*mid, z)` — z right-aligns.
+ Box
  -> trail(*mid, z)
    << "trail n=[mid.size] mid=[mid] z=[z]"

b = Box.new
b.trail(9)
b.trail(1, 9)
b.trail(1, 2, 3, 9)
