# 03 — OOP

Classes, methods, inheritance, and traits. Tungsten is object-oriented without
the ceremony of `class` / `def` / `end`.

← [02 — Syntax](02-syntax.md) · [Index](README.md) · Next: [04 — Literals & units](04-literals-and-units.md) →

---

## Classes with `+`

`+ Name` defines a class. Methods use `->`. Constructors commonly bind
instance fields from arguments with `@name`, and a trailing `ro` or `rw`
generates accessors:

```tungsten
+ Dog
  -> new(@name, @breed) rw

  -> speak
    "woof from [@name]"

d = Dog.new("Rex", "lab")
# or, without .new:
d = Dog("Rex", "lab")

<< d.speak()
<< d.breed
d.name = "Max"
```

| Trailing marker | Meaning |
| --------------- | ------- |
| `ro` | Read-only accessors for the `@` fields in that constructor |
| `rw` | Read-write accessors |

Standalone accessor declarations also exist *(compiled)*:

```tungsten
+ Animal
  ro :name
  ro :sound

  -> new(@name, @sound)

  -> speak
    << "[self.name] says [self.sound]"
```

---

## Methods

```tungsten
+ Point
  -> new(@x, @y) ro

  -> distance/1
    dx = x - x'             # x' is the other point's x (prime notation)
    dy = y - y'
    (dx.sq + dy.sq).sqrt

<< Point(3, 4).distance(Point(0, 0))   # => 5
```

Notes:

- `-> distance/1` is the arity form: one argument, available as `@1` or via
  field-relative prime notation in some patterns.
- Named parameters also work: `-> greet(name)`.
- A `-> name` with **no body** is abstract — subclasses or intrinsics supply
  the implementation.
- Instance fields are `@name` inside the class; generated readers may expose
  them as bare `name` depending on `ro`/`rw`.

---

## Inheritance

`< Parent` after the class name:

```tungsten
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
```

A fuller walk-through:

```bash
bin/tungsten -o /tmp/classes doc/examples/03-oop/classes.w && /tmp/classes
# Rex says woof
# Rex fetches the ball!
# Whiskers says meow
# Whiskers purrs...
```

(Quick-run support for some inheritance / accessor shapes is still catching
up — prefer `-o` when an OOP example misbehaves under plain `bin/tungsten`.)

---

## Traits

Traits are reusable method bundles. A class opts in with `is TraitName`:

```tungsten
trait Printable
  -> to_string
    "[self.label]: [self.value]"

  -> print_self
    << self.to_string()

+ Temperature
  is Printable
  rw :value
  ro :scale

  -> new(@value, @scale)

  -> label
    "Temperature"

+ Distance
  is Printable
  rw :value
  ro :unit

  -> new(@value, @unit)

  -> label
    "Distance"

temp = Temperature.new(72, "F")
temp.print_self()             # => Temperature: 72

dist = Distance.new(42, "km")
dist.print_self()             # => Distance: 42
```

```bash
bin/tungsten -o /tmp/traits doc/examples/03-oop/traits.w && /tmp/traits
```

Trait **method dispatch** is a *(compiled)* feature: use the native path for
programs that rely on `is Trait` methods.

Inside a trait, `with OtherTrait` composes another trait in.

---

## Pattern for a small domain type

```tungsten
+ Money
  -> new(@amount) ro          # amount is a Currency literal / Decimal

  -> +/1
    Money(@amount + @1.amount)

  -> to_s
    @amount.to_s

a = Money($10.00)
b = Money($2.50)
<< (a + b).to_s               # depends on operator method wiring
```

Operators are methods on the receiver (`+/1`, `*/1`, …), so domain types can
participate in arithmetic notation.

---

## Layout and fields (advanced peek)

For low-level / systems code, `- data` introduces a typed memory-layout block,
and `ro` / `rw` / `field` / `readonly` declare fields. You do not need this for
application classes — stick to `@` constructor binding until you are writing
runtime-shaped types.

---

## Stdlib registration (if you add a core type)

The standard library is lazy-loaded from an autoload table in
`core/tungsten.w`. A new stdlib class is **invisible** until it has an
`auto :ClassName, "relative/path"` line there. Application code does not need
that; only changes under `core/` do.

---

## Summary

| Construct | Form |
| --------- | ---- |
| Class | `+ Name` / `+ Name < Parent` |
| Method | `-> name` / `-> name/N` / `-> name(@x, @y)` |
| Constructor fields | `@x` in `new`, plus trailing `ro` or `rw` |
| Trait | `trait Name` … `is Name` on the class |
| Construct | `Dog.new(...)` or `Dog(...)` |

Next: **[04 — Literals & units](04-literals-and-units.md)**
