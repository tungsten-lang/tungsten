# Associative array / Creation

colors = {
  red: "#FF0000"
  green: "#00FF00"
  blue: "#0000FF"
}

puts colors[:red]
puts colors[:green]
puts colors[:blue]

# Iteration
colors.each { |key, value|
  puts "[key] => [value]"
}

## expect skip currently unsupported in this runtime
