# Iterative Towers of Hanoi using a stack

class Stack
  -> new
    @data = []

  -> push(val)
    @data.push(val)

  -> pop
    @data.pop

  -> peek
    @data.last

  -> empty?
    @data.empty?

  -> size
    @data.length

  -> to_s
    @data.to_s

a = Stack()
b = Stack()
c = Stack()

n = 4
n.downto(1) { |i| a.push(i) }

puts "Initial: A=[a] B=[b] C=[c]"

-> move(from, to, from_name, to_name)
  disk = from.pop
  to.push(disk)
  puts "Move [disk] from [from_name] to [to_name]"

total = (1 << n) - 1
1.upto(total) { |step|
  case
    when step % 3 == 1
      if a.empty? or (!c.empty? and c.peek < a.peek)
        move(c, a, "C", "A")
      else
        move(a, c, "A", "C")
    when step % 3 == 2
      if a.empty? or (!b.empty? and b.peek < a.peek)
        move(b, a, "B", "A")
      else
        move(a, b, "A", "B")
    when step % 3 == 0
      if b.empty? or (!c.empty? and c.peek < b.peek)
        move(c, b, "C", "B")
      else
        move(b, c, "B", "C")
}

puts "Final: A=[a] B=[b] C=[c]"

## expect skip currently unsupported in this runtime
