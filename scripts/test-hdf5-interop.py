#!/usr/bin/env python3
"""Independent h5py fixtures -> compiled Tungsten -> standard HDF5 -> h5py."""
import json
import os
from pathlib import Path
import subprocess
import h5py
import numpy as np
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'build/reports/hdf5-interop'
OUT.mkdir(parents=True,exist_ok=True)
foreign=OUT/'foreign.h5'
result=OUT/'written.h5'
result.unlink(missing_ok=True)
with h5py.File(foreign,'w',libver='latest') as file:
 d=file.create_dataset('nested/measurements',data=np.arange(24,dtype='>f8').reshape(2,3,4),chunks=(1,3,4),compression='gzip')
 d.attrs['unit']='kelvin';d.attrs['run']=17
 file['empty']=np.empty((0,3),dtype=np.float32)
 file['scalar']=np.array(42,dtype=np.int64)
 file['huge_integer']=np.array([2**63+9],dtype=np.uint64)
source=OUT/'roundtrip.w'
source.write_text('''use core/io/interop
record = SciIO.read_hdf5_dataset(ARGV[0], "nested/measurements")
if record["shape"] != [2, 3, 4] || record["values"][23] != ~23.0 || record["attributes"]["unit"] != "kelvin"
  raise "foreign shape/value/attribute mismatch"
empty = SciIO.read_hdf5_dataset(ARGV[0], "empty")
scalar = SciIO.read_hdf5_dataset(ARGV[0], "scalar")
big = SciIO.read_hdf5_dataset(ARGV[0], "huge_integer")
SciIO.write_hdf5_standard(ARGV[1], {"copied": record, "empty": empty, "scalar": scalar, "big": big})
rejected = false
begin
  SciIO.write_hdf5_standard(ARGV[1], {"again": scalar})
rescue error
  rejected = true
if !rejected
  raise "existing destination overwritten"
<< "PASS"
''')
def run(args):
 p=subprocess.run([str(a) for a in args],cwd=ROOT,text=True,capture_output=True,timeout=90,
  env={**os.environ,'TUNGSTEN_SCIENCE_PYTHON':str(ROOT/'build/venv-science/bin/python')})
 assert p.returncode==0,p.stdout+p.stderr
 return p.stdout
run([ROOT/'bin/tungsten-compiler','compile',source,'--out',OUT/'roundtrip','--no-lto'])
assert 'PASS' in run([OUT/'roundtrip',foreign,result])
with h5py.File(result,'r') as file:
 np.testing.assert_array_equal(file['copied'][:],np.arange(24).reshape(2,3,4))
 assert file['copied'].attrs['unit']=='kelvin' and file['copied'].attrs['run']==17
 assert file['copied'].compression=='gzip'
 assert file['empty'].shape==(0,3) and file['empty'].dtype==np.dtype('float32')
 assert file['scalar'].shape==() and file['scalar'][()]==42
 assert file['big'][0]==2**63+9
print('PASS: independent compressed/big-endian HDF5, rank-3 shape, attributes, empty/scalar/uint64, no overwrite')
for record in [
 {'dtype':'float64','shape':[2],'values':[1]},
 {'dtype':'uint64','shape':[1],'values':[-1]},
 {'dtype':'float32','shape':[1],'values':[1e100]},
 {'dtype':'complex128','shape':[1],'values':[1]},
]:
 target=OUT/'invalid.h5'
 target.unlink(missing_ok=True)
 request=OUT/'request.json';response=OUT/'response.json'
 request.write_text(json.dumps({'version':1,'operation':'hdf5_write','path':str(target),'datasets':{'data':record}}))
 run([ROOT/'build/venv-science/bin/python',ROOT/'runtime/science_interop.py',request,response])
 assert json.loads(response.read_text())['ok'] is False
 assert not target.exists()
print('PASS: malformed shape, integer range, float overflow and unsupported dtype rejected before publication')
