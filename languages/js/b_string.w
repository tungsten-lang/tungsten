# runtime/b_string — String and String.prototype. Strings are UTF-8; positions and
# lengths are in UTF-16 code units, so ASCII strings (the common case) index bytes directly.
# (Ported from blade/js/b_string.w.)

in JS

-> js_this_str(v, what)
  return v if v.is_a?(String)
  js_throw_type("String.prototype." + what + " called on null or undefined") if js_nullish?(v)
  return v.internal if js_special?(v, "String") && js_string?(v.internal)
  js_to_string(v)

# UTF-16 offset → byte offset in s.
-> js_unit_to_byte(s, u)
  return u if js_ascii?(s)
  n = s.size
  i = 0
  k = 0
  while i < n && k < u
    b = s.byte_at(i)
    if b < 128
      i += 1
      k += 1
    elsif b < 224
      i += 2
      k += 1
    elsif b < 240
      i += 3
      k += 1
    else
      i += 4
      k += 2
  i > n ? n : i

-> js_byte_to_unit(s, bi)
  return bi if js_ascii?(s)
  i = 0
  k = 0
  while i < bi
    b = s.byte_at(i)
    if b < 128
      i += 1
      k += 1
    elsif b < 224
      i += 2
      k += 1
    elsif b < 240
      i += 3
      k += 1
    else
      i += 4
      k += 2
  k

-> js_str_index_of(s, sub, from)
  if js_ascii?(s)
    n = s.size
    from = 0 if from < 0
    return (from <= n ? from : n) if sub.size == 0
    return -1 if from >= n
    bi = s.index(sub, from)
    return bi == nil ? -1 : bi
  n = js_len(s)
  from = 0 if from < 0
  return (from <= n ? from : n) if sub.size == 0
  return -1 if from >= n
  bi = s.index(sub, js_unit_to_byte(s, from))
  return -1 if bi == nil
  js_byte_to_unit(s, bi)

-> js_str_last_index_of(s, sub, from)
  n = js_len(s)
  from = n if from > n
  from = 0 if from < 0
  sl = js_len(sub)
  k = from
  k = n - sl if k > n - sl
  while k >= 0
    return k if js_substring(s, k, k + sl) == sub
    k -= 1
  -1

-> js_str_slice(s, a, b)
  if js_ascii?(s) && js_number?(a) && (b == nil || js_number?(b))
    n = s.size
    ai = a.to_i
    bi = b == nil ? n : b.to_i
    if ai >= 0 && bi >= 0 && ai.to_f == a && (b == nil || bi.to_f == b)
      ai = n if ai > n
      bi = n if bi > n
      return "" if bi <= ai
      return s.slice(ai, bi - ai)
  n = js_len(s)
  ai = js_rel_index(a, n, 0)
  bi = js_rel_index(b, n, n)
  js_substring(s, ai, bi)

-> js_clamp_int(v, lo, hi, dflt)
  return dflt if v == nil
  n = js_to_integer(v)
  return lo if n < lo + ~0.0
  return hi if n > hi + ~0.0
  n.to_i

-> js_str_substring(s, a, b)
  n = js_len(s)
  ai = js_clamp_int(a, 0, n, 0)
  bi = js_clamp_int(b, 0, n, n)
  if ai > bi
    t = ai
    ai = bi
    bi = t
  js_substring(s, ai, bi)

-> js_str_substr(s, a, l)
  n = js_len(s)
  st = js_rel_index(a, n, 0)
  len = l == nil ? n - st : js_clamp_int(l, 0, n - st, n - st)
  return "" if len <= 0
  js_substring(s, st, st + len)

-> js_str_repeat(s, c)
  n = js_to_integer(c)
  js_throw_range("Invalid count value: " + js_number_to_s(n)) if n < ~0.0 || n == INF
  return "" if n == ~0.0 || s.size == 0
  js_throw_range("Invalid string length") if n * s.size > ~536870888.0
  s * n.to_i

-> js_str_pad(s, maxlen, fill, at_start)
  n = js_to_length(maxlen)
  len = js_len(s)
  return s if n <= len
  f = fill == nil ? " " : js_to_string(fill)
  return s if f.size == 0
  need = n - len
  fl = js_len(f)
  reps = need / fl + 1
  pad = js_substring(f * reps, 0, need)
  at_start ? pad + s : s + pad

JS_UP_SPECIAL = {223 => [83, 83], 304 => [304], 329 => [700, 78], 496 => [74, 780], 912 => [921, 776, 769], 944 => [933, 776, 769], 1415 => [1333, 1362], 7830 => [72, 817], 7831 => [84, 776], 7832 => [87, 778], 7833 => [89, 778], 7834 => [65, 702], 8016 => [933, 787], 8018 => [933, 787, 768], 8020 => [933, 787, 769], 8022 => [933, 787, 834], 8064 => [7944, 921], 8065 => [7945, 921], 8066 => [7946, 921], 8067 => [7947, 921], 8068 => [7948, 921], 8069 => [7949, 921], 8070 => [7950, 921], 8071 => [7951, 921], 8072 => [7944, 921], 8073 => [7945, 921], 8074 => [7946, 921], 8075 => [7947, 921], 8076 => [7948, 921], 8077 => [7949, 921], 8078 => [7950, 921], 8079 => [7951, 921], 8080 => [7976, 921], 8081 => [7977, 921], 8082 => [7978, 921], 8083 => [7979, 921], 8084 => [7980, 921], 8085 => [7981, 921], 8086 => [7982, 921], 8087 => [7983, 921], 8088 => [7976, 921], 8089 => [7977, 921], 8090 => [7978, 921], 8091 => [7979, 921], 8092 => [7980, 921], 8093 => [7981, 921], 8094 => [7982, 921], 8095 => [7983, 921], 8096 => [8040, 921], 8097 => [8041, 921], 8098 => [8042, 921], 8099 => [8043, 921], 8100 => [8044, 921], 8101 => [8045, 921], 8102 => [8046, 921], 8103 => [8047, 921], 8104 => [8040, 921], 8105 => [8041, 921], 8106 => [8042, 921], 8107 => [8043, 921], 8108 => [8044, 921], 8109 => [8045, 921], 8110 => [8046, 921], 8111 => [8047, 921], 8114 => [8122, 921], 8115 => [913, 921], 8116 => [902, 921], 8118 => [913, 834], 8119 => [913, 834, 921], 8124 => [913, 921], 8130 => [8138, 921], 8131 => [919, 921], 8132 => [905, 921], 8134 => [919, 834], 8135 => [919, 834, 921], 8140 => [919, 921], 8146 => [921, 776, 768], 8147 => [921, 776, 769], 8150 => [921, 834], 8151 => [921, 776, 834], 8162 => [933, 776, 768], 8163 => [933, 776, 769], 8164 => [929, 787], 8166 => [933, 834], 8167 => [933, 776, 834], 8178 => [8186, 921], 8179 => [937, 921], 8180 => [911, 921], 8182 => [937, 834], 8183 => [937, 834, 921], 8188 => [937, 921], 64256 => [70, 70], 64257 => [70, 73], 64258 => [70, 76], 64259 => [70, 70, 73], 64260 => [70, 70, 76], 64261 => [83, 84], 64262 => [83, 84], 64275 => [1348, 1350], 64276 => [1348, 1333], 64277 => [1348, 1339], 64278 => [1358, 1350], 64279 => [1348, 1341]}

