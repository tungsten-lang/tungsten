# Traits — reusable method bundles

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

  -> to_celsius
    if self.scale == "F"
      Temperature.new((self.value - 32) * 5 / 9, "C")
    else
      self

+ Distance
  is Printable
  rw :value
  ro :unit

  -> new(@value, @unit)

  -> label
    "Distance"

temp = Temperature.new(72, "F")
temp.print_self()

dist = Distance.new(42, "km")
dist.print_self()

## expect stdout
## Temperature: 72
## Distance: 42
