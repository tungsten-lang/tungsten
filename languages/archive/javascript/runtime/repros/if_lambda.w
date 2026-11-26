-> a1(a)
  h = nil
  if a
    h = 5
  h
-> a2(a)
  h = nil
  if a
    h = ->(x) x + 1
  h
-> a3(a)
  h = 0
  if a
    h = ->(x) x + 1
  h
-> a4(a)
  h = nil
  if a
    h = ->(x) x + 1
  else
    h = ->(x) x + 2
  h
-> a5(a)
  h = ->(x) x
  if a
    h = ->(x) x + 1
  h
<< [a1(true), a2(true) == nil, a3(true) == 0, a4(true) == nil, a5(true).call(1)]
