# Vector products

-> dot(a, b)
  a[0] * b[0] + a[1] * b[1] + a[2] * b[2]

-> cross(a, b)
  [
    a[1] * b[2] - a[2] * b[1],
    a[2] * b[0] - a[0] * b[2],
    a[0] * b[1] - a[1] * b[0]
  ]

-> scalar_triple(a, b, c)
  dot(a, cross(b, c))

-> vector_triple(a, b, c)
  cross(a, cross(b, c))

a = [3, 4, 5]
b = [4, 3, 5]
c = [-5, -12, -13]

<< "a . b = [dot(a, b)]"
<< "a x b = [cross(a, b)]"
<< "a . (b x c) = [scalar_triple(a, b, c)]"
<< "a x (b x c) = [vector_triple(a, b, c)]"

## expect stdout
## a . b = 49
## a x b = [5, 5, -7]
## a . (b x c) = 6
## a x (b x c) = [-267, 204, -3]
