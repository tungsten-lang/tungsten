# Iteration: each/times/each_with_index with explicit and implicit block
# params, while/until/loop, next and break.
#
# Cross-engine parity spec (scripts/parity.sh).

acc = []
(1..3).each -> (i)
  acc.push(i * 10)
<< "each.explicit [acc]"
sum = 0
[1, 2, 3].each ->(x)
  sum += x
<< "each.arr [sum]"
sum2 = 0
(1..4).each -> sum2 += item
<< "each.item [sum2]"
sum3 = 0
5.times ->(i)
  sum3 += i
<< "times.i [sum3]"
sum4 = 0
5.times -> sum4 += 1
<< "times.noarg [sum4]"
idx = []
["a", "b"].each_with_index ->(x, i)
  idx.push("[i]:[x]")
<< "ewi [idx.join(",")]"
w = 0
i = 0
while i < 5
  w += i
  i += 1
<< "while [w]"
u = 0
until u >= 3
  u += 1
<< "until [u]"
l = 0
loop
  l += 1
  break if l == 4
<< "loop [l]"
j = 0
r = []
while j < 10
  j += 1
  next if j % 2 == 0
  break if j > 7
  r.push(j)
<< "next.break [r]"
