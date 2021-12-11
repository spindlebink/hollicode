#
# bytecode_generator.cr
#

require "json"
require "./core"

module Hollicode
  class BytecodeGenerator
    BYTECODE_FORMAT_VERSION = "0.1.0"

    abstract class Operation; end

    macro define_no_args_op(op_code, method_name, operation_name)
      class {{operation_name}} < Operation
        getter op_code = {{op_code}}
      end

      def {{method_name}}
        @operations << {{operation_name}}.new
      end

      def {{method_name}}_header
        @header_operations << {{operation_name}}.new
      end
    end

    macro define_single_arg_op(op_code, method_name, operation_name, arg_type)
      class {{operation_name}} < Operation
        getter op_code = {{op_code}}
        property value : {{arg_type}}
        def initialize(@value)
        end
      end

      def {{method_name}}(value : {{arg_type}})
        op = {{operation_name}}.new value
        @operations << op
        op
      end

      def {{method_name}}_header(value : {{arg_type}})
        op = {{operation_name}}.new value
        @header_operations << op
        op
      end
    end

    define_no_args_op    0x00,  push_return,        ReturnOp
    define_no_args_op    0x01,  push_pop,           PopOp
    define_single_arg_op 0x02,  push_jump,          JumpOp,            Int32
    define_single_arg_op 0x03,  push_jump_if_false, JumpIfFalseOp,     Int32
    define_single_arg_op 0x04,  push_goto,          GotoOp,            Int32
    define_no_args_op    0x10,  push_nil,           NilOp
    define_single_arg_op 0x11,  push_boolean,       BooleanConstantOp, Bool
    define_single_arg_op 0x12,  push_number,        NumberConstantOp,  Float64
    define_single_arg_op 0x13,  push_string,        StringConstantOp,  String
    define_single_arg_op 0x14,  push_variable,      VariableOp,        String
    define_single_arg_op 0x15,  push_function,      FunctionOp,        String
    define_no_args_op    0x20,  push_not,           NotOp
    define_no_args_op    0x21,  push_negate,        NegateOp
    define_single_arg_op 0x22,  push_call,          CallOp,            Int32
    define_no_args_op    0x23,  push_add,           AddOp
    define_no_args_op    0x24,  push_subtract,      SubtractOp
    define_no_args_op    0x25,  push_multiply,      MultiplyOp
    define_no_args_op    0x26,  push_divide,        DivideOp
    define_no_args_op    0x27,  push_or,            OrOp
    define_no_args_op    0x28,  push_and,           AndOp
    define_no_args_op    0x29,  push_inequality,    NotEqualOp
    define_no_args_op    0x2a,  push_equality,      EqualityOp
    define_no_args_op    0x2b,  push_lesser_equal,  LessThanOrEqualOp
    define_no_args_op    0x2c,  push_greater_equal, GreaterThanOrEqualOp
    define_no_args_op    0x2d,  push_lesser,        LessThanOp
    define_no_args_op    0x2e,  push_greater,       GreaterThanOp
    define_no_args_op    0x40,  push_echo,          EchoOp
    define_no_args_op    0x41,  push_option,        OptionOp
    define_no_args_op    0x42,  push_wait,          WaitOp

    @op_names = {
      0x00 => "RET",
      0x01 => "POP",
      0x02 => "JMP",
      0x03 => "FJMP",
      0x04 => "GOTO",
      0x10 => "NIL",
      0x11 => "BOOL",
      0x12 => "NUM",
      0x13 => "STR",
      0x14 => "GETV",
      0x15 => "GETF",
      0x20 => "NOT",
      0x21 => "NEG",
      0x22 => "CALL",
      0x23 => "ADD",
      0x24 => "SUB",
      0x25 => "MULT",
      0x26 => "DIV",
      0x27 => "OR",
      0x28 => "AND",
      0x29 => "NEQ",
      0x2a => "EQ",
      0x2b => "LEQ",
      0x2c => "GEQ",
      0x2d => "LESS",
      0x2e => "MORE",
      0x40 => "ECHO",
      0x41 => "OPT",
      0x42 => "WAIT"
    }

    @header_operations = [] of Operation
    @operations = [] of Operation

    def num_ops
      @operations.size
    end

    def get_plain_text
      String.build do |str|
        str << JSON.build do |json|
          json.object do
            json.field "version", LANGUAGE_VERSION
            json.field "bytecodeVersion", BYTECODE_FORMAT_VERSION
          end
        end
        str << "\n"
        @operations.each do |operation|
          str << @op_names[operation.op_code]
          if operation.responds_to? :value
            str << "\t" << operation.value
          end
          str << "\n"
        end
      end
    end

    def get_json
      String.build do |str|
        str << JSON.build do |json|
          json.object do
            json.field "header" do
              json.object do
                json.field "version", LANGUAGE_VERSION
                json.field "bytecodeVersion", BYTECODE_FORMAT_VERSION
              end
            end
            json.field "instructions" do
              json.array do
                @operations.each do |operation|
                  if operation.responds_to? :value
                    json.array do
                      json.string @op_names[operation.op_code]
                      if operation.responds_to? :value
                        operation.value.to_json json
                      end
                    end
                  else
                    json.string @op_names[operation.op_code]
                  end
                end
              end
            end
          end
        end
      end
    end

    def debug_print
      @operations.each do |operation|
        if operation.responds_to? :value
          print operation.class.to_s, " ", operation.value, "\n"
        else
          puts operation.class.to_s
        end
      end
    end
  end
end
