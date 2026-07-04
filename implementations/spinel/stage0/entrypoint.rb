# frozen_string_literal: true

if ARGV.length == 0
  $stderr.puts "usage: tungsten-stage0 FILE.w [args...]"
  exit 64
end

file = ARGV[0]
source = File.read(file)
interpreter = Tungsten::Interpreter.new
interpreter.instance_variable_set(:@argv, ARGV[1..])
interpreter.run(source, file)
