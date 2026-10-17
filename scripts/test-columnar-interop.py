#!/usr/bin/env python3
"""Independent PyArrow Parquet/Arrow fixtures -> compiled Tungsten (native SciIO) -> PyArrow."""
import os
from pathlib import Path
import subprocess
import pyarrow as pa
import pyarrow.parquet as pq
import pyarrow.ipc as ipc
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'build/reports/columnar-interop'
OUT.mkdir(parents=True,exist_ok=True)
schema=pa.schema([
 pa.field('measure',pa.float64(),metadata={b'unit':b'kelvin'}),
 pa.field('label',pa.string()),pa.field('big',pa.uint64()),pa.field('flag',pa.bool_(),nullable=False)
],metadata={b'run':b'17',b'binary':b'\x00\xff'})
table=pa.Table.from_arrays([pa.array([1.25,None,3.5]),pa.array(['α','',None]),
 pa.array([2**63+9,None,7],type=pa.uint64()),pa.array([True,False,True])],schema=schema)
pq.write_table(table,OUT/'foreign.parquet',compression='gzip',use_dictionary=True)
for name in ('written.parquet','written.arrow','from-arrow.parquet','bad.parquet'):
 (OUT/name).unlink(missing_ok=True)
source=OUT/'roundtrip.w'
source.write_text('''use core/io/interop
record = SciIO.read_parquet_standard(ARGV[0])
if record["rows"] != 3 || record["columns"][0]["values"][1] != nil
  raise "row/null mismatch"
SciIO.write_parquet_standard(ARGV[1], record)
SciIO.write_arrow_ipc(ARGV[2], record)
from_arrow = SciIO.read_arrow_ipc(ARGV[2])
SciIO.write_parquet_standard(ARGV[3], from_arrow)

bad_tables = [
  {columns: [{name: "x", dtype: "int64", values: [nil], nullable: false}]},
  {columns: [{name: "x", dtype: "int64", values: [1]}, {name: "y", dtype: "int64", values: []}]}
]
i = 0
while i < bad_tables.size
  rejected = false
  begin
    SciIO.write_parquet_standard(ARGV[4], bad_tables[i])
  rescue error
    rejected = true
  if !rejected
    raise "malformed table accepted"
  i += 1
<< "PASS"
''')
def run(args):
 env=dict(os.environ)
 env.pop('TUNGSTEN_SCIENCE_PYTHON',None)
 p=subprocess.run([str(a) for a in args],cwd=ROOT,text=True,capture_output=True,timeout=90,env=env)
 assert p.returncode==0,p.stdout+p.stderr
 return p.stdout
run([ROOT/'bin/tungsten-compiler','compile',source,'--out',OUT/'roundtrip','--no-lto'])
assert 'PASS' in run([OUT/'roundtrip',OUT/'foreign.parquet',OUT/'written.parquet',OUT/'written.arrow',OUT/'from-arrow.parquet',OUT/'bad.parquet'])
assert not (OUT/'bad.parquet').exists()
for name in ('written.parquet','from-arrow.parquet'):
 assert pq.read_table(OUT/name).equals(table,check_metadata=True)
with ipc.open_file(OUT/'written.arrow') as file:
 assert file.read_all().equals(table,check_metadata=True)
print('PASS: independent Parquet -> Tungsten -> Parquet/Arrow -> Tungsten -> Parquet; exact schema/metadata/null/uint64/unicode parity and invalid records')
