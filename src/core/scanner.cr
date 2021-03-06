#
# scanner.cr
#

module Hollicode
  # Valid types of tokens.
  enum Hollicode::TokenType
    Undefined
    Indent
    Unindent
    TextLine
    DirectiveTag
    Anchor
    Goto
    OpenDirective
    CloseDirective
    OpenParenthesis
    CloseParenthesis
    Word
    Dot
    Comma
    Colon
    NumberLiteral
    StringLiteral
    BooleanLiteral
    NilLiteral
    If
    Else
    Include
    Option
    Wait
    Return
    Equal
    Not
    GreaterThan
    LessThan
    GreaterThanOrEqual
    LessThanOrEqual
    EqualEqual
    NotEqual
    And
    Or
    Plus
    Minus
    Divide
    Multiply

    Error
    BOF
    EOF
  end

  # Token struct
  record Token, type = TokenType::Undefined, lexeme = "", line = 0

  # Scanner class. Takes a string of code and produces an array of tokens.
  class Scanner
    TAB_SIZE                               = 8
    ERROR_MESSAGE_BAD_UNINDENT             = "unmatched indentation level"
    ERROR_MESSAGE_UNTERMINATED_EXPRESSION  = "mismatched expression brackets"
    ERROR_MESSAGE_UNTERMINATED_PARENTHESES = "mismatched parentheses"
    ERROR_MESSAGE_UNTERMINATED_STRING      = "unterminated string"
    ERROR_MESSAGE_MIXED_INDENTATION        = "mixed tabs and spaces"
    ERROR_MESSAGE_UNEXPECTED_CHARACTER     = "unexpected character"

    @source = ""
    @indent_stack = [] of Int32
    @tokens = Array(Token).new
    @current_line = 1
    @start_index = 0
    @current_index = 0

    @newline = true

    getter tokens

    # Scans a string of source, populating the `tokens` array with scanned
    # tokens.
    def scan(@source)
      @indent_stack.clear
      @indent_stack << 0
      @tokens.clear
      @tokens << Token.new TokenType::BOF, lexeme = "", line = 0
      @current_line = 1
      @start_index = 0
      @current_index = 0
      @newline = true
      while !finished?
        scan_next
      end
      while @indent_stack.last != 0
        push_custom_token TokenType::Unindent
        @indent_stack.pop
      end
      push_custom_token TokenType::EOF

      # @tokens.each do |token|
      #   puts "#{token.line}: #{token.type} #{token.lexeme}"
      # end
    end

    # Scans the next token in the source string.
    private def scan_next
      c = peek
      # puts "scan next: '#{c}'"
      case c
      when ' ', '\t'
        if @newline
          # Skip forward to the first non-skip character--the scanner doesn't
          # store comments, empty lines, or unnecessary indents
          while peek != Char::ZERO && (peek == ' ' || peek == '\t' || peek == '\n')
            if peek == '\n'
              @current_line += 1
            end
            advance
            if peek == '~' && peek(1) == '~'
              advance_to_newline
            end
          end
          # Now rewind to the beginning of that line
          while peek(-1) != '\n' && peek(-1) != Char::ZERO
            # puts "back: '#{peek(-1)}' at index #{@current_index}"
            advance -1
          end
          @newline = false

          # https://docs.python.org/3/reference/lexical_analysis.html#indentation
          indent_level = 0
          tab_stop = TAB_SIZE
          while peek == ' ' || peek == '\t'
            if peek == ' '
              indent_level += 1
              tab_stop -= 1
              if tab_stop == 0
                tab_stop = TAB_SIZE
              end
            else
              indent_level += tab_stop
              tab_stop = TAB_SIZE
            end
            advance
          end
          if peek == '\n'
            @newline = true
            @current_line += 1
            advance
          else
            if indent_level > @indent_stack.last
              @indent_stack << indent_level
              push_custom_token TokenType::Indent
            elsif indent_level < @indent_stack.last
              while @indent_stack.size > 1 && @indent_stack.last != indent_level
                push_custom_token TokenType::Unindent
                @indent_stack.pop
              end
              if indent_level != @indent_stack.last
                push_custom_token TokenType::Error, ERROR_MESSAGE_BAD_UNINDENT
              end
            end
          end
        else
          advance
        end
        @start_index = @current_index
      when '\n'
        @newline = true
        @current_line += 1
        advance
        @start_index = @current_index
      else
        if @newline
          @newline = false
          while @indent_stack.size > 1
            push_custom_token TokenType::Unindent
            @indent_stack.pop
          end
        end
        case c
        when '@'
          scan_expression
        when '-'
          advance
          if match_and_advance('>')
            advance_to_newline
            token_string = get_token_string.lchop("->").lstrip
            push_token TokenType::Goto, token_string
          else
            # explicit text line
            advance_to_newline
            token_string = get_token_string.lstrip
            push_token TokenType::TextLine, token_string.lchop("-").lstrip
          end
        when '#'
          advance_to_newline
          token_string = get_token_string.lchop('#').lstrip
          push_token TokenType::Anchor, token_string
        when '~'
          # comment
          if peek(1) == '~'
            advance_to_newline
            # token_string = get_token_string.lchop("~~")
            # push_token TokenType::Comment, token_string
          end
        when Char::ZERO
          advance
        else
          advance_to_newline
          push_token TokenType::TextLine
        end
      end
    end

    # Scans tokens for an expression.
    private def scan_expression
      bracket_depth = 0
      paren_depth = 0
      directive_done = false
      # skip opening @
      if peek == '@'
        push_token TokenType::OpenDirective
        advance
      end
      while !directive_done
        @start_index = @current_index
        case c = advance
        when '@'
          push_custom_token TokenType::Error, ERROR_MESSAGE_UNEXPECTED_CHARACTER, @current_line
        when '\n', Char::ZERO
          push_token TokenType::CloseDirective
          @newline = true
          directive_done = true
        when '('
          push_token TokenType::OpenParenthesis
          paren_depth += 1
        when ')'
          push_token TokenType::CloseParenthesis
          paren_depth -= 1
        when '"', '\''
          scan_string
        when ':'
          while !finished?
            if peek == '\n'
              break
            end
            advance
          end
          lexeme = get_token_string.lchop(":").lstrip
          push_custom_token TokenType::DirectiveTag, lexeme
        when '.'
          if peek.number?
            scan_number
          else
            push_token TokenType::Dot
          end
        when ','
          push_token TokenType::Comma
        when '>'
          push_token match_and_advance('=') ? TokenType::GreaterThanOrEqual : TokenType::GreaterThan
        when '<'
          push_token match_and_advance('=') ? TokenType::LessThanOrEqual : TokenType::LessThanOrEqual
        when '='
          push_token match_and_advance('=') ? TokenType::EqualEqual : TokenType::Equal
        when '!'
          push_token match_and_advance('=') ? TokenType::NotEqual : TokenType::Not
        when '+'
          push_token TokenType::Plus
        when '-'
          push_token TokenType::Minus
        when '*'
          push_token TokenType::Multiply
        when '/'
          push_token TokenType::Divide
        when '&'
          if match_and_advance('&')
            push_token TokenType::And
          else
            push_custom_token TokenType::Error, ERROR_MESSAGE_UNEXPECTED_CHARACTER
          end
        when '|'
          if match_and_advance('|')
            push_token TokenType::Or
          end
        else
          if c.number?
            scan_number
          elsif c == '_' || c.letter?
            advance -1
            scan_word
          end
        end
      end

      if paren_depth > 0
        push_custom_token TokenType::Error, ERROR_MESSAGE_UNTERMINATED_PARENTHESES
      end
    end

    # Scans token for a number.
    private def scan_number
      started_with_dot = peek(-1) == '.'
      while peek.try &.number?
        advance
      end
      if !started_with_dot
        if peek == '.'
          advance
          while peek.try &.number?
            advance
          end
        end
      end
      push_token TokenType::NumberLiteral
    end

    # Scans token for a string literal.
    private def scan_string
      opening_quote = peek -1
      escaped = false
      starting_line = @current_line
      str = String::Builder.new
      while !(peek == opening_quote && !escaped)
        if peek == '\\'
          escaped = true
        elsif peek == Char::ZERO
          push_custom_token TokenType::Error, ERROR_MESSAGE_UNTERMINATED_STRING, starting_line
          break
        else
          if escaped
            escaped = false
            case peek
            when 'n'
              str << "\n"
            when 't'
              str << "\t"
            when 'r'
              str << "\r"
            else
              str << peek
            end
          else
            str << peek
            if peek == "\n"
              @current_line += 1
            end
          end
        end
        advance
      end
      advance
      push_custom_token TokenType::StringLiteral, str.to_s, starting_line
    end

    # Scans token for a word.
    private def scan_word
      advance
      while peek == '_' || peek.try &.letter? || peek.try &.number?
        advance
      end
      word = get_token_string
      # 'not', 'and', and 'or' are equivalent to !, &&, and ||, so we have to
      # treat them as distinct operator tokens
      if word == "not"
        push_token TokenType::Not
      elsif word == "and"
        push_token TokenType::And
      elsif word == "or"
        push_token TokenType::Or
      elsif word == "true" || word == "false"
        push_token TokenType::BooleanLiteral
      elsif word == "nil"
        push_token TokenType::NilLiteral
      elsif word == "if"
        push_token TokenType::If
      elsif word == "else"
        push_token TokenType::Else
      elsif word == "include"
        push_token TokenType::Include
      elsif word == "wait"
        push_token TokenType::Wait
      elsif word == "option"
        push_token TokenType::Option
      elsif word == "return"
        push_token TokenType::Return
      else
        # On the other hand, we handle differentiation between function calls
        # and if/elseif/else statements in the parser
        push_token TokenType::Word
      end
    end

    # Returns whether the scanner has reached the end of the source string.
    private def finished?
      return @current_index >= @source.size
    end

    # Gets the string between `start_index` and `current_index`.
    private def get_token_string
      @source[@start_index...@current_index]
    end

    # Pushes a token of type `token_type` to the stack.
    private def push_token(token_type, lexeme = get_token_string)
      @tokens << Token.new token_type, lexeme, @current_line
      @start_index = @current_index
    end

    # Pushes an empty token of type `token_type` to the stack.
    private def push_custom_token(token_type, lexeme = "", line = @current_line)
      @tokens << Token.new token_type, lexeme, line
    end

    # Gets the current character and advances the index by one.
    private def advance(n = 1)
      c = peek
      @current_index += n
      if @current_index < 0
        @current_index = 0
      end
      return c
    end

    # Advances to the next new line or end of file.
    private def advance_to_newline
      while peek != Char::ZERO && peek != '\n'
        advance
      end
    end

    # Advances if the next character is `match_char`. Returns `true` if it was.
    private def match_and_advance(match_char)
      if peek.nil? || peek != match_char
        return false
      else
        @current_index += 1
        return true
      end
    end

    # Gets the current character without advancing the index.
    private def peek(how_far = 0)
      if @current_index + how_far < 0 || @current_index + how_far >= @source.size
        Char::ZERO
      else
        @source[@current_index + how_far]
      end
    end
  end
end
