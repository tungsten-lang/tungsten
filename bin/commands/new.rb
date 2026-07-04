name = ARGV.shift
unless name
  $stderr.puts "Usage: tungsten new <project-name>"
  exit 1
end

color = $stdout.tty? && !ENV["NO_COLOR"]
bold = color ? "\e[1m" : ""
yellow = color ? "\e[33m" : ""
dim = color ? "\e[2m" : ""
green = color ? "\e[32m" : ""
reset = color ? "\e[0m" : ""

Dir.mkdir(name)
File.write("#{name}/main.w", "<< \"hello world\"\n")
puts "#{bold}#{yellow}✶ Created #{name}/#{reset}"
puts "  #{dim}main.w#{reset}"
puts
puts "#{green}Run: cd #{name} && tungsten main.w#{reset}"
exit
