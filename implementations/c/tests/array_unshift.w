# The compiler prepends closure capture scratch to an entry block.
# Cover empty arrays, backing growth, return-self and reference elements.
values = []
same = values.unshift(3)
same.push(4)
<< values.size()
<< values[0]
<< values[1]
values.unshift(2)
<< values.shift()

i = 0
while i < 256
  values.unshift(i)
  i += 1
<< values.size()
<< values[0]
<< values[255]
<< values[256]

inner = [7]
values.unshift(inner)
inner[0] = 9
<< values[0][0]
values.unshift(nil)
<< values[0] == nil
<< values[1][0]
