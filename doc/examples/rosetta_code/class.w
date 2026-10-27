# Classes and methods

+ Counter
  -> new(@count) ro

  -> increment
    @count += 1

  -> add(n)
    @count += n

c = Counter.new(0)
c.increment
c.increment
c.add(5)
<< c.count

## expect stdout
## 7
