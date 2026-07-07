"""Bucketed rectangular (n,m,p) energy-walk searcher generator.

Same walk policy as rect_gen.py (pressure-gated flips, cycling threshold,
periodic structured-plus, band reset, improvement dumps) but every linear
scan is replaced by hash-chain lookups:

  - terms live in STABLE slots (mask regions of st[] indexed by slot;
    free-list reuse); LIVE region is the dense list of occupied slots
    (uniform random pick); POS[slot] -> dense index for O(1) swap-remove
  - three doubly-linked hash chains key slots by u-, v-, w-mask; heads
    store slot+1 (0 = empty) so the zero-initialized array is a valid table
  - partner search   : walk the axis chain of the picked mask      O(chain)
  - dup check        : walk the u-chain, compare all three masks   O(chain)
  - pressure         : u-chain terms matching exactly one of v/w, plus
                       v-chain terms matching w but not u          O(chain)

Profiled motivation: at rank 212 the linear walker spends ~97% of its time
in these scans (partner ring-scan 73%, xor_insert+pressure 24%).

ALL mutable search state lives in ONE i64 array `st`, passed as a param to
every fn. Load-bearing, not style: global typed-array STORES from inside
fns re-box the value (wide masks >=2^47 land as bigint pointer bits —
found 2026-07-02), while param-array stores take the checked raw path.
Also honored: no array-typed locals; no global-scalar writes from fns
(shadowing); no fn-internal `break` (sentinel exits); array-read args
hoisted to `## i64` locals before calls. Region offsets are baked here.

Usage: python3 bucket_gen.py <n> <m> <p> <recv> [seed] [cap] [thr] [thrper] [plusper]
"""


