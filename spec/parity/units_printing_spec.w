# Units and quantities: printed forms, accessors, scientific literals.
#
# Cross-engine parity spec (scripts/parity.sh).

<< "value [(5 km).value]"
<< "unit_name [(5 km).unit_name]"
<< "to_f [(5 km).to_f]"
<< "type [type(5 km)]"
<< "sci.lit [1.5e3 m]"
<< "sci.planck [6.626_070_15e-34 J·s]"
<< "temp [20 °C]"
<< "deg [90 deg]"
q = 3 m
<< "tos " + q.to_s()
<< "interp [q]"
<< q
