# Regex Unicode, character-class, property, backref, and match-data helpers.
# Included by core/regex.w (first worker in the module-split dependency chain).

-> __regex_clex_raw(cp_in)
  cp = cp_in ## i64
  wvalue_bits(ccall("w_char_new", cp)) & 70368744177663

-> __regex_fold_pair_cp(cp_in)
  cp = cp_in ## i64
  if cp >= 65 && cp <= 90
    return cp + 32
  if cp >= 97 && cp <= 122
    return cp - 32
  if cp < 128
    return cp
  lx = __regex_clex_raw(cp) ## i64
  cat = (lx >> 3) & 31
  if cat != 0 && cat != 1 && cat != 2
    return cp
  raw = (lx >> 10) & 511
  delta = raw >= 256 ? raw - 512 : raw
  if delta == 0 || delta == -256
    return cp
  cp + delta

-> __regex_downcase_cp(cp_in)
  cp = cp_in ## i64
  if cp >= 65 && cp <= 90
    return cp + 32
  if cp < 128
    return cp
  lx = __regex_clex_raw(cp) ## i64
  cat = (lx >> 3) & 31
  if cat != 0 && cat != 2
    return cp
  raw = (lx >> 10) & 511
  delta = raw >= 256 ? raw - 512 : raw
  if delta == 0 || delta == -256
    return cp
  cp + delta

-> __regex_upcase_cp(cp_in)
  cp = cp_in ## i64
  if cp >= 97 && cp <= 122
    return cp - 32
  if cp < 128
    return cp
  lx = __regex_clex_raw(cp) ## i64
  cat = (lx >> 3) & 31
  if cat == 2
    return cp - 1
  if cat != 1
    return cp
  raw = (lx >> 10) & 511
  delta = raw >= 256 ? raw - 512 : raw
  if delta == 0 || delta == -256
    return cp
  cp + delta

-> __regex_downcase_lex_cp(lx_in)
  lx = lx_in ## i64
  cp = (lx >> 25) & 2097151
  cat = (lx >> 3) & 31
  if cat != 0 && cat != 2
    return cp
  raw = (lx >> 10) & 511
  delta = raw >= 256 ? raw - 512 : raw
  if delta == 0 || delta == -256
    return cp
  cp + delta

-> __regex_escape_str(str, specials)
  out = ""
  cs = str.chars()
  i = 0
  while i < cs.size()
    c = cs[i]
    if specials.include?(c)
      out = out + "\\" + c
    else
      out = out + c
    i = i + 1
  out

-> __regex_needs_escaping(str, specials)
  cs = str.chars()
  i = 0
  while i < cs.size()
    if specials.include?(cs[i])
      return true
    i = i + 1
  false

-> __regex_hex_val(cp_in)
  c = cp_in ## i64
  if c >= 48 && c <= 57
    return c - 48
  if c >= 65 && c <= 70
    return c - 55
  if c >= 97 && c <= 102
    return c - 87
  -1

-> __regex_normalize_prop_name(raw)
  s = ""
  cs = raw.chars()
  i = 0
  while i < cs.size()
    c = cs[i]
    if c != " " && c != "\t" && c != "_" && c != "-"
      s = s + c.downcase()
    i = i + 1
  if s.starts_with?("generalcategory=")
    s = s.slice(16, s.size() - 16)
  elsif s.starts_with?("gc=")
    s = s.slice(3, s.size() - 3)
  elsif s.starts_with?("script=")
    s = s.slice(7, s.size() - 7)
  elsif s.starts_with?("sc=")
    s = s.slice(3, s.size() - 3)
  elsif s.starts_with?("block=")
    s = "in" + s.slice(6, s.size() - 6)
  elsif s.starts_with?("blk=")
    s = "in" + s.slice(4, s.size() - 4)
  elsif s.starts_with?("is") && s.size() > 2
    s = s.slice(2, s.size() - 2)
  s

-> __regex_resolve_prop_cat_mask(norm)
  case norm
  when "lu", "uppercaseletter", "upper", "uppercase" then 1
  when "ll", "lowercaseletter", "lower", "lowercase" then 2
  when "lt", "titlecaseletter" then 4
  when "lm", "modifierletter" then 8
  when "lo", "otherletter" then 16
  when "lc", "casedletter" then 7
  when "l", "letter", "alpha", "alphabetic" then 31
  when "nd", "decimalnumber", "digit" then 32
  when "nl", "letternumber" then 64
  when "no", "othernumber" then 128
  when "n", "number" then 224
  when "alnum" then 63
  when "zs", "spaceseparator" then 256
  when "zl", "lineseparator" then 512
  when "zp", "paragraphseparator" then 1024
  when "z", "separator" then 1792
  when "mn", "nonspacingmark" then 2048
  when "mc", "spacingmark" then 4096
  when "me", "enclosingmark" then 8192
  when "m", "mark", "combiningmark" then 14336
  when "pc", "connectorpunctuation" then 16384
  when "pd", "dashpunctuation" then 32768
  when "ps", "openpunctuation" then 65536
  when "pe", "closepunctuation" then 131072
  when "pi", "initialpunctuation", "initialquotepunctuation" then 262144
  when "pf", "finalpunctuation", "finalquotepunctuation" then 524288
  when "po", "otherpunctuation" then 1048576
  when "p", "punct", "punctuation" then 2080768
  when "sm", "mathsymbol" then 2097152
  when "sc", "currencysymbol" then 4194304
  when "sk", "modifiersymbol" then 8388608
  when "so", "othersymbol" then 16777216
  when "s", "symbol" then 31457280
  when "cc", "control", "cntrl" then 33554432
  when "cf", "format" then 67108864
  when "cs", "surrogate" then 134217728
  when "co", "privateuse" then 268435456
  when "cn", "unassigned" then 536870912
  when "c", "other" then 1040187392
  when "assigned" then 536870911
  when "graph" then 33554175
  when "emoji" then 1073741824
  when "print" then 2147483648
  else 0

