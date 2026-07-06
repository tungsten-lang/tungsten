# 100 Doors

doors = bool[100]

1..100 -> pass.prev...100 .step(pass) -> doors.flip(door_idx)

0..99 -> << "Door [i + 1] is open" if doors[i]

## expect skip compiled-only for now — the Ruby interpreter (which runs this harness) can't execute it; try `bin/tungsten 100_doors.w`
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
