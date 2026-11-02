require "tmpdir"
require "json"
require "open3"
ROOT = File.realpath(File.join(__dir__, "../../.."))
Dir.mktmpdir("av-native-library-") do |root|
  File.write(File.join(root, "Bitfile"), "requires [\"tungsten-av\"]\nav.project \"library-import\", source: \"source.mov\", toolchain: #{ROOT.to_json}\n")
  File.write(File.join(root, "main.w"), <<~W)
    use av
    project = Av:Project.load(".")
    << project.name
    << project.profiles.keys.join(",")
  W
  out, err, status = Open3.capture3({"BASH_ENV" => nil, "BIT_HOME" => File.join(root, "empty-registry"), "TUNGSTEN_CACHE_DIR" => File.join(ROOT, "build/cache")}, File.join(ROOT, "bin/tungsten"), File.join(root, "main.w"), chdir: root)
  raise "native library import: #{out}\n#{err}" unless status.success? && out == "library-import\nmaster\n"
  raise "import wrote project artifacts" if File.exist?(File.join(root, ".av"))
  puts "PASS native AV library import and declared C companion from a foreign project"
end
