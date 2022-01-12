require "option_parser"
require "./core"

input_file = ""
output_file = ""
target_format = ""
arguments = ARGV.dup

should_exit = false

OptionParser.parse(arguments) do |parser|
  parser.banner = "Usage: hollicode [arguments]"
  parser.on "-v", "--version", "Show version information." do
    puts "Hollicode compiler version #{Hollicode::LANGUAGE_VERSION}"
    should_exit = true
  end
  parser.on "-h", "--help", "Show this help" do
    puts parser
    should_exit = true
  end
  parser.on "-f FILE", "--file=FILE", "The input file." do |f|
    input_file = f
  end
  parser.on "-o OUTPUT", "--out=OUTPUT", "The output file." do |o|
    output_file = o
  end
  parser.on "-t TARGET", "--target=TARGET", "The target format. Can be `json`, `lua`, or `text`. Leave blank to guess based on file extension (`.json`, `.lua`, or `.hlct`)." do |t|
    target_format = t
  end

  parser.unknown_args do |unknown|
    unknown.each do |argument|
      if input_file.empty?
        input_file = argument
      elsif output_file.empty?
        output_file = argument
      end
    end

    if !should_exit && unknown.size == 0 && input_file.empty? && output_file.empty?
      puts parser
      should_exit = true
    end
  end
end

if !should_exit
  if output_file.empty?
    if target_format.empty?
      target_format = "json"
    end
    output_file = input_file.rstrip(".hlc") + (target_format == "json" ? ".json" : target_format == "lua" ? ".lua" : ".hlct")
  end

  if target_format.empty?
    target_format = output_file.ends_with?(".json") ? "json" : output_file.ends_with?(".lua") ? "lua" : output_file.ends_with?(".hlct") ? "text" : ""
    if target_format.empty?
      puts "Could not determine output target from file extension. Specify it using `-t TARGET` or `--target=TARGET`."
      exit 1
    end
  end

  if target_format != "json" && target_format != "lua" && target_format != "text"
    puts "Invalid target format '#{target_format}'. Valid options are:\n* json\n* lua\n* text"
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
          elsif target_format == "lua"
            out_file << compiler.get_lua
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
end
