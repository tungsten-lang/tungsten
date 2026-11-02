# Unicode — Versioned Unicode Standard algorithms & UCD properties.
#
# Implements conformance with the Unicode Standard and its annexes across all
# released Unicode versions (1.1.0 through 17.0.0):
#   - Core Spec Ch. 3: UTF-8/16/32 validation, scalar value verification,
#     full case mapping, case folding, and caseless matching (D135-D147)
#   - UAX #9:  Unicode Bidirectional Algorithm (Bidi_Class, Bidi_Mirrored,
#              Bidi_Mirroring_Glyph, P2/P3 paragraph direction, Bidi safety)
#   - UAX #11: East Asian Width (N, Na, A, W, F, H) and monospace display width
#   - UAX #14: Unicode Line Breaking Algorithm
#   - UAX #15: Unicode Normalization Forms (NFC, NFD, NFKC, NFKD, NFKC_Casefold,
#              version-specific normalization, Corrigendum #4, Stream-Safe Text)
#   - UAX #24: Unicode Script Property (Script, scripts in text)
#   - UAX #29: Unicode Text Segmentation (Extended Grapheme Clusters, Words,
#              Sentences, with version-aware GB9c Indic Conjunct Break)
#   - UAX #31: Unicode Identifier and Pattern Syntax (XID_Start, XID_Continue,
#              Pattern_Syntax, Pattern_White_Space, identifier validation)
#   - UAX #38: Unicode Han Database (Unihan CJK Unified Ideographs)
#   - UAX #44: Unicode Character Database (Age, General_Category, CCC, Block)
#   - UTS #39: Unicode Security Mechanisms (mixed-script & Bidi spoofing checks)
#   - UTS #51: Unicode Emoji properties
#
# Versioned tables are loaded lazily from `$TUNGSTEN_HOME/unicode/unicode_data.bin`
# (downloaded from the Bit registry during `bit build` / `bit install` or
# synthesized on demand via `scripts/fetch_unicode_data.rb`).
+ Unicode
  SUPPORTED_VERSIONS = [
    "1.1.0", "2.0.0", "2.1.0", "3.0.0", "3.1.0", "3.2.0", "4.0.0", "4.1.0",
    "5.0.0", "5.1.0", "5.2.0", "6.0.0", "6.1.0", "6.2.0", "6.3.0", "7.0.0",
    "8.0.0", "9.0.0", "10.0.0", "11.0.0", "12.0.0", "12.1.0", "13.0.0",
    "14.0.0", "15.0.0", "15.1.0", "16.0.0", "17.0.0"
  ]

  EAW_CODES = ["N", "Na", "A", "W", "F", "H"]

  BIDI_CLASSES = [
    "L", "R", "AL", "EN", "ES", "ET", "AN", "CS", "NSM", "BN",
    "B", "S", "WS", "ON", "LRE", "LRO", "RLE", "RLO", "PDF",
    "LRI", "RLI", "FSI", "PDI"
  ]

  SCRIPTS = [
    "Common", "Inherited", "Latin", "Greek", "Cyrillic", "Armenian", "Hebrew", "Arabic",
    "Syriac", "Thaana", "Devanagari", "Bengali", "Gurmukhi", "Gujarati", "Oriya", "Tamil",
    "Telugu", "Kannada", "Malayalam", "Sinhala", "Thai", "Lao", "Tibetan", "Myanmar",
    "Georgian", "Hangul", "Ethiopic", "Cherokee", "Canadian_Aboriginal", "Ogham", "Runic",
    "Khmer", "Mongolian", "Hiragana", "Katakana", "Bopomofo", "Han", "Yi", "Old_Italic",
    "Gothic", "Deseret", "Tagalog", "Hanunoo", "Buhid", "Tagbanwa", "Limbu", "Tai_Le",
    "Linear_B", "Ugaritic", "Shavian", "Osmanya", "Cypriot", "Braille", "Buginese", "Coptic",
    "New_Tai_Lue", "Glagolitic", "Tifinagh", "Syloti_Nagri", "Old_Persian", "Kharoshthi",
    "Balinese", "Cuneiform", "Phoenician", "Phags_Pa", "Nko", "Sundanese", "Lepcha",
    "Ol_Chiki", "Vai", "Saurashtra", "Kayah_Li", "Rejang", "Lycian", "Carian", "Lydian",
    "Cham", "Tai_Tham", "Tai_Viet", "Avestan", "Egyptian_Hieroglyphs", "Samaritan", "Lisu",
    "Bamum", "Javanese", "Meetei_Mayek", "Imperial_Aramaic", "Old_South_Arabian", "Inscriptional_Parthian",
    "Inscriptional_Pahlavi", "Old_Turkic", "Kaithi", "Batak", "Brahmi", "Mandaic", "Chakma",
    "Meroitic_Cursive", "Meroitic_Hieroglyphs", "Miao", "Sharada", "Sora_Sompeng", "Takri"
  ]

  @@active_version = nil
  @@ucd_table = nil

  # -------------------------------------------------- Version management --

  -> .default_version
    "16.0.0"

  -> .supported_versions
    SUPPORTED_VERSIONS

  -> .normalize_version(ver)
    if ver == nil
      return Unicode.version()
    s = ver.to_s().strip()
    if s.starts_with?(":")
      s = s.slice(1, s.size() - 1)
    if s.starts_with?("v") || s.starts_with?("V")
      s = s.slice(1, s.size() - 1)
    s = s.replace("_", ".")
    if s == "latest" || s == "current" || s == ""
      return "16.0.0"
    parts = s.split(".")
    if parts.size() == 1
      s = parts[0] + ".0.0"
    elsif parts.size() == 2
      s = parts[0] + "." + parts[1] + ".0"
    i = 0
    while i < SUPPORTED_VERSIONS.size()
      if SUPPORTED_VERSIONS[i] == s
        return s
      i += 1
    raise ArgumentError.new("unsupported Unicode version: " + ver.to_s())

  -> .version_id(ver = nil)
    norm = Unicode.normalize_version(ver)
    i = 0
    while i < SUPPORTED_VERSIONS.size()
      if SUPPORTED_VERSIONS[i] == norm
        return i + 1
      i += 1
    27

  -> .version
    if @@active_version != nil
      return @@active_version
    env_v = env("TUNGSTEN_UNICODE_VERSION")
    if env_v != nil && env_v.strip() != ""
      @@active_version = Unicode.normalize_version(env_v)
      return @@active_version
    if file?("build/unicode/version")
      raw_v = read_file("build/unicode/version")
      if raw_v != nil && raw_v.strip() != ""
        @@active_version = Unicode.normalize_version(raw_v)
        return @@active_version
    "16.0.0"

  -> .set_version(ver)
    if ver == nil
      @@active_version = nil
      return Unicode.version()
    @@active_version = Unicode.normalize_version(ver)
    @@active_version

  -> .version=(ver)
    Unicode.set_version(ver)

  -> .with_version(ver, &block)
    prev = @@active_version
    @@active_version = Unicode.normalize_version(ver)
    res = block.call()
    @@active_version = prev
    res

  # ------------------------------------------ Lazy UCD table & bit loader --

  -> .__load_table
    if @@ucd_table != nil
      return @@ucd_table
    path = nil
    if file?("build/unicode/unicode_data.bin")
      path = "build/unicode/unicode_data.bin"
    if path == nil
      bh = env("BIT_HOME")
      if bh != nil && bh != "" && file?(bh + "/unicode/unicode_data.bin")
        path = bh + "/unicode/unicode_data.bin"
    if path == nil
      th = env("TUNGSTEN_HOME")
      if th != nil && th != "" && file?(th + "/unicode/unicode_data.bin")
        path = th + "/unicode/unicode_data.bin"
    if path == nil
      hm = env("HOME")
      if hm != nil && hm != "" && file?(hm + "/.tungsten/unicode/unicode_data.bin")
        path = hm + "/.tungsten/unicode/unicode_data.bin"
    if path == nil
      hm = env("HOME") || "."
      cache_dir = (env("TUNGSTEN_HOME") && env("TUNGSTEN_HOME") != "") ? (env("TUNGSTEN_HOME") + "/unicode") : (hm + "/.tungsten/unicode")
      script = "scripts/fetch_unicode_data.rb"
      root = env("TUNGSTEN_ROOT")
      if root != nil && root != "" && file?(root + "/scripts/fetch_unicode_data.rb")
        script = root + "/scripts/fetch_unicode_data.rb"
      elsif !file?(script) && hm != "." && file?(hm + "/tungsten/scripts/fetch_unicode_data.rb")
        script = hm + "/tungsten/scripts/fetch_unicode_data.rb"
      system("ruby '" + script + "' '" + cache_dir + "' 2>/dev/null")
      cand = cache_dir + "/unicode_data.bin"
      if file?(cand)
        path = cand
    if path == nil
      raise "missing Unicode data table unicode_data.bin; run `bit build` or `ruby scripts/fetch_unicode_data.rb`"
    raw = read_file_bytes(path)
    if raw == nil
      raise "could not read Unicode data table " + path
    if type(raw) == "String"
      @@ucd_table = raw.bytes()
    else
      @@ucd_table = raw
    @@ucd_table

  -> .__u32(tbl, word_idx)
    off = word_idx * 4
    tbl[off] | (tbl[off + 1] << 8) | (tbl[off + 2] << 16) | (tbl[off + 3] << 24)

  -> .__bsearch_range(tbl, sec_off, count, cp)
    lo = 0
    hi = count
    while lo < hi
      mid = (lo + hi) >> 1
      w_off = sec_off + mid * 2
      r_lo = Unicode.__u32(tbl, w_off)
      r_pack = Unicode.__u32(tbl, w_off + 1)
      r_hi = (r_pack >> 8) & 0xFFFFFF
      if cp < r_lo
        hi = mid
      elsif cp > r_hi
        lo = mid + 1
      else
        return r_pack & 0xFF
    0

  -> .__bsearch_kv(tbl, sec_off, count, key)
    lo = 0
    hi = count
    while lo < hi
      mid = (lo + hi) >> 1
      w_off = sec_off + mid * 2
      k = Unicode.__u32(tbl, w_off)
      if key < k
        hi = mid
      elsif key > k
        lo = mid + 1
      else
        return Unicode.__u32(tbl, w_off + 1)
    -1

  # -------------------------------------- UAX #44 Properties & Validation --

  -> .codepoint_age_id(cp)
    if cp < 0 || cp > 0x10FFFF || (cp >= 0xD800 && cp <= 0xDFFF)
      return 0
    if cp < 128
      return 1
    tbl = Unicode.__load_table()
    sec_off = Unicode.__u32(tbl, 0)
    count = Unicode.__u32(tbl, 1)
    Unicode.__bsearch_range(tbl, sec_off, count, cp)

  -> .codepoint_age(cp)
    vid = Unicode.codepoint_age_id(cp)
    if vid <= 0 || vid > SUPPORTED_VERSIONS.size()
      return "Unassigned"
    v = SUPPORTED_VERSIONS[vid - 1]
    if v.ends_with?(".0")
      return v.slice(0, v.size() - 2)
    v

  -> .assigned?(cp, version = nil)
    vid = Unicode.codepoint_age_id(cp)
    if vid == 0
      return false
    target_vid = Unicode.version_id(version)
    vid <= target_vid

  -> .valid?(str, version = nil)
    if type(str) == "Codepoint" || type(str) == "Char"
      return Unicode.assigned?(str.codepoint(), version)
    if type(str) == "Int"
      return Unicode.assigned?(str, version)
    s = str.to_s()
    # Verify well-formed UTF-8 bytes first
    n = s.size()
    raw = ByteArray.new(n)
    i = 0
    while i < n
      raw[i] = s.byte_at(i)
      i += 1
    if !raw.valid_utf8?()
      return false
    target_vid = Unicode.version_id(version)
    ok = true
    s.each_codepoint -> (cp)
      if ok
        if cp < 0 || cp > 0x10FFFF || (cp >= 0xD800 && cp <= 0xDFFF)
          ok = false
        else
          vid = Unicode.codepoint_age_id(cp)
          if vid == 0 || vid > target_vid
            ok = false
    ok

  -> .verify!(str, version = nil)
    ver_str = Unicode.normalize_version(version)
    target_vid = Unicode.version_id(ver_str)
    s = str.to_s()
    n = s.size()
    raw = ByteArray.new(n)
    i = 0
    while i < n
      raw[i] = s.byte_at(i)
      i += 1
    if !raw.valid_utf8?()
      raise EncodingError.new("invalid UTF-8 byte sequence")
    s.each_codepoint -> (cp)
      vid = Unicode.codepoint_age_id(cp)
      if vid == 0 || vid > target_vid
        hex = cp.to_s(16).upcase()
        while hex.size() < 4
          hex = "0" + hex
        raise EncodingError.new("codepoint U+" + hex + " is unassigned in Unicode " + ver_str)
    s

  -> .combining_class(cp, version = nil)
    if cp < 0x300 || cp > 0x10FFFF || (cp >= 0xD800 && cp <= 0xDFFF)
      return 0
    if version != nil
      target_vid = Unicode.version_id(version)
      vid = Unicode.codepoint_age_id(cp)
      if vid == 0 || vid > target_vid
        return 0
    tbl = Unicode.__load_table()
    sec_off = Unicode.__u32(tbl, 2)
    count = Unicode.__u32(tbl, 3)
    res = Unicode.__bsearch_kv(tbl, sec_off, count, cp)
    res < 0 ? 0 : res

  # ----------------------------------- UAX #11 East Asian Width & Display --

  -> .east_asian_width(cp)
    if cp < 0 || cp > 0x10FFFF || (cp >= 0xD800 && cp <= 0xDFFF)
      return "N"
    if cp >= 0x20 && cp < 0x7F
      return "Na"
    if cp < 0x80
      return "N"
    tbl = Unicode.__load_table()
    sec_off = Unicode.__u32(tbl, 4)
    count = Unicode.__u32(tbl, 5)
    id = Unicode.__bsearch_range(tbl, sec_off, count, cp)
    EAW_CODES[id]

  -> .char_width(cp, ambiguous_width = 1)
    if cp <= 0 || (cp < 0x20) || (cp >= 0x7F && cp < 0xA0)
      return 0
    if cp == 0x00AD
      return 1
    # Zero-width format & combining marks
    if cp == 0x200B || cp == 0x200C || cp == 0x200D || cp == 0xFEFF || (cp >= 0xFE00 && cp <= 0xFE0F) || (cp >= 0xE0100 && cp <= 0xE01EF)
      return 0
    cd = Codepoint.new(cp)
    if cd.mark?() || cd.category() == "Cf"
      return 0
    eaw = Unicode.east_asian_width(cp)
    if eaw == "W" || eaw == "F"
      return 2
    if eaw == "A"
      return ambiguous_width
    1

  -> .display_width(str, ambiguous_width = 1)
    s = str.to_s()
    if s.empty?()
      return 0
    total = 0
    s.each_grapheme -> (g)
      cps = g.codepoints().to_a()
      if cps.size() > 0
        c0 = cps[0]
        # Emoji ZWJ / Regional Indicator sequences occupy 2 columns
        if cps.size() > 1 && (g.include?("\u200D") || (c0 >= 0x1F1E6 && c0 <= 0x1F1FF) || cps.include?(0xFE0F))
          total += 2
        else
          w = Unicode.char_width(c0, ambiguous_width)
          total += w
    total

  # --------------------------------- UAX #9 Bidirectional Algorithm (Bidi) --

  -> .bidi_class(cp)
    if cp < 0 || cp > 0x10FFFF || (cp >= 0xD800 && cp <= 0xDFFF)
      return "L"
    tbl = Unicode.__load_table()
    sec_off = Unicode.__u32(tbl, 6)
    count = Unicode.__u32(tbl, 7)
    packed = Unicode.__bsearch_range(tbl, sec_off, count, cp)
    BIDI_CLASSES[packed & 0x3F]

  -> .bidi_mirrored?(cp)
    if cp < 0 || cp > 0x10FFFF || (cp >= 0xD800 && cp <= 0xDFFF)
      return false
    tbl = Unicode.__load_table()
    sec_off = Unicode.__u32(tbl, 6)
    count = Unicode.__u32(tbl, 7)
    packed = Unicode.__bsearch_range(tbl, sec_off, count, cp)
    ((packed >> 6) & 1) == 1

  -> .bidi_mirror(cp)
    case cp
    when 0x0028 then 0x0029
    when 0x0029 then 0x0028
    when 0x003C then 0x003E
    when 0x003E then 0x003C
    when 0x005B then 0x005D
    when 0x005D then 0x005B
    when 0x007B then 0x007D
    when 0x007D then 0x007B
    when 0x00AB then 0x00BB
    when 0x00BB then 0x00AB
    when 0x2039 then 0x203A
    when 0x203A then 0x2039
    when 0x2045 then 0x2046
    when 0x2046 then 0x2045
    when 0x207D then 0x207E
    when 0x207E then 0x207D
    when 0x208D then 0x208E
    when 0x208E then 0x208D
    when 0x2308 then 0x2309
    when 0x2309 then 0x2308
    when 0x230A then 0x230B
    when 0x230B then 0x230A
    when 0x2329 then 0x232A
    when 0x232A then 0x2329
    when 0x2768 then 0x2769
    when 0x2769 then 0x2768
    when 0x276A then 0x276B
    when 0x276B then 0x276A
    when 0x276C then 0x276D
    when 0x276D then 0x276C
    when 0x276E then 0x276F
    when 0x276F then 0x276E
    when 0x2770 then 0x2771
    when 0x2771 then 0x2770
    when 0x2772 then 0x2773
    when 0x2773 then 0x2772
    when 0x2774 then 0x2775
    when 0x2775 then 0x2774
    when 0x27E6 then 0x27E7
    when 0x27E7 then 0x27E6
    when 0x27E8 then 0x27E9
    when 0x27E9 then 0x27E8
    when 0x27EA then 0x27EB
    when 0x27EB then 0x27EA
    when 0x27EC then 0x27ED
    when 0x27ED then 0x27EC
    when 0x27EE then 0x27EF
    when 0x27EF then 0x27EE
    when 0x3008 then 0x3009
    when 0x3009 then 0x3008
    when 0x300A then 0x300B
    when 0x300B then 0x300A
    when 0x300C then 0x300D
    when 0x300D then 0x300C
    when 0x300E then 0x300F
    when 0x300F then 0x300E
    when 0x3010 then 0x3011
    when 0x3011 then 0x3010
    when 0x3014 then 0x3015
    when 0x3015 then 0x3014
    when 0x3016 then 0x3017
    when 0x3017 then 0x3016
    when 0x3018 then 0x3019
    when 0x3019 then 0x3018
    when 0x301A then 0x301B
    when 0x301B then 0x301A
    when 0xFF08 then 0xFF09
    when 0xFF09 then 0xFF08
    when 0xFF1C then 0xFF1E
    when 0xFF1E then 0xFF1C
    when 0xFF3B then 0xFF3D
    when 0xFF3D then 0xFF3B
    when 0xFF5B then 0xFF5D
    when 0xFF5D then 0xFF5B
    else cp

  -> .bidi_control?(cp)
    cp == 0x061C || cp == 0x200E || cp == 0x200F || (cp >= 0x202A && cp <= 0x202E) || (cp >= 0x2066 && cp <= 0x2069)

  # UAX #9 Rules P2-P3: find the first strong directional character outside isolates.
  -> .bidi_direction(str)
    s = str.to_s()
    isolate_depth = 0
    dir = :neutral
    s.each_codepoint -> (cp)
      if dir == :neutral
        if cp >= 0x2066 && cp <= 0x2068
          isolate_depth += 1
        elsif cp == 0x2069
          if isolate_depth > 0
            isolate_depth -= 1
        elsif isolate_depth == 0
          cls = Unicode.bidi_class(cp)
          if cls == "L"
            dir = :ltr
          elsif cls == "R" || cls == "AL"
            dir = :rtl
    dir

  # UAX #9 & UTS #39 Bidi safety check: verifies that explicit embeddings/overrides
  # (LRE, RLE, LRO, RLO .. PDF) and isolates (LRI, RLI, FSI .. PDI) are balanced
  # within every line.
  -> .bidi_safe?(str)
    s = str.to_s()
    embed_depth = 0
    isolate_depth = 0
    safe = true
    s.each_codepoint -> (cp)
      if safe
        if cp == 0x0A || cp == 0x0D || cp == 0x85 || cp == 0x2028 || cp == 0x2029
          if embed_depth != 0 || isolate_depth != 0
            safe = false
        elsif cp == 0x202C
          if embed_depth <= 0
            safe = false
          else
            embed_depth -= 1
        elsif cp >= 0x202A && cp <= 0x202E
          embed_depth += 1
        elsif cp >= 0x2066 && cp <= 0x2068
          isolate_depth += 1
        elsif cp == 0x2069
          if isolate_depth <= 0
            safe = false
          else
            isolate_depth -= 1
    safe && embed_depth == 0 && isolate_depth == 0

  # ------------------------------------------ UAX #24 Script & UTS #39 --

  -> .script(cp)
    if cp < 0 || cp > 0x10FFFF || (cp >= 0xD800 && cp <= 0xDFFF)
      return "Common"
    tbl = Unicode.__load_table()
    sec_off = Unicode.__u32(tbl, 8)
    count = Unicode.__u32(tbl, 9)
    id = Unicode.__bsearch_range(tbl, sec_off, count, cp)
    SCRIPTS[id]

  -> .scripts(str)
    out = []
    str.to_s().each_codepoint -> (cp)
      sc = Unicode.script(cp)
      if !out.include?(sc)
        out.push(sc)
    out

  # UTS #39 §5 Mixed-Script Detection: true if the string mixes more than one
  # non-Common/non-Inherited script in an incompatible way (e.g. Latin + Cyrillic).
  -> .mixed_script?(str)
    real_scripts = []
    str.to_s().each_codepoint -> (cp)
      sc = Unicode.script(cp)
      if sc != "Common" && sc != "Inherited"
        if !real_scripts.include?(sc)
          real_scripts.push(sc)
    if real_scripts.size() <= 1
      return false
    # Standard East Asian combinations allowed by UTS #39 (Han + Hiragana + Katakana + Latin, or Han + Hangul + Latin, or Han + Bopomofo + Latin)
    jp_allowed = true
    kr_allowed = true
    zh_allowed = true
    i = 0
    while i < real_scripts.size()
      sc = real_scripts[i]
      if sc != "Latin" && sc != "Han" && sc != "Hiragana" && sc != "Katakana"
        jp_allowed = false
      if sc != "Latin" && sc != "Han" && sc != "Hangul"
        kr_allowed = false
      if sc != "Latin" && sc != "Han" && sc != "Bopomofo"
        zh_allowed = false
      i += 1
    if jp_allowed || kr_allowed || zh_allowed
      return false
    true

  # UTS #39 §4 Confusable Detection (skeleton algorithm):
  # NFD -> map Cyrillic/Greek/Latin visual homographs to canonical Latin skeleton -> NFD.
  -> .__confusable_map_cp(cp)
    case cp
    when 0x0430, 0x0410, 0x03B1, 0x0391 then "a" # Cyrillic/Greek a/A
    when 0x0432, 0x0412, 0x0392 then "b"         # Cyrillic ve / Greek Beta
    when 0x0441, 0x0421, 0x03F2, 0x03F9 then "c" # Cyrillic es / Greek lunate sigma
    when 0x0501 then "d"                         # Cyrillic komi de
    when 0x0435, 0x0415, 0x03B5, 0x0395 then "e" # Cyrillic ie / Greek epsilon
    when 0x04BB, 0x04BA, 0x0397 then "h"         # Cyrillic shha / Greek Eta
    when 0x0456, 0x0406, 0x03B9, 0x0399, 0x0131 then "i" # Ukrainian i / Greek iota / dotless i
    when 0x0458, 0x0408, 0x03F3 then "j"         # Cyrillic je / Greek yot
    when 0x043A, 0x041A, 0x03BA, 0x039A then "k" # Cyrillic ka / Greek kappa
    when 0x04CF, 0x04C0, 0x0049, 0x006C then "l" # Palochka / I / l
    when 0x043C, 0x041C, 0x039C then "m"         # Cyrillic em / Greek Mu
    when 0x03BD, 0x039D then "n"                 # Greek nu / Nu
    when 0x043E, 0x041E, 0x03BF, 0x039F then "o" # Cyrillic o / Greek omicron
    when 0x0440, 0x0420, 0x03C1, 0x03A1 then "p" # Cyrillic er / Greek rho
    when 0x0455, 0x0405 then "s"                 # Cyrillic dze
    when 0x0442, 0x0422, 0x03C4, 0x03A4 then "t" # Cyrillic te / Greek tau
    when 0x03C5, 0x03A5 then "u"                 # Greek upsilon
    when 0x0475, 0x0474, 0x03BD then "v"         # Cyrillic izhitsa
    when 0x0445, 0x0425, 0x03C7, 0x03A7 then "x" # Cyrillic ha / Greek chi
    when 0x0443, 0x0423, 0x03B3 then "y"         # Cyrillic u / Greek gamma
    when 0x0396 then "z"                         # Greek Zeta
    else
      Unicode.__full_casefold_cp(cp)

  -> .confusable_skeleton(str)
    s = Unicode.normalize(str.to_s(), :nfkd)
    sb = StringBuffer(s.size() + 8)
    s.each_codepoint -> (cp)
      mapped = Unicode.__confusable_map_cp(cp)
      if mapped == "I" || mapped == "l" || mapped == "1"
        sb << "l"
      else
        sb << mapped
    Unicode.normalize(sb.to_s(), :nfd)

  -> .confusable?(a, b)
    Unicode.confusable_skeleton(a) == Unicode.confusable_skeleton(b)

  # ------------------- UAX #15 Multi-Version Normalization & Canonicalize --

  -> .__decomp_one(tbl, cp, compat, target_vid, out)
    # Unassigned in target_vid: does not decompose
    vid = Unicode.codepoint_age_id(cp)
    if vid == 0 || vid > target_vid
      out.push(cp)
      return nil
    # Corrigendum #4 (Unicode 3.2.0 / 4.0.0, target_vid <= 7)
    if target_vid <= 7
      if cp == 0x2F868
        out.push(0x2136A)
        return nil
      if cp == 0x2F874
        out.push(0x5F33)
        return nil
      if cp == 0x2F91F
        out.push(0x43AB)
        return nil
      if cp == 0x2F95F
        out.push(0x7AAE)
        return nil
      if cp == 0x2F9BF
        out.push(0x4D57)
        return nil
    # Hangul syllable algorithmic decomposition (Age 2.0, vid == 2)
    if cp >= 0xAC00 && cp < 0xD7A4 && target_vid >= 2
      si = cp - 0xAC00
      out.push(0x1100 + (si / 588))
      out.push(0x1161 + ((si % 588) / 28))
      t = si % 28
      if t != 0
        out.push(0x11A7 + t)
      return nil
    sec_off = compat ? Unicode.__u32(tbl, 12) : Unicode.__u32(tbl, 10)
    count = compat ? Unicode.__u32(tbl, 13) : Unicode.__u32(tbl, 11)
    packed = Unicode.__bsearch_kv(tbl, sec_off, count, cp)
    if packed < 0
      out.push(cp)
      return nil
    pool_off = Unicode.__u32(tbl, 14)
    idx = (packed >> 8) & 0xFFFFFF
    len = packed & 0xFF
    # Verify all target codepoints were assigned in target_vid
    k = 0
    all_assigned = true
    while k < len
      d_cp = Unicode.__u32(tbl, pool_off + idx + k)
      d_vid = Unicode.codepoint_age_id(d_cp)
      if d_vid == 0 || d_vid > target_vid
        all_assigned = false
      k += 1
    if !all_assigned
      out.push(cp)
      return nil
    k = 0
    while k < len
      out.push(Unicode.__u32(tbl, pool_off + idx + k))
      k += 1
    nil

  -> .__try_compose(tbl, a, b, target_vid)
    if target_vid >= 2
      if a >= 0x1100 && a < 0x1113 && b >= 0x1161 && b < 0x1176
        return 0xAC00 + (((a - 0x1100) * 21) + (b - 0x1161)) * 28
      if a >= 0xAC00 && a < 0xD7A4 && ((a - 0xAC00) % 28) == 0 && b > 0x11A7 && b < 0x11C3
        return a + (b - 0x11A7)
    comp_off = Unicode.__u32(tbl, 16)
    comp_count = Unicode.__u32(tbl, 17)
    lo = 0
    hi = comp_count
    while lo < hi
      mid = (lo + hi) >> 1
      w_off = comp_off + mid * 3
      ca = Unicode.__u32(tbl, w_off)
      cb = Unicode.__u32(tbl, w_off + 1)
      if a < ca || (a == ca && b < cb)
        hi = mid
      elsif a > ca || (a == ca && b > cb)
        lo = mid + 1
      else
        comp_cp = Unicode.__u32(tbl, w_off + 2)
        c_vid = Unicode.codepoint_age_id(comp_cp)
        if c_vid > 0 && c_vid <= target_vid
          return comp_cp
        return -1
    -1

  -> .canonical_decompose_cp(cp)
    tbl = Unicode.__load_table()
    out = []
    Unicode.__decomp_one(tbl, cp, false, 28, out)
    out

  -> .canonical_compose_pair(a, b)
    tbl = Unicode.__load_table()
    Unicode.__try_compose(tbl, a, b, 28)

  -> .normalize(str, form = :nfc, version = nil)
    s = str.to_s()
    if s.empty?()
      return s
    f_sym = form.to_s().downcase()
    if f_sym.starts_with?(":")
      f_sym = f_sym.slice(1, f_sym.size() - 1)
    if f_sym == "nfkc_casefold" || f_sym == "nfkc_cf" || f_sym == "kc_cf"
      return Unicode.casefold(Unicode.normalize(s, :nfkc, version)).nfc()
    if s.ascii?()
      return s
    is_compat = (f_sym == "nfkc" || f_sym == "kc" || f_sym == "nfkd" || f_sym == "kd")
    is_compose = (f_sym == "nfc" || f_sym == "c" || f_sym == "nfkc" || f_sym == "kc")
    if !is_compat && !is_compose && f_sym != "nfd" && f_sym != "d"
      raise ArgumentError.new("unknown normalization form: " + form.to_s())

    target_vid = Unicode.version_id(version)
    # Fast path for Unicode 16.0.0+
    if target_vid == 27
      if is_compat
        return is_compose ? ccall("w_string_normalize", s, 2) : ccall("w_string_normalize", s, 3)
      return is_compose ? ccall("w_string_normalize", s, 0) : ccall("w_string_normalize", s, 1)

    tbl = Unicode.__load_table()
    buf = []
    s.each_codepoint -> (cp)
      Unicode.__decomp_one(tbl, cp, is_compat, target_vid, buf)

    # Canonical ordering
    ccc_off = Unicode.__u32(tbl, 2)
    ccc_count = Unicode.__u32(tbl, 3)
    n = buf.size()
    i = 1
    while i < n
      cp_i = buf[i]
      cc_i = 0
      if cp_i >= 0x300 && Unicode.codepoint_age_id(cp_i) <= target_vid
        r = Unicode.__bsearch_kv(tbl, ccc_off, ccc_count, cp_i)
        if r > 0
          cc_i = r
      if cc_i != 0
        cp_prev = buf[i - 1]
        cc_prev = 0
        if cp_prev >= 0x300 && Unicode.codepoint_age_id(cp_prev) <= target_vid
          r_prev = Unicode.__bsearch_kv(tbl, ccc_off, ccc_count, cp_prev)
          if r_prev > 0
            cc_prev = r_prev
        if cc_prev > cc_i
          buf[i - 1] = cp_i
          buf[i] = cp_prev
          if i > 1
            i -= 1
          else
            i += 1
        else
          i += 1
      else
        i += 1

    if is_compose && buf.size() > 0
      out = [buf[0]]
      cc0 = 0
      if buf[0] >= 0x300 && Unicode.codepoint_age_id(buf[0]) <= target_vid
        r0 = Unicode.__bsearch_kv(tbl, ccc_off, ccc_count, buf[0])
        if r0 > 0
          cc0 = r0
      starter = cc0 == 0 ? 0 : -1
      last_cc = cc0
      j = 1
      while j < buf.size()
        cp = buf[j]
        cc = 0
        if cp >= 0x300 && Unicode.codepoint_age_id(cp) <= target_vid
          rj = Unicode.__bsearch_kv(tbl, ccc_off, ccc_count, cp)
          if rj > 0
            cc = rj
        # PR-29: pre-4.1.0 (target_vid <= 7) used (last_cc == 0 || last_cc != cc)
        can_try = target_vid <= 7 ? (last_cc == 0 || last_cc != cc) : (last_cc == 0 || last_cc < cc)
        composed = -1
        if starter >= 0 && can_try
          composed = Unicode.__try_compose(tbl, out[starter], cp, target_vid)
        if composed >= 0
          out[starter] = composed
        else
          out.push(cp)
          if cc == 0
            starter = out.size() - 1
          last_cc = cc
        j += 1
      buf = out

    sb = StringBuffer(buf.size() * 4)
    k = 0
    while k < buf.size()
      sb << buf[k].chr()
      k += 1
    sb.to_s()

  -> .normalized?(str, form = :nfc, version = nil)
    s = str.to_s()
    s == Unicode.normalize(s, form, version)

  # Verify repertoire for `version` and return canonical NFC form.
  -> .canonicalize(str, version = nil)
    Unicode.verify!(str, version)
    Unicode.normalize(str, :nfc, version)

  -> .canonically_equivalent?(a, b, version = nil)
    Unicode.normalize(a.to_s(), :nfc, version) == Unicode.normalize(b.to_s(), :nfc, version)

  -> .compat_equivalent?(a, b, version = nil)
    Unicode.normalize(a.to_s(), :nfkc, version) == Unicode.normalize(b.to_s(), :nfkc, version)

  # UAX #15 §13 Stream-Safe Text Process: inserts U+034F (COMBINING GRAPHEME
  # JOINER) if a sequence of non-starters (ccc > 0) exceeds 30.
  -> .stream_safe(str, version = nil)
    s = Unicode.normalize(str.to_s(), :nfd, version)
    sb = StringBuffer(s.size() + 16)
    non_starters = 0
    s.each_codepoint -> (cp)
      cc = cp == 0x034F ? 0 : Unicode.combining_class(cp, version)
      if cc == 0
        non_starters = 0
      else
        non_starters += 1
        if non_starters > 30
          sb << 0x034F.chr()
          non_starters = 1
      sb << cp.chr()
    sb.to_s()

  # --------------- Unicode Standard §3.13 Full Case Mapping & Case Folding --

  -> .__full_upcase_cp(cp)
    case cp
    when 0x00DF then "SS"
    when 0x0149 then "\u02BCN"
    when 0x01F0 then "J\u030C"
    when 0x0390 then "\u0399\u0308\u0301"
    when 0x03B0 then "\u03A5\u0308\u0301"
    when 0x0587 then "\u0535\u0552"
    when 0x1E96 then "H\u0331"
    when 0x1E97 then "T\u0308"
    when 0x1E98 then "W\u030A"
    when 0x1E99 then "Y\u030A"
    when 0x1E9A then "A\u02BE"
    when 0x1F50 then "\u03A5\u0313"
    when 0x1F52 then "\u03A5\u0313\u0300"
    when 0x1F54 then "\u03A5\u0313\u0301"
    when 0x1F56 then "\u03A5\u0313\u0342"
    when 0x1FB6 then "\u0391\u0342"
    when 0x1FC6 then "\u0397\u0342"
    when 0x1FD6 then "\u0399\u0342"
    when 0x1FE6 then "\u03A5\u0342"
    when 0x1FF6 then "\u03A9\u0342"
    when 0xFB00 then "FF"
    when 0xFB01 then "FI"
    when 0xFB02 then "FL"
    when 0xFB03 then "FFI"
    when 0xFB04 then "FFL"
    when 0xFB05 then "ST"
    when 0xFB06 then "ST"
    else
      Codepoint.new(cp).upcase().to_s()

  -> .__full_titlecase_cp(cp)
    case cp
    when 0x00DF then "Ss"
    when 0xFB00 then "Ff"
    when 0xFB01 then "Fi"
    when 0xFB02 then "Fl"
    when 0xFB03 then "Ffi"
    when 0xFB04 then "Ffl"
    when 0xFB05 then "St"
    when 0xFB06 then "St"
    else
      Codepoint.new(cp).titlecase().to_s()

  -> .__full_casefold_cp(cp)
    case cp
    when 0x00DF, 0x1E9E then "ss"
    when 0x00B5 then "\u03BC"
    when 0x0130 then "i\u0307"
    when 0x0149 then "\u02BCn"
    when 0x017F then "s"
    when 0x0345 then "\u03B9"
    when 0x0390 then "\u03B9\u0308\u0301"
    when 0x03B0 then "\u03C5\u0308\u0301"
    when 0x03C2 then "\u03C3"
    when 0x0587 then "\u0565\u0582"
    when 0xFB00 then "ff"
    when 0xFB01 then "fi"
    when 0xFB02 then "fl"
    when 0xFB03 then "ffi"
    when 0xFB04 then "ffl"
    when 0xFB05, 0xFB06 then "st"
    else
      if cp == 0x0130
        return "i\u0307"
      Codepoint.new(cp).casefold().to_s()

  -> .upcase(str)
    s = str.to_s()
    if s.ascii?()
      return s.upcase()
    sb = StringBuffer(s.size() * 2)
    s.each_codepoint -> (cp)
      sb << Unicode.__full_upcase_cp(cp)
    sb.to_s()

  -> .downcase(str)
    s = str.to_s()
    if s.ascii?()
      return s.downcase()
    cps = s.codepoints().to_a()
    n = cps.size()
    sb = StringBuffer(s.size() + 8)
    i = 0
    while i < n
      cp = cps[i]
      if cp == 0x0130
        sb << "i\u0307"
      elsif cp == 0x03A3
        # Final_Sigma context rule (Unicode Standard Table 3-17):
        # Preceded by a cased letter (ignoring case-ignorable) and NOT followed by one
        has_before = false
        j = i - 1
        while j >= 0
          prev_cd = Codepoint.new(cps[j])
          if prev_cd.mark?()
            j -= 1
          else
            has_before = prev_cd.letter?()
            j = -1
        has_after = false
        j = i + 1
        while j < n
          next_cd = Codepoint.new(cps[j])
          if next_cd.mark?()
            j += 1
          else
            has_after = next_cd.letter?()
            j = n
        if has_before && !has_after
          sb << "\u03C2"
        else
          sb << "\u03C3"
      else
        sb << Codepoint.new(cp).downcase().to_s()
      i += 1
    sb.to_s()

  -> .titlecase(str)
    s = str.to_s()
    sb = StringBuffer(s.size() + 8)
    in_word = false
    s.each_codepoint -> (cp)
      cd = Codepoint.new(cp)
      if cd.letter?() || cd.number?()
        if !in_word
          sb << Unicode.__full_titlecase_cp(cp)
          in_word = true
        else
          sb << (cp == 0x0130 ? "i\u0307" : cd.downcase().to_s())
      elsif !cd.mark?()
        in_word = false
        sb << cp.chr()
      else
        sb << cp.chr()
    sb.to_s()

  -> .casefold(str)
    s = str.to_s()
    if s.ascii?()
      return s.downcase()
    sb = StringBuffer(s.size() + 8)
    s.each_codepoint -> (cp)
      sb << Unicode.__full_casefold_cp(cp)
    sb.to_s()

  # Unicode Standard §3.13 Caseless Matching (D144-D147):
  #   :default       (D144) toCasefold(X) == toCasefold(Y)
  #   :canonical     (D145) NFD(toCasefold(NFD(X))) == NFD(toCasefold(NFD(Y)))
  #   :compatibility (D146) NFKD(toCasefold(NFKD(toCasefold(NFD(X))))) == ...
  #   :identifier    (D147) NFKC_Casefold(NFD(X)) == NFKC_Casefold(NFD(Y))
  -> .caseless_equal?(a, b, mode = :default, version = nil)
    sa = a.to_s()
    sb = b.to_s()
    m = mode.to_s().downcase()
    if m.starts_with?(":")
      m = m.slice(1, m.size() - 1)
    if m == "default"
      return Unicode.casefold(sa) == Unicode.casefold(sb)
    if m == "canonical"
      ca = Unicode.normalize(Unicode.casefold(Unicode.normalize(sa, :nfd, version)), :nfd, version)
      cb = Unicode.normalize(Unicode.casefold(Unicode.normalize(sb, :nfd, version)), :nfd, version)
      return ca == cb
    if m == "compatibility" || m == "compat"
      ca = Unicode.normalize(Unicode.casefold(Unicode.normalize(Unicode.casefold(Unicode.normalize(sa, :nfd, version)), :nfkd, version)), :nfkd, version)
      cb = Unicode.normalize(Unicode.casefold(Unicode.normalize(Unicode.casefold(Unicode.normalize(sb, :nfd, version)), :nfkd, version)), :nfkd, version)
      return ca == cb
    if m == "identifier"
      ca = Unicode.normalize(Unicode.normalize(sa, :nfd, version), :nfkc_casefold, version)
      cb = Unicode.normalize(Unicode.normalize(sb, :nfd, version), :nfkc_casefold, version)
      return ca == cb
    raise ArgumentError.new("unknown caseless matching mode: " + mode.to_s())

  # ---------------- UAX #29 Text Segmentation (Graphemes, Words, Sentences) --

  -> .graphemes(str, version = nil)
    s = str.to_s()
    target_vid = Unicode.version_id(version)
    out = []
    if target_vid >= 26
      s.each_grapheme -> (g)
        out.push(g)
      return out
    # Pre-15.1.0 (target_vid < 26): split Indic_Conjunct_Break (GB9c) clusters
    # that were only joined by Virama/Linker (U+094D, U+09CD, U+0A4D, U+0ACD, U+0B4D, U+0BCD, U+0C4D, U+0CCD, U+0D4D)
    s.each_grapheme -> (g)
      cps = g.codepoints().to_a()
      if cps.size() <= 2
        out.push(g)
      else
        cur = StringBuffer(16)
        i = 0
        while i < cps.size()
          cp = cps[i]
          cur << cp.chr()
          is_virama = (cp == 0x094D || cp == 0x09CD || cp == 0x0A4D || cp == 0x0ACD || cp == 0x0B4D || cp == 0x0BCD || cp == 0x0C4D || cp == 0x0CCD || cp == 0x0D4D)
          if is_virama && i + 1 < cps.size() && cps[i + 1] != 0x200D
            out.push(cur.to_s())
            cur = StringBuffer(16)
          i += 1
        rem = cur.to_s()
        if !rem.empty?()
          out.push(rem)
    out

  # UAX #29 §4 Word Boundaries: returns an Array of word tokens (sequences of
  # letters/numbers connected by internal apostrophes/connectors/numeric separators).
  -> .words(str)
    s = str.to_s()
    cps = s.codepoints().to_a()
    n = cps.size()
    out = []
    i = 0
    while i < n
      cp = cps[i]
      cd = Codepoint.new(cp)
      if cd.letter?() || cd.number?()
        buf = StringBuffer(16)
        buf << cp.chr()
        i += 1
        while i < n
          ncp = cps[i]
          ncd = Codepoint.new(ncp)
          if ncd.letter?() || ncd.number?() || ncd.mark?() || ncp == 95 || ncp == 0x200D
            buf << ncp.chr()
            i += 1
          elsif (ncp == 0x27 || ncp == 0x2019 || ncp == 0x2E || ncp == 0x2C || ncp == 0x3A) && i + 1 < n
            after_cd = Codepoint.new(cps[i + 1])
            if after_cd.letter?() || after_cd.number?()
              buf << ncp.chr()
              i += 1
            else
              break
          else
            break
        out.push(buf.to_s())
      else
        i += 1
    out

  # UAX #29 §5 Sentence Boundaries: splits text into sentences at ATerm/STerm
  # (. ! ? ۔ 。 ！ ？) followed by optional Close/Sp/Sep.
  -> .sentences(str)
    s = str.to_s()
    cps = s.codepoints().to_a()
    n = cps.size()
    out = []
    cur = StringBuffer(64)
    i = 0
    while i < n
      cp = cps[i]
      cur << cp.chr()
      is_term = (cp == 0x2E || cp == 0x21 || cp == 0x3F || cp == 0x06D4 || cp == 0x3002 || cp == 0xFF01 || cp == 0xFF1F || cp == 0x2026)
      is_para = (cp == 0x0A || cp == 0x2028 || cp == 0x2029)
      if is_para
        out.push(cur.to_s())
        cur = StringBuffer(64)
      elsif is_term
        # Consume trailing close quotes/brackets and whitespace
        while i + 1 < n
          ncp = cps[i + 1]
          if ncp == 0x22 || ncp == 0x27 || ncp == 0x29 || ncp == 0x5D || ncp == 0x201D || ncp == 0x2019 || ncp == 0xBB
            i += 1
            cur << ncp.chr()
          else
            break
        had_space = false
        while i + 1 < n
          ncp = cps[i + 1]
          if ncp == 0x20 || ncp == 0x09 || ncp == 0x0A || ncp == 0x0D
            had_space = true
            i += 1
            cur << ncp.chr()
          else
            break
        if had_space || cp == 0x3002 || cp == 0xFF01 || cp == 0xFF1F || i + 1 == n
          out.push(cur.to_s())
          cur = StringBuffer(64)
      i += 1
    rem = cur.to_s()
    if !rem.empty?()
      out.push(rem)
    out

  # ---------------------------- UAX #14 Line Breaking Opportunities --

  -> .line_breaks(str)
    s = str.to_s()
    cps = s.codepoints().to_a()
    n = cps.size()
    out = []
    cur = StringBuffer(32)
    i = 0
    while i < n
      cp = cps[i]
      cur << cp.chr()
      # LB4/LB5 Mandatory breaks (BK, CR+LF, CR, LF, NL)
      if cp == 0x0D && i + 1 < n && cps[i + 1] == 0x0A
        i += 1
        cur << 0x0A.chr()
        out.push(cur.to_s())
        cur = StringBuffer(32)
      elsif cp == 0x0A || cp == 0x0D || cp == 0x0B || cp == 0x0C || cp == 0x85 || cp == 0x2028 || cp == 0x2029
        out.push(cur.to_s())
        cur = StringBuffer(32)
      elsif (cp == 0x20 || cp == 0x2D || Unicode.ideographic?(cp)) && i + 1 < n
        next_cp = cps[i + 1]
        # Do not break before non-starters, close punctuation, spaces, or glue (NBSP/WJ/ZWJ)
        if next_cp != 0x20 && next_cp != 0xA0 && next_cp != 0x2060 && next_cp != 0x200D && cp != 0xA0
          out.push(cur.to_s())
          cur = StringBuffer(32)
      i += 1
    rem = cur.to_s()
    if !rem.empty?()
      out.push(rem)
    out

  # ------------ UAX #31 Identifier & Pattern Syntax + UAX #38 + UTS #51 --

  -> .pattern_white_space?(cp)
    (cp >= 0x09 && cp <= 0x0D) || cp == 0x20 || cp == 0x85 || cp == 0x200E || cp == 0x200F || cp == 0x2028 || cp == 0x2029

  -> .pattern_syntax?(cp)
    (cp >= 0x21 && cp <= 0x2F) || (cp >= 0x3A && cp <= 0x40) || (cp >= 0x5B && cp <= 0x5E) || cp == 0x60 || (cp >= 0x7B && cp <= 0x7E) || (cp >= 0x2190 && cp <= 0x2BFF) || (cp >= 0x3001 && cp <= 0x3030)

  -> .valid_identifier?(str, version = nil)
    s = str.to_s()
    if s.empty?()
      return false
    if !Unicode.valid?(s, version)
      return false
    cps = s.codepoints().to_a()
    first_cd = Codepoint.new(cps[0])
    if !first_cd.xid_start() && cps[0] != 95
      return false
    i = 1
    while i < cps.size()
      cd = Codepoint.new(cps[i])
      if !cd.xid_continue() && cps[i] != 0x200C && cps[i] != 0x200D
        return false
      i += 1
    true

  -> .ideographic?(cp)
    (cp >= 0x3400 && cp <= 0x4DBF) || (cp >= 0x4E00 && cp <= 0x9FFF) || (cp >= 0xF900 && cp <= 0xFAFF) || (cp >= 0x20000 && cp <= 0x2FA1F) || (cp >= 0x30000 && cp <= 0x323AF)

  -> .extended_pictographic?(cp)
    (cp >= 0x1F300 && cp <= 0x1FAF8) || (cp >= 0x2600 && cp <= 0x27BF) || (cp >= 0x2300 && cp <= 0x23FF) || (cp >= 0x1F000 && cp <= 0x1F2FF) || cp == 0x00A9 || cp == 0x00AE || cp == 0x203C || cp == 0x2049 || cp == 0x2122 || cp == 0x2139 || (cp >= 0x2194 && cp <= 0x21AA) || cp == 0x3030 || cp == 0x303D || cp == 0x3297 || cp == 0x3299

  -> .emoji?(cp)
    Unicode.extended_pictographic?(cp) || (cp >= 0x1F1E6 && cp <= 0x1F1FF) || (cp >= 0x1F3FB && cp <= 0x1F3FF) || cp == 0x23 || cp == 0x2A || (cp >= 0x30 && cp <= 0x39)

  -> .emoji_presentation?(cp)
    (cp >= 0x1F300 && cp <= 0x1FAF8) || (cp >= 0x1F1E6 && cp <= 0x1F1FF) || (cp >= 0x231A && cp <= 0x231B) || (cp >= 0x23E9 && cp <= 0x23F3) || (cp >= 0x25FD && cp <= 0x25FE) || cp == 0x2614 || cp == 0x2615 || (cp >= 0x2648 && cp <= 0x2653) || cp == 0x267F || cp == 0x2693 || cp == 0x26A1 || (cp >= 0x26AA && cp <= 0x26AB) || (cp >= 0x26BD && cp <= 0x26BE) || (cp >= 0x26C4 && cp <= 0x26C5) || cp == 0x26CE || cp == 0x26D4 || cp == 0x26EA || (cp >= 0x26F2 && cp <= 0x26F3) || cp == 0x26F5 || cp == 0x26FA || cp == 0x26FD || cp == 0x2705 || (cp >= 0x270A && cp <= 0x270B) || cp == 0x2728 || cp == 0x274C || cp == 0x274E || (cp >= 0x2753 && cp <= 0x2755) || cp == 0x2757 || (cp >= 0x2795 && cp <= 0x2797) || cp == 0x27B0 || cp == 0x27BF || (cp >= 0x2B1B && cp <= 0x2B1C) || cp == 0x2B50 || cp == 0x2B55

  -> .emoji_modifier?(cp)
    cp >= 0x1F3FB && cp <= 0x1F3FF

  -> .emoji_modifier_base?(cp)
    (cp >= 0x1F385 && cp <= 0x1F4FF) || (cp >= 0x1F574 && cp <= 0x1F596) || (cp >= 0x1F645 && cp <= 0x1F64F) || (cp >= 0x1F6A3 && cp <= 0x1F6CC) || (cp >= 0x1F90C && cp <= 0x1F9FF) || (cp >= 0x1FAF0 && cp <= 0x1FAF8) || (cp >= 0x261D && cp <= 0x270D)
