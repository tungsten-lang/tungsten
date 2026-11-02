# Regex prefilter advance and linear / bounded-backtracking VM execution loops.
# Included by core/regex.w after core/regex/matcher_fast.w.

-> __regex_scan_rep_end(tpc_in, sp_in, subj_in, n_in, subj_ascii_in, ops_in, args_a_in, branches_in, cls_bm_in, classes_in)
  tpc = tpc_in ## i64
  e = sp_in ## i64
  subj = subj_in ## i64[]
  n = n_in ## i64
  subj_ascii = subj_ascii_in ## i64
  ops = ops_in ## i64[]
  args_a = args_a_in ## i64[]
  branches = branches_in ## i64[]
  top = ops[tpc] ## i64
  if top == 11
    mask = args_a[tpc] ## i64
    if branches[tpc] == 0
      while e < n && (subj[e] & mask) != 0
        e = e + 1
    else
      while e < n && (subj[e] & mask) == 0
        e = e + 1
  elsif top == 17
    want = args_a[tpc] ## i64
    mask = branches[tpc] ## i64
    while e < n && subj[e] >= want && subj[e] <= mask
      e = e + 1
  elsif top == 1
    want = args_a[tpc] ## i64
    while e < n && subj[e] == want
      e = e + 1
  elsif top == 18
    want = args_a[tpc] ## i64
    mask = branches[tpc] ## i64
    while e < n && (subj[e] == want || subj[e] == mask)
      e = e + 1
  elsif top == 19
    want = args_a[tpc] ## i64
    mask = branches[tpc] ## i64
    if want < 1073741824 && mask == 0
      while e < n && ((want >> ((subj[e] >> 3) & 31)) & 1) != 0
        e = e + 1
    else
      while e < n && __regex_cat_match(want, mask, subj[e])
        e = e + 1
  elsif top == 2
    want = args_a[tpc] ## i64
    while e < n && subj[e] != want
      e = e + 1
  elsif top == 3
    cls_bm = cls_bm_in ## i64[]
    cidx = (args_a[tpc] ## i64) * 6
    if subj_ascii == 1
      bm0 = cls_bm[cidx] ## i64
      bm1 = cls_bm[cidx + 1] ## i64
      bm2 = cls_bm[cidx + 2] ## i64
      bm3 = cls_bm[cidx + 3] ## i64
      while e < n
        ch = subj[e] ## i64
        blk = ch >> 30
        if blk < 2
          bm = (blk == 0 ? bm0 : bm1) ## i64
        else
          bm = (blk == 2 ? bm2 : bm3) ## i64
        if ((bm >> ((ch >> 25) & 31)) & 1) == 0
          break
        e = e + 1
    else
      bm2 = cls_bm[cidx + 4] ## i64
      bm3 = cls_bm[cidx + 5] ## i64
      while e < n
        ch = subj[e] ## i64
        cp = (ch >> 25) & 2097151
        if cp < 128
          if ((cls_bm[cidx + (cp >> 5)] >> (cp & 31)) & 1) == 0
            break
        elsif !(ch >= bm2 && ch <= bm3) && !__regex_class_match_slow(classes_in[args_a[tpc]], ch)
          break
        e = e + 1
  e

-> __regex_lead_after_advance(subj_in, n_in, subj_ascii_in, start_in, smode_in, lead_after_char_in, lead_rep_nb_in, ops_in, args_a_in, branches_in, cls_bm_in, classes_in)
  subj = subj_in ## i64[]
  n = n_in ## i64
  subj_ascii = subj_ascii_in ## i64
  start = start_in ## i64
  smode = smode_in ## i64
  lead_after_char = lead_after_char_in ## i64
  lead_rep_nb = lead_rep_nb_in ## i64
  ops = ops_in ## i64[]
  args_a = args_a_in ## i64[]
  branches = branches_in ## i64[]
  cls_bm = cls_bm_in ## i64[]
  at_pos = start + 1
  while at_pos + 3 < n
    if subj[at_pos] == lead_after_char
      break
    if subj[at_pos + 1] == lead_after_char
      at_pos = at_pos + 1
      break
    if subj[at_pos + 2] == lead_after_char
      at_pos = at_pos + 2
      break
    if subj[at_pos + 3] == lead_after_char
      at_pos = at_pos + 3
      break
    at_pos = at_pos + 4
  while at_pos < n && subj[at_pos] != lead_after_char
    at_pos = at_pos + 1
  if at_pos >= n
    return -1
  s0 = at_pos
  tpc = (lead_rep_nb == 2 ? 4 : 3) ## i64
  top = ops[tpc] ## i64
  if top == 3
    cidx = (args_a[tpc] ## i64) * 6
    if smode == 0 && lead_rep_nb == 1
      ch = subj[s0 - 1] ## i64
      if subj_ascii == 1
        if ((cls_bm[cidx + (ch >> 30)] >> ((ch >> 25) & 31)) & 1) != 0
          s0 = s0 - 1
      else
        cp = (ch >> 25) & 2097151
        if cp < 128
          if ((cls_bm[cidx + (cp >> 5)] >> (cp & 31)) & 1) != 0
            s0 = s0 - 1
        elsif (ch >= cls_bm[cidx + 4] && ch <= cls_bm[cidx + 5]) || __regex_class_match_slow(classes_in[args_a[tpc]], ch)
          s0 = s0 - 1
    elsif subj_ascii == 1
      bm0 = cls_bm[cidx] ## i64
      bm1 = cls_bm[cidx + 1] ## i64
      bm2 = cls_bm[cidx + 2] ## i64
      bm3 = cls_bm[cidx + 3] ## i64
      while s0 > start
        ch = subj[s0 - 1] ## i64
        blk = ch >> 30
        if blk < 2
          bm = (blk == 0 ? bm0 : bm1) ## i64
        else
          bm = (blk == 2 ? bm2 : bm3) ## i64
        if ((bm >> ((ch >> 25) & 31)) & 1) == 0
          break
        s0 = s0 - 1
    else
      bm2 = cls_bm[cidx + 4] ## i64
      bm3 = cls_bm[cidx + 5] ## i64
      while s0 > start
        ch = subj[s0 - 1] ## i64
        cp = (ch >> 25) & 2097151
        if cp < 128
          if ((cls_bm[cidx + (cp >> 5)] >> (cp & 31)) & 1) == 0
            break
        elsif !(ch >= bm2 && ch <= bm3) && !__regex_class_match_slow(classes_in[args_a[tpc]], ch)
          break
        s0 = s0 - 1
  elsif top == 11
    mask = args_a[tpc] ## i64
    if branches[tpc] == 0
      if smode == 0 && lead_rep_nb == 1
        if (subj[s0 - 1] & mask) != 0
          s0 = s0 - 1
      else
        while s0 > start && (subj[s0 - 1] & mask) != 0
          s0 = s0 - 1
    else
      while s0 > start && (subj[s0 - 1] & mask) == 0
        s0 = s0 - 1
  elsif top == 17
    want = args_a[tpc] ## i64
    mask = branches[tpc] ## i64
    while s0 > start && subj[s0 - 1] >= want && subj[s0 - 1] <= mask
      s0 = s0 - 1
  else
    while s0 > start && __regex_consume_at(tpc, subj[s0 - 1], ops, args_a, branches, cls_bm, classes_in)
      s0 = s0 - 1
  if s0 == at_pos
    return (at_pos + 1) << 1
  (s0 << 31) | (at_pos << 1) | 1

-> __regex_prefilter_advance(subj_in, n_in, subj_ascii_in, start_in, max_start_in, pf_kind_in, pf_char_in, pf_flag_in, pfs89_in, pf_set_in, pf_set_n_in, pf_lit_in, pf_lit_n_in, limit_in, first_in, last_in)
  subj = subj_in ## i64[]
  n = n_in ## i64
  subj_ascii = subj_ascii_in ## i64
  start = start_in ## i64
  max_start = max_start_in ## i64
  pf_kind = pf_kind_in ## i64
  pf_char = pf_char_in ## i64
  pf_flag = pf_flag_in ## i64
  pfs89 = pfs89_in ## i64[]
  pf_set = pf_set_in ## i64[]
  pf_set_n = pf_set_n_in ## i64
  pf_lit = pf_lit_in ## i64[]
  pf_lit_n = pf_lit_n_in ## i64
  limit = limit_in ## i64
  first = first_in ## i64
  last = last_in ## i64
  ch = 0 ## i64
  cp = 0 ## i64
  blk = 0 ## i64
  bm = 0 ## i64
  j = 0 ## i64
  i = 0 ## i64
  if pf_kind == 2
    while start <= max_start && (subj[start] & pf_char) == 0
      start = start + 1
  elsif pf_kind == 1
    while start <= max_start && subj[start] != pf_char
      start = start + 1
  elsif pf_kind == 10
    if start == 0
      start = 1
    while start <= max_start && subj[start - 1] != pf_char
      start = start + 1
  elsif pf_kind == 6
    while start <= max_start && subj[start] != pf_char && subj[start] != pf_flag
      start = start + 1
  elsif pf_kind == 8
    if subj_ascii == 1
      while start <= max_start
        ch = subj[start] ## i64
        if ((pf_char >> ((ch >> 25) & 31)) & 1) != 0 && ((pfs89[ch >> 30] >> ((ch >> 25) & 31)) & 1) != 0
          break
        start = start + 1
    else
      while start <= max_start
        ch = (subj[start] >> 25) & 2097151
        if ch < 128 && ((pf_char >> (ch & 31)) & 1) != 0 && ((pfs89[ch >> 5] >> (ch & 31)) & 1) != 0
          break
        start = start + 1
  elsif pf_kind == 9
    lim9_m = (max_start < n - 1 ? max_start : (n - 1)) ## i64
    if subj_ascii == 1 && start <= lim9_m
      ch = (subj[start] >> 25) & 31
      while start + 3 <= lim9_m
        cp = (subj[start + 1] >> 25) & 31
        blk = (subj[start + 2] >> 25) & 31
        bm = (subj[start + 3] >> 25) & 31
        j = (subj[start + 4] >> 25) & 31
        if ((((pf_char >> ch) & (pf_flag >> cp)) | ((pf_char >> cp) & (pf_flag >> blk)) | ((pf_char >> blk) & (pf_flag >> bm)) | ((pf_char >> bm) & (pf_flag >> j))) & 1) != 0
          break
        ch = j
        start = start + 4
      while start <= lim9_m
        cp = (subj[start + 1] >> 25) & 31
        if (((pf_char >> ch) & (pf_flag >> cp)) & 1) != 0
          break
        ch = cp
        start = start + 1
    elsif subj_ascii == 0
      while start <= lim9_m
        ch = (subj[start] >> 25) & 2097151
        if ch < 128 && ((pf_char >> (ch & 31)) & 1) != 0
          cp = (subj[start + 1] >> 25) & 2097151
          if cp < 128 && ((pf_flag >> (cp & 31)) & 1) != 0
            break
        start = start + 1
    if start > lim9_m
      start = n
  elsif pf_kind == 3
    while start <= max_start
      ch = subj[start] ## i64
      if pf_flag != 0 && (ch & pf_flag) != 0
        break
      j = 0
      while j < pf_set_n && pf_set[j] != ch
        j = j + 1
      if j < pf_set_n
        break
      start = start + 1
  elsif pf_kind == 4
    i = start
    start = max_start + 1
    while i <= limit
      if subj[i] == first && subj[i + pf_lit_n - 1] == last
        j = 1
        while j < pf_lit_n - 1 && subj[i + j] == pf_lit[j]
          j = j + 1
        if j >= pf_lit_n - 1
          start = i
          break
      i = i + 1
  elsif pf_kind == 5
    while start <= max_start && (subj[start] < pf_char || subj[start] > pf_flag)
      start = start + 1
  elsif pf_kind == 7
    if pf_char < 1073741824
      if pf_flag == 0
        while start <= max_start && ((pf_char >> ((subj[start] >> 3) & 31)) & 1) == 0
          start = start + 1
      else
        while start <= max_start && ((pf_char >> ((subj[start] >> 3) & 31)) & 1) != 0
          start = start + 1
    else
      while start <= max_start && !__regex_cat_match(pf_char, pf_flag, subj[start])
        start = start + 1
  if start > max_start || start >= n
    return -1
  start

-> __regex_run_linear1(subj_in, n_in, subj_ascii_in, start_in, smode_in, lead_after_char_in, lead_rep_nb_in, lead_e_in, ops_in, args_a_in, branches_in, cls_bm_in, classes_in, saved_in, nl_in, search_from_in)
  subj = subj_in ## i64[]
  n = n_in ## i64
  subj_ascii = subj_ascii_in ## i64
  start = start_in ## i64
  smode = smode_in ## i64
  lead_after_char = lead_after_char_in ## i64
  lead_rep_nb = lead_rep_nb_in ## i64
  lead_e = lead_e_in ## i64
  ops = ops_in ## i64[]
  args_a = args_a_in ## i64[]
  branches = branches_in ## i64[]
  cls_bm = cls_bm_in ## i64[]
  saved = saved_in ## i64[]
  nl = nl_in ## i64
  search_from = search_from_in ## i64
  pc = 0 ## i64
  sp = 0 ## i64
  if lead_after_char >= 0
    saved[0] = start
    if lead_rep_nb == 2
      saved[2] = start
      saved[3] = lead_e
      pc = 7
    else
      pc = 5
    sp = lead_e + 1
  else
    pc = 0
    sp = start
  rg_pos = -1 ## i64
  rg_sp = 0 ## i64
  rg_cont = 0 ## i64
  op = 0 ## i64
  mask = 0 ## i64
  tpc = 0 ## i64
  top = 0 ## i64
  e = 0 ## i64
  want = 0 ## i64
  cidx = 0 ## i64
  slot = 0 ## i64
  ch = 0 ## i64
  cp = 0 ## i64
  j = 0 ## i64
  while true
    while true
      op = ops[pc] ## i64
      if op == 11
        mask = args_a[pc] ## i64
        if branches[pc] == 0
          if sp < n && (subj[sp] & mask) != 0
            pc = pc + 1
            sp = sp + 1
            while ops[pc] == 11 && branches[pc] == 0 && sp < n && (subj[sp] & args_a[pc]) != 0
              pc = pc + 1
              sp = sp + 1
          else
            break
        else
          if sp < n && (subj[sp] & mask) == 0
            pc = pc + 1
            sp = sp + 1
          else
            break
      elsif op == 1
        if sp < n && subj[sp] == args_a[pc]
          pc = pc + 1
          sp = sp + 1
          while ops[pc] == 1
            if sp < n && subj[sp] == args_a[pc]
              pc = pc + 1
              sp = sp + 1
            else
              pc = -1
              break
          if pc < 0
            break
          if ops[pc] == 5
            pc = args_a[pc] ## i64
        else
          break
      elsif op == 7
        saved[args_a[pc]] = sp
        pc = pc + 1
        while ops[pc] == 7
          saved[args_a[pc]] = sp
          pc = pc + 1
      elsif op == 4
        return -10
      elsif op == 18
        if sp < n && (subj[sp] == args_a[pc] || subj[sp] == branches[pc])
          pc = pc + 1
          sp = sp + 1
          while ops[pc] == 18
            if sp < n && (subj[sp] == args_a[pc] || subj[sp] == branches[pc])
              pc = pc + 1
              sp = sp + 1
            else
              pc = -1
              break
          if pc < 0
            break
          if ops[pc] == 5
            pc = args_a[pc] ## i64
        else
          break
      elsif op == 27
        if sp >= n
          while ops[pc] == 27
            pc = branches[pc] ## i64
        else
          ch = subj[sp] ## i64
          while ops[pc] == 27
            tpc = args_a[pc] ## i64
            top = ops[tpc] ## i64
            if top == 1
              if ch == args_a[tpc]
                sp = sp + 1
                pc = tpc + 1
                break
            elsif ch == args_a[tpc] || ch == branches[tpc]
              sp = sp + 1
              pc = tpc + 1
              break
            pc = branches[pc] ## i64
      elsif op == 17
        if sp < n && subj[sp] >= args_a[pc] && subj[sp] <= branches[pc]
          pc = pc + 1
          sp = sp + 1
        else
          break
      elsif op == 19
        if sp < n
          want = args_a[pc] ## i64
          mask = branches[pc] ## i64
          if want < 1073741824
            if (((want >> ((subj[sp] >> 3) & 31)) & 1) != mask)
              pc = pc + 1
              sp = sp + 1
            else
              break
          elsif __regex_cat_match(want, mask, subj[sp])
            pc = pc + 1
            sp = sp + 1
          else
            break
        else
          break
      elsif op == 16 || op == 14
        if op == 16 && smode == 0 && ops[branches[pc] + 1] == 4 && ops[branches[pc]] == 7
          return -10
        e = __regex_scan_rep_end(args_a[pc], sp, subj, n, subj_ascii, ops, args_a, branches, cls_bm, classes_in) ## i64
        if op == 16
          if (lead_rep_nb == 1 && pc == 2) || (lead_rep_nb == 2 && pc == 3)
            lead_e = e
          sp = e
          pc = branches[pc] ## i64
        else
          rg_cont = branches[pc] ## i64
          rg_sp = sp
          rg_pos = e
          if ops[rg_cont] == 1
            want = args_a[rg_cont] ## i64
            if rg_pos == n
              rg_pos = rg_pos - 1
            while rg_pos >= rg_sp && subj[rg_pos] != want
              rg_pos = rg_pos - 1
            if rg_pos < rg_sp
              break
            sp = rg_pos + 1
            pc = rg_cont + 1
            rg_pos = rg_pos - 1
          else
            sp = rg_pos
            pc = rg_cont
            rg_pos = rg_pos - 1
      elsif op == 3
        if sp < n
          ch = subj[sp] ## i64
          cidx = (args_a[pc] ## i64) * 6
          if subj_ascii == 1
            if ((cls_bm[cidx + (ch >> 30)] >> ((ch >> 25) & 31)) & 1) != 0
              pc = pc + 1
              sp = sp + 1
            else
              break
          else
            cp = (ch >> 25) & 2097151
            if cp < 128
              if ((cls_bm[cidx + (cp >> 5)] >> (cp & 31)) & 1) != 0
                pc = pc + 1
                sp = sp + 1
              else
                break
            elsif (ch >= cls_bm[cidx + 4] && ch <= cls_bm[cidx + 5]) || __regex_class_match_slow(classes_in[args_a[pc]], ch)
              pc = pc + 1
              sp = sp + 1
            else
              break
        else
          break
      elsif op == 25
        want = branches[pc] ## i64
        top = want & 15
        tpc = args_a[pc] ## i64
        if tpc == pc + 3
          ch = args_a[pc + 1] ## i64
          if top == 1
            if sp < n && subj[sp] == ch
              pc = tpc
            else
              break
          elsif top == 2
            if sp >= n || subj[sp] != ch
              pc = tpc
            else
              break
          elsif top == 3
            if sp > 0 && subj[sp - 1] == ch
              pc = tpc
            else
              break
          else
            if sp == 0 || subj[sp - 1] != ch
              pc = tpc
            else
              break
        else
          ch = args_a[pc + 1] ## i64
          mask = args_a[pc + 2] ## i64
          if top == 1
            if sp + 1 < n && subj[sp] == ch && subj[sp + 1] == mask
              pc = tpc
            else
              break
          elsif top == 2
            if sp + 1 >= n || subj[sp] != ch || subj[sp + 1] != mask
              pc = tpc
            else
              break
          elsif top == 3
            if sp >= 2 && subj[sp - 2] == ch && subj[sp - 1] == mask
              pc = tpc
            else
              break
          else
            if sp < 2 || subj[sp - 2] != ch || subj[sp - 1] != mask
              pc = tpc
            else
              break
      elsif op == 2
        if sp < n && subj[sp] != args_a[pc]
          pc = pc + 1
          sp = sp + 1
        else
          break
      elsif op == 8
        if sp == 0 || subj[sp - 1] == nl
          pc = pc + 1
        else
          break
      elsif op == 9
        if sp == n || subj[sp] == nl
          pc = pc + 1
        else
          break
      elsif op == 20
        want = args_a[pc] ## i64
        if want == 1
          if sp == 0
            pc = pc + 1
          else
            break
        elsif want == 2
          if sp == n
            pc = pc + 1
          else
            break
        elsif want == 3
          if sp == n || (sp + 1 == n && subj[sp] == nl)
            pc = pc + 1
          else
            break
        elsif want == 4
          if sp == search_from
            pc = pc + 1
          else
            break
        else
          break
      elsif op == 10
        if ((sp > 0 ? (subj[sp - 1] & 2) : 0) != (sp < n ? (subj[sp] & 2) : 0))
          if args_a[pc] != 1
            break
        elsif args_a[pc] == 1
          break
        pc = pc + 1
      elsif op == 21
        slot = (args_a[pc] ## i64) * 2
        want = saved[slot] ## i64
        mask = saved[slot + 1] ## i64
        e = mask - want
        if want < 0 || mask < 0 || sp + e > n
          break
        j = 0
        while j < e && subj[sp + j] == subj[want + j]
          j = j + 1
        if j >= e
          sp = sp + e
          pc = pc + 1
        else
          break
      elsif op == 5
        pc = args_a[pc] ## i64
      else
        break
    if rg_pos < rg_sp
      break
    if ops[rg_cont] == 1
      want = args_a[rg_cont] ## i64
      while rg_pos >= rg_sp && subj[rg_pos] != want
        rg_pos = rg_pos - 1
      if rg_pos < rg_sp
        break
      sp = rg_pos + 1
      pc = rg_cont + 1
      rg_pos = rg_pos - 1
    else
      sp = rg_pos
      pc = rg_cont
      rg_pos = rg_pos - 1
  lead_e

-> __regex_run_linear2(subj_in, n_in, subj_ascii_in, start_in, smode_in, lead_after_char_in, lead_rep_nb_in, lead_e_in, ops_in, args_a_in, branches_in, cls_bm_in, classes_in, saved_in, nl_in, search_from_in)
  subj = subj_in ## i64[]
  n = n_in ## i64
  subj_ascii = subj_ascii_in ## i64
  start = start_in ## i64
  lead_after_char = lead_after_char_in ## i64
  lead_rep_nb = lead_rep_nb_in ## i64
  lead_e = lead_e_in ## i64
  ops = ops_in ## i64[]
  args_a = args_a_in ## i64[]
  branches = branches_in ## i64[]
  cls_bm = cls_bm_in ## i64[]
  saved = saved_in ## i64[]
  nl = nl_in ## i64
  search_from = search_from_in ## i64
  pc = 0 ## i64
  sp = 0 ## i64
  u_cnt = 0 ## i64
  u_s0 = 0 ## i64
  u_v0 = 0 ## i64
  u_s1 = 0 ## i64
  u_v1 = 0 ## i64
  u_s2 = 0 ## i64
  u_v2 = 0 ## i64
  u_s3 = 0 ## i64
  u_v3 = 0 ## i64
  b_cnt = 0 ## i64
  b_pc0 = 0 ## i64
  b_sp0 = 0 ## i64
  b_u0 = 0 ## i64
  b_pc1 = 0 ## i64
  b_sp1 = 0 ## i64
  b_u1 = 0 ## i64
  b_pc2 = 0 ## i64
  b_sp2 = 0 ## i64
  b_u2 = 0 ## i64
  b_pc3 = 0 ## i64
  b_sp3 = 0 ## i64
  b_u3 = 0 ## i64
  tu = 0 ## i64
  op = 0 ## i64
  mask = 0 ## i64
  tpc = 0 ## i64
  top = 0 ## i64
  e = 0 ## i64
  want = 0 ## i64
  cidx = 0 ## i64
  slot = 0 ## i64
  nop = 0 ## i64
  old = 0 ## i64
  ch = 0 ## i64
  cp = 0 ## i64
  j = 0 ## i64
  if lead_after_char >= 0
    u_s0 = 0
    u_v0 = saved[0] ## i64
    saved[0] = start
    if lead_rep_nb == 2
      u_cnt = 3
      u_s1 = 2
      u_v1 = saved[2] ## i64
      saved[2] = start
      u_s2 = 3
      u_v2 = saved[3] ## i64
      saved[3] = lead_e
      pc = 7
    else
      u_cnt = 1
      pc = 5
    sp = lead_e + 1
  else
    pc = 0
    sp = start
    u_cnt = 0
  b_cnt = 0
  while true
    op = ops[pc] ## i64
    if op == 1
      if sp < n && subj[sp] == args_a[pc]
        pc = pc + 1
        sp = sp + 1
      else
        pc = -1
    elsif op == 18
      if sp < n && (subj[sp] == args_a[pc] || subj[sp] == branches[pc])
        pc = pc + 1
        sp = sp + 1
      else
        pc = -1
    elsif op == 11
      mask = args_a[pc] ## i64
      if branches[pc] == 0
        if sp < n && (subj[sp] & mask) != 0
          pc = pc + 1
          sp = sp + 1
        else
          pc = -1
      else
        if sp < n && (subj[sp] & mask) == 0
          pc = pc + 1
          sp = sp + 1
        else
          pc = -1
    elsif op == 17
      if sp < n && subj[sp] >= args_a[pc] && subj[sp] <= branches[pc]
        pc = pc + 1
        sp = sp + 1
      else
        pc = -1
    elsif op == 19
      if sp < n && __regex_cat_match(args_a[pc], branches[pc], subj[sp])
        pc = pc + 1
        sp = sp + 1
      else
        pc = -1
    elsif op == 16
      e = __regex_scan_rep_end(args_a[pc], sp, subj, n, subj_ascii, ops, args_a, branches, cls_bm, classes_in) ## i64
      if (lead_rep_nb == 1 && pc == 2) || (lead_rep_nb == 2 && pc == 3)
        lead_e = e
      sp = e
      pc = branches[pc] ## i64
    elsif op == 7
      slot = args_a[pc] ## i64
      nop = ops[pc + 1] ## i64
      if nop == 4
        saved[slot] = sp
        return -10
      if nop == 7 && ops[pc + 2] == 4
        saved[slot] = sp
        saved[args_a[pc + 1]] = sp
        return -10
      if nop == 1 && (sp >= n || subj[sp] != args_a[pc + 1])
        pc = -1
      elsif u_cnt < 4
        old = saved[slot] ## i64
        if u_cnt == 0
          u_s0 = slot
          u_v0 = old
        elsif u_cnt == 1
          u_s1 = slot
          u_v1 = old
        elsif u_cnt == 2
          u_s2 = slot
          u_v2 = old
        else
          u_s3 = slot
          u_v3 = old
        u_cnt = u_cnt + 1
        saved[slot] = sp
        pc = pc + 1
      else
        while u_cnt > 0
          u_cnt = u_cnt - 1
          if u_cnt == 0
            saved[u_s0] = u_v0
          elsif u_cnt == 1
            saved[u_s1] = u_v1
          elsif u_cnt == 2
            saved[u_s2] = u_v2
          else
            saved[u_s3] = u_v3
        return -20
    elsif op == 6
      tpc = args_a[pc] ## i64
      top = ops[tpc] ## i64
      if (top == 1 && (sp >= n || subj[sp] != args_a[tpc])) || (top == 7 && ops[tpc + 1] == 1 && (sp >= n || subj[sp] != args_a[tpc + 1]))
        pc = branches[pc] ## i64
      elsif b_cnt < 4
        if b_cnt == 0
          b_pc0 = branches[pc] ## i64
          b_sp0 = sp
          b_u0 = u_cnt
        elsif b_cnt == 1
          b_pc1 = branches[pc] ## i64
          b_sp1 = sp
          b_u1 = u_cnt
        elsif b_cnt == 2
          b_pc2 = branches[pc] ## i64
          b_sp2 = sp
          b_u2 = u_cnt
        else
          b_pc3 = branches[pc] ## i64
          b_sp3 = sp
          b_u3 = u_cnt
        b_cnt = b_cnt + 1
        pc = tpc
      else
        while u_cnt > 0
          u_cnt = u_cnt - 1
          if u_cnt == 0
            saved[u_s0] = u_v0
          elsif u_cnt == 1
            saved[u_s1] = u_v1
          elsif u_cnt == 2
            saved[u_s2] = u_v2
          else
            saved[u_s3] = u_v3
        return -20
    elsif op == 27
      tpc = args_a[pc] ## i64
      if sp < n
        ch = subj[sp] ## i64
        top = ops[tpc] ## i64
        if top == 1
          if ch == args_a[tpc]
            sp = sp + 1
            pc = tpc + 1
          else
            pc = branches[pc] ## i64
        elsif ch == args_a[tpc] || ch == branches[tpc]
          sp = sp + 1
          pc = tpc + 1
        else
          pc = branches[pc] ## i64
      else
        pc = branches[pc] ## i64
    elsif op == 5
      pc = args_a[pc] ## i64
    elsif op == 4
      return -10
    elsif op == 21
      slot = (args_a[pc] ## i64) * 2
      want = saved[slot] ## i64
      mask = saved[slot + 1] ## i64
      if want < 0 || mask < 0 || sp + (mask - want) > n
        pc = -1
      elsif branches[pc] == 0
        j = 0
        e = mask - want
        while j < e && subj[sp + j] == subj[want + j]
          j = j + 1
        if j >= e
          sp = sp + e
          pc = pc + 1
        else
          pc = -1
      else
        e = __regex_match_backref(args_a[pc], 1, sp, saved, subj, n) ## i64
        if e >= 0
          sp = e
          pc = pc + 1
        else
          pc = -1
    elsif op == 3
      if sp < n
        ch = subj[sp] ## i64
        cidx = (args_a[pc] ## i64) * 6
        cp = (ch >> 25) & 2097151
        if cp < 128
          if ((cls_bm[cidx + (cp >> 5)] >> (cp & 31)) & 1) != 0
            pc = pc + 1
            sp = sp + 1
          else
            pc = -1
        elsif (ch >= cls_bm[cidx + 4] && ch <= cls_bm[cidx + 5]) || __regex_class_match_slow(classes_in[args_a[pc]], ch)
          pc = pc + 1
          sp = sp + 1
        else
          pc = -1
      else
        pc = -1
    elsif op == 2
      if sp < n && subj[sp] != args_a[pc]
        pc = pc + 1
        sp = sp + 1
      else
        pc = -1
    elsif op == 8
      if sp == 0 || subj[sp - 1] == nl
        pc = pc + 1
      else
        pc = -1
    elsif op == 9
      if sp == n || subj[sp] == nl
        pc = pc + 1
      else
        pc = -1
    elsif op == 20
      want = args_a[pc] ## i64
      if want == 1
        if sp == 0
          pc = pc + 1
        else
          pc = -1
      elsif want == 2
        if sp == n
          pc = pc + 1
        else
          pc = -1
      elsif want == 3
        if sp == n || (sp + 1 == n && subj[sp] == nl)
          pc = pc + 1
        else
          pc = -1
      elsif want == 4
        if sp == search_from
          pc = pc + 1
        else
          pc = -1
      else
        pc = -1
    elsif op == 10
      if ((sp > 0 ? (subj[sp - 1] & 2) : 0) != (sp < n ? (subj[sp] & 2) : 0))
        if args_a[pc] != 1
          pc = -1
        else
          pc = pc + 1
      elsif args_a[pc] == 1
        pc = -1
      else
        pc = pc + 1
    else
      pc = -1
    if pc < 0
      if b_cnt > 0
        b_cnt = b_cnt - 1
        if b_cnt == 0
          pc = b_pc0
          sp = b_sp0
          tu = b_u0
        elsif b_cnt == 1
          pc = b_pc1
          sp = b_sp1
          tu = b_u1
        elsif b_cnt == 2
          pc = b_pc2
          sp = b_sp2
          tu = b_u2
        else
          pc = b_pc3
          sp = b_sp3
          tu = b_u3
        while u_cnt > tu
          u_cnt = u_cnt - 1
          if u_cnt == 0
            saved[u_s0] = u_v0
          elsif u_cnt == 1
            saved[u_s1] = u_v1
          elsif u_cnt == 2
            saved[u_s2] = u_v2
          else
            saved[u_s3] = u_v3
      else
        while u_cnt > 0
          u_cnt = u_cnt - 1
          if u_cnt == 0
            saved[u_s0] = u_v0
          elsif u_cnt == 1
            saved[u_s1] = u_v1
          elsif u_cnt == 2
            saved[u_s2] = u_v2
          else
            saved[u_s3] = u_v3
        break
  lead_e

-> __regex_vm_run(pc_in, sp_in, saved_in, subj_in, n_in, subj_ascii_in, ops_in, args_a_in, branches_in, guard_in, cls_bm_in, classes_in, nl_in, search_from_in, ncap_in, has_backref, has_subcall, memo_in, memo_gen_in, cs_ctx_in, vm_state_in)
  subj = subj_in ## i64[]
  n = n_in ## i64
  ops = ops_in ## i64[]
  args_a = args_a_in ## i64[]
  branches = branches_in ## i64[]
  saved = saved_in ## i64[]
  vm_state = vm_state_in ## i64[]
  nl = nl_in ## i64
  pc = pc_in ## i64
  sp = sp_in ## i64
  u_cnt = 0 ## i64
  u_s0 = 0 ## i64
  u_v0 = 0 ## i64
  u_s1 = 0 ## i64
  u_v1 = 0 ## i64
  u_s2 = 0 ## i64
  u_v2 = 0 ## i64
  u_s3 = 0 ## i64
  u_v3 = 0 ## i64
  b_cnt = 0 ## i64
  b_pc0 = 0 ## i64
  b_sp0 = 0 ## i64
  b_u0 = 0 ## i64
  b_pc1 = 0 ## i64
  b_sp1 = 0 ## i64
  b_u1 = 0 ## i64
  b_pc2 = 0 ## i64
  b_sp2 = 0 ## i64
  b_u2 = 0 ## i64
  b_pc3 = 0 ## i64
  b_sp3 = 0 ## i64
  b_u3 = 0 ## i64
  tu = 0 ## i64
  res = -1 ## i64
  op = 0 ## i64
  mask = 0 ## i64
  tpc = 0 ## i64
  top = 0 ## i64
  e = 0 ## i64
  want = 0 ## i64
  cont = 0 ## i64
  pos = 0 ## i64
  r = 0 ## i64
  slot = 0 ## i64
  nop = 0 ## i64
  old = 0 ## i64
  g = 0 ## i64
  while true
    op = ops[pc] ## i64
    if op == 1
      if sp < n && subj[sp] == args_a[pc]
        pc = pc + 1
        sp = sp + 1
      else
        pc = -1
    elsif op == 18
      if sp < n && (subj[sp] == args_a[pc] || subj[sp] == branches[pc])
        pc = pc + 1
        sp = sp + 1
      else
        pc = -1
    elsif op == 11
      mask = args_a[pc] ## i64
      if branches[pc] == 0
        if sp < n && (subj[sp] & mask) != 0
          pc = pc + 1
          sp = sp + 1
        else
          pc = -1
      else
        if sp < n && (subj[sp] & mask) == 0
          pc = pc + 1
          sp = sp + 1
        else
          pc = -1
    elsif op == 2
      if sp < n && subj[sp] != args_a[pc]
        pc = pc + 1
        sp = sp + 1
      else
        pc = -1
    elsif op == 3
      if sp < n && __regex_class_match(args_a[pc], subj[sp], cls_bm_in, classes_in)
        pc = pc + 1
        sp = sp + 1
      else
        pc = -1
    elsif op == 17
      if sp < n && subj[sp] >= args_a[pc] && subj[sp] <= branches[pc]
        pc = pc + 1
        sp = sp + 1
      else
        pc = -1
    elsif op == 19
      if sp < n && __regex_cat_match(args_a[pc], branches[pc], subj[sp])
        pc = pc + 1
        sp = sp + 1
      else
        pc = -1
    elsif op == 16
      sp = __regex_scan_rep_end(args_a[pc], sp, subj, n, subj_ascii_in, ops, args_a, branches, cls_bm_in, classes_in) ## i64
      pc = branches[pc] ## i64
    elsif op == 14
      e = __regex_scan_rep_end(args_a[pc], sp, subj, n, subj_ascii_in, ops, args_a, branches, cls_bm_in, classes_in) ## i64
      cont = branches[pc] ## i64
      pos = e
      if ops[cont] == 1
        want = args_a[cont] ## i64
        if pos == n
          pos = pos - 1
        while pos >= sp
          if subj[pos] == want
            r = __regex_vm_run(cont + 1, pos + 1, saved, subj, n, subj_ascii_in, ops, args_a, branches, guard_in, cls_bm_in, classes_in, nl, search_from_in, ncap_in, has_backref, has_subcall, memo_in, memo_gen_in, cs_ctx_in, vm_state) ## i64
            if r >= 0
              return r
          pos = pos - 1
      else
        while pos >= sp
          r = __regex_vm_run(cont, pos, saved, subj, n, subj_ascii_in, ops, args_a, branches, guard_in, cls_bm_in, classes_in, nl, search_from_in, ncap_in, has_backref, has_subcall, memo_in, memo_gen_in, cs_ctx_in, vm_state) ## i64
          if r >= 0
            return r
          pos = pos - 1
      pc = -1
    elsif op == 15
      e = __regex_scan_rep_end(args_a[pc], sp, subj, n, subj_ascii_in, ops, args_a, branches, cls_bm_in, classes_in) ## i64
      cont = branches[pc] ## i64
      pos = sp
      if ops[cont] == 1
        want = args_a[cont] ## i64
        while pos <= e
          if pos < n && subj[pos] == want
            r = __regex_vm_run(cont + 1, pos + 1, saved, subj, n, subj_ascii_in, ops, args_a, branches, guard_in, cls_bm_in, classes_in, nl, search_from_in, ncap_in, has_backref, has_subcall, memo_in, memo_gen_in, cs_ctx_in, vm_state) ## i64
            if r >= 0
              return r
          pos = pos + 1
      else
        while pos <= e
          r = __regex_vm_run(cont, pos, saved, subj, n, subj_ascii_in, ops, args_a, branches, guard_in, cls_bm_in, classes_in, nl, search_from_in, ncap_in, has_backref, has_subcall, memo_in, memo_gen_in, cs_ctx_in, vm_state) ## i64
          if r >= 0
            return r
          pos = pos + 1
      pc = -1
    elsif op == 4
      return sp
    elsif op == 26
      if args_a[pc] == 0 || sp == vm_state[0]
        return sp
      pc = -1
    elsif op == 25
      if (ncap_in ## i64) == 1
        want = branches[pc] ## i64
        top = want & 15
        if top == 1
          if __regex_vm_run(pc + 1, sp, saved, subj, n, subj_ascii_in, ops, args_a, branches, guard_in, cls_bm_in, classes_in, nl, search_from_in, ncap_in, has_backref, has_subcall, memo_in, memo_gen_in, cs_ctx_in, vm_state) >= 0
            pc = args_a[pc] ## i64
          else
            pc = -1
        elsif top == 2
          if __regex_vm_run(pc + 1, sp, saved, subj, n, subj_ascii_in, ops, args_a, branches, guard_in, cls_bm_in, classes_in, nl, search_from_in, ncap_in, has_backref, has_subcall, memo_in, memo_gen_in, cs_ctx_in, vm_state) >= 0
            pc = -1
          else
            pc = args_a[pc] ## i64
        elsif top == 5
          e = __regex_vm_run(pc + 1, sp, saved, subj, n, subj_ascii_in, ops, args_a, branches, guard_in, cls_bm_in, classes_in, nl, search_from_in, ncap_in, has_backref, has_subcall, memo_in, memo_gen_in, cs_ctx_in, vm_state) ## i64
          if e >= 0
            sp = e
            pc = args_a[pc] ## i64
          else
            pc = -1
        else
          if __regex_eval_lookbehind(pc, sp, saved, subj, n, subj_ascii_in, ops, args_a, branches, guard_in, cls_bm_in, classes_in, nl, search_from_in, ncap_in, has_backref, has_subcall, memo_in, memo_gen_in, cs_ctx_in, vm_state)
            pc = args_a[pc] ## i64
          else
            pc = -1
      else
        r = __regex_run_assert_cap(pc, sp, saved, subj, n, subj_ascii_in, ops, args_a, branches, guard_in, cls_bm_in, classes_in, nl, search_from_in, ncap_in, has_backref, has_subcall, memo_in, memo_gen_in, cs_ctx_in, vm_state) ## i64
        if r >= 0
          return r
        pc = -1
    elsif op == 27
      tpc = args_a[pc] ## i64
      if sp < n
        want = subj[sp] ## i64
        top = ops[tpc] ## i64
        if top == 1
          if want == args_a[tpc]
            sp = sp + 1
            pc = tpc + 1
          else
            pc = branches[pc] ## i64
        elsif want == args_a[tpc] || want == branches[tpc]
          sp = sp + 1
          pc = tpc + 1
        else
          pc = branches[pc] ## i64
      else
        pc = branches[pc] ## i64
    elsif op == 5
      pc = args_a[pc] ## i64
    elsif op == 6
      tpc = args_a[pc] ## i64
      top = ops[tpc] ## i64
      if (top == 1 && (sp >= n || subj[sp] != args_a[tpc])) || (top == 7 && ops[tpc + 1] == 1 && (sp >= n || subj[sp] != args_a[tpc + 1]))
        pc = branches[pc] ## i64
      elsif !has_subcall && b_cnt < 4
        if b_cnt == 0
          b_pc0 = branches[pc] ## i64
          b_sp0 = sp
          b_u0 = u_cnt
        elsif b_cnt == 1
          b_pc1 = branches[pc] ## i64
          b_sp1 = sp
          b_u1 = u_cnt
        elsif b_cnt == 2
          b_pc2 = branches[pc] ## i64
          b_sp2 = sp
          b_u2 = u_cnt
        else
          b_pc3 = branches[pc] ## i64
          b_sp3 = sp
          b_u3 = u_cnt
        b_cnt = b_cnt + 1
        pc = tpc
      else
        old = vm_state[1] ## i64
        r = __regex_vm_run(tpc, sp, saved, subj, n, subj_ascii_in, ops, args_a, branches, guard_in, cls_bm_in, classes_in, nl, search_from_in, ncap_in, has_backref, has_subcall, memo_in, memo_gen_in, cs_ctx_in, vm_state) ## i64
        if r >= 0
          return r
        vm_state[1] = old
        pc = branches[pc] ## i64
    elsif op == 7
      slot = args_a[pc] ## i64
      nop = ops[pc + 1] ## i64
      if nop == 4
        saved[slot] = sp
        return sp
      if nop == 7 && ops[pc + 2] == 4
        saved[slot] = sp
        saved[args_a[pc + 1]] = sp
        return sp
      if nop == 1 && (sp >= n || subj[sp] != args_a[pc + 1])
        pc = -1
      else
        old = saved[slot] ## i64
        if u_cnt < 4
          if u_cnt == 0
            u_s0 = slot
            u_v0 = old
          elsif u_cnt == 1
            u_s1 = slot
            u_v1 = old
          elsif u_cnt == 2
            u_s2 = slot
            u_v2 = old
          else
            u_s3 = slot
            u_v3 = old
          u_cnt = u_cnt + 1
          saved[slot] = sp
          pc = pc + 1
        else
          saved[slot] = sp
          r = __regex_vm_run(pc + 1, sp, saved, subj, n, subj_ascii_in, ops, args_a, branches, guard_in, cls_bm_in, classes_in, nl, search_from_in, ncap_in, has_backref, has_subcall, memo_in, memo_gen_in, cs_ctx_in, vm_state) ## i64
          if r >= 0
            return r
          saved[slot] = old
          pc = -1
    elsif op == 12
      g = args_a[pc] ## i64
      guard = guard_in ## i64[]
      if !has_backref && !has_subcall
        memo = memo_in ## i64[]
        midx = g * (n + 1) + sp
        if memo[midx] == (memo_gen_in ## i64)
          pc = -1
        else
          memo[midx] = memo_gen_in ## i64
          old = guard[g] ## i64
          guard[g] = sp
          r = __regex_vm_run(pc + 1, sp, saved, subj, n, subj_ascii_in, ops, args_a, branches, guard_in, cls_bm_in, classes_in, nl, search_from_in, ncap_in, has_backref, has_subcall, memo_in, memo_gen_in, cs_ctx_in, vm_state) ## i64
          if r >= 0
            return r
          guard[g] = old
          pc = -1
      else
        old = guard[g] ## i64
        guard[g] = sp
        r = __regex_vm_run(pc + 1, sp, saved, subj, n, subj_ascii_in, ops, args_a, branches, guard_in, cls_bm_in, classes_in, nl, search_from_in, ncap_in, has_backref, has_subcall, memo_in, memo_gen_in, cs_ctx_in, vm_state) ## i64
        if r >= 0
          return r
        guard[g] = old
        pc = -1
    elsif op == 13
      guard = guard_in ## i64[]
      g = args_a[pc] ## i64
      if sp == guard[g]
        pc = -1
      else
        pc = pc + 1
    elsif op == 8
      if sp == 0 || subj[sp - 1] == nl
        pc = pc + 1
      else
        pc = -1
    elsif op == 9
      if sp == n || subj[sp] == nl
        pc = pc + 1
      else
        pc = -1
    elsif op == 20
      want = args_a[pc] ## i64
      if want == 1
        if sp == 0
          pc = pc + 1
        else
          pc = -1
      elsif want == 2
        if sp == n
          pc = pc + 1
        else
          pc = -1
      elsif want == 3
        if sp == n || (sp + 1 == n && subj[sp] == nl)
          pc = pc + 1
        else
          pc = -1
      elsif want == 4
        if sp == (search_from_in ## i64)
          pc = pc + 1
        else
          pc = -1
      else
        pc = -1
    elsif op == 21
      g = args_a[pc] ## i64
      want = branches[pc] ## i64
      e = __regex_match_backref(g, want, sp, saved, subj, n) ## i64
      if e >= 0
        sp = e
        pc = pc + 1
      else
        pc = -1
    elsif op == 22
      tpc = args_a[pc] ## i64
      g = branches[pc] ## i64
      cs_ctx = cs_ctx_in ## Array
      cs_ret = cs_ctx[0] ## i64[]
      cs_par = cs_ctx[1] ## i64[]
      cs_grp = cs_ctx[2] ## i64[]
      cs_ost = cs_ctx[3] ## i64[]
      cs_ret.push(pc + 1)
      cs_par.push(vm_state[1])
      cs_grp.push(g)
      if g > 0 && saved[g * 2] >= 0 && saved[g * 2 + 1] < 0
        cs_ost.push(saved[g * 2])
      else
        cs_ost.push(-1)
      cs_ctx[0] = cs_ret
      cs_ctx[1] = cs_par
      cs_ctx[2] = cs_grp
      cs_ctx[3] = cs_ost
      vm_state[1] = cs_ret.size() - 1
      pc = tpc
    elsif op == 23
      top = vm_state[1] ## i64
      if top < 0
        return sp
      cs_ctx = cs_ctx_in ## Array
      cs_ret = cs_ctx[0] ## i64[]
      cs_par = cs_ctx[1] ## i64[]
      cs_grp = cs_ctx[2] ## i64[]
      cs_ost = cs_ctx[3] ## i64[]
      g = cs_grp[top] ## i64
      want = cs_ost[top] ## i64
      if g > 0 && want >= 0
        old = saved[g * 2] ## i64
        e = saved[g * 2 + 1] ## i64
        saved[g * 2] = want
        saved[g * 2 + 1] = -1
        vm_state[1] = cs_par[top]
        r = __regex_vm_run(cs_ret[top], sp, saved, subj, n, subj_ascii_in, ops, args_a, branches, guard_in, cls_bm_in, classes_in, nl, search_from_in, ncap_in, has_backref, has_subcall, memo_in, memo_gen_in, cs_ctx_in, vm_state) ## i64
        if r >= 0
          return r
        saved[g * 2] = old
        saved[g * 2 + 1] = e
        vm_state[1] = top
        pc = -1
      else
        vm_state[1] = cs_par[top]
        pc = cs_ret[top] ## i64
    elsif op == 24
      want = args_a[pc] ## i64
      e = __regex_match_special(want, sp, subj, n) ## i64
      if e >= 0
        sp = e
        pc = pc + 1
      else
        pc = -1
    elsif op == 10
      if ((sp > 0 && (subj[sp - 1] & 2) != 0) != (sp < n && (subj[sp] & 2) != 0))
        if args_a[pc] != 1
          pc = -1
        else
          pc = pc + 1
      elsif args_a[pc] == 1
        pc = -1
      else
        pc = pc + 1
    else
      pc = -1
    if pc < 0
      if b_cnt > 0
        b_cnt = b_cnt - 1
        if b_cnt == 0
          pc = b_pc0
          sp = b_sp0
          tu = b_u0
        elsif b_cnt == 1
          pc = b_pc1
          sp = b_sp1
          tu = b_u1
        elsif b_cnt == 2
          pc = b_pc2
          sp = b_sp2
          tu = b_u2
        else
          pc = b_pc3
          sp = b_sp3
          tu = b_u3
        while u_cnt > tu
          u_cnt = u_cnt - 1
          if u_cnt == 0
            saved[u_s0] = u_v0
          elsif u_cnt == 1
            saved[u_s1] = u_v1
          elsif u_cnt == 2
            saved[u_s2] = u_v2
          else
            saved[u_s3] = u_v3
      else
        break
  if u_cnt >= 4
    saved[u_s3] = u_v3
  if u_cnt >= 3
    saved[u_s2] = u_v2
  if u_cnt >= 2
    saved[u_s1] = u_v1
  if u_cnt >= 1
    saved[u_s0] = u_v0
  res

-> __regex_eval_lookbehind(pc_in, sp_in, saved_in, subj_in, n_in, subj_ascii_in, ops_in, args_a_in, branches_in, guard_in, cls_bm_in, classes_in, nl_in, search_from_in, ncap_in, has_backref, has_subcall, memo_in, memo_gen_in, cs_ctx_in, vm_state_in)
  pc = pc_in ## i64
  sp = sp_in ## i64
  branches = branches_in ## i64[]
  vm_state = vm_state_in ## i64[]
  enc = branches[pc] ## i64
  kind = enc & 15
  min_l = enc >> 20
  max_e = (enc >> 4) & 65535
  hi_s = sp - min_l
  if hi_s < 0
    return kind == 4
  lo_s = max_e == 65535 ? 0 : (sp - max_e)
  if lo_s < 0
    lo_s = 0
  old_t = vm_state[0] ## i64
  vm_state[0] = sp
  if kind == 3
    s = lo_s
    while s <= hi_s
      if __regex_vm_run(pc + 1, s, saved_in, subj_in, n_in, subj_ascii_in, ops_in, args_a_in, branches_in, guard_in, cls_bm_in, classes_in, nl_in, search_from_in, ncap_in, has_backref, has_subcall, memo_in, memo_gen_in, cs_ctx_in, vm_state) == sp
        vm_state[0] = old_t
        return true
      s = s + 1
    vm_state[0] = old_t
    return false
  s = hi_s
  while s >= lo_s
    if __regex_vm_run(pc + 1, s, saved_in, subj_in, n_in, subj_ascii_in, ops_in, args_a_in, branches_in, guard_in, cls_bm_in, classes_in, nl_in, search_from_in, ncap_in, has_backref, has_subcall, memo_in, memo_gen_in, cs_ctx_in, vm_state) == sp
      vm_state[0] = old_t
      return false
    s = s - 1
  vm_state[0] = old_t
  true

-> __regex_run_assert_cap(pc_in, sp_in, saved_in, subj_in, n_in, subj_ascii_in, ops_in, args_a_in, branches_in, guard_in, cls_bm_in, classes_in, nl_in, search_from_in, ncap_in, has_backref, has_subcall, memo_in, memo_gen_in, cs_ctx_in, vm_state_in)
  pc = pc_in ## i64
  sp = sp_in ## i64
  saved = saved_in ## i64[]
  args_a = args_a_in ## i64[]
  branches = branches_in ## i64[]
  after_pc = args_a[pc] ## i64
  enc = branches[pc] ## i64
  kind = enc & 15
  sn = saved.size() ## i64
  snap = i64[sn]
  si = 0 ## i64
  while si < sn
    snap[si] = saved[si]
    si = si + 1
  if kind == 1
    if __regex_vm_run(pc + 1, sp, saved, subj_in, n_in, subj_ascii_in, ops_in, args_a_in, branches_in, guard_in, cls_bm_in, classes_in, nl_in, search_from_in, ncap_in, has_backref, has_subcall, memo_in, memo_gen_in, cs_ctx_in, vm_state_in) >= 0
      r = __regex_vm_run(after_pc, sp, saved, subj_in, n_in, subj_ascii_in, ops_in, args_a_in, branches_in, guard_in, cls_bm_in, classes_in, nl_in, search_from_in, ncap_in, has_backref, has_subcall, memo_in, memo_gen_in, cs_ctx_in, vm_state_in) ## i64
      if r >= 0
        return r
    i = 0 ## i64
    while i < sn
      saved[i] = snap[i]
      i = i + 1
    return -1
  if kind == 2
    if __regex_vm_run(pc + 1, sp, saved, subj_in, n_in, subj_ascii_in, ops_in, args_a_in, branches_in, guard_in, cls_bm_in, classes_in, nl_in, search_from_in, ncap_in, has_backref, has_subcall, memo_in, memo_gen_in, cs_ctx_in, vm_state_in) >= 0
      i = 0 ## i64
      while i < sn
        saved[i] = snap[i]
        i = i + 1
      return -1
    return __regex_vm_run(after_pc, sp, saved, subj_in, n_in, subj_ascii_in, ops_in, args_a_in, branches_in, guard_in, cls_bm_in, classes_in, nl_in, search_from_in, ncap_in, has_backref, has_subcall, memo_in, memo_gen_in, cs_ctx_in, vm_state_in)
  if kind == 5
    e = __regex_vm_run(pc + 1, sp, saved, subj_in, n_in, subj_ascii_in, ops_in, args_a_in, branches_in, guard_in, cls_bm_in, classes_in, nl_in, search_from_in, ncap_in, has_backref, has_subcall, memo_in, memo_gen_in, cs_ctx_in, vm_state_in) ## i64
    if e >= 0
      r = __regex_vm_run(after_pc, e, saved, subj_in, n_in, subj_ascii_in, ops_in, args_a_in, branches_in, guard_in, cls_bm_in, classes_in, nl_in, search_from_in, ncap_in, has_backref, has_subcall, memo_in, memo_gen_in, cs_ctx_in, vm_state_in) ## i64
      if r >= 0
        return r
    i = 0 ## i64
    while i < sn
      saved[i] = snap[i]
      i = i + 1
    return -1
  if __regex_eval_lookbehind(pc, sp, saved, subj_in, n_in, subj_ascii_in, ops_in, args_a_in, branches_in, guard_in, cls_bm_in, classes_in, nl_in, search_from_in, ncap_in, has_backref, has_subcall, memo_in, memo_gen_in, cs_ctx_in, vm_state_in)
    if kind == 4
      i = 0 ## i64
      while i < sn
        saved[i] = snap[i]
        i = i + 1
    r = __regex_vm_run(after_pc, sp, saved, subj_in, n_in, subj_ascii_in, ops_in, args_a_in, branches_in, guard_in, cls_bm_in, classes_in, nl_in, search_from_in, ncap_in, has_backref, has_subcall, memo_in, memo_gen_in, cs_ctx_in, vm_state_in) ## i64
    if r >= 0
      return r
  i = 0 ## i64
  while i < sn
    saved[i] = snap[i]
    i = i + 1
  -1

