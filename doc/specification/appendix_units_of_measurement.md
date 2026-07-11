# Appendix: Units of measurement

## Normative quantity model

A Tungsten dimension is an eight-axis SI exponent vector plus a sparse set of
semantic exponents. Semantic axes are normative: equality requires both the SI
and semantic portions to match. Angle is a semantic dimension; energy does not
gain an angle exponent. Torque, heat capacity, entropy, dose, specific energy,
activity, frequency, and named event rates may use semantic axes to prevent
same-vector category errors.

An unannotated `Quantity` is a vector. `.point(origin)` marks an affine
coordinate and `.delta(origin)` marks a displacement. Point plus delta and
delta plus point produce a point; point minus point produces a delta; adding
two points is invalid. Origins, when both present, must compare equal. Absolute
temperature units are points by default and delta-temperature units are
vectors.

The expression `value ± uncertainty` constructs a `Measurement`. Standard,
expanded, asymmetric, correlated, component, and provenance metadata are part
of the measurement model. Calibration applies an explicit measurement model
and its uncertainty budget; it is not an ordinary unit conversion.

Physical equivalencies are opt-in named operations. `:mass_energy`,
`:spectral`, and `:thermal` are the initial standard bridges. The conversion
operator must continue to reject cross-dimensional conversion.

`Tensor<f64, m/s>.zeros(shape)` constructs a homogeneous tensor whose dtype and
unit annotate the aggregate rather than each element. Addition and subtraction
require matching tensor units.

To do:

    Tetration: 2↑↑1000 = 2^2^2^2....1000 times (or hyper-4, repeated exponentiation)
    Easily creates numbers greater than the 2^80 atoms in the universe.
    What is the largest number representable by 2^80 bits? 2^2^80 - 1

    https://en.wikipedia.org/wiki/List_of_humorous_units_of_measurement

    https://www.nist.gov/pml/time-and-frequency-division/popular-links/time-frequency-z/time-and-frequency-z-f#:~:text=Femtosecond%20(fs),(10%2D15%20s).

    Atomic Units of measurement
    https://en.wikipedia.org/wiki/Atomic_units

    Support SI dimension representation for casting (ML2T−1, Q2W−1L−1)
    https://en.wikipedia.org/wiki/International_System_of_Quantities

    https://en.wikipedia.org/wiki/Orders_of_magnitude_(time)

    SI says there should be a space between the number and the measure
    NIST (maintains SI and Customary measure for the US) says treat like symbols, same as SI
    - space between number and symbol
    - lower case
    - no period as part of the symbol
    - no pluralization

    https://www.quora.com/Does-the-abbreviation-oz-of-ounce-need-a-space-after-the-number-E-g-22oz-or-22-oz

