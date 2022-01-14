#
# compiler.cr
#
# TODO: allow arguments to be passed to `[option]`
#

require "./scanner"
require "./bytecode_generator"

module Hollicode
  # Types of compiled statement.
  enum StatementType
    Undefined
    TextLine
    Anchor
    Goto
    Branch
    Include
    Option
    Wait
    Return
    FunctionCall
  end

  # Expression class.
  #
  # Expressions are the primary syntax tree node found in directives. They are a
  # more traditional parsed format which generally map to...well, *expressions*.
  abstract class Expression
    UNDEFINED = Empty.new

    # Empty expression.
    class Empty < Expression
    end

    # Binary expression.
    class Binary < Expression
      getter left : Expression
      getter operator : Token
      getter right : Expression

      def initialize(@left, @operator, @right)
      end
    end

    # Unary expression.
    class Unary < Expression
      getter operator : Token
      getter right : Expression

      def initialize(@operator, @right)
      end
    end

    # Function call expression.
    class Call < Expression
      getter method : Expression
      getter arguments : Array(Expression)

      def to_s(io : IO)
        io << "<Call: " << method << ", " << arguments.size << " argument(s)>"
      end

      def initialize(@method, @arguments)
      end
    end

    # Lookup expression.
    class Lookup < Expression
      getter parent : Expression
      getter child : Expression

      def initialize(@parent, @child)
      end
    end

    # Grouped expression.
    class Grouping < Expression
      getter expression : Expression

      def initialize(@expression)
      end
    end

    # Terminal (i.e. non-reduceable) expression.
    class Terminal < Expression
      getter value : Token

      def to_s(io : IO)
        io << "<Terminal: '" << value.lexeme << "'>"
      end

      def initialize(@value)
      end
    end

    class Value < Terminal
    end
  end

  class Compiler
    MULTILINE_TEXT_SEPARATOR = " "

    @source_string = ""
    @bytecode : BytecodeGenerator

    @scanner = Scanner.new
    @index = 0
    @compilation_okay = true

    @goto_commands = {} of String => Array(BytecodeGenerator::TracedJumpOp)
    @anchor_points = {} of String => Int32
    @compile_history = [] of StatementType

    @found_wait = false

    property compilation_path = ""

    def initialize
      @bytecode = BytecodeGenerator.new
    end

    def initialize(@bytecode)
    end

    # Compiles a string of source into bytecode.

    # Returns `true` if compilation happened without errors or `false`
    # otherwise.
    def compile(@source_string)
      @compilation_okay = true
      @scanner.scan @source_string
      consume TokenType::BOF, "unknown scanner error"
      while !peek.type.eof?
        compile_statement
      end
      patch_gotos_and_anchors
      if !@found_wait
        report_warning peek(-1).line, "no `wait` command found. The script may never yield."
      end
      @compilation_okay
    end

    # Returns generated bytecode in plain text format.
    #
    # See BYTECODE.md for explanation of various export formats.
    def get_plain_text
      if @compilation_okay
        @bytecode.get_plain_text
      else
        ""
      end
    end

    # Returns generated bytecode in JSON format.
    def get_json
      if @compilation_okay
        @bytecode.get_json
      else
        ""
      end
    end

    # Returns generated bytecode in Lua format.
    def get_lua
      if @compilation_okay
        @bytecode.get_lua
      else
        ""
      end
    end

    # Patches `->` directives with anchor points.
    #
    # TODO: Use JMP instead of GOTO.
    private def patch_gotos_and_anchors
      @goto_commands.each do |anchor_name, commands|
        if !@anchor_points.has_key? anchor_name
          report_error 0, "no anchor point stored as #{anchor_name}"
        elsif anchor_point = @anchor_points[anchor_name]?
          commands.each do |command|
            command.value = anchor_point - command.value
          end
        end
      end
    end

    # Compiles statements until the end of the source string is reached.
    private def compile_indented_block
      if match_any TokenType::Indent
        while !peek.type.unindent? && !peek.type.eof?
          compile_statement
        end
        consume TokenType::Unindent, "unknown block indentation error"
      end
    end

    # Compiles a single statement.
    private def compile_statement
      case advance.type
      when TokenType::TextLine
        compile_text_line
      when TokenType::Anchor
        @compile_history << StatementType::Anchor
        @anchor_points[get_anchor_name peek(-1).lexeme] = @bytecode.num_ops
        compile_indented_block
      when TokenType::Goto
        @compile_history << StatementType::Goto
        anchor_name = get_anchor_name peek(-1).lexeme
        if @goto_commands.has_key? anchor_name
          @goto_commands[anchor_name] << @bytecode.push_traced_jump @bytecode.num_ops
        else
          @goto_commands[anchor_name] = [@bytecode.push_traced_jump @bytecode.num_ops]
        end
        compile_indented_block
      when TokenType::OpenExpression
        case peek.type
        when TokenType::CloseExpression
          report_warning peek.line, "empty directive. Ignoring."
          advance
        when TokenType::If
          compile_if_statement
        when TokenType::Include
          compile_include_statement
        when TokenType::Option
          compile_option_statement
        when TokenType::Wait
          compile_wait_statement
        when TokenType::Return
          compile_return_statement
        when TokenType::Word
          compile_directive_call_statement
        else
          report_error peek(-1).line, "unknown directive: expected function name but got #{peek.type}"
        end
      else
        report_warning peek(-1).line, "unused token #{peek(-1).type.to_s}. Ignoring."
      end
    end

    # Compiles a text line statement.
    private def compile_text_line
      @compile_history << StatementType::TextLine
      builder = String::Builder.new
      builder << peek(-1).lexeme
      if match_any TokenType::Indent
        while !peek.type.unindent? && !peek.type.eof?
          if !peek.type.text_line?
            report_error peek.line, "invalid block text: expected text line but got #{peek.type}"
            break
          else
            builder << MULTILINE_TEXT_SEPARATOR << advance.lexeme
          end
        end
        consume TokenType::Unindent, "unknown block indentation error"
      end
      @bytecode.push_string builder.to_s
      @bytecode.push_echo
    end

    # Compiles an if statement (and any associated `else` statement).
    #
    # TODO: add support for `else if`
    private def compile_if_statement
      @compile_history << StatementType::Branch

      consume TokenType::If, "unknown control flow compilation error"
      compile_expression
      consume TokenType::CloseExpression, "expected ']' to close `if`"
      compile_conditional
    end

    # Compiles a conditional expression (i.e. `if/else`, `once/else`)
    #
    # TODO: add support for `once/else`
    private def compile_conditional
      conditional_start = @bytecode.num_ops
      conditional_jump = @bytecode.push_jump_if_false 0
      @bytecode.push_pop
      compile_indented_block

      else_start = @bytecode.num_ops
      else_jump = @bytecode.push_jump 0
      @bytecode.push_pop
      compile_else_statement

      # backpatch `if` and `else` jumps
      # * `if` jump, which happens if expression is false, jumps past `else`
      #     jump by 1 (= beginning of else block)
      # * `else` jump, which happens at end of `if` block, jumps `else` block
      conditional_jump.value = else_start - conditional_start + 1
      else_jump.value = @bytecode.num_ops - else_start
    end

    # Compiles an `else` statement.
    private def compile_else_statement
      if match_any TokenType::OpenExpression
        if match_any TokenType::Else
          consume TokenType::CloseExpression, "`else` takes no arguments"
          compile_indented_block
        else
          # back up; we've entered an unrelated expression, not an `else`
          advance -1
        end
      end
    end

    # Compiles an `include` statement.
    private def compile_include_statement
      @compile_history << StatementType::Include
      include_line = peek.line
      consume TokenType::Include, "unknown control flow compilation error"
      file_path = ""
      if check_any TokenType::StringLiteral
        file_path = advance.lexeme
        consume TokenType::CloseExpression, "expected ']' to close `include`"
      elsif match_any TokenType::CloseExpression
        consume TokenType::DirectiveTag, "no file path passed to `include` directive"
        file_path = peek(-1).lexeme
      else
        report_error peek.line, "`include` directive must take a constant string"
      end
      file_path = Path.new "#{compilation_path}/#{file_path}"
      begin
        File.open(file_path, "r") do |file|
          include_compiler = Compiler.new @bytecode
          include_compiler.compilation_path = file_path.dirname
          success = include_compiler.compile file.gets_to_end
          if !success
            report_error include_line, "compilation of included file '#{file_path}' failed. Exiting."
          end
        end
      rescue error
        report_error include_line, "failed to read file '#{file_path}'"
      end
    end

    # Compiles an `option` statement.
    private def compile_option_statement
      @compile_history << StatementType::Option
      consume TokenType::Option, "unknown control flow compilation error"
      arguments = parse_directive_arguments
      arguments.reverse_each { |a| emit_expression a }
      @bytecode.push_option arguments.size
      block_start = @bytecode.num_ops
      option_jump = @bytecode.push_jump 0
      compile_indented_block
      @bytecode.push_return
      option_jump.value = @bytecode.num_ops - block_start
    end

    # Compiles a `wait` statement.
    private def compile_wait_statement
      @found_wait = true
      @compile_history << StatementType::Wait
      consume TokenType::Wait, "unknown control flow compilation error"
      consume TokenType::CloseExpression, "`wait` takes no arguments"
      @bytecode.push_wait
      compile_indented_block
    end

    # Compiles a `return` statement.
    private def compile_return_statement
      @compile_history << StatementType::Return
      consume TokenType::Return, "unknown control flow compilation error"
      consume TokenType::CloseExpression, "`return` takes no arguments"
      @bytecode.push_return
      compile_indented_block
    end

    # Compiles a function call statement.
    private def compile_directive_call_statement
      @compile_history << StatementType::FunctionCall
      method = parse_lookup
      arguments = parse_directive_arguments
      emit_expression Expression::Call.new method, arguments
      compile_indented_block
    end

    # Compiles an expression.
    private def compile_expression
      emit_expression parse_expression
    end

    # Emits code for an expression.
    private def emit_expression(expr)
      case expr
      when Expression::Terminal
        emit_terminal expr
      when Expression::Binary
        emit_expression expr.right
        emit_expression expr.left
        emit_binary_operator expr.operator
      when Expression::Call
        expr.arguments.reverse_each { |a| emit_expression a }
        emit_expression expr.method
        @bytecode.push_call expr.arguments.size
      when Expression::Unary
        emit_expression expr.right
        emit_unary_operator expr.operator
      when Expression::Lookup
        emit_lookup expr
      when Expression::Grouping
        emit_expression expr.expression
      end
    end

    # Emits a constant or variable lookup to the bytecode writer.
    private def emit_terminal(expr)
      if expr.is_a? Expression::Terminal
        case expr.value.type
        when TokenType::NilLiteral
          @bytecode.push_nil
        when TokenType::BooleanLiteral
          @bytecode.push_boolean expr.value.lexeme == "true" ? true : false
        when TokenType::NumberLiteral
          @bytecode.push_number expr.value.lexeme.to_f
        when TokenType::StringLiteral
          @bytecode.push_string expr.value.lexeme
        when TokenType::Word
          @bytecode.push_variable expr.value.lexeme
        end
      end
    end

    # Emits associated op code for a binary operator.
    private def emit_binary_operator(token)
      op = token.lexeme
      # `and` and `or` can be either the word or &&/||, so unify them
      case token.type
      when TokenType::And
        op = "&&"
      when TokenType::Or
        op = "||"
      end
      @bytecode.push_binary_op op
    end

    # Emits associated op code for a unary operator.
    private def emit_unary_operator(token)
      case token.type
      when TokenType::Minus
        @bytecode.push_negate
      when TokenType::Not
        @bytecode.push_not
      end
    end

    # Emits associated op code for a lookup.
    private def emit_lookup(expr)
      emit_lookup_item expr.child
      if (parent = expr.parent).is_a? Expression::Terminal
        if parent.value.type.word?
          @bytecode.push_variable parent.value.lexeme
        else
          report_error parent.value.line, "'#{parent.value.lexeme}' is not a variable"
        end
      else
        emit_lookup_item expr.parent
      end
      @bytecode.push_lookup
    end

    # Emits a single component of a lookup.
    private def emit_lookup_item(expr)
      if expr.is_a? Expression::Terminal
        if expr.value.type.word?
          @bytecode.push_string expr.value.lexeme
        else
          emit_expression expr
        end
      else
        emit_expression expr
      end
    end

    #
    # Expression parsing
    #
    # Hollicode keeps track of two code formats, essentially--one simple
    # notation used for anchors, text lines, and goto commands, and one more
    # traditional syntax used in directives. When we come across a bracket, we
    # sort of morph into expression parsing mode until we find the associated
    # closing bracket.
    #

    private def parse_directive_arguments
      starting_line = peek(-1).line
      arguments = [] of Expression
      while !peek.type.close_expression?
        if peek.type.open_expression?
          report_error peek.line, "cannot pass directive as argument to directive. Use function call: `f()`."
        elsif peek.type.eof?
          report_error starting_line, "directive never terminates"
        else
          arguments << parse_expression
          if !peek.type.close_expression?
            consume TokenType::Comma, "arguments must be separated by commas"
          end
        end
      end
      consume TokenType::CloseExpression, "unknown control flow compilation error"
      if match_any TokenType::DirectiveTag
        arguments.unshift Expression::Terminal.new(Token.new(TokenType::StringLiteral, peek(-1).lexeme, peek(-1).line))
      end
      arguments
    end

    # expression -> and_or
    private def parse_expression
      parse_and_or
    end

    # and_or -> comparison ( ( AND | OR ) comparison )*
    private def parse_and_or
      expr = parse_equality
      while match_any TokenType::And, TokenType::Or
        operator = peek(-1).not_nil!
        right = parse_equality
        expr = Expression::Binary.new expr, operator, right
      end
      expr
    end

    # equality -> andor ( ( != | == ) andor )*
    private def parse_equality
      expr = parse_comparison
      while match_any TokenType::NotEqual, TokenType::EqualEqual
        operator = peek(-1).not_nil!
        right = parse_comparison
        expr = Expression::Binary.new expr, operator, right
      end
      expr
    end

    # comparison -> term ( ( > | >= | < | <= ) term )*
    private def parse_comparison
      expr = parse_term
      while match_any TokenType::GreaterThan, TokenType::GreaterThanOrEqual, TokenType::LessThan, TokenType::LessThanOrEqual
        operator = peek(-1).not_nil!
        right = parse_term
        expr = Expression::Binary.new expr, operator, right
      end
      expr
    end

    # term -> factor ( ( - | + ) factor )*
    private def parse_term
      expr = parse_factor
      while match_any TokenType::Minus, TokenType::Plus
        operator = peek(-1).not_nil!
        right = parse_factor
        expr = Expression::Binary.new expr, operator, right
      end
      expr
    end

    # factor -> unary ( ( / | * ) unary )*
    private def parse_factor
      expr = parse_unary
      while match_any TokenType::Divide, TokenType::Multiply
        operator = peek(-1).not_nil!
        right = parse_unary
        expr = Expression::Binary.new expr, operator, right
      end
      expr
    end

    # unary -> ( ( NOT | - | : ) unary )* method_call
    private def parse_unary
      if match_any TokenType::Not, TokenType::Minus
        operator = peek(-1).not_nil!
        right = parse_unary
        return Expression::Unary.new operator, right
      elsif match_any TokenType::Colon
        if !match_any TokenType::Word, TokenType::BooleanLiteral
          report_error peek.line, "colon capturing must take a word"
        else
          return Expression::Terminal.new(Token.new(TokenType::StringLiteral, peek(-1).lexeme, peek(-1).line))
        end
      end
      parse_method_call
    end

    # method_call -> lookup ( OPEN_PARENTHESIS arguments? CLOSE_PARENTHESIS ) | arguments
    private def parse_method_call
      expr = parse_lookup
      if match_any TokenType::OpenParenthesis
        starting_line = peek(-1).line
        arguments = [] of Expression
        while !peek.type.close_parenthesis?
          if peek.type.open_expression?
            report_error peek.line, "cannot pass directive as argument to function. Use function call: `f()`."
          elsif peek.type.eof?
            report_error starting_line, "function call never terminates"
          else
            arguments << parse_expression
            if !peek.type.close_parenthesis?
              consume TokenType::Comma, "arguments must be separated by commas"
            end
          end
        end
        consume TokenType::CloseParenthesis, "unterminated method call"
        expr = Expression::Call.new expr, arguments
      end
      expr
    end

    # lookup -> primary ( . primary )*
    private def parse_lookup
      expr = parse_primary
      while match_any TokenType::Dot
        n = parse_primary
        expr = Expression::Lookup.new expr, n
      end
      expr
    end

    # primary -> ( OPEN_PARENTHESIS expression CLOSE_PARENTHESIS ) | TERMINAL
    private def parse_primary
      if match_any TokenType::OpenParenthesis
        expr = parse_expression
        if !match_any TokenType::CloseParenthesis
          puts "warning: unterminated parenthetical"
        end
        Expression::Grouping.new expr
      else
        Expression::Terminal.new advance.not_nil!
      end
    end

    # Returns true and advances if the next token is any of the given types.
    private def match_any(*token_types)
      token_types.each do |token_type|
        if peek.type == token_type
          advance
          return true
        end
      end
    end

    # Returns `true` if the next token is any of the given types. Does not
    # consume the token.
    private def check_any(*token_types)
      token_types.each do |token_type|
        if peek.type == token_type
          return true
        end
      end
    end

    # Consumes a token of type `token_type` or reports an error.
    private def consume(token_type, error_message = "")
      if peek.type == token_type
        advance
      else
        report_error peek.line, error_message
      end
    end

    # Consumes the current token and returns it.
    private def advance(how_many = 1)
      token = peek
      count = how_many.abs
      while true
        token = peek
        @index += how_many.sign
        if token.type.error?
          error_message = token.lexeme
          # (maybe: include nearby token)
          # if !peek.type.undefined?
          #   near_token = peek.lexeme
          #   if near_token.size > NEAR_TOKEN_ERROR_TRUNCATE_LIMIT
          #     near_token = near_token[...NEAR_TOKEN_ERROR_TRUNCATE_LIMIT].rstrip + "..."
          #   end
          #   error_message += " (near '" + near_token + "')"
          # end
          report_error token.line, error_message
        else
          count -= 1
          if count == 0
            break
          end
        end
      end
      return token
    end

    private def get_anchor_name(name)
      name.downcase.delete("^a-z0-9 ")
    end

    # Peeks at the token at +- `how_far` (defaults to 0, which denotes current
    # token).
    private def peek(how_far = 0)
      if token = @scanner.tokens[@index + how_far]?
        token
      else
        if @index + how_far >= @scanner.tokens.size
          @scanner.tokens.last
        else
          @scanner.tokens.first
        end
      end
    end

    # Returns whether the parser has reached the end of the token list.
    private def finished?
      @index >= @scanner.tokens.size || peek.type == TokenType::EOF
    end

    private def report_warning(line, message)
      STDERR << "[line " << line << "]: Warning: " << message << "\n"
    end

    # Prints a parsing error to STDERR.
    private def report_error(line, message = "unknown")
      @compilation_okay = false
      STDERR << "[line " << line << "]: Error: " << message << "\n"
    end
  end
end
