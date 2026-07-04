in Tungsten

+ Token
  rw :type, default: :EOF
  rw :value
  rw :file

  rw :row, :col, default: 0

  rw :location, default: -> Location.new(file, row, col)

  -> to_s
    ["<[type]", "[value]>".strip].join(' ')
