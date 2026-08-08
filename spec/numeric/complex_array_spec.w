# ComplexArray — interleaved (re, im) f64 storage with FCMLA bulk kernels.
# Values chosen exact in f64 so both engines print identical output.

xs = ComplexArray.new(3)
xs[0] = Complex.new(1.0, 1.0)
xs[1] = Complex.new(2.0, 0.0)
xs[2] = Complex.new(0.0, 3.0)
<< "size " + xs.size.to_s
<< "get " + xs[0].to_s + " " + xs[2].to_s

ys = ComplexArray.from([Complex.new(2.0, 3.0), Complex.new(1.0, 1.0), Complex.new(0.0, 2.0)])

# elementwise multiply: (1+i)(2+3i) = -1+5i ; (2)(1+i) = 2+2i ; (3i)(2i) = -6
m = xs.mul(ys)
<< "mul " + m.to_s

# conjugate dot: conj(1+i)(2+3i) + conj(2)(1+i) + conj(3i)(2i)
#  = (1-i)(2+3i) + 2(1+i) + (-3i)(2i) = (5+i) + (2+2i) + 6 = 13+3i
d = xs.conj_dot(ys)
<< "cdot " + d.to_s

# scale by i rotates: (1+i)i = -1+i
s = xs.scale(Complex.i)
<< "scalei " + s[0].to_s

# real scale
r = xs.scale(2.0)
<< "scale2 " + r[1].to_s

# add / sub ride the plain f64 elementwise kernels
a = xs + ys
<< "add " + a[0].to_s
b = xs - ys
<< "sub " + b[0].to_s

# tower interop through []= (Complex<f64> accepted via .real/.imag)
zs = ComplexArray.new(1)
zs[0] = Complex.new(7.0, -2.0)
<< "set " + zs[0].to_s

# kernel-vs-scalar oracle at a size crossing the unrolled lane loop,
# including negative and fractional values
n = 37
p = ComplexArray.new(n)
q = ComplexArray.new(n)
i = 0
while i < n
  fi = i.to_f
  p[i] = Complex.new(fi * 0.5 - 3.0, 2.0 - fi * 0.25)
  q[i] = Complex.new(1.5 - fi * 0.125, fi * 0.75 - 4.0)
  i += 1
kernel = p.mul(q)
ok = true
i = 0
while i < n
  want = p[i] * q[i]
  ok = false if !(kernel[i] == want)
  i += 1
<< "oracle " + ok.to_s

kd = p.conj_dot(q)
sr = 0.0
si = 0.0
i = 0
while i < n
  t = p[i].conjugate * q[i]
  sr = sr + t.real
  si = si + t.imag
  i += 1
<< "doracle " + ((kd.real - sr).abs < 0.0000001 && (kd.imag - si).abs < 0.0000001).to_s
