#
# parser.cr
#

module Hollicode
  # Parser class. Takes an array of tokens and produces an AST.
  class Parser
    @tokens = [] of Token
    @index = 0
    @parse_root = Statement::UNDEFINED

    getter parse_root

    # Parses an array of tokens.
    def parse(@tokens)
      @index = 0
      @parse_root = Statement::Root.new
      @parse_root.children = parse_statement_children
    end

    # Parses a statement and its children.
    private def parse_statement
      statement = Statement::UNDEFINED
      if match_any TokenType::OpenExpression
        start = parse_expression
        arguments = [] of Expression
        while !peek.try &.type.== TokenType::CloseExpression
          argument = parse_expression
          arguments << argument
          if match_any TokenType::Comma
          end
        end
        if !match_any TokenType::CloseExpression
          puts "warning: unterminated expression"
        end
        if match_any TokenType::ExpressionTag
          statement = Statement::Directive.new start, peek(-1).not_nil!
          statement.arguments = arguments
        else
          statement = Statement::Directive.new start
          statement.arguments = arguments
        end
      elsif match_any TokenType::TextLine
        statement = Statement::TextLine.new peek(-1).not_nil!
      elsif match_any TokenType::Anchor
        statement = Statement::Anchor.new peek(-1).not_nil!
      elsif match_any TokenType::Goto
        statement = Statement::Goto.new peek(-1).not_nil!
      end
      if match_any TokenType::Indent
        statement.children = parse_statement_children
        if !match_any TokenType::Unindent
          puts "warning: unknown lex error: unterminated block"
        end
      end
      statement
    end

    # Parses an array of statements.
    private def parse_statement_children
      children = [] of Statement
      while check_any TokenType::OpenExpression, TokenType::TextLine, TokenType::Anchor, TokenType::Goto
        children << parse_statement
      end
      return children
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

    # expression -> equality
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
        if peek.try &.type.== token_type
          advance
          return true
        end
      end
    end

    # Returns `true` if the next token is any of the given types. Does not
    # consume the token.
    private def check_any(*token_types)
      token_types.each do |token_type|
        if peek.try &.type.== token_type
          return true
        end
      end
    end

    # Consumes the current token and returns it.
    private def advance
      t = peek
      @index += 1
      return t
    end

    # Peeks at the token at +- `how_far` (defaults to 0, which denotes current
    # token).
    private def peek(how_far = 0)
      @tokens[@index + how_far]?
    end

    # Returns whether the parser has reached the end of the token list.
    private def finished?
      @index >= @tokens.size
    end
  end
end
