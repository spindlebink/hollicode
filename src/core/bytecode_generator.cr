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

    define_no_args_op 0x00, push_return, ReturnOp
    define_no_args_op 0x01, push_pop, PopOp
    define_single_arg_op 0x02, push_jump, JumpOp, Int32
    define_single_arg_op 0x03, push_jump_if_false, JumpIfFalseOp, Int32
    define_single_arg_op 0x04, push_traced_jump, TracedJumpOp, Int32
    define_no_args_op 0x10, push_nil, NilOp
    define_single_arg_op 0x11, push_boolean, BooleanConstantOp, Bool
    define_single_arg_op 0x12, push_number, NumberConstantOp, Float64
    define_single_arg_op 0x13, push_string, StringConstantOp, String
    define_single_arg_op 0x14, push_variable, VariableOp, String
    define_no_args_op 0x15, push_lookup, LookupOp
    define_no_args_op 0x21, push_not, NotOp
    define_no_args_op 0x22, push_negate, NegateOp
    define_single_arg_op 0x23, push_binary_op, BinaryOP, String
    define_single_arg_op 0x40, push_call, CallOp, Int32
    define_no_args_op 0x41, push_echo, EchoOp
    define_single_arg_op 0x42, push_option, OptionOp, Int32
    define_no_args_op 0x43, push_wait, WaitOp

    @op_names = {
      0x00 => "RET",
      0x01 => "POP",
      0x02 => "JMP",
      0x03 => "FJMP",
      0x04 => "TJMP",
      0x10 => "NIL",
      0x11 => "BOOL",
      0x12 => "NUM",
      0x13 => "STR",
      0x14 => "GETV",
      0x15 => "LOOK",
      0x21 => "NOT",
      0x22 => "NEG",
      0x23 => "BOP",
      0x40 => "CALL",
      0x41 => "ECHO",
      0x42 => "OPT",
      0x43 => "WAIT",
    }

    @header_operations = [] of Operation
    @operations = [] of Operation

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
            if (value_string = operation.value).is_a? String
              str << "\t" << value_string.gsub({'"' => "\\\"", '\n' => "\\\n"})
            else
              str << "\t" << operation.value
            end
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
                      operation.value.to_json json
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

    def get_lua
      String.build do |str|
        str << "return {\n"
        str << "\theader = {version = \"#{LANGUAGE_VERSION}\", bytecodeVersion = \"#{BYTECODE_FORMAT_VERSION}\"},\n"
        if @operations.size == 0
          str << "\tinstructions = {}\n"
        else
          str << "\tinstructions = {\n"
          @operations.each_with_index do |operation, index|
            if operation.responds_to? :value
              str << "\t\t{"
              write_lua_value str, @op_names[operation.op_code]
              str << ", "
              write_lua_value str, operation.value
              str << "}"
            else
              str << "\t\t"
              write_lua_value str, @op_names[operation.op_code]
            end
            if index != @operations.size - 1
              str << ","
            end
            str << "\n"
          end
          str << "\t}\n"
        end
        str << "}"
      end
    end

    protected def write_lua_value(io, value)
      if value.is_a? String
        io << "\"" << value.gsub({'"' => "\\\"", '\n' => "\\\n"}) << "\""
      elsif value.is_a? Bool
        io << (value ? "true" : "false")
      else
        io << value
      end
    end

    protected def num_ops
      @operations.size
    end
  end
end
