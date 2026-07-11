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

  # Opt-in bridges between dimensions. Ordinary `to`/`|` conversion never
  # invokes physical constants implicitly.
  -> equivalent(target_unit, using)
    ccall("w_quantity_equivalent", self, target_unit, using)
