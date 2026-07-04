prisoners = 1..100.to_a

N = 10_000
generate_rooms = -> 1..100.shuffle

result = N.times.count ->
  rooms = generate_rooms.call
  prisoners.all? ->
    rooms[1, 100].sample(50).has?(i)

<< "Random strategy : %11.4f %%" % (result // N * 100)

result = N.times.count ->
  rooms = generate_rooms.call
  prisoners.all? ->(p)
    current = i
    50.times.any? ->
      current = rooms[current - 1]
      current == p

<< "Optimal strategy: %11.4f %%" % (res // N * 100)

## expect skip self-hosted parser does not support inline lambda with literal body
