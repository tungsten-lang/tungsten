# Regex fast-path matchers: raw ASCII precheck, capture fast-paths, match_exact?
# kernels, and specialized scan_all / gsub / split loops.
# Included by core/regex.w after core/regex/prefilter.w.

-> __regex_ascii_raw_precheck(subject, start_in, pf_kind_in, pf_char_in, pf_flag_in, pf_lit_in, pfs89_in, req_char_in, ascii_lex_in)
  start = start_in ## i64
  pf_kind = pf_kind_in ## i64
  pf_char = pf_char_in ## i64
  pf_flag = pf_flag_in ## i64
  pfs89 = pfs89_in ## i64[]
  req_char = req_char_in ## i64
  n_ascii = ccall_nobox("w_string_byte_length", subject) ## i64
  ptr = ccall_nobox("w_string_data_ptr", subject) ## i64
  if pf_kind == 4
    pf_lit_raw = pf_lit_in ## i64[]
    plen_raw = pf_lit_raw.size() ## i64
    lim_raw = n_ascii - plen_raw
    f_cp = (pf_lit_raw[0] >> 25) & 2097151
    l_cp = (pf_lit_raw[plen_raw - 1] >> 25) & 2097151
    if f_cp >= 128 || l_cp >= 128
      return -1
    ri = start
    start = n_ascii
    while ri <= lim_raw
      if raw_load_u8(ptr, ri) == f_cp && raw_load_u8(ptr, ri + plen_raw - 1) == l_cp
        rj = 1 ## i64
        while rj < plen_raw - 1 && raw_load_u8(ptr, ri + rj) == ((pf_lit_raw[rj] >> 25) & 2097151)
          rj = rj + 1
        if rj >= plen_raw - 1
          start = ri
          break
      ri = ri + 1
    if start >= n_ascii
      return -1
    return start
  elsif pf_kind == 1
    pf_cp = (pf_char >> 25) & 2097151
    while start < n_ascii && raw_load_u8(ptr, start) != pf_cp
      start = start + 1
    if start >= n_ascii
      return -1
  elsif pf_kind == 10
    pf_cp = (pf_char >> 25) & 2097151
    if start == 0
      start = 1
    while start < n_ascii && raw_load_u8(ptr, start - 1) != pf_cp
      start = start + 1
    if start >= n_ascii
      return -1
  elsif pf_kind == 6
    c1_cp = (pf_char >> 25) & 2097151
    c2_cp = (pf_flag >> 25) & 2097151
    while start < n_ascii
      b0 = raw_load_u8(ptr, start) ## i64
      if b0 == c1_cp || b0 == c2_cp
        break
      start = start + 1
    if start >= n_ascii
      return -1
  elsif pf_kind == 5
    lo_cp = (pf_char >> 25) & 2097151
    hi_cp = (pf_flag >> 25) & 2097151
    while start < n_ascii
      b0 = raw_load_u8(ptr, start) ## i64
      if b0 >= lo_cp && b0 <= hi_cp
        break
      start = start + 1
    if start >= n_ascii
      return -1
  elsif pf_kind == 7 && pf_char < 1073741824
    tbl_pf = ascii_lex_in ## i64[]
    while start < n_ascii
      b0 = raw_load_u8(ptr, start) ## i64
      if (((pf_char >> ((tbl_pf[b0] >> 3) & 31)) & 1) != pf_flag)
        break
      start = start + 1
    if start >= n_ascii
      return -1
  elsif pf_kind == 8
    while start < n_ascii
      b0 = raw_load_u8(ptr, start) ## i64
      if ((pfs89[b0 >> 5] >> (b0 & 31)) & 1) != 0
        break
      start = start + 1
    if start >= n_ascii
      return -1
  elsif pf_kind == 9
    lim9_r = n_ascii - 1
    while start < lim9_r
      b0 = raw_load_u8(ptr, start) ## i64
      if ((pfs89[b0 >> 5] >> (b0 & 31)) & 1) != 0
        b1 = raw_load_u8(ptr, start + 1) ## i64
        if ((pfs89[4 + (b1 >> 5)] >> (b1 & 31)) & 1) != 0
          break
      start = start + 1
    if start >= lim9_r
      return -1
  if req_char >= 0 && pf_kind != 4
    req_cp = (req_char >> 25) & 2097151
    if req_cp >= 128
      return -1
    ri = n_ascii - 1
    while ri >= start && raw_load_u8(ptr, ri) != req_cp
      ri = ri - 1
    if ri < start
      return -1
  start

