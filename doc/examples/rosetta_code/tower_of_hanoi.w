# Tower of Hanoi

-> hanoi(n, from, to, via)
  if n > 0
    hanoi(n - 1, from, via, to)
    << "Move disk [n] from [from] to [to]"
    hanoi(n - 1, via, to, from)

hanoi(4, "A", "C", "B")

## expect stdout
## Move disk 1 from A to B
## Move disk 2 from A to C
## Move disk 1 from B to C
## Move disk 3 from A to B
## Move disk 1 from C to A
## Move disk 2 from C to B
## Move disk 1 from A to B
## Move disk 4 from A to C
## Move disk 1 from B to C
## Move disk 2 from B to A
## Move disk 1 from C to A
## Move disk 3 from B to C
## Move disk 1 from A to B
## Move disk 2 from A to C
## Move disk 1 from B to C
