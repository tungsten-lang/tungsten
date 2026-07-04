+ Dog
  -> new(name)
    @name = name

  -> speak
    << "woof from " + @name

d = Dog.new("Rex")
d.speak()
