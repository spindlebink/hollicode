#
# compiler.cr
#

require "./scanner"
require "./bytecode_generator"

module Hollicode
  class Compiler
    # NEAR_TOKEN_ERROR_TRUNCATE_LIMIT = 16

    @source_string = ""
    @bytecode = BytecodeGenerator.new

    @scanner = Scanner.new
    @index = 0
    @compilation_okay = true

    enum Precedence
      None
      Assignment
      Or
      And
      Equality
      Comparison
      Term
      Factor
      Unary
      Call
      Primary
    end

    alias ParseRule = NamedTuple(prefix: Proc(Nil) | Nil, infix: Proc(Nil) | Nil, precedence: Precedence)
    @parse_rules : Hash(TokenType, ParseRule)
    
    def initialize
      @parse_rules = {
        TokenType::OpenParenthesis     => {prefix: ->parse_grouping, infix: nil, precedence: Precedence::None},
        TokenType::Minus               => {prefix: ->parse_unary, infix: ->parse_binary, precedence: Precedence::Term},
        TokenType::Plus                => {prefix: nil, infix: ->parse_binary, precedence: Precedence::Term},
        TokenType::Divide              => {prefix: nil, infix: ->parse_binary, precedence: Precedence::Factor},
        TokenType::Multiply            => {prefix: nil, infix: ->parse_binary, precedence: Precedence::Factor},
        TokenType::NumberLiteral       => {prefix: ->parse_number, infix: nil, precedence: Precedence::None},
        TokenType::Boolean             => {prefix: ->parse_literal, infix: nil, precedence: Precedence::None}
      }
    end

    # Compiles a string of source into bytecode.
    def compile(@source_string)
      @compilation_okay = true
      @scanner.scan @source_string

      @scanner.tokens.each do |token|
        puts token
      end
      # expression

      @compilation_okay
    end

    # Compiles an expression.
    def parse_expression
      parse_precedence Precedence::Assignment
      return
    end

    # Parses a grouped expression.
    def parse_grouping
      consume TokenType::OpenParenthesis
      parse_expression
      consume TokenType::CloseParenthesis
      return
    end

    # Parses a unary operation.
    def parse_unary
      operator_type = peek(-1).type
      parse_precedence Precedence::Unary
      case operator_type
      when TokenType::Minus
        @bytecode.push_negate
      when TokenType::Not
        @bytecode.push_not
      end
      return
    end

    # Parses a binary expression.
    def parse_binary
      operator_type = peek(-1).type
      rule = get_rule operator_type
      parse_precedence rule[:precedence] + 1
      case operator_type
      when TokenType::Plus
        @bytecode.push_add
      when TokenType::Minus
        @bytecode.push_subtract
      when TokenType::Multiply
        @bytecode.push_multiply
      when TokenType::Divide
        @bytecode.push_divide
      end
      return
    end

    # Parses a number constant.
    def parse_number
      value = peek(-1).lexeme.to_f
      @bytecode.push_number value
      return
    end

    def parse_precedence(precedence)
      advance
      prefix_rule = get_rule(peek(-1).type)[:prefix]
      if prefix_rule.nil?
        puts "expect expression"
        return
      end
      
      prefix_rule.call
      
      while precedence <= get_rule(peek.type).precedence
        advance
        infix_rule = get_rule peek(-1).infix
        infix_rule.call
      end

      return
    end

    # Gets the parser rule for a given token type.
    private def get_rule(token_type)
      if rule = @parse_rules[token_type]?
        rule
      else
        {prefix: nil, infix: nil, precedence: Precedence::None}
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
    private def advance
      token = peek
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
          break
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
        Token.new TokenType::Undefined, "", -1
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