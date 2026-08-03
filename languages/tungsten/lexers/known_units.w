# Shared generated membership table for the self-hosted reference lexer.
# Regenerate with: ruby scripts/gen_units.rb --write

# --- BEGIN GENERATED: regex_known_unit_name ---
-> regex_known_unit_name?(s)
  if s in ("1/mol" "A" "A/m²" "AU tbsp" "Ah" "Apgar" "B" "B/flop" "B/s" "BOE" "BPM" "BTU")
    return true
  if s in ("Ba" "Beaufort" "Bortle" "Bps" "Bq" "Bq/kg" "Bq/m³" "C" "C/m³" "CFU" "CFU/mL" "CFUs")
    return true
  if s in ("CWT" "Ci" "D" "DMIPS" "DU" "DWORD" "Da" "E" "EA" "EB" "EBps" "EBq")
    return true
  if s in ("EC" "EDa" "EF" "EF-scale" "EFLOPS" "EGy" "EH" "EHz" "EJ" "EJy" "EK" "EL")
    return true
  if s in ("EN" "EOPS" "EPa" "ES" "ESv" "ET" "EV" "EVA" "EW" "EWb" "Eb" "Ebps")
    return true
  if s in ("Ecd" "Ecentury" "EeV" "Eflops" "Efortnight" "Eg" "Eh" "EiB" "Eib" "Ekat" "El" "Elm")
    return true
  if s in ("Elx" "Em" "Emol" "Eotvos" "Epc" "Eq" "Eq/L" "Es" "Et" "Evar" "Eötvös" "EΩ")
    return true
  if s in ("F" "F-scale" "F/m" "FLOPS" "FPS" "Fr_catheter" "GA" "GB" "GB/s" "GBps" "GBq" "GC")
    return true
  if s in ("GDa" "GF" "GFLOPS" "GGy" "GH" "GHz" "GIPS" "GJ" "GJy" "GK" "GL" "GMAC/s")
    return true
  if s in ("GN" "GOPS" "GPa" "GS" "GSv" "GT" "GT/s" "GUPS" "GV" "GVA" "GW" "GWb")
    return true
  if s in ("Ga" "Gal" "Gb" "Gb/s" "Gbps" "Gcd" "Gcentury" "GeV" "Gflops" "Gfortnight" "Gg" "GiB")
    return true
  if s in ("GiB/s" "Gib" "Gkat" "Gl" "Glm" "Glx" "Gm" "Gmol" "Gpc" "Gs" "Gt" "Gtok/s")
    return true
  if s in ("Gvar" "Gy" "Gy/s" "GΩ" "H" "HB" "HRC" "HU" "HV" "Hz" "IOPS" "ISO")
    return true
  if s in ("ISO sensitivity" "ISO_speed" "IU" "IU/mL" "J" "J/(kg·K)" "J/(mol·K)" "J/K" "J/kg" "J/kg/K" "J/m²" "J/m³")
    return true
  if s in ("J/op" "J/tok" "Jy" "J·s" "K" "KB" "KOPS" "KiB" "Kib" "L" "L per 100 km" "L/100km")
    return true
  if s in ("L/min" "LT" "L_sun_nominal" "La" "L☉_N" "M" "MA" "MAC/s" "MB" "MB/s" "MBps" "MBq")
    return true
  if s in ("MC" "MDa" "MF" "MFLOPS" "MGy" "MH" "MHz" "MIPS" "MJ" "MJy" "MK" "ML")
    return true
  if s in ("MMAC/s" "MN" "MOPS" "MPG" "MPGe" "MPa" "MS" "MSv" "MT" "MT/s" "MV" "MVA")
    return true
  if s in ("MW" "MWb" "MWh" "M_bol" "Mach at 20 C" "Mach in air at 20 C" "Mag" "Mb" "Mb/s" "Mbol" "Mbps" "Mcd")
    return true
  if s in ("Mcentury" "MeV" "Mflops" "Mfortnight" "Mg" "MiB" "MiB/s" "Mib" "Mkat" "Ml" "Mlm" "Mlx")
    return true
  if s in ("Mm" "Mmol" "Mohs" "Mpc" "Ms" "Mt" "Mtok/s" "Mvar" "Mw" "Mx" "MΩ" "M⊕")
    return true
  if s in ("M☉" "M☽" "M♃" "N" "N/A²" "N/m" "N·m" "N·s" "Oe" "Osm/L" "P" "PA")
    return true
  if s in ("PB" "PBps" "PBq" "PC" "PDa" "PF" "PFLOPS" "PFU" "PFU/mL" "PFUs" "PGy" "PH")
    return true
  if s in ("PHz" "PJ" "PJy" "PK" "PL" "PN" "POPS" "PPFD" "PPS" "PPa" "PS" "PSv")
    return true
  if s in ("PT" "PV" "PVA" "PVU" "PW" "PWb" "Pa" "Pb" "Pbps" "Pcd" "Pcentury" "PeV")
    return true
  if s in ("Pflops" "Pfortnight" "Pg" "PiB" "Pib" "Pkat" "Pl" "Planck length" "Planck mass" "Planck time" "Plm" "Plx")
    return true
  if s in ("Pm" "Pmol" "Ppc" "Ps" "Pt" "Pvar" "PΩ" "QA" "QALY" "QALYs" "QB" "QBps")
    return true
  if s in ("QBq" "QC" "QDa" "QF" "QGy" "QH" "QHz" "QJ" "QJy" "QK" "QL" "QN")
    return true
  if s in ("QPS" "QPa" "QS" "QSv" "QT" "QV" "QVA" "QW" "QWORD" "QWb" "Qb" "Qbps")
    return true
  if s in ("Qcd" "Qcentury" "QeV" "Qfortnight" "Qg" "QiB" "Qib" "Qkat" "Ql" "Qlm" "Qlx" "Qm")
    return true
  if s in ("Qmol" "Qpc" "Qs" "Qt" "Qvar" "QΩ" "RA" "RB" "RBE" "RBps" "RBq" "RC")
    return true
  if s in ("RDa" "RF" "RGy" "RH" "RHz" "RJ" "RJy" "RK" "RL" "RN" "RPS" "RPa")
    return true
  if s in ("RS" "RSv" "RT" "RU" "RV" "RVA" "RW" "RWb" "R_exposure" "R_sun_nominal" "Rb" "Rbps")
    return true
  if s in ("Rcd" "Rcentury" "ReV" "Rfortnight" "Rg" "RiB" "Rib" "Richter" "Rkat" "Rl" "Rlm" "Rlx")
    return true
  if s in ("Rm" "Rmol" "Rpc" "Rs" "Rt" "Rvar" "Ry" "RΩ" "R⊕" "R☉" "R☉_N" "S")
    return true
  if s in ("S/m" "SS_category" "Saffir-Simpson" "St" "Sv" "Sv/h" "Sv_ocean" "Svedberg" "T" "T/s" "TA" "TB")
    return true
  if s in ("TBps" "TBq" "TC" "TCE" "TDa" "TECU" "TEPS" "TF" "TFLOPS" "TGy" "TH" "THz")
    return true
  if s in ("TJ" "TJy" "TK" "TL" "TMAC/s" "TN" "TOPS" "TPS" "TPa" "TS" "TSv" "TT")
    return true
  if s in ("TT/s" "TV" "TVA" "TW" "TWb" "Tb" "Tbps" "Tcd" "Tcentury" "TeV" "Tflops" "Tfortnight")
    return true
  if s in ("Tg" "TiB" "Tib" "Tkat" "Tl" "Tlm" "Tlx" "Tm" "Tmol" "Torr" "Tpc" "Ts")
    return true
  if s in ("Tt" "Tvar" "TΩ" "U/L" "U_enzyme" "V" "V/m" "VA" "W" "W/(m²·K⁴)" "W/(m·K)" "W/m/K")
    return true
  if s in ("W/m²" "W/m²/Hz" "W/m³" "W/sr" "W/sr/m²" "Wb" "YA" "YB" "YBps" "YBq" "YC" "YDa")
    return true
  if s in ("YF" "YFLOPS" "YGy" "YH" "YHz" "YJ" "YJy" "YK" "YL" "YN" "YPa" "YS")
    return true
  if s in ("YSv" "YT" "YV" "YVA" "YW" "YWb" "Yb" "Ybps" "Ycd" "Ycentury" "YeV" "Yflops")
    return true
  if s in ("Yfortnight" "Yg" "YiB" "Yib" "Ykat" "Yl" "Ylm" "Ylx" "Ym" "Ymol" "Ypc" "Ys")
    return true
  if s in ("Yt" "Yvar" "YΩ" "ZA" "ZB" "ZBps" "ZBq" "ZC" "ZDa" "ZF" "ZFLOPS" "ZGy")
    return true
  if s in ("ZH" "ZHz" "ZJ" "ZJy" "ZK" "ZL" "ZN" "ZPa" "ZS" "ZSv" "ZT" "ZV")
    return true
  if s in ("ZVA" "ZW" "ZWb" "Zb" "Zbps" "Zcd" "Zcentury" "ZeV" "Zflops" "Zfortnight" "Zg" "ZiB")
    return true
  if s in ("Zib" "Zkat" "Zl" "Zlm" "Zlx" "Zm" "Zmol" "Zpc" "Zs" "Zt" "Zvar" "ZΩ")
    return true
  if s in ("a0" "aA" "aB" "aBps" "aBq" "aC" "aDa" "aF" "aGy" "aH" "aHz" "aJ")
    return true
  if s in ("aJy" "aK" "aL" "aN" "aPa" "aS" "aSv" "aT" "aV" "aVA" "aW" "aWb")
    return true
  if s in ("a_0" "ab" "ab-1" "abA" "abC" "abF" "abH" "abV" "ab^-1" "abampere" "abarn" "abcoulomb")
    return true
  if s in ("abfarad" "abhenry" "abinv" "abohm" "abps" "absolute magnitude" "absorbed-dose rad" "abvolt" "abΩ" "ab⁻¹" "ac" "acd")
    return true
  if s in ("acentury" "acre" "acres" "aeV" "afortnight" "ag" "akat" "al" "alm" "alpha" "altuve" "altuves")
    return true
  if s in ("alx" "am" "amah" "amol" "amot" "amp hours" "ampere" "ampere hour" "ampere-hour" "amperes" "amperes per square meter" "amphora")
    return true
  if s in ("amphorae" "amphoras" "angstrom" "angstroms" "angular acceleration" "angular velocity" "apc" "apgar" "apgar score" "apostilb" "apostilbs" "apparent magnitude")
    return true
  if s in ("arcmin" "arcsec" "areal density" "aroura" "arourae" "arouras" "arpent" "arpents" "arshin" "arshins" "as" "asb")
    return true
  if s in ("astronomical unit" "astronomical units" "at" "atm" "atmosphere" "atmospheres" "attobarn" "attobarns" "au" "australian tablespoon" "australian tablespoons" "australian tbsp")
    return true
  if s in ("australian_tbsp" "avar" "aΩ" "b" "baker's dozen" "bakers dozen" "bakers_dozen" "ban" "banana" "banana for scale" "banana_for_scale" "bananas")
    return true
  if s in ("bananas for scale" "bar" "barleycorn" "barleycorns" "barn" "barn megaparsec" "barn-megaparsec" "barn-megaparsecs" "barns" "barrel" "barrel of oil equivalent" "barrels")
    return true
  if s in ("barye" "basis point" "basis points" "basis_point" "basis_points" "bath" "baths" "baud" "beard second" "beard seconds" "beard-second" "beard-seconds")
    return true
  if s in ("beat" "beats" "beats per minute" "beaufort" "becquerel" "becquerels" "beka" "bekah" "bekas" "biblical talent" "biblical_mil" "biblical_mina")
    return true
  if s in ("biblical_talent" "billions and billions" "biot" "bit" "bit/(s·Hz)" "bit/s" "bit/s/Hz" "bit/symbol" "bits" "bits per second per hertz" "bits per symbol" "block")
    return true
  if s in ("blocks" "boe" "bohr magneton" "bohr_magneton" "bohr_radius" "boiler horsepower" "boiler_horsepower" "bolometric magnitude" "bortle" "bottle" "bottles" "bp_finance")
    return true
  if s in ("bpm" "bps" "brad" "brads" "brinell" "bu" "bushel" "bushels" "butt" "byte" "bytes" "bytes per flop")
    return true
  if s in ("cA" "cB" "cBps" "cBq" "cC" "cDa" "cF" "cGy" "cH" "cHz" "cJ" "cJy")
    return true
  if s in ("cK" "cL" "cN" "cP" "cPa" "cS" "cSt" "cSv" "cT" "cV" "cVA" "cW")
    return true
  if s in ("cWb" "cable" "cable length" "cable lengths" "cable_length" "cables" "cal" "cal_IT" "cal_th" "calorie" "calorie IT" "calories")
    return true
  if s in ("candela" "candela per square meter" "candelas" "carat" "carats" "catalytic activity concentration" "cb" "cbps" "ccd" "ccentury" "cd" "cd/m²")
    return true
  if s in ("ceV" "cell" "cells" "cells/mL" "celsius" "celsius difference" "cent" "cent_pitch" "centipoise" "centistokes" "cents" "centuries")
    return true
  if s in ("century" "cfortnight" "cg" "ch" "chain" "chains" "charge density" "chelakim" "chelek" "chetvert" "chetverts" "chi")
    return true
  if s in ("chinese dan" "chinese li" "chinese_dan" "chinese_li" "chis" "cicero" "ckat" "cl" "clm" "clo" "clo unit" "cloth nail")
    return true
  if s in ("cluster" "clusters" "clx" "cm" "cm-1" "cmH2O" "cm^-1" "cmol" "cm²" "cm³" "cm⁻¹" "colony forming unit")
    return true
  if s in ("colony-forming unit" "compton wavelength" "compton wavelength electron" "compton wavelength neutron" "compton wavelength proton" "compton_e" "compton_n" "compton_p" "compton_wavelength" "conductivity" "copies" "copies/mL")
    return true
  if s in ("copy" "cord" "cords" "coulomb" "coulombs" "coulombs per cubic meter" "count" "counts per minute" "counts per second" "cpc" "cpm" "cps")
    return true
  if s in ("crumb" "crumbs" "cs" "css rem" "ct" "cubic meters per second" "cubit" "cubits" "cun" "cuns" "cup" "cups")
    return true
  if s in ("curie" "curies" "current density" "cvar" "cwt" "cyc" "cycle" "cycles" "cΩ" "d" "dA" "dB")
    return true
  if s in ("dBps" "dBq" "dC" "dDa" "dF" "dGy" "dH" "dHz" "dJ" "dJy" "dK" "dL")
    return true
  if s in ("dN" "dPa" "dS" "dSv" "dT" "dV" "dVA" "dW" "dWb" "daA" "daB" "daBps")
    return true
  if s in ("daBq" "daC" "daDa" "daF" "daGy" "daH" "daHz" "daJ" "daJy" "daK" "daL" "daN")
    return true
  if s in ("daPa" "daS" "daSv" "daT" "daV" "daVA" "daW" "daWb" "dab" "dabps" "dacd" "dacentury")
    return true
  if s in ("daeV" "dafortnight" "dag" "dakat" "dal" "dalm" "dalton" "daltons" "dalx" "dam" "damol" "dan_cn")
    return true
  if s in ("dapc" "darcies" "darcy" "das" "dash" "dashes" "dat" "davar" "day" "days" "daΩ" "db")
    return true
  if s in ("dbps" "dcd" "dcentury" "deV" "debye" "debyes" "decade" "decades" "decay" "decays" "decays per minute" "deciban")
    return true
  if s in ("decibans" "decitex" "deg" "degree" "degrees" "delisle" "delta celsius" "delta fahrenheit" "delta kelvin" "delta rankine" "denier" "deniers")
    return true
  if s in ("dfortnight" "dg" "didot" "digit" "digits" "diopter" "diopters" "dioptre" "dioptres" "dit" "dits" "dkat")
    return true
  if s in ("dl" "dlm" "dlx" "dm" "dmol" "dobson unit" "dobson units" "dog year" "dog years" "dogyear" "donkey power" "donkey-power")
    return true
  if s in ("donkeypower" "dots per inch" "dots per pixel" "dozen" "dozens" "dpc" "dpi" "dpm" "dppx" "dr" "drachm" "drams")
    return true
  if s in ("drop" "drops" "ds" "dt" "dvar" "dword" "dwords" "dwt" "dyn" "dyne" "dynes" "dΩ")
    return true
  if s in ("eV" "earth mass" "earth radius" "earthmass" "earthradius" "edge" "edges" "egypt_palm" "egyptian palm" "egyptian palms" "einstein" "einsteins")
    return true
  if s in ("electric field" "electric horsepower" "electric_horsepower" "electron mass" "electron_mass" "electronvolt" "electronvolts" "em" "en" "energy density" "english cubit" "english cubits")
    return true
  if s in ("english_cubit" "enhanced fujita" "entropy" "enzyme unit" "enzyme units" "eotvos" "ephah" "ephahs" "ephas" "equivalent" "equivalents" "erg")
    return true
  if s in ("etzba" "etzbaot" "ev" "e₀" "f stop" "f-stop" "f-stops" "fA" "fB" "fBps" "fBq" "fC")
    return true
  if s in ("fDa" "fF" "fGy" "fH" "fHz" "fJ" "fJy" "fK" "fL" "fN" "fPa" "fS")
    return true
  if s in ("fSv" "fT" "fV" "fVA" "fW" "fWb" "f_stop" "fahrenheit" "fahrenheit difference" "farad" "farads" "fathom")
    return true
  if s in ("fathoms" "fb" "fb-1" "fb^-1" "fbarn" "fbinv" "fbps" "fb⁻¹" "fc" "fcd" "fcentury" "feV")
    return true
  if s in ("feet" "feet of water" "femtobarn" "femtobarns" "fen" "fens" "ffortnight" "fg" "fine structure constant" "fine_structure" "fingerbreadth" "firkin")
    return true
  if s in ("firkins" "fkat" "fl" "fl dr" "fl oz" "fldr" "flm" "flop" "flop/J" "flops" "flops per joule" "flops_count")
    return true
  if s in ("floz" "fluid dram" "fluid drams" "fluid ounce" "fluid ounces" "flx" "fm" "fmol" "foe" "foes" "foot" "foot candle")
    return true
  if s in ("foot candles" "foot of water" "foot pound" "foot pounds" "foot-candle" "foot-lambert" "foot-pound" "foot-pounds" "fortnight" "fortnights" "fpc" "fps")
    return true
  if s in ("frame" "frames" "frames per second" "franklin" "french gauge" "french_gauge" "fs" "fstop" "ft" "ft H2O" "ft of water" "ftH2O")
    return true
  if s in ("ftlbf" "ft²" "fujita" "fujita scale" "funt" "funt_ru" "fur" "furlong" "furlongs" "fvar" "fΩ" "g")
    return true
  if s in ("g CO2e" "g/L" "g/dL" "g0" "gCO₂e" "gCO₂e/kWh" "gCO₂e/pkm" "g_n" "gal" "gallon" "gallons" "gauss")
    return true
  if s in ("gaz" "gazes" "gee" "geopotential meter" "geopotential metre" "gerah" "gerahs" "giga-updates per second" "gigaton" "gigatons" "gilbert" "gilberts")
    return true
  if s in ("gill" "gills" "gon" "googol" "googolplex" "googolplexes" "googols" "gos" "gpm" "gr" "grad" "gradian")
    return true
  if s in ("gradians" "grain" "grains" "gram" "grams" "grams CO2e" "grape jelly" "grave" "gray" "grays" "great gross" "great_gross")
    return true
  if s in ("grid carbon intensity" "gross" "gō" "g₀" "h" "hA" "hB" "hBps" "hBq" "hC" "hDa" "hF")
    return true
  if s in ("hGy" "hH" "hHz" "hJ" "hJy" "hK" "hL" "hN" "hPa" "hS" "hSv" "hT")
    return true
  if s in ("hV" "hVA" "hW" "hWb" "ha" "halakim" "half step" "halfstep" "hand" "handbreadth" "handbreadths" "hands")
    return true
  if s in ("hartley" "hartleys" "hartree" "hartrees" "hath" "haths" "hb" "hbps" "hcd" "hcentury" "heV" "heap")
    return true
  if s in ("heaps" "heat capacity" "heat flux" "heat_capacity" "hectare" "hectares" "helek" "henries" "henry" "henrys" "hertz" "hfortnight")
    return true
  if s in ("hg" "hin" "hins" "hkat" "hl" "hlm" "hlx" "hm" "hmol" "hogshead" "hogsheads" "hole")
    return true
  if s in ("holes" "horsepower" "hounsfield" "hounsfield_unit" "hour" "hours" "hp" "hpc" "hs" "ht" "hvar" "hΩ")
    return true
  if s in ("imp gal" "imperial bottle" "imperial gallon" "imperial gallons" "imperial pint" "imperial pints" "imperial_pint" "impgal" "impulse" "in H2O" "in of water" "inH2O")
    return true
  if s in ("inHg" "inch" "inch of water" "inches" "inches of water" "indian kos" "instant" "instants" "instruction" "instructions" "international table calorie" "international unit")
    return true
  if s in ("international units" "inv_ab" "inv_fb" "inv_nb" "inv_pb" "inverse attobarn" "inverse femtobarn" "inverse nanobarn" "inverse picobarn" "io" "io_op" "io_ops")
    return true
  if s in ("iops" "ios" "isaron" "iso" "issaron" "iugera" "iugerum" "j" "jam" "janskies" "jansky" "janskys")
    return true
  if s in ("japanese cup" "japanese cups" "japanese_cup" "jelly" "jerk" "jeroboam" "jeroboams" "jiffies" "jiffy" "jigger" "jiggers" "jin")
    return true
  if s in ("jins" "jo" "jos" "joule" "joules" "joules per kelvin" "joules per operation" "joules per token" "jubilee" "jubilees" "jugerum" "julian year")
    return true
  if s in ("julian years" "julianyear" "jupiter mass" "jupitermass" "kA" "kB" "kBps" "kBq" "kC" "kDa" "kF" "kFLOPS")
    return true
  if s in ("kGy" "kH" "kHz" "kJ" "kJy" "kK" "kL" "kN" "kPa" "kS" "kSv" "kT")
    return true
  if s in ("kV" "kVA" "kW" "kWb" "kWh" "kab" "kabim" "kabs" "kanme" "kanmes" "kat" "kat/m³")
    return true
  if s in ("katal" "katals" "kayser" "kaysers" "kb" "kbps" "kcal" "kcal_IT" "kcal_th" "kcd" "kcentury" "keV")
    return true
  if s in ("kelvin" "kelvin difference" "kflops" "kfortnight" "kg" "kg CO2e" "kg/m" "kg/m²" "kg/m³" "kg/s" "kgCO₂e" "kgf")
    return true
  if s in ("kg·m/s" "khet" "khets" "kikar" "kilderkin" "kilderkins" "kilocalorie" "kilocalories" "kilogram" "kilogram force" "kilogram-force" "kilograms")
    return true
  if s in ("kilograms CO2e" "kilograms per cubic meter" "kilograms per second" "kiloton" "kilotons" "kilowarhol" "kilowarhols" "kilowatt hour" "kilowatt hours" "kilowatt-hour" "kilowatt-hours" "kkat")
    return true
  if s in ("kl" "klm" "klx" "km" "km/h" "kmol" "km²" "kn" "knot" "knots" "koku" "kokus")
    return true
  if s in ("kor" "korim" "kors" "kos" "kos_indian" "kpc" "kph" "ks" "kt" "ktok/s" "kvar" "kΩ")
    return true
  if s in ("l" "l/100km" "lambert" "lamberts" "lb" "lbf" "lbs" "league" "leagues" "li_cn" "liang" "liangs")
    return true
  if s in ("libra romana" "libra_roma" "lieue de poste" "lieue_de_poste" "lieues de poste" "light hour" "light hours" "light minute" "light minutes" "light nanosecond" "light second" "light seconds")
    return true
  if s in ("light year" "light years" "light-nanosecond" "light_nanosecond" "lighthour" "lighthours" "lightminute" "lightminutes" "lightsecond" "lightseconds" "lightyear" "lightyears")
    return true
  if s in ("linear density" "link" "link_chain" "links" "liter" "liters" "liters per 100 km" "liters per minute" "litre" "litres" "litres per minute" "lm")
    return true
  if s in ("lm·s" "long ton" "long tons" "lumen" "lumens" "luminous energy" "luminous exposure" "lunar month" "lunar months" "lunarmonth" "lustra" "lustrum")
    return true
  if s in ("lustrums" "lux" "lx" "lx·s" "ly" "m" "m H2O" "m of water" "m/s" "m/s²" "m/s³" "mA")
    return true
  if s in ("mB" "mBps" "mBq" "mC" "mDa" "mEq/L" "mF" "mGal" "mGy" "mH" "mH2O" "mHz")
    return true
  if s in ("mJ" "mJy" "mK" "mL" "mM" "mN" "mOsm/L" "mPa" "mS" "mSv" "mT" "mV")
    return true
  if s in ("mVA" "mW" "mWb" "m_e" "m_n" "m_p" "m_μ" "mac" "mach" "mach_air_20C" "macs" "mag")
    return true
  if s in ("magnitude" "magnitudes" "magnum" "magnums" "maneh" "mas" "mass density" "mass flow" "maund" "maunds" "maxwell" "maxwells")
    return true
  if s in ("mb" "mbar" "mbps" "mcd" "mcentury" "meV" "megaton" "megatons" "melchizedek" "melchizedeks" "meter" "meter of water")
    return true
  if s in ("meters" "meters of water" "methuselah" "methuselahs" "metric cup" "metric cups" "metric tablespoon" "metric tablespoons" "metric tbsp" "metric ton" "metric tons" "metric_cup")
    return true
  if s in ("metric_tbsp" "mfortnight" "mg" "mg/L" "mg/dL" "mg/dL glucose" "mg/dL_glucose" "mho" "mi" "mi/h" "mickey" "mickeys")
    return true
  if s in ("microarcsecond" "microarcseconds" "microlife" "microlives" "micromolar" "micromort" "micromorts" "mil" "mile" "mile per hour" "miles" "miles per gallon")
    return true
  if s in ("miles per gallon equivalent" "miles per hour" "mill_finance" "mille passuum" "mille_passuum" "millennia" "millennium" "millenniums" "milliarcsecond" "milliarcseconds" "milligal" "milligals")
    return true
  if s in ("millihelen" "millihelens" "millimolar" "mils" "min" "mina" "minas" "minute" "minutes" "mkat" "ml" "mlm")
    return true
  if s in ("mlx" "mm" "mmHg" "mmol" "mmol/L" "mmol/L glucose" "mmol/L_glucose" "mo" "mohs" "mol" "mol/L" "mol/mol")
    return true
  if s in ("mol/m³" "mol_photon/m²/s" "molal" "molar" "molar concentration" "molarity" "mole" "mole fraction" "moles" "moment" "moment magnitude" "moment_magnitude")
    return true
  if s in ("moments" "momentum" "momme" "mommes" "month" "months" "moon mass" "moonmass" "mpc" "mpg" "mpge" "mph")
    return true
  if s in ("ms" "mt" "mu" "muB" "muon mass" "muon_mass" "mus" "mvar" "m²" "m³" "m³/(kg·s²)" "m³/s")
    return true
  if s in ("mΩ" "mₚₗ" "nA" "nB" "nBps" "nBq" "nC" "nDa" "nF" "nGy" "nH" "nHz")
    return true
  if s in ("nJ" "nJy" "nK" "nL" "nM" "nN" "nPa" "nS" "nSv" "nT" "nV" "nVA")
    return true
  if s in ("nW" "nWb" "nail_cloth" "nanobarn" "nanobarns" "nanomolar" "nat" "nats" "nautical mile" "nautical miles" "nb" "nb-1")
    return true
  if s in ("nb^-1" "nbarn" "nbps" "nb⁻¹" "ncd" "ncentury" "neV" "nebuchadnezzar" "nebuchadnezzars" "neutron mass" "neutron_mass" "newton")
    return true
  if s in ("newtons" "newtons per meter" "nfortnight" "ng" "ng/mL" "nibble" "nibbles" "nit" "nits" "nkat" "nl" "nlm")
    return true
  if s in ("nlx" "nm" "nmi" "nmol" "nmol/L" "nominal solar luminosity" "nominal solar radius" "normality" "npc" "ns" "nt" "nvar")
    return true
  if s in ("nΩ" "o" "octave" "octaves" "octet" "octets" "oersted" "oersteds" "ohm" "ohm meter" "ohms" "oil barrel")
    return true
  if s in ("oil barrels" "oil_barrel" "omer" "omers" "onah" "onot" "op" "op/J" "operations per joule" "ops" "ops_per_s" "osmol")
    return true
  if s in ("osmolar" "osmole" "osmoles" "ounce" "ounces" "outhouse" "oz" "ozt" "pA" "pB" "pBps" "pBq")
    return true
  if s in ("pC" "pDa" "pF" "pGy" "pH" "pHz" "pJ" "pJy" "pK" "pL" "pN" "pPa")
    return true
  if s in ("pS" "pSv" "pT" "pV" "pVA" "pW" "pWb" "packet" "packets" "page" "pages" "paragraph")
    return true
  if s in ("paragraphs" "parsa" "parsec" "parsecs" "parts per billion" "parts per billion by volume" "parts per hundred million" "parts per million" "parts per million by mass" "parts per million by volume" "parts per trillion" "parts-per-billion")
    return true
  if s in ("parts-per-million" "parts-per-trillion" "pascal" "pascals" "passus" "passuses" "pb" "pb-1" "pb^-1" "pbarn" "pbps" "pb⁻¹")
    return true
  if s in ("pc" "pcd" "pcentury" "peV" "peanut butter" "peanutbutter" "peck" "pecks" "pedes" "pennyweight" "pennyweights" "perch")
    return true
  if s in ("perches" "person hour" "person hours" "person_hour" "pes" "petabyte" "petabytes" "petroleum barrel" "petroleum_barrel" "pfortnight" "pg" "phon")
    return true
  if s in ("phons" "phot" "photon" "photons" "photosynthetic photon flux density" "phots" "pica" "picas" "piccolo" "picobarn" "picobarns" "pied")
    return true
  if s in ("pied du roi" "pieds" "pieds du roi" "pieze" "pinch" "pinches" "pint" "pints" "pip" "pipe" "pipes" "pips")
    return true
  if s in ("pixel" "pixels" "pk" "pkat" "pl" "planck length" "planck mass" "planck time" "plaque forming unit" "plaque-forming unit" "plm" "plx")
    return true
  if s in ("pm" "pmol" "point" "points" "poise" "potential vorticity unit" "potential vorticity units" "pouce" "pouces" "pound" "pound force" "pound-force")
    return true
  if s in ("pounds" "ppb" "ppbv" "ppc" "pphm" "ppm" "ppmv" "ppmw" "pps" "ppt" "proton mass" "proton_mass")
    return true
  if s in ("ps" "psi" "pt" "pud" "puds" "puncheon" "puncheons" "pvar" "px" "pΩ" "qA" "qB")
    return true
  if s in ("qBps" "qBq" "qC" "qDa" "qF" "qGy" "qH" "qHz" "qJ" "qJy" "qK" "qL")
    return true
  if s in ("qN" "qPa" "qS" "qSv" "qT" "qV" "qVA" "qW" "qWb" "qb" "qbps" "qcd")
    return true
  if s in ("qcentury" "qeV" "qfortnight" "qg" "qkat" "ql" "qlm" "qlx" "qm" "qmol" "qpc" "qps")
    return true
  if s in ("qquad" "qr" "qs" "qt" "quad" "quality adjusted life year" "quality-adjusted life year" "quart" "quarter" "quarters" "quarts" "queries")
    return true
  if s in ("query" "quintal" "quintals" "qvar" "qword" "qwords" "qΩ" "rA" "rB" "rBps" "rBq" "rC")
    return true
  if s in ("rDa" "rF" "rGy" "rH" "rHz" "rJ" "rJy" "rK" "rL" "rN" "rPa" "rS")
    return true
  if s in ("rSv" "rT" "rV" "rVA" "rW" "rWb" "rack unit" "rack units" "rad" "rad/s" "rad/s²" "rad_dose")
    return true
  if s in ("radian" "radiance" "radians" "radiant exposure" "radiant intensity" "radiation absorbed dose" "rankine" "rankine difference" "rb" "rbe" "rbps" "rcd")
    return true
  if s in ("rcentury" "rd" "reV" "reactive power" "reaumur" "rega" "regaim" "rehoboam" "relative biological effectiveness" "rem" "rem_css" "rems")
    return true
  if s in ("request" "requests" "resistivity" "rev" "revolution" "revolutions" "revolutions per minute" "revs" "rfortnight" "rg" "ri" "richter")
    return true
  if s in ("richter scale" "rkat" "rl" "rlm" "rlx" "rm" "rmol" "rockwell" "rod" "rods" "roentgen" "roentgens")
    return true
  if s in ("roman libra" "roman mile" "roman uncia" "romer" "rope" "ropes" "rot" "rotation" "rotations" "rotations per minute" "royal cubit" "royal cubits")
    return true
  if s in ("royal_cubit" "rpc" "rpm" "rps" "rs" "rt" "rundlet" "rundlets" "russian funt" "russian_funt" "rutherford" "rutherfords")
    return true
  if s in ("rvar" "rydberg" "rydberg_unit" "rydbergs" "réaumur" "rømer" "rΩ" "s" "sabbath day's journey" "sabbatical" "saffir simpson" "saffir_simpson")
    return true
  if s in ("sagan" "sagans" "sample" "samples" "savart" "savarts" "sazhen" "sazhens" "sb" "score" "scores" "scruple")
    return true
  if s in ("scruples" "seah" "seahs" "second" "seconds" "sector" "sectors" "seer" "seers" "seim" "semitone" "semitones")
    return true
  if s in ("shaftment" "shaftments" "shake" "shakes" "shaku" "shakus" "shed" "shekalim" "shekel" "shekels" "shmita" "shmitas")
    return true
  if s in ("shmitta" "short ton" "short tons" "sidereal day" "sidereal days" "sidereal year" "sidereal years" "siderealday" "siderealyear" "siemens" "siemens per meter" "sievert")
    return true
  if s in ("sieverts" "sk" "skot" "skots" "slug" "slugs" "smidgen" "smidgens" "smoot" "smoots" "solar mass" "solar radius")
    return true
  if s in ("solarmass" "solarradius" "sone" "sones" "span" "spans" "specific energy" "specific heat capacity" "specific_energy" "spectral efficiency" "spectral flux density" "split")
    return true
  if s in ("splits" "sq ft" "sqft" "sqm" "square feet" "square foot" "sr" "st" "standard gravity" "statA" "statC" "statF")
    return true
  if s in ("statH" "statV" "statampere" "statcoulomb" "statfarad" "stathenry" "statohm" "statvolt" "statΩ" "steradian" "steradians" "stere")
    return true
  if s in ("stick" "stick of butter" "sticks" "sticks of butter" "stilb" "stilbs" "stokes" "stone" "stones" "stop" "stops" "story point")
    return true
  if s in ("story points" "story_point" "stère" "stères" "sun" "suns" "surface tension" "svedberg" "svedbergs" "sverdrup" "sverdrups" "symbol")
    return true
  if s in ("symbols" "synodic month" "synodic months" "t" "tablespoon" "tablespoons" "talent" "talents" "talmudic mil" "talmudic_mil" "tatami" "tatamis")
    return true
  if s in ("tbsp" "tce" "teaspoon" "teaspoons" "techum" "techum shabbat" "tefach" "tefachim" "tenth cent" "tenth_cent" "tertian" "tesla")
    return true
  if s in ("teslas" "tex" "texpt" "therm" "thermal conductivity" "thermochemical calorie" "thermochemical kilocalorie" "therms" "tick" "ticks" "tierce" "tierces")
    return true
  if s in ("tn" "toise" "toises" "tok" "tok/J" "tok/s" "token" "tokens" "tokens per joule" "tola" "tolas" "ton")
    return true
  if s in ("tonne" "tonne of coal equivalent" "tonnes" "tons" "torque" "torr" "torrs" "total electron content unit" "tps" "transaction" "transactions" "transfer")
    return true
  if s in ("transfers" "transport carbon intensity" "traversed edges per second" "tropical year" "tropical years" "tropicalyear" "troy ounce" "troy ounces" "troyounce" "tsp" "tsubo" "tsubos")
    return true
  if s in ("tun" "tuns" "turn" "turns" "txn" "tₚ" "u" "uA" "uB" "uBps" "uBq" "uC")
    return true
  if s in ("uDa" "uF" "uGy" "uH" "uHz" "uJ" "uJy" "uK" "uL" "uM" "uN" "uPa")
    return true
  if s in ("uS" "uSv" "uT" "uV" "uVA" "uW" "uWb" "uas" "ub" "ubps" "ucd" "ucentury")
    return true
  if s in ("ueV" "ufortnight" "ug" "ukat" "ul" "ulm" "ulx" "um" "umol" "uncia_roma" "upc" "update")
    return true
  if s in ("updates" "us" "ut" "uvar" "uΩ" "var" "vershok" "vershoks" "verst" "versts" "vh" "vickers")
    return true
  if s in ("viewport height" "viewport width" "volt" "volt ampere" "volt-ampere" "volts" "volts per meter" "volumetric flow" "vw" "warhol" "warhols" "water horsepower")
    return true
  if s in ("water_horsepower" "watt" "watts" "watts per square meter" "wavenumber" "weber" "webers" "wedgwood" "week" "weeks" "wk" "yA")
    return true
  if s in ("yB" "yBps" "yBq" "yC" "yDa" "yF" "yGy" "yH" "yHz" "yJ" "yJy" "yK")
    return true
  if s in ("yL" "yN" "yPa" "yS" "ySv" "yT" "yV" "yVA" "yW" "yWb" "yard" "yards")
    return true
  if s in ("yb" "ybps" "ycd" "ycentury" "yd" "yeV" "year" "years" "yfortnight" "yg" "ykat" "yl")
    return true
  if s in ("ylm" "ylx" "ym" "ymol" "yovel" "yovels" "ypc" "yr" "ys" "yt" "yvar" "yΩ")
    return true
  if s in ("zA" "zB" "zBps" "zBq" "zC" "zDa" "zF" "zGy" "zH" "zHz" "zJ" "zJy")
    return true
  if s in ("zK" "zL" "zN" "zPa" "zS" "zSv" "zT" "zV" "zVA" "zW" "zWb" "zb")
    return true
  if s in ("zbps" "zcd" "zcentury" "zeV" "zeret" "zfortnight" "zg" "zhang" "zhangs" "zkat" "zl" "zlm")
    return true
  if s in ("zlx" "zm" "zmol" "zpc" "zs" "zt" "zvar" "zΩ" "°" "°C" "°De" "°F")
    return true
  if s in ("°N" "°R" "°Ra" "°Re" "°Ré" "°Rø" "°W" "°r" "µA" "µB" "µBps" "µBq")
    return true
  if s in ("µC" "µDa" "µF" "µGy" "µH" "µHz" "µJ" "µJy" "µK" "µL" "µM" "µN")
    return true
  if s in ("µPa" "µS" "µSv" "µT" "µV" "µVA" "µW" "µWb" "µas" "µb" "µbps" "µcd")
    return true
  if s in ("µcentury" "µeV" "µfortnight" "µg" "µg/mL" "µkat" "µl" "µlm" "µlx" "µm" "µmol" "µmol/L")
    return true
  if s in ("µmol_photon/m²/s" "µpc" "µs" "µt" "µvar" "µΩ" "Å" "ångström" "ɡ" "ʒ" "ΔK" "Δ°C")
    return true
  if s in ("Δ°De" "Δ°F" "Δ°N" "Δ°R" "Δ°Ré" "Δ°Rø" "Δ°W" "Ω" "Ω·m" "α" "μA" "μB")
    return true
  if s in ("μBps" "μBq" "μC" "μDa" "μF" "μGy" "μH" "μHz" "μJ" "μJy" "μK" "μL")
    return true
  if s in ("μM" "μN" "μPa" "μS" "μSv" "μT" "μV" "μVA" "μW" "μWb" "μ_B" "μas")
    return true
  if s in ("μb" "μbps" "μcd" "μcentury" "μeV" "μfortnight" "μg" "μkat" "μl" "μlife" "μlm" "μlx")
    return true
  if s in ("μm" "μmol" "μmort" "μpc" "μs" "μt" "μvar" "μΩ" "℃" "℈" "℉" "ℓₚ")
    return true
  if s in ("℔" "℥" "℧" "㍳")
    return true
  false

# --- END GENERATED: regex_known_unit_name ---
