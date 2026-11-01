in Av

+ Media
  ro :toolchain, :package, :runner
  -> new(@toolchain, @package, @runner)

  -> call(command, args = [])
    run = [@toolchain + "/bin/tungsten", @package + "/lib/media_worker.w", "--", command]
    args.each ->(a)
      run.push(a.to_s)
    text = @runner.run(run)["stdout"]
    lines = text.split("\n")
    while lines.size > 0
      line = lines.pop.strip
      if line != ""
        return JSON.parse(line)
    raise "native AV worker returned no result"

  -> capabilities
    call("capabilities")

  -> facts(path)
    call("facts", [path])

  -> probe(path)
    @runner.json(["ffprobe", "-v", "error", "-show_streams", "-show_format", "-of", "json", path])

  -> request(command, path, options, directory, destination = nil)
    File.mkdir_p(directory)
    request = directory + "/" + command + ".json"
    Util.json(request, {"source": path, "destination": destination, "options": options})
    call(command, [request])

  -> ffmpeg(args)
    run = ["ffmpeg", "-nostdin", "-hide_banner"]
    args.each ->(a)
      run.push(a.to_s)
    @runner.run(run)
