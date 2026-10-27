# Queue/Definition

+ Queue
  -> new
    @items = []

  -> push(x)
    @items.push(x)

  -> pop
    @items.shift

  -> empty?
    @items.empty?

q = Queue.new
q.push("first")
q.push("second")
q.push("third")

<< q.pop
<< q.pop
<< q.empty?
<< q.pop
<< q.empty?

## expect stdout
## first
## second
## false
## third
## true