# Unicode 17.0.0 BMP Simple_Uppercase_Mapping & Simple_Lowercase_Mapping runs: [start, count, step, delta, ...].
JS_BMP_UP_RUNS = [97, 26, 1, -32, 181, 1, 1, 743, 224, 23, 1, -32, 248, 7, 1, -32, 255, 1, 1, 121, 257, 24, 2, -1, 305, 1, 1, -232, 307, 3, 2, -1, 314, 8, 2, -1, 331, 23, 2, -1, 378, 3, 2, -1, 383, 1, 1, -300, 384, 1, 1, 195, 387, 2, 2, -1, 392, 1, 1, -1, 396, 1, 1, -1, 402, 1, 1, -1, 405, 1, 1, 97, 409, 1, 1, -1, 410, 1, 1, 163, 411, 1, 1, 42561, 414, 1, 1, 130, 417, 3, 2, -1, 424, 1, 1, -1, 429, 1, 1, -1, 432, 1, 1, -1, 436, 2, 2, -1, 441, 1, 1, -1, 445, 1, 1, -1, 447, 1, 1, 56, 453, 1, 1, -1, 454, 1, 1, -2, 456, 1, 1, -1, 457, 1, 1, -2, 459, 1, 1, -1, 460, 1, 1, -2, 462, 8, 2, -1, 477, 1, 1, -79, 479, 9, 2, -1, 498, 1, 1, -1, 499, 1, 1, -2, 501, 1, 1, -1, 505, 20, 2, -1, 547, 9, 2, -1, 572, 1, 1, -1, 575, 2, 1, 10815, 578, 1, 1, -1, 583, 5, 2, -1, 592, 1, 1, 10783, 593, 1, 1, 10780, 594, 1, 1, 10782, 595, 1, 1, -210, 596, 1, 1, -206, 598, 2, 1, -205, 601, 1, 1, -202, 603, 1, 1, -203, 604, 1, 1, 42319, 608, 1, 1, -205, 609, 1, 1, 42315, 611, 1, 1, -207, 612, 1, 1, 42343, 613, 1, 1, 42280, 614, 1, 1, 42308, 616, 1, 1, -209, 617, 1, 1, -211, 618, 1, 1, 42308, 619, 1, 1, 10743, 620, 1, 1, 42305, 623, 1, 1, -211, 625, 1, 1, 10749, 626, 1, 1, -213, 629, 1, 1, -214, 637, 1, 1, 10727, 640, 1, 1, -218, 642, 1, 1, 42307, 643, 1, 1, -218, 647, 1, 1, 42282, 648, 1, 1, -218, 649, 1, 1, -69, 650, 2, 1, -217, 652, 1, 1, -71, 658, 1, 1, -219, 669, 1, 1, 42261, 670, 1, 1, 42258, 837, 1, 1, 84, 881, 2, 2, -1, 887, 1, 1, -1, 891, 3, 1, 130, 940, 1, 1, -38, 941, 3, 1, -37, 945, 17, 1, -32, 962, 1, 1, -31, 963, 9, 1, -32, 972, 1, 1, -64, 973, 2, 1, -63, 976, 1, 1, -62, 977, 1, 1, -57, 981, 1, 1, -47, 982, 1, 1, -54, 983, 1, 1, -8, 985, 12, 2, -1, 1008, 1, 1, -86, 1009, 1, 1, -80, 1010, 1, 1, 7, 1011, 1, 1, -116, 1013, 1, 1, -96, 1016, 1, 1, -1, 1019, 1, 1, -1, 1072, 32, 1, -32, 1104, 16, 1, -80, 1121, 17, 2, -1, 1163, 27, 2, -1, 1218, 7, 2, -1, 1231, 1, 1, -15, 1233, 48, 2, -1, 1377, 38, 1, -48, 4304, 43, 1, 3008, 4349, 3, 1, 3008, 5112, 6, 1, -8, 7296, 1, 1, -6254, 7297, 1, 1, -6253, 7298, 1, 1, -6244, 7299, 2, 1, -6242, 7301, 1, 1, -6243, 7302, 1, 1, -6236, 7303, 1, 1, -6181, 7304, 1, 1, 35266, 7306, 1, 1, -1, 7545, 1, 1, 35332, 7549, 1, 1, 3814, 7566, 1, 1, 35384, 7681, 75, 2, -1, 7835, 1, 1, -59, 7841, 48, 2, -1, 7936, 8, 1, 8, 7952, 6, 1, 8, 7968, 8, 1, 8, 7984, 8, 1, 8, 8000, 6, 1, 8, 8017, 4, 2, 8, 8032, 8, 1, 8, 8048, 2, 1, 74, 8050, 4, 1, 86, 8054, 2, 1, 100, 8056, 2, 1, 128, 8058, 2, 1, 112, 8060, 2, 1, 126, 8112, 2, 1, 8, 8126, 1, 1, -7205, 8144, 2, 1, 8, 8160, 2, 1, 8, 8165, 1, 1, 7, 8526, 1, 1, -28, 8560, 16, 1, -16, 8580, 1, 1, -1, 9424, 26, 1, -26, 11312, 48, 1, -48, 11361, 1, 1, -1, 11365, 1, 1, -10795, 11366, 1, 1, -10792, 11368, 3, 2, -1, 11379, 1, 1, -1, 11382, 1, 1, -1, 11393, 50, 2, -1, 11500, 2, 2, -1, 11507, 1, 1, -1, 11520, 38, 1, -7264, 11559, 1, 1, -7264, 11565, 1, 1, -7264, 42561, 23, 2, -1, 42625, 14, 2, -1, 42787, 7, 2, -1, 42803, 31, 2, -1, 42874, 2, 2, -1, 42879, 5, 2, -1, 42892, 1, 1, -1, 42897, 2, 2, -1, 42900, 1, 1, 48, 42903, 10, 2, -1, 42933, 8, 2, -1, 42952, 2, 2, -1, 42957, 8, 2, -1, 42998, 1, 1, -1, 43859, 1, 1, -928, 43888, 80, 1, -38864, 65345, 26, 1, -32]
JS_BMP_LO_RUNS = [65, 26, 1, 32, 192, 23, 1, 32, 216, 7, 1, 32, 256, 24, 2, 1, 306, 3, 2, 1, 313, 8, 2, 1, 330, 23, 2, 1, 376, 1, 1, -121, 377, 3, 2, 1, 385, 1, 1, 210, 386, 2, 2, 1, 390, 1, 1, 206, 391, 1, 1, 1, 393, 2, 1, 205, 395, 1, 1, 1, 398, 1, 1, 79, 399, 1, 1, 202, 400, 1, 1, 203, 401, 1, 1, 1, 403, 1, 1, 205, 404, 1, 1, 207, 406, 1, 1, 211, 407, 1, 1, 209, 408, 1, 1, 1, 412, 1, 1, 211, 413, 1, 1, 213, 415, 1, 1, 214, 416, 3, 2, 1, 422, 1, 1, 218, 423, 1, 1, 1, 425, 1, 1, 218, 428, 1, 1, 1, 430, 1, 1, 218, 431, 1, 1, 1, 433, 2, 1, 217, 435, 2, 2, 1, 439, 1, 1, 219, 440, 1, 1, 1, 444, 1, 1, 1, 452, 1, 1, 2, 453, 1, 1, 1, 455, 1, 1, 2, 456, 1, 1, 1, 458, 1, 1, 2, 459, 9, 2, 1, 478, 9, 2, 1, 497, 1, 1, 2, 498, 2, 2, 1, 502, 1, 1, -97, 503, 1, 1, -56, 504, 20, 2, 1, 544, 1, 1, -130, 546, 9, 2, 1, 570, 1, 1, 10795, 571, 1, 1, 1, 573, 1, 1, -163, 574, 1, 1, 10792, 577, 1, 1, 1, 579, 1, 1, -195, 580, 1, 1, 69, 581, 1, 1, 71, 582, 5, 2, 1, 880, 2, 2, 1, 886, 1, 1, 1, 895, 1, 1, 116, 902, 1, 1, 38, 904, 3, 1, 37, 908, 1, 1, 64, 910, 2, 1, 63, 913, 17, 1, 32, 931, 9, 1, 32, 975, 1, 1, 8, 984, 12, 2, 1, 1012, 1, 1, -60, 1015, 1, 1, 1, 1017, 1, 1, -7, 1018, 1, 1, 1, 1021, 3, 1, -130, 1024, 16, 1, 80, 1040, 32, 1, 32, 1120, 17, 2, 1, 1162, 27, 2, 1, 1216, 1, 1, 15, 1217, 7, 2, 1, 1232, 48, 2, 1, 1329, 38, 1, 48, 4256, 38, 1, 7264, 4295, 1, 1, 7264, 4301, 1, 1, 7264, 5024, 80, 1, 38864, 5104, 6, 1, 8, 7305, 1, 1, 1, 7312, 43, 1, -3008, 7357, 3, 1, -3008, 7680, 75, 2, 1, 7838, 1, 1, -7615, 7840, 48, 2, 1, 7944, 8, 1, -8, 7960, 6, 1, -8, 7976, 8, 1, -8, 7992, 8, 1, -8, 8008, 6, 1, -8, 8025, 4, 2, -8, 8040, 8, 1, -8, 8072, 8, 1, -8, 8088, 8, 1, -8, 8104, 8, 1, -8, 8120, 2, 1, -8, 8122, 2, 1, -74, 8124, 1, 1, -9, 8136, 4, 1, -86, 8140, 1, 1, -9, 8152, 2, 1, -8, 8154, 2, 1, -100, 8168, 2, 1, -8, 8170, 2, 1, -112, 8172, 1, 1, -7, 8184, 2, 1, -128, 8186, 2, 1, -126, 8188, 1, 1, -9, 8486, 1, 1, -7517, 8490, 1, 1, -8383, 8491, 1, 1, -8262, 8498, 1, 1, 28, 8544, 16, 1, 16, 8579, 1, 1, 1, 9398, 26, 1, 26, 11264, 48, 1, 48, 11360, 1, 1, 1, 11362, 1, 1, -10743, 11363, 1, 1, -3814, 11364, 1, 1, -10727, 11367, 3, 2, 1, 11373, 1, 1, -10780, 11374, 1, 1, -10749, 11375, 1, 1, -10783, 11376, 1, 1, -10782, 11378, 1, 1, 1, 11381, 1, 1, 1, 11390, 2, 1, -10815, 11392, 50, 2, 1, 11499, 2, 2, 1, 11506, 1, 1, 1, 42560, 23, 2, 1, 42624, 14, 2, 1, 42786, 7, 2, 1, 42802, 31, 2, 1, 42873, 2, 2, 1, 42877, 1, 1, -35332, 42878, 5, 2, 1, 42891, 1, 1, 1, 42893, 1, 1, -42280, 42896, 2, 2, 1, 42902, 10, 2, 1, 42922, 1, 1, -42308, 42923, 1, 1, -42319, 42924, 1, 1, -42315, 42925, 1, 1, -42305, 42926, 1, 1, -42308, 42928, 1, 1, -42258, 42929, 1, 1, -42282, 42930, 1, 1, -42261, 42931, 1, 1, 928, 42932, 8, 2, 1, 42948, 1, 1, -48, 42949, 1, 1, -42307, 42950, 1, 1, -35384, 42951, 2, 2, 1, 42955, 1, 1, -42343, 42956, 8, 2, 1, 42972, 1, 1, -42561, 42997, 1, 1, 1, 65313, 26, 1, 32]
JS_BMP_CASE_CACHE = [nil, nil]

