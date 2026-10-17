# Native standard scientific interchange (`core/io/interop`)

Explicitly import `core/io/interop` for pure-Tungsten standard HDF5, Apache
Parquet, and Apache Arrow IPC **file** reading and writing. No external Python
worker, virtual environment, or C libraries (`libhdf5`, `libarrow`) are required
at runtime.

```w
use core/io/interop
record = SciIO.read_hdf5_dataset("input.h5", "measurements/temperature")
<< record["shape"]
SciIO.write_hdf5_standard("output.h5", {"temperature": record})
```

Dataset records contain `dtype`, `shape`, `order: "C"`, flat `values`, and
`attributes`. Standard HDF5 reading supports nested groups (v1 symbol-table
B-trees and v2 link messages), compact/contiguous/chunked layouts (v3 B-tree
and v4/v5 single-chunk or Fixed Array), `gzip` (DEFLATE) decompression, endian
conversion, rank-N/scalar/empty datasets, and scalar/string attributes (including
Global Heap variable-length UTF-8 strings). Writing produces standard HDF5 files
(Superblock v0, Object Header v1, contiguous or `gzip` chunked B-tree v1, and
attributes) readable by independent tools such as `h5py`. The supported values
are finite `float32`/`float64`, `int32`/`int64`, `uint32`/`uint64`, and `bool`.
Integer decimal strings are accepted losslessly to accommodate `BigInt` values.
Unsupported dtypes, nonfinite floats, inconsistent shapes, and out-of-range
integers are rejected before any file is written. Existing destination files are
never overwritten.

`uv run --with h5py --with numpy python3 scripts/test-hdf5-interop.py` checks
independent `h5py`-created compressed/big-endian files through a compiled
Tungsten program and reopens its standard HDF5 output with `h5py`. It covers
attributes, rank 3, empty/scalar values, `uint64` above `2^63`, no-overwrite,
and invalid records.

References: [HDF5 File Format Specification](https://docs.hdfgroup.org/hdf5/latest/_f_m_t3.html).

## Parquet and Arrow IPC (item 20)

The same explicit import provides `SciIO.read_parquet_standard(path)` /
`write_parquet_standard(path, table)` and `read_arrow_ipc(path)` /
`write_arrow_ipc(path, table)`. These read and write standard Apache Parquet
(Thrift Compact Protocol footer, `PLAIN` and `RLE_DICTIONARY`/`PLAIN_DICTIONARY`
pages, RLE/bit-packed hybrid definition levels, `UNCOMPRESSED` and `GZIP`
compression, and `ARROW:schema` metadata preservation) and Apache Arrow IPC
**file** format (`ARROW1` framing + FlatBuffers `Schema`, `RecordBatch`, and
`Footer`); the old `TPAR` functions in `core/io` are unchanged.

A table record contains ordered `columns`, `rows`, and `metadata_base64`.
Each column has `name`, `dtype`, `nullable`, `values` (`nil` represents null),
and `metadata_base64`. Schema/field metadata bytes are base64-encoded so
arbitrary binary metadata survives round-trips. Numeric types above plus UTF-8
strings are supported; dictionary-encoded Parquet reads normalize to their value
type. Column lengths, nullability, numeric ranges, and UTF-8 string control
characters are validated before writing.

`uv run --with pyarrow python3 scripts/test-columnar-interop.py` independently
creates dictionary/compressed Parquet with PyArrow, passes it through compiled
Tungsten into both Parquet and Arrow IPC formats, then reads Arrow IPC through
Tungsten and writes Parquet again. PyArrow verifies exact values, schema,
field/table metadata, nulls, Unicode, and large `uint64`, as well as rejection
of invalid nullability and mismatched column lengths.

References: [Apache Parquet Format](https://parquet.apache.org/docs/file-format/),
[Apache Arrow Columnar Format](https://arrow.apache.org/docs/format/Columnar.html).
