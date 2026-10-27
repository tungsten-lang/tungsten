# Dragon curve

-> dragon_turns(iterations)
  turns = []
  i = 0
  while i < iterations
    next_turns = []
    j = 0
    while j < turns.size
      next_turns.push(turns[j])
      j += 1
    next_turns.push("R")
    j = turns.size - 1
    while j >= 0
      if turns[j] == "R"
        next_turns.push("L")
      else
        next_turns.push("R")
      j -= 1
    turns = next_turns
    i += 1
  turns.join("")

(1..4).each -> (n)
  << "n=[n]: [dragon_turns(n)]"

## expect stdout
## n=1: R
## n=2: RRL
## n=3: RRLRRLL
## n=4: RRLRRLLRRRLLRLL
