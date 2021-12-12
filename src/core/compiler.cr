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

    # Grouped expression.
    class Grouping < Expression
      getter expression : Expression
      def initialize(@expression)
      end
    end

    # Terminal (i.e. non-reduceable) expression.
    class Terminal < Expression
      getter value : Token
      def initialize(@value)
      end
    end
  end

  class Compiler
    # NEAR_TOKEN_ERROR_TRUNCATE_LIMIT = 16

    @source_string = ""
    @bytecode : BytecodeGenerator

    @scanner = Scanner.new
    @index = 0
    @compilation_okay = true

    @goto_commands = {} of String => Array(BytecodeGenerator::JumpOp)
    @anchor_points = {} of String => Int32
    @compile_history = [] of StatementType

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
          @goto_commands[anchor_name] << @bytecode.push_jump @bytecode.num_ops
        else
          @goto_commands[anchor_name] = [@bytecode.push_jump @bytecode.num_ops]
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
        when TokenType::Word
          compile_function_call_statement
        else
          report_error peek(-1).line, "unknown directive: expected function name but got #{peek(-1).type}"
        end
      else
        report_warning peek(-1).line, "unused token #{peek(-1).type.to_s}. Ignoring."
      end
    end

    # Compiles a text line statement.
    private def compile_text_line
      @compile_history << StatementType::TextLine
      @bytecode.push_string peek(-1).lexeme
      @bytecode.push_echo
      compile_indented_block
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
            report_error include_line, "Compilation of included file '#{file_path}' failed. Exiting."
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
      consume TokenType::CloseExpression, "`option` takes no arguments. Did you mean to use a directive tag? `[option] Directive tag`"
      option_tag = ""
      if match_any TokenType::DirectiveTag
        option_tag = peek(-1).lexeme
      end
      @bytecode.push_string option_tag
      @bytecode.push_option
      block_start = @bytecode.num_ops
      option_jump = @bytecode.push_jump 0
      compile_indented_block
      @bytecode.push_return
      option_jump.value = @bytecode.num_ops - block_start
    end

    # Compiles a `wait` statement.
    private def compile_wait_statement
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
    private def compile_function_call_statement
      @compile_history << StatementType::FunctionCall

      function_name_token = advance
      arguments = [] of Expression

      if match_any TokenType::Colon
        consume TokenType::Word, "target of colon string capture must be an identifier"
        arguments << Expression::Terminal.new Token.new TokenType::StringLiteral, peek(-1).lexeme, peek(-1).line
        # @bytecode.push_string peek(-1).lexeme
        if !peek.type.close_expression?
          consume TokenType::Comma, "arguments to directive must be separated by commas"
        end
      end
      while !peek.type.close_expression?
        if peek.type.open_expression?
          report_error peek.line, "cannot nest directives"
          return
        elsif peek.type.eof?
          report_error function_name_token.line, "function call directive never terminates"
          return
        else
          arguments << parse_expression
          if !peek.type.close_expression?
            consume TokenType::Comma, "arguments to directive must be separated by commas"
          end
        end
      end
      consume TokenType::CloseExpression, "unknown control flow compilation error"
      # pin any directive tag onto the end of the arguments list as a string
      if match_any TokenType::DirectiveTag
        arguments.unshift Expression::Terminal.new(Token.new(TokenType::StringLiteral, peek(-1).lexeme, peek(-1).line))
      end
      arguments.reverse!
      arguments.each { |a| emit_expression a }
      @bytecode.push_function function_name_token.lexeme
      @bytecode.push_call arguments.size
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
      when Expression::Unary
        emit_expression expr.right
        emit_unary_operator expr.operator
      when Expression::Grouping
        emit_expression expr.expression
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

    #
    # Expression parsing
    #
    # Hollicode keeps track of two code formats, essentially--one simple
    # notation used for anchors, text lines, and goto commands, and one more
    # traditional syntax used in directives. When we come across a bracket, we
    # sort of morph into expression parsing mode until we find the associated
    # closing bracket.
    #

    private def parse_expression
      parse_and_or
    end

    # andor -> comparison ( ( AND | OR ) comparison )*
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

    # unary -> ( ( NOT | - ) unary )* primary
    private def parse_unary
      if match_any TokenType::Not, TokenType::Minus
        operator = peek(-1).not_nil!
        right = parse_unary
        return Expression::Unary.new operator, right
      end
      parse_primary
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