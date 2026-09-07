#!/usr/bin/env ruby
# Independent GF(2) reconstruction. Does not invoke the searcher's verifier.
require "digest"
require "json"
require "optparse"

module MetaflipTensorVerifier
  module_function

  def dimensions(shape)
    parts = shape.split("x")
    raise "expected shape NxMxP" unless parts.length == 3 && parts.all? { |part| part.match?(/\A[1-9][0-9]*\z/) }
    parts.map { |part| Integer(part, 10) }
  end

  def bit_positions(word)
    result = []
    until word.zero?
      low = word & -word
      result << low.bit_length - 1
      word ^= low
    end
    result
  end

  def verify_text(text, n, m, p)
    raise "non-positive shape" unless [n, m, p].all? { |value| value.is_a?(Integer) && value.positive? }
    lines = text.lines.map(&:strip).reject { |line| line.empty? || line.start_with?("#") }
    raise "empty tensor certificate" if lines.empty?
    header = lines.first.match?(/\A[0-9]+\z/)
    rank = header ? Integer(lines.shift, 10) : lines.length
    raise "wrong term count" unless rank.positive? && lines.length == rank
    widths = [n * m, m * p, n * p]
    tensor = Array.new(widths[0] * widths[1], 0)
    density = 0
    lines.each_with_index do |line, index|
      words = line.split
      # Curated corpus files use R-prefixed rows without a numeric header;
      # checkpoints use three decimal words after a rank header.
      prefixed = words.first == "R"
      words.shift if prefixed
      raise "missing rank header or R prefix" unless header || prefixed
      raise "malformed factor triple at term #{index}" unless words.length == 3 && words.all? { |word| word.match?(/\A[0-9]+\z/) }
      factors = words.map { |word| Integer(word, 10) }
      raise "zero or out-of-bounds factor at term #{index}" unless factors.zip(widths).all? { |word, width| word.positive? && word.bit_length <= width }
      u, v, w = factors
      ubits, vbits, wbits = factors.map { |word| bit_positions(word) }
      density += ubits.length + vbits.length + wbits.length
      ubits.each do |a|
        vbits.each { |b| tensor[a * widths[1] + b] ^= w }
      end
    end
    widths[0].times do |a|
      widths[1].times do |b|
        expected = a % m == b / p ? 1 << ((a / m) * p + b % p) : 0
        raise "inexact GF(2) tensor at coefficients #{a},#{b}" unless tensor[a * widths[1] + b] == expected
      end
    end
    { exact: true, shape: "#{n}x#{m}x#{p}", rank: rank, density: density,
      sha256: Digest::SHA256.hexdigest(text) }
  end

  def verify(path, n, m, p)
    verify_text(File.binread(path), n, m, p).merge(path: File.expand_path(path))
  end

  def infer_shape(path)
    File.expand_path(path).split(File::SEPARATOR).reverse.find { |part| part.match?(/\A[1-9][0-9]*x[1-9][0-9]*x[1-9][0-9]*\z/) } ||
      raise("cannot infer shape for #{path}; pass --shape NxMxP")
  end

  def main(argv)
    shape = nil
    OptionParser.new do |parser|
      parser.banner = "Usage: verify_tensor.rb [--shape NxMxP] CERTIFICATE..."
      parser.on("--shape SHAPE") { |value| dimensions(value); shape = value }
    end.parse!(argv)
    raise "provide at least one certificate" if argv.empty?
    results = argv.map do |path|
      verify(path, *dimensions(shape || infer_shape(path)))
    end
    puts JSON.pretty_generate(results)
  end
end

if $PROGRAM_NAME == __FILE__
  begin
    MetaflipTensorVerifier.main(ARGV)
  rescue StandardError => error
    warn "Tensor verification failed: #{error.message}"
    exit 1
  end
end
