## parity xfail ljust/rjust/center exist interpreted but are "undefined method 'ljust' for String" compiled
# Strings: padding methods.
#
# Cross-engine parity spec (scripts/parity.sh).

<< "ljust [("hi").ljust(5)]|"
<< "rjust [("hi").rjust(5)]"
<< "center [("hi").center(6)]|"
