# frozen_string_literal: true

module Tungsten
  class Calendar
    attr_reader :key
    alias name key

    KEYS = {
      "sweden" => "sweden", "stockholm" => "sweden", "finland" => "sweden",
      "helsinki" => "sweden", "europe/stockholm" => "sweden", "europe/helsinki" => "sweden",
      "denmark" => "denmark", "norway" => "denmark", "copenhagen" => "denmark",
      "oslo" => "denmark", "europe/copenhagen" => "denmark", "europe/oslo" => "denmark",
      "denmark-norway" => "denmark",
      "britain" => "britain", "england" => "britain", "london" => "britain",
      "uk" => "britain", "gb" => "britain", "great britain" => "britain",
      "europe/london" => "britain",
      "rome" => "catholic", "italy" => "catholic", "spain" => "catholic",
      "portugal" => "catholic", "papal" => "catholic", "catholic" => "catholic",
      "europe/rome" => "catholic", "europe/madrid" => "catholic", "europe/lisbon" => "catholic",
      "amsterdam" => "amsterdam", "netherlands" => "amsterdam", "holland" => "amsterdam",
      "europe/amsterdam" => "amsterdam",
      "russia" => "russia", "moscow" => "russia", "petrograd" => "russia",
      "leningrad" => "russia", "europe/moscow" => "russia", "ussr" => "russia",
      "soviet" => "russia"
    }.freeze

    def self.at(name)
      key = KEYS[name.to_s.downcase]
      raise ArgumentError, "Date.in: unknown calendar '#{name}'" unless key
      new(key)
    end

    def initialize(key)
      @key = key
    end

    def to_s = "Calendar(#{@key})"
    alias inspect to_s

    def parse(string)
      d = Date.parse(string)
      raise ArgumentError, "Date.in('#{@key}'): #{d} is not a civil date in this jurisdiction" unless accepts?(d)
      d
    end

    def accepts?(d)
      y, m, day = d.year, d.month, d.day
      case @key
      when "sweden" then sweden_accepts(y, m, day)
      when "denmark" then denmark_accepts(y, m, day)
      when "britain" then britain_accepts(y, m, day)
      when "catholic" then catholic_accepts(y, m, day)
      when "amsterdam" then gregorian_day_ok(y, m, day)
      when "russia" then russia_accepts(y, m, day)
      else true
      end
    end

    private

    def sweden_accepts(y, m, day)
      return true if y == 1712 && m == 2 && day == 30
      return false if y == 1700 && m == 2 && day == 29
      return false if y == 1753 && m == 2 && day.between?(18, 28)
      gregorian_after(y, m, day, 1753, 3, 1) ? gregorian_day_ok(y, m, day) : julian_day_ok(y, m, day)
    end

    def denmark_accepts(y, m, day)
      return false if y == 1700 && m == 2 && day.between?(19, 29)
      gregorian_after(y, m, day, 1700, 3, 1) ? gregorian_day_ok(y, m, day) : julian_day_ok(y, m, day)
    end

    def britain_accepts(y, m, day)
      return false if y == 1752 && m == 9 && day.between?(3, 13)
      gregorian_after(y, m, day, 1752, 9, 14) ? gregorian_day_ok(y, m, day) : julian_day_ok(y, m, day)
    end

    def catholic_accepts(y, m, day)
      return false if y == 1582 && m == 10 && day.between?(5, 14)
      gregorian_after(y, m, day, 1582, 10, 15) ? gregorian_day_ok(y, m, day) : julian_day_ok(y, m, day)
    end

    def russia_accepts(y, m, day)
      return false if y == 1918 && m == 2 && day.between?(1, 13)
      gregorian_after(y, m, day, 1918, 2, 14) ? gregorian_day_ok(y, m, day) : julian_day_ok(y, m, day)
    end

    def gregorian_after(y, m, day, y0, m0, d0)
      y > y0 || (y == y0 && (m > m0 || (m == m0 && day >= d0)))
    end

    def gregorian_day_ok(y, m, day)
      return false if y == 1712 && m == 2 && day == 30
      return false if m == 2 && day == 29 && (y % 100).zero? && (y % 400) != 0
      true
    end

    def julian_day_ok(y, m, day)
      !(y == 1712 && m == 2 && day == 30)
    end
  end
end