-> js_bmp_case_map(upper)
  idx = upper ? 0 : 1
  m = JS_BMP_CASE_CACHE[idx]
  if m == nil
    m = {}
    runs = upper ? JS_BMP_UP_RUNS : JS_BMP_LO_RUNS
    i = 0
    while i < runs.size
      st = runs[i]
      cnt = runs[i + 1]
      step = runs[i + 2]
      d = runs[i + 3]
      k = 0
      while k < cnt
        c = st + k * step
        m[c] = c + d
        k += 1
      i += 4
    JS_BMP_CASE_CACHE[idx] = m
  m

-> js_str_case(s, upper)
  if js_ascii?(s)
    return upper ? s.upcase : s.downcase
  # Decode code points & raw slices so SpecialCasing.txt and Final_Sigma are 100% Unicode 17.0.0 exact.
  cps = []
  raws = []
  n = s.size
  bi = 0
  while bi < n
    w = js_utf8_width(s, bi)
    w = n - bi if bi + w > n
    cps.push(js_utf8_decode_at(s, bi))
    raws.push(s.slice(bi, w))
    bi += w
  sb = StringBuffer()
  m = cps.size
  if upper
    umap = js_bmp_case_map(true)
    i = 0
    while i < m
      cp = cps[i]
      sp = JS_UP_SPECIAL[cp]
      if sp != nil
        j = 0
        while j < sp.size
          sb.append(js_cp_str(sp[j]))
          j += 1
      elsif cp >= 55296 && cp <= 57343
        sb.append(raws[i])
      elsif cp <= 65535
        mc = umap[cp]
        sb.append(mc != nil ? js_cp_str(mc) : raws[i])
      else
        sb.append(raws[i].unicode_upcase)
      i += 1
    r = sb.to_s
    ccall("w_value_free_w", sb)
    return r
  lmap = js_bmp_case_map(false)
  cased_tab = nil
  ci_tab = nil
  i = 0
  while i < m
    cp = cps[i]
    if cp == 304
      sb.append("i")
      sb.append(js_cp_str(775))
    elsif cp == 931
      if cased_tab == nil
        cased_tab = rx_rtab_get(8)
        ci_tab = rx_rtab_get(7)
      j = i - 1
      while j >= 0 && rx_r_has?(ci_tab, cps[j])
        j -= 1
      before_cased = j >= 0 && rx_r_has?(cased_tab, cps[j])
      after_cased = false
      if before_cased
        j = i + 1
        while j < m && rx_r_has?(ci_tab, cps[j])
          j += 1
        after_cased = j < m && rx_r_has?(cased_tab, cps[j])
      sb.append(js_cp_str((before_cased && !after_cased) ? 962 : 963))
    elsif cp >= 55296 && cp <= 57343
      sb.append(raws[i])
    elsif cp <= 65535
      mc = lmap[cp]
      sb.append(mc != nil ? js_cp_str(mc) : raws[i])
    else
      sb.append(raws[i].unicode_downcase)
    i += 1
  r = sb.to_s
  ccall("w_value_free_w", sb)
  r

