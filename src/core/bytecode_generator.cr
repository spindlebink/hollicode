#
# bytecode_generator.cr
#

module Hollicode
  class BytecodeGenerator
    abstract struct Operation; end

    struct NumberConstantOp < Operation
      getter value : Float64
      def initialize(@value)
      end
    end

    struct StringConstantOp < Operation
      getter value : String
      def initialize(@value)
      end
    end

    struct BooleanConstantOp < Operation
      getter value : Bool
      def initialize(@value)
      end
    end

    macro define_no_args_op(method_name, operation_name)
      struct {{operation_name}} < Operation
      end

      def {{method_name}}
        @operations << {{operation_name}}.new
      end
    end

    define_no_args_op push_return, ReturnOp
    define_no_args_op push_negate, NegateOp
    define_no_args_op push_not, NotOp
    define_no_args_op push_add, AddOp
    define_no_args_op push_subtract, SubtractOp
    define_no_args_op push_multiply, MultiplyOp
    define_no_args_op push_divide, DivideOp
    define_no_args_op push_true, PushTrueOp
    define_no_args_op push_false, PushFalseOp

    @operations = [] of Operation

    def push_number(value)
      @operations << NumberConstantOp.new value
    end

    def push_string(value)
      @operations << StringConstantOp.new value
    end

    def push_boolean(value)
      @operations << BooleanConstantOp.new value
    end
  end
end
