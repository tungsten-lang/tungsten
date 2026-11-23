# Cross-engine is_a? parity + inline tag lowering + local typed-array alias
# scopes + fixed-id fused-elementwise ewscope metadata.

use core/duration

-> check(name, cond)
  if cond
    << "PASS " + name
  else
    << "FAIL " + name
    exit 1

# 1. Primitive is_a? matrix across inline-tag and runtime paths
vals = [42, (1 << 80), ~3.14, 3.14, "hi", :sym, [1], {a: 1}, true, false, nil, (1..5), 5m30s]

check("int is Int", vals[0].is_a?(Int))
check("int is Integer", vals[0].is_a?(Integer))
check("int not BigInt", !vals[0].is_a?(BigInt))
check("int not Float", !vals[0].is_a?(Float))
check("int not String", !vals[0].is_a?(String))
check("int not Nil", !vals[0].is_a?(Nil))

check("bigint is Int", vals[1].is_a?(Int))
check("bigint is Integer", vals[1].is_a?(Integer))
check("bigint is BigInt", vals[1].is_a?(BigInt))
check("bigint not Float", !vals[1].is_a?(Float))

check("float is Float", vals[2].is_a?(Float))
check("float not Int", !vals[2].is_a?(Int))
check("float not Decimal", !vals[2].is_a?(Decimal))

check("decimal is Decimal", vals[3].is_a?(Decimal))
check("decimal not Float", !vals[3].is_a?(Float))

check("string is String", vals[4].is_a?(String))
check("string not Symbol", !vals[4].is_a?(Symbol))

# Long concatenated strings stay WRope until flattened; is_a? must recognize them.
rope = "https://accounts.google.com/v3/signin/" + "identifier?hl=en&passive=true&" + "continue=https://www.google.com/&flowName=GlifWebSignIn"
str_cls = String
check("rope is String", rope.is_a?(String))
check("rope is String (var)", rope.is_a?(str_cls))
check("rope is String (name)", rope.is_a?("String"))
check("rope not Symbol", !rope.is_a?(Symbol))
check("rope not Int", !rope.is_a?(Int))
check("rope not Hash", !rope.is_a?(Hash))

check("symbol is Symbol", vals[5].is_a?(Symbol))
check("symbol not String", !vals[5].is_a?(String))

check("array is Array", vals[6].is_a?(Array))
check("array not Hash", !vals[6].is_a?(Hash))

check("hash is Hash", vals[7].is_a?(Hash))
check("hash not Array", !vals[7].is_a?(Array))

check("true is Boolean", vals[8].is_a?(Boolean))
check("false is Boolean", vals[9].is_a?(Boolean))
check("true not Nil", !vals[8].is_a?(Nil))
check("false not Int", !vals[9].is_a?(Int))

check("nil is Nil", vals[10].is_a?(Nil))
check("nil not Boolean", !vals[10].is_a?(Boolean))
check("nil not Hash", !vals[10].is_a?(Hash))

check("range is Range", vals[11].is_a?(Range))
check("range not Array", !vals[11].is_a?(Array))

check("duration is Duration", vals[12].is_a?(Duration))
check("duration not Int", !vals[12].is_a?(Int))

# 2. User classes, inheritance, dynamic class variables, string targets
+ Animal
  -> new(@name)
+ Dog < Animal
  -> bark
    "woof"

dog = Dog.new("rex")
cat = Animal.new("cat")
cls_var = Animal
check("subclass is_a? self", dog.is_a?(Dog))
check("subclass is_a? parent", dog.is_a?(Animal))
check("parent not subclass", !cat.is_a?(Dog))
check("dynamic class var", dog.is_a?(cls_var))
check("string target class", dog.is_a?("Animal"))
check("string target primitive", vals[10].is_a?("Nil") && vals[11].is_a?("Range"))
check("Class object not String", !String.is_a?(String))

# 3. Tight loop exercising inline is_a? (used for IR & perf verification)
-> count_kinds(xs)
  ints = 0
  strs = 0
  nils = 0
  hashes = 0
  i = 0
  while i < xs.size
    x = xs[i]
    if x.is_a?(Integer)
      ints += 1
    elsif x.is_a?(String)
      strs += 1
    elsif x.is_a?(Nil)
      nils += 1
    elsif x.is_a?(Hash)
      hashes += 1
    i += 1
  ints * 1000 + strs * 100 + nils * 10 + hashes

check("count_kinds loop", count_kinds(vals) == 2111)

# 4. Local typed-array alias scopes: 1 param + 1 local scratch buffer
-> xor_with_scratch(src, n) (u8[] i64) i64
  scratch = u8[n]
  i = 0 ## i64
  while i < n
    scratch[i] = (src[i] ^ 0x5A) & 255
    i += 1
  acc = 0 ## i64
  j = 0 ## i64
  while j < n
    acc += scratch[j] + src[j]
    j += 1
  acc

in_bytes = u8[16]
bi = 0
while bi < 16
  in_bytes[bi] = bi
  bi += 1
# sum_{k=0..15} (k + (k ^ 0x5A)) = 120 + (16*0x50 + 120) = 1520
check("local typed array alias scope", xor_with_scratch(in_bytes, 16) == 1520)

# 5. Multiple fused elementwise sites in one function (fixed-id ewscope)
-> multi_fused(a, b) (f64[] f64[]) f64
  c = a .* ~2.0 .+ b
  d = c .* ~0.5 .- a
  d.sum

fa = f64[8]
fb = f64[8]
fi = 0
while fi < 8
  fa[fi] = (fi + 1).to_f()
  fb[fi] = (fi * 2).to_f()
  fi += 1
# d[i] = ((2*a[i] + b[i]) * 0.5) - a[i] = b[i] * 0.5 = i => sum(0..7) = 28.0
check("multi_fused fixed-id ewscope", multi_fused(fa, fb) == ~28.0)

<< "is_a_and_alias_scope_spec: all checks passed"
