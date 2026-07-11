/* Scientific I/O native bridges (HDF5, NetCDF, Parquet, …).
 *
 * Strong implementations link when the corresponding system libraries
 * are present and the build passes this file in. Until then weak stubs
 * in runtime.c raise with install guidance.
 *
 * This file is intentionally a thin placeholder so the Tungsten SciIO
 * surface can compile against symbols; flesh out with libhdf5 / netcdf /
 * arrow as optional deps (pkg-config).
 */
#include "runtime.h"
#include "wvalue.h"

#if defined(TUNGSTEN_HAVE_HDF5)
#include <hdf5.h>
/* … real impls … */
#endif

/* When no native libs are compiled in, this TU can be empty — weak
 * stubs in runtime.c provide the symbols. */
