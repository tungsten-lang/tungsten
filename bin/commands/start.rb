# tungsten start — the first-run welcome: what Tungsten is, a map of the
# ecosystem, a runnable one-liner, and the right next step.
#
# This command deliberately lives on the Ruby-dispatch path (see bin/tungsten
# and bin/tungsten.rb) so it works on a fresh clone that has no compiled
# `bin/tungsten-compiler` yet — the one command a newcomer can always run.
#
# ROOT and HAVE_COMPILER are defined by bin/tungsten.rb (this file is `load`ed
# into that process, so those top-level constants are in scope).

require "rbconfig"
require "open3"

color  = $stdout.tty? && !ENV["NO_COLOR"]
bold   = color ? "\e[1m"  : ""
dim    = color ? "\e[2m"  : ""
cyan   = color ? "\e[36m" : ""
yellow = color ? "\e[33m" : ""
green  = color ? "\e[32m" : ""
reset  = color ? "\e[0m"  : ""

# --agent: the front door for AI coding agents. Emits the compact language
# primer itself (doc/TUNGSTEN_FOR_LLMS.md — inject it straight into context),
# then pointers to the deeper machine-oriented surfaces.
if ARGV.include?("--agent")
  primer = File.join(ROOT, "doc/TUNGSTEN_FOR_LLMS.md")
  puts File.read(primer) if File.exist?(primer)
  puts
  puts "More for agents:"
  puts "  stdlib index:  #{File.join(ROOT, "doc/CORE.md")}"
  puts "  MCP server:    #{File.join(ROOT, "bits/tungsten-lsp/bin/mcp-server.w")} (build: bin/tungsten build)"
  puts "  examples:      #{File.join(ROOT, "doc/examples")} (## expect blocks = machine-checked output)"
  puts "  web index:     https://tungsten-lang.org/llms.txt"
  exit
end

puts
puts "#{bold}#{cyan}W  Tungsten#{reset} #{dim}— pseudocode that runs#{reset}"
puts
puts "An object-oriented language that reads like the pseudocode in your"
puts "notebook. No ends, braces, colons, or return; blocks close by dedent."
puts

puts "#{bold}The map#{reset}"
puts "  #{yellow}Language#{reset}  write #{dim}.w#{reset} files; they compile to a native binary (@gpu fn -> Metal)"
puts "  #{yellow}REPL#{reset}      #{green}tungsten --repl#{reset}  -- an interactive playground (a.k.a. wit)"
puts "  #{yellow}bit#{reset}       the package manager: find, install, and test shared code"
puts "  #{yellow}Docs#{reset}      #{File.join("doc", "getting-started")}/  +  tungsten-lang.org"
puts

puts "#{bold}Try it now#{reset}"
puts "  #{green}bin/tungsten -e '<< 1 + 1'#{reset}   #{dim}#=> 2#{reset}"
puts "  #{dim}(more in the guide: currency, units, classes without the noise)#{reset}"
puts

# Tailor the next step to what actually exists on this machine.
if HAVE_COMPILER
  puts "#{bold}Next#{reset}"
  puts "  #{green}tungsten --repl#{reset}      explore interactively"
  puts "  #{green}tungsten new myapp#{reset}   scaffold a project"
else
  puts "#{bold}Next — build the compiler#{reset} #{dim}(a fresh clone ships without one)#{reset}"
  puts "  #{green}bin/tungsten build#{reset}"
  puts "  #{dim}or one-line install:#{reset} #{green}curl -fsSL tungsten-lang.org/install | sh#{reset}"
end
puts

puts "#{bold}Guide#{reset}  #{cyan}https://tungsten-lang.org/getting-started.html#{reset}"

# ── The 60-second tour (Decision 1A) ─────────────────────────────────────────
# Runs REAL snippets through the compiled engine. Gated three ways so it can
# never hang or lie: needs a TTY (piped/CI output stays static), needs the
# compiled binary (a fresh clone hasn't built one yet), and skips under CI=1.
if HAVE_COMPILER && $stdout.tty? && $stdin.tty? && ENV["CI"].nil?
  tour = [
    ["price minus a percentage — money is a native literal", %q(<< $499.99 - 15%)],
    ["integers don't overflow", %q(<< 2 ** 64)],
    ["ranges are collections", %q(<< (1..100).sum)],
    ["calculus is notation, not a library", %q(<< ∫(x², 0..2))],
    ["arrays do what you'd hope", %q(<< [3, 1, 2].sort)]
  ]
  puts
  print "#{bold}Press Enter for a 20-second tour#{reset} #{dim}(anything else skips)#{reset} "
  if $stdin.gets&.strip == ""
    tour.each do |label, snippet|
      puts
      puts "  #{dim}# #{label}#{reset}"
      puts "  #{green}#{snippet}#{reset}"
      out, _err, _st = Open3.capture3(File.join(ROOT, "bin/tungsten"), "-e", snippet)
      out.each_line { |l| puts "  #{bold}#{l.chomp}#{reset}" }
    end
    puts
    puts "That's the flavor. The playground is #{green}tungsten repl#{reset} — try"
    puts "#{cyan}? Σ(2x⁷ + 3x²)#{reset}, then press #{bold}Enter on a blank line#{reset} and #{bold}↑/↓#{reset} to scrub"
    puts "the coefficients live. #{cyan}? ∫(x², 0..2)#{reset} plots the curve and shades the area."
  end
end

# Native Windows isn't a target yet; point those users at WSL2. (Under WSL the
# host_os reads as linux, so this only fires on genuine native-Windows Ruby.)
if RbConfig::CONFIG["host_os"] =~ /mswin|mingw|cygwin/
  puts
  puts "#{yellow}On Windows?#{reset} Tungsten targets macOS + Linux today -- use WSL2."
end

exit
