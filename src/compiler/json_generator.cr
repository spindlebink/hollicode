#
# code_generator.cr
#

require "json"

module Hollicode
  # Code generator class. Produces bytecode from a parsed syntax tree.
  class JSONCodeGenerator
    HEADER_MODE_AST = 0_u8
    HEADER_MODE_BYTECODE = 1_u8

    OP_TEXT_LINE = 0_u8

    struct Header
      include JSON::Serializable
      property signature = ""
      property version = "0.0.0"
      property mode = HEADER_MODE_AST

      def initialize
      end
    end

    struct CompiledCode
      include JSON::Serializable

      property header : Header
      property text = [] of String
      property exec = [] of ExecutionNode

      def initialize(@header)
      end
    end

    abstract struct ExecutionNode
      abstract def to_json(json : JSON::Builder)

      struct TextLine < ExecutionNode
        getter text_index = 0
        getter next_exec = 0
        def initialize(@text_index, @next_exec)
        end

        def to_json(json : JSON::Builder)
          json.array do
            json.number OP_TEXT_LINE
            json.number @text_index
            json.number @next_exec
          end
        end
      end
    end

    @parse_root = Statement::UNDEFINED
    @compiling = CompiledCode.new Header.new
    @anchors = {} of String => Int32

    # Generates a MessagePack structure for a parsed syntax tree.
    def generate(@parse_root)
      @compiling.header = Header.new
      process_children @parse_root
    end

    private def process(node)
      case node
      when Statement::Root
        process_children node
      when Statement::Anchor
        @anchors[node.value.lexeme] = @compiling.exec.size
        process_children node
      when Statement::TextLine
        @compiling.text << node.value.lexeme
        @compiling.exec << ExecutionNode::TextLine.new @compiling.text.size, @compiling.exec.size + 1
        process_children node
      when Statement::Directive
        directive = node.as Statement::Directive
        case directive.start.type
        when Expression::Terminal
        end
      end
    end

    private def process_children(node)
      node.children.each do |child_node|
        process child_node
      end
    end

    # Returns the 
    def get_generated
      @compiling.to_json
    end
  end
end
