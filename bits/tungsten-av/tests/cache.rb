# Exercise the generic native companion source/header invalidation contract.
require "tmpdir"
require "open3"
require "json"
ROOT = File.realpath(File.join(__dir__, "../../.."))
Dir.mktmpdir("av-native-cache-") do |temporary|
  root = File.join(temporary, "with spaces")
  Dir.mkdir(root)
  File.write(File.join(root, "Bitfile"), "name \"cache-fixture\"\nincludes [\"bridge.c\"]\n")
  File.write(File.join(root, "bridge.h"), "#define ANSWER 1\n")
  File.write(File.join(root, "bridge.c"), "#include \"runtime.h\"\n#include \"wvalue.h\"\n#include \"bridge.h\"\nWValue fixture_answer(void) { return w_int(ANSWER); }\n")
  File.write(File.join(root, "main.w"), "<< ccall(\"fixture_answer\")\n")
  run = lambda do
    out, err, status = Open3.capture3({"BASH_ENV" => nil}, File.join(ROOT, "bin/tungsten"), File.join(root, "main.w"), chdir: ROOT)
    raise "native cache fixture failed: #{out}\n#{err}" unless status.success?
    Integer(out.strip)
  end
  raise "initial C result" unless run.call == 1
  File.write(File.join(root, "bridge.h"), "#define ANSWER 2\n")
  raise "stale C header cache" unless run.call == 2
  File.open(File.join(root, "bridge.c"), "a") { |f| f.puts "/* source changed */" }
  raise "source rebuild failed" unless run.call == 2
  duplicate_env = {"BASH_ENV" => nil, "TUNGSTEN_C_INCLUDES" => File.join(root, "bridge.c")}
  out, err, status = Open3.capture3(duplicate_env, File.join(ROOT, "bin/tungsten"), File.join(root, "main.w"), chdir: ROOT)
  raise "duplicate inherited companion: #{out}\n#{err}" unless status.success? && out.strip == "2"
  puts "PASS native companion source/header invalidation, inherited deduplication and spaces in paths"
end
