require "option_parser"
require "./core/compiler"

input_file = ""
output_file = ""
arguments = ARGV.dup

OptionParser.parse(arguments) do |parser|
  parser.banner = "Usage: hollicode [arguments]"
  parser.on "-f FILE", "--file=FILE", "The input file." do |f|
    input_file = f
  end
  parser.on "-o OUTPUT", "--out=OUTPUT", "The output file." do |o|
    output_file = o
  end
end

File.open(input_file, "r") do |file|
  compiler = Hollicode::Compiler.new
  success = compiler.compile file.gets_to_end
  if !success
    STDERR << "Compilation failed. Exiting." << "\n"
    exit 1
  else
    File.open(output_file, "w") do |out_file|
      out_file << compiler.get_plain_text
    end
  end
end
