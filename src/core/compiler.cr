#
# compiler.cr
#

require "./scanner"
require "./bytecode_generator"

module Hollicode
  class Statement
    property children = [] of Statement

    class RootStatement < Statement
    end

    class DirectiveStatement < Statement
      getter start : Expression
      getter tag : Token
      property arguments = [] of Expression
      def initialize(@start, @tag = Token.new TokenType::Undefined, "", 0)
      end
    end

    # A line of text.
    class TextLineStatement < Statement
      getter value : Token
      def initialize(@value)
      end
    end

    # An anchor.
    class AnchorStatement < Statement
      getter value : Token
      def initialize(@value)
      end
    end

    # A goto statement.
    class GotoStatement < Statement
      getter value : Token
      def initialize(@value)
      end
    end
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
    @bytecode = BytecodeGenerator.new

    @scanner = Scanner.new
    @index = 0
    @compilation_okay = true

    # Compiles a string of source into bytecode.
    def compile(@source_string)
      @compilation_okay = true
      @scanner.scan @source_string

      @scanner.tokens.each do |token|
        puts token
      end
      
      parse_root
      @bytecode.debug_print

      @compilation_okay
    end

    def get_plain_text
      if @compilation_okay
        @bytecode.get_plain_text
      else
        ""
      end
    end

    private def compile_expression(expr)
      case expr
      when Expression::Terminal
        term = expr.as Expression::Terminal
        case term.value.type
        when TokenType::NumberLiteral
          @bytecode.push_number term.value.lexeme.to_f
        when TokenType::StringLiteral
          @bytecode.push_string term.value.lexeme
        when TokenType::BooleanLiteral
          @bytecode.push_boolean term.value.lexeme == "true" ? true : false
        when TokenType::NilLiteral
          @bytecode.push_nil
        when TokenType::Word
          @bytecode.push_variable term.value.lexeme
        end
      end
    end

    private def compile_directive_start(expr, argument_count = 0)
      case expr
      when Expression::Terminal
        term = expr.as Expression::Terminal
        case term.value.type
        when TokenType::If
          compile_if term
        when TokenType::Return
          @bytecode.push_return
        else
          compile_call term, argument_count
        end
      end
    end

    private def compile_if(expr)
      starting_ops = @bytecode.num_ops
      jump_op = @bytecode.push_jump_if_false 0
        @bytecode.push_pop
        parse_indented_block
        hop_else = @bytecode.push_jump 0
        hop_start = @bytecode.num_ops
      jump_op.value = @bytecode.num_ops - starting_ops
      # @bytecode.push_not
      # else_starting_ops = @bytecode.num_ops
      # else_jump_op = @bytecode.push_jump_if_false 0
      @bytecode.push_pop
      if peek.type == TokenType::OpenExpression && peek(1).type == TokenType::Else
        advance 2
        consume TokenType::CloseExpression, "unterminated 'else' directive"
        parse_indented_block
      end
      # else_jump_op.value = @bytecode.num_ops - else_starting_ops
      hop_else.value = @bytecode.num_ops - hop_start + 1
    end

    private def compile_call(expr, argument_count)
      compile_expression expr
      @bytecode.push_call argument_count
    end

    private def parse_root
      while !peek.type.eof?
        parse_statement
      end
    end

    private def parse_indented_block
      if match_any TokenType::Indent
        while !peek.type.unindent? && !peek.type.eof?
          parse_statement
        end
        consume TokenType::Unindent, "unknown indentation error"
      end
    end

    private def parse_statement
      if match_any TokenType::OpenExpression
        start = parse_expression
        arguments = [] of Expression
        while !peek.type.close_expression? && !peek.type.eof?
          argument = parse_expression
          arguments << argument
          if peek.type.close_expression?
            # done
          else
            consume TokenType::Comma, "expected ',' between arguments"
          end
        end
        consume TokenType::CloseExpression, "unterminated directive"
        arguments.each do |argument|
          compile_expression argument
        end
        compile_directive_start start, arguments.size
      elsif match_any TokenType::TextLine
        @bytecode.push_string peek(-1).lexeme
        @bytecode.push_echo
      else
        advance
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
      parse_equality
    end

    # equality -> comparison ( ( != | == ) comparison )*
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
    private def advance(num = 1)
      token = peek
      count = num
      while true
        token = peek
        @index += 1
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

    # Peeks at the token at +- `how_far` (defaults to 0, which denotes current
    # token).
    private def peek(how_far = 0)
      if token = @scanner.tokens[@index + how_far]?
        token
      else
        Token.new TokenType::EOF, "", -1
      end
    end

    # Returns whether the parser has reached the end of the token list.
    private def finished?
      @index >= @scanner.tokens.size || peek.type == TokenType::EOF
    end

    # Prints a parsing error to STDERR.
    private def report_error(line, message)
      @compilation_okay = false
      STDERR << "[line " << line << "]: parse error: " << message << "\n"
    end
  end
end