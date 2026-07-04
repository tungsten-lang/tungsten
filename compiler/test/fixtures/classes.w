+ Dog
  -> new(@name)

  -> bark
    "woof"

  -> greet
    "I'm [@name]"

d = Dog.new("Rex")
<< d.bark()
<< d.greet()

+ Animal
  -> speak
    "..."

+ Cat < Animal
  -> speak
    "meow"

c = Cat.new()
<< c.speak()
