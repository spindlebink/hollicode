#
# prelude.cr
#

module Hollicode
  # Valid types of tokens.
  enum Hollicode::TokenType
    Undefined
    Indent
    Unindent
    TextLine
    ExpressionTag
    Anchor
    Goto
    OpenExpression
    CloseExpression    
    OpenParenthesis
    CloseParenthesis
    Word
    Dot
    Comma
    NumberLiteral
    StringLiteral
    BooleanLiteral
    NilLiteral
    If
    Else
    Option
    GreaterThan
    LessThan
    GreaterThanOrEqual
    LessThanOrEqual
    Equal
    EqualEqual
    NotEqual
    Not
    And
    Or
    Plus
    Minus
    Divide
    Multiply
  end

  # Token struct
  record Token, type = TokenType::Undefined, lexeme = "", line = 0

  # Statement class.
  #
  # Statements are individual text lines, anchors, directives, etc., along with
  # any associated children.
  class Statement
    property children = [] of Statement

    UNDEFINED = Statement.new

    # A root statement forms the root of the parsed AST.
    class Root < Statement
    end

    # A code directive enclosed in brackets with optional arguments and an
    # optional tag.
    class Directive < Statement
      getter start : Expression
      getter tag : Token
      property arguments = [] of Expression
      def initialize(@start, @tag = Token.new TokenType::Undefined, "", 0)
      end
    end

    # A line of text.
    class TextLine < Statement
      getter value : Token
      def initialize(@value)
      end
    end

    # An anchor.
    class Anchor < Statement
      getter value : Token
      def initialize(@value)
      end
    end

    # A goto statement.
    class Goto < Statement
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

  class Scanner; end
  class Parser; end
  class BytecodeGenerator; end
end