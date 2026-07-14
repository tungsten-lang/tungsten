# Fixed-size numeric method microbenchmark.
#
# Measures the public Vec/Mat methods whose generic implementations may build
# iterator/zip temporaries.  Keep the iteration count modest: public methods
# return fresh value objects and the current runtime does not reclaim them
# during the process.
#
#   bin/tungsten -o /tmp/fixed_numeric_ops \
#     benchmarks/linalg/tungsten/fixed_numeric_ops.w
#   /tmp/fixed_numeric_ops 100000

k = ARGV[0] == nil ? 0 : ARGV[0].to_i
if k <= 0
  k = 100000

v3a = Vec3<f64>.new([~1.25, ~2.5, ~3.75] ## f64[3])
v3b = Vec3<f64>.new([~4.0, ~5.0, ~6.0] ## f64[3])
v4a = Vec4<f64>.new([~1.25, ~2.5, ~3.75, ~4.5] ## f64[4])
v4b = Vec4<f64>.new([~4.0, ~5.0, ~6.0, ~7.0] ## f64[4])

m3a = Mat3<f64>.new([
  ~1.0, ~2.0, ~3.0,
  ~4.0, ~5.0, ~6.0,
  ~7.0, ~8.0, ~10.0
] ## f64[9])
m3b = Mat3<f64>.new([
  ~2.0, ~3.0, ~4.0,
  ~5.0, ~6.0, ~7.0,
  ~8.0, ~9.0, ~11.0
] ## f64[9])

m4a = Mat4<f64>.new([
  ~1.0, ~2.0, ~3.0, ~4.0,
  ~5.0, ~6.0, ~7.0, ~8.0,
  ~9.0, ~10.0, ~11.0, ~12.0,
  ~13.0, ~14.0, ~15.0, ~17.0
] ## f64[16])
m4b = Mat4<f64>.new([
  ~2.0, ~3.0, ~4.0, ~5.0,
  ~6.0, ~7.0, ~8.0, ~9.0,
  ~10.0, ~11.0, ~12.0, ~13.0,
  ~14.0, ~15.0, ~16.0, ~18.0
] ## f64[16])

vr = v3a + v3b
t0 = clock()
i = 0
while i < k
  vr = v3a + v3b
  i++
t1 = clock()
<< "vec3 add ns/op:" << ((t1 - t0) * ~1000000000.0 / k) << " checksum:" << vr.x

dot = v3a.dot(v3b)
t0 = clock()
i = 0
while i < k
  dot = v3a.dot(v3b)
  i++
t1 = clock()
<< "vec3 dot ns/op:" << ((t1 - t0) * ~1000000000.0 / k) << " checksum:" << dot

len2 = v4a.length_squared
t0 = clock()
i = 0
while i < k
  len2 = v4a.length_squared
  i++
t1 = clock()
<< "vec4 abs2 ns/op:" << ((t1 - t0) * ~1000000000.0 / k) << " checksum:" << len2

mr3 = m3a + m3b
t0 = clock()
i = 0
while i < k
  mr3 = m3a + m3b
  i++
t1 = clock()
<< "mat3 add ns/op:" << ((t1 - t0) * ~1000000000.0 / k) << " checksum:" << mr3.elements[0]

mr4 = m4a + m4b
t0 = clock()
i = 0
while i < k
  mr4 = m4a + m4b
  i++
t1 = clock()
<< "mat4 add ns/op:" << ((t1 - t0) * ~1000000000.0 / k) << " checksum:" << mr4.elements[0]

ia = Interval.new(~-3.0, ~5.0)
ib = Interval.new(~-7.0, ~11.0)
ir = ia * ib
t0 = clock()
i = 0
while i < k
  ir = ia * ib
  i++
t1 = clock()
<< "interval mixed mul ns/op:" << ((t1 - t0) * ~1000000000.0 / k) << " checksum:" << ir.lo

ipa = Interval.new(~2.0, ~5.0)
ipb = Interval.new(~3.0, ~11.0)
ipr = ipa * ipb
t0 = clock()
i = 0
while i < k
  ipr = ipa * ipb
  i++
t1 = clock()
<< "interval positive mul ns/op:" << ((t1 - t0) * ~1000000000.0 / k) << " checksum:" << ipr.hi

pow_k = k / 1000
if pow_k < 1
  pow_k = 1
if pow_k > 500
  pow_k = 500
zbase = Complex<f64>.new([~0.999, ~0.001] ## f64[2])
zlinear = zbase
t0 = clock()
i = 0
while i < pow_k
  zlinear = zbase
  e = 1
  while e < 127
    zlinear = zlinear * zbase
    e++
  i++
t1 = clock()
<< "complex pow127 linear ns/op:" << ((t1 - t0) * ~1000000000.0 / pow_k) << " checksum:" << zlinear.real

zbinary = zbase ** 127
t0 = clock()
i = 0
while i < pow_k
  zbinary = zbase ** 127
  i++
t1 = clock()
<< "complex pow127 binary ns/op:" << ((t1 - t0) * ~1000000000.0 / pow_k) << " checksum:" << zbinary.real
