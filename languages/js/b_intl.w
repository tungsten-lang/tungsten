# runtime/b_intl — ECMA-402 Internationalization API (Part 1):
# Core BCP 47 / Unicode Locale ID validation & canonicalization, ResolveLocale,
# Intl namespace (getCanonicalLocales, supportedValuesOf), Intl.Locale (+ Locale-info),
# Intl.Collator, Intl.PluralRules, Intl.RelativeTimeFormat, Intl.ListFormat,
# Intl.DisplayNames, and Intl.Segmenter.

in JS

-> js_math_floor(n)
  Math.floor(n)

-> js_bi_from_int(n)
  JS:BigIntValue.new(n ## int)

-> js_bi_from_num(n)
  return JS:BigIntValue.new(0 ## int) if n != n || n == ~0.0
  neg = n < ~0.0
  a = neg ? ~0.0 - n : n
  if a < ~9007199254740992.0
    v = a.to_i ## int
    return JS:BigIntValue.new(neg ? (0 ## int) - v : v)
  # Exact IEEE 754 binary64 integer decoding (zero decimal rounding error!)
  bits = (wvalue_bits(a) ## i64) - 281474976710656
  exp = ((bits >> 52) & 2047) - 1023
  mant = (bits & 4503599627370495) | 4503599627370496
  shift = exp - 52
  v = mant ## int
  if shift > 0
    v = v << shift
  elsif shift < 0
    v = v >> (0 - shift)
  JS:BigIntValue.new(neg ? (0 ## int) - v : v)

-> js_parse_int_str(s)
  ei = s.index("e")
  ei = s.index("E") if ei == nil
  if ei != nil
    mant = s.slice(0, ei)
    exp = s.slice(ei + 1, s.size - ei - 1).to_i
    di = mant.index(".")
    if di != nil
      frac = mant.size - di - 1
      mant = mant.slice(0, di) + mant.slice(di + 1, frac)
      exp -= frac
    v = mant.to_i ## int
    k = 0
    while k < exp
      v = v * (10 ## int)
      k += 1
    return v
  s.to_i ## int

-> js_bi_add(a, b)
  JS:BigIntValue.new(a.v + b.v)

-> js_bi_mul(a, b)
  JS:BigIntValue.new(a.v * b.v)

# ---- Shared constants & ASCII helpers ----

INTL_FALLBACK_SYM = JS:Symbol.new("IntlLegacyConstructedSymbol")

INTL_UNITS = [
  "acre", "bit", "byte", "celsius", "centimeter", "day", "degree", "fahrenheit",
  "fluid-ounce", "foot", "gallon", "gigabit", "gigabyte", "gram", "hectare",
  "hour", "inch", "kilobit", "kilobyte", "kilogram", "kilometer", "liter",
  "megabit", "megabyte", "meter", "microsecond", "mile", "mile-scandinavian",
  "milliliter", "millimeter", "millisecond", "minute", "month", "nanosecond",
  "ounce", "percent", "petabyte", "pound", "second", "stone", "terabit",
  "terabyte", "week", "yard", "year"
]

INTL_UNITS_SET = {}
INTL_UNITS.each ->(u) INTL_UNITS_SET[u] = true

INTL_WEEKDAY_MAP = {
  "0" => "sun", "1" => "mon", "2" => "tue", "3" => "wed",
  "4" => "thu", "5" => "fri", "6" => "sat", "7" => "sun"
}

INTL_WEEKDAY_NUM = {
  "mon" => 1, "tue" => 2, "wed" => 3, "thu" => 4,
  "fri" => 5, "sat" => 6, "sun" => 7
}

# Exact 16 calendars required by ECMA-402 / intl-era-monthcode / Temporal
INTL_ECMA_CALENDARS = [
  "buddhist", "chinese", "coptic", "dangi", "ethioaa", "ethiopic",
  "gregory", "hebrew", "indian", "islamic-civil", "islamic-tbla",
  "islamic-umalqura", "iso8601", "japanese", "persian", "roc"
]

# UTS 35 / CLDR supplementalMetadata tag, language, region, variant, subdivision & transform aliases
INTL_TAG_MAPPINGS = {
  "art-lojban" => "jbo",
  "cel-gaulish" => "xtg",
  "zh-guoyu" => "zh",
  "zh-hakka" => "hak",
  "zh-xiang" => "hsn"
}

INTL_LANG_MAPPINGS = {
  "aam" => "aas", "aar" => "aa", "abk" => "ab", "adp" => "dz", "afr" => "af",
  "aju" => "jrb", "aka" => "ak", "alb" => "sq", "als" => "sq", "amh" => "am",
  "ara" => "ar", "arb" => "ar", "arg" => "an", "arm" => "hy", "asd" => "snz",
  "asm" => "as", "aue" => "ktz", "ava" => "av", "ave" => "ae", "aym" => "ay",
  "ayr" => "ay", "ayx" => "nun", "aze" => "az", "azj" => "az", "bak" => "ba",
  "bam" => "bm", "baq" => "eu", "bcc" => "bal", "bcl" => "bik", "bel" => "be",
  "ben" => "bn", "bgm" => "bcg", "bh" => "bho", "bih" => "bho", "bis" => "bi",
  "bjd" => "drl", "bod" => "bo", "bos" => "bs", "bre" => "br", "bul" => "bg",
  "bur" => "my", "bxk" => "luy", "bxr" => "bua", "cat" => "ca", "ccq" => "rki",
  "ces" => "cs", "cha" => "ch", "che" => "ce", "chi" => "zh", "chu" => "cu",
  "chv" => "cv", "cjr" => "mom", "cka" => "cmr", "cld" => "syr", "cmk" => "xch",
  "cmn" => "zh", "cor" => "kw", "cos" => "co", "coy" => "pij", "cqu" => "quh",
  "cre" => "cr", "cwd" => "cr", "cym" => "cy", "cze" => "cs", "dan" => "da",
  "deu" => "de", "dgo" => "doi", "dhd" => "mwr", "dik" => "din", "diq" => "zza",
  "dit" => "dif", "div" => "dv", "drh" => "mn", "dut" => "nl", "dzo" => "dz",
  "ekk" => "et", "ell" => "el", "emk" => "man", "eng" => "en", "epo" => "eo",
  "esk" => "ik", "est" => "et", "eus" => "eu", "ewe" => "ee", "fao" => "fo",
  "fas" => "fa", "fat" => "ak", "fij" => "fj", "fin" => "fi", "fra" => "fr",
  "fre" => "fr", "fry" => "fy", "fuc" => "ff", "ful" => "ff", "gav" => "dev",
  "gaz" => "om", "gbo" => "grb", "geo" => "ka", "ger" => "de", "gfx" => "vaj",
  "ggn" => "gvr", "gla" => "gd", "gle" => "ga", "glg" => "gl", "glv" => "gv",
  "gno" => "gon", "gre" => "el", "grn" => "gn", "gti" => "nyc", "gug" => "gn",
  "guj" => "gu", "guv" => "duz", "gya" => "gba", "hat" => "ht", "hau" => "ha",
  "hdn" => "hai", "hea" => "hmn", "heb" => "he", "her" => "hz", "him" => "srx",
  "hin" => "hi", "hmo" => "ho", "hrr" => "jal", "hrv" => "hr", "hun" => "hu",
  "hye" => "hy", "ibi" => "opa", "ibo" => "ig", "ice" => "is", "ido" => "io",
  "iii" => "ii", "ike" => "iu", "iku" => "iu", "ile" => "ie", "ilw" => "gal",
  "in" => "id", "ina" => "ia", "ind" => "id", "ipk" => "ik", "isl" => "is",
  "ita" => "it", "iw" => "he", "jav" => "jv", "jeg" => "oyb", "ji" => "yi",
  "jpn" => "ja", "jw" => "jv", "kal" => "kl", "kan" => "kn", "kas" => "ks",
  "kat" => "ka", "kau" => "kr", "kaz" => "kk", "kgc" => "tdf", "kgh" => "kml",
  "khk" => "mn", "khm" => "km", "kik" => "ki", "kin" => "rw", "kir" => "ky",
  "kmr" => "ku", "knc" => "kr", "kng" => "kg", "knn" => "kok", "koj" => "kwv",
  "kom" => "kv", "kon" => "kg", "kor" => "ko", "kpv" => "kv", "krm" => "bmf",
  "ktr" => "dtp", "kua" => "kj", "kur" => "ku", "kvs" => "gdj", "kwq" => "yam",
  "kxe" => "tvd", "kzj" => "dtp", "kzt" => "dtp", "lao" => "lo", "lat" => "la",
  "lav" => "lv", "lbk" => "bnc", "lii" => "raq", "lim" => "li", "lin" => "ln",
  "lit" => "lt", "llo" => "ngt", "lmm" => "rmx", "ltz" => "lb", "lub" => "lu",
  "lug" => "lg", "lvs" => "lv", "mac" => "mk", "mah" => "mh", "mal" => "ml",
  "mao" => "mi", "mar" => "mr", "may" => "ms", "meg" => "cir", "mhr" => "chm",
  "mkd" => "mk", "mlg" => "mg", "mlt" => "mt", "mnk" => "man", "mo" => "ro",
  "mol" => "ro", "mon" => "mn", "mri" => "mi", "msa" => "ms", "mst" => "mry",
  "mup" => "raj", "mwj" => "vaj", "mya" => "my", "myd" => "aog", "myt" => "mry",
  "nad" => "xny", "nau" => "na", "nav" => "nv", "nbl" => "nr", "ncp" => "kdz",
  "nde" => "nd", "ndo" => "ng", "nep" => "ne", "nld" => "nl", "nno" => "nn",
  "nns" => "nbr", "nnx" => "ngv", "no" => "nb", "nob" => "nb", "nor" => "nb",
  "npi" => "ne", "nts" => "pij", "nya" => "ny", "oci" => "oc", "ojg" => "oj",
  "oji" => "oj", "ori" => "or", "orm" => "om", "ory" => "or", "oss" => "os",
  "oun" => "vaj", "pan" => "pa", "pbu" => "ps", "pcr" => "adx", "per" => "fa",
  "pes" => "fa", "pli" => "pi", "plt" => "mg", "pmc" => "huw", "pmu" => "phr",
  "pnb" => "lah", "pol" => "pl", "por" => "pt", "ppa" => "bfy", "ppr" => "lcq",
  "pry" => "prt", "pus" => "ps", "puz" => "pub", "que" => "qu", "quz" => "qu",
  "rmy" => "rom", "roh" => "rm", "ron" => "ro", "rum" => "ro", "run" => "rn",
  "rus" => "ru", "sag" => "sg", "san" => "sa", "sca" => "hle", "scc" => "sr",
  "scr" => "hr", "sin" => "si", "skk" => "oyb", "slk" => "sk", "slo" => "sk",
  "slv" => "sl", "sme" => "se", "smo" => "sm", "sna" => "sn", "snd" => "sd",
  "som" => "so", "sot" => "st", "spa" => "es", "spy" => "kln", "sqi" => "sq",
  "src" => "sc", "srd" => "sc", "srp" => "sr", "ssw" => "ss", "sun" => "su",
  "swa" => "sw", "swe" => "sv", "swh" => "sw", "tah" => "ty", "tam" => "ta",
  "tat" => "tt", "tdu" => "dtp", "tel" => "te", "tgk" => "tg", "tgl" => "fil",
  "tha" => "th", "thc" => "tpo", "thx" => "oyb", "tib" => "bo", "tie" => "ras",
  "tir" => "ti", "tkk" => "twm", "tl" => "fil", "tlw" => "weo", "tmp" => "tyj",
  "tne" => "kak", "ton" => "to", "tsf" => "taj", "tsn" => "tn", "tso" => "ts",
  "ttq" => "tmh", "tuk" => "tk", "tur" => "tr", "tw" => "ak", "twi" => "ak",
  "uig" => "ug", "ukr" => "uk", "umu" => "del", "uok" => "ema", "urd" => "ur",
  "uzb" => "uz", "uzn" => "uz", "ven" => "ve", "vie" => "vi", "vol" => "vo",
  "wel" => "cy", "wln" => "wa", "wol" => "wo", "xba" => "cax", "xho" => "xh",
  "xia" => "acn", "xkh" => "waw", "xpe" => "kpe", "xsj" => "suj", "xsl" => "den",
  "ybd" => "rki", "ydd" => "yi", "yid" => "yi", "yma" => "lrr", "ymt" => "mtm",
  "yor" => "yo", "yos" => "zom", "yuu" => "yug", "zai" => "zap", "zha" => "za",
  "zho" => "zh", "zsm" => "ms", "zul" => "zu", "zyb" => "za"
}

INTL_COMPLEX_LANG_MAPPINGS = {
  "cnr" => ["sr", nil, "ME"],
  "drw" => ["fa", nil, "AF"],
  "hbs" => ["sr", "Latn", nil],
  "prs" => ["fa", nil, "AF"],
  "sh" => ["sr", "Latn", nil],
  "swc" => ["sw", nil, "CD"],
  "tnf" => ["fa", nil, "AF"]
}

INTL_REGION_MAPPINGS = {
  "004" => "AF", "008" => "AL", "010" => "AQ", "012" => "DZ", "016" => "AS",
  "020" => "AD", "024" => "AO", "028" => "AG", "031" => "AZ", "032" => "AR",
  "036" => "AU", "040" => "AT", "044" => "BS", "048" => "BH", "050" => "BD",
  "051" => "AM", "052" => "BB", "056" => "BE", "060" => "BM", "062" => "034",
  "064" => "BT", "068" => "BO", "070" => "BA", "072" => "BW", "074" => "BV",
  "076" => "BR", "084" => "BZ", "086" => "IO", "090" => "SB", "092" => "VG",
  "096" => "BN", "100" => "BG", "104" => "MM", "108" => "BI", "112" => "BY",
  "116" => "KH", "120" => "CM", "124" => "CA", "132" => "CV", "136" => "KY",
  "140" => "CF", "144" => "LK", "148" => "TD", "152" => "CL", "156" => "CN",
  "158" => "TW", "162" => "CX", "166" => "CC", "170" => "CO", "174" => "KM",
  "175" => "YT", "178" => "CG", "180" => "CD", "184" => "CK", "188" => "CR",
  "191" => "HR", "192" => "CU", "196" => "CY", "203" => "CZ", "204" => "BJ",
  "208" => "DK", "212" => "DM", "214" => "DO", "218" => "EC", "222" => "SV",
  "226" => "GQ", "230" => "ET", "231" => "ET", "232" => "ER", "233" => "EE",
  "234" => "FO", "238" => "FK", "239" => "GS", "242" => "FJ", "246" => "FI",
  "248" => "AX", "249" => "FR", "250" => "FR", "254" => "GF", "258" => "PF",
  "260" => "TF", "262" => "DJ", "266" => "GA", "268" => "GE", "270" => "GM",
  "275" => "PS", "276" => "DE", "278" => "DE", "280" => "DE", "288" => "GH",
  "292" => "GI", "296" => "KI", "300" => "GR", "304" => "GL", "308" => "GD",
  "312" => "GP", "316" => "GU", "320" => "GT", "324" => "GN", "328" => "GY",
  "332" => "HT", "334" => "HM", "336" => "VA", "340" => "HN", "344" => "HK",
  "348" => "HU", "352" => "IS", "356" => "IN", "360" => "ID", "364" => "IR",
  "368" => "IQ", "372" => "IE", "376" => "IL", "380" => "IT", "384" => "CI",
  "388" => "JM", "392" => "JP", "398" => "KZ", "400" => "JO", "404" => "KE",
  "408" => "KP", "410" => "KR", "414" => "KW", "417" => "KG", "418" => "LA",
  "422" => "LB", "426" => "LS", "428" => "LV", "430" => "LR", "434" => "LY",
  "438" => "LI", "440" => "LT", "442" => "LU", "446" => "MO", "450" => "MG",
  "454" => "MW", "458" => "MY", "462" => "MV", "466" => "ML", "470" => "MT",
  "474" => "MQ", "478" => "MR", "480" => "MU", "484" => "MX", "492" => "MC",
  "496" => "MN", "498" => "MD", "499" => "ME", "500" => "MS", "504" => "MA",
  "508" => "MZ", "512" => "OM", "516" => "NA", "520" => "NR", "524" => "NP",
  "528" => "NL", "531" => "CW", "533" => "AW", "534" => "SX", "535" => "BQ",
  "540" => "NC", "548" => "VU", "554" => "NZ", "558" => "NI", "562" => "NE",
  "566" => "NG", "570" => "NU", "574" => "NF", "578" => "NO", "580" => "MP",
  "581" => "UM", "583" => "FM", "584" => "MH", "585" => "PW", "586" => "PK",
  "591" => "PA", "598" => "PG", "600" => "PY", "604" => "PE", "608" => "PH",
  "612" => "PN", "616" => "PL", "620" => "PT", "624" => "GW", "626" => "TL",
  "630" => "PR", "634" => "QA", "638" => "RE", "642" => "RO", "643" => "RU",
  "646" => "RW", "652" => "BL", "654" => "SH", "659" => "KN", "660" => "AI",
  "662" => "LC", "663" => "MF", "666" => "PM", "670" => "VC", "674" => "SM",
  "678" => "ST", "682" => "SA", "686" => "SN", "688" => "RS", "690" => "SC",
  "694" => "SL", "702" => "SG", "703" => "SK", "704" => "VN", "705" => "SI",
  "706" => "SO", "710" => "ZA", "716" => "ZW", "720" => "YE", "724" => "ES",
  "728" => "SS", "729" => "SD", "732" => "EH", "736" => "SD", "740" => "SR",
  "744" => "SJ", "748" => "SZ", "752" => "SE", "756" => "CH", "760" => "SY",
  "762" => "TJ", "764" => "TH", "768" => "TG", "772" => "TK", "776" => "TO",
  "780" => "TT", "784" => "AE", "788" => "TN", "792" => "TR", "795" => "TM",
  "796" => "TC", "798" => "TV", "800" => "UG", "804" => "UA", "807" => "MK",
  "818" => "EG", "826" => "GB", "830" => "JE", "831" => "GG", "832" => "JE",
  "833" => "IM", "834" => "TZ", "840" => "US", "850" => "VI", "854" => "BF",
  "858" => "UY", "860" => "UZ", "862" => "VE", "876" => "WF", "882" => "WS",
  "886" => "YE", "887" => "YE", "891" => "RS", "894" => "ZM",
  "958" => "AA", "959" => "QM", "960" => "QN", "962" => "QP", "963" => "QQ",
  "964" => "QR", "965" => "QS", "966" => "QT", "967" => "EU", "968" => "QV",
  "969" => "QW", "970" => "QX", "971" => "QY", "972" => "QZ", "973" => "XA",
  "974" => "XB", "975" => "XC", "976" => "XD", "977" => "XE", "978" => "XF",
  "979" => "XG", "980" => "XH", "981" => "XI", "982" => "XJ", "983" => "XK",
  "984" => "XL", "985" => "XM", "986" => "XN", "987" => "XO", "988" => "XP",
  "989" => "XQ", "990" => "XR", "991" => "XS", "992" => "XT", "993" => "XU",
  "994" => "XV", "995" => "XW", "996" => "XX", "997" => "XY", "998" => "XZ",
  "999" => "ZZ",
  "BU" => "MM", "CS" => "RS", "CT" => "KI", "DD" => "DE", "DY" => "BJ",
  "FQ" => "AQ", "FX" => "FR", "HV" => "BF", "JT" => "UM", "MI" => "UM",
  "NH" => "VU", "NQ" => "AQ", "PU" => "UM", "PZ" => "PA", "QU" => "EU",
  "RH" => "ZW", "TP" => "TL", "UK" => "GB", "VD" => "VN", "WK" => "UM",
  "YD" => "YE", "YU" => "RS", "ZR" => "CD"
}

INTL_SU_MAP = {
  "default" => "RU", "ab" => "GE", "az" => "AZ", "be" => "BY", "crh" => "UA",
  "et" => "EE", "gag" => "MD", "got" => "UA", "hy" => "AM", "ji" => "UA",
  "ka" => "GE", "kaa" => "UZ", "kk" => "KZ", "ku-Yezi" => "GE", "ky" => "KG",
  "lt" => "LT", "ltg" => "LV", "lv" => "LV", "os" => "GE", "rue" => "UA",
  "sgs" => "LT", "sog" => "UZ", "tg" => "TJ", "tk" => "TM", "tkr" => "AZ",
  "tly" => "AZ", "ttt" => "AZ", "ug-Cyrl" => "KZ", "uk" => "UA",
  "und-Armn" => "AM", "und-Chrs" => "UZ", "und-Geor" => "GE", "und-Goth" => "UA",
  "und-Sogd" => "UZ", "und-Sogo" => "UZ", "und-Yezi" => "GE", "uz" => "UZ",
  "vro" => "EE", "xco" => "UZ", "xmf" => "GE"
}

INTL_CIS_MAP = {
  "default" => "RU", "ab" => "GE", "az" => "AZ", "be" => "BY", "crh" => "UA",
  "gag" => "MD", "got" => "UA", "hy" => "AM", "ji" => "UA", "ka" => "GE",
  "kaa" => "UZ", "kk" => "KZ", "ku-Yezi" => "GE", "ky" => "KG", "os" => "GE",
  "rue" => "UA", "sog" => "UZ", "tg" => "TJ", "tk" => "TM", "tkr" => "AZ",
  "tly" => "AZ", "ttt" => "AZ", "ug-Cyrl" => "KZ", "uk" => "UA",
  "und-Armn" => "AM", "und-Chrs" => "UZ", "und-Geor" => "GE", "und-Goth" => "UA",
  "und-Sogd" => "UZ", "und-Sogo" => "UZ", "und-Yezi" => "GE", "uz" => "UZ",
  "xco" => "UZ", "xmf" => "GE"
}

INTL_NT_MAP = {
  "default" => "SA", "akk" => "IQ", "ckb" => "IQ", "ku-Arab" => "IQ",
  "mis" => "IQ", "syr" => "IQ", "und-Hatr" => "IQ", "und-Syrc" => "IQ", "und-Xsux" => "IQ"
}

INTL_COMPLEX_REGION_MAPPINGS = {
  "172" => INTL_CIS_MAP,
  "200" => { "default" => "CZ", "sk" => "SK" },
  "530" => { "default" => "CW", "vic" => "SX" },
  "532" => { "default" => "CW", "vic" => "SX" },
  "536" => INTL_NT_MAP,
  "582" => { "default" => "FM", "mh" => "MH", "pau" => "PW" },
  "810" => INTL_SU_MAP,
  "890" => { "default" => "RS", "bs" => "BA", "hr" => "HR", "mk" => "MK", "sl" => "SI" },
  "AN" => { "default" => "CW", "vic" => "SX" },
  "NT" => INTL_NT_MAP,
  "PC" => { "default" => "FM", "mh" => "MH", "pau" => "PW" },
  "SU" => INTL_SU_MAP
}

INTL_VARIANT_MAPPINGS = {
  "aaland" => [:region, "AX"],
  "arevela" => [:language, "hy"],
  "arevmda" => [:language, "hyw"],
  "heploc" => [:variant, "alalc97"],
  "polytoni" => [:variant, "polyton"]
}

INTL_SUBDIV_MAPPINGS = {
  "cn11" => "cnbj", "cn12" => "cntj", "cn13" => "cnhe", "cn14" => "cnsx",
  "cn15" => "cnmn", "cn21" => "cnln", "cn22" => "cnjl", "cn23" => "cnhl",
  "cn31" => "cnsh", "cn32" => "cnjs", "cn33" => "cnzj", "cn34" => "cnah",
  "cn35" => "cnfj", "cn36" => "cnjx", "cn37" => "cnsd", "cn41" => "cnha",
  "cn42" => "cnhb", "cn43" => "cnhn", "cn44" => "cngd", "cn45" => "cngx",
  "cn46" => "cnhi", "cn50" => "cncq", "cn51" => "cnsc", "cn52" => "cngz",
  "cn53" => "cnyn", "cn54" => "cnxz", "cn61" => "cnsn", "cn62" => "cngs",
  "cn63" => "cnqh", "cn64" => "cnnx", "cn65" => "cnxj",
  "cz10a" => "cz110", "cz10b" => "cz111", "cz10c" => "cz112", "cz10d" => "cz113",
  "cz10e" => "cz114", "cz10f" => "cz115", "cz611" => "cz663", "cz612" => "cz632",
  "cz613" => "cz633", "cz614" => "cz634", "cz615" => "cz635", "cz621" => "cz641",
  "cz622" => "cz642", "cz623" => "cz643", "cz624" => "cz644", "cz626" => "cz646",
  "cz627" => "cz647", "czjc" => "cz31", "czjm" => "cz64", "czka" => "cz41",
  "czkr" => "cz52", "czli" => "cz51", "czmo" => "cz80", "czol" => "cz71",
  "czpa" => "cz53", "czpl" => "cz32", "czpr" => "cz10", "czst" => "cz20",
  "czus" => "cz42", "czvy" => "cz63", "czzl" => "cz72",
  "fra" => "frges", "frb" => "frnaq", "frc" => "frara", "frd" => "frbfc",
  "fre" => "frbre", "frf" => "frcvl", "frg" => "frges", "frh" => "frcor",
  "fri" => "frbfc", "frj" => "fridf", "frk" => "frocc", "frl" => "frnaq",
  "frm" => "frges", "frn" => "frocc", "fro" => "frhdf", "frp" => "frnor",
  "frq" => "frnor", "frr" => "frpdl", "frs" => "frhdf", "frt" => "frnaq",
  "fru" => "frpac", "frv" => "frara",
  "laxn" => "laxs", "lud" => "lucl", "lug" => "luec", "lul" => "luca",
  "mrnkc" => "mr13", "no23" => "no50", "nzn" => "nzauk", "nzs" => "nzcan",
  "omba" => "ombj", "omsh" => "omsj",
  "plds" => "pl02", "plkp" => "pl04", "pllb" => "pl08", "plld" => "pl10",
  "pllu" => "pl06", "plma" => "pl12", "plmz" => "pl14", "plop" => "pl16",
  "plpd" => "pl20", "plpk" => "pl18", "plpm" => "pl22", "plsk" => "pl26",
  "plsl" => "pl24", "plwn" => "pl28", "plwp" => "pl30", "plzp" => "pl32",
  "tteto" => "tttob", "ttrcm" => "ttmrc", "ttwto" => "tttob",
  "twkhq" => "twkhh", "twtnq" => "twtnn", "twtpq" => "twnwt", "twtxq" => "twtxg"
}

-> intl_alpha?(s)
  return false if s.size == 0
  i = 0
  while i < s.size
    c = s.byte_at(i)
    return false if !((c >= 65 && c <= 90) || (c >= 97 && c <= 122))
    i += 1
  true

-> intl_digit?(s)
  return false if s.size == 0
  i = 0
  while i < s.size
    c = s.byte_at(i)
    return false if c < 48 || c > 57
    i += 1
  true

-> intl_alnum?(s)
  return false if s.size == 0
  i = 0
  while i < s.size
    c = s.byte_at(i)
    return false if !((c >= 65 && c <= 90) || (c >= 97 && c <= 122) || (c >= 48 && c <= 57))
    i += 1
  true

-> intl_lower(s)
  return "" if s.size == 0
  ba = ByteArray.new(s.size)
  i = 0
  while i < s.size
    c = s.byte_at(i)
    ba[i] = (c >= 65 && c <= 90) ? c + 32 : c
    i += 1
  ccall("w_string_from_byte_array", ba)

-> intl_upper(s)
  return "" if s.size == 0
  ba = ByteArray.new(s.size)
  i = 0
  while i < s.size
    c = s.byte_at(i)
    ba[i] = (c >= 97 && c <= 122) ? c - 32 : c
    i += 1
  ccall("w_string_from_byte_array", ba)

-> intl_title(s)
  return "" if s.size == 0
  ba = ByteArray.new(s.size)
  c0 = s.byte_at(0)
  ba[0] = (c0 >= 97 && c0 <= 122) ? c0 - 32 : c0
  i = 1
  while i < s.size
    c = s.byte_at(i)
    ba[i] = (c >= 65 && c <= 90) ? c + 32 : c
    i += 1
  ccall("w_string_from_byte_array", ba)

-> intl_sort_strs(arr)
  # Simple in-place insertion/merge sort by ASCII/UTF-16 code unit order
  n = arr.size
  return arr if n <= 1
  # Use iterative bottom-up merge sort (O(n log n) for timezones/currencies!)
  out = arr.dup
  tmp = Array.new(n, nil)
  w = 1
  while w < n
    i = 0
    while i < n
      mid = i + w
      mid = n if mid > n
      hi = i + w * 2
      hi = n if hi > n
      a = i
      b = mid
      k = i
      while a < mid && b < hi
        if js_str_cmp(out[a], out[b]) <= 0
          tmp[k] = out[a]
          a += 1
        else
          tmp[k] = out[b]
          b += 1
        k += 1
      while a < mid
        tmp[k] = out[a]
        a += 1
        k += 1
      while b < hi
        tmp[k] = out[b]
        b += 1
        k += 1
      j = i
      while j < hi
        out[j] = tmp[j]
        j += 1
      i += w * 2
    w *= 2
  out

-> intl_uniq_sorted(arr)
  s = intl_sort_strs(arr)
  out = []
  i = 0
  while i < s.size
    out.push(s[i]) if i == 0 || s[i] != s[i - 1]
    i += 1
  out

# ---- Strict BCP 47 / Unicode Locale Identifier parser & canonicalizer (ECMA-402 §6.2) ----

-> intl_is_lang_subtag?(s)
  n = s.size
  intl_alpha?(s) && ((n >= 2 && n <= 3) || (n >= 5 && n <= 8))

-> intl_is_script_subtag?(s)
  s.size == 4 && intl_alpha?(s)

-> intl_is_region_subtag?(s)
  (s.size == 2 && intl_alpha?(s)) || (s.size == 3 && intl_digit?(s))

-> intl_is_variant_subtag?(s)
  n = s.size
  return intl_alnum?(s) if n >= 5 && n <= 8
  return false if n != 4
  c0 = s.byte_at(0)
  c0 >= 48 && c0 <= 57 && intl_alnum?(s)

-> intl_is_type_nonterminal?(s)
  return false if s.size == 0
  parts = s.split("-")
  i = 0
  while i < parts.size
    p = parts[i]
    return false if p.size < 3 || p.size > 8 || !intl_alnum?(p)
    i += 1
  true

# Parse unicode_language_id from `subs[idx..]`.
# Returns [next_idx, lang, script, region, variants_array] or nil if invalid.
-> intl_parse_lang_id(subs, idx, allow_extlang)
  n = subs.size
  return nil if idx >= n
  lang = subs[idx]
  return nil if !intl_is_lang_subtag?(lang)
  lang = intl_lower(lang)
  idx += 1
  # Optional extlang (only in BCP 47 language tags, 1..3 groups of 3 alpha when lang is 2-3 alpha)
  extlangs = []
  if allow_extlang && lang.size <= 3
    while idx < n && subs[idx].size == 3 && intl_alpha?(subs[idx]) && extlangs.size < 3
      extlangs.push(intl_lower(subs[idx]))
      idx += 1
    # Per UTS 35 / RFC 5646: more than 1 extlang is invalid in canonical BCP 47 (or ICU handles 1)
    return nil if extlangs.size > 1
  script = nil
  if idx < n && intl_is_script_subtag?(subs[idx])
    script = intl_title(subs[idx])
    idx += 1
  region = nil
  if idx < n && intl_is_region_subtag?(subs[idx])
    region = intl_upper(subs[idx])
    idx += 1
  vars = []
  seen_var = {}
  while idx < n && intl_is_variant_subtag?(subs[idx])
    v = intl_lower(subs[idx])
    return nil if seen_var.has_key?(v)
    seen_var[v] = true
    vars.push(v)
    idx += 1
  lang_full = extlangs.size > 0 ? (lang + "-" + extlangs[0]) : lang
  [idx, lang_full, script, region, vars]

# Canonicalize a parsed unicode_language_id per UTS 35 §3.2.1 (CLDR supplementalMetadata aliases).
-> intl_canon_lang_id(lang, script, region, vars)
  # Check complete tag aliases (e.g. art-lojban -> jbo, art-fonipa-lojban -> jbo-fonipa)
  if script == nil && region == nil && vars.size >= 1
    ti = 0
    while ti < vars.size
      whole = lang + "-" + vars[ti]
      if INTL_TAG_MAPPINGS.has_key?(whole)
        lang = INTL_TAG_MAPPINGS[whole]
        nvars = []
        tj = 0
        while tj < vars.size
          nvars.push(vars[tj]) if tj != ti
          tj += 1
        vars = nvars
        break
      ti += 1
  # Sign-language region aliases (e.g. sgn-GR -> gss) handled by ICU
  if lang == "sgn" && script == nil && region != nil
    loc = icu_for_language_tag(lang + "-" + region)
    if loc != nil && loc.size > 0
      tag = icu_to_language_tag(loc, true)
      if tag != nil && tag.size > 0 && !tag.starts_with?("sgn-")
        lang = tag
        region = nil
  # Apply language subtag mappings
  if INTL_LANG_MAPPINGS.has_key?(lang)
    lang = INTL_LANG_MAPPINGS[lang]
  elsif INTL_COMPLEX_LANG_MAPPINGS.has_key?(lang)
    cm = INTL_COMPLEX_LANG_MAPPINGS[lang]
    lang = cm[0]
    script = cm[1] if script == nil && cm[1] != nil
    region = cm[2] if region == nil && cm[2] != nil
  # Apply region subtag mappings (simple + complex likely-subtag dependent)
  if region != nil
    if INTL_REGION_MAPPINGS.has_key?(region)
      region = INTL_REGION_MAPPINGS[region]
    elsif INTL_COMPLEX_REGION_MAPPINGS.has_key?(region)
      rm = INTL_COMPLEX_REGION_MAPPINGS[region]
      mkey = script != nil ? (lang + "-" + script) : lang
      if rm.has_key?(mkey)
        region = rm[mkey]
      elsif script != nil && rm.has_key?(lang)
        region = rm[lang]
      else
        region = rm["default"]
  # Apply variant mappings (including hepburn-heploc -> alalc97) & deduplicate/sort
  has_heploc = vars.include?("heploc")
  out_vars = []
  i = 0
  while i < vars.size
    v = vars[i]
    if has_heploc && v == "hepburn"
      i += 1
      next
    if INTL_VARIANT_MAPPINGS.has_key?(v)
      vm = INTL_VARIANT_MAPPINGS[v]
      if vm[0] == :language
        lang = vm[1]
      elsif vm[0] == :region
        region = vm[1]
      else
        out_vars.push(vm[1]) if !out_vars.include?(vm[1])
    else
      out_vars.push(v) if !out_vars.include?(v)
    i += 1
  parts = [lang]
  parts.push(script) if script != nil
  parts.push(region) if region != nil
  intl_sort_strs(out_vars).each ->(v) parts.push(v)
  parts.join("-")

# Canonicalize a full BCP 47 / Unicode Locale ID. Throws RangeError if structurally invalid!
-> intl_canonicalize_locale_id(tag)
  js_throw_range("Invalid language tag: " + tag) if tag.size == 0 || !tag.ascii?
  # Check no underscores, no leading/trailing '-', no '--'
  return_err = tag.byte_at(0) == 45 || tag.byte_at(tag.size - 1) == 45
  js_throw_range("Invalid language tag: " + tag) if return_err
  subs = tag.split("-")
  # Every subtag must be non-empty ASCII alphanumeric
  i = 0
  while i < subs.size
    js_throw_range("Invalid language tag: " + tag) if subs[i].size == 0 || !intl_alnum?(subs[i])
    i += 1
  # Reject private-use-only tags like "x-foo" and irregular grandfathered like "i-klingon"
  js_throw_range("Invalid language tag: " + tag) if subs[0].size == 1
  # Strict UTS 35 unicode_language_id: NO extlang subtags allowed (allow_extlang = false)!
  p = intl_parse_lang_id(subs, 0, false)
  js_throw_range("Invalid language tag: " + tag) if p == nil
  idx = p[0]
  base = intl_canon_lang_id(p[1], p[2], p[3], p[4])
  return base if idx >= subs.size

  # Parse extensions (non-x) and optional trailing -x- private-use
  exts = {}      # singleton -> canonical extension string (without leading singleton-)
  pu = nil
  while idx < subs.size
    sg = intl_lower(subs[idx])
    js_throw_range("Invalid language tag: " + tag) if sg.size != 1
    if sg == "x"
      idx += 1
      pu_subs = []
      while idx < subs.size
        s = intl_lower(subs[idx])
        js_throw_range("Invalid language tag: " + tag) if s.size < 1 || s.size > 8
        pu_subs.push(s)
        idx += 1
      js_throw_range("Invalid language tag: " + tag) if pu_subs.size == 0
      pu = "x-" + pu_subs.join("-")
      break
    js_throw_range("Invalid language tag: " + tag) if exts.has_key?(sg)
    idx += 1
    start_idx = idx
    while idx < subs.size && subs[idx].size > 1
      idx += 1
    seg_len = idx - start_idx
    js_throw_range("Invalid language tag: " + tag) if seg_len == 0
    if sg == "u"
      # Unicode locale extension: attributes (3-8) + keywords (2-char key + 0+ 3-8 values)
      attrs = []
      seen_attr = {}
      j = start_idx
      while j < idx && subs[j].size >= 3 && subs[j].size <= 8
        a = intl_lower(subs[j])
        if !seen_attr.has_key?(a)
          seen_attr[a] = true
          attrs.push(a)
        j += 1
      kws = {}
      kw_keys = []
      while j < idx
        k = intl_lower(subs[j])
        js_throw_range("Invalid language tag: " + tag) if k.size != 2 || !intl_alnum?(k)
        c1 = k.byte_at(1)
        js_throw_range("Invalid language tag: " + tag) if c1 < 97 || c1 > 122
        j += 1
        vals = []
        while j < idx && subs[j].size >= 3 && subs[j].size <= 8
          vals.push(intl_lower(subs[j]))
          j += 1
        if !kws.has_key?(k)
          vstr = vals.join("-")
          vstr = intl_canon_u_value(k, vstr)
          kws[k] = vstr
          kw_keys.push(k)
      js_throw_range("Invalid language tag: " + tag) if attrs.size == 0 && kw_keys.size == 0
      out_u = []
      intl_sort_strs(attrs).each ->(a) out_u.push(a)
      intl_sort_strs(kw_keys).each ->(k)
        out_u.push(k)
        v = kws[k]
        out_u.push(v) if v.size > 0 && v != "true"
      exts["u"] = "u-" + out_u.join("-")
    elsif sg == "t"
      # Transformed extension: optional tlang + zero or more tfields (alpha+digit key + 1+ 3-8 subtags)
      j = start_idx
      tlang = nil
      if j < idx && !(subs[j].size == 2 && intl_alpha?(subs[j].slice(0, 1)) && intl_digit?(subs[j].slice(1, 1)))
        tp = intl_parse_lang_id(subs, j, false)
        js_throw_range("Invalid language tag: " + tag) if tp == nil
        j = tp[0]
        tlang = intl_lower(intl_canon_lang_id(tp[1], tp[2], tp[3], tp[4]))
      tfields = {}
      tkeys = []
      while j < idx
        tk = intl_lower(subs[j])
        js_throw_range("Invalid language tag: " + tag) if tk.size != 2 || !intl_alpha?(tk.slice(0, 1)) || !intl_digit?(tk.slice(1, 1))
        js_throw_range("Invalid language tag: " + tag) if tfields.has_key?(tk)
        j += 1
        tvals = []
        while j < idx && subs[j].size >= 3 && subs[j].size <= 8
          tvals.push(intl_lower(subs[j]))
          j += 1
        js_throw_range("Invalid language tag: " + tag) if tvals.size == 0
        tv = tvals.join("-")
        tv = "charname" if tk == "d0" && tv == "name"
        tv = "prprname" if tk == "m0" && tv == "names"
        tfields[tk] = tv
        tkeys.push(tk)
      js_throw_range("Invalid language tag: " + tag) if tlang == nil && tkeys.size == 0
      out_t = []
      out_t.push(tlang) if tlang != nil
      intl_sort_strs(tkeys).each ->(tk)
        out_t.push(tk)
        out_t.push(tfields[tk])
      exts["t"] = "t-" + out_t.join("-")
    else
      # Other singleton extension: subtags must be 2-8 alphanum
      sub_out = []
      j = start_idx
      while j < idx
        s = intl_lower(subs[j])
        js_throw_range("Invalid language tag: " + tag) if s.size < 2 || s.size > 8
        sub_out.push(s)
        j += 1
      exts[sg] = sg + "-" + sub_out.join("-")

  # Reassemble in canonical order: base + sorted extensions + private-use
  res = [base]
  intl_sort_strs(exts.keys).each ->(k) res.push(exts[k])
  res.push(pu) if pu != nil
  res.join("-")

# Canonicalize CLDR/UTS35 Unicode extension keyword values (ca, co, kf, kn, kb, kc, kh, kk, ks, ms, tz, rg, sd)
-> intl_canon_u_value(k, v)
  return "" if v == "true"
  if k == "kb" || k == "kc" || k == "kh" || k == "kk" || k == "kn"
    return "" if v == "yes"
    return "false" if v == "no"
  elsif k == "ca"
    return "ethioaa" if v == "ethiopic-amete-alem"
    return "islamic-civil" if v == "islamicc"
  elsif k == "co"
    return "dict" if v == "dictionary"
    return "phonebk" if v == "phonebook"
    return "trad" if v == "traditional"
  elsif k == "kf"
    return "false" if v == "no"
  elsif k == "ks"
    return "level1" if v == "primary"
    return "level2" if v == "secondary"
    return "level3" if v == "tertiary"
    return "level4" if v == "quaternary"
    return "identic" if v == "identical"
  elsif k == "ms"
    return "uksystem" if v == "imperial"
  elsif k == "rg" || k == "sd"
    return INTL_SUBDIV_MAPPINGS[v] if INTL_SUBDIV_MAPPINGS.has_key?(v)
  elsif k == "tz"
    if v.size > 0
      # Use ICU BCP 47 timezone alias canonicalization (cnckg -> cnsha, eire -> iedub, est -> papty, gmt0 -> gmt, uct/zulu -> utc)
      u = icu_to_unicode_locale_type("tz", v)
      return u if u != nil && u.size > 0
  v

# Split a canonicalized locale tag into [base_name, u_attrs, u_kws_hash, other_exts_str]
-> intl_split_tag(tag)
  subs = tag.split("-")
  n = subs.size
  i = 0
  base_parts = []
  while i < n && subs[i].size > 1
    base_parts.push(subs[i])
    i += 1
  base = base_parts.join("-")
  u_attrs = []
  u_kws = {}
  other_exts = {}
  pu = nil
  while i < n
    sg = subs[i]
    if sg == "x"
      pu = subs.slice(i, n - i).join("-")
      break
    i += 1
    st = i
    while i < n && subs[i].size > 1
      i += 1
    if sg == "u"
      j = st
      while j < i && subs[j].size >= 3
        u_attrs.push(subs[j])
        j += 1
      while j < i
        k = subs[j]
        j += 1
        vals = []
        while j < i && subs[j].size >= 3
          vals.push(subs[j])
          j += 1
        u_kws[k] = vals.size == 0 ? "" : vals.join("-")
    else
      other_exts[sg] = sg + "-" + subs.slice(st, i - st).join("-")
  [base, u_attrs, u_kws, other_exts, pu]

-> intl_join_tag(base, u_attrs, u_kws, other_exts, pu)
  exts = other_exts.dup
  if u_attrs.size > 0 || u_kws.size > 0
    u_parts = []
    intl_sort_strs(u_attrs).each ->(a) u_parts.push(a)
    intl_sort_strs(u_kws.keys).each ->(k)
      u_parts.push(k)
      v = u_kws[k]
      u_parts.push(v) if v != nil && v.size > 0 && v != "true"
    exts["u"] = "u-" + u_parts.join("-")
  out = [base]
  intl_sort_strs(exts.keys).each ->(k) out.push(exts[k])
  out.push(pu) if pu != nil
  out.join("-")

# ---- ECMA-402 Abstract Operations (§9) ----

# CanonicalizeLocaleList ( locales )
-> intl_canonicalize_locale_list(locales)
  return [] if locales == nil
  seen = []
  seen_set = {}
  if js_string?(locales)
    tag = intl_canonicalize_locale_id(locales)
    return [tag]
  if js_special?(locales, "Intl.Locale")
    tag = locales.internal[0]
    return [tag]
  o = js_to_obj(locales)
  len = js_to_length(jget(o, "length"))
  k = 0
  while k < len
    ks = k.to_s
    if jhas_property?(o, ks)
      kv = jget(o, ks)
      tag = nil
      if js_string?(kv)
        tag = intl_canonicalize_locale_id(kv)
      elsif js_special?(kv, "Intl.Locale")
        tag = kv.internal[0]
      elsif js_object?(kv)
        tag = intl_canonicalize_locale_id(js_to_string(kv))
      else
        js_throw_type("Language ID should be string or object")
      if !seen_set.has_key?(tag)
        seen_set[tag] = true
        seen.push(tag)
    k += 1
  seen

# BestAvailableLocale ( availableLocales, locale )
-> intl_best_available_locale(avail, locale)
  cand = locale
  while true
    return cand if avail.has_key?(cand)
    pos = cand.rindex("-")
    return nil if pos == nil
    if pos >= 2 && cand.byte_at(pos - 2) == 45
      pos -= 2
    cand = cand.slice(0, pos)
  nil

# LookupMatcher / BestFitMatcher (returns [matched_base, u_kws_hash])
-> intl_match_locale(avail, req_list)
  i = 0
  while i < req_list.size
    sp = intl_split_tag(req_list[i])
    base = sp[0]
    m = intl_best_available_locale(avail, base)
    if m != nil
      return [m, sp[2]]
    i += 1
  [icu_default_locale(), {}]

# ResolveLocale ( availableLocales, requestedLocales, opt, relevantExtensionKeys )
# Returns Hash: { "locale" => resolved_tag, "dataLocale" => base_tag, key => resolved_val_or_nil ... }
-> intl_resolve_locale(avail, req_list, opt, rel_keys, valid_vals_fn = nil)
  m = intl_match_locale(avail, req_list)
  found = m[0]
  u_kws = m[1]
  res = { "dataLocale" => found }
  u_out = []
  i = 0
  while i < rel_keys.size
    k = rel_keys[i]
    val = nil
    ext_used = nil
    if u_kws.has_key?(k)
      uv = u_kws[k]
      if valid_vals_fn == nil || valid_vals_fn.call(k, uv, found)
        val = uv
        ext_used = uv
    if opt.has_key?(k) && opt[k] != nil
      ov = opt[k]
      if valid_vals_fn == nil || valid_vals_fn.call(k, ov, found)
        if ov != val
          val = ov
          ext_used = nil
    res[k] = val
    if ext_used != nil
      u_out.push(k)
      u_out.push(ext_used) if ext_used != "true" && ext_used.size > 0
    i += 1
  loc = u_out.size > 0 ? (found + "-u-" + u_out.join("-")) : found
  res["locale"] = loc
  res

# GetOptionsObject ( options ) — ECMA-402 §9.2.11
-> intl_get_options_object(opts)
  return js_new_object(nil) if opts == nil
  return opts if js_object?(opts)
  js_throw_type("Options must be an object")

# CoerceOptionsToObject ( options ) — ECMA-402 §9.2.12
-> intl_coerce_options_to_object(opts)
  return js_new_object(nil) if opts == nil
  js_to_obj(opts)

# GetOption ( options, property, type, values, fallback )
# type: :string, :boolean
-> intl_get_option(opts, prop, type, values, fallback)
  v = jget(opts, prop)
  if v == nil
    js_throw_range("Option '" + prop + "' is required") if fallback == :required
    return fallback
  if type == :boolean
    return js_truthy(v)
  s = js_to_string(v)
  if values != nil && !values.include?(s)
    js_throw_range("Invalid value '" + s + "' for option '" + prop + "'")
  s

# DefaultNumberOption ( value, minimum, maximum, fallback )
-> intl_default_number_option(v, mn, mx, fallback)
  return fallback if v == nil
  n = js_to_number(v)
  js_throw_range("Option value out of range") if n != n || n < mn + ~0.0 || n > mx + ~0.0
  js_math_floor(n).to_i

# GetNumberOption ( options, property, minimum, maximum, fallback )
-> intl_get_number_option(opts, prop, mn, mx, fallback)
  intl_default_number_option(jget(opts, prop), mn, mx, fallback)

# SupportedLocales ( availableLocales, requestedLocales, options )
-> intl_supported_locales(avail, req_list, opts)
  if opts != nil
    o = js_to_obj(opts)
    intl_get_option(o, "localeMatcher", :string, ["lookup", "best fit"], "best fit")
  out = []
  i = 0
  while i < req_list.size
    tag = req_list[i]
    base = intl_split_tag(tag)[0]
    m = intl_best_available_locale(avail, base)
    out.push(tag) if m != nil
    i += 1
  js_realm().adopt_array(out)

# Map BCP 47 calendar / collation names to ICU names and vice versa
-> intl_cal_icu_to_bcp47(s)
  return "gregory" if s == "gregorian"
  return "ethioaa" if s == "ethiopic-amete-alem"
  return "islamic-civil" if s == "islamicc"
  s

-> intl_cal_bcp47_to_icu(s)
  return "gregorian" if s == "gregory"
  return "ethiopic-amete-alem" if s == "ethioaa"
  s

-> intl_col_icu_to_bcp47(s)
  return "dict" if s == "dictionary"
  return "phonebk" if s == "phonebook"
  return "trad" if s == "traditional"
  s

-> intl_col_bcp47_to_icu(s)
  return "dictionary" if s == "dict"
  return "phonebook" if s == "phonebk"
  return "traditional" if s == "trad"
  s

# ---- Intl.supportedValuesOf ( key ) ----

INTL_SUPP_CACHE = {}

# IANA 2024b primary zone overrides where ICU's CLDR canonical ID still keeps POSIX/legacy IDs separate
INTL_TZ_PRIMARY_OVERRIDES = {
  "CET" => "Europe/Brussels",
  "CST6CDT" => "America/Chicago",
  "EET" => "Europe/Athens",
  "EST" => "America/Panama",
  "EST5EDT" => "America/New_York",
  "HST" => "Pacific/Honolulu",
  "MET" => "Europe/Brussels",
  "MST" => "America/Phoenix",
  "MST7MDT" => "America/Denver",
  "PST8PDT" => "America/Los_Angeles",
  "WET" => "Europe/Lisbon",
  "Etc/GMT+0" => "UTC",
  "Etc/GMT-0" => "UTC",
  "Etc/Greenwich" => "UTC"
}

-> intl_supported_values_list(key)
  return INTL_SUPP_CACHE[key] if INTL_SUPP_CACHE.has_key?(key)
  out = nil
  if key == "calendar"
    out = INTL_ECMA_CALENDARS.dup
  elsif key == "collation"
    raw = icu_all_collations()
    mapped = []
    raw.each ->(c)
      b = intl_col_icu_to_bcp47(c)
      mapped.push(b) if b != "standard" && b != "search"
    out = intl_uniq_sorted(mapped)
  elsif key == "currency"
    out = intl_uniq_sorted(icu_available_currencies())
  elsif key == "numberingSystem"
    out = intl_uniq_sorted(icu_available_numbering_systems())
  elsif key == "timeZone"
    # Canonical IANA timezone IDs (including UTC, excluding Etc/Unknown, Factory, SystemV/*, non-IANA & POSIX backward links)
    raw = icu_all_timezones(1)
    mapped = ["UTC"]
    raw.each ->(tz)
      next if tz == "Etc/Unknown" || tz == "Factory" || tz.starts_with?("SystemV/")
      iana = icu_iana_tz(tz)
      next if iana == nil || iana.size == 0 || iana == "Etc/Unknown" || iana.starts_with?("SystemV/")
      # Keep primary canonical IDs (mapping POSIX backward links & Etc/UTC -> primary IANA zone)
      iana = INTL_TZ_PRIMARY_OVERRIDES[iana] if INTL_TZ_PRIMARY_OVERRIDES.has_key?(iana)
      iana = "UTC" if iana == "Etc/UTC" || iana == "Etc/GMT"
      mapped.push(iana)
    out = intl_uniq_sorted(mapped)
  elsif key == "unit"
    out = INTL_UNITS.dup
  else
    js_throw_range("Invalid key '" + key + "' for Intl.supportedValuesOf")
  INTL_SUPP_CACHE[key] = out
  out

-> intl_supported_values_of(key_val)
  k = js_to_string(key_val)
  js_realm().new_array(intl_supported_values_list(k))

# ---- Intl.Locale (+ Intl.Locale-info) ----

-> intl_check_locale(this, what)
  return this.internal if js_special?(this, "Intl.Locale")
  js_throw_type("Intl.Locale.prototype." + what + " called on incompatible receiver")

# Parse a base language ID into [lang, script, region, variants_str_or_nil]
-> intl_parse_base_parts(base)
  subs = base.split("-")
  lang = subs[0]
  idx = 1
  script = nil
  if idx < subs.size && intl_is_script_subtag?(subs[idx])
    script = subs[idx]
    idx += 1
  region = nil
  if idx < subs.size && intl_is_region_subtag?(subs[idx])
    region = subs[idx]
    idx += 1
  vars = idx < subs.size ? subs.slice(idx, subs.size - idx).join("-") : nil
  [lang, script, region, vars]

-> intl_locale_from_tag(tag, proto)
  sp = intl_split_tag(tag)
  base = sp[0]
  u_kws = sp[2]
  bp = intl_parse_base_parts(base)
  cal = u_kws.has_key?("ca") ? u_kws["ca"] : nil
  col = u_kws.has_key?("co") ? u_kws["co"] : nil
  hc = u_kws.has_key?("hc") ? u_kws["hc"] : nil
  kf = u_kws.has_key?("kf") ? u_kws["kf"] : nil
  kn = u_kws.has_key?("kn") ? (u_kws["kn"] == "true" || u_kws["kn"] == "") : false
  nu = u_kws.has_key?("nu") ? u_kws["nu"] : nil
  fw = u_kws.has_key?("fw") ? u_kws["fw"] : nil
  # internal = [full_tag, base, lang, script, region, variants, cal, col, hc, kf, kn, nu, fw]
  o = js_new_special(proto, "Intl.Locale")
  o.internal = [tag, base, bp[0], bp[1], bp[2], bp[3], cal, col, hc, kf, kn, nu, fw]
  o

-> intl_locale_ctor(args, nt)
  js_throw_type("Constructor Intl.Locale requires 'new'") if nt == nil
  tag_arg = js_arg(args, 0)
  opts_arg = js_arg(args, 1)
  tag = nil
  if js_string?(tag_arg)
    tag = intl_canonicalize_locale_id(tag_arg)
  elsif js_special?(tag_arg, "Intl.Locale")
    tag = tag_arg.internal[0]
  elsif js_object?(tag_arg)
    tag = intl_canonicalize_locale_id(js_to_string(tag_arg))
  else
    js_throw_type("First argument to Intl.Locale constructor can't be empty or missing")
  opts = intl_coerce_options_to_object(opts_arg)
  # ApplyOptionsToTag (exact ECMA-402 §14.1.2 property read order!)
  sp = intl_split_tag(tag)
  bp = intl_parse_base_parts(sp[0])
  lang = bp[0]
  script = bp[1]
  region = bp[2]
  vars = bp[3]

  opt_lang = intl_get_option(opts, "language", :string, nil, nil)
  if opt_lang != nil
    js_throw_range("Invalid language option: " + opt_lang) if !intl_is_lang_subtag?(opt_lang)
    lang = intl_lower(opt_lang)
  opt_script = intl_get_option(opts, "script", :string, nil, nil)
  if opt_script != nil
    js_throw_range("Invalid script option: " + opt_script) if !intl_is_script_subtag?(opt_script)
    script = intl_title(opt_script)
  opt_region = intl_get_option(opts, "region", :string, nil, nil)
  if opt_region != nil
    js_throw_range("Invalid region option: " + opt_region) if !intl_is_region_subtag?(opt_region)
    region = intl_upper(opt_region)
  opt_vars = intl_get_option(opts, "variants", :string, nil, nil)
  if opt_vars != nil
    js_throw_range("Invalid variants option") if opt_vars.size == 0
    vp = opt_vars.split("-")
    vseen = {}
    i = 0
    while i < vp.size
      v = intl_lower(vp[i])
      js_throw_range("Invalid variants option: " + opt_vars) if !intl_is_variant_subtag?(v) || vseen.has_key?(v)
      vseen[v] = true
      i += 1
    vars = intl_sort_strs(vp.map ->(x) intl_lower(x)).join("-")

  # Rebuild base tag & re-canonicalize
  bparts = [lang]
  bparts.push(script) if script != nil
  bparts.push(region) if region != nil
  bparts.push(vars) if vars != nil && vars.size > 0
  new_base = intl_canonicalize_locale_id(bparts.join("-"))
  u_kws = sp[2].dup

  # Unicode extension options in exact ECMA-402 order: calendar, collation, firstDayOfWeek, hourCycle, caseFirst, numeric, numberingSystem
  opt_cal = intl_get_option(opts, "calendar", :string, nil, nil)
  if opt_cal != nil
    js_throw_range("Invalid calendar option: " + opt_cal) if !intl_is_type_nonterminal?(opt_cal)
    u_kws["ca"] = intl_canon_u_value("ca", intl_lower(opt_cal))

  opt_col = intl_get_option(opts, "collation", :string, nil, nil)
  if opt_col != nil
    js_throw_range("Invalid collation option: " + opt_col) if !intl_is_type_nonterminal?(opt_col)
    u_kws["co"] = intl_canon_u_value("co", intl_lower(opt_col))

  opt_fw = intl_get_option(opts, "firstDayOfWeek", :string, nil, nil)
  if opt_fw != nil
    if INTL_WEEKDAY_MAP.has_key?(opt_fw)
      opt_fw = INTL_WEEKDAY_MAP[opt_fw]
    else
      js_throw_range("Invalid firstDayOfWeek option: " + opt_fw) if !intl_is_type_nonterminal?(opt_fw)
      opt_fw = intl_lower(opt_fw)
    u_kws["fw"] = opt_fw == "true" ? "" : opt_fw

  opt_hc = intl_get_option(opts, "hourCycle", :string, ["h11", "h12", "h23", "h24"], nil)
  u_kws["hc"] = opt_hc if opt_hc != nil

  opt_kf = intl_get_option(opts, "caseFirst", :string, ["upper", "lower", "false"], nil)
  u_kws["kf"] = opt_kf if opt_kf != nil

  opt_kn = intl_get_option(opts, "numeric", :boolean, nil, nil)
  u_kws["kn"] = opt_kn ? "true" : "false" if opt_kn != nil

  opt_nu = intl_get_option(opts, "numberingSystem", :string, nil, nil)
  if opt_nu != nil
    js_throw_range("Invalid numberingSystem option: " + opt_nu) if !intl_is_type_nonterminal?(opt_nu)
    u_kws["nu"] = intl_lower(opt_nu)

  full = intl_canonicalize_locale_id(intl_join_tag(new_base, sp[1], u_kws, sp[3], sp[4]))
  proto = js_realm().proto_from(nt, "Intl.Locale")
  intl_locale_from_tag(full, proto)

-> intl_locale_maximize(this)
  d = intl_check_locale(this, "maximize")
  sp = intl_split_tag(d[0])
  loc = icu_for_language_tag(sp[0])
  max_loc = loc != nil ? icu_add_likely_subtags(loc) : nil
  max_base = max_loc != nil ? icu_to_language_tag(max_loc, true) : sp[0]
  max_base = sp[0] if max_base == nil || max_base.size == 0
  full = intl_join_tag(max_base, sp[1], sp[2], sp[3], sp[4])
  intl_locale_from_tag(full, js_realm().intrinsic("Intl.Locale.prototype"))

-> intl_locale_minimize(this)
  d = intl_check_locale(this, "minimize")
  sp = intl_split_tag(d[0])
  loc = icu_for_language_tag(sp[0])
  min_loc = loc != nil ? icu_minimize_subtags(loc) : nil
  min_base = min_loc != nil ? icu_to_language_tag(min_loc, true) : sp[0]
  min_base = sp[0] if min_base == nil || min_base.size == 0
  full = intl_join_tag(min_base, sp[1], sp[2], sp[3], sp[4])
  intl_locale_from_tag(full, js_realm().intrinsic("Intl.Locale.prototype"))

-> intl_locale_get_calendars(this)
  d = intl_check_locale(this, "getCalendars")
  return js_realm().adopt_array([d[6]]) if d[6] != nil
  loc = icu_for_language_tag(d[0])
  loc = d[1] if loc == nil
  raw = icu_available_calendars(loc, true)
  out = []
  raw.each ->(c)
    b = intl_cal_icu_to_bcp47(c)
    out.push(b) if !out.include?(b) && INTL_ECMA_CALENDARS.include?(b)
  out.push("gregory") if out.size == 0
  js_realm().adopt_array(out)

-> intl_locale_get_collations(this)
  d = intl_check_locale(this, "getCollations")
  return js_realm().adopt_array([d[7]]) if d[7] != nil
  loc = icu_for_language_tag(d[0])
  loc = d[1] if loc == nil
  raw = icu_available_collations(loc, true)
  out = []
  raw.each ->(c)
    b = intl_col_icu_to_bcp47(c)
    out.push(b) if b != "standard" && b != "search" && !out.include?(b)
  js_realm().adopt_array(intl_sort_strs(out))

-> intl_subdiv_region(val)
  return nil if val == nil || val.size < 2
  reg = val.slice(0, 2)
  return nil if !intl_alpha?(reg)
  intl_upper(reg)

-> intl_locale_get_hour_cycles(this)
  d = intl_check_locale(this, "getHourCycles")
  return js_realm().adopt_array([d[8]]) if d[8] != nil
  # RegionPreference(locale): rg > explicit region > sd > maximized region > "001"
  sp = intl_split_tag(d[0])
  u_kws = sp[2]
  reg = u_kws.has_key?("rg") ? intl_subdiv_region(u_kws["rg"]) : nil
  reg = d[4] if reg == nil && d[4] != nil && d[4].size > 0
  reg = intl_subdiv_region(u_kws["sd"]) if reg == nil && u_kws.has_key?("sd")
  if reg == nil
    loc0 = icu_for_language_tag(d[1])
    mloc = loc0 != nil ? icu_add_likely_subtags(loc0) : nil
    mtag = mloc != nil ? icu_to_language_tag(mloc, true) : nil
    if mtag != nil && mtag.size > 0
      mbp = intl_parse_base_parts(mtag)
      reg = mbp[2] if mbp[2] != nil && mbp[2].size > 0
  reg = "001" if reg == nil
  loc = d[2] + "_" + reg
  hc = intl_icu_default_hour_cycle(loc, "j")
  js_realm().adopt_array([hc])

-> intl_icu_default_hour_cycle(loc, skel_str = "j")
  fn_open = icu_sym("udatpg_open")
  fn_best = icu_sym("udatpg_getBestPattern")
  fn_close = icu_sym("udatpg_close")
  lb = icu_cstr(loc)
  eb = icu_err_buf()
  pg = icu_c2(fn_open, icu_ptr(lb), icu_ptr(eb))
  lb.size
  if pg == 0 || icu_err_code(eb) > 0
    eb.size
    return "h23"
  u = icu_to_u16(skel_str)
  skel = u[0]
  dst = ByteArray.new(128)
  icu_err_reset(eb)
  n = icu_sext32(icu_c6(fn_best, pg, icu_ptr(skel), u[1], icu_ptr(dst), 64, icu_ptr(eb)))
  icu_c1(fn_close, pg)
  skel.size
  ec = icu_err_code(eb)
  eb.size
  return "h23" if ec > 0 || n <= 0
  pat = icu_from_u16_ba(dst, n)
  in_q = false
  i = 0
  while i < pat.size
    c = pat.byte_at(i)
    if c == 39
      in_q = !in_q
    elsif !in_q
      return "h11" if c == 75   # 'K'
      return "h12" if c == 104  # 'h'
      return "h23" if c == 72   # 'H'
      return "h24" if c == 107  # 'k'
    i += 1
  "h23"

-> intl_locale_get_numbering_systems(this)
  d = intl_check_locale(this, "getNumberingSystems")
  return js_realm().adopt_array([d[11]]) if d[11] != nil
  loc = icu_for_language_tag(d[0])
  loc = d[1] if loc == nil
  fn_open = icu_sym("unumsys_open")
  fn_name = icu_sym("unumsys_getName")
  fn_close = icu_sym("unumsys_close")
  lb = icu_cstr(loc)
  eb = icu_err_buf()
  ns = icu_c2(fn_open, icu_ptr(lb), icu_ptr(eb))
  lb.size
  nm = "latn"
  if ns != 0 && icu_err_code(eb) <= 0
    p = icu_c1(fn_name, ns)
    s = icu_read_cstr_ptr(p)
    nm = s if s != nil && s.size > 0
    icu_c1(fn_close, ns)
  eb.size
  js_realm().adopt_array([nm])

-> intl_locale_get_time_zones(this)
  d = intl_check_locale(this, "getTimeZones")
  reg = d[4]
  return nil if reg == nil || reg.size == 0
  fn_open = icu_sym("ucal_openTimeZoneIDEnumeration")
  rb = icu_cstr(reg)
  eb = icu_err_buf()
  # UCAL_ZONE_TYPE_CANONICAL_LOCATION = 2
  en = icu_c4(fn_open, 2, icu_ptr(rb), 0, icu_ptr(eb))
  rb.size
  ec = icu_err_code(eb)
  eb.size
  return js_realm().adopt_array([]) if ec > 0 || en == 0
  raw = icu_read_enum(en)
  out = []
  raw.each ->(tz)
    iana = icu_iana_tz(tz)
    out.push(iana != nil ? iana : tz)
  js_realm().adopt_array(intl_uniq_sorted(out))

-> intl_locale_get_text_info(this)
  d = intl_check_locale(this, "getTextInfo")
  sc = d[3]
  if sc == nil
    loc0 = icu_for_language_tag(d[1])
    mloc = loc0 != nil ? icu_add_likely_subtags(loc0) : nil
    mtag = mloc != nil ? icu_to_language_tag(mloc, true) : nil
    if mtag != nil && mtag.size > 0
      mbp = intl_parse_base_parts(mtag)
      sc = mbp[1]
  dir = sc != nil ? icu_script_direction(sc) : nil
  o = js_realm().new_object
  o.define("direction", dir, ATTR_W + ATTR_E + ATTR_C)
  o

-> intl_locale_get_week_info(this)
  d = intl_check_locale(this, "getWeekInfo")
  loc = icu_for_language_tag(d[0])
  loc = d[1] if loc == nil
  # Open an ICU calendar for the locale (handles region override -u-rg- and subdivision -u-sd- automatically!)
  fn_open = icu_sym("ucal_open")
  fn_attr = icu_sym("ucal_getAttribute")
  fn_dow = icu_sym("ucal_getDayOfWeekType")
  fn_close = icu_sym("ucal_close")
  lb = icu_cstr(loc)
  eb = icu_err_buf()
  cal = icu_c5(fn_open, 0, 0, icu_ptr(lb), 0, icu_ptr(eb))
  lb.size
  first_day = 1
  weekend = []
  if cal != 0 && icu_err_code(eb) <= 0
    # UCAL_FIRST_DAY_OF_WEEK = 1 (ICU: Sun=1, Mon=2, ..., Sat=7 -> ISO: Mon=1, ..., Sun=7)
    fd_icu = icu_sext32(icu_c2(fn_attr, cal, 1))
    first_day = fd_icu == 1 ? 7 : (fd_icu - 1)
    # Check each ISO day 1..7 (Mon=2, Tue=3, Wed=4, Thu=5, Fri=6, Sat=7, Sun=1 in ICU)
    iso = 1
    while iso <= 7
      icu_d = iso == 7 ? 1 : (iso + 1)
      icu_err_reset(eb)
      wt = icu_sext32(icu_c3(fn_dow, cal, icu_d, icu_ptr(eb)))
      # UCAL_WEEKEND = 1, UCAL_WEEKEND_ONSET = 2, UCAL_WEEKEND_CEASE = 3
      # Per ECMA-402: weekend includes full weekend days (and onset if transition == 0)
      if wt == 1
        weekend.push(iso + ~0.0)
      elsif wt == 2
        fn_wt = icu_sym("ucal_getWeekendTransition")
        icu_err_reset(eb)
        tr = icu_sext32(icu_c3(fn_wt, cal, icu_d, icu_ptr(eb)))
        weekend.push(iso + ~0.0) if tr == 0
      iso += 1
    icu_c1(fn_close, cal)
  eb.size
  # Override firstDay if -u-fw- is a valid weekday!
  if d[12] != nil && INTL_WEEKDAY_NUM.has_key?(d[12])
    first_day = INTL_WEEKDAY_NUM[d[12]]
  o = js_realm().new_object
  o.define("firstDay", first_day + ~0.0, ATTR_W + ATTR_E + ATTR_C)
  o.define("weekend", js_realm().adopt_array(weekend), ATTR_W + ATTR_E + ATTR_C)
  o

# ---- Intl.Collator ----

-> intl_fallback_sym
  js_realm().intrinsic("%IntlFallbackSymbol%")

# Unwrap legacy FallbackSymbol for Collator / NumberFormat / DateTimeFormat
-> intl_unwrap(this, kind, what)
  return this.internal if js_special?(this, kind)
  if js_object?(this)
    fb = jget(this, intl_fallback_sym())
    return fb.internal if js_special?(fb, kind)
  js_throw_type(kind + ".prototype." + what + " called on incompatible receiver")

# OrdinaryHasInstance (without invoking Symbol.hasInstance!)
-> intl_ordinary_has_instance?(val, ctor)
  return false if !js_object?(val) || !js_callable?(ctor)
  cp = jget(ctor, "prototype")
  return false if !js_object?(cp)
  cur = val.proto
  while cur != nil
    return true if cur == cp
    cur = cur.proto
  false

# ChainOrCreate for legacy Intl.{NumberFormat,DateTimeFormat} called without `new`
-> intl_legacy_chain(this, nt, ctor_name, inst)
  if nt == nil && js_object?(this)
    ctor = js_realm().intrinsic(ctor_name)
    if intl_ordinary_has_instance?(this, ctor)
      fsym = intl_fallback_sym()
      js_throw_type("Cannot re-initialize " + ctor_name) if jget_own_property(this, fsym) != nil
      js_throw_type("Cannot define property on non-extensible object") if !this.is_extensible?
      this.define(fsym, inst, 0)
      return this
  inst

INTL_LOC_COL_CACHE = {}

-> intl_locale_supported_collations(data_loc)
  return INTL_LOC_COL_CACHE[data_loc] if INTL_LOC_COL_CACHE.has_key?(data_loc)
  icu_loc = icu_for_language_tag(data_loc)
  icu_loc = data_loc if icu_loc == nil
  raw = icu_available_collations(icu_loc, false)
  out = {}
  raw.each ->(c)
    b = intl_col_icu_to_bcp47(c)
    out[b] = true if b != "standard" && b != "search"
  INTL_LOC_COL_CACHE[data_loc] = out
  out

-> intl_collator_default_ignore_punct(icu_loc)
  fn_open = icu_sym("ucol_open")
  fn_get = icu_sym("ucol_getAttribute")
  fn_close = icu_sym("ucol_close")
  lb = icu_cstr(icu_loc)
  eb = icu_err_buf()
  col = icu_c2(fn_open, icu_ptr(lb), icu_ptr(eb))
  lb.size
  res = false
  if col != 0 && icu_err_code(eb) <= 0
    icu_err_reset(eb)
    # UCOL_ALTERNATE_HANDLING = 1, UCOL_SHIFTED = 20
    alt = icu_sext32(icu_c3(fn_get, col, 1, icu_ptr(eb)))
    res = (alt == 20)
    icu_c1(fn_close, col)
  eb.size
  res

-> intl_collator_ctor(this, args, nt)
  locales = js_arg(args, 0)
  opts_arg = js_arg(args, 1)
  req = intl_canonicalize_locale_list(locales)
  opts = intl_coerce_options_to_object(opts_arg)
  usage = intl_get_option(opts, "usage", :string, ["sort", "search"], "sort")
  intl_get_option(opts, "localeMatcher", :string, ["lookup", "best fit"], "best fit")
  opt_co = intl_get_option(opts, "collation", :string, nil, nil)
  if opt_co != nil
    js_throw_range("Invalid collation option: " + opt_co) if !intl_is_type_nonterminal?(opt_co)
    opt_co = intl_canon_u_value("co", intl_lower(opt_co))
  opt_kn = intl_get_option(opts, "numeric", :boolean, nil, nil)
  opt_kf = intl_get_option(opts, "caseFirst", :string, ["upper", "lower", "false"], nil)
  sensitivity = intl_get_option(opts, "sensitivity", :string, ["base", "accent", "case", "variant"], nil)
  ignore_punct = intl_get_option(opts, "ignorePunctuation", :boolean, nil, nil)

  avail = icu_available_locales()
  opt_map = {}
  opt_map["co"] = opt_co if opt_co != nil
  opt_map["kn"] = (opt_kn ? "" : "false") if opt_kn != nil
  opt_map["kf"] = opt_kf if opt_kf != nil
  vfn = ->(k, v, found)
    if k == "co"
      usage == "sort" && intl_locale_supported_collations(found).has_key?(v)
    elsif k == "kn"
      v == "true" || v == "false" || v == ""
    elsif k == "kf"
      v == "upper" || v == "lower" || v == "false"
    else
      false
  rel = usage == "search" ? ["kn", "kf"] : ["co", "kn", "kf"]
  r = intl_resolve_locale(avail, req, opt_map, rel, vfn)
  res_loc = r["locale"]
  data_loc = r["dataLocale"]
  co = (usage == "sort" && r["co"] != nil) ? r["co"] : "default"
  kn = r["kn"] == "true" || r["kn"] == ""
  kf = r["kf"] != nil ? r["kf"] : "false"
  sens = sensitivity != nil ? sensitivity : "variant"
  # Open ICU collator
  icu_loc = icu_for_language_tag(data_loc)
  icu_loc = data_loc if icu_loc == nil
  if usage == "search"
    icu_loc = icu_loc + "@collation=search"
  elsif co != "default"
    icu_loc = icu_loc + "@collation=" + intl_col_bcp47_to_icu(co)
  # Query ICU default ignorePunctuation (Thai defaults to true!)
  ignore_punct = intl_collator_default_ignore_punct(icu_loc) if ignore_punct == nil
  proto = js_realm().proto_from(nt != nil ? nt : js_realm().intrinsic("Intl.Collator"), "Intl.Collator")
  o = js_new_special(proto, "Intl.Collator")
  # internal = [locale, usage, sens, ignore_punct, co, kn, kf, icu_loc, bound_compare]
  o.internal = [res_loc, usage, sens, ignore_punct, co, kn, kf, icu_loc, nil]
  o

-> intl_collator_compare_vals(d, x, y)
  sx = js_to_string(x)
  sy = js_to_string(y)
  fn_open = icu_sym("ucol_open")
  fn_set = icu_sym("ucol_setAttribute")
  fn_cmp = icu_sym("ucol_strcoll")
  fn_close = icu_sym("ucol_close")
  lb = icu_cstr(d[7])
  eb = icu_err_buf()
  col = icu_c2(fn_open, icu_ptr(lb), icu_ptr(eb))
  lb.size
  if col == 0 || icu_err_code(eb) > 0
    eb.size
    return js_str_cmp(sx, sy) + ~0.0
  # Apply attributes:
  # UCOL_STRENGTH = 5, UCOL_CASE_LEVEL = 3, UCOL_CASE_FIRST = 2, UCOL_NUMERIC_COLLATION = 7, UCOL_ALTERNATE_HANDLING = 1, UCOL_NORMALIZATION_MODE = 4
  sens = d[2]
  if sens == "base"
    icu_c4(fn_set, col, 5, 0, icu_ptr(eb))    # UCOL_PRIMARY = 0
  elsif sens == "accent"
    icu_c4(fn_set, col, 5, 1, icu_ptr(eb))    # UCOL_SECONDARY = 1
  elsif sens == "case"
    icu_c4(fn_set, col, 5, 0, icu_ptr(eb))    # UCOL_PRIMARY = 0
    icu_err_reset(eb)
    icu_c4(fn_set, col, 3, 17, icu_ptr(eb))   # UCOL_CASE_LEVEL = UCOL_ON (17)
  else
    icu_c4(fn_set, col, 5, 2, icu_ptr(eb))    # UCOL_TERTIARY = 2
  # Always enable normalization mode (UCOL_ON = 17) per ECMA-402!
  icu_err_reset(eb)
  icu_c4(fn_set, col, 4, 17, icu_ptr(eb))
  # ignorePunctuation: UCOL_ALTERNATE_HANDLING (1) -> UCOL_SHIFTED (20) / UCOL_NON_IGNORABLE (21)
  icu_err_reset(eb)
  icu_c4(fn_set, col, 1, d[3] ? 20 : 21, icu_ptr(eb))
  # numeric: UCOL_NUMERIC_COLLATION (7) -> UCOL_ON (17) / UCOL_OFF (16)
  if d[5]
    icu_err_reset(eb)
    icu_c4(fn_set, col, 7, 17, icu_ptr(eb))
  # caseFirst: UCOL_CASE_FIRST (2) -> UCOL_UPPER_FIRST (25) / UCOL_LOWER_FIRST (24) / UCOL_OFF (16)
  kf = d[6]
  if kf == "upper"
    icu_err_reset(eb)
    icu_c4(fn_set, col, 2, 25, icu_ptr(eb))
  elsif kf == "lower"
    icu_err_reset(eb)
    icu_c4(fn_set, col, 2, 24, icu_ptr(eb))
  ux = icu_to_u16(sx)
  uy = icu_to_u16(sy)
  bx = ux[0]
  by = uy[0]
  res = icu_sext32(icu_c5(fn_cmp, col, icu_ptr(bx), ux[1], icu_ptr(by), uy[1]))
  bx.size
  by.size
  icu_c1(fn_close, col)
  eb.size
  res + ~0.0

-> intl_collator_get_compare(this)
  d = intl_unwrap(this, "Intl.Collator", "compare")
  return d[8] if d[8] != nil
  fn = ->(th, args, nt) intl_collator_compare_vals(d, js_arg(args, 0), js_arg(args, 1))
  bf = js_realm().native("", 2, fn)
  d[8] = bf
  bf

-> intl_collator_resolved(this)
  d = intl_unwrap(this, "Intl.Collator", "resolvedOptions")
  o = js_realm().new_object
  o.define("locale", d[0], ATTR_W + ATTR_E + ATTR_C)
  o.define("usage", d[1], ATTR_W + ATTR_E + ATTR_C)
  o.define("sensitivity", d[2], ATTR_W + ATTR_E + ATTR_C)
  o.define("ignorePunctuation", d[3], ATTR_W + ATTR_E + ATTR_C)
  o.define("collation", d[4], ATTR_W + ATTR_E + ATTR_C)
  o.define("numeric", d[5], ATTR_W + ATTR_E + ATTR_C)
  o.define("caseFirst", d[6], ATTR_W + ATTR_E + ATTR_C)
  o

# ---- Intl.PluralRules ----

-> intl_plural_ctor(args, nt)
  js_throw_type("Constructor Intl.PluralRules requires 'new'") if nt == nil
  req = intl_canonicalize_locale_list(js_arg(args, 0))
  opts = intl_coerce_options_to_object(js_arg(args, 1))
  intl_get_option(opts, "localeMatcher", :string, ["lookup", "best fit"], "best fit")
  type = intl_get_option(opts, "type", :string, ["cardinal", "ordinal"], "cardinal")
  notation = intl_get_option(opts, "notation", :string, ["standard", "scientific", "engineering", "compact"], "standard")
  compact_disp = intl_get_option(opts, "compactDisplay", :string, ["short", "long"], "short")
  # Digit options (SetNumberFormatDigitOptions — ECMA-402 §15.1.1)
  dig = intl_set_digit_options(opts, 0, 3, notation)
  avail = icu_available_locales()
  r = intl_resolve_locale(avail, req, {}, [])
  loc = r["locale"]
  data_loc = r["dataLocale"]
  # Query ICU plural categories via uplrules_getKeywords
  fn_open = icu_sym("uplrules_openForType")
  fn_kw = icu_sym("uplrules_getKeywords")
  fn_close = icu_sym("uplrules_close")
  icu_loc = icu_for_language_tag(data_loc)
  icu_loc = data_loc if icu_loc == nil
  lb = icu_cstr(icu_loc)
  eb = icu_err_buf()
  pr = icu_c3(fn_open, icu_ptr(lb), type == "ordinal" ? 1 : 0, icu_ptr(eb))
  lb.size
  cats = ["other"]
  if pr != 0 && icu_err_code(eb) <= 0
    icu_err_reset(eb)
    en = icu_c2(fn_kw, pr, icu_ptr(eb))
    if en != 0 && icu_err_code(eb) <= 0
      raw_cats = icu_read_enum(en)
      # Order per CLDR: zero, one, two, few, many, other
      order = ["zero", "one", "two", "few", "many", "other"]
      cats = []
      order.each ->(c) cats.push(c) if raw_cats.include?(c)
    icu_c1(fn_close, pr)
  eb.size
  proto = js_realm().proto_from(nt, "Intl.PluralRules")
  o = js_new_special(proto, "Intl.PluralRules")
  # internal = [locale, type, dig_opts, cats, icu_loc, notation, compact_disp]
  o.internal = [loc, type, dig, cats, icu_loc, notation, compact_disp]
  o

-> intl_plural_skeleton(d)
  sk = []
  notat = d[5]
  if notat == "scientific"
    sk.push("scientific")
  elsif notat == "engineering"
    sk.push("engineering")
  elsif notat == "compact"
    sk.push(d[6] == "long" ? "compact-long" : "compact-short")
  ds = intl_digit_skeleton(d[2])
  sk.push(ds) if ds.size > 0
  sk.join(" ")

-> intl_plural_select(this, val)
  js_throw_type("Intl.PluralRules.prototype.select called on incompatible receiver") if !js_special?(this, "Intl.PluralRules")
  d = this.internal
  n = js_to_number(val)
  return "other" if n != n || !js_finite?(n)
  # Format with ICU number formatter using our notation + digit skeleton, then uplrules_selectFormatted!
  skel = intl_plural_skeleton(d)
  fn_nf_open = icu_sym("unumf_openForSkeletonAndLocale")
  fn_nf_res = icu_sym("unumf_openResult")
  fn_nf_fmt = icu_sym("unumf_formatDouble")
  fn_nf_c_res = icu_sym("unumf_closeResult")
  fn_nf_c = icu_sym("unumf_close")
  fn_pr_open = icu_sym("uplrules_openForType")
  fn_pr_sel = icu_sym("uplrules_selectFormatted")
  fn_pr_c = icu_sym("uplrules_close")
  us = icu_to_u16(skel)
  sba = us[0]
  lb = icu_cstr(d[4])
  eb = icu_err_buf()
  nf = icu_c4(fn_nf_open, icu_ptr(sba), us[1], icu_ptr(lb), icu_ptr(eb))
  res = icu_c1(fn_nf_res, icu_ptr(eb))
  icu_err_reset(eb)
  icu_c_pdpp(fn_nf_fmt, nf, wvalue_bits(n) ## i64, res, icu_ptr(eb))
  icu_err_reset(eb)
  pr = icu_c3(fn_pr_open, icu_ptr(lb), d[1] == "ordinal" ? 1 : 0, icu_ptr(eb))
  dst = ByteArray.new(64)
  out = "other"
  if pr != 0 && res != 0 && icu_err_code(eb) <= 0
    icu_err_reset(eb)
    ln = icu_sext32(icu_c5(fn_pr_sel, pr, res, icu_ptr(dst), 32, icu_ptr(eb)))
    out = icu_from_u16_ba(dst, ln) if icu_err_code(eb) <= 0 && ln > 0
  icu_c1(fn_pr_c, pr) if pr != 0
  icu_c1(fn_nf_c_res, res) if res != 0
  icu_c1(fn_nf_c, nf) if nf != 0
  sba.size
  lb.size
  eb.size
  out

-> intl_plural_select_range(this, start_v, end_v)
  js_throw_type("Intl.PluralRules.prototype.selectRange called on incompatible receiver") if !js_special?(this, "Intl.PluralRules")
  js_throw_type("start and end must be provided") if start_v == nil || end_v == nil
  d = this.internal
  x = js_to_number(start_v)
  y = js_to_number(end_v)
  js_throw_range("Range arguments cannot be NaN") if x != x || y != y
  skel = intl_plural_skeleton(d)
  fn_nrf_open = icu_sym("unumrf_openForSkeletonWithCollapseAndIdentityFallback")
  fn_nrf_res = icu_sym("unumrf_openResult")
  fn_nrf_fmt = icu_sym("unumrf_formatDoubleRange")
  fn_nrf_c_res = icu_sym("unumrf_closeResult")
  fn_nrf_c = icu_sym("unumrf_close")
  fn_pr_open = icu_sym("uplrules_openForType")
  fn_pr_sel = icu_sym("uplrules_selectForRange")
  fn_pr_c = icu_sym("uplrules_close")
  us = icu_to_u16(skel)
  sba = us[0]
  lb = icu_cstr(d[4])
  eb = icu_err_buf()
  nrf = icu_c7(fn_nrf_open, icu_ptr(sba), us[1], 0, 1, icu_ptr(lb), 0, icu_ptr(eb))
  res = icu_c1(fn_nrf_res, icu_ptr(eb))
  icu_err_reset(eb)
  icu_c_pddpp(fn_nrf_fmt, nrf, wvalue_bits(x) ## i64, wvalue_bits(y) ## i64, res, icu_ptr(eb))
  icu_err_reset(eb)
  pr = icu_c3(fn_pr_open, icu_ptr(lb), d[1] == "ordinal" ? 1 : 0, icu_ptr(eb))
  dst = ByteArray.new(64)
  out = "other"
  if pr != 0 && res != 0 && icu_err_code(eb) <= 0
    icu_err_reset(eb)
    ln = icu_sext32(icu_c5(fn_pr_sel, pr, res, icu_ptr(dst), 32, icu_ptr(eb)))
    out = icu_from_u16_ba(dst, ln) if icu_err_code(eb) <= 0 && ln > 0
  icu_c1(fn_pr_c, pr) if pr != 0
  icu_c1(fn_nrf_c_res, res) if res != 0
  icu_c1(fn_nrf_c, nrf) if nrf != 0
  sba.size
  lb.size
  eb.size
  out

-> intl_plural_resolved(this)
  js_throw_type("Intl.PluralRules.prototype.resolvedOptions called on incompatible receiver") if !js_special?(this, "Intl.PluralRules")
  d = this.internal
  dig = d[2]
  o = js_realm().new_object
  o.define("locale", d[0], ATTR_W + ATTR_E + ATTR_C)
  o.define("type", d[1], ATTR_W + ATTR_E + ATTR_C)
  o.define("notation", d[5], ATTR_W + ATTR_E + ATTR_C)
  o.define("minimumIntegerDigits", dig[0] + ~0.0, ATTR_W + ATTR_E + ATTR_C)
  if dig[1] != nil
    o.define("minimumFractionDigits", dig[1] + ~0.0, ATTR_W + ATTR_E + ATTR_C)
    o.define("maximumFractionDigits", dig[2] + ~0.0, ATTR_W + ATTR_E + ATTR_C)
  if dig[3] != nil
    o.define("minimumSignificantDigits", dig[3] + ~0.0, ATTR_W + ATTR_E + ATTR_C)
    o.define("maximumSignificantDigits", dig[4] + ~0.0, ATTR_W + ATTR_E + ATTR_C)
  o.define("pluralCategories", js_realm().new_array(d[3]), ATTR_W + ATTR_E + ATTR_C)
  o.define("roundingIncrement", dig[5] + ~0.0, ATTR_W + ATTR_E + ATTR_C)
  o.define("roundingMode", dig[6], ATTR_W + ATTR_E + ATTR_C)
  o.define("roundingPriority", dig[7], ATTR_W + ATTR_E + ATTR_C)
  o.define("trailingZeroDisplay", dig[8], ATTR_W + ATTR_E + ATTR_C)
  o.define("compactDisplay", d[6], ATTR_W + ATTR_E + ATTR_C) if d[5] == "compact"
  o

# ---- Intl.RelativeTimeFormat ----

INTL_RTF_UNITS = {
  "year" => 0, "years" => 0,
  "quarter" => 1, "quarters" => 1,
  "month" => 2, "months" => 2,
  "week" => 3, "weeks" => 3,
  "day" => 4, "days" => 4,
  "hour" => 5, "hours" => 5,
  "minute" => 6, "minutes" => 6,
  "second" => 7, "seconds" => 7
}

INTL_RTF_SINGULAR = ["year", "quarter", "month", "week", "day", "hour", "minute", "second"]

-> intl_rtf_ctor(args, nt)
  js_throw_type("Constructor Intl.RelativeTimeFormat requires 'new'") if nt == nil
  req = intl_canonicalize_locale_list(js_arg(args, 0))
  opts = intl_coerce_options_to_object(js_arg(args, 1))
  intl_get_option(opts, "localeMatcher", :string, ["lookup", "best fit"], "best fit")
  opt_nu = intl_get_option(opts, "numberingSystem", :string, nil, nil)
  if opt_nu != nil
    js_throw_range("Invalid numberingSystem: " + opt_nu) if !intl_is_type_nonterminal?(opt_nu)
    opt_nu = intl_lower(opt_nu)
  style = intl_get_option(opts, "style", :string, ["long", "short", "narrow"], "long")
  numeric = intl_get_option(opts, "numeric", :string, ["always", "auto"], "always")
  avail = icu_available_locales()
  supp_nu = intl_supported_values_list("numberingSystem")
  opt_map = {}
  opt_map["nu"] = opt_nu if opt_nu != nil && supp_nu.include?(opt_nu)
  vfn = ->(k, v, found) supp_nu.include?(v)
  r = intl_resolve_locale(avail, req, opt_map, ["nu"], vfn)
  nu = r["nu"]
  if nu == nil
    # Default numbering system for dataLocale
    loc0 = icu_for_language_tag(r["dataLocale"])
    loc0 = r["dataLocale"] if loc0 == nil
    fn_o = icu_sym("unumsys_open")
    fn_n = icu_sym("unumsys_getName")
    fn_c = icu_sym("unumsys_close")
    lb = icu_cstr(loc0)
    eb = icu_err_buf()
    ns = icu_c2(fn_o, icu_ptr(lb), icu_ptr(eb))
    lb.size
    nu = "latn"
    if ns != 0 && icu_err_code(eb) <= 0
      p = icu_c1(fn_n, ns)
      s = icu_read_cstr_ptr(p)
      nu = s if s != nil && s.size > 0
      icu_c1(fn_c, ns)
    eb.size
  icu_loc = icu_for_language_tag(r["dataLocale"] + "-u-nu-" + nu)
  icu_loc = r["dataLocale"] if icu_loc == nil
  proto = js_realm().proto_from(nt, "Intl.RelativeTimeFormat")
  o = js_new_special(proto, "Intl.RelativeTimeFormat")
  # internal = [locale, style, numeric, nu, icu_loc]
  o.internal = [r["locale"], style, numeric, nu, icu_loc]
  o

-> intl_rtf_run(d, val_arg, unit_arg, want_parts)
  v = js_to_number(val_arg)
  js_throw_range("Value need to be finite number for Intl.RelativeTimeFormat") if !js_finite?(v)
  u_str = js_to_string(unit_arg)
  js_throw_range("Invalid unit argument for Intl.RelativeTimeFormat: " + u_str) if !INTL_RTF_UNITS.has_key?(u_str)
  uid = INTL_RTF_UNITS[u_str]
  unit_sing = INTL_RTF_SINGULAR[uid]
  w_enum = d[1] == "short" ? 1 : (d[1] == "narrow" ? 2 : 0)
  fn_open = icu_sym("ureldatefmt_open")
  fn_res = icu_sym("ureldatefmt_openResult")
  fn_fmt = icu_sym(d[2] == "always" ? "ureldatefmt_formatNumericToResult" : "ureldatefmt_formatToResult")
  fn_val = icu_sym("ureldatefmt_resultAsValue")
  fn_c_res = icu_sym("ureldatefmt_closeResult")
  fn_c = icu_sym("ureldatefmt_close")
  lb = icu_cstr(d[4])
  eb = icu_err_buf()
  # UDISPCTX_CAPITALIZATION_NONE = 256
  fmt = icu_c5(fn_open, icu_ptr(lb), 0, w_enum, 256, icu_ptr(eb))
  res = icu_c1(fn_res, icu_ptr(eb))
  icu_err_reset(eb)
  icu_c_pdipp(fn_fmt, fmt, wvalue_bits(v) ## i64, uid, res, icu_ptr(eb))
  icu_err_reset(eb)
  fv = icu_c2(fn_val, res, icu_ptr(eb))
  ex = icu_fmtval_extract(fv, -1)
  icu_c1(fn_c_res, res) if res != 0
  icu_c1(fn_c, fmt) if fmt != 0
  lb.size
  eb.size
  full_str = ex[0]
  return full_str if !want_parts
  # Build parts from UFormattedValue fields (UFIELD_CATEGORY_NUMBER = 2, UFIELD_CATEGORY_RELATIVE_DATETIME = 4)
  raw_parts = ex[1]
  ulen = js_len(full_str)
  num_spans = []
  raw_parts.each ->(pt)
    if pt[0] == 2 && pt[3] > pt[2]
      # UNumberFormatFields
      num_spans.push([pt[1], pt[2], pt[3]])
  clean_spans = intl_split_nested_num_spans(num_spans)
  out = []
  pos = 0
  i = 0
  while i < clean_spans.size
    sp = clean_spans[i]
    st = sp[1]
    lm = sp[2]
    if st > pos
      p = js_realm().new_object
      p.define("type", "literal", ATTR_W + ATTR_E + ATTR_C)
      p.define("value", js_substring(full_str, pos, st), ATTR_W + ATTR_E + ATTR_C)
      out.push(p)
    if lm > st && st >= pos
      p = js_realm().new_object
      p.define("type", intl_num_field_name(sp[0], v, v < ~0.0), ATTR_W + ATTR_E + ATTR_C)
      p.define("value", js_substring(full_str, st, lm), ATTR_W + ATTR_E + ATTR_C)
      p.define("unit", unit_sing, ATTR_W + ATTR_E + ATTR_C)
      out.push(p)
      pos = lm
    i += 1
  if pos < ulen
    p = js_realm().new_object
    p.define("type", "literal", ATTR_W + ATTR_E + ATTR_C)
    p.define("value", js_substring(full_str, pos, ulen), ATTR_W + ATTR_E + ATTR_C)
    out.push(p)
  js_realm().adopt_array(out)

# ---- Intl.ListFormat ----

-> intl_lf_ctor(args, nt)
  js_throw_type("Constructor Intl.ListFormat requires 'new'") if nt == nil
  req = intl_canonicalize_locale_list(js_arg(args, 0))
  opts = intl_get_options_object(js_arg(args, 1))
  intl_get_option(opts, "localeMatcher", :string, ["lookup", "best fit"], "best fit")
  type = intl_get_option(opts, "type", :string, ["conjunction", "disjunction", "unit"], "conjunction")
  style = intl_get_option(opts, "style", :string, ["long", "short", "narrow"], "long")
  avail = icu_available_locales()
  r = intl_resolve_locale(avail, req, {}, [])
  icu_loc = icu_for_language_tag(r["dataLocale"])
  icu_loc = r["dataLocale"] if icu_loc == nil
  proto = js_realm().proto_from(nt, "Intl.ListFormat")
  o = js_new_special(proto, "Intl.ListFormat")
  o.internal = [r["locale"], type, style, icu_loc]
  o

-> intl_lf_iterable_to_strs(list)
  return [] if list == nil
  # StringListFromIterable (ECMA-402 §13.5.1)
  it = js_get_iterator(list)
  out = []
  while true
    v = js_iter_step(it)
    break if v == JS_ITER_DONE
    if !js_string?(v)
      js_iter_close_quiet(it)
      js_throw_type("Iterable yielded non-string element to Intl.ListFormat")
    out.push(v)
  out

-> intl_lf_run(this, list, want_parts)
  js_throw_type("Intl.ListFormat method called on incompatible receiver") if !js_special?(this, "Intl.ListFormat")
  d = this.internal
  strs = intl_lf_iterable_to_strs(list)
  if strs.size == 0
    return want_parts ? js_realm().adopt_array([]) : ""
  t_enum = d[1] == "disjunction" ? 1 : (d[1] == "unit" ? 2 : 0)
  w_enum = d[2] == "short" ? 1 : (d[2] == "narrow" ? 2 : 0)
  fn_open = icu_sym("ulistfmt_openForType")
  fn_res = icu_sym("ulistfmt_openResult")
  fn_fmt = icu_sym("ulistfmt_formatStringsToResult")
  fn_val = icu_sym("ulistfmt_resultAsValue")
  fn_c_res = icu_sym("ulistfmt_closeResult")
  fn_c = icu_sym("ulistfmt_close")
  lb = icu_cstr(d[3])
  eb = icu_err_buf()
  lf = icu_c4(fn_open, icu_ptr(lb), t_enum, w_enum, icu_ptr(eb))
  res = icu_c1(fn_res, icu_ptr(eb))
  n = strs.size
  # Keep all UTF-16 ByteArrays alive in `u_bufs`, pack ptrs and int32 lengths
  u_bufs = Array.new(n, nil)
  ptrs = ByteArray.new(n * 8)
  lens = ByteArray.new(n * 4)
  i = 0
  while i < n
    u = icu_to_u16(strs[i])
    u_bufs[i] = u[0]
    icu_store_i64(icu_ptr(ptrs), i * 8, icu_ptr(u[0]))
    icu_store_i32(icu_ptr(lens), i * 4, u[1])
    i += 1
  icu_err_reset(eb)
  icu_c6(fn_fmt, lf, icu_ptr(ptrs), icu_ptr(lens), n, res, icu_ptr(eb))
  icu_err_reset(eb)
  fv = icu_c2(fn_val, res, icu_ptr(eb))
  ex = icu_fmtval_extract(fv, 3)  # UFIELD_CATEGORY_LIST = 3
  icu_c1(fn_c_res, res) if res != 0
  icu_c1(fn_c, lf) if lf != 0
  u_bufs.size
  ptrs.size
  lens.size
  lb.size
  eb.size
  full_str = ex[0]
  return full_str if !want_parts
  # ULISTFMT_ELEMENT_FIELD = 1, ULISTFMT_LITERAL_FIELD = 0
  ulen = js_len(full_str)
  elems = []
  ex[1].each ->(pt) elems.push([pt[2], pt[3]]) if pt[1] == 1
  out = []
  pos = 0
  i = 0
  while i < elems.size
    st = elems[i][0]
    lm = elems[i][1]
    if st > pos
      p = js_realm().new_object
      p.define("type", "literal", ATTR_W + ATTR_E + ATTR_C)
      p.define("value", js_substring(full_str, pos, st), ATTR_W + ATTR_E + ATTR_C)
      out.push(p)
    p = js_realm().new_object
    p.define("type", "element", ATTR_W + ATTR_E + ATTR_C)
    p.define("value", js_substring(full_str, st, lm), ATTR_W + ATTR_E + ATTR_C)
    out.push(p)
    pos = lm
    i += 1
  if pos < ulen
    p = js_realm().new_object
    p.define("type", "literal", ATTR_W + ATTR_E + ATTR_C)
    p.define("value", js_substring(full_str, pos, ulen), ATTR_W + ATTR_E + ATTR_C)
    out.push(p)
  js_realm().adopt_array(out)

# ---- Intl.DisplayNames ----

-> intl_dn_ctor(args, nt)
  js_throw_type("Constructor Intl.DisplayNames requires 'new'") if nt == nil
  proto = js_realm().proto_from(nt, "Intl.DisplayNames")
  req = intl_canonicalize_locale_list(js_arg(args, 0))
  opts_arg = js_arg(args, 1)
  js_throw_type("Options argument is required for Intl.DisplayNames") if opts_arg == nil
  opts = intl_get_options_object(opts_arg)
  intl_get_option(opts, "localeMatcher", :string, ["lookup", "best fit"], "best fit")
  style = intl_get_option(opts, "style", :string, ["narrow", "short", "long"], "long")
  type = intl_get_option(opts, "type", :string, ["language", "region", "script", "currency", "calendar", "dateTimeField"], nil)
  js_throw_type("Option 'type' is required for Intl.DisplayNames") if type == nil
  fallback = intl_get_option(opts, "fallback", :string, ["code", "none"], "code")
  lang_disp = intl_get_option(opts, "languageDisplay", :string, ["dialect", "standard"], "dialect")
  avail = icu_available_locales()
  r = intl_resolve_locale(avail, req, {}, [])
  icu_loc = icu_for_language_tag(r["dataLocale"])
  icu_loc = r["dataLocale"] if icu_loc == nil
  o = js_new_special(proto, "Intl.DisplayNames")
  # internal = [locale, style, type, fallback, lang_disp, icu_loc]
  o.internal = [r["locale"], style, type, fallback, lang_disp, icu_loc]
  o

INTL_DT_FIELDS = {
  "era" => 0, "year" => 1, "quarter" => 2, "month" => 3,
  "weekOfYear" => 4, "weekday" => 6, "day" => 9, "dayPeriod" => 10,
  "hour" => 11, "minute" => 12, "second" => 13, "timeZoneName" => 15
}

-> intl_dn_of(this, code_arg)
  js_throw_type("Intl.DisplayNames.prototype.of called on incompatible receiver") if !js_special?(this, "Intl.DisplayNames")
  d = this.internal
  code = js_to_string(code_arg)
  type = d[2]
  style = d[1]
  fb = d[3]
  ldisp = d[4]
  icu_loc = d[5]

  # CanonicalCodeForDisplayNames (ECMA-402 §12.5.1)
  canon = nil
  if type == "language"
    canon = intl_canonicalize_locale_id(code)
    # Must be a unicode_language_id (no extensions!)
    sp = intl_split_tag(canon)
    js_throw_range("Invalid language code: " + code) if sp[0] != canon
  elsif type == "region"
    js_throw_range("Invalid region code: " + code) if !intl_is_region_subtag?(code)
    canon = intl_upper(code)
  elsif type == "script"
    js_throw_range("Invalid script code: " + code) if !intl_is_script_subtag?(code)
    canon = intl_title(code)
  elsif type == "currency"
    js_throw_range("Invalid currency code: " + code) if code.size != 3 || !intl_alpha?(code)
    canon = intl_upper(code)
  elsif type == "calendar"
    js_throw_range("Invalid calendar code: " + code) if !intl_is_type_nonterminal?(code)
    canon = intl_canon_u_value("ca", intl_lower(code))
  elsif type == "dateTimeField"
    js_throw_range("Invalid dateTimeField code: " + code) if !INTL_DT_FIELDS.has_key?(code)
    canon = code

  # Lookup via ICU
  res = nil
  if type == "dateTimeField"
    fn_open = icu_sym("udatpg_open")
    fn_get = icu_sym("udatpg_getFieldDisplayName")
    fn_close = icu_sym("udatpg_close")
    lb = icu_cstr(icu_loc)
    eb = icu_err_buf()
    pg = icu_c2(fn_open, icu_ptr(lb), icu_ptr(eb))
    lb.size
    if pg != 0 && icu_err_code(eb) <= 0
      w_e = style == "short" ? 1 : (style == "narrow" ? 2 : 0)
      dst = ByteArray.new(256)
      icu_err_reset(eb)
      n = icu_sext32(icu_c6(fn_get, pg, INTL_DT_FIELDS[canon], w_e, icu_ptr(dst), 128, icu_ptr(eb)))
      res = icu_from_u16_ba(dst, n) if icu_err_code(eb) <= 0 && n > 0
      icu_c1(fn_close, pg)
    eb.size
  elsif type == "currency"
    fn_get = icu_sym("ucurr_getName")
    uc = icu_to_u16(canon)
    cba = uc[0]
    lb = icu_cstr(icu_loc)
    chb = ByteArray.new(8)
    lenb = ByteArray.new(8)
    eb = icu_err_buf()
    # UCURR_LONG_NAME=1, UCURR_SYMBOL_NAME=0, UCURR_NARROW_SYMBOL_NAME=2
    st_e = style == "long" ? 1 : (style == "narrow" ? 2 : 0)
    p = icu_c6(fn_get, icu_ptr(cba), icu_ptr(lb), st_e, icu_ptr(chb), icu_ptr(lenb), icu_ptr(eb))
    ec = icu_err_code(eb)
    ln = icu_load_i32(icu_ptr(lenb), 0)
    cba.size
    lb.size
    chb.size
    lenb.size
    eb.size
    if p != 0 && ec <= 0 && ln > 0
      s = icu_from_u16_ptr(p, ln)
      # If fallback == "none" and ICU returned the currency code itself because unknown (ec == -128 U_USING_DEFAULT_WARNING or not in ISO list)
      if fb == "none" && s == canon && !intl_supported_values_list("currency").include?(canon)
        res = nil
      else
        res = s
  else
    # language, region, script, calendar via ULocaleDisplayNames (uldn_openForContext)
    fn_open = icu_sym("uldn_openForContext")
    fn_close = icu_sym("uldn_close")
    ctxs = ByteArray.new(16)
    # 0: UDISPCTX_STANDARD_NAMES (0) / UDISPCTX_DIALECT_NAMES (1)
    # 1: UDISPCTX_LENGTH_FULL (512) / UDISPCTX_LENGTH_SHORT (513)
    # 2: UDISPCTX_SUBSTITUTE (768) / UDISPCTX_NO_SUBSTITUTE (769)
    icu_store_i32(icu_ptr(ctxs), 0, ldisp == "standard" ? 0 : 1)
    icu_store_i32(icu_ptr(ctxs), 4, style == "long" ? 512 : 513)
    icu_store_i32(icu_ptr(ctxs), 8, fb == "none" ? 769 : 768)
    lb = icu_cstr(icu_loc)
    eb = icu_err_buf()
    ldn = icu_c4(fn_open, icu_ptr(lb), icu_ptr(ctxs), 3, icu_ptr(eb))
    lb.size
    ctxs.size
    if ldn != 0 && icu_err_code(eb) <= 0
      dst = ByteArray.new(512)
      icu_err_reset(eb)
      n = -1
      if type == "language"
        fn_q = icu_sym("uldn_localeDisplayName")
        cb = icu_cstr(canon)
        n = icu_sext32(icu_c5(fn_q, ldn, icu_ptr(cb), icu_ptr(dst), 256, icu_ptr(eb)))
        cb.size
      elsif type == "region"
        fn_q = icu_sym("uldn_regionDisplayName")
        cb = icu_cstr(canon)
        n = icu_sext32(icu_c5(fn_q, ldn, icu_ptr(cb), icu_ptr(dst), 256, icu_ptr(eb)))
        cb.size
      elsif type == "script"
        fn_q = icu_sym("uldn_scriptDisplayName")
        cb = icu_cstr(canon)
        n = icu_sext32(icu_c5(fn_q, ldn, icu_ptr(cb), icu_ptr(dst), 256, icu_ptr(eb)))
        cb.size
      elsif type == "calendar"
        fn_q = icu_sym("uldn_keyValueDisplayName")
        kb = icu_cstr("calendar")
        vb = icu_cstr(intl_cal_bcp47_to_icu(canon))
        n = icu_sext32(icu_c6(fn_q, ldn, icu_ptr(kb), icu_ptr(vb), icu_ptr(dst), 256, icu_ptr(eb)))
        kb.size
        vb.size
      ec2 = icu_err_code(eb)
      if ec2 <= 0 && n > 0
        res = icu_from_u16_ba(dst, n)
      icu_c1(fn_close, ldn)
    eb.size

  return res if res != nil
  fb == "code" ? canon : nil

-> intl_dn_resolved(this)
  js_throw_type("Intl.DisplayNames.prototype.resolvedOptions called on incompatible receiver") if !js_special?(this, "Intl.DisplayNames")
  d = this.internal
  o = js_realm().new_object
  o.define("locale", d[0], ATTR_W + ATTR_E + ATTR_C)
  o.define("style", d[1], ATTR_W + ATTR_E + ATTR_C)
  o.define("type", d[2], ATTR_W + ATTR_E + ATTR_C)
  o.define("fallback", d[3], ATTR_W + ATTR_E + ATTR_C)
  o.define("languageDisplay", d[4], ATTR_W + ATTR_E + ATTR_C) if d[2] == "language"
  o

# ---- Intl.Segmenter ----

-> intl_seg_ctor(args, nt)
  js_throw_type("Constructor Intl.Segmenter requires 'new'") if nt == nil
  req = intl_canonicalize_locale_list(js_arg(args, 0))
  opts = intl_get_options_object(js_arg(args, 1))
  intl_get_option(opts, "localeMatcher", :string, ["lookup", "best fit"], "best fit")
  gran = intl_get_option(opts, "granularity", :string, ["grapheme", "word", "sentence"], "grapheme")
  avail = icu_available_locales()
  r = intl_resolve_locale(avail, req, {}, [])
  icu_loc = icu_for_language_tag(r["dataLocale"])
  icu_loc = r["dataLocale"] if icu_loc == nil
  proto = js_realm().proto_from(nt, "Intl.Segmenter")
  o = js_new_special(proto, "Intl.Segmenter")
  o.internal = [r["locale"], gran, icu_loc]
  o

# Compute all segments [start_u16, end_u16, is_word_like] using ICU UBreakIterator!
-> intl_seg_compute(icu_loc, gran, str)
  return [] if str.size == 0
  # UBRK_CHARACTER=0, UBRK_WORD=1, UBRK_SENTENCE=3
  btype = gran == "word" ? 1 : (gran == "sentence" ? 3 : 0)
  fn_open = icu_sym("ubrk_open")
  fn_first = icu_sym("ubrk_first")
  fn_next = icu_sym("ubrk_next")
  fn_stat = icu_sym("ubrk_getRuleStatus")
  fn_close = icu_sym("ubrk_close")
  lb = icu_cstr(icu_loc)
  us = icu_to_u16(str)
  uba = us[0]
  ulen = us[1]
  eb = icu_err_buf()
  bi = icu_c5(fn_open, btype, icu_ptr(lb), icu_ptr(uba), ulen, icu_ptr(eb))
  segs = []
  if bi != 0 && icu_err_code(eb) <= 0
    prev = icu_sext32(icu_c1(fn_first, bi))
    while true
      cur = icu_sext32(icu_c1(fn_next, bi))
      break if cur < 0   # UBRK_DONE == -1
      wl = false
      if gran == "word"
        st = icu_sext32(icu_c1(fn_stat, bi))
        wl = st >= 100  # UBRK_WORD_NONE_LIMIT = 100
      segs.push([prev, cur, wl])
      prev = cur
    icu_c1(fn_close, bi)
  lb.size
  uba.size
  eb.size
  segs

-> intl_seg_make_data(str, gran, seg)
  o = js_realm().new_object
  o.define("segment", js_substring(str, seg[0], seg[1]), ATTR_W + ATTR_E + ATTR_C)
  o.define("index", seg[0] + ~0.0, ATTR_W + ATTR_E + ATTR_C)
  o.define("input", str, ATTR_W + ATTR_E + ATTR_C)
  o.define("isWordLike", seg[2], ATTR_W + ATTR_E + ATTR_C) if gran == "word"
  o

-> intl_seg_segment(this, input_arg)
  js_throw_type("Intl.Segmenter.prototype.segment called on incompatible receiver") if !js_special?(this, "Intl.Segmenter")
  d = this.internal
  str = js_to_string(input_arg)
  segs = intl_seg_compute(d[2], d[1], str)
  o = js_new_special(js_realm().intrinsic("%SegmentsPrototype%"), "Intl.Segments")
  o.internal = [d[1], str, segs, js_len(str)]
  o

-> intl_segments_containing(this, idx_arg)
  js_throw_type("Segments.prototype.containing called on incompatible receiver") if !js_special?(this, "Intl.Segments")
  d = this.internal
  n = js_to_integer(idx_arg)
  slen = d[3]
  return nil if n < ~0.0 || n >= slen + ~0.0
  ni = n.to_i
  segs = d[2]
  # Binary search for segment where seg[0] <= ni < seg[1]
  lo = 0
  hi = segs.size - 1
  while lo <= hi
    mid = (lo + hi) >> 1
    s = segs[mid]
    if ni < s[0]
      hi = mid - 1
    elsif ni >= s[1]
      lo = mid + 1
    else
      return intl_seg_make_data(d[1], d[0], s)
  nil

-> intl_segments_iter(this)
  js_throw_type("Segments.prototype[Symbol.iterator] called on incompatible receiver") if !js_special?(this, "Intl.Segments")
  d = this.internal
  it = js_new_special(js_realm().intrinsic("%SegmentIteratorPrototype%"), "Intl.SegmentIterator")
  it.internal = [d[0], d[1], d[2], 0]
  it

-> intl_seg_iter_next(this)
  js_throw_type("SegmentIterator.prototype.next called on incompatible receiver") if !js_special?(this, "Intl.SegmentIterator")
  d = this.internal
  idx = d[3]
  segs = d[2]
  if idx >= segs.size
    return js_iter_result(nil, true)
  d[3] = idx + 1
  js_iter_result(intl_seg_make_data(d[1], d[0], segs[idx]), false)

# ---- Realm Installation (called by b_intl_fmt.w after both parts load) ----

-> js_install_intl_core(r, intl)
  # Intl.getCanonicalLocales & Intl.supportedValuesOf
  r.method(intl, "getCanonicalLocales", 1, ->(this, args, nt) r.adopt_array(intl_canonicalize_locale_list(js_arg(args, 0))))
  r.method(intl, "supportedValuesOf", 1, ->(this, args, nt) intl_supported_values_of(js_arg(args, 0)))

  # Intl.Locale
  lp = js_new_object(r.object_proto)
  lc = r.native("Locale", 1, ->(this, args, nt) intl_locale_ctor(args, nt), true)
  lc.define("prototype", lp, 0)
  lp.define("constructor", lc, BUILTIN_ATTRS)
  lp.define(SYM_TO_STRING_TAG, "Intl.Locale", ATTR_C)
  r.set_intrinsic("Intl.Locale", lc)
  r.set_intrinsic("Intl.Locale.prototype", lp)
  intl.define("Locale", lc, BUILTIN_ATTRS)
  r.method(lp, "maximize", 0, ->(this, args, nt) intl_locale_maximize(this))
  r.method(lp, "minimize", 0, ->(this, args, nt) intl_locale_minimize(this))
  r.method(lp, "toString", 0, ->(this, args, nt) intl_check_locale(this, "toString")[0])
  r.getter(lp, "baseName", ->(this, args, nt) intl_check_locale(this, "baseName")[1])
  r.getter(lp, "calendar", ->(this, args, nt) intl_check_locale(this, "calendar")[6])
  r.getter(lp, "caseFirst", ->(this, args, nt) intl_check_locale(this, "caseFirst")[9])
  r.getter(lp, "collation", ->(this, args, nt) intl_check_locale(this, "collation")[7])
  r.getter(lp, "firstDayOfWeek", ->(this, args, nt) intl_check_locale(this, "firstDayOfWeek")[12])
  r.getter(lp, "hourCycle", ->(this, args, nt) intl_check_locale(this, "hourCycle")[8])
  r.getter(lp, "numeric", ->(this, args, nt) intl_check_locale(this, "numeric")[10])
  r.getter(lp, "numberingSystem", ->(this, args, nt) intl_check_locale(this, "numberingSystem")[11])
  r.getter(lp, "language", ->(this, args, nt) intl_check_locale(this, "language")[2])
  r.getter(lp, "script", ->(this, args, nt) intl_check_locale(this, "script")[3])
  r.getter(lp, "region", ->(this, args, nt) intl_check_locale(this, "region")[4])
  r.getter(lp, "variants", ->(this, args, nt) intl_check_locale(this, "variants")[5])
  r.method(lp, "getCalendars", 0, ->(this, args, nt) intl_locale_get_calendars(this))
  r.method(lp, "getCollations", 0, ->(this, args, nt) intl_locale_get_collations(this))
  r.method(lp, "getHourCycles", 0, ->(this, args, nt) intl_locale_get_hour_cycles(this))
  r.method(lp, "getNumberingSystems", 0, ->(this, args, nt) intl_locale_get_numbering_systems(this))
  r.method(lp, "getTextInfo", 0, ->(this, args, nt) intl_locale_get_text_info(this))
  r.method(lp, "getTimeZones", 0, ->(this, args, nt) intl_locale_get_time_zones(this))
  r.method(lp, "getWeekInfo", 0, ->(this, args, nt) intl_locale_get_week_info(this))

  # Intl.Collator
  cp = js_new_object(r.object_proto)
  cc = r.native("Collator", 0, ->(this, args, nt) intl_collator_ctor(this, args, nt), true)
  cc.define("prototype", cp, 0)
  cp.define("constructor", cc, BUILTIN_ATTRS)
  cp.define(SYM_TO_STRING_TAG, "Intl.Collator", ATTR_C)
  r.set_intrinsic("Intl.Collator", cc)
  r.set_intrinsic("Intl.Collator.prototype", cp)
  intl.define("Collator", cc, BUILTIN_ATTRS)
  r.method(cc, "supportedLocalesOf", 1, ->(this, args, nt) intl_supported_locales(icu_available_locales(), intl_canonicalize_locale_list(js_arg(args, 0)), js_arg(args, 1)))
  r.getter(cp, "compare", ->(this, args, nt) intl_collator_get_compare(this))
  r.method(cp, "resolvedOptions", 0, ->(this, args, nt) intl_collator_resolved(this))

  # Intl.PluralRules
  pp = js_new_object(r.object_proto)
  pc = r.native("PluralRules", 0, ->(this, args, nt) intl_plural_ctor(args, nt), true)
  pc.define("prototype", pp, 0)
  pp.define("constructor", pc, BUILTIN_ATTRS)
  pp.define(SYM_TO_STRING_TAG, "Intl.PluralRules", ATTR_C)
  r.set_intrinsic("Intl.PluralRules", pc)
  r.set_intrinsic("Intl.PluralRules.prototype", pp)
  intl.define("PluralRules", pc, BUILTIN_ATTRS)
  r.method(pc, "supportedLocalesOf", 1, ->(this, args, nt) intl_supported_locales(icu_available_locales(), intl_canonicalize_locale_list(js_arg(args, 0)), js_arg(args, 1)))
  r.method(pp, "select", 1, ->(this, args, nt) intl_plural_select(this, js_arg(args, 0)))
  r.method(pp, "selectRange", 2, ->(this, args, nt) intl_plural_select_range(this, js_arg(args, 0), js_arg(args, 1)))
  r.method(pp, "resolvedOptions", 0, ->(this, args, nt) intl_plural_resolved(this))

  # Intl.RelativeTimeFormat
  rp = js_new_object(r.object_proto)
  rc = r.native("RelativeTimeFormat", 0, ->(this, args, nt) intl_rtf_ctor(args, nt), true)
  rc.define("prototype", rp, 0)
  rp.define("constructor", rc, BUILTIN_ATTRS)
  rp.define(SYM_TO_STRING_TAG, "Intl.RelativeTimeFormat", ATTR_C)
  r.set_intrinsic("Intl.RelativeTimeFormat", rc)
  r.set_intrinsic("Intl.RelativeTimeFormat.prototype", rp)
  intl.define("RelativeTimeFormat", rc, BUILTIN_ATTRS)
  r.method(rc, "supportedLocalesOf", 1, ->(this, args, nt) intl_supported_locales(icu_available_locales(), intl_canonicalize_locale_list(js_arg(args, 0)), js_arg(args, 1)))
  rtf_fmt = ->(this, args, nt)
    js_throw_type("Intl.RelativeTimeFormat.prototype.format called on incompatible receiver") if !js_special?(this, "Intl.RelativeTimeFormat")
    intl_rtf_run(this.internal, js_arg(args, 0), js_arg(args, 1), false)
  rtf_parts = ->(this, args, nt)
    js_throw_type("Intl.RelativeTimeFormat.prototype.formatToParts called on incompatible receiver") if !js_special?(this, "Intl.RelativeTimeFormat")
    intl_rtf_run(this.internal, js_arg(args, 0), js_arg(args, 1), true)
  rtf_res = ->(this, args, nt)
    js_throw_type("Intl.RelativeTimeFormat.prototype.resolvedOptions called on incompatible receiver") if !js_special?(this, "Intl.RelativeTimeFormat")
    d = this.internal
    o = js_realm().new_object
    o.define("locale", d[0], ATTR_W + ATTR_E + ATTR_C)
    o.define("style", d[1], ATTR_W + ATTR_E + ATTR_C)
    o.define("numeric", d[2], ATTR_W + ATTR_E + ATTR_C)
    o.define("numberingSystem", d[3], ATTR_W + ATTR_E + ATTR_C)
    o
  r.method(rp, "format", 2, rtf_fmt)
  r.method(rp, "formatToParts", 2, rtf_parts)
  r.method(rp, "resolvedOptions", 0, rtf_res)

  # Intl.ListFormat
  lfp = js_new_object(r.object_proto)
  lfc = r.native("ListFormat", 0, ->(this, args, nt) intl_lf_ctor(args, nt), true)
  lfc.define("prototype", lfp, 0)
  lfp.define("constructor", lfc, BUILTIN_ATTRS)
  lfp.define(SYM_TO_STRING_TAG, "Intl.ListFormat", ATTR_C)
  r.set_intrinsic("Intl.ListFormat", lfc)
  r.set_intrinsic("Intl.ListFormat.prototype", lfp)
  intl.define("ListFormat", lfc, BUILTIN_ATTRS)
  r.method(lfc, "supportedLocalesOf", 1, ->(this, args, nt) intl_supported_locales(icu_available_locales(), intl_canonicalize_locale_list(js_arg(args, 0)), js_arg(args, 1)))
  r.method(lfp, "format", 1, ->(this, args, nt) intl_lf_run(this, js_arg(args, 0), false))
  r.method(lfp, "formatToParts", 1, ->(this, args, nt) intl_lf_run(this, js_arg(args, 0), true))
  lf_res = ->(this, args, nt)
    js_throw_type("Intl.ListFormat.prototype.resolvedOptions called on incompatible receiver") if !js_special?(this, "Intl.ListFormat")
    d = this.internal
    o = js_realm().new_object
    o.define("locale", d[0], ATTR_W + ATTR_E + ATTR_C)
    o.define("type", d[1], ATTR_W + ATTR_E + ATTR_C)
    o.define("style", d[2], ATTR_W + ATTR_E + ATTR_C)
    o
  r.method(lfp, "resolvedOptions", 0, lf_res)

  # Intl.DisplayNames
  dnp = js_new_object(r.object_proto)
  dnc = r.native("DisplayNames", 2, ->(this, args, nt) intl_dn_ctor(args, nt), true)
  dnc.define("prototype", dnp, 0)
  dnp.define("constructor", dnc, BUILTIN_ATTRS)
  dnp.define(SYM_TO_STRING_TAG, "Intl.DisplayNames", ATTR_C)
  r.set_intrinsic("Intl.DisplayNames", dnc)
  r.set_intrinsic("Intl.DisplayNames.prototype", dnp)
  intl.define("DisplayNames", dnc, BUILTIN_ATTRS)
  r.method(dnc, "supportedLocalesOf", 1, ->(this, args, nt) intl_supported_locales(icu_available_locales(), intl_canonicalize_locale_list(js_arg(args, 0)), js_arg(args, 1)))
  r.method(dnp, "of", 1, ->(this, args, nt) intl_dn_of(this, js_arg(args, 0)))
  r.method(dnp, "resolvedOptions", 0, ->(this, args, nt) intl_dn_resolved(this))

  # Intl.Segmenter + %SegmentsPrototype% + %SegmentIteratorPrototype%
  sgp = js_new_object(r.object_proto)
  sgc = r.native("Segmenter", 0, ->(this, args, nt) intl_seg_ctor(args, nt), true)
  sgc.define("prototype", sgp, 0)
  sgp.define("constructor", sgc, BUILTIN_ATTRS)
  sgp.define(SYM_TO_STRING_TAG, "Intl.Segmenter", ATTR_C)
  r.set_intrinsic("Intl.Segmenter", sgc)
  r.set_intrinsic("Intl.Segmenter.prototype", sgp)
  intl.define("Segmenter", sgc, BUILTIN_ATTRS)
  r.method(sgc, "supportedLocalesOf", 1, ->(this, args, nt) intl_supported_locales(icu_available_locales(), intl_canonicalize_locale_list(js_arg(args, 0)), js_arg(args, 1)))
  r.method(sgp, "segment", 1, ->(this, args, nt) intl_seg_segment(this, js_arg(args, 0)))
  sg_res = ->(this, args, nt)
    js_throw_type("Intl.Segmenter.prototype.resolvedOptions called on incompatible receiver") if !js_special?(this, "Intl.Segmenter")
    d = this.internal
    o = js_realm().new_object
    o.define("locale", d[0], ATTR_W + ATTR_E + ATTR_C)
    o.define("granularity", d[1], ATTR_W + ATTR_E + ATTR_C)
    o
  r.method(sgp, "resolvedOptions", 0, sg_res)

  segs_p = js_new_object(r.object_proto)
  r.set_intrinsic("%SegmentsPrototype%", segs_p)
  r.method(segs_p, "containing", 1, ->(this, args, nt) intl_segments_containing(this, js_arg(args, 0)))
  r.method(segs_p, SYM_ITERATOR, 0, ->(this, args, nt) intl_segments_iter(this))

  sit_p = js_new_object(r.intrinsic("%IteratorPrototype%"))
  sit_p.define(SYM_TO_STRING_TAG, "Segmenter String Iterator", ATTR_C)
  r.set_intrinsic("%SegmentIteratorPrototype%", sit_p)
  r.method(sit_p, "next", 0, ->(this, args, nt) intl_seg_iter_next(this))
  nil
