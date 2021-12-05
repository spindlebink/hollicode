require "option_parser"
require "./compiler"

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
  scanner = Hollicode::Scanner.new
  parser = Hollicode::Parser.new

  contents = file.gets_to_end

  scanner.scan contents
  parser.parse scanner.tokens

  # code_generator.compile parser.parse_root
  # File.open(output_file, "w") do |out_file|
    # out_file << code_generator.get_string
  # end
end
