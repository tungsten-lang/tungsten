items=[1,2,"hi"]
data={foo: 1,"bar":2}
money=$10
-> add(a,b=1)
  a+b
+ Box
  -> new(@value)
  -> value
    @value
if items.size>0
  << "count=[items.size]"
elsif false
  << :no
else
  << nil
case items.size
when 0,1
  << "small"
else
  << "big"
