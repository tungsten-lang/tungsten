# Hash freezing

`Hash#freeze` marks the existing hash immutable and returns it. All aliases see
the same state. `Hash#frozen?` reports the flag. Freezing is idempotent and also
freezes nested hashes reachable through keys, values, and arrays; cycles are
allowed. This does not make a hash copy.

```tungsten
units = {"m" => true, "s" => true}
same_units = units
units.freeze()
same_units.frozen?()          # true
units.has_key?("m")          # true
same_units["kg"] = true      # FrozenError
```

Reads, membership checks, iteration, and nonmutating operations continue to
work. Insert, overwrite, delete, and destructive merge/update raise
`FrozenError`, including deleting an absent key and merging an empty hash.
An exception leaves the original entries unchanged. `merge` creates a new,
mutable outer hash; values retain their original identities and frozen state.

The native implementation uses the existing `W_HASH_FLAG_FROZEN` header bit.
Frozen hashes are excluded from recycling, and scratch reuse allocates a new
hash. The compiler's interpreted mode uses the same primitives; the bootstrap
VM and Ruby engine enforce the hash mutation boundary too.

The unit-name registry freezes its table once at compiler startup. Tokenization
only reads that table, so file edits during a compiler or REPL process cannot
change its vocabulary halfway through a run.
