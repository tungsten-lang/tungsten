# Differential audit of the packed topology against the previous link-graph
# implementation. Compare unchanged reports; orientability/genus changes have
# their own constructive/nonorientable fixtures in geometry_mesh_spec.w.
require 'open3'
require 'tmpdir'

root = File.expand_path('../..', __dir__)
revision = ARGV.fetch(0, '68b485e')
baseline, status = Open3.capture2('git', 'show', "#{revision}:core/geometry/mesh.w", chdir: root)
abort 'cannot read baseline mesh source' unless status.success?
baseline = baseline.gsub('name == "Integer" || name == "BigInt"',
                         'name == "Integer" || name == "Int" || name == "BigInt"')
baseline = baseline.gsub('name != "Integer" && name != "BigInt"',
                         'name != "Integer" && name != "Int" && name != "BigInt"')
compiler = ENV.fetch('GEOMETRY_COMPILER', File.join(root, 'bin/tungsten'))
rng = Random.new(73921)
cases = 500.times.map do
  count = rng.rand(3..10)
  faces = Array.new(rng.rand(0..22)) { (0...count).to_a.sample(3, random: rng) }
  [(0...count).map { |i| [i, 0] }, faces]
end
program = "cases = #{cases.inspect}\n"
program += <<~W
  cases.each -> (entry)
    mesh = TriangleMesh.new(entry[0], entry[1])
    top = mesh.topology
    << [top.edges, top.boundary_edges, top.nonmanifold_edges,
        top.orientation_conflicts, top.duplicate_face_groups,
        top.isolated_vertices, top.nonmanifold_vertices,
        top.connected_component_count, top.surface_component_count,
        top.euler_characteristic, top.boundary_component_count,
        top.combinatorial_manifold?, top.consistently_oriented?, top.closed?]
W
Dir.mktmpdir('geometry-topology-oracle-') do |dir|
  outputs = {}
  { baseline: baseline, current: 'use core/geometry/mesh' }.each do |name, imports|
    path = File.join(dir, "#{name}.w")
    binary = File.join(dir, name.to_s)
    File.write(path, imports + "\n" + program)
    log, compiled = Open3.capture2e({ 'TUNGSTEN_ROOT' => root }, compiler, 'compile', path, '--out', binary, chdir: root)
    abort log unless compiled.success?
    outputs[name], ran = Open3.capture2(binary, chdir: root)
    abort "#{name} failed" unless ran.success?
  end
  old = outputs[:baseline].lines
  new = outputs[:current].lines
  abort 'incomplete corpus output' unless old.size == cases.size && new.size == cases.size
  old.zip(new).each_with_index do |(before, after), index|
    abort "case #{index}: #{cases[index].inspect}\nbefore: #{before}\nafter: #{after}" unless before == after
  end
end
puts "500 seeded meshes: all unchanged topology reports agree with #{revision}"
