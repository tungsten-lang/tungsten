bars = '▁' .. '█'

msg = 'Numbers separated by spaces: '

loop ->
  numbers = gets(msg).to_args.to_f

  << bars[*numbers.normalize(bars.size)].join

## expect skip interactive loop example
