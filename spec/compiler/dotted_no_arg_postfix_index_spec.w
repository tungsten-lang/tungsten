# A tight index after a dotted no-argument call indexes the returned value.
# It must not be consumed as a bare Array argument to the dotted call.

+ DottedNoArgPostfixIndexProbe
  -> values
    [10, 20, 30]

  -> echo(value)
    value

probe = DottedNoArgPostfixIndexProbe.new()
if probe.values[0] != 10
  << "FAIL dotted no-arg postfix index: first element"
  exit(1)
if probe.values[2] != 30
  << "FAIL dotted no-arg postfix index: last element"
  exit(1)

# Whitespace keeps its established meaning: this is a bare Array argument,
# not an index on the result of echo.
spaced = probe.echo [4, 5]
if spaced[1] != 5
  << "FAIL spaced Array bare argument changed meaning"
  exit(1)

<< "PASS dotted no-arg postfix index"
