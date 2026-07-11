# Native sci I/O round-trips (forces sci_io_native via @w_sci_).
# Also touch blas so current compilers link blas_bridge (WTensor dual-home).
# Run: bin/tungsten -o /tmp/io_nat spec/sci/io_native_spec.w && /tmp/io_nat

use core/io

vals = [~1.0, ~2.0, ~3.5, ~-4.0]

# ---- NetCDF classic ----
npath = "/tmp/tungsten_nc_smoke.nc"
SciIO.write_netcdf_f32(npath, vals)
nd = SciIO.read_netcdf_f32(npath)
<< nd[0]
<< nd[2]
<< nd[3]

# ---- HDF5-signature + TH5C body ----
hpath = "/tmp/tungsten_h5_smoke.h5"
SciIO.write_hdf5_f32(hpath, vals)
sb = ccall("w_sci_hdf5_superblock", hpath)
<< sb[0]
hd = SciIO.read_hdf5_f32(hpath)
<< hd[0]
<< hd[3]

# sniff
<< SciIO.sniff(npath)[:format]
<< SciIO.sniff(hpath)[:format]

ok = nd[0] == ~1.0 && nd[2] == ~3.5 && hd[1] == ~2.0 && hd[3] == ~-4.0
if ok
  << "IO_NATIVE_OK"
else
  << "IO_NATIVE_FAIL"
