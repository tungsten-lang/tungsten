# Builtins: env() of an unset variable is nil on every engine (its printed
# form is covered by nil_display_spec).
#
# Cross-engine parity spec (scripts/parity.sh).

<< "unset.nil [env("TUNGSTEN_PARITY_UNSET_XYZ") == nil]"
<< "unset.type [type(env("TUNGSTEN_PARITY_UNSET_XYZ"))]"
<< "home.set [env("HOME") != nil]"
<< "home.type [type(env("HOME"))]"
