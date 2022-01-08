require "option_parser"
require "./core"

input_file = ""
output_file = ""
target_format = ""
arguments = ARGV.dup

OptionParser.parse(arguments) do |parser|
  parser.banner = "Usage: hollicode [arguments]"
  parser.on "-f FILE", "--file=FILE", "The input file." do |f|
    input_file = f
  end
  parser.on "-o OUTPUT", "--out=OUTPUT", "The output file." do |o|
    output_file = o
  end
  parser.on "-t TARGET", "--target=TARGET", "The target format. Can be either `json` or `text`. Leave blank to guess based on file extension (`.hlcj` or `.hlct`)." do |t|
    target_format = t
  end
  parser.on "-h", "--help", "Show this help" do |h|
    puts parser
    exit
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

  if output_file.empty?
    output_file = input_file.rstrip(".hlc") + ".hlcj"
    target_format = "json"
  elsif target_format.empty?
    target_format = output_file.ends_with?(".hlcj") ? "json" : output_file.ends_with?(".hlct") ? "text" : ""
    if target_format.empty?
      puts "Could not determine output target from file extension. Specify it using `-t TARGET` or `--target=TARGET`."
      exit 1
    end
  end

  if target_format != "json" && target_format != "text"
    puts "Invalid target format '#{target_format}'. Valid options are:\n* json\n* text"
  end

  if input_file.empty? || output_file.empty?
    puts parser
    exit
  end
end

begin
  File.open(input_file, "r") do |file|
    compiler = Hollicode::Compiler.new
    compiler.compilation_path = File.dirname input_file
    success = compiler.compile file.gets_to_end
    if !success
      STDERR << "Compilation failed. Exiting." << "\n"
      exit 1
    else
      File.open(output_file, "w") do |out_file|
        if target_format == "json"
          out_file << compiler.get_json
        elsif target_format == "text"
          out_file << compiler.get_plain_text
        end
      end
    end
  end
rescue whoops
  STDERR << "Could not read file '" << input_file << "'.\n"
  exit 1
end
