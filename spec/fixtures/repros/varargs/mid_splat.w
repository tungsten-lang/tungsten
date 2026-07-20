# fixed before AND after the splat: `-> m(x, *mid, z)`.
+ Box
  -> mid(x, *mid, z)
    << "mid x=[x] n=[mid.size] mid=[mid] z=[z]"

b = Box.new
b.mid(1, 9)
b.mid(1, 2, 9)
b.mid(1, 2, 3, 4, 9)
