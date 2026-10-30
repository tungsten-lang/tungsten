# Dutch national flag problem

-> dutch_flag_sort(balls)
  lo = 0
  mid = 0
  hi = balls.size - 1
  while mid <= hi
    if balls[mid] == 0
      t = balls[lo]
      balls[lo] = balls[mid]
      balls[mid] = t
      lo += 1
      mid += 1
    elsif balls[mid] == 1
      mid += 1
    else
      t = balls[mid]
      balls[mid] = balls[hi]
      balls[hi] = t
      hi -= 1
  balls

names = ["red", "white", "blue"]
sorted = dutch_flag_sort([2, 0, 1, 2, 1, 0, 0, 2, 1])
labels = []
sorted.each -> (b)
  labels.push(names[b])

<< labels.join(" ")

## expect stdout
## red red red white white white blue blue blue
