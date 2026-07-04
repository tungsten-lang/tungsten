next_open = 1
delta = 3

(1..100).each ->(pass)
  state = "closed"
  if pass == next_open
    state = "open"
    next_open += delta
    delta += 2
  << "Door [pass] is [state]."

## expect stdout
## Door 1 is open.
## Door 2 is closed.
## Door 3 is closed.
## ...
## Door 100 is open.
