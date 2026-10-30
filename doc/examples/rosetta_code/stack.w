# Stack

+ Stack
  -> new
    @items = []

  -> push(x)
    @items.push(x)

  -> pop
    @items.pop

  -> peek
    @items.last

  -> empty?
    @items.empty?

s = Stack.new
<< s.empty?
s.push(10)
s.push(20)
s.push(30)
<< s.peek
<< s.pop
<< s.pop
<< s.empty?
<< s.pop
<< s.empty?

## expect stdout
## true
## 30
## 30
## 20
## false
## 10
## true
