# leading fixed param + splat: `-> m(x, *rest)`.
+ Box
  -> lead(x, *rest)
    << "lead x=[x] n=[rest.size] v=[rest]"

b = Box.new
b.lead(1)
b.lead(1, 2)
b.lead(1, 2, 3, 4)
