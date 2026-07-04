# Variables and basic types
name = "Tungsten"
version = 1
pi = 3.14159
active = true

<< "Language: [name]"
<< "Version: [version]"
<< "Pi: [pi]"
<< "Active: [active]"

## parity skip decimal formatting differs in compiled output
## expect stdout
## Language: Tungsten
## Version: 1
## Pi: 3.14159
## Active: true