-> js_is_trim_cp(cp)
  cp == 9 || cp == 10 || cp == 11 || cp == 12 || cp == 13 || cp == 32 || cp == 160 || cp == 5760 || (cp >= 8192 && cp <= 8202) || cp == 8232 || cp == 8233 || cp == 8239 || cp == 8287 || cp == 12288 || cp == 65279

-> js_str_trim(s, start, fin)
  a = 0
  b = s.size
  if start
    while a < b
      w = js_utf8_width(s, a)
      cp = js_utf8_decode_at(s, a)
      break if !js_is_trim_cp(cp)
      a += w
  if fin
    while b > a
      j = b - 1
      while j > a && (s.byte_at(j) & 192) == 128
        j -= 1
      cp = js_utf8_decode_at(s, j)
      break if !js_is_trim_cp(cp)
      b = j
  return s if a == 0 && b == s.size
  s.slice(a, b - a)

-> js_utf8_width(s, i)
  b = s.byte_at(i)
  b < 128 ? 1 : (b < 224 ? 2 : (b < 240 ? 3 : 4))

-> js_utf8_decode_at(s, i)
  b = s.byte_at(i)
  return b if b < 128
  n = s.size
  return ((b & 31) << 6) | (s.byte_at(i + 1) & 63) if b < 224 && i + 1 < n
  return ((b & 15) << 12) | ((s.byte_at(i + 1) & 63) << 6) | (s.byte_at(i + 2) & 63) if b < 240 && i + 2 < n
  return ((b & 7) << 18) | ((s.byte_at(i + 1) & 63) << 12) | ((s.byte_at(i + 2) & 63) << 6) | (s.byte_at(i + 3) & 63) if i + 3 < n
  65533

