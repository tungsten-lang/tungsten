fn leaf()
  41

fn depth4()
  leaf()

fn depth3()
  depth4()

fn depth2()
  depth3()

fn depth1()
  depth2()

fn even_depth(n)
  if n == 0
    return 2
  odd_depth(n - 1)

fn odd_depth(n)
  if n == 0
    return 4
  even_depth(n - 1)

<< depth1() + even_depth(2)
