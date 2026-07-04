+ Dog
  @@all = []

  -> .register(d)
    @@all.push(d)

  -> .count
    @@all.size()

  ro :name
  -> new(@name)

Dog.register(Dog.new("Rex"))
Dog.register(Dog.new("Buddy"))
<< Dog.count
