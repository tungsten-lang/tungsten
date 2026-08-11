# Print the declaration block produced by the real emitter. The ccall contract
# verifier consumes this instead of maintaining a second LLVM declaration list.

use ../lib/emitter

print declare_runtime()
