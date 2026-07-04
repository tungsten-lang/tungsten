module Tungsten
  class Location
    include Comparable

    attr_reader(*%i[file row col])

    def initialize(file, row, col)
      @file = file
      @row = row
      @col = col
    end

    def dir
      File.dirname(file)
    end

    def between?(min, max)
      return false unless min && max

      min <= self && self <= max
    end

    def inspect
      to_s
    end

    def to_s
      (file ? file : "(script)") + ":" + row.to_s + ":" + col.to_s
    end

    def <=>(obj)
      return nil unless file == obj.file

      row_order = row <=> obj.row
      return row_order unless row_order == 0

      col <=> obj.col
    end
  end
end
