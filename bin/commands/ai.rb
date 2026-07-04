load_gem!
prompt = ARGV.join(" ")
require "tungsten/ai"
Tungsten::AI.new.run(prompt)
exit
