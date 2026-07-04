# Appendix: Physical and Scientific Constants

Values are from CODATA 2022 (published May 2024 by NIST). After the 2019 SI
redefinition, seven constants are exact by definition; many others become exact
because they derive purely from those seven. Constants marked **(exact)** have
zero measurement uncertainty.

Sources: [NIST Fundamental Physical Constants](https://physics.nist.gov/cuu/Constants/),
[Frink units database](https://frinklang.org/frinkdata/units.txt),
[Wikipedia: List of physical constants](https://en.wikipedia.org/wiki/List_of_physical_constants).

## Notation

    299_792_458 m/s        Int quantity    — exact integer value with unit
    8.314462618 J/mol·K    Decimal quantity — exact non-integer value (arbitrary precision)
    ~6.674e-11 m³/kg·s²    Float quantity  — approximate/measured value (IEEE 754 double)

The `~` prefix selects hardware Float, which supports `e` notation for scientific
notation. Measured constants should use Float since experimental uncertainty
dwarfs floating-point rounding error. Exact constants use Int or Decimal to
preserve full precision.

Constants already available as built-in variables are shown with their variable
name (e.g. `c`, `ℎ`, `Nₐ`).


## 1. Defining Constants of the SI

The 2019 SI redefinition fixed these seven constants to exact numerical values.
All SI units derive from them.

| Constant | Symbol | Value | SI Unit | Tungsten |
|----------|--------|-------|---------|----------|
| Speed of light in vacuum | c | 299 792 458 | m·s⁻¹ | `c` = `299_792_458 m/s` |
| Planck constant | h | 6.626 070 15 &times; 10⁻³⁴ | J·Hz⁻¹ | `ℎ` = `~6.62607015e-34 J*s` |
| Elementary charge | e | 1.602 176 634 &times; 10⁻¹⁹ | C | `e₀` = `~1.602176634e-19 C` |
| Boltzmann constant | k | 1.380 649 &times; 10⁻²³ | J·K⁻¹ | `kB` = `~1.380649e-23 J/K` |
| Avogadro constant | N_A | 6.022 140 76 &times; 10²³ | mol⁻¹ | `Nₐ` = `~6.02214076e23 mol⁻¹` |
| Luminous efficacy of 540 THz radiation | K_cd | 683 | lm·W⁻¹ | `683 lm/W` |
| Hyperfine transition frequency of ¹³³Cs | &Delta;&nu;_Cs | 9 192 631 770 | Hz | `9_192_631_770 Hz` |


## 2. Universal Constants

| Constant | Symbol | Value | SI Unit | Rel. Uncertainty | Tungsten |
|----------|--------|-------|---------|-----------------|----------|
| Newtonian constant of gravitation | G | 6.674 30(15) &times; 10⁻¹¹ | m³·kg⁻¹·s⁻² | 2.2 &times; 10⁻⁵ | `G` = `~6.67430e-11 m³/kg·s²` |
| Reduced Planck constant | ℏ | 1.054 571 817... &times; 10⁻³⁴ | J·s | exact (h/2&pi;) | `ℏ` = `~1.054571817e-34 J*s` |
| Planck mass | m_P | 2.176 434(24) &times; 10⁻⁸ | kg | 1.1 &times; 10⁻⁵ | `~2.176434e-8 kg` |
| Planck length | l_P | 1.616 255(18) &times; 10⁻³⁵ | m | 1.1 &times; 10⁻⁵ | `~1.616255e-35 m` |
| Planck time | t_P | 5.391 247(60) &times; 10⁻⁴⁴ | s | 1.1 &times; 10⁻⁵ | `~5.391247e-44 s` |
| Planck temperature | T_P | 1.416 784(16) &times; 10³² | K | 1.1 &times; 10⁻⁵ | `~1.416784e32 K` |


## 3. Electromagnetic Constants

| Constant | Symbol | Value | SI Unit | Rel. Uncertainty | Tungsten |
|----------|--------|-------|---------|-----------------|----------|
| Vacuum electric permittivity | &epsilon;₀ | 8.854 187 8188(14) &times; 10⁻¹² | F·m⁻¹ | 1.6 &times; 10⁻¹⁰ | `ε₀` = `~8.8541878188e-12 F/m` |
| Vacuum magnetic permeability | &mu;₀ | 1.256 637 061 27(20) &times; 10⁻⁶ | N·A⁻² | 1.6 &times; 10⁻¹⁰ | `μ₀` = `~1.25663706127e-6 H/m` |
| Characteristic impedance of vacuum | Z₀ | 376.730 313 412(59) | &Omega; | 1.6 &times; 10⁻¹⁰ | `~376.730313412 Ω` |
| Fine-structure constant | &alpha; | 7.297 352 5643(11) &times; 10⁻³ | (dimensionless) | 1.5 &times; 10⁻¹⁰ | `α` = `~7.2973525643e-3` |
| Inverse fine-structure constant | &alpha;⁻¹ | 137.035 999 177(21) | (dimensionless) | 1.5 &times; 10⁻¹⁰ | `~137.035999177` |
| Josephson constant | K_J | 483 597.848 4... &times; 10⁹ | Hz·V⁻¹ | exact (2e/h) | `~4.835978484e14 Hz/V` |
| Von Klitzing constant | R_K | 25 812.807 45... | &Omega; | exact (h/e²) | `~25812.80745 Ω` |
| Bohr magneton | &mu;_B | 9.274 010 0657(29) &times; 10⁻²⁴ | J·T⁻¹ | 3.1 &times; 10⁻¹⁰ | `~9.2740100657e-24 J/T` |
| Nuclear magneton | &mu;_N | 5.050 783 7393(16) &times; 10⁻²⁷ | J·T⁻¹ | 3.1 &times; 10⁻¹⁰ | `~5.0507837393e-27 J/T` |
| Electron magnetic moment | &mu;_e | &minus;9.284 764 7043(28) &times; 10⁻²⁴ | J·T⁻¹ | 3.0 &times; 10⁻¹⁰ | `~-9.2847647043e-24 J/T` |
| Proton magnetic moment | &mu;_p | 1.410 606 797 36(60) &times; 10⁻²⁶ | J·T⁻¹ | 4.2 &times; 10⁻¹⁰ | `~1.41060679736e-26 J/T` |
| Neutron magnetic moment | &mu;_n | &minus;9.662 3653(23) &times; 10⁻²⁷ | J·T⁻¹ | 2.4 &times; 10⁻⁷ | `~-9.6623653e-27 J/T` |
| Muon magnetic moment | &mu;_&mu; | &minus;4.490 448 30(10) &times; 10⁻²⁶ | J·T⁻¹ | 2.2 &times; 10⁻⁸ | `~-4.49044830e-26 J/T` |


## 4. Atomic and Nuclear Constants

| Constant | Symbol | Value | SI Unit | Rel. Uncertainty | Tungsten |
|----------|--------|-------|---------|-----------------|----------|
| Electron mass | m_e | 9.109 383 7139(28) &times; 10⁻³¹ | kg | 3.1 &times; 10⁻¹⁰ | `mₑ` = `~9.1093837139e-31 kg` |
| Proton mass | m_p | 1.672 621 925 95(52) &times; 10⁻²⁷ | kg | 3.1 &times; 10⁻¹⁰ | `mₚ` = `~1.67262192595e-27 kg` |
| Neutron mass | m_n | 1.674 927 500 56(85) &times; 10⁻²⁷ | kg | 5.1 &times; 10⁻¹⁰ | `~1.67492750056e-27 kg` |
| Muon mass | m_&mu; | 1.883 531 627(42) &times; 10⁻²⁸ | kg | 2.2 &times; 10⁻⁸ | `~1.883531627e-28 kg` |
| Tau mass | m_&tau; | 3.167 54(21) &times; 10⁻²⁷ | kg | 6.8 &times; 10⁻⁵ | `~3.16754e-27 kg` |
| Atomic mass constant | m_u | 1.660 539 068 92(52) &times; 10⁻²⁷ | kg | 3.1 &times; 10⁻¹⁰ | `~1.66053906892e-27 kg` |
| Proton-electron mass ratio | m_p/m_e | 1 836.152 673 426(32) | (dimensionless) | 1.7 &times; 10⁻¹¹ | `~1836.152673426` |
| Bohr radius | a₀ | 5.291 772 105 44(82) &times; 10⁻¹¹ | m | 1.6 &times; 10⁻¹⁰ | `a₀` = `~5.29177210544e-11 m` |
| Rydberg constant | R_&infin; | 10 973 731.568 157(12) | m⁻¹ | 1.1 &times; 10⁻¹² | `~10973731.568157 m⁻¹` |
| Hartree energy | E_h | 4.359 744 722 2(60) &times; 10⁻¹⁸ | J | 1.4 &times; 10⁻¹⁰ | `~4.3597447222e-18 J` |
| Classical electron radius | r_e | 2.817 940 3205(13) &times; 10⁻¹⁵ | m | 4.7 &times; 10⁻¹⁰ | `~2.8179403205e-15 m` |
| Compton wavelength (electron) | &lambda;_C | 2.426 310 238 67(73) &times; 10⁻¹² | m | 3.0 &times; 10⁻¹⁰ | `~2.42631023867e-12 m` |
| Compton wavelength (proton) | &lambda;_C,p | 1.321 409 855 39(40) &times; 10⁻¹⁵ | m | 3.1 &times; 10⁻¹⁰ | `~1.32140985539e-15 m` |
| Compton wavelength (neutron) | &lambda;_C,n | 1.319 590 905 82(75) &times; 10⁻¹⁵ | m | 5.7 &times; 10⁻¹⁰ | `~1.31959090582e-15 m` |
| Thomson cross section | &sigma;_e | 6.652 458 7051(62) &times; 10⁻²⁹ | m² | 9.3 &times; 10⁻¹⁰ | `~6.6524587051e-29 m²` |


## 5. Thermodynamic and Physico-Chemical Constants

| Constant | Symbol | Value | SI Unit | Rel. Uncertainty | Tungsten |
|----------|--------|-------|---------|-----------------|----------|
| Molar gas constant | R | 8.314 462 618... | J·mol⁻¹·K⁻¹ | exact (N_A &middot; k) | `R` = `8.314462618 J/mol·K` |
| Faraday constant | F | 96 485.332 12... | C·mol⁻¹ | exact (N_A &middot; e) | `𝐹` = `96_485.33212 C/mol` |
| Stefan-Boltzmann constant | &sigma; | 5.670 374 419... &times; 10⁻⁸ | W·m⁻²·K⁻⁴ | exact (derived) | `σ` = `~5.670374419e-8 W/m²·K⁴` |
| Wien displacement law constant | b | 2.897 771 955... &times; 10⁻³ | m·K | exact (derived) | `~2.897771955e-3 m·K` |
| First radiation constant | c₁ | 3.741 771 852... &times; 10⁻¹⁶ | W·m² | exact (derived) | `~3.741771852e-16 W·m²` |
| Second radiation constant | c₂ | 1.438 776 877... &times; 10⁻² | m·K | exact (derived) | `~1.438776877e-2 m·K` |
| Loschmidt constant (273.15 K, 101.325 kPa) | n₀ | 2.686 780 111... &times; 10²⁵ | m⁻³ | exact (derived) | `~2.686780111e25 m⁻³` |
| Molar volume of ideal gas (STP) | V_m | 22.413 969 54... &times; 10⁻³ | m³·mol⁻¹ | exact (derived) | `0.02241396954 m³/mol` |


## 6. Adopted and Conventional Constants

| Constant | Symbol | Value | SI Unit | Tungsten |
|----------|--------|-------|---------|----------|
| Standard acceleration of gravity | g_n | 9.806 65 | m·s⁻² | `g₀` = `9.80665 m/s²` |
| Standard atmosphere | atm | 101 325 | Pa | `101_325 Pa` or `1 atm` |
| Standard-state pressure | p&deg; | 100 000 | Pa | `100_000 Pa` |
| Molar mass of carbon-12 | M(¹²C) | 12 &times; 10⁻³ | kg·mol⁻¹ | `0.012 kg/mol` |
| Conventional Josephson constant | K_J-90 | 483 597.9 &times; 10⁹ | Hz·V⁻¹ | `~483597.9e9 Hz/V` |
| Conventional von Klitzing constant | R_K-90 | 25 812.807 | &Omega; | `25_812.807 Ω` |


## 7. Astronomical Constants

| Constant | Symbol | Value | SI Unit | Tungsten |
|----------|--------|-------|---------|----------|
| Astronomical unit | au | 149 597 870 700 | m | `149_597_870_700 m` or `1 au` |
| Light-year | ly | 9.460 730 472 5808 &times; 10¹⁵ | m | `1 ly` |
| Parsec | pc | 3.085 677 581 4914 &times; 10¹⁶ | m | `1 pc` |
| Solar mass | M_&odot; | 1.988 92 &times; 10³⁰ | kg | `1 solarmass` |
| Earth mass | M_&oplus; | 5.9722 &times; 10²⁴ | kg | `1 earthmass` |
| Jupiter mass | M_J | 1.8986 &times; 10²⁷ | kg | `1 jupitermass` |
| Moon mass | M_&loz; | 7.342 &times; 10²² | kg | `1 moonmass` |
| Solar radius | R_&odot; | 6.96 &times; 10⁸ | m | `1 solarradius` |
| Earth radius (mean) | R_&oplus; | 6.371 &times; 10⁶ | m | `1 earthradius` |
| Hubble constant | H₀ | ~67.4(5) | km·s⁻¹·Mpc⁻¹ | `~67.4 km/s·Mpc` |
| CMB temperature | T_CMB | 2.725 48(57) | K | `~2.72548 K` |


## 8. Constants Implicit in the Unit System

These constants are already encoded in the unit conversion factors of built-in
units. Writing `1 eV` automatically carries the correct SI value.

| Unit | Implicit Constant | SI Factor | Tungsten |
|------|-------------------|-----------|----------|
| `eV` (electronvolt) | elementary charge | 1.602 176 634 &times; 10⁻¹⁹ J | `1 eV` |
| `Da` (dalton) | atomic mass constant | 1.660 539 066 60 &times; 10⁻²⁷ kg | `1 Da` |
| `atm` (atmosphere) | standard atmosphere | 101 325 Pa | `1 atm` |
| `cal` (calorie) | thermochemical calorie | 4.1868 J | `1 cal` |
| `u` (atomic mass unit) | same as dalton | 1.660 539 066 60 &times; 10⁻²⁷ kg | `1 u` |


## Notes

### Exact vs Measured

The 2019 SI redefinition made seven constants exact by definition (Section 1).
Constants derived purely from those seven (e.g. R = N_A &middot; k, F = N_A &middot; e,
&sigma; = 2&pi;⁵k⁴/15h³c²) are also exact. The gravitational constant G remains
the least-precisely known fundamental constant, with a relative uncertainty of
2.2 &times; 10⁻⁵.

### Numeric Type Semantics

Tungsten's three numeric types map naturally to the epistemological status of
constants:

    Int      exact integer           299_792_458 m/s     (speed of light)
    Decimal  exact non-integer       9.80665 m/s²        (standard gravity)
    Float    measured / approximate  ~6.674e-11 m³/kg·s² (gravitational constant)

### Built-in Variables

The interpreter pre-defines 17 physical constants as global variables:

    c  ℎ  ℏ  G  g₀  Nₐ  kB  e₀  R  ε₀  μ₀  σ  α  mₑ  mₚ  a₀  𝐹

Plus 6 mathematical constants: `π`, `τ`, `ϕ`/`φ`, `ℯ`, `ℇ`, `∞`.

Note: `𝐹` (U+1D439, Mathematical Italic Capital F) is used for the Faraday
constant to disambiguate from `F` (Farad unit). Local variables like `c = 1`
will shadow the built-in — this is by design.

<small>Values: CODATA 2022 &mdash; [physics.nist.gov/cuu/Constants](https://physics.nist.gov/cuu/Constants/)</small>
<small>Frink: [frinklang.org/frinkdata/units.txt](https://frinklang.org/frinkdata/units.txt)</small>
