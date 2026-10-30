# Monty Hall problem

# Deterministic evaluation over all 9 (car_door, initial_pick) combinations
-> monty_hall_exact()
  stay_wins = 0
  switch_wins = 0
  total = 0
  (0..2).each -> (car)
    (0..2).each -> (pick)
      total += 1
      if pick == car
        stay_wins += 1
      else
        switch_wins += 1
  << "Stay wins:   [stay_wins]/[total]"
  << "Switch wins: [switch_wins]/[total]"

monty_hall_exact()

## expect stdout
## Stay wins:   3/9
## Switch wins: 6/9
