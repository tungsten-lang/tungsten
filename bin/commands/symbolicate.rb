require "json"
require "optparse"

usage = <<~USAGE
  Usage: tungsten symbolicate SIDEMAP [symbol-or-hash ...]
         tungsten symbolicate SIDEMAP < backtrace.txt

  Resolves compact __wy_ symbols using a compiler .sidemap file.
USAGE

OptionParser.new do |opts|
  opts.banner = usage
  opts.on("-h", "--help", "Show this help") do
    puts opts
    exit 0
  end
end.parse!(ARGV)

sidemap_path = ARGV.shift

unless sidemap_path && File.file?(sidemap_path)
  warn usage
  exit 1
end

data = JSON.parse(File.read(sidemap_path))
hash_entries = data.fetch("hashes")
symbol_entries = {}
hash_entries.each do |hash, entry|
  symbol_entries[entry.fetch("symbol")] = [ hash, entry ]
end

def symbolicate_display_name(original)
  klass = original["class"]
  method = original["method"]
  kind = original["kind"]
  symbol = original["symbol"]

  name =
    if klass && klass != "" && method && method != ""
      sep = %w[static_method static_wrapper].include?(kind) ? "." : "#"
      "#{klass}#{sep}#{method}"
    elsif method && method != ""
      method
    else
      symbol
    end

  file = original["file"]
  line = original["line"]
  if file && file != "" && line
    "#{name} (#{file}:#{line})"
  else
    name
  end
end

def symbolicate_lookup(token, hash_entries, symbol_entries)
  normalized = token.sub(/\A_+(__wy_)/, "__wy_")
  pair = symbol_entries[normalized]

  if pair
    hash, entry = pair
  elsif normalized.match?(/\A[0-9a-f]{16}\z/) && hash_entries[normalized]
    hash = normalized
    entry = hash_entries[normalized]
    normalized = entry.fetch("symbol")
  else
    return "#{token} => <unknown>"
  end

  originals = entry.fetch("originals").map { |original| symbolicate_display_name(original) }
  "#{normalized} [#{hash}] => #{originals.join("; ")}"
end

tokens = ARGV
symbol_pattern = /__wy_[0-9a-f]{1,16}(?:_\d+)?/

if tokens.empty?
  if STDIN.tty?
    warn usage
    exit 1
  end

  STDIN.each_line do |line|
    symbols = line.scan(symbol_pattern).uniq
    print line
    symbols.each do |symbol|
      puts "    #{symbolicate_lookup(symbol, hash_entries, symbol_entries)}"
    end
  end
else
  tokens.each do |token|
    puts symbolicate_lookup(token, hash_entries, symbol_entries)
  end
end
