# Special variables: `$name` globals, visible across functions without
# threading a parameter through every call

$counter = 0

-> increment
  $counter += 1

increment
increment
increment

<< $counter

## expect stdout
## 3
