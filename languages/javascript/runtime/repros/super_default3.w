+ Base
  -> new
  -> put(k, flags = 7)
    << "Base#put " + k + " " + flags.to_s
    1

+ Kid < Base
  -> new
  -> put(k, flags = 7)
    << "Kid#put"
    super(k, flags)

<< Kid.new.put("a", 5)
<< Kid.new.put("b")
