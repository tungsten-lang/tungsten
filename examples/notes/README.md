# Tungsten Notes: first complete example (item 29)

Run from the repository root:

```sh
python3 scripts/run-notes-demo.py
```

To include standard HDF5, Parquet and Arrow outputs, use the optional environment
from `experiments/science-interop/requirements.txt`:

```sh
python3 scripts/run-notes-demo.py --science-python build/venv-science/bin/python
```

The runner prints a new run directory's manifest and `.tnotes` document, then
opens the document in the native macOS Notes prototype. `--no-open` keeps the
same verification workflow without opening a window. It requires Node,
LLVM clang/wasm-ld and the macOS Swift toolchain.

The example:

1. Computes `(x+1)^2` at 21 integer inputs in compiled Tungsten and renders a
   custom object's `to_notes` table, line plot and small-matrix result.
2. Builds the same typed numerical source for WASM and runs it in Node.
3. Checks every native/WASM value against an independent integer reference.
4. Optionally writes genuine HDF5, Parquet and Arrow IPC files and reopens each
   with an independent h5py/PyArrow check.
5. Adds a **finite checked** certificate block only after those checks pass,
   validates the document using the native app decoder, and opens it.

The certificate is about those 21 samples. It does not claim a general theorem,
proof-kernel verification, performance improvement or cross-GPU parity.
`verification-example.json` records the initially checked finite evidence.

Each run has a unique directory beneath `build/cache/notes-demo/runs`, with the
native binary, WASM/LLVM, data outputs, producer/final Notes documents, stdout /
stderr, commands/timings, tool versions, source/compiler/output hashes,
verification evidence and terminal manifest. Failures retain their outputs and
an explicit failed status. No run overwrites a previous run.

This is the first concrete sample of item 22's proposed recorder, with a
limited provenance scope: entry/key source hashes, Git state, tool/binary
identity and output hashes. It is not a hermetic archive of the complete
Core/runtime/toolchain dependency graph. Live cells, async kernel transport,
rich artifact blocks and replay controls inside the app remain future work.
