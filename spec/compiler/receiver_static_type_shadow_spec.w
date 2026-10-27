# A local with an unknown static type must not borrow a same-named module
# variable's numeric type. Hash lookup deliberately hides the array type.
# The wrong receiver type rewrites array.each into integer range iteration.

-> receiver_shadow_check(name, got, want)
  if got != want
    << "FAIL [name]: got=[got] want=[want]"
    exit(1)
  << "PASS [name]"

receiver_shadow_rows = 0
receiver_global_rows = [71, 73]

-> receiver_shadow_local
  box = { "items": [41, 43] }
  receiver_shadow_rows = box["items"]
  receiver_shadow_rows.each -> (item)
    return item
  -1

-> receiver_shadow_parameter(receiver_shadow_rows)
  receiver_shadow_rows.each -> (item)
    return item
  -1

+ ReceiverShadowProbe
  -> values
    box = { "items": [51, 53] }
    box["items"]

  -> first_value
    receiver_shadow_rows = self.values
    receiver_shadow_rows.each -> (item)
      return item
    -1

-> receiver_actual_global
  receiver_global_rows.each -> (item)
    return item
  -1

receiver_shadow_check("function local shadows module", receiver_shadow_local, 41)
receiver_box = { "items": [61, 63] }
receiver_shadow_check("parameter shadows module", receiver_shadow_parameter(receiver_box["items"]), 61)
receiver_shadow_check("method local shadows module", ReceiverShadowProbe.new.first_value, 51)
receiver_shadow_check("actual module reference", receiver_actual_global, 71)
receiver_shadow_check("module binding unchanged", receiver_shadow_rows, 0)
