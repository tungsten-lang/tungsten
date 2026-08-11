# Regression for the historical compiled slot-clobber shape in Physics.si:
# an inline value.class.to_s guard, an early return, and a case containing
# quantity literals/conversions. Exercise Quantity, Decimal, then Quantity so
# packed numeric dispatch and control-flow joins cannot silently corrupt value.

-> check(name, condition)
  if condition
    << "PASS " + name
  else
    << "FAIL " + name
    exit 1

+ QuantityControlFlowParity
  -> .si(value, unit_name)
    if value.class.to_s() != "Quantity"
      return value.to_f()
    case unit_name
      when "m"
        ((value | "m") / 1 m).to_f()
      when "s"
        ((value | "s") / 1 s).to_f()
      when "Pa"
        ((value | "Pa") / 1 Pa).to_f()
      else
        ~-1.0

  -> .literal_for(kind)
    case kind
      when "speed"
        100 m/s
      when "pressure"
        5 Pa
      else
        3 kg

check("quantity.guard_before_decimal", QuantityControlFlowParity.si(2 km, "m") == ~2000.0)
check("quantity.early_decimal_return", QuantityControlFlowParity.si(0.4, "s") == ~0.4)
check("quantity.guard_after_decimal", QuantityControlFlowParity.si(3 km, "m") == ~3000.0)
check("quantity.case_speed", ccall("w_quantity_unit_name", QuantityControlFlowParity.literal_for("speed")) == "m/s")
check("quantity.case_pressure", ccall("w_quantity_unit_name", QuantityControlFlowParity.literal_for("pressure")) == "Pa")
check("quantity.case_else", ccall("w_quantity_unit_name", QuantityControlFlowParity.literal_for("mass")) == "kg")
