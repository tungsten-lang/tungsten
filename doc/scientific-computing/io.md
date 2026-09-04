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

**Optional standard-format bridge**

Explicitly import `core/io/interop` and configure `TUNGSTEN_SCIENCE_PYTHON` with
h5py. `SciIO.read_hdf5_dataset` returns shape/dtype/values/attribute records;
`SciIO.write_hdf5_standard` writes genuine HDF5 readable by independent tools.
This supports compressed multidimensional datasets through h5py, with explicit
copy/size/type limits. See [the contract and test](../../experiments/science-interop/README.md).
The same optional import provides standard Parquet and Arrow IPC file methods,
including nulls and schema metadata. TPAR remains a separate native format.
Core's default native path still requires no system scientific I/O libraries.

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
