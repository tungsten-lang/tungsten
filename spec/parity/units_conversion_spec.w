# Units and quantities: conversion via the `|` operator, with digit hints.
#
# Cross-engine parity spec (scripts/parity.sh).

<< "pipe.km [2000 m | km]"
<< "pipe.m [5 ft | m]"
<< "pipe.kmh [5 m/s | km/h]"
<< "pipe.digits [6 ft + 2 in | cm(2)]"
<< "pipe.eV [1 J | eV]"
<< "pipe.interp [5 m/s | km/h(1)]"
<< "pipe.attach [2.5 | km]"
<< "pipe.area [10 ft * 10 ft | m²]"
d = 1500 m
<< "pipe.var [d | km]"
