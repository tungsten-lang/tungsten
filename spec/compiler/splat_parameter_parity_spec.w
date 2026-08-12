-> check(name, condition)
  if condition
    << "PASS " + name
  else
    << "FAIL " + name

-> gather(*items)
  items

+ SplatBox
  -> only(*items)
    items

  -> lead(first, *items)
    [first, items]

  -> trail(*items, last)
    [items, last]

  -> middle(first, *items, last)
    [first, items, last]

+ StaticSplatBox
  -> .middle(first, *items, last)
    [first, items, last]

box = SplatBox.new

check("top.empty", gather() == [])
check("top.many", gather(1, 2, 3) == [1, 2, 3])
check("instance.empty", box.only() == [])
check("instance.many", box.only(1, 2, 3) == [1, 2, 3])
check("leading.empty", box.lead(1) == [1, []])
check("leading.many", box.lead(1, 2, 3) == [1, [2, 3]])
check("trailing.empty", box.trail(9) == [[], 9])
check("trailing.many", box.trail(1, 2, 9) == [[1, 2], 9])
check("middle.empty", box.middle(1, 9) == [1, [], 9])
check("middle.many", box.middle(1, 2, 3, 9) == [1, [2, 3], 9])
check("static.empty", StaticSplatBox.middle(1, 9) == [1, [], 9])
check("static.many", StaticSplatBox.middle(1, 2, 3, 9) == [1, [2, 3], 9])