-> js_str_split(this, sep, limit)
  js_throw_type("String.prototype.split called on null or undefined") if js_nullish?(this)
  r = js_realm()
  if js_object?(sep)
    sp = js_get_method(sep, SYM_SPLIT)
    return js_call_arr(sp, sep, [this, limit]) if sp != nil
  s = js_this_str(this, "split")
  lim = limit == nil ? 4294967295 : js_to_uint32(limit)
  sepstr = js_to_string(sep)
  return r.adopt_array([]) if lim == 0
  return r.adopt_array([s]) if sep == nil
  out = []
  if sepstr.size == 0
    if js_ascii?(s)
      i = 0
      while i < s.size && out.size < lim
        out.push(s.slice(i, 1))
        i += 1
    else
      u = js_units(s)
      i = 0
      while i < u.size && out.size < lim
        out.push(js_from_units([u[i]]))
        i += 1
    return r.adopt_array(out)
  if lim == 4294967295 && sepstr.size > 0
    return r.adopt_array([""]) if s.size == 0
    return r.adopt_array(s.split(sepstr))
  st = 0
  while out.size < lim
    j = s.index(sepstr, st)
    if j == nil
      out.push(s.slice(st, s.size - st))
      break
    out.push(s.slice(st, j - st))
    st = j + sepstr.size
  r.adopt_array(out)

# GetSubstitution for string patterns and regex matches (captures: Array, named: a JS object or nil).
-> js_get_substitution(matched, s, pos, captures, named, repl)
  return repl if repl.index("$") == nil
  sb = StringBuffer()
  tot = 0
  n = repl.size
  i = 0
  m = captures.size
  while i < n
    c = repl.byte_at(i)
    if c == 36 && i + 1 < n
      d = repl.byte_at(i + 1)
      if d == 36
        tot += 1
        js_throw_range("Invalid string length") if tot > 268435456
        sb.append("$")
        i += 2
      elsif d == 38
        tot += matched.size
        js_throw_range("Invalid string length") if tot > 268435456
        sb.append(matched)
        i += 2
      elsif d == 96
        sub = js_substring(s, 0, pos)
        tot += sub.size
        js_throw_range("Invalid string length") if tot > 268435456
        sb.append(sub)
        i += 2
      elsif d == 39
        e = pos + js_len(matched)
        sub = js_substring(s, e, js_len(s))
        tot += sub.size
        js_throw_range("Invalid string length") if tot > 268435456
        sb.append(sub)
        i += 2
      elsif d >= 48 && d <= 57
        num = d - 48
        used = 2
        if i + 2 < n && repl.byte_at(i + 2) >= 48 && repl.byte_at(i + 2) <= 57
          two = num * 10 + (repl.byte_at(i + 2) - 48)
          if two >= 1 && two <= m
            num = two
            used = 3
        if num >= 1 && num <= m
          cv = captures[num - 1]
          if cv != nil
            tot += cv.size
            js_throw_range("Invalid string length") if tot > 268435456
            sb.append(cv)
          i += used
        else
          tot += 1
          js_throw_range("Invalid string length") if tot > 268435456
          sb.append("$")
          i += 1
      elsif d == 60 && named != nil
        e = repl.index(">", i + 2)
        if e == nil
          tot += 2
          js_throw_range("Invalid string length") if tot > 268435456
          sb.append("$<")
          i += 2
        else
          gname = repl.slice(i + 2, e - i - 2)
          gv = jget(named, gname)
          if gv != nil
            gvs = js_to_string(gv)
            tot += gvs.size
            js_throw_range("Invalid string length") if tot > 268435456
            sb.append(gvs)
          i = e + 1
      else
        tot += 1
        js_throw_range("Invalid string length") if tot > 268435456
        sb.append("$")
        i += 1
    elsif c == 36
      # a lone "$" at the end
      tot += 1
      js_throw_range("Invalid string length") if tot > 268435456
      sb.append("$")
      i += 1
    else
      j = repl.index("$", i)
      j = n if j == nil
      tot += j - i
      js_throw_range("Invalid string length") if tot > 268435456
      sb.append(repl.slice(i, j - i))
      i = j
  r = sb.to_s
  ccall("w_value_free_w", sb)
  r

-> js_str_replace(this, pat, repl, all)
  js_throw_type("String.prototype.replace called on null or undefined") if js_nullish?(this)
  if js_object?(pat)
    if all && js_is_regexp?(pat)
      fv = jget(pat, "flags")
      js_throw_type("String.prototype.replaceAll called on null or undefined flags") if js_nullish?(fv)
      js_throw_type("replaceAll must be called with a global RegExp") if js_to_string(fv).index("g") == nil
    rp = js_get_method(pat, SYM_REPLACE)
    return js_call_arr(rp, pat, [this, repl]) if rp != nil
  s = js_this_str(this, "replace")
  p = js_to_string(pat)
  fun = js_callable?(repl) ? repl : nil
  rs = fun == nil ? js_to_string(repl) : nil
  sb = StringBuffer()
  st = 0
  searched = 0
  while true
    j = s.index(p, searched)
    break if j == nil
    sb.append(s.slice(st, j - st))
    upos = js_byte_to_unit(s, j)
    if fun != nil
      sb.append(js_to_string(js_call(fun, nil, 3, p, upos + ~0.0, s, nil, nil)))
    else
      sb.append(js_get_substitution(p, s, upos, [], nil, rs))
    st = j + p.size
    searched = p.size == 0 ? st + js_utf8_len_at(s, st) : st
    break if !all
    break if searched > s.size
  sb.append(s.slice(st, s.size - st)) if st <= s.size
  r = sb.to_s
  ccall("w_value_free_w", sb)
  r

-> js_str_from_char_code(args)
  if args.size == 1
    c = js_to_uint32(args[0]) & 65535
    return c.chr if c < 128 && c > 0
  units = []
  i = 0
  while i < args.size
    units.push(js_to_uint32(args[i]) & 65535)
    i += 1
  js_from_units(units)