def gen(n, m, p, recv, arr=200, cap=14000000000, seed=None, thr=6, thrper=300000, plusper=2000, band=10, adaptive_esc=None, stopat=None, randstart=False, z1max=4, z1q=100000000, workq=3000000000, wstep=10, wq=500000000, thr0=10, thrbump=2, rsmax=4, world_record=None, tiegap=2000, tiemax=500, record_bandq=None, runtime_seed=False,
        worker=False):
    thrspan = thr + 1
    AB, BB, CB = n*m, m*p, n*p
    MODA, MODB = 1 << AB, 1 << BB
    maxbits = max(AB, BB, CB) + 1
    seed_lines = None
    if seed is not None:
        seed_lines = [ln for ln in open(seed).read().splitlines()
                      if ln.startswith(("us[", "vs[", "ws["))]
        seed_rank = len(seed_lines) // 3
        arr = max(arr, seed_rank + 80)
    else:
        seed_rank = n * m * p
        arr = max(arr, seed_rank + 80)
    TS = 1
    while TS < 8 * arr + 8:
        TS *= 2

    off = {}
    cur = 0
    for name, size in [("P2", maxbits), ("US", arr), ("VS", arr), ("WS", arr),
                       ("BUS", arr), ("BVS", arr), ("BWS", arr),
                       ("LIVE", arr), ("POS", arr), ("FL", arr), ("FLT", 2),
                       ("HU", TS), ("HV", TS), ("HW", TS),
                       ("NXU", arr), ("PVU", arr), ("NXV", arr), ("PVV", arr),
                       ("NXW", arr), ("PVW", arr), ("IDL", arr),
                       ("SU", arr + 8), ("SV", arr + 8), ("SW", arr + 8),
                       # STV: per-walker schedule state, persisted across rounds so
                       # walk_worker(st, steps) can be called repeatedly (thread
                       # worker mode). Slots: 0 rank, 1 best_rank, 2 rng, 3 aband,
                       # 4 wthr, 5 wraps, 6 mv, 7 nextesc, 8 cyclesv, 9 cycled.
                       ("STV", 12)]:
        off[name] = cur
        cur += size
    TOT = cur
    O = off

    if runtime_seed:
        # Read the startup scheme from a bare-dump file (rank\nu v w\n...) named
        # by av0[4], parse and install it — same pattern the GPU relay uses. Lets
        # the orchestrator seed each walker at (re)launch time: naive on the first
        # launch, a random fleet-best after a CYCLEOUT. All string parsing happens
        # here at startup, never in the hot move loop.
        seed_block = f"""sav = argv()
rspath = sav[4]
rscontent = read_file(rspath)
rslines = rscontent.split("\\n")
rsrank = rslines[0].to_i() ## i64
rsi = 0 ## i64
while rsi < rsrank
  rsp = rslines[rsi + 1].split(" ")
  rsu = rsp[0].to_i() ## i64
  rsv = rsp[1].to_i() ## i64
  rsw = rsp[2].to_i() ## i64
  rank = ins_term(st, rsu, rsv, rsw, rank)
  rsi += 1"""
    elif seed_lines is not None:
        seed_terms = "\n".join(
            ln.replace("us[", f"st[{O['SU']} + ").replace("vs[", f"st[{O['SV']} + ")
              .replace("ws[", f"st[{O['SW']} + ")
            for ln in seed_lines)
        seed_block = f"""{seed_terms}
bi = 0
while bi < {seed_rank}
  tu = st[{O['SU']} + bi] ## i64
  tv = st[{O['SV']} + bi] ## i64
  tw = st[{O['SW']} + bi] ## i64
  rank = ins_term(st, tu, tv, tw, rank)
  bi += 1"""
    else:
        seed_block = f"""ni = 0
while ni < {n}
  nj = 0
  while nj < {m}
    nk = 0
    while nk < {p}
      tu = st[{O['P2']} + ni * {m} + nj] ## i64
      tv = st[{O['P2']} + nj * {p} + nk] ## i64
      tw = st[{O['P2']} + ni * {p} + nk] ## i64
      rank = ins_term(st, tu, tv, tw, rank)
      nk += 1
    nj += 1
  ni += 1"""

    esc_block = ""
    impreset = ""
    cycles_read = ""   # cal2zone2: read sawtooth-cycles-before-CYCLEOUT from av0[5]
    if adaptive_esc == "wcal2":
        # start 1-4 @100M; work 5..wthr @3B; wander @+10/500M; wrap>60 -> bstart.
        # 2 wraps -> fresh RNG + FULL reset-to-seed (naive) incl. best arrays.
        # calibration: every descent sets wthr = max(wthr, band+2).
        restart_naive = f"""        rwx = 0 ## i64
        while rank > 0
          rsl = st[{O['LIVE']} + rank - 1] ## i64
          rcu = st[{O['US']} + rsl] ## i64
          rcv = st[{O['VS']} + rsl] ## i64
          rcw = st[{O['WS']} + rsl] ## i64
          rank = ins_term(st, rcu, rcv, rcw, rank)
        rni = 0
        while rni < {n}
          rnj = 0
          while rnj < {m}
            rnk = 0
            while rnk < {p}
              rtu = st[{O['P2']} + rni * {m} + rnj] ## i64
              rtv = st[{O['P2']} + rnj * {p} + rnk] ## i64
              rtw = st[{O['P2']} + rni * {p} + rnk] ## i64
              rank = ins_term(st, rtu, rtv, rtw, rank)
              rnk += 1
            rnj += 1
          rni += 1
        best_rank = rank
        rci = 0
        while rci < rank
          rsl = st[{O['LIVE']} + rci] ## i64
          st[{O['BUS']} + rci] = st[{O['US']} + rsl]
          st[{O['BVS']} + rci] = st[{O['VS']} + rsl]
          st[{O['BWS']} + rci] = st[{O['WS']} + rsl]
          rci += 1"""
        esc_block = f"""  if mv >= nextesc
    nb = aband + 1 ## i64
    if aband > wthr
      nb = aband + {wstep}
    if nb > 60
      nb = bstart
      wraps = wraps + 1
      if wraps >= 2
        wraps = 0
        rng = ((rng ^ (mv & 2147483647)) * 1103515245 + 54321) & 2147483647
        rng = (rng * 1103515245 + 12345) & 2147483647
        rng = (rng * 1103515245 + 12345) & 2147483647
{restart_naive}
        << "RESTART mv=" + mv.to_s()
        flush()
    aband = nb
    q = {z1q} ## i64
    if aband > {z1max}
      q = {workq}
    if aband > wthr
      q = {wq}
    nextesc = mv + q
    << "BAND band=" + aband.to_s() + " rank=" + rank.to_s() + " mv=" + mv.to_s()
    flush()"""
        impreset = f"""    if aband + {thrbump} > wthr
      wthr = aband + {thrbump}
      if wthr > 58
        wthr = 58
      << "WTHR thr=" + wthr.to_s() + " band=" + aband.to_s() + " mv=" + mv.to_s()
      flush()
    if aband != bstart
      aband = bstart
      << "BAND band=" + aband.to_s() + " rank=" + rank.to_s() + " mv=" + mv.to_s()
      flush()
    nextesc = mv + {z1q}"""
    elif adaptive_esc == "wcal":
        # start zone 1-4: +1/100M; work zone 5..wthr: +1/3B; wander zone: +10/500M.
        # wrap past 60 -> start band (count wraps; 2 wraps -> fresh RNG).
        # self-calibrating ceiling: crossing within 2 of wthr raises wthr by 2.
        esc_block = """  if mv >= nextesc
    nb = aband + 1 ## i64
    if aband > wthr
      nb = aband + 10
    if nb > 60
      nb = bstart
      wraps = wraps + 1
      if wraps >= 2
        wraps = 0
        rng = ((rng ^ (mv & 2147483647)) * 1103515245 + 54321) & 2147483647
        rng = (rng * 1103515245 + 12345) & 2147483647
        rng = (rng * 1103515245 + 12345) & 2147483647
        << "RESEED mv=" + mv.to_s()
        flush()
    aband = nb
    q = 100000000 ## i64
    if aband >= 5
      q = 3000000000
    if aband > wthr
      q = 500000000
    nextesc = mv + q
    << "BAND band=" + aband.to_s() + " rank=" + rank.to_s() + " mv=" + mv.to_s()
    flush()"""
        impreset = """    if aband >= wthr - 2
      wthr = wthr + 2
      if wthr > 58
        wthr = 58
      << "WTHR thr=" + wthr.to_s() + " band=" + aband.to_s() + " mv=" + mv.to_s()
      flush()
    if aband != bstart
      aband = bstart
      << "BAND band=" + aband.to_s() + " rank=" + rank.to_s() + " mv=" + mv.to_s()
      flush()
    nextesc = mv + 100000000"""
    elif adaptive_esc == "cal2zone":
        # Erik's preview spec: work zone (band <= wthr, starts at 7) -> +1
        # band / 2B moves; wander zone (band > wthr) -> +12 bands / 500M moves;
        # past 60 -> sawtooth back to bstart. wthr self-calibrates UP-ONLY: any
        # descent sets wthr = max(wthr, descent_band + 1). Any descent also
        # resets band to bstart. 2 full cycles (hit-60-and-wrap, NOT a
        # descent-triggered reset) with no descent -> fresh RNG; if this run
        # started from naive (no external seed file), also hard-reset the
        # whole working scheme back to naive on that same trigger.
        restart_naive = f"""        rwx = 0 ## i64
        while rank > 0
          rsl = st[{O['LIVE']} + rank - 1] ## i64
          rcu = st[{O['US']} + rsl] ## i64
          rcv = st[{O['VS']} + rsl] ## i64
          rcw = st[{O['WS']} + rsl] ## i64
          rank = ins_term(st, rcu, rcv, rcw, rank)
        rni = 0
        while rni < {n}
          rnj = 0
          while rnj < {m}
            rnk = 0
            while rnk < {p}
              rtu = st[{O['P2']} + rni * {m} + rnj] ## i64
              rtv = st[{O['P2']} + rnj * {p} + rnk] ## i64
              rtw = st[{O['P2']} + rni * {p} + rnk] ## i64
              rank = ins_term(st, rtu, rtv, rtw, rank)
              rnk += 1
            rnj += 1
          rni += 1
        best_rank = rank
        rci = 0
        while rci < rank
          rsl = st[{O['LIVE']} + rci] ## i64
          st[{O['BUS']} + rci] = st[{O['US']} + rsl]
          st[{O['BVS']} + rci] = st[{O['VS']} + rsl]
          st[{O['BWS']} + rci] = st[{O['WS']} + rsl]
          rci += 1"""
        cycle_reset = restart_naive if seed is None else ""
        # Record-mode budget: while the LIVE scheme sits AT the world record
        # (rank <= world_record), dwell record_bandq moves per band before
        # escalating (vs the 2B/500M zone quanta) — give a walker parked on the
        # frontier a much longer look at each band. Only injected when both a
        # world_record and a record_bandq are supplied.
        recordq_block = ""
        if world_record is not None and record_bandq is not None:
            recordq_block = f"""
    if rank <= {world_record}
      q = {record_bandq}"""
        esc_block = f"""  if mv >= nextesc
    nb = aband + 1 ## i64
    if aband > wthr
      nb = aband + 12
    if nb > 60
      nb = bstart
      wraps = wraps + 1
      if wraps >= 2
        wraps = 0
        rng = ((rng ^ (mv & 2147483647)) * 1103515245 + 54321) & 2147483647
        rng = (rng * 1103515245 + 12345) & 2147483647
        rng = (rng * 1103515245 + 12345) & 2147483647
{cycle_reset}
        << "FRESHRNG mv=" + mv.to_s()
        flush()
    aband = nb
    q = 2000000000 ## i64
    if aband > wthr
      q = 500000000{recordq_block}
    nextesc = mv + q
    << "BAND band=" + aband.to_s() + " rank=" + rank.to_s() + " mv=" + mv.to_s()
    flush()"""
        impreset = f"""    if aband + 1 > wthr
      wthr = aband + 1
      << "WTHR thr=" + wthr.to_s() + " band=" + aband.to_s() + " mv=" + mv.to_s()
      flush()
    if aband != bstart
      aband = bstart
      << "BAND band=" + aband.to_s() + " rank=" + rank.to_s() + " mv=" + mv.to_s()
      flush()
    nextesc = mv + 2000000000"""
    elif adaptive_esc == "cal2zone2":
        # cal2zone variant (2026-07-06): work zone (band <= wthr) +1 band / 2.5B
        # moves; wander zone (band > wthr) +12 / 500M; sawtooth wrap at band 60.
        # FOUR full cycles with no descent -> the walker prints CYCLEOUT and EXITS
        # (mv = cap); the orchestrator reseeds it from the fleet's current best
        # (random among ties) and relaunches. wthr rises by ONE whenever a descent
        # lands within one band of the threshold. Record budget (record_bandq):
        # dwell that many moves per band while rank <= world_record.
        recordq_block = ""
        if world_record is not None and record_bandq is not None:
            recordq_block = f"""
    if rank <= {world_record}
      q = {record_bandq}"""
        # sawtooth cycles before a CYCLEOUT reseed: runtime-tunable via av0[5]
        # (default 4 when not supplied, so existing 5-arg callers are unchanged).
        cycles_read = """cyclesv = 4 ## i64
if av0.size() > 5
  cyclesv = av0[5].to_i()
<< "CYCLES " + cyclesv.to_s()
flush()"""
        esc_block = f"""  if mv >= nextesc
    nb = aband + 1 ## i64
    if aband > wthr
      nb = aband + 12
    if nb > 60
      nb = bstart
      wraps = wraps + 1
      if wraps >= cyclesv
        << "CYCLEOUT rank=" + rank.to_s() + " mv=" + mv.to_s()
        flush()
        mv = {cap}
    aband = nb
    q = 2500000000 ## i64
    if aband > wthr
      q = 500000000{recordq_block}
    nextesc = mv + q
    << "BAND band=" + aband.to_s() + " rank=" + rank.to_s() + " mv=" + mv.to_s()
    flush()"""
        impreset = f"""    if aband >= wthr - 1
      if aband <= wthr + 1
        wthr = wthr + 1
        if wthr > 58
          wthr = 58
        << "WTHR thr=" + wthr.to_s() + " band=" + aband.to_s() + " mv=" + mv.to_s()
        flush()
    if aband != bstart
      aband = bstart
      << "BAND band=" + aband.to_s() + " rank=" + rank.to_s() + " mv=" + mv.to_s()
      flush()
    nextesc = mv + 2500000000"""
    elif adaptive_esc == "zones":
        # zone quanta: bands 1-4 -> +1/500M; 5-20 -> +1/2B; 21+ -> +5/1B; sawtooth at 60
        esc_block = """  if mv >= nextesc
    nb = aband + 1 ## i64
    if aband >= 20
      nb = aband + 5
    if aband >= 60
      nb = bstart
    aband = nb
    q = 500000000 ## i64
    if aband >= 5
      q = 2000000000
    if aband >= 21
      q = 1000000000
    nextesc = mv + q
    << "BAND band=" + aband.to_s() + " rank=" + rank.to_s() + " mv=" + mv.to_s()
    flush()"""
        impreset = """    if aband != bstart
      aband = bstart
      << "BAND band=" + aband.to_s() + " rank=" + rank.to_s() + " mv=" + mv.to_s()
      flush()
    nextesc = mv + 500000000"""
    elif adaptive_esc:
        esc_block = f"""  if (mv % {adaptive_esc}) == 0
    if mv > 0
      nb = aband + 1 ## i64
      if aband >= 30
        nb = aband + 5
      if aband >= 60
        nb = bstart
      aband = nb
      << "BAND band=" + aband.to_s() + " rank=" + rank.to_s() + " mv=" + mv.to_s()
      flush()"""
        impreset = """    if aband != bstart
      aband = bstart
      << "BAND band=" + aband.to_s() + " rank=" + rank.to_s() + " mv=" + mv.to_s()
      flush()"""
    else:
        esc_block = "  aband = aband"
        impreset = "    aband = aband"
    stop_block = ""
    if stopat is not None:
        stop_block = f"""    if best_rank <= {stopat}
      mv = {cap}"""

    # Tie-or-beat logging: independent of the personal-best dump above, which
    # only fires on STRICT improvement over this walker's own best (never true
    # at mv=0 when seeded AT the record, so ties were previously invisible).
    # Logs a transition of the LIVE scheme into rank <= world_record — a tie
    # (== world_record) or a genuine beat (< world_record) — but ONLY when its
    # density (total set bits) is a NEW BEST for this walker: a walker seeded
    # AT the record can dither right at the boundary continuously (observed
    # empirically 2026-07-05: one 18-walker/121s smoke test wrote 740,403 tie
    # files under a plain move-gap rate limit — tiegap alone does not bound
    # this). Density-gating both matches the actual goal ("find a sparser
    # one") and self-limits organically (a walker's own best density can only
    # improve a bounded number of times). tiegap becomes a light secondary
    # floor (not the primary control); tiemax is a hard per-walker cap as a
    # second independent backstop.
    tie_helpers = ""
    tie_init = ""
    tie_check = ""
    prevrank_update = ""
    if world_record is not None:
        tie_helpers = f"""
-> pc(x) (i64) i64
  c = 0 ## i64
  y = x ## i64
  while y != 0
    y = y & (y - 1)
    c = c + 1
  c

-> total_bits_live(st, uo, vo, wo, mo, rank) (i64[] i64 i64 i64 i64 i64) i64
  tb = 0 ## i64
  t = 0 ## i64
  while t < rank
    sl = st[mo + t] ## i64
    tb = tb + pc(st[uo + sl]) + pc(st[vo + sl]) + pc(st[wo + sl])
    t += 1
  tb"""
        tie_init = f"""
tiedir = ""
if av0.size() > 3
  tiedir = av0[3]
tiehit = 0 ## i64
last_tie_mv = 0 - {tiegap} - 1 ## i64
best_tie_bits = 999999999 ## i64
prevrank = rank ## i64"""
        tie_check = f"""
  if tiedir.size() > 0
    if tiehit < {tiemax}
      if snapped == 0
        if rank <= {world_record}
          if prevrank > {world_record}
            if mv - last_tie_mv >= {tiegap}
              tbits = total_bits_live(st, {O['US']}, {O['VS']}, {O['WS']}, {O['LIVE']}, rank) ## i64
              if tbits < best_tie_bits
                best_tie_bits = tbits
                last_tie_mv = mv
                tiehit = tiehit + 1
                << "TIE rank=" + rank.to_s() + " bits=" + tbits.to_s() + " mv=" + mv.to_s() + " v=" + verify(st, {O['US']}, {O['VS']}, {O['WS']}, {O['LIVE']}, rank, 13).to_s()
                flush()
                tiebody = rank.to_s() + "\\n"
                tdi = 0
                while tdi < rank
                  tsl = st[{O['LIVE']} + tdi] ## i64
                  tiebody = tiebody + st[{O['US']} + tsl].to_s() + " " + st[{O['VS']} + tsl].to_s() + " " + st[{O['WS']} + tsl].to_s() + "\\n"
                  tdi += 1
                write_file(tiedir + "_" + tiehit.to_s() + ".txt", tiebody)
                if rank < {world_record}
                  << "!!!!!! NEW RECORD rank=" + rank.to_s() + " (world record was {world_record}) mv=" + mv.to_s() + " !!!!!!"
                  flush()"""
        prevrank_update = "  prevrank = rank"

    binit = f"bstart = {band} ## i64"
    if randstart:
        binit = f"""rng = (rng * 1103515245 + 12345) & 2147483647
rng = (rng * 1103515245 + 12345) & 2147483647
rng = (rng * 1103515245 + 12345) & 2147483647
bstart = 1 + ((rng >> 27) % {rsmax}) ## i64"""
    return f'''st = i64[{TOT}]
st[{O['P2']}] = 1
kk = 1
while kk < {maxbits}
  st[{O['P2']} + kk] = st[{O['P2']} + kk - 1] + st[{O['P2']} + kk - 1]
  kk += 1
ii = 0
while ii < {arr}
  st[{O['IDL']} + ii] = ii
  st[{O['FL']} + ii] = {arr} - 1 - ii
  ii += 1
st[{O['FLT']}] = {arr}

-> hsh(x) (i64) i64
  y = x ^ (x >> 21) ^ (x >> 42) ## i64
  ((y * 2654435761) >> 13) & {TS - 1}

-> chain_link(st, ho, nxo, pvo, slot, key) (i64[] i64 i64 i64 i64 i64) i64
  hb = hsh(key) ## i64
  old = st[ho + hb] ## i64
  st[nxo + slot] = old
  st[pvo + slot] = 0
  if old != 0
    st[pvo + old - 1] = slot + 1
  st[ho + hb] = slot + 1
  0

-> chain_unlink(st, ho, nxo, pvo, slot, key) (i64[] i64 i64 i64 i64 i64) i64
  nn = st[nxo + slot] ## i64
  pp = st[pvo + slot] ## i64
  if pp == 0
    st[ho + hsh(key)] = nn
  if pp != 0
    st[nxo + pp - 1] = nn
  if nn != 0
    st[pvo + nn - 1] = pp
  0

-> ins_term(st, u, v, w, rank) (i64[] i64 i64 i64 i64) i64
  res = rank ## i64
  zero = 0 ## i64
  if u == 0
    zero = 1
  if v == 0
    zero = 1
  if w == 0
    zero = 1
  if zero == 0
    found = 0 - 1 ## i64
    c = st[{O['HU']} + hsh(u)] ## i64
    while c != 0
      s = c - 1 ## i64
      if st[{O['US']} + s] == u
        if st[{O['VS']} + s] == v
          if st[{O['WS']} + s] == w
            found = s
      c = st[{O['NXU']} + s]
      if found >= 0
        c = 0
    if found < 0
      fltop = st[{O['FLT']}] ## i64
      slot = st[{O['FL']} + fltop - 1] ## i64
      st[{O['FLT']}] = fltop - 1
      st[{O['US']} + slot] = u
      st[{O['VS']} + slot] = v
      st[{O['WS']} + slot] = w
      z0 = chain_link(st, {O['HU']}, {O['NXU']}, {O['PVU']}, slot, u) ## i64
      z0 = chain_link(st, {O['HV']}, {O['NXV']}, {O['PVV']}, slot, v) ## i64
      z0 = chain_link(st, {O['HW']}, {O['NXW']}, {O['PVW']}, slot, w) ## i64
      st[{O['LIVE']} + rank] = slot
      st[{O['POS']} + slot] = rank
      res = rank + 1
    if found >= 0
      z0 = chain_unlink(st, {O['HU']}, {O['NXU']}, {O['PVU']}, found, u) ## i64
      z0 = chain_unlink(st, {O['HV']}, {O['NXV']}, {O['PVV']}, found, v) ## i64
      z0 = chain_unlink(st, {O['HW']}, {O['NXW']}, {O['PVW']}, found, w) ## i64
      dp = st[{O['POS']} + found] ## i64
      lastslot = st[{O['LIVE']} + rank - 1] ## i64
      st[{O['LIVE']} + dp] = lastslot
      st[{O['POS']} + lastslot] = dp
      fltop = st[{O['FLT']}] ## i64
      st[{O['FL']} + fltop] = found
      st[{O['FLT']}] = fltop + 1
      res = rank - 1
  res

-> chain_count(st, ho, nxo, mo, key, ti) (i64[] i64 i64 i64 i64 i64) i64
  cnt = 0 ## i64
  c = st[ho + hsh(key)] ## i64
  while c != 0
    s = c - 1 ## i64
    if st[mo + s] == key
      if s != ti
        cnt = cnt + 1
    c = st[nxo + s]
  cnt

-> chain_pick(st, ho, nxo, mo, key, ti, want) (i64[] i64 i64 i64 i64 i64 i64) i64
  seen = 0 ## i64
  res = 0 - 1 ## i64
  c = st[ho + hsh(key)] ## i64
  while c != 0
    s = c - 1 ## i64
    if st[mo + s] == key
      if s != ti
        if seen == want
          res = s
        if res < 0
          seen = seen + 1
    c = st[nxo + s]
    if res >= 0
      c = 0
  res

-> chain_rpick(st, ho, nxo, mo, key, ti, rseed) (i64[] i64 i64 i64 i64 i64 i64) i64
  seen = 0 ## i64
  res = 0 - 1 ## i64
  r = rseed ## i64
  c = st[ho + hsh(key)] ## i64
  while c != 0
    s = c - 1 ## i64
    if st[mo + s] == key
      if s != ti
        seen = seen + 1
        r = (r * 1103515245 + 12345) & 2147483647
        if ((r * seen) >> 31) == 0
          res = s
    c = st[nxo + s]
  res

-> pressure(st, u, v, w) (i64[] i64 i64 i64) i64
  cnt = 0 ## i64
  c = st[{O['HU']} + hsh(u)] ## i64
  while c != 0
    s = c - 1 ## i64
    if st[{O['US']} + s] == u
      mv2 = 0 ## i64
      if st[{O['VS']} + s] == v
        mv2 = 1
      mw2 = 0 ## i64
      if st[{O['WS']} + s] == w
        mw2 = 1
      if mv2 + mw2 == 1
        cnt = cnt + 1
    c = st[{O['NXU']} + s]
  c = st[{O['HV']} + hsh(v)] ## i64
  while c != 0
    s = c - 1 ## i64
    if st[{O['VS']} + s] == v
      if st[{O['US']} + s] != u
        if st[{O['WS']} + s] == w
          cnt = cnt + 1
    c = st[{O['NXV']} + s]
  cnt

-> parity(mask, vec, width) (i64 i64 i64) i64
  pr = 0
  b = 0
  while b < width
    if ((mask >> b) & 1) == 1
      if ((vec >> b) & 1) == 1
        pr = (pr + 1) % 2
    b += 1
  pr

-> verify(st, uo, vo, wo, mo, rank, seed0) (i64[] i64 i64 i64 i64 i64 i64) i64
  ok = 1
  s = seed0
  trial = 0
  while trial < 20
    s = (s * 16807) % 2147483647
    s2 = (s * 16807) % 2147483647
    av = ((s * 8388608) ^ s2) % {MODA}
    s = (s2 * 16807) % 2147483647
    s2 = (s * 16807) % 2147483647
    bv = ((s * 8388608) ^ s2) % {MODB}
    s = s2
    o = 0
    while o < {CB}
      cs = 0
      t = 0
      while t < rank
        sl = st[mo + t] ## i64
        if ((st[wo + sl] >> o) & 1) == 1
          if parity(st[uo + sl], av, {AB}) == 1
            if parity(st[vo + sl], bv, {BB}) == 1
              cs = (cs + 1) % 2
        t += 1
      oi = o / {p}
      oj = o % {p}
      ct = 0
      kx = 0
      while kx < {m}
        if ((av >> (oi * {m} + kx)) & 1) == 1
          if ((bv >> (kx * {p} + oj)) & 1) == 1
            ct = (ct + 1) % 2
        kx += 1
      if cs != ct
        ok = 0
      o += 1
    trial += 1
  ok
{tie_helpers}

rank = 0 ## i64
{seed_block}
<< "seed rank=" + rank.to_s() + " verify=" + verify(st, {O['US']}, {O['VS']}, {O['WS']}, {O['LIVE']}, rank, 7).to_s()
flush()
best_rank = rank ## i64
bi = 0
while bi < rank
  sl = st[{O['LIVE']} + bi] ## i64
  st[{O['BUS']} + bi] = st[{O['US']} + sl]
  st[{O['BVS']} + bi] = st[{O['VS']} + sl]
  st[{O['BWS']} + bi] = st[{O['WS']} + sl]
  bi += 1
base = 1
dumpfile = ""
recorddir = ""
recordhit = 0 ## i64
av0 = argv()
if av0.size() > 0
  base = av0[0].to_i()
if av0.size() > 1
  dumpfile = av0[1]
if av0.size() > 2
  recorddir = av0[2]
{tie_init}
rng = base * 1009 + 12345 ## i64
threshold = {thr} ## i64
{binit}
aband = bstart ## i64
nextesc = {z1q} ## i64
wthr = {thr0} ## i64
wraps = 0 ## i64
{cycles_read}
<< "BSTART " + bstart.to_s()
flush()
mv = 0 ## i64
while mv < {cap}
  rng = (rng * 1103515245 + 12345) & 2147483647
  td = (rng * rank) >> 31 ## i64
  ti = st[{O['LIVE']} + td] ## i64
  ui = st[{O['US']} + ti] ## i64
  vi = st[{O['VS']} + ti] ## i64
  wi = st[{O['WS']} + ti] ## i64
  rng = (rng * 1103515245 + 12345) & 2147483647
  axis = (((rng >> 22) & 511) * 3) >> 9 ## i64
  partner = 0 - 1 ## i64
  rng = (rng * 1103515245 + 12345) & 2147483647
  if axis == 0
    partner = chain_rpick(st, {O['HU']}, {O['NXU']}, {O['US']}, ui, ti, rng)
  if axis == 1
    partner = chain_rpick(st, {O['HV']}, {O['NXV']}, {O['VS']}, vi, ti, rng)
  if axis == 2
    partner = chain_rpick(st, {O['HW']}, {O['NXW']}, {O['WS']}, wi, ti, rng)
  if partner >= 0
    uj = st[{O['US']} + partner] ## i64
    vj = st[{O['VS']} + partner] ## i64
    wj = st[{O['WS']} + partner] ## i64
    au = ui ## i64
    av2 = vi ## i64
    aw = wi ## i64
    bu = ui ## i64
    bv = vi ## i64
    bw = wj ## i64
    if axis == 0
      aw = wi ^ wj
      bv = vi ^ vj
    if axis == 1
      aw = wi ^ wj
      bu = ui ^ uj
    if axis == 2
      av2 = vi ^ vj
      aw = wi
      bu = ui ^ uj
      bv = vj
      bw = wi
    pold = pressure(st, ui, vi, wi) + pressure(st, uj, vj, wj) ## i64
    rankb = rank ## i64
    rank = ins_term(st, ui, vi, wi, rank) ## i64
    rank = ins_term(st, uj, vj, wj, rank) ## i64
    rank = ins_term(st, au, av2, aw, rank) ## i64
    rank = ins_term(st, bu, bv, bw, rank) ## i64
    pnew = pressure(st, au, av2, aw) + pressure(st, bu, bv, bw) ## i64
    acc = 0 ## i64
    if rank < rankb
      acc = 1
    if pnew + threshold >= pold
      acc = 1
    if acc == 0
      rank = ins_term(st, ui, vi, wi, rank) ## i64
      rank = ins_term(st, uj, vj, wj, rank) ## i64
      rank = ins_term(st, au, av2, aw, rank) ## i64
      rank = ins_term(st, bu, bv, bw, rank) ## i64
  if (mv % {plusper}) == 0
    rng = (rng * 1103515245 + 12345) & 2147483647
    pd1 = (rng * rank) >> 31 ## i64
    pt1 = st[{O['LIVE']} + pd1] ## i64
    rng = (rng * 1103515245 + 12345) & 2147483647
    pd2 = (rng * rank) >> 31 ## i64
    pt2 = st[{O['LIVE']} + pd2] ## i64
    spu = st[{O['US']} + pt1] ## i64
    spv = st[{O['VS']} + pt1] ## i64
    spw = st[{O['WS']} + pt1] ## i64
    wpr = st[{O['WS']} + pt2] ## i64
    if wpr != spw
      if wpr != 0
        spw2 = spw ^ wpr ## i64
        rank = ins_term(st, spu, spv, spw, rank) ## i64
        rank = ins_term(st, spu, spv, wpr, rank) ## i64
        rank = ins_term(st, spu, spv, spw2, rank) ## i64
  threshold = {thr} - ((mv / {thrper}) % {thrspan}) ## i64
{esc_block}
  snapped = 0 ## i64
  if rank > best_rank + aband
    while rank > 0
      sl = st[{O['LIVE']} + rank - 1] ## i64
      cu = st[{O['US']} + sl] ## i64
      cv = st[{O['VS']} + sl] ## i64
      cw = st[{O['WS']} + sl] ## i64
      rank = ins_term(st, cu, cv, cw, rank)
    ri = 0
    while ri < best_rank
      cu = st[{O['BUS']} + ri] ## i64
      cv = st[{O['BVS']} + ri] ## i64
      cw = st[{O['BWS']} + ri] ## i64
      rank = ins_term(st, cu, cv, cw, rank)
      ri += 1
    snapped = 1 ## i64
  if rank < best_rank
    best_rank = rank
    << "IMP rank=" + rank.to_s() + " band=" + aband.to_s() + " mv=" + mv.to_s()
    flush()
{impreset}
    ci = 0
    while ci < rank
      sl = st[{O['LIVE']} + ci] ## i64
      st[{O['BUS']} + ci] = st[{O['US']} + sl]
      st[{O['BVS']} + ci] = st[{O['VS']} + sl]
      st[{O['BWS']} + ci] = st[{O['WS']} + sl]
      ci += 1
    if dumpfile.size() > 0
      dumpbody = rank.to_s() + "\\n"
      di2 = 0
      while di2 < rank
        dumpbody = dumpbody + st[{O['BUS']} + di2].to_s() + " " + st[{O['BVS']} + di2].to_s() + " " + st[{O['BWS']} + di2].to_s() + "\\n"
        di2 += 1
      write_file(dumpfile, dumpbody)
      if recorddir.size() > 0
        if rank <= {recv}
          recordhit = recordhit + 1
          write_file(recorddir + "_" + recordhit.to_s() + ".txt", dumpbody)
{stop_block}
    if best_rank <= {recv}
      << "*** FOUND mv=" + mv.to_s() + " rank=" + rank.to_s() + " verify=" + verify(st, {O['US']}, {O['VS']}, {O['WS']}, {O['LIVE']}, rank, 7).to_s()
      di = 0
      while di < rank
        sl = st[{O['LIVE']} + di] ## i64
        << "R " + st[{O['US']} + sl].to_s() + " " + st[{O['VS']} + sl].to_s() + " " + st[{O['WS']} + sl].to_s()
        di += 1
      flush()
{tie_check}
  if (mv % 50000000) == 0
    << "  mv=" + mv.to_s() + " best=" + best_rank.to_s() + " cur=" + rank.to_s() + " v=" + verify(st, {O['US']}, {O['VS']}, {O['WS']}, {O['LIVE']}, rank, 7).to_s()
    flush()
{prevrank_update}
  mv += 1
<< "DONE best=" + best_rank.to_s() + " verify=" + verify(st, {O['BUS']}, {O['BVS']}, {O['BWS']}, {O['IDL']}, best_rank, 31).to_s()
di = 0
while di < best_rank
  << "R " + st[{O['BUS']} + di].to_s() + " " + st[{O['BVS']} + di].to_s() + " " + st[{O['BWS']} + di].to_s()
  di += 1
'''


