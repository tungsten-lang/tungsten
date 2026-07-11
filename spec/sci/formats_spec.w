# Native multi-format I/O: HDF5 multi-ds, Parquet PLAIN, Zarr, NetCDF.
# Run: bin/tungsten -o /tmp/fmts spec/sci/formats_spec.w && /tmp/fmts

use core/io

vals = [~1.25, ~2.5, ~-3.0]
vals2 = [~10.0, ~20.0]

# ---- HDF5 multi-dataset (TH5D) ----
SciIO.write_hdf5_datasets("/tmp/t_multi.h5", ["a", "b"], [vals, vals2])
names = SciIO.hdf5_list("/tmp/t_multi.h5")
<< names[0]
<< names[1]
a = SciIO.hdf5_read("/tmp/t_multi.h5", "a")
b = SciIO.hdf5_read("/tmp/t_multi.h5", "b")
<< a[0]
<< b[1]

# ---- Parquet PLAIN f32 (TPAR) ----
SciIO.write_parquet_f32("/tmp/t.parquet", ["col"], [vals])
c = SciIO.read_parquet_f32("/tmp/t.parquet", "col")
<< c[2]

# ---- Zarr uncompressed 1-D ----
SciIO.write_zarr_f32("/tmp/t_zarr", vals)
z = SciIO.read_zarr_f32("/tmp/t_zarr")
<< z[1]

# ---- NetCDF still works ----
SciIO.write_netcdf_f32("/tmp/t.nc", vals)
n = SciIO.read_netcdf_f32("/tmp/t.nc")
<< n[0]

ok = a[0] == ~1.25 && b[1] == ~20.0 && c[2] == ~-3.0 && z[1] == ~2.5 && n[0] == ~1.25
if ok
  << "FORMATS_OK"
else
  << "FORMATS_FAIL"
