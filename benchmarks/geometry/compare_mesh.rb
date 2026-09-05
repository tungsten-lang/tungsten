# Compare a historical mesh implementation to current source using the same
# compiler and current shared dependencies. Generated files stay in a tempdir.
require 'open3'
require 'tmpdir'
require 'json'

root = File.expand_path('../..', __dir__)
revision = ARGV.fetch(0, '68b485e')
sizes = ARGV.drop(1).map { |n| Integer(n) }
sizes = [100, 200, 400] if sizes.empty?
abort 'grid sizes must be positive' unless sizes.all?(&:positive?)
baseline, status = Open3.capture2('git', 'show', "#{revision}:core/geometry/mesh.w", chdir: root)
abort 'cannot read baseline mesh source' unless status.success?
# Preserve the historical algorithms while accepting main's renamed inline
# integer class. No storage, topology, or arithmetic code is substituted.
baseline = baseline.gsub('name == "Integer" || name == "BigInt"',
                         'name == "Integer" || name == "Int" || name == "BigInt"')
baseline = baseline.gsub('name != "Integer" && name != "BigInt"',
                         'name != "Integer" && name != "Int" && name != "BigInt"')
source = File.read(File.join(__dir__, 'mesh_build.w'))
compiler = ENV.fetch('GEOMETRY_COMPILER', File.join(root, 'bin/tungsten'))
results = []
Dir.mktmpdir('geometry-benchmark-') do |dir|
  binaries = {}
  { 'baseline' => source.sub('use core/geometry/mesh', baseline), 'current' => source }.each do |name, code|
    path = File.join(dir, "#{name}.w")
    File.write(path, code)
    binary = File.join(dir, name)
    output, compile_status = Open3.capture2e({ 'TUNGSTEN_ROOT' => root }, compiler, 'compile', path, '--out', binary, chdir: root)
    abort output unless compile_status.success?
    binaries[name] = binary
  end
  sizes.each do |n|
    %w[input mesh topology].each do |mode|
      binaries.each do |name, binary|
        environment = { 'GEOMETRY_GRID_N' => n.to_s, 'GEOMETRY_BENCH_MODE' => mode }
        stdout, stderr, run_status = Open3.capture3(environment, '/usr/bin/time', '-l', binary, chdir: root)
        abort "#{name}: #{stdout}\n#{stderr}" unless run_status.success?
        result = { version: name, baseline_revision: revision, baseline_int_alias: true, grid: n, mode: mode,
                   faces: 2*n*n, build_ms: Float(stdout[/build_ms=(\S+)/, 1]),
                   peak_rss_bytes: Integer(stderr[/\s(\d+)\s+maximum resident set size/, 1]) }
        results << result
        puts JSON.generate(result)
      end
    end
  end
end