-> js_str_from_code_point(args)
  sb = StringBuffer()
  i = 0
  while i < args.size
    a = args[i]
    n = js_to_number(a)
    if n != n || n < ~0.0 || n > ~1114111.0 || n != Math.floor(n)
      js_throw_range("Invalid code point " + js_to_string(a))
    sb.append(js_cp_str(n.to_i))
    i += 1
  r = sb.to_s
  ccall("w_value_free_w", sb)
  r

-> js_str_raw(args)
  cooked = js_to_obj(js_arg(args, 0))
  raw = js_to_obj(jget(cooked, "raw"))
  n = js_len_of(raw)
  sb = StringBuffer()
  i = 0
  while i < n
    sb.append(js_to_string(js_el(raw, i)))
    if i + 1 < n && i + 1 < args.size
      sb.append(js_to_string(args[i + 1]))
    i += 1
  r = sb.to_s
  ccall("w_value_free_w", sb)
  r

-> js_str_code_point_at(s, idx)
  n = js_len(s)
  i = js_to_integer(idx)
  return nil if i < ~0.0 || i >= n + ~0.0
  k = i.to_i
  if js_ascii?(s)
    return s.byte_at(k) + ~0.0
  u = js_units(s)
  c = u[k]
  if c >= 55296 && c <= 56319 && k + 1 < u.size && u[k + 1] >= 56320 && u[k + 1] <= 57343
    return (65536 + ((c - 55296) << 10) + (u[k + 1] - 56320)) + ~0.0
  c + ~0.0

-> js_str_char_code_at(s, idx)
  if js_number?(idx) && js_ascii?(s)
    k = idx.to_i
    return s.byte_at(k) + ~0.0 if k + ~0.0 == idx && k >= 0 && k < s.size
  i = idx == nil ? ~0.0 : js_to_integer(idx)
  n = js_len(s)
  return js_nan() if i < ~0.0 || i >= n + ~0.0
  js_unit_at(s, i.to_i)

-> js_str_char_at(s, idx)
  i = idx == nil ? ~0.0 : js_to_integer(idx)
  n = js_len(s)
  return "" if i < ~0.0 || i >= n + ~0.0
  js_char_at(s, i.to_i)

-> js_str_at_m(s, idx)
  n = js_len(s)
  i = js_to_integer(idx)
  i = i + n if i < ~0.0
  return nil if i < ~0.0 || i >= n + ~0.0
  js_char_at(s, i.to_i)

-> js_str_starts(this, args, at_end)
  s = js_this_str(this, at_end ? "endsWith" : "startsWith")
  p = js_arg(args, 0)
  js_throw_type("First argument to String.prototype." + (at_end ? "endsWith" : "startsWith") + " must not be a regular expression") if js_is_regexp?(p)
  ps = js_to_string(p)
  n = js_len(s)
  if at_end
    e = js_clamp_int(js_arg(args, 1), 0, n, n)
    st = e - js_len(ps)
    return false if st < 0
    return js_substring(s, st, e) == ps
  st = js_clamp_int(js_arg(args, 1), 0, n, 0)
  return s.slice(st, ps.size) == ps if js_ascii?(s)
  js_substring(s, st, st + js_len(ps)) == ps

-> js_str_includes(this, args)
  s = js_this_str(this, "includes")
  p = js_arg(args, 0)
  js_throw_type("First argument to String.prototype.includes must not be a regular expression") if js_is_regexp?(p)
  js_str_index_of(s, js_to_string(p), js_clamp_int(js_arg(args, 1), 0, js_len(s), 0)) >= 0

-> js_locale_compare(a, b)
  return ~0.0 if a == b
  # canonically equivalent strings compare equal
  if !a.ascii? || !b.ascii?
    a = a.nfc
    b = b.nfc
    return ~0.0 if a == b
  la = js_str_case(a, false)
  lb = js_str_case(b, false)
  if la != lb
    return la < lb ? ~-1.0 : ~1.0
  # same letters: lowercase sorts first
  a > b ? ~-1.0 : ~1.0

-> js_str_normalize(s, f)
  form = f == nil ? "NFC" : js_to_string(f)
  js_throw_range("The normalization form should be one of NFC, NFD, NFKC, NFKD.") if !(form == "NFC" || form == "NFD" || form == "NFKC" || form == "NFKD")
  return s if js_ascii?(s)
  if form == "NFC"
    return s.nfc
  if form == "NFD"
    return s.nfd
  if form == "NFKC"
    return s.nfkc
  s.nfkd

-> js_str_well_formed?(s)
  return true if js_ascii?(s)
  u = js_units(s)
  i = 0
  while i < u.size
    c = u[i]
    if c >= 55296 && c <= 56319
      return false if i + 1 >= u.size || u[i + 1] < 56320 || u[i + 1] > 57343
      i += 2
    elsif c >= 56320 && c <= 57343
      return false
    else
      i += 1
  true

-> js_str_to_well_formed(s)
  return s if js_str_well_formed?(s)
  u = js_units(s)
  out = []
  i = 0
  while i < u.size
    c = u[i]
    if c >= 55296 && c <= 56319 && i + 1 < u.size && u[i + 1] >= 56320 && u[i + 1] <= 57343
      out.push(c)
      out.push(u[i + 1])
      i += 2
    elsif c >= 55296 && c <= 57343
      out.push(65533)
      i += 1
    else
      out.push(c)
      i += 1
  js_from_units(out)

