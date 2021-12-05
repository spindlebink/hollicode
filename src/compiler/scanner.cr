#
# scanner.cr
#

module Hollicode
  # Scanner class. Takes a string of code and produces an array of tokens.
  class Scanner
    TAB_SIZE = 8

    @source = ""
    @indent_stack = [] of Int32
    @tokens = Array(Token).new
    @current_line = 0
    @start_index = 0
    @current_index = 0

    @newline = false

    getter tokens

    # Scans a string of source, populating the `tokens` array with scanned
    # tokens.
    def scan(@source)
      @indent_stack.clear
      @indent_stack << 0
      @tokens.clear
      @current_line = 0
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
    end

    # Scans the next token in the source string.
    private def scan_next
      c = peek
      if !c.nil?
        case c
        when ' ', '\t'
          if @newline
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
              advance
            else
              # print "at border of ", peek.not_nil!, ", indent was ", indent_level, " and stack was ", @indent_stack, "\n"
              if indent_level > @indent_stack.last
                @indent_stack << indent_level
                push_custom_token TokenType::Indent
              elsif indent_level < @indent_stack.last
                while @indent_stack.size > 1 && @indent_stack.last != indent_level
                  push_custom_token TokenType::Unindent
                  @indent_stack.pop
                end
                if indent_level != @indent_stack.last
                  puts "indentation error: unexpected indentation"
                end
              end
            end
          else
            advance
          end
          @start_index = @current_index
        when '\n'
          @newline = true
          advance
        else
          if @newline
            @newline = false
            while @indent_stack.size > 1
              push_custom_token TokenType::Unindent
              @indent_stack.pop
            end
          end
          case c
          when '['
            scan_expression
          when '-'
            advance
            if match_and_advance('>')
              advance_to_newline
              token_string = get_token_string.lchop("->").lstrip
              push_token TokenType::Goto, token_string
            end
          when '#'
            advance_to_newline
            token_string = get_token_string.lchop("#").lstrip
            push_token TokenType::Anchor, token_string
          else
            advance_to_newline
            push_token TokenType::TextLine
          end
        end
      end
    end

    # Scans tokens for an expression.
    private def scan_expression
      bracket_depth = 0
      paren_depth = 0
      while !finished?
        @start_index = @current_index
        case c = advance
        when '['
          push_token TokenType::OpenExpression
          bracket_depth += 1
        when ']'
          push_token TokenType::CloseExpression
          bracket_depth -= 1
        when '('
          push_token TokenType::OpenParenthesis
          paren_depth += 1
        when ')'
          push_token TokenType::CloseParenthesis
          paren_depth -= 1
        when '.'
          if peek.try &.number?
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
        when '&'
          if match_and_advance('&')
            push_token TokenType::And
          end
        when '|'
          if match_and_advance('|')
            push_token TokenType::Or
          end
        else
          if c.try &.number?
            scan_number
          elsif c == '_' || c.try &.letter?
            scan_word
          end
        end
        if bracket_depth == 0
          if paren_depth > 0
            puts "warning: unterminated parenthetical"
          end
          while peek == ' ' || peek == '\t'
            advance
          end
          @start_index = @current_index
          if !peek.nil? && peek != '\n'
            while !peek.nil? && peek != '\n'
              advance
            end
            push_token TokenType::ExpressionTag
          end
          return
        end
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

    # Scans token for a word.
    private def scan_word
      while peek == '_' || peek.try &.letter?
        advance
      end
      while peek.try &.number?
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

    private def get_token_string
      @source[@start_index...@current_index]
    end

    # Pushes a token of type `token_type` to the stack.
    private def push_token(token_type, lexeme = get_token_string)
      @tokens << Token.new token_type, lexeme, @current_line
      @start_index = @current_index
    end

    # Pushes an empty token of type `token_type` to the stack.
    private def push_custom_token(token_type, lexeme = "")
      @tokens << Token.new token_type, lexeme, @current_line
    end

    # Gets the current character and advances the index by one.
    private def advance
      c = peek
      @current_index += 1
      return c
    end

    # Advances to the next new line or end of file.
    private def advance_to_newline
      while !peek.nil? && peek != '\n'
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
      return @source[@current_index + how_far]?
    end
  end
end