def gen_worker(n, m, p, recv, world_record=None, cycles=4, thr=6, thrper=300000,
               plusper=2000, arr=200):
    """Thread-worker form of the cal2zone2 walker for flipfleet.w.

    Emits a MODULE of functions (no standalone `main`) that operate on a caller-
    owned `st = i64[worker_st_size(...)]`, so N of them can run on N threads over
    N separate `st` arrays:

      init_naive(st, seed)    build the naive scheme + init schedule state in st
      walk_worker(st, steps)  run `steps` flip-graph moves (allocation-free, no
                              I/O); schedule state (rng/aband/wthr/wraps/mv/
                              nextesc/best_rank/rank) lives in st's STV slots and
                              is loaded at entry / saved at exit — so repeated
                              calls continue one walker's cal2zone2 descent
      read_best_rank/…/cycled main-thread readers for coordination + the TUI

    The hash-chain helpers (hsh/chain_link/ins_term/chain_rpick/pressure/verify)
    are reused verbatim from gen() so this stays the *same* walker; only the
    driver (loop wrapper + state persistence + I/O removal) is new here.
    """
    # ---- layout (mirrors gen(); STV is last so earlier offsets are identical) --
    AB, BB, CB = n * m, m * p, n * p
    MODA, MODB = 1 << AB, 1 << BB
    maxbits = max(AB, BB, CB) + 1
    seed_rank = n * m * p
    arr = max(arr, seed_rank + 80)
    TS = 1
    while TS < 8 * arr + 8:
        TS *= 2
    off, cur = {}, 0
    for name, size in [("P2", maxbits), ("US", arr), ("VS", arr), ("WS", arr),
                       ("BUS", arr), ("BVS", arr), ("BWS", arr),
                       ("LIVE", arr), ("POS", arr), ("FL", arr), ("FLT", 2),
                       ("HU", TS), ("HV", TS), ("HW", TS),
                       ("NXU", arr), ("PVU", arr), ("NXV", arr), ("PVV", arr),
                       ("NXW", arr), ("PVW", arr), ("IDL", arr),
                       ("SU", arr + 8), ("SV", arr + 8), ("SW", arr + 8),
                       ("STV", 12)]:
        off[name] = cur
        cur += size
    TOT = cur
    O = off
    S = off["STV"]  # STV slots: 0 rank 1 best 2 rng 3 aband 4 wthr 5 wraps 6 mv
                    #            7 nextesc 8 cyclesv 9 cycled

    # ---- reuse gen()'s io-free hash-chain helpers by slicing them out ----------
    full = gen(n, m, p, recv, adaptive_esc="cal2zone2", band=1, thr0=7,
               world_record=None, thr=thr, thrper=thrper, plusper=plusper, arr=arr)
    helpers = full[full.index("-> hsh(x)"):full.index("\nrank = 0 ## i64")]

    thrspan = thr + 1
    # record budget: dwell 10B moves/band while at/under the world record
    recq = ""
    if world_record is not None:
        recq = f"""
      if rank <= {world_record}
        q = 10000000000"""

    return f'''{helpers}

-> wpc(x) (i64) i64
  c = 0 ## i64
  y = x ## i64
  while y != 0
    y = y & (y - 1)
    c = c + 1
  c

-> worker_st_size (i64)
  {TOT}

-> init_naive(st, seed, dslack, cycles) (i64[] i64 i64 i64) i64
  st[{O['P2']}] = 1
  kk = 1 ## i64
  while kk < {maxbits}
    st[{O['P2']} + kk] = st[{O['P2']} + kk - 1] + st[{O['P2']} + kk - 1]
    kk += 1
  ii = 0 ## i64
  while ii < {arr}
    st[{O['IDL']} + ii] = ii
    st[{O['FL']} + ii] = {arr} - 1 - ii
    ii += 1
  st[{O['FLT']}] = {arr}
  hz = 0 ## i64
  while hz < {TS}
    st[{O['HU']} + hz] = 0
    st[{O['HV']} + hz] = 0
    st[{O['HW']} + hz] = 0
    hz += 1
  rank = 0 ## i64
  ni = 0 ## i64
  while ni < {n}
    nj = 0 ## i64
    while nj < {m}
      nk = 0 ## i64
      while nk < {p}
        tu = st[{O['P2']} + ni * {m} + nj] ## i64
        tv = st[{O['P2']} + nj * {p} + nk] ## i64
        tw = st[{O['P2']} + ni * {p} + nk] ## i64
        rank = ins_term(st, tu, tv, tw, rank)
        nk += 1
      nj += 1
    ni += 1
  bi = 0 ## i64
  while bi < rank
    sl = st[{O['LIVE']} + bi] ## i64
    st[{O['BUS']} + bi] = st[{O['US']} + sl]
    st[{O['BVS']} + bi] = st[{O['VS']} + sl]
    st[{O['BWS']} + bi] = st[{O['WS']} + sl]
    bi += 1
  st[{S}] = rank
  st[{S} + 1] = rank
  st[{S} + 2] = seed * 1009 + 12345
  st[{S} + 3] = 1
  st[{S} + 4] = 7
  st[{S} + 5] = 0
  st[{S} + 6] = 0
  st[{S} + 7] = 100000000
  st[{S} + 8] = cycles
  st[{S} + 9] = 0
  st[{S} + 10] = dslack
  0

-> walk_worker(st, steps) (i64[] i64) i64
  rank = st[{S}] ## i64
  best_rank = st[{S} + 1] ## i64
  rng = st[{S} + 2] ## i64
  aband = st[{S} + 3] ## i64
  wthr = st[{S} + 4] ## i64
  wraps = st[{S} + 5] ## i64
  mv = st[{S} + 6] ## i64
  nextesc = st[{S} + 7] ## i64
  cyclesv = st[{S} + 8] ## i64
  dslack = st[{S} + 10] ## i64
  bstart = 1 ## i64
  threshold = {thr} ## i64
  sc = 0 ## i64
  while sc < steps
    rng = (rng * 1103515245 + 12345) & 2147483647
    td = (rng * rank) >> 31 ## i64
    ti = st[{O['LIVE']} + td] ## i64
    ui = st[{O['US']} + ti] ## i64
    vi = st[{O['VS']} + ti] ## i64
    wi = st[{O['WS']} + ti] ## i64
    rng = (rng * 1103515245 + 12345) & 2147483647
    axis = (((rng >> 22) & 511) * 3) >> 9 ## i64
    partner = 0 - 1 ## i64
    rng = (rng * 1103515245 + 12345) & 2147483647
    if axis == 0
      partner = chain_rpick(st, {O['HU']}, {O['NXU']}, {O['US']}, ui, ti, rng)
    if axis == 1
      partner = chain_rpick(st, {O['HV']}, {O['NXV']}, {O['VS']}, vi, ti, rng)
    if axis == 2
      partner = chain_rpick(st, {O['HW']}, {O['NXW']}, {O['WS']}, wi, ti, rng)
    if partner >= 0
      uj = st[{O['US']} + partner] ## i64
      vj = st[{O['VS']} + partner] ## i64
      wj = st[{O['WS']} + partner] ## i64
      au = ui ## i64
      av2 = vi ## i64
      aw = wi ## i64
      bu = ui ## i64
      bv = vi ## i64
      bw = wj ## i64
      if axis == 0
        aw = wi ^ wj
        bv = vi ^ vj
      if axis == 1
        aw = wi ^ wj
        bu = ui ^ uj
      if axis == 2
        av2 = vi ^ vj
        aw = wi
        bu = ui ^ uj
        bv = vj
        bw = wi
      pold = pressure(st, ui, vi, wi) + pressure(st, uj, vj, wj) ## i64
      rankb = rank ## i64
      rank = ins_term(st, ui, vi, wi, rank) ## i64
      rank = ins_term(st, uj, vj, wj, rank) ## i64
      rank = ins_term(st, au, av2, aw, rank) ## i64
      rank = ins_term(st, bu, bv, bw, rank) ## i64
      pnew = pressure(st, au, av2, aw) + pressure(st, bu, bv, bw) ## i64
      acc = 0 ## i64
      if rank < rankb
        acc = 1
      if acc == 0
        if pnew + threshold >= pold
          dn = wpc(au) + wpc(av2) + wpc(aw) + wpc(bu) + wpc(bv) + wpc(bw) ## i64
          do0 = wpc(ui) + wpc(vi) + wpc(wi) + wpc(uj) + wpc(vj) + wpc(wj) ## i64
          if dn <= do0 + dslack
            acc = 1
      if acc == 0
        rank = ins_term(st, ui, vi, wi, rank) ## i64
        rank = ins_term(st, uj, vj, wj, rank) ## i64
        rank = ins_term(st, au, av2, aw, rank) ## i64
        rank = ins_term(st, bu, bv, bw, rank) ## i64
    if (mv % {plusper}) == 0
      rng = (rng * 1103515245 + 12345) & 2147483647
      pd1 = (rng * rank) >> 31 ## i64
      pt1 = st[{O['LIVE']} + pd1] ## i64
      rng = (rng * 1103515245 + 12345) & 2147483647
      pd2 = (rng * rank) >> 31 ## i64
      pt2 = st[{O['LIVE']} + pd2] ## i64
      spu = st[{O['US']} + pt1] ## i64
      spv = st[{O['VS']} + pt1] ## i64
      spw = st[{O['WS']} + pt1] ## i64
      wpr = st[{O['WS']} + pt2] ## i64
      if wpr != spw
        if wpr != 0
          spw2 = spw ^ wpr ## i64
          rank = ins_term(st, spu, spv, spw, rank) ## i64
          rank = ins_term(st, spu, spv, wpr, rank) ## i64
          rank = ins_term(st, spu, spv, spw2, rank) ## i64
    threshold = {thr} - ((mv / {thrper}) % {thrspan}) ## i64
    if mv >= nextesc
      nb = aband + 1 ## i64
      if aband > wthr
        nb = aband + 12
      if nb > 60
        nb = bstart
        wraps = wraps + 1
        if wraps >= cyclesv
          st[{S} + 9] = 1
      aband = nb
      q = 2500000000 ## i64
      if aband > wthr
        q = 500000000{recq}
      nextesc = mv + q
    if rank > best_rank + aband
      hz = 0 ## i64
      while hz < {TS}
        st[{O['HU']} + hz] = 0
        st[{O['HV']} + hz] = 0
        st[{O['HW']} + hz] = 0
        hz += 1
      fz = 0 ## i64
      while fz < {arr}
        st[{O['FL']} + fz] = {arr} - 1 - fz
        fz += 1
      st[{O['FLT']}] = {arr}
      rank = 0 ## i64
      ri = 0 ## i64
      while ri < best_rank
        cu = st[{O['BUS']} + ri] ## i64
        cv = st[{O['BVS']} + ri] ## i64
        cw = st[{O['BWS']} + ri] ## i64
        rank = ins_term(st, cu, cv, cw, rank)
        ri += 1
    if rank < best_rank
      best_rank = rank
      if aband >= wthr - 1
        if aband <= wthr + 1
          wthr = wthr + 1
          if wthr > 58
            wthr = 58
      if aband != bstart
        aband = bstart
      nextesc = mv + 2500000000
      ci = 0 ## i64
      while ci < rank
        sl = st[{O['LIVE']} + ci] ## i64
        st[{O['BUS']} + ci] = st[{O['US']} + sl]
        st[{O['BVS']} + ci] = st[{O['VS']} + sl]
        st[{O['BWS']} + ci] = st[{O['WS']} + sl]
        ci += 1
    mv += 1
    sc += 1
  st[{S}] = rank
  st[{S} + 1] = best_rank
  st[{S} + 2] = rng
  st[{S} + 3] = aband
  st[{S} + 4] = wthr
  st[{S} + 5] = wraps
  st[{S} + 6] = mv
  st[{S} + 7] = nextesc
  best_rank

-> read_best_rank(st) (i64[]) i64
  st[{S} + 1]

-> read_best_u(st, i) (i64[] i64) i64
  st[{O['BUS']} + i]

-> read_best_v(st, i) (i64[] i64) i64
  st[{O['BVS']} + i]

-> read_best_w(st, i) (i64[] i64) i64
  st[{O['BWS']} + i]

-> read_cycled(st) (i64[]) i64
  st[{S} + 9]

-> verify_best(st) (i64[]) i64
  verify(st, {O['BUS']}, {O['BVS']}, {O['BWS']}, {O['IDL']}, st[{S} + 1], 31)

-> best_bits(st) (i64[]) i64
  tb = 0 ## i64
  br = st[{S} + 1] ## i64
  t = 0 ## i64
  while t < br
    tb = tb + wpc(st[{O['BUS']} + t]) + wpc(st[{O['BVS']} + t]) + wpc(st[{O['BWS']} + t])
    t += 1
  tb

-> reseed_from(st, src, seed) (i64[] i64[] i64) i64
  hz = 0 ## i64
  while hz < {TS}
    st[{O['HU']} + hz] = 0
    st[{O['HV']} + hz] = 0
    st[{O['HW']} + hz] = 0
    hz += 1
  fz = 0 ## i64
  while fz < {arr}
    st[{O['FL']} + fz] = {arr} - 1 - fz
    fz += 1
  st[{O['FLT']}] = {arr}
  rank = 0 ## i64
  srank = src[{S} + 1] ## i64
  si = 0 ## i64
  while si < srank
    rank = ins_term(st, src[{O['BUS']} + si], src[{O['BVS']} + si], src[{O['BWS']} + si], rank)
    si += 1
  ci = 0 ## i64
  while ci < rank
    sl = st[{O['LIVE']} + ci] ## i64
    st[{O['BUS']} + ci] = st[{O['US']} + sl]
    st[{O['BVS']} + ci] = st[{O['VS']} + sl]
    st[{O['BWS']} + ci] = st[{O['WS']} + sl]
    ci += 1
  st[{S}] = rank
  st[{S} + 1] = rank
  st[{S} + 2] = seed * 1009 + 12345
  st[{S} + 3] = 1
  st[{S} + 4] = 7
  st[{S} + 5] = 0
  st[{S} + 6] = 0
  st[{S} + 7] = 100000000
  st[{S} + 9] = 0
  0

-> load_scheme(st, path, seed) (i64[] String i64) i64
  hz = 0 ## i64
  while hz < {TS}
    st[{O['HU']} + hz] = 0
    st[{O['HV']} + hz] = 0
    st[{O['HW']} + hz] = 0
    hz += 1
  fz = 0 ## i64
  while fz < {arr}
    st[{O['FL']} + fz] = {arr} - 1 - fz
    fz += 1
  st[{O['FLT']}] = {arr}
  rank = 0 ## i64
  content = read_file(path)
  lines = content.split("\\n")
  srank = lines[0].to_i() ## i64
  si = 0 ## i64
  while si < srank
    parts = lines[si + 1].split(" ")
    rank = ins_term(st, parts[0].to_i(), parts[1].to_i(), parts[2].to_i(), rank)
    si += 1
  ci = 0 ## i64
  while ci < rank
    sl = st[{O['LIVE']} + ci] ## i64
    st[{O['BUS']} + ci] = st[{O['US']} + sl]
    st[{O['BVS']} + ci] = st[{O['VS']} + sl]
    st[{O['BWS']} + ci] = st[{O['WS']} + sl]
    ci += 1
  st[{S}] = rank
  st[{S} + 1] = rank
  st[{S} + 2] = seed * 1009 + 12345
  st[{S} + 3] = 1
  st[{S} + 4] = 7
  st[{S} + 5] = 0
  st[{S} + 6] = 0
  st[{S} + 7] = 100000000
  st[{S} + 9] = 0
  rank

-> dump_scheme(st, path) (i64[] String) i64
  br = st[{S} + 1] ## i64
  body = br.to_s() + "\\n"
  di = 0 ## i64
  while di < br
    body = body + st[{O['BUS']} + di].to_s() + " " + st[{O['BVS']} + di].to_s() + " " + st[{O['BWS']} + di].to_s() + "\\n"
    di += 1
  z = write_file(path, body)
  br
'''


if __name__ == "__main__":
    import sys
    if len(sys.argv) > 1 and sys.argv[1] == "--worker":
        n, m, p, recv = int(sys.argv[2]), int(sys.argv[3]), int(sys.argv[4]), int(sys.argv[5])
        wr = int(sys.argv[6]) if len(sys.argv) > 6 else None
        print(gen_worker(n, m, p, recv, world_record=wr), end="")
        sys.exit(0)
    n, m, p, recv = int(sys.argv[1]), int(sys.argv[2]), int(sys.argv[3]), int(sys.argv[4])
    seed = sys.argv[5] if len(sys.argv) > 5 else None
    cap = int(sys.argv[6]) if len(sys.argv) > 6 else 14000000000
    thr = int(sys.argv[7]) if len(sys.argv) > 7 else 6
    thrper = int(sys.argv[8]) if len(sys.argv) > 8 else 300000
    plusper = int(sys.argv[9]) if len(sys.argv) > 9 else 2000
    world_record = int(sys.argv[10]) if len(sys.argv) > 10 else None
    print(gen(n, m, p, recv, seed=seed, cap=cap, thr=thr, thrper=thrper, plusper=plusper,
              world_record=world_record), end="")
