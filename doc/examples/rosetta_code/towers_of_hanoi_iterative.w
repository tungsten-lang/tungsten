# Iterative Towers of Hanoi using a stack

a = []
b = []
c = []

n = 4
(1..n).to_a.reverse.each -> (i) a.push(i)

<< "Initial: A=[a] B=[b] C=[c]"

-> move(from, to, from_name, to_name)
  disk = from.pop
  to.push(disk)
  << "Move [disk] from [from_name] to [to_name]"

total = (1 << n) - 1

(1..total).each -> (step)
  case
  when step % 3 == 1
    if a.empty? or (!c.empty? and c.last < a.last)
      move(c, a, "C", "A")
    else
      move(a, c, "A", "C")
  when step % 3 == 2
    if a.empty? or (!b.empty? and b.last < a.last)
      move(b, a, "B", "A")
    else
      move(a, b, "A", "B")
  when step % 3 == 0
    if b.empty? or (!c.empty? and c.last < b.last)
      move(c, b, "C", "B")
    else
      move(b, c, "B", "C")

<< "Final: A=[a] B=[b] C=[c]"

## expect skip compiled-only for now — the Ruby interpreter (which runs this harness) can't execute it; try `bin/tungsten towers_of_hanoi_iterative.w`
## expect stdout
## Initial: A=[4, 3, 2, 1] B=[] C=[]
## Move 1 from A to C
## Move 2 from A to B
## Move 1 from C to B
## Move 3 from A to C
## Move 1 from B to A
## Move 2 from B to C
## Move 1 from A to C
## Move 4 from A to B
## Move 1 from C to B
## Move 2 from C to A
## Move 1 from B to A
## Move 3 from C to B
## Move 1 from A to C
## Move 2 from A to B
## Move 1 from C to B
## Final: A=[] B=[4, 3, 2, 1] C=[]
