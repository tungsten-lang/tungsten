# Singly-linked list

+ Node
  -> new(@value, @next) ro

+ LinkedList
  is Enumerable

  -> new
    @head = nil

  -> prepend(val)
    @head = Node(val, @head)

  -> each
    current = @head
    while current
      yield current.value
      current = current.next

  -> to_s
    map(:to_s).join(" -> ")

list = LinkedList()
list.prepend(3)
list.prepend(2)
list.prepend(1)

<< list

## expect skip currently unsupported in this runtime
