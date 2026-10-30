# Count the coins (Making change)

-> count_coins(amount, coins)
  ways = []
  i = 0
  while i <= amount
    ways.push(0)
    i += 1
  ways[0] = 1
  c = 0
  while c < coins.size
    coin = coins[c]
    j = coin
    while j <= amount
      ways[j] += ways[j - coin]
      j += 1
    c += 1
  ways[amount]

<< count_coins(100, [1, 5, 10, 25])
<< count_coins(1000, [1, 5, 10, 25, 50, 100])

## expect stdout
## 242
## 2103596
