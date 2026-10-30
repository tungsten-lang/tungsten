# Sum and product of an array

nums = [1, 2, 3, 4, 5]
sum = 0
prod = 1
nums.each -> (x)
  sum += x
  prod *= x

<< "Sum: [sum]"
<< "Product: [prod]"

## expect stdout
## Sum: 15
## Product: 120
