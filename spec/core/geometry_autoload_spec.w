# Deliberately no feature import: exercise class and facade autoload order.
raise "FAIL measure autoload" if EuclideanMeasure.validate_dimension(2) != 2
mesh = TriangleMesh.new([[0,0], [1,0], [0,1]], [[0,1,2]])
raise "FAIL mesh autoload" if mesh.orientable_genus != 0
report = TriangleMeshTopology.new(mesh)
raise "FAIL topology autoload" if report.edge_faces(0) != [0]
raise "FAIL predicate autoload" if GeometryPredicates.orient2d([0,0], [1,0], [0,1]) != 1
raise "FAIL facade after mesh" if Geometry.triangle_mesh(mesh.vertices, mesh.faces).orientable_genus != 0
raise "FAIL smooth coexistence" if Geometry.chart([:x, :y]).dimension != 2
raise "FAIL transitive integer helper" if !Integer.value?(281474976710656)
<< "geometry_autoload_spec: all checks passed"