# String exotic objects (§10.4.3): new String(s) / Object(s) expose "0"…len-1 as
# non-writable, enumerable, non-configurable own properties ahead of "length".
+ StringObject < JS:Special
  -> new(@shape)
    @cls = "String"
    @ext = nil
    @internal = ""
    @s0 = nil
    @s1 = nil
    @s2 = nil
    @s3 = nil
    jsr_set_kind(wvalue_bits(self) ## i64, KIND_EXOTIC)

  -> str_index(k)
    return nil if !js_string?(k) || k.size == 0 || k.byte_at(0) < 48 || k.byte_at(0) > 57 || !js_array_index?(k)
    i = k.to_i
    i < js_len(@internal) ? i : nil

  -> has_own?(k)
    return true if str_index(k) != nil
    super(k)

  -> has_own_slot?(k)
    has_own?(k)

  -> get_own(k)
    i = str_index(k)
    return js_char_at(@internal, i) if i != nil
    super(k)

  -> enumerable?(k)
    return true if str_index(k) != nil
    super(k)

  -> get(k, receiver = JS_HOLE)
    i = str_index(k)
    return js_char_at(@internal, i) if i != nil
    super(k, receiver)

  -> set(k, v, receiver = JS_HOLE)
    return false if str_index(k) != nil
    super(k, v, receiver)

  -> has_property?(k)
    return true if str_index(k) != nil
    super(k)

  -> get_own_property(k)
    i = str_index(k)
    return JS:PropDesc.data(js_char_at(@internal, i), ATTR_E) if i != nil
    super(k)

  -> define_own_property(k, desc)
    i = str_index(k)
    if i != nil
      # only a compatible redefinition succeeds (ValidateAndApplyPropertyDescriptor)
      return false if desc.configurable == true || desc.enumerable == false || desc.accessor? || desc.writable == true
      return false if desc.has_value && !js_same_value(desc.value, js_char_at(@internal, i))
      return true
    super(k, desc)

  -> delete_own(k)
    return false if str_index(k) != nil
    super(k)

  -> own_keys
    out = []
    n = js_len(@internal)
    i = 0
    while i < n
      out.push(i.to_s)
      i += 1
    rest = super()
    # integer keys beyond the string's length sort after its indices
    ints = []
    others = []
    i = 0
    while i < rest.size
      if js_string?(rest[i]) && js_array_index?(rest[i])
        ints.push(rest[i])
      else
        others.push(rest[i])
      i += 1
    out + ints + others

-> js_string_object(proto, s)
  o = JS:StringObject.new(js_root_shape(proto, SP_INLINE, SP_IBASE))
  o.internal = s
  o.define("length", js_len(s) + ~0.0, 0)
  o

-> js_string_ctor(args, nt)
  v = args.size == 0 ? "" : args[0]
  s = (nt == nil && v.is_a?(JS:Symbol)) ? v.to_s : js_to_string(v)
  return s if nt == nil
  js_string_object(js_realm().proto_from(nt, "String"), s)

-> js_str_concat(this, args)
  s = js_this_str(this, "concat")
  i = 0
  while i < args.size
    s = js_str_cat(s, js_to_string(args[i]))
    i += 1
  s

-> js_str_match(this, rx, all)
  js_throw_type("String.prototype.match called on null or undefined") if js_nullish?(this)
  sym = all ? SYM_MATCH_ALL : SYM_MATCH
  if js_object?(rx)
    if all && js_is_regexp?(rx)
      fv = jget(rx, "flags")
      js_throw_type("String.prototype.matchAll called on null or undefined flags") if js_nullish?(fv)
      js_throw_type("String.prototype.matchAll called with a non-global RegExp argument") if js_to_string(fv).index("g") == nil
    m = js_get_method(rx, sym)
    return js_call_arr(m, rx, [this]) if m != nil
  s = js_this_str(this, "match")
  re = js_regexp_create(rx == nil ? "" : js_to_string(rx), all ? "g" : "")
  js_invoke(re, sym, [s])

-> js_str_search(this, rx)
  js_throw_type("String.prototype.search called on null or undefined") if js_nullish?(this)
  if js_object?(rx)
    m = js_get_method(rx, SYM_SEARCH)
    return js_call_arr(m, rx, [this]) if m != nil
  s = js_this_str(this, "search")
  re = js_regexp_create(rx == nil ? "" : js_to_string(rx), "")
  js_invoke(re, SYM_SEARCH, [s])

js_install(->(r) js_install_string(r))

-> js_install_string(r)
  sp = js_new_special(r.object_proto, "String")
  sp.internal = ""
  sp.define("length", ~0.0, 0)
  sc = r.constructor("String", 1, ->(this, args, nt) js_string_ctor(args, nt), sp)
  r.method(sc, "fromCharCode", 1, ->(this, args, nt) js_str_from_char_code(args))
  r.method(sc, "fromCodePoint", 1, ->(this, args, nt) js_str_from_code_point(args))
  r.method(sc, "raw", 1, ->(this, args, nt) js_str_raw(args))
  r.method(sp, "at", 1, ->(this, args, nt) js_str_at_m(js_this_str(this, "at"), js_arg(args, 0)))
  r.method(sp, "charAt", 1, ->(this, args, nt) js_str_char_at(js_this_str(this, "charAt"), js_arg(args, 0)))
  r.method(sp, "charCodeAt", 1, ->(this, args, nt) js_str_char_code_at(js_this_str(this, "charCodeAt"), js_arg(args, 0)))
  r.method(sp, "codePointAt", 1, ->(this, args, nt) js_str_code_point_at(js_this_str(this, "codePointAt"), js_arg(args, 0)))
  r.method(sp, "concat", 1, ->(this, args, nt) js_str_concat(this, args))
  r.method(sp, "endsWith", 1, ->(this, args, nt) js_str_starts(this, args, true))
  r.method(sp, "startsWith", 1, ->(this, args, nt) js_str_starts(this, args, false))
  r.method(sp, "includes", 1, ->(this, args, nt) js_str_includes(this, args))
  r.method(sp, "indexOf", 1, ->(this, args, nt) js_str_index_of_v(this, args))
  r.method(sp, "lastIndexOf", 1, ->(this, args, nt) js_str_last_index_of_v(this, args))
  r.method(sp, "localeCompare", 1, ->(this, args, nt) js_locale_compare(js_this_str(this, "localeCompare"), js_to_string(js_arg(args, 0))))
  r.method(sp, "match", 1, ->(this, args, nt) js_str_match(this, js_arg(args, 0), false))
  r.method(sp, "matchAll", 1, ->(this, args, nt) js_str_match(this, js_arg(args, 0), true))
  r.method(sp, "normalize", 0, ->(this, args, nt) js_str_normalize(js_this_str(this, "normalize"), js_arg(args, 0)))
  r.method(sp, "padEnd", 1, ->(this, args, nt) js_str_pad(js_this_str(this, "padEnd"), js_arg(args, 0), js_arg(args, 1), false))
  r.method(sp, "padStart", 1, ->(this, args, nt) js_str_pad(js_this_str(this, "padStart"), js_arg(args, 0), js_arg(args, 1), true))
  r.method(sp, "repeat", 1, ->(this, args, nt) js_str_repeat(js_this_str(this, "repeat"), js_arg(args, 0)))
  r.method(sp, "replace", 2, ->(this, args, nt) js_str_replace(this, js_arg(args, 0), js_arg(args, 1), false))
  r.method(sp, "replaceAll", 2, ->(this, args, nt) js_str_replace(this, js_arg(args, 0), js_arg(args, 1), true))
  r.method(sp, "search", 1, ->(this, args, nt) js_str_search(this, js_arg(args, 0)))
  r.method(sp, "slice", 2, ->(this, args, nt) js_str_slice(js_this_str(this, "slice"), js_arg(args, 0), js_arg(args, 1)))
  r.method(sp, "split", 2, ->(this, args, nt) js_str_split(this, js_arg(args, 0), js_arg(args, 1)))
  r.method(sp, "substring", 2, ->(this, args, nt) js_str_substring(js_this_str(this, "substring"), js_arg(args, 0), js_arg(args, 1)))
  r.method(sp, "substr", 2, ->(this, args, nt) js_str_substr(js_this_str(this, "substr"), js_arg(args, 0), js_arg(args, 1)))
  r.method(sp, "toLowerCase", 0, ->(this, args, nt) js_str_case(js_this_str(this, "toLowerCase"), false))
  r.method(sp, "toUpperCase", 0, ->(this, args, nt) js_str_case(js_this_str(this, "toUpperCase"), true))
  r.method(sp, "toLocaleLowerCase", 0, ->(this, args, nt) js_str_case(js_this_str(this, "toLocaleLowerCase"), false))
  r.method(sp, "toLocaleUpperCase", 0, ->(this, args, nt) js_str_case(js_this_str(this, "toLocaleUpperCase"), true))
  r.method(sp, "toString", 0, ->(this, args, nt) js_this_string_value(this))
  r.method(sp, "valueOf", 0, ->(this, args, nt) js_this_string_value(this))
  r.method(sp, "trim", 0, ->(this, args, nt) js_str_trim(js_this_str(this, "trim"), true, true))
  ts = r.method(sp, "trimStart", 0, ->(this, args, nt) js_str_trim(js_this_str(this, "trimStart"), true, false))
  te = r.method(sp, "trimEnd", 0, ->(this, args, nt) js_str_trim(js_this_str(this, "trimEnd"), false, true))
  sp.define("trimLeft", ts, BUILTIN_ATTRS)
  sp.define("trimRight", te, BUILTIN_ATTRS)
  r.method(sp, "isWellFormed", 0, ->(this, args, nt) js_str_well_formed?(js_this_str(this, "isWellFormed")))
  r.method(sp, "toWellFormed", 0, ->(this, args, nt) js_str_to_well_formed(js_this_str(this, "toWellFormed")))
  it = r.method(sp, SYM_ITERATOR, 0, ->(this, args, nt) js_string_iter(js_this_str(this, "\[Symbol.iterator]")))
  r.set_intrinsic("%StringProto_iterator%", it)
  hm = ["anchor:a:name", "big:big:", "blink:blink:", "bold:b:", "fixed:tt:", "fontcolor:font:color", "fontsize:font:size", "italics:i:", "link:a:href", "small:small:", "strike:strike:", "sub:sub:", "sup:sup:"]
  i = 0
  while i < hm.size
    js_install_html_method(r, sp, hm[i])
    i += 1
  nil

-> js_install_html_method(r, sp, spec)
  parts = spec.split(":")
  nm = parts[0]
  tag = parts[1]
  at = parts.size > 2 ? parts[2] : ""
  r.method(sp, nm, at == "" ? 0 : 1, ->(this, args, nt) js_html_wrap(js_this_str(this, nm), tag, at, js_arg(args, 0)))

-> js_html_wrap(s, tag, at, v)
  open = "<" + tag
  open = open + " " + at + "=\"" + js_quot_escape(js_to_string(v)) + "\"" if at != ""
  open + ">" + s + "</" + tag + ">"

-> js_quot_escape(s)
  return s if s.index("\"") == nil
  sb = StringBuffer()
  i = 0
  while i < s.size
    if s.byte_at(i) == 34
      sb.append("&quot;")
    else
      j = s.index("\"", i)
      j = s.size if j == nil
      sb.append(s.slice(i, j - i))
      i = j - 1
    i += 1
  r = sb.to_s
  ccall("w_value_free_w", sb)
  r

-> js_this_string_value(v)
  return v if v.is_a?(String)
  return v.internal if js_special?(v, "String") && js_string?(v.internal)
  js_throw_type("String.prototype.valueOf requires that 'this' be a String")

-> js_str_last_index_of_v(this, args)
  s = js_this_str(this, "lastIndexOf")
  sub = js_to_string(js_arg(args, 0))
  p = js_to_number(js_arg(args, 1))
  from = p != p ? js_len(s) : (p == INF ? js_len(s) : (p == NEG_INF ? 0 : js_to_integer(p).to_i))
  js_str_last_index_of(s, sub, from) + ~0.0

-> js_str_index_of_v(this, args)
  s = js_this_str(this, "indexOf")
  sub = js_to_string(js_arg(args, 0))
  js_str_index_of(s, sub, js_clamp_int(js_arg(args, 1), 0, js_len(s), 0)) + ~0.0

# Bytes in the UTF-8 sequence starting at byte i (1 past the end).
-> js_utf8_len_at(s, i)
  return 1 if i >= s.size
  b = s.byte_at(i)
  return 1 if b < 128
  return 2 if b < 224
  return 3 if b < 240
  4
