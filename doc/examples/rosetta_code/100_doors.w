# 100 Doors

doors = []
0..99 -> doors.push(false)

1..100 ->
  i = pass - 1

  while i < 100
    doors[i] = !doors[i]
    i += pass

1..100 ->
  << "Door [i] is open" if doors[i - 1]

## expect stdout
## Door 1 is open
## Door 4 is open
## Door 9 is open
## Door 16 is open
## Door 25 is open
## Door 36 is open
## Door 49 is open
## Door 64 is open
## Door 81 is open
## Door 100 is open
