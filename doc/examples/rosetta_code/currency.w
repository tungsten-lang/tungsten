# http://rosettacode.org/wiki/Currency

items<table>
  | *name*    | price | quantity              |
  | hamburger | $5.50 | 4_000_000_000_000_000 |
  | milkshake | $2.86 | 2                     |

items[:cost] = items.product(:price, :quantity)

subtotal = items.sum(:cost)

tax      = subtotal * 7.65%
total    = subtotal + tax

items ->
  blankrow

  row quantity: "subtotal", cost: subtotal, align: "|"
  row quantity: "tax",      cost: tax
  row quantity: "total",    cost: total

  align "<>>"
  print

## expect skip currently unsupported in this runtime
