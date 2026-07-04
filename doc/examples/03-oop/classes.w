# Classes and inheritance

+ Animal
  ro :name
  ro :sound

  -> new(@name, @sound)

  -> speak
    << "[self.name] says [self.sound]"

+ Dog < Animal
  -> new(@name)
    @sound = "woof"

  -> fetch(item)
    << "[self.name] fetches the [item]!"

+ Cat < Animal
  -> new(@name)
    @sound = "meow"

  -> purr
    << "[self.name] purrs..."

rex = Dog.new("Rex")
whiskers = Cat.new("Whiskers")

rex.speak()
rex.fetch("ball")

whiskers.speak()
whiskers.purr()

## expect stdout
## Rex says woof
## Rex fetches the ball!
## Whiskers says meow
## Whiskers purrs...
