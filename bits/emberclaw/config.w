+ Config
  rw :data

  -> new(file)
    @data = parse(file)

  -> parse(file)
    content = read(file)  # Assuming read available
    # Simple parse: assume key=value lines
    hash = {}
    content.lines.each ->(line)
      if line =~ /(.+)=(.+)/
        hash[$1.trim.to_sym] = $2.trim
    hash
