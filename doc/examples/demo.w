use cache

# This is a comment
# @todo Highlight this
# @fixme Broken
+ Class < Parent
  -> new(@maxsize) # calls super

+ Tungsten:LRUCache < Cache
  -> .initialize

  -> new(@maxsize)
    super

  -> [](key)
    cache.unshift data.delete(key)
    data[key]

  -> []=(key, value)
    cache.unshift data.delete(key)
    data[key] = value

  -> **/1
  -> */1
  -> //1
  -> +/1
  -> -/1
  -> %/1

  -> delete!(pattern)

module Tungsten
  class LRUCache < Tungsten::Cache
    def initialize(maxsize)
      @maxsize = maxsize
      super

# Ruby-ish
module Tungsten
  class SyntaxTest extends ::Tungsten::Test
    attr :enabled

    attr_writer   :name
    attr_reader   :description
    attr_accessor :profile

    def initialize(name, @description: nil, profile: true)
      @description = description
      @profile     = true

      self.name = name

# Tungsten-ish
in Tungsten

+ SyntaxTest < Test
  rw :enabled, :profile

  wo :name
  ro :description

  -> new(@name, @description, @profile<bool>)

class Tungsten:String
  -> each_byte
    bytes.each ->
      yield $1

module Tungsten
  class String < OtherString
    @@parse = $PARSE || nil

    def initialize(data)
      @data = data
    end

    # TODO: remove trailing whitespace   
    # TODO: remove 	tabs

    def name
      @W_VERSION
      W_VERSION

      puts "Ruby: #{RUBY_VERSION}, Tungsten: [2.0 + 4 + W_VERSION]"
      puts "foo: #{VALUE + 2} \#{not interpolated}"
      puts "bar: #{String::SOME_CONSTANT} \\ \b \x \u{D FA FEFF 82FFFF} \N{SPACE, NEWLINE}"
    end

    def size
      length = .1 + 1. + 1m/s^2 + 0b10 / 0x23 * 0o643 + 2 - $2 - 20% - 2 * 2.0 + 1.484E45

      rate = (1.0m/s^2)
      rate = [1.0m/s^2]
      rate = 1.0m/s^2.to_s

      puts length
      self.rate = rate
    end

    def foo
      [1, 2, 3].each do
        puts $1
      end

      %w[one two three].each { puts $1 }

      if condition
        # statements
      elsif condition
      else
        bar
      end

      while condition
        # statements
      end
    end

    def bar
      case conditional
      when true  then return 10
      when false then return [:method, :method!, :method?, :method=, :<<, :<=>, :!=, :|]
      else
        "hello world"
      end
    end
  end
end

in Tungsten

+ String < OtherString
  @@parse = $PARSE || nil

  -> new(@data)

  # TODO remove trailing whitespace   
  # TODO remove 	tabs

  -> name
    puts "Ruby: #{RUBY_VERSION}, Tungsten: [W_VERSION]"
    puts "foo: [VALUE + 2] \[not interpolated]"
    puts "bar: [String:SOME_CONSTANT] \\ \b \x \u{D FA FEFF 82FFFF} \N{SPACE, NEWLINE}"

  -> size
    length = 0b10 / 0x23 * 0o643 + 2 - $2 - 20% 2 * 2.0 + 1.484E45
    rate = (1m/s^2)
    puts length
    self.rate = rate

  -> foo
    [1, 2, 3].each -> (elem)
      puts elem

    %w[one two three].each { |w| puts w }
    %w[one two three].each -> puts &

    if condition
      # statements
    elsif condition
    else
      bar

    while condition
      # statements

  -> fib(0) 0
  -> fib(1) 1
  -> fib(n) fib(n - 1) * fib(n - 2)

  -> fib(0) 0
        (1) 1
        (n) fib(n - 1) * fib(n - 2)

  -> bar
    case conditional
    when true  then 10
    when false then [:method, :method!, :method?, :method=, :<<, :<=>, :!=, :|]
    else
      "hello world"