-> __regex_cap_fast_match(cap_fast_kind_in, subj_in, n_in, start_in, saved_in, args_a_in, plen_c_in, pf_char_in, pf_flag_in, pf_lit_in)
  subj = subj_in ## i64[]
  n = n_in ## i64
  start = start_in ## i64
  saved = saved_in ## i64[]
  args_a = args_a_in ## i64[]
  if (cap_fast_kind_in ## i64) == 2
    sep1_c = args_a[7] ## i64
    sep2_c = args_a[12] ## i64
    stop_c = (n - 10) ## i64
    while start <= stop_c
      if subj[start + 4] == sep1_c
        if subj[start + 7] == sep2_c
          digs_c = (subj[start] & subj[start + 1] & subj[start + 2] & subj[start + 3] & subj[start + 5] & subj[start + 6] & subj[start + 8] & subj[start + 9]) ## i64
          if (digs_c & 1) != 0
            saved[0] = start
            saved[1] = start + 10
            saved[2] = start
            saved[3] = start + 4
            saved[4] = start + 5
            saved[5] = start + 7
            saved[6] = start + 8
            saved[7] = start + 10
            return true
      start = start + 1
    return false
  plen_c = plen_c_in ## i64
  pf_char = pf_char_in ## i64
  pf_flag = pf_flag_in ## i64
  cmask_c = args_a[plen_c + 2] ## i64
  stop_c1 = (n - plen_c - 1) ## i64
  while start <= stop_c1
    if subj[start + plen_c - 1] == pf_flag
      if subj[start] == pf_char
        if (subj[start + plen_c] & cmask_c) != 0
          j_c = 1 ## i64
          if plen_c > 2
            pf_lit_c = pf_lit_in ## i64[]
            while j_c < plen_c - 1
              if subj[start + j_c] != pf_lit_c[j_c]
                break
              j_c = j_c + 1
          if j_c >= plen_c - 1
            cap_b = (start + plen_c) ## i64
            cap_e = (cap_b + 1) ## i64
            while cap_e + 3 < n
              if (subj[cap_e] & subj[cap_e + 1] & subj[cap_e + 2] & subj[cap_e + 3] & cmask_c) == 0
                break
              cap_e = cap_e + 4
            while cap_e < n
              if (subj[cap_e] & cmask_c) == 0
                break
              cap_e = cap_e + 1
            saved[0] = start
            saved[1] = cap_e
            saved[2] = cap_b
            saved[3] = cap_e
            return true
    start = start + 1
  false

-> __regex_match_exact_fast(kind_in, subj_in, n_in, subj_ascii_in, ops_in, args_a_in, branches_in, pf_set_in, pf_char_in, pf_flag_in, cls_bm_in, classes_in, lead_after_char_in)
  subj = subj_in ## i64[]
  n = n_in ## i64
  subj_ascii = subj_ascii_in ## i64
  i = 0 ## i64
  kind = kind_in ## i64
  if (kind == 6 || kind == 7) && subj_ascii == 1
    args_a = args_a_in ## i64[]
    bm9 = pf_set_in ## i64[]
    pf1 = pf_char_in ## i64
    pf2 = pf_flag_in ## i64
    m_ic = (kind == 7 ? 1074233368 : 0) ## i64
    lim6 = (n - 1) ## i64
    s6 = 0 ## i64
    if s6 >= lim6
      return 0
    ch6 = ((subj[0] >> 25) & 31) ## i64
    cp6 = 0 ## i64
    while s6 < lim6
      while s6 < lim6
        cp6 = ((subj[s6 + 1] >> 25) & 31) ## i64
        if (((pf1 >> ch6) & (pf2 >> cp6)) & 1) != 0
          break
        ch6 = cp6
        s6 = s6 + 1
      if s6 >= lim6
        return 0
      ent6 = bm9[8 + ch6] ## i64
      pc6 = (ent6 & 65535) ## i64
      end_pc = (ent6 >> 16) ## i64
      sp6 = (s6 + (end_pc - pc6)) ## i64
      if sp6 <= n && (subj[sp6 - 1] | m_ic) == (args_a[end_pc - 1] | m_ic) && (subj[s6] | m_ic) == (args_a[pc6] | m_ic)
        pc6 = pc6 + 1
        k6 = (s6 + 1) ## i64
        end_mid = (end_pc - 1) ## i64
        while pc6 < end_mid && (subj[k6] | m_ic) == (args_a[pc6] | m_ic)
          pc6 = pc6 + 1
          k6 = k6 + 1
        if pc6 >= end_mid
          return 1
      ch6 = cp6
      s6 = s6 + 1
    return 0
  if kind == 8
    ops = ops_in ## i64[]
    args_a = args_a_in ## i64[]
    end8 = (ops.size() - 2) ## i64
    plen8 = (end8 - 1) ## i64
    lim8 = (n - plen8) ## i64
    m8 = pf_char_in ## i64
    if end8 == 11
      if ops[5] == 1
        if ops[8] == 1
          sep1_8 = args_a[5] ## i64
          sep2_8 = args_a[8] ## i64
          while i <= lim8
            if subj[i + 4] == sep1_8
              if subj[i + 7] == sep2_8
                if (subj[i] & subj[i + 1] & subj[i + 2] & subj[i + 3] & subj[i + 5] & subj[i + 6] & subj[i + 8] & subj[i + 9] & m8) != 0
                  return 1
            i = i + 1
          return 0
    while i <= lim8
      if (subj[i] & m8) != 0
        pc8 = 2 ## i64
        while pc8 < end8
          ch8 = subj[i + pc8 - 1] ## i64
          if ops[pc8] == 11
            if (ch8 & args_a[pc8]) == 0
              break
          elsif ch8 != args_a[pc8]
            break
          pc8 = pc8 + 1
        if pc8 >= end8
          return 1
      i = i + 1
    return 0
  if kind >= 9
    if kind == 9
      args_a = args_a_in ## i64[]
      ch9 = args_a[5] ## i64
      m9 = args_a[1] ## i64
      i = 1 ## i64
      while i + 3 < n
        if subj[i] == ch9 || subj[i + 1] == ch9 || subj[i + 2] == ch9 || subj[i + 3] == ch9
          if subj[i] == ch9 && (subj[i - 1] & m9) != 0
            return 1
          if subj[i + 1] == ch9 && (subj[i] & m9) != 0
            return 1
          if subj[i + 2] == ch9 && (subj[i + 1] & m9) != 0
            return 1
          if subj[i + 3] == ch9 && (subj[i + 2] & m9) != 0
            return 1
        i = i + 4
      while i < n
        if subj[i] == ch9 && (subj[i - 1] & m9) != 0
          return 1
        i = i + 1
      return 0
    if kind == 10
      args_a = args_a_in ## i64[]
      m10 = args_a[1] ## i64
      c1_10 = args_a[5] ## i64
      c2_10 = args_a[6] ## i64
      skip2_10 = (((c1_10 | c2_10) & m10) == 0 ? 2 : 1) ## i64
      while i < n
        if (subj[i] & m10) != 0
          i = i + 1
          while i < n && (subj[i] & m10) != 0
            i = i + 1
          if i + 1 >= n || subj[i] != c1_10 || subj[i + 1] != c2_10
            return 1
          i = i + skip2_10
        else
          i = i + 1
      return 0
    if kind == 11
      args_a = args_a_in ## i64[]
      c11 = args_a[2] ## i64
      m11 = args_a[5] ## i64
      while i < n
        if (subj[i] & m11) != 0
          if i == 0 || (subj[i - 1] != c11 && (subj[i - 1] & 2) == 0)
            return 1
          i = i + 1
          while i < n && (subj[i] & 2) != 0
            i = i + 1
        else
          i = i + 1
      return 0
    if kind == 14
      args_a = args_a_in ## i64[]
      c14 = pf_char_in ## i64
      m14 = args_a[4] ## i64
      lim14 = (n - 1) ## i64
      while i + 3 < lim14
        if subj[i] == c14 || subj[i + 1] == c14 || subj[i + 2] == c14 || subj[i + 3] == c14
          if subj[i] == c14 && (subj[i + 1] & m14) != 0
            return 1
          if subj[i + 1] == c14 && (subj[i + 2] & m14) != 0
            return 1
          if subj[i + 2] == c14 && (subj[i + 3] & m14) != 0
            return 1
          if subj[i + 3] == c14 && (subj[i + 4] & m14) != 0
            return 1
        i = i + 4
      while i < lim14
        if subj[i] == c14 && (subj[i + 1] & m14) != 0
          return 1
        i = i + 1
      return 0
    if kind == 15
      args_a = args_a_in ## i64[]
      m1_15 = args_a[1] ## i64
      sep15 = args_a[4] ## i64
      m2_15 = args_a[5] ## i64
      lim15 = (n - 1) ## i64
      i = 1 ## i64
      while i + 3 < lim15
        if subj[i] == sep15 || subj[i + 1] == sep15 || subj[i + 2] == sep15 || subj[i + 3] == sep15
          if subj[i] == sep15 && (subj[i - 1] & m1_15) != 0 && (subj[i + 1] & m2_15) != 0
            return 1
          if subj[i + 1] == sep15 && (subj[i] & m1_15) != 0 && (subj[i + 2] & m2_15) != 0
            return 1
          if subj[i + 2] == sep15 && (subj[i + 1] & m1_15) != 0 && (subj[i + 3] & m2_15) != 0
            return 1
          if subj[i + 3] == sep15 && (subj[i + 2] & m1_15) != 0 && (subj[i + 4] & m2_15) != 0
            return 1
        i = i + 4
      while i < lim15
        if subj[i] == sep15 && (subj[i - 1] & m1_15) != 0 && (subj[i + 1] & m2_15) != 0
          return 1
        i = i + 1
      return 0
    if kind == 16
      args_a = args_a_in ## i64[]
      m16 = args_a[2] ## i64
      sep16 = args_a[6] ## i64
      lim16 = (n - 1) ## i64
      at16 = 1 ## i64
      while at16 < lim16
        while at16 + 3 < lim16
          if subj[at16] == sep16 || subj[at16 + 1] == sep16 || subj[at16 + 2] == sep16 || subj[at16 + 3] == sep16
            break
          at16 = at16 + 4
        while at16 < lim16 && subj[at16] != sep16
          at16 = at16 + 1
        if at16 >= lim16
          return 0
        if (subj[at16 - 1] & m16) != 0
          s16 = (at16 - 1) ## i64
          while s16 > 0 && (subj[s16 - 1] & m16) != 0
            s16 = s16 - 1
          while s16 < at16
            len16 = (at16 - s16) ## i64
            if at16 + len16 < n
              k16 = 0 ## i64
              while k16 < len16 && subj[s16 + k16] == subj[at16 + 1 + k16]
                k16 = k16 + 1
              if k16 >= len16
                return 1
            s16 = s16 + 1
        at16 = at16 + 1
      return 0
    if kind == 12 && subj_ascii == 1
      args_a = args_a_in ## i64[]
      branches = branches_in ## i64[]
      cbm12 = cls_bm_in ## i64[]
      sep12 = args_a[4] ## i64
      c0_12 = (args_a[1] ## i64) * 6
      lo12 = args_a[5] ## i64
      hi12 = branches[5] ## i64
      lim12 = (n - 1) ## i64
      i = 1 ## i64
      while i < lim12
        if subj[i] == sep12
          ch_n12 = subj[i + 1] ## i64
          if ch_n12 >= lo12 && ch_n12 <= hi12
            ch_p12 = subj[i - 1] ## i64
            if ((cbm12[c0_12 + (ch_p12 >> 30)] >> ((ch_p12 >> 25) & 31)) & 1) != 0
              return 1
        i = i + 1
      return 0
  if kind == 1
    mask = pf_char_in ## i64
    while i < n
      if (subj[i] & mask) != 0
        return 1
      i = i + 1
    return 0
  if kind == 2
    if subj_ascii != 1
      return -1
    bm = pf_set_in ## i64[]
    m32 = pf_char_in ## i64
    while i < n
      ch = subj[i] ## i64
      if ((m32 >> ((ch >> 25) & 31)) & 1) != 0 && ((bm[ch >> 30] >> ((ch >> 25) & 31)) & 1) != 0
        return 1
      i = i + 1
    return 0
  if kind == 3
    lo = pf_char_in ## i64
    hi = pf_flag_in ## i64
    if classes_in == nil
      while i < n
        ch = subj[i] ## i64
        if ch >= lo && ch <= hi
          return 1
        i = i + 1
      return 0
    cbm = cls_bm_in ## i64[]
    rlo = cbm[4] ## i64
    rhi = cbm[5] ## i64
    while i < n
      ch = subj[i] ## i64
      if ch >= lo && ch <= hi
        if (ch >= rlo && ch <= rhi) || __regex_class_match_slow(classes_in[0], ch)
          return 1
      i = i + 1
    return 0
  if kind == 4
    m1 = pf_char_in ## i64
    args_a = args_a_in ## i64[]
    m2 = args_a[2] ## i64
    lim = (n - 1) ## i64
    while i < lim
      if (((m1 >> ((subj[i] >> 3) & 31)) & (m2 >> ((subj[i + 1] >> 3) & 31))) & 1) != 0
        return 1
      i = i + 1
    return 0
  if kind == 5 && subj_ascii == 1
    cbm5 = cls_bm_in ## i64[]
    args_a = args_a_in ## i64[]
    lead_ch = lead_after_char_in ## i64
    dot_ch = args_a[8] ## i64
    c0_b = (args_a[1] ## i64) * 6
    c1_b = (args_a[5] ## i64) * 6
    c2_b = (args_a[9] ## i64) * 6
    b1_0 = cbm5[c1_b] ## i64
    b1_1 = cbm5[c1_b + 1] ## i64
    b1_2 = cbm5[c1_b + 2] ## i64
    b1_3 = cbm5[c1_b + 3] ## i64
    at_pos = 1 ## i64
    while at_pos < n
      while at_pos + 3 < n
        if subj[at_pos] == lead_ch || subj[at_pos + 1] == lead_ch || subj[at_pos + 2] == lead_ch || subj[at_pos + 3] == lead_ch
          break
        at_pos = at_pos + 4
      while at_pos < n && subj[at_pos] != lead_ch
        at_pos = at_pos + 1
      if at_pos >= n
        return 0
      ch_prev = subj[at_pos - 1] ## i64
      if ((cbm5[c0_b + (ch_prev >> 30)] >> ((ch_prev >> 25) & 31)) & 1) != 0
        e = (at_pos + 1) ## i64
        while e < n
          ch = subj[e] ## i64
          blk = (ch >> 30) ## i64
          if blk < 2
            bm_cur = (blk == 0 ? b1_0 : b1_1) ## i64
          else
            bm_cur = (blk == 2 ? b1_2 : b1_3) ## i64
          if ((bm_cur >> ((ch >> 25) & 31)) & 1) == 0
            break
          e = e + 1
        if e > at_pos + 1 && e + 2 < n && subj[e] == dot_ch
          c_t1 = subj[e + 1] ## i64
          c_t2 = subj[e + 2] ## i64
          if ((cbm5[c2_b + (c_t1 >> 30)] >> ((c_t1 >> 25) & 31)) & 1) != 0 && ((cbm5[c2_b + (c_t2 >> 30)] >> ((c_t2 >> 25) & 31)) & 1) != 0
            return 1
      at_pos = at_pos + 1
    return 0
  -1

-> __regex_scan_flag_fast(s_str, subj_in, n_in, is_ascii_f, mask_in)
  out = []
  subj = subj_in ## i64[]
  n = n_in ## i64
  mask = mask_in ## i64
  i = 0 ## i64
  while i < n
    while i < n && (subj[i] & mask) == 0
      i = i + 1
    if i >= n
      break
    b0_f = i ## i64
    i = i + 1
    while i < n && (subj[i] & mask) != 0
      i = i + 1
    out.push(is_ascii_f ? s_str.slice(b0_f, i - b0_f) : ccall("w_string_from_codes", subj, b0_f, i - b0_f))
  out

-> __regex_gsub_flag_fast(subject, s_str, replacement, subj_in, n_in, is_ascii_f, mask_in)
  subj = subj_in ## i64[]
  n = n_in ## i64
  mask = mask_in ## i64
  i = 0 ## i64
  while i < n && (subj[i] & mask) == 0
    i = i + 1
  if i >= n
    return subject
  sb_f = StringBuffer(n + 16)
  last_f = 0 ## i64
  while i < n
    if i > last_f
      if is_ascii_f
        if i - last_f == 1
          sb_f.append(wvalue_from_bits((-1_970_324_836_974_590 | (((subj[last_f] >> 25) & 255) << 4)) ## i64))
        else
          sb_f.append(s_str.slice(last_f, i - last_f))
      else
        sb_f.append(ccall("w_string_from_codes", subj, last_f, i - last_f))
    i = i + 1
    while i < n && (subj[i] & mask) != 0
      i = i + 1
    sb_f.append(replacement)
    last_f = i
    while i < n && (subj[i] & mask) == 0
      i = i + 1
  if last_f < n
    if is_ascii_f
      if n - last_f == 1
        sb_f.append(wvalue_from_bits((-1_970_324_836_974_590 | (((subj[last_f] >> 25) & 255) << 4)) ## i64))
      else
        sb_f.append(s_str.slice(last_f, n - last_f))
    else
      sb_f.append(ccall("w_string_from_codes", subj, last_f, n - last_f))
  sb_f.to_s()

-> __regex_split_delim_fast(s_str, subj_in, n_in, is_ascii_s, args_s_in)
  out = []
  args_s = args_s_in ## i64[]
  m1_s = args_s[2] ## i64
  delim_s = args_s[3] ## i64
  m2_s = args_s[5] ## i64
  subj = subj_in ## i64[]
  n = n_in ## i64
  last_s = 0 ## i64
  i_s = 0 ## i64
  while i_s < n
    while i_s < n && subj[i_s] != delim_s
      i_s = i_s + 1
    if i_s >= n
      break
    b0_s = i_s ## i64
    while b0_s > last_s && (subj[b0_s - 1] & m1_s) != 0
      b0_s = b0_s - 1
    e0_s = (i_s + 1) ## i64
    while e0_s < n && (subj[e0_s] & m2_s) != 0
      e0_s = e0_s + 1
    if is_ascii_s
      if b0_s - last_s == 1
        out.push(wvalue_from_bits((-1_970_324_836_974_590 | (((subj[last_s] >> 25) & 255) << 4)) ## i64))
      else
        out.push(s_str.slice(last_s, b0_s - last_s))
    else
      out.push(b0_s <= last_s ? "" : ccall("w_string_from_codes", subj, last_s, b0_s - last_s))
    last_s = e0_s
    i_s = e0_s
  if is_ascii_s
    if n - last_s == 1
      out.push(wvalue_from_bits((-1_970_324_836_974_590 | (((subj[last_s] >> 25) & 255) << 4)) ## i64))
    else
      out.push(s_str.slice(last_s, n - last_s))
  else
    out.push(n <= last_s ? "" : ccall("w_string_from_codes", subj, last_s, n - last_s))
  out

-> __regex_decode_subject(subject, subj_buf_in, ascii_lex_in, state_in)
  state = state_in ## i64[]
  if subject.ascii?()
    state[1] = 1
    sv = (wvalue_bits(subject) & -2) ## i64
    smode = (sv >> 1) & 7
    buf = subj_buf_in != nil ? (subj_buf_in ## i64[]) : i64[64]
    tbl = ascii_lex_in ## i64[]
    if smode <= 5
      i = 0 ## i64
      while i < smode
        buf[i] = tbl[(sv >> (4 + 8 * i)) & 255]
        i = i + 1
      state[0] = smode
      return buf
    n = ccall_nobox("w_string_byte_length", subject) ## i64
    if n > buf.size()
      cap = buf.size() ## i64
      while cap < n
        cap = cap * 2
      buf = i64[cap]
    ptr = ccall_nobox("w_string_data_ptr", subject) ## i64
    i = 0 ## i64
    while i < n
      buf[i] = tbl[raw_load_u8(ptr, i)]
      i = i + 1
    state[0] = n
    return buf
  state[1] = 0
  codes = subject.codes() ## i64[]
  n = codes.size() ## i64
  i = 0 ## i64
  while i < n
    codes[i] = codes[i] & 70368744177663
    i = i + 1
  state[0] = n
  codes

-> __regex_pure_lit_find(subject, start_in, pure_lit_in, pf_lit_str_in, pf_lit_len_in, saved_in)
  start = start_in ## i64
  pure_lit = pure_lit_in ## i64
  pf_lit_len = pf_lit_len_in ## i64
  saved = saved_in ## i64[]
  s_str_p = subject ## string
  if !s_str_p.ascii?()
    return -2
  if pure_lit == 1
    pos = s_str_p.index(pf_lit_str_in ## string, start)
    if pos == nil
      return -1
    s0_lit = pos ## i64
    saved[0] = s0_lit
    saved[1] = s0_lit + pf_lit_len
    return s_str_p.size() ## i64
  if start > 0
    return -1
  ok_lit = pure_lit == 2 ? s_str_p.starts_with?(pf_lit_str_in) : (s_str_p == pf_lit_str_in)
  if !ok_lit
    return -1
  saved[0] = 0
  saved[1] = pf_lit_len
  s_str_p.size() ## i64

-> __regex_pure_lit_match_p(subject, sv_tag_in, lit_mode_in, pf_lit_str_in, pf_lit_ptr_in, pf_lit_bytes_in)
  sv_tag = sv_tag_in ## i64
  lit_mode = lit_mode_in ## i64
  s_str = subject ## string
  if lit_mode == 1
    return s_str.index(pf_lit_str_in ## string) != nil
  if lit_mode == 2
    p_ptr = pf_lit_ptr_in ## i64
    p_len = pf_lit_bytes_in ## i64
    if p_ptr != 0 && ((sv_tag >> 1) & 7) >= 6
      if (ccall_nobox("w_string_byte_length", subject) ## i64) < p_len
        return false
      s_ptr = ccall_nobox("w_string_data_ptr", subject) ## i64
      si_p = 0 ## i64
      while si_p + 3 < p_len
        if raw_load_u8(s_ptr, si_p) != raw_load_u8(p_ptr, si_p) || raw_load_u8(s_ptr, si_p + 1) != raw_load_u8(p_ptr, si_p + 1) || raw_load_u8(s_ptr, si_p + 2) != raw_load_u8(p_ptr, si_p + 2) || raw_load_u8(s_ptr, si_p + 3) != raw_load_u8(p_ptr, si_p + 3)
          return false
        si_p = si_p + 4
      while si_p < p_len
        if raw_load_u8(s_ptr, si_p) != raw_load_u8(p_ptr, si_p)
          return false
        si_p = si_p + 1
      return true
    return s_str.starts_with?(pf_lit_str_in)
  s_str == pf_lit_str_in

-> __regex_last_capture(index, last_saved_in, last_ncap_in, last_subj_str, last_subj, last_subj_len)
  idx = index ## i64
  saved = last_saved_in ## i64[]
  ncap = last_ncap_in ## i64
  if idx == 1000001
    a = saved[0] ## i64
    if a < 0
      return nil
    return Regex.span_from_str(last_subj_str, last_subj, 0, a)
  if idx == 1000002
    b = saved[1] ## i64
    if b < 0
      return nil
    return Regex.span_from_str(last_subj_str, last_subj, b, last_subj_len)
  if idx == 1000003
    g = ncap - 1
    while g >= 1
      ga = saved[g * 2] ## i64
      gb = saved[g * 2 + 1] ## i64
      if ga >= 0 && gb >= 0
        return Regex.span_from_str(last_subj_str, last_subj, ga, gb)
      g = g - 1
    return nil
  if idx < 0 || idx >= ncap
    return nil
  a = saved[idx * 2] ## i64
  b = saved[idx * 2 + 1] ## i64
  if a < 0 || b < 0
    return nil
  Regex.span_from_str(last_subj_str, last_subj, a, b)

-> __regex_copy_subj_if_needed(last_subj, last_subj_str, last_subj_len)
  if last_subj != nil && (last_subj_str == nil || !(last_subj_str ## string).ascii?())
    n = last_subj_len ## i64
    sc = i64[n]
    si = 0 ## i64
    src = last_subj ## i64[]
    while si < n
      sc[si] = src[si]
      si = si + 1
    return sc
  nil


