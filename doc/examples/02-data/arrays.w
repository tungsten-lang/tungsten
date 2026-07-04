# Array operations
numbers = [5, 3, 1, 4, 2]

<< "Original: [numbers.join(", ")]"
<< "Sorted:   [numbers.sort.join(", ")]"
<< "Sum:      [numbers.sum]"
<< "Min:      [numbers.min]"
<< "Max:      [numbers.max]"
<< "Length:   [numbers.size]"

# Functional operations
doubled = numbers.map(->(x) x * 2)
<< "Doubled:  [doubled.join(", ")]"

evens = numbers.select(->(x) x % 2 == 0)
<< "Evens:    [evens.join(", ")]"

total = numbers.reduce(0, ->(a, b) a + b)
<< "Total:    [total]"

## expect stdout
## Original: 5, 3, 1, 4, 2
## Sorted:   1, 2, 3, 4, 5
## Sum:      15
## Min:      1
## Max:      5
## Length:   5
## Doubled:  10, 6, 2, 8, 4
## Evens:    4, 2
## Total:    15
