# A finite numerical sample shared by native Tungsten, WASM and Notes.
use core/notes
use core/io/interop
use ../../experiments/wasm/kernels

+ NotesPolynomialSample
  -> new(@rows)
  -> to_notes
    Notes.table(["x", "(x + 1)²"], @rows)

rows = []
points = []
flat = []
xs = []
ys = []
x = -10 ## i64
started = clock()
while x <= 10
  y = polynomial(x) ## i64
  rows.push([x, y])
  points.push([x.to_f(), y.to_f()])
  flat.push(x.to_f())
  flat.push(y.to_f())
  xs.push(x)
  ys.push(y)
  x += 1
elapsed = clock() - started

# Exercise caller-owned small-matrix output while preserving both inputs.
a = Mat3<f64>.identity
b = Mat3<f64>.identity
out = Mat3<f64>.zero
a.add_into(b, out)
if out.trace() != ~6.0 || a.trace() != ~3.0
  raise "matrix output/source check failed"

blocks = [
  Notes.text("Native Tungsten computed 21 integer samples. The run recorder checks each sample against WebAssembly and an independent integer reference."),
  Notes.render(NotesPolynomialSample.new(rows)),
  Notes.line_plot(points),
  Notes.table(["operation", "result"], [["Mat3 reusable-output addition trace", out.trace()], ["native sample loop seconds", elapsed]])
]
Notes.write(ARGV[0] + "/producer.tnotes", "One experiment, inspectable results", blocks)

if env("TUNGSTEN_SCIENCE_PYTHON") != nil
  SciIO.write_hdf5_standard(ARGV[0] + "/samples.h5", {
    "samples": {dtype: "float64", shape: [21, 2], values: flat, attributes: {formula: "(x + 1)^2"}}
  })
  table = {rows: 21, columns: [
    {name: "x", dtype: "int64", nullable: false, values: xs},
    {name: "y", dtype: "int64", nullable: false, values: ys}
  ]}
  SciIO.write_parquet_standard(ARGV[0] + "/samples.parquet", table)
  SciIO.write_arrow_ipc(ARGV[0] + "/samples.arrow", table)
<< "Produced 21 samples"
