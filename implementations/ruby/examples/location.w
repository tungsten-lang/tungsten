in Tungsten

+ Location
  is Comparable

  ro :file, :row, :col

  -> new(@file, @row, @col)

  -> dir
    File.dirname(file)

  -> between?
    min <= self <= max

  -> inspect
    to_s

  -> to_s
    "[file]:[row]:[col]"

  -> <=>/1
    return nil unless file == @1.file

    [row, col] <=> [@1.row, @1.col]
