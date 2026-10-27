# 100 doors

doors = []
(0...100).each -> (_)
  doors.push(false)

(1..100).each -> (pass)
  door = pass - 1
  while door < 100
    doors[door] = !doors[door]
    door += pass

(0...100).each -> (i)
  if doors[i]
    << "Door [i + 1] is open"

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
