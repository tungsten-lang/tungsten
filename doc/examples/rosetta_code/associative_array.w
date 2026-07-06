# Associative array / Creation

colors = {
  red: "#FF0000",
  green: "#00FF00",
  blue: "#0000FF"
}

<< colors[:red]
<< colors[:green]
<< colors[:blue]

# Iteration
colors.each -> (key, value)
  << "[key] => [value]"

## expect skip compiled-only for now — the Ruby interpreter (which runs this harness) can't execute it; try `bin/tungsten associative_array.w`
## expect stdout
## #FF0000
## #00FF00
## #0000FF
## green => #00FF00
## red => #FF0000
## blue => #0000FF
