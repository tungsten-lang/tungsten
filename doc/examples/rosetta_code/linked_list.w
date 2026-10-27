# Singly-linked list

+ Node
  -> new(@value, @next) ro

+ LinkedList
  is Enumerable

  -> new
    @head = nil

  -> prepend(val)
    @head = Node.new(val, @head)

  -> each
    current = @head
    while current
      yield current.value
      current = current.next

  -> to_s
    parts = []
    each -> (v) parts.push(v.to_s)
    parts.join(" -> ")

list = LinkedList.new
list.prepend(3)
list.prepend(2)
list.prepend(1)

<< list

## expect stdout
## 1 -> 2 -> 3
