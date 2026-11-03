# Independent ten-square rectangular surface fixture. No competition models.
# Each row gives neighbor, transported orientation and edge for R,L,U,D.
-> box_net_fixture_geometry
  [
    [8,3,0,6,1,1,4,0,2,2,2,3],
    [7,1,5,9,3,4,5,2,6,3,0,7],
    [6,0,9,8,0,8,3,0,10,0,2,3],
    [7,0,12,9,0,11,1,0,7,2,0,10],
    [8,0,13,6,0,14,5,0,15,0,0,2],
    [9,0,16,7,0,17,1,2,6,4,0,15],
    [4,0,14,2,0,9,7,0,18,0,3,1],
    [5,0,17,3,0,12,1,3,5,6,0,18],
    [2,0,8,4,0,13,9,0,19,0,1,0],
    [3,0,11,5,0,16,1,1,4,8,0,19]
  ]

-> box_net_fixture_flat(cs, rename)
  total = 0
  cs.each -> (c) total += c.size
  lits = i64[total]
  offs = i64[cs.size]
  lens = i64[cs.size]
  at = 0
  ci = 0
  cs.each -> (c)
    offs[ci] = at
    lens[ci] = c.size
    c.each -> (v)
      value = v
      if rename
        magnitude = ((v < 0 ? -v : v)*7) % 461
        value = v < 0 ? -magnitude : magnitude
      lits[at] = value
      at += 1
    ci += 1
  {"nvars": 460, "flat_ncl": cs.size, "flat_nlits": total,
   "flat_lits": lits, "flat_offs": offs, "flat_lens": lens}

-> box_net_fixture_exact(cs, row)
  cs.push(row)
  a = 0
  while a < row.size
    b = 0
    while b < a
      cs.push([-row[a],-row[b]])
      b += 1
    a += 1

-> box_net_fixture_clauses
  base = box_net_fixture_geometry
  turns = [[0,1,2,3],[3,2,0,1],[1,0,3,2],[2,3,1,0]]
  quads = [[9,10,12,18],[8,10,11,19],[14,15,17,18],[13,15,16,19]]
  corners = [[5,7,12],[5,6,17],[4,6,16],[4,7,11],[0,2,13],[0,3,8],[1,3,9],[1,2,14]]
  cs = []
  b = 0
  while b < 2
    i = 0
    while i < 10
      row = []
      r = 0
      while r < 4
        row.push(b*60+21+4*i+r)
        r += 1
      box_net_fixture_exact(cs,row)
      i += 1
    i = 0
    while i < 10
      r = 0
      while r < 4
        d = 0
        while d < 4
          at = 3*turns[r][d]
          ni = base[i][at]
          nr = (base[i][at+1]+r) % 4
          edge = base[i][at+2]
          cs.push([-(b*60+21+4*i+r),b*60+1+edge,b*60+21+4*ni+nr])
          d += 1
        r += 1
      i += 1
    quads.each -> (q)
      neg = 0
      while neg < 4
        row = []
        k = 0
        while k < 4
          v = b*60+1+q[k]
          row.push(k == neg ? -v : v)
          k += 1
        cs.push(row)
        neg += 1
    corners.each -> (q) cs.push([b*60+1+q[0],b*60+1+q[1],b*60+1+q[2]])
    b += 1
  j = 0
  while j < 10
    row = []
    i = 0
    while i < 10
      row.push(121+10*j+i)
      i += 1
    box_net_fixture_exact(cs,row)
    j += 1
  i = 0
  while i < 10
    row = []
    j = 0
    while j < 10
      row.push(121+10*j+i)
      j += 1
    box_net_fixture_exact(cs,row)
    i += 1
  j = 0
  while j < 10
    i = 0
    while i < 10
      r = 0
      while r < 4
        d = 0
        while d < 4
          cs.push([-(121+10*j+i),-(81+4*j+(d+r)%4),-(21+4*i+d),221+4*i+r])
          d += 1
        d = 0
        while d < 4
          a = 3*d
          b = 3*turns[r][d]
          ni = base[i][a]
          nj = base[j][b]
          e0 = 1+base[i][a+2]
          e1 = 61+base[j][b+2]
          rv = 221+4*i+r
          mv = 121+10*j+i
          cs.push([-rv,-mv,e0,121+10*nj+ni])
          cs.push([-rv,-mv,e0,-e1])
          cs.push([-rv,-mv,-e0,e1])
          d += 1
        r += 1
      i += 1
    j += 1
  cs.push([21])
  cs.push([81])
  cs.push([121])
  cs.push([132])
  cs
