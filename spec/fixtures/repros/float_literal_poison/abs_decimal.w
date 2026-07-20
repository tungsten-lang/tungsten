# abs was the sibling omission in the Decimal IC table. Decimal#abs stays an
# exact Decimal (matching Integer#abs's exactness, not Float#abs). This is the
# shape koala Splitter's integer test_pct workaround was avoiding.
<< "abs pos: " + (0.25).abs.to_s
<< "abs neg: " + (-0.25).abs.to_s
<< "abs whole: " + (-5.0).abs.to_s
