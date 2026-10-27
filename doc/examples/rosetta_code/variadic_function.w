# Variadic function

-> print_all(*items)
  items.each -> (item)
    << item

print_all("Mary", "had", "a", "little", "lamb")

## expect stdout
## Mary
## had
## a
## little
## lamb
