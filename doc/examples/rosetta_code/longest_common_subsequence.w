# Longest common subsequence

-> lcs(a, b)
  ac = a.chars
  bc = b.chars
  m = ac.size
  n = bc.size
  dp = []
  i = 0
  while i <= m
    row = []
    j = 0
    while j <= n
      row.push(0)
      j += 1
    dp.push(row)
    i += 1
  i = 1
  while i <= m
    j = 1
    while j <= n
      if ac[i - 1] == bc[j - 1]
        dp[i][j] = dp[i - 1][j - 1] + 1
      else
        up = dp[i - 1][j]
        left = dp[i][j - 1]
        if up >= left
          dp[i][j] = up
        else
          dp[i][j] = left
      j += 1
    i += 1
  out = ""
  i = m
  j = n
  while i > 0 && j > 0
    if ac[i - 1] == bc[j - 1]
      out = ac[i - 1] + out
      i -= 1
      j -= 1
    elsif dp[i - 1][j] >= dp[i][j - 1]
      i -= 1
    else
      j -= 1
  out

<< lcs("1234", "1224533324")
<< lcs("thisisatest", "testing123testing")

## expect stdout
## 1234
## tsitest
