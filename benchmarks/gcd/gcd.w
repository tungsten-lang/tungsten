## u64: a, b, az, bz, shift, d, tz, lo, mag
fn gcd(a, b)
  return b if a == 0
  return a if b == 0
  az = cttz(a)
  bz = cttz(b)
  shift = az < bz ? az : bz
  a = a >> az
  b = b >> bz
  while a != b
    d = a - b
    tz = cttz(d)
    lo = b
    mag = d
    if a < b
      lo = a
      mag = 0 - d
    b = lo
    a = mag >> tz
  return a << shift

fn main
  result = 0 ## u64
  with i in 1..22000000
    result += gcd(i, 31415927)

  result

<< main
