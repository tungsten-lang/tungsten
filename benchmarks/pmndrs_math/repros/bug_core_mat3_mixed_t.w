# Pre-existing in core: Mat3's same-class typed overloads (`*/1(Mat3)`,
# `mul_into/2(Mat3 Mat3)`) do f64 loads on an f32 operand's buffer, reading
# 72 bytes from a 36-byte array. The result is denormals/NaN, not an error.
a = Mat3<f64>.new([~1.0, ~2.0, ~3.0, ~4.0, ~5.0, ~6.0, ~7.0, ~8.0, ~9.0] ## f64[9])
eye32 = Mat3<f32>.new([~1.0, ~0.0, ~0.0, ~0.0, ~1.0, ~0.0, ~0.0, ~0.0, ~1.0] ## f32[9])
out = Mat3<f64>.new([~0.0, ~0.0, ~0.0, ~0.0, ~0.0, ~0.0, ~0.0, ~0.0, ~0.0] ## f64[9])
<< "expect 1 2 3 4 5 6 7 8 9 (a times the identity)"
<< "a * eye32:        " + (a * eye32).elements.to_s
<< "a.mul_into(eye32): " + a.mul_into(eye32, out).elements.to_s
