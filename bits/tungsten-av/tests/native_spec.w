# spec: compiled -- package POSIX companion and media runtime are native APIs
use ../lib/av

+ Checks
  -> .assert(name, value)
    raise "FAIL [name]" if !value
    << "PASS [name]"

  -> .reject(name, code)
    rejected = false
    begin
      code.call
    rescue error
      rejected = true
    assert(name, rejected)

root = File.join(Env.get("TMPDIR") || "/tmp", "av-spec-" + Av:Util.id())
File.mkdir_p(root)
root = File.realpath(root)
begin
  parsed = Tungsten:Bit:Bitfile.literal_arguments("\"name\", unicode: \"א #𓀀\", rate: \[30000, 1001], yes: true, quality: 0.85")
  Checks.assert("literal unicode and exact rate", parsed[1]["unicode"] == "א #𓀀" && parsed[1]["rate"] == [30000, 1001])
  Checks.reject("reject executable expression", ->() Tungsten:Bit:Bitfile.literal_arguments("Process.exec(\[\"bad\"])"))
  Checks.reject("duplicate keys", ->() Tungsten:Bit:Bitfile.literal_arguments("name: 1, name: 2"))
  Checks.reject("nonfinite number", ->() Tungsten:Bit:Bitfile.literal_arguments("1e999"))
  Checks.reject("nesting bound", ->() Tungsten:Bit:Bitfile.literal_arguments("\[" * 20 + "0" + "]" * 20))
  Checks.assert("project names reject newline", !Av:Schema.name?("valid\ninvalid"))
  Checks.reject("bitrate rejects newline", -> Av:Schema.bitrate("1M\ninvalid"))
  Checks.assert("bitrate conversion", Av:Schema.bitrate("1.8M") == 1800000)
  Checks.reject("fractional bit per second", -> Av:Schema.bitrate("1.0001k"))
  base = "av.project \"fixture\", source: \"input.mov\"\n"
  File.write(root + "/Bitfile", base + "av.output \"share\", from: \"master\"\nav.output \"master\"\n")
  project = Av:Project.load(root)
  Checks.assert("topological profiles", project.profiles.keys == ["master", "share"])
  Checks.assert("native PCM defaults", project.profiles["master"]["audio"]["sample_format"] == "s24le")
  Checks.assert("selected dependencies", Av:Planner.selected(project.profiles, ["share"]).keys == ["master", "share"])
  File.write(root + "/Bitfile", base + "av.output \"one\", from: \"two\"\nav.output \"two\", from: \"one\"\n")
  Checks.reject("cyclic profiles", -> Av:Project.load(root))
  File.write(root + "/Bitfile", "av.project \"fixture\", source: \"input.mov\", workspace: \".git/cache\"\n")
  Checks.reject("workspace isolation", -> Av:Project.load(root))
  File.write(root + "/Bitfile", base + "av.video \"all\", codec: :h264, depth: 10\n")
  Checks.reject("codec depth conflict", -> Av:Project.load(root))
  File.write(root + "/Bitfile", base + "av.audio \"all\", channels: true\n")
  Checks.reject("boolean channels", -> Av:Project.load(root))
  File.write(root + "/report.txt", "controls: 7 rejected: 7\n")
  gates = [{"path": root + "/report.txt", "pattern": "controls: (\\d+) rejected: (\\d+)", "equal": [1, 2]}]
  Checks.assert("source gate capture equality", Av:QC.source_gates(gates)["ok"])
  File.write(root + "/report.txt", "controls: 7 rejected: 6\n")
  Checks.assert("source gate failure", !Av:QC.source_gates(gates)["ok"])
  Checks.assert("anomaly exemptions", Av:QC.uncovered(0, 10, [[0, 2], [4, 8], [7, 10]]) == [[2, 4]])
  File.write(root + "/captions.srt", "1\n00:00:00,100 --> 00:00:00,900\nHello\n")
  cues = Av:Text.captions(root + "/captions.srt")
  Checks.assert("subtitle timestamps", cues.size == 1 && cues[0]["start"] == ~0.1)
  font = "/System/Library/Fonts/Supplemental/Arial.ttf"
  if File.file?(font)
    Checks.assert("native font outlines", Av:Text.shape("Hello", font, 24)["paths"].size > 0)
    Checks.assert("native layout", Av:Text.layout(cues, {"size": 12, "minimum_size": 10}, 160, 90, font)["ok"])
    Checks.reject("font coverage rejects missing glyph", -> Av:Text.shape("𓀀", font, 24))
  budget = Av:Budget.new({"memory_mb": 512, "jobs": 64, "animation_jobs": 32}, 536870912, 16).choose(1920, 1080)
  Checks.assert("memory bounds workers", budget["jobs"] <= 2 && budget["animation_jobs"] <= budget["jobs"])
  Checks.reject("insufficient memory", -> Av:Budget.new({"memory_mb": 1}).choose(1920, 1080))
  File.write(root + "/input.mov", "old")
  snapshots = Av:Snapshots.new(root + "/inputs")
  sealed = snapshots.seal(root + "/input.mov")
  File.write(root + "/input.mov", "new")
  Checks.assert("immutable snapshots", File.read(sealed["path"]) == "old" && File.extname(sealed["path"]) == ".mov")
  File.write(root + "/main.w", "use helper\n<< helper()\n")
  File.write(root + "/helper.w", "-> helper\n  1\n")
  frozen = snapshots.tree([root + "/main.w"], root, root + "/trees")
  Checks.assert("local use graph frozen", frozen["records"].size == 2 && File.read(frozen["mapping"][root + "/main.w"]).include?(frozen["mapping"][root + "/helper.w"].slice(0, frozen["mapping"][root + "/helper.w"].size - 2)))
  File.mkdir_p(root + "/with spaces")
  File.write(root + "/with spaces/helper.w", "-> spaced_helper\n  7\n")
  File.write(root + "/quoted.w", "use \"with spaces/helper\"\n<< spaced_helper()\n")
  quoted = snapshots.tree([root + "/quoted.w"], root, root + "/trees")
  Checks.assert("quoted local use paths", quoted["mapping"].has_key?(root + "/with spaces/helper.w"))
  File.write(root + "/input.mov", "old")
  File.chmod(sealed["path"], 0o644)
  File.write(sealed["path"], "corrupt")
  Checks.reject("corrupt snapshot rejected", -> snapshots.seal(root + "/input.mov"))
  File.write(root + "/candidate", "verified")
  File.write(root + "/delivery", "legacy")
  entries = [{"source": root + "/candidate", "destination": root + "/delivery", "role": "master"}]
  verify = ->(path, entry, reports)
    {"ok": File.read(path) == "verified"}
  release = Av:Publisher.new(root + "/releases", verify).publish(entries, {})
  Checks.assert("atomic release", File.symlink?(root + "/delivery") && File.read(root + "/delivery") == "verified")
  reject = ->(path, entry, reports)
    {"ok": false}
  Checks.reject("bad candidate cannot activate", -> Av:Publisher.new(root + "/releases", reject).publish(entries, {}))
  Checks.assert("failed release preserves prior bytes", File.read(root + "/delivery") == "verified" && File.read(root + "/releases/current/manifest.json") == File.read(release + "/manifest.json"))
  runner = Av:Runner.new(1)
  Checks.assert("native argv preserves literals", runner.run(["/usr/bin/printf", "%s", "$(false) ; literal"])["stdout"] == "$(false) ; literal")
  Checks.reject("bounded stage deadline", -> runner.run(["/bin/sleep", "5"]))
ensure
  Av:Util.remove_tree(root)
