load_gem!
files = ARGV.dup
ARGV.clear
write_in_place = files.delete("-w")

if files.empty?
  $stderr.puts "Usage: tungsten fmt [-w] <file.w ...>"
  exit 1
end

color = $stderr.tty? && !ENV["NO_COLOR"]
dim = color ? "\e[2m" : ""
reset = color ? "\e[0m" : ""

formatter = Tungsten::Formatter.new
files.each do |f|
  source = File.read(f)
  formatted = formatter.format(source)
  if write_in_place
    if formatted != source
      File.write(f, formatted)
      $stderr.puts "#{dim}formatted#{reset} #{f}"
    end
  else
    print formatted
  end
end
exit
