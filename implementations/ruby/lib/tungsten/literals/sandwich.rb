# frozen_string_literal: true

module Tungsten
  # Tungsten::Sandwich — produced by `peanutbutter + jelly` arithmetic.
  # Renders a colored ASCII PB&J sandwich. Easter egg: see Quantity#+.
  class Sandwich
    BREAD = "\e[38;5;179m"   # golden tan
    PB    = "\e[38;5;130m"   # peanut-butter brown
    JELLY = "\e[38;5;93m"    # grape purple
    TITLE = "\e[1;38;5;220m" # bold gold
    NOTE  = "\e[38;5;213m"   # bright pink for ♫
    RESET = "\e[0m"

    def to_s
      [
        "",
        "       #{BREAD}╭───────────────────────╮#{RESET}",
        "       #{BREAD}│░░░░░░░░ B R E A D ░░░░│#{RESET}",
        "       #{BREAD}╰───────────────────────╯#{RESET}",
        "       #{PB}▓▓▓▓ PEANUT  BUTTER ▓▓▓▓#{RESET}",
        "       #{PB}▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓#{RESET}",
        "       #{JELLY}▒▒▒▒▒ GRAPE  JELLY ▒▒▒▒▒#{RESET}",
        "       #{JELLY}▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒#{RESET}",
        "       #{BREAD}╭───────────────────────╮#{RESET}",
        "       #{BREAD}│░░░░░░░░ B R E A D ░░░░│#{RESET}",
        "       #{BREAD}╰───────────────────────╯#{RESET}",
        "",
        "    #{NOTE}♫#{RESET} #{TITLE}It's peanut butter jelly time!#{RESET} #{NOTE}♫#{RESET}",
        "",
      ].join("\n")
    end

    def inspect
      to_s
    end
  end
end
