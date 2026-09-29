# respond_to? finds a method by String name but not by Symbol:
# `q.respond_to?(:components)` is false for a Quaternion.
q = Quaternion<f64>.new([~1.0, ~2.0, ~3.0, ~4.0] ## f64[4])
<< "string: expect true, got " + q.respond_to?("components").to_s
<< "symbol: expect true, got " + q.respond_to?(:components).to_s