-> __regex_resolve_prop_cp_ranges(norm)
  case norm
  when "ascii", "inbasiclatin", "basiclatin"
    [[0, 127]]
  when "any"
    [[0, 1114111]]
  when "xdigit", "hexdigit"
    [[48, 57], [65, 70], [97, 102]]
  when "blank"
    [[9, 9], [32, 32], [160, 160], [5760, 5760], [8192, 8202], [8239, 8239], [8287, 8287], [12288, 12288]]
  when "space", "whitespace"
    [[9, 13], [32, 32], [133, 133], [160, 160], [5760, 5760], [8192, 8202], [8232, 8233], [8239, 8239], [8287, 8287], [12288, 12288]]
  when "latin", "latn"
    [[65, 90], [97, 122], [170, 170], [186, 186], [192, 214], [216, 246], [248, 696], [736, 740], [7424, 7461], [7468, 7516], [7522, 7525], [7531, 7679], [7680, 7935], [8305, 8305], [8319, 8319], [8336, 8348], [8490, 8491], [8498, 8498], [8526, 8526], [8544, 8584], [11360, 11391], [42786, 42887], [42891, 43007], [43824, 43866], [43872, 43880], [64256, 64262], [65313, 65338], [65345, 65370]]
  when "greek", "grek"
    [[880, 883], [885, 887], [890, 893], [895, 895], [900, 906], [908, 908], [910, 929], [931, 993], [1008, 1023], [7462, 7466], [7517, 7521], [7526, 7530], [7936, 8190], [8486, 8486], [43877, 43877], [65856, 65934], [119296, 119365]]
  when "cyrillic", "cyrl", "incyrillic"
    [[1024, 1156], [1159, 1327], [7296, 7304], [7467, 7467], [7544, 7544], [11744, 11775], [42560, 42655], [65070, 65071]]
  when "arabic", "arab", "inarabic"
    [[1536, 1791], [1872, 1919], [2160, 2207], [2208, 2303], [64336, 65023], [65136, 65279], [69216, 69246], [126464, 126719]]
  when "hebrew", "hebr", "inhebrew"
    [[1425, 1479], [1488, 1514], [1519, 1524], [64285, 64310], [64312, 64316], [64318, 64318], [64320, 64321], [64323, 64324], [64326, 64335]]
  when "devanagari", "deva", "indevanagari"
    [[2304, 2431], [43232, 43263], [72448, 72457]]
  when "thai", "inthai"
    [[3585, 3642], [3648, 3675]]
  when "hiragana", "hira", "inhiragana"
    [[12353, 12438], [12445, 12447], [110593, 110879], [110898, 110898], [110928, 110930], [127488, 127488]]
  when "katakana", "kana", "inkatakana"
    [[12449, 12538], [12541, 12543], [12784, 12799], [13008, 13054], [13056, 13143], [65382, 65391], [65393, 65437], [110576, 110592], [110880, 110882], [110933, 110933], [110948, 110951]]
  when "han", "hani", "incjkunifiedideographs", "cjkunifiedideographs"
    [[11904, 11929], [11931, 12019], [12032, 12245], [12293, 12293], [12295, 12295], [12321, 12329], [12344, 12347], [13312, 19903], [19968, 40959], [63744, 64109], [64112, 64217], [131072, 173791], [173824, 177977], [177984, 178205], [178208, 183969], [183984, 191456], [191472, 192093], [194560, 195101], [196608, 201546], [201552, 205743]]
  when "hangul", "hang", "inhangulsyllables", "hangulsyllables"
    [[4352, 4607], [12334, 12335], [12593, 12686], [12800, 12830], [12896, 12926], [43360, 43388], [44032, 55203], [55216, 55238], [55243, 55291], [65440, 65470], [65474, 65479], [65482, 65487], [65490, 65495], [65498, 65500]]
  when "inlatin1supplement", "latin1supplement"
    [[128, 255]]
  when "inlatinextendeda", "latinextendeda"
    [[256, 383]]
  when "inlatinextendedb", "latinextendedb"
    [[384, 591]]
  when "inipaextensions", "ipaextensions"
    [[592, 687]]
  when "inspacingmodifierletters", "spacingmodifierletters"
    [[688, 767]]
  when "incombiningdiacriticalmarks", "combiningdiacriticalmarks"
    [[768, 879]]
  when "ingreekandcoptic", "greekandcoptic"
    [[880, 1023]]
  when "ingeneralpunctuation", "generalpunctuation"
    [[8192, 8303]]
  when "insuperscriptsandsubscripts", "superscriptsandsubscripts"
    [[8304, 8351]]
  when "incurrencysymbols", "currencysymbols"
    [[8352, 8399]]
  when "inletterlikesymbols", "letterlikesymbols"
    [[8448, 8527]]
  when "innumberforms", "numberforms"
    [[8528, 8591]]
  when "inarrows", "arrows"
    [[8592, 8703]]
  when "inmathematicaloperators", "mathematicaloperators"
    [[8704, 8959]]
  when "inmiscellaneoustechnical", "miscellaneoustechnical"
    [[8960, 9215]]
  when "inboxdrawing", "boxdrawing"
    [[9472, 9599]]
  when "inblockelements", "blockelements"
    [[9600, 9631]]
  when "ingeometricshapes", "geometricshapes"
    [[9632, 9727]]
  when "inmiscellaneoussymbols", "miscellaneoussymbols"
    [[9728, 9983]]
  when "indingbats", "dingbats"
    [[9984, 10175]]
  when "incjksymbolsandpunctuation", "cjksymbolsandpunctuation"
    [[12288, 12351]]
  when "inprivateusearea", "privateusearea"
    [[57344, 63743]]
  when "inhalfwidthandfullwidthforms", "halfwidthandfullwidthforms"
    [[65280, 65519]]
  when "inmiscellaneoussymbolsandpictographs", "inmiscellaneoussymbolsandpictographs", "miscellaneoussymbolsandpictographs"
    [[127744, 128511]]
  when "inemoticons", "emoticons"
    [[128512, 128591]]
  when "intransportandmapsymbols", "transportandmapsymbols"
    [[128640, 128767]]
  when "insupplementalsymbolsandpictographs", "supplementalsymbolsandpictographs"
    [[129280, 129535]]
  else
    nil

