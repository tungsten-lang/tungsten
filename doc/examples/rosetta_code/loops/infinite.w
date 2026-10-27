# Loops/Infinite

-> run_bounded_infinite()
  count = 0
  while true
    << "SPAM"
    count += 1
    if count >= 5
      break

run_bounded_infinite()

## expect stdout
## SPAM
## SPAM
## SPAM
## SPAM
## SPAM
