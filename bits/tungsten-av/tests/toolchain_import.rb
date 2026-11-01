require "tmpdir"
require "open3"
require "fileutils"
ROOT = File.realpath(File.join(__dir__, "../../.."))
Dir.mktmpdir("av-native-import-") do |root|
  File.write(File.join(root, "Bitfile"), "name \"foreign-project\"\n")
  Dir.mkdir(File.join(root, "bits"))
  source = File.join(root, "command.w")
  File.write(source, <<~W)
    use bit/command
    + ForeignCommand < Tungsten:Bit:Command
      -> execute
        << option(:mode)
        << @raw_args.size
    ForeignCommand.new(["--mode", "native"]).execute
  W
  driver = File.join(ROOT, "bin/tungsten")
  transcripts = []
  engines = [[], ["run", "--interpret"]]
  engines << ["--ruby"] if ENV["RUN_RUBY_PARITY"] == "1"
  engines.each do |prefix|
    out, err, status = Open3.capture3({"BASH_ENV" => nil, "BIT_HOME" => File.join(root, "empty-registry"), "TUNGSTEN_CACHE_DIR" => File.join(ROOT, "build/cache")}, driver, *prefix, source, chdir: root)
    raise "bundled bit import #{prefix}: #{out}\n#{err}" unless status.success?
    transcripts << out
  end
  raise "bundled import engine mismatch" unless transcripts.uniq == ["native\n2\n"]
  puts "PASS bundled Bit:Command imports from a foreign project on selected engines"
end
