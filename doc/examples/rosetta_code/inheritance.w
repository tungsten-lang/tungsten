# Inheritance/Single

+ Animal
  -> new(@name) ro

  -> speak
    << "[name] says [sound]"

  -> sound
    "..."

+ Dog < Animal
  -> sound
    "Woof!"

+ Cat < Animal
  -> sound
    "Meow!"

dog = Dog.new("Rex")
cat = Cat.new("Whiskers")
dog.speak
cat.speak

## expect stdout
## Rex says Woof!
## Whiskers says Meow!