-> __regex_cat_match(mask_in, neg_in, ch_in)
  mask = mask_in ## i64
  ch = ch_in ## i64
  hit = ((mask >> ((ch >> 3) & 31)) & 1) != 0
  if !hit && mask >= 1073741824
    if (mask & 1073741824) != 0 && (ch & 16777216) != 0
      hit = true
    elsif (mask & 2147483648) != 0 && (ch & 8388608) != 0
      hit = true
  if neg_in == 1
    return !hit
  hit

-> __regex_class_match_slow(c_in, lx_in)
  c = c_in ## i64[]
  lx = lx_in ## i64
  neg = c[0] == 1
  pos_f = c[1] ## i64
  if pos_f != 0 && (lx & pos_f) != 0
    return !neg
  neg_f = c[2] ## i64
  if neg_f != 0
    if (neg_f & 1) != 0 && (lx & 1) == 0
      return !neg
    if (neg_f & 2) != 0 && (lx & 2) == 0
      return !neg
    if (neg_f & 4) != 0 && (lx & 4) == 0
      return !neg
  pos_cat = c[3] ## i64
  if pos_cat != 0 && __regex_cat_match(pos_cat, 0, lx)
    return !neg
  neg_cat = c[4] ## i64
  if neg_cat != 0 && __regex_cat_match(neg_cat, 1, lx)
    return !neg
  n = c.size() ## i64
  i = 5 ## i64
  while i < n
    if lx >= c[i] && lx <= c[i + 1]
      return !neg
    i = i + 2
  neg

