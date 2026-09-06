# Unit registry catalog

Generated from `data/unit_registry.json` and `data/unit_metadata.tsv` with
`ruby scripts/gen_units_catalog.rb`. These data files are authoritative;
no language implementation supplies definitions to this catalog.

Factors and offsets are exact rationals: canonical value = value × factor + offset.
Dimension powers use length, mass, time, current, temperature, substance, luminosity, information order.
Semantic tags remain part of dimension identity. Constants and contextual or
reference scales retain their explicit kind; a listed factor does not supply
missing calibration, reference conditions, or physical context.

| Symbol | Kind | SI factor | SI offset | Dimension powers | Semantic tags | Description | Aliases |
|---|---|---|---|---|---|---|---|
| A | unit | 1/1 | 0/1 | 0,0,0,1,0,0,0,0 |  | ampere — SI base unit of electric current | ampere, amperes |
| A/m² | unit | 1/1 | 0/1 | -2,0,0,1,0,0,0,0 |  | amperes per square metre — electric-current density | amperes per square meter, current density |
| Ah | unit | 3600/1 | 0/1 | 0,0,1,1,0,0,0,0 |  | ampere hour equal to 3600 coulombs | amp hours, ampere hour, ampere-hour |
| B | unit | 1/1 | 0/1 | 0,0,0,0,0,0,0,1 |  |  | byte, bytes |
| B/flop | unit | 1/1 | 0/1 | 0,0,0,0,0,0,0,1 | flop:-1 | bytes per floating-point operation — computational intensity reciprocal | bytes per flop |
| B/s | unit | 1/1 | 0/1 | 0,0,-1,0,0,0,0,1 |  |  |  |
| BOE | unit | 6119000000/1 | 0/1 | 2,1,-2,0,0,0,0,0 |  |  | barrel of oil equivalent, boe |
| BTU | unit | 4085925351/3872710 | 0/1 | 2,1,-2,0,0,0,0,0 |  |  |  |
| Ba | unit | 1/10 | 0/1 | -1,1,-2,0,0,0,0,0 |  |  | barye |
| Bps | unit | 1/1 | 0/1 | 0,0,-1,0,0,0,0,1 |  |  |  |
| Bq | unit | 1/1 | 0/1 | 0,0,-1,0,0,0,0,0 | decay:1 | becquerel — one radioactive decay per second | becquerel, becquerels |
| Bq/kg | unit | 1/1 | 0/1 | 0,-1,-1,0,0,0,0,0 | decay:1 |  |  |
| Bq/m³ | unit | 1/1 | 0/1 | -3,0,-1,0,0,0,0,0 | decay:1 |  |  |
| C | unit | 1/1 | 0/1 | 0,0,1,1,0,0,0,0 |  |  | coulomb, coulombs |
| C/m³ | unit | 1/1 | 0/1 | -3,0,1,1,0,0,0,0 |  | coulombs per cubic metre — volume charge density | charge density, coulombs per cubic meter |
| CFU | unit | 1/1 | 0/1 | 0,0,0,0,0,0,0,0 | colony_forming_unit:1 | colony-forming unit | CFUs, colony forming unit, colony-forming unit |
| CFU/mL | unit | 1000000/1 | 0/1 | -3,0,0,0,0,0,0,0 | colony_forming_unit:1 |  |  |
| CWT | unit | 56699/1250 | 0/1 | 0,1,0,0,0,0,0,0 |  |  |  |
| Ci | unit | 37000000000/1 | 0/1 | 0,0,-1,0,0,0,0,0 | decay:1 |  | curie, curies |
| D | unit | 1/299792543559856548873184585153 | 0/1 | 1,0,1,1,0,0,0,0 |  |  | debye, debyes |
| DMIPS | unit | 1000000/1 | 0/1 | 0,0,-1,0,0,0,0,0 | instruction:1 |  |  |
| DU | unit | 67175/150553519 | 0/1 | -2,0,0,0,0,1,0,0 |  | Dobson unit for atmospheric trace-gas column amount | dobson unit, dobson units |
| Da | unit | 1/602214076208112205666689957 | 0/1 | 0,1,0,0,0,0,0,0 |  |  | dalton, daltons |
| EF | reference_scale | 1/1 | 0/1 | 0,0,0,0,0,0,0,0 | ef:1 |  | EF-scale, enhanced fujita |
| EFLOPS | unit | 1000000000000000000/1 | 0/1 | 0,0,-1,0,0,0,0,0 | flop:1 |  |  |
| EOPS | unit | 1000000000000000000/1 | 0/1 | 0,0,-1,0,0,0,0,0 | op:1 |  |  |
| EV | unit | 1/1 | 0/1 | 0,0,0,0,0,0,0,0 | exposure_value:1 |  | ev, stop, stops |
| Eflops | unit | 1000000000000000000/1 | 0/1 | 0,0,-1,0,0,0,0,0 | flop:1 |  |  |
| EiB | unit | 1152921504606846976/1 | 0/1 | 0,0,0,0,0,0,0,1 |  |  |  |
| Eotvos | unit | 1/1000000000 | 0/1 | 0,0,-2,0,0,0,0,0 |  | gravity-gradient unit equal to 10^-9 reciprocal seconds squared | E, Eötvös, eotvos |
| Eq | unit | 1/1 | 0/1 | 0,0,0,0,0,1,0,0 | chemical_equivalent:1 | chemical equivalent amount | equivalent, equivalents |
| Eq/L | unit | 1000/1 | 0/1 | -3,0,0,0,0,1,0,0 | chemical_equivalent:1 |  | normality |
| F | unit | 1/1 | 0/1 | -2,-1,4,2,0,0,0,0 |  |  | farad, farads |
| FLOPS | unit | 1/1 | 0/1 | 0,0,-1,0,0,0,0,0 | flop:1 |  |  |
| GB/s | unit | 1000000000/1 | 0/1 | 0,0,-1,0,0,0,0,1 |  |  |  |
| GFLOPS | unit | 1000000000/1 | 0/1 | 0,0,-1,0,0,0,0,0 | flop:1 |  |  |
| GIPS | unit | 1000000000/1 | 0/1 | 0,0,-1,0,0,0,0,0 | instruction:1 |  |  |
| GMAC/s | unit | 1000000000/1 | 0/1 | 0,0,-1,0,0,0,0,0 | mac:1 |  |  |
| GOPS | unit | 1000000000/1 | 0/1 | 0,0,-1,0,0,0,0,0 | op:1 |  |  |
| GT/s | unit | 1000000000/1 | 0/1 | 0,0,-1,0,0,0,0,0 | transfer:1 |  |  |
| GUPS | unit | 1000000000/1 | 0/1 | 0,0,-1,0,0,0,0,0 | cell_update:1 | one billion cell or memory updates per second | giga-updates per second |
| Ga | unit | 1/10000 | 0/1 | 0,1,-2,-1,0,0,0,0 |  |  | gauss |
| Gal | unit | 1/100 | 0/1 | 1,0,-2,0,0,0,0,0 |  |  |  |
| Gb | unit | 116522652/146426683 | 0/1 | 0,0,0,1,0,0,0,0 |  |  | gilbert, gilberts |
| Gb/s | unit | 125000000/1 | 0/1 | 0,0,-1,0,0,0,0,1 |  |  |  |
| Gflops | unit | 1000000000/1 | 0/1 | 0,0,-1,0,0,0,0,0 | flop:1 |  |  |
| GiB | unit | 1073741824/1 | 0/1 | 0,0,0,0,0,0,0,1 |  |  |  |
| GiB/s | unit | 1073741824/1 | 0/1 | 0,0,-1,0,0,0,0,1 |  |  |  |
| Gtok/s | unit | 1000000000/1 | 0/1 | 0,0,-1,0,0,0,0,0 | token:1 |  |  |
| Gy | unit | 1/1 | 0/1 | 2,0,-2,0,0,0,0,0 | absorbed_dose:1 | gray — absorbed dose of one joule per kilogram | gray, grays |
| Gy/s | unit | 1/1 | 0/1 | 2,0,-3,0,0,0,0,0 | absorbed_dose:1 |  |  |
| H | unit | 1/1 | 0/1 | 2,1,-2,-2,0,0,0,0 |  |  | henries, henry, henrys |
| Hz | unit | 1/1 | 0/1 | 0,0,-1,0,0,0,0,0 | cycle:1 | hertz — one cycle per second | hertz |
| IOPS | unit | 1/1 | 0/1 | 0,0,-1,0,0,0,0,0 | io:1 |  |  |
| ISO_speed | unit | 1/1 | 0/1 | 0,0,0,0,0,0,0,0 | iso_sensitivity:1 |  | ISO, ISO sensitivity, iso |
| IU | contextual_unit | 1/1 | 0/1 | 0,0,0,0,0,0,0,0 | international_unit:1 | international unit whose physical amount depends on the named biological substance | international unit, international units |
| IU/mL | unit | 1000000/1 | 0/1 | -3,0,0,0,0,0,0,0 | international_unit:1 |  |  |
| J | unit | 1/1 | 0/1 | 2,1,-2,0,0,0,0,0 |  | joule — SI derived unit of energy, N·m | joule, joules |
| J/K | unit | 1/1 | 0/1 | 2,1,-2,0,-1,0,0,0 |  | joules per kelvin — heat capacity or entropy | joules per kelvin |
| J/kg | unit | 1/1 | 0/1 | 2,0,-2,0,0,0,0,0 |  | joules per kilogram — specific energy |  |
| J/kg/K | unit | 1/1 | 0/1 | 2,0,-2,0,-1,0,0,0 |  | joules per kilogram-kelvin — specific heat capacity | J/(kg·K), specific heat capacity |
| J/m² | unit | 1/1 | 0/1 | 0,1,-2,0,0,0,0,0 |  |  | radiant exposure |
| J/m³ | unit | 1/1 | 0/1 | -1,1,-2,0,0,0,0,0 |  | joules per cubic metre — energy density | energy density |
| J/op | unit | 1/1 | 0/1 | 2,1,-2,0,0,0,0,0 | op:-1 | joules per operation — computational energy efficiency | joules per operation |
| J/tok | unit | 1/1 | 0/1 | 2,1,-2,0,0,0,0,0 | token:-1 | joules per token — model-inference energy intensity | joules per token |
| Jy | unit | 1/100000000000000000000000000 | 0/1 | 0,1,-2,0,0,0,0,0 | cycle:-1 | jansky equal to 10^-26 watt per square metre per hertz | janskies, jansky, janskys |
| K | unit | 1/1 | 0/1 | 0,0,0,0,1,0,0,0 |  | kelvin — SI base unit of thermodynamic temperature | kelvin |
| KB | unit | 1000/1 | 0/1 | 0,0,0,0,0,0,0,1 |  |  |  |
| KOPS | unit | 1000/1 | 0/1 | 0,0,-1,0,0,0,0,0 | op:1 |  |  |
| KiB | unit | 1024/1 | 0/1 | 0,0,0,0,0,0,0,1 |  |  |  |
| L | unit | 1/1000 | 0/1 | 3,0,0,0,0,0,0,0 |  |  | l, liter, liters, litre, litres |
| L/100km | unit | 1/100000000 | 0/1 | 2,0,0,0,0,0,0,0 |  |  | L per 100 km, l/100km, liters per 100 km |
| L/min | unit | 1/60000 | 0/1 | 3,0,-1,0,0,0,0,0 |  | litres per minute — practical volumetric flow rate | liters per minute, litres per minute |
| LT | unit | 1016047/1000 | 0/1 | 0,1,0,0,0,0,0,0 |  |  | long ton, long tons |
| L_sun_nominal | nominal_unit | 382800000000000000000000000/1 | 0/1 | 2,1,-3,0,0,0,0,0 |  | IAU nominal solar luminosity equal to exactly 3.828e26 watts | L☉_N, nominal solar luminosity |
| La | unit | 2898221063/910503 | 0/1 | -2,0,0,0,0,0,1,0 | luminance:1 |  | lambert, lamberts |
| M | unit | 1000/1 | 0/1 | -3,0,0,0,0,1,0,0 |  | molar concentration equal to one mole per litre | molar concentration, molarity |
| MAC/s | unit | 1/1 | 0/1 | 0,0,-1,0,0,0,0,0 | mac:1 |  |  |
| MB/s | unit | 1000000/1 | 0/1 | 0,0,-1,0,0,0,0,1 |  |  |  |
| MFLOPS | unit | 1000000/1 | 0/1 | 0,0,-1,0,0,0,0,0 | flop:1 |  |  |
| MIPS | unit | 1000000/1 | 0/1 | 0,0,-1,0,0,0,0,0 | instruction:1 |  |  |
| MMAC/s | unit | 1000000/1 | 0/1 | 0,0,-1,0,0,0,0,0 | mac:1 |  |  |
| MOPS | unit | 1000000/1 | 0/1 | 0,0,-1,0,0,0,0,0 | op:1 |  |  |
| MT/s | unit | 1000000/1 | 0/1 | 0,0,-1,0,0,0,0,0 | transfer:1 |  |  |
| MWh | unit | 3600000000/1 | 0/1 | 2,1,-2,0,0,0,0,0 |  |  |  |
| M_bol | reference_scale | 1/1 | 0/1 | 0,0,0,0,0,0,0,0 | magnitude_bolometric:1 |  | Mbol, bolometric magnitude |
| Mag | reference_scale | 1/1 | 0/1 | 0,0,0,0,0,0,0,0 | magnitude_absolute:1 |  | absolute magnitude |
| Mb/s | unit | 125000/1 | 0/1 | 0,0,-1,0,0,0,0,1 |  |  |  |
| Mflops | unit | 1000000/1 | 0/1 | 0,0,-1,0,0,0,0,0 | flop:1 |  |  |
| MiB | unit | 1048576/1 | 0/1 | 0,0,0,0,0,0,0,1 |  |  |  |
| MiB/s | unit | 1048576/1 | 0/1 | 0,0,-1,0,0,0,0,1 |  |  |  |
| Mtok/s | unit | 1000000/1 | 0/1 | 0,0,-1,0,0,0,0,0 | token:1 |  |  |
| Mx | unit | 1/100000000 | 0/1 | 2,1,-2,-1,0,0,0,0 |  |  | maxwell, maxwells |
| N | unit | 1/1 | 0/1 | 1,1,-2,0,0,0,0,0 |  | newton — SI derived unit of force, kg·m/s² | newton, newtons |
| N/m | unit | 1/1 | 0/1 | 0,1,-2,0,0,0,0,0 |  | newtons per metre — surface tension | newtons per meter, surface tension |
| N·m | unit | 1/1 | 0/1 | 2,1,-2,0,0,0,0,0 | torque:1 | newton metre — torque | torque |
| N·s | unit | 1/1 | 0/1 | 1,1,-1,0,0,0,0,0 | impulse:1 | newton second — impulse | impulse |
| Oe | unit | 707761077/8893988 | 0/1 | -1,0,0,1,0,0,0,0 |  |  | oersted, oersteds |
| Osm/L | unit | 1000/1 | 0/1 | -3,0,0,0,0,1,0,0 | osmotic_entity:1 |  | osmolar |
| P | unit | 1/10 | 0/1 | -1,1,-1,0,0,0,0,0 |  |  | poise |
| PB | unit | 1000000000000000/1 | 0/1 | 0,0,0,0,0,0,0,1 |  | petabyte — 10¹⁵ bytes | petabyte, petabytes |
| PFLOPS | unit | 1000000000000000/1 | 0/1 | 0,0,-1,0,0,0,0,0 | flop:1 |  |  |
| PFU | unit | 1/1 | 0/1 | 0,0,0,0,0,0,0,0 | plaque_forming_unit:1 | plaque-forming unit | PFUs, plaque forming unit, plaque-forming unit |
| PFU/mL | unit | 1000000/1 | 0/1 | -3,0,0,0,0,0,0,0 | plaque_forming_unit:1 |  |  |
| POPS | unit | 1000000000000000/1 | 0/1 | 0,0,-1,0,0,0,0,0 | op:1 |  |  |
| PPS | unit | 1/1 | 0/1 | 0,0,-1,0,0,0,0,0 | packet:1 |  |  |
| PS | unit | 588399/800 | 0/1 | 2,1,-3,0,0,0,0,0 |  |  |  |
| PVU | unit | 1/1000000 | 0/1 | 2,-1,-1,0,1,0,0,0 |  | potential-vorticity unit equal to 10^-6 kelvin square metres per kilogram second | potential vorticity unit, potential vorticity units |
| Pa | unit | 1/1 | 0/1 | -1,1,-2,0,0,0,0,0 |  | pascal — SI derived unit of pressure, N/m² | pascal, pascals |
| Pflops | unit | 1000000000000000/1 | 0/1 | 0,0,-1,0,0,0,0,0 | flop:1 |  |  |
| PiB | unit | 1125899906842624/1 | 0/1 | 0,0,0,0,0,0,0,1 |  |  |  |
| QALY | unit | 31556952/1 | 0/1 | 0,0,1,0,0,0,0,0 | quality_adjusted_life:1 | quality-adjusted life year | QALYs, quality adjusted life year, quality-adjusted life year |
| QPS | unit | 1/1 | 0/1 | 0,0,-1,0,0,0,0,0 | query:1 |  |  |
| RBE | reference_scale | 1/1 | 0/1 | 0,0,0,0,0,0,0,0 | rbe:1 |  | rbe, relative biological effectiveness |
| RPS | unit | 1/1 | 0/1 | 0,0,-1,0,0,0,0,0 | request:1 |  |  |
| RU | unit | 889/20000 | 0/1 | 1,0,0,0,0,0,0,0 |  |  | rack unit, rack units |
| R_exposure | unit | 129/500000 | 0/1 | 0,-1,1,1,0,0,0,0 | ionizing_radiation_exposure:1 | roentgen exposure equal to 2.58e-4 coulomb per kilogram | roentgen, roentgens |
| R_sun_nominal | nominal_unit | 695700000/1 | 0/1 | 1,0,0,0,0,0,0,0 |  | IAU nominal solar radius equal to exactly 6.957e8 metres | R☉_N, nominal solar radius |
| S | unit | 1/1 | 0/1 | -2,-1,3,2,0,0,0,0 |  |  | mho, siemens, ℧ |
| S/m | unit | 1/1 | 0/1 | -3,-1,3,2,0,0,0,0 |  | siemens per metre — electrical conductivity | conductivity, siemens per meter |
| St | unit | 1/10000 | 0/1 | 2,0,-1,0,0,0,0,0 |  |  | stokes |
| Sv | unit | 1/1 | 0/1 | 2,0,-2,0,0,0,0,0 | equivalent_dose:1 | sievert — equivalent or effective radiation dose of one joule per kilogram | sievert, sieverts |
| Sv/h | unit | 1/3600 | 0/1 | 2,0,-3,0,0,0,0,0 | equivalent_dose:1 |  |  |
| Svedberg | unit | 1/10000000000000 | 0/1 | 0,0,1,0,0,0,0,0 |  | sedimentation coefficient unit equal to 10^-13 seconds | svedberg, svedbergs |
| T | unit | 1/1 | 0/1 | 0,1,-2,-1,0,0,0,0 |  |  | tesla, teslas |
| T/s | unit | 1/1 | 0/1 | 0,0,-1,0,0,0,0,0 | transfer:1 |  |  |
| TCE | unit | 29310000000/1 | 0/1 | 2,1,-2,0,0,0,0,0 |  |  | tce, tonne of coal equivalent |
| TECU | unit | 10000000000000000/1 | 0/1 | -2,0,0,0,0,0,0,0 | electron_column_density:1 | total-electron-content unit equal to 10^16 electrons per square metre | total electron content unit |
| TEPS | unit | 1000000000000/1 | 0/1 | 0,0,-1,0,0,0,0,0 | graph_edge:1 | traversed edges per second | traversed edges per second |
| TFLOPS | unit | 1000000000000/1 | 0/1 | 0,0,-1,0,0,0,0,0 | flop:1 |  |  |
| TMAC/s | unit | 1000000000000/1 | 0/1 | 0,0,-1,0,0,0,0,0 | mac:1 |  |  |
| TOPS | unit | 1000000000000/1 | 0/1 | 0,0,-1,0,0,0,0,0 | op:1 |  |  |
| TPS | unit | 1/1 | 0/1 | 0,0,-1,0,0,0,0,0 | transaction:1 |  |  |
| TT/s | unit | 1000000000000/1 | 0/1 | 0,0,-1,0,0,0,0,0 | transfer:1 |  |  |
| Tflops | unit | 1000000000000/1 | 0/1 | 0,0,-1,0,0,0,0,0 | flop:1 |  |  |
| TiB | unit | 1099511627776/1 | 0/1 | 0,0,0,0,0,0,0,1 |  |  |  |
| Torr | unit | 20265/152 | 0/1 | -1,1,-2,0,0,0,0,0 |  |  |  |
| U/L | unit | 1/60000 | 0/1 | -3,0,-1,0,0,1,0,0 |  |  |  |
| U_enzyme | unit | 1/60000000 | 0/1 | 0,0,-1,0,0,1,0,0 |  | enzyme unit equal to one micromole per minute | enzyme unit, enzyme units |
| V | unit | 1/1 | 0/1 | 2,1,-3,-1,0,0,0,0 |  | volt — SI derived unit of electric potential | volt, volts |
| V/m | unit | 1/1 | 0/1 | 1,1,-3,-1,0,0,0,0 |  | volts per metre — electric-field strength | electric field, volts per meter |
| VA | unit | 1/1 | 0/1 | 2,1,-3,0,0,0,0,0 | apparent_power:1 | volt ampere, the unit of apparent power | volt ampere, volt-ampere |
| W | unit | 1/1 | 0/1 | 2,1,-3,0,0,0,0,0 |  | watt — SI derived unit of power, J/s | watt, watts |
| W/m/K | unit | 1/1 | 0/1 | 1,1,-3,0,-1,0,0,0 |  | watts per metre-kelvin — thermal conductivity | W/(m·K), thermal conductivity |
| W/m² | unit | 1/1 | 0/1 | 0,1,-3,0,0,0,0,0 |  | watts per square metre — heat or irradiance flux | heat flux, watts per square meter |
| W/m²/Hz | unit | 1/1 | 0/1 | 0,1,-2,0,0,0,0,0 | cycle:-1 |  | spectral flux density |
| W/m³ | unit | 1/1 | 0/1 | -1,1,-3,0,0,0,0,0 |  |  |  |
| W/sr | unit | 1/1 | 0/1 | 2,1,-3,0,0,0,0,0 | solid_angle:-1 |  | radiant intensity |
| W/sr/m² | unit | 1/1 | 0/1 | 0,1,-3,0,0,0,0,0 | solid_angle:-1 |  | radiance |
| Wb | unit | 1/1 | 0/1 | 2,1,-2,-1,0,0,0,0 |  |  | weber, webers |
| YFLOPS | unit | 999999999999999983222784/1 | 0/1 | 0,0,-1,0,0,0,0,0 | flop:1 |  |  |
| Yflops | unit | 999999999999999983222784/1 | 0/1 | 0,0,-1,0,0,0,0,0 | flop:1 |  |  |
| ZFLOPS | unit | 1000000000000000000000/1 | 0/1 | 0,0,-1,0,0,0,0,0 | flop:1 |  |  |
| Zflops | unit | 1000000000000000000000/1 | 0/1 | 0,0,-1,0,0,0,0,0 | flop:1 |  |  |
| abA | unit | 10/1 | 0/1 | 0,0,0,1,0,0,0,0 |  | abampere equal to 10 amperes | abampere, biot |
| abC | unit | 10/1 | 0/1 | 0,0,1,1,0,0,0,0 |  |  | abcoulomb |
| abF | unit | 1000000000/1 | 0/1 | -2,-1,4,2,0,0,0,0 |  |  | abfarad |
| abH | unit | 1/1000000000 | 0/1 | 2,1,-2,-2,0,0,0,0 |  |  | abhenry |
| abV | unit | 1/100000000 | 0/1 | 2,1,-3,-1,0,0,0,0 |  |  | abvolt |
| abΩ | unit | 1/1000000000 | 0/1 | 2,1,-3,-2,0,0,0,0 |  |  | abohm |
| ab⁻¹ | unit | 9999999999999999931398190359470212947659194368/1 | 0/1 | -2,0,0,0,0,0,0,0 |  |  | ab-1, ab^-1, abinv, inv_ab, inverse attobarn |
| ac | unit | 316160658/78125 | 0/1 | 2,0,0,0,0,0,0,0 |  |  | acre, acres |
| altuve | unit | 33/20 | 0/1 | 1,0,0,0,0,0,0,0 |  |  | altuves |
| amphora | unit | 82/3125 | 0/1 | 3,0,0,0,0,0,0,0 |  |  | amphorae, amphoras |
| apgar | reference_scale | 1/1 | 0/1 | 0,0,0,0,0,0,0,0 | apgar:1 |  | Apgar, apgar score |
| arcmin | unit | 1650943/5675523967 | 0/1 | 0,0,0,0,0,0,0,0 | angle:1 |  |  |
| arcsec | unit | 286277/59048869938 | 0/1 | 0,0,0,0,0,0,0,0 | angle:1 |  |  |
| aroura | unit | 11025/4 | 0/1 | 2,0,0,0,0,0,0,0 |  |  | arourae, arouras |
| arpent | unit | 341889/100 | 0/1 | 2,0,0,0,0,0,0,0 |  |  | arpents |
| arshin | unit | 889/1250 | 0/1 | 1,0,0,0,0,0,0,0 |  |  | arshins |
| asb | unit | 78256779/245850922 | 0/1 | -2,0,0,0,0,0,1,0 | luminance:1 |  | apostilb, apostilbs |
| at | unit | 196133/2 | 0/1 | -1,1,-2,0,0,0,0,0 |  |  |  |
| atm | unit | 101325/1 | 0/1 | -1,1,-2,0,0,0,0,0 |  |  | atmosphere, atmospheres |
| attobarn | unit | 1/9999999999999998797663428295064584535003541106 | 0/1 | 2,0,0,0,0,0,0,0 |  |  | abarn, attobarns |
| au | unit | 149597870700/1 | 0/1 | 1,0,0,0,0,0,0,0 |  |  | astronomical unit, astronomical units, ㍳ |
| australian_tbsp | unit | 1/50000 | 0/1 | 3,0,0,0,0,0,0,0 |  |  | AU tbsp, australian tablespoon, australian tablespoons, australian tbsp |
| b | unit | 1/8 | 0/1 | 0,0,0,0,0,0,0,1 |  |  | bit, bits |
| bakers_dozen | unit | 13/1 | 0/1 | 0,0,0,0,0,0,0,0 |  |  | baker's dozen, bakers dozen |
| ban | unit | 36741077/88481330 | 0/1 | 0,0,0,0,0,0,0,1 |  |  | dit, dits, hartley, hartleys |
| banana | unit | 1/10000000 | 0/1 | 2,0,-2,0,0,0,0,0 | equivalent_dose:1 | banana equivalent dose — approximately 0.1 microsievert | bananas |
| banana_for_scale | unit | 9/50 | 0/1 | 1,0,0,0,0,0,0,0 |  |  | banana for scale, bananas for scale |
| bar | unit | 100000/1 | 0/1 | -1,1,-2,0,0,0,0,0 |  |  |  |
| barleycorn | unit | 127/15000 | 0/1 | 1,0,0,0,0,0,0,0 |  |  | barleycorns |
| barn | unit | 1/10000000000000000000000000000 | 0/1 | 2,0,0,0,0,0,0,0 |  |  | barns |
| barn megaparsec | unit | 180197/58397870562 | 0/1 | 3,0,0,0,0,0,0,0 |  |  | barn-megaparsec, barn-megaparsecs |
| barrel | unit | 2981/25000 | 0/1 | 3,0,0,0,0,0,0,0 |  |  | barrels |
| basis_point | unit | 1/10000 | 0/1 | 0,0,0,0,0,0,0,0 |  |  | basis point, basis points, basis_points, bp_finance |
| bath | unit | 27/1250 | 0/1 | 3,0,0,0,0,0,0,0 |  |  | baths |
| baud | unit | 1/1 | 0/1 | 0,0,-1,0,0,0,0,0 | symbol:1 | symbols transmitted per second |  |
| beard second | unit | 1/200000000 | 0/1 | 1,0,0,0,0,0,0,0 |  |  | beard seconds, beard-second, beard-seconds |
| beat | unit | 1/1 | 0/1 | 0,0,0,0,0,0,0,0 | beat:1 |  | beats |
| beaufort | reference_scale | 1/1 | 0/1 | 0,0,0,0,0,0,0,0 | beaufort:1 |  | Beaufort |
| beka | unit | 23/4000 | 0/1 | 0,1,0,0,0,0,0,0 |  |  | bekah, bekas |
| biblical_mil | unit | 4572/5 | 0/1 | 1,0,0,0,0,0,0,0 |  |  | talmudic mil, talmudic_mil |
| biblical_mina | unit | 23/40 | 0/1 | 0,1,0,0,0,0,0,0 |  |  | maneh, mina, minas |
| biblical_talent | unit | 69/2 | 0/1 | 0,1,0,0,0,0,0,0 |  |  | biblical talent, kikar, talent, talents |
| bit/s | unit | 1/8 | 0/1 | 0,0,-1,0,0,0,0,1 |  |  |  |
| bit/s/Hz | unit | 1/8 | 0/1 | 0,0,0,0,0,0,0,1 | spectral_efficiency:1 | bits per second per hertz — spectral efficiency | bit/(s·Hz), bits per second per hertz, spectral efficiency |
| bit/symbol | unit | 1/8 | 0/1 | 0,0,0,0,0,0,0,1 | symbol:-1 | information carried per modulation symbol | bits per symbol |
| block | unit | 1024/1 | 0/1 | 0,0,0,0,0,0,0,1 |  |  | blocks |
| bohr_radius | unit | 1331/25152254718769 | 0/1 | 1,0,0,0,0,0,0,0 |  | atomic unit of length for the hydrogen ground state | a0, a_0 |
| boiler_horsepower | unit | 19619/2 | 0/1 | 2,1,-3,0,0,0,0,0 |  |  | boiler horsepower |
| bortle | reference_scale | 1/1 | 0/1 | 0,0,0,0,0,0,0,0 | bortle:1 |  | Bortle |
| bottle | unit | 3/4000 | 0/1 | 3,0,0,0,0,0,0,0 |  |  | bottles |
| bpm | unit | 1/60 | 0/1 | 0,0,-1,0,0,0,0,0 | beat:1 |  | BPM, beats per minute |
| bps | unit | 1/8 | 0/1 | 0,0,-1,0,0,0,0,1 |  |  |  |
| brad | unit | 18369286/748432043 | 0/1 | 0,0,0,0,0,0,0,0 | angle:1 |  | brads |
| brinell | unit | 1/1 | 0/1 | 0,0,0,0,0,0,0,0 | hardness_brinell:1 |  | HB |
| bushel | unit | 220244188543/6250000000000 | 0/1 | 3,0,0,0,0,0,0,0 |  |  | bu, bushels |
| cP | unit | 1/1000 | 0/1 | -1,1,-1,0,0,0,0,0 |  |  | centipoise |
| cSt | unit | 1/1000000 | 0/1 | 2,0,-1,0,0,0,0,0 |  |  | centistokes |
| cable | unit | 926/5 | 0/1 | 1,0,0,0,0,0,0,0 |  |  | cables |
| cable_length | unit | 926/5 | 0/1 | 1,0,0,0,0,0,0,0 |  |  | cable length, cable lengths |
| cal | unit | 10467/2500 | 0/1 | 2,1,-2,0,0,0,0,0 |  |  | calorie, calories |
| cal_IT | unit | 10467/2500 | 0/1 | 2,1,-2,0,0,0,0,0 |  | International Table calorie equal to exactly 4.1868 joules | calorie IT, international table calorie |
| cal_th | unit | 523/125 | 0/1 | 2,1,-2,0,0,0,0,0 |  | thermochemical calorie equal to exactly 4.184 joules | thermochemical calorie |
| carat | unit | 1/5000 | 0/1 | 0,1,0,0,0,0,0,0 |  |  | carats, ct |
| cd | unit | 1/1 | 0/1 | 0,0,0,0,0,0,1,0 | luminous_intensity:1 | candela — SI base unit of luminous intensity | candela, candelas |
| cd/m² | unit | 1/1 | 0/1 | -2,0,0,0,0,0,1,0 | luminance:1 | candelas per square metre — SI luminance expression | candela per square meter |
| cell | unit | 1/1 | 0/1 | 0,0,0,0,0,0,0,0 | cell_count:1 |  | cells |
| cells/mL | unit | 1000000/1 | 0/1 | -3,0,0,0,0,0,0,0 | cell_count:1 |  |  |
| cent_pitch | unit | 1/1 | 0/1 | 0,0,0,0,0,0,0,0 | pitch:1 |  | cent, cents |
| century | unit | 3155695200/1 | 0/1 | 0,0,1,0,0,0,0,0 |  |  | centuries |
| ch | unit | 12573/625 | 0/1 | 1,0,0,0,0,0,0,0 |  |  | chain, chains |
| chetvert | unit | 20991/100000 | 0/1 | 3,0,0,0,0,0,0,0 |  |  | chetverts |
| chi | unit | 1/3 | 0/1 | 1,0,0,0,0,0,0,0 |  |  | chis |
| cicero | unit | 225639/50000000 | 0/1 | 1,0,0,0,0,0,0,0 |  |  |  |
| clo | unit | 31/200 | 0/1 | 0,-1,3,0,1,0,0,0 |  | clothing-insulation unit equal to 0.155 square metre kelvin per watt | clo unit |
| cluster | unit | 4096/1 | 0/1 | 0,0,0,0,0,0,0,1 |  |  | clusters |
| cmH2O | unit | 196133/2000 | 0/1 | -1,1,-2,0,0,0,0,0 |  |  |  |
| compton_e | unit | 244/100564221388997 | 0/1 | 1,0,0,0,0,0,0,0 |  |  | compton wavelength, compton wavelength electron, compton_wavelength |
| compton_n | unit | 6/4546863708731791 | 0/1 | 1,0,0,0,0,0,0,0 |  |  | compton wavelength neutron |
| compton_p | unit | 4/3027069900897207 | 0/1 | 1,0,0,0,0,0,0,0 |  |  | compton wavelength proton |
| copies/mL | unit | 1000000/1 | 0/1 | -3,0,0,0,0,0,0,0 | molecular_copy:1 |  |  |
| copy | unit | 1/1 | 0/1 | 0,0,0,0,0,0,0,0 | molecular_copy:1 |  | copies |
| cord | unit | 906139/250000 | 0/1 | 3,0,0,0,0,0,0,0 |  |  | cords |
| count | unit | 1/1 | 0/1 | 0,0,0,0,0,0,0,0 | detector_count:1 |  |  |
| cpm | unit | 1/60 | 0/1 | 0,0,-1,0,0,0,0,0 | detector_count:1 |  | counts per minute |
| cps | unit | 1/1 | 0/1 | 0,0,-1,0,0,0,0,0 | detector_count:1 |  | counts per second |
| crumb | unit | 1/4 | 0/1 | 0,0,0,0,0,0,0,1 |  |  | crumbs |
| cubit | unit | 1143/2500 | 0/1 | 1,0,0,0,0,0,0,0 |  |  | amah, amot, cubits |
| cun | unit | 1/30 | 0/1 | 1,0,0,0,0,0,0,0 |  |  | cuns |
| cup | unit | 473176473/2000000000000 | 0/1 | 3,0,0,0,0,0,0,0 |  |  | cups |
| cwt | unit | 1016047/20000 | 0/1 | 0,1,0,0,0,0,0,0 |  |  |  |
| cycle | unit | 1/1 | 0/1 | 0,0,0,0,0,0,0,0 | cycle:1 |  | cyc, cycles |
| d | unit | 86400/1 | 0/1 | 0,0,1,0,0,0,0,0 |  |  | day, days |
| dan_cn | unit | 50/1 | 0/1 | 0,1,0,0,0,0,0,0 |  |  | chinese dan, chinese_dan |
| darcy | unit | 9869233/10000000000000000000 | 0/1 | 2,0,0,0,0,0,0,0 |  | porous-medium permeability unit | darcies |
| dash | unit | 122699/199149509426 | 0/1 | 3,0,0,0,0,0,0,0 |  |  | dashes |
| decade | unit | 315569520/1 | 0/1 | 0,0,1,0,0,0,0,0 |  |  | decades |
| decay | unit | 1/1 | 0/1 | 0,0,0,0,0,0,0,0 | decay:1 |  | decays |
| deciban | unit | 34582415/832827539 | 0/1 | 0,0,0,0,0,0,0,1 |  |  | decibans |
| decitex | unit | 1/10000000 | 0/1 | 0,0,0,0,0,0,0,0 | linear_density:1 |  | decitex |
| deg | unit | 14964008/857374503 | 0/1 | 0,0,0,0,0,0,0,0 | angle:1 |  | degree, degrees, ° |
| denier | unit | 1/9000000 | 0/1 | 0,0,0,0,0,0,0,0 | linear_density:1 |  | deniers |
| didot | unit | 75213/200000000 | 0/1 | 1,0,0,0,0,0,0,0 |  |  |  |
| digit | unit | 3/160 | 0/1 | 1,0,0,0,0,0,0,0 |  |  | digits |
| diopter | unit | 1/1 | 0/1 | -1,0,0,0,0,0,0,0 |  | reciprocal metre used for optical power | diopters, dioptre, dioptres |
| dogyear | unit | 4508136/1 | 0/1 | 0,0,1,0,0,0,0,0 |  |  | dog year, dog years |
| donkeypower | unit | 25013/100 | 0/1 | 2,1,-3,0,0,0,0,0 |  |  | donkey power, donkey-power |
| dozen | unit | 12/1 | 0/1 | 0,0,0,0,0,0,0,0 |  |  | dozens |
| dpi | unit | 5000/127 | 0/1 | -1,0,0,0,0,0,0,0 |  | dots per inch — spatial resolution | dots per inch |
| dpm | unit | 1/60 | 0/1 | 0,0,-1,0,0,0,0,0 | decay:1 |  | decays per minute |
| dppx | unit | 480000/127 | 0/1 | -1,0,0,0,0,0,0,0 |  | dots per CSS pixel — resolution unit equal to 96 dpi | dots per pixel |
| dr | unit | 4429613/2500000000 | 0/1 | 0,1,0,0,0,0,0,0 |  |  | drachm, drams |
| drop | unit | 1/20000000 | 0/1 | 3,0,0,0,0,0,0,0 |  |  | drops |
| dword | unit | 4/1 | 0/1 | 0,0,0,0,0,0,0,1 |  |  | DWORD, dwords |
| dyn | unit | 1/100000 | 0/1 | 1,1,-2,0,0,0,0,0 |  |  | dyne, dynes |
| eV | unit | 801088317/5000000000000000000000000000 | 0/1 | 2,1,-2,0,0,0,0,0 |  | electronvolt — energy gained by one elementary charge through one volt | electronvolt, electronvolts |
| earthmass | reference_quantity | 5972200000000000224395264/1 | 0/1 | 0,1,0,0,0,0,0,0 |  |  | M⊕, earth mass |
| earthradius | reference_quantity | 6371000/1 | 0/1 | 1,0,0,0,0,0,0,0 |  |  | R⊕, earth radius |
| edge | unit | 1/1 | 0/1 | 0,0,0,0,0,0,0,0 | graph_edge:1 |  | edges |
| egypt_palm | unit | 3/40 | 0/1 | 1,0,0,0,0,0,0,0 |  |  | egyptian palm, egyptian palms |
| einstein | unit | 1/1 | 0/1 | 0,0,0,0,0,1,0,0 | photon:1 | one mole of photons | einsteins |
| electric_horsepower | unit | 746/1 | 0/1 | 2,1,-3,0,0,0,0,0 |  |  | electric horsepower |
| electron_mass | physical_constant | 1/1097769105757763229651765532459 | 0/1 | 0,1,0,0,0,0,0,0 |  | rest mass of an electron | electron mass, m_e |
| em | unit | 1/1 | 0/1 | 0,0,0,0,0,0,0,0 | em:1 |  | quad |
| en | unit | 1/2 | 0/1 | 0,0,0,0,0,0,0,0 | em:1 |  |  |
| english_cubit | unit | 1143/2500 | 0/1 | 1,0,0,0,0,0,0,0 |  |  | english cubit, english cubits |
| entropy | unit | 1/1 | 0/1 | 2,1,-2,0,-1,0,0,0 | entropy:1 | joules per kelvin tagged as thermodynamic entropy |  |
| ephah | unit | 27/1250 | 0/1 | 3,0,0,0,0,0,0,0 |  |  | ephahs, ephas |
| erg | unit | 1/10000000 | 0/1 | 2,1,-2,0,0,0,0,0 |  |  |  |
| fL | unit | 330354972/96418561 | 0/1 | -2,0,0,0,0,0,1,0 | luminance:1 |  | foot-lambert |
| f_stop | unit | 1/1 | 0/1 | 0,0,0,0,0,0,0,0 | f_stop:1 |  | f stop, f-stop, f-stops, fstop |
| fathom | unit | 1143/625 | 0/1 | 1,0,0,0,0,0,0,0 |  |  | fathoms |
| fb⁻¹ | unit | 10000000000000000139372116959414099130712064/1 | 0/1 | -2,0,0,0,0,0,0,0 |  |  | fb-1, fb^-1, fbinv, inv_fb, inverse femtobarn |
| fc | unit | 1562500/145161 | 0/1 | -2,0,0,0,0,0,1,0 | illuminance:1 | foot-candle equal to one lumen per square international foot | foot candle, foot candles, foot-candle |
| femtobarn | unit | 1/9999999999999998229813284190235572552885414 | 0/1 | 2,0,0,0,0,0,0,0 |  |  | fbarn, femtobarns |
| fen | unit | 1/300 | 0/1 | 1,0,0,0,0,0,0,0 |  |  | fens |
| fine_structure | physical_constant | 6648447/911076577 | 0/1 | 0,0,0,0,0,0,0,0 |  |  | alpha, fine structure constant, α |
| fingerbreadth | unit | 381/20000 | 0/1 | 1,0,0,0,0,0,0,0 |  |  | etzba, etzbaot |
| firkin | unit | 4091481/100000000 | 0/1 | 3,0,0,0,0,0,0,0 |  |  | firkins |
| fldr | unit | 473176473/128000000000000 | 0/1 | 3,0,0,0,0,0,0,0 |  |  | fl dr, fluid dram, fluid drams |
| flop | unit | 1/1 | 0/1 | 0,0,0,0,0,0,0,0 | flop:1 |  | flops_count |
| flop/J | unit | 1/1 | 0/1 | -2,-1,2,0,0,0,0,0 | flop:1 |  | flops per joule |
| flops | unit | 1/1 | 0/1 | 0,0,-1,0,0,0,0,0 | flop:1 |  |  |
| floz | unit | 473176473/16000000000000 | 0/1 | 3,0,0,0,0,0,0,0 |  |  | fl oz, fluid ounce, fluid ounces |
| foe | unit | 100000000000000000000000000000000000000000000/1 | 0/1 | 2,1,-2,0,0,0,0,0 |  | energy unit equal to 10^44 joules | foes |
| fortnight | unit | 1209600/1 | 0/1 | 0,0,1,0,0,0,0,0 |  |  | fortnights |
| fps | unit | 1/1 | 0/1 | 0,0,-1,0,0,0,0,0 | frame:1 |  | FPS, frames per second |
| frame | unit | 1/1 | 0/1 | 0,0,0,0,0,0,0,0 | frame:1 |  | frames |
| french_gauge | unit | 1/3000 | 0/1 | 1,0,0,0,0,0,0,0 |  |  | Fr_catheter, french gauge |
| ft | unit | 381/1250 | 0/1 | 1,0,0,0,0,0,0,0 |  |  | feet, foot |
| ftH2O | unit | 29890669/10000 | 0/1 | -1,1,-2,0,0,0,0,0 |  |  | feet of water, foot of water, ft H2O, ft of water |
| ftlbf | unit | 416402469/307122700 | 0/1 | 2,1,-2,0,0,0,0,0 |  |  | foot pound, foot pounds, foot-pound, foot-pounds |
| fujita | reference_scale | 1/1 | 0/1 | 0,0,0,0,0,0,0,0 | fujita:1 |  | F-scale, fujita scale |
| funt_ru | unit | 40951241/100000000 | 0/1 | 0,1,0,0,0,0,0,0 |  |  | funt, russian funt, russian_funt |
| fur | unit | 25146/125 | 0/1 | 1,0,0,0,0,0,0,0 |  |  | furlong, furlongs |
| g | unit | 1/1000 | 0/1 | 0,1,0,0,0,0,0,0 |  | gram — one thousandth of a kilogram | gram, grams |
| g/L | unit | 1/1 | 0/1 | -3,1,0,0,0,0,0,0 |  |  |  |
| g/dL | unit | 10/1 | 0/1 | -3,1,0,0,0,0,0,0 |  |  |  |
| gCO₂e | unit | 1/1000 | 0/1 | 0,1,0,0,0,0,0,0 | co2e:1 | grams of carbon-dioxide equivalent | g CO2e, grams CO2e |
| gCO₂e/kWh | unit | 1/3600000000 | 0/1 | -2,0,2,0,0,0,0,0 | co2e:1 | grams CO₂e per kilowatt-hour — electricity carbon intensity | grid carbon intensity |
| gCO₂e/pkm | unit | 1/1000000 | 0/1 | -1,1,0,0,0,0,0,0 | transport_co2e:1 | grams CO₂e per passenger-kilometre — transport carbon intensity | transport carbon intensity |
| g_n | unit | 196133/20000 | 0/1 | 1,0,-2,0,0,0,0,0 |  |  |  |
| gal | unit | 473176473/125000000000 | 0/1 | 3,0,0,0,0,0,0,0 |  |  | gallon, gallons |
| gaz | unit | 1143/1250 | 0/1 | 1,0,0,0,0,0,0,0 |  |  | gazes |
| gee | unit | 196133/20000 | 0/1 | 1,0,-2,0,0,0,0,0 |  |  |  |
| gerah | unit | 23/40000 | 0/1 | 0,1,0,0,0,0,0,0 |  |  | gerahs |
| gigaton | unit | 1000000000000/1 | 0/1 | 0,1,0,0,0,0,0,0 |  |  | gigatons |
| gill | unit | 473176473/4000000000000 | 0/1 | 3,0,0,0,0,0,0,0 |  |  | gills |
| gon | unit | 10906443/694325726 | 0/1 | 0,0,0,0,0,0,0,0 | angle:1 |  | grad, gradian, gradians |
| googol | unit | 10000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000/1 | 0/1 | 0,0,0,0,0,0,0,0 |  |  | googols |
| googolplex | unit | 10000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000/1 | 0/1 | 0,0,0,0,0,0,0,0 |  |  | googolplexes |
| gpm | unit | 196133/20000 | 0/1 | 2,0,-2,0,0,0,0,0 | geopotential:1 | geopotential metre equal to 9.80665 square metres per second squared | geopotential meter, geopotential metre |
| gr | unit | 918413/14173278532 | 0/1 | 0,1,0,0,0,0,0,0 |  |  | grain, grains |
| great_gross | unit | 1728/1 | 0/1 | 0,0,0,0,0,0,0,0 |  |  | great gross |
| gross | unit | 144/1 | 0/1 | 0,0,0,0,0,0,0,0 |  |  |  |
| gō | unit | 18039/100000000 | 0/1 | 3,0,0,0,0,0,0,0 |  |  | gos |
| g₀ | unit | 196133/20000 | 0/1 | 1,0,-2,0,0,0,0,0 |  |  | g0, standard gravity, ɡ |
| h | unit | 3600/1 | 0/1 | 0,0,1,0,0,0,0,0 |  |  | hour, hours |
| ha | unit | 10000/1 | 0/1 | 2,0,0,0,0,0,0,0 |  |  | hectare, hectares |
| hand | unit | 127/1250 | 0/1 | 1,0,0,0,0,0,0,0 |  |  | hands |
| handbreadth | unit | 381/5000 | 0/1 | 1,0,0,0,0,0,0,0 |  |  | handbreadths, tefach, tefachim |
| hartree | unit | 1/229371227839632473 | 0/1 | 2,1,-2,0,0,0,0,0 |  | atomic unit of energy, approximately 27.211 electronvolts | Eh, hartrees |
| hath | unit | 1143/2500 | 0/1 | 1,0,0,0,0,0,0,0 |  |  | haths |
| heap | unit | 1/1 | 0/1 | 0,0,0,0,0,0,0,0 | heap:1 |  | heaps |
| heat_capacity | unit | 1/1 | 0/1 | 2,1,-2,0,-1,0,0,0 | heat_capacity:1 | joules per kelvin tagged as heat capacity | heat capacity |
| helek | unit | 10/3 | 0/1 | 0,0,1,0,0,0,0,0 |  |  | chelakim, chelek, halakim |
| hin | unit | 9/2500 | 0/1 | 3,0,0,0,0,0,0,0 |  |  | hins |
| hogshead | unit | 2981/12500 | 0/1 | 3,0,0,0,0,0,0,0 |  |  | hogsheads |
| hole | unit | 1/1 | 0/1 | 0,0,0,0,0,0,0,0 | hole:1 |  | holes |
| hounsfield_unit | reference_scale | 1/1 | 0/1 | 0,0,0,0,0,0,0,0 | hounsfield:1 |  | HU, hounsfield |
| hp | unit | 2068973376/2774539 | 0/1 | 2,1,-3,0,0,0,0,0 |  |  | horsepower |
| imperial_pint | unit | 825646/1452933239 | 0/1 | 3,0,0,0,0,0,0,0 |  |  | imperial pint, imperial pints |
| impgal | unit | 454609/100000000 | 0/1 | 3,0,0,0,0,0,0,0 |  |  | imp gal, imperial gallon, imperial gallons |
| in | unit | 127/5000 | 0/1 | 1,0,0,0,0,0,0,0 |  |  | inch, inches |
| inH2O | unit | 2490889/10000 | 0/1 | -1,1,-2,0,0,0,0,0 |  |  | in H2O, in of water, inch of water, inches of water |
| inHg | unit | 3386389/1000 | 0/1 | -1,1,-2,0,0,0,0,0 |  |  |  |
| instant | unit | 1/1 | 0/1 | 0,0,0,0,0,0,0,0 | instant:1 |  | instants |
| instruction | unit | 1/1 | 0/1 | 0,0,0,0,0,0,0,0 | instruction:1 |  | instructions |
| io | unit | 1/1 | 0/1 | 0,0,0,0,0,0,0,0 | io:1 |  | io_op, io_ops, ios |
| iops | unit | 1/1 | 0/1 | 0,0,-1,0,0,0,0,0 | io:1 |  |  |
| iugerum | unit | 251943/100 | 0/1 | 2,0,0,0,0,0,0,0 |  |  | iugera, jugerum |
| japanese_cup | unit | 1/5000 | 0/1 | 3,0,0,0,0,0,0,0 |  |  | japanese cup, japanese cups |
| jelly | unit | 1/1 | 0/1 | 0,0,0,0,0,0,0,0 | jelly:1 |  | grape jelly, j, jam |
| jeroboam | unit | 3/1000 | 0/1 | 3,0,0,0,0,0,0,0 |  |  | jeroboams, rehoboam |
| jiffy | unit | 1/1 | 0/1 | 0,0,0,0,0,0,0,0 | jiffy:1 |  | jiffies |
| jigger | unit | 443603/10000000000 | 0/1 | 3,0,0,0,0,0,0,0 |  |  | jiggers |
| jin | unit | 1/2 | 0/1 | 0,1,0,0,0,0,0,0 |  |  | jins |
| jo | unit | 100/33 | 0/1 | 1,0,0,0,0,0,0,0 |  |  | jos |
| julianyear | unit | 31557600/1 | 0/1 | 0,0,1,0,0,0,0,0 |  |  | julian year, julian years |
| jupitermass | reference_quantity | 1898599999999999942269599744/1 | 0/1 | 0,1,0,0,0,0,0,0 |  |  | M♃, jupiter mass |
| kFLOPS | unit | 1000/1 | 0/1 | 0,0,-1,0,0,0,0,0 | flop:1 |  |  |
| kWh | unit | 3600000/1 | 0/1 | 2,1,-2,0,0,0,0,0 |  |  | kilowatt hour, kilowatt hours, kilowatt-hour, kilowatt-hours |
| kab | unit | 3/2500 | 0/1 | 3,0,0,0,0,0,0,0 |  |  | kabim, kabs |
| kanme | unit | 15/4 | 0/1 | 0,1,0,0,0,0,0,0 |  |  | kanmes |
| kat | unit | 1/1 | 0/1 | 0,0,-1,0,0,1,0,0 |  |  | katal, katals |
| kat/m³ | unit | 1/1 | 0/1 | -3,0,-1,0,0,1,0,0 |  | katals per cubic metre — catalytic activity concentration | catalytic activity concentration |
| kayser | unit | 100/1 | 0/1 | -1,0,0,0,0,0,0,0 |  |  | cm-1, cm^-1, cm⁻¹, kaysers, wavenumber |
| kcal | unit | 20934/5 | 0/1 | 2,1,-2,0,0,0,0,0 |  |  | kilocalorie, kilocalories |
| kcal_IT | unit | 20934/5 | 0/1 | 2,1,-2,0,0,0,0,0 |  |  |  |
| kcal_th | unit | 4184/1 | 0/1 | 2,1,-2,0,0,0,0,0 |  |  | thermochemical kilocalorie |
| kflops | unit | 1000/1 | 0/1 | 0,0,-1,0,0,0,0,0 | flop:1 |  |  |
| kg | unit | 1/1 | 0/1 | 0,1,0,0,0,0,0,0 |  | kilogram — SI base unit of mass, defined via the Planck constant h | grave, kilogram, kilograms |
| kg/m | unit | 1/1 | 0/1 | -1,1,0,0,0,0,0,0 |  | kilograms per metre — linear mass density | linear density |
| kg/m² | unit | 1/1 | 0/1 | -2,1,0,0,0,0,0,0 |  | kilograms per square metre — areal mass density | areal density |
| kg/m³ | unit | 1/1 | 0/1 | -3,1,0,0,0,0,0,0 |  | kilograms per cubic metre — SI mass density | kilograms per cubic meter, mass density |
| kg/s | unit | 1/1 | 0/1 | 0,1,-1,0,0,0,0,0 |  | kilograms per second — SI mass flow rate | kilograms per second, mass flow |
| kgCO₂e | unit | 1/1 | 0/1 | 0,1,0,0,0,0,0,0 | co2e:1 | kilograms of carbon-dioxide equivalent | kg CO2e, kilograms CO2e |
| kgf | unit | 196133/20000 | 0/1 | 1,1,-2,0,0,0,0,0 |  |  | kilogram force, kilogram-force |
| kg·m/s | unit | 1/1 | 0/1 | 1,1,-1,0,0,0,0,0 | momentum:1 | kilogram metres per second — momentum | momentum |
| khet | unit | 105/2 | 0/1 | 1,0,0,0,0,0,0,0 |  |  | khets |
| kilderkin | unit | 4091481/50000000 | 0/1 | 3,0,0,0,0,0,0,0 |  |  | kilderkins |
| kiloton | unit | 1000000/1 | 0/1 | 0,1,0,0,0,0,0,0 |  |  | kilotons |
| kilowarhol | unit | 15000/1 | 0/1 | 0,0,0,0,0,0,0,0 | fame:1 |  | kilowarhols |
| knot | unit | 463/900 | 0/1 | 1,0,-1,0,0,0,0,0 |  |  | kn, knots, kt |
| koku | unit | 18039/100000 | 0/1 | 3,0,0,0,0,0,0,0 |  |  | kokus |
| kor | unit | 27/125 | 0/1 | 3,0,0,0,0,0,0,0 |  |  | korim, kors |
| kos | unit | 3219/1 | 0/1 | 1,0,0,0,0,0,0,0 |  |  | indian kos, kos_indian |
| kph | unit | 5/18 | 0/1 | 1,0,-1,0,0,0,0,0 |  |  |  |
| ktok/s | unit | 1000/1 | 0/1 | 0,0,-1,0,0,0,0,0 | token:1 |  |  |
| l | unit | 1/1000 | 0/1 | 3,0,0,0,0,0,0,0 |  |  |  |
| lb | unit | 45359237/100000000 | 0/1 | 0,1,0,0,0,0,0,0 |  |  | lbs, pound, pounds |
| lbf | unit | 8896443230521/2000000000000 | 0/1 | 1,1,-2,0,0,0,0,0 |  |  | pound force, pound-force |
| league | unit | 603504/125 | 0/1 | 1,0,0,0,0,0,0,0 |  |  | leagues |
| li_cn | unit | 500/1 | 0/1 | 1,0,0,0,0,0,0,0 |  |  | chinese li, chinese_li |
| liang | unit | 1/20 | 0/1 | 0,1,0,0,0,0,0,0 |  |  | liangs |
| libra_roma | unit | 16447/50000 | 0/1 | 0,1,0,0,0,0,0,0 |  |  | libra romana, roman libra |
| lieue_de_poste | unit | 487259/125 | 0/1 | 1,0,0,0,0,0,0,0 |  |  | lieue de poste, lieues de poste |
| light_nanosecond | unit | 34420332/114813869 | 0/1 | 1,0,0,0,0,0,0,0 |  |  | light nanosecond, light-nanosecond |
| lighthour | unit | 1079252848800/1 | 0/1 | 1,0,0,0,0,0,0,0 |  |  | light hour, light hours, lighthours |
| lightminute | unit | 17987547480/1 | 0/1 | 1,0,0,0,0,0,0,0 |  |  | light minute, light minutes, lightminutes |
| lightsecond | unit | 299792458/1 | 0/1 | 1,0,0,0,0,0,0,0 |  |  | light second, light seconds, lightseconds |
| link_chain | unit | 12573/62500 | 0/1 | 1,0,0,0,0,0,0,0 |  |  | link, links |
| lm | unit | 1/1 | 0/1 | 0,0,0,0,0,0,1,0 | luminous_flux:1 | lumen — SI unit of luminous flux | lumen, lumens |
| lm·s | unit | 1/1 | 0/1 | 0,0,1,0,0,0,1,0 | luminous_flux:1 | lumen second — quantity of light | luminous energy |
| lunarmonth | unit | 63786096/25 | 0/1 | 0,0,1,0,0,0,0,0 |  |  | lunar month, lunar months, synodic month, synodic months |
| lustrum | unit | 157784760/1 | 0/1 | 0,0,1,0,0,0,0,0 |  |  | lustra, lustrums |
| lx | unit | 1/1 | 0/1 | -2,0,0,0,0,0,1,0 | illuminance:1 | lux — SI unit of illuminance, one lumen per square metre | lux |
| lx·s | unit | 1/1 | 0/1 | -2,0,1,0,0,0,1,0 | illuminance:1 | lux second — luminous exposure | luminous exposure |
| ly | unit | 9460730472580800/1 | 0/1 | 1,0,0,0,0,0,0,0 |  |  | light year, light years, lightyear, lightyears |
| m | unit | 1/1 | 0/1 | 1,0,0,0,0,0,0,0 |  | metre — SI base unit of length, defined via the speed of light c | meter, meters |
| m/s³ | unit | 1/1 | 0/1 | 1,0,-3,0,0,0,0,0 |  | metres per second cubed — jerk | jerk |
| mEq/L | unit | 1/1 | 0/1 | -3,0,0,0,0,1,0,0 | chemical_equivalent:1 |  |  |
| mGal | unit | 1/100000 | 0/1 | 1,0,-2,0,0,0,0,0 |  | milligal equal to 10^-5 metres per second squared | milligal, milligals |
| mH2O | unit | 196133/20 | 0/1 | -1,1,-2,0,0,0,0,0 |  |  | m H2O, m of water, meter of water, meters of water |
| mOsm/L | unit | 1/1 | 0/1 | -3,0,0,0,0,1,0,0 | osmotic_entity:1 |  |  |
| mac | unit | 1/1 | 0/1 | 0,0,0,0,0,0,0,0 | mac:1 |  | macs |
| mach | contextual_reference | 16573/50 | 0/1 | 1,0,-1,0,0,0,0,0 |  |  |  |
| mach_air_20C | unit | 343/1 | 0/1 | 1,0,-1,0,0,0,0,0 |  | Mach number in dry air at 20 degrees Celsius using 343 m/s | Mach at 20 C, Mach in air at 20 C |
| mag | reference_scale | 1/1 | 0/1 | 0,0,0,0,0,0,0,0 | magnitude_apparent:1 |  | apparent magnitude, magnitude, magnitudes |
| magnum | unit | 3/2000 | 0/1 | 3,0,0,0,0,0,0,0 |  |  | magnums |
| mas | unit | 7835/1616084756946 | 0/1 | 0,0,0,0,0,0,0,0 | angle:1 | milliarcsecond equal to one thousandth of an arcsecond | milliarcsecond, milliarcseconds |
| maund | unit | 186621/5000 | 0/1 | 0,1,0,0,0,0,0,0 |  |  | maunds |
| mbar | unit | 100/1 | 0/1 | -1,1,-2,0,0,0,0,0 |  |  |  |
| megaton | unit | 1000000000/1 | 0/1 | 0,1,0,0,0,0,0,0 |  |  | megatons |
| melchizedek | unit | 3/100 | 0/1 | 3,0,0,0,0,0,0,0 |  |  | melchizedeks |
| methuselah | unit | 3/500 | 0/1 | 3,0,0,0,0,0,0,0 |  |  | imperial bottle, methuselahs |
| metric_cup | unit | 1/4000 | 0/1 | 3,0,0,0,0,0,0,0 |  |  | metric cup, metric cups |
| metric_tbsp | unit | 3/200000 | 0/1 | 3,0,0,0,0,0,0,0 |  |  | metric tablespoon, metric tablespoons, metric tbsp |
| mg/L | unit | 1/1000 | 0/1 | -3,1,0,0,0,0,0,0 |  |  |  |
| mg/dL | unit | 1/100 | 0/1 | -3,1,0,0,0,0,0,0 |  |  |  |
| mg/dL_glucose | unit | 22203/400000 | 0/1 | 0,0,0,0,0,0,0,0 | glucose_concentration:1 | milligrams of glucose per decilitre | mg/dL glucose |
| mi | unit | 201168/125 | 0/1 | 1,0,0,0,0,0,0,0 |  |  | mile, miles |
| mi/h | unit | 1397/3125 | 0/1 | 1,0,-1,0,0,0,0,0 |  |  |  |
| mickey | unit | 127/1000000 | 0/1 | 1,0,0,0,0,0,0,0 |  |  | mickeys |
| microlife | unit | 1800/1 | 0/1 | 0,0,1,0,0,0,0,0 |  |  | microlives, μlife |
| micromort | unit | 1/1000000 | 0/1 | 0,0,0,0,0,0,0,0 |  |  | micromorts, μmort |
| mil | unit | 2752991/2804173606 | 0/1 | 0,0,0,0,0,0,0,0 | angle:1 |  | mils |
| mille_passuum | unit | 1480/1 | 0/1 | 1,0,0,0,0,0,0,0 |  |  | mille passuum, roman mile |
| millennium | unit | 31556952000/1 | 0/1 | 0,0,1,0,0,0,0,0 |  |  | millennia, millenniums |
| millihelen | unit | 1/1 | 0/1 | 0,0,0,0,0,0,0,0 | beauty:1 |  | millihelens |
| min | unit | 60/1 | 0/1 | 0,0,1,0,0,0,0,0 |  |  | minute, minutes |
| mmHg | unit | 66661/500 | 0/1 | -1,1,-2,0,0,0,0,0 |  |  |  |
| mmol/L | unit | 1/1 | 0/1 | -3,0,0,0,0,1,0,0 |  |  | mM, millimolar |
| mmol/L_glucose | unit | 1/1 | 0/1 | 0,0,0,0,0,0,0,0 | glucose_concentration:1 | millimoles of glucose per litre | mmol/L glucose |
| mohs | unit | 1/1 | 0/1 | 0,0,0,0,0,0,0,0 | hardness_mohs:1 |  | Mohs |
| mol | unit | 1/1 | 0/1 | 0,0,0,0,0,1,0,0 |  | mole — SI base unit of amount of substance | mole, moles |
| mol/L | unit | 1000/1 | 0/1 | -3,0,0,0,0,1,0,0 |  |  |  |
| mol/mol | unit | 1/1 | 0/1 | 0,0,0,0,0,0,0,0 | ratio:1 | moles per mole — amount fraction | mole fraction |
| mol/m³ | unit | 1/1 | 0/1 | -3,0,0,0,0,1,0,0 |  |  |  |
| mol_photon/m²/s | unit | 1/1 | 0/1 | -2,0,-1,0,0,1,0,0 | photon:1 |  |  |
| molal | unit | 1/1 | 0/1 | 0,-1,0,0,0,1,0,0 |  |  |  |
| molar | unit | 1000/1 | 0/1 | -3,0,0,0,0,1,0,0 |  |  |  |
| moment | unit | 1/1 | 0/1 | 0,0,0,0,0,0,0,0 | moment:1 |  | moments |
| moment_magnitude | reference_scale | 1/1 | 0/1 | 0,0,0,0,0,0,0,0 | magnitude:1 |  | Mw, moment magnitude |
| momme | unit | 3/800 | 0/1 | 0,1,0,0,0,0,0,0 |  |  | mommes |
| month | unit | 2629746/1 | 0/1 | 0,0,1,0,0,0,0,0 |  |  | mo, months |
| moonmass | reference_quantity | 73419999999999996854272/1 | 0/1 | 0,1,0,0,0,0,0,0 |  |  | M☽, moon mass |
| mpg | unit | 48000000000/112903 | 0/1 | -2,0,0,0,0,0,0,0 |  |  | MPG, miles per gallon |
| mpge | unit | 48000000000/112903 | 0/1 | -2,0,0,0,0,0,0,0 |  |  | MPGe, miles per gallon equivalent |
| mph | unit | 1397/3125 | 0/1 | 1,0,-1,0,0,0,0,0 |  |  | mile per hour, miles per hour |
| mu | unit | 2000/3 | 0/1 | 2,0,0,0,0,0,0,0 |  |  | mus |
| muon_mass | physical_constant | 1/5309175517231704459743524612 | 0/1 | 0,1,0,0,0,0,0,0 |  |  | m_μ, muon mass |
| m³/s | unit | 1/1 | 0/1 | 3,0,-1,0,0,0,0,0 |  | cubic metres per second — SI volumetric flow rate | cubic meters per second, volumetric flow |
| mₚₗ | unit | 18401/845465564313 | 0/1 | 0,1,0,0,0,0,0,0 |  |  | Planck mass, planck mass |
| nail_cloth | unit | 1143/20000 | 0/1 | 1,0,0,0,0,0,0,0 |  |  | cloth nail |
| nanobarn | unit | 1/9999999999999998292708552841744766579 | 0/1 | 2,0,0,0,0,0,0,0 |  |  | nanobarns, nbarn |
| nat | unit | 51711048/286746937 | 0/1 | 0,0,0,0,0,0,0,1 |  |  | nats |
| nb⁻¹ | unit | 9999999999999999538762658202121142272/1 | 0/1 | -2,0,0,0,0,0,0,0 |  |  | inv_nb, inverse nanobarn, nb-1, nb^-1 |
| nebuchadnezzar | unit | 3/200 | 0/1 | 3,0,0,0,0,0,0,0 |  |  | nebuchadnezzars |
| neutron_mass | physical_constant | 1/597040768134859443467254089 | 0/1 | 0,1,0,0,0,0,0,0 |  | rest mass of a neutron | m_n, neutron mass |
| ng/mL | unit | 1/1000000 | 0/1 | -3,1,0,0,0,0,0,0 |  |  |  |
| nibble | unit | 1/2 | 0/1 | 0,0,0,0,0,0,0,1 |  |  | nibbles |
| nit | unit | 1/1 | 0/1 | -2,0,0,0,0,0,1,0 | luminance:1 | unit of luminance equal to one candela per square metre | nits |
| nmi | unit | 1852/1 | 0/1 | 1,0,0,0,0,0,0,0 |  |  | nautical mile, nautical miles |
| nmol/L | unit | 1/1000000 | 0/1 | -3,0,0,0,0,1,0,0 |  |  | nM, nanomolar |
| o | unit | 1/1 | 0/1 | 0,0,0,0,0,0,0,1 |  |  | octet, octets |
| octave | unit | 1200/1 | 0/1 | 0,0,0,0,0,0,0,0 | pitch:1 |  | octaves |
| oil_barrel | unit | 41225904/259303135 | 0/1 | 3,0,0,0,0,0,0,0 |  |  | oil barrel, oil barrels, petroleum barrel, petroleum_barrel |
| omer | unit | 27/12500 | 0/1 | 3,0,0,0,0,0,0,0 |  |  | isaron, issaron, omers |
| onah | unit | 43200/1 | 0/1 | 0,0,1,0,0,0,0,0 |  |  | onot |
| op | unit | 1/1 | 0/1 | 0,0,0,0,0,0,0,0 | op:1 |  | ops |
| op/J | unit | 1/1 | 0/1 | -2,-1,2,0,0,0,0,0 | op:1 |  | operations per joule |
| ops_per_s | unit | 1/1 | 0/1 | 0,0,-1,0,0,0,0,0 | op:1 |  |  |
| osmol | unit | 1/1 | 0/1 | 0,0,0,0,0,1,0,0 | osmotic_entity:1 | osmole of osmotically active entities | osmole, osmoles |
| outhouse | unit | 1/9999999999999999654148077044956645 | 0/1 | 2,0,0,0,0,0,0,0 |  |  |  |
| oz | unit | 45359237/1600000000 | 0/1 | 0,1,0,0,0,0,0,0 |  |  | ounce, ounces |
| packet | unit | 1/1 | 0/1 | 0,0,0,0,0,0,0,0 | packet:1 |  | packets |
| page | unit | 4096/1 | 0/1 | 0,0,0,0,0,0,0,1 |  |  | pages |
| paragraph | unit | 16/1 | 0/1 | 0,0,0,0,0,0,0,1 |  |  | paragraphs |
| parsa | unit | 18288/5 | 0/1 | 1,0,0,0,0,0,0,0 |  |  |  |
| passus | unit | 37/25 | 0/1 | 1,0,0,0,0,0,0,0 |  |  | passus, passuses |
| pb⁻¹ | unit | 10000000000000000303786028427003666890752/1 | 0/1 | -2,0,0,0,0,0,0,0 |  |  | inv_pb, inverse picobarn, pb-1, pb^-1 |
| pc | unit | 30856775814914000/1 | 0/1 | 1,0,0,0,0,0,0,0 |  |  | parsec, parsecs |
| peanutbutter | unit | 1/1 | 0/1 | 0,0,0,0,0,0,0,0 | peanutbutter:1 |  | pb, peanut butter |
| peck | unit | 220244188543/25000000000000 | 0/1 | 3,0,0,0,0,0,0,0 |  |  | pecks, pk |
| pennyweight | unit | 155517/100000000 | 0/1 | 0,1,0,0,0,0,0,0 |  |  | dwt, pennyweights |
| perch | unit | 12573/2500 | 0/1 | 1,0,0,0,0,0,0,0 |  |  | perches |
| person_hour | unit | 3600/1 | 0/1 | 0,0,1,0,0,0,0,0 | person:1 | one person working for one hour | person hour, person hours |
| pes | unit | 37/125 | 0/1 | 1,0,0,0,0,0,0,0 |  |  | pedes |
| phon | unit | 1/1 | 0/1 | 0,0,0,0,0,0,0,0 | loudness_level:1 |  | phons |
| phot | unit | 10000/1 | 0/1 | -2,0,0,0,0,0,1,0 | illuminance:1 | phot equal to 10000 lux | phots |
| photon | unit | 1/1 | 0/1 | 0,0,0,0,0,0,0,0 | photon:1 | one photon event count | photons |
| pica | unit | 4233333/1000000000 | 0/1 | 1,0,0,0,0,0,0,0 |  |  | picas |
| picobarn | unit | 1/9999999999999999687492382876429102444312 | 0/1 | 2,0,0,0,0,0,0,0 |  |  | pbarn, picobarns |
| pied | unit | 1624203/5000000 | 0/1 | 1,0,0,0,0,0,0,0 |  |  | pied du roi, pieds, pieds du roi |
| pieze | unit | 1000/1 | 0/1 | -1,1,-2,0,0,0,0,0 |  |  |  |
| pinch | unit | 122699/398299018852 | 0/1 | 3,0,0,0,0,0,0,0 |  |  | pinches |
| pip | unit | 1/10000 | 0/1 | 0,0,0,0,0,0,0,0 |  |  | pips |
| pipe | unit | 2981/6250 | 0/1 | 3,0,0,0,0,0,0,0 |  |  | butt, pipes |
| point | unit | 176389/500000000 | 0/1 | 1,0,0,0,0,0,0,0 |  |  | points |
| pouce | unit | 2707/100000 | 0/1 | 1,0,0,0,0,0,0,0 |  |  | pouces |
| ppb | unit | 1/1000000000 | 0/1 | 0,0,0,0,0,0,0,0 | ratio:1 |  | parts per billion, parts-per-billion |
| ppbv | unit | 1/1000000000 | 0/1 | 0,0,0,0,0,0,0,0 | volume_fraction:1 |  | parts per billion by volume |
| pphm | unit | 1/100000000 | 0/1 | 0,0,0,0,0,0,0,0 | ratio:1 |  | parts per hundred million |
| ppm | unit | 1/1000000 | 0/1 | 0,0,0,0,0,0,0,0 | ratio:1 | parts per million — ratio of 10⁻⁶ | parts per million, parts-per-million |
| ppmv | unit | 1/1000000 | 0/1 | 0,0,0,0,0,0,0,0 | volume_fraction:1 | parts per million by volume | parts per million by volume |
| ppmw | unit | 1/1000000 | 0/1 | 0,0,0,0,0,0,0,0 | mass_fraction:1 | parts per million by mass | parts per million by mass |
| pps | unit | 1/1 | 0/1 | 0,0,-1,0,0,0,0,0 | packet:1 |  |  |
| ppt | unit | 1/1000000000000 | 0/1 | 0,0,0,0,0,0,0,0 | ratio:1 |  | parts per trillion, parts-per-trillion |
| proton_mass | physical_constant | 1/597863740655678261017993869 | 0/1 | 0,1,0,0,0,0,0,0 |  | rest mass of a proton | m_p, proton mass |
| psi | unit | 6894757/1000 | 0/1 | -1,1,-2,0,0,0,0,0 |  |  |  |
| pt | unit | 473176473/1000000000000 | 0/1 | 3,0,0,0,0,0,0,0 |  |  | pint, pints |
| pud | unit | 32761/2000 | 0/1 | 0,1,0,0,0,0,0,0 |  |  | puds |
| puncheon | unit | 31797/100000 | 0/1 | 3,0,0,0,0,0,0,0 |  |  | puncheons, tertian |
| px | unit | 127/480000 | 0/1 | 1,0,0,0,0,0,0,0 |  | CSS reference pixel — one ninety-sixth of a CSS inch | pixel, pixels |
| qps | unit | 1/1 | 0/1 | 0,0,-1,0,0,0,0,0 | query:1 |  |  |
| qquad | unit | 2/1 | 0/1 | 0,0,0,0,0,0,0,0 | em:1 |  |  |
| qr | unit | 635029/50000 | 0/1 | 0,1,0,0,0,0,0,0 |  |  | quarter, quarters |
| qt | unit | 473176473/500000000000 | 0/1 | 3,0,0,0,0,0,0,0 |  |  | quart, quarts |
| query | unit | 1/1 | 0/1 | 0,0,0,0,0,0,0,0 | query:1 |  | queries |
| quintal | unit | 100/1 | 0/1 | 0,1,0,0,0,0,0,0 |  |  | quintals |
| qword | unit | 8/1 | 0/1 | 0,0,0,0,0,0,0,1 |  |  | QWORD, qwords |
| rad | unit | 1/1 | 0/1 | 0,0,0,0,0,0,0,0 | angle:1 | radian — plane angle subtending an arc equal to the radius | radian, radians |
| rad/s | unit | 1/1 | 0/1 | 0,0,-1,0,0,0,0,0 | angle:1 | radians per second — angular velocity | angular velocity |
| rad/s² | unit | 1/1 | 0/1 | 0,0,-2,0,0,0,0,0 | angle:1 | radians per second squared — angular acceleration | angular acceleration |
| rad_dose | unit | 1/100 | 0/1 | 2,0,-2,0,0,0,0,0 | absorbed_dose:1 | radiation absorbed dose equal to 0.01 gray | absorbed-dose rad, radiation absorbed dose |
| rd | unit | 1000000/1 | 0/1 | 0,0,-1,0,0,0,0,0 | decay:1 |  | rutherford, rutherfords |
| rega | unit | 76/405 | 0/1 | 0,0,1,0,0,0,0,0 |  |  | regaim |
| rem | unit | 1/100 | 0/1 | 2,0,-2,0,0,0,0,0 | equivalent_dose:1 | roentgen equivalent man — 0.01 sievert | rems |
| rem_css | unit | 1/1 | 0/1 | 0,0,0,0,0,0,0,0 | css_root_font_size:1 | CSS root-em — size relative to the root element font | css rem |
| request | unit | 1/1 | 0/1 | 0,0,0,0,0,0,0,0 | request:1 |  | requests |
| revolution | unit | 1/1 | 0/1 | 0,0,0,0,0,0,0,0 | revolution:1 |  | rev, revolutions, revs |
| ri | unit | 4320/11 | 0/1 | 1,0,0,0,0,0,0,0 |  |  |  |
| richter | reference_scale | 1/1 | 0/1 | 0,0,0,0,0,0,0,0 | magnitude:1 |  | Richter, richter scale |
| rockwell | unit | 1/1 | 0/1 | 0,0,0,0,0,0,0,0 | hardness_rockwell:1 |  | HRC |
| rod | unit | 12573/2500 | 0/1 | 1,0,0,0,0,0,0,0 |  |  | rod, rods |
| rope | unit | 762/125 | 0/1 | 1,0,0,0,0,0,0,0 |  |  | ropes |
| rotation | unit | 1/1 | 0/1 | 0,0,0,0,0,0,0,0 | rotation:1 |  | rot, rotations |
| royal_cubit | unit | 21/40 | 0/1 | 1,0,0,0,0,0,0,0 |  |  | royal cubit, royal cubits |
| rpm | unit | 1/60 | 0/1 | 0,0,-1,0,0,0,0,0 | revolution:1 |  | revolutions per minute, rotations per minute |
| rps | unit | 1/1 | 0/1 | 0,0,-1,0,0,0,0,0 | request:1 |  |  |
| rundlet | unit | 3407/50000 | 0/1 | 3,0,0,0,0,0,0,0 |  |  | rundlets |
| rydberg_unit | unit | 1/458742455679275483 | 0/1 | 2,1,-2,0,0,0,0,0 |  |  | Ry, rydberg, rydbergs |
| s | unit | 1/1 | 0/1 | 0,0,1,0,0,0,0,0 |  | second — SI base unit of time, defined by the caesium-133 hyperfine transition | second, seconds |
| saffir_simpson | reference_scale | 1/1 | 0/1 | 0,0,0,0,0,0,0,0 | saffir_simpson:1 |  | SS_category, Saffir-Simpson, saffir simpson |
| sagan | unit | 4000000000/1 | 0/1 | 0,0,0,0,0,0,0,0 |  |  | billions and billions, sagans |
| sample | unit | 1/1 | 0/1 | 0,0,0,0,0,0,0,0 | sample:1 |  | samples |
| savart | unit | 1000/301 | 0/1 | 0,0,0,0,0,0,0,0 | pitch:1 |  | savarts |
| sazhen | unit | 2667/1250 | 0/1 | 1,0,0,0,0,0,0,0 |  |  | sazhens |
| sb | unit | 10000/1 | 0/1 | -2,0,0,0,0,0,1,0 | luminance:1 |  | stilb, stilbs |
| score | unit | 20/1 | 0/1 | 0,0,0,0,0,0,0,0 |  |  | scores |
| seah | unit | 9/1250 | 0/1 | 3,0,0,0,0,0,0,0 |  |  | seahs, seim |
| sector | unit | 512/1 | 0/1 | 0,0,0,0,0,0,0,1 |  |  | sectors |
| seer | unit | 9331/10000 | 0/1 | 0,1,0,0,0,0,0,0 |  |  | seers |
| semitone | unit | 100/1 | 0/1 | 0,0,0,0,0,0,0,0 | pitch:1 |  | half step, halfstep, semitones |
| shaftment | unit | 381/2500 | 0/1 | 1,0,0,0,0,0,0,0 |  |  | shaftments |
| shake | unit | 1/100000000 | 0/1 | 0,0,1,0,0,0,0,0 |  |  | shakes |
| shaku | unit | 10/33 | 0/1 | 1,0,0,0,0,0,0,0 |  |  | shakus |
| shed | unit | 1/9999999999999998996536225270321325685027812444704008 | 0/1 | 2,0,0,0,0,0,0,0 |  |  |  |
| shekel | unit | 23/2000 | 0/1 | 0,1,0,0,0,0,0,0 |  |  | shekalim, shekels |
| shmita | unit | 220898664/1 | 0/1 | 0,0,1,0,0,0,0,0 |  |  | sabbatical, shmitas, shmitta |
| siderealday | unit | 172328181/2000 | 0/1 | 0,0,1,0,0,0,0,0 |  |  | sidereal day, sidereal days |
| siderealyear | unit | 3944768688/125 | 0/1 | 0,0,1,0,0,0,0,0 |  |  | sidereal year, sidereal years |
| sk | unit | 2111208/6632555543 | 0/1 | -2,0,0,0,0,0,1,0 | luminance:1 |  | skot, skots |
| slug | unit | 14593903/1000000 | 0/1 | 0,1,0,0,0,0,0,0 |  |  | slugs |
| smidgen | unit | 61415/398724264139 | 0/1 | 3,0,0,0,0,0,0,0 |  |  | smidgens |
| smoot | unit | 8509/5000 | 0/1 | 1,0,0,0,0,0,0,0 |  | informal length equal to 1.7018 metres | smoots |
| solarmass | reference_quantity | 1988919999999999913189181489152/1 | 0/1 | 0,1,0,0,0,0,0,0 |  |  | M☉, solar mass |
| solarradius | reference_quantity | 696000000/1 | 0/1 | 1,0,0,0,0,0,0,0 |  |  | R☉, solar radius |
| sone | unit | 1/1 | 0/1 | 0,0,0,0,0,0,0,0 | loudness:1 |  | sones |
| span | unit | 1143/5000 | 0/1 | 1,0,0,0,0,0,0,0 |  |  | spans, zeret |
| specific_energy | unit | 1/1 | 0/1 | 2,0,-2,0,0,0,0,0 | specific_energy:1 | joules per kilogram tagged as specific energy | specific energy |
| split | unit | 3/16000 | 0/1 | 3,0,0,0,0,0,0,0 |  |  | piccolo, splits |
| sqft | unit | 145161/1562500 | 0/1 | 2,0,0,0,0,0,0,0 |  |  | sq ft, square feet, square foot |
| sqm | unit | 1/1 | 0/1 | 2,0,0,0,0,0,0,0 |  |  |  |
| sr | unit | 1/1 | 0/1 | 0,0,0,0,0,0,0,0 | solid_angle:1 | steradian — SI unit of solid angle | steradian, steradians |
| st | unit | 635029/100000 | 0/1 | 0,1,0,0,0,0,0,0 |  |  | stone, stones |
| statA | unit | 1/2997924580 | 0/1 | 0,0,0,1,0,0,0,0 |  |  | statampere |
| statC | unit | 1/2997924580 | 0/1 | 0,0,1,1,0,0,0,0 |  | statcoulomb, the electrostatic CGS unit of charge | franklin, statcoulomb |
| statF | unit | 25000/22468879468420441 | 0/1 | -2,-1,4,2,0,0,0,0 |  |  | statfarad |
| statH | unit | 22468879468420441/25000 | 0/1 | 2,1,-2,-2,0,0,0,0 |  |  | stathenry |
| statV | unit | 149896229/500000 | 0/1 | 2,1,-3,-1,0,0,0,0 |  |  | statvolt |
| statΩ | unit | 22468879468420441/25000 | 0/1 | 2,1,-3,-2,0,0,0,0 |  |  | statohm |
| stere | unit | 1/1 | 0/1 | 3,0,0,0,0,0,0,0 |  |  | stère, stères |
| stick | unit | 45359237/400000000 | 0/1 | 0,1,0,0,0,0,0,0 |  |  | stick of butter, sticks, sticks of butter |
| story_point | unit | 1/1 | 0/1 | 0,0,0,0,0,0,0,0 | story_point:1 | relative software-estimation unit | story point, story points |
| sun | unit | 1/33 | 0/1 | 1,0,0,0,0,0,0,0 |  |  | suns |
| sverdrup | unit | 1000000/1 | 0/1 | 3,0,-1,0,0,0,0,0 |  | volumetric transport equal to 10^6 cubic metres per second | Sv_ocean, sverdrups |
| symbol | unit | 1/1 | 0/1 | 0,0,0,0,0,0,0,0 | symbol:1 |  | symbols |
| t | unit | 1000/1 | 0/1 | 0,1,0,0,0,0,0,0 |  |  | metric ton, metric tons, tonne, tonnes |
| tatami | unit | 200/121 | 0/1 | 2,0,0,0,0,0,0,0 |  |  | tatamis |
| tbsp | unit | 473176473/32000000000000 | 0/1 | 3,0,0,0,0,0,0,0 |  |  | tablespoon, tablespoons |
| techum | unit | 4572/5 | 0/1 | 1,0,0,0,0,0,0,0 |  |  | sabbath day's journey, techum shabbat |
| tenth_cent | unit | 1/1000 | 0/1 | 0,0,0,0,0,0,0,0 |  |  | mill_finance, tenth cent |
| tex | unit | 1/1000000 | 0/1 | 0,0,0,0,0,0,0,0 | linear_density:1 |  |  |
| texpt | unit | 127/361350 | 0/1 | 1,0,0,0,0,0,0,0 |  |  |  |
| therm | unit | 52752792631/500 | 0/1 | 2,1,-2,0,0,0,0,0 |  |  | therms |
| tick | unit | 1/1 | 0/1 | 0,0,0,0,0,0,0,0 | tick:1 |  | ticks |
| tierce | unit | 7949/50000 | 0/1 | 3,0,0,0,0,0,0,0 |  |  | tierces |
| tn | unit | 181437/200 | 0/1 | 0,1,0,0,0,0,0,0 |  |  | short ton, short tons, ton, tons |
| toise | unit | 487259/250000 | 0/1 | 1,0,0,0,0,0,0,0 |  |  | toises |
| tok | unit | 1/1 | 0/1 | 0,0,0,0,0,0,0,0 | token:1 |  | token, tokens |
| tok/J | unit | 1/1 | 0/1 | -2,-1,2,0,0,0,0,0 | token:1 |  | tokens per joule |
| tok/s | unit | 1/1 | 0/1 | 0,0,-1,0,0,0,0,0 | token:1 |  |  |
| tola | unit | 729/62500 | 0/1 | 0,1,0,0,0,0,0,0 |  |  | tolas |
| torr | unit | 20265/152 | 0/1 | -1,1,-2,0,0,0,0,0 |  |  | torrs |
| tps | unit | 1/1 | 0/1 | 0,0,-1,0,0,0,0,0 | transaction:1 |  |  |
| transfer | unit | 1/1 | 0/1 | 0,0,0,0,0,0,0,0 | transfer:1 |  | transfers |
| tropicalyear | unit | 3944615652/125 | 0/1 | 0,0,1,0,0,0,0,0 |  |  | tropical year, tropical years |
| troyounce | unit | 62207/2000000 | 0/1 | 0,1,0,0,0,0,0,0 |  |  | ozt, troy ounce, troy ounces |
| tsp | unit | 157725491/32000000000000 | 0/1 | 3,0,0,0,0,0,0,0 |  |  | teaspoon, teaspoons |
| tsubo | unit | 400/121 | 0/1 | 2,0,0,0,0,0,0,0 |  |  | tsubos |
| tun | unit | 2981/3125 | 0/1 | 3,0,0,0,0,0,0,0 |  |  | tuns |
| turn | unit | 411557987/65501488 | 0/1 | 0,0,0,0,0,0,0,0 | angle:1 |  | turns |
| txn | unit | 1/1 | 0/1 | 0,0,0,0,0,0,0,0 | transaction:1 |  | transaction, transactions |
| tₚ | unit | 1/18548584399861476915153871883696645983820063 | 0/1 | 0,0,1,0,0,0,0,0 |  |  | Planck time, planck time |
| u | unit | 1/602214076208112205666689957 | 0/1 | 0,1,0,0,0,0,0,0 |  |  |  |
| uncia_roma | unit | 137/5000 | 0/1 | 0,1,0,0,0,0,0,0 |  |  | roman uncia |
| update | unit | 1/1 | 0/1 | 0,0,0,0,0,0,0,0 | cell_update:1 |  | updates |
| var | unit | 1/1 | 0/1 | 2,1,-3,0,0,0,0,0 | reactive_power:1 | volt ampere reactive, the unit of reactive power | reactive power |
| vershok | unit | 889/20000 | 0/1 | 1,0,0,0,0,0,0,0 |  |  | vershoks |
| verst | unit | 5334/5 | 0/1 | 1,0,0,0,0,0,0,0 |  |  | versts |
| vh | unit | 1/1 | 0/1 | 0,0,0,0,0,0,0,0 | viewport_height_percent:1 | one percent of viewport height | viewport height |
| vickers | unit | 1/1 | 0/1 | 0,0,0,0,0,0,0,0 | hardness_vickers:1 |  | HV |
| vw | unit | 1/1 | 0/1 | 0,0,0,0,0,0,0,0 | viewport_width_percent:1 | one percent of viewport width | viewport width |
| warhol | unit | 15/1 | 0/1 | 0,0,0,0,0,0,0,0 | fame:1 |  | warhols |
| water_horsepower | unit | 746043/1000 | 0/1 | 2,1,-3,0,0,0,0,0 |  |  | water horsepower |
| week | unit | 604800/1 | 0/1 | 0,0,1,0,0,0,0,0 |  |  | weeks, wk |
| yd | unit | 1143/1250 | 0/1 | 1,0,0,0,0,0,0,0 |  |  | yard, yards |
| year | unit | 31556952/1 | 0/1 | 0,0,1,0,0,0,0,0 |  |  | years, yr |
| yovel | unit | 1577847600/1 | 0/1 | 0,0,1,0,0,0,0,0 |  |  | jubilee, jubilees, yovels |
| zhang | unit | 10/3 | 0/1 | 1,0,0,0,0,0,0,0 |  |  | zhangs |
| °C | unit | 1/1 | 5463/20 | 0,0,0,0,1,0,0,0 |  | degree Celsius — an absolute temperature point with the ice point near zero | celsius, ℃ |
| °De | unit | -2/3 | 7463/20 | 0,0,0,0,1,0,0,0 |  |  | delisle |
| °F | unit | 5/9 | 45967/180 | 0,0,0,0,1,0,0,0 |  | degree Fahrenheit — an absolute temperature point | fahrenheit, ℉ |
| °N | unit | 100/33 | 5463/20 | 0,0,0,0,1,0,0,0 |  |  |  |
| °R | unit | 5/9 | 0/1 | 0,0,0,0,1,0,0,0 |  |  | rankine, °Ra |
| °Ré | unit | 5/4 | 5463/20 | 0,0,0,0,1,0,0,0 |  |  | reaumur, réaumur, °Re, °r |
| °Rø | unit | 40/21 | 36241/140 | 0,0,0,0,1,0,0,0 |  |  | romer, rømer |
| °W | unit | 36111/500 | 17063/20 | 0,0,0,0,1,0,0,0 |  |  | wedgwood |
| µas | unit | 301/62085706680376 | 0/1 | 0,0,0,0,0,0,0,0 | angle:1 |  | microarcsecond, microarcseconds, uas, μas |
| µg/mL | unit | 1/1000 | 0/1 | -3,1,0,0,0,0,0,0 |  |  |  |
| µmol/L | unit | 1/1000 | 0/1 | -3,0,0,0,0,1,0,0 |  |  | micromolar, uM, µM, μM |
| µmol_photon/m²/s | unit | 1/1000000 | 0/1 | -2,0,-1,0,0,1,0,0 | photon:1 |  | PPFD, photosynthetic photon flux density |
| Å | unit | 1/10000000000 | 0/1 | 1,0,0,0,0,0,0,0 |  |  | angstrom, angstroms, ångström |
| ʒ | unit | 8367717/2152226789 | 0/1 | 0,1,0,0,0,0,0,0 |  |  |  |
| ΔK | unit | 1/1 | 0/1 | 0,0,0,0,1,0,0,0 | temperature_delta:1 | kelvin temperature difference | delta kelvin, kelvin difference |
| Δ°C | unit | 1/1 | 0/1 | 0,0,0,0,1,0,0,0 | temperature_delta:1 | degree Celsius temperature difference | celsius difference, delta celsius |
| Δ°De | unit | -2/3 | 0/1 | 0,0,0,0,1,0,0,0 | temperature_delta:1 |  |  |
| Δ°F | unit | 5/9 | 0/1 | 0,0,0,0,1,0,0,0 | temperature_delta:1 | degree Fahrenheit temperature difference | delta fahrenheit, fahrenheit difference |
| Δ°N | unit | 100/33 | 0/1 | 0,0,0,0,1,0,0,0 | temperature_delta:1 |  |  |
| Δ°R | unit | 5/9 | 0/1 | 0,0,0,0,1,0,0,0 | temperature_delta:1 |  | delta rankine, rankine difference |
| Δ°Ré | unit | 5/4 | 0/1 | 0,0,0,0,1,0,0,0 | temperature_delta:1 |  |  |
| Δ°Rø | unit | 40/21 | 0/1 | 0,0,0,0,1,0,0,0 | temperature_delta:1 |  |  |
| Δ°W | unit | 36111/500 | 0/1 | 0,0,0,0,1,0,0,0 | temperature_delta:1 |  |  |
| Ω | unit | 1/1 | 0/1 | 2,1,-3,-2,0,0,0,0 |  | ohm — SI derived unit of electrical resistance | ohm, ohms |
| Ω·m | unit | 1/1 | 0/1 | 3,1,-3,-2,0,0,0,0 |  | ohm metre — electrical resistivity | ohm meter, resistivity |
| μ_B | unit | 1/107828220107272931415416 | 0/1 | 2,0,0,1,0,0,0,0 |  |  | bohr magneton, bohr_magneton, muB |
| ℈ | unit | 2789239/2152226789 | 0/1 | 0,1,0,0,0,0,0,0 |  |  | scruple, scruples |
| ℓₚ | unit | 1/61871424991724689232852500479813578 | 0/1 | 1,0,0,0,0,0,0,0 |  |  | Planck length, planck length |
| ℔ | unit | 58319019/156250000 | 0/1 | 0,1,0,0,0,0,0,0 |  |  |  |
| ℥ | unit | 19439673/625000000 | 0/1 | 0,1,0,0,0,0,0,0 |  |  |  |
