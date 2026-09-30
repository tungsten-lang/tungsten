# Port blockers (branch port/eval)

Language and stdlib problems met while writing the benchmark harness. Each entry has a
minimal repro (compiled with `bin/tungsten`, macOS arm64) and the workaround in the code.

## 1. Untyped integer arithmetic wraps at 64 bits

```
out = 1
i = 0
while i < 20
  out = out * 10
  i += 1
<< out      # 7766279631452241920, expected 100000000000000000000
```

Also at top level: `m = 1234567890123; << m * m * m` prints `5741104579333083507`. Integers built from
literals are compiled as raw machine integers and lose the BigInt promotion.
Workaround: `10 ** k` (promotes), and a call boundary for a product of unknown size
(`Format.times(a, b)` in `lib/metaflip/bench/format.w`).

## 2. `Float#to_i` saturates at 2^63

```
<< (~1e21).to_i     # 9223372036854775807
```

Workaround: `Format.fixed` halves the value (exactly) below 2^53 before converting and shifts the integer back.

## 3. `File.dirname`, `File.basename`, `File.realpath` are undefined in compiled programs

`File.dirname("/a/b")` raises `undefined method 'file_dirname' for File` (same for `file_basename`, `file_realpath`).
`File.expand_path`, `File.join`, `File.mkdir_p`, `File.rm`, `File.exists?` work.
Workaround: `Paths.dirname` / `Paths.basename` on strings (`lib/metaflip/bench/proc.w`).

## 4. Division without spaces after a closing parenthesis

```
-> f(st, c) (i64[] i64[]) i64
  period = c[46] ## i64
  ((st[7]+period-1)/period)*period
```

The interpreter reports `undefined method 'size' for 2004`; the compiled binary crashes with a segmentation fault.
`((st[7] + period - 1) / period) * period` works. Workaround: spaces around `/` (and a separate statement).

## 5. `a+@b` lexes as the unary-plus method

```
+ P
  -> new(@p, @q)
  -> sum
    @p+@q
<< P.new(1, 2).sum      # undefined method 'q' for P
```

Workaround: `@p + @q`.

## 6. Typed instance method called through `self`

```
+ S
  -> new(@a)
  -> pick(i, at) (i64 f64) f64
    2.5
  -> all(t) (f64)
    out = f64[2]
    i = 0 ## i64
    while i < 2
      out[i] = self.pick(i, t)
      i += 1
    out
<< S.new(1).all(100.0)   # runtime error: expected int, got nil
```

A direct call `S.new(1).pick(0, 1.0)` works. Workaround: no parameter types on instance methods that other methods call.

## 7. Wrapper flags

`bin/tungsten file.w check` prints `200 OK` (the word is taken as the syntax-check subcommand), and `--name`
options after the file are rejected by the wrapper (`Unknown flag: --experiment`) unless they follow a bare `--`.
Compiled binaries are unaffected. The tools are run through `bench/tool.sh` (compiles once, execs the binary).

## 8. Missing stdlib: resource usage of children

`Process` offers `spawn`/`poll`/`wait`/`kill` but no rusage; `getrusage`/`wait4` need raw buffers.
Written inside the bit with `ccall_nobox("wait4", ...)`, `ccall_nobox("w_typed_array_data_ptr", array)`,
`waitid` with `WNOWAIT` and `proc_pid_rusage` (`lib/metaflip/bench/proc.w`). A clock for the CPU time of the
process is `ccall_nobox("clock")` (microseconds).
