# Regression: units that were missing from the reference registry (MWh, mbar,
# Torr, sqm) now resolve to real dimensions and convert. Joke/marker units (PB)
# stay no-conversion sentinels rather than silently acting as scalars.
<< 2 MWh + 1 kWh
<< 2 mbar + 1 bar
<< 760 Torr + 0 atm
<< 1 sqm + 1 sqft
<< 5 sqm
