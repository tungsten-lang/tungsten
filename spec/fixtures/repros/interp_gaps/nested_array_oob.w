# Out-of-bounds reads on nested arrays must return nil — never a neighboring
# allocation's word. Generic `[]` dispatch (the interpreter's index path and
# any compiled call site with an untyped receiver) rode the UNCHECKED
# w_array_idx IC row: `[[1,2],[3,4]][9]` returned 2, an adjacent inner-array
# element. Fixed by routing the IC rows for [] / []= through the checked
# w_array_get / w_array_set (koala's Matrix#at bounds-check workaround from
# a54d64a is no longer load-bearing).
m = [[1, 2], [3, 4]]
r1 = m[9] == nil
r2 = m[2] == nil
r3 = m[100] == nil
r4 = m[0 - 1].join("-")
<< "m9-nil=[r1]"
<< "m2-nil=[r2]"
<< "m100-nil=[r3]"
<< "mneg=[r4]"
n = [1, 2, 3]
r5 = n[9] == nil
<< "flat9-nil=[r5]"
lit = [[1, 2], [3, 4]][9]
r6 = lit == nil
<< "lit9-nil=[r6]"
w = [1, 2]
w[50] = 9
ws = w.size
<< "oob-set-size=[ws]"
