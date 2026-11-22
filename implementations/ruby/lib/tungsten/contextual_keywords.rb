# frozen_string_literal: true

module Tungsten
  # `fn` and `on` are contextual keywords, mirroring contextual_keyword_at?
  # in languages/tungsten/lexers/regex_helpers.w: a keyword only where its
  # grammar applies, an identifier everywhere else. (`go` is an identifier
  # in this implementation, which has no `go -> body` spawn.)
  #   fn  `fn name(...)`: blanks and then a name follow.
  #   on  `on TARGET (with CAP)*` + indented body: it opens a statement, a
  #       target (a name after blanks, `(` or `!`) follows, the rest of the
  #       line is target syntax or a comment, and the next code line is
  #       indented deeper and does not start with `.`.
  # Neither is a keyword after `.`/`&.`; the lexers check that and statement
  # start. `src` is the source String, `start`/`finish` byte offsets.
  class ContextualKeywords
    def self.contextual?(word)
      word == "fn" || word == "on"
    end

    def self.keyword_at?(word, src, start, finish, statement_start)
      return fn_at?(src, finish) if word == "fn"
      return statement_start && on_at?(src, start, finish) if word == "on"

      true
    end

    def self.blank?(byte)
      byte == 32 || byte == 9
    end

    def self.name_start?(byte)
      !byte.nil? && ((byte >= 97 && byte <= 122) || (byte >= 65 && byte <= 90) || byte == 95)
    end

    def self.target_byte?(byte)
      name_start?(byte) || (byte >= 48 && byte <= 57) || blank?(byte) ||
        byte == 40 || byte == 41 || byte == 33 || byte == 38 || byte == 124
    end

    def self.skip_blanks(src, pos)
      while pos < src.bytesize && blank?(src.getbyte(pos))
        pos += 1
      end
      pos
    end

    def self.skip_to_newline(src, pos)
      while pos < src.bytesize && src.getbyte(pos) != 10
        pos += 1
      end
      pos
    end

    def self.fn_at?(src, finish)
      pos = skip_blanks(src, finish)
      pos > finish && name_start?(src.getbyte(pos))
    end

    def self.on_at?(src, start, finish)
      len = src.bytesize
      pos = skip_blanks(src, finish)
      return false if pos >= len

      first = src.getbyte(pos)
      return false unless first == 40 || first == 33 || (pos > finish && name_start?(first))

      while pos < len && src.getbyte(pos) != 10
        byte = src.getbyte(pos)
        if byte == 35
          pos = skip_to_newline(src, pos)
          break
        end
        return false unless target_byte?(byte)

        pos += 1
      end
      on_body_follows?(src, start, pos + 1)
    end

    # The next line with code on it is indented deeper than the line holding
    # `start` and does not start with `.`.
    def self.on_body_follows?(src, start, from)
      line = start
      while line > 0 && src.getbyte(line - 1) != 10
        line -= 1
      end
      indent = skip_blanks(src, line) - line
      q = from
      while q < src.bytesize
        r = skip_blanks(src, q)
        return false if r >= src.bytesize

        byte = src.getbyte(r)
        if byte == 10 || byte == 35
          q = skip_to_newline(src, r) + 1
          next
        end
        return r - q > indent && byte != 46
      end
      false
    end
  end
end
