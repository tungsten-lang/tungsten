# Class/static direct-call path with fixed parameters on both sides of splat.
+ StaticBox
  -> .collect(x, *mid, z)
    << "static x=[x] n=[mid.size] mid=[mid] z=[z]"

StaticBox.collect(1, 9)
StaticBox.collect(1, 2, 9)
StaticBox.collect(1, 2, 3, 4, 9)
