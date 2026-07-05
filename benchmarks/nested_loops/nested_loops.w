## i32 i, j, k
fn nested_loops
  count = 0
  with i in 0...1000, j in 0...1000, k in 0...1000
    count = (count + i * 31 + j * 17 + k) % 1000000007

  count

<< nested_loops
