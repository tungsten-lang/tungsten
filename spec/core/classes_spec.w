# Classes, fields, methods, and inheritance.
#
# Run: `bin/tungsten -o /tmp/cls spec/core/classes_spec.w && /tmp/cls`

-> check(name, got, want)
  if got == want
    << "PASS " + name
  else
    << "FAIL " + name + " got " + got.to_s() + " want " + want.to_s()
    exit 1

# -- Simple class with field + methods --
+ Counter
  -> new
    @n = 0

  -> value
    @n

  -> inc
    @n = @n + 1
    @n

  -> add(k)
    @n = @n + k
    @n

c = Counter.new()
check("counter.init", c.value(), 0)
check("counter.inc", c.inc(), 1)
check("counter.inc2", c.inc(), 2)
check("counter.add", c.add(10), 12)
check("counter.value", c.value(), 12)

# -- Constructor binding args to fields --
+ Greeter
  -> new(@name)

  -> greet
    "hello " + @name

  -> rename(n)
    @name = n
    @name

g = Greeter.new("Rex")
check("greeter.greet", g.greet(), "hello Rex")
check("greeter.rename", g.rename("Max"), "Max")
check("greeter.greet_after", g.greet(), "hello Max")

# -- Inheritance: override + call inherited shape --
+ Animal
  -> new(@name)

  -> speak
    "..."

  -> label
    @name + " says " + speak()

+ Dog < Animal
  -> speak
    "woof"

+ Cat < Animal
  -> speak
    "meow"

  -> purr
    @name + " purrs"

dog = Dog.new("Rex")
cat = Cat.new("Whiskers")

check("inherit.dog.speak", dog.speak(), "woof")
check("inherit.cat.speak", cat.speak(), "meow")
check("inherit.dog.label", dog.label(), "Rex says woof")
check("inherit.cat.label", cat.label(), "Whiskers says meow")
check("inherit.cat.purr", cat.purr(), "Whiskers purrs")

anon = Animal.new("Anon")
check("inherit.base.default", anon.speak(), "...")

# -- Subclass constructor setting superclass fields --
+ LoudDog < Animal
  -> new(@name)
    @extra = "!"

  -> speak
    "WOOF" + @extra

ld = LoudDog.new("Bo")
check("subclass.ctor.speak", ld.speak(), "WOOF!")
check("subclass.ctor.label", ld.label(), "Bo says WOOF!")

<< "classes_spec: all checks passed"
