# Optional standard scientific interchange

Install `requirements.txt` in a virtual environment and set
`TUNGSTEN_SCIENCE_PYTHON` to its Python executable. Explicitly import
`core/io/interop`; ordinary Core I/O never requires Python or these libraries.
The worker must remain beside the source installation at
`runtime/science_interop.py`; compiled applications must ship/configure that
installation and Python environment. This is a subprocess bridge, not a
zero-copy ABI or a throughput claim.

```w
use core/io/interop
record = SciIO.read_hdf5_dataset("input.h5", "measurements/temperature")
<< record["shape"]
SciIO.write_hdf5_standard("output.h5", {"temperature": record})
```

Dataset records contain `dtype`, `shape`, `order: "C"`, flat `values`, and
`attributes`. Standard HDF5 reading supports groups, gzip/chunks, endian
conversion, rank-N/scalar/empty datasets through h5py. Writing supports
uncompressed or gzip datasets, attributes and nested names. The supported
values are finite float32/64, int32/64, uint32/64, and bool. Integer decimal
strings are accepted losslessly to accommodate Core JSON's BigInt encoder.
Unsupported dtypes, nonfinite floats, inconsistent shapes and out-of-range
integers are rejected. Metadata values are preserved in the supported JSON
subset; original attribute storage dtypes and chunk layouts are not promised.

Protocol v1 is bounded to one million values per dataset and 64 MiB of JSON.
There are explicit copies/serialization, so use it as an interoperability
baseline. Larger datasets need a binary-buffer/streaming protocol. JSON is
passed through private temporary files and an argv-only child process; both
files are removed on normal completion or raised errors. Workers emit structured
errors. Successful writes publish a complete file and refuse existing targets.

`build/venv-science/bin/python scripts/test-hdf5-interop.py` checks independent
h5py-created compressed/big-endian files through a compiled Tungsten program
and reopens its standard HDF5 output with h5py. It covers attributes, rank 3,
empty/scalar values, uint64 above 2^63, no-overwrite, and invalid records.

References: [h5py datasets](https://docs.h5py.org/en/stable/high/dataset.html),
[h5py attributes](https://docs.h5py.org/en/stable/high/attr.html).
