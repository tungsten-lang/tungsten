# Runtime-backed Quantity methods must work when receiver provenance has been
# erased by container access as well as on a literal/static receiver.
-> check(name, condition)
  if condition
    << "PASS " + name
  else
    << "FAIL " + name
    exit 1

q = [5 m][0]
check("metadata.value", q.value == 5)
check("metadata.unit_name", q.unit_name == "m")
check("metadata.to_f", q.to_f == ~5.0)
check("role.default", !q.point? && !q.delta? && q.origin == nil)

point = [q][0].point(:map)
check("role.point", point.point? && !point.delta? && point.origin == :map)

delta = [q][0].delta()
check("role.delta", !delta.point? && delta.delta? && delta.origin == nil)

energy = [1 kg][0].equivalent("J", "mass_energy")
check("equivalent", energy.unit_name == "J")

energy_alias = [1 kg][0].equivalent_to("J", "mass_energy")
check("equivalent_alias", energy_alias.unit_name == "J")
