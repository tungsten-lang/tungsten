# Architecture-neutral carry kernels must not leak AArch64 inline assembly
# into x86_64 release artifacts. The ARM path remains hand-written asm; this
# contract pins the portable WIRE lowering selected by the target triple.

use ../lib/emitter

addmul = render_instruction({
  op: :asm_addmul1,
  temp: "%am",
  outp: "%out",
  ooff: "%oo",
  ap: "%a",
  aoff: "%ao",
  bsc: "%b",
  n: "%n"
}, nil, {}, nil, "", false)

if addmul.index("call i64 asm") != nil
  raise "portable asm_addmul1 emitted architecture-specific assembly"
if addmul.index("mul i128") == nil || addmul.index("lshr i128") == nil
  raise "portable asm_addmul1 omitted the i128 carry loop"

mulbase = render_instruction({
  op: :asm_mulbase,
  temp: "%mb",
  outp: "%out",
  ooff: "%oo",
  ap: "%a",
  aoff: "%ao",
  bp: "%b",
  boff: "%bo",
  na: "%na",
  nb: "%nb"
}, nil, {}, nil, "", false)

if mulbase.index("call i64 asm") != nil
  raise "portable asm_mulbase emitted architecture-specific assembly"
if mulbase.index("mul i128") == nil || mulbase.index("mb.zero.head") == nil
  raise "portable asm_mulbase omitted zeroing or the i128 carry loop"

arm = render_instruction({
  op: :asm_mulbase,
  temp: "%arm",
  outp: "%out",
  ooff: "%oo",
  ap: "%a",
  aoff: "%ao",
  bp: "%b",
  boff: "%bo",
  na: "%na",
  nb: "%nb"
}, nil, {}, nil, "", true)

if arm.index("call i64 asm") == nil || arm.index("umulh") == nil
  raise "arm64 asm_mulbase lost its specialized assembly path"

<< "portable-asm-lowering: ok"
