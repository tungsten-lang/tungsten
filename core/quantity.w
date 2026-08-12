# Quantity — numeric value with unit (tag 0xFFFD)
+ Quantity
  # Ordinary quantities are vectors. Points are explicit, except absolute
  # temperatures, and carry an optional coordinate-frame/origin annotation.
  -> point(origin = :default)
    ccall("w_quantity_point", self, origin)

  -> delta(origin = nil)
    ccall("w_quantity_delta", self, origin)

  -> point?
    ccall("w_quantity_point_p", self)

  -> delta?
    ccall("w_quantity_delta_p", self)

  -> origin
    ccall("w_quantity_origin", self)

  # Bare numeric value (a Decimal), without the unit: (5 km).value -> 5.
  -> value
    ccall("w_quantity_value", self)

  # Registry spelling of the unit: (5 km).unit_name -> "km".
  -> unit_name
    ccall("w_quantity_unit_name", self)

  # Evaluate to an imprecise Float: π-quantities (`2π`) collapse to
  # coeff·π, dimensioned quantities to their bare numeric value.
  -> to_f
    ccall("w_quantity_to_f", self)

  # Opt-in bridges between dimensions. Ordinary `to`/`|` conversion never
  # invokes physical constants implicitly.
  -> equivalent(target_unit, using)
    ccall("w_quantity_equivalent", self, target_unit, using)

  alias_method :equivalent_to/2, :equivalent/2
