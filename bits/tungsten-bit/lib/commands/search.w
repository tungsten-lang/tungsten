# bit search — search the registry for bits
in Tungsten:Bit:Commands

+ Search < Command
  -> summary
    "Search bits.tungsten-lang.org for bits"

  -> usage
    "USAGE\n  bit search QUERY (options)\n\nOPTIONS\n      --registry URL    Registry to search\n  -l, --limit NUM       Max results\n      --sort FIELD      Sort by relevance, downloads, recent\n      --json            Output as JSON\n"

  -> execute
    query = .args.join(" ")
    abort "Please provide a search query" if query.empty?

    registry = option(:registry, default_bit_source())
    client = Registry:Client.new(registry)

    results = client.search(
      query,
      option(:limit, 25) |> self.to_i,
      option(:sort, "relevance")
    )

    if results.empty?
      say "No bits found matching '" + query + "'"
      return

    if flag?(:json)
      say results |> JSON.encode
      return

    names = unique_bit_names(results)
    say "Found " + names.size().to_s + " bits:\n"
    names.each -> (name)
      versions = bits_named(results, name)
      bit = latest_bit(versions)
      line = "  " + name + " (" + version_list(versions) + ")"
      if versions.size() > 1
        line = line + " " + versions.size().to_s + " versions"
      say line
      if bit != nil && bit.summary != nil && bit.summary != ""
        say "    " + bit.summary + "\n"
