# pmndrs/math-inspired A/B benchmarks

A/B experiments testing whether implementation ideas from
[pmndrs/math](https://github.com/pmndrs/math) (a glMatrix-lineage,
allocation-free JS math library) speed up Tungsten's existing numeric
classes (Vec2/3/4, Mat2/3/4, Quaternion, StatsRng, Polygon).

## Method

Each `*_ab.w` file compares candidate bodies, written exactly as they would
land in `core/`, in a `…Fast<T> < Core<T>` subclass against a control. The
fair control is the real core class itself or a `…Copy<T>` subclass holding
the current core bodies copied verbatim: an inheriting no-override `…Base`
subclass runs 2-10% slow, because inherited methods on a subclass receiver
miss the `class.new` fast-path guard.

Every binary takes `<variant> <iters>` and prints
`ns/op: <float> checksum: <value>`. Build with `--release` (plain `-o` is
`-O0` and inverts rankings):

    bin/tungsten --release -o /tmp/quat_ab benchmarks/pmndrs_math/quat_ab.w
    benchmarks/pmndrs_math/ab.py /tmp/quat_ab 1000000 5 base fast

`ab.py` runs each variant in its own process, interleaved, and reports
median wall ns/op, instructions/op (contention-immune), cycles/op, and
peak memory. Instructions retired cannot see latency (fdiv vs fmul), so
latency-bound changes are judged on wall/cycles with extra reps.

## Language gotchas hit while writing these

- A subclass must re-declare `- data` / `T elements[N]` (or `components`):
  otherwise its bodies see the inherited field as untyped and run boxed
  (a verbatim Mat4 `inverse` went from 57 ns to 1480 ns).
- Inside a subclass, a self-type annotation must name the subclass
  (`(Mat4Fast)`), since `(Mat4)` only types the parameter inside `Mat4<T>`.
- `(Vec4)` / `(Vector)` parameter annotations do not type the argument's
  components; read them as `v[0] ## T`. `-x` on a typed float and
  `2 * typed_float` lower to boxed runtime calls.

- An ALL-CAPS name like `QB` is a constant, so `QB<f64>` parses as a
  comparison. Use PascalCase class names.
- Compiled `Generic<T>.new(...)` inside an `elsif` arm resolves the class
  to nil ("undefined method 'new' for nil"); `if`/`else` arms are fine.
  Build objects before branching.
