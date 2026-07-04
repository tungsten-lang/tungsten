# Inheritance

+ Animal
  -> new(@name) ro

  -> speak
    << "[name] says [sound]"

  -> sound "..."

+ Dog < Animal
  -> sound "Woof!"

+ Cat < Animal
  -> sound "Meow!"

dog = Dog("Rex")
cat = Cat("Whiskers")
dog.speak
cat.speak

## expect skip compiled-only for now — the Ruby interpreter (which runs this harness) can't execute it; try `bin/tungsten inheritance.w`
## expect stdout
## Rex says Woof!
## Whiskers says Meow!
