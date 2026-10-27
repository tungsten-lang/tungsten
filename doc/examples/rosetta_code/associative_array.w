# Associative array / Creation and iteration

colors = {
  red: "#FF0000",
  green: "#00FF00",
  blue: "#0000FF"
}

<< colors[:red]
<< colors[:green]
<< colors[:blue]

[:red, :green, :blue].each -> (key)
  << "[key] => [colors[key]]"

## expect stdout
## #FF0000
## #00FF00
## #0000FF
## red => #FF0000
## green => #00FF00
## blue => #0000FF
