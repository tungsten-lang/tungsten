# Priority queue

+ PriorityQueue
  -> new
    @items = []

  -> push(priority, task)
    @items.push([priority, task])
    # Keep sorted by ascending priority
    i = @items.size - 1
    while i > 0 && @items[i - 1][0] > @items[i][0]
      t = @items[i - 1]
      @items[i - 1] = @items[i]
      @items[i] = t
      i -= 1

  -> pop
    item = @items.shift
    item[1]

  -> empty?
    @items.empty?

pq = PriorityQueue.new
pq.push(3, "Clear drains")
pq.push(4, "Feed cat")
pq.push(5, "Make tea")
pq.push(1, "Solve RC tasks")
pq.push(2, "Tax return")

-> drain_queue(pq)
  while !pq.empty?
    << pq.pop

drain_queue(pq)

## expect stdout
## Solve RC tasks
## Tax return
## Clear drains
## Feed cat
## Make tea
