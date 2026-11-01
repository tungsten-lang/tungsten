# Resolve the authored clock without creating build directories or running generators.
use ../../../../apps/studio/lib/base
use ../../../../apps/studio/lib/resolve
args = argv()
episode = JSON.parse(File.read(args[0]))
# Planning needs a recipe token for duration-based program shots but never runs
# a generator. Dynamic counts/captions must be authored or prepared explicitly.
sections = [episode]
episode["cuts"].keys.each ->(key)
  sections.push(episode["cuts"][key])
sections.each ->(section)
  if section["shots"] != nil
    section["shots"].each ->(shot)
      if shot["kind"] == "program"
        shot["source_sha"] = "av-plan:" + Crypto.sha256(JSON.encode(shot["program"]))
        shot["program_dur"] = JSON.encode(shot["program"]["run"]).include?("{dur}")
resolved = Resolver.new(episode, args[1], {}, {}, {}).resolve
<< JSON.encode(resolved)
