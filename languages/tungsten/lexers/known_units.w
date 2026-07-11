# Shared generated membership table for the self-hosted reference lexer.
# Regenerate with: ruby scripts/gen_units.rb --write

# --- BEGIN GENERATED: regex_known_unit_name ---
-> regex_known_unit_name?(s)
  if s in ("1/mol" "A" "A/m²" "AU tbsp" "Apgar" "B" "B/flop" "BOE" "BPM" "BTU" "Ba" "Beaufort")
    return true
  if s in ("Bortle" "Bps" "Bq" "C" "C/m³" "CWT" "Ci" "D" "DMIPS" "DWORD" "Da" "EF")
    return true
  if s in ("EF-scale" "EFLOPS" "EOPS" "EV" "Eflops" "Eh" "EiB" "F" "F-scale" "F/m" "FLOPS" "FPS")
    return true
  if s in ("Fr_catheter" "GB" "GFLOPS" "GHz" "GIPS" "GJ" "GMAC/s" "GOPS" "GPa" "GT/s" "GW" "Ga")
    return true
  if s in ("Gal" "Gb" "Gflops" "GiB" "Gtok/s" "Gy" "H" "HB" "HRC" "HU" "HV" "Hz")
    return true
  if s in ("IOPS" "ISO" "ISO sensitivity" "ISO_speed" "J" "J/(kg·K)" "J/(mol·K)" "J/K" "J/kg" "J/kg/K" "J/m³" "J/op")
    return true
  if s in ("J/tok" "Jy" "J·s" "K" "KB" "KOPS" "KiB" "L" "L per 100 km" "L/100km" "L/min" "LT")
    return true
  if s in ("La" "MAC/s" "MB" "MFLOPS" "MHz" "MIPS" "MJ" "MMAC/s" "MOPS" "MPG" "MPGe" "MPa")
    return true
  if s in ("MT/s" "MV" "MW" "MWh" "M_bol" "Mach at 20 C" "Mach in air at 20 C" "Mag" "Mbol" "Mflops" "MiB" "Mohs")
    return true
  if s in ("Mtok/s" "Mw" "Mx" "M⊕" "M☉" "M☽" "M♃" "N" "N/A²" "N/m" "N·m" "N·s")
    return true
  if s in ("Oe" "P" "PB" "PFLOPS" "POPS" "PPS" "PS" "Pa" "Pflops" "PiB" "Planck length" "Planck mass")
    return true
  if s in ("Planck time" "QALY" "QALYs" "QPS" "QWORD" "RBE" "RPS" "RU" "Richter" "Ry" "R⊕" "R☉")
    return true
  if s in ("S" "S/m" "SS_category" "Saffir-Simpson" "St" "Sv" "T" "T/s" "TB" "TCE" "TFLOPS" "THz")
    return true
  if s in ("TMAC/s" "TOPS" "TPS" "TT/s" "Tflops" "TiB" "Torr" "V" "V/m" "W" "W/(m²·K⁴)" "W/(m·K)")
    return true
  if s in ("W/m/K" "W/m²" "Wb" "YFLOPS" "Yflops" "ZFLOPS" "Zflops" "a0" "a_0" "ab-1" "ab^-1" "abarn")
    return true
  if s in ("abinv" "absolute magnitude" "ab⁻¹" "ac" "acre" "acres" "alpha" "altuve" "altuves" "amah" "amot" "ampere")
    return true
  if s in ("amperes" "amperes per square meter" "amphora" "amphorae" "amphoras" "angstrom" "angstroms" "angular acceleration" "angular velocity" "apgar" "apgar score" "apostilb")
    return true
  if s in ("apostilbs" "apparent magnitude" "arcmin" "arcsec" "areal density" "aroura" "arourae" "arouras" "arpent" "arpents" "arshin" "arshins")
    return true
  if s in ("asb" "astronomical unit" "astronomical units" "at" "atm" "atmosphere" "atmospheres" "attobarn" "attobarns" "au" "australian tablespoon" "australian tablespoons")
    return true
  if s in ("australian tbsp" "australian_tbsp" "b" "baker's dozen" "bakers dozen" "bakers_dozen" "ban" "banana" "banana for scale" "banana_for_scale" "bananas" "bananas for scale")
    return true
  if s in ("bar" "barleycorn" "barleycorns" "barn" "barn megaparsec" "barn-megaparsec" "barn-megaparsecs" "barns" "barrel" "barrel of oil equivalent" "barrels" "barye")
    return true
  if s in ("basis point" "basis points" "basis_point" "basis_points" "bath" "baths" "baud" "beard second" "beard seconds" "beard-second" "beard-seconds" "beat")
    return true
  if s in ("beats" "beats per minute" "beaufort" "becquerel" "becquerels" "beka" "bekah" "bekas" "biblical talent" "biblical_mil" "biblical_mina" "biblical_talent")
    return true
  if s in ("billions and billions" "bit" "bit/(s·Hz)" "bit/s/Hz" "bits" "bits per second per hertz" "block" "blocks" "boe" "bohr magneton" "bohr_magneton" "bohr_radius")
    return true
  if s in ("boiler horsepower" "boiler_horsepower" "bolometric magnitude" "bortle" "bottle" "bottles" "bp_finance" "bpm" "bps" "brad" "brads" "brinell")
    return true
  if s in ("bu" "bushel" "bushels" "butt" "byte" "bytes" "bytes per flop" "cP" "cSt" "cable" "cable length" "cable lengths")
    return true
  if s in ("cable_length" "cables" "cal" "calorie" "calories" "candela" "candela per square meter" "candelas" "carat" "carats" "catalytic activity concentration" "cd")
    return true
  if s in ("cd/m²" "celsius" "celsius difference" "cent" "cent_pitch" "centipoise" "centistokes" "cents" "centuries" "century" "ch" "chain")
    return true
  if s in ("chains" "charge density" "chelakim" "chelek" "chetvert" "chetverts" "chi" "chinese dan" "chinese li" "chinese_dan" "chinese_li" "chis")
    return true
  if s in ("cicero" "cloth nail" "cluster" "clusters" "cm" "cm-1" "cmH2O" "cm^-1" "cm²" "cm³" "cm⁻¹" "compton wavelength")
    return true
  if s in ("compton wavelength electron" "compton wavelength neutron" "compton wavelength proton" "compton_e" "compton_n" "compton_p" "compton_wavelength" "conductivity" "cord" "cords" "coulomb" "coulombs")
    return true
  if s in ("coulombs per cubic meter" "crumb" "crumbs" "css rem" "ct" "cubic meters per second" "cubit" "cubits" "cun" "cuns" "cup" "cups")
    return true
  if s in ("curie" "curies" "current density" "cwt" "cyc" "cycle" "cycles" "d" "dalton" "daltons" "dan_cn" "dash")
    return true
  if s in ("dashes" "day" "days" "debye" "debyes" "decade" "decades" "decay" "decays" "deciban" "decibans" "decitex")
    return true
  if s in ("deg" "degree" "degrees" "delisle" "delta celsius" "delta fahrenheit" "delta kelvin" "delta rankine" "denier" "deniers" "didot" "digit")
    return true
  if s in ("digits" "dit" "dits" "dog year" "dog years" "dogyear" "donkey power" "donkey-power" "donkeypower" "dots per inch" "dots per pixel" "dozen")
    return true
  if s in ("dozens" "dpi" "dppx" "dr" "drachm" "drams" "drop" "drops" "dword" "dwords" "dwt" "dyn")
    return true
  if s in ("dyne" "dynes" "eV" "earth mass" "earth radius" "earthmass" "earthradius" "egypt_palm" "egyptian palm" "egyptian palms" "electric field" "electric horsepower")
    return true
  if s in ("electric_horsepower" "electron mass" "electron_mass" "electronvolt" "electronvolts" "em" "en" "energy density" "english cubit" "english cubits" "english_cubit" "enhanced fujita")
    return true
  if s in ("entropy" "ephah" "ephahs" "ephas" "erg" "etzba" "etzbaot" "ev" "e₀" "f stop" "f-stop" "f-stops")
    return true
  if s in ("fL" "f_stop" "fahrenheit" "fahrenheit difference" "farad" "farads" "fathom" "fathoms" "fb-1" "fb^-1" "fbarn" "fbinv")
    return true
  if s in ("fb⁻¹" "feet" "feet of water" "femtobarn" "femtobarns" "fen" "fens" "fine structure constant" "fine_structure" "fingerbreadth" "firkin" "firkins")
    return true
  if s in ("fl dr" "fl oz" "fldr" "flop" "flops" "flops_count" "floz" "fluid dram" "fluid drams" "fluid ounce" "fluid ounces" "foot")
    return true
  if s in ("foot of water" "foot pound" "foot pounds" "foot-lambert" "foot-pound" "foot-pounds" "fortnight" "fortnights" "fps" "frame" "frames" "frames per second")
    return true
  if s in ("french gauge" "french_gauge" "fstop" "ft" "ft H2O" "ft of water" "ftH2O" "ftlbf" "ft²" "fujita" "fujita scale" "funt")
    return true
  if s in ("funt_ru" "fur" "furlong" "furlongs" "g" "g CO2e" "g0" "gCO₂e" "gCO₂e/kWh" "gCO₂e/pkm" "g_n" "gal")
    return true
  if s in ("gallon" "gallons" "gauss" "gaz" "gazes" "gee" "gerah" "gerahs" "gigaton" "gigatons" "gilbert" "gilberts")
    return true
  if s in ("gill" "gills" "gon" "googol" "googolplex" "googolplexes" "googols" "gos" "gr" "grad" "gradian" "gradians")
    return true
  if s in ("grain" "grains" "gram" "grams" "grams CO2e" "grape jelly" "grave" "gray" "grays" "great gross" "great_gross" "grid carbon intensity")
    return true
  if s in ("gross" "gō" "g₀" "h" "ha" "halakim" "half step" "halfstep" "hand" "handbreadth" "handbreadths" "hands")
    return true
  if s in ("hartley" "hartleys" "hartree" "hartrees" "hath" "haths" "heap" "heaps" "heat capacity" "heat flux" "heat_capacity" "hectare")
    return true
  if s in ("hectares" "helek" "henries" "henry" "henrys" "hertz" "hin" "hins" "hogshead" "hogsheads" "hole" "holes")
    return true
  if s in ("horsepower" "hounsfield" "hounsfield_unit" "hour" "hours" "hp" "imp gal" "imperial bottle" "imperial gallon" "imperial gallons" "imperial pint" "imperial pints")
    return true
  if s in ("imperial_pint" "impgal" "impulse" "in H2O" "in of water" "inH2O" "inHg" "inch" "inch of water" "inches" "inches of water" "indian kos")
    return true
  if s in ("instant" "instants" "instruction" "instructions" "inv_ab" "inv_fb" "inv_nb" "inv_pb" "inverse attobarn" "inverse femtobarn" "inverse nanobarn" "inverse picobarn")
    return true
  if s in ("io" "io_op" "io_ops" "iops" "ios" "isaron" "iso" "issaron" "iugera" "iugerum" "j" "jam")
    return true
  if s in ("janskies" "jansky" "janskys" "japanese cup" "japanese cups" "japanese_cup" "jelly" "jerk" "jeroboam" "jeroboams" "jiffies" "jiffy")
    return true
  if s in ("jigger" "jiggers" "jin" "jins" "jo" "jos" "joule" "joules" "joules per kelvin" "joules per operation" "joules per token" "jubilee")
    return true
  if s in ("jubilees" "jugerum" "julian year" "julian years" "julianyear" "jupiter mass" "jupitermass" "kFLOPS" "kHz" "kJ" "kPa" "kV")
    return true
  if s in ("kW" "kWh" "kab" "kabim" "kabs" "kanme" "kanmes" "kat" "kat/m³" "katal" "katals" "kayser")
    return true
  if s in ("kaysers" "kcal" "kelvin" "kelvin difference" "kflops" "kg" "kg CO2e" "kg/m" "kg/m²" "kg/m³" "kg/s" "kgCO₂e")
    return true
  if s in ("kgf" "kg·m/s" "khet" "khets" "kikar" "kilderkin" "kilderkins" "kilocalorie" "kilocalories" "kilogram" "kilogram force" "kilogram-force")
    return true
  if s in ("kilograms" "kilograms CO2e" "kilograms per cubic meter" "kilograms per second" "kiloton" "kilotons" "kilowarhol" "kilowarhols" "kilowatt hour" "kilowatt hours" "kilowatt-hour" "kilowatt-hours")
    return true
  if s in ("km" "km/h" "km²" "kn" "knot" "knots" "koku" "kokus" "kor" "korim" "kors" "kos")
    return true
  if s in ("kos_indian" "kph" "kt" "ktok/s" "l" "l/100km" "lambert" "lamberts" "lb" "lbf" "lbs" "league")
    return true
  if s in ("leagues" "li_cn" "liang" "liangs" "libra romana" "libra_roma" "lieue de poste" "lieue_de_poste" "lieues de poste" "light hour" "light hours" "light minute")
    return true
  if s in ("light minutes" "light nanosecond" "light second" "light seconds" "light year" "light years" "light-nanosecond" "light_nanosecond" "lighthour" "lighthours" "lightminute" "lightminutes")
    return true
  if s in ("lightsecond" "lightseconds" "lightyear" "lightyears" "linear density" "link" "link_chain" "links" "liter" "liters" "liters per 100 km" "liters per minute")
    return true
  if s in ("litre" "litres" "litres per minute" "lm" "lm·s" "long ton" "long tons" "lumen" "lumens" "luminous energy" "luminous exposure" "lunar month")
    return true
  if s in ("lunar months" "lunarmonth" "lustra" "lustrum" "lustrums" "lux" "lx" "lx·s" "ly" "m" "m H2O" "m of water")
    return true
  if s in ("m/s" "m/s²" "m/s³" "mA" "mH2O" "mL" "m_e" "m_n" "m_p" "m_μ" "mac" "mach")
    return true
  if s in ("mach_air_20C" "macs" "mag" "magnitude" "magnitudes" "magnum" "magnums" "maneh" "mass density" "mass flow" "maund" "maunds")
    return true
  if s in ("maxwell" "maxwells" "mbar" "megaton" "megatons" "melchizedek" "melchizedeks" "meter" "meter of water" "meters" "meters of water" "methuselah")
    return true
  if s in ("methuselahs" "metric cup" "metric cups" "metric tablespoon" "metric tablespoons" "metric tbsp" "metric ton" "metric tons" "metric_cup" "metric_tbsp" "mg" "mg/dL glucose")
    return true
  if s in ("mg/dL_glucose" "mho" "mi" "mi/h" "mickey" "mickeys" "microlife" "microlives" "micromort" "micromorts" "mil" "mile")
    return true
  if s in ("mile per hour" "miles" "miles per gallon" "miles per gallon equivalent" "miles per hour" "mill_finance" "mille passuum" "mille_passuum" "millennia" "millennium" "millenniums" "millihelen")
    return true
  if s in ("millihelens" "mils" "min" "mina" "minas" "minute" "minutes" "mm" "mmHg" "mmol/L glucose" "mmol/L_glucose" "mo")
    return true
  if s in ("mohs" "mol" "mol/mol" "molal" "molar" "mole" "mole fraction" "moles" "moment" "moment magnitude" "moment_magnitude" "moments")
    return true
  if s in ("momentum" "momme" "mommes" "month" "months" "moon mass" "moonmass" "mpg" "mpge" "mph" "ms" "mu")
    return true
  if s in ("muB" "muon mass" "muon_mass" "mus" "m²" "m³" "m³/(kg·s²)" "m³/s" "mₚₗ" "nail_cloth" "nanobarn" "nanobarns")
    return true
  if s in ("nat" "nats" "nautical mile" "nautical miles" "nb-1" "nb^-1" "nbarn" "nb⁻¹" "nebuchadnezzar" "nebuchadnezzars" "neutron mass" "neutron_mass")
    return true
  if s in ("newton" "newtons" "newtons per meter" "nibble" "nibbles" "nit" "nits" "nm" "nmi" "ns" "o" "octave")
    return true
  if s in ("octaves" "octet" "octets" "oersted" "oersteds" "ohm" "ohm meter" "ohms" "oil barrel" "oil barrels" "oil_barrel" "omer")
    return true
  if s in ("omers" "onah" "onot" "op" "ops" "ops_per_s" "ounce" "ounces" "outhouse" "oz" "ozt" "packet")
    return true
  if s in ("packets" "page" "pages" "paragraph" "paragraphs" "parsa" "parsec" "parsecs" "parts per billion" "parts per hundred million" "parts per million" "parts per trillion")
    return true
  if s in ("parts-per-billion" "parts-per-million" "parts-per-trillion" "pascal" "pascals" "passus" "passuses" "pb" "pb-1" "pb^-1" "pbarn" "pb⁻¹")
    return true
  if s in ("pc" "peanut butter" "peanutbutter" "peck" "pecks" "pedes" "pennyweight" "pennyweights" "perch" "perches" "person hour" "person hours")
    return true
  if s in ("person_hour" "pes" "petabyte" "petabytes" "petroleum barrel" "petroleum_barrel" "phon" "phons" "pica" "picas" "piccolo" "picobarn")
    return true
  if s in ("picobarns" "pied" "pied du roi" "pieds" "pieds du roi" "pieze" "pinch" "pinches" "pint" "pints" "pip" "pipe")
    return true
  if s in ("pipes" "pips" "pixel" "pixels" "pk" "planck length" "planck mass" "planck time" "pm" "point" "points" "poise")
    return true
  if s in ("pouce" "pouces" "pound" "pound force" "pound-force" "pounds" "ppb" "pphm" "ppm" "pps" "ppt" "proton mass")
    return true
  if s in ("proton_mass" "ps" "psi" "pt" "pud" "puds" "puncheon" "puncheons" "px" "qps" "qquad" "qr")
    return true
  if s in ("qt" "quad" "quality adjusted life year" "quality-adjusted life year" "quart" "quarter" "quarters" "quarts" "queries" "query" "quintal" "quintals")
    return true
  if s in ("qword" "qwords" "rack unit" "rack units" "rad" "rad/s" "rad/s²" "radian" "radians" "rankine" "rankine difference" "rbe")
    return true
  if s in ("rd" "reaumur" "rega" "regaim" "rehoboam" "relative biological effectiveness" "rem" "rem_css" "rems" "request" "requests" "resistivity")
    return true
  if s in ("rev" "revolution" "revolutions" "revolutions per minute" "revs" "ri" "richter" "richter scale" "rockwell" "rod" "rods" "roman libra")
    return true
  if s in ("roman mile" "roman uncia" "romer" "rope" "ropes" "rot" "rotation" "rotations" "rotations per minute" "royal cubit" "royal cubits" "royal_cubit")
    return true
  if s in ("rpm" "rps" "rundlet" "rundlets" "russian funt" "russian_funt" "rutherford" "rutherfords" "rydberg" "rydberg_unit" "rydbergs" "réaumur")
    return true
  if s in ("rømer" "s" "sabbath day's journey" "sabbatical" "saffir simpson" "saffir_simpson" "sagan" "sagans" "sample" "samples" "savart" "savarts")
    return true
  if s in ("sazhen" "sazhens" "sb" "score" "scores" "scruple" "scruples" "seah" "seahs" "second" "seconds" "sector")
    return true
  if s in ("sectors" "seer" "seers" "seim" "semitone" "semitones" "shaftment" "shaftments" "shake" "shakes" "shaku" "shakus")
    return true
  if s in ("shed" "shekalim" "shekel" "shekels" "shmita" "shmitas" "shmitta" "short ton" "short tons" "sidereal day" "sidereal days" "sidereal year")
    return true
  if s in ("sidereal years" "siderealday" "siderealyear" "siemens" "siemens per meter" "sievert" "sieverts" "sk" "skot" "skots" "slug" "slugs")
    return true
  if s in ("smidgen" "smidgens" "smoot" "smoots" "solar mass" "solar radius" "solarmass" "solarradius" "sone" "sones" "span" "spans")
    return true
  if s in ("specific energy" "specific heat capacity" "specific_energy" "spectral efficiency" "split" "splits" "sq ft" "sqft" "sqm" "square feet" "square foot" "sr")
    return true
  if s in ("st" "standard gravity" "steradian" "steradians" "stere" "stick" "stick of butter" "sticks" "sticks of butter" "stilb" "stilbs" "stokes")
    return true
  if s in ("stone" "stones" "stop" "stops" "story point" "story points" "story_point" "stère" "stères" "sun" "suns" "surface tension")
    return true
  if s in ("synodic month" "synodic months" "t" "tablespoon" "tablespoons" "talent" "talents" "talmudic mil" "talmudic_mil" "tatami" "tatamis" "tbsp")
    return true
  if s in ("tce" "teaspoon" "teaspoons" "techum" "techum shabbat" "tefach" "tefachim" "tenth cent" "tenth_cent" "tertian" "tesla" "teslas")
    return true
  if s in ("tex" "texpt" "therm" "thermal conductivity" "therms" "tick" "ticks" "tierce" "tierces" "tn" "toise" "toises")
    return true
  if s in ("tok" "tok/s" "token" "tokens" "tola" "tolas" "ton" "tonne" "tonne of coal equivalent" "tonnes" "tons" "torque")
    return true
  if s in ("torr" "torrs" "tps" "transaction" "transactions" "transfer" "transfers" "transport carbon intensity" "tropical year" "tropical years" "tropicalyear" "troy ounce")
    return true
  if s in ("troy ounces" "troyounce" "tsp" "tsubo" "tsubos" "tun" "tuns" "turn" "turns" "txn" "tₚ" "u")
    return true
  if s in ("uncia_roma" "vershok" "vershoks" "verst" "versts" "vh" "vickers" "viewport height" "viewport width" "volt" "volts" "volts per meter")
    return true
  if s in ("volumetric flow" "vw" "warhol" "warhols" "water horsepower" "water_horsepower" "watt" "watts" "watts per square meter" "wavenumber" "weber" "webers")
    return true
  if s in ("wedgwood" "week" "weeks" "wk" "yard" "yards" "yd" "year" "years" "yovel" "yovels" "yr")
    return true
  if s in ("zeret" "zhang" "zhangs" "°" "°C" "°De" "°F" "°N" "°R" "°Ra" "°Re" "°Ré")
    return true
  if s in ("°Rø" "°W" "°r" "µA" "µg" "µm" "µs" "Å" "ångström" "ɡ" "ʒ" "ΔK")
    return true
  if s in ("Δ°C" "Δ°De" "Δ°F" "Δ°N" "Δ°R" "Δ°Ré" "Δ°Rø" "Δ°W" "Ω" "Ω·m" "α" "μ_B")
    return true
  if s in ("μlife" "μmort" "℃" "℈" "℉" "ℓₚ" "℔" "℥" "℧" "㍳")
    return true
  false

# --- END GENERATED: regex_known_unit_name ---
