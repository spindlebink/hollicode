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
  parser.on "-h", "--help", "Show this help" do |h|
    puts parser
    exit
  end
end

if input_file.empty?
  if arguments.size > 0
    input_file = arguments[0]
    arguments.shift
  end
end

if output_file.empty?
  if arguments.size > 0
    output_file = arguments[0]
    arguments.shift
  end
end

if input_file.empty? || output_file.empty?
  STDERR << "Insufficient input provided.\n"
  exit 1
end

begin
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
rescue whoops
  STDERR << "Could not read file '" << input_file << "'.\n"
  exit 1
end