-> __regex_class_match(cls_in, lx_in, cls_bm_in, classes_in)
  cidx = (cls_in ## i64) * 6
  lx = lx_in ## i64
  cp = (lx >> 25) & 2097151
  cbm = cls_bm_in ## i64[]
  if cp < 128
    return ((cbm[cidx + (cp >> 5)] >> (cp & 31)) & 1) != 0
  if lx >= cbm[cidx + 4] && lx <= cbm[cidx + 5]
    return true
  __regex_class_match_slow(classes_in[cls_in], lx)

-> __regex_set_match(s, lx_in)
  lx = lx_in ## i64
  if s == "d"
    return (lx & 1) != 0
  if s == "D"
    return (lx & 1) == 0
  if s == "w"
    return (lx & 2) != 0
  if s == "W"
    return (lx & 2) == 0
  if s == "s"
    return (lx & 4) != 0
  if s == "S"
    return (lx & 4) == 0
  false

-> __regex_consume_at(pc_in, ch_in, ops_in, args_a_in, branches_in, cls_bm_in, classes_in)
  ops = ops_in ## i64[]
  args_a = args_a_in ## i64[]
  branches = branches_in ## i64[]
  pc = pc_in ## i64
  ch = ch_in ## i64
  op = ops[pc] ## i64
  if op == 1
    return ch == args_a[pc]
  if op == 18
    return ch == args_a[pc] || ch == branches[pc]
  if op == 11
    hit = (ch & args_a[pc]) != 0
    if branches[pc] == 1
      return !hit
    return hit
  if op == 2
    return ch != args_a[pc]
  if op == 3
    return __regex_class_match(args_a[pc], ch, cls_bm_in, classes_in)
  if op == 17
    return ch >= args_a[pc] && ch <= branches[pc]
  if op == 19
    return __regex_cat_match(args_a[pc], branches[pc], ch)
  false

-> __regex_build_class_entry(neg_in, pos_f_in, neg_f_in, pos_cat_in, neg_cat_in, ranges_in, ascii_lex_in, cbm_in, cbase_in)
  neg = neg_in ## i64
  pos_f = pos_f_in ## i64
  neg_f = neg_f_in ## i64
  pos_cat = pos_cat_in ## i64
  neg_cat = neg_cat_in ## i64
  ranges = ranges_in ## i64[]
  rn = ranges.size() ## i64
  cls_arr = i64[5 + rn]
  cls_arr[0] = neg
  cls_arr[1] = pos_f
  cls_arr[2] = neg_f
  cls_arr[3] = pos_cat
  cls_arr[4] = neg_cat
  ri = 0 ## i64
  while ri < rn
    cls_arr[5 + ri] = ranges[ri]
    ri = ri + 1
  bm0 = 0 ## i64
  bm1 = 0 ## i64
  bm2 = 0 ## i64
  bm3 = 0 ## i64
  one = 1 ## i64
  if (pos_f & 4) == 0 && neg_f == 0 && pos_cat == 0 && neg_cat == 0
    if (pos_f & 1) != 0
      bm1 = bm1 | 67043328
    if (pos_f & 2) != 0
      bm1 = bm1 | 67043328
      bm2 = bm2 | 2281701374
      bm3 = bm3 | 134217726
    ri = 0
    while ri < rn
      lo_cp = (ranges[ri] >> 25) & 2097151
      if lo_cp < 128
        hi_cp = (ranges[ri + 1] >> 25) & 2097151
        if hi_cp > 127
          hi_cp = 127
        if (lo_cp >> 5) == (hi_cp >> 5)
          cnt = hi_cp - lo_cp + 1
          bit = cnt >= 32 ? 4294967295 : (((one << cnt) - 1) << (lo_cp & 31))
          blk = lo_cp >> 5
          if blk == 0
            bm0 = bm0 | bit
          elsif blk == 1
            bm1 = bm1 | bit
          elsif blk == 2
            bm2 = bm2 | bit
          else
            bm3 = bm3 | bit
        else
          cp = lo_cp
          while cp <= hi_cp
            sh = cp & 31
            bit = one << sh
            blk = cp >> 5
            if blk == 0
              bm0 = bm0 | bit
            elsif blk == 1
              bm1 = bm1 | bit
            elsif blk == 2
              bm2 = bm2 | bit
            else
              bm3 = bm3 | bit
            cp = cp + 1
      ri = ri + 2
    if neg == 1
      bm0 = bm0 ^ 4294967295
      bm1 = bm1 ^ 4294967295
      bm2 = bm2 ^ 4294967295
      bm3 = bm3 ^ 4294967295
  else
    tbl = ascii_lex_in ## i64[]
    cp = 0 ## i64
    while cp < 128
      lx = tbl[cp] ## i64
      if __regex_class_match_slow(cls_arr, lx)
        sh = cp & 31
        bit = one << sh
        blk = cp >> 5
        if blk == 0
          bm0 = bm0 | bit
        elsif blk == 1
          bm1 = bm1 | bit
        elsif blk == 2
          bm2 = bm2 | bit
        else
          bm3 = bm3 | bit
      cp = cp + 1
  cbm = cbm_in ## i64[]
  cbase = cbase_in ## i64
  cbm[cbase] = bm0
  cbm[cbase + 1] = bm1
  cbm[cbase + 2] = bm2
  cbm[cbase + 3] = bm3
  if neg == 0 && rn >= 2
    cbm[cbase + 4] = ranges[0]
    cbm[cbase + 5] = ranges[1]
  else
    cbm[cbase + 4] = 1
    cbm[cbase + 5] = 0
  cls_arr

-> __regex_resolve_group_ref(ref_in, ngroup_in, ref_names_in, group_names_in)
  ref = ref_in ## i64
  ngroup = ngroup_in ## i64
  if ref >= 0
    if ref >= ngroup
      raise "invalid group reference: " + ref.to_s()
    return ref
  s = ref_names_in[0 - ref - 1]
  if s == "0"
    return 0
  cs = s.chars()
  all_digits = cs.size() > 0
  i = 0
  while i < cs.size()
    if cs[i] < "0" || cs[i] > "9"
      all_digits = false
      break
    i = i + 1
  if all_digits
    idx = s.to_i()
    if idx < 0 || idx >= ngroup
      raise "invalid numbered group reference: " + s
    return idx
  if group_names_in != nil && group_names_in.has_key?(s)
    return group_names_in[s]
  raise "undefined named group reference: " + s

-> __regex_match_backref(g_in, icase_in, sp_in, saved_in, subj_in, subj_len_in)
  saved = saved_in ## i64[]
  g = g_in ## i64
  sp = sp_in ## i64
  a = saved[g * 2] ## i64
  b = saved[g * 2 + 1] ## i64
  if a < 0 || b < 0
    return -1
  len = b - a
  n = subj_len_in ## i64
  if sp + len > n
    return -1
  subj = subj_in ## i64[]
  i = 0 ## i64
  if icase_in == 0
    while i < len
      if subj[sp + i] != subj[a + i]
        return -1
      i = i + 1
  else
    while i < len
      c1 = subj[sp + i] ## i64
      c2 = subj[a + i] ## i64
      if c1 != c2 && __regex_downcase_lex_cp(c1) != __regex_downcase_lex_cp(c2)
        return -1
      i = i + 1
  sp + len

-> __regex_match_special(mode_in, sp_in, subj_in, subj_len_in)
  mode = mode_in ## i64
  sp = sp_in ## i64
  n = subj_len_in ## i64
  if sp >= n
    return -1
  subj = subj_in ## i64[]
  ch = subj[sp] ## i64
  cp = (ch >> 25) & 2097151
  if mode == 1
    if cp == 13
      if sp + 1 < n && ((subj[sp + 1] >> 25) & 2097151) == 10
        return sp + 2
      return sp + 1
    if (cp >= 10 && cp <= 12) || cp == 133 || cp == 8232 || cp == 8233
      return sp + 1
    return -1
  if cp == 13
    if sp + 1 < n && ((subj[sp + 1] >> 25) & 2097151) == 10
      return sp + 2
    return sp + 1
  if cp == 10
    return sp + 1
  e = sp + 1
  while e < n
    nx = subj[e] ## i64
    ncat = (nx >> 3) & 31
    ncp = (nx >> 25) & 2097151
    if (ncat >= 11 && ncat <= 13) || ncp == 65038 || ncp == 65039 || (ncp >= 127995 && ncp <= 127999)
      e = e + 1
    elsif ncp == 8205 && e + 1 < n
      e = e + 2
    else
      break
  e

-> __regex_match_group_index(key, name_to_group)
  kbits = wvalue_bits(key) ## i64
  ktag = (kbits >> 48) ## i64
  if ktag == -6
    return key
  if ktag == -7
    if name_to_group == nil
      return nil
    ntg = name_to_group ## Hash
    if (kbits & 1) == 0
      return ntg[key]
    return ntg[key.to_s]
  kind = type(key)
  if kind == "Int" || kind == "Integer" || kind == "BigInt"
    return key
  if kind == "String"
    if name_to_group == nil
      return nil
    return (name_to_group ## hash)[key]
  if kind == "Symbol"
    if name_to_group == nil
      return nil
    return (name_to_group ## hash)[key.to_s]
  nil

-> __regex_decode_pattern(pat, parse_p_in, pos_box_in)
  p = parse_p_in ## i64[]
  pos_box = pos_box_in ## i64[]
  if pat.ascii?()
    pv = (wvalue_bits(pat) & -2) ## i64
    pmode = (pv >> 1) & 7
    if pmode <= 5
      i = 0 ## i64
      while i < pmode
        p[i] = (pv >> (4 + 8 * i)) & 255
        i = i + 1
      pos_box[0] = pmode
      return p
    n = ccall_nobox("w_string_byte_length", pat) ## i64
    if n > p.size()
      cap = p.size() ## i64
      while cap < n
        cap = cap * 2
      p = i64[cap]
    ptr = ccall_nobox("w_string_data_ptr", pat) ## i64
    i = 0 ## i64
    while i < n
      p[i] = raw_load_u8(ptr, i)
      i = i + 1
    pos_box[0] = n
    return p
  pos_box[1] = 0
  codes = pat.codes() ## i64[]
  n = codes.size() ## i64
  if n > p.size()
    cap = p.size() ## i64
    while cap < n
      cap = cap * 2
    p = i64[cap]
  i = 0 ## i64
  while i < n
    p[i] = (codes[i] >> 25) & 2097151
    i = i + 1
  pos_box[0] = n
  p

-> __regex_clex_cp_box(cp_in, ascii_lex_in, pos_box_in)
  cp = cp_in ## i64
  if cp >= 0 && cp < 128
    tbl = ascii_lex_in ## i64[]
    return tbl[cp]
  pos_box = pos_box_in ## i64[]
  pos_box[1] = 0
  __regex_clex_raw(cp)

-> __regex_slice_pattern_cps(p_in, start_in, len_in)
  p = p_in ## i64[]
  s = start_in ## i64
  e = s + (len_in ## i64)
  out = ""
  while s < e
    out = out + Char.new(p[s]).to_s()
    s = s + 1
  out

-> __regex_parse_hex_fixed(p_in, plen_in, pos_box_in, max_digits_in, exact)
  p = p_in ## i64[]
  plen = plen_in ## i64
  pos_box = pos_box_in ## i64[]
  i = pos_box[0] ## i64
  max_digits = max_digits_in ## i64
  val = 0 ## i64
  cnt = 0 ## i64
  while cnt < max_digits && i < plen
    hv = __regex_hex_val(p[i]) ## i64
    if hv < 0
      break
    val = (val << 4) | hv
    i = i + 1
    cnt = cnt + 1
  pos_box[0] = i
  if exact && cnt != max_digits
    raise "invalid hex/unicode escape in regex"
  if cnt == 0
    raise "invalid hex escape in regex"
  val

-> __regex_parse_bracketed_ref(kind_ch, p_in, plen_in, pos_box_in, source_in)
  p = p_in ## i64[]
  plen = plen_in ## i64
  pos_box = pos_box_in ## i64[]
  i = pos_box[0] ## i64
  if i >= plen
    raise "unterminated \\" + kind_ch + " reference in regex"
  open = p[i] ## i64
  i = i + 1
  close = 0 ## i64
  if open == 60
    close = 62
  elsif open == 39
    close = 39
  else
    raise "expected '<' or \"'\" after \\" + kind_ch + " in regex"
  nstart = i
  while i < plen && p[i] != close
    i = i + 1
  nlen = i - nstart
  if i >= plen || p[i] != close || nlen == 0
    raise "unterminated \\" + kind_ch + " reference in regex"
  pos_box[0] = i + 1
  src = source_in ## string
  src.ascii?() ? src.slice(nstart, nlen) : __regex_slice_pattern_cps(p, nstart, nlen)

-> __regex_parse_escape_cp(e_in, p_in, plen_in, pos_box_in)
  e = e_in ## i64
  if e == 110
    return 10
  if e == 116
    return 9
  if e == 114
    return 13
  if e == 97
    return 7
  if e == 101
    return 27
  if e == 102
    return 12
  if e == 118
    return 11
  p = p_in ## i64[]
  plen = plen_in ## i64
  pos_box = pos_box_in ## i64[]
  i = pos_box[0] ## i64
  if e == 48
    val = 0 ## i64
    cnt = 0 ## i64
    while cnt < 2 && i < plen
      oc = p[i] ## i64
      if oc >= 48 && oc <= 55
        val = (val << 3) | (oc - 48)
        i = i + 1
        cnt = cnt + 1
      else
        break
    pos_box[0] = i
    return val
  if e == 120
    if i < plen && p[i] == 123
      pos_box[0] = i + 1
      val = __regex_parse_hex_fixed(p, plen, pos_box, 6, false)
      i2 = pos_box[0] ## i64
      if i2 >= plen || p[i2] != 125
        raise "unterminated \\x{...} escape in regex"
      pos_box[0] = i2 + 1
      return val
    return __regex_parse_hex_fixed(p, plen, pos_box, 2, false)
  if e == 117
    if i >= plen || p[i] != 123
      return __regex_parse_hex_fixed(p, plen, pos_box, 4, true)
    return -1
  if e == 99 || (e == 67 && i < plen && p[i] == 45)
    if e == 67
      i = i + 1
    if i >= plen
      raise "incomplete \\c control escape in regex"
    x = p[i] ## i64
    i = i + 1
    if x == 92 && i < plen
      x = p[i] ## i64
      i = i + 1
    pos_box[0] = i
    if x == 63
      return 127
    return x & 31
  -1

-> __regex_parse_u_braced_cps(p_in, plen_in, pos_box_in)
  p = p_in ## i64[]
  plen = plen_in ## i64
  pos_box = pos_box_in ## i64[]
  pos_box[0] = (pos_box[0] ## i64) + 1
  cps = i64[0]
  while (pos_box[0] ## i64) < plen
    while (pos_box[0] ## i64) < plen && (p[pos_box[0]] == 32 || p[pos_box[0]] == 9)
      pos_box[0] = (pos_box[0] ## i64) + 1
    if (pos_box[0] ## i64) < plen && p[pos_box[0]] == 125
      break
    cp = __regex_parse_hex_fixed(p, plen, pos_box, 6, false)
    cps.push(cp)
    while (pos_box[0] ## i64) < plen && (p[pos_box[0]] == 32 || p[pos_box[0]] == 9)
      pos_box[0] = (pos_box[0] ## i64) + 1
    if (pos_box[0] ## i64) < plen && p[pos_box[0]] == 125
      break
  i = pos_box[0] ## i64
  if i >= plen || p[i] != 125 || cps.size() == 0
    raise "invalid \\u{...} escape in regex"
  pos_box[0] = i + 1
  cps

-> __regex_read_prop_spec(neg_in, p_in, plen_in, pos_box_in, source_in)
  p = p_in ## i64[]
  plen = plen_in ## i64
  pos_box = pos_box_in ## i64[]
  i = pos_box[0] ## i64
  neg = neg_in
  raw = ""
  if i < plen && p[i] == 123
    i = i + 1
    nstart = i
    while i < plen && p[i] != 125
      i = i + 1
    nlen = i - nstart
    if i >= plen || p[i] != 125 || nlen == 0
      raise "unterminated \\p{...} property in regex"
    pos_box[0] = i + 1
    src = source_in ## string
    raw = src.ascii?() ? src.slice(nstart, nlen) : __regex_slice_pattern_cps(p, nstart, nlen)
  elsif i < plen
    raw = Char.new(p[i]).to_s()
    pos_box[0] = i + 1
  else
    raise "incomplete \\p property in regex"
  if raw.starts_with?("^")
    neg = !neg
    raw = raw.slice(1, raw.size() - 1)
  norm = __regex_normalize_prop_name(raw)
  if !(norm == "ascii" || norm == "inbasiclatin" || norm == "basiclatin") || neg
    pos_box[1] = 0
  [norm, neg, raw]

-> __regex_resolve_unicode_prop(spec, ignore_case, range_cache_in, ascii_lex_in, pos_box_in)
  norm = spec[0]
  neg = spec[1]
  raw = spec[2]
  if norm == "word"
    return [21, 2, neg ? 1 : 0, nil]
  cat_mask = __regex_resolve_prop_cat_mask(norm) ## i64
  if cat_mask != 0
    if ignore_case && (cat_mask == 1 || cat_mask == 2 || cat_mask == 4)
      cat_mask = 7
    return [3, cat_mask, neg ? 1 : 0, nil]
  range_cache = range_cache_in ## Hash
  cached = range_cache[norm]
  if cached != nil
    cached_ranges = cached ## i64[]
    if !neg && cached_ranges.size() == 2
      return [22, cached_ranges[0], cached_ranges[1], nil]
    return [5, neg ? 1 : 0, 0, cached_ranges]
  cp_ranges = __regex_resolve_prop_cp_ranges(norm)
  if cp_ranges != nil
    if !neg && cp_ranges.size() == 1
      p0 = cp_ranges[0]
      r0_lex = __regex_clex_cp_box(p0[0], ascii_lex_in, pos_box_in) ## i64
      r1_lex = __regex_clex_cp_box(p0[1], ascii_lex_in, pos_box_in) ## i64
      flat1 = i64[2]
      flat1[0] = r0_lex
      flat1[1] = r1_lex
      range_cache[norm] = flat1
      return [22, r0_lex, r1_lex, nil]
    flat = i64[cp_ranges.size() * 2]
    ri = 0 ## i64
    best_ri = 0 ## i64
    best_span = -1 ## i64
    while ri < cp_ranges.size()
      pair = cp_ranges[ri]
      lo_p = pair[0] ## i64
      hi_p = pair[1] ## i64
      span_p = (hi_p - lo_p) + (lo_p < 1150 ? 10000 : (lo_p < 55296 ? 5000 : 0))
      if span_p > best_span
        best_span = span_p
        best_ri = ri
      flat[ri * 2] = __regex_clex_cp_box(lo_p, ascii_lex_in, pos_box_in)
      flat[ri * 2 + 1] = __regex_clex_cp_box(hi_p, ascii_lex_in, pos_box_in)
      ri = ri + 1
    if best_ri > 0
      t0 = flat[0]
      t1 = flat[1]
      flat[0] = flat[best_ri * 2]
      flat[1] = flat[best_ri * 2 + 1]
      flat[best_ri * 2] = t0
      flat[best_ri * 2 + 1] = t1
    range_cache[norm] = flat
    return [5, neg ? 1 : 0, 0, flat]
  raise "unknown Unicode property in regex: " + raw

-> __regex_push_class_single(ranges_in, cp_in, ignore_case, ascii_lex_in, pos_box_in)
  ranges = ranges_in ## i64[]
  cp = cp_in ## i64
  pos_box = pos_box_in ## i64[]
  if ignore_case
    if cp >= 128
      pos_box[1] = 0
    alt = __regex_fold_pair_cp(cp) ## i64
    if alt != cp
      lx1 = __regex_clex_cp_box(cp, ascii_lex_in, pos_box)
      lx2 = __regex_clex_cp_box(alt, ascii_lex_in, pos_box)
      ranges.push(lx1)
      ranges.push(lx1)
      ranges.push(lx2)
      ranges.push(lx2)
      return ranges
  lx = __regex_clex_cp_box(cp, ascii_lex_in, pos_box)
  ranges.push(lx)
  ranges.push(lx)
  ranges

-> __regex_parse_class_body(p_in, plen_in, pos_box_in, source_in, ignore_case, ascii_lex_in)
  p = p_in ## i64[]
  plen = plen_in ## i64
  pos_box = pos_box_in ## i64[]
  tbl = ascii_lex_in ## i64[]
  neg = 0 ## i64
  if (pos_box[0] ## i64) < plen && p[pos_box[0]] == 94
    pos_box[0] = (pos_box[0] ## i64) + 1
    neg = 1
  ranges = i64[0]
  pos_f = 0 ## i64
  neg_f = 0 ## i64
  pos_cat = 0 ## i64
  neg_cat = 0 ## i64
  while (pos_box[0] ## i64) < plen && p[pos_box[0]] != 93
    c = p[pos_box[0]] ## i64
    pos_box[0] = (pos_box[0] ## i64) + 1
    if c == 92
      e = p[pos_box[0]] ## i64
      pos_box[0] = (pos_box[0] ## i64) + 1
      if e == 100
        pos_f = pos_f | 1
        next
      if e == 119
        pos_f = pos_f | 2
        next
      if e == 115
        pos_f = pos_f | 4
        next
      if e == 68
        neg_f = neg_f | 1
        next
      if e == 87
        neg_f = neg_f | 2
        next
      if e == 83
        neg_f = neg_f | 4
        next
      if e == 104
        ranges.push(tbl[48])
        ranges.push(tbl[57])
        ranges.push(tbl[65])
        ranges.push(tbl[70])
        ranges.push(tbl[97])
        ranges.push(tbl[102])
        next
      if e == 72
        ranges.push(tbl[0])
        ranges.push(tbl[47])
        ranges.push(tbl[58])
        ranges.push(tbl[64])
        ranges.push(tbl[71])
        ranges.push(tbl[96])
        ranges.push(tbl[103])
        ranges.push(__regex_clex_cp_box(1114111, tbl, pos_box))
        next
      if e == 112 || e == 80
        spec = __regex_read_prop_spec(e == 80, p, plen, pos_box, source_in)
        pnorm = spec[0]
        pneg = spec[1]
        praw = spec[2]
        if pnorm == "word"
          if pneg
            neg_f = neg_f | 2
          else
            pos_f = pos_f | 2
          next
        cm = __regex_resolve_prop_cat_mask(pnorm) ## i64
        if cm != 0
          if ignore_case && (cm == 1 || cm == 2 || cm == 4)
            cm = 7
          if pneg
            neg_cat = neg_cat | cm
          else
            pos_cat = pos_cat | cm
          next
        cpr = __regex_resolve_prop_cp_ranges(pnorm)
        if cpr == nil
          raise "unknown Unicode property in regex class: " + praw
        if !pneg
          ri = 0
          while ri < cpr.size()
            pair = cpr[ri]
            ranges.push(__regex_clex_cp_box(pair[0], tbl, pos_box))
            ranges.push(__regex_clex_cp_box(pair[1], tbl, pos_box))
            ri = ri + 1
        else
          cur = 0 ## i64
          ri = 0
          while ri < cpr.size()
            pair = cpr[ri]
            lo_r = pair[0] ## i64
            hi_r = pair[1] ## i64
            if cur < lo_r
              ranges.push(__regex_clex_cp_box(cur, tbl, pos_box))
              ranges.push(__regex_clex_cp_box(lo_r - 1, tbl, pos_box))
            cur = hi_r + 1
            ri = ri + 1
          if cur <= 1114111
            ranges.push(__regex_clex_cp_box(cur, tbl, pos_box))
            ranges.push(__regex_clex_cp_box(1114111, tbl, pos_box))
        next
      if e == 117 && (pos_box[0] ## i64) < plen && p[pos_box[0]] == 123
        cps = __regex_parse_u_braced_cps(p, plen, pos_box) ## i64[]
        if cps.size() == 1 && (pos_box[0] ## i64) < plen && p[pos_box[0]] == 45
          c = cps[0]
        else
          ci = 0 ## i64
          while ci < cps.size()
            ranges = __regex_push_class_single(ranges, cps[ci], ignore_case, tbl, pos_box) ## i64[]
            ci = ci + 1
          next
      else
        ecp = __regex_parse_escape_cp(e, p, plen, pos_box) ## i64
        if ecp >= 0
          c = ecp
        elsif e == 98
          c = 8
        else
          c = e
    cur_i = pos_box[0] ## i64
    if cur_i < plen && p[cur_i] == 45 && cur_i + 1 < plen && p[cur_i + 1] != 93
      pos_box[0] = cur_i + 2
      hi = p[cur_i + 1] ## i64
      if hi == 92
        he = p[pos_box[0]] ## i64
        pos_box[0] = (pos_box[0] ## i64) + 1
        if he == 117 && (pos_box[0] ## i64) < plen && p[pos_box[0]] == 123
          hcps = __regex_parse_u_braced_cps(p, plen, pos_box) ## i64[]
          hi = hcps[0]
        else
          hecp = __regex_parse_escape_cp(he, p, plen, pos_box) ## i64
          hi = hecp >= 0 ? hecp : he
      if ignore_case
        if c >= 128 || hi >= 128
          pos_box[1] = 0
        if __regex_fold_pair_cp(c) != c || __regex_fold_pair_cp(hi) != hi
          ranges.push(__regex_clex_cp_box(__regex_downcase_cp(c), tbl, pos_box))
          ranges.push(__regex_clex_cp_box(__regex_downcase_cp(hi), tbl, pos_box))
          ranges.push(__regex_clex_cp_box(__regex_upcase_cp(c), tbl, pos_box))
          ranges.push(__regex_clex_cp_box(__regex_upcase_cp(hi), tbl, pos_box))
        else
          ranges.push(__regex_clex_cp_box(c, tbl, pos_box))
          ranges.push(__regex_clex_cp_box(hi, tbl, pos_box))
      else
        ranges.push(__regex_clex_cp_box(c, tbl, pos_box))
        ranges.push(__regex_clex_cp_box(hi, tbl, pos_box))
    else
      ranges = __regex_push_class_single(ranges, c, ignore_case, tbl, pos_box) ## i64[]
  if (pos_box[0] ## i64) < plen && p[pos_box[0]] == 93
    pos_box[0] = (pos_box[0] ## i64) + 1
  [neg, pos_f, neg_f, pos_cat, neg_cat, ranges]

-> __regex_parse_group_header(p_in, plen_in, state_in, source_in, group_names_in)
  p = p_in ## i64[]
  plen = plen_in ## i64
  state = state_in ## i64[]
  i = state[0] ## i64
  cap = -1 ## i64
  look_kind = 0 ## i64
  ngroup = state[3] ## i64
  group_names = group_names_in
  if i < plen && p[i] == 63
    i = i + 1
    form = p[i] ## i64
    i = i + 1
    if form == 61
      look_kind = 1
    elsif form == 33
      look_kind = 2
    elsif form == 62
      look_kind = 5
    elsif form == 35
      while i < plen && p[i] != 41
        i = i + 1
      if i < plen && p[i] == 41
        i = i + 1
      state[0] = i
      return [1, group_names]
    elsif form == 60
      if i < plen && p[i] == 61
        i = i + 1
        look_kind = 3
      elsif i < plen && p[i] == 33
        i = i + 1
        look_kind = 4
      else
        nstart = i
        if i >= plen
          raise "invalid named regex capture"
        fc = p[i] ## i64
        if !((fc >= 97 && fc <= 122) || (fc >= 65 && fc <= 90) || fc == 95)
          raise "invalid named regex capture"
        while i < plen && p[i] != 62
          nc = p[i] ## i64
          i = i + 1
          if !((nc >= 97 && nc <= 122) || (nc >= 65 && nc <= 90) || (nc >= 48 && nc <= 57) || nc == 95)
            raise "invalid named regex capture"
        nlen = i - nstart
        if i >= plen || p[i] != 62 || nlen == 0
          raise "invalid named regex capture"
        i = i + 1
        src = source_in ## string
        name = src.ascii?() ? src.slice(nstart, nlen) : __regex_slice_pattern_cps(p, nstart, nlen)
        if group_names == nil
          group_names = {}
        elsif (group_names ## Hash).has_key?(name)
          raise "duplicate named regex capture: " + name
        cap = ngroup
        ngroup = cap + 1
        (group_names ## Hash)[name] = cap
    elsif form == 105 || form == 109 || form == 120 || form == 45
      neg_flag = false
      cur_f = form
      while true
        if cur_f == 45
          neg_flag = true
        elsif cur_f == 105
          state[4] = neg_flag ? 0 : 1
        elsif cur_f == 109
          state[5] = neg_flag ? 0 : 1
        elsif cur_f == 120
          state[6] = neg_flag ? 0 : 1
        else
          raise "unsupported regex group flag: " + Char.new(cur_f).to_s()
        if i < plen && p[i] == 41
          state[0] = i + 1
          return [1, group_names]
        if i < plen && p[i] == 58
          i = i + 1
          break
        if i >= plen
          raise "unterminated inline flag group in regex"
        cur_f = p[i] ## i64
        i = i + 1
    elsif form != 58
      raise "unsupported regex group form: ?" + Char.new(form).to_s()
  else
    cap = ngroup
    ngroup = cap + 1
  state[0] = i
  state[1] = cap
  state[2] = look_kind
  state[3] = ngroup
  [0, group_names]

-> __regex_new_ast(k_in, a_in, b_in, c_in, ast_ctx_in, id_in)
  ast_ctx = ast_ctx_in ## Array
  id = id_in ## i64
  ak = ast_ctx[0] ## i64[]
  if id >= ak.size()
    cap = ak.size() * 2
    ak2 = i64[cap]
    aa2 = i64[cap]
    ab2 = i64[cap]
    ac2 = i64[cap]
    an2 = i64[cap]
    aa0 = ast_ctx[1] ## i64[]
    ab0 = ast_ctx[2] ## i64[]
    ac0 = ast_ctx[3] ## i64[]
    an0 = ast_ctx[4] ## i64[]
    i = 0 ## i64
    while i < id
      ak2[i] = ak[i]
      aa2[i] = aa0[i]
      ab2[i] = ab0[i]
      ac2[i] = ac0[i]
      an2[i] = an0[i]
      i = i + 1
    ast_ctx[0] = ak2
    ast_ctx[1] = aa2
    ast_ctx[2] = ab2
    ast_ctx[3] = ac2
    ast_ctx[4] = an2
    ak = ak2
  aa = ast_ctx[1] ## i64[]
  ab = ast_ctx[2] ## i64[]
  ac = ast_ctx[3] ## i64[]
  an = ast_ctx[4] ## i64[]
  ak[id] = k_in ## i64
  aa[id] = a_in ## i64
  ab[id] = b_in ## i64
  ac[id] = c_in ## i64
  an[id] = -1
  id

-> __regex_simplify_class_ast(neg_in, pos_f_in, neg_f_in, pos_cat_in, neg_cat_in, ranges_in, out_in)
  neg = neg_in ## i64
  pos_f = pos_f_in ## i64
  neg_f = neg_f_in ## i64
  pos_cat = pos_cat_in ## i64
  neg_cat = neg_cat_in ## i64
  ranges = ranges_in ## i64[]
  out = out_in ## i64[]
  rn = ranges.size() ## i64
  if neg == 0 && pos_f == 0 && neg_f == 0 && pos_cat == 0 && neg_cat == 0 && rn == 2
    if ranges[0] == ranges[1]
      out[0] = 1
      out[1] = ranges[0]
      out[2] = 0
      return true
    out[0] = 22
    out[1] = ranges[0]
    out[2] = ranges[1]
    return true
  if rn == 0 && pos_f == 0 && neg_f == 0
    if pos_cat != 0 && neg_cat == 0
      out[0] = 3
      out[1] = pos_cat
      out[2] = neg
      return true
    if pos_cat == 0 && neg_cat != 0
      out[0] = 3
      out[1] = neg_cat
      out[2] = neg == 1 ? 0 : 1
      return true
  if rn == 0 && pos_cat == 0 && neg_cat == 0
    if (pos_f == 1 || pos_f == 2 || pos_f == 4) && neg_f == 0
      out[0] = 21
      out[1] = pos_f
      out[2] = neg
      return true
    if (neg_f == 1 || neg_f == 2 || neg_f == 4) && pos_f == 0
      out[0] = 21
      out[1] = neg_f
      out[2] = neg == 1 ? 0 : 1
      return true
  false




