# Classes: inheritance and overriding, is_a? up and down the chain, traits
# via `is`, polymorphic dispatch over a mixed array, super in constructors.
#
# Cross-engine parity spec (scripts/parity.sh).

+ Animal
  ro :name
  -> new(@name)
  -> speak
    "..."
  -> intro
    "[@name] says [speak()]"

+ Dog < Animal
  -> speak
    "Woof"

<< "inherit [Dog.new("Rex").intro]"
<< "base [Animal.new("Thing").intro]"
<< "is_a.parent [Dog.new("x").is_a?(Animal)]"
<< "is_a.child [Animal.new("x").is_a?(Dog)]"
<< "type.child [type(Dog.new("x"))]"

trait Printable
  -> describe
    "[label()]: [value()]"

+ Temperature
  is Printable
  -> new(@v)
  -> label
    "Temperature"
  -> value
    @v

<< "trait [Temperature.new(72).describe]"

+ Shape
  -> area
    0
  -> describe
    "[type(self)] area=[area()]"

+ Square < Shape
  -> new(@s)
  -> area
    @s * @s

<< "poly [Square.new(3).describe] [Shape.new.describe]"
shapes = [Square.new(2), Shape.new]
<< "poly.map [shapes.map -> item.area]"

