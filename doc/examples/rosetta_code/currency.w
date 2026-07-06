# Currency: exact decimal money arithmetic (no floating-point rounding error)

items = [
  {name: "hamburger", price: $5.50, quantity: 4},
  {name: "milkshake", price: $2.86, quantity: 2}
]

subtotal = $0.00
items.each -> (item)
  cost = item[:price] * item[:quantity]
  << "[item[:name]]: [item[:quantity]] x [item[:price]] = [cost]"
  subtotal += cost

tax_rate = 0.0765
tax = subtotal * tax_rate
total = subtotal + tax

<< "Subtotal: [subtotal]"
<< "Tax:      [tax]"
<< "Total:    [total]"

## expect stdout
## hamburger: 4 x $5.50 = $22.00
## milkshake: 2 x $2.86 = $5.72
## Subtotal: $27.72
## Tax:      ≈$2.12
## Total:    ≈$29.84
