#ifndef W_RUNTIME_UNITY_INCLUDE
#include "runtime_internal.h"
#include <ctype.h>
#include <limits.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#define die w_rt_die
#define dief w_rt_dief
#define die_as w_rt_die_as
#define as_str w_rt_as_str
#define w_string_n w_rt_string_n
#define decimal_normalize w_rt_decimal_normalize
#define decimal_quotient_i128 w_rt_decimal_quotient_i128
#define decimal_narrow_i128 w_rt_decimal_narrow_i128
#define decimal_align w_rt_decimal_align
#define domain_heap_alloc w_rt_domain_heap_alloc
#define decimal_extract w_rt_decimal_extract
#define quantity_extract w_rt_quantity_extract
#define is_decimal_any w_rt_is_decimal_any
#define is_quantity_any w_rt_is_quantity_any
#define quantity_explicit_role w_rt_quantity_explicit_role
#define quantity_origin_value w_rt_quantity_origin_value
#define quantity_with_role w_rt_quantity_with_role
#define date_shift_quantity w_rt_date_shift_quantity
#endif

/* ---- Quantity ---- */

/* --- BEGIN GENERATED: unit_names --- */
#define W_UNIT_CAPACITY 8192
#define W_UNIT_CUSTOM_BASE 4096
static const char *unit_names[W_UNIT_CAPACITY] = {
    /* 0-: SI base */
    [0] = "m",
    [1] = "kg",
    [2] = "s",
    [3] = "A",
    [4] = "K",
    [5] = "mol",
    [6] = "cd",

    /* 7-: SI derived */
    [7] = "Hz",
    [8] = "N",
    [9] = "Pa",
    [10] = "J",
    [11] = "W",
    [12] = "C",
    [13] = "V",
    [14] = "F",
    [15] = "\xce\xa9",
    [16] = "S",
    [17] = "Wb",
    [18] = "T",
    [19] = "H",
    [20] = "\xc2\xb0\x43",
    [21] = "lm",
    [22] = "lx",
    [23] = "Bq",
    [24] = "Gy",
    [25] = "Sv",
    [26] = "kat",

    /* 27-: prefixed length */
    [27] = "km",
    [28] = "cm",
    [29] = "mm",
    [30] = "\xc2\xb5m",
    [31] = "nm",
    [32] = "pm",

    /* 33-: prefixed mass */
    [33] = "g",
    [34] = "mg",
    [35] = "\xc2\xb5g",
    [36] = "t",

    /* 37-: prefixed time */
    [37] = "ms",
    [38] = "\xc2\xb5s",
    [39] = "ns",
    [40] = "ps",

    /* 41-: prefixed frequency */
    [41] = "kHz",
    [42] = "MHz",
    [43] = "GHz",
    [44] = "THz",

    /* 45-: prefixed energy */
    [45] = "kJ",
    [46] = "MJ",
    [47] = "GJ",

    /* 48-: prefixed power */
    [48] = "kW",
    [49] = "MW",
    [50] = "GW",

    /* 51-: prefixed energy */
    [51] = "kWh",
    [52] = "MWh",

    /* 53-: prefixed electric */
    [53] = "mA",
    [54] = "\xc2\xb5\x41",
    [55] = "kV",
    [56] = "MV",

    /* 57-: prefixed pressure */
    [57] = "kPa",
    [58] = "MPa",
    [59] = "GPa",

    /* 60-: imperial length */
    [60] = "in",
    [61] = "ft",
    [62] = "yd",
    [63] = "mi",

    /* 64-: imperial mass */
    [64] = "oz",
    [65] = "lb",

    /* 66-: imperial volume */
    [66] = "fl oz",
    [67] = "gal",
    [68] = "qt",
    [69] = "pt",

    /* 70-: area */
    [70] = "m\xc2\xb2",
    [71] = "cm\xc2\xb2",
    [72] = "km\xc2\xb2",
    [73] = "ha",
    [74] = "acre",
    [75] = "ft\xc2\xb2",

    /* 76-: volume */
    [76] = "m\xc2\xb3",
    [77] = "cm\xc2\xb3",
    [78] = "L",
    [79] = "mL",

    /* 80-: speed */
    [80] = "m/s",
    [81] = "km/h",
    [82] = "mph",

    /* 83-: acceleration */
    [83] = "m/s\xc2\xb2",

    /* 84-: angular */
    [84] = "rad",
    [85] = "\xc2\xb0",
    [86] = "sr",

    /* 87-: temperature */
    [87] = "\xc2\xb0\x46",

    /* 88-: information */
    [88] = "bit",
    [89] = "B",
    [90] = "KB",
    [91] = "MB",
    [92] = "GB",
    [93] = "TB",
    [94] = "PB",
    [95] = "KiB",
    [96] = "MiB",
    [97] = "GiB",
    [98] = "TiB",

    /* 99-: compound */
    [99] = "J\xc2\xb7s",
    [100] = "m\xc2\xb3/(kg\xc2\xb7s\xc2\xb2)",
    [101] = "1/mol",
    [102] = "J/K",
    [103] = "J/(mol\xc2\xb7K)",
    [104] = "F/m",
    [105] = "N/A\xc2\xb2",
    [106] = "W/(m\xc2\xb2\xc2\xb7K\xe2\x81\xb4)",

    /* 107-: energy */
    [107] = "eV",
    [108] = "cal",
    [109] = "kcal",

    /* 110-: pressure */
    [110] = "atm",
    [111] = "bar",
    [112] = "mbar",
    [113] = "Torr",

    /* 114-: length */
    [114] = "nmi",
    [115] = "ly",
    [116] = "au",
    [117] = "pc",

    /* 118-: electric */
    [118] = "e\xe2\x82\x80",

    /* 119-: mass */
    [119] = "lbs",

    /* 120-: area */
    [120] = "sqft",
    [121] = "sqm",

    /* 122-: speed */
    [122] = "mi/h",

    /* 255-: sentinel */
    [255] = "%",

    /* 256-: registry */
    [256] = "\xc2\xb0R",
    [257] = "\xc2\xb0\x44\x65",
    [258] = "\xc2\xb0N",
    [259] = "\xc2\xb0R\xc3\xa9",
    [260] = "\xc2\xb0R\xc3\xb8",
    [261] = "\xc2\xb0W",
    [262] = "\xce\x94K",
    [263] = "\xce\x94\xc2\xb0\x43",
    [264] = "\xce\x94\xc2\xb0\x46",
    [265] = "\xce\x94\xc2\xb0R",
    [266] = "\xce\x94\xc2\xb0\x44\x65",
    [267] = "\xce\x94\xc2\xb0N",
    [268] = "\xce\x94\xc2\xb0R\xc3\xa9",
    [269] = "\xce\x94\xc2\xb0R\xc3\xb8",
    [270] = "\xce\x94\xc2\xb0W",
    [271] = "fur",
    [272] = "rod",
    [273] = "ch",
    [274] = "smoot",
    [275] = "hand",
    [276] = "league",
    [277] = "RU",
    [278] = "\xc3\x85",
    [279] = "fathom",
    [280] = "cable",

    /* 281-: compound */
    [281] = "knot",
    [282] = "kph",

    /* 283-: registry */
    [283] = "mach",
    [284] = "lightsecond",
    [285] = "lightminute",
    [286] = "lighthour",
    [287] = "\xe2\x84\x93\xe2\x82\x9a",
    [288] = "gr",
    [289] = "dr",
    [290] = "st",
    [291] = "qr",
    [292] = "cwt",
    [293] = "CWT",
    [294] = "tn",
    [295] = "LT",
    [296] = "Da",
    [297] = "u",
    [298] = "slug",
    [299] = "m\xe2\x82\x9a\xe2\x82\x97",
    [300] = "\xe2\x84\x88",
    [301] = "\xca\x92",
    [302] = "\xe2\x84\xa5",
    [303] = "\xe2\x84\x94",
    [304] = "troyounce",
    [305] = "pennyweight",
    [306] = "carat",
    [307] = "quintal",
    [308] = "min",
    [309] = "h",
    [310] = "d",
    [311] = "week",
    [312] = "month",
    [313] = "year",
    [314] = "decade",
    [315] = "millennium",
    [316] = "fortnight",
    [317] = "century",
    [318] = "shake",
    [319] = "siderealyear",
    [320] = "tropicalyear",
    [321] = "julianyear",
    [322] = "siderealday",
    [323] = "lunarmonth",
    [324] = "lustrum",
    [325] = "dogyear",
    [326] = "t\xe2\x82\x9a",
    [327] = "ac",
    [328] = "barn",
    [329] = "l",
    [330] = "cup",
    [331] = "gill",
    [332] = "floz",
    [333] = "fldr",
    [334] = "impgal",
    [335] = "bushel",
    [336] = "peck",
    [337] = "tbsp",
    [338] = "tsp",
    [339] = "drop",
    [340] = "dash",
    [341] = "pinch",
    [342] = "smidgen",
    [343] = "jigger",
    [344] = "firkin",
    [345] = "rundlet",
    [346] = "tierce",
    [347] = "hogshead",
    [348] = "puncheon",
    [349] = "pipe",
    [350] = "tun",
    [351] = "kilderkin",
    [352] = "split",
    [353] = "bottle",
    [354] = "magnum",
    [355] = "jeroboam",
    [356] = "methuselah",
    [357] = "nebuchadnezzar",
    [358] = "melchizedek",
    [359] = "Ba",
    [360] = "at",
    [361] = "psi",
    [362] = "torr",
    [363] = "mmHg",
    [364] = "inHg",
    [365] = "cmH2O",
    [366] = "lbf",
    [367] = "kgf",
    [368] = "erg",
    [369] = "cal_IT",
    [370] = "cal_th",
    [371] = "kcal_IT",
    [372] = "kcal_th",
    [373] = "BTU",
    [374] = "therm",
    [375] = "ftlbf",
    [376] = "dyn",
    [377] = "hp",
    [378] = "PS",
    [379] = "Ga",

    /* 380-: compound */
    [380] = "Ci",

    /* 381-: registry */
    [381] = "rem",
    [382] = "deg",
    [383] = "arcmin",
    [384] = "arcsec",
    [385] = "gon",
    [386] = "turn",
    [387] = "mil",
    [388] = "brad",
    [389] = "Gal",
    [390] = "b",
    [391] = "nibble",
    [392] = "o",
    [393] = "PiB",
    [394] = "EiB",

    /* 395-: compound */
    [395] = "bps",
    [396] = "Bps",
    [397] = "baud",

    /* 398-: registry */
    [398] = "P",
    [399] = "cP",
    [400] = "St",
    [401] = "cSt",
    [402] = "solarmass",
    [403] = "earthmass",
    [404] = "jupitermass",
    [405] = "moonmass",
    [406] = "solarradius",
    [407] = "earthradius",
    [408] = "point",
    [409] = "pica",
    [410] = "texpt",
    [411] = "didot",
    [412] = "cicero",
    [413] = "altuve",
    [414] = "outhouse",
    [415] = "shed",
    [416] = "barrel",
    [417] = "stere",
    [418] = "cord",
    [419] = "beard second",
    [420] = "barn megaparsec",
    [421] = "banana",
    [422] = "warhol",
    [423] = "kilowarhol",

    /* 424-: compound */
    [424] = "rpm",
    [425] = "rd",

    /* 426-: registry */
    [426] = "Mx",
    [427] = "millihelen",
    [428] = "nit",
    [429] = "sb",
    [430] = "La",
    [431] = "fL",
    [432] = "asb",
    [433] = "sk",
    [434] = "em",
    [435] = "en",
    [436] = "qquad",
    [437] = "peanutbutter",
    [438] = "jelly",
    [439] = "beat",
    [440] = "cycle",
    [441] = "frame",
    [442] = "instant",
    [443] = "jiffy",
    [444] = "moment",
    [445] = "sample",
    [446] = "tick",
    [447] = "revolution",
    [448] = "decay",
    [449] = "rotation",
    [450] = "flop",
    [451] = "op",
    [452] = "mac",
    [453] = "instruction",
    [454] = "tok",
    [455] = "transfer",
    [456] = "query",
    [457] = "request",
    [458] = "txn",
    [459] = "packet",
    [460] = "io",
    [461] = "nat",
    [462] = "ban",
    [463] = "deciban",
    [464] = "ppm",
    [465] = "ppb",
    [466] = "ppt",
    [467] = "pphm",
    [468] = "sone",
    [469] = "phon",
    [470] = "Jy",
    [471] = "mag",
    [472] = "Mag",
    [473] = "M_bol",
    [474] = "femtobarn",
    [475] = "attobarn",
    [476] = "picobarn",
    [477] = "nanobarn",
    [478] = "fb\xe2\x81\xbb\xc2\xb9",
    [479] = "ab\xe2\x81\xbb\xc2\xb9",
    [480] = "pb\xe2\x81\xbb\xc2\xb9",
    [481] = "nb\xe2\x81\xbb\xc2\xb9",
    [482] = "Oe",
    [483] = "Gb",
    [484] = "D",
    [485] = "\xce\xbc_B",
    [486] = "micromort",
    [487] = "microlife",
    [488] = "kayser",
    [489] = "mohs",
    [490] = "vickers",
    [491] = "rockwell",
    [492] = "brinell",
    [493] = "dozen",
    [494] = "gross",
    [495] = "great_gross",
    [496] = "score",
    [497] = "bakers_dozen",
    [498] = "googol",
    [499] = "googolplex",
    [500] = "cubit",
    [501] = "span",
    [502] = "handbreadth",
    [503] = "fingerbreadth",
    [504] = "biblical_mil",
    [505] = "parsa",
    [506] = "techum",
    [507] = "omer",
    [508] = "ephah",
    [509] = "hin",
    [510] = "bath",
    [511] = "seah",
    [512] = "kor",
    [513] = "kab",
    [514] = "shekel",
    [515] = "biblical_mina",
    [516] = "biblical_talent",
    [517] = "gerah",
    [518] = "beka",
    [519] = "helek",
    [520] = "rega",
    [521] = "onah",
    [522] = "yovel",
    [523] = "shmita",
    [524] = "g\xe2\x82\x80",
    [525] = "g_n",
    [526] = "gee",
    [527] = "mpg",
    [528] = "mpge",
    [529] = "L/100km",
    [530] = "stick",
    [531] = "kiloton",
    [532] = "megaton",
    [533] = "gigaton",
    [534] = "oil_barrel",
    [535] = "BOE",
    [536] = "TCE",
    [537] = "heap",
    [538] = "hole",
    [539] = "shaku",
    [540] = "sun",
    [541] = "ri",
    [542] = "jo",
    [543] = "tsubo",
    [544] = "tatami",
    [545] = "koku",
    [546] = "g\xc5\x8d",
    [547] = "momme",
    [548] = "kanme",
    [549] = "chi",
    [550] = "cun",
    [551] = "fen",
    [552] = "zhang",
    [553] = "li",
    [554] = "mu",
    [555] = "jin",
    [556] = "liang",
    [557] = "dan",
    [558] = "verst",
    [559] = "arshin",
    [560] = "sazhen",
    [561] = "vershok",
    [562] = "pud",
    [563] = "funt_ru",
    [564] = "chetvert",
    [565] = "pied",
    [566] = "pouce",
    [567] = "toise",
    [568] = "arpent",
    [569] = "lieue_de_poste",
    [570] = "pes",
    [571] = "passus",
    [572] = "mille_passuum",
    [573] = "iugerum",
    [574] = "libra_roma",
    [575] = "uncia_roma",
    [576] = "amphora",
    [577] = "royal_cubit",
    [578] = "egypt_palm",
    [579] = "digit",
    [580] = "khet",
    [581] = "aroura",
    [582] = "hath",
    [583] = "gaz",
    [584] = "kos",
    [585] = "tola",
    [586] = "seer",
    [587] = "maund",
    [588] = "hartree",
    [589] = "rydberg_unit",
    [590] = "bohr_radius",
    [591] = "compton_e",
    [592] = "compton_p",
    [593] = "compton_n",
    [594] = "fine_structure",
    [595] = "electron_mass",
    [596] = "proton_mass",
    [597] = "neutron_mass",
    [598] = "muon_mass",
    [599] = "boiler_horsepower",
    [600] = "electric_horsepower",
    [601] = "water_horsepower",
    [602] = "donkeypower",
    [603] = "metric_cup",
    [604] = "metric_tbsp",
    [605] = "australian_tbsp",
    [606] = "japanese_cup",
    [607] = "imperial_pint",
    [608] = "crumb",
    [609] = "dword",
    [610] = "qword",
    [611] = "paragraph",
    [612] = "sector",
    [613] = "page",
    [614] = "block",
    [615] = "cluster",
    [616] = "EV",
    [617] = "f_stop",
    [618] = "ISO_speed",
    [619] = "cent_pitch",
    [620] = "semitone",
    [621] = "savart",
    [622] = "octave",
    [623] = "basis_point",
    [624] = "tenth_cent",
    [625] = "pip",
    [626] = "link_chain",
    [627] = "rope",
    [628] = "perch",
    [629] = "barleycorn",
    [630] = "shaftment",
    [631] = "english_cubit",
    [632] = "nail_cloth",
    [633] = "cable_length",
    [634] = "mH2O",
    [635] = "inH2O",
    [636] = "ftH2O",
    [637] = "pieze",
    [638] = "denier",
    [639] = "tex",
    [640] = "decitex",
    [641] = "french_gauge",
    [642] = "mickey",
    [643] = "sagan",
    [644] = "light_nanosecond",
    [645] = "banana_for_scale",
    [646] = "kg/m\xc2\xb3",
    [647] = "m\xc2\xb3/s",
    [648] = "L/min",
    [649] = "kg/s",
    [650] = "heat_capacity",
    [651] = "entropy",
    [652] = "J/kg/K",
    [653] = "W/m/K",
    [654] = "W/m\xc2\xb2",
    [655] = "V/m",
    [656] = "A/m\xc2\xb2",
    [657] = "\xce\xa9\xc2\xb7m",
    [658] = "S/m",
    [659] = "C/m\xc2\xb3",
    [660] = "N/m",
    [661] = "kg/m",
    [662] = "kg/m\xc2\xb2",
    [663] = "J/m\xc2\xb3",
    [664] = "J/kg",
    [665] = "specific_energy",
    [666] = "mol/mol",
    [667] = "kat/m\xc2\xb3",
    [668] = "cd/m\xc2\xb2",
    [669] = "lx\xc2\xb7s",
    [670] = "lm\xc2\xb7s",
    [671] = "rad/s",
    [672] = "rad/s\xc2\xb2",
    [673] = "m/s\xc2\xb3",
    [674] = "kg\xc2\xb7m/s",
    [675] = "N\xc2\xb7s",
    [676] = "N\xc2\xb7m",
    [677] = "bit/s/Hz",
    [678] = "J/op",
    [679] = "J/tok",
    [680] = "B/flop",
    [681] = "kgCO\xe2\x82\x82\x65",
    [682] = "gCO\xe2\x82\x82\x65",
    [683] = "gCO\xe2\x82\x82\x65/kWh",
    [684] = "gCO\xe2\x82\x82\x65/pkm",
    [685] = "px",
    [686] = "dpi",
    [687] = "dppx",
    [688] = "rem_css",
    [689] = "vw",
    [690] = "vh",
    [691] = "person_hour",
    [692] = "QALY",
    [693] = "story_point",
    [694] = "mg/dL_glucose",
    [695] = "mmol/L_glucose",
    [696] = "mach_air_20C",
    [697] = "M",
    [698] = "mol/L",
    [699] = "mmol/L",
    [700] = "\xc2\xb5mol/L",
    [701] = "nmol/L",
    [702] = "mol/m\xc2\xb3",
    [703] = "g/L",
    [704] = "mg/L",
    [705] = "mg/dL",
    [706] = "g/dL",
    [707] = "\xc2\xb5g/mL",
    [708] = "ng/mL",
    [709] = "Eq",
    [710] = "Eq/L",
    [711] = "mEq/L",
    [712] = "osmol",
    [713] = "Osm/L",
    [714] = "mOsm/L",
    [715] = "U_enzyme",
    [716] = "U/L",
    [717] = "IU",
    [718] = "CFU",
    [719] = "PFU",
    [720] = "cell",
    [721] = "copy",
    [722] = "CFU/mL",
    [723] = "PFU/mL",
    [724] = "cells/mL",
    [725] = "copies/mL",
    [726] = "IU/mL",
    [727] = "Svedberg",
    [728] = "Ah",
    [729] = "var",
    [730] = "VA",
    [731] = "abA",
    [732] = "statA",
    [733] = "abC",
    [734] = "statC",
    [735] = "abV",
    [736] = "statV",
    [737] = "ab\xce\xa9",
    [738] = "stat\xce\xa9",
    [739] = "abF",
    [740] = "statF",
    [741] = "abH",
    [742] = "statH",
    [743] = "phot",
    [744] = "fc",
    [745] = "diopter",
    [746] = "W/sr",
    [747] = "W/sr/m\xc2\xb2",
    [748] = "W/m\xc2\xb2/Hz",
    [749] = "W/m\xc2\xb3",
    [750] = "J/m\xc2\xb2",
    [751] = "photon",
    [752] = "einstein",
    [753] = "mol_photon/m\xc2\xb2/s",
    [754] = "\xc2\xb5mol_photon/m\xc2\xb2/s",
    [755] = "rad_dose",
    [756] = "R_exposure",
    [757] = "Gy/s",
    [758] = "Sv/h",
    [759] = "Bq/kg",
    [760] = "Bq/m\xc2\xb3",
    [761] = "count",
    [762] = "mas",
    [763] = "\xc2\xb5\x61s",
    [764] = "R_sun_nominal",
    [765] = "L_sun_nominal",
    [766] = "foe",
    [767] = "DU",
    [768] = "PVU",
    [769] = "sverdrup",
    [770] = "darcy",
    [771] = "mGal",
    [772] = "Eotvos",
    [773] = "TECU",
    [774] = "gpm",
    [775] = "clo",
    [776] = "ppmv",
    [777] = "ppbv",
    [778] = "ppmw",
    [779] = "symbol",
    [780] = "edge",
    [781] = "update",
    [782] = "bit/s",
    [783] = "B/s",
    [784] = "Mb/s",
    [785] = "Gb/s",
    [786] = "MB/s",
    [787] = "GB/s",
    [788] = "MiB/s",
    [789] = "GiB/s",
    [790] = "bit/symbol",
    [791] = "flop/J",
    [792] = "op/J",
    [793] = "tok/J",
    [794] = "bortle",
    [795] = "beaufort",
    [796] = "saffir_simpson",
    [797] = "fujita",
    [798] = "EF",
    [799] = "richter",
    [800] = "moment_magnitude",
    [801] = "apgar",
    [802] = "RBE",
    [803] = "hounsfield_unit",
    [804] = "short_cubit",
    [805] = "hekat",
    [806] = "ro",
    [807] = "khar",
    [808] = "decan",
    [809] = "slope",
    [810] = "percent_grade",
    [811] = "batter",
    [812] = "seked",
    [813] = "yin",
    [814] = "bu_cn",
    [815] = "hao",
    [816] = "qing",
    [817] = "qian",
    [818] = "dou",
    [819] = "sheng",

    /* 820-: compound */
    [820] = "bpm",
    [821] = "fps",
    [822] = "dpm",
    [823] = "cps",
    [824] = "cpm",
    [825] = "flops",
    [826] = "FLOPS",
    [827] = "kflops",
    [828] = "kFLOPS",
    [829] = "Mflops",
    [830] = "MFLOPS",
    [831] = "Gflops",
    [832] = "GFLOPS",
    [833] = "Tflops",
    [834] = "TFLOPS",
    [835] = "Pflops",
    [836] = "PFLOPS",
    [837] = "Eflops",
    [838] = "EFLOPS",
    [839] = "Zflops",
    [840] = "ZFLOPS",
    [841] = "Yflops",
    [842] = "YFLOPS",
    [843] = "ops_per_s",
    [844] = "KOPS",
    [845] = "MOPS",
    [846] = "GOPS",
    [847] = "TOPS",
    [848] = "POPS",
    [849] = "EOPS",
    [850] = "MIPS",
    [851] = "GIPS",
    [852] = "DMIPS",
    [853] = "MAC/s",
    [854] = "MMAC/s",
    [855] = "GMAC/s",
    [856] = "TMAC/s",
    [857] = "tok/s",
    [858] = "ktok/s",
    [859] = "Mtok/s",
    [860] = "Gtok/s",
    [861] = "T/s",
    [862] = "MT/s",
    [863] = "GT/s",
    [864] = "TT/s",
    [865] = "qps",
    [866] = "QPS",
    [867] = "rps",
    [868] = "RPS",
    [869] = "tps",
    [870] = "TPS",
    [871] = "pps",
    [872] = "PPS",
    [873] = "iops",
    [874] = "IOPS",
    [875] = "TEPS",
    [876] = "GUPS",
    [877] = "molar",
    [878] = "molal",

    /* 879-: generated prefix */
    [879] = "Qm",
    [880] = "Qg",
    [881] = "Qs",
    [882] = "QA",
    [883] = "QK",
    [884] = "Qmol",
    [885] = "Qcd",
    [886] = "QJy",
    [887] = "Qvar",
    [888] = "QVA",
    [889] = "QN",
    [890] = "QJ",
    [891] = "QW",
    [892] = "QPa",
    [893] = "QHz",
    [894] = "QV",
    [895] = "QC",
    [896] = "Q\xce\xa9",
    [897] = "QF",
    [898] = "QH",
    [899] = "QS",
    [900] = "QWb",
    [901] = "QT",
    [902] = "Qlm",
    [903] = "Qlx",
    [904] = "QBq",
    [905] = "QGy",
    [906] = "QSv",
    [907] = "Qkat",
    [908] = "QL",
    [909] = "Ql",
    [910] = "QeV",
    [911] = "QDa",
    [912] = "Qt",
    [913] = "Qb",
    [914] = "QB",
    [915] = "Qbps",
    [916] = "QBps",
    [917] = "Qpc",
    [918] = "Qfortnight",
    [919] = "Qcentury",
    [920] = "Rm",
    [921] = "Rg",
    [922] = "Rs",
    [923] = "RA",
    [924] = "RK",
    [925] = "Rmol",
    [926] = "Rcd",
    [927] = "RJy",
    [928] = "Rvar",
    [929] = "RVA",
    [930] = "RN",
    [931] = "RJ",
    [932] = "RW",
    [933] = "RPa",
    [934] = "RHz",
    [935] = "RV",
    [936] = "RC",
    [937] = "R\xce\xa9",
    [938] = "RF",
    [939] = "RH",
    [940] = "RS",
    [941] = "RWb",
    [942] = "RT",
    [943] = "Rlm",
    [944] = "Rlx",
    [945] = "RBq",
    [946] = "RGy",
    [947] = "RSv",
    [948] = "Rkat",
    [949] = "RL",
    [950] = "Rl",
    [951] = "ReV",
    [952] = "RDa",
    [953] = "Rt",
    [954] = "Rb",
    [955] = "RB",
    [956] = "Rbps",
    [957] = "RBps",
    [958] = "Rpc",
    [959] = "Rfortnight",
    [960] = "Rcentury",
    [961] = "Ym",
    [962] = "Yg",
    [963] = "Ys",
    [964] = "YA",
    [965] = "YK",
    [966] = "Ymol",
    [967] = "Ycd",
    [968] = "YJy",
    [969] = "Yvar",
    [970] = "YVA",
    [971] = "YN",
    [972] = "YJ",
    [973] = "YW",
    [974] = "YPa",
    [975] = "YHz",
    [976] = "YV",
    [977] = "YC",
    [978] = "Y\xce\xa9",
    [979] = "YF",
    [980] = "YH",
    [981] = "YS",
    [982] = "YWb",
    [983] = "YT",
    [984] = "Ylm",
    [985] = "Ylx",
    [986] = "YBq",
    [987] = "YGy",
    [988] = "YSv",
    [989] = "Ykat",
    [990] = "YL",
    [991] = "Yl",
    [992] = "YeV",
    [993] = "YDa",
    [994] = "Yt",
    [995] = "Yb",
    [996] = "YB",
    [997] = "Ybps",
    [998] = "YBps",
    [999] = "Ypc",
    [1000] = "Yfortnight",
    [1001] = "Ycentury",
    [1002] = "Zm",
    [1003] = "Zg",
    [1004] = "Zs",
    [1005] = "ZA",
    [1006] = "ZK",
    [1007] = "Zmol",
    [1008] = "Zcd",
    [1009] = "ZJy",
    [1010] = "Zvar",
    [1011] = "ZVA",
    [1012] = "ZN",
    [1013] = "ZJ",
    [1014] = "ZW",
    [1015] = "ZPa",
    [1016] = "ZHz",
    [1017] = "ZV",
    [1018] = "ZC",
    [1019] = "Z\xce\xa9",
    [1020] = "ZF",
    [1021] = "ZH",
    [1022] = "ZS",
    [1023] = "ZWb",
    [1024] = "ZT",
    [1025] = "Zlm",
    [1026] = "Zlx",
    [1027] = "ZBq",
    [1028] = "ZGy",
    [1029] = "ZSv",
    [1030] = "Zkat",
    [1031] = "ZL",
    [1032] = "Zl",
    [1033] = "ZeV",
    [1034] = "ZDa",
    [1035] = "Zt",
    [1036] = "Zb",
    [1037] = "ZB",
    [1038] = "Zbps",
    [1039] = "ZBps",
    [1040] = "Zpc",
    [1041] = "Zfortnight",
    [1042] = "Zcentury",
    [1043] = "Em",
    [1044] = "Eg",
    [1045] = "Es",
    [1046] = "EA",
    [1047] = "EK",
    [1048] = "Emol",
    [1049] = "Ecd",
    [1050] = "EJy",
    [1051] = "Evar",
    [1052] = "EVA",
    [1053] = "EN",
    [1054] = "EJ",
    [1055] = "EW",
    [1056] = "EPa",
    [1057] = "EHz",
    [1058] = "EC",
    [1059] = "E\xce\xa9",
    [1060] = "EH",
    [1061] = "ES",
    [1062] = "EWb",
    [1063] = "ET",
    [1064] = "Elm",
    [1065] = "Elx",
    [1066] = "EBq",
    [1067] = "EGy",
    [1068] = "ESv",
    [1069] = "Ekat",
    [1070] = "EL",
    [1071] = "El",
    [1072] = "EeV",
    [1073] = "EDa",
    [1074] = "Et",
    [1075] = "Eb",
    [1076] = "EB",
    [1077] = "Ebps",
    [1078] = "EBps",
    [1079] = "Epc",
    [1080] = "Efortnight",
    [1081] = "Ecentury",
    [1082] = "Pm",
    [1083] = "Pg",
    [1084] = "Ps",
    [1085] = "PA",
    [1086] = "PK",
    [1087] = "Pmol",
    [1088] = "Pcd",
    [1089] = "PJy",
    [1090] = "Pvar",
    [1091] = "PVA",
    [1092] = "PN",
    [1093] = "PJ",
    [1094] = "PW",
    [1095] = "PPa",
    [1096] = "PHz",
    [1097] = "PV",
    [1098] = "PC",
    [1099] = "P\xce\xa9",
    [1100] = "PF",
    [1101] = "PH",
    [1102] = "PWb",
    [1103] = "PT",
    [1104] = "Plm",
    [1105] = "Plx",
    [1106] = "PBq",
    [1107] = "PGy",
    [1108] = "PSv",
    [1109] = "Pkat",
    [1110] = "PL",
    [1111] = "Pl",
    [1112] = "PeV",
    [1113] = "PDa",
    [1114] = "Pt",
    [1115] = "Pb",
    [1116] = "Pbps",
    [1117] = "PBps",
    [1118] = "Ppc",
    [1119] = "Pfortnight",
    [1120] = "Pcentury",
    [1121] = "Tm",
    [1122] = "Tg",
    [1123] = "Ts",
    [1124] = "TA",
    [1125] = "TK",
    [1126] = "Tmol",
    [1127] = "Tcd",
    [1128] = "TJy",
    [1129] = "Tvar",
    [1130] = "TVA",
    [1131] = "TN",
    [1132] = "TJ",
    [1133] = "TW",
    [1134] = "TPa",
    [1135] = "TV",
    [1136] = "TC",
    [1137] = "T\xce\xa9",
    [1138] = "TF",
    [1139] = "TH",
    [1140] = "TS",
    [1141] = "TWb",
    [1142] = "TT",
    [1143] = "Tlm",
    [1144] = "Tlx",
    [1145] = "TBq",
    [1146] = "TGy",
    [1147] = "TSv",
    [1148] = "Tkat",
    [1149] = "TL",
    [1150] = "Tl",
    [1151] = "TeV",
    [1152] = "TDa",
    [1153] = "Tt",
    [1154] = "Tb",
    [1155] = "Tbps",
    [1156] = "TBps",
    [1157] = "Tpc",
    [1158] = "Tfortnight",
    [1159] = "Tcentury",
    [1160] = "Gm",
    [1161] = "Gg",
    [1162] = "Gs",
    [1163] = "GA",
    [1164] = "GK",
    [1165] = "Gmol",
    [1166] = "Gcd",
    [1167] = "GJy",
    [1168] = "Gvar",
    [1169] = "GVA",
    [1170] = "GN",
    [1171] = "GV",
    [1172] = "GC",
    [1173] = "G\xce\xa9",
    [1174] = "GF",
    [1175] = "GH",
    [1176] = "GS",
    [1177] = "GWb",
    [1178] = "GT",
    [1179] = "Glm",
    [1180] = "Glx",
    [1181] = "GBq",
    [1182] = "GGy",
    [1183] = "GSv",
    [1184] = "Gkat",
    [1185] = "GL",
    [1186] = "Gl",
    [1187] = "GeV",
    [1188] = "GDa",
    [1189] = "Gt",
    [1190] = "Gbps",
    [1191] = "GBps",
    [1192] = "Gpc",
    [1193] = "Gfortnight",
    [1194] = "Gcentury",
    [1195] = "Mm",
    [1196] = "Mg",
    [1197] = "Ms",
    [1198] = "MA",
    [1199] = "MK",
    [1200] = "Mmol",
    [1201] = "Mcd",
    [1202] = "MJy",
    [1203] = "Mvar",
    [1204] = "MVA",
    [1205] = "MN",
    [1206] = "MC",
    [1207] = "M\xce\xa9",
    [1208] = "MF",
    [1209] = "MH",
    [1210] = "MS",
    [1211] = "MWb",
    [1212] = "MT",
    [1213] = "Mlm",
    [1214] = "Mlx",
    [1215] = "MBq",
    [1216] = "MGy",
    [1217] = "MSv",
    [1218] = "Mkat",
    [1219] = "ML",
    [1220] = "Ml",
    [1221] = "MeV",
    [1222] = "MDa",
    [1223] = "Mt",
    [1224] = "Mb",
    [1225] = "Mbps",
    [1226] = "MBps",
    [1227] = "Mpc",
    [1228] = "Mfortnight",
    [1229] = "Mcentury",
    [1230] = "ks",
    [1231] = "kA",
    [1232] = "kK",
    [1233] = "kmol",
    [1234] = "kcd",
    [1235] = "kJy",
    [1236] = "kvar",
    [1237] = "kVA",
    [1238] = "kN",
    [1239] = "kC",
    [1240] = "k\xce\xa9",
    [1241] = "kF",
    [1242] = "kH",
    [1243] = "kS",
    [1244] = "kWb",
    [1245] = "kT",
    [1246] = "klm",
    [1247] = "klx",
    [1248] = "kBq",
    [1249] = "kGy",
    [1250] = "kSv",
    [1251] = "kkat",
    [1252] = "kL",
    [1253] = "kl",
    [1254] = "keV",
    [1255] = "kDa",
    [1256] = "kb",
    [1257] = "kB",
    [1258] = "kbps",
    [1259] = "kBps",
    [1260] = "kpc",
    [1261] = "kfortnight",
    [1262] = "kcentury",
    [1263] = "hm",
    [1264] = "hg",
    [1265] = "hs",
    [1266] = "hA",
    [1267] = "hK",
    [1268] = "hmol",
    [1269] = "hcd",
    [1270] = "hJy",
    [1271] = "hvar",
    [1272] = "hVA",
    [1273] = "hN",
    [1274] = "hJ",
    [1275] = "hW",
    [1276] = "hPa",
    [1277] = "hHz",
    [1278] = "hV",
    [1279] = "hC",
    [1280] = "h\xce\xa9",
    [1281] = "hF",
    [1282] = "hH",
    [1283] = "hS",
    [1284] = "hWb",
    [1285] = "hT",
    [1286] = "hlm",
    [1287] = "hlx",
    [1288] = "hBq",
    [1289] = "hGy",
    [1290] = "hSv",
    [1291] = "hkat",
    [1292] = "hL",
    [1293] = "hl",
    [1294] = "heV",
    [1295] = "hDa",
    [1296] = "ht",
    [1297] = "hb",
    [1298] = "hB",
    [1299] = "hbps",
    [1300] = "hBps",
    [1301] = "hpc",
    [1302] = "hfortnight",
    [1303] = "hcentury",
    [1304] = "dam",
    [1305] = "dag",
    [1306] = "das",
    [1307] = "daA",
    [1308] = "daK",
    [1309] = "damol",
    [1310] = "dacd",
    [1311] = "daJy",
    [1312] = "davar",
    [1313] = "daVA",
    [1314] = "daN",
    [1315] = "daJ",
    [1316] = "daW",
    [1317] = "daPa",
    [1318] = "daHz",
    [1319] = "daV",
    [1320] = "daC",
    [1321] = "da\xce\xa9",
    [1322] = "daF",
    [1323] = "daH",
    [1324] = "daS",
    [1325] = "daWb",
    [1326] = "daT",
    [1327] = "dalm",
    [1328] = "dalx",
    [1329] = "daBq",
    [1330] = "daGy",
    [1331] = "daSv",
    [1332] = "dakat",
    [1333] = "daL",
    [1334] = "dal",
    [1335] = "daeV",
    [1336] = "daDa",
    [1337] = "dat",
    [1338] = "dab",
    [1339] = "daB",
    [1340] = "dabps",
    [1341] = "daBps",
    [1342] = "dapc",
    [1343] = "dafortnight",
    [1344] = "dacentury",
    [1345] = "dm",
    [1346] = "dg",
    [1347] = "ds",
    [1348] = "dA",
    [1349] = "dK",
    [1350] = "dmol",
    [1351] = "dcd",
    [1352] = "dJy",
    [1353] = "dvar",
    [1354] = "dVA",
    [1355] = "dN",
    [1356] = "dJ",
    [1357] = "dW",
    [1358] = "dPa",
    [1359] = "dHz",
    [1360] = "dV",
    [1361] = "dC",
    [1362] = "d\xce\xa9",
    [1363] = "dF",
    [1364] = "dH",
    [1365] = "dS",
    [1366] = "dWb",
    [1367] = "dT",
    [1368] = "dlm",
    [1369] = "dlx",
    [1370] = "dBq",
    [1371] = "dGy",
    [1372] = "dSv",
    [1373] = "dkat",
    [1374] = "dL",
    [1375] = "dl",
    [1376] = "deV",
    [1377] = "dDa",
    [1378] = "dt",
    [1379] = "db",
    [1380] = "dB",
    [1381] = "dbps",
    [1382] = "dBps",
    [1383] = "dpc",
    [1384] = "dfortnight",
    [1385] = "dcentury",
    [1386] = "cg",
    [1387] = "cs",
    [1388] = "cA",
    [1389] = "cK",
    [1390] = "cmol",
    [1391] = "ccd",
    [1392] = "cJy",
    [1393] = "cvar",
    [1394] = "cVA",
    [1395] = "cN",
    [1396] = "cJ",
    [1397] = "cW",
    [1398] = "cPa",
    [1399] = "cHz",
    [1400] = "cV",
    [1401] = "cC",
    [1402] = "c\xce\xa9",
    [1403] = "cF",
    [1404] = "cH",
    [1405] = "cS",
    [1406] = "cWb",
    [1407] = "cT",
    [1408] = "clm",
    [1409] = "clx",
    [1410] = "cBq",
    [1411] = "cGy",
    [1412] = "cSv",
    [1413] = "ckat",
    [1414] = "cL",
    [1415] = "cl",
    [1416] = "ceV",
    [1417] = "cDa",
    [1418] = "cb",
    [1419] = "cB",
    [1420] = "cbps",
    [1421] = "cBps",
    [1422] = "cpc",
    [1423] = "cfortnight",
    [1424] = "ccentury",
    [1425] = "mK",
    [1426] = "mmol",
    [1427] = "mcd",
    [1428] = "mJy",
    [1429] = "mvar",
    [1430] = "mVA",
    [1431] = "mN",
    [1432] = "mJ",
    [1433] = "mW",
    [1434] = "mPa",
    [1435] = "mHz",
    [1436] = "mV",
    [1437] = "mC",
    [1438] = "m\xce\xa9",
    [1439] = "mF",
    [1440] = "mH",
    [1441] = "mS",
    [1442] = "mWb",
    [1443] = "mT",
    [1444] = "mlm",
    [1445] = "mlx",
    [1446] = "mBq",
    [1447] = "mGy",
    [1448] = "mSv",
    [1449] = "mkat",
    [1450] = "ml",
    [1451] = "meV",
    [1452] = "mDa",
    [1453] = "mt",
    [1454] = "mb",
    [1455] = "mB",
    [1456] = "mbps",
    [1457] = "mBps",
    [1458] = "mpc",
    [1459] = "mfortnight",
    [1460] = "mcentury",
    [1461] = "um",
    [1462] = "ug",
    [1463] = "us",
    [1464] = "uA",
    [1465] = "uK",
    [1466] = "umol",
    [1467] = "ucd",
    [1468] = "uJy",
    [1469] = "uvar",
    [1470] = "uVA",
    [1471] = "uN",
    [1472] = "uJ",
    [1473] = "uW",
    [1474] = "uPa",
    [1475] = "uHz",
    [1476] = "uV",
    [1477] = "uC",
    [1478] = "u\xce\xa9",
    [1479] = "uF",
    [1480] = "uH",
    [1481] = "uS",
    [1482] = "uWb",
    [1483] = "uT",
    [1484] = "ulm",
    [1485] = "ulx",
    [1486] = "uBq",
    [1487] = "uGy",
    [1488] = "uSv",
    [1489] = "ukat",
    [1490] = "uL",
    [1491] = "ul",
    [1492] = "ueV",
    [1493] = "uDa",
    [1494] = "ut",
    [1495] = "ub",
    [1496] = "uB",
    [1497] = "ubps",
    [1498] = "uBps",
    [1499] = "upc",
    [1500] = "ufortnight",
    [1501] = "ucentury",
    [1502] = "\xce\xbcm",
    [1503] = "\xce\xbcg",
    [1504] = "\xce\xbcs",
    [1505] = "\xce\xbc\x41",
    [1506] = "\xce\xbcK",
    [1507] = "\xce\xbcmol",
    [1508] = "\xce\xbc\x63\x64",
    [1509] = "\xce\xbcJy",
    [1510] = "\xce\xbcvar",
    [1511] = "\xce\xbcVA",
    [1512] = "\xce\xbcN",
    [1513] = "\xce\xbcJ",
    [1514] = "\xce\xbcW",
    [1515] = "\xce\xbcPa",
    [1516] = "\xce\xbcHz",
    [1517] = "\xce\xbcV",
    [1518] = "\xce\xbc\x43",
    [1519] = "\xce\xbc\xce\xa9",
    [1520] = "\xce\xbc\x46",
    [1521] = "\xce\xbcH",
    [1522] = "\xce\xbcS",
    [1523] = "\xce\xbcWb",
    [1524] = "\xce\xbcT",
    [1525] = "\xce\xbclm",
    [1526] = "\xce\xbclx",
    [1527] = "\xce\xbc\x42q",
    [1528] = "\xce\xbcGy",
    [1529] = "\xce\xbcSv",
    [1530] = "\xce\xbckat",
    [1531] = "\xce\xbcL",
    [1532] = "\xce\xbcl",
    [1533] = "\xce\xbc\x65V",
    [1534] = "\xce\xbc\x44\x61",
    [1535] = "\xce\xbct",
    [1536] = "\xce\xbc\x62",
    [1537] = "\xce\xbc\x42",
    [1538] = "\xce\xbc\x62ps",
    [1539] = "\xce\xbc\x42ps",
    [1540] = "\xce\xbcpc",
    [1541] = "\xce\xbc\x66ortnight",
    [1542] = "\xce\xbc\x63\x65ntury",
    [1543] = "\xc2\xb5K",
    [1544] = "\xc2\xb5mol",
    [1545] = "\xc2\xb5\x63\x64",
    [1546] = "\xc2\xb5Jy",
    [1547] = "\xc2\xb5var",
    [1548] = "\xc2\xb5VA",
    [1549] = "\xc2\xb5N",
    [1550] = "\xc2\xb5J",
    [1551] = "\xc2\xb5W",
    [1552] = "\xc2\xb5Pa",
    [1553] = "\xc2\xb5Hz",
    [1554] = "\xc2\xb5V",
    [1555] = "\xc2\xb5\x43",
    [1556] = "\xc2\xb5\xce\xa9",
    [1557] = "\xc2\xb5\x46",
    [1558] = "\xc2\xb5H",
    [1559] = "\xc2\xb5S",
    [1560] = "\xc2\xb5Wb",
    [1561] = "\xc2\xb5T",
    [1562] = "\xc2\xb5lm",
    [1563] = "\xc2\xb5lx",
    [1564] = "\xc2\xb5\x42q",
    [1565] = "\xc2\xb5Gy",
    [1566] = "\xc2\xb5Sv",
    [1567] = "\xc2\xb5kat",
    [1568] = "\xc2\xb5L",
    [1569] = "\xc2\xb5l",
    [1570] = "\xc2\xb5\x65V",
    [1571] = "\xc2\xb5\x44\x61",
    [1572] = "\xc2\xb5t",
    [1573] = "\xc2\xb5\x62",
    [1574] = "\xc2\xb5\x42",
    [1575] = "\xc2\xb5\x62ps",
    [1576] = "\xc2\xb5\x42ps",
    [1577] = "\xc2\xb5pc",
    [1578] = "\xc2\xb5\x66ortnight",
    [1579] = "\xc2\xb5\x63\x65ntury",
    [1580] = "ng",
    [1581] = "nA",
    [1582] = "nK",
    [1583] = "nmol",
    [1584] = "ncd",
    [1585] = "nJy",
    [1586] = "nvar",
    [1587] = "nVA",
    [1588] = "nN",
    [1589] = "nJ",
    [1590] = "nW",
    [1591] = "nPa",
    [1592] = "nHz",
    [1593] = "nV",
    [1594] = "nC",
    [1595] = "n\xce\xa9",
    [1596] = "nF",
    [1597] = "nH",
    [1598] = "nS",
    [1599] = "nWb",
    [1600] = "nT",
    [1601] = "nlm",
    [1602] = "nlx",
    [1603] = "nBq",
    [1604] = "nGy",
    [1605] = "nSv",
    [1606] = "nkat",
    [1607] = "nL",
    [1608] = "nl",
    [1609] = "neV",
    [1610] = "nDa",
    [1611] = "nt",
    [1612] = "nb",
    [1613] = "nB",
    [1614] = "nbps",
    [1615] = "nBps",
    [1616] = "npc",
    [1617] = "nfortnight",
    [1618] = "ncentury",
    [1619] = "pg",
    [1620] = "pA",
    [1621] = "pK",
    [1622] = "pmol",
    [1623] = "pcd",
    [1624] = "pJy",
    [1625] = "pvar",
    [1626] = "pVA",
    [1627] = "pN",
    [1628] = "pJ",
    [1629] = "pW",
    [1630] = "pPa",
    [1631] = "pHz",
    [1632] = "pV",
    [1633] = "pC",
    [1634] = "p\xce\xa9",
    [1635] = "pF",
    [1636] = "pH",
    [1637] = "pS",
    [1638] = "pWb",
    [1639] = "pT",
    [1640] = "plm",
    [1641] = "plx",
    [1642] = "pBq",
    [1643] = "pGy",
    [1644] = "pSv",
    [1645] = "pkat",
    [1646] = "pL",
    [1647] = "pl",
    [1648] = "peV",
    [1649] = "pDa",
    [1650] = "pB",
    [1651] = "pbps",
    [1652] = "pBps",
    [1653] = "ppc",
    [1654] = "pfortnight",
    [1655] = "pcentury",
    [1656] = "fm",
    [1657] = "fg",
    [1658] = "fs",
    [1659] = "fA",
    [1660] = "fK",
    [1661] = "fmol",
    [1662] = "fcd",
    [1663] = "fJy",
    [1664] = "fvar",
    [1665] = "fVA",
    [1666] = "fN",
    [1667] = "fJ",
    [1668] = "fW",
    [1669] = "fPa",
    [1670] = "fHz",
    [1671] = "fV",
    [1672] = "fC",
    [1673] = "f\xce\xa9",
    [1674] = "fF",
    [1675] = "fH",
    [1676] = "fS",
    [1677] = "fWb",
    [1678] = "fT",
    [1679] = "flm",
    [1680] = "flx",
    [1681] = "fBq",
    [1682] = "fGy",
    [1683] = "fSv",
    [1684] = "fkat",
    [1685] = "fl",
    [1686] = "feV",
    [1687] = "fDa",
    [1688] = "fb",
    [1689] = "fB",
    [1690] = "fbps",
    [1691] = "fBps",
    [1692] = "fpc",
    [1693] = "ffortnight",
    [1694] = "fcentury",
    [1695] = "am",
    [1696] = "ag",
    [1697] = "as",
    [1698] = "aA",
    [1699] = "aK",
    [1700] = "amol",
    [1701] = "acd",
    [1702] = "aJy",
    [1703] = "avar",
    [1704] = "aVA",
    [1705] = "aN",
    [1706] = "aJ",
    [1707] = "aW",
    [1708] = "aPa",
    [1709] = "aHz",
    [1710] = "aV",
    [1711] = "aC",
    [1712] = "a\xce\xa9",
    [1713] = "aF",
    [1714] = "aH",
    [1715] = "aS",
    [1716] = "aWb",
    [1717] = "aT",
    [1718] = "alm",
    [1719] = "alx",
    [1720] = "aBq",
    [1721] = "aGy",
    [1722] = "aSv",
    [1723] = "akat",
    [1724] = "aL",
    [1725] = "al",
    [1726] = "aeV",
    [1727] = "aDa",
    [1728] = "ab",
    [1729] = "aB",
    [1730] = "abps",
    [1731] = "aBps",
    [1732] = "apc",
    [1733] = "afortnight",
    [1734] = "acentury",
    [1735] = "zm",
    [1736] = "zg",
    [1737] = "zs",
    [1738] = "zA",
    [1739] = "zK",
    [1740] = "zmol",
    [1741] = "zcd",
    [1742] = "zJy",
    [1743] = "zvar",
    [1744] = "zVA",
    [1745] = "zN",
    [1746] = "zJ",
    [1747] = "zW",
    [1748] = "zPa",
    [1749] = "zHz",
    [1750] = "zV",
    [1751] = "zC",
    [1752] = "z\xce\xa9",
    [1753] = "zF",
    [1754] = "zH",
    [1755] = "zS",
    [1756] = "zWb",
    [1757] = "zT",
    [1758] = "zlm",
    [1759] = "zlx",
    [1760] = "zBq",
    [1761] = "zGy",
    [1762] = "zSv",
    [1763] = "zkat",
    [1764] = "zL",
    [1765] = "zl",
    [1766] = "zeV",
    [1767] = "zDa",
    [1768] = "zt",
    [1769] = "zb",
    [1770] = "zB",
    [1771] = "zbps",
    [1772] = "zBps",
    [1773] = "zpc",
    [1774] = "zfortnight",
    [1775] = "zcentury",
    [1776] = "ym",
    [1777] = "yg",
    [1778] = "ys",
    [1779] = "yA",
    [1780] = "yK",
    [1781] = "ymol",
    [1782] = "ycd",
    [1783] = "yJy",
    [1784] = "yvar",
    [1785] = "yVA",
    [1786] = "yN",
    [1787] = "yJ",
    [1788] = "yW",
    [1789] = "yPa",
    [1790] = "yHz",
    [1791] = "yV",
    [1792] = "yC",
    [1793] = "y\xce\xa9",
    [1794] = "yF",
    [1795] = "yH",
    [1796] = "yS",
    [1797] = "yWb",
    [1798] = "yT",
    [1799] = "ylm",
    [1800] = "ylx",
    [1801] = "yBq",
    [1802] = "yGy",
    [1803] = "ySv",
    [1804] = "ykat",
    [1805] = "yL",
    [1806] = "yl",
    [1807] = "yeV",
    [1808] = "yDa",
    [1809] = "yt",
    [1810] = "yb",
    [1811] = "yB",
    [1812] = "ybps",
    [1813] = "yBps",
    [1814] = "ypc",
    [1815] = "yfortnight",
    [1816] = "ycentury",
    [1817] = "rm",
    [1818] = "rg",
    [1819] = "rs",
    [1820] = "rA",
    [1821] = "rK",
    [1822] = "rmol",
    [1823] = "rcd",
    [1824] = "rJy",
    [1825] = "rvar",
    [1826] = "rVA",
    [1827] = "rN",
    [1828] = "rJ",
    [1829] = "rW",
    [1830] = "rPa",
    [1831] = "rHz",
    [1832] = "rV",
    [1833] = "rC",
    [1834] = "r\xce\xa9",
    [1835] = "rF",
    [1836] = "rH",
    [1837] = "rS",
    [1838] = "rWb",
    [1839] = "rT",
    [1840] = "rlm",
    [1841] = "rlx",
    [1842] = "rBq",
    [1843] = "rGy",
    [1844] = "rSv",
    [1845] = "rkat",
    [1846] = "rL",
    [1847] = "rl",
    [1848] = "reV",
    [1849] = "rDa",
    [1850] = "rt",
    [1851] = "rb",
    [1852] = "rB",
    [1853] = "rbps",
    [1854] = "rBps",
    [1855] = "rpc",
    [1856] = "rfortnight",
    [1857] = "rcentury",
    [1858] = "qm",
    [1859] = "qg",
    [1860] = "qs",
    [1861] = "qA",
    [1862] = "qK",
    [1863] = "qmol",
    [1864] = "qcd",
    [1865] = "qJy",
    [1866] = "qvar",
    [1867] = "qVA",
    [1868] = "qN",
    [1869] = "qJ",
    [1870] = "qW",
    [1871] = "qPa",
    [1872] = "qHz",
    [1873] = "qV",
    [1874] = "qC",
    [1875] = "q\xce\xa9",
    [1876] = "qF",
    [1877] = "qH",
    [1878] = "qS",
    [1879] = "qWb",
    [1880] = "qT",
    [1881] = "qlm",
    [1882] = "qlx",
    [1883] = "qBq",
    [1884] = "qGy",
    [1885] = "qSv",
    [1886] = "qkat",
    [1887] = "qL",
    [1888] = "ql",
    [1889] = "qeV",
    [1890] = "qDa",
    [1891] = "qb",
    [1892] = "qB",
    [1893] = "qbps",
    [1894] = "qBps",
    [1895] = "qpc",
    [1896] = "qfortnight",
    [1897] = "qcentury",
    [1898] = "Kib",
    [1899] = "Mib",
    [1900] = "Gib",
    [1901] = "Tib",
    [1902] = "Pib",
    [1903] = "Eib",
    [1904] = "Zib",
    [1905] = "ZiB",
    [1906] = "Yib",
    [1907] = "YiB",
    [1908] = "Rib",
    [1909] = "RiB",
    [1910] = "Qib",
    [1911] = "QiB",
};

typedef struct { const char *name; int id; } WUnitAlias;
static const WUnitAlias unit_aliases[] = {
    {"%", 255},
    {"1/mol", 101},
    {"A", 3},
    {"A/m\xc2\xb2", 656},
    {"AU tbsp", 605},
    {"Ah", 728},
    {"Apgar", 801},
    {"B", 89},
    {"B/flop", 680},
    {"B/s", 783},
    {"BOE", 535},
    {"BPM", 820},
    {"BTU", 373},
    {"Ba", 359},
    {"Beaufort", 795},
    {"Bortle", 794},
    {"Bps", 396},
    {"Bq", 23},
    {"Bq/kg", 759},
    {"Bq/m\xc2\xb3", 760},
    {"C", 12},
    {"C/m\xc2\xb3", 659},
    {"CFU", 718},
    {"CFU/mL", 722},
    {"CFUs", 718},
    {"CWT", 293},
    {"Ci", 380},
    {"D", 484},
    {"DMIPS", 852},
    {"DU", 767},
    {"DWORD", 609},
    {"Da", 296},
    {"E", 772},
    {"EA", 1046},
    {"EB", 1076},
    {"EBps", 1078},
    {"EBq", 1066},
    {"EC", 1058},
    {"EDa", 1073},
    {"EF", 798},
    {"EF-scale", 798},
    {"EFLOPS", 838},
    {"EGy", 1067},
    {"EH", 1060},
    {"EHz", 1057},
    {"EJ", 1054},
    {"EJy", 1050},
    {"EK", 1047},
    {"EL", 1070},
    {"EN", 1053},
    {"EOPS", 849},
    {"EPa", 1056},
    {"ES", 1061},
    {"ESv", 1068},
    {"ET", 1063},
    {"EV", 616},
    {"EVA", 1052},
    {"EW", 1055},
    {"EWb", 1062},
    {"Eb", 1075},
    {"Ebps", 1077},
    {"Ecd", 1049},
    {"Ecentury", 1081},
    {"EeV", 1072},
    {"Eflops", 837},
    {"Efortnight", 1080},
    {"Eg", 1044},
    {"Eh", 588},
    {"EiB", 394},
    {"Eib", 1903},
    {"Ekat", 1069},
    {"El", 1071},
    {"Elm", 1064},
    {"Elx", 1065},
    {"Em", 1043},
    {"Emol", 1048},
    {"Eotvos", 772},
    {"Epc", 1079},
    {"Eq", 709},
    {"Eq/L", 710},
    {"Es", 1045},
    {"Et", 1074},
    {"Evar", 1051},
    {"E\xc3\xb6tv\xc3\xb6s", 772},
    {"E\xce\xa9", 1059},
    {"F", 14},
    {"F-scale", 797},
    {"F/m", 104},
    {"FLOPS", 826},
    {"FPS", 821},
    {"Fr_catheter", 641},
    {"GA", 1163},
    {"GB", 92},
    {"GB/s", 787},
    {"GBps", 1191},
    {"GBq", 1181},
    {"GC", 1172},
    {"GDa", 1188},
    {"GF", 1174},
    {"GFLOPS", 832},
    {"GGy", 1182},
    {"GH", 1175},
    {"GHz", 43},
    {"GIPS", 851},
    {"GJ", 47},
    {"GJy", 1167},
    {"GK", 1164},
    {"GL", 1185},
    {"GMAC/s", 855},
    {"GN", 1170},
    {"GOPS", 846},
    {"GPa", 59},
    {"GS", 1176},
    {"GSv", 1183},
    {"GT", 1178},
    {"GT/s", 863},
    {"GUPS", 876},
    {"GV", 1171},
    {"GVA", 1169},
    {"GW", 50},
    {"GWb", 1177},
    {"Ga", 379},
    {"Gal", 389},
    {"Gb", 483},
    {"Gb/s", 785},
    {"Gbps", 1190},
    {"Gcd", 1166},
    {"Gcentury", 1194},
    {"GeV", 1187},
    {"Gflops", 831},
    {"Gfortnight", 1193},
    {"Gg", 1161},
    {"GiB", 97},
    {"GiB/s", 789},
    {"Gib", 1900},
    {"Gkat", 1184},
    {"Gl", 1186},
    {"Glm", 1179},
    {"Glx", 1180},
    {"Gm", 1160},
    {"Gmol", 1165},
    {"Gpc", 1192},
    {"Gs", 1162},
    {"Gt", 1189},
    {"Gtok/s", 860},
    {"Gvar", 1168},
    {"Gy", 24},
    {"Gy/s", 757},
    {"G\xce\xa9", 1173},
    {"H", 19},
    {"HB", 492},
    {"HRC", 491},
    {"HU", 803},
    {"HV", 490},
    {"Hz", 7},
    {"IOPS", 874},
    {"ISO", 618},
    {"ISO sensitivity", 618},
    {"ISO_speed", 618},
    {"IU", 717},
    {"IU/mL", 726},
    {"J", 10},
    {"J/(kg\xc2\xb7K)", 652},
    {"J/(mol\xc2\xb7K)", 103},
    {"J/K", 102},
    {"J/kg", 664},
    {"J/kg/K", 652},
    {"J/m\xc2\xb2", 750},
    {"J/m\xc2\xb3", 663},
    {"J/op", 678},
    {"J/tok", 679},
    {"Jy", 470},
    {"J\xc2\xb7s", 99},
    {"K", 4},
    {"KB", 90},
    {"KOPS", 844},
    {"KiB", 95},
    {"Kib", 1898},
    {"L", 78},
    {"L per 100 km", 529},
    {"L/100km", 529},
    {"L/min", 648},
    {"LT", 295},
    {"L_sun_nominal", 765},
    {"La", 430},
    {"L\xe2\x98\x89_N", 765},
    {"M", 697},
    {"MA", 1198},
    {"MAC/s", 853},
    {"MB", 91},
    {"MB/s", 786},
    {"MBps", 1226},
    {"MBq", 1215},
    {"MC", 1206},
    {"MDa", 1222},
    {"MF", 1208},
    {"MFLOPS", 830},
    {"MGy", 1216},
    {"MH", 1209},
    {"MHz", 42},
    {"MIPS", 850},
    {"MJ", 46},
    {"MJy", 1202},
    {"MK", 1199},
    {"ML", 1219},
    {"MMAC/s", 854},
    {"MN", 1205},
    {"MOPS", 845},
    {"MPG", 527},
    {"MPGe", 528},
    {"MPa", 58},
    {"MS", 1210},
    {"MSv", 1217},
    {"MT", 1212},
    {"MT/s", 862},
    {"MV", 56},
    {"MVA", 1204},
    {"MW", 49},
    {"MWb", 1211},
    {"MWh", 52},
    {"M_bol", 473},
    {"Mach at 20 C", 696},
    {"Mach in air at 20 C", 696},
    {"Mag", 472},
    {"Mb", 1224},
    {"Mb/s", 784},
    {"Mbol", 473},
    {"Mbps", 1225},
    {"Mcd", 1201},
    {"Mcentury", 1229},
    {"MeV", 1221},
    {"Mflops", 829},
    {"Mfortnight", 1228},
    {"Mg", 1196},
    {"MiB", 96},
    {"MiB/s", 788},
    {"Mib", 1899},
    {"Mkat", 1218},
    {"Ml", 1220},
    {"Mlm", 1213},
    {"Mlx", 1214},
    {"Mm", 1195},
    {"Mmol", 1200},
    {"Mohs", 489},
    {"Mpc", 1227},
    {"Ms", 1197},
    {"Mt", 1223},
    {"Mtok/s", 859},
    {"Mvar", 1203},
    {"Mw", 800},
    {"Mx", 426},
    {"M\xce\xa9", 1207},
    {"M\xe2\x8a\x95", 403},
    {"M\xe2\x98\x89", 402},
    {"M\xe2\x98\xbd", 405},
    {"M\xe2\x99\x83", 404},
    {"N", 8},
    {"N/A\xc2\xb2", 105},
    {"N/m", 660},
    {"N\xc2\xb7m", 676},
    {"N\xc2\xb7s", 675},
    {"Oe", 482},
    {"Osm/L", 713},
    {"P", 398},
    {"PA", 1085},
    {"PB", 94},
    {"PBps", 1117},
    {"PBq", 1106},
    {"PC", 1098},
    {"PDa", 1113},
    {"PF", 1100},
    {"PFLOPS", 836},
    {"PFU", 719},
    {"PFU/mL", 723},
    {"PFUs", 719},
    {"PGy", 1107},
    {"PH", 1101},
    {"PHz", 1096},
    {"PJ", 1093},
    {"PJy", 1089},
    {"PK", 1086},
    {"PL", 1110},
    {"PN", 1092},
    {"POPS", 848},
    {"PPFD", 754},
    {"PPS", 872},
    {"PPa", 1095},
    {"PS", 378},
    {"PSv", 1108},
    {"PT", 1103},
    {"PV", 1097},
    {"PVA", 1091},
    {"PVU", 768},
    {"PW", 1094},
    {"PWb", 1102},
    {"Pa", 9},
    {"Pb", 1115},
    {"Pbps", 1116},
    {"Pcd", 1088},
    {"Pcentury", 1120},
    {"PeV", 1112},
    {"Pflops", 835},
    {"Pfortnight", 1119},
    {"Pg", 1083},
    {"PiB", 393},
    {"Pib", 1902},
    {"Pkat", 1109},
    {"Pl", 1111},
    {"Planck length", 287},
    {"Planck mass", 299},
    {"Planck time", 326},
    {"Plm", 1104},
    {"Plx", 1105},
    {"Pm", 1082},
    {"Pmol", 1087},
    {"Ppc", 1118},
    {"Ps", 1084},
    {"Pt", 1114},
    {"Pvar", 1090},
    {"P\xce\xa9", 1099},
    {"QA", 882},
    {"QALY", 692},
    {"QALYs", 692},
    {"QB", 914},
    {"QBps", 916},
    {"QBq", 904},
    {"QC", 895},
    {"QDa", 911},
    {"QF", 897},
    {"QGy", 905},
    {"QH", 898},
    {"QHz", 893},
    {"QJ", 890},
    {"QJy", 886},
    {"QK", 883},
    {"QL", 908},
    {"QN", 889},
    {"QPS", 866},
    {"QPa", 892},
    {"QS", 899},
    {"QSv", 906},
    {"QT", 901},
    {"QV", 894},
    {"QVA", 888},
    {"QW", 891},
    {"QWORD", 610},
    {"QWb", 900},
    {"Qb", 913},
    {"Qbps", 915},
    {"Qcd", 885},
    {"Qcentury", 919},
    {"QeV", 910},
    {"Qfortnight", 918},
    {"Qg", 880},
    {"QiB", 1911},
    {"Qib", 1910},
    {"Qkat", 907},
    {"Ql", 909},
    {"Qlm", 902},
    {"Qlx", 903},
    {"Qm", 879},
    {"Qmol", 884},
    {"Qpc", 917},
    {"Qs", 881},
    {"Qt", 912},
    {"Qvar", 887},
    {"Q\xce\xa9", 896},
    {"RA", 923},
    {"RB", 955},
    {"RBE", 802},
    {"RBps", 957},
    {"RBq", 945},
    {"RC", 936},
    {"RDa", 952},
    {"RF", 938},
    {"RGy", 946},
    {"RH", 939},
    {"RHz", 934},
    {"RJ", 931},
    {"RJy", 927},
    {"RK", 924},
    {"RL", 949},
    {"RN", 930},
    {"RPS", 868},
    {"RPa", 933},
    {"RS", 940},
    {"RSv", 947},
    {"RT", 942},
    {"RU", 277},
    {"RV", 935},
    {"RVA", 929},
    {"RW", 932},
    {"RWb", 941},
    {"R_exposure", 756},
    {"R_sun_nominal", 764},
    {"Rb", 954},
    {"Rbps", 956},
    {"Rcd", 926},
    {"Rcentury", 960},
    {"ReV", 951},
    {"Rfortnight", 959},
    {"Rg", 921},
    {"RiB", 1909},
    {"Rib", 1908},
    {"Richter", 799},
    {"Rkat", 948},
    {"Rl", 950},
    {"Rlm", 943},
    {"Rlx", 944},
    {"Rm", 920},
    {"Rmol", 925},
    {"Rpc", 958},
    {"Rs", 922},
    {"Rt", 953},
    {"Rvar", 928},
    {"Ry", 589},
    {"R\xce\xa9", 937},
    {"R\xe2\x8a\x95", 407},
    {"R\xe2\x98\x89", 406},
    {"R\xe2\x98\x89_N", 764},
    {"S", 16},
    {"S/m", 658},
    {"SS_category", 796},
    {"Saffir-Simpson", 796},
    {"St", 400},
    {"Sv", 25},
    {"Sv/h", 758},
    {"Sv_ocean", 769},
    {"Svedberg", 727},
    {"T", 18},
    {"T/s", 861},
    {"TA", 1124},
    {"TB", 93},
    {"TBps", 1156},
    {"TBq", 1145},
    {"TC", 1136},
    {"TCE", 536},
    {"TDa", 1152},
    {"TECU", 773},
    {"TEPS", 875},
    {"TF", 1138},
    {"TFLOPS", 834},
    {"TGy", 1146},
    {"TH", 1139},
    {"THz", 44},
    {"TJ", 1132},
    {"TJy", 1128},
    {"TK", 1125},
    {"TL", 1149},
    {"TMAC/s", 856},
    {"TN", 1131},
    {"TOPS", 847},
    {"TPS", 870},
    {"TPa", 1134},
    {"TS", 1140},
    {"TSv", 1147},
    {"TT", 1142},
    {"TT/s", 864},
    {"TV", 1135},
    {"TVA", 1130},
    {"TW", 1133},
    {"TWb", 1141},
    {"Tb", 1154},
    {"Tbps", 1155},
    {"Tcd", 1127},
    {"Tcentury", 1159},
    {"TeV", 1151},
    {"Tflops", 833},
    {"Tfortnight", 1158},
    {"Tg", 1122},
    {"TiB", 98},
    {"Tib", 1901},
    {"Tkat", 1148},
    {"Tl", 1150},
    {"Tlm", 1143},
    {"Tlx", 1144},
    {"Tm", 1121},
    {"Tmol", 1126},
    {"Torr", 113},
    {"Tpc", 1157},
    {"Ts", 1123},
    {"Tt", 1153},
    {"Tvar", 1129},
    {"T\xce\xa9", 1137},
    {"U/L", 716},
    {"U_enzyme", 715},
    {"V", 13},
    {"V/m", 655},
    {"VA", 730},
    {"W", 11},
    {"W/(m\xc2\xb2\xc2\xb7K\xe2\x81\xb4)", 106},
    {"W/(m\xc2\xb7K)", 653},
    {"W/m/K", 653},
    {"W/m\xc2\xb2", 654},
    {"W/m\xc2\xb2/Hz", 748},
    {"W/m\xc2\xb3", 749},
    {"W/sr", 746},
    {"W/sr/m\xc2\xb2", 747},
    {"Wb", 17},
    {"YA", 964},
    {"YB", 996},
    {"YBps", 998},
    {"YBq", 986},
    {"YC", 977},
    {"YDa", 993},
    {"YF", 979},
    {"YFLOPS", 842},
    {"YGy", 987},
    {"YH", 980},
    {"YHz", 975},
    {"YJ", 972},
    {"YJy", 968},
    {"YK", 965},
    {"YL", 990},
    {"YN", 971},
    {"YPa", 974},
    {"YS", 981},
    {"YSv", 988},
    {"YT", 983},
    {"YV", 976},
    {"YVA", 970},
    {"YW", 973},
    {"YWb", 982},
    {"Yb", 995},
    {"Ybps", 997},
    {"Ycd", 967},
    {"Ycentury", 1001},
    {"YeV", 992},
    {"Yflops", 841},
    {"Yfortnight", 1000},
    {"Yg", 962},
    {"YiB", 1907},
    {"Yib", 1906},
    {"Ykat", 989},
    {"Yl", 991},
    {"Ylm", 984},
    {"Ylx", 985},
    {"Ym", 961},
    {"Ymol", 966},
    {"Ypc", 999},
    {"Ys", 963},
    {"Yt", 994},
    {"Yvar", 969},
    {"Y\xce\xa9", 978},
    {"ZA", 1005},
    {"ZB", 1037},
    {"ZBps", 1039},
    {"ZBq", 1027},
    {"ZC", 1018},
    {"ZDa", 1034},
    {"ZF", 1020},
    {"ZFLOPS", 840},
    {"ZGy", 1028},
    {"ZH", 1021},
    {"ZHz", 1016},
    {"ZJ", 1013},
    {"ZJy", 1009},
    {"ZK", 1006},
    {"ZL", 1031},
    {"ZN", 1012},
    {"ZPa", 1015},
    {"ZS", 1022},
    {"ZSv", 1029},
    {"ZT", 1024},
    {"ZV", 1017},
    {"ZVA", 1011},
    {"ZW", 1014},
    {"ZWb", 1023},
    {"Zb", 1036},
    {"Zbps", 1038},
    {"Zcd", 1008},
    {"Zcentury", 1042},
    {"ZeV", 1033},
    {"Zflops", 839},
    {"Zfortnight", 1041},
    {"Zg", 1003},
    {"ZiB", 1905},
    {"Zib", 1904},
    {"Zkat", 1030},
    {"Zl", 1032},
    {"Zlm", 1025},
    {"Zlx", 1026},
    {"Zm", 1002},
    {"Zmol", 1007},
    {"Zpc", 1040},
    {"Zs", 1004},
    {"Zt", 1035},
    {"Zvar", 1010},
    {"Z\xce\xa9", 1019},
    {"a0", 590},
    {"aA", 1698},
    {"aB", 1729},
    {"aBps", 1731},
    {"aBq", 1720},
    {"aC", 1711},
    {"aDa", 1727},
    {"aF", 1713},
    {"aGy", 1721},
    {"aH", 1714},
    {"aHz", 1709},
    {"aJ", 1706},
    {"aJy", 1702},
    {"aK", 1699},
    {"aL", 1724},
    {"aN", 1705},
    {"aPa", 1708},
    {"aS", 1715},
    {"aSv", 1722},
    {"aT", 1717},
    {"aV", 1710},
    {"aVA", 1704},
    {"aW", 1707},
    {"aWb", 1716},
    {"a_0", 590},
    {"ab", 1728},
    {"ab-1", 479},
    {"abA", 731},
    {"abC", 733},
    {"abF", 739},
    {"abH", 741},
    {"abV", 735},
    {"ab^-1", 479},
    {"abampere", 731},
    {"abarn", 475},
    {"abcoulomb", 733},
    {"abfarad", 739},
    {"abhenry", 741},
    {"abinv", 479},
    {"abohm", 737},
    {"abps", 1730},
    {"absolute magnitude", 472},
    {"absorbed-dose rad", 755},
    {"abvolt", 735},
    {"ab\xce\xa9", 737},
    {"ab\xe2\x81\xbb\xc2\xb9", 479},
    {"ac", 327},
    {"acd", 1701},
    {"acentury", 1734},
    {"acre", 74},
    {"acres", 327},
    {"aeV", 1726},
    {"afortnight", 1733},
    {"ag", 1696},
    {"akat", 1723},
    {"al", 1725},
    {"alm", 1718},
    {"alpha", 594},
    {"altuve", 413},
    {"altuves", 413},
    {"alx", 1719},
    {"am", 1695},
    {"amah", 500},
    {"amol", 1700},
    {"amot", 500},
    {"amp hours", 728},
    {"ampere", 3},
    {"ampere hour", 728},
    {"ampere-hour", 728},
    {"amperes", 3},
    {"amperes per square meter", 656},
    {"amphora", 576},
    {"amphorae", 576},
    {"amphoras", 576},
    {"angstrom", 278},
    {"angstroms", 278},
    {"angular acceleration", 672},
    {"angular velocity", 671},
    {"apc", 1732},
    {"apgar", 801},
    {"apgar score", 801},
    {"apostilb", 432},
    {"apostilbs", 432},
    {"apparent magnitude", 471},
    {"arcmin", 383},
    {"arcsec", 384},
    {"areal density", 662},
    {"aroura", 581},
    {"arourae", 581},
    {"arouras", 581},
    {"arpent", 568},
    {"arpents", 568},
    {"arshin", 559},
    {"arshins", 559},
    {"as", 1697},
    {"asb", 432},
    {"astronomical unit", 116},
    {"astronomical units", 116},
    {"at", 360},
    {"atm", 110},
    {"atmosphere", 110},
    {"atmospheres", 110},
    {"attobarn", 475},
    {"attobarns", 475},
    {"au", 116},
    {"australian tablespoon", 605},
    {"australian tablespoons", 605},
    {"australian tbsp", 605},
    {"australian_tbsp", 605},
    {"avar", 1703},
    {"a\xce\xa9", 1712},
    {"b", 390},
    {"baker's dozen", 497},
    {"bakers dozen", 497},
    {"bakers_dozen", 497},
    {"ban", 462},
    {"banana", 421},
    {"banana for scale", 645},
    {"banana_for_scale", 645},
    {"bananas", 421},
    {"bananas for scale", 645},
    {"bar", 111},
    {"barleycorn", 629},
    {"barleycorns", 629},
    {"barn", 328},
    {"barn megaparsec", 420},
    {"barn-megaparsec", 420},
    {"barn-megaparsecs", 420},
    {"barns", 328},
    {"barrel", 416},
    {"barrel of oil equivalent", 535},
    {"barrels", 416},
    {"barye", 359},
    {"basis point", 623},
    {"basis points", 623},
    {"basis_point", 623},
    {"basis_points", 623},
    {"bath", 510},
    {"baths", 510},
    {"batter", 811},
    {"batters", 811},
    {"baud", 397},
    {"beard second", 419},
    {"beard seconds", 419},
    {"beard-second", 419},
    {"beard-seconds", 419},
    {"beat", 439},
    {"beats", 439},
    {"beats per minute", 820},
    {"beaufort", 795},
    {"becquerel", 23},
    {"becquerels", 23},
    {"beka", 518},
    {"bekah", 518},
    {"bekas", 518},
    {"biblical talent", 516},
    {"biblical_mil", 504},
    {"biblical_mina", 515},
    {"biblical_talent", 516},
    {"billions and billions", 643},
    {"biot", 731},
    {"bit", 88},
    {"bit/(s\xc2\xb7Hz)", 677},
    {"bit/s", 782},
    {"bit/s/Hz", 677},
    {"bit/symbol", 790},
    {"bits", 390},
    {"bits per second per hertz", 677},
    {"bits per symbol", 790},
    {"block", 614},
    {"blocks", 614},
    {"boe", 535},
    {"bohr magneton", 485},
    {"bohr_magneton", 485},
    {"bohr_radius", 590},
    {"boiler horsepower", 599},
    {"boiler_horsepower", 599},
    {"bolometric magnitude", 473},
    {"bortle", 794},
    {"bottle", 353},
    {"bottles", 353},
    {"bp_finance", 623},
    {"bpm", 820},
    {"bps", 395},
    {"brad", 388},
    {"brads", 388},
    {"brinell", 492},
    {"bu", 335},
    {"bu_cn", 814},
    {"bushel", 335},
    {"bushels", 335},
    {"butt", 349},
    {"byte", 89},
    {"bytes", 89},
    {"bytes per flop", 680},
    {"cA", 1388},
    {"cB", 1419},
    {"cBps", 1421},
    {"cBq", 1410},
    {"cC", 1401},
    {"cDa", 1417},
    {"cF", 1403},
    {"cGy", 1411},
    {"cH", 1404},
    {"cHz", 1399},
    {"cJ", 1396},
    {"cJy", 1392},
    {"cK", 1389},
    {"cL", 1414},
    {"cN", 1395},
    {"cP", 399},
    {"cPa", 1398},
    {"cS", 1405},
    {"cSt", 401},
    {"cSv", 1412},
    {"cT", 1407},
    {"cV", 1400},
    {"cVA", 1394},
    {"cW", 1397},
    {"cWb", 1406},
    {"cable", 280},
    {"cable length", 633},
    {"cable lengths", 633},
    {"cable_length", 633},
    {"cables", 280},
    {"cal", 108},
    {"cal_IT", 369},
    {"cal_th", 370},
    {"calorie", 108},
    {"calorie IT", 369},
    {"calories", 108},
    {"candela", 6},
    {"candela per square meter", 668},
    {"candelas", 6},
    {"carat", 306},
    {"carats", 306},
    {"catalytic activity concentration", 667},
    {"cb", 1418},
    {"cbps", 1420},
    {"ccd", 1391},
    {"ccentury", 1424},
    {"cd", 6},
    {"cd/m\xc2\xb2", 668},
    {"ceV", 1416},
    {"cell", 720},
    {"cells", 720},
    {"cells/mL", 724},
    {"celsius", 20},
    {"celsius difference", 263},
    {"cent", 619},
    {"cent_pitch", 619},
    {"centipoise", 399},
    {"centistokes", 401},
    {"cents", 619},
    {"centuries", 317},
    {"century", 317},
    {"cfortnight", 1423},
    {"cg", 1386},
    {"ch", 273},
    {"chain", 273},
    {"chains", 273},
    {"charge density", 659},
    {"chelakim", 519},
    {"chelek", 519},
    {"chetvert", 564},
    {"chetverts", 564},
    {"chi", 549},
    {"chinese bu", 814},
    {"chinese dan", 557},
    {"chinese li", 553},
    {"chinese pace", 814},
    {"chinese paces", 814},
    {"chinese_dan", 557},
    {"chinese_li", 553},
    {"chis", 549},
    {"cicero", 412},
    {"ckat", 1413},
    {"cl", 1415},
    {"clm", 1408},
    {"clo", 775},
    {"clo unit", 775},
    {"cloth nail", 632},
    {"cluster", 615},
    {"clusters", 615},
    {"clx", 1409},
    {"cm", 28},
    {"cm-1", 488},
    {"cmH2O", 365},
    {"cm^-1", 488},
    {"cmol", 1390},
    {"cm\xc2\xb2", 71},
    {"cm\xc2\xb3", 77},
    {"cm\xe2\x81\xbb\xc2\xb9", 488},
    {"colony forming unit", 718},
    {"colony-forming unit", 718},
    {"compton wavelength", 591},
    {"compton wavelength electron", 591},
    {"compton wavelength neutron", 593},
    {"compton wavelength proton", 592},
    {"compton_e", 591},
    {"compton_n", 593},
    {"compton_p", 592},
    {"compton_wavelength", 591},
    {"conductivity", 658},
    {"copies", 721},
    {"copies/mL", 725},
    {"copy", 721},
    {"cord", 418},
    {"cords", 418},
    {"coulomb", 12},
    {"coulombs", 12},
    {"coulombs per cubic meter", 659},
    {"count", 761},
    {"counts per minute", 824},
    {"counts per second", 823},
    {"cpc", 1422},
    {"cpm", 824},
    {"cps", 823},
    {"crumb", 608},
    {"crumbs", 608},
    {"cs", 1387},
    {"css rem", 688},
    {"ct", 306},
    {"cubic meters per second", 647},
    {"cubit", 500},
    {"cubits", 500},
    {"cun", 550},
    {"cuns", 550},
    {"cup", 330},
    {"cups", 330},
    {"curie", 380},
    {"curies", 380},
    {"current density", 656},
    {"cvar", 1393},
    {"cwt", 292},
    {"cyc", 440},
    {"cycle", 440},
    {"cycles", 440},
    {"c\xce\xa9", 1402},
    {"d", 310},
    {"dA", 1348},
    {"dB", 1380},
    {"dBps", 1382},
    {"dBq", 1370},
    {"dC", 1361},
    {"dDa", 1377},
    {"dF", 1363},
    {"dGy", 1371},
    {"dH", 1364},
    {"dHz", 1359},
    {"dJ", 1356},
    {"dJy", 1352},
    {"dK", 1349},
    {"dL", 1374},
    {"dN", 1355},
    {"dPa", 1358},
    {"dS", 1365},
    {"dSv", 1372},
    {"dT", 1367},
    {"dV", 1360},
    {"dVA", 1354},
    {"dW", 1357},
    {"dWb", 1366},
    {"daA", 1307},
    {"daB", 1339},
    {"daBps", 1341},
    {"daBq", 1329},
    {"daC", 1320},
    {"daDa", 1336},
    {"daF", 1322},
    {"daGy", 1330},
    {"daH", 1323},
    {"daHz", 1318},
    {"daJ", 1315},
    {"daJy", 1311},
    {"daK", 1308},
    {"daL", 1333},
    {"daN", 1314},
    {"daPa", 1317},
    {"daS", 1324},
    {"daSv", 1331},
    {"daT", 1326},
    {"daV", 1319},
    {"daVA", 1313},
    {"daW", 1316},
    {"daWb", 1325},
    {"dab", 1338},
    {"dabps", 1340},
    {"dacd", 1310},
    {"dacentury", 1344},
    {"daeV", 1335},
    {"dafortnight", 1343},
    {"dag", 1305},
    {"dakat", 1332},
    {"dal", 1334},
    {"dalm", 1327},
    {"dalton", 296},
    {"daltons", 296},
    {"dalx", 1328},
    {"dam", 1304},
    {"damol", 1309},
    {"dan", 557},
    {"dans", 557},
    {"dapc", 1342},
    {"darcies", 770},
    {"darcy", 770},
    {"das", 1306},
    {"dash", 340},
    {"dashes", 340},
    {"dat", 1337},
    {"davar", 1312},
    {"day", 310},
    {"days", 310},
    {"da\xce\xa9", 1321},
    {"db", 1379},
    {"dbps", 1381},
    {"dcd", 1351},
    {"dcentury", 1385},
    {"deV", 1376},
    {"debye", 484},
    {"debyes", 484},
    {"decade", 314},
    {"decades", 314},
    {"decan", 808},
    {"decans", 808},
    {"decay", 448},
    {"decays", 448},
    {"decays per minute", 822},
    {"deciban", 463},
    {"decibans", 463},
    {"decitex", 640},
    {"deg", 382},
    {"degree", 382},
    {"degrees", 382},
    {"delisle", 257},
    {"delta celsius", 263},
    {"delta fahrenheit", 264},
    {"delta kelvin", 262},
    {"delta rankine", 265},
    {"denier", 638},
    {"deniers", 638},
    {"dfortnight", 1384},
    {"dg", 1346},
    {"didot", 411},
    {"digit", 579},
    {"digits", 579},
    {"diopter", 745},
    {"diopters", 745},
    {"dioptre", 745},
    {"dioptres", 745},
    {"dit", 462},
    {"dits", 462},
    {"dkat", 1373},
    {"dl", 1375},
    {"dlm", 1368},
    {"dlx", 1369},
    {"dm", 1345},
    {"dmol", 1350},
    {"dobson unit", 767},
    {"dobson units", 767},
    {"dog year", 325},
    {"dog years", 325},
    {"dogyear", 325},
    {"donkey power", 602},
    {"donkey-power", 602},
    {"donkeypower", 602},
    {"dots per inch", 686},
    {"dots per pixel", 687},
    {"dou", 818},
    {"dous", 818},
    {"dozen", 493},
    {"dozens", 493},
    {"dpc", 1383},
    {"dpi", 686},
    {"dpm", 822},
    {"dppx", 687},
    {"dr", 289},
    {"drachm", 289},
    {"drams", 289},
    {"drop", 339},
    {"drops", 339},
    {"ds", 1347},
    {"dt", 1378},
    {"dvar", 1353},
    {"dword", 609},
    {"dwords", 609},
    {"dwt", 305},
    {"dyn", 376},
    {"dyne", 376},
    {"dynes", 376},
    {"d\xce\xa9", 1362},
    {"eV", 107},
    {"earth mass", 403},
    {"earth radius", 407},
    {"earthmass", 403},
    {"earthradius", 407},
    {"edge", 780},
    {"edges", 780},
    {"egypt_palm", 578},
    {"egyptian cubit", 577},
    {"egyptian cubits", 577},
    {"egyptian palm", 578},
    {"egyptian palms", 578},
    {"egyptian_cubit", 577},
    {"einstein", 752},
    {"einsteins", 752},
    {"electric field", 655},
    {"electric horsepower", 600},
    {"electric_horsepower", 600},
    {"electron mass", 595},
    {"electron_mass", 595},
    {"electronvolt", 107},
    {"electronvolts", 107},
    {"em", 434},
    {"en", 435},
    {"energy density", 663},
    {"english cubit", 631},
    {"english cubits", 631},
    {"english_cubit", 631},
    {"enhanced fujita", 798},
    {"entropy", 651},
    {"enzyme unit", 715},
    {"enzyme units", 715},
    {"eotvos", 772},
    {"ephah", 508},
    {"ephahs", 508},
    {"ephas", 508},
    {"equivalent", 709},
    {"equivalents", 709},
    {"erg", 368},
    {"etzba", 503},
    {"etzbaot", 503},
    {"ev", 616},
    {"e\xe2\x82\x80", 118},
    {"f stop", 617},
    {"f-stop", 617},
    {"f-stops", 617},
    {"fA", 1659},
    {"fB", 1689},
    {"fBps", 1691},
    {"fBq", 1681},
    {"fC", 1672},
    {"fDa", 1687},
    {"fF", 1674},
    {"fGy", 1682},
    {"fH", 1675},
    {"fHz", 1670},
    {"fJ", 1667},
    {"fJy", 1663},
    {"fK", 1660},
    {"fL", 431},
    {"fN", 1666},
    {"fPa", 1669},
    {"fS", 1676},
    {"fSv", 1683},
    {"fT", 1678},
    {"fV", 1671},
    {"fVA", 1665},
    {"fW", 1668},
    {"fWb", 1677},
    {"f_stop", 617},
    {"fahrenheit", 87},
    {"fahrenheit difference", 264},
    {"farad", 14},
    {"farads", 14},
    {"fathom", 279},
    {"fathoms", 279},
    {"fb", 1688},
    {"fb-1", 478},
    {"fb^-1", 478},
    {"fbarn", 474},
    {"fbinv", 478},
    {"fbps", 1690},
    {"fb\xe2\x81\xbb\xc2\xb9", 478},
    {"fc", 744},
    {"fcd", 1662},
    {"fcentury", 1694},
    {"feV", 1686},
    {"feet", 61},
    {"feet of water", 636},
    {"femtobarn", 474},
    {"femtobarns", 474},
    {"fen", 551},
    {"fens", 551},
    {"ffortnight", 1693},
    {"fg", 1657},
    {"fine structure constant", 594},
    {"fine_structure", 594},
    {"fingerbreadth", 503},
    {"firkin", 344},
    {"firkins", 344},
    {"fkat", 1684},
    {"fl", 1685},
    {"fl dr", 333},
    {"fl oz", 66},
    {"fldr", 333},
    {"flm", 1679},
    {"flop", 450},
    {"flop/J", 791},
    {"flops", 825},
    {"flops per joule", 791},
    {"flops_count", 450},
    {"floz", 332},
    {"fluid dram", 333},
    {"fluid drams", 333},
    {"fluid ounce", 332},
    {"fluid ounces", 332},
    {"flx", 1680},
    {"fm", 1656},
    {"fmol", 1661},
    {"foe", 766},
    {"foes", 766},
    {"foot", 61},
    {"foot candle", 744},
    {"foot candles", 744},
    {"foot of water", 636},
    {"foot pound", 375},
    {"foot pounds", 375},
    {"foot-candle", 744},
    {"foot-lambert", 431},
    {"foot-pound", 375},
    {"foot-pounds", 375},
    {"fortnight", 316},
    {"fortnights", 316},
    {"fpc", 1692},
    {"fps", 821},
    {"frame", 441},
    {"frames", 441},
    {"frames per second", 821},
    {"franklin", 734},
    {"french gauge", 641},
    {"french_gauge", 641},
    {"fs", 1658},
    {"fstop", 617},
    {"ft", 61},
    {"ft H2O", 636},
    {"ft of water", 636},
    {"ftH2O", 636},
    {"ftlbf", 375},
    {"ft\xc2\xb2", 75},
    {"fujita", 797},
    {"fujita scale", 797},
    {"funt", 563},
    {"funt_ru", 563},
    {"fur", 271},
    {"furlong", 271},
    {"furlongs", 271},
    {"fvar", 1664},
    {"f\xce\xa9", 1673},
    {"g", 33},
    {"g CO2e", 682},
    {"g/L", 703},
    {"g/dL", 706},
    {"g0", 524},
    {"gCO\xe2\x82\x82\x65", 682},
    {"gCO\xe2\x82\x82\x65/kWh", 683},
    {"gCO\xe2\x82\x82\x65/pkm", 684},
    {"g_n", 525},
    {"gal", 67},
    {"gallon", 67},
    {"gallons", 67},
    {"gauss", 379},
    {"gaz", 583},
    {"gazes", 583},
    {"gee", 526},
    {"geopotential meter", 774},
    {"geopotential metre", 774},
    {"gerah", 517},
    {"gerahs", 517},
    {"giga-updates per second", 876},
    {"gigaton", 533},
    {"gigatons", 533},
    {"gilbert", 483},
    {"gilberts", 483},
    {"gill", 331},
    {"gills", 331},
    {"gon", 385},
    {"googol", 498},
    {"googolplex", 499},
    {"googolplexes", 499},
    {"googols", 498},
    {"gos", 546},
    {"gpm", 774},
    {"gr", 288},
    {"grad", 385},
    {"gradian", 385},
    {"gradians", 385},
    {"grain", 288},
    {"grains", 288},
    {"gram", 33},
    {"grams", 33},
    {"grams CO2e", 682},
    {"grape jelly", 438},
    {"grave", 1},
    {"gray", 24},
    {"grays", 24},
    {"great gross", 495},
    {"great_gross", 495},
    {"grid carbon intensity", 683},
    {"gross", 494},
    {"g\xc5\x8d", 546},
    {"g\xe2\x82\x80", 524},
    {"h", 309},
    {"hA", 1266},
    {"hB", 1298},
    {"hBps", 1300},
    {"hBq", 1288},
    {"hC", 1279},
    {"hDa", 1295},
    {"hF", 1281},
    {"hGy", 1289},
    {"hH", 1282},
    {"hHz", 1277},
    {"hJ", 1274},
    {"hJy", 1270},
    {"hK", 1267},
    {"hL", 1292},
    {"hN", 1273},
    {"hPa", 1276},
    {"hS", 1283},
    {"hSv", 1290},
    {"hT", 1285},
    {"hV", 1278},
    {"hVA", 1272},
    {"hW", 1275},
    {"hWb", 1284},
    {"ha", 73},
    {"halakim", 519},
    {"half step", 620},
    {"halfstep", 620},
    {"hand", 275},
    {"handbreadth", 502},
    {"handbreadths", 502},
    {"hands", 275},
    {"hao", 815},
    {"haos", 815},
    {"hartley", 462},
    {"hartleys", 462},
    {"hartree", 588},
    {"hartrees", 588},
    {"hath", 582},
    {"haths", 582},
    {"hb", 1297},
    {"hbps", 1299},
    {"hcd", 1269},
    {"hcentury", 1303},
    {"heV", 1294},
    {"heap", 537},
    {"heaps", 537},
    {"heat capacity", 650},
    {"heat flux", 654},
    {"heat_capacity", 650},
    {"hectare", 73},
    {"hectares", 73},
    {"hekat", 805},
    {"hekats", 805},
    {"helek", 519},
    {"henries", 19},
    {"henry", 19},
    {"henrys", 19},
    {"heqat", 805},
    {"heqats", 805},
    {"hertz", 7},
    {"hfortnight", 1302},
    {"hg", 1264},
    {"hin", 509},
    {"hins", 509},
    {"hkat", 1291},
    {"hl", 1293},
    {"hlm", 1286},
    {"hlx", 1287},
    {"hm", 1263},
    {"hmol", 1268},
    {"hogshead", 347},
    {"hogsheads", 347},
    {"hole", 538},
    {"holes", 538},
    {"horsepower", 377},
    {"hounsfield", 803},
    {"hounsfield_unit", 803},
    {"hour", 309},
    {"hours", 309},
    {"hp", 377},
    {"hpc", 1301},
    {"hs", 1265},
    {"ht", 1296},
    {"hvar", 1271},
    {"h\xce\xa9", 1280},
    {"imp gal", 334},
    {"imperial bottle", 356},
    {"imperial gallon", 334},
    {"imperial gallons", 334},
    {"imperial pint", 607},
    {"imperial pints", 607},
    {"imperial_pint", 607},
    {"impgal", 334},
    {"impulse", 675},
    {"in", 60},
    {"in H2O", 635},
    {"in of water", 635},
    {"inH2O", 635},
    {"inHg", 364},
    {"inch", 60},
    {"inch of water", 635},
    {"inches", 60},
    {"inches of water", 635},
    {"indian kos", 584},
    {"instant", 442},
    {"instants", 442},
    {"instruction", 453},
    {"instructions", 453},
    {"international table calorie", 369},
    {"international unit", 717},
    {"international units", 717},
    {"inv_ab", 479},
    {"inv_fb", 478},
    {"inv_nb", 481},
    {"inv_pb", 480},
    {"inverse attobarn", 479},
    {"inverse femtobarn", 478},
    {"inverse nanobarn", 481},
    {"inverse picobarn", 480},
    {"io", 460},
    {"io_op", 460},
    {"io_ops", 460},
    {"iops", 873},
    {"ios", 460},
    {"isaron", 507},
    {"iso", 618},
    {"issaron", 507},
    {"iugera", 573},
    {"iugerum", 573},
    {"j", 438},
    {"jam", 438},
    {"janskies", 470},
    {"jansky", 470},
    {"janskys", 470},
    {"japanese cup", 606},
    {"japanese cups", 606},
    {"japanese_cup", 606},
    {"jelly", 438},
    {"jerk", 673},
    {"jeroboam", 355},
    {"jeroboams", 355},
    {"jiffies", 443},
    {"jiffy", 443},
    {"jigger", 343},
    {"jiggers", 343},
    {"jin", 555},
    {"jins", 555},
    {"jo", 542},
    {"jos", 542},
    {"joule", 10},
    {"joules", 10},
    {"joules per kelvin", 102},
    {"joules per operation", 678},
    {"joules per token", 679},
    {"jubilee", 522},
    {"jubilees", 522},
    {"jugerum", 573},
    {"julian year", 321},
    {"julian years", 321},
    {"julianyear", 321},
    {"jupiter mass", 404},
    {"jupitermass", 404},
    {"kA", 1231},
    {"kB", 1257},
    {"kBps", 1259},
    {"kBq", 1248},
    {"kC", 1239},
    {"kDa", 1255},
    {"kF", 1241},
    {"kFLOPS", 828},
    {"kGy", 1249},
    {"kH", 1242},
    {"kHz", 41},
    {"kJ", 45},
    {"kJy", 1235},
    {"kK", 1232},
    {"kL", 1252},
    {"kN", 1238},
    {"kPa", 57},
    {"kS", 1243},
    {"kSv", 1250},
    {"kT", 1245},
    {"kV", 55},
    {"kVA", 1237},
    {"kW", 48},
    {"kWb", 1244},
    {"kWh", 51},
    {"kab", 513},
    {"kabim", 513},
    {"kabs", 513},
    {"kanme", 548},
    {"kanmes", 548},
    {"kat", 26},
    {"kat/m\xc2\xb3", 667},
    {"katal", 26},
    {"katals", 26},
    {"kayser", 488},
    {"kaysers", 488},
    {"kb", 1256},
    {"kbps", 1258},
    {"kcal", 109},
    {"kcal_IT", 371},
    {"kcal_th", 372},
    {"kcd", 1234},
    {"kcentury", 1262},
    {"keV", 1254},
    {"kelvin", 4},
    {"kelvin difference", 262},
    {"kflops", 827},
    {"kfortnight", 1261},
    {"kg", 1},
    {"kg CO2e", 681},
    {"kg/m", 661},
    {"kg/m\xc2\xb2", 662},
    {"kg/m\xc2\xb3", 646},
    {"kg/s", 649},
    {"kgCO\xe2\x82\x82\x65", 681},
    {"kgf", 367},
    {"kg\xc2\xb7m/s", 674},
    {"khar", 807},
    {"khars", 807},
    {"khet", 580},
    {"khets", 580},
    {"kikar", 516},
    {"kilderkin", 351},
    {"kilderkins", 351},
    {"kilocalorie", 109},
    {"kilocalories", 109},
    {"kilogram", 1},
    {"kilogram force", 367},
    {"kilogram-force", 367},
    {"kilograms", 1},
    {"kilograms CO2e", 681},
    {"kilograms per cubic meter", 646},
    {"kilograms per second", 649},
    {"kiloton", 531},
    {"kilotons", 531},
    {"kilowarhol", 423},
    {"kilowarhols", 423},
    {"kilowatt hour", 51},
    {"kilowatt hours", 51},
    {"kilowatt-hour", 51},
    {"kilowatt-hours", 51},
    {"kkat", 1251},
    {"kl", 1253},
    {"klm", 1246},
    {"klx", 1247},
    {"km", 27},
    {"km/h", 81},
    {"kmol", 1233},
    {"km\xc2\xb2", 72},
    {"kn", 281},
    {"knot", 281},
    {"knots", 281},
    {"koku", 545},
    {"kokus", 545},
    {"kor", 512},
    {"korim", 512},
    {"kors", 512},
    {"kos", 584},
    {"kos_indian", 584},
    {"kpc", 1260},
    {"kph", 282},
    {"ks", 1230},
    {"kt", 281},
    {"ktok/s", 858},
    {"kvar", 1236},
    {"k\xce\xa9", 1240},
    {"l", 329},
    {"l/100km", 529},
    {"lambert", 430},
    {"lamberts", 430},
    {"lb", 65},
    {"lbf", 366},
    {"lbs", 119},
    {"league", 276},
    {"leagues", 276},
    {"li", 553},
    {"liang", 556},
    {"liangs", 556},
    {"libra romana", 574},
    {"libra_roma", 574},
    {"lieue de poste", 569},
    {"lieue_de_poste", 569},
    {"lieues de poste", 569},
    {"light hour", 286},
    {"light hours", 286},
    {"light minute", 285},
    {"light minutes", 285},
    {"light nanosecond", 644},
    {"light second", 284},
    {"light seconds", 284},
    {"light year", 115},
    {"light years", 115},
    {"light-nanosecond", 644},
    {"light_nanosecond", 644},
    {"lighthour", 286},
    {"lighthours", 286},
    {"lightminute", 285},
    {"lightminutes", 285},
    {"lightsecond", 284},
    {"lightseconds", 284},
    {"lightyear", 115},
    {"lightyears", 115},
    {"linear density", 661},
    {"link", 626},
    {"link_chain", 626},
    {"links", 626},
    {"lis", 553},
    {"liter", 78},
    {"liters", 78},
    {"liters per 100 km", 529},
    {"liters per minute", 648},
    {"litre", 78},
    {"litres", 78},
    {"litres per minute", 648},
    {"lm", 21},
    {"lm\xc2\xb7s", 670},
    {"long ton", 295},
    {"long tons", 295},
    {"lumen", 21},
    {"lumens", 21},
    {"luminous energy", 670},
    {"luminous exposure", 669},
    {"lunar month", 323},
    {"lunar months", 323},
    {"lunarmonth", 323},
    {"lustra", 324},
    {"lustrum", 324},
    {"lustrums", 324},
    {"lux", 22},
    {"lx", 22},
    {"lx\xc2\xb7s", 669},
    {"ly", 115},
    {"m", 0},
    {"m H2O", 634},
    {"m of water", 634},
    {"m/s", 80},
    {"m/s\xc2\xb2", 83},
    {"m/s\xc2\xb3", 673},
    {"mA", 53},
    {"mB", 1455},
    {"mBps", 1457},
    {"mBq", 1446},
    {"mC", 1437},
    {"mDa", 1452},
    {"mEq/L", 711},
    {"mF", 1439},
    {"mGal", 771},
    {"mGy", 1447},
    {"mH", 1440},
    {"mH2O", 634},
    {"mHz", 1435},
    {"mJ", 1432},
    {"mJy", 1428},
    {"mK", 1425},
    {"mL", 79},
    {"mM", 699},
    {"mN", 1431},
    {"mOsm/L", 714},
    {"mPa", 1434},
    {"mS", 1441},
    {"mSv", 1448},
    {"mT", 1443},
    {"mV", 1436},
    {"mVA", 1430},
    {"mW", 1433},
    {"mWb", 1442},
    {"m_e", 595},
    {"m_n", 597},
    {"m_p", 596},
    {"m_\xce\xbc", 598},
    {"mac", 452},
    {"mace", 817},
    {"maces", 817},
    {"mach", 283},
    {"mach_air_20C", 696},
    {"macs", 452},
    {"mag", 471},
    {"magnitude", 471},
    {"magnitudes", 471},
    {"magnum", 354},
    {"magnums", 354},
    {"maneh", 515},
    {"mas", 762},
    {"mass density", 646},
    {"mass flow", 649},
    {"maund", 587},
    {"maunds", 587},
    {"maxwell", 426},
    {"maxwells", 426},
    {"mb", 1454},
    {"mbar", 112},
    {"mbps", 1456},
    {"mcd", 1427},
    {"mcentury", 1460},
    {"meV", 1451},
    {"megaton", 532},
    {"megatons", 532},
    {"melchizedek", 358},
    {"melchizedeks", 358},
    {"meter", 0},
    {"meter of water", 634},
    {"meters", 0},
    {"meters of water", 634},
    {"methuselah", 356},
    {"methuselahs", 356},
    {"metric cup", 603},
    {"metric cups", 603},
    {"metric tablespoon", 604},
    {"metric tablespoons", 604},
    {"metric tbsp", 604},
    {"metric ton", 36},
    {"metric tons", 36},
    {"metric_cup", 603},
    {"metric_tbsp", 604},
    {"mfortnight", 1459},
    {"mg", 34},
    {"mg/L", 704},
    {"mg/dL", 705},
    {"mg/dL glucose", 694},
    {"mg/dL_glucose", 694},
    {"mho", 16},
    {"mi", 63},
    {"mi/h", 122},
    {"mickey", 642},
    {"mickeys", 642},
    {"microarcsecond", 763},
    {"microarcseconds", 763},
    {"microlife", 487},
    {"microlives", 487},
    {"micromolar", 700},
    {"micromort", 486},
    {"micromorts", 486},
    {"mil", 387},
    {"mile", 63},
    {"mile per hour", 82},
    {"miles", 63},
    {"miles per gallon", 527},
    {"miles per gallon equivalent", 528},
    {"miles per hour", 82},
    {"mill_finance", 624},
    {"mille passuum", 572},
    {"mille_passuum", 572},
    {"millennia", 315},
    {"millennium", 315},
    {"millenniums", 315},
    {"milliarcsecond", 762},
    {"milliarcseconds", 762},
    {"milligal", 771},
    {"milligals", 771},
    {"millihelen", 427},
    {"millihelens", 427},
    {"millimolar", 699},
    {"mils", 387},
    {"min", 308},
    {"mina", 515},
    {"minas", 515},
    {"minute", 308},
    {"minutes", 308},
    {"mkat", 1449},
    {"ml", 1450},
    {"mlm", 1444},
    {"mlx", 1445},
    {"mm", 29},
    {"mmHg", 363},
    {"mmol", 1426},
    {"mmol/L", 699},
    {"mmol/L glucose", 695},
    {"mmol/L_glucose", 695},
    {"mo", 312},
    {"mohs", 489},
    {"mol", 5},
    {"mol/L", 698},
    {"mol/mol", 666},
    {"mol/m\xc2\xb3", 702},
    {"mol_photon/m\xc2\xb2/s", 753},
    {"molal", 878},
    {"molar", 877},
    {"molar concentration", 697},
    {"molarity", 697},
    {"mole", 5},
    {"mole fraction", 666},
    {"moles", 5},
    {"moment", 444},
    {"moment magnitude", 800},
    {"moment_magnitude", 800},
    {"moments", 444},
    {"momentum", 674},
    {"momme", 547},
    {"mommes", 547},
    {"month", 312},
    {"months", 312},
    {"moon mass", 405},
    {"moonmass", 405},
    {"mpc", 1458},
    {"mpg", 527},
    {"mpge", 528},
    {"mph", 82},
    {"ms", 37},
    {"mt", 1453},
    {"mu", 554},
    {"muB", 485},
    {"muon mass", 598},
    {"muon_mass", 598},
    {"mus", 554},
    {"mvar", 1429},
    {"m\xc2\xb2", 70},
    {"m\xc2\xb3", 76},
    {"m\xc2\xb3/(kg\xc2\xb7s\xc2\xb2)", 100},
    {"m\xc2\xb3/s", 647},
    {"m\xce\xa9", 1438},
    {"m\xe2\x82\x9a\xe2\x82\x97", 299},
    {"nA", 1581},
    {"nB", 1613},
    {"nBps", 1615},
    {"nBq", 1603},
    {"nC", 1594},
    {"nDa", 1610},
    {"nF", 1596},
    {"nGy", 1604},
    {"nH", 1597},
    {"nHz", 1592},
    {"nJ", 1589},
    {"nJy", 1585},
    {"nK", 1582},
    {"nL", 1607},
    {"nM", 701},
    {"nN", 1588},
    {"nPa", 1591},
    {"nS", 1598},
    {"nSv", 1605},
    {"nT", 1600},
    {"nV", 1593},
    {"nVA", 1587},
    {"nW", 1590},
    {"nWb", 1599},
    {"nail_cloth", 632},
    {"nanobarn", 477},
    {"nanobarns", 477},
    {"nanomolar", 701},
    {"nat", 461},
    {"nats", 461},
    {"nautical mile", 114},
    {"nautical miles", 114},
    {"nb", 1612},
    {"nb-1", 481},
    {"nb^-1", 481},
    {"nbarn", 477},
    {"nbps", 1614},
    {"nb\xe2\x81\xbb\xc2\xb9", 481},
    {"ncd", 1584},
    {"ncentury", 1618},
    {"neV", 1609},
    {"nebuchadnezzar", 357},
    {"nebuchadnezzars", 357},
    {"neutron mass", 597},
    {"neutron_mass", 597},
    {"newton", 8},
    {"newtons", 8},
    {"newtons per meter", 660},
    {"nfortnight", 1617},
    {"ng", 1580},
    {"ng/mL", 708},
    {"nibble", 391},
    {"nibbles", 391},
    {"nit", 428},
    {"nits", 428},
    {"nkat", 1606},
    {"nl", 1608},
    {"nlm", 1601},
    {"nlx", 1602},
    {"nm", 31},
    {"nmi", 114},
    {"nmol", 1583},
    {"nmol/L", 701},
    {"nominal solar luminosity", 765},
    {"nominal solar radius", 764},
    {"normality", 710},
    {"npc", 1616},
    {"ns", 39},
    {"nt", 1611},
    {"nvar", 1586},
    {"n\xce\xa9", 1595},
    {"o", 392},
    {"octave", 622},
    {"octaves", 622},
    {"octet", 392},
    {"octets", 392},
    {"oersted", 482},
    {"oersteds", 482},
    {"ohm", 15},
    {"ohm meter", 657},
    {"ohms", 15},
    {"oil barrel", 534},
    {"oil barrels", 534},
    {"oil_barrel", 534},
    {"omer", 507},
    {"omers", 507},
    {"onah", 521},
    {"onot", 521},
    {"op", 451},
    {"op/J", 792},
    {"operations per joule", 792},
    {"ops", 451},
    {"ops_per_s", 843},
    {"osmol", 712},
    {"osmolar", 713},
    {"osmole", 712},
    {"osmoles", 712},
    {"ounce", 64},
    {"ounces", 64},
    {"outhouse", 414},
    {"oz", 64},
    {"ozt", 304},
    {"pA", 1620},
    {"pB", 1650},
    {"pBps", 1652},
    {"pBq", 1642},
    {"pC", 1633},
    {"pDa", 1649},
    {"pF", 1635},
    {"pGy", 1643},
    {"pH", 1636},
    {"pHz", 1631},
    {"pJ", 1628},
    {"pJy", 1624},
    {"pK", 1621},
    {"pL", 1646},
    {"pN", 1627},
    {"pPa", 1630},
    {"pS", 1637},
    {"pSv", 1644},
    {"pT", 1639},
    {"pV", 1632},
    {"pVA", 1626},
    {"pW", 1629},
    {"pWb", 1638},
    {"packet", 459},
    {"packets", 459},
    {"page", 613},
    {"pages", 613},
    {"palm", 502},
    {"palms", 502},
    {"paragraph", 611},
    {"paragraphs", 611},
    {"parsa", 505},
    {"parsec", 117},
    {"parsecs", 117},
    {"parts per billion", 465},
    {"parts per billion by volume", 777},
    {"parts per hundred million", 467},
    {"parts per million", 464},
    {"parts per million by mass", 778},
    {"parts per million by volume", 776},
    {"parts per trillion", 466},
    {"parts-per-billion", 465},
    {"parts-per-million", 464},
    {"parts-per-trillion", 466},
    {"pascal", 9},
    {"pascals", 9},
    {"passus", 571},
    {"passuses", 571},
    {"pb", 437},
    {"pb-1", 480},
    {"pb^-1", 480},
    {"pbarn", 476},
    {"pbps", 1651},
    {"pb\xe2\x81\xbb\xc2\xb9", 480},
    {"pc", 117},
    {"pcd", 1623},
    {"pcentury", 1655},
    {"peV", 1648},
    {"peanut butter", 437},
    {"peanutbutter", 437},
    {"peck", 336},
    {"pecks", 336},
    {"pedes", 570},
    {"pennyweight", 305},
    {"pennyweights", 305},
    {"percent grade", 810},
    {"percent grades", 810},
    {"percent_grade", 810},
    {"perch", 628},
    {"perches", 628},
    {"person hour", 691},
    {"person hours", 691},
    {"person_hour", 691},
    {"pes", 570},
    {"petabyte", 94},
    {"petabytes", 94},
    {"petroleum barrel", 534},
    {"petroleum_barrel", 534},
    {"pfortnight", 1654},
    {"pg", 1619},
    {"phon", 469},
    {"phons", 469},
    {"phot", 743},
    {"photon", 751},
    {"photons", 751},
    {"photosynthetic photon flux density", 754},
    {"phots", 743},
    {"pica", 409},
    {"picas", 409},
    {"piccolo", 352},
    {"picobarn", 476},
    {"picobarns", 476},
    {"pied", 565},
    {"pied du roi", 565},
    {"pieds", 565},
    {"pieds du roi", 565},
    {"pieze", 637},
    {"pinch", 341},
    {"pinches", 341},
    {"pint", 69},
    {"pints", 69},
    {"pip", 625},
    {"pipe", 349},
    {"pipes", 349},
    {"pips", 625},
    {"pixel", 685},
    {"pixels", 685},
    {"pk", 336},
    {"pkat", 1645},
    {"pl", 1647},
    {"planck length", 287},
    {"planck mass", 299},
    {"planck time", 326},
    {"plaque forming unit", 719},
    {"plaque-forming unit", 719},
    {"plm", 1640},
    {"plx", 1641},
    {"pm", 32},
    {"pmol", 1622},
    {"point", 408},
    {"points", 408},
    {"poise", 398},
    {"potential vorticity unit", 768},
    {"potential vorticity units", 768},
    {"pouce", 566},
    {"pouces", 566},
    {"pound", 65},
    {"pound force", 366},
    {"pound-force", 366},
    {"pounds", 65},
    {"ppb", 465},
    {"ppbv", 777},
    {"ppc", 1653},
    {"pphm", 467},
    {"ppm", 464},
    {"ppmv", 776},
    {"ppmw", 778},
    {"pps", 871},
    {"ppt", 466},
    {"proton mass", 596},
    {"proton_mass", 596},
    {"ps", 40},
    {"psi", 361},
    {"pt", 69},
    {"pud", 562},
    {"puds", 562},
    {"puncheon", 348},
    {"puncheons", 348},
    {"pvar", 1625},
    {"px", 685},
    {"p\xce\xa9", 1634},
    {"qA", 1861},
    {"qB", 1892},
    {"qBps", 1894},
    {"qBq", 1883},
    {"qC", 1874},
    {"qDa", 1890},
    {"qF", 1876},
    {"qGy", 1884},
    {"qH", 1877},
    {"qHz", 1872},
    {"qJ", 1869},
    {"qJy", 1865},
    {"qK", 1862},
    {"qL", 1887},
    {"qN", 1868},
    {"qPa", 1871},
    {"qS", 1878},
    {"qSv", 1885},
    {"qT", 1880},
    {"qV", 1873},
    {"qVA", 1867},
    {"qW", 1870},
    {"qWb", 1879},
    {"qb", 1891},
    {"qbps", 1893},
    {"qcd", 1864},
    {"qcentury", 1897},
    {"qeV", 1889},
    {"qfortnight", 1896},
    {"qg", 1859},
    {"qian", 817},
    {"qians", 817},
    {"qing", 816},
    {"qings", 816},
    {"qkat", 1886},
    {"ql", 1888},
    {"qlm", 1881},
    {"qlx", 1882},
    {"qm", 1858},
    {"qmol", 1863},
    {"qpc", 1895},
    {"qps", 865},
    {"qquad", 436},
    {"qr", 291},
    {"qs", 1860},
    {"qt", 68},
    {"quad", 434},
    {"quality adjusted life year", 692},
    {"quality-adjusted life year", 692},
    {"quart", 68},
    {"quarter", 291},
    {"quarters", 291},
    {"quarts", 68},
    {"queries", 456},
    {"query", 456},
    {"quintal", 307},
    {"quintals", 307},
    {"qvar", 1866},
    {"qword", 610},
    {"qwords", 610},
    {"q\xce\xa9", 1875},
    {"rA", 1820},
    {"rB", 1852},
    {"rBps", 1854},
    {"rBq", 1842},
    {"rC", 1833},
    {"rDa", 1849},
    {"rF", 1835},
    {"rGy", 1843},
    {"rH", 1836},
    {"rHz", 1831},
    {"rJ", 1828},
    {"rJy", 1824},
    {"rK", 1821},
    {"rL", 1846},
    {"rN", 1827},
    {"rPa", 1830},
    {"rS", 1837},
    {"rSv", 1844},
    {"rT", 1839},
    {"rV", 1832},
    {"rVA", 1826},
    {"rW", 1829},
    {"rWb", 1838},
    {"rack unit", 277},
    {"rack units", 277},
    {"rad", 84},
    {"rad/s", 671},
    {"rad/s\xc2\xb2", 672},
    {"rad_dose", 755},
    {"radian", 84},
    {"radiance", 747},
    {"radians", 84},
    {"radiant exposure", 750},
    {"radiant intensity", 746},
    {"radiation absorbed dose", 755},
    {"rankine", 256},
    {"rankine difference", 265},
    {"rb", 1851},
    {"rbe", 802},
    {"rbps", 1853},
    {"rcd", 1823},
    {"rcentury", 1857},
    {"rd", 425},
    {"reV", 1848},
    {"reactive power", 729},
    {"reaumur", 259},
    {"rega", 520},
    {"regaim", 520},
    {"rehoboam", 355},
    {"relative biological effectiveness", 802},
    {"rem", 381},
    {"rem_css", 688},
    {"rems", 381},
    {"request", 457},
    {"requests", 457},
    {"resistivity", 657},
    {"rev", 447},
    {"revolution", 447},
    {"revolutions", 447},
    {"revolutions per minute", 424},
    {"revs", 447},
    {"rfortnight", 1856},
    {"rg", 1818},
    {"ri", 541},
    {"richter", 799},
    {"richter scale", 799},
    {"rkat", 1845},
    {"rl", 1847},
    {"rlm", 1840},
    {"rlx", 1841},
    {"rm", 1817},
    {"rmol", 1822},
    {"ro", 806},
    {"rockwell", 491},
    {"rod", 272},
    {"rods", 272},
    {"roentgen", 756},
    {"roentgens", 756},
    {"roman libra", 574},
    {"roman mile", 572},
    {"roman uncia", 575},
    {"romer", 260},
    {"rope", 627},
    {"ropes", 627},
    {"ros", 806},
    {"rot", 449},
    {"rotation", 449},
    {"rotations", 449},
    {"rotations per minute", 424},
    {"royal cubit", 577},
    {"royal cubits", 577},
    {"royal_cubit", 577},
    {"rpc", 1855},
    {"rpm", 424},
    {"rps", 867},
    {"rs", 1819},
    {"rt", 1850},
    {"rundlet", 345},
    {"rundlets", 345},
    {"russian funt", 563},
    {"russian_funt", 563},
    {"rutherford", 425},
    {"rutherfords", 425},
    {"rvar", 1825},
    {"rydberg", 589},
    {"rydberg_unit", 589},
    {"rydbergs", 589},
    {"r\xc3\xa9\x61umur", 259},
    {"r\xc3\xb8mer", 260},
    {"r\xce\xa9", 1834},
    {"s", 2},
    {"sabbath day's journey", 506},
    {"sabbatical", 523},
    {"saffir simpson", 796},
    {"saffir_simpson", 796},
    {"sagan", 643},
    {"sagans", 643},
    {"sample", 445},
    {"samples", 445},
    {"savart", 621},
    {"savarts", 621},
    {"sazhen", 560},
    {"sazhens", 560},
    {"sb", 429},
    {"score", 496},
    {"scores", 496},
    {"scruple", 300},
    {"scruples", 300},
    {"seah", 511},
    {"seahs", 511},
    {"second", 2},
    {"seconds", 2},
    {"sector", 612},
    {"sectors", 612},
    {"seer", 586},
    {"seers", 586},
    {"seim", 511},
    {"seked", 812},
    {"sekeds", 812},
    {"semitone", 620},
    {"semitones", 620},
    {"shaftment", 630},
    {"shaftments", 630},
    {"shake", 318},
    {"shakes", 318},
    {"shaku", 539},
    {"shakus", 539},
    {"shed", 415},
    {"shekalim", 514},
    {"shekel", 514},
    {"shekels", 514},
    {"sheng", 819},
    {"shengs", 819},
    {"shesep", 578},
    {"sheseps", 578},
    {"shmita", 523},
    {"shmitas", 523},
    {"shmitta", 523},
    {"short cubit", 804},
    {"short cubits", 804},
    {"short ton", 294},
    {"short tons", 294},
    {"short_cubit", 804},
    {"sidereal day", 322},
    {"sidereal days", 322},
    {"sidereal year", 319},
    {"sidereal years", 319},
    {"siderealday", 322},
    {"siderealyear", 319},
    {"siemens", 16},
    {"siemens per meter", 658},
    {"sievert", 25},
    {"sieverts", 25},
    {"sk", 433},
    {"skot", 433},
    {"skots", 433},
    {"slope", 809},
    {"slopes", 809},
    {"slug", 298},
    {"slugs", 298},
    {"smidgen", 342},
    {"smidgens", 342},
    {"smoot", 274},
    {"smoots", 274},
    {"solar mass", 402},
    {"solar radius", 406},
    {"solarmass", 402},
    {"solarradius", 406},
    {"sone", 468},
    {"sones", 468},
    {"span", 501},
    {"spans", 501},
    {"specific energy", 665},
    {"specific heat capacity", 652},
    {"specific_energy", 665},
    {"spectral efficiency", 677},
    {"spectral flux density", 748},
    {"split", 352},
    {"splits", 352},
    {"sq ft", 120},
    {"sqft", 120},
    {"sqm", 121},
    {"square feet", 120},
    {"square foot", 120},
    {"sr", 86},
    {"st", 290},
    {"standard gravity", 524},
    {"statA", 732},
    {"statC", 734},
    {"statF", 740},
    {"statH", 742},
    {"statV", 736},
    {"statampere", 732},
    {"statcoulomb", 734},
    {"statfarad", 740},
    {"stathenry", 742},
    {"statohm", 738},
    {"statvolt", 736},
    {"stat\xce\xa9", 738},
    {"steradian", 86},
    {"steradians", 86},
    {"stere", 417},
    {"stick", 530},
    {"stick of butter", 530},
    {"sticks", 530},
    {"sticks of butter", 530},
    {"stilb", 429},
    {"stilbs", 429},
    {"stokes", 400},
    {"stone", 290},
    {"stones", 290},
    {"stop", 616},
    {"stops", 616},
    {"story point", 693},
    {"story points", 693},
    {"story_point", 693},
    {"st\xc3\xa8re", 417},
    {"st\xc3\xa8res", 417},
    {"sun", 540},
    {"suns", 540},
    {"surface tension", 660},
    {"svedberg", 727},
    {"svedbergs", 727},
    {"sverdrup", 769},
    {"sverdrups", 769},
    {"symbol", 779},
    {"symbols", 779},
    {"synodic month", 323},
    {"synodic months", 323},
    {"t", 36},
    {"tablespoon", 337},
    {"tablespoons", 337},
    {"talent", 516},
    {"talents", 516},
    {"talmudic mil", 504},
    {"talmudic_mil", 504},
    {"tatami", 544},
    {"tatamis", 544},
    {"tbsp", 337},
    {"tce", 536},
    {"teaspoon", 338},
    {"teaspoons", 338},
    {"techum", 506},
    {"techum shabbat", 506},
    {"tefach", 502},
    {"tefachim", 502},
    {"tenth cent", 624},
    {"tenth_cent", 624},
    {"tertian", 348},
    {"tesla", 18},
    {"teslas", 18},
    {"tex", 639},
    {"texpt", 410},
    {"therm", 374},
    {"thermal conductivity", 653},
    {"thermochemical calorie", 370},
    {"thermochemical kilocalorie", 372},
    {"therms", 374},
    {"tick", 446},
    {"ticks", 446},
    {"tierce", 346},
    {"tierces", 346},
    {"tn", 294},
    {"toise", 567},
    {"toises", 567},
    {"tok", 454},
    {"tok/J", 793},
    {"tok/s", 857},
    {"token", 454},
    {"tokens", 454},
    {"tokens per joule", 793},
    {"tola", 585},
    {"tolas", 585},
    {"ton", 294},
    {"tonne", 36},
    {"tonne of coal equivalent", 536},
    {"tonnes", 36},
    {"tons", 294},
    {"torque", 676},
    {"torr", 362},
    {"torrs", 362},
    {"total electron content unit", 773},
    {"tps", 869},
    {"transaction", 458},
    {"transactions", 458},
    {"transfer", 455},
    {"transfers", 455},
    {"transport carbon intensity", 684},
    {"traversed edges per second", 875},
    {"tropical year", 320},
    {"tropical years", 320},
    {"tropicalyear", 320},
    {"troy ounce", 304},
    {"troy ounces", 304},
    {"troyounce", 304},
    {"tsp", 338},
    {"tsubo", 543},
    {"tsubos", 543},
    {"tun", 350},
    {"tuns", 350},
    {"turn", 386},
    {"turns", 386},
    {"txn", 458},
    {"t\xe2\x82\x9a", 326},
    {"u", 297},
    {"uA", 1464},
    {"uB", 1496},
    {"uBps", 1498},
    {"uBq", 1486},
    {"uC", 1477},
    {"uDa", 1493},
    {"uF", 1479},
    {"uGy", 1487},
    {"uH", 1480},
    {"uHz", 1475},
    {"uJ", 1472},
    {"uJy", 1468},
    {"uK", 1465},
    {"uL", 1490},
    {"uM", 700},
    {"uN", 1471},
    {"uPa", 1474},
    {"uS", 1481},
    {"uSv", 1488},
    {"uT", 1483},
    {"uV", 1476},
    {"uVA", 1470},
    {"uW", 1473},
    {"uWb", 1482},
    {"uas", 763},
    {"ub", 1495},
    {"ubps", 1497},
    {"ucd", 1467},
    {"ucentury", 1501},
    {"ueV", 1492},
    {"ufortnight", 1500},
    {"ug", 1462},
    {"ukat", 1489},
    {"ul", 1491},
    {"ulm", 1484},
    {"ulx", 1485},
    {"um", 1461},
    {"umol", 1466},
    {"uncia_roma", 575},
    {"upc", 1499},
    {"update", 781},
    {"updates", 781},
    {"us", 1463},
    {"ut", 1494},
    {"uvar", 1469},
    {"u\xce\xa9", 1478},
    {"var", 729},
    {"vershok", 561},
    {"vershoks", 561},
    {"verst", 558},
    {"versts", 558},
    {"vh", 690},
    {"vickers", 490},
    {"viewport height", 690},
    {"viewport width", 689},
    {"volt", 13},
    {"volt ampere", 730},
    {"volt-ampere", 730},
    {"volts", 13},
    {"volts per meter", 655},
    {"volumetric flow", 647},
    {"vw", 689},
    {"warhol", 422},
    {"warhols", 422},
    {"water horsepower", 601},
    {"water_horsepower", 601},
    {"watt", 11},
    {"watts", 11},
    {"watts per square meter", 654},
    {"wavenumber", 488},
    {"weber", 17},
    {"webers", 17},
    {"wedgwood", 261},
    {"week", 311},
    {"weeks", 311},
    {"wk", 311},
    {"yA", 1779},
    {"yB", 1811},
    {"yBps", 1813},
    {"yBq", 1801},
    {"yC", 1792},
    {"yDa", 1808},
    {"yF", 1794},
    {"yGy", 1802},
    {"yH", 1795},
    {"yHz", 1790},
    {"yJ", 1787},
    {"yJy", 1783},
    {"yK", 1780},
    {"yL", 1805},
    {"yN", 1786},
    {"yPa", 1789},
    {"yS", 1796},
    {"ySv", 1803},
    {"yT", 1798},
    {"yV", 1791},
    {"yVA", 1785},
    {"yW", 1788},
    {"yWb", 1797},
    {"yard", 62},
    {"yards", 62},
    {"yb", 1810},
    {"ybps", 1812},
    {"ycd", 1782},
    {"ycentury", 1816},
    {"yd", 62},
    {"yeV", 1807},
    {"year", 313},
    {"years", 313},
    {"yfortnight", 1815},
    {"yg", 1777},
    {"yin", 813},
    {"yins", 813},
    {"ykat", 1804},
    {"yl", 1806},
    {"ylm", 1799},
    {"ylx", 1800},
    {"ym", 1776},
    {"ymol", 1781},
    {"yovel", 522},
    {"yovels", 522},
    {"ypc", 1814},
    {"yr", 313},
    {"ys", 1778},
    {"yt", 1809},
    {"yvar", 1784},
    {"y\xce\xa9", 1793},
    {"zA", 1738},
    {"zB", 1770},
    {"zBps", 1772},
    {"zBq", 1760},
    {"zC", 1751},
    {"zDa", 1767},
    {"zF", 1753},
    {"zGy", 1761},
    {"zH", 1754},
    {"zHz", 1749},
    {"zJ", 1746},
    {"zJy", 1742},
    {"zK", 1739},
    {"zL", 1764},
    {"zN", 1745},
    {"zPa", 1748},
    {"zS", 1755},
    {"zSv", 1762},
    {"zT", 1757},
    {"zV", 1750},
    {"zVA", 1744},
    {"zW", 1747},
    {"zWb", 1756},
    {"zb", 1769},
    {"zbps", 1771},
    {"zcd", 1741},
    {"zcentury", 1775},
    {"zeV", 1766},
    {"zeret", 501},
    {"zfortnight", 1774},
    {"zg", 1736},
    {"zhang", 552},
    {"zhangs", 552},
    {"zkat", 1763},
    {"zl", 1765},
    {"zlm", 1758},
    {"zlx", 1759},
    {"zm", 1735},
    {"zmol", 1740},
    {"zpc", 1773},
    {"zs", 1737},
    {"zt", 1768},
    {"zvar", 1743},
    {"z\xce\xa9", 1752},
    {"\xc2\xb0", 85},
    {"\xc2\xb0\x43", 20},
    {"\xc2\xb0\x44\x65", 257},
    {"\xc2\xb0\x46", 87},
    {"\xc2\xb0N", 258},
    {"\xc2\xb0R", 256},
    {"\xc2\xb0Ra", 256},
    {"\xc2\xb0Re", 259},
    {"\xc2\xb0R\xc3\xa9", 259},
    {"\xc2\xb0R\xc3\xb8", 260},
    {"\xc2\xb0W", 261},
    {"\xc2\xb0r", 259},
    {"\xc2\xb5\x41", 54},
    {"\xc2\xb5\x42", 1574},
    {"\xc2\xb5\x42ps", 1576},
    {"\xc2\xb5\x42q", 1564},
    {"\xc2\xb5\x43", 1555},
    {"\xc2\xb5\x44\x61", 1571},
    {"\xc2\xb5\x46", 1557},
    {"\xc2\xb5Gy", 1565},
    {"\xc2\xb5H", 1558},
    {"\xc2\xb5Hz", 1553},
    {"\xc2\xb5J", 1550},
    {"\xc2\xb5Jy", 1546},
    {"\xc2\xb5K", 1543},
    {"\xc2\xb5L", 1568},
    {"\xc2\xb5M", 700},
    {"\xc2\xb5N", 1549},
    {"\xc2\xb5Pa", 1552},
    {"\xc2\xb5S", 1559},
    {"\xc2\xb5Sv", 1566},
    {"\xc2\xb5T", 1561},
    {"\xc2\xb5V", 1554},
    {"\xc2\xb5VA", 1548},
    {"\xc2\xb5W", 1551},
    {"\xc2\xb5Wb", 1560},
    {"\xc2\xb5\x61s", 763},
    {"\xc2\xb5\x62", 1573},
    {"\xc2\xb5\x62ps", 1575},
    {"\xc2\xb5\x63\x64", 1545},
    {"\xc2\xb5\x63\x65ntury", 1579},
    {"\xc2\xb5\x65V", 1570},
    {"\xc2\xb5\x66ortnight", 1578},
    {"\xc2\xb5g", 35},
    {"\xc2\xb5g/mL", 707},
    {"\xc2\xb5kat", 1567},
    {"\xc2\xb5l", 1569},
    {"\xc2\xb5lm", 1562},
    {"\xc2\xb5lx", 1563},
    {"\xc2\xb5m", 30},
    {"\xc2\xb5mol", 1544},
    {"\xc2\xb5mol/L", 700},
    {"\xc2\xb5mol_photon/m\xc2\xb2/s", 754},
    {"\xc2\xb5pc", 1577},
    {"\xc2\xb5s", 38},
    {"\xc2\xb5t", 1572},
    {"\xc2\xb5var", 1547},
    {"\xc2\xb5\xce\xa9", 1556},
    {"\xc3\x85", 278},
    {"\xc3\xa5ngstr\xc3\xb6m", 278},
    {"\xc9\xa1", 524},
    {"\xca\x92", 301},
    {"\xce\x94K", 262},
    {"\xce\x94\xc2\xb0\x43", 263},
    {"\xce\x94\xc2\xb0\x44\x65", 266},
    {"\xce\x94\xc2\xb0\x46", 264},
    {"\xce\x94\xc2\xb0N", 267},
    {"\xce\x94\xc2\xb0R", 265},
    {"\xce\x94\xc2\xb0R\xc3\xa9", 268},
    {"\xce\x94\xc2\xb0R\xc3\xb8", 269},
    {"\xce\x94\xc2\xb0W", 270},
    {"\xce\xa9", 15},
    {"\xce\xa9\xc2\xb7m", 657},
    {"\xce\xb1", 594},
    {"\xce\xbc\x41", 1505},
    {"\xce\xbc\x42", 1537},
    {"\xce\xbc\x42ps", 1539},
    {"\xce\xbc\x42q", 1527},
    {"\xce\xbc\x43", 1518},
    {"\xce\xbc\x44\x61", 1534},
    {"\xce\xbc\x46", 1520},
    {"\xce\xbcGy", 1528},
    {"\xce\xbcH", 1521},
    {"\xce\xbcHz", 1516},
    {"\xce\xbcJ", 1513},
    {"\xce\xbcJy", 1509},
    {"\xce\xbcK", 1506},
    {"\xce\xbcL", 1531},
    {"\xce\xbcM", 700},
    {"\xce\xbcN", 1512},
    {"\xce\xbcPa", 1515},
    {"\xce\xbcS", 1522},
    {"\xce\xbcSv", 1529},
    {"\xce\xbcT", 1524},
    {"\xce\xbcV", 1517},
    {"\xce\xbcVA", 1511},
    {"\xce\xbcW", 1514},
    {"\xce\xbcWb", 1523},
    {"\xce\xbc_B", 485},
    {"\xce\xbc\x61s", 763},
    {"\xce\xbc\x62", 1536},
    {"\xce\xbc\x62ps", 1538},
    {"\xce\xbc\x63\x64", 1508},
    {"\xce\xbc\x63\x65ntury", 1542},
    {"\xce\xbc\x65V", 1533},
    {"\xce\xbc\x66ortnight", 1541},
    {"\xce\xbcg", 1503},
    {"\xce\xbckat", 1530},
    {"\xce\xbcl", 1532},
    {"\xce\xbclife", 487},
    {"\xce\xbclm", 1525},
    {"\xce\xbclx", 1526},
    {"\xce\xbcm", 1502},
    {"\xce\xbcmol", 1507},
    {"\xce\xbcmort", 486},
    {"\xce\xbcpc", 1540},
    {"\xce\xbcs", 1504},
    {"\xce\xbct", 1535},
    {"\xce\xbcvar", 1510},
    {"\xce\xbc\xce\xa9", 1519},
    {"\xe2\x84\x83", 20},
    {"\xe2\x84\x88", 300},
    {"\xe2\x84\x89", 87},
    {"\xe2\x84\x93\xe2\x82\x9a", 287},
    {"\xe2\x84\x94", 303},
    {"\xe2\x84\xa5", 302},
    {"\xe2\x84\xa7", 16},
    {"\xe3\x8d\xb3", 116},
};
static int unit_lookup_id(const char *name) {
    int lo = 0, hi = (int)(sizeof(unit_aliases) / sizeof(unit_aliases[0])) - 1;
    while (lo <= hi) {
        int mid = lo + (hi - lo) / 2;
        int cmp = strcmp(name, unit_aliases[mid].name);
        if (cmp == 0) return unit_aliases[mid].id;
        if (cmp < 0) hi = mid - 1; else lo = mid + 1;
    }
    return -1;
}
/* --- END GENERATED: unit_names --- */

/* --- BEGIN GENERATED: unit_info --- */
typedef struct { int8_t dim[8]; int16_t custom_id; int8_t custom_exp; int64_t num; int64_t den; int16_t factor_scale; int64_t off_num; int64_t off_den; } WUnitInfo;
static const char *custom_dimension_names[] = {
    NULL,
    "absorbed_dose",
    "angle",
    "apgar",
    "apparent_power",
    "batter",
    "beat",
    "beaufort",
    "beauty",
    "bortle",
    "cell_count",
    "cell_update",
    "chemical_equivalent",
    "co2e",
    "colony_forming_unit",
    "css_root_font_size",
    "cycle",
    "decay",
    "detector_count",
    "ef",
    "electron_column_density",
    "em",
    "entropy",
    "equivalent_dose",
    "exposure_value",
    "e\xe2\x82\x80",
    "f_stop",
    "fame",
    "flop",
    "frame",
    "fujita",
    "geopotential",
    "glucose_concentration",
    "graph_edge",
    "hardness_brinell",
    "hardness_mohs",
    "hardness_rockwell",
    "hardness_vickers",
    "heap",
    "heat_capacity",
    "hole",
    "hounsfield",
    "illuminance",
    "impulse",
    "instant",
    "instruction",
    "international_unit",
    "io",
    "ionizing_radiation_exposure",
    "iso_sensitivity",
    "jelly",
    "jiffy",
    "linear_density",
    "loudness",
    "loudness_level",
    "luminance",
    "luminous_flux",
    "luminous_intensity",
    "mac",
    "magnitude",
    "magnitude_absolute",
    "magnitude_apparent",
    "magnitude_bolometric",
    "mass_fraction",
    "molecular_copy",
    "moment",
    "momentum",
    "op",
    "osmotic_entity",
    "packet",
    "peanutbutter",
    "person",
    "photon",
    "pitch",
    "plaque_forming_unit",
    "quality_adjusted_life",
    "query",
    "ratio",
    "rbe",
    "reactive_power",
    "request",
    "revolution",
    "rotation",
    "saffir_simpson",
    "sample",
    "slope",
    "solid_angle",
    "specific_energy",
    "spectral_efficiency",
    "story_point",
    "symbol",
    "temperature_delta",
    "tick",
    "token",
    "torque",
    "transaction",
    "transfer",
    "transport_co2e",
    "viewport_height_percent",
    "viewport_width_percent",
    "volume_fraction",
};
/* non-const: the custom region takes synthesized compound units at runtime */
static WUnitInfo unit_info[W_UNIT_CAPACITY] = {
    [0] = {{1,0,0,0,0,0,0,0}, 0, 0, 1, 1, 0, 0, 1}, /* m */
    [1] = {{0,1,0,0,0,0,0,0}, 0, 0, 1, 1, 0, 0, 1}, /* kg */
    [2] = {{0,0,1,0,0,0,0,0}, 0, 0, 1, 1, 0, 0, 1}, /* s */
    [3] = {{0,0,0,1,0,0,0,0}, 0, 0, 1, 1, 0, 0, 1}, /* A */
    [4] = {{0,0,0,0,1,0,0,0}, 0, 0, 1, 1, 0, 0, 1}, /* K */
    [5] = {{0,0,0,0,0,1,0,0}, 0, 0, 1, 1, 0, 0, 1}, /* mol */
    [6] = {{0,0,0,0,0,0,1,0}, 57, 1, 1, 1, 0, 0, 1}, /* cd */
    [7] = {{0,0,-1,0,0,0,0,0}, 16, 1, 1, 1, 0, 0, 1}, /* Hz */
    [8] = {{1,1,-2,0,0,0,0,0}, 0, 0, 1, 1, 0, 0, 1}, /* N */
    [9] = {{-1,1,-2,0,0,0,0,0}, 0, 0, 1, 1, 0, 0, 1}, /* Pa */
    [10] = {{2,1,-2,0,0,0,0,0}, 0, 0, 1, 1, 0, 0, 1}, /* J */
    [11] = {{2,1,-3,0,0,0,0,0}, 0, 0, 1, 1, 0, 0, 1}, /* W */
    [12] = {{0,0,1,1,0,0,0,0}, 0, 0, 1, 1, 0, 0, 1}, /* C */
    [13] = {{2,1,-3,-1,0,0,0,0}, 0, 0, 1, 1, 0, 0, 1}, /* V */
    [14] = {{-2,-1,4,2,0,0,0,0}, 0, 0, 1, 1, 0, 0, 1}, /* F */
    [15] = {{2,1,-3,-2,0,0,0,0}, 0, 0, 1, 1, 0, 0, 1}, /* \xce\xa9 */
    [16] = {{-2,-1,3,2,0,0,0,0}, 0, 0, 1, 1, 0, 0, 1}, /* S */
    [17] = {{2,1,-2,-1,0,0,0,0}, 0, 0, 1, 1, 0, 0, 1}, /* Wb */
    [18] = {{0,1,-2,-1,0,0,0,0}, 0, 0, 1, 1, 0, 0, 1}, /* T */
    [19] = {{2,1,-2,-2,0,0,0,0}, 0, 0, 1, 1, 0, 0, 1}, /* H */
    [20] = {{0,0,0,0,1,0,0,0}, 0, 0, 1, 1, 0, 5463, 20}, /* \xc2\xb0\x43 */
    [21] = {{0,0,0,0,0,0,1,0}, 56, 1, 1, 1, 0, 0, 1}, /* lm */
    [22] = {{-2,0,0,0,0,0,1,0}, 42, 1, 1, 1, 0, 0, 1}, /* lx */
    [23] = {{0,0,-1,0,0,0,0,0}, 17, 1, 1, 1, 0, 0, 1}, /* Bq */
    [24] = {{2,0,-2,0,0,0,0,0}, 1, 1, 1, 1, 0, 0, 1}, /* Gy */
    [25] = {{2,0,-2,0,0,0,0,0}, 23, 1, 1, 1, 0, 0, 1}, /* Sv */
    [26] = {{0,0,-1,0,0,1,0,0}, 0, 0, 1, 1, 0, 0, 1}, /* kat */
    [27] = {{1,0,0,0,0,0,0,0}, 0, 0, 1, 1, 3, 0, 1}, /* km */
    [28] = {{1,0,0,0,0,0,0,0}, 0, 0, 1, 1, -2, 0, 1}, /* cm */
    [29] = {{1,0,0,0,0,0,0,0}, 0, 0, 1, 1, -3, 0, 1}, /* mm */
    [30] = {{1,0,0,0,0,0,0,0}, 0, 0, 1, 1, -6, 0, 1}, /* \xc2\xb5m */
    [31] = {{1,0,0,0,0,0,0,0}, 0, 0, 1, 1, -9, 0, 1}, /* nm */
    [32] = {{1,0,0,0,0,0,0,0}, 0, 0, 1, 1, -12, 0, 1}, /* pm */
    [33] = {{0,1,0,0,0,0,0,0}, 0, 0, 1, 1, -3, 0, 1}, /* g */
    [34] = {{0,1,0,0,0,0,0,0}, 0, 0, 1, 1, -6, 0, 1}, /* mg */
    [35] = {{0,1,0,0,0,0,0,0}, 0, 0, 1, 1, -9, 0, 1}, /* \xc2\xb5g */
    [36] = {{0,1,0,0,0,0,0,0}, 0, 0, 1, 1, 3, 0, 1}, /* t */
    [37] = {{0,0,1,0,0,0,0,0}, 0, 0, 1, 1, -3, 0, 1}, /* ms */
    [38] = {{0,0,1,0,0,0,0,0}, 0, 0, 1, 1, -6, 0, 1}, /* \xc2\xb5s */
    [39] = {{0,0,1,0,0,0,0,0}, 0, 0, 1, 1, -9, 0, 1}, /* ns */
    [40] = {{0,0,1,0,0,0,0,0}, 0, 0, 1, 1, -12, 0, 1}, /* ps */
    [41] = {{0,0,-1,0,0,0,0,0}, 16, 1, 1, 1, 3, 0, 1}, /* kHz */
    [42] = {{0,0,-1,0,0,0,0,0}, 16, 1, 1, 1, 6, 0, 1}, /* MHz */
    [43] = {{0,0,-1,0,0,0,0,0}, 16, 1, 1, 1, 9, 0, 1}, /* GHz */
    [44] = {{0,0,-1,0,0,0,0,0}, 16, 1, 1, 1, 12, 0, 1}, /* THz */
    [45] = {{2,1,-2,0,0,0,0,0}, 0, 0, 1, 1, 3, 0, 1}, /* kJ */
    [46] = {{2,1,-2,0,0,0,0,0}, 0, 0, 1, 1, 6, 0, 1}, /* MJ */
    [47] = {{2,1,-2,0,0,0,0,0}, 0, 0, 1, 1, 9, 0, 1}, /* GJ */
    [48] = {{2,1,-3,0,0,0,0,0}, 0, 0, 1, 1, 3, 0, 1}, /* kW */
    [49] = {{2,1,-3,0,0,0,0,0}, 0, 0, 1, 1, 6, 0, 1}, /* MW */
    [50] = {{2,1,-3,0,0,0,0,0}, 0, 0, 1, 1, 9, 0, 1}, /* GW */
    [51] = {{2,1,-2,0,0,0,0,0}, 0, 0, 36, 1, 5, 0, 1}, /* kWh */
    [52] = {{2,1,-2,0,0,0,0,0}, 0, 0, 36, 1, 8, 0, 1}, /* MWh */
    [53] = {{0,0,0,1,0,0,0,0}, 0, 0, 1, 1, -3, 0, 1}, /* mA */
    [54] = {{0,0,0,1,0,0,0,0}, 0, 0, 1, 1, -6, 0, 1}, /* \xc2\xb5\x41 */
    [55] = {{2,1,-3,-1,0,0,0,0}, 0, 0, 1, 1, 3, 0, 1}, /* kV */
    [56] = {{2,1,-3,-1,0,0,0,0}, 0, 0, 1, 1, 6, 0, 1}, /* MV */
    [57] = {{-1,1,-2,0,0,0,0,0}, 0, 0, 1, 1, 3, 0, 1}, /* kPa */
    [58] = {{-1,1,-2,0,0,0,0,0}, 0, 0, 1, 1, 6, 0, 1}, /* MPa */
    [59] = {{-1,1,-2,0,0,0,0,0}, 0, 0, 1, 1, 9, 0, 1}, /* GPa */
    [60] = {{1,0,0,0,0,0,0,0}, 0, 0, 127, 5, -3, 0, 1}, /* in */
    [61] = {{1,0,0,0,0,0,0,0}, 0, 0, 381, 125, -1, 0, 1}, /* ft */
    [62] = {{1,0,0,0,0,0,0,0}, 0, 0, 1143, 125, -1, 0, 1}, /* yd */
    [63] = {{1,0,0,0,0,0,0,0}, 0, 0, 201168, 125, 0, 0, 1}, /* mi */
    [64] = {{0,1,0,0,0,0,0,0}, 0, 0, 45359237, 16, -8, 0, 1}, /* oz */
    [65] = {{0,1,0,0,0,0,0,0}, 0, 0, 45359237, 1, -8, 0, 1}, /* lb */
    [66] = {{3,0,0,0,0,0,0,0}, 0, 0, 473176473, 16, -12, 0, 1}, /* fl oz */
    [67] = {{3,0,0,0,0,0,0,0}, 0, 0, 473176473, 125, -9, 0, 1}, /* gal */
    [68] = {{3,0,0,0,0,0,0,0}, 0, 0, 473176473, 5, -11, 0, 1}, /* qt */
    [69] = {{3,0,0,0,0,0,0,0}, 0, 0, 473176473, 1, -12, 0, 1}, /* pt */
    [70] = {{2,0,0,0,0,0,0,0}, 0, 0, 1, 1, 0, 0, 1}, /* m\xc2\xb2 */
    [71] = {{2,0,0,0,0,0,0,0}, 0, 0, 1, 1, -4, 0, 1}, /* cm\xc2\xb2 */
    [72] = {{2,0,0,0,0,0,0,0}, 0, 0, 1, 1, 6, 0, 1}, /* km\xc2\xb2 */
    [73] = {{2,0,0,0,0,0,0,0}, 0, 0, 1, 1, 4, 0, 1}, /* ha */
    [74] = {{2,0,0,0,0,0,0,0}, 0, 0, 316160658, 78125, 0, 0, 1}, /* acre */
    [75] = {{2,0,0,0,0,0,0,0}, 0, 0, 145161, 15625, -2, 0, 1}, /* ft\xc2\xb2 */
    [76] = {{3,0,0,0,0,0,0,0}, 0, 0, 1, 1, 0, 0, 1}, /* m\xc2\xb3 */
    [77] = {{3,0,0,0,0,0,0,0}, 0, 0, 1, 1, -6, 0, 1}, /* cm\xc2\xb3 */
    [78] = {{3,0,0,0,0,0,0,0}, 0, 0, 1, 1, -3, 0, 1}, /* L */
    [79] = {{3,0,0,0,0,0,0,0}, 0, 0, 1, 1, -6, 0, 1}, /* mL */
    [80] = {{1,0,-1,0,0,0,0,0}, 0, 0, 1, 1, 0, 0, 1}, /* m/s */
    [81] = {{1,0,-1,0,0,0,0,0}, 0, 0, 5, 18, 0, 0, 1}, /* km/h */
    [82] = {{1,0,-1,0,0,0,0,0}, 0, 0, 1397, 3125, 0, 0, 1}, /* mph */
    [83] = {{1,0,-2,0,0,0,0,0}, 0, 0, 1, 1, 0, 0, 1}, /* m/s\xc2\xb2 */
    [84] = {{0,0,0,0,0,0,0,0}, 2, 1, 1, 1, 0, 0, 1}, /* rad */
    [85] = {{0,0,0,0,0,0,0,0}, 2, 1, 14964008, 857374503, 0, 0, 1}, /* \xc2\xb0 */
    [86] = {{0,0,0,0,0,0,0,0}, 86, 1, 1, 1, 0, 0, 1}, /* sr */
    [87] = {{0,0,0,0,1,0,0,0}, 0, 0, 5, 9, 0, 45967, 180}, /* \xc2\xb0\x46 */
    [88] = {{0,0,0,0,0,0,0,1}, 0, 0, 1, 8, 0, 0, 1}, /* bit */
    [89] = {{0,0,0,0,0,0,0,1}, 0, 0, 1, 1, 0, 0, 1}, /* B */
    [90] = {{0,0,0,0,0,0,0,1}, 0, 0, 1, 1, 3, 0, 1}, /* KB */
    [91] = {{0,0,0,0,0,0,0,1}, 0, 0, 1, 1, 6, 0, 1}, /* MB */
    [92] = {{0,0,0,0,0,0,0,1}, 0, 0, 1, 1, 9, 0, 1}, /* GB */
    [93] = {{0,0,0,0,0,0,0,1}, 0, 0, 1, 1, 12, 0, 1}, /* TB */
    [94] = {{0,0,0,0,0,0,0,1}, 0, 0, 1, 1, 15, 0, 1}, /* PB */
    [95] = {{0,0,0,0,0,0,0,1}, 0, 0, 1024, 1, 0, 0, 1}, /* KiB */
    [96] = {{0,0,0,0,0,0,0,1}, 0, 0, 1048576, 1, 0, 0, 1}, /* MiB */
    [97] = {{0,0,0,0,0,0,0,1}, 0, 0, 1073741824, 1, 0, 0, 1}, /* GiB */
    [98] = {{0,0,0,0,0,0,0,1}, 0, 0, 1099511627776, 1, 0, 0, 1}, /* TiB */
    [99] = {{2,1,-1,0,0,0,0,0}, 0, 0, 1, 1, 0, 0, 1}, /* J\xc2\xb7s */
    [100] = {{3,-1,-2,0,0,0,0,0}, 0, 0, 1, 1, 0, 0, 1}, /* m\xc2\xb3/(kg\xc2\xb7s\xc2\xb2) */
    [101] = {{0,0,0,0,0,-1,0,0}, 0, 0, 1, 1, 0, 0, 1}, /* 1/mol */
    [102] = {{2,1,-2,0,-1,0,0,0}, 0, 0, 1, 1, 0, 0, 1}, /* J/K */
    [103] = {{2,1,-2,0,-1,-1,0,0}, 0, 0, 1, 1, 0, 0, 1}, /* J/(mol\xc2\xb7K) */
    [104] = {{-3,-1,4,2,0,0,0,0}, 0, 0, 1, 1, 0, 0, 1}, /* F/m */
    [105] = {{1,1,-2,-2,0,0,0,0}, 0, 0, 1, 1, 0, 0, 1}, /* N/A\xc2\xb2 */
    [106] = {{0,1,-3,0,-4,0,0,0}, 0, 0, 1, 1, 0, 0, 1}, /* W/(m\xc2\xb2\xc2\xb7K\xe2\x81\xb4) */
    [107] = {{2,1,-2,0,0,0,0,0}, 0, 0, 801088317, 5, -27, 0, 1}, /* eV */
    [108] = {{2,1,-2,0,0,0,0,0}, 0, 0, 10467, 25, -2, 0, 1}, /* cal */
    [109] = {{2,1,-2,0,0,0,0,0}, 0, 0, 20934, 5, 0, 0, 1}, /* kcal */
    [110] = {{-1,1,-2,0,0,0,0,0}, 0, 0, 101325, 1, 0, 0, 1}, /* atm */
    [111] = {{-1,1,-2,0,0,0,0,0}, 0, 0, 1, 1, 5, 0, 1}, /* bar */
    [112] = {{-1,1,-2,0,0,0,0,0}, 0, 0, 1, 1, 2, 0, 1}, /* mbar */
    [113] = {{-1,1,-2,0,0,0,0,0}, 0, 0, 20265, 152, 0, 0, 1}, /* Torr */
    [114] = {{1,0,0,0,0,0,0,0}, 0, 0, 1852, 1, 0, 0, 1}, /* nmi */
    [115] = {{1,0,0,0,0,0,0,0}, 0, 0, 94607304725808, 1, 2, 0, 1}, /* ly */
    [116] = {{1,0,0,0,0,0,0,0}, 0, 0, 1495978707, 1, 2, 0, 1}, /* au */
    [117] = {{1,0,0,0,0,0,0,0}, 0, 0, 30856775814914, 1, 3, 0, 1}, /* pc */
    [118] = {{0,0,0,0,0,0,0,0}, 25, 1, 1, 1, 0, 0, 1}, /* e\xe2\x82\x80 */
    [119] = {{0,1,0,0,0,0,0,0}, 0, 0, 45359237, 1, -8, 0, 1}, /* lbs */
    [120] = {{2,0,0,0,0,0,0,0}, 0, 0, 145161, 15625, -2, 0, 1}, /* sqft */
    [121] = {{2,0,0,0,0,0,0,0}, 0, 0, 1, 1, 0, 0, 1}, /* sqm */
    [122] = {{1,0,-1,0,0,0,0,0}, 0, 0, 1397, 3125, 0, 0, 1}, /* mi/h */
    [255] = {{0,0,0,0,0,0,0,0}, 0, 0, 0, 0, 0, 0, 1}, /* % */
    [256] = {{0,0,0,0,1,0,0,0}, 0, 0, 5, 9, 0, 0, 1}, /* \xc2\xb0R */
    [257] = {{0,0,0,0,1,0,0,0}, 0, 0, -2, 3, 0, 7463, 20}, /* \xc2\xb0\x44\x65 */
    [258] = {{0,0,0,0,1,0,0,0}, 0, 0, 1, 33, 2, 5463, 20}, /* \xc2\xb0N */
    [259] = {{0,0,0,0,1,0,0,0}, 0, 0, 5, 4, 0, 5463, 20}, /* \xc2\xb0R\xc3\xa9 */
    [260] = {{0,0,0,0,1,0,0,0}, 0, 0, 4, 21, 1, 36241, 140}, /* \xc2\xb0R\xc3\xb8 */
    [261] = {{0,0,0,0,1,0,0,0}, 0, 0, 36111, 5, -2, 17063, 20}, /* \xc2\xb0W */
    [262] = {{0,0,0,0,1,0,0,0}, 91, 1, 1, 1, 0, 0, 1}, /* \xce\x94K */
    [263] = {{0,0,0,0,1,0,0,0}, 91, 1, 1, 1, 0, 0, 1}, /* \xce\x94\xc2\xb0\x43 */
    [264] = {{0,0,0,0,1,0,0,0}, 91, 1, 5, 9, 0, 0, 1}, /* \xce\x94\xc2\xb0\x46 */
    [265] = {{0,0,0,0,1,0,0,0}, 91, 1, 5, 9, 0, 0, 1}, /* \xce\x94\xc2\xb0R */
    [266] = {{0,0,0,0,1,0,0,0}, 91, 1, -2, 3, 0, 0, 1}, /* \xce\x94\xc2\xb0\x44\x65 */
    [267] = {{0,0,0,0,1,0,0,0}, 91, 1, 1, 33, 2, 0, 1}, /* \xce\x94\xc2\xb0N */
    [268] = {{0,0,0,0,1,0,0,0}, 91, 1, 5, 4, 0, 0, 1}, /* \xce\x94\xc2\xb0R\xc3\xa9 */
    [269] = {{0,0,0,0,1,0,0,0}, 91, 1, 4, 21, 1, 0, 1}, /* \xce\x94\xc2\xb0R\xc3\xb8 */
    [270] = {{0,0,0,0,1,0,0,0}, 91, 1, 36111, 5, -2, 0, 1}, /* \xce\x94\xc2\xb0W */
    [271] = {{1,0,0,0,0,0,0,0}, 0, 0, 25146, 125, 0, 0, 1}, /* fur */
    [272] = {{1,0,0,0,0,0,0,0}, 0, 0, 12573, 25, -2, 0, 1}, /* rod */
    [273] = {{1,0,0,0,0,0,0,0}, 0, 0, 12573, 625, 0, 0, 1}, /* ch */
    [274] = {{1,0,0,0,0,0,0,0}, 0, 0, 8509, 5, -3, 0, 1}, /* smoot */
    [275] = {{1,0,0,0,0,0,0,0}, 0, 0, 127, 125, -1, 0, 1}, /* hand */
    [276] = {{1,0,0,0,0,0,0,0}, 0, 0, 603504, 125, 0, 0, 1}, /* league */
    [277] = {{1,0,0,0,0,0,0,0}, 0, 0, 889, 2, -4, 0, 1}, /* RU */
    [278] = {{1,0,0,0,0,0,0,0}, 0, 0, 1, 1, -10, 0, 1}, /* \xc3\x85 */
    [279] = {{1,0,0,0,0,0,0,0}, 0, 0, 1143, 625, 0, 0, 1}, /* fathom */
    [280] = {{1,0,0,0,0,0,0,0}, 0, 0, 926, 5, 0, 0, 1}, /* cable */
    [281] = {{1,0,-1,0,0,0,0,0}, 0, 0, 463, 9, -2, 0, 1}, /* knot */
    [282] = {{1,0,-1,0,0,0,0,0}, 0, 0, 5, 18, 0, 0, 1}, /* kph */
    [283] = {{1,0,-1,0,0,0,0,0}, 0, 0, 16573, 5, -1, 0, 1}, /* mach */
    [284] = {{1,0,0,0,0,0,0,0}, 0, 0, 299792458, 1, 0, 0, 1}, /* lightsecond */
    [285] = {{1,0,0,0,0,0,0,0}, 0, 0, 1798754748, 1, 1, 0, 1}, /* lightminute */
    [286] = {{1,0,0,0,0,0,0,0}, 0, 0, 10792528488, 1, 2, 0, 1}, /* lighthour */
    [287] = {{1,0,0,0,0,0,0,0}, 0, 0, 16162550000000002, 1, -51, 0, 1}, /* \xe2\x84\x93\xe2\x82\x9a */
    [288] = {{0,1,0,0,0,0,0,0}, 0, 0, 918413, 14173278532, 0, 0, 1}, /* gr */
    [289] = {{0,1,0,0,0,0,0,0}, 0, 0, 4429613, 25, -8, 0, 1}, /* dr */
    [290] = {{0,1,0,0,0,0,0,0}, 0, 0, 635029, 1, -5, 0, 1}, /* st */
    [291] = {{0,1,0,0,0,0,0,0}, 0, 0, 635029, 5, -4, 0, 1}, /* qr */
    [292] = {{0,1,0,0,0,0,0,0}, 0, 0, 1016047, 2, -4, 0, 1}, /* cwt */
    [293] = {{0,1,0,0,0,0,0,0}, 0, 0, 56699, 125, -1, 0, 1}, /* CWT */
    [294] = {{0,1,0,0,0,0,0,0}, 0, 0, 181437, 2, -2, 0, 1}, /* tn */
    [295] = {{0,1,0,0,0,0,0,0}, 0, 0, 1016047, 1, -3, 0, 1}, /* LT */
    [296] = {{0,1,0,0,0,0,0,0}, 0, 0, 166053906660000015, 1, -44, 0, 1}, /* Da */
    [297] = {{0,1,0,0,0,0,0,0}, 0, 0, 166053906660000015, 1, -44, 0, 1}, /* u */
    [298] = {{0,1,0,0,0,0,0,0}, 0, 0, 14593903, 1, -6, 0, 1}, /* slug */
    [299] = {{0,1,0,0,0,0,0,0}, 0, 0, 18401, 845465564313, 0, 0, 1}, /* m\xe2\x82\x9a\xe2\x82\x97 */
    [300] = {{0,1,0,0,0,0,0,0}, 0, 0, 2789239, 2152226789, 0, 0, 1}, /* \xe2\x84\x88 */
    [301] = {{0,1,0,0,0,0,0,0}, 0, 0, 8367717, 2152226789, 0, 0, 1}, /* \xca\x92 */
    [302] = {{0,1,0,0,0,0,0,0}, 0, 0, 19439673, 625, -6, 0, 1}, /* \xe2\x84\xa5 */
    [303] = {{0,1,0,0,0,0,0,0}, 0, 0, 58319019, 15625, -4, 0, 1}, /* \xe2\x84\x94 */
    [304] = {{0,1,0,0,0,0,0,0}, 0, 0, 62207, 2, -6, 0, 1}, /* troyounce */
    [305] = {{0,1,0,0,0,0,0,0}, 0, 0, 155517, 1, -8, 0, 1}, /* pennyweight */
    [306] = {{0,1,0,0,0,0,0,0}, 0, 0, 1, 5, -3, 0, 1}, /* carat */
    [307] = {{0,1,0,0,0,0,0,0}, 0, 0, 1, 1, 2, 0, 1}, /* quintal */
    [308] = {{0,0,1,0,0,0,0,0}, 0, 0, 6, 1, 1, 0, 1}, /* min */
    [309] = {{0,0,1,0,0,0,0,0}, 0, 0, 36, 1, 2, 0, 1}, /* h */
    [310] = {{0,0,1,0,0,0,0,0}, 0, 0, 864, 1, 2, 0, 1}, /* d */
    [311] = {{0,0,1,0,0,0,0,0}, 0, 0, 6048, 1, 2, 0, 1}, /* week */
    [312] = {{0,0,1,0,0,0,0,0}, 0, 0, 2629746, 1, 0, 0, 1}, /* month */
    [313] = {{0,0,1,0,0,0,0,0}, 0, 0, 31556952, 1, 0, 0, 1}, /* year */
    [314] = {{0,0,1,0,0,0,0,0}, 0, 0, 31556952, 1, 1, 0, 1}, /* decade */
    [315] = {{0,0,1,0,0,0,0,0}, 0, 0, 31556952, 1, 3, 0, 1}, /* millennium */
    [316] = {{0,0,1,0,0,0,0,0}, 0, 0, 12096, 1, 2, 0, 1}, /* fortnight */
    [317] = {{0,0,1,0,0,0,0,0}, 0, 0, 31556952, 1, 2, 0, 1}, /* century */
    [318] = {{0,0,1,0,0,0,0,0}, 0, 0, 1, 1, -8, 0, 1}, /* shake */
    [319] = {{0,0,1,0,0,0,0,0}, 0, 0, 3944768688, 125, 0, 0, 1}, /* siderealyear */
    [320] = {{0,0,1,0,0,0,0,0}, 0, 0, 3944615652, 125, 0, 0, 1}, /* tropicalyear */
    [321] = {{0,0,1,0,0,0,0,0}, 0, 0, 315576, 1, 2, 0, 1}, /* julianyear */
    [322] = {{0,0,1,0,0,0,0,0}, 0, 0, 172328181, 2, -3, 0, 1}, /* siderealday */
    [323] = {{0,0,1,0,0,0,0,0}, 0, 0, 63786096, 25, 0, 0, 1}, /* lunarmonth */
    [324] = {{0,0,1,0,0,0,0,0}, 0, 0, 15778476, 1, 1, 0, 1}, /* lustrum */
    [325] = {{0,0,1,0,0,0,0,0}, 0, 0, 4508136, 1, 0, 0, 1}, /* dogyear */
    [326] = {{0,0,1,0,0,0,0,0}, 0, 0, 539124700000000066, 1, -61, 0, 1}, /* t\xe2\x82\x9a */
    [327] = {{2,0,0,0,0,0,0,0}, 0, 0, 316160658, 78125, 0, 0, 1}, /* ac */
    [328] = {{2,0,0,0,0,0,0,0}, 0, 0, 1, 1, -28, 0, 1}, /* barn */
    [329] = {{3,0,0,0,0,0,0,0}, 0, 0, 1, 1, -3, 0, 1}, /* l */
    [330] = {{3,0,0,0,0,0,0,0}, 0, 0, 473176473, 2, -12, 0, 1}, /* cup */
    [331] = {{3,0,0,0,0,0,0,0}, 0, 0, 473176473, 4, -12, 0, 1}, /* gill */
    [332] = {{3,0,0,0,0,0,0,0}, 0, 0, 473176473, 16, -12, 0, 1}, /* floz */
    [333] = {{3,0,0,0,0,0,0,0}, 0, 0, 473176473, 128, -12, 0, 1}, /* fldr */
    [334] = {{3,0,0,0,0,0,0,0}, 0, 0, 454609, 1, -8, 0, 1}, /* impgal */
    [335] = {{3,0,0,0,0,0,0,0}, 0, 0, 220244188543, 625, -10, 0, 1}, /* bushel */
    [336] = {{3,0,0,0,0,0,0,0}, 0, 0, 220244188543, 25, -12, 0, 1}, /* peck */
    [337] = {{3,0,0,0,0,0,0,0}, 0, 0, 473176473, 32, -12, 0, 1}, /* tbsp */
    [338] = {{3,0,0,0,0,0,0,0}, 0, 0, 157725491, 32, -12, 0, 1}, /* tsp */
    [339] = {{3,0,0,0,0,0,0,0}, 0, 0, 1, 2, -7, 0, 1}, /* drop */
    [340] = {{3,0,0,0,0,0,0,0}, 0, 0, 122699, 199149509426, 0, 0, 1}, /* dash */
    [341] = {{3,0,0,0,0,0,0,0}, 0, 0, 122699, 398299018852, 0, 0, 1}, /* pinch */
    [342] = {{3,0,0,0,0,0,0,0}, 0, 0, 61415, 398724264139, 0, 0, 1}, /* smidgen */
    [343] = {{3,0,0,0,0,0,0,0}, 0, 0, 443603, 1, -10, 0, 1}, /* jigger */
    [344] = {{3,0,0,0,0,0,0,0}, 0, 0, 4091481, 1, -8, 0, 1}, /* firkin */
    [345] = {{3,0,0,0,0,0,0,0}, 0, 0, 3407, 5, -4, 0, 1}, /* rundlet */
    [346] = {{3,0,0,0,0,0,0,0}, 0, 0, 7949, 5, -4, 0, 1}, /* tierce */
    [347] = {{3,0,0,0,0,0,0,0}, 0, 0, 2981, 125, -2, 0, 1}, /* hogshead */
    [348] = {{3,0,0,0,0,0,0,0}, 0, 0, 31797, 1, -5, 0, 1}, /* puncheon */
    [349] = {{3,0,0,0,0,0,0,0}, 0, 0, 2981, 625, -1, 0, 1}, /* pipe */
    [350] = {{3,0,0,0,0,0,0,0}, 0, 0, 2981, 3125, 0, 0, 1}, /* tun */
    [351] = {{3,0,0,0,0,0,0,0}, 0, 0, 4091481, 5, -7, 0, 1}, /* kilderkin */
    [352] = {{3,0,0,0,0,0,0,0}, 0, 0, 3, 16, -3, 0, 1}, /* split */
    [353] = {{3,0,0,0,0,0,0,0}, 0, 0, 3, 4, -3, 0, 1}, /* bottle */
    [354] = {{3,0,0,0,0,0,0,0}, 0, 0, 3, 2, -3, 0, 1}, /* magnum */
    [355] = {{3,0,0,0,0,0,0,0}, 0, 0, 3, 1, -3, 0, 1}, /* jeroboam */
    [356] = {{3,0,0,0,0,0,0,0}, 0, 0, 3, 5, -2, 0, 1}, /* methuselah */
    [357] = {{3,0,0,0,0,0,0,0}, 0, 0, 3, 2, -2, 0, 1}, /* nebuchadnezzar */
    [358] = {{3,0,0,0,0,0,0,0}, 0, 0, 3, 1, -2, 0, 1}, /* melchizedek */
    [359] = {{-1,1,-2,0,0,0,0,0}, 0, 0, 1, 1, -1, 0, 1}, /* Ba */
    [360] = {{-1,1,-2,0,0,0,0,0}, 0, 0, 196133, 2, 0, 0, 1}, /* at */
    [361] = {{-1,1,-2,0,0,0,0,0}, 0, 0, 6894757, 1, -3, 0, 1}, /* psi */
    [362] = {{-1,1,-2,0,0,0,0,0}, 0, 0, 20265, 152, 0, 0, 1}, /* torr */
    [363] = {{-1,1,-2,0,0,0,0,0}, 0, 0, 66661, 5, -2, 0, 1}, /* mmHg */
    [364] = {{-1,1,-2,0,0,0,0,0}, 0, 0, 3386389, 1, -3, 0, 1}, /* inHg */
    [365] = {{-1,1,-2,0,0,0,0,0}, 0, 0, 196133, 2, -3, 0, 1}, /* cmH2O */
    [366] = {{1,1,-2,0,0,0,0,0}, 0, 0, 8896443230521, 2, -12, 0, 1}, /* lbf */
    [367] = {{1,1,-2,0,0,0,0,0}, 0, 0, 196133, 2, -4, 0, 1}, /* kgf */
    [368] = {{2,1,-2,0,0,0,0,0}, 0, 0, 1, 1, -7, 0, 1}, /* erg */
    [369] = {{2,1,-2,0,0,0,0,0}, 0, 0, 10467, 25, -2, 0, 1}, /* cal_IT */
    [370] = {{2,1,-2,0,0,0,0,0}, 0, 0, 523, 125, 0, 0, 1}, /* cal_th */
    [371] = {{2,1,-2,0,0,0,0,0}, 0, 0, 20934, 5, 0, 0, 1}, /* kcal_IT */
    [372] = {{2,1,-2,0,0,0,0,0}, 0, 0, 4184, 1, 0, 0, 1}, /* kcal_th */
    [373] = {{2,1,-2,0,0,0,0,0}, 0, 0, 4085925351, 387271, -1, 0, 1}, /* BTU */
    [374] = {{2,1,-2,0,0,0,0,0}, 0, 0, 52752792631, 5, -2, 0, 1}, /* therm */
    [375] = {{2,1,-2,0,0,0,0,0}, 0, 0, 416402469, 3071227, -2, 0, 1}, /* ftlbf */
    [376] = {{1,1,-2,0,0,0,0,0}, 0, 0, 1, 1, -5, 0, 1}, /* dyn */
    [377] = {{2,1,-3,0,0,0,0,0}, 0, 0, 2068973376, 2774539, 0, 0, 1}, /* hp */
    [378] = {{2,1,-3,0,0,0,0,0}, 0, 0, 588399, 8, -2, 0, 1}, /* PS */
    [379] = {{0,1,-2,-1,0,0,0,0}, 0, 0, 1, 1, -4, 0, 1}, /* Ga */
    [380] = {{0,0,-1,0,0,0,0,0}, 17, 1, 37, 1, 9, 0, 1}, /* Ci */
    [381] = {{2,0,-2,0,0,0,0,0}, 23, 1, 1, 1, -2, 0, 1}, /* rem */
    [382] = {{0,0,0,0,0,0,0,0}, 2, 1, 14964008, 857374503, 0, 0, 1}, /* deg */
    [383] = {{0,0,0,0,0,0,0,0}, 2, 1, 1650943, 5675523967, 0, 0, 1}, /* arcmin */
    [384] = {{0,0,0,0,0,0,0,0}, 2, 1, 286277, 59048869938, 0, 0, 1}, /* arcsec */
    [385] = {{0,0,0,0,0,0,0,0}, 2, 1, 10906443, 694325726, 0, 0, 1}, /* gon */
    [386] = {{0,0,0,0,0,0,0,0}, 2, 1, 411557987, 65501488, 0, 0, 1}, /* turn */
    [387] = {{0,0,0,0,0,0,0,0}, 2, 1, 2752991, 2804173606, 0, 0, 1}, /* mil */
    [388] = {{0,0,0,0,0,0,0,0}, 2, 1, 18369286, 748432043, 0, 0, 1}, /* brad */
    [389] = {{1,0,-2,0,0,0,0,0}, 0, 0, 1, 1, -2, 0, 1}, /* Gal */
    [390] = {{0,0,0,0,0,0,0,1}, 0, 0, 1, 8, 0, 0, 1}, /* b */
    [391] = {{0,0,0,0,0,0,0,1}, 0, 0, 1, 2, 0, 0, 1}, /* nibble */
    [392] = {{0,0,0,0,0,0,0,1}, 0, 0, 1, 1, 0, 0, 1}, /* o */
    [393] = {{0,0,0,0,0,0,0,1}, 0, 0, 1125899906842624, 1, 0, 0, 1}, /* PiB */
    [394] = {{0,0,0,0,0,0,0,1}, 0, 0, 1152921504606846976, 1, 0, 0, 1}, /* EiB */
    [395] = {{0,0,-1,0,0,0,0,1}, 0, 0, 1, 8, 0, 0, 1}, /* bps */
    [396] = {{0,0,-1,0,0,0,0,1}, 0, 0, 1, 1, 0, 0, 1}, /* Bps */
    [397] = {{0,0,-1,0,0,0,0,0}, 90, 1, 1, 1, 0, 0, 1}, /* baud */
    [398] = {{-1,1,-1,0,0,0,0,0}, 0, 0, 1, 1, -1, 0, 1}, /* P */
    [399] = {{-1,1,-1,0,0,0,0,0}, 0, 0, 1, 1, -3, 0, 1}, /* cP */
    [400] = {{2,0,-1,0,0,0,0,0}, 0, 0, 1, 1, -4, 0, 1}, /* St */
    [401] = {{2,0,-1,0,0,0,0,0}, 0, 0, 1, 1, -6, 0, 1}, /* cSt */
    [402] = {{0,1,0,0,0,0,0,0}, 0, 0, 198891999999999991, 1, 13, 0, 1}, /* solarmass */
    [403] = {{0,1,0,0,0,0,0,0}, 0, 0, 597220000000000022, 1, 7, 0, 1}, /* earthmass */
    [404] = {{0,1,0,0,0,0,0,0}, 0, 0, 189859999999999994, 1, 10, 0, 1}, /* jupitermass */
    [405] = {{0,1,0,0,0,0,0,0}, 0, 0, 734199999999999969, 1, 5, 0, 1}, /* moonmass */
    [406] = {{1,0,0,0,0,0,0,0}, 0, 0, 696, 1, 6, 0, 1}, /* solarradius */
    [407] = {{1,0,0,0,0,0,0,0}, 0, 0, 6371, 1, 3, 0, 1}, /* earthradius */
    [408] = {{1,0,0,0,0,0,0,0}, 0, 0, 176389, 5, -8, 0, 1}, /* point */
    [409] = {{1,0,0,0,0,0,0,0}, 0, 0, 4233333, 1, -9, 0, 1}, /* pica */
    [410] = {{1,0,0,0,0,0,0,0}, 0, 0, 127, 36135, -1, 0, 1}, /* texpt */
    [411] = {{1,0,0,0,0,0,0,0}, 0, 0, 75213, 2, -8, 0, 1}, /* didot */
    [412] = {{1,0,0,0,0,0,0,0}, 0, 0, 225639, 5, -7, 0, 1}, /* cicero */
    [413] = {{1,0,0,0,0,0,0,0}, 0, 0, 33, 2, -1, 0, 1}, /* altuve */
    [414] = {{2,0,0,0,0,0,0,0}, 0, 0, 100000000000000003, 1, -51, 0, 1}, /* outhouse */
    [415] = {{2,0,0,0,0,0,0,0}, 0, 0, 10000000000000001, 1, -68, 0, 1}, /* shed */
    [416] = {{3,0,0,0,0,0,0,0}, 0, 0, 2981, 25, -3, 0, 1}, /* barrel */
    [417] = {{3,0,0,0,0,0,0,0}, 0, 0, 1, 1, 0, 0, 1}, /* stere */
    [418] = {{3,0,0,0,0,0,0,0}, 0, 0, 906139, 25, -4, 0, 1}, /* cord */
    [419] = {{1,0,0,0,0,0,0,0}, 0, 0, 1, 2, -8, 0, 1}, /* beard second */
    [420] = {{3,0,0,0,0,0,0,0}, 0, 0, 180197, 58397870562, 0, 0, 1}, /* barn megaparsec */
    [421] = {{2,0,-2,0,0,0,0,0}, 23, 1, 1, 1, -7, 0, 1}, /* banana */
    [422] = {{0,0,0,0,0,0,0,0}, 27, 1, 15, 1, 0, 0, 1}, /* warhol */
    [423] = {{0,0,0,0,0,0,0,0}, 27, 1, 15, 1, 3, 0, 1}, /* kilowarhol */
    [424] = {{0,0,-1,0,0,0,0,0}, 81, 1, 1, 6, -1, 0, 1}, /* rpm */
    [425] = {{0,0,-1,0,0,0,0,0}, 17, 1, 1, 1, 6, 0, 1}, /* rd */
    [426] = {{2,1,-2,-1,0,0,0,0}, 0, 0, 1, 1, -8, 0, 1}, /* Mx */
    [427] = {{0,0,0,0,0,0,0,0}, 8, 1, 1, 1, 0, 0, 1}, /* millihelen */
    [428] = {{-2,0,0,0,0,0,1,0}, 55, 1, 1, 1, 0, 0, 1}, /* nit */
    [429] = {{-2,0,0,0,0,0,1,0}, 55, 1, 1, 1, 4, 0, 1}, /* sb */
    [430] = {{-2,0,0,0,0,0,1,0}, 55, 1, 2898221063, 910503, 0, 0, 1}, /* La */
    [431] = {{-2,0,0,0,0,0,1,0}, 55, 1, 330354972, 96418561, 0, 0, 1}, /* fL */
    [432] = {{-2,0,0,0,0,0,1,0}, 55, 1, 78256779, 245850922, 0, 0, 1}, /* asb */
    [433] = {{-2,0,0,0,0,0,1,0}, 55, 1, 2111208, 6632555543, 0, 0, 1}, /* sk */
    [434] = {{0,0,0,0,0,0,0,0}, 21, 1, 1, 1, 0, 0, 1}, /* em */
    [435] = {{0,0,0,0,0,0,0,0}, 21, 1, 1, 2, 0, 0, 1}, /* en */
    [436] = {{0,0,0,0,0,0,0,0}, 21, 1, 2, 1, 0, 0, 1}, /* qquad */
    [437] = {{0,0,0,0,0,0,0,0}, 70, 1, 1, 1, 0, 0, 1}, /* peanutbutter */
    [438] = {{0,0,0,0,0,0,0,0}, 50, 1, 1, 1, 0, 0, 1}, /* jelly */
    [439] = {{0,0,0,0,0,0,0,0}, 6, 1, 1, 1, 0, 0, 1}, /* beat */
    [440] = {{0,0,0,0,0,0,0,0}, 16, 1, 1, 1, 0, 0, 1}, /* cycle */
    [441] = {{0,0,0,0,0,0,0,0}, 29, 1, 1, 1, 0, 0, 1}, /* frame */
    [442] = {{0,0,0,0,0,0,0,0}, 44, 1, 1, 1, 0, 0, 1}, /* instant */
    [443] = {{0,0,0,0,0,0,0,0}, 51, 1, 1, 1, 0, 0, 1}, /* jiffy */
    [444] = {{0,0,0,0,0,0,0,0}, 65, 1, 1, 1, 0, 0, 1}, /* moment */
    [445] = {{0,0,0,0,0,0,0,0}, 84, 1, 1, 1, 0, 0, 1}, /* sample */
    [446] = {{0,0,0,0,0,0,0,0}, 92, 1, 1, 1, 0, 0, 1}, /* tick */
    [447] = {{0,0,0,0,0,0,0,0}, 81, 1, 1, 1, 0, 0, 1}, /* revolution */
    [448] = {{0,0,0,0,0,0,0,0}, 17, 1, 1, 1, 0, 0, 1}, /* decay */
    [449] = {{0,0,0,0,0,0,0,0}, 82, 1, 1, 1, 0, 0, 1}, /* rotation */
    [450] = {{0,0,0,0,0,0,0,0}, 28, 1, 1, 1, 0, 0, 1}, /* flop */
    [451] = {{0,0,0,0,0,0,0,0}, 67, 1, 1, 1, 0, 0, 1}, /* op */
    [452] = {{0,0,0,0,0,0,0,0}, 58, 1, 1, 1, 0, 0, 1}, /* mac */
    [453] = {{0,0,0,0,0,0,0,0}, 45, 1, 1, 1, 0, 0, 1}, /* instruction */
    [454] = {{0,0,0,0,0,0,0,0}, 93, 1, 1, 1, 0, 0, 1}, /* tok */
    [455] = {{0,0,0,0,0,0,0,0}, 96, 1, 1, 1, 0, 0, 1}, /* transfer */
    [456] = {{0,0,0,0,0,0,0,0}, 76, 1, 1, 1, 0, 0, 1}, /* query */
    [457] = {{0,0,0,0,0,0,0,0}, 80, 1, 1, 1, 0, 0, 1}, /* request */
    [458] = {{0,0,0,0,0,0,0,0}, 95, 1, 1, 1, 0, 0, 1}, /* txn */
    [459] = {{0,0,0,0,0,0,0,0}, 69, 1, 1, 1, 0, 0, 1}, /* packet */
    [460] = {{0,0,0,0,0,0,0,0}, 47, 1, 1, 1, 0, 0, 1}, /* io */
    [461] = {{0,0,0,0,0,0,0,1}, 0, 0, 51711048, 286746937, 0, 0, 1}, /* nat */
    [462] = {{0,0,0,0,0,0,0,1}, 0, 0, 36741077, 8848133, -1, 0, 1}, /* ban */
    [463] = {{0,0,0,0,0,0,0,1}, 0, 0, 34582415, 832827539, 0, 0, 1}, /* deciban */
    [464] = {{0,0,0,0,0,0,0,0}, 77, 1, 1, 1, -6, 0, 1}, /* ppm */
    [465] = {{0,0,0,0,0,0,0,0}, 77, 1, 1, 1, -9, 0, 1}, /* ppb */
    [466] = {{0,0,0,0,0,0,0,0}, 77, 1, 1, 1, -12, 0, 1}, /* ppt */
    [467] = {{0,0,0,0,0,0,0,0}, 77, 1, 1, 1, -8, 0, 1}, /* pphm */
    [468] = {{0,0,0,0,0,0,0,0}, 53, 1, 1, 1, 0, 0, 1}, /* sone */
    [469] = {{0,0,0,0,0,0,0,0}, 54, 1, 1, 1, 0, 0, 1}, /* phon */
    [470] = {{0,1,-2,0,0,0,0,0}, 16, -1, 1, 1, -26, 0, 1}, /* Jy */
    [471] = {{0,0,0,0,0,0,0,0}, 61, 1, 1, 1, 0, 0, 1}, /* mag */
    [472] = {{0,0,0,0,0,0,0,0}, 60, 1, 1, 1, 0, 0, 1}, /* Mag */
    [473] = {{0,0,0,0,0,0,0,0}, 62, 1, 1, 1, 0, 0, 1}, /* M_bol */
    [474] = {{2,0,0,0,0,0,0,0}, 0, 0, 100000000000000018, 1, -60, 0, 1}, /* femtobarn */
    [475] = {{2,0,0,0,0,0,0,0}, 0, 0, 100000000000000012, 1, -63, 0, 1}, /* attobarn */
    [476] = {{2,0,0,0,0,0,0,0}, 0, 0, 100000000000000003, 1, -57, 0, 1}, /* picobarn */
    [477] = {{2,0,0,0,0,0,0,0}, 0, 0, 100000000000000017, 1, -54, 0, 1}, /* nanobarn */
    [478] = {{-2,0,0,0,0,0,0,0}, 0, 0, 100000000000000001, 1, 26, 0, 1}, /* fb\xe2\x81\xbb\xc2\xb9 */
    [479] = {{-2,0,0,0,0,0,0,0}, 0, 0, 999999999999999993, 1, 28, 0, 1}, /* ab\xe2\x81\xbb\xc2\xb9 */
    [480] = {{-2,0,0,0,0,0,0,0}, 0, 0, 100000000000000003, 1, 23, 0, 1}, /* pb\xe2\x81\xbb\xc2\xb9 */
    [481] = {{-2,0,0,0,0,0,0,0}, 0, 0, 999999999999999954, 1, 19, 0, 1}, /* nb\xe2\x81\xbb\xc2\xb9 */
    [482] = {{-1,0,0,1,0,0,0,0}, 0, 0, 707761077, 8893988, 0, 0, 1}, /* Oe */
    [483] = {{0,0,0,1,0,0,0,0}, 0, 0, 116522652, 146426683, 0, 0, 1}, /* Gb */
    [484] = {{1,0,1,1,0,0,0,0}, 0, 0, 333564000000000034, 1, -47, 0, 1}, /* D */
    [485] = {{2,0,0,1,0,0,0,0}, 0, 0, 927401007830000118, 1, -41, 0, 1}, /* \xce\xbc_B */
    [486] = {{0,0,0,0,0,0,0,0}, 0, 0, 1, 1, -6, 0, 1}, /* micromort */
    [487] = {{0,0,1,0,0,0,0,0}, 0, 0, 18, 1, 2, 0, 1}, /* microlife */
    [488] = {{-1,0,0,0,0,0,0,0}, 0, 0, 1, 1, 2, 0, 1}, /* kayser */
    [489] = {{0,0,0,0,0,0,0,0}, 35, 1, 1, 1, 0, 0, 1}, /* mohs */
    [490] = {{0,0,0,0,0,0,0,0}, 37, 1, 1, 1, 0, 0, 1}, /* vickers */
    [491] = {{0,0,0,0,0,0,0,0}, 36, 1, 1, 1, 0, 0, 1}, /* rockwell */
    [492] = {{0,0,0,0,0,0,0,0}, 34, 1, 1, 1, 0, 0, 1}, /* brinell */
    [493] = {{0,0,0,0,0,0,0,0}, 0, 0, 12, 1, 0, 0, 1}, /* dozen */
    [494] = {{0,0,0,0,0,0,0,0}, 0, 0, 144, 1, 0, 0, 1}, /* gross */
    [495] = {{0,0,0,0,0,0,0,0}, 0, 0, 1728, 1, 0, 0, 1}, /* great_gross */
    [496] = {{0,0,0,0,0,0,0,0}, 0, 0, 2, 1, 1, 0, 1}, /* score */
    [497] = {{0,0,0,0,0,0,0,0}, 0, 0, 13, 1, 0, 0, 1}, /* bakers_dozen */
    [498] = {{0,0,0,0,0,0,0,0}, 0, 0, 1, 1, 100, 0, 1}, /* googol */
    [499] = {{0,0,0,0,0,0,0,0}, 0, 0, 1, 1, 1000, 0, 1}, /* googolplex */
    [500] = {{1,0,0,0,0,0,0,0}, 0, 0, 1143, 25, -2, 0, 1}, /* cubit */
    [501] = {{1,0,0,0,0,0,0,0}, 0, 0, 1143, 5, -3, 0, 1}, /* span */
    [502] = {{1,0,0,0,0,0,0,0}, 0, 0, 381, 5, -3, 0, 1}, /* handbreadth */
    [503] = {{1,0,0,0,0,0,0,0}, 0, 0, 381, 2, -4, 0, 1}, /* fingerbreadth */
    [504] = {{1,0,0,0,0,0,0,0}, 0, 0, 4572, 5, 0, 0, 1}, /* biblical_mil */
    [505] = {{1,0,0,0,0,0,0,0}, 0, 0, 18288, 5, 0, 0, 1}, /* parsa */
    [506] = {{1,0,0,0,0,0,0,0}, 0, 0, 4572, 5, 0, 0, 1}, /* techum */
    [507] = {{3,0,0,0,0,0,0,0}, 0, 0, 27, 125, -2, 0, 1}, /* omer */
    [508] = {{3,0,0,0,0,0,0,0}, 0, 0, 27, 125, -1, 0, 1}, /* ephah */
    [509] = {{3,0,0,0,0,0,0,0}, 0, 0, 9, 25, -2, 0, 1}, /* hin */
    [510] = {{3,0,0,0,0,0,0,0}, 0, 0, 27, 125, -1, 0, 1}, /* bath */
    [511] = {{3,0,0,0,0,0,0,0}, 0, 0, 9, 125, -1, 0, 1}, /* seah */
    [512] = {{3,0,0,0,0,0,0,0}, 0, 0, 27, 125, 0, 0, 1}, /* kor */
    [513] = {{3,0,0,0,0,0,0,0}, 0, 0, 3, 25, -2, 0, 1}, /* kab */
    [514] = {{0,1,0,0,0,0,0,0}, 0, 0, 23, 2, -3, 0, 1}, /* shekel */
    [515] = {{0,1,0,0,0,0,0,0}, 0, 0, 23, 4, -1, 0, 1}, /* biblical_mina */
    [516] = {{0,1,0,0,0,0,0,0}, 0, 0, 69, 2, 0, 0, 1}, /* biblical_talent */
    [517] = {{0,1,0,0,0,0,0,0}, 0, 0, 23, 4, -4, 0, 1}, /* gerah */
    [518] = {{0,1,0,0,0,0,0,0}, 0, 0, 23, 4, -3, 0, 1}, /* beka */
    [519] = {{0,0,1,0,0,0,0,0}, 0, 0, 1, 3, 1, 0, 1}, /* helek */
    [520] = {{0,0,1,0,0,0,0,0}, 0, 0, 76, 405, 0, 0, 1}, /* rega */
    [521] = {{0,0,1,0,0,0,0,0}, 0, 0, 432, 1, 2, 0, 1}, /* onah */
    [522] = {{0,0,1,0,0,0,0,0}, 0, 0, 15778476, 1, 2, 0, 1}, /* yovel */
    [523] = {{0,0,1,0,0,0,0,0}, 0, 0, 220898664, 1, 0, 0, 1}, /* shmita */
    [524] = {{1,0,-2,0,0,0,0,0}, 0, 0, 196133, 2, -4, 0, 1}, /* g\xe2\x82\x80 */
    [525] = {{1,0,-2,0,0,0,0,0}, 0, 0, 196133, 2, -4, 0, 1}, /* g_n */
    [526] = {{1,0,-2,0,0,0,0,0}, 0, 0, 196133, 2, -4, 0, 1}, /* gee */
    [527] = {{-2,0,0,0,0,0,0,0}, 0, 0, 48, 112903, 9, 0, 1}, /* mpg */
    [528] = {{-2,0,0,0,0,0,0,0}, 0, 0, 48, 112903, 9, 0, 1}, /* mpge */
    [529] = {{2,0,0,0,0,0,0,0}, 0, 0, 1, 1, -8, 0, 1}, /* L/100km */
    [530] = {{0,1,0,0,0,0,0,0}, 0, 0, 45359237, 4, -8, 0, 1}, /* stick */
    [531] = {{0,1,0,0,0,0,0,0}, 0, 0, 1, 1, 6, 0, 1}, /* kiloton */
    [532] = {{0,1,0,0,0,0,0,0}, 0, 0, 1, 1, 9, 0, 1}, /* megaton */
    [533] = {{0,1,0,0,0,0,0,0}, 0, 0, 1, 1, 12, 0, 1}, /* gigaton */
    [534] = {{3,0,0,0,0,0,0,0}, 0, 0, 41225904, 259303135, 0, 0, 1}, /* oil_barrel */
    [535] = {{2,1,-2,0,0,0,0,0}, 0, 0, 6119, 1, 6, 0, 1}, /* BOE */
    [536] = {{2,1,-2,0,0,0,0,0}, 0, 0, 2931, 1, 7, 0, 1}, /* TCE */
    [537] = {{0,0,0,0,0,0,0,0}, 38, 1, 1, 1, 0, 0, 1}, /* heap */
    [538] = {{0,0,0,0,0,0,0,0}, 40, 1, 1, 1, 0, 0, 1}, /* hole */
    [539] = {{1,0,0,0,0,0,0,0}, 0, 0, 1, 33, 1, 0, 1}, /* shaku */
    [540] = {{1,0,0,0,0,0,0,0}, 0, 0, 1, 33, 0, 0, 1}, /* sun */
    [541] = {{1,0,0,0,0,0,0,0}, 0, 0, 432, 11, 1, 0, 1}, /* ri */
    [542] = {{1,0,0,0,0,0,0,0}, 0, 0, 1, 33, 2, 0, 1}, /* jo */
    [543] = {{2,0,0,0,0,0,0,0}, 0, 0, 4, 121, 2, 0, 1}, /* tsubo */
    [544] = {{2,0,0,0,0,0,0,0}, 0, 0, 2, 121, 2, 0, 1}, /* tatami */
    [545] = {{3,0,0,0,0,0,0,0}, 0, 0, 18039, 1, -5, 0, 1}, /* koku */
    [546] = {{3,0,0,0,0,0,0,0}, 0, 0, 18039, 1, -8, 0, 1}, /* g\xc5\x8d */
    [547] = {{0,1,0,0,0,0,0,0}, 0, 0, 3, 8, -2, 0, 1}, /* momme */
    [548] = {{0,1,0,0,0,0,0,0}, 0, 0, 15, 4, 0, 0, 1}, /* kanme */
    [549] = {{1,0,0,0,0,0,0,0}, 0, 0, 1, 3, 0, 0, 1}, /* chi */
    [550] = {{1,0,0,0,0,0,0,0}, 0, 0, 1, 3, -1, 0, 1}, /* cun */
    [551] = {{1,0,0,0,0,0,0,0}, 0, 0, 1, 3, -2, 0, 1}, /* fen */
    [552] = {{1,0,0,0,0,0,0,0}, 0, 0, 1, 3, 1, 0, 1}, /* zhang */
    [553] = {{1,0,0,0,0,0,0,0}, 0, 0, 5, 1, 2, 0, 1}, /* li */
    [554] = {{2,0,0,0,0,0,0,0}, 0, 0, 2, 3, 3, 0, 1}, /* mu */
    [555] = {{0,1,0,0,0,0,0,0}, 0, 0, 1, 2, 0, 0, 1}, /* jin */
    [556] = {{0,1,0,0,0,0,0,0}, 0, 0, 1, 2, -1, 0, 1}, /* liang */
    [557] = {{0,1,0,0,0,0,0,0}, 0, 0, 5, 1, 1, 0, 1}, /* dan */
    [558] = {{1,0,0,0,0,0,0,0}, 0, 0, 5334, 5, 0, 0, 1}, /* verst */
    [559] = {{1,0,0,0,0,0,0,0}, 0, 0, 889, 125, -1, 0, 1}, /* arshin */
    [560] = {{1,0,0,0,0,0,0,0}, 0, 0, 2667, 125, -1, 0, 1}, /* sazhen */
    [561] = {{1,0,0,0,0,0,0,0}, 0, 0, 889, 2, -4, 0, 1}, /* vershok */
    [562] = {{0,1,0,0,0,0,0,0}, 0, 0, 32761, 2, -3, 0, 1}, /* pud */
    [563] = {{0,1,0,0,0,0,0,0}, 0, 0, 40951241, 1, -8, 0, 1}, /* funt_ru */
    [564] = {{3,0,0,0,0,0,0,0}, 0, 0, 20991, 1, -5, 0, 1}, /* chetvert */
    [565] = {{1,0,0,0,0,0,0,0}, 0, 0, 1624203, 5, -6, 0, 1}, /* pied */
    [566] = {{1,0,0,0,0,0,0,0}, 0, 0, 2707, 1, -5, 0, 1}, /* pouce */
    [567] = {{1,0,0,0,0,0,0,0}, 0, 0, 487259, 25, -4, 0, 1}, /* toise */
    [568] = {{2,0,0,0,0,0,0,0}, 0, 0, 341889, 1, -2, 0, 1}, /* arpent */
    [569] = {{1,0,0,0,0,0,0,0}, 0, 0, 487259, 125, 0, 0, 1}, /* lieue_de_poste */
    [570] = {{1,0,0,0,0,0,0,0}, 0, 0, 37, 125, 0, 0, 1}, /* pes */
    [571] = {{1,0,0,0,0,0,0,0}, 0, 0, 37, 25, 0, 0, 1}, /* passus */
    [572] = {{1,0,0,0,0,0,0,0}, 0, 0, 148, 1, 1, 0, 1}, /* mille_passuum */
    [573] = {{2,0,0,0,0,0,0,0}, 0, 0, 251943, 1, -2, 0, 1}, /* iugerum */
    [574] = {{0,1,0,0,0,0,0,0}, 0, 0, 16447, 5, -4, 0, 1}, /* libra_roma */
    [575] = {{0,1,0,0,0,0,0,0}, 0, 0, 137, 5, -3, 0, 1}, /* uncia_roma */
    [576] = {{3,0,0,0,0,0,0,0}, 0, 0, 82, 3125, 0, 0, 1}, /* amphora */
    [577] = {{1,0,0,0,0,0,0,0}, 0, 0, 21, 4, -1, 0, 1}, /* royal_cubit */
    [578] = {{1,0,0,0,0,0,0,0}, 0, 0, 3, 4, -1, 0, 1}, /* egypt_palm */
    [579] = {{1,0,0,0,0,0,0,0}, 0, 0, 3, 16, -1, 0, 1}, /* digit */
    [580] = {{1,0,0,0,0,0,0,0}, 0, 0, 105, 2, 0, 0, 1}, /* khet */
    [581] = {{2,0,0,0,0,0,0,0}, 0, 0, 11025, 4, 0, 0, 1}, /* aroura */
    [582] = {{1,0,0,0,0,0,0,0}, 0, 0, 1143, 25, -2, 0, 1}, /* hath */
    [583] = {{1,0,0,0,0,0,0,0}, 0, 0, 1143, 125, -1, 0, 1}, /* gaz */
    [584] = {{1,0,0,0,0,0,0,0}, 0, 0, 3219, 1, 0, 0, 1}, /* kos */
    [585] = {{0,1,0,0,0,0,0,0}, 0, 0, 729, 625, -2, 0, 1}, /* tola */
    [586] = {{0,1,0,0,0,0,0,0}, 0, 0, 9331, 1, -4, 0, 1}, /* seer */
    [587] = {{0,1,0,0,0,0,0,0}, 0, 0, 186621, 5, -3, 0, 1}, /* maund */
    [588] = {{2,1,-2,0,0,0,0,0}, 0, 0, 1, 229371227839632473, 0, 0, 1}, /* hartree */
    [589] = {{2,1,-2,0,0,0,0,0}, 0, 0, 1, 458742455679275483, 0, 0, 1}, /* rydberg_unit */
    [590] = {{1,0,0,0,0,0,0,0}, 0, 0, 1331, 25152254718769, 0, 0, 1}, /* bohr_radius */
    [591] = {{1,0,0,0,0,0,0,0}, 0, 0, 244, 100564221388997, 0, 0, 1}, /* compton_e */
    [592] = {{1,0,0,0,0,0,0,0}, 0, 0, 4, 3027069900897207, 0, 0, 1}, /* compton_p */
    [593] = {{1,0,0,0,0,0,0,0}, 0, 0, 6, 4546863708731791, 0, 0, 1}, /* compton_n */
    [594] = {{0,0,0,0,0,0,0,0}, 0, 0, 6648447, 911076577, 0, 0, 1}, /* fine_structure */
    [595] = {{0,1,0,0,0,0,0,0}, 0, 0, 910938370150000167, 1, -48, 0, 1}, /* electron_mass */
    [596] = {{0,1,0,0,0,0,0,0}, 0, 0, 167262192369000028, 1, -44, 0, 1}, /* proton_mass */
    [597] = {{0,1,0,0,0,0,0,0}, 0, 0, 167492749804000019, 1, -44, 0, 1}, /* neutron_mass */
    [598] = {{0,1,0,0,0,0,0,0}, 0, 0, 188353162700000022, 1, -45, 0, 1}, /* muon_mass */
    [599] = {{2,1,-3,0,0,0,0,0}, 0, 0, 19619, 2, 0, 0, 1}, /* boiler_horsepower */
    [600] = {{2,1,-3,0,0,0,0,0}, 0, 0, 746, 1, 0, 0, 1}, /* electric_horsepower */
    [601] = {{2,1,-3,0,0,0,0,0}, 0, 0, 746043, 1, -3, 0, 1}, /* water_horsepower */
    [602] = {{2,1,-3,0,0,0,0,0}, 0, 0, 25013, 1, -2, 0, 1}, /* donkeypower */
    [603] = {{3,0,0,0,0,0,0,0}, 0, 0, 1, 4, -3, 0, 1}, /* metric_cup */
    [604] = {{3,0,0,0,0,0,0,0}, 0, 0, 3, 2, -5, 0, 1}, /* metric_tbsp */
    [605] = {{3,0,0,0,0,0,0,0}, 0, 0, 1, 5, -4, 0, 1}, /* australian_tbsp */
    [606] = {{3,0,0,0,0,0,0,0}, 0, 0, 1, 5, -3, 0, 1}, /* japanese_cup */
    [607] = {{3,0,0,0,0,0,0,0}, 0, 0, 825646, 1452933239, 0, 0, 1}, /* imperial_pint */
    [608] = {{0,0,0,0,0,0,0,1}, 0, 0, 1, 4, 0, 0, 1}, /* crumb */
    [609] = {{0,0,0,0,0,0,0,1}, 0, 0, 4, 1, 0, 0, 1}, /* dword */
    [610] = {{0,0,0,0,0,0,0,1}, 0, 0, 8, 1, 0, 0, 1}, /* qword */
    [611] = {{0,0,0,0,0,0,0,1}, 0, 0, 16, 1, 0, 0, 1}, /* paragraph */
    [612] = {{0,0,0,0,0,0,0,1}, 0, 0, 512, 1, 0, 0, 1}, /* sector */
    [613] = {{0,0,0,0,0,0,0,1}, 0, 0, 4096, 1, 0, 0, 1}, /* page */
    [614] = {{0,0,0,0,0,0,0,1}, 0, 0, 1024, 1, 0, 0, 1}, /* block */
    [615] = {{0,0,0,0,0,0,0,1}, 0, 0, 4096, 1, 0, 0, 1}, /* cluster */
    [616] = {{0,0,0,0,0,0,0,0}, 24, 1, 1, 1, 0, 0, 1}, /* EV */
    [617] = {{0,0,0,0,0,0,0,0}, 26, 1, 1, 1, 0, 0, 1}, /* f_stop */
    [618] = {{0,0,0,0,0,0,0,0}, 49, 1, 1, 1, 0, 0, 1}, /* ISO_speed */
    [619] = {{0,0,0,0,0,0,0,0}, 73, 1, 1, 1, 0, 0, 1}, /* cent_pitch */
    [620] = {{0,0,0,0,0,0,0,0}, 73, 1, 1, 1, 2, 0, 1}, /* semitone */
    [621] = {{0,0,0,0,0,0,0,0}, 73, 1, 1, 301, 3, 0, 1}, /* savart */
    [622] = {{0,0,0,0,0,0,0,0}, 73, 1, 12, 1, 2, 0, 1}, /* octave */
    [623] = {{0,0,0,0,0,0,0,0}, 0, 0, 1, 1, -4, 0, 1}, /* basis_point */
    [624] = {{0,0,0,0,0,0,0,0}, 0, 0, 1, 1, -3, 0, 1}, /* tenth_cent */
    [625] = {{0,0,0,0,0,0,0,0}, 0, 0, 1, 1, -4, 0, 1}, /* pip */
    [626] = {{1,0,0,0,0,0,0,0}, 0, 0, 12573, 625, -2, 0, 1}, /* link_chain */
    [627] = {{1,0,0,0,0,0,0,0}, 0, 0, 762, 125, 0, 0, 1}, /* rope */
    [628] = {{1,0,0,0,0,0,0,0}, 0, 0, 12573, 25, -2, 0, 1}, /* perch */
    [629] = {{1,0,0,0,0,0,0,0}, 0, 0, 127, 15, -3, 0, 1}, /* barleycorn */
    [630] = {{1,0,0,0,0,0,0,0}, 0, 0, 381, 25, -2, 0, 1}, /* shaftment */
    [631] = {{1,0,0,0,0,0,0,0}, 0, 0, 1143, 25, -2, 0, 1}, /* english_cubit */
    [632] = {{1,0,0,0,0,0,0,0}, 0, 0, 1143, 2, -4, 0, 1}, /* nail_cloth */
    [633] = {{1,0,0,0,0,0,0,0}, 0, 0, 926, 5, 0, 0, 1}, /* cable_length */
    [634] = {{-1,1,-2,0,0,0,0,0}, 0, 0, 196133, 2, -1, 0, 1}, /* mH2O */
    [635] = {{-1,1,-2,0,0,0,0,0}, 0, 0, 2490889, 1, -4, 0, 1}, /* inH2O */
    [636] = {{-1,1,-2,0,0,0,0,0}, 0, 0, 29890669, 1, -4, 0, 1}, /* ftH2O */
    [637] = {{-1,1,-2,0,0,0,0,0}, 0, 0, 1, 1, 3, 0, 1}, /* pieze */
    [638] = {{0,0,0,0,0,0,0,0}, 52, 1, 1, 9, -6, 0, 1}, /* denier */
    [639] = {{0,0,0,0,0,0,0,0}, 52, 1, 1, 1, -6, 0, 1}, /* tex */
    [640] = {{0,0,0,0,0,0,0,0}, 52, 1, 1, 1, -7, 0, 1}, /* decitex */
    [641] = {{1,0,0,0,0,0,0,0}, 0, 0, 1, 3, -3, 0, 1}, /* french_gauge */
    [642] = {{1,0,0,0,0,0,0,0}, 0, 0, 127, 1, -6, 0, 1}, /* mickey */
    [643] = {{0,0,0,0,0,0,0,0}, 0, 0, 4, 1, 9, 0, 1}, /* sagan */
    [644] = {{1,0,0,0,0,0,0,0}, 0, 0, 34420332, 114813869, 0, 0, 1}, /* light_nanosecond */
    [645] = {{1,0,0,0,0,0,0,0}, 0, 0, 9, 5, -1, 0, 1}, /* banana_for_scale */
    [646] = {{-3,1,0,0,0,0,0,0}, 0, 0, 1, 1, 0, 0, 1}, /* kg/m\xc2\xb3 */
    [647] = {{3,0,-1,0,0,0,0,0}, 0, 0, 1, 1, 0, 0, 1}, /* m\xc2\xb3/s */
    [648] = {{3,0,-1,0,0,0,0,0}, 0, 0, 1, 6, -4, 0, 1}, /* L/min */
    [649] = {{0,1,-1,0,0,0,0,0}, 0, 0, 1, 1, 0, 0, 1}, /* kg/s */
    [650] = {{2,1,-2,0,-1,0,0,0}, 39, 1, 1, 1, 0, 0, 1}, /* heat_capacity */
    [651] = {{2,1,-2,0,-1,0,0,0}, 22, 1, 1, 1, 0, 0, 1}, /* entropy */
    [652] = {{2,0,-2,0,-1,0,0,0}, 0, 0, 1, 1, 0, 0, 1}, /* J/kg/K */
    [653] = {{1,1,-3,0,-1,0,0,0}, 0, 0, 1, 1, 0, 0, 1}, /* W/m/K */
    [654] = {{0,1,-3,0,0,0,0,0}, 0, 0, 1, 1, 0, 0, 1}, /* W/m\xc2\xb2 */
    [655] = {{1,1,-3,-1,0,0,0,0}, 0, 0, 1, 1, 0, 0, 1}, /* V/m */
    [656] = {{-2,0,0,1,0,0,0,0}, 0, 0, 1, 1, 0, 0, 1}, /* A/m\xc2\xb2 */
    [657] = {{3,1,-3,-2,0,0,0,0}, 0, 0, 1, 1, 0, 0, 1}, /* \xce\xa9\xc2\xb7m */
    [658] = {{-3,-1,3,2,0,0,0,0}, 0, 0, 1, 1, 0, 0, 1}, /* S/m */
    [659] = {{-3,0,1,1,0,0,0,0}, 0, 0, 1, 1, 0, 0, 1}, /* C/m\xc2\xb3 */
    [660] = {{0,1,-2,0,0,0,0,0}, 0, 0, 1, 1, 0, 0, 1}, /* N/m */
    [661] = {{-1,1,0,0,0,0,0,0}, 0, 0, 1, 1, 0, 0, 1}, /* kg/m */
    [662] = {{-2,1,0,0,0,0,0,0}, 0, 0, 1, 1, 0, 0, 1}, /* kg/m\xc2\xb2 */
    [663] = {{-1,1,-2,0,0,0,0,0}, 0, 0, 1, 1, 0, 0, 1}, /* J/m\xc2\xb3 */
    [664] = {{2,0,-2,0,0,0,0,0}, 0, 0, 1, 1, 0, 0, 1}, /* J/kg */
    [665] = {{2,0,-2,0,0,0,0,0}, 87, 1, 1, 1, 0, 0, 1}, /* specific_energy */
    [666] = {{0,0,0,0,0,0,0,0}, 77, 1, 1, 1, 0, 0, 1}, /* mol/mol */
    [667] = {{-3,0,-1,0,0,1,0,0}, 0, 0, 1, 1, 0, 0, 1}, /* kat/m\xc2\xb3 */
    [668] = {{-2,0,0,0,0,0,1,0}, 55, 1, 1, 1, 0, 0, 1}, /* cd/m\xc2\xb2 */
    [669] = {{-2,0,1,0,0,0,1,0}, 42, 1, 1, 1, 0, 0, 1}, /* lx\xc2\xb7s */
    [670] = {{0,0,1,0,0,0,1,0}, 56, 1, 1, 1, 0, 0, 1}, /* lm\xc2\xb7s */
    [671] = {{0,0,-1,0,0,0,0,0}, 2, 1, 1, 1, 0, 0, 1}, /* rad/s */
    [672] = {{0,0,-2,0,0,0,0,0}, 2, 1, 1, 1, 0, 0, 1}, /* rad/s\xc2\xb2 */
    [673] = {{1,0,-3,0,0,0,0,0}, 0, 0, 1, 1, 0, 0, 1}, /* m/s\xc2\xb3 */
    [674] = {{1,1,-1,0,0,0,0,0}, 66, 1, 1, 1, 0, 0, 1}, /* kg\xc2\xb7m/s */
    [675] = {{1,1,-1,0,0,0,0,0}, 43, 1, 1, 1, 0, 0, 1}, /* N\xc2\xb7s */
    [676] = {{2,1,-2,0,0,0,0,0}, 94, 1, 1, 1, 0, 0, 1}, /* N\xc2\xb7m */
    [677] = {{0,0,0,0,0,0,0,1}, 88, 1, 1, 8, 0, 0, 1}, /* bit/s/Hz */
    [678] = {{2,1,-2,0,0,0,0,0}, 67, -1, 1, 1, 0, 0, 1}, /* J/op */
    [679] = {{2,1,-2,0,0,0,0,0}, 93, -1, 1, 1, 0, 0, 1}, /* J/tok */
    [680] = {{0,0,0,0,0,0,0,1}, 28, -1, 1, 1, 0, 0, 1}, /* B/flop */
    [681] = {{0,1,0,0,0,0,0,0}, 13, 1, 1, 1, 0, 0, 1}, /* kgCO\xe2\x82\x82\x65 */
    [682] = {{0,1,0,0,0,0,0,0}, 13, 1, 1, 1, -3, 0, 1}, /* gCO\xe2\x82\x82\x65 */
    [683] = {{-2,0,2,0,0,0,0,0}, 13, 1, 1, 36, -8, 0, 1}, /* gCO\xe2\x82\x82\x65/kWh */
    [684] = {{-1,1,0,0,0,0,0,0}, 97, 1, 1, 1, -6, 0, 1}, /* gCO\xe2\x82\x82\x65/pkm */
    [685] = {{1,0,0,0,0,0,0,0}, 0, 0, 127, 48, -4, 0, 1}, /* px */
    [686] = {{-1,0,0,0,0,0,0,0}, 0, 0, 5, 127, 3, 0, 1}, /* dpi */
    [687] = {{-1,0,0,0,0,0,0,0}, 0, 0, 48, 127, 4, 0, 1}, /* dppx */
    [688] = {{0,0,0,0,0,0,0,0}, 15, 1, 1, 1, 0, 0, 1}, /* rem_css */
    [689] = {{0,0,0,0,0,0,0,0}, 99, 1, 1, 1, 0, 0, 1}, /* vw */
    [690] = {{0,0,0,0,0,0,0,0}, 98, 1, 1, 1, 0, 0, 1}, /* vh */
    [691] = {{0,0,1,0,0,0,0,0}, 71, 1, 36, 1, 2, 0, 1}, /* person_hour */
    [692] = {{0,0,1,0,0,0,0,0}, 75, 1, 31556952, 1, 0, 0, 1}, /* QALY */
    [693] = {{0,0,0,0,0,0,0,0}, 89, 1, 1, 1, 0, 0, 1}, /* story_point */
    [694] = {{0,0,0,0,0,0,0,0}, 32, 1, 22203, 4, -5, 0, 1}, /* mg/dL_glucose */
    [695] = {{0,0,0,0,0,0,0,0}, 32, 1, 1, 1, 0, 0, 1}, /* mmol/L_glucose */
    [696] = {{1,0,-1,0,0,0,0,0}, 0, 0, 343, 1, 0, 0, 1}, /* mach_air_20C */
    [697] = {{-3,0,0,0,0,1,0,0}, 0, 0, 1, 1, 3, 0, 1}, /* M */
    [698] = {{-3,0,0,0,0,1,0,0}, 0, 0, 1, 1, 3, 0, 1}, /* mol/L */
    [699] = {{-3,0,0,0,0,1,0,0}, 0, 0, 1, 1, 0, 0, 1}, /* mmol/L */
    [700] = {{-3,0,0,0,0,1,0,0}, 0, 0, 1, 1, -3, 0, 1}, /* \xc2\xb5mol/L */
    [701] = {{-3,0,0,0,0,1,0,0}, 0, 0, 1, 1, -6, 0, 1}, /* nmol/L */
    [702] = {{-3,0,0,0,0,1,0,0}, 0, 0, 1, 1, 0, 0, 1}, /* mol/m\xc2\xb3 */
    [703] = {{-3,1,0,0,0,0,0,0}, 0, 0, 1, 1, 0, 0, 1}, /* g/L */
    [704] = {{-3,1,0,0,0,0,0,0}, 0, 0, 1, 1, -3, 0, 1}, /* mg/L */
    [705] = {{-3,1,0,0,0,0,0,0}, 0, 0, 1, 1, -2, 0, 1}, /* mg/dL */
    [706] = {{-3,1,0,0,0,0,0,0}, 0, 0, 1, 1, 1, 0, 1}, /* g/dL */
    [707] = {{-3,1,0,0,0,0,0,0}, 0, 0, 1, 1, -3, 0, 1}, /* \xc2\xb5g/mL */
    [708] = {{-3,1,0,0,0,0,0,0}, 0, 0, 1, 1, -6, 0, 1}, /* ng/mL */
    [709] = {{0,0,0,0,0,1,0,0}, 12, 1, 1, 1, 0, 0, 1}, /* Eq */
    [710] = {{-3,0,0,0,0,1,0,0}, 12, 1, 1, 1, 3, 0, 1}, /* Eq/L */
    [711] = {{-3,0,0,0,0,1,0,0}, 12, 1, 1, 1, 0, 0, 1}, /* mEq/L */
    [712] = {{0,0,0,0,0,1,0,0}, 68, 1, 1, 1, 0, 0, 1}, /* osmol */
    [713] = {{-3,0,0,0,0,1,0,0}, 68, 1, 1, 1, 3, 0, 1}, /* Osm/L */
    [714] = {{-3,0,0,0,0,1,0,0}, 68, 1, 1, 1, 0, 0, 1}, /* mOsm/L */
    [715] = {{0,0,-1,0,0,1,0,0}, 0, 0, 1, 6, -7, 0, 1}, /* U_enzyme */
    [716] = {{-3,0,-1,0,0,1,0,0}, 0, 0, 1, 6, -4, 0, 1}, /* U/L */
    [717] = {{0,0,0,0,0,0,0,0}, 46, 1, 1, 1, 0, 0, 1}, /* IU */
    [718] = {{0,0,0,0,0,0,0,0}, 14, 1, 1, 1, 0, 0, 1}, /* CFU */
    [719] = {{0,0,0,0,0,0,0,0}, 74, 1, 1, 1, 0, 0, 1}, /* PFU */
    [720] = {{0,0,0,0,0,0,0,0}, 10, 1, 1, 1, 0, 0, 1}, /* cell */
    [721] = {{0,0,0,0,0,0,0,0}, 64, 1, 1, 1, 0, 0, 1}, /* copy */
    [722] = {{-3,0,0,0,0,0,0,0}, 14, 1, 1, 1, 6, 0, 1}, /* CFU/mL */
    [723] = {{-3,0,0,0,0,0,0,0}, 74, 1, 1, 1, 6, 0, 1}, /* PFU/mL */
    [724] = {{-3,0,0,0,0,0,0,0}, 10, 1, 1, 1, 6, 0, 1}, /* cells/mL */
    [725] = {{-3,0,0,0,0,0,0,0}, 64, 1, 1, 1, 6, 0, 1}, /* copies/mL */
    [726] = {{-3,0,0,0,0,0,0,0}, 46, 1, 1, 1, 6, 0, 1}, /* IU/mL */
    [727] = {{0,0,1,0,0,0,0,0}, 0, 0, 1, 1, -13, 0, 1}, /* Svedberg */
    [728] = {{0,0,1,1,0,0,0,0}, 0, 0, 36, 1, 2, 0, 1}, /* Ah */
    [729] = {{2,1,-3,0,0,0,0,0}, 79, 1, 1, 1, 0, 0, 1}, /* var */
    [730] = {{2,1,-3,0,0,0,0,0}, 4, 1, 1, 1, 0, 0, 1}, /* VA */
    [731] = {{0,0,0,1,0,0,0,0}, 0, 0, 1, 1, 1, 0, 1}, /* abA */
    [732] = {{0,0,0,1,0,0,0,0}, 0, 0, 1, 299792458, -1, 0, 1}, /* statA */
    [733] = {{0,0,1,1,0,0,0,0}, 0, 0, 1, 1, 1, 0, 1}, /* abC */
    [734] = {{0,0,1,1,0,0,0,0}, 0, 0, 1, 299792458, -1, 0, 1}, /* statC */
    [735] = {{2,1,-3,-1,0,0,0,0}, 0, 0, 1, 1, -8, 0, 1}, /* abV */
    [736] = {{2,1,-3,-1,0,0,0,0}, 0, 0, 149896229, 5, -5, 0, 1}, /* statV */
    [737] = {{2,1,-3,-2,0,0,0,0}, 0, 0, 1, 1, -9, 0, 1}, /* ab\xce\xa9 */
    [738] = {{2,1,-3,-2,0,0,0,0}, 0, 0, 22468879468420441, 25, -3, 0, 1}, /* stat\xce\xa9 */
    [739] = {{-2,-1,4,2,0,0,0,0}, 0, 0, 1, 1, 9, 0, 1}, /* abF */
    [740] = {{-2,-1,4,2,0,0,0,0}, 0, 0, 25, 22468879468420441, 3, 0, 1}, /* statF */
    [741] = {{2,1,-2,-2,0,0,0,0}, 0, 0, 1, 1, -9, 0, 1}, /* abH */
    [742] = {{2,1,-2,-2,0,0,0,0}, 0, 0, 22468879468420441, 25, -3, 0, 1}, /* statH */
    [743] = {{-2,0,0,0,0,0,1,0}, 42, 1, 1, 1, 4, 0, 1}, /* phot */
    [744] = {{-2,0,0,0,0,0,1,0}, 42, 1, 15625, 145161, 2, 0, 1}, /* fc */
    [745] = {{-1,0,0,0,0,0,0,0}, 0, 0, 1, 1, 0, 0, 1}, /* diopter */
    [746] = {{2,1,-3,0,0,0,0,0}, 86, -1, 1, 1, 0, 0, 1}, /* W/sr */
    [747] = {{0,1,-3,0,0,0,0,0}, 86, -1, 1, 1, 0, 0, 1}, /* W/sr/m\xc2\xb2 */
    [748] = {{0,1,-2,0,0,0,0,0}, 16, -1, 1, 1, 0, 0, 1}, /* W/m\xc2\xb2/Hz */
    [749] = {{-1,1,-3,0,0,0,0,0}, 0, 0, 1, 1, 0, 0, 1}, /* W/m\xc2\xb3 */
    [750] = {{0,1,-2,0,0,0,0,0}, 0, 0, 1, 1, 0, 0, 1}, /* J/m\xc2\xb2 */
    [751] = {{0,0,0,0,0,0,0,0}, 72, 1, 1, 1, 0, 0, 1}, /* photon */
    [752] = {{0,0,0,0,0,1,0,0}, 72, 1, 1, 1, 0, 0, 1}, /* einstein */
    [753] = {{-2,0,-1,0,0,1,0,0}, 72, 1, 1, 1, 0, 0, 1}, /* mol_photon/m\xc2\xb2/s */
    [754] = {{-2,0,-1,0,0,1,0,0}, 72, 1, 1, 1, -6, 0, 1}, /* \xc2\xb5mol_photon/m\xc2\xb2/s */
    [755] = {{2,0,-2,0,0,0,0,0}, 1, 1, 1, 1, -2, 0, 1}, /* rad_dose */
    [756] = {{0,-1,1,1,0,0,0,0}, 48, 1, 129, 5, -5, 0, 1}, /* R_exposure */
    [757] = {{2,0,-3,0,0,0,0,0}, 1, 1, 1, 1, 0, 0, 1}, /* Gy/s */
    [758] = {{2,0,-3,0,0,0,0,0}, 23, 1, 1, 36, -2, 0, 1}, /* Sv/h */
    [759] = {{0,-1,-1,0,0,0,0,0}, 17, 1, 1, 1, 0, 0, 1}, /* Bq/kg */
    [760] = {{-3,0,-1,0,0,0,0,0}, 17, 1, 1, 1, 0, 0, 1}, /* Bq/m\xc2\xb3 */
    [761] = {{0,0,0,0,0,0,0,0}, 18, 1, 1, 1, 0, 0, 1}, /* count */
    [762] = {{0,0,0,0,0,0,0,0}, 2, 1, 7835, 1616084756946, 0, 0, 1}, /* mas */
    [763] = {{0,0,0,0,0,0,0,0}, 2, 1, 301, 62085706680376, 0, 0, 1}, /* \xc2\xb5\x61s */
    [764] = {{1,0,0,0,0,0,0,0}, 0, 0, 6957, 1, 5, 0, 1}, /* R_sun_nominal */
    [765] = {{2,1,-3,0,0,0,0,0}, 0, 0, 3828, 1, 23, 0, 1}, /* L_sun_nominal */
    [766] = {{2,1,-2,0,0,0,0,0}, 0, 0, 1, 1, 44, 0, 1}, /* foe */
    [767] = {{-2,0,0,0,0,1,0,0}, 0, 0, 67175, 150553519, 0, 0, 1}, /* DU */
    [768] = {{2,-1,-1,0,1,0,0,0}, 0, 0, 1, 1, -6, 0, 1}, /* PVU */
    [769] = {{3,0,-1,0,0,0,0,0}, 0, 0, 1, 1, 6, 0, 1}, /* sverdrup */
    [770] = {{2,0,0,0,0,0,0,0}, 0, 0, 9869233, 1, -19, 0, 1}, /* darcy */
    [771] = {{1,0,-2,0,0,0,0,0}, 0, 0, 1, 1, -5, 0, 1}, /* mGal */
    [772] = {{0,0,-2,0,0,0,0,0}, 0, 0, 1, 1, -9, 0, 1}, /* Eotvos */
    [773] = {{-2,0,0,0,0,0,0,0}, 20, 1, 1, 1, 16, 0, 1}, /* TECU */
    [774] = {{2,0,-2,0,0,0,0,0}, 31, 1, 196133, 2, -4, 0, 1}, /* gpm */
    [775] = {{0,-1,3,0,1,0,0,0}, 0, 0, 31, 2, -2, 0, 1}, /* clo */
    [776] = {{0,0,0,0,0,0,0,0}, 100, 1, 1, 1, -6, 0, 1}, /* ppmv */
    [777] = {{0,0,0,0,0,0,0,0}, 100, 1, 1, 1, -9, 0, 1}, /* ppbv */
    [778] = {{0,0,0,0,0,0,0,0}, 63, 1, 1, 1, -6, 0, 1}, /* ppmw */
    [779] = {{0,0,0,0,0,0,0,0}, 90, 1, 1, 1, 0, 0, 1}, /* symbol */
    [780] = {{0,0,0,0,0,0,0,0}, 33, 1, 1, 1, 0, 0, 1}, /* edge */
    [781] = {{0,0,0,0,0,0,0,0}, 11, 1, 1, 1, 0, 0, 1}, /* update */
    [782] = {{0,0,-1,0,0,0,0,1}, 0, 0, 1, 8, 0, 0, 1}, /* bit/s */
    [783] = {{0,0,-1,0,0,0,0,1}, 0, 0, 1, 1, 0, 0, 1}, /* B/s */
    [784] = {{0,0,-1,0,0,0,0,1}, 0, 0, 125, 1, 3, 0, 1}, /* Mb/s */
    [785] = {{0,0,-1,0,0,0,0,1}, 0, 0, 125, 1, 6, 0, 1}, /* Gb/s */
    [786] = {{0,0,-1,0,0,0,0,1}, 0, 0, 1, 1, 6, 0, 1}, /* MB/s */
    [787] = {{0,0,-1,0,0,0,0,1}, 0, 0, 1, 1, 9, 0, 1}, /* GB/s */
    [788] = {{0,0,-1,0,0,0,0,1}, 0, 0, 1048576, 1, 0, 0, 1}, /* MiB/s */
    [789] = {{0,0,-1,0,0,0,0,1}, 0, 0, 1073741824, 1, 0, 0, 1}, /* GiB/s */
    [790] = {{0,0,0,0,0,0,0,1}, 90, -1, 1, 8, 0, 0, 1}, /* bit/symbol */
    [791] = {{-2,-1,2,0,0,0,0,0}, 28, 1, 1, 1, 0, 0, 1}, /* flop/J */
    [792] = {{-2,-1,2,0,0,0,0,0}, 67, 1, 1, 1, 0, 0, 1}, /* op/J */
    [793] = {{-2,-1,2,0,0,0,0,0}, 93, 1, 1, 1, 0, 0, 1}, /* tok/J */
    [794] = {{0,0,0,0,0,0,0,0}, 9, 1, 1, 1, 0, 0, 1}, /* bortle */
    [795] = {{0,0,0,0,0,0,0,0}, 7, 1, 1, 1, 0, 0, 1}, /* beaufort */
    [796] = {{0,0,0,0,0,0,0,0}, 83, 1, 1, 1, 0, 0, 1}, /* saffir_simpson */
    [797] = {{0,0,0,0,0,0,0,0}, 30, 1, 1, 1, 0, 0, 1}, /* fujita */
    [798] = {{0,0,0,0,0,0,0,0}, 19, 1, 1, 1, 0, 0, 1}, /* EF */
    [799] = {{0,0,0,0,0,0,0,0}, 59, 1, 1, 1, 0, 0, 1}, /* richter */
    [800] = {{0,0,0,0,0,0,0,0}, 59, 1, 1, 1, 0, 0, 1}, /* moment_magnitude */
    [801] = {{0,0,0,0,0,0,0,0}, 3, 1, 1, 1, 0, 0, 1}, /* apgar */
    [802] = {{0,0,0,0,0,0,0,0}, 78, 1, 1, 1, 0, 0, 1}, /* RBE */
    [803] = {{0,0,0,0,0,0,0,0}, 41, 1, 1, 1, 0, 0, 1}, /* hounsfield_unit */
    [804] = {{1,0,0,0,0,0,0,0}, 0, 0, 9, 2, -1, 0, 1}, /* short_cubit */
    [805] = {{3,0,0,0,0,0,0,0}, 0, 0, 3087, 64, -4, 0, 1}, /* hekat */
    [806] = {{3,0,0,0,0,0,0,0}, 0, 0, 3087, 2048, -5, 0, 1}, /* ro */
    [807] = {{3,0,0,0,0,0,0,0}, 0, 0, 3087, 32, -3, 0, 1}, /* khar */
    [808] = {{0,0,1,0,0,0,0,0}, 0, 0, 864, 1, 3, 0, 1}, /* decan */
    [809] = {{0,0,0,0,0,0,0,0}, 85, 1, 1, 1, 0, 0, 1}, /* slope */
    [810] = {{0,0,0,0,0,0,0,0}, 85, 1, 1, 1, -2, 0, 1}, /* percent_grade */
    [811] = {{0,0,0,0,0,0,0,0}, 5, 1, 1, 1, 0, 0, 1}, /* batter */
    [812] = {{0,0,0,0,0,0,0,0}, 5, 1, 1, 7, 0, 0, 1}, /* seked */
    [813] = {{1,0,0,0,0,0,0,0}, 0, 0, 1, 3, 2, 0, 1}, /* yin */
    [814] = {{1,0,0,0,0,0,0,0}, 0, 0, 5, 3, 0, 0, 1}, /* bu_cn */
    [815] = {{1,0,0,0,0,0,0,0}, 0, 0, 1, 3, -4, 0, 1}, /* hao */
    [816] = {{2,0,0,0,0,0,0,0}, 0, 0, 2, 3, 5, 0, 1}, /* qing */
    [817] = {{0,1,0,0,0,0,0,0}, 0, 0, 1, 2, -2, 0, 1}, /* qian */
    [818] = {{3,0,0,0,0,0,0,0}, 0, 0, 1, 1, -2, 0, 1}, /* dou */
    [819] = {{3,0,0,0,0,0,0,0}, 0, 0, 1, 1, -3, 0, 1}, /* sheng */
    [820] = {{0,0,-1,0,0,0,0,0}, 6, 1, 1, 6, -1, 0, 1}, /* bpm */
    [821] = {{0,0,-1,0,0,0,0,0}, 29, 1, 1, 1, 0, 0, 1}, /* fps */
    [822] = {{0,0,-1,0,0,0,0,0}, 17, 1, 1, 6, -1, 0, 1}, /* dpm */
    [823] = {{0,0,-1,0,0,0,0,0}, 18, 1, 1, 1, 0, 0, 1}, /* cps */
    [824] = {{0,0,-1,0,0,0,0,0}, 18, 1, 1, 6, -1, 0, 1}, /* cpm */
    [825] = {{0,0,-1,0,0,0,0,0}, 28, 1, 1, 1, 0, 0, 1}, /* flops */
    [826] = {{0,0,-1,0,0,0,0,0}, 28, 1, 1, 1, 0, 0, 1}, /* FLOPS */
    [827] = {{0,0,-1,0,0,0,0,0}, 28, 1, 1, 1, 3, 0, 1}, /* kflops */
    [828] = {{0,0,-1,0,0,0,0,0}, 28, 1, 1, 1, 3, 0, 1}, /* kFLOPS */
    [829] = {{0,0,-1,0,0,0,0,0}, 28, 1, 1, 1, 6, 0, 1}, /* Mflops */
    [830] = {{0,0,-1,0,0,0,0,0}, 28, 1, 1, 1, 6, 0, 1}, /* MFLOPS */
    [831] = {{0,0,-1,0,0,0,0,0}, 28, 1, 1, 1, 9, 0, 1}, /* Gflops */
    [832] = {{0,0,-1,0,0,0,0,0}, 28, 1, 1, 1, 9, 0, 1}, /* GFLOPS */
    [833] = {{0,0,-1,0,0,0,0,0}, 28, 1, 1, 1, 12, 0, 1}, /* Tflops */
    [834] = {{0,0,-1,0,0,0,0,0}, 28, 1, 1, 1, 12, 0, 1}, /* TFLOPS */
    [835] = {{0,0,-1,0,0,0,0,0}, 28, 1, 1, 1, 15, 0, 1}, /* Pflops */
    [836] = {{0,0,-1,0,0,0,0,0}, 28, 1, 1, 1, 15, 0, 1}, /* PFLOPS */
    [837] = {{0,0,-1,0,0,0,0,0}, 28, 1, 1, 1, 18, 0, 1}, /* Eflops */
    [838] = {{0,0,-1,0,0,0,0,0}, 28, 1, 1, 1, 18, 0, 1}, /* EFLOPS */
    [839] = {{0,0,-1,0,0,0,0,0}, 28, 1, 1, 1, 21, 0, 1}, /* Zflops */
    [840] = {{0,0,-1,0,0,0,0,0}, 28, 1, 1, 1, 21, 0, 1}, /* ZFLOPS */
    [841] = {{0,0,-1,0,0,0,0,0}, 28, 1, 999999999999999983, 1, 6, 0, 1}, /* Yflops */
    [842] = {{0,0,-1,0,0,0,0,0}, 28, 1, 999999999999999983, 1, 6, 0, 1}, /* YFLOPS */
    [843] = {{0,0,-1,0,0,0,0,0}, 67, 1, 1, 1, 0, 0, 1}, /* ops_per_s */
    [844] = {{0,0,-1,0,0,0,0,0}, 67, 1, 1, 1, 3, 0, 1}, /* KOPS */
    [845] = {{0,0,-1,0,0,0,0,0}, 67, 1, 1, 1, 6, 0, 1}, /* MOPS */
    [846] = {{0,0,-1,0,0,0,0,0}, 67, 1, 1, 1, 9, 0, 1}, /* GOPS */
    [847] = {{0,0,-1,0,0,0,0,0}, 67, 1, 1, 1, 12, 0, 1}, /* TOPS */
    [848] = {{0,0,-1,0,0,0,0,0}, 67, 1, 1, 1, 15, 0, 1}, /* POPS */
    [849] = {{0,0,-1,0,0,0,0,0}, 67, 1, 1, 1, 18, 0, 1}, /* EOPS */
    [850] = {{0,0,-1,0,0,0,0,0}, 45, 1, 1, 1, 6, 0, 1}, /* MIPS */
    [851] = {{0,0,-1,0,0,0,0,0}, 45, 1, 1, 1, 9, 0, 1}, /* GIPS */
    [852] = {{0,0,-1,0,0,0,0,0}, 45, 1, 1, 1, 6, 0, 1}, /* DMIPS */
    [853] = {{0,0,-1,0,0,0,0,0}, 58, 1, 1, 1, 0, 0, 1}, /* MAC/s */
    [854] = {{0,0,-1,0,0,0,0,0}, 58, 1, 1, 1, 6, 0, 1}, /* MMAC/s */
    [855] = {{0,0,-1,0,0,0,0,0}, 58, 1, 1, 1, 9, 0, 1}, /* GMAC/s */
    [856] = {{0,0,-1,0,0,0,0,0}, 58, 1, 1, 1, 12, 0, 1}, /* TMAC/s */
    [857] = {{0,0,-1,0,0,0,0,0}, 93, 1, 1, 1, 0, 0, 1}, /* tok/s */
    [858] = {{0,0,-1,0,0,0,0,0}, 93, 1, 1, 1, 3, 0, 1}, /* ktok/s */
    [859] = {{0,0,-1,0,0,0,0,0}, 93, 1, 1, 1, 6, 0, 1}, /* Mtok/s */
    [860] = {{0,0,-1,0,0,0,0,0}, 93, 1, 1, 1, 9, 0, 1}, /* Gtok/s */
    [861] = {{0,0,-1,0,0,0,0,0}, 96, 1, 1, 1, 0, 0, 1}, /* T/s */
    [862] = {{0,0,-1,0,0,0,0,0}, 96, 1, 1, 1, 6, 0, 1}, /* MT/s */
    [863] = {{0,0,-1,0,0,0,0,0}, 96, 1, 1, 1, 9, 0, 1}, /* GT/s */
    [864] = {{0,0,-1,0,0,0,0,0}, 96, 1, 1, 1, 12, 0, 1}, /* TT/s */
    [865] = {{0,0,-1,0,0,0,0,0}, 76, 1, 1, 1, 0, 0, 1}, /* qps */
    [866] = {{0,0,-1,0,0,0,0,0}, 76, 1, 1, 1, 0, 0, 1}, /* QPS */
    [867] = {{0,0,-1,0,0,0,0,0}, 80, 1, 1, 1, 0, 0, 1}, /* rps */
    [868] = {{0,0,-1,0,0,0,0,0}, 80, 1, 1, 1, 0, 0, 1}, /* RPS */
    [869] = {{0,0,-1,0,0,0,0,0}, 95, 1, 1, 1, 0, 0, 1}, /* tps */
    [870] = {{0,0,-1,0,0,0,0,0}, 95, 1, 1, 1, 0, 0, 1}, /* TPS */
    [871] = {{0,0,-1,0,0,0,0,0}, 69, 1, 1, 1, 0, 0, 1}, /* pps */
    [872] = {{0,0,-1,0,0,0,0,0}, 69, 1, 1, 1, 0, 0, 1}, /* PPS */
    [873] = {{0,0,-1,0,0,0,0,0}, 47, 1, 1, 1, 0, 0, 1}, /* iops */
    [874] = {{0,0,-1,0,0,0,0,0}, 47, 1, 1, 1, 0, 0, 1}, /* IOPS */
    [875] = {{0,0,-1,0,0,0,0,0}, 33, 1, 1, 1, 12, 0, 1}, /* TEPS */
    [876] = {{0,0,-1,0,0,0,0,0}, 11, 1, 1, 1, 9, 0, 1}, /* GUPS */
    [877] = {{-3,0,0,0,0,1,0,0}, 0, 0, 1, 1, 3, 0, 1}, /* molar */
    [878] = {{0,-1,0,0,0,1,0,0}, 0, 0, 1, 1, 0, 0, 1}, /* molal */
    [879] = {{1,0,0,0,0,0,0,0}, 0, 0, 1, 1, 30, 0, 1}, /* Qm */
    [880] = {{0,1,0,0,0,0,0,0}, 0, 0, 1, 1, 27, 0, 1}, /* Qg */
    [881] = {{0,0,1,0,0,0,0,0}, 0, 0, 1, 1, 30, 0, 1}, /* Qs */
    [882] = {{0,0,0,1,0,0,0,0}, 0, 0, 1, 1, 30, 0, 1}, /* QA */
    [883] = {{0,0,0,0,1,0,0,0}, 0, 0, 1, 1, 30, 0, 1}, /* QK */
    [884] = {{0,0,0,0,0,1,0,0}, 0, 0, 1, 1, 30, 0, 1}, /* Qmol */
    [885] = {{0,0,0,0,0,0,1,0}, 57, 1, 1, 1, 30, 0, 1}, /* Qcd */
    [886] = {{0,1,-2,0,0,0,0,0}, 16, -1, 1, 1, 4, 0, 1}, /* QJy */
    [887] = {{2,1,-3,0,0,0,0,0}, 79, 1, 1, 1, 30, 0, 1}, /* Qvar */
    [888] = {{2,1,-3,0,0,0,0,0}, 4, 1, 1, 1, 30, 0, 1}, /* QVA */
    [889] = {{1,1,-2,0,0,0,0,0}, 0, 0, 1, 1, 30, 0, 1}, /* QN */
    [890] = {{2,1,-2,0,0,0,0,0}, 0, 0, 1, 1, 30, 0, 1}, /* QJ */
    [891] = {{2,1,-3,0,0,0,0,0}, 0, 0, 1, 1, 30, 0, 1}, /* QW */
    [892] = {{-1,1,-2,0,0,0,0,0}, 0, 0, 1, 1, 30, 0, 1}, /* QPa */
    [893] = {{0,0,-1,0,0,0,0,0}, 16, 1, 1, 1, 30, 0, 1}, /* QHz */
    [894] = {{2,1,-3,-1,0,0,0,0}, 0, 0, 1, 1, 30, 0, 1}, /* QV */
    [895] = {{0,0,1,1,0,0,0,0}, 0, 0, 1, 1, 30, 0, 1}, /* QC */
    [896] = {{2,1,-3,-2,0,0,0,0}, 0, 0, 1, 1, 30, 0, 1}, /* Q\xce\xa9 */
    [897] = {{-2,-1,4,2,0,0,0,0}, 0, 0, 1, 1, 30, 0, 1}, /* QF */
    [898] = {{2,1,-2,-2,0,0,0,0}, 0, 0, 1, 1, 30, 0, 1}, /* QH */
    [899] = {{-2,-1,3,2,0,0,0,0}, 0, 0, 1, 1, 30, 0, 1}, /* QS */
    [900] = {{2,1,-2,-1,0,0,0,0}, 0, 0, 1, 1, 30, 0, 1}, /* QWb */
    [901] = {{0,1,-2,-1,0,0,0,0}, 0, 0, 1, 1, 30, 0, 1}, /* QT */
    [902] = {{0,0,0,0,0,0,1,0}, 56, 1, 1, 1, 30, 0, 1}, /* Qlm */
    [903] = {{-2,0,0,0,0,0,1,0}, 42, 1, 1, 1, 30, 0, 1}, /* Qlx */
    [904] = {{0,0,-1,0,0,0,0,0}, 17, 1, 1, 1, 30, 0, 1}, /* QBq */
    [905] = {{2,0,-2,0,0,0,0,0}, 1, 1, 1, 1, 30, 0, 1}, /* QGy */
    [906] = {{2,0,-2,0,0,0,0,0}, 23, 1, 1, 1, 30, 0, 1}, /* QSv */
    [907] = {{0,0,-1,0,0,1,0,0}, 0, 0, 1, 1, 30, 0, 1}, /* Qkat */
    [908] = {{3,0,0,0,0,0,0,0}, 0, 0, 1, 1, 27, 0, 1}, /* QL */
    [909] = {{3,0,0,0,0,0,0,0}, 0, 0, 1, 1, 27, 0, 1}, /* Ql */
    [910] = {{2,1,-2,0,0,0,0,0}, 0, 0, 1602176634, 1, 2, 0, 1}, /* QeV */
    [911] = {{0,1,0,0,0,0,0,0}, 0, 0, 166053906660000015, 1, -44, 0, 1}, /* QDa */
    [912] = {{0,1,0,0,0,0,0,0}, 0, 0, 1, 1, 33, 0, 1}, /* Qt */
    [913] = {{0,0,0,0,0,0,0,1}, 0, 0, 125, 1, 27, 0, 1}, /* Qb */
    [914] = {{0,0,0,0,0,0,0,1}, 0, 0, 1, 1, 30, 0, 1}, /* QB */
    [915] = {{0,0,-1,0,0,0,0,1}, 0, 0, 125, 1, 27, 0, 1}, /* Qbps */
    [916] = {{0,0,-1,0,0,0,0,1}, 0, 0, 1, 1, 30, 0, 1}, /* QBps */
    [917] = {{1,0,0,0,0,0,0,0}, 0, 0, 30856775814914, 1, 33, 0, 1}, /* Qpc */
    [918] = {{0,0,1,0,0,0,0,0}, 0, 0, 12096, 1, 32, 0, 1}, /* Qfortnight */
    [919] = {{0,0,1,0,0,0,0,0}, 0, 0, 31556952, 1, 32, 0, 1}, /* Qcentury */
    [920] = {{1,0,0,0,0,0,0,0}, 0, 0, 1, 1, 27, 0, 1}, /* Rm */
    [921] = {{0,1,0,0,0,0,0,0}, 0, 0, 1, 1, 24, 0, 1}, /* Rg */
    [922] = {{0,0,1,0,0,0,0,0}, 0, 0, 1, 1, 27, 0, 1}, /* Rs */
    [923] = {{0,0,0,1,0,0,0,0}, 0, 0, 1, 1, 27, 0, 1}, /* RA */
    [924] = {{0,0,0,0,1,0,0,0}, 0, 0, 1, 1, 27, 0, 1}, /* RK */
    [925] = {{0,0,0,0,0,1,0,0}, 0, 0, 1, 1, 27, 0, 1}, /* Rmol */
    [926] = {{0,0,0,0,0,0,1,0}, 57, 1, 1, 1, 27, 0, 1}, /* Rcd */
    [927] = {{0,1,-2,0,0,0,0,0}, 16, -1, 1, 1, 1, 0, 1}, /* RJy */
    [928] = {{2,1,-3,0,0,0,0,0}, 79, 1, 1, 1, 27, 0, 1}, /* Rvar */
    [929] = {{2,1,-3,0,0,0,0,0}, 4, 1, 1, 1, 27, 0, 1}, /* RVA */
    [930] = {{1,1,-2,0,0,0,0,0}, 0, 0, 1, 1, 27, 0, 1}, /* RN */
    [931] = {{2,1,-2,0,0,0,0,0}, 0, 0, 1, 1, 27, 0, 1}, /* RJ */
    [932] = {{2,1,-3,0,0,0,0,0}, 0, 0, 1, 1, 27, 0, 1}, /* RW */
    [933] = {{-1,1,-2,0,0,0,0,0}, 0, 0, 1, 1, 27, 0, 1}, /* RPa */
    [934] = {{0,0,-1,0,0,0,0,0}, 16, 1, 1, 1, 27, 0, 1}, /* RHz */
    [935] = {{2,1,-3,-1,0,0,0,0}, 0, 0, 1, 1, 27, 0, 1}, /* RV */
    [936] = {{0,0,1,1,0,0,0,0}, 0, 0, 1, 1, 27, 0, 1}, /* RC */
    [937] = {{2,1,-3,-2,0,0,0,0}, 0, 0, 1, 1, 27, 0, 1}, /* R\xce\xa9 */
    [938] = {{-2,-1,4,2,0,0,0,0}, 0, 0, 1, 1, 27, 0, 1}, /* RF */
    [939] = {{2,1,-2,-2,0,0,0,0}, 0, 0, 1, 1, 27, 0, 1}, /* RH */
    [940] = {{-2,-1,3,2,0,0,0,0}, 0, 0, 1, 1, 27, 0, 1}, /* RS */
    [941] = {{2,1,-2,-1,0,0,0,0}, 0, 0, 1, 1, 27, 0, 1}, /* RWb */
    [942] = {{0,1,-2,-1,0,0,0,0}, 0, 0, 1, 1, 27, 0, 1}, /* RT */
    [943] = {{0,0,0,0,0,0,1,0}, 56, 1, 1, 1, 27, 0, 1}, /* Rlm */
    [944] = {{-2,0,0,0,0,0,1,0}, 42, 1, 1, 1, 27, 0, 1}, /* Rlx */
    [945] = {{0,0,-1,0,0,0,0,0}, 17, 1, 1, 1, 27, 0, 1}, /* RBq */
    [946] = {{2,0,-2,0,0,0,0,0}, 1, 1, 1, 1, 27, 0, 1}, /* RGy */
    [947] = {{2,0,-2,0,0,0,0,0}, 23, 1, 1, 1, 27, 0, 1}, /* RSv */
    [948] = {{0,0,-1,0,0,1,0,0}, 0, 0, 1, 1, 27, 0, 1}, /* Rkat */
    [949] = {{3,0,0,0,0,0,0,0}, 0, 0, 1, 1, 24, 0, 1}, /* RL */
    [950] = {{3,0,0,0,0,0,0,0}, 0, 0, 1, 1, 24, 0, 1}, /* Rl */
    [951] = {{2,1,-2,0,0,0,0,0}, 0, 0, 801088317, 5, 0, 0, 1}, /* ReV */
    [952] = {{0,1,0,0,0,0,0,0}, 0, 0, 166053906660000015, 1, -44, 0, 1}, /* RDa */
    [953] = {{0,1,0,0,0,0,0,0}, 0, 0, 1, 1, 30, 0, 1}, /* Rt */
    [954] = {{0,0,0,0,0,0,0,1}, 0, 0, 125, 1, 24, 0, 1}, /* Rb */
    [955] = {{0,0,0,0,0,0,0,1}, 0, 0, 1, 1, 27, 0, 1}, /* RB */
    [956] = {{0,0,-1,0,0,0,0,1}, 0, 0, 125, 1, 24, 0, 1}, /* Rbps */
    [957] = {{0,0,-1,0,0,0,0,1}, 0, 0, 1, 1, 27, 0, 1}, /* RBps */
    [958] = {{1,0,0,0,0,0,0,0}, 0, 0, 30856775814914, 1, 30, 0, 1}, /* Rpc */
    [959] = {{0,0,1,0,0,0,0,0}, 0, 0, 12096, 1, 29, 0, 1}, /* Rfortnight */
    [960] = {{0,0,1,0,0,0,0,0}, 0, 0, 31556952, 1, 29, 0, 1}, /* Rcentury */
    [961] = {{1,0,0,0,0,0,0,0}, 0, 0, 1, 1, 24, 0, 1}, /* Ym */
    [962] = {{0,1,0,0,0,0,0,0}, 0, 0, 1, 1, 21, 0, 1}, /* Yg */
    [963] = {{0,0,1,0,0,0,0,0}, 0, 0, 1, 1, 24, 0, 1}, /* Ys */
    [964] = {{0,0,0,1,0,0,0,0}, 0, 0, 1, 1, 24, 0, 1}, /* YA */
    [965] = {{0,0,0,0,1,0,0,0}, 0, 0, 1, 1, 24, 0, 1}, /* YK */
    [966] = {{0,0,0,0,0,1,0,0}, 0, 0, 1, 1, 24, 0, 1}, /* Ymol */
    [967] = {{0,0,0,0,0,0,1,0}, 57, 1, 1, 1, 24, 0, 1}, /* Ycd */
    [968] = {{0,1,-2,0,0,0,0,0}, 16, -1, 1, 1, -2, 0, 1}, /* YJy */
    [969] = {{2,1,-3,0,0,0,0,0}, 79, 1, 1, 1, 24, 0, 1}, /* Yvar */
    [970] = {{2,1,-3,0,0,0,0,0}, 4, 1, 1, 1, 24, 0, 1}, /* YVA */
    [971] = {{1,1,-2,0,0,0,0,0}, 0, 0, 1, 1, 24, 0, 1}, /* YN */
    [972] = {{2,1,-2,0,0,0,0,0}, 0, 0, 1, 1, 24, 0, 1}, /* YJ */
    [973] = {{2,1,-3,0,0,0,0,0}, 0, 0, 1, 1, 24, 0, 1}, /* YW */
    [974] = {{-1,1,-2,0,0,0,0,0}, 0, 0, 1, 1, 24, 0, 1}, /* YPa */
    [975] = {{0,0,-1,0,0,0,0,0}, 16, 1, 1, 1, 24, 0, 1}, /* YHz */
    [976] = {{2,1,-3,-1,0,0,0,0}, 0, 0, 1, 1, 24, 0, 1}, /* YV */
    [977] = {{0,0,1,1,0,0,0,0}, 0, 0, 1, 1, 24, 0, 1}, /* YC */
    [978] = {{2,1,-3,-2,0,0,0,0}, 0, 0, 1, 1, 24, 0, 1}, /* Y\xce\xa9 */
    [979] = {{-2,-1,4,2,0,0,0,0}, 0, 0, 1, 1, 24, 0, 1}, /* YF */
    [980] = {{2,1,-2,-2,0,0,0,0}, 0, 0, 1, 1, 24, 0, 1}, /* YH */
    [981] = {{-2,-1,3,2,0,0,0,0}, 0, 0, 1, 1, 24, 0, 1}, /* YS */
    [982] = {{2,1,-2,-1,0,0,0,0}, 0, 0, 1, 1, 24, 0, 1}, /* YWb */
    [983] = {{0,1,-2,-1,0,0,0,0}, 0, 0, 1, 1, 24, 0, 1}, /* YT */
    [984] = {{0,0,0,0,0,0,1,0}, 56, 1, 1, 1, 24, 0, 1}, /* Ylm */
    [985] = {{-2,0,0,0,0,0,1,0}, 42, 1, 1, 1, 24, 0, 1}, /* Ylx */
    [986] = {{0,0,-1,0,0,0,0,0}, 17, 1, 1, 1, 24, 0, 1}, /* YBq */
    [987] = {{2,0,-2,0,0,0,0,0}, 1, 1, 1, 1, 24, 0, 1}, /* YGy */
    [988] = {{2,0,-2,0,0,0,0,0}, 23, 1, 1, 1, 24, 0, 1}, /* YSv */
    [989] = {{0,0,-1,0,0,1,0,0}, 0, 0, 1, 1, 24, 0, 1}, /* Ykat */
    [990] = {{3,0,0,0,0,0,0,0}, 0, 0, 1, 1, 21, 0, 1}, /* YL */
    [991] = {{3,0,0,0,0,0,0,0}, 0, 0, 1, 1, 21, 0, 1}, /* Yl */
    [992] = {{2,1,-2,0,0,0,0,0}, 0, 0, 801088317, 5, -3, 0, 1}, /* YeV */
    [993] = {{0,1,0,0,0,0,0,0}, 0, 0, 166053906660000015, 1, -44, 0, 1}, /* YDa */
    [994] = {{0,1,0,0,0,0,0,0}, 0, 0, 1, 1, 27, 0, 1}, /* Yt */
    [995] = {{0,0,0,0,0,0,0,1}, 0, 0, 125, 1, 21, 0, 1}, /* Yb */
    [996] = {{0,0,0,0,0,0,0,1}, 0, 0, 1, 1, 24, 0, 1}, /* YB */
    [997] = {{0,0,-1,0,0,0,0,1}, 0, 0, 125, 1, 21, 0, 1}, /* Ybps */
    [998] = {{0,0,-1,0,0,0,0,1}, 0, 0, 1, 1, 24, 0, 1}, /* YBps */
    [999] = {{1,0,0,0,0,0,0,0}, 0, 0, 30856775814914, 1, 27, 0, 1}, /* Ypc */
    [1000] = {{0,0,1,0,0,0,0,0}, 0, 0, 12096, 1, 26, 0, 1}, /* Yfortnight */
    [1001] = {{0,0,1,0,0,0,0,0}, 0, 0, 31556952, 1, 26, 0, 1}, /* Ycentury */
    [1002] = {{1,0,0,0,0,0,0,0}, 0, 0, 1, 1, 21, 0, 1}, /* Zm */
    [1003] = {{0,1,0,0,0,0,0,0}, 0, 0, 1, 1, 18, 0, 1}, /* Zg */
    [1004] = {{0,0,1,0,0,0,0,0}, 0, 0, 1, 1, 21, 0, 1}, /* Zs */
    [1005] = {{0,0,0,1,0,0,0,0}, 0, 0, 1, 1, 21, 0, 1}, /* ZA */
    [1006] = {{0,0,0,0,1,0,0,0}, 0, 0, 1, 1, 21, 0, 1}, /* ZK */
    [1007] = {{0,0,0,0,0,1,0,0}, 0, 0, 1, 1, 21, 0, 1}, /* Zmol */
    [1008] = {{0,0,0,0,0,0,1,0}, 57, 1, 1, 1, 21, 0, 1}, /* Zcd */
    [1009] = {{0,1,-2,0,0,0,0,0}, 16, -1, 1, 1, -5, 0, 1}, /* ZJy */
    [1010] = {{2,1,-3,0,0,0,0,0}, 79, 1, 1, 1, 21, 0, 1}, /* Zvar */
    [1011] = {{2,1,-3,0,0,0,0,0}, 4, 1, 1, 1, 21, 0, 1}, /* ZVA */
    [1012] = {{1,1,-2,0,0,0,0,0}, 0, 0, 1, 1, 21, 0, 1}, /* ZN */
    [1013] = {{2,1,-2,0,0,0,0,0}, 0, 0, 1, 1, 21, 0, 1}, /* ZJ */
    [1014] = {{2,1,-3,0,0,0,0,0}, 0, 0, 1, 1, 21, 0, 1}, /* ZW */
    [1015] = {{-1,1,-2,0,0,0,0,0}, 0, 0, 1, 1, 21, 0, 1}, /* ZPa */
    [1016] = {{0,0,-1,0,0,0,0,0}, 16, 1, 1, 1, 21, 0, 1}, /* ZHz */
    [1017] = {{2,1,-3,-1,0,0,0,0}, 0, 0, 1, 1, 21, 0, 1}, /* ZV */
    [1018] = {{0,0,1,1,0,0,0,0}, 0, 0, 1, 1, 21, 0, 1}, /* ZC */
    [1019] = {{2,1,-3,-2,0,0,0,0}, 0, 0, 1, 1, 21, 0, 1}, /* Z\xce\xa9 */
    [1020] = {{-2,-1,4,2,0,0,0,0}, 0, 0, 1, 1, 21, 0, 1}, /* ZF */
    [1021] = {{2,1,-2,-2,0,0,0,0}, 0, 0, 1, 1, 21, 0, 1}, /* ZH */
    [1022] = {{-2,-1,3,2,0,0,0,0}, 0, 0, 1, 1, 21, 0, 1}, /* ZS */
    [1023] = {{2,1,-2,-1,0,0,0,0}, 0, 0, 1, 1, 21, 0, 1}, /* ZWb */
    [1024] = {{0,1,-2,-1,0,0,0,0}, 0, 0, 1, 1, 21, 0, 1}, /* ZT */
    [1025] = {{0,0,0,0,0,0,1,0}, 56, 1, 1, 1, 21, 0, 1}, /* Zlm */
    [1026] = {{-2,0,0,0,0,0,1,0}, 42, 1, 1, 1, 21, 0, 1}, /* Zlx */
    [1027] = {{0,0,-1,0,0,0,0,0}, 17, 1, 1, 1, 21, 0, 1}, /* ZBq */
    [1028] = {{2,0,-2,0,0,0,0,0}, 1, 1, 1, 1, 21, 0, 1}, /* ZGy */
    [1029] = {{2,0,-2,0,0,0,0,0}, 23, 1, 1, 1, 21, 0, 1}, /* ZSv */
    [1030] = {{0,0,-1,0,0,1,0,0}, 0, 0, 1, 1, 21, 0, 1}, /* Zkat */
    [1031] = {{3,0,0,0,0,0,0,0}, 0, 0, 1, 1, 18, 0, 1}, /* ZL */
    [1032] = {{3,0,0,0,0,0,0,0}, 0, 0, 1, 1, 18, 0, 1}, /* Zl */
    [1033] = {{2,1,-2,0,0,0,0,0}, 0, 0, 801088317, 5, -6, 0, 1}, /* ZeV */
    [1034] = {{0,1,0,0,0,0,0,0}, 0, 0, 166053906660000015, 1, -44, 0, 1}, /* ZDa */
    [1035] = {{0,1,0,0,0,0,0,0}, 0, 0, 1, 1, 24, 0, 1}, /* Zt */
    [1036] = {{0,0,0,0,0,0,0,1}, 0, 0, 125, 1, 18, 0, 1}, /* Zb */
    [1037] = {{0,0,0,0,0,0,0,1}, 0, 0, 1, 1, 21, 0, 1}, /* ZB */
    [1038] = {{0,0,-1,0,0,0,0,1}, 0, 0, 125, 1, 18, 0, 1}, /* Zbps */
    [1039] = {{0,0,-1,0,0,0,0,1}, 0, 0, 1, 1, 21, 0, 1}, /* ZBps */
    [1040] = {{1,0,0,0,0,0,0,0}, 0, 0, 30856775814914, 1, 24, 0, 1}, /* Zpc */
    [1041] = {{0,0,1,0,0,0,0,0}, 0, 0, 12096, 1, 23, 0, 1}, /* Zfortnight */
    [1042] = {{0,0,1,0,0,0,0,0}, 0, 0, 31556952, 1, 23, 0, 1}, /* Zcentury */
    [1043] = {{1,0,0,0,0,0,0,0}, 0, 0, 1, 1, 18, 0, 1}, /* Em */
    [1044] = {{0,1,0,0,0,0,0,0}, 0, 0, 1, 1, 15, 0, 1}, /* Eg */
    [1045] = {{0,0,1,0,0,0,0,0}, 0, 0, 1, 1, 18, 0, 1}, /* Es */
    [1046] = {{0,0,0,1,0,0,0,0}, 0, 0, 1, 1, 18, 0, 1}, /* EA */
    [1047] = {{0,0,0,0,1,0,0,0}, 0, 0, 1, 1, 18, 0, 1}, /* EK */
    [1048] = {{0,0,0,0,0,1,0,0}, 0, 0, 1, 1, 18, 0, 1}, /* Emol */
    [1049] = {{0,0,0,0,0,0,1,0}, 57, 1, 1, 1, 18, 0, 1}, /* Ecd */
    [1050] = {{0,1,-2,0,0,0,0,0}, 16, -1, 1, 1, -8, 0, 1}, /* EJy */
    [1051] = {{2,1,-3,0,0,0,0,0}, 79, 1, 1, 1, 18, 0, 1}, /* Evar */
    [1052] = {{2,1,-3,0,0,0,0,0}, 4, 1, 1, 1, 18, 0, 1}, /* EVA */
    [1053] = {{1,1,-2,0,0,0,0,0}, 0, 0, 1, 1, 18, 0, 1}, /* EN */
    [1054] = {{2,1,-2,0,0,0,0,0}, 0, 0, 1, 1, 18, 0, 1}, /* EJ */
    [1055] = {{2,1,-3,0,0,0,0,0}, 0, 0, 1, 1, 18, 0, 1}, /* EW */
    [1056] = {{-1,1,-2,0,0,0,0,0}, 0, 0, 1, 1, 18, 0, 1}, /* EPa */
    [1057] = {{0,0,-1,0,0,0,0,0}, 16, 1, 1, 1, 18, 0, 1}, /* EHz */
    [1058] = {{0,0,1,1,0,0,0,0}, 0, 0, 1, 1, 18, 0, 1}, /* EC */
    [1059] = {{2,1,-3,-2,0,0,0,0}, 0, 0, 1, 1, 18, 0, 1}, /* E\xce\xa9 */
    [1060] = {{2,1,-2,-2,0,0,0,0}, 0, 0, 1, 1, 18, 0, 1}, /* EH */
    [1061] = {{-2,-1,3,2,0,0,0,0}, 0, 0, 1, 1, 18, 0, 1}, /* ES */
    [1062] = {{2,1,-2,-1,0,0,0,0}, 0, 0, 1, 1, 18, 0, 1}, /* EWb */
    [1063] = {{0,1,-2,-1,0,0,0,0}, 0, 0, 1, 1, 18, 0, 1}, /* ET */
    [1064] = {{0,0,0,0,0,0,1,0}, 56, 1, 1, 1, 18, 0, 1}, /* Elm */
    [1065] = {{-2,0,0,0,0,0,1,0}, 42, 1, 1, 1, 18, 0, 1}, /* Elx */
    [1066] = {{0,0,-1,0,0,0,0,0}, 17, 1, 1, 1, 18, 0, 1}, /* EBq */
    [1067] = {{2,0,-2,0,0,0,0,0}, 1, 1, 1, 1, 18, 0, 1}, /* EGy */
    [1068] = {{2,0,-2,0,0,0,0,0}, 23, 1, 1, 1, 18, 0, 1}, /* ESv */
    [1069] = {{0,0,-1,0,0,1,0,0}, 0, 0, 1, 1, 18, 0, 1}, /* Ekat */
    [1070] = {{3,0,0,0,0,0,0,0}, 0, 0, 1, 1, 15, 0, 1}, /* EL */
    [1071] = {{3,0,0,0,0,0,0,0}, 0, 0, 1, 1, 15, 0, 1}, /* El */
    [1072] = {{2,1,-2,0,0,0,0,0}, 0, 0, 801088317, 5, -9, 0, 1}, /* EeV */
    [1073] = {{0,1,0,0,0,0,0,0}, 0, 0, 166053906660000015, 1, -44, 0, 1}, /* EDa */
    [1074] = {{0,1,0,0,0,0,0,0}, 0, 0, 1, 1, 21, 0, 1}, /* Et */
    [1075] = {{0,0,0,0,0,0,0,1}, 0, 0, 125, 1, 15, 0, 1}, /* Eb */
    [1076] = {{0,0,0,0,0,0,0,1}, 0, 0, 1, 1, 18, 0, 1}, /* EB */
    [1077] = {{0,0,-1,0,0,0,0,1}, 0, 0, 125, 1, 15, 0, 1}, /* Ebps */
    [1078] = {{0,0,-1,0,0,0,0,1}, 0, 0, 1, 1, 18, 0, 1}, /* EBps */
    [1079] = {{1,0,0,0,0,0,0,0}, 0, 0, 30856775814914, 1, 21, 0, 1}, /* Epc */
    [1080] = {{0,0,1,0,0,0,0,0}, 0, 0, 12096, 1, 20, 0, 1}, /* Efortnight */
    [1081] = {{0,0,1,0,0,0,0,0}, 0, 0, 31556952, 1, 20, 0, 1}, /* Ecentury */
    [1082] = {{1,0,0,0,0,0,0,0}, 0, 0, 1, 1, 15, 0, 1}, /* Pm */
    [1083] = {{0,1,0,0,0,0,0,0}, 0, 0, 1, 1, 12, 0, 1}, /* Pg */
    [1084] = {{0,0,1,0,0,0,0,0}, 0, 0, 1, 1, 15, 0, 1}, /* Ps */
    [1085] = {{0,0,0,1,0,0,0,0}, 0, 0, 1, 1, 15, 0, 1}, /* PA */
    [1086] = {{0,0,0,0,1,0,0,0}, 0, 0, 1, 1, 15, 0, 1}, /* PK */
    [1087] = {{0,0,0,0,0,1,0,0}, 0, 0, 1, 1, 15, 0, 1}, /* Pmol */
    [1088] = {{0,0,0,0,0,0,1,0}, 57, 1, 1, 1, 15, 0, 1}, /* Pcd */
    [1089] = {{0,1,-2,0,0,0,0,0}, 16, -1, 1, 1, -11, 0, 1}, /* PJy */
    [1090] = {{2,1,-3,0,0,0,0,0}, 79, 1, 1, 1, 15, 0, 1}, /* Pvar */
    [1091] = {{2,1,-3,0,0,0,0,0}, 4, 1, 1, 1, 15, 0, 1}, /* PVA */
    [1092] = {{1,1,-2,0,0,0,0,0}, 0, 0, 1, 1, 15, 0, 1}, /* PN */
    [1093] = {{2,1,-2,0,0,0,0,0}, 0, 0, 1, 1, 15, 0, 1}, /* PJ */
    [1094] = {{2,1,-3,0,0,0,0,0}, 0, 0, 1, 1, 15, 0, 1}, /* PW */
    [1095] = {{-1,1,-2,0,0,0,0,0}, 0, 0, 1, 1, 15, 0, 1}, /* PPa */
    [1096] = {{0,0,-1,0,0,0,0,0}, 16, 1, 1, 1, 15, 0, 1}, /* PHz */
    [1097] = {{2,1,-3,-1,0,0,0,0}, 0, 0, 1, 1, 15, 0, 1}, /* PV */
    [1098] = {{0,0,1,1,0,0,0,0}, 0, 0, 1, 1, 15, 0, 1}, /* PC */
    [1099] = {{2,1,-3,-2,0,0,0,0}, 0, 0, 1, 1, 15, 0, 1}, /* P\xce\xa9 */
    [1100] = {{-2,-1,4,2,0,0,0,0}, 0, 0, 1, 1, 15, 0, 1}, /* PF */
    [1101] = {{2,1,-2,-2,0,0,0,0}, 0, 0, 1, 1, 15, 0, 1}, /* PH */
    [1102] = {{2,1,-2,-1,0,0,0,0}, 0, 0, 1, 1, 15, 0, 1}, /* PWb */
    [1103] = {{0,1,-2,-1,0,0,0,0}, 0, 0, 1, 1, 15, 0, 1}, /* PT */
    [1104] = {{0,0,0,0,0,0,1,0}, 56, 1, 1, 1, 15, 0, 1}, /* Plm */
    [1105] = {{-2,0,0,0,0,0,1,0}, 42, 1, 1, 1, 15, 0, 1}, /* Plx */
    [1106] = {{0,0,-1,0,0,0,0,0}, 17, 1, 1, 1, 15, 0, 1}, /* PBq */
    [1107] = {{2,0,-2,0,0,0,0,0}, 1, 1, 1, 1, 15, 0, 1}, /* PGy */
    [1108] = {{2,0,-2,0,0,0,0,0}, 23, 1, 1, 1, 15, 0, 1}, /* PSv */
    [1109] = {{0,0,-1,0,0,1,0,0}, 0, 0, 1, 1, 15, 0, 1}, /* Pkat */
    [1110] = {{3,0,0,0,0,0,0,0}, 0, 0, 1, 1, 12, 0, 1}, /* PL */
    [1111] = {{3,0,0,0,0,0,0,0}, 0, 0, 1, 1, 12, 0, 1}, /* Pl */
    [1112] = {{2,1,-2,0,0,0,0,0}, 0, 0, 801088317, 5, -12, 0, 1}, /* PeV */
    [1113] = {{0,1,0,0,0,0,0,0}, 0, 0, 166053906660000015, 1, -44, 0, 1}, /* PDa */
    [1114] = {{0,1,0,0,0,0,0,0}, 0, 0, 1, 1, 18, 0, 1}, /* Pt */
    [1115] = {{0,0,0,0,0,0,0,1}, 0, 0, 125, 1, 12, 0, 1}, /* Pb */
    [1116] = {{0,0,-1,0,0,0,0,1}, 0, 0, 125, 1, 12, 0, 1}, /* Pbps */
    [1117] = {{0,0,-1,0,0,0,0,1}, 0, 0, 1, 1, 15, 0, 1}, /* PBps */
    [1118] = {{1,0,0,0,0,0,0,0}, 0, 0, 30856775814914, 1, 18, 0, 1}, /* Ppc */
    [1119] = {{0,0,1,0,0,0,0,0}, 0, 0, 12096, 1, 17, 0, 1}, /* Pfortnight */
    [1120] = {{0,0,1,0,0,0,0,0}, 0, 0, 31556952, 1, 17, 0, 1}, /* Pcentury */
    [1121] = {{1,0,0,0,0,0,0,0}, 0, 0, 1, 1, 12, 0, 1}, /* Tm */
    [1122] = {{0,1,0,0,0,0,0,0}, 0, 0, 1, 1, 9, 0, 1}, /* Tg */
    [1123] = {{0,0,1,0,0,0,0,0}, 0, 0, 1, 1, 12, 0, 1}, /* Ts */
    [1124] = {{0,0,0,1,0,0,0,0}, 0, 0, 1, 1, 12, 0, 1}, /* TA */
    [1125] = {{0,0,0,0,1,0,0,0}, 0, 0, 1, 1, 12, 0, 1}, /* TK */
    [1126] = {{0,0,0,0,0,1,0,0}, 0, 0, 1, 1, 12, 0, 1}, /* Tmol */
    [1127] = {{0,0,0,0,0,0,1,0}, 57, 1, 1, 1, 12, 0, 1}, /* Tcd */
    [1128] = {{0,1,-2,0,0,0,0,0}, 16, -1, 1, 1, -14, 0, 1}, /* TJy */
    [1129] = {{2,1,-3,0,0,0,0,0}, 79, 1, 1, 1, 12, 0, 1}, /* Tvar */
    [1130] = {{2,1,-3,0,0,0,0,0}, 4, 1, 1, 1, 12, 0, 1}, /* TVA */
    [1131] = {{1,1,-2,0,0,0,0,0}, 0, 0, 1, 1, 12, 0, 1}, /* TN */
    [1132] = {{2,1,-2,0,0,0,0,0}, 0, 0, 1, 1, 12, 0, 1}, /* TJ */
    [1133] = {{2,1,-3,0,0,0,0,0}, 0, 0, 1, 1, 12, 0, 1}, /* TW */
    [1134] = {{-1,1,-2,0,0,0,0,0}, 0, 0, 1, 1, 12, 0, 1}, /* TPa */
    [1135] = {{2,1,-3,-1,0,0,0,0}, 0, 0, 1, 1, 12, 0, 1}, /* TV */
    [1136] = {{0,0,1,1,0,0,0,0}, 0, 0, 1, 1, 12, 0, 1}, /* TC */
    [1137] = {{2,1,-3,-2,0,0,0,0}, 0, 0, 1, 1, 12, 0, 1}, /* T\xce\xa9 */
    [1138] = {{-2,-1,4,2,0,0,0,0}, 0, 0, 1, 1, 12, 0, 1}, /* TF */
    [1139] = {{2,1,-2,-2,0,0,0,0}, 0, 0, 1, 1, 12, 0, 1}, /* TH */
    [1140] = {{-2,-1,3,2,0,0,0,0}, 0, 0, 1, 1, 12, 0, 1}, /* TS */
    [1141] = {{2,1,-2,-1,0,0,0,0}, 0, 0, 1, 1, 12, 0, 1}, /* TWb */
    [1142] = {{0,1,-2,-1,0,0,0,0}, 0, 0, 1, 1, 12, 0, 1}, /* TT */
    [1143] = {{0,0,0,0,0,0,1,0}, 56, 1, 1, 1, 12, 0, 1}, /* Tlm */
    [1144] = {{-2,0,0,0,0,0,1,0}, 42, 1, 1, 1, 12, 0, 1}, /* Tlx */
    [1145] = {{0,0,-1,0,0,0,0,0}, 17, 1, 1, 1, 12, 0, 1}, /* TBq */
    [1146] = {{2,0,-2,0,0,0,0,0}, 1, 1, 1, 1, 12, 0, 1}, /* TGy */
    [1147] = {{2,0,-2,0,0,0,0,0}, 23, 1, 1, 1, 12, 0, 1}, /* TSv */
    [1148] = {{0,0,-1,0,0,1,0,0}, 0, 0, 1, 1, 12, 0, 1}, /* Tkat */
    [1149] = {{3,0,0,0,0,0,0,0}, 0, 0, 1, 1, 9, 0, 1}, /* TL */
    [1150] = {{3,0,0,0,0,0,0,0}, 0, 0, 1, 1, 9, 0, 1}, /* Tl */
    [1151] = {{2,1,-2,0,0,0,0,0}, 0, 0, 801088317, 5, -15, 0, 1}, /* TeV */
    [1152] = {{0,1,0,0,0,0,0,0}, 0, 0, 166053906660000015, 1, -44, 0, 1}, /* TDa */
    [1153] = {{0,1,0,0,0,0,0,0}, 0, 0, 1, 1, 15, 0, 1}, /* Tt */
    [1154] = {{0,0,0,0,0,0,0,1}, 0, 0, 125, 1, 9, 0, 1}, /* Tb */
    [1155] = {{0,0,-1,0,0,0,0,1}, 0, 0, 125, 1, 9, 0, 1}, /* Tbps */
    [1156] = {{0,0,-1,0,0,0,0,1}, 0, 0, 1, 1, 12, 0, 1}, /* TBps */
    [1157] = {{1,0,0,0,0,0,0,0}, 0, 0, 30856775814914, 1, 15, 0, 1}, /* Tpc */
    [1158] = {{0,0,1,0,0,0,0,0}, 0, 0, 12096, 1, 14, 0, 1}, /* Tfortnight */
    [1159] = {{0,0,1,0,0,0,0,0}, 0, 0, 31556952, 1, 14, 0, 1}, /* Tcentury */
    [1160] = {{1,0,0,0,0,0,0,0}, 0, 0, 1, 1, 9, 0, 1}, /* Gm */
    [1161] = {{0,1,0,0,0,0,0,0}, 0, 0, 1, 1, 6, 0, 1}, /* Gg */
    [1162] = {{0,0,1,0,0,0,0,0}, 0, 0, 1, 1, 9, 0, 1}, /* Gs */
    [1163] = {{0,0,0,1,0,0,0,0}, 0, 0, 1, 1, 9, 0, 1}, /* GA */
    [1164] = {{0,0,0,0,1,0,0,0}, 0, 0, 1, 1, 9, 0, 1}, /* GK */
    [1165] = {{0,0,0,0,0,1,0,0}, 0, 0, 1, 1, 9, 0, 1}, /* Gmol */
    [1166] = {{0,0,0,0,0,0,1,0}, 57, 1, 1, 1, 9, 0, 1}, /* Gcd */
    [1167] = {{0,1,-2,0,0,0,0,0}, 16, -1, 1, 1, -17, 0, 1}, /* GJy */
    [1168] = {{2,1,-3,0,0,0,0,0}, 79, 1, 1, 1, 9, 0, 1}, /* Gvar */
    [1169] = {{2,1,-3,0,0,0,0,0}, 4, 1, 1, 1, 9, 0, 1}, /* GVA */
    [1170] = {{1,1,-2,0,0,0,0,0}, 0, 0, 1, 1, 9, 0, 1}, /* GN */
    [1171] = {{2,1,-3,-1,0,0,0,0}, 0, 0, 1, 1, 9, 0, 1}, /* GV */
    [1172] = {{0,0,1,1,0,0,0,0}, 0, 0, 1, 1, 9, 0, 1}, /* GC */
    [1173] = {{2,1,-3,-2,0,0,0,0}, 0, 0, 1, 1, 9, 0, 1}, /* G\xce\xa9 */
    [1174] = {{-2,-1,4,2,0,0,0,0}, 0, 0, 1, 1, 9, 0, 1}, /* GF */
    [1175] = {{2,1,-2,-2,0,0,0,0}, 0, 0, 1, 1, 9, 0, 1}, /* GH */
    [1176] = {{-2,-1,3,2,0,0,0,0}, 0, 0, 1, 1, 9, 0, 1}, /* GS */
    [1177] = {{2,1,-2,-1,0,0,0,0}, 0, 0, 1, 1, 9, 0, 1}, /* GWb */
    [1178] = {{0,1,-2,-1,0,0,0,0}, 0, 0, 1, 1, 9, 0, 1}, /* GT */
    [1179] = {{0,0,0,0,0,0,1,0}, 56, 1, 1, 1, 9, 0, 1}, /* Glm */
    [1180] = {{-2,0,0,0,0,0,1,0}, 42, 1, 1, 1, 9, 0, 1}, /* Glx */
    [1181] = {{0,0,-1,0,0,0,0,0}, 17, 1, 1, 1, 9, 0, 1}, /* GBq */
    [1182] = {{2,0,-2,0,0,0,0,0}, 1, 1, 1, 1, 9, 0, 1}, /* GGy */
    [1183] = {{2,0,-2,0,0,0,0,0}, 23, 1, 1, 1, 9, 0, 1}, /* GSv */
    [1184] = {{0,0,-1,0,0,1,0,0}, 0, 0, 1, 1, 9, 0, 1}, /* Gkat */
    [1185] = {{3,0,0,0,0,0,0,0}, 0, 0, 1, 1, 6, 0, 1}, /* GL */
    [1186] = {{3,0,0,0,0,0,0,0}, 0, 0, 1, 1, 6, 0, 1}, /* Gl */
    [1187] = {{2,1,-2,0,0,0,0,0}, 0, 0, 801088317, 5, -18, 0, 1}, /* GeV */
    [1188] = {{0,1,0,0,0,0,0,0}, 0, 0, 166053906660000015, 1, -44, 0, 1}, /* GDa */
    [1189] = {{0,1,0,0,0,0,0,0}, 0, 0, 1, 1, 12, 0, 1}, /* Gt */
    [1190] = {{0,0,-1,0,0,0,0,1}, 0, 0, 125, 1, 6, 0, 1}, /* Gbps */
    [1191] = {{0,0,-1,0,0,0,0,1}, 0, 0, 1, 1, 9, 0, 1}, /* GBps */
    [1192] = {{1,0,0,0,0,0,0,0}, 0, 0, 30856775814914, 1, 12, 0, 1}, /* Gpc */
    [1193] = {{0,0,1,0,0,0,0,0}, 0, 0, 12096, 1, 11, 0, 1}, /* Gfortnight */
    [1194] = {{0,0,1,0,0,0,0,0}, 0, 0, 31556952, 1, 11, 0, 1}, /* Gcentury */
    [1195] = {{1,0,0,0,0,0,0,0}, 0, 0, 1, 1, 6, 0, 1}, /* Mm */
    [1196] = {{0,1,0,0,0,0,0,0}, 0, 0, 1, 1, 3, 0, 1}, /* Mg */
    [1197] = {{0,0,1,0,0,0,0,0}, 0, 0, 1, 1, 6, 0, 1}, /* Ms */
    [1198] = {{0,0,0,1,0,0,0,0}, 0, 0, 1, 1, 6, 0, 1}, /* MA */
    [1199] = {{0,0,0,0,1,0,0,0}, 0, 0, 1, 1, 6, 0, 1}, /* MK */
    [1200] = {{0,0,0,0,0,1,0,0}, 0, 0, 1, 1, 6, 0, 1}, /* Mmol */
    [1201] = {{0,0,0,0,0,0,1,0}, 57, 1, 1, 1, 6, 0, 1}, /* Mcd */
    [1202] = {{0,1,-2,0,0,0,0,0}, 16, -1, 1, 1, -20, 0, 1}, /* MJy */
    [1203] = {{2,1,-3,0,0,0,0,0}, 79, 1, 1, 1, 6, 0, 1}, /* Mvar */
    [1204] = {{2,1,-3,0,0,0,0,0}, 4, 1, 1, 1, 6, 0, 1}, /* MVA */
    [1205] = {{1,1,-2,0,0,0,0,0}, 0, 0, 1, 1, 6, 0, 1}, /* MN */
    [1206] = {{0,0,1,1,0,0,0,0}, 0, 0, 1, 1, 6, 0, 1}, /* MC */
    [1207] = {{2,1,-3,-2,0,0,0,0}, 0, 0, 1, 1, 6, 0, 1}, /* M\xce\xa9 */
    [1208] = {{-2,-1,4,2,0,0,0,0}, 0, 0, 1, 1, 6, 0, 1}, /* MF */
    [1209] = {{2,1,-2,-2,0,0,0,0}, 0, 0, 1, 1, 6, 0, 1}, /* MH */
    [1210] = {{-2,-1,3,2,0,0,0,0}, 0, 0, 1, 1, 6, 0, 1}, /* MS */
    [1211] = {{2,1,-2,-1,0,0,0,0}, 0, 0, 1, 1, 6, 0, 1}, /* MWb */
    [1212] = {{0,1,-2,-1,0,0,0,0}, 0, 0, 1, 1, 6, 0, 1}, /* MT */
    [1213] = {{0,0,0,0,0,0,1,0}, 56, 1, 1, 1, 6, 0, 1}, /* Mlm */
    [1214] = {{-2,0,0,0,0,0,1,0}, 42, 1, 1, 1, 6, 0, 1}, /* Mlx */
    [1215] = {{0,0,-1,0,0,0,0,0}, 17, 1, 1, 1, 6, 0, 1}, /* MBq */
    [1216] = {{2,0,-2,0,0,0,0,0}, 1, 1, 1, 1, 6, 0, 1}, /* MGy */
    [1217] = {{2,0,-2,0,0,0,0,0}, 23, 1, 1, 1, 6, 0, 1}, /* MSv */
    [1218] = {{0,0,-1,0,0,1,0,0}, 0, 0, 1, 1, 6, 0, 1}, /* Mkat */
    [1219] = {{3,0,0,0,0,0,0,0}, 0, 0, 1, 1, 3, 0, 1}, /* ML */
    [1220] = {{3,0,0,0,0,0,0,0}, 0, 0, 1, 1, 3, 0, 1}, /* Ml */
    [1221] = {{2,1,-2,0,0,0,0,0}, 0, 0, 801088317, 5, -21, 0, 1}, /* MeV */
    [1222] = {{0,1,0,0,0,0,0,0}, 0, 0, 166053906660000015, 1, -44, 0, 1}, /* MDa */
    [1223] = {{0,1,0,0,0,0,0,0}, 0, 0, 1, 1, 9, 0, 1}, /* Mt */
    [1224] = {{0,0,0,0,0,0,0,1}, 0, 0, 125, 1, 3, 0, 1}, /* Mb */
    [1225] = {{0,0,-1,0,0,0,0,1}, 0, 0, 125, 1, 3, 0, 1}, /* Mbps */
    [1226] = {{0,0,-1,0,0,0,0,1}, 0, 0, 1, 1, 6, 0, 1}, /* MBps */
    [1227] = {{1,0,0,0,0,0,0,0}, 0, 0, 30856775814914, 1, 9, 0, 1}, /* Mpc */
    [1228] = {{0,0,1,0,0,0,0,0}, 0, 0, 12096, 1, 8, 0, 1}, /* Mfortnight */
    [1229] = {{0,0,1,0,0,0,0,0}, 0, 0, 31556952, 1, 8, 0, 1}, /* Mcentury */
    [1230] = {{0,0,1,0,0,0,0,0}, 0, 0, 1, 1, 3, 0, 1}, /* ks */
    [1231] = {{0,0,0,1,0,0,0,0}, 0, 0, 1, 1, 3, 0, 1}, /* kA */
    [1232] = {{0,0,0,0,1,0,0,0}, 0, 0, 1, 1, 3, 0, 1}, /* kK */
    [1233] = {{0,0,0,0,0,1,0,0}, 0, 0, 1, 1, 3, 0, 1}, /* kmol */
    [1234] = {{0,0,0,0,0,0,1,0}, 57, 1, 1, 1, 3, 0, 1}, /* kcd */
    [1235] = {{0,1,-2,0,0,0,0,0}, 16, -1, 1, 1, -23, 0, 1}, /* kJy */
    [1236] = {{2,1,-3,0,0,0,0,0}, 79, 1, 1, 1, 3, 0, 1}, /* kvar */
    [1237] = {{2,1,-3,0,0,0,0,0}, 4, 1, 1, 1, 3, 0, 1}, /* kVA */
    [1238] = {{1,1,-2,0,0,0,0,0}, 0, 0, 1, 1, 3, 0, 1}, /* kN */
    [1239] = {{0,0,1,1,0,0,0,0}, 0, 0, 1, 1, 3, 0, 1}, /* kC */
    [1240] = {{2,1,-3,-2,0,0,0,0}, 0, 0, 1, 1, 3, 0, 1}, /* k\xce\xa9 */
    [1241] = {{-2,-1,4,2,0,0,0,0}, 0, 0, 1, 1, 3, 0, 1}, /* kF */
    [1242] = {{2,1,-2,-2,0,0,0,0}, 0, 0, 1, 1, 3, 0, 1}, /* kH */
    [1243] = {{-2,-1,3,2,0,0,0,0}, 0, 0, 1, 1, 3, 0, 1}, /* kS */
    [1244] = {{2,1,-2,-1,0,0,0,0}, 0, 0, 1, 1, 3, 0, 1}, /* kWb */
    [1245] = {{0,1,-2,-1,0,0,0,0}, 0, 0, 1, 1, 3, 0, 1}, /* kT */
    [1246] = {{0,0,0,0,0,0,1,0}, 56, 1, 1, 1, 3, 0, 1}, /* klm */
    [1247] = {{-2,0,0,0,0,0,1,0}, 42, 1, 1, 1, 3, 0, 1}, /* klx */
    [1248] = {{0,0,-1,0,0,0,0,0}, 17, 1, 1, 1, 3, 0, 1}, /* kBq */
    [1249] = {{2,0,-2,0,0,0,0,0}, 1, 1, 1, 1, 3, 0, 1}, /* kGy */
    [1250] = {{2,0,-2,0,0,0,0,0}, 23, 1, 1, 1, 3, 0, 1}, /* kSv */
    [1251] = {{0,0,-1,0,0,1,0,0}, 0, 0, 1, 1, 3, 0, 1}, /* kkat */
    [1252] = {{3,0,0,0,0,0,0,0}, 0, 0, 1, 1, 0, 0, 1}, /* kL */
    [1253] = {{3,0,0,0,0,0,0,0}, 0, 0, 1, 1, 0, 0, 1}, /* kl */
    [1254] = {{2,1,-2,0,0,0,0,0}, 0, 0, 801088317, 5, -24, 0, 1}, /* keV */
    [1255] = {{0,1,0,0,0,0,0,0}, 0, 0, 166053906660000015, 1, -44, 0, 1}, /* kDa */
    [1256] = {{0,0,0,0,0,0,0,1}, 0, 0, 125, 1, 0, 0, 1}, /* kb */
    [1257] = {{0,0,0,0,0,0,0,1}, 0, 0, 1, 1, 3, 0, 1}, /* kB */
    [1258] = {{0,0,-1,0,0,0,0,1}, 0, 0, 125, 1, 0, 0, 1}, /* kbps */
    [1259] = {{0,0,-1,0,0,0,0,1}, 0, 0, 1, 1, 3, 0, 1}, /* kBps */
    [1260] = {{1,0,0,0,0,0,0,0}, 0, 0, 30856775814914, 1, 6, 0, 1}, /* kpc */
    [1261] = {{0,0,1,0,0,0,0,0}, 0, 0, 12096, 1, 5, 0, 1}, /* kfortnight */
    [1262] = {{0,0,1,0,0,0,0,0}, 0, 0, 31556952, 1, 5, 0, 1}, /* kcentury */
    [1263] = {{1,0,0,0,0,0,0,0}, 0, 0, 1, 1, 2, 0, 1}, /* hm */
    [1264] = {{0,1,0,0,0,0,0,0}, 0, 0, 1, 1, -1, 0, 1}, /* hg */
    [1265] = {{0,0,1,0,0,0,0,0}, 0, 0, 1, 1, 2, 0, 1}, /* hs */
    [1266] = {{0,0,0,1,0,0,0,0}, 0, 0, 1, 1, 2, 0, 1}, /* hA */
    [1267] = {{0,0,0,0,1,0,0,0}, 0, 0, 1, 1, 2, 0, 1}, /* hK */
    [1268] = {{0,0,0,0,0,1,0,0}, 0, 0, 1, 1, 2, 0, 1}, /* hmol */
    [1269] = {{0,0,0,0,0,0,1,0}, 57, 1, 1, 1, 2, 0, 1}, /* hcd */
    [1270] = {{0,1,-2,0,0,0,0,0}, 16, -1, 1, 1, -24, 0, 1}, /* hJy */
    [1271] = {{2,1,-3,0,0,0,0,0}, 79, 1, 1, 1, 2, 0, 1}, /* hvar */
    [1272] = {{2,1,-3,0,0,0,0,0}, 4, 1, 1, 1, 2, 0, 1}, /* hVA */
    [1273] = {{1,1,-2,0,0,0,0,0}, 0, 0, 1, 1, 2, 0, 1}, /* hN */
    [1274] = {{2,1,-2,0,0,0,0,0}, 0, 0, 1, 1, 2, 0, 1}, /* hJ */
    [1275] = {{2,1,-3,0,0,0,0,0}, 0, 0, 1, 1, 2, 0, 1}, /* hW */
    [1276] = {{-1,1,-2,0,0,0,0,0}, 0, 0, 1, 1, 2, 0, 1}, /* hPa */
    [1277] = {{0,0,-1,0,0,0,0,0}, 16, 1, 1, 1, 2, 0, 1}, /* hHz */
    [1278] = {{2,1,-3,-1,0,0,0,0}, 0, 0, 1, 1, 2, 0, 1}, /* hV */
    [1279] = {{0,0,1,1,0,0,0,0}, 0, 0, 1, 1, 2, 0, 1}, /* hC */
    [1280] = {{2,1,-3,-2,0,0,0,0}, 0, 0, 1, 1, 2, 0, 1}, /* h\xce\xa9 */
    [1281] = {{-2,-1,4,2,0,0,0,0}, 0, 0, 1, 1, 2, 0, 1}, /* hF */
    [1282] = {{2,1,-2,-2,0,0,0,0}, 0, 0, 1, 1, 2, 0, 1}, /* hH */
    [1283] = {{-2,-1,3,2,0,0,0,0}, 0, 0, 1, 1, 2, 0, 1}, /* hS */
    [1284] = {{2,1,-2,-1,0,0,0,0}, 0, 0, 1, 1, 2, 0, 1}, /* hWb */
    [1285] = {{0,1,-2,-1,0,0,0,0}, 0, 0, 1, 1, 2, 0, 1}, /* hT */
    [1286] = {{0,0,0,0,0,0,1,0}, 56, 1, 1, 1, 2, 0, 1}, /* hlm */
    [1287] = {{-2,0,0,0,0,0,1,0}, 42, 1, 1, 1, 2, 0, 1}, /* hlx */
    [1288] = {{0,0,-1,0,0,0,0,0}, 17, 1, 1, 1, 2, 0, 1}, /* hBq */
    [1289] = {{2,0,-2,0,0,0,0,0}, 1, 1, 1, 1, 2, 0, 1}, /* hGy */
    [1290] = {{2,0,-2,0,0,0,0,0}, 23, 1, 1, 1, 2, 0, 1}, /* hSv */
    [1291] = {{0,0,-1,0,0,1,0,0}, 0, 0, 1, 1, 2, 0, 1}, /* hkat */
    [1292] = {{3,0,0,0,0,0,0,0}, 0, 0, 1, 1, -1, 0, 1}, /* hL */
    [1293] = {{3,0,0,0,0,0,0,0}, 0, 0, 1, 1, -1, 0, 1}, /* hl */
    [1294] = {{2,1,-2,0,0,0,0,0}, 0, 0, 801088317, 5, -25, 0, 1}, /* heV */
    [1295] = {{0,1,0,0,0,0,0,0}, 0, 0, 166053906660000015, 1, -44, 0, 1}, /* hDa */
    [1296] = {{0,1,0,0,0,0,0,0}, 0, 0, 1, 1, 5, 0, 1}, /* ht */
    [1297] = {{0,0,0,0,0,0,0,1}, 0, 0, 25, 2, 0, 0, 1}, /* hb */
    [1298] = {{0,0,0,0,0,0,0,1}, 0, 0, 1, 1, 2, 0, 1}, /* hB */
    [1299] = {{0,0,-1,0,0,0,0,1}, 0, 0, 25, 2, 0, 0, 1}, /* hbps */
    [1300] = {{0,0,-1,0,0,0,0,1}, 0, 0, 1, 1, 2, 0, 1}, /* hBps */
    [1301] = {{1,0,0,0,0,0,0,0}, 0, 0, 30856775814914, 1, 5, 0, 1}, /* hpc */
    [1302] = {{0,0,1,0,0,0,0,0}, 0, 0, 12096, 1, 4, 0, 1}, /* hfortnight */
    [1303] = {{0,0,1,0,0,0,0,0}, 0, 0, 31556952, 1, 4, 0, 1}, /* hcentury */
    [1304] = {{1,0,0,0,0,0,0,0}, 0, 0, 1, 1, 1, 0, 1}, /* dam */
    [1305] = {{0,1,0,0,0,0,0,0}, 0, 0, 1, 1, -2, 0, 1}, /* dag */
    [1306] = {{0,0,1,0,0,0,0,0}, 0, 0, 1, 1, 1, 0, 1}, /* das */
    [1307] = {{0,0,0,1,0,0,0,0}, 0, 0, 1, 1, 1, 0, 1}, /* daA */
    [1308] = {{0,0,0,0,1,0,0,0}, 0, 0, 1, 1, 1, 0, 1}, /* daK */
    [1309] = {{0,0,0,0,0,1,0,0}, 0, 0, 1, 1, 1, 0, 1}, /* damol */
    [1310] = {{0,0,0,0,0,0,1,0}, 57, 1, 1, 1, 1, 0, 1}, /* dacd */
    [1311] = {{0,1,-2,0,0,0,0,0}, 16, -1, 1, 1, -25, 0, 1}, /* daJy */
    [1312] = {{2,1,-3,0,0,0,0,0}, 79, 1, 1, 1, 1, 0, 1}, /* davar */
    [1313] = {{2,1,-3,0,0,0,0,0}, 4, 1, 1, 1, 1, 0, 1}, /* daVA */
    [1314] = {{1,1,-2,0,0,0,0,0}, 0, 0, 1, 1, 1, 0, 1}, /* daN */
    [1315] = {{2,1,-2,0,0,0,0,0}, 0, 0, 1, 1, 1, 0, 1}, /* daJ */
    [1316] = {{2,1,-3,0,0,0,0,0}, 0, 0, 1, 1, 1, 0, 1}, /* daW */
    [1317] = {{-1,1,-2,0,0,0,0,0}, 0, 0, 1, 1, 1, 0, 1}, /* daPa */
    [1318] = {{0,0,-1,0,0,0,0,0}, 16, 1, 1, 1, 1, 0, 1}, /* daHz */
    [1319] = {{2,1,-3,-1,0,0,0,0}, 0, 0, 1, 1, 1, 0, 1}, /* daV */
    [1320] = {{0,0,1,1,0,0,0,0}, 0, 0, 1, 1, 1, 0, 1}, /* daC */
    [1321] = {{2,1,-3,-2,0,0,0,0}, 0, 0, 1, 1, 1, 0, 1}, /* da\xce\xa9 */
    [1322] = {{-2,-1,4,2,0,0,0,0}, 0, 0, 1, 1, 1, 0, 1}, /* daF */
    [1323] = {{2,1,-2,-2,0,0,0,0}, 0, 0, 1, 1, 1, 0, 1}, /* daH */
    [1324] = {{-2,-1,3,2,0,0,0,0}, 0, 0, 1, 1, 1, 0, 1}, /* daS */
    [1325] = {{2,1,-2,-1,0,0,0,0}, 0, 0, 1, 1, 1, 0, 1}, /* daWb */
    [1326] = {{0,1,-2,-1,0,0,0,0}, 0, 0, 1, 1, 1, 0, 1}, /* daT */
    [1327] = {{0,0,0,0,0,0,1,0}, 56, 1, 1, 1, 1, 0, 1}, /* dalm */
    [1328] = {{-2,0,0,0,0,0,1,0}, 42, 1, 1, 1, 1, 0, 1}, /* dalx */
    [1329] = {{0,0,-1,0,0,0,0,0}, 17, 1, 1, 1, 1, 0, 1}, /* daBq */
    [1330] = {{2,0,-2,0,0,0,0,0}, 1, 1, 1, 1, 1, 0, 1}, /* daGy */
    [1331] = {{2,0,-2,0,0,0,0,0}, 23, 1, 1, 1, 1, 0, 1}, /* daSv */
    [1332] = {{0,0,-1,0,0,1,0,0}, 0, 0, 1, 1, 1, 0, 1}, /* dakat */
    [1333] = {{3,0,0,0,0,0,0,0}, 0, 0, 1, 1, -2, 0, 1}, /* daL */
    [1334] = {{3,0,0,0,0,0,0,0}, 0, 0, 1, 1, -2, 0, 1}, /* dal */
    [1335] = {{2,1,-2,0,0,0,0,0}, 0, 0, 801088317, 5, -26, 0, 1}, /* daeV */
    [1336] = {{0,1,0,0,0,0,0,0}, 0, 0, 166053906660000015, 1, -44, 0, 1}, /* daDa */
    [1337] = {{0,1,0,0,0,0,0,0}, 0, 0, 1, 1, 4, 0, 1}, /* dat */
    [1338] = {{0,0,0,0,0,0,0,1}, 0, 0, 5, 4, 0, 0, 1}, /* dab */
    [1339] = {{0,0,0,0,0,0,0,1}, 0, 0, 1, 1, 1, 0, 1}, /* daB */
    [1340] = {{0,0,-1,0,0,0,0,1}, 0, 0, 5, 4, 0, 0, 1}, /* dabps */
    [1341] = {{0,0,-1,0,0,0,0,1}, 0, 0, 1, 1, 1, 0, 1}, /* daBps */
    [1342] = {{1,0,0,0,0,0,0,0}, 0, 0, 30856775814914, 1, 4, 0, 1}, /* dapc */
    [1343] = {{0,0,1,0,0,0,0,0}, 0, 0, 12096, 1, 3, 0, 1}, /* dafortnight */
    [1344] = {{0,0,1,0,0,0,0,0}, 0, 0, 31556952, 1, 3, 0, 1}, /* dacentury */
    [1345] = {{1,0,0,0,0,0,0,0}, 0, 0, 1, 1, -1, 0, 1}, /* dm */
    [1346] = {{0,1,0,0,0,0,0,0}, 0, 0, 1, 1, -4, 0, 1}, /* dg */
    [1347] = {{0,0,1,0,0,0,0,0}, 0, 0, 1, 1, -1, 0, 1}, /* ds */
    [1348] = {{0,0,0,1,0,0,0,0}, 0, 0, 1, 1, -1, 0, 1}, /* dA */
    [1349] = {{0,0,0,0,1,0,0,0}, 0, 0, 1, 1, -1, 0, 1}, /* dK */
    [1350] = {{0,0,0,0,0,1,0,0}, 0, 0, 1, 1, -1, 0, 1}, /* dmol */
    [1351] = {{0,0,0,0,0,0,1,0}, 57, 1, 1, 1, -1, 0, 1}, /* dcd */
    [1352] = {{0,1,-2,0,0,0,0,0}, 16, -1, 1, 1, -27, 0, 1}, /* dJy */
    [1353] = {{2,1,-3,0,0,0,0,0}, 79, 1, 1, 1, -1, 0, 1}, /* dvar */
    [1354] = {{2,1,-3,0,0,0,0,0}, 4, 1, 1, 1, -1, 0, 1}, /* dVA */
    [1355] = {{1,1,-2,0,0,0,0,0}, 0, 0, 1, 1, -1, 0, 1}, /* dN */
    [1356] = {{2,1,-2,0,0,0,0,0}, 0, 0, 1, 1, -1, 0, 1}, /* dJ */
    [1357] = {{2,1,-3,0,0,0,0,0}, 0, 0, 1, 1, -1, 0, 1}, /* dW */
    [1358] = {{-1,1,-2,0,0,0,0,0}, 0, 0, 1, 1, -1, 0, 1}, /* dPa */
    [1359] = {{0,0,-1,0,0,0,0,0}, 16, 1, 1, 1, -1, 0, 1}, /* dHz */
    [1360] = {{2,1,-3,-1,0,0,0,0}, 0, 0, 1, 1, -1, 0, 1}, /* dV */
    [1361] = {{0,0,1,1,0,0,0,0}, 0, 0, 1, 1, -1, 0, 1}, /* dC */
    [1362] = {{2,1,-3,-2,0,0,0,0}, 0, 0, 1, 1, -1, 0, 1}, /* d\xce\xa9 */
    [1363] = {{-2,-1,4,2,0,0,0,0}, 0, 0, 1, 1, -1, 0, 1}, /* dF */
    [1364] = {{2,1,-2,-2,0,0,0,0}, 0, 0, 1, 1, -1, 0, 1}, /* dH */
    [1365] = {{-2,-1,3,2,0,0,0,0}, 0, 0, 1, 1, -1, 0, 1}, /* dS */
    [1366] = {{2,1,-2,-1,0,0,0,0}, 0, 0, 1, 1, -1, 0, 1}, /* dWb */
    [1367] = {{0,1,-2,-1,0,0,0,0}, 0, 0, 1, 1, -1, 0, 1}, /* dT */
    [1368] = {{0,0,0,0,0,0,1,0}, 56, 1, 1, 1, -1, 0, 1}, /* dlm */
    [1369] = {{-2,0,0,0,0,0,1,0}, 42, 1, 1, 1, -1, 0, 1}, /* dlx */
    [1370] = {{0,0,-1,0,0,0,0,0}, 17, 1, 1, 1, -1, 0, 1}, /* dBq */
    [1371] = {{2,0,-2,0,0,0,0,0}, 1, 1, 1, 1, -1, 0, 1}, /* dGy */
    [1372] = {{2,0,-2,0,0,0,0,0}, 23, 1, 1, 1, -1, 0, 1}, /* dSv */
    [1373] = {{0,0,-1,0,0,1,0,0}, 0, 0, 1, 1, -1, 0, 1}, /* dkat */
    [1374] = {{3,0,0,0,0,0,0,0}, 0, 0, 1, 1, -4, 0, 1}, /* dL */
    [1375] = {{3,0,0,0,0,0,0,0}, 0, 0, 1, 1, -4, 0, 1}, /* dl */
    [1376] = {{2,1,-2,0,0,0,0,0}, 0, 0, 801088317, 5, -28, 0, 1}, /* deV */
    [1377] = {{0,1,0,0,0,0,0,0}, 0, 0, 166053906660000015, 1, -44, 0, 1}, /* dDa */
    [1378] = {{0,1,0,0,0,0,0,0}, 0, 0, 1, 1, 2, 0, 1}, /* dt */
    [1379] = {{0,0,0,0,0,0,0,1}, 0, 0, 1, 8, -1, 0, 1}, /* db */
    [1380] = {{0,0,0,0,0,0,0,1}, 0, 0, 1, 1, -1, 0, 1}, /* dB */
    [1381] = {{0,0,-1,0,0,0,0,1}, 0, 0, 1, 8, -1, 0, 1}, /* dbps */
    [1382] = {{0,0,-1,0,0,0,0,1}, 0, 0, 1, 1, -1, 0, 1}, /* dBps */
    [1383] = {{1,0,0,0,0,0,0,0}, 0, 0, 30856775814914, 1, 2, 0, 1}, /* dpc */
    [1384] = {{0,0,1,0,0,0,0,0}, 0, 0, 12096, 1, 1, 0, 1}, /* dfortnight */
    [1385] = {{0,0,1,0,0,0,0,0}, 0, 0, 31556952, 1, 1, 0, 1}, /* dcentury */
    [1386] = {{0,1,0,0,0,0,0,0}, 0, 0, 1, 1, -5, 0, 1}, /* cg */
    [1387] = {{0,0,1,0,0,0,0,0}, 0, 0, 1, 1, -2, 0, 1}, /* cs */
    [1388] = {{0,0,0,1,0,0,0,0}, 0, 0, 1, 1, -2, 0, 1}, /* cA */
    [1389] = {{0,0,0,0,1,0,0,0}, 0, 0, 1, 1, -2, 0, 1}, /* cK */
    [1390] = {{0,0,0,0,0,1,0,0}, 0, 0, 1, 1, -2, 0, 1}, /* cmol */
    [1391] = {{0,0,0,0,0,0,1,0}, 57, 1, 1, 1, -2, 0, 1}, /* ccd */
    [1392] = {{0,1,-2,0,0,0,0,0}, 16, -1, 1, 1, -28, 0, 1}, /* cJy */
    [1393] = {{2,1,-3,0,0,0,0,0}, 79, 1, 1, 1, -2, 0, 1}, /* cvar */
    [1394] = {{2,1,-3,0,0,0,0,0}, 4, 1, 1, 1, -2, 0, 1}, /* cVA */
    [1395] = {{1,1,-2,0,0,0,0,0}, 0, 0, 1, 1, -2, 0, 1}, /* cN */
    [1396] = {{2,1,-2,0,0,0,0,0}, 0, 0, 1, 1, -2, 0, 1}, /* cJ */
    [1397] = {{2,1,-3,0,0,0,0,0}, 0, 0, 1, 1, -2, 0, 1}, /* cW */
    [1398] = {{-1,1,-2,0,0,0,0,0}, 0, 0, 1, 1, -2, 0, 1}, /* cPa */
    [1399] = {{0,0,-1,0,0,0,0,0}, 16, 1, 1, 1, -2, 0, 1}, /* cHz */
    [1400] = {{2,1,-3,-1,0,0,0,0}, 0, 0, 1, 1, -2, 0, 1}, /* cV */
    [1401] = {{0,0,1,1,0,0,0,0}, 0, 0, 1, 1, -2, 0, 1}, /* cC */
    [1402] = {{2,1,-3,-2,0,0,0,0}, 0, 0, 1, 1, -2, 0, 1}, /* c\xce\xa9 */
    [1403] = {{-2,-1,4,2,0,0,0,0}, 0, 0, 1, 1, -2, 0, 1}, /* cF */
    [1404] = {{2,1,-2,-2,0,0,0,0}, 0, 0, 1, 1, -2, 0, 1}, /* cH */
    [1405] = {{-2,-1,3,2,0,0,0,0}, 0, 0, 1, 1, -2, 0, 1}, /* cS */
    [1406] = {{2,1,-2,-1,0,0,0,0}, 0, 0, 1, 1, -2, 0, 1}, /* cWb */
    [1407] = {{0,1,-2,-1,0,0,0,0}, 0, 0, 1, 1, -2, 0, 1}, /* cT */
    [1408] = {{0,0,0,0,0,0,1,0}, 56, 1, 1, 1, -2, 0, 1}, /* clm */
    [1409] = {{-2,0,0,0,0,0,1,0}, 42, 1, 1, 1, -2, 0, 1}, /* clx */
    [1410] = {{0,0,-1,0,0,0,0,0}, 17, 1, 1, 1, -2, 0, 1}, /* cBq */
    [1411] = {{2,0,-2,0,0,0,0,0}, 1, 1, 1, 1, -2, 0, 1}, /* cGy */
    [1412] = {{2,0,-2,0,0,0,0,0}, 23, 1, 1, 1, -2, 0, 1}, /* cSv */
    [1413] = {{0,0,-1,0,0,1,0,0}, 0, 0, 1, 1, -2, 0, 1}, /* ckat */
    [1414] = {{3,0,0,0,0,0,0,0}, 0, 0, 1, 1, -5, 0, 1}, /* cL */
    [1415] = {{3,0,0,0,0,0,0,0}, 0, 0, 1, 1, -5, 0, 1}, /* cl */
    [1416] = {{2,1,-2,0,0,0,0,0}, 0, 0, 801088317, 5, -29, 0, 1}, /* ceV */
    [1417] = {{0,1,0,0,0,0,0,0}, 0, 0, 166053906660000015, 1, -44, 0, 1}, /* cDa */
    [1418] = {{0,0,0,0,0,0,0,1}, 0, 0, 1, 8, -2, 0, 1}, /* cb */
    [1419] = {{0,0,0,0,0,0,0,1}, 0, 0, 1, 1, -2, 0, 1}, /* cB */
    [1420] = {{0,0,-1,0,0,0,0,1}, 0, 0, 1, 8, -2, 0, 1}, /* cbps */
    [1421] = {{0,0,-1,0,0,0,0,1}, 0, 0, 1, 1, -2, 0, 1}, /* cBps */
    [1422] = {{1,0,0,0,0,0,0,0}, 0, 0, 30856775814914, 1, 1, 0, 1}, /* cpc */
    [1423] = {{0,0,1,0,0,0,0,0}, 0, 0, 12096, 1, 0, 0, 1}, /* cfortnight */
    [1424] = {{0,0,1,0,0,0,0,0}, 0, 0, 31556952, 1, 0, 0, 1}, /* ccentury */
    [1425] = {{0,0,0,0,1,0,0,0}, 0, 0, 1, 1, -3, 0, 1}, /* mK */
    [1426] = {{0,0,0,0,0,1,0,0}, 0, 0, 1, 1, -3, 0, 1}, /* mmol */
    [1427] = {{0,0,0,0,0,0,1,0}, 57, 1, 1, 1, -3, 0, 1}, /* mcd */
    [1428] = {{0,1,-2,0,0,0,0,0}, 16, -1, 1, 1, -29, 0, 1}, /* mJy */
    [1429] = {{2,1,-3,0,0,0,0,0}, 79, 1, 1, 1, -3, 0, 1}, /* mvar */
    [1430] = {{2,1,-3,0,0,0,0,0}, 4, 1, 1, 1, -3, 0, 1}, /* mVA */
    [1431] = {{1,1,-2,0,0,0,0,0}, 0, 0, 1, 1, -3, 0, 1}, /* mN */
    [1432] = {{2,1,-2,0,0,0,0,0}, 0, 0, 1, 1, -3, 0, 1}, /* mJ */
    [1433] = {{2,1,-3,0,0,0,0,0}, 0, 0, 1, 1, -3, 0, 1}, /* mW */
    [1434] = {{-1,1,-2,0,0,0,0,0}, 0, 0, 1, 1, -3, 0, 1}, /* mPa */
    [1435] = {{0,0,-1,0,0,0,0,0}, 16, 1, 1, 1, -3, 0, 1}, /* mHz */
    [1436] = {{2,1,-3,-1,0,0,0,0}, 0, 0, 1, 1, -3, 0, 1}, /* mV */
    [1437] = {{0,0,1,1,0,0,0,0}, 0, 0, 1, 1, -3, 0, 1}, /* mC */
    [1438] = {{2,1,-3,-2,0,0,0,0}, 0, 0, 1, 1, -3, 0, 1}, /* m\xce\xa9 */
    [1439] = {{-2,-1,4,2,0,0,0,0}, 0, 0, 1, 1, -3, 0, 1}, /* mF */
    [1440] = {{2,1,-2,-2,0,0,0,0}, 0, 0, 1, 1, -3, 0, 1}, /* mH */
    [1441] = {{-2,-1,3,2,0,0,0,0}, 0, 0, 1, 1, -3, 0, 1}, /* mS */
    [1442] = {{2,1,-2,-1,0,0,0,0}, 0, 0, 1, 1, -3, 0, 1}, /* mWb */
    [1443] = {{0,1,-2,-1,0,0,0,0}, 0, 0, 1, 1, -3, 0, 1}, /* mT */
    [1444] = {{0,0,0,0,0,0,1,0}, 56, 1, 1, 1, -3, 0, 1}, /* mlm */
    [1445] = {{-2,0,0,0,0,0,1,0}, 42, 1, 1, 1, -3, 0, 1}, /* mlx */
    [1446] = {{0,0,-1,0,0,0,0,0}, 17, 1, 1, 1, -3, 0, 1}, /* mBq */
    [1447] = {{2,0,-2,0,0,0,0,0}, 1, 1, 1, 1, -3, 0, 1}, /* mGy */
    [1448] = {{2,0,-2,0,0,0,0,0}, 23, 1, 1, 1, -3, 0, 1}, /* mSv */
    [1449] = {{0,0,-1,0,0,1,0,0}, 0, 0, 1, 1, -3, 0, 1}, /* mkat */
    [1450] = {{3,0,0,0,0,0,0,0}, 0, 0, 1, 1, -6, 0, 1}, /* ml */
    [1451] = {{2,1,-2,0,0,0,0,0}, 0, 0, 801088317, 5, -30, 0, 1}, /* meV */
    [1452] = {{0,1,0,0,0,0,0,0}, 0, 0, 166053906660000015, 1, -44, 0, 1}, /* mDa */
    [1453] = {{0,1,0,0,0,0,0,0}, 0, 0, 1, 1, 0, 0, 1}, /* mt */
    [1454] = {{0,0,0,0,0,0,0,1}, 0, 0, 1, 8, -3, 0, 1}, /* mb */
    [1455] = {{0,0,0,0,0,0,0,1}, 0, 0, 1, 1, -3, 0, 1}, /* mB */
    [1456] = {{0,0,-1,0,0,0,0,1}, 0, 0, 1, 8, -3, 0, 1}, /* mbps */
    [1457] = {{0,0,-1,0,0,0,0,1}, 0, 0, 1, 1, -3, 0, 1}, /* mBps */
    [1458] = {{1,0,0,0,0,0,0,0}, 0, 0, 30856775814914, 1, 0, 0, 1}, /* mpc */
    [1459] = {{0,0,1,0,0,0,0,0}, 0, 0, 6048, 5, 0, 0, 1}, /* mfortnight */
    [1460] = {{0,0,1,0,0,0,0,0}, 0, 0, 15778476, 5, 0, 0, 1}, /* mcentury */
    [1461] = {{1,0,0,0,0,0,0,0}, 0, 0, 1, 1, -6, 0, 1}, /* um */
    [1462] = {{0,1,0,0,0,0,0,0}, 0, 0, 1, 1, -9, 0, 1}, /* ug */
    [1463] = {{0,0,1,0,0,0,0,0}, 0, 0, 1, 1, -6, 0, 1}, /* us */
    [1464] = {{0,0,0,1,0,0,0,0}, 0, 0, 1, 1, -6, 0, 1}, /* uA */
    [1465] = {{0,0,0,0,1,0,0,0}, 0, 0, 1, 1, -6, 0, 1}, /* uK */
    [1466] = {{0,0,0,0,0,1,0,0}, 0, 0, 1, 1, -6, 0, 1}, /* umol */
    [1467] = {{0,0,0,0,0,0,1,0}, 57, 1, 1, 1, -6, 0, 1}, /* ucd */
    [1468] = {{0,1,-2,0,0,0,0,0}, 16, -1, 1, 1, -32, 0, 1}, /* uJy */
    [1469] = {{2,1,-3,0,0,0,0,0}, 79, 1, 1, 1, -6, 0, 1}, /* uvar */
    [1470] = {{2,1,-3,0,0,0,0,0}, 4, 1, 1, 1, -6, 0, 1}, /* uVA */
    [1471] = {{1,1,-2,0,0,0,0,0}, 0, 0, 1, 1, -6, 0, 1}, /* uN */
    [1472] = {{2,1,-2,0,0,0,0,0}, 0, 0, 1, 1, -6, 0, 1}, /* uJ */
    [1473] = {{2,1,-3,0,0,0,0,0}, 0, 0, 1, 1, -6, 0, 1}, /* uW */
    [1474] = {{-1,1,-2,0,0,0,0,0}, 0, 0, 1, 1, -6, 0, 1}, /* uPa */
    [1475] = {{0,0,-1,0,0,0,0,0}, 16, 1, 1, 1, -6, 0, 1}, /* uHz */
    [1476] = {{2,1,-3,-1,0,0,0,0}, 0, 0, 1, 1, -6, 0, 1}, /* uV */
    [1477] = {{0,0,1,1,0,0,0,0}, 0, 0, 1, 1, -6, 0, 1}, /* uC */
    [1478] = {{2,1,-3,-2,0,0,0,0}, 0, 0, 1, 1, -6, 0, 1}, /* u\xce\xa9 */
    [1479] = {{-2,-1,4,2,0,0,0,0}, 0, 0, 1, 1, -6, 0, 1}, /* uF */
    [1480] = {{2,1,-2,-2,0,0,0,0}, 0, 0, 1, 1, -6, 0, 1}, /* uH */
    [1481] = {{-2,-1,3,2,0,0,0,0}, 0, 0, 1, 1, -6, 0, 1}, /* uS */
    [1482] = {{2,1,-2,-1,0,0,0,0}, 0, 0, 1, 1, -6, 0, 1}, /* uWb */
    [1483] = {{0,1,-2,-1,0,0,0,0}, 0, 0, 1, 1, -6, 0, 1}, /* uT */
    [1484] = {{0,0,0,0,0,0,1,0}, 56, 1, 1, 1, -6, 0, 1}, /* ulm */
    [1485] = {{-2,0,0,0,0,0,1,0}, 42, 1, 1, 1, -6, 0, 1}, /* ulx */
    [1486] = {{0,0,-1,0,0,0,0,0}, 17, 1, 1, 1, -6, 0, 1}, /* uBq */
    [1487] = {{2,0,-2,0,0,0,0,0}, 1, 1, 1, 1, -6, 0, 1}, /* uGy */
    [1488] = {{2,0,-2,0,0,0,0,0}, 23, 1, 1, 1, -6, 0, 1}, /* uSv */
    [1489] = {{0,0,-1,0,0,1,0,0}, 0, 0, 1, 1, -6, 0, 1}, /* ukat */
    [1490] = {{3,0,0,0,0,0,0,0}, 0, 0, 1, 1, -9, 0, 1}, /* uL */
    [1491] = {{3,0,0,0,0,0,0,0}, 0, 0, 1, 1, -9, 0, 1}, /* ul */
    [1492] = {{2,1,-2,0,0,0,0,0}, 0, 0, 801088317, 5, -33, 0, 1}, /* ueV */
    [1493] = {{0,1,0,0,0,0,0,0}, 0, 0, 166053906660000015, 1, -44, 0, 1}, /* uDa */
    [1494] = {{0,1,0,0,0,0,0,0}, 0, 0, 1, 1, -3, 0, 1}, /* ut */
    [1495] = {{0,0,0,0,0,0,0,1}, 0, 0, 1, 8, -6, 0, 1}, /* ub */
    [1496] = {{0,0,0,0,0,0,0,1}, 0, 0, 1, 1, -6, 0, 1}, /* uB */
    [1497] = {{0,0,-1,0,0,0,0,1}, 0, 0, 1, 8, -6, 0, 1}, /* ubps */
    [1498] = {{0,0,-1,0,0,0,0,1}, 0, 0, 1, 1, -6, 0, 1}, /* uBps */
    [1499] = {{1,0,0,0,0,0,0,0}, 0, 0, 15428387907457, 5, -2, 0, 1}, /* upc */
    [1500] = {{0,0,1,0,0,0,0,0}, 0, 0, 756, 625, 0, 0, 1}, /* ufortnight */
    [1501] = {{0,0,1,0,0,0,0,0}, 0, 0, 3944619, 125, -1, 0, 1}, /* ucentury */
    [1502] = {{1,0,0,0,0,0,0,0}, 0, 0, 1, 1, -6, 0, 1}, /* \xce\xbcm */
    [1503] = {{0,1,0,0,0,0,0,0}, 0, 0, 1, 1, -9, 0, 1}, /* \xce\xbcg */
    [1504] = {{0,0,1,0,0,0,0,0}, 0, 0, 1, 1, -6, 0, 1}, /* \xce\xbcs */
    [1505] = {{0,0,0,1,0,0,0,0}, 0, 0, 1, 1, -6, 0, 1}, /* \xce\xbc\x41 */
    [1506] = {{0,0,0,0,1,0,0,0}, 0, 0, 1, 1, -6, 0, 1}, /* \xce\xbcK */
    [1507] = {{0,0,0,0,0,1,0,0}, 0, 0, 1, 1, -6, 0, 1}, /* \xce\xbcmol */
    [1508] = {{0,0,0,0,0,0,1,0}, 57, 1, 1, 1, -6, 0, 1}, /* \xce\xbc\x63\x64 */
    [1509] = {{0,1,-2,0,0,0,0,0}, 16, -1, 1, 1, -32, 0, 1}, /* \xce\xbcJy */
    [1510] = {{2,1,-3,0,0,0,0,0}, 79, 1, 1, 1, -6, 0, 1}, /* \xce\xbcvar */
    [1511] = {{2,1,-3,0,0,0,0,0}, 4, 1, 1, 1, -6, 0, 1}, /* \xce\xbcVA */
    [1512] = {{1,1,-2,0,0,0,0,0}, 0, 0, 1, 1, -6, 0, 1}, /* \xce\xbcN */
    [1513] = {{2,1,-2,0,0,0,0,0}, 0, 0, 1, 1, -6, 0, 1}, /* \xce\xbcJ */
    [1514] = {{2,1,-3,0,0,0,0,0}, 0, 0, 1, 1, -6, 0, 1}, /* \xce\xbcW */
    [1515] = {{-1,1,-2,0,0,0,0,0}, 0, 0, 1, 1, -6, 0, 1}, /* \xce\xbcPa */
    [1516] = {{0,0,-1,0,0,0,0,0}, 16, 1, 1, 1, -6, 0, 1}, /* \xce\xbcHz */
    [1517] = {{2,1,-3,-1,0,0,0,0}, 0, 0, 1, 1, -6, 0, 1}, /* \xce\xbcV */
    [1518] = {{0,0,1,1,0,0,0,0}, 0, 0, 1, 1, -6, 0, 1}, /* \xce\xbc\x43 */
    [1519] = {{2,1,-3,-2,0,0,0,0}, 0, 0, 1, 1, -6, 0, 1}, /* \xce\xbc\xce\xa9 */
    [1520] = {{-2,-1,4,2,0,0,0,0}, 0, 0, 1, 1, -6, 0, 1}, /* \xce\xbc\x46 */
    [1521] = {{2,1,-2,-2,0,0,0,0}, 0, 0, 1, 1, -6, 0, 1}, /* \xce\xbcH */
    [1522] = {{-2,-1,3,2,0,0,0,0}, 0, 0, 1, 1, -6, 0, 1}, /* \xce\xbcS */
    [1523] = {{2,1,-2,-1,0,0,0,0}, 0, 0, 1, 1, -6, 0, 1}, /* \xce\xbcWb */
    [1524] = {{0,1,-2,-1,0,0,0,0}, 0, 0, 1, 1, -6, 0, 1}, /* \xce\xbcT */
    [1525] = {{0,0,0,0,0,0,1,0}, 56, 1, 1, 1, -6, 0, 1}, /* \xce\xbclm */
    [1526] = {{-2,0,0,0,0,0,1,0}, 42, 1, 1, 1, -6, 0, 1}, /* \xce\xbclx */
    [1527] = {{0,0,-1,0,0,0,0,0}, 17, 1, 1, 1, -6, 0, 1}, /* \xce\xbc\x42q */
    [1528] = {{2,0,-2,0,0,0,0,0}, 1, 1, 1, 1, -6, 0, 1}, /* \xce\xbcGy */
    [1529] = {{2,0,-2,0,0,0,0,0}, 23, 1, 1, 1, -6, 0, 1}, /* \xce\xbcSv */
    [1530] = {{0,0,-1,0,0,1,0,0}, 0, 0, 1, 1, -6, 0, 1}, /* \xce\xbckat */
    [1531] = {{3,0,0,0,0,0,0,0}, 0, 0, 1, 1, -9, 0, 1}, /* \xce\xbcL */
    [1532] = {{3,0,0,0,0,0,0,0}, 0, 0, 1, 1, -9, 0, 1}, /* \xce\xbcl */
    [1533] = {{2,1,-2,0,0,0,0,0}, 0, 0, 801088317, 5, -33, 0, 1}, /* \xce\xbc\x65V */
    [1534] = {{0,1,0,0,0,0,0,0}, 0, 0, 166053906660000015, 1, -44, 0, 1}, /* \xce\xbc\x44\x61 */
    [1535] = {{0,1,0,0,0,0,0,0}, 0, 0, 1, 1, -3, 0, 1}, /* \xce\xbct */
    [1536] = {{0,0,0,0,0,0,0,1}, 0, 0, 1, 8, -6, 0, 1}, /* \xce\xbc\x62 */
    [1537] = {{0,0,0,0,0,0,0,1}, 0, 0, 1, 1, -6, 0, 1}, /* \xce\xbc\x42 */
    [1538] = {{0,0,-1,0,0,0,0,1}, 0, 0, 1, 8, -6, 0, 1}, /* \xce\xbc\x62ps */
    [1539] = {{0,0,-1,0,0,0,0,1}, 0, 0, 1, 1, -6, 0, 1}, /* \xce\xbc\x42ps */
    [1540] = {{1,0,0,0,0,0,0,0}, 0, 0, 15428387907457, 5, -2, 0, 1}, /* \xce\xbcpc */
    [1541] = {{0,0,1,0,0,0,0,0}, 0, 0, 756, 625, 0, 0, 1}, /* \xce\xbc\x66ortnight */
    [1542] = {{0,0,1,0,0,0,0,0}, 0, 0, 3944619, 125, -1, 0, 1}, /* \xce\xbc\x63\x65ntury */
    [1543] = {{0,0,0,0,1,0,0,0}, 0, 0, 1, 1, -6, 0, 1}, /* \xc2\xb5K */
    [1544] = {{0,0,0,0,0,1,0,0}, 0, 0, 1, 1, -6, 0, 1}, /* \xc2\xb5mol */
    [1545] = {{0,0,0,0,0,0,1,0}, 57, 1, 1, 1, -6, 0, 1}, /* \xc2\xb5\x63\x64 */
    [1546] = {{0,1,-2,0,0,0,0,0}, 16, -1, 1, 1, -32, 0, 1}, /* \xc2\xb5Jy */
    [1547] = {{2,1,-3,0,0,0,0,0}, 79, 1, 1, 1, -6, 0, 1}, /* \xc2\xb5var */
    [1548] = {{2,1,-3,0,0,0,0,0}, 4, 1, 1, 1, -6, 0, 1}, /* \xc2\xb5VA */
    [1549] = {{1,1,-2,0,0,0,0,0}, 0, 0, 1, 1, -6, 0, 1}, /* \xc2\xb5N */
    [1550] = {{2,1,-2,0,0,0,0,0}, 0, 0, 1, 1, -6, 0, 1}, /* \xc2\xb5J */
    [1551] = {{2,1,-3,0,0,0,0,0}, 0, 0, 1, 1, -6, 0, 1}, /* \xc2\xb5W */
    [1552] = {{-1,1,-2,0,0,0,0,0}, 0, 0, 1, 1, -6, 0, 1}, /* \xc2\xb5Pa */
    [1553] = {{0,0,-1,0,0,0,0,0}, 16, 1, 1, 1, -6, 0, 1}, /* \xc2\xb5Hz */
    [1554] = {{2,1,-3,-1,0,0,0,0}, 0, 0, 1, 1, -6, 0, 1}, /* \xc2\xb5V */
    [1555] = {{0,0,1,1,0,0,0,0}, 0, 0, 1, 1, -6, 0, 1}, /* \xc2\xb5\x43 */
    [1556] = {{2,1,-3,-2,0,0,0,0}, 0, 0, 1, 1, -6, 0, 1}, /* \xc2\xb5\xce\xa9 */
    [1557] = {{-2,-1,4,2,0,0,0,0}, 0, 0, 1, 1, -6, 0, 1}, /* \xc2\xb5\x46 */
    [1558] = {{2,1,-2,-2,0,0,0,0}, 0, 0, 1, 1, -6, 0, 1}, /* \xc2\xb5H */
    [1559] = {{-2,-1,3,2,0,0,0,0}, 0, 0, 1, 1, -6, 0, 1}, /* \xc2\xb5S */
    [1560] = {{2,1,-2,-1,0,0,0,0}, 0, 0, 1, 1, -6, 0, 1}, /* \xc2\xb5Wb */
    [1561] = {{0,1,-2,-1,0,0,0,0}, 0, 0, 1, 1, -6, 0, 1}, /* \xc2\xb5T */
    [1562] = {{0,0,0,0,0,0,1,0}, 56, 1, 1, 1, -6, 0, 1}, /* \xc2\xb5lm */
    [1563] = {{-2,0,0,0,0,0,1,0}, 42, 1, 1, 1, -6, 0, 1}, /* \xc2\xb5lx */
    [1564] = {{0,0,-1,0,0,0,0,0}, 17, 1, 1, 1, -6, 0, 1}, /* \xc2\xb5\x42q */
    [1565] = {{2,0,-2,0,0,0,0,0}, 1, 1, 1, 1, -6, 0, 1}, /* \xc2\xb5Gy */
    [1566] = {{2,0,-2,0,0,0,0,0}, 23, 1, 1, 1, -6, 0, 1}, /* \xc2\xb5Sv */
    [1567] = {{0,0,-1,0,0,1,0,0}, 0, 0, 1, 1, -6, 0, 1}, /* \xc2\xb5kat */
    [1568] = {{3,0,0,0,0,0,0,0}, 0, 0, 1, 1, -9, 0, 1}, /* \xc2\xb5L */
    [1569] = {{3,0,0,0,0,0,0,0}, 0, 0, 1, 1, -9, 0, 1}, /* \xc2\xb5l */
    [1570] = {{2,1,-2,0,0,0,0,0}, 0, 0, 801088317, 5, -33, 0, 1}, /* \xc2\xb5\x65V */
    [1571] = {{0,1,0,0,0,0,0,0}, 0, 0, 166053906660000015, 1, -44, 0, 1}, /* \xc2\xb5\x44\x61 */
    [1572] = {{0,1,0,0,0,0,0,0}, 0, 0, 1, 1, -3, 0, 1}, /* \xc2\xb5t */
    [1573] = {{0,0,0,0,0,0,0,1}, 0, 0, 1, 8, -6, 0, 1}, /* \xc2\xb5\x62 */
    [1574] = {{0,0,0,0,0,0,0,1}, 0, 0, 1, 1, -6, 0, 1}, /* \xc2\xb5\x42 */
    [1575] = {{0,0,-1,0,0,0,0,1}, 0, 0, 1, 8, -6, 0, 1}, /* \xc2\xb5\x62ps */
    [1576] = {{0,0,-1,0,0,0,0,1}, 0, 0, 1, 1, -6, 0, 1}, /* \xc2\xb5\x42ps */
    [1577] = {{1,0,0,0,0,0,0,0}, 0, 0, 15428387907457, 5, -2, 0, 1}, /* \xc2\xb5pc */
    [1578] = {{0,0,1,0,0,0,0,0}, 0, 0, 756, 625, 0, 0, 1}, /* \xc2\xb5\x66ortnight */
    [1579] = {{0,0,1,0,0,0,0,0}, 0, 0, 3944619, 125, -1, 0, 1}, /* \xc2\xb5\x63\x65ntury */
    [1580] = {{0,1,0,0,0,0,0,0}, 0, 0, 1, 1, -12, 0, 1}, /* ng */
    [1581] = {{0,0,0,1,0,0,0,0}, 0, 0, 1, 1, -9, 0, 1}, /* nA */
    [1582] = {{0,0,0,0,1,0,0,0}, 0, 0, 1, 1, -9, 0, 1}, /* nK */
    [1583] = {{0,0,0,0,0,1,0,0}, 0, 0, 1, 1, -9, 0, 1}, /* nmol */
    [1584] = {{0,0,0,0,0,0,1,0}, 57, 1, 1, 1, -9, 0, 1}, /* ncd */
    [1585] = {{0,1,-2,0,0,0,0,0}, 16, -1, 1, 1, -35, 0, 1}, /* nJy */
    [1586] = {{2,1,-3,0,0,0,0,0}, 79, 1, 1, 1, -9, 0, 1}, /* nvar */
    [1587] = {{2,1,-3,0,0,0,0,0}, 4, 1, 1, 1, -9, 0, 1}, /* nVA */
    [1588] = {{1,1,-2,0,0,0,0,0}, 0, 0, 1, 1, -9, 0, 1}, /* nN */
    [1589] = {{2,1,-2,0,0,0,0,0}, 0, 0, 1, 1, -9, 0, 1}, /* nJ */
    [1590] = {{2,1,-3,0,0,0,0,0}, 0, 0, 1, 1, -9, 0, 1}, /* nW */
    [1591] = {{-1,1,-2,0,0,0,0,0}, 0, 0, 1, 1, -9, 0, 1}, /* nPa */
    [1592] = {{0,0,-1,0,0,0,0,0}, 16, 1, 1, 1, -9, 0, 1}, /* nHz */
    [1593] = {{2,1,-3,-1,0,0,0,0}, 0, 0, 1, 1, -9, 0, 1}, /* nV */
    [1594] = {{0,0,1,1,0,0,0,0}, 0, 0, 1, 1, -9, 0, 1}, /* nC */
    [1595] = {{2,1,-3,-2,0,0,0,0}, 0, 0, 1, 1, -9, 0, 1}, /* n\xce\xa9 */
    [1596] = {{-2,-1,4,2,0,0,0,0}, 0, 0, 1, 1, -9, 0, 1}, /* nF */
    [1597] = {{2,1,-2,-2,0,0,0,0}, 0, 0, 1, 1, -9, 0, 1}, /* nH */
    [1598] = {{-2,-1,3,2,0,0,0,0}, 0, 0, 1, 1, -9, 0, 1}, /* nS */
    [1599] = {{2,1,-2,-1,0,0,0,0}, 0, 0, 1, 1, -9, 0, 1}, /* nWb */
    [1600] = {{0,1,-2,-1,0,0,0,0}, 0, 0, 1, 1, -9, 0, 1}, /* nT */
    [1601] = {{0,0,0,0,0,0,1,0}, 56, 1, 1, 1, -9, 0, 1}, /* nlm */
    [1602] = {{-2,0,0,0,0,0,1,0}, 42, 1, 1, 1, -9, 0, 1}, /* nlx */
    [1603] = {{0,0,-1,0,0,0,0,0}, 17, 1, 1, 1, -9, 0, 1}, /* nBq */
    [1604] = {{2,0,-2,0,0,0,0,0}, 1, 1, 1, 1, -9, 0, 1}, /* nGy */
    [1605] = {{2,0,-2,0,0,0,0,0}, 23, 1, 1, 1, -9, 0, 1}, /* nSv */
    [1606] = {{0,0,-1,0,0,1,0,0}, 0, 0, 1, 1, -9, 0, 1}, /* nkat */
    [1607] = {{3,0,0,0,0,0,0,0}, 0, 0, 1, 1, -12, 0, 1}, /* nL */
    [1608] = {{3,0,0,0,0,0,0,0}, 0, 0, 1, 1, -12, 0, 1}, /* nl */
    [1609] = {{2,1,-2,0,0,0,0,0}, 0, 0, 801088317, 5, -36, 0, 1}, /* neV */
    [1610] = {{0,1,0,0,0,0,0,0}, 0, 0, 166053906660000015, 1, -44, 0, 1}, /* nDa */
    [1611] = {{0,1,0,0,0,0,0,0}, 0, 0, 1, 1, -6, 0, 1}, /* nt */
    [1612] = {{0,0,0,0,0,0,0,1}, 0, 0, 1, 8, -9, 0, 1}, /* nb */
    [1613] = {{0,0,0,0,0,0,0,1}, 0, 0, 1, 1, -9, 0, 1}, /* nB */
    [1614] = {{0,0,-1,0,0,0,0,1}, 0, 0, 1, 8, -9, 0, 1}, /* nbps */
    [1615] = {{0,0,-1,0,0,0,0,1}, 0, 0, 1, 1, -9, 0, 1}, /* nBps */
    [1616] = {{1,0,0,0,0,0,0,0}, 0, 0, 15428387907457, 5, -5, 0, 1}, /* npc */
    [1617] = {{0,0,1,0,0,0,0,0}, 0, 0, 189, 15625, -1, 0, 1}, /* nfortnight */
    [1618] = {{0,0,1,0,0,0,0,0}, 0, 0, 3944619, 125, -4, 0, 1}, /* ncentury */
    [1619] = {{0,1,0,0,0,0,0,0}, 0, 0, 1, 1, -15, 0, 1}, /* pg */
    [1620] = {{0,0,0,1,0,0,0,0}, 0, 0, 1, 1, -12, 0, 1}, /* pA */
    [1621] = {{0,0,0,0,1,0,0,0}, 0, 0, 1, 1, -12, 0, 1}, /* pK */
    [1622] = {{0,0,0,0,0,1,0,0}, 0, 0, 1, 1, -12, 0, 1}, /* pmol */
    [1623] = {{0,0,0,0,0,0,1,0}, 57, 1, 1, 1, -12, 0, 1}, /* pcd */
    [1624] = {{0,1,-2,0,0,0,0,0}, 16, -1, 1, 1, -38, 0, 1}, /* pJy */
    [1625] = {{2,1,-3,0,0,0,0,0}, 79, 1, 1, 1, -12, 0, 1}, /* pvar */
    [1626] = {{2,1,-3,0,0,0,0,0}, 4, 1, 1, 1, -12, 0, 1}, /* pVA */
    [1627] = {{1,1,-2,0,0,0,0,0}, 0, 0, 1, 1, -12, 0, 1}, /* pN */
    [1628] = {{2,1,-2,0,0,0,0,0}, 0, 0, 1, 1, -12, 0, 1}, /* pJ */
    [1629] = {{2,1,-3,0,0,0,0,0}, 0, 0, 1, 1, -12, 0, 1}, /* pW */
    [1630] = {{-1,1,-2,0,0,0,0,0}, 0, 0, 1, 1, -12, 0, 1}, /* pPa */
    [1631] = {{0,0,-1,0,0,0,0,0}, 16, 1, 1, 1, -12, 0, 1}, /* pHz */
    [1632] = {{2,1,-3,-1,0,0,0,0}, 0, 0, 1, 1, -12, 0, 1}, /* pV */
    [1633] = {{0,0,1,1,0,0,0,0}, 0, 0, 1, 1, -12, 0, 1}, /* pC */
    [1634] = {{2,1,-3,-2,0,0,0,0}, 0, 0, 1, 1, -12, 0, 1}, /* p\xce\xa9 */
    [1635] = {{-2,-1,4,2,0,0,0,0}, 0, 0, 1, 1, -12, 0, 1}, /* pF */
    [1636] = {{2,1,-2,-2,0,0,0,0}, 0, 0, 1, 1, -12, 0, 1}, /* pH */
    [1637] = {{-2,-1,3,2,0,0,0,0}, 0, 0, 1, 1, -12, 0, 1}, /* pS */
    [1638] = {{2,1,-2,-1,0,0,0,0}, 0, 0, 1, 1, -12, 0, 1}, /* pWb */
    [1639] = {{0,1,-2,-1,0,0,0,0}, 0, 0, 1, 1, -12, 0, 1}, /* pT */
    [1640] = {{0,0,0,0,0,0,1,0}, 56, 1, 1, 1, -12, 0, 1}, /* plm */
    [1641] = {{-2,0,0,0,0,0,1,0}, 42, 1, 1, 1, -12, 0, 1}, /* plx */
    [1642] = {{0,0,-1,0,0,0,0,0}, 17, 1, 1, 1, -12, 0, 1}, /* pBq */
    [1643] = {{2,0,-2,0,0,0,0,0}, 1, 1, 1, 1, -12, 0, 1}, /* pGy */
    [1644] = {{2,0,-2,0,0,0,0,0}, 23, 1, 1, 1, -12, 0, 1}, /* pSv */
    [1645] = {{0,0,-1,0,0,1,0,0}, 0, 0, 1, 1, -12, 0, 1}, /* pkat */
    [1646] = {{3,0,0,0,0,0,0,0}, 0, 0, 1, 1, -15, 0, 1}, /* pL */
    [1647] = {{3,0,0,0,0,0,0,0}, 0, 0, 1, 1, -15, 0, 1}, /* pl */
    [1648] = {{2,1,-2,0,0,0,0,0}, 0, 0, 801088317, 5, -39, 0, 1}, /* peV */
    [1649] = {{0,1,0,0,0,0,0,0}, 0, 0, 166053906660000015, 1, -44, 0, 1}, /* pDa */
    [1650] = {{0,0,0,0,0,0,0,1}, 0, 0, 1, 1, -12, 0, 1}, /* pB */
    [1651] = {{0,0,-1,0,0,0,0,1}, 0, 0, 1, 8, -12, 0, 1}, /* pbps */
    [1652] = {{0,0,-1,0,0,0,0,1}, 0, 0, 1, 1, -12, 0, 1}, /* pBps */
    [1653] = {{1,0,0,0,0,0,0,0}, 0, 0, 15428387907457, 5, -8, 0, 1}, /* ppc */
    [1654] = {{0,0,1,0,0,0,0,0}, 0, 0, 189, 15625, -4, 0, 1}, /* pfortnight */
    [1655] = {{0,0,1,0,0,0,0,0}, 0, 0, 3944619, 125, -7, 0, 1}, /* pcentury */
    [1656] = {{1,0,0,0,0,0,0,0}, 0, 0, 1, 1, -15, 0, 1}, /* fm */
    [1657] = {{0,1,0,0,0,0,0,0}, 0, 0, 1, 1, -18, 0, 1}, /* fg */
    [1658] = {{0,0,1,0,0,0,0,0}, 0, 0, 1, 1, -15, 0, 1}, /* fs */
    [1659] = {{0,0,0,1,0,0,0,0}, 0, 0, 1, 1, -15, 0, 1}, /* fA */
    [1660] = {{0,0,0,0,1,0,0,0}, 0, 0, 1, 1, -15, 0, 1}, /* fK */
    [1661] = {{0,0,0,0,0,1,0,0}, 0, 0, 1, 1, -15, 0, 1}, /* fmol */
    [1662] = {{0,0,0,0,0,0,1,0}, 57, 1, 1, 1, -15, 0, 1}, /* fcd */
    [1663] = {{0,1,-2,0,0,0,0,0}, 16, -1, 1, 1, -41, 0, 1}, /* fJy */
    [1664] = {{2,1,-3,0,0,0,0,0}, 79, 1, 1, 1, -15, 0, 1}, /* fvar */
    [1665] = {{2,1,-3,0,0,0,0,0}, 4, 1, 1, 1, -15, 0, 1}, /* fVA */
    [1666] = {{1,1,-2,0,0,0,0,0}, 0, 0, 1, 1, -15, 0, 1}, /* fN */
    [1667] = {{2,1,-2,0,0,0,0,0}, 0, 0, 1, 1, -15, 0, 1}, /* fJ */
    [1668] = {{2,1,-3,0,0,0,0,0}, 0, 0, 1, 1, -15, 0, 1}, /* fW */
    [1669] = {{-1,1,-2,0,0,0,0,0}, 0, 0, 1, 1, -15, 0, 1}, /* fPa */
    [1670] = {{0,0,-1,0,0,0,0,0}, 16, 1, 1, 1, -15, 0, 1}, /* fHz */
    [1671] = {{2,1,-3,-1,0,0,0,0}, 0, 0, 1, 1, -15, 0, 1}, /* fV */
    [1672] = {{0,0,1,1,0,0,0,0}, 0, 0, 1, 1, -15, 0, 1}, /* fC */
    [1673] = {{2,1,-3,-2,0,0,0,0}, 0, 0, 1, 1, -15, 0, 1}, /* f\xce\xa9 */
    [1674] = {{-2,-1,4,2,0,0,0,0}, 0, 0, 1, 1, -15, 0, 1}, /* fF */
    [1675] = {{2,1,-2,-2,0,0,0,0}, 0, 0, 1, 1, -15, 0, 1}, /* fH */
    [1676] = {{-2,-1,3,2,0,0,0,0}, 0, 0, 1, 1, -15, 0, 1}, /* fS */
    [1677] = {{2,1,-2,-1,0,0,0,0}, 0, 0, 1, 1, -15, 0, 1}, /* fWb */
    [1678] = {{0,1,-2,-1,0,0,0,0}, 0, 0, 1, 1, -15, 0, 1}, /* fT */
    [1679] = {{0,0,0,0,0,0,1,0}, 56, 1, 1, 1, -15, 0, 1}, /* flm */
    [1680] = {{-2,0,0,0,0,0,1,0}, 42, 1, 1, 1, -15, 0, 1}, /* flx */
    [1681] = {{0,0,-1,0,0,0,0,0}, 17, 1, 1, 1, -15, 0, 1}, /* fBq */
    [1682] = {{2,0,-2,0,0,0,0,0}, 1, 1, 1, 1, -15, 0, 1}, /* fGy */
    [1683] = {{2,0,-2,0,0,0,0,0}, 23, 1, 1, 1, -15, 0, 1}, /* fSv */
    [1684] = {{0,0,-1,0,0,1,0,0}, 0, 0, 1, 1, -15, 0, 1}, /* fkat */
    [1685] = {{3,0,0,0,0,0,0,0}, 0, 0, 1, 1, -18, 0, 1}, /* fl */
    [1686] = {{2,1,-2,0,0,0,0,0}, 0, 0, 801088317, 5, -42, 0, 1}, /* feV */
    [1687] = {{0,1,0,0,0,0,0,0}, 0, 0, 166053906660000015, 1, -44, 0, 1}, /* fDa */
    [1688] = {{0,0,0,0,0,0,0,1}, 0, 0, 1, 8, -15, 0, 1}, /* fb */
    [1689] = {{0,0,0,0,0,0,0,1}, 0, 0, 1, 1, -15, 0, 1}, /* fB */
    [1690] = {{0,0,-1,0,0,0,0,1}, 0, 0, 1, 8, -15, 0, 1}, /* fbps */
    [1691] = {{0,0,-1,0,0,0,0,1}, 0, 0, 1, 1, -15, 0, 1}, /* fBps */
    [1692] = {{1,0,0,0,0,0,0,0}, 0, 0, 15428387907457, 5, -11, 0, 1}, /* fpc */
    [1693] = {{0,0,1,0,0,0,0,0}, 0, 0, 189, 15625, -7, 0, 1}, /* ffortnight */
    [1694] = {{0,0,1,0,0,0,0,0}, 0, 0, 3944619, 125, -10, 0, 1}, /* fcentury */
    [1695] = {{1,0,0,0,0,0,0,0}, 0, 0, 1, 1, -18, 0, 1}, /* am */
    [1696] = {{0,1,0,0,0,0,0,0}, 0, 0, 1, 1, -21, 0, 1}, /* ag */
    [1697] = {{0,0,1,0,0,0,0,0}, 0, 0, 1, 1, -18, 0, 1}, /* as */
    [1698] = {{0,0,0,1,0,0,0,0}, 0, 0, 1, 1, -18, 0, 1}, /* aA */
    [1699] = {{0,0,0,0,1,0,0,0}, 0, 0, 1, 1, -18, 0, 1}, /* aK */
    [1700] = {{0,0,0,0,0,1,0,0}, 0, 0, 1, 1, -18, 0, 1}, /* amol */
    [1701] = {{0,0,0,0,0,0,1,0}, 57, 1, 1, 1, -18, 0, 1}, /* acd */
    [1702] = {{0,1,-2,0,0,0,0,0}, 16, -1, 1, 1, -44, 0, 1}, /* aJy */
    [1703] = {{2,1,-3,0,0,0,0,0}, 79, 1, 1, 1, -18, 0, 1}, /* avar */
    [1704] = {{2,1,-3,0,0,0,0,0}, 4, 1, 1, 1, -18, 0, 1}, /* aVA */
    [1705] = {{1,1,-2,0,0,0,0,0}, 0, 0, 1, 1, -18, 0, 1}, /* aN */
    [1706] = {{2,1,-2,0,0,0,0,0}, 0, 0, 1, 1, -18, 0, 1}, /* aJ */
    [1707] = {{2,1,-3,0,0,0,0,0}, 0, 0, 1, 1, -18, 0, 1}, /* aW */
    [1708] = {{-1,1,-2,0,0,0,0,0}, 0, 0, 1, 1, -18, 0, 1}, /* aPa */
    [1709] = {{0,0,-1,0,0,0,0,0}, 16, 1, 1, 1, -18, 0, 1}, /* aHz */
    [1710] = {{2,1,-3,-1,0,0,0,0}, 0, 0, 1, 1, -18, 0, 1}, /* aV */
    [1711] = {{0,0,1,1,0,0,0,0}, 0, 0, 1, 1, -18, 0, 1}, /* aC */
    [1712] = {{2,1,-3,-2,0,0,0,0}, 0, 0, 1, 1, -18, 0, 1}, /* a\xce\xa9 */
    [1713] = {{-2,-1,4,2,0,0,0,0}, 0, 0, 1, 1, -18, 0, 1}, /* aF */
    [1714] = {{2,1,-2,-2,0,0,0,0}, 0, 0, 1, 1, -18, 0, 1}, /* aH */
    [1715] = {{-2,-1,3,2,0,0,0,0}, 0, 0, 1, 1, -18, 0, 1}, /* aS */
    [1716] = {{2,1,-2,-1,0,0,0,0}, 0, 0, 1, 1, -18, 0, 1}, /* aWb */
    [1717] = {{0,1,-2,-1,0,0,0,0}, 0, 0, 1, 1, -18, 0, 1}, /* aT */
    [1718] = {{0,0,0,0,0,0,1,0}, 56, 1, 1, 1, -18, 0, 1}, /* alm */
    [1719] = {{-2,0,0,0,0,0,1,0}, 42, 1, 1, 1, -18, 0, 1}, /* alx */
    [1720] = {{0,0,-1,0,0,0,0,0}, 17, 1, 1, 1, -18, 0, 1}, /* aBq */
    [1721] = {{2,0,-2,0,0,0,0,0}, 1, 1, 1, 1, -18, 0, 1}, /* aGy */
    [1722] = {{2,0,-2,0,0,0,0,0}, 23, 1, 1, 1, -18, 0, 1}, /* aSv */
    [1723] = {{0,0,-1,0,0,1,0,0}, 0, 0, 1, 1, -18, 0, 1}, /* akat */
    [1724] = {{3,0,0,0,0,0,0,0}, 0, 0, 1, 1, -21, 0, 1}, /* aL */
    [1725] = {{3,0,0,0,0,0,0,0}, 0, 0, 1, 1, -21, 0, 1}, /* al */
    [1726] = {{2,1,-2,0,0,0,0,0}, 0, 0, 801088317, 5, -45, 0, 1}, /* aeV */
    [1727] = {{0,1,0,0,0,0,0,0}, 0, 0, 166053906660000015, 1, -44, 0, 1}, /* aDa */
    [1728] = {{0,0,0,0,0,0,0,1}, 0, 0, 1, 8, -18, 0, 1}, /* ab */
    [1729] = {{0,0,0,0,0,0,0,1}, 0, 0, 1, 1, -18, 0, 1}, /* aB */
    [1730] = {{0,0,-1,0,0,0,0,1}, 0, 0, 1, 8, -18, 0, 1}, /* abps */
    [1731] = {{0,0,-1,0,0,0,0,1}, 0, 0, 1, 1, -18, 0, 1}, /* aBps */
    [1732] = {{1,0,0,0,0,0,0,0}, 0, 0, 15428387907457, 5, -14, 0, 1}, /* apc */
    [1733] = {{0,0,1,0,0,0,0,0}, 0, 0, 189, 15625, -10, 0, 1}, /* afortnight */
    [1734] = {{0,0,1,0,0,0,0,0}, 0, 0, 3944619, 125, -13, 0, 1}, /* acentury */
    [1735] = {{1,0,0,0,0,0,0,0}, 0, 0, 1, 1, -21, 0, 1}, /* zm */
    [1736] = {{0,1,0,0,0,0,0,0}, 0, 0, 1, 1, -24, 0, 1}, /* zg */
    [1737] = {{0,0,1,0,0,0,0,0}, 0, 0, 1, 1, -21, 0, 1}, /* zs */
    [1738] = {{0,0,0,1,0,0,0,0}, 0, 0, 1, 1, -21, 0, 1}, /* zA */
    [1739] = {{0,0,0,0,1,0,0,0}, 0, 0, 1, 1, -21, 0, 1}, /* zK */
    [1740] = {{0,0,0,0,0,1,0,0}, 0, 0, 1, 1, -21, 0, 1}, /* zmol */
    [1741] = {{0,0,0,0,0,0,1,0}, 57, 1, 1, 1, -21, 0, 1}, /* zcd */
    [1742] = {{0,1,-2,0,0,0,0,0}, 16, -1, 1, 1, -47, 0, 1}, /* zJy */
    [1743] = {{2,1,-3,0,0,0,0,0}, 79, 1, 1, 1, -21, 0, 1}, /* zvar */
    [1744] = {{2,1,-3,0,0,0,0,0}, 4, 1, 1, 1, -21, 0, 1}, /* zVA */
    [1745] = {{1,1,-2,0,0,0,0,0}, 0, 0, 1, 1, -21, 0, 1}, /* zN */
    [1746] = {{2,1,-2,0,0,0,0,0}, 0, 0, 1, 1, -21, 0, 1}, /* zJ */
    [1747] = {{2,1,-3,0,0,0,0,0}, 0, 0, 1, 1, -21, 0, 1}, /* zW */
    [1748] = {{-1,1,-2,0,0,0,0,0}, 0, 0, 1, 1, -21, 0, 1}, /* zPa */
    [1749] = {{0,0,-1,0,0,0,0,0}, 16, 1, 1, 1, -21, 0, 1}, /* zHz */
    [1750] = {{2,1,-3,-1,0,0,0,0}, 0, 0, 1, 1, -21, 0, 1}, /* zV */
    [1751] = {{0,0,1,1,0,0,0,0}, 0, 0, 1, 1, -21, 0, 1}, /* zC */
    [1752] = {{2,1,-3,-2,0,0,0,0}, 0, 0, 1, 1, -21, 0, 1}, /* z\xce\xa9 */
    [1753] = {{-2,-1,4,2,0,0,0,0}, 0, 0, 1, 1, -21, 0, 1}, /* zF */
    [1754] = {{2,1,-2,-2,0,0,0,0}, 0, 0, 1, 1, -21, 0, 1}, /* zH */
    [1755] = {{-2,-1,3,2,0,0,0,0}, 0, 0, 1, 1, -21, 0, 1}, /* zS */
    [1756] = {{2,1,-2,-1,0,0,0,0}, 0, 0, 1, 1, -21, 0, 1}, /* zWb */
    [1757] = {{0,1,-2,-1,0,0,0,0}, 0, 0, 1, 1, -21, 0, 1}, /* zT */
    [1758] = {{0,0,0,0,0,0,1,0}, 56, 1, 1, 1, -21, 0, 1}, /* zlm */
    [1759] = {{-2,0,0,0,0,0,1,0}, 42, 1, 1, 1, -21, 0, 1}, /* zlx */
    [1760] = {{0,0,-1,0,0,0,0,0}, 17, 1, 1, 1, -21, 0, 1}, /* zBq */
    [1761] = {{2,0,-2,0,0,0,0,0}, 1, 1, 1, 1, -21, 0, 1}, /* zGy */
    [1762] = {{2,0,-2,0,0,0,0,0}, 23, 1, 1, 1, -21, 0, 1}, /* zSv */
    [1763] = {{0,0,-1,0,0,1,0,0}, 0, 0, 1, 1, -21, 0, 1}, /* zkat */
    [1764] = {{3,0,0,0,0,0,0,0}, 0, 0, 1, 1, -24, 0, 1}, /* zL */
    [1765] = {{3,0,0,0,0,0,0,0}, 0, 0, 1, 1, -24, 0, 1}, /* zl */
    [1766] = {{2,1,-2,0,0,0,0,0}, 0, 0, 801088317, 5, -48, 0, 1}, /* zeV */
    [1767] = {{0,1,0,0,0,0,0,0}, 0, 0, 166053906660000015, 1, -44, 0, 1}, /* zDa */
    [1768] = {{0,1,0,0,0,0,0,0}, 0, 0, 1, 1, -18, 0, 1}, /* zt */
    [1769] = {{0,0,0,0,0,0,0,1}, 0, 0, 1, 8, -21, 0, 1}, /* zb */
    [1770] = {{0,0,0,0,0,0,0,1}, 0, 0, 1, 1, -21, 0, 1}, /* zB */
    [1771] = {{0,0,-1,0,0,0,0,1}, 0, 0, 1, 8, -21, 0, 1}, /* zbps */
    [1772] = {{0,0,-1,0,0,0,0,1}, 0, 0, 1, 1, -21, 0, 1}, /* zBps */
    [1773] = {{1,0,0,0,0,0,0,0}, 0, 0, 15428387907457, 5, -17, 0, 1}, /* zpc */
    [1774] = {{0,0,1,0,0,0,0,0}, 0, 0, 189, 15625, -13, 0, 1}, /* zfortnight */
    [1775] = {{0,0,1,0,0,0,0,0}, 0, 0, 3944619, 125, -16, 0, 1}, /* zcentury */
    [1776] = {{1,0,0,0,0,0,0,0}, 0, 0, 1, 1, -24, 0, 1}, /* ym */
    [1777] = {{0,1,0,0,0,0,0,0}, 0, 0, 1, 1, -27, 0, 1}, /* yg */
    [1778] = {{0,0,1,0,0,0,0,0}, 0, 0, 1, 1, -24, 0, 1}, /* ys */
    [1779] = {{0,0,0,1,0,0,0,0}, 0, 0, 1, 1, -24, 0, 1}, /* yA */
    [1780] = {{0,0,0,0,1,0,0,0}, 0, 0, 1, 1, -24, 0, 1}, /* yK */
    [1781] = {{0,0,0,0,0,1,0,0}, 0, 0, 1, 1, -24, 0, 1}, /* ymol */
    [1782] = {{0,0,0,0,0,0,1,0}, 57, 1, 1, 1, -24, 0, 1}, /* ycd */
    [1783] = {{0,1,-2,0,0,0,0,0}, 16, -1, 1, 1, -50, 0, 1}, /* yJy */
    [1784] = {{2,1,-3,0,0,0,0,0}, 79, 1, 1, 1, -24, 0, 1}, /* yvar */
    [1785] = {{2,1,-3,0,0,0,0,0}, 4, 1, 1, 1, -24, 0, 1}, /* yVA */
    [1786] = {{1,1,-2,0,0,0,0,0}, 0, 0, 1, 1, -24, 0, 1}, /* yN */
    [1787] = {{2,1,-2,0,0,0,0,0}, 0, 0, 1, 1, -24, 0, 1}, /* yJ */
    [1788] = {{2,1,-3,0,0,0,0,0}, 0, 0, 1, 1, -24, 0, 1}, /* yW */
    [1789] = {{-1,1,-2,0,0,0,0,0}, 0, 0, 1, 1, -24, 0, 1}, /* yPa */
    [1790] = {{0,0,-1,0,0,0,0,0}, 16, 1, 1, 1, -24, 0, 1}, /* yHz */
    [1791] = {{2,1,-3,-1,0,0,0,0}, 0, 0, 1, 1, -24, 0, 1}, /* yV */
    [1792] = {{0,0,1,1,0,0,0,0}, 0, 0, 1, 1, -24, 0, 1}, /* yC */
    [1793] = {{2,1,-3,-2,0,0,0,0}, 0, 0, 1, 1, -24, 0, 1}, /* y\xce\xa9 */
    [1794] = {{-2,-1,4,2,0,0,0,0}, 0, 0, 1, 1, -24, 0, 1}, /* yF */
    [1795] = {{2,1,-2,-2,0,0,0,0}, 0, 0, 1, 1, -24, 0, 1}, /* yH */
    [1796] = {{-2,-1,3,2,0,0,0,0}, 0, 0, 1, 1, -24, 0, 1}, /* yS */
    [1797] = {{2,1,-2,-1,0,0,0,0}, 0, 0, 1, 1, -24, 0, 1}, /* yWb */
    [1798] = {{0,1,-2,-1,0,0,0,0}, 0, 0, 1, 1, -24, 0, 1}, /* yT */
    [1799] = {{0,0,0,0,0,0,1,0}, 56, 1, 1, 1, -24, 0, 1}, /* ylm */
    [1800] = {{-2,0,0,0,0,0,1,0}, 42, 1, 1, 1, -24, 0, 1}, /* ylx */
    [1801] = {{0,0,-1,0,0,0,0,0}, 17, 1, 1, 1, -24, 0, 1}, /* yBq */
    [1802] = {{2,0,-2,0,0,0,0,0}, 1, 1, 1, 1, -24, 0, 1}, /* yGy */
    [1803] = {{2,0,-2,0,0,0,0,0}, 23, 1, 1, 1, -24, 0, 1}, /* ySv */
    [1804] = {{0,0,-1,0,0,1,0,0}, 0, 0, 1, 1, -24, 0, 1}, /* ykat */
    [1805] = {{3,0,0,0,0,0,0,0}, 0, 0, 1, 1, -27, 0, 1}, /* yL */
    [1806] = {{3,0,0,0,0,0,0,0}, 0, 0, 1, 1, -27, 0, 1}, /* yl */
    [1807] = {{2,1,-2,0,0,0,0,0}, 0, 0, 801088317, 5, -51, 0, 1}, /* yeV */
    [1808] = {{0,1,0,0,0,0,0,0}, 0, 0, 166053906660000015, 1, -44, 0, 1}, /* yDa */
    [1809] = {{0,1,0,0,0,0,0,0}, 0, 0, 1, 1, -21, 0, 1}, /* yt */
    [1810] = {{0,0,0,0,0,0,0,1}, 0, 0, 1, 8, -24, 0, 1}, /* yb */
    [1811] = {{0,0,0,0,0,0,0,1}, 0, 0, 1, 1, -24, 0, 1}, /* yB */
    [1812] = {{0,0,-1,0,0,0,0,1}, 0, 0, 1, 8, -24, 0, 1}, /* ybps */
    [1813] = {{0,0,-1,0,0,0,0,1}, 0, 0, 1, 1, -24, 0, 1}, /* yBps */
    [1814] = {{1,0,0,0,0,0,0,0}, 0, 0, 15428387907457, 5, -20, 0, 1}, /* ypc */
    [1815] = {{0,0,1,0,0,0,0,0}, 0, 0, 189, 15625, -16, 0, 1}, /* yfortnight */
    [1816] = {{0,0,1,0,0,0,0,0}, 0, 0, 3944619, 125, -19, 0, 1}, /* ycentury */
    [1817] = {{1,0,0,0,0,0,0,0}, 0, 0, 1, 1, -27, 0, 1}, /* rm */
    [1818] = {{0,1,0,0,0,0,0,0}, 0, 0, 1, 1, -30, 0, 1}, /* rg */
    [1819] = {{0,0,1,0,0,0,0,0}, 0, 0, 1, 1, -27, 0, 1}, /* rs */
    [1820] = {{0,0,0,1,0,0,0,0}, 0, 0, 1, 1, -27, 0, 1}, /* rA */
    [1821] = {{0,0,0,0,1,0,0,0}, 0, 0, 1, 1, -27, 0, 1}, /* rK */
    [1822] = {{0,0,0,0,0,1,0,0}, 0, 0, 1, 1, -27, 0, 1}, /* rmol */
    [1823] = {{0,0,0,0,0,0,1,0}, 57, 1, 1, 1, -27, 0, 1}, /* rcd */
    [1824] = {{0,1,-2,0,0,0,0,0}, 16, -1, 1, 1, -53, 0, 1}, /* rJy */
    [1825] = {{2,1,-3,0,0,0,0,0}, 79, 1, 1, 1, -27, 0, 1}, /* rvar */
    [1826] = {{2,1,-3,0,0,0,0,0}, 4, 1, 1, 1, -27, 0, 1}, /* rVA */
    [1827] = {{1,1,-2,0,0,0,0,0}, 0, 0, 1, 1, -27, 0, 1}, /* rN */
    [1828] = {{2,1,-2,0,0,0,0,0}, 0, 0, 1, 1, -27, 0, 1}, /* rJ */
    [1829] = {{2,1,-3,0,0,0,0,0}, 0, 0, 1, 1, -27, 0, 1}, /* rW */
    [1830] = {{-1,1,-2,0,0,0,0,0}, 0, 0, 1, 1, -27, 0, 1}, /* rPa */
    [1831] = {{0,0,-1,0,0,0,0,0}, 16, 1, 1, 1, -27, 0, 1}, /* rHz */
    [1832] = {{2,1,-3,-1,0,0,0,0}, 0, 0, 1, 1, -27, 0, 1}, /* rV */
    [1833] = {{0,0,1,1,0,0,0,0}, 0, 0, 1, 1, -27, 0, 1}, /* rC */
    [1834] = {{2,1,-3,-2,0,0,0,0}, 0, 0, 1, 1, -27, 0, 1}, /* r\xce\xa9 */
    [1835] = {{-2,-1,4,2,0,0,0,0}, 0, 0, 1, 1, -27, 0, 1}, /* rF */
    [1836] = {{2,1,-2,-2,0,0,0,0}, 0, 0, 1, 1, -27, 0, 1}, /* rH */
    [1837] = {{-2,-1,3,2,0,0,0,0}, 0, 0, 1, 1, -27, 0, 1}, /* rS */
    [1838] = {{2,1,-2,-1,0,0,0,0}, 0, 0, 1, 1, -27, 0, 1}, /* rWb */
    [1839] = {{0,1,-2,-1,0,0,0,0}, 0, 0, 1, 1, -27, 0, 1}, /* rT */
    [1840] = {{0,0,0,0,0,0,1,0}, 56, 1, 1, 1, -27, 0, 1}, /* rlm */
    [1841] = {{-2,0,0,0,0,0,1,0}, 42, 1, 1, 1, -27, 0, 1}, /* rlx */
    [1842] = {{0,0,-1,0,0,0,0,0}, 17, 1, 1, 1, -27, 0, 1}, /* rBq */
    [1843] = {{2,0,-2,0,0,0,0,0}, 1, 1, 1, 1, -27, 0, 1}, /* rGy */
    [1844] = {{2,0,-2,0,0,0,0,0}, 23, 1, 1, 1, -27, 0, 1}, /* rSv */
    [1845] = {{0,0,-1,0,0,1,0,0}, 0, 0, 1, 1, -27, 0, 1}, /* rkat */
    [1846] = {{3,0,0,0,0,0,0,0}, 0, 0, 1, 1, -30, 0, 1}, /* rL */
    [1847] = {{3,0,0,0,0,0,0,0}, 0, 0, 1, 1, -30, 0, 1}, /* rl */
    [1848] = {{2,1,-2,0,0,0,0,0}, 0, 0, 801088317, 5, -54, 0, 1}, /* reV */
    [1849] = {{0,1,0,0,0,0,0,0}, 0, 0, 166053906660000015, 1, -44, 0, 1}, /* rDa */
    [1850] = {{0,1,0,0,0,0,0,0}, 0, 0, 1, 1, -24, 0, 1}, /* rt */
    [1851] = {{0,0,0,0,0,0,0,1}, 0, 0, 1, 8, -27, 0, 1}, /* rb */
    [1852] = {{0,0,0,0,0,0,0,1}, 0, 0, 1, 1, -27, 0, 1}, /* rB */
    [1853] = {{0,0,-1,0,0,0,0,1}, 0, 0, 1, 8, -27, 0, 1}, /* rbps */
    [1854] = {{0,0,-1,0,0,0,0,1}, 0, 0, 1, 1, -27, 0, 1}, /* rBps */
    [1855] = {{1,0,0,0,0,0,0,0}, 0, 0, 15428387907457, 5, -23, 0, 1}, /* rpc */
    [1856] = {{0,0,1,0,0,0,0,0}, 0, 0, 189, 15625, -19, 0, 1}, /* rfortnight */
    [1857] = {{0,0,1,0,0,0,0,0}, 0, 0, 3944619, 125, -22, 0, 1}, /* rcentury */
    [1858] = {{1,0,0,0,0,0,0,0}, 0, 0, 1, 1, -30, 0, 1}, /* qm */
    [1859] = {{0,1,0,0,0,0,0,0}, 0, 0, 1, 1, -33, 0, 1}, /* qg */
    [1860] = {{0,0,1,0,0,0,0,0}, 0, 0, 1, 1, -30, 0, 1}, /* qs */
    [1861] = {{0,0,0,1,0,0,0,0}, 0, 0, 1, 1, -30, 0, 1}, /* qA */
    [1862] = {{0,0,0,0,1,0,0,0}, 0, 0, 1, 1, -30, 0, 1}, /* qK */
    [1863] = {{0,0,0,0,0,1,0,0}, 0, 0, 1, 1, -30, 0, 1}, /* qmol */
    [1864] = {{0,0,0,0,0,0,1,0}, 57, 1, 1, 1, -30, 0, 1}, /* qcd */
    [1865] = {{0,1,-2,0,0,0,0,0}, 16, -1, 1, 1, -56, 0, 1}, /* qJy */
    [1866] = {{2,1,-3,0,0,0,0,0}, 79, 1, 1, 1, -30, 0, 1}, /* qvar */
    [1867] = {{2,1,-3,0,0,0,0,0}, 4, 1, 1, 1, -30, 0, 1}, /* qVA */
    [1868] = {{1,1,-2,0,0,0,0,0}, 0, 0, 1, 1, -30, 0, 1}, /* qN */
    [1869] = {{2,1,-2,0,0,0,0,0}, 0, 0, 1, 1, -30, 0, 1}, /* qJ */
    [1870] = {{2,1,-3,0,0,0,0,0}, 0, 0, 1, 1, -30, 0, 1}, /* qW */
    [1871] = {{-1,1,-2,0,0,0,0,0}, 0, 0, 1, 1, -30, 0, 1}, /* qPa */
    [1872] = {{0,0,-1,0,0,0,0,0}, 16, 1, 1, 1, -30, 0, 1}, /* qHz */
    [1873] = {{2,1,-3,-1,0,0,0,0}, 0, 0, 1, 1, -30, 0, 1}, /* qV */
    [1874] = {{0,0,1,1,0,0,0,0}, 0, 0, 1, 1, -30, 0, 1}, /* qC */
    [1875] = {{2,1,-3,-2,0,0,0,0}, 0, 0, 1, 1, -30, 0, 1}, /* q\xce\xa9 */
    [1876] = {{-2,-1,4,2,0,0,0,0}, 0, 0, 1, 1, -30, 0, 1}, /* qF */
    [1877] = {{2,1,-2,-2,0,0,0,0}, 0, 0, 1, 1, -30, 0, 1}, /* qH */
    [1878] = {{-2,-1,3,2,0,0,0,0}, 0, 0, 1, 1, -30, 0, 1}, /* qS */
    [1879] = {{2,1,-2,-1,0,0,0,0}, 0, 0, 1, 1, -30, 0, 1}, /* qWb */
    [1880] = {{0,1,-2,-1,0,0,0,0}, 0, 0, 1, 1, -30, 0, 1}, /* qT */
    [1881] = {{0,0,0,0,0,0,1,0}, 56, 1, 1, 1, -30, 0, 1}, /* qlm */
    [1882] = {{-2,0,0,0,0,0,1,0}, 42, 1, 1, 1, -30, 0, 1}, /* qlx */
    [1883] = {{0,0,-1,0,0,0,0,0}, 17, 1, 1, 1, -30, 0, 1}, /* qBq */
    [1884] = {{2,0,-2,0,0,0,0,0}, 1, 1, 1, 1, -30, 0, 1}, /* qGy */
    [1885] = {{2,0,-2,0,0,0,0,0}, 23, 1, 1, 1, -30, 0, 1}, /* qSv */
    [1886] = {{0,0,-1,0,0,1,0,0}, 0, 0, 1, 1, -30, 0, 1}, /* qkat */
    [1887] = {{3,0,0,0,0,0,0,0}, 0, 0, 1, 1, -33, 0, 1}, /* qL */
    [1888] = {{3,0,0,0,0,0,0,0}, 0, 0, 1, 1, -33, 0, 1}, /* ql */
    [1889] = {{2,1,-2,0,0,0,0,0}, 0, 0, 801088317, 5, -57, 0, 1}, /* qeV */
    [1890] = {{0,1,0,0,0,0,0,0}, 0, 0, 166053906660000015, 1, -44, 0, 1}, /* qDa */
    [1891] = {{0,0,0,0,0,0,0,1}, 0, 0, 1, 8, -30, 0, 1}, /* qb */
    [1892] = {{0,0,0,0,0,0,0,1}, 0, 0, 1, 1, -30, 0, 1}, /* qB */
    [1893] = {{0,0,-1,0,0,0,0,1}, 0, 0, 1, 8, -30, 0, 1}, /* qbps */
    [1894] = {{0,0,-1,0,0,0,0,1}, 0, 0, 1, 1, -30, 0, 1}, /* qBps */
    [1895] = {{1,0,0,0,0,0,0,0}, 0, 0, 15428387907457, 5, -26, 0, 1}, /* qpc */
    [1896] = {{0,0,1,0,0,0,0,0}, 0, 0, 189, 15625, -22, 0, 1}, /* qfortnight */
    [1897] = {{0,0,1,0,0,0,0,0}, 0, 0, 3944619, 125, -25, 0, 1}, /* qcentury */
    [1898] = {{0,0,0,0,0,0,0,1}, 0, 0, 128, 1, 0, 0, 1}, /* Kib */
    [1899] = {{0,0,0,0,0,0,0,1}, 0, 0, 131072, 1, 0, 0, 1}, /* Mib */
    [1900] = {{0,0,0,0,0,0,0,1}, 0, 0, 134217728, 1, 0, 0, 1}, /* Gib */
    [1901] = {{0,0,0,0,0,0,0,1}, 0, 0, 137438953472, 1, 0, 0, 1}, /* Tib */
    [1902] = {{0,0,0,0,0,0,0,1}, 0, 0, 140737488355328, 1, 0, 0, 1}, /* Pib */
    [1903] = {{0,0,0,0,0,0,0,1}, 0, 0, 144115188075855872, 1, 0, 0, 1}, /* Eib */
    [1904] = {{0,0,0,0,0,0,0,1}, 0, 0, 147573952589676413, 1, 3, 0, 1}, /* Zib */
    [1905] = {{0,0,0,0,0,0,0,1}, 0, 0, 11805916207174113, 1, 5, 0, 1}, /* ZiB */
    [1906] = {{0,0,0,0,0,0,0,1}, 0, 0, 151115727451828647, 1, 6, 0, 1}, /* Yib */
    [1907] = {{0,0,0,0,0,0,0,1}, 0, 0, 120892581961462917, 1, 7, 0, 1}, /* YiB */
    [1908] = {{0,0,0,0,0,0,0,1}, 0, 0, 154742504910672534, 1, 9, 0, 1}, /* Rib */
    [1909] = {{0,0,0,0,0,0,0,1}, 0, 0, 123794003928538027, 1, 10, 0, 1}, /* RiB */
    [1910] = {{0,0,0,0,0,0,0,1}, 0, 0, 158456325028528675, 1, 12, 0, 1}, /* Qib */
    [1911] = {{0,0,0,0,0,0,0,1}, 0, 0, 12676506002282294, 1, 14, 0, 1}, /* QiB */
};
/* --- END GENERATED: unit_info --- */

void w_register_unit(int id, const char *name) {
    if (id < 0 || id >= W_UNIT_CAPACITY || id == W_UNIT_PERCENT) return;
    /* Copy name string so it persists */
    size_t len = strlen(name);
    char *copy = malloc(len + 1);
    memcpy(copy, name, len + 1);
    unit_names[id] = copy;
}

void w_register_unit_wv(int id, WValue name) {
    w_register_unit(id, as_str(name));
}

WValue w_quantity(int unit_id, int64_t sig, int scale) {
    decimal_normalize(&sig, &scale);
    /* IDs above 255 use the existing heap-domain representation; the compact
     * nan-box layout and its percent sentinel remain unchanged. */
    if (unit_id >= 0 && unit_id <= 255 && w_quantity_fits(sig, scale))
        return w_box_quantity(unit_id, sig, scale);
    return domain_heap_alloc(W_DOMAIN_QUANTITY, sig, scale, unit_id, 0);
}

/* ---- WValue-ABI literal parsers ----
 * The tree-walk interpreter (and the REPL) evaluate literal AST nodes at
 * runtime, after the lowering tables are out of reach — these shims parse the
 * captured literal text into the same exact domain values the compiled path
 * builds. sig/scale parsing mirrors lowering/literals.w parse_sig_scale. */
static int parse_sig_scale_cstr(const char *s, int64_t *sig_out, int *scale_out) {
    int64_t sig = 0;
    int scale = 0, neg = 0, seen_dot = 0, seen_digit = 0;
    int i = 0;
    if (s[0] == '-') { neg = 1; i++; }
    else if (s[0] == '+') i++;
    for (; s[i]; i++) {
        char c = s[i];
        if (c == '_') continue;
        if (c == '.') { if (seen_dot) return 0; seen_dot = 1; continue; }
        if (c == 'e' || c == 'E') {
            int esign = 1, ev = 0;
            i++;
            if (s[i] == '-') { esign = -1; i++; }
            else if (s[i] == '+') i++;
            if (!s[i]) return 0;
            for (; s[i]; i++) {
                if (s[i] < '0' || s[i] > '9') return 0;
                ev = ev * 10 + (s[i] - '0');
            }
            scale += esign * ev;
            break;
        }
        if (c < '0' || c > '9') return 0;
        sig = sig * 10 + (c - '0');
        seen_digit = 1;
        if (seen_dot) scale--;
    }
    if (!seen_digit) return 0;
    *sig_out = neg ? -sig : sig;
    *scale_out = scale;
    return 1;
}

/* Beyond-i64 significands parse exactly through the bigint reader and
 * construct a BigDecimal (the walker's literal path; the compiled path
 * reaches the same construction via w_decimal_from_digits). */
WValue w_bigint_from_dec_str(WValue str);
static WValue decimal_parse_big(const char *s) {
    int neg = 0;
    if (*s == '-') { neg = 1; s++; }
    else if (*s == '+') s++;
    size_t cap = strlen(s) + 1;
    char *digits = malloc(cap);
    size_t n = 0;
    int64_t frac = 0, expv = 0;
    int in_frac = 0;
    const char *p = s;
    for (; *p; p++) {
        if (*p >= '0' && *p <= '9') { digits[n++] = *p; if (in_frac) frac++; }
        else if (*p == '.' && !in_frac) in_frac = 1;
        else if (*p == '_') continue;
        else if (*p == 'e' || *p == 'E') { expv = strtoll(p + 1, NULL, 10); break; }
        else { free(digits); dief("invalid decimal literal: %s", s); }
    }
    digits[n] = '\0';
    WValue sig = w_bigint_from_dec_str(w_string_n(digits, n));
    free(digits);
    if (neg) sig = w_neg(sig);
    return w_decimal_big(sig, expv - frac);
}

WValue w_decimal_parse(WValue str_v) {
    const char *s = as_str(str_v);
    size_t digs = 0;
    for (const char *q = s; *q; q++) if (*q >= '0' && *q <= '9') digs++;
    if (digs > 18) return decimal_parse_big(s);
    int64_t sig; int scale;
    if (!parse_sig_scale_cstr(s, &sig, &scale)) dief("invalid decimal literal: %s", s);
    return w_decimal(sig, scale);
}

WValue w_currency_parse(WValue amount_v, WValue prefix_v, WValue suffix_v) {
    const char *amount = as_str(amount_v);
    int64_t sig; int scale;
    if (!parse_sig_scale_cstr(amount, &sig, &scale)) dief("invalid currency literal: %s", amount);
    int sym = 0;
    if (!w_is_nil(prefix_v)) {
        static const struct { const char *sym; int id; } prefix_map[] = {
            {"$", 0}, {"\xe2\x82\xac", 1}, {"\xc2\xa3", 2}, {"\xc2\xa5", 3},
            {"\xe2\x82\xb9", 4}, {"\xe2\x82\xa9", 6}, {"\xe2\x82\xbf", 7},
            {"\xe2\x82\xbd", 12}, {"\xe0\xb8\xbf", 13}, {"Fr", 8}, {"C$", 9},
            {"A$", 10}, {"R$", 11}, {"z\xc5\x82", 14},
        };
        const char *p = as_str(prefix_v);
        for (size_t k = 0; k < sizeof(prefix_map) / sizeof(prefix_map[0]); k++) {
            if (strcmp(prefix_map[k].sym, p) == 0) { sym = prefix_map[k].id; break; }
        }
    } else if (!w_is_nil(suffix_v)) {
        const char *sfx = as_str(suffix_v);
        if (strcmp(sfx, "\xc2\xa2") == 0)      { sym = 0; scale -= 2; }  /* ¢ → $/100 */
        else if (strcmp(sfx, "p") == 0)        { sym = 2; scale -= 2; }  /* p → £/100 */
        else if (strcmp(sfx, "\xe5\x86\x86") == 0) sym = 3;              /* 円 */
        else if (strcmp(sfx, "\xe5\x85\x83") == 0) sym = 5;              /* 元 */
        else if (strcmp(sfx, "/-") == 0)           sym = 4;
    }
    return w_currency(sym, sig, scale);
}

WValue w_quantity_parse(WValue num_v, WValue unit_v) {
    const char *num = as_str(num_v);
    const char *unit = as_str(unit_v);
    int64_t sig; int scale;
    if (!parse_sig_scale_cstr(num, &sig, &scale)) dief("invalid quantity literal: %s", num);
    int unit_id = unit_lookup_id(unit);
    if (unit_id < 0) {
        /* Unknown named unit: reuse an already-registered custom slot with
         * this name — every parse of `2π` must yield the SAME unit id, or
         * same-unit arithmetic (2π + 1π) sees a dimension mismatch. Only
         * then claim a free slot so the value displays with its own name. */
        for (int i = W_UNIT_CUSTOM_BASE; i < W_UNIT_CAPACITY; i++) {
            if (unit_names[i] && strcmp(unit_names[i], unit) == 0) { unit_id = i; break; }
        }
        for (int i = W_UNIT_CUSTOM_BASE; unit_id < 0 && i < W_UNIT_CAPACITY; i++) {
            if (!unit_names[i]) { w_register_unit(i, unit); unit_id = i; break; }
        }
        if (unit_id < 0) dief("too many custom units: %s", unit);
    }
    return w_quantity(unit_id, sig, scale);
}

WValue w_quantity_unit_name(WValue quantity) {
    if (!is_quantity_any(quantity)) return W_NIL;
    int unit, scale;
    int64_t sig;
    quantity_extract(quantity, &unit, &sig, &scale);
    if (unit < 0 || unit >= W_UNIT_CAPACITY || !unit_names[unit]) return W_NIL;
    return w_string(unit_names[unit]);
}

WValue w_quantity_value(WValue quantity) {
    if (!is_quantity_any(quantity)) return W_NIL;
    int unit, scale;
    int64_t sig;
    quantity_extract(quantity, &unit, &sig, &scale);
    return w_decimal(sig, scale);
}

/* ---- Cross-unit conversion ----
 * unit_info (generated above from the Ruby reference's exact rational
 * factors) lets same-dimension units convert: 3kg + 500g = 3.5 kg. The
 * value converts into the LEFT operand's unit. Conversion is exact when
 * the rational terminates in decimal (all the 2,5-denominator factors:
 * ft = 381/1250 m, lb = 45359237/10^8 kg, …); otherwise it rounds
 * half-up after 12 extra digits, like decimal division. */
static int quantity_dims_equal(const WUnitInfo *x, const WUnitInfo *y) {
    for (int i = 0; i < 8; i++)
        if (x->dim[i] != y->dim[i]) return 0;
    return x->custom_id == y->custom_id && x->custom_exp == y->custom_exp;
}

/* Round a rational n/d (d>0) into (sig, scale) with half-away rounding and
 * trailing-zero stripping, matching the legacy multiplicative path. `scale`
 * is the starting decimal exponent (0 for the affine path, the input scale
 * for the multiplicative path). Returns 0 on int64 overflow. */
static int quantity_rat_to_decimal(__int128 n, __int128 d, int64_t *sig, int *scale) {
    return decimal_quotient_i128(n, d, 1, sig, scale);
}

static int quantity_convert(int64_t *sig, int *scale, int from_unit, int to_unit) {
    if (from_unit == to_unit) return 1;
    if (from_unit < 0 || from_unit >= W_UNIT_CAPACITY ||
        to_unit < 0 || to_unit >= W_UNIT_CAPACITY) return 0;
    const WUnitInfo *f = &unit_info[from_unit];
    const WUnitInfo *t = &unit_info[to_unit];
    if (f->den == 0 || t->den == 0) return 0;      /* no-conversion sentinel */
    if (!quantity_dims_equal(f, t)) return 0;

    /* Affine scales (temperature: °C/°F/°R carry a nonzero offset) convert
     * through the SI base: SI = raw × f.num/f.den + f.off; then
     * raw_to = (SI − t.off) × t.den/t.num. Purely-multiplicative units keep
     * the exact legacy path below. */
    if (f->off_num != 0 || t->off_num != 0) {
        /* Current affine units all use unscaled rational factors. Keeping this
         * guard makes any future prefixed affine definition fail explicitly. */
        if (f->factor_scale != 0 || t->factor_scale != 0) return 0;
        /* raw = sig × 10^scale as a rational rn/rd */
        __int128 rn = *sig, rd = 1;
        if (*scale >= 0) { for (int k = 0; k < *scale; k++) rn *= 10; }
        else             { for (int k = 0; k < -(*scale); k++) rd *= 10; }
        __int128 fn = f->num, fd = f->den, on = f->off_num, od = f->off_den;
        __int128 tn = t->num, td = t->den, ton = t->off_num, tod = t->off_den;
        if (od == 0) od = 1;
        if (tod == 0) tod = 1;
        /* SI = rn/rd × fn/fd + on/od = (rn·fn·od + on·rd·fd) / (rd·fd·od) */
        __int128 si_n = rn * fn * od + on * rd * fd;
        __int128 si_d = rd * fd * od;
        /* diff = SI − ton/tod = (si_n·tod − ton·si_d) / (si_d·tod) */
        __int128 df_n = si_n * tod - ton * si_d;
        __int128 df_d = si_d * tod;
        /* value_to = diff × td/tn = (df_n·td) / (df_d·tn) */
        __int128 vn = df_n * td;
        __int128 vd = df_d * tn;
        int rscale = 0;
        if (!quantity_rat_to_decimal(vn, vd, sig, &rscale)) return 0;
        *scale = rscale;
        return 1;
    }

    /* value × (f.num/f.den) × (t.den/t.num) */
    __int128 n = (__int128)(*sig) * f->num * t->den;
    __int128 d = (__int128)f->den * t->num;
    *scale += f->factor_scale - t->factor_scale;
    return quantity_rat_to_decimal(n, d, sig, scale);
}

/* Temperature points are affine coordinates; temperature differences are
 * linear vectors. Their SI exponent is intentionally the same, but the delta
 * kind is tagged so ordinary conversion cannot mix them accidentally. */
static int quantity_is_temperature_point(int unit) {
    if (unit < 0 || unit >= W_UNIT_CAPACITY) return 0;
    const WUnitInfo *u = &unit_info[unit];
    if (u->den == 0 || u->custom_id != 0 || u->custom_exp != 0) return 0;
    for (int i = 0; i < 8; i++) {
        int expected = i == 4 ? 1 : 0;
        if (u->dim[i] != expected) return 0;
    }
    return 1;
}

static int quantity_is_temperature_delta(int unit) {
    if (unit < 0 || unit >= W_UNIT_CAPACITY) return 0;
    const WUnitInfo *u = &unit_info[unit];
    if (u->custom_id <= 0 || u->custom_exp != 1) return 0;
    if (u->custom_id >= (int)(sizeof(custom_dimension_names) / sizeof(custom_dimension_names[0]))) return 0;
    return strcmp(custom_dimension_names[u->custom_id], "temperature_delta") == 0;
}

static int quantity_role(WValue v, int unit) {
    int explicit_role = quantity_explicit_role(v);
    if (explicit_role != 0) return explicit_role;
    if (quantity_is_temperature_point(unit)) return W_QUANTITY_ROLE_POINT;
    if (quantity_is_temperature_delta(unit)) return W_QUANTITY_ROLE_DELTA;
    return 0;
}

WValue w_quantity_point_p(WValue quantity) {
    int unit, scale;
    int64_t sig;
    quantity_extract(quantity, &unit, &sig, &scale);
    return quantity_role(quantity, unit) == W_QUANTITY_ROLE_POINT ? W_TRUE : W_FALSE;
}

WValue w_quantity_delta_p(WValue quantity) {
    int unit, scale;
    int64_t sig;
    quantity_extract(quantity, &unit, &sig, &scale);
    return quantity_role(quantity, unit) == W_QUANTITY_ROLE_DELTA ? W_TRUE : W_FALSE;
}

static WValue quantity_result_with_role(WValue result, int role, WValue origin) {
    return role == 0 ? result : quantity_with_role(result, role, origin);
}

static WValue quantity_combined_origin(WValue a, WValue b) {
    WValue oa = quantity_origin_value(a);
    WValue ob = quantity_origin_value(b);
    if (oa != W_NIL && ob != W_NIL && oa != ob)
        die("cannot combine points/deltas with different origins");
    return oa != W_NIL ? oa : ob;
}

/* Convert only the interval size, deliberately ignoring affine offsets and
 * the point/delta kind distinction. */
static int quantity_convert_interval(int64_t *sig, int *scale, int from_unit, int to_unit) {
    const WUnitInfo *f = &unit_info[from_unit];
    const WUnitInfo *t = &unit_info[to_unit];
    if (f->den == 0 || t->den == 0) return 0;
    __int128 n = (__int128)(*sig) * f->num * t->den;
    __int128 d = (__int128)f->den * t->num;
    *scale += f->factor_scale - t->factor_scale;
    return quantity_rat_to_decimal(n, d, sig, scale);
}

static int quantity_delta_unit_for_point(int point_unit) {
    const char *name = unit_names[point_unit] ? unit_names[point_unit] : "";
    const char *delta = "\xce\x94" "K";
    if (strcmp(name, "K") == 0) delta = "\xce\x94" "K";
    else if (strcmp(name, "\xc2\xb0" "C") == 0) delta = "\xce\x94\xc2\xb0" "C";
    else if (strcmp(name, "\xc2\xb0" "F") == 0) delta = "\xce\x94\xc2\xb0" "F";
    else if (strcmp(name, "\xc2\xb0" "R") == 0) delta = "\xce\x94\xc2\xb0" "R";
    else if (strcmp(name, "\xc2\xb0" "De") == 0) delta = "\xce\x94\xc2\xb0" "De";
    else if (strcmp(name, "\xc2\xb0" "N") == 0) delta = "\xce\x94\xc2\xb0" "N";
    else if (strcmp(name, "\xc2\xb0" "R\xc3\xa9") == 0) delta = "\xce\x94\xc2\xb0" "R\xc3\xa9";
    else if (strcmp(name, "\xc2\xb0" "R\xc3\xb8") == 0) delta = "\xce\x94\xc2\xb0" "R\xc3\xb8";
    else if (strcmp(name, "\xc2\xb0" "W") == 0) delta = "\xce\x94\xc2\xb0" "W";
    return unit_lookup_id(delta);
}

/* Defined with the date helpers below; the compiler's static-quantity
 * lowering routes `date ± <time quantity>` through these entry points,
 * so they must delegate before extracting quantity fields. */
#ifdef W_RUNTIME_UNITY_INCLUDE
static WValue date_shift_quantity(WValue d, WValue q, int sign);
#endif

WValue w_quantity_add(WValue a, WValue b) {
    if (w_is_date(a) && is_quantity_any(b))
        return date_shift_quantity(a, b, 1);
    if (is_quantity_any(a) && w_is_date(b))
        return date_shift_quantity(b, a, 1);
    int unit_a, unit_b;
    int64_t a_sig64, b_sig64;
    int a_scale, b_scale;
    quantity_extract(a, &unit_a, &a_sig64, &a_scale);
    quantity_extract(b, &unit_b, &b_sig64, &b_scale);
    const char *add_name_a = unit_names[unit_a] ? unit_names[unit_a] : "";
    const char *add_name_b = unit_names[unit_b] ? unit_names[unit_b] : "";
    if (a_sig64 == 1 && a_scale == 0 && b_sig64 == 1 && b_scale == 0 &&
        ((strcmp(add_name_a, "PB") == 0 && strcmp(add_name_b, "J") == 0) ||
         (strcmp(add_name_a, "J") == 0 && strcmp(add_name_b, "PB") == 0))) {
        return w_string(
            "\n"
            "       \x1b[38;5;179m╭───────────────────────╮\x1b[0m\n"
            "       \x1b[38;5;179m│░░░░░░░░ B R E A D ░░░░│\x1b[0m\n"
            "       \x1b[38;5;179m╰───────────────────────╯\x1b[0m\n"
            "       \x1b[38;5;130m▓▓▓▓ PEANUT  BUTTER ▓▓▓▓\x1b[0m\n"
            "       \x1b[38;5;93m▒▒▒▒▒ GRAPE  JELLY ▒▒▒▒▒\x1b[0m\n"
            "       \x1b[38;5;179m╭───────────────────────╮\x1b[0m\n"
            "       \x1b[38;5;179m│░░░░░░░░ B R E A D ░░░░│\x1b[0m\n"
            "       \x1b[38;5;179m╰───────────────────────╯\x1b[0m\n"
            "\n    \x1b[38;5;213m♫\x1b[0m \x1b[1;38;5;220mIt's peanut butter jelly time!\x1b[0m \x1b[38;5;213m♫\x1b[0m\n");
    }
    int role_a = quantity_role(a, unit_a);
    int role_b = quantity_role(b, unit_b);
    int a_point = role_a == W_QUANTITY_ROLE_POINT;
    int b_point = role_b == W_QUANTITY_ROLE_POINT;
    int a_delta = role_a == W_QUANTITY_ROLE_DELTA;
    int b_delta = role_b == W_QUANTITY_ROLE_DELTA;
    WValue result_origin = quantity_combined_origin(a, b);
    if (a_point && b_point) {
        if (quantity_is_temperature_point(unit_a) && quantity_is_temperature_point(unit_b))
            die("cannot add two absolute temperatures; add a temperature difference instead");
        die("cannot add two points; add a delta to a point instead");
    }
    if (a_point && b_delta && quantity_is_temperature_point(unit_a) && quantity_is_temperature_delta(unit_b)) {
        if (!quantity_convert_interval(&b_sig64, &b_scale, unit_b, unit_a))
            die("cannot convert temperature difference");
    } else if (a_delta && b_point && quantity_is_temperature_delta(unit_a) && quantity_is_temperature_point(unit_b)) {
        if (!quantity_convert_interval(&a_sig64, &a_scale, unit_a, unit_b))
            die("cannot convert temperature difference");
        __int128 as = a_sig64, bs = b_sig64;
        decimal_align(&as, &a_scale, &bs, &b_scale);
        return quantity_result_with_role(w_quantity(unit_b, (int64_t)(as + bs), a_scale), W_QUANTITY_ROLE_POINT, result_origin);
    } else if (unit_a != unit_b && !quantity_convert(&b_sig64, &b_scale, unit_b, unit_a)) {
        const char *na = unit_names[unit_a] ? unit_names[unit_a] : "?";
        const char *nb = unit_names[unit_b] ? unit_names[unit_b] : "?";
        dief("cannot add %s and %s (dimension mismatch)", na, nb);
    }
    __int128 a_sig = a_sig64, b_sig = b_sig64;
    decimal_align(&a_sig, &a_scale, &b_sig, &b_scale);
    int result_role = (a_point || b_point) ? W_QUANTITY_ROLE_POINT :
                      ((a_delta || b_delta) ? W_QUANTITY_ROLE_DELTA : 0);
    return quantity_result_with_role(w_quantity(unit_a, (int64_t)(a_sig + b_sig), a_scale), result_role, result_origin);
}

WValue w_quantity_sub(WValue a, WValue b) {
    if (w_is_date(a) && is_quantity_any(b))
        return date_shift_quantity(a, b, -1);
    int unit_a, unit_b;
    int64_t a_sig64, b_sig64;
    int a_scale, b_scale;
    quantity_extract(a, &unit_a, &a_sig64, &a_scale);
    quantity_extract(b, &unit_b, &b_sig64, &b_scale);
    int role_a = quantity_role(a, unit_a);
    int role_b = quantity_role(b, unit_b);
    int a_point = role_a == W_QUANTITY_ROLE_POINT;
    int b_point = role_b == W_QUANTITY_ROLE_POINT;
    int a_delta = role_a == W_QUANTITY_ROLE_DELTA;
    int b_delta = role_b == W_QUANTITY_ROLE_DELTA;
    WValue result_origin = quantity_combined_origin(a, b);
    int result_unit = unit_a;
    if (a_point && b_point && quantity_is_temperature_point(unit_a) && quantity_is_temperature_point(unit_b)) {
        if (unit_a != unit_b && !quantity_convert(&b_sig64, &b_scale, unit_b, unit_a))
            die("cannot convert absolute temperature");
        result_unit = quantity_delta_unit_for_point(unit_a);
        if (result_unit < 0) die("missing temperature-difference unit");
    } else if (a_point && b_delta && quantity_is_temperature_point(unit_a) && quantity_is_temperature_delta(unit_b)) {
        if (!quantity_convert_interval(&b_sig64, &b_scale, unit_b, unit_a))
            die("cannot convert temperature difference");
    } else if (!a_point && b_point) {
        die("cannot subtract an absolute temperature from a temperature difference");
    } else if (unit_a != unit_b && !quantity_convert(&b_sig64, &b_scale, unit_b, unit_a)) {
        const char *na = unit_names[unit_a] ? unit_names[unit_a] : "?";
        const char *nb = unit_names[unit_b] ? unit_names[unit_b] : "?";
        dief("cannot subtract %s and %s (dimension mismatch)", na, nb);
    }
    __int128 a_sig = a_sig64, b_sig = b_sig64;
    decimal_align(&a_sig, &a_scale, &b_sig, &b_scale);
    int64_t result_sig = (int64_t)(a_sig - b_sig);
    if (a_point && b_point && quantity_is_temperature_point(unit_a) && quantity_is_temperature_point(unit_b) &&
        !quantity_convert_interval(&result_sig, &a_scale, unit_a, result_unit))
        die("cannot convert resulting temperature difference");
    int result_role = 0;
    if (a_point && b_point) result_role = W_QUANTITY_ROLE_DELTA;
    else if (a_point) result_role = W_QUANTITY_ROLE_POINT;
    else if (a_delta || b_delta) result_role = W_QUANTITY_ROLE_DELTA;
    return quantity_result_with_role(w_quantity(result_unit, result_sig, a_scale), result_role, result_origin);
}

/* ---- Dimensional algebra: quantity × quantity, quantity ÷ quantity ----
 * Dimension vectors add (mul) or subtract (div); the result unit is the
 * first table unit whose dimension AND exact factor match the product
 * (10 ft * 10 ft = 100 ft²). A dim-match with a different factor converts
 * (m × m read back in cm² works); a fully-zero dimension collapses to a
 * plain decimal (10 ft / 5 ft = 2). */
static int64_t w_gcd64(int64_t a, int64_t b) {
    while (b) { int64_t t = a % b; a = b; b = t; }
    return a < 0 ? -a : a;
}

static int quantity_dims_equal2(const int8_t *x, const int8_t *y) {
    for (int i = 0; i < 8; i++)
        if (x[i] != y[i]) return 0;
    return 1;
}

static int quantity_signature_equal(const int8_t *dim, int custom_id, int custom_exp,
                                    const WUnitInfo *u) {
    return quantity_dims_equal2(dim, u->dim) && custom_id == u->custom_id &&
           custom_exp == u->custom_exp;
}

static int quantity_factor_equal(int64_t an, int64_t ad, int as,
                                 int64_t bn, int64_t bd, int bs) {
    long double a = ((long double)an / (long double)ad) * powl(10.0L, as);
    long double b = ((long double)bn / (long double)bd) * powl(10.0L, bs);
    if (a == b) return 1;
    long double mag = fmaxl(fabsl(a), fabsl(b));
    return mag != 0.0L && fabsl(a - b) <= mag * 1e-15L;
}

/* Reduced rational product an/ad × bn/bd → rn/rd; 0 on int64 overflow. */
static int rat_mul64(int64_t an, int64_t ad, int64_t bn, int64_t bd,
                     int64_t *rn, int64_t *rd) {
    int64_t g1 = w_gcd64(an, bd), g2 = w_gcd64(bn, ad);
    if (g1) { an /= g1; bd /= g1; }
    if (g2) { bn /= g2; ad /= g2; }
    __int128 n = (__int128)an * bn, d = (__int128)ad * bd;
    if (n > INT64_MAX || n < INT64_MIN || d > INT64_MAX || d < INT64_MIN) return 0;
    *rn = (int64_t)n; *rd = (int64_t)d;
    return 1;
}

/* value ← value × num/den with decimal scale extension (round half-up
 * after 12 extra digits). Same contract as quantity_convert's tail. */
static int apply_rational(int64_t *sig, int *scale, int64_t num, int64_t den) {
    return decimal_quotient_i128((__int128)(*sig) * num, den, 1, sig, scale);
}

/* Synthesize (or find) a custom unit for an unnamed dimension/factor combo.
 * The display name is built from SI base symbols in conventional order
 * (kg·m/s, m/s², …); the dim/factor lands in unit_info so later arithmetic
 * keeps converting. Returns the unit id, or -1 if the custom region is full
 * or the name overflows. */
static int quantity_synth_compound(const int8_t *dim, int custom_id, int custom_exp,
                                   int64_t fn, int64_t fd, int factor_scale) {
    /* Reuse an existing custom entry with the same dim+factor. */
    for (int i = W_UNIT_CUSTOM_BASE; i < W_UNIT_CAPACITY; i++) {
        if (!unit_names[i] || unit_info[i].den == 0) continue;
        if (!quantity_signature_equal(dim, custom_id, custom_exp, &unit_info[i])) continue;
        if (quantity_factor_equal(fn, fd, factor_scale, unit_info[i].num,
                                  unit_info[i].den, unit_info[i].factor_scale))
            return i;
    }
    /* Conventional display order: mass, length, time, current, temp,
     * substance, luminosity, information. dim[] is indexed
     * [length, mass, time, A, K, mol, cd, bit]. */
    static const int order[8] = {1, 0, 2, 3, 4, 5, 6, 7};
    static const char *base_syms[8] = {"m", "kg", "s", "A", "K", "mol", "cd", "b"};
    char name[64];
    int pos = 0, wrote_num = 0;
    if (custom_id > 0 && custom_exp > 0 &&
        custom_id < (int)(sizeof(custom_dimension_names) / sizeof(custom_dimension_names[0]))) {
        pos += snprintf(name + pos, sizeof(name) - pos, "%s", custom_dimension_names[custom_id]);
        if (custom_exp != 1) pos += snprintf(name + pos, sizeof(name) - pos, "^%d", custom_exp);
        wrote_num = 1;
    }
    for (int oi = 0; oi < 8; oi++) {
        int axis = order[oi];
        int e = dim[axis];
        if (e <= 0) continue;
        if (wrote_num && pos < 60) { memcpy(name + pos, "\xc2\xb7", 2); pos += 2; } /* · */
        pos += snprintf(name + pos, sizeof(name) - pos, "%s", base_syms[axis]);
        if (e == 2 && pos < 60) { memcpy(name + pos, "\xc2\xb2", 2); pos += 2; }
        else if (e == 3 && pos < 60) { memcpy(name + pos, "\xc2\xb3", 2); pos += 2; }
        else if (e > 3) pos += snprintf(name + pos, sizeof(name) - pos, "^%d", e);
        wrote_num = 1;
    }
    if (custom_id > 0 && custom_exp < 0 && pos < 60 &&
        custom_id < (int)(sizeof(custom_dimension_names) / sizeof(custom_dimension_names[0]))) {
        pos += snprintf(name + pos, sizeof(name) - pos, "/%s", custom_dimension_names[custom_id]);
        if (custom_exp != -1) pos += snprintf(name + pos, sizeof(name) - pos, "^%d", -custom_exp);
    }
    if (!wrote_num && pos < 60) name[pos++] = '1';
    for (int oi = 0; oi < 8; oi++) {
        int axis = order[oi];
        int e = dim[axis];
        if (e >= 0) continue;
        e = -e;
        if (pos < 60) name[pos++] = '/';
        pos += snprintf(name + pos, sizeof(name) - pos, "%s", base_syms[axis]);
        if (e == 2 && pos < 60) { memcpy(name + pos, "\xc2\xb2", 2); pos += 2; }
        else if (e == 3 && pos < 60) { memcpy(name + pos, "\xc2\xb3", 2); pos += 2; }
        else if (e > 3) pos += snprintf(name + pos, sizeof(name) - pos, "^%d", e);
    }
    if (pos >= 60) return -1;
    name[pos] = '\0';
    for (int i = W_UNIT_CUSTOM_BASE; i < W_UNIT_CAPACITY; i++) {
        if (unit_names[i]) continue;
        w_register_unit(i, name);
        unit_info[i].num = fn;
        unit_info[i].den = fd;
        unit_info[i].factor_scale = factor_scale;
        unit_info[i].custom_id = custom_id;
        unit_info[i].custom_exp = custom_exp;
        memcpy(unit_info[i].dim, dim, 8);
        return i;
    }
    return -1;
}

static WValue quantity_combine(WValue a, WValue b, int divide) {
    int unit_a, unit_b, a_scale, b_scale;
    int64_t a_sig, b_sig;
    quantity_extract(a, &unit_a, &a_sig, &a_scale);
    quantity_extract(b, &unit_b, &b_sig, &b_scale);
    if (quantity_role(a, unit_a) == W_QUANTITY_ROLE_POINT ||
        quantity_role(b, unit_b) == W_QUANTITY_ROLE_POINT)
        die("cannot multiply or divide a point; subtract points or operate on a delta");
    const char *na = unit_names[unit_a] ? unit_names[unit_a] : "?";
    const char *nb = unit_names[unit_b] ? unit_names[unit_b] : "?";
    const WUnitInfo *fa = &unit_info[unit_a], *fb = &unit_info[unit_b];
    const char *opname = divide ? "divide" : "multiply";
    if (fa->den == 0 || fb->den == 0)
        dief("cannot %s %s and %s (no conversion info)", opname, na, nb);
    if (fa->off_num != 0 || fb->off_num != 0)
        dief("cannot %s an affine absolute temperature; convert it to kelvin or use a temperature difference", opname);

    int8_t dim[8];
    int all_zero = 1;
    for (int i = 0; i < 8; i++) {
        dim[i] = (int8_t)(divide ? fa->dim[i] - fb->dim[i] : fa->dim[i] + fb->dim[i]);
        if (dim[i]) all_zero = 0;
    }
    int custom_id = 0, custom_exp = 0;
    if (fa->custom_id && fb->custom_id && fa->custom_id != fb->custom_id)
        dief("cannot %s %s and %s (multiple custom dimensions)", opname, na, nb);
    if (fa->custom_id) {
        custom_id = fa->custom_id;
        custom_exp = fa->custom_exp;
    }
    if (fb->custom_id) {
        custom_id = fb->custom_id;
        custom_exp += divide ? -fb->custom_exp : fb->custom_exp;
    }
    if (custom_exp == 0) custom_id = 0;
    if (custom_id != 0) all_zero = 0;
    int64_t fn, fd;
    int ok = divide ? rat_mul64(fa->num, fa->den, fb->den, fb->num, &fn, &fd)
                    : rat_mul64(fa->num, fa->den, fb->num, fb->den, &fn, &fd);
    if (!ok) dief("factor overflow combining %s and %s", na, nb);
    int factor_scale = fa->factor_scale + (divide ? -fb->factor_scale : fb->factor_scale);

    int64_t sig;
    int scale;
    if (divide) {
        if (b_sig == 0) die_as("ZeroDivisionError", "division by zero");
        sig = a_sig;
        scale = a_scale - b_scale;
        if (!apply_rational(&sig, &scale, 1, b_sig))
            dief("quantity overflow dividing %s by %s", na, nb);
    } else {
        __int128 p = (__int128)a_sig * b_sig;
        scale = a_scale + b_scale;
        while (p != 0 && p % 10 == 0 && scale < 0) { p /= 10; scale++; }
        decimal_narrow_i128(&p, &scale);
        sig = (int64_t)p;
    }

    if (all_zero) {
        /* Dimensionless ratio: apply the residual factor, return a Decimal. */
        scale += factor_scale;
        if (!apply_rational(&sig, &scale, fn, fd))
            dief("quantity overflow combining %s and %s", na, nb);
        return w_decimal(sig, scale);
    }

    /* Exact factor match first (10 ft × 10 ft → ft², not a converted m²). */
    for (int i = 0; i < W_UNIT_CAPACITY; i++) {
        if (!unit_names[i] || unit_info[i].den == 0 || unit_info[i].off_num != 0) continue;
        if (!quantity_signature_equal(dim, custom_id, custom_exp, &unit_info[i])) continue;
        if (quantity_factor_equal(fn, fd, factor_scale, unit_info[i].num,
                                  unit_info[i].den, unit_info[i].factor_scale))
            return w_quantity(i, sig, scale);
    }
    /* Coherent unit next (m³ before fl oz so rational decimal factors stay exact). */
    for (int i = 0; i < W_UNIT_CAPACITY; i++) {
        if (!unit_names[i] || unit_info[i].den == 0 || unit_info[i].off_num != 0) continue;
        if (unit_info[i].num != 1 || unit_info[i].den != 1 || unit_info[i].factor_scale != 0) continue;
        if (!quantity_signature_equal(dim, custom_id, custom_exp, &unit_info[i])) continue;
        int64_t s2 = sig;
        int sc2 = scale + factor_scale;
        if (apply_rational(&s2, &sc2, fn, fd))
            return w_quantity(i, s2, sc2);
    }
    /* Any same-dimension unit, converting the factor ratio into it. */
    for (int i = 0; i < W_UNIT_CAPACITY; i++) {
        if (!unit_names[i] || unit_info[i].den == 0 || unit_info[i].off_num != 0) continue;
        if (!quantity_signature_equal(dim, custom_id, custom_exp, &unit_info[i])) continue;
        int64_t cn, cd;
        if (!rat_mul64(fn, fd, unit_info[i].den, unit_info[i].num, &cn, &cd)) continue;
        int64_t s2 = sig;
        int sc2 = scale + factor_scale - unit_info[i].factor_scale;
        if (apply_rational(&s2, &sc2, cn, cd))
            return w_quantity(i, s2, sc2);
    }
    /* No named unit — synthesize an anonymous compound (kg·m/s) in the
     * custom region so chained arithmetic carries its dimension until it
     * lands on a named one: (kg × m/s) × m/s ends at J. */
    int synth = quantity_synth_compound(dim, custom_id, custom_exp, fn, fd, factor_scale);
    if (synth >= 0) return w_quantity(synth, sig, scale);
    dief("no unit for the %s of %s and %s", divide ? "quotient" : "product", na, nb);
    return W_NIL;
}

WValue w_quantity_mul(WValue a, WValue b) { return quantity_combine(a, b, 0); }
WValue w_quantity_div(WValue a, WValue b) { return quantity_combine(a, b, 1); }

/* Snap a raw double into decimal sig/scale at the same 12 significant
 * digits decimal division carries. Shared by `| unit` attachment and the
 * scalar-arithmetic rows that admit a Float into the quantity domain —
 * the value goes imprecise at this boundary, but stays a quantity. */
static int double_to_sig_scale(double d, int64_t *sig, int *scale) {
    char dbuf[40];
    if (!isfinite(d)) return 0;
    snprintf(dbuf, sizeof dbuf, "%.12g", d);
    return parse_sig_scale_cstr(dbuf, sig, scale);
}

/* ---- π-quantities ----
 * `2π` lexes through the unit machinery (custom-unit fall-through, name
 * "π"): an exact decimal multiple of π. Unlike a dimensioned quantity it
 * is a NUMBER, so evaluation boundaries — Math.*, mixed +/- with plain
 * numerics, order comparisons, to_f — collapse it to coeff·π as an
 * (imprecise) double. Multiplicative scaling stays exact and keeps the
 * unit, so `2π * 50 * t` reaches Math.sin as an exact multiple of π. */
static int quantity_pi_parts(WValue v, int64_t *sig, int *scale) {
    int unit;
    if (!is_quantity_any(v)) return 0;
    quantity_extract(v, &unit, sig, scale);
    if (unit < 0 || unit >= W_UNIT_CAPACITY || !unit_names[unit]) return 0;
    if (strcmp(unit_names[unit], "\xcf\x80") == 0) return 1;      /* π */
    if (strcmp(unit_names[unit], "\xcf\x84") == 0) {              /* τ = 2π */
        if (*sig > INT64_MAX / 2 || *sig < INT64_MIN / 2) return 0;
        *sig *= 2;
        return 1;
    }
    return 0;
}

static double quantity_pi_double(int64_t sig, int scale) {
    return (double)sig * pow(10.0, (double)scale) * M_PI;
}

/* Quantity#to_f — evaluate to an imprecise Float: π-quantities collapse
 * to coeff·π, dimensioned quantities to their bare numeric value. */
WValue w_quantity_to_f(WValue quantity) {
    int unit, scale;
    int64_t sig;
    if (!is_quantity_any(quantity)) return W_NIL;
    if (quantity_pi_parts(quantity, &sig, &scale))
        return w_float(quantity_pi_double(sig, scale));
    quantity_extract(quantity, &unit, &sig, &scale);
    return w_float((double)sig * pow(10.0, (double)scale));
}

/* ---- Conversion pipe: `5 kg + 3 kg | lb(2)` ----
 * Convert a quantity into the named unit, optionally rounding half-up to
 * `digits` decimals (digits < 0 = no rounding). The unit arrives as its
 * NAME — both front-ends intercept `| unit` / `| unit(d)` syntactically. */
WValue w_quantity_pipe(WValue q, WValue unit_name_v, WValue digits_v) {
    /* Array lhs (`%d[1.0 2.5] | m/s`): map elementwise — decimals/ints
     * attach the unit, quantities convert. Boxed arrays only; a typed
     * buffer has no per-element WValues to rebuild as quantities. */
    if (w_is_array(q)) {
        WArray *a = w_as_array(q);
        if (a->ebits != 65)
            dief("| unit conversion: expected a boxed array, not a typed buffer");
        WValue *slots = (WValue *)a->slots;
        WValue out = w_array_new_empty();
        for (int64_t i = 0; i < a->size; i++)
            out = w_array_push(out, w_quantity_pipe(slots[a->start + i], unit_name_v, digits_v));
        return out;
    }
    const char *uname = as_str(unit_name_v);
    int target = unit_lookup_id(uname);
    if (target < 0) dief("unknown unit in | conversion: %s", uname);
    int unit, scale;
    int64_t sig;
    if (is_quantity_any(q)) {
        quantity_extract(q, &unit, &sig, &scale);
        if (!quantity_convert(&sig, &scale, unit, target))
            dief("cannot convert %s to %s (dimension mismatch)",
                 unit_names[unit] ? unit_names[unit] : "?", uname);
    } else if (is_decimal_any(q)) {
        /* Bare number | unit — nothing to convert from; attach the unit. */
        decimal_extract(q, &sig, &scale);
    } else if (w_is_int(q)) {
        sig = w_as_int(q);
        scale = 0;
    } else if (w_is_double(q)) {
        /* Raw float (e.g. a sqrt result) — snap, then attach. */
        if (!double_to_sig_scale(w_as_double(q), &sig, &scale))
            dief("| unit conversion: non-finite float");
    } else {
        dief("| unit conversion expects a quantity");
    }
    int64_t digits = w_is_int(digits_v) ? w_as_int(digits_v) : -1;
    if (digits >= 0 && scale < -digits) {
        int64_t div = 1;
        for (int k = scale; k < -digits; k++) div *= 10;
        int64_t rem = sig % div;
        sig /= div;
        scale = (int)-digits;
        int64_t half = div / 2;
        if (rem >= half) sig++;
        else if (-rem >= half) sig--;
        while (sig != 0 && sig % 10 == 0 && scale < 0) { sig /= 10; scale++; }
    }
    return w_quantity(target, sig, scale);
}

WValue w_quantity_mul_scalar(WValue quantity, WValue scalar) {
    int unit;
    int64_t q_sig64;
    int q_scale;
    quantity_extract(quantity, &unit, &q_sig64, &q_scale);
    int role = quantity_role(quantity, unit);
    if (role == W_QUANTITY_ROLE_POINT)
        die("cannot multiply a point; subtract points or operate on a delta");
    if (unit_info[unit].off_num != 0)
        die("cannot multiply an affine absolute temperature; convert it to kelvin or use a temperature difference");
    __int128 q_sig = q_sig64;
    if (w_is_int(scalar)) {
        q_sig *= w_as_int(scalar);
    } else if (is_decimal_any(scalar)) {
        int64_t s_sig; int s_scale;
        decimal_extract(scalar, &s_sig, &s_scale);
        q_sig *= s_sig;
        q_scale += s_scale;
    } else if (w_is_double(scalar)) {
        /* Float scalar joins the decimal domain the way `| unit` does:
         * snapped to 12 significant digits. Imprecise, but stays a unit. */
        int64_t s_sig; int s_scale;
        if (!double_to_sig_scale(w_as_double(scalar), &s_sig, &s_scale))
            die("cannot multiply quantity by non-finite float");
        q_sig *= s_sig;
        q_scale += s_scale;
    } else {
        die("cannot multiply quantity by non-numeric");
    }
    decimal_narrow_i128(&q_sig, &q_scale);
    return quantity_result_with_role(w_quantity(unit, (int64_t)q_sig, q_scale), role, quantity_origin_value(quantity));
}

WValue w_quantity_div_scalar(WValue quantity, WValue scalar) {
    int unit;
    int64_t q_sig64;
    int q_scale;
    quantity_extract(quantity, &unit, &q_sig64, &q_scale);
    int role = quantity_role(quantity, unit);
    if (role == W_QUANTITY_ROLE_POINT)
        die("cannot divide a point; subtract points or operate on a delta");
    if (unit_info[unit].off_num != 0)
        die("cannot divide an affine absolute temperature; convert it to kelvin or use a temperature difference");
    int64_t s_sig; int s_scale;
    if (w_is_int(scalar)) {
        s_sig = w_as_int(scalar);
        s_scale = 0;
    } else if (w_is_double(scalar)) {
        /* Float divisor: snap to 12 significant digits, like `| unit`. */
        if (!double_to_sig_scale(w_as_double(scalar), &s_sig, &s_scale))
            die("cannot divide quantity by non-finite float");
    } else if (is_decimal_any(scalar)) {
        decimal_extract(scalar, &s_sig, &s_scale);
    } else {
        die("cannot divide quantity by non-numeric");
        return W_NIL;
    }
    if (s_sig == 0) die_as("ZeroDivisionError", "division by zero");
    int64_t result_sig;
    int result_scale = q_scale - s_scale;
    if (!decimal_quotient_i128(q_sig64, s_sig, 0, &result_sig, &result_scale))
        die("quantity overflow dividing by scalar");
    return quantity_result_with_role(w_quantity(unit, result_sig, result_scale), role, quantity_origin_value(quantity));
}

static double quantity_unit_factor_double(const WUnitInfo *u) {
    return ((double)u->num / (double)u->den) * pow(10.0, (double)u->factor_scale);
}

static double quantity_unit_offset_double(const WUnitInfo *u) {
    if (u->off_den == 0) return 0.0;
    return (double)u->off_num / (double)u->off_den;
}

static int quantity_dim_is(const WUnitInfo *u, int length, int mass, int time, int temperature) {
    int expected[8] = {length, mass, time, 0, temperature, 0, 0, 0};
    for (int i = 0; i < 8; i++) if (u->dim[i] != expected[i]) return 0;
    return u->custom_id == 0 && u->custom_exp == 0;
}

static int quantity_dim_is_frequency(const WUnitInfo *u) {
    if (u->dim[2] != -1) return 0;
    for (int i = 0; i < 8; i++) if (i != 2 && u->dim[i] != 0) return 0;
    if (u->custom_id <= 0 || u->custom_exp != 1) return 0;
    return strcmp(custom_dimension_names[u->custom_id], "cycle") == 0;
}

WValue w_quantity_equivalent(WValue quantity, WValue target_unit_v, WValue equivalence_v) {
    int source_unit, source_scale;
    int64_t source_sig;
    quantity_extract(quantity, &source_unit, &source_sig, &source_scale);
    const char *target_name = as_str(target_unit_v);
    const char *kind = as_str(equivalence_v);
    int target_unit = unit_lookup_id(target_name);
    if (target_unit < 0) dief("unknown target unit for equivalence: %s", target_name);
    const WUnitInfo *source = &unit_info[source_unit];
    const WUnitInfo *target = &unit_info[target_unit];
    double source_raw = (double)source_sig * pow(10.0, (double)source_scale);
    double source_si = source_raw * quantity_unit_factor_double(source) + quantity_unit_offset_double(source);
    double target_si = 0.0;

    int source_mass = quantity_dim_is(source, 0, 1, 0, 0);
    int target_mass = quantity_dim_is(target, 0, 1, 0, 0);
    int source_energy = quantity_dim_is(source, 2, 1, -2, 0);
    int target_energy = quantity_dim_is(target, 2, 1, -2, 0);
    int source_length = quantity_dim_is(source, 1, 0, 0, 0);
    int target_length = quantity_dim_is(target, 1, 0, 0, 0);
    int source_frequency = quantity_dim_is_frequency(source);
    int target_frequency = quantity_dim_is_frequency(target);
    int source_temperature = quantity_dim_is(source, 0, 0, 0, 1);
    int target_temperature = quantity_dim_is(target, 0, 0, 0, 1);

    if (strcmp(kind, "mass_energy") == 0) {
        const double c2 = 299792458.0 * 299792458.0;
        if (source_mass && target_energy) target_si = source_si * c2;
        else if (source_energy && target_mass) target_si = source_si / c2;
        else die("mass_energy equivalence requires mass and energy");
    } else if (strcmp(kind, "spectral") == 0) {
        const double c = 299792458.0;
        const double h = 6.62607015e-34;
        if (source_length && target_frequency) target_si = c / source_si;
        else if (source_frequency && target_length) target_si = c / source_si;
        else if (source_length && target_energy) target_si = h * c / source_si;
        else if (source_energy && target_length) target_si = h * c / source_si;
        else if (source_frequency && target_energy) target_si = h * source_si;
        else if (source_energy && target_frequency) target_si = source_si / h;
        else die("spectral equivalence requires length, frequency, or photon energy");
    } else if (strcmp(kind, "thermal") == 0) {
        const double kb = 1.380649e-23;
        if (source_temperature && target_energy) target_si = source_si * kb;
        else if (source_energy && target_temperature) target_si = source_si / kb;
        else die("thermal equivalence requires temperature and energy");
    } else {
        dief("unknown physical equivalence: %s", kind);
    }

    double target_raw = (target_si - quantity_unit_offset_double(target)) /
                        quantity_unit_factor_double(target);
    char number[64];
    snprintf(number, sizeof(number), "%.15g", target_raw);
    int64_t sig;
    int scale;
    if (!parse_sig_scale_cstr(number, &sig, &scale)) die("failed to represent equivalence result");
    return w_quantity(target_unit, sig, scale);
}

W_RT_INTERNAL const char *w_rt_unit_name(int unit) {
    return (unit >= 0 && unit < W_UNIT_CAPACITY) ? unit_names[unit] : NULL;
}
W_RT_INTERNAL int w_rt_unit_lookup_id(const char *name) {
    return unit_lookup_id(name);
}
W_RT_INTERNAL int w_rt_parse_sig_scale_cstr(const char *s, int64_t *sig_out, int *scale_out) {
    return parse_sig_scale_cstr(s, sig_out, scale_out);
}
W_RT_INTERNAL int w_rt_quantity_convert(int64_t *sig, int *scale, int from_unit, int to_unit) {
    return quantity_convert(sig, scale, from_unit, to_unit);
}
W_RT_INTERNAL int w_rt_quantity_pi_parts(WValue v, int64_t *sig, int *scale) {
    return quantity_pi_parts(v, sig, scale);
}
W_RT_INTERNAL double w_rt_quantity_pi_double(int64_t sig, int scale) {
    return quantity_pi_double(sig, scale);
}
W_RT_INTERNAL int w_rt_double_to_sig_scale(double d, int64_t *sig, int *scale) {
    return double_to_sig_scale(d, sig, scale);
}
