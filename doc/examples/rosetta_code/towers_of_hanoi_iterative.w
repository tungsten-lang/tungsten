# Towers of Hanoi (iterative)

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
  if step % 3 == 1
    if a.empty? || (!c.empty? && c.last < a.last)
      move(c, a, "C", "A")
    else
      move(a, c, "A", "C")
  elsif step % 3 == 2
    if a.empty? || (!b.empty? && b.last < a.last)
      move(b, a, "B", "A")
    else
      move(a, b, "A", "B")
  else
    if b.empty? || (!c.empty? && c.last < b.last)
      move(c, b, "C", "B")
    else
      move(b, c, "B", "C")

<< "Final: A=[a] B=[b] C=[c]"

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
