# *args-only: collect all args into a real array; empty -> [] (not nil).
+ Box
  -> cap(*a)
    << "cap n=[a.size] v=[a]"

b = Box.new
b.cap()
b.cap(10)
b.cap(10, 20, 30)
