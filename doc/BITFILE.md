## Bitfile
```
source "https://bits.tungsten-lang.org"

external "ruby", "4.0.2"
external "llvm", "current"
external "openssl", "current"

bit “tungsten-carbide”, “~> 0.0.1”

group :development ->
  bit "tungsten-console"
```
