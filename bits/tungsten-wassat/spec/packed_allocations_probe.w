# Native allocation regression, driven by packed_allocations_test.py.
use wassat

ar = i64[70005]
cm = i64[2]
alive = i64[1]
wd = i64[40]
wp = i64[32]
ws = i64[3]
bd = i64[40]
bp = i64[32]
bs = i64[3]
cm[0] = 70001
cm[1] = 3
alive[0] = 1
ar[70001] = -1
ar[70002] = 2
ar[70003] = 3
ws[1] = 32
bs[1] = 32
i = 0
while i < 100000
  wassat_hdr_put(ar, 70000, 70000, 3)
  wd[13] = 0
  wassat_ws_add(wd, wp, ws, 3, 70001, 2)
  bd[13] = 0
  wassat_bl_add(bd, bp, bs, 3, 70000, 5)
  wassat_ws_rebuild(cm, alive, ar, wd, wp, ws, 1, 10)
  i += 1
<< "packed allocation probe complete"