The following units are defined as built-ins:

    Binary Information
      b:   Bit       # e.g. Kib
      B:   Byte      # e.g. KiB
      o:   Octet     # e.g. Kio
      bps: b/s       # e.g. Mbps
      Bps: B/s       # e.g. MBps

    SI Units
    | time                | t     | second   | s   |
    | length              | l,x,r | metre    | m   |
    | mass                | m     | kilogram | kg  |
    | electric current    | I, i  | ampere   | A   |
    | temperature         | T     | kelvin   | K   |
    | amount of substance | n     | mole     | mol |
    | luminous intensity  | Iᵥ    | candela  | cd  |

    Time
      tₚ: 10⁻⁴⁴  planck time
      qs: 10⁻³⁰  quectosecond
      rs: 10⁻²⁷  rontosecond
      ys: 10⁻²⁴  yoctosecond
      zs: 10⁻²¹  zeptosecond
      as: 10⁻¹⁸  attosecond
      fs: 10⁻¹⁵  femtosecond      1fs: cycle time for ultraviolet light with wavelength of 300nm
      ps: 10⁻¹²  picosecond       1ps: mean lifetime of a bottom quark
      ns: 10⁻⁹   nanosecond       1ns: time for light to travel 30cm
      μs: 10⁻⁶   microsecond      2.2μs: lifetime of a muon
      ms: 10⁻³   millisecond      1ms: time for a neuron in the human brain to fire and return to rest
      cs: 10⁻²   centisecond      2cs: cycle time of European 50Hz AC electricity
                                  10-20cs: human reflex response to visual stimuli
      ds: 10⁻¹   decisecond       1-4ds: blink of an eye

      s:   second
      min: minute
      h:   hour
      d:   day
      fortnight
      microcentury                about 52 minutes

      # unconvertible measures of time
      beat
      cycle
      frame
      instant
      jiffy: a context-sensitive unit of time (33.3564ps, 3ys, 20ms, 10ms, or 1ms)
      moment
      sample
      tick

      bpc:  barn-parsec      the volume of the path a cosmic ray or neutrino takes from source to observer
      bMpc: barn-megaparsec: about 2/3 of a teaspoon, 2 bMpc of water contain as many molecules as there are bMpc of water on Earth

     
    Mass
      kg: kilogram
       g: gram
       t: tonne, metric ton # 1t = 1_000kg = 1Mg

       Grave

          gr: grain (1/7000 lb)
          dr: drachm (1/256 lb)
          oz: ounce  (1/16  lb)
          lb: pound (16 oz)
          st: stone   (14 lbs)
          qr: quarter (28 lbs)
         CWT: short hundredweight (US) (100 lb) (sometimes cental)
         cwt:  long hundredweight (UK) (112 lb, 8 st)
      tn, st: short ton (US) (2000 lbs)
          LT:  long ton (UK) (2240 lbs, 160 st)

    # https://en.wikipedia.org/wiki/Avoirdupois
    Mass (Avoirdupois)
        dram:  1/16 ounce, 1/256 pound, 27 11/32 grains
        ounce: 16 drams, 437.5 grains

    # https://en.wikipedia.org/wiki/Apothecaries%27_system
    Mass (Apothecaries)
      ℈ scruple: 20 grains
      ʒ drachm:  60 grains, 3 scruples, 1/8 ounce apothecaries (oz ap, or ℥), 1/96 pound apothecaries (lb ap), 60 grains
      ℥ ounce:  480 grains, 8 drachms, troy oz (oz t)
      ℔ pound:  

    # https://en.wikipedia.org/wiki/Dram_(unit)
    Mass (Greek)
        drachma
        obols
        mina

    # https://en.wikipedia.org/wiki/Ancient_Roman_units_of_measurement
    Mass (Roman)
        drachma: 
        pounds:   96 drachma

    Mass (Sasanian)
        drachm

    Mass (Ottoman)
        dirhem: درهم

    # https://en.wikipedia.org/wiki/English_brewery_cask_units
    Beer casks
       tun: 1/35 larger than a wine tun
       butt: half a tun, two hogsheads, 1/35 larger than the wine pipe or butt
      
       kilderkin: 
       firkin: 9 gallons

    # https://en.wikipedia.org/wiki/English_wine_cask_units
    #
    # A tun of wine was originally 256 wine gallons, reduced to 252 gallons (to be divisible by small integers, including 7)
    # The Imperial system reduced a tun to 210 imperial gallons (also divisible by small integers, including 7)
    #   a 252-gallon tun of wine has a mass between a short ton and a long ton
    #
    # The Queen Anne wine gallon of 231 cubic inches was adopted in 1707 and still serves as the definition of the US gallon.
    Wine casks
        rundlet       1/14 tun, 1/7 butt
        barrel         1/8 tun, half a wine hogshead
        tierce         1/6 tun, half a puncheon, third of a butt (closely related to modern oil barrel)
        hogshead       1/4 tun, comparable to a beer hogshead, half a butt
        puncheon       1/3 tun (also tertian)
        pipe, butt     half a tun, 105 imp gal
        tun            8 14th-century barrels of wine, 252 US gallons (954 L or 210 Imperial gallons)

        wine gallon    abolished by Britian in 1826; multiply by 0.832674 to convert to imperial gallons
                       speculated it was originally meant to hold eight troy pounds of wine
                       the 1706 Queen Anne statute specifies as 231 cubic inches
                       a cylinder 7 inches in diameter x 6 inches high

    Thermodynamic Temperature
      ℃,  °C:  Celsius,     0 °C
          °D:  Delisle
      ℉,  °F:  Fahrenheit, 32 °F
      K,   K:  Kelvin
          °N:  Newton
      °Ra,°R:  Rankine
      °Ré,°Re: Réaumur   # °R ?
          °Rø: Rømer

    Length
             m: metre
        au, ㍳: astronomical unit

            in: inch
            ft: foot (12 inches)
            yd: yard (3 feet)
              : rod (1/320 mile, 3.5 ft)
              : chain (66 ft) (an acre is 10 square chains)
            mi: mile (5,280 feet)

         lt yr: light year, 10[light years]
         nautical mile, 1[nautical mile]

        # https://en.wikipedia.org/wiki/List_of_humorous_units_of_measurement#Length
        altuve: 5ft 5in, 1.65m (named after José Altuve)
        attoparsec: 10^-18 parsecs (~1.215 in, 3.086 cm))
            parsec: 3.26 light-years
        beard-second: 100 angstroms, 10 nanometres, length avg beard grows in one second
        smoot: 5' 7", the length of Oliver Smoot, used to measure the Harvard Bridge, 364.4 smoots ± 1 ear)

    Length (typographic)
        \quad    same as em, width of capital M (M is slightly less than one em)
        \!      -3/18 quad
        \,       3/18 quad, half space
        \:       4/18 quad
        \;       5/18 quad
        \        6/18 quad, full space
        \qquad      2 quad
        

    Area
      10⁻²⁸m²: barn
           m²: square meters
      ac: Acre
      ha: Hectare # 1ha = 100m * 100m

      # particle physics
      barn: 1.0 x 10^-28 m^2
      outhouse: (1.0 x 10^-6 barns)
      shed:     (1.0 x 10^-24 barns)

    # The difference between US and Imperial gill and similar measures is ~20%
    # https://en.wikipedia.org/wiki/Gallon#U.S._liquid_gallon
    # https://en.wikipedia.org/wiki/Gill_(unit)
    Volume
      m³:      cubic meters
      mL:      milliliter
      l, L:    litre # 1L = 10cm * 10cm * 10cm

      US
        half oz: half ounce (🝳)
        fl oz:   fluid ounce (fl℥)
        gill:    teacup, 4fl℥, 4[fluid ounce], or 4[fl oz]
        cup:     2 gills, 8 fl oz
        pint:    4 gills, 2 cups
        quart:   2 pints
        gal:     4 quarts, gallon, based on the 1706 British wine gallon, 231 cubic inches (3.785411784 L)

      Imperial
        dr, dram: (or drachm, if you're British) (unit of mass in avoirdupois system) (mass and vol in apothecaries' system)
        fl dr:    fluid dram, fluid drachm, fluidram, or fluidrachm (fl dr, ƒ 3, or fʒ)
        gill:     teacup, 5[imp fl oz], 40 imp fl drams
        cup:      2 gills, 8 fl oz
        pint:     4 gills
        imp gal:  Imperial gallon 4.54609 L

    Volume of stacked firewood
      stere or stère
      cord
      kuub
      motti (Finnish)
      mått  (Swedish)

    Volumetric flow rate
      m³/s: cubic meters per second

    Amount of substance
      mol: Mole
    # Avogadro constant: 6.022_140_76 x 10^23

    Atomic mass
      u, Da: unified atomic mass unit or Dalton # 1Da = 1.660538921(73)×10⁻²⁷kg

    Velocity
      m/s: meters per second

      furlongs/fortnight: ~0.00037 mph
      beard-seconds / microfortnight: ~5nm
      attoparsecs / microfortnight: about 1 inch

    Acceleration
      Gal

    Energy (or work, or heat)
      J: Joule         # kg·m²·s⁻² = N·m = Pa·m³ = W·s = C·V
      eV: Electronvolt # 1eV = 1.602176565(35)×10^−19J
      Erg

    Force
      N: Newton # m·kg·s⁻²
      Dyne

    Pressure
      Pa:  Pascal # N/m² = kg·m⁻¹·s⁻²
      Ba:  Barye (or sometimes barad, barrie, bary, baryd, baryed, barie)
      bar: Bar
      at:  Technical atmosphere
      atm: Standard atmosphere
      psi: Pounds per square inch

    Frequency
      Hz: Hertz

    Amount of Substance
      mol: Mole

    Catalytic activity
      kat: Katal

    Energy per Amount of substance
      J/mol: Joule per mole


    # SI electromagnetism units
    Electric current (I)
      A: Ampere # A (= W/V = C/s)

    Electric charge (Q)
      C: Coulomb # A·s

    Potential difference (U, ΔV, Δφ, E)
    Electromotive force
      V: Volt # J/C = kg·m²·s⁻³·A⁻¹

    Electric resistance
    Impedance
    Reactance
      Ω, ㏀, ㏁, Ω, U+1D6C0, U+1D6FA, U+1D734, U+1D76E, U+1D7A8: Ohm
      # Ω = V/A = kg·m²·s⁻³·A⁻² = J·s⁻¹·A⁻² = S⁻¹ = s/F

    Resistivity (p)
      Ω·m: ohm metre # kg·m³·s⁻³·A⁻²

    Electric power (P)
      W: Watt # V·A = kg·m²·s⁻³

    Capacitance (C)
      F: Farad # C/V = kg⁻¹·m⁻²·A²·s⁴

    Electric flux (ΦE)
      V·m: volt metre # kg·m³·s⁻³·A⁻¹

    Electric field strength (E)
      V/m: volt per metre # N/C = kg·m·A⁻¹·s⁻³

    Electric displacement field (D)
      C/m²: coulomb per square metre # A·s·m⁻²

    Permittivity
      F/m: farad per metre # kg⁻¹·m⁻³·A²·s⁴

    Electric susceptibility (χe)
      - # dimensionless

    Conductance (G)
    Admittance (Y)
    Susceptance (B)
      ℧, S, mho: Siemens # Ω⁻¹ = kg⁻¹·m⁻²·s³·A²

    Conductivity (κ, γ, σ)
      S/m: siemens per metre # kg⁻¹·m⁻³·s³·A²

    Magnetic flux density (B)
    Magnetic induction
          T: Tesla # Wb/m² = kg·s⁻²·A⁻¹ = N·A⁻¹·m⁻¹
      G, Ga: Gauss

    Magnetic flux (Φ, ΦM, ΦB)
      Wb: webers # V·s = kg·m²·s⁻²·A⁻¹

    Magnetic field strength (H)
      A/m: ampere per metre # A·m⁻¹

    Magnetic pole strength
      Am, A·m: ampere-meter

    Inductance
      H: Henry # Wb/A = V·s/A = kg·m²·s⁻²·A⁻²
      Abhenry (equal to one billionth of a henry)

    Permeability
      H/m: henry per metre # kg·m·s⁻²·A⁻²

    Magnetic susceptibility
      - # dimensionless


    # SI photometry units
    Luminous intensity (Iᵥ)
      C: Candela # lm/sr

    Luminance (Lᵥ)
      cd/m²: Candela per square meter (sometimes called nits, 1 nit = 1 cd/m²)
      Bril
      sk: Skot
      fL: Foot-Lambert (sometimes fl or fl-L)
      asb: Apostilb
      L, la, Lb: Lambert
      sb: Stilb

    Luminous energy (Qᵥ)
      lm⋅s: lumen second (sometimes called talbots)

    Luminous flux (Φᵥ), or luminous power
      lm: lumen # cd⋅sr

    Illuminance (Eᵥ) used for light incident on a surface
      lx: lux # lm/m²

    Luminous emittance (Mᵥ) used for light emitted from a surface
      lx: lux # lm/m²

    Luminous exposure (Hᵥ)
      lx⋅s: lux second

    Luminous energy density (ω ᵥ)
      lm⋅s⋅m⁻³: lumen second per metre³

    Luminous efficacy (η)
      lm/W: lumer per Watt

    Luminous efficiency (V)


    # SI radiometry units
    Radiant energy (Qe)
      J: joule

    Radiant flux (Φe)
      W: watt

    Spectral power (Φeλ)
      W⋅m⁻¹: watt per metre

    Radiant intensity (Ie)
      W⋅sr⁻¹: watt per steradian

    Spectral intensity (Ieλ)
      W⋅sr⁻¹⋅m⁻¹: watt per steradian per metre

    Radiance (Le)
      W⋅sr⁻¹⋅m⁻²: watt per steradian per square metre

    Spectral radiance (Leλ)
      W⋅sr⁻¹⋅m⁻³: watt per steradian per cubic metre
      W⋅sr⁻¹⋅m⁻²⋅Hz⁻¹: watt per steradian per square metre per hertz

    Irradiance (Ee)
      W⋅m⁻²: watt per square metre

    Spectral irradiance (Eeλ or Eeν)
      W⋅m⁻³: watt per cubic metre

    Radiant exitance / Radiant emittance (Me)
      W⋅m⁻²: watt per square metre

    Spectral radiant exitance / Spectral radiant emittance (Meλ or Meν)
      W⋅m⁻³: watt per cubic metre
      W⋅m⁻²⋅Hz⁻¹: watt per square meter per hertz

    Radiosity (Je)
      W⋅m⁻²: watt per square metre

    Spectral radiosity (Jeλ)
      W⋅m⁻³: watt per cubic metre

    Radiant exposure (He)
      J⋅m⁻²: joule per square metre

    Radiant energy density (ω e)
      J⋅m⁻³: joule per cubic metre


    Radioactivity
      Bq: Becquerel
      Ci: Curie (older)
      rd: Rutherford (obsolete)

    Absorbed radiation dose
      rad: Rad
      Gy: Gray # J/kg

    Equivalent dose
      Sv: sievert # J/kg

    Effective dose
      Sv: sievert

    Committed dose
      Sv: sievert

    Raio of measurements of physical field and power quantities
      Np: neper

    Logarithmic ratio
      dB: Decibel

    Angle
      °: degrees
      ′: arcminutes
      ″: arcseconds
      ‴: ligne

    Solid angle
      sr: stredian

    Plane angle
      rad: radian

    Beauty
      millihelens: if Helen of Troy launched a thousand ships, a millihelen is the measure of beauty required to launch a single ship

    Fame
      warhol: 15 minutes of fame
      kilowarhol: 10.4 days of fame

    Powder charge
      dram: equivalent of black powder in drams avoirdupois

<small>Source: [physics.nist.gov/cuu/Units/units.html](http://physics.nist.gov/cuu/Units/units.html)</small>
<small>Source: [en.wikipedia.org/wiki/Outline_of_the_metric_system](http://en.wikipedia.org/wiki/Outline_of_the_metric_system)</small>
