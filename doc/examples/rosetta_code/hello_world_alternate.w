# https://rosettacode.org/wiki/Hello_world/Text#Ruby
#
# "<<" is sugar for $stdout.puts  @1
# "<-" is sugar for $stdout.print @1
# "<?" is sugar for $stdout.puts  @1.inspect
# "<!" is sugar for $stderr.puts  @1

<< "Hello world!"

name = "Tungsten"
<< "Hello, [name]."

# stdout, without newline
<- "Hello world!"
## expect stdout
## Hello world!
## Hello, Tungsten.
## Hello world!
