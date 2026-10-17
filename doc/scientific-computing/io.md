# Scientific I/O (`core/io`)

**No system libhdf5 / libnetcdf / Arrow.** In-tree C in `runtime/sci_io_native.c`.

## What is TH5? (honest answer)

**TH5 is not full HDF5.** It is a **Tungsten-native** binary layout that:

1. Starts with the standard **8-byte HDF5 signature** (`\x89HDF\r\n\x1a\n`) so
   tools that only sniff the magic may call the file “HDF5-like”.
2. Then stores a **simple Tungsten payload**, not an HDF5 object header /
   B-tree / fractal heap / filter pipeline.

| Tag | Meaning | Layout after 16-byte stub |
|-----|---------|---------------------------|
| **TH5C** | Tungsten HDF5 **C**ontiguous — one anonymous f32 array | `"TH5C"` + u32 LE nelem + nelem×f32 LE |
| **TH5D** | Tungsten HDF5 multi-**D**ataset — named f32 arrays | `"TH5D"` + u32 n + repeated (name_len, name, nelem, f32 data) |

**What we did implement**

- Superblock/signature **sniff** (`hdf5_superblock`)
- **Write/read TH5C** single anonymous f32 vector
- **Write/list/read TH5D** multi-named f32 datasets
- Round-trip **our** writers ↔ **our** readers

**Current native foreign-reader subset**

`runtime/sci_io_native.c` also walks foreign HDF5 object headers for a limited
contiguous numeric subset, including endian conversion. It does not implement
a general chunk/filter reader. TH5C/TH5D writers remain Tungsten-specific.

**Standard-format interchange (`core/io/interop`)**

Explicitly import `core/io/interop` for pure-Tungsten standard HDF5, Apache
Parquet, and Apache Arrow IPC file reading and writing with zero external
Python or C library dependencies. `SciIO.read_hdf5_dataset` returns
shape/dtype/values/attribute records (including compressed chunked datasets,
endian conversion, and attributes); `SciIO.write_hdf5_standard` writes genuine
HDF5 readable by independent tools (`h5py`, etc.). The same module provides
`SciIO.read_parquet_standard`, `SciIO.write_parquet_standard`,
`SciIO.read_arrow_ipc`, and `SciIO.write_arrow_ipc`, including nulls,
dictionary-encoded pages, and schema/field metadata. See
[the contract and tests](../../experiments/science-interop/README.md).
TPAR and TH5C/TH5D remain separate lightweight formats in `core/io`.

## Format status

| Format | Status |
|--------|--------|
| CSV | pure Tungsten read/write |
| FITS | header + BE f32 image unpack |
| Zarr | write/read 1-D f32 uncompressed (`.zarray` + chunk `0`) |
| MATLAB `.mat` | Level-5 text header sniff |
| NetCDF classic | 1-D f32 write/read (classic CDF layout, not NetCDF-4/HDF5) |
| **TH5C / TH5D** | Tungsten contiguous f32 (see above) — **not** full HDF5 |
| Parquet **TPAR** | PLAIN f32 columns (Tungsten simple footer; not full Thrift) |
| safetensors | via MLX / llama (ML weights) |

```
use core/io
SciIO.write_hdf5_datasets("/tmp/x.h5", ["a","b"], [va, vb])  # TH5D
<< SciIO.hdf5_list("/tmp/x.h5")
<< SciIO.hdf5_read("/tmp/x.h5", "a")
SciIO.write_parquet_f32("/tmp/t.parquet", ["col"], [vals])   # TPAR
SciIO.write_zarr_f32("/tmp/z", vals)
<< SciIO.read_zarr_f32("/tmp/z")
```

Linked when IR references `@w_sci_`.
