# Hollicode bytecode instructions

Hollicode compiles to a slim set of instructions designed to be easily interpreted from a dynamic language. Since we're talking narrative instructions here and not full program logic, performance isn't really an issue: depending on how interactive your narrative is, you'll be interpreting at most a couple dozen instructions at a time. With that in mind, Hollicode's bytecode is significantly higher-level than what you might expect if you're familiar with programming language implementation.

If you're new to bytecode or interpreters in general and you're looking to implement an interpreter for Hollicode in your language of choice, read on to the next section. If you know what you're doing and are just looking for a specification for Hollicode's instructions, skip to "Instruction specification" further down on this page.

## Implementing an interpreter

Bytecode is much less complicated than the name would suggest. All it really is is a simplified set of instructions that represents a computer program. Bytecode is easy to interpret and generally portable, a sort of universal (to compiler or ecosystem, at least) simplification of code into an atomic sequence of steps.

Where we might read `a = 1 + 2` to ourselves as "set variable `a` to the value of `1` plus `2`," stack-based bytecode might represent it as:

* push the integer 2 to the stack
* push the integer 1 to the stack
* remove the top two values from the stack, add them, and push their sum to the stack
* remove the top value from the stack and set the variable named `a` to it

More succinctly, in a fictional bytecode format, we might represent the above statement as:

```
INT 2
INT 1
ADD
SET a
```

At the end of the first two lines, the interpreter's stack is `[2 1]`. After `ADD`, it becomes `[3]`; after `SET a`, it becomes `[]`, and we've stored the `3` elsewhere, presumably wherever we keep variables.

Each operation is simple to execute, but, given a sufficiently knowledgeable compiler, any complex program can be reduced to them. The interpreter's job, then, is to take those operations, execute them correctly, and thereby produce the behavior we're looking for.

The Hollicode compiler generates bytecode like this. It can output multiple formats--plain text or JSON right now; MessagePack may be forthcoming, I just don't have a need for it at the moment--but each format is only a different way of expressing this sequence of operations.

To use Hollicode's compiled output in your game, you'll need an interpreter for its bytecode. Implementing a  interpreter is one of the more straightforward parts of writing a programming language. Here'll be your steps for a Hollicode interpreter:

* **Write a stack structure for the interpreter to use.** If you're using a scripting language like Lua or GDScript (what Hollicode's bytecode was designed for), you'll implement the stack as a simple table or array respectively. The stack needs to be capable of holding variables of multiple types with their type information included, since the Hollicode compiler doesn't have type-specific operators. You'll need methods to push to the top of the stack and pop things off the top of the stack.
	
	Here's a bare example of what an interpreter stack might look like in Lua, taking advantage of its flexible typing:
	```lua
	local stack = {}

	-- A `pop` method removes the top item in the stack and returns it
	local function pop()
		return table.remove(stack)
	end

	-- A `push` method adds a new value to the top of the stack
	local function push(what)
		table.insert(stack, what)
	end
	```

	You'll also need to implement a separate stack holding previous execution points. At various times during interpretation of a Hollicode program, you'll need to jump to different places in the code. When you do this, you'll need to store where you were so that when you're done executing that portion of code you can return to it.

* **Write a running loop.** The core of your interpreter will be a loop that takes a single instruction, executes it, and moves on to the next. This means you'll need an integer pointer to the current instruction's index. It'll be incremented and transformed throughout the life of the program.

	Bare Lua example:
	```lua
	-- Tradition demands we call it `ip` for Instruction Pointer
	local ip = 1
	local instructions = {}

	local executeCurrentInstruction, run, yield

	yield = false

	function executeCurrentInstruction()
		-- 1. Take current instruction, do instruction-specific code
		
		-- 2. When we're done with our instruction-specific code, increment `ip` as necessary. We may not always be incrementing it by `1`, since some instructions require jumping to specific points in the instruction list or incrementing IP by a certain amount.

		-- 3. We can also set `yield` to `true` in this method if an operation requests that the program pause, or if we reach the end of the instruction list.
		if ip > #instructions then
			yield = true
		end
	end

	function run()
		while not yield do
			executeCurrentInstruction()
		end
	end
	```

* **Implement code for each instruction.** This is the big one: a different procedure will need to run depending on what the current instruction is. Given the non-performance-sensitive nature of Hollicode's purpose, you can probably get by with just a big `switch` or `if` statement, although I'd recommend a more structured approach, such as a hash table of functions or something like that. It can be better for readability. It's up to you.

	Lua example (if statement):

	```lua
	function executeCurrentInstruction()
		-- Depending on how you load your instructions, you might obtain the instruction name through string matching or you might get it from a JSON parser. A short explanation of formats shows up in the next bullet point or in `BYTECODE_SCHEMA.md`.
		local instructionName = ... -- get current instruction name, however you might do it

		if instructionName == "POP" then
			pop()
			-- Be sure to increment the instruction pointer when we're done
			ip = ip + 1
		elseif instructionName == "NUM" then
			local numberValue = ... -- get the argument to the instruction (i.e. the 10 in `NUM	10`--
															-- once again, this'll be determined by the compilation format)
			push(tonumber(numberValue))
			ip = ip + 1
		elseif ... -- etc.; implement code for each operation
		end
	end
	```

	Lua example (function table):

	```lua
	local operations = {
		POP = function()
			pop()
			ip = ip + 1
		end,
		NUM = function(argument)
			push(tonumber(argument))
			ip = ip + 1
		end
	}

	function executeCurrentInstruction()
		local instructionName = ... -- see note above
		local argument = ... -- see note above--also, the operation may not take an argument, depending on what it is

		if operations[instructionName] then
			-- Look up the corresponding instruction from the table and call it
			operations[instructionName](argument)
		else
			-- Add a fail state if we haven't implemented one of the instructions
			error("unsupported instruction: " .. instructionName)
		end
	end
	```

* **Import instructions from a compiled Hollicode file.** Hollicode can compile to JSON or plain text at the moment. Both are easy to parse--basically every scripting language has either built-in JSON support or an easily-accessible package for it, and the plain text format is straightforward in its own right.
	
	The JSON format looks like this:
	```jsonc
	{
		"header": {
			// header info
		},
		// list of instructions:
		"instructions": [
			["GETV", "a"],
			["NUM", 10],
			["BOP", "+"]
			// ...
		]
	}
	```

	The plaintext format looks like this:
	
	```txt
	{header info}
	GETV	a
	NUM	10
	BOP +
	```
	
	Each operation name (`GETV`, `NUM`, `BOP` in this case) is guaranteed to be a string of characters with no spaces. If the operation takes an argument, the argument will be separated from the operation name by a tab character (`\t`).

	Once you've loaded a list of the compiled instructions from a file, the interpreter should start at the first instruction and work its way from there per the `run`/`executeCurrentInstruction` loop.

When you've got the framework of your interpreter down, you'll just need to implement code for each individual instruction. Following is a specification for what each one does.

## Instruction specification

Specified in pseudocode. The variable `ip` represents the current position of the interpreter in the instruction list. You'll need to implement these behaviors exactly in your interpreter, or the code won't run right.

### Core interpreter instructions

* `POP`

	Pop the top item off the stack and discard it.

	```
	stack.pop()
	ip = ip + 1
	```

* `JMP distance`

	Jump `distance` in the instruction list.

	`distance` here may be positive or negative.

	```
	ip = ip + distance
	```

* `FJMP distance`

	Pop the top item off the stack and jump `distance` if it evaluates to `false`.

	`distance` here may be positive or negative.

	```
	check = stack.pop()

	if not check:
		ip = ip + distance
	else:
		ip = ip + 1
	```

* `TJMP distance`

	Push the current instruction pointer to the traceback, then jump `distance` in the instruction list. This instruction is a jump command that keeps track of the position we jumped from, ensuring that we can return to it on receiving a `RET` instruction.

	```
	traceback.push(ip)
	ip = ip + distance
	```

* `RET`

	Pop the top item off the traceback stack and set the instruction pointer to the next instruction after it. If the traceback is empty, this should end execution.

	```
	if traceback.size() > 0:
		ip = traceback.pop() + 1
	else:
		execution_finished()
	```

* `NIL`

	Push a `nil`/`null`/`void` constant to the top of the stack.

	> Depending on your language, you may not be able to add nil values to arrays directly. I handle this fact in the Lua interpreter by keeping track of a unique table called `NIL_CONSTANT`, then checking for equality with it when popping or peeking from the stack and returning a real `nil` if the equality checks out.

	```
	stack.push(nil)
	ip = ip + 1
	```

* `BOOL boolean`

	Push a Boolean constant to the top of the stack. The argument is guaranteed to be either the string `true` or the string `false`.

	```
	if boolean == "true":
		stack.push(true)
	elseif boolean == "false":
		stack.push(false)
	ip = ip + 1
	```

* `STR string`

	Push a string constant to the top of the stack.

	```
	stack.push(string)
	ip = ip + 1
	```

* `GETV name`

	Obtain the value of a variable named `name` from the interpreter's environment and push its value to the top of the stack.

	> Make sure to do sufficient error checking, especially if you allow the interpreter's user to specify variable values themselves: either report an error and abort if a value isn't found, or push a `nil` to the stack. If a variable silently doesn't get added to the stack you'll likely get all sorts of errors.

	```
	value = get_variable_value(name)
	stack.push(value)
	ip = ip + 1
	```

* `GETF name`

	Obtain a pointer to a function named `name` from the interpreter's environment and push it to the top of the stack.

	If your language has first-class functions, you might implement this as a simple variable access+push. It's a separate instruction because not every language has first-class functions.

	> Once again, make sure to do sufficient error checking, especially if you allow the user to specify function handles themselves.

	```
	func = get_function_handle(name)
	stack.push(func)
	ip = ip + 1
	```

* `CALL num_args`

	Pop the top item off the stack, pop `num_args` items off the stack after that, and call the first item as a function, passing the popped values as arguments.

	> Arguments will have been compiled in reverse order, which means you can fill an array with them from 0-`num_args` as they pop off the stack. That is, for a function call `[do_thing arg1, arg2, arg3]`, Hollicode's compiler will compile the call as:
	> ```
	> GETV	arg3
	> GETV	arg2
	> GETV	arg1
	> GETF	do_thing
	> CALL	3
	> ```

	```
	func_handle = stack.pop()
	func_arguments = []

	for i from 0 to num_args:
		func_arguments.push(stack.pop())

	func_handle(func_arguments)
	```

* `NOT`

	Pop the top value off the stack, apply a Boolean `not` operator to it, and push it back.

	```
	stack.push(not stack.pop())
	```

* `NEG`

	Pop the top value off the stack, apply a numerical negative operator to it, and push it back.

	```
	stack.push(-stack.pop())
	```

* `BOP operator`

	Pop the top two values off the stack, apply a binary operator to them, and push the result to the stack.

	Valid operators (passed as strings) are:
	* `+` - addition
	* `-` - subtraction
	* `*` - multiplication
	* `/` - division
	* `>` - greater than
	* `>=` - greater than or equal
	* `<` - less than
	* `<=` - less than or equal
	* `==` - equal
	* `!=` - not equal
	* `&&` - Boolean and
	* `||` - Boolean or

	```
	left = stack.pop()
	right = stack.pop()
	switch operator:
		"+":
			stack.push(left + right)
		"-":
			stack.push(left - right)
		"*":
			stack.push(left * right)
		"/":
			stack.push(left / right)
		">":
			stack.push(left > right)
		">=":
			stack.push(left >= right)
		"<":
			stack.push(left < right)
		"<=":
			stack.push(left <= right)
		"==":
			stack.push(left == right)
		"!=":
			stack.push(left != right)
		"&&":
			stack.push(left and right)
		"||":
			stack.push(left or right)
	ip = ip + 1
	```

* `ECHO`

	Pop the top value off the stack and send it to the text buffer. The compiler will only ever use this instruction with a string on top of the stack.

	> This could be described as Hollicode's central function. When expressing a narrative, Hollicode will interpret lines of text to be said or written as calls to this instruction. For instance, the following code:
	> 
	> ```
	> > Conversation beginning
	> 	First thing someone says
	> 	Second thing someone says
	> 	Description of the room
	> 	Etcetera
	> ```
	>
	> Will result in four separate calls to `ECHO`. It's up to you as the interpreter writer to determine the most idiomatic way to use this instruction. In the GDScript-based interpreter I use for my WIP RPG, calling this instruction means emitting a signal which is hooked up to the scrolling text display object. In a debug environment, you might just `print` the top value on the stack.

	```
	message = stack.pop()
	text_buffer.append(message)
	ip = ip + 1
	```

### User input instructions

Hollicode can't assume narratives will be interactive in the same way, so it uses a method of requesting user input to follow branching narratives that will need to be tailored to your language and interpreter structure. Because of this, the following section will be more of a conceptual tutorial rather than a reference specification. Different languages work in different ways, and Hollicode's input instructions don't demand a particular format for their execution.

Two instructions remain for the interpreter, `OPT` and `WAIT`. From high up, the `OPT` instruction provides a possible option for the narrative to follow (e.g. a choice the player will make), then the `WAIT` instruction signals to the interpreter that all possible options have been specified and that the interpreter should await input. When input is received (e.g. the player selects a dialogue option), control will need to proceed to the point in execution associated with whatever option was selected.

As an example, the following code might be part of a conversation with an NPC:
```
> Conversation start
	"What can I do for you?" the shopkeeper says.

	[option] Tell me about your bookstore.
		She shrugs. "We've been here since...oh, sixteen, seventeen years?"
		"Used to be a lot busier. Not so much, now, what with...."
		She gestures vaguely at the dereliction around her.
		-> Conversation end

	[option] Actually, I think I'm good.
		-> Conversation end

	[wait]

> Conversation end
	The light is fading; snow has just begun to fall outside. You bid farewell to the shopkeeper. She nods and goes back to dusting the shelves.
```

We'll need a way to execute code for a given option, and we need to know when our options should become available.

In a fictitious RPG engine, we might express these options like this:
```lua
local function displayShopkeeperConversation()
	say('"What can I do for you?" the shopkeeper says.')
	local options = {
		["Tell me about your bookstore."] = function()
			say('She shrugs. "We\'ve been here since...oh, sixteen, seventeen years?"')
			say('"Used to be a lot busier. Not so much, now, what with...."')
			say('She trails off, gesturing vaguely at the dereliction around her.')
			goToPoint("Conversation end")
		end,
		["Actually, I think I'm good."] = function()
			goToPoint("Conversation end")
		end
	}
	showOptions(options)
end
```

This is, essentially, how `OPT` and `WAIT` work, but on a bytecode level. First, `OPT` registers a possible option, then `WAIT` sends a request to display them and requests input for which to take.

To do this, your interpreter will need to store the current instruction pointer when it receives an `OPT` command and push that stored value to an internal list of available options. When input is received (however your interpreter's interface for receiving it might work), execution should pick up from the next control instruction from the associated option, depending on which option gets picked. Pseudo-bytecode:

```
OPTION 1
	DO THING
	DO THING
OPTION 2
	DO THING
	DO THING
AWAIT INPUT
```

In this example, the interpreter will stop execution at `AWAIT INPUT`, presumably offering the viable options to the engine that's using it. Then, the engine will receive input and instruct the interpreter to travel to the beginning of whichever option's been selected. When that option has been executed, control returns to the instruction after `AWAIT INPUT`.

This process is how Hollicode's input bytecode works, with slightly different specifics. For example, the current iteration of the Lua reference interpreter manages options by calling an overrideable `onOption()` method when it comes across an `OPT` instruction. The programmer can use `onOption` to push options to a text buffer or otherwise create interactable objects for the player. Then, the interpreter provides an overrideable `onWait()` method which signals that the interpreter is awaiting input. When input's been received, the programmer signals to the interpreter to move to an option using `interpreter:selectOptionAndStart(optionIndex)`. Execution continues from there.

The point is that different languages or ecosystems will determine a useful workflow for `OPT` differently. It's up to you to implement option selection in a language-idiomatic way. What's important is that the interpreter's *semantics* for input line up with how the instructions are meant to work.

Here's as close as can be expressed to a specification of the `OPT` and `WAIT` instructions:

* `OPT num_args`

	Pop `num_args` values off the stack and signal to the interpreter's environment that an option has been received using those arguments. The interpreter should store the current instruction pointer internally so that when input is received the interpreter can proceed from that point.

	> Arguments will have been compiled in reverse order, which means you can fill an array with them from 0-`num_args` as they pop off the stack. See note at instruction `CALL`.

	```
	option_arguments = []

	for i from 0 to num_args:
		option_arguments.push(stack.pop())
	
	available_options.push(ip)
	ip = ip + 1
	signal_option(option_arguments)
	```

	Including multiple arguments allows options to be called like functions:
	```
	[option 4, true] Say something interesting
	```
	The above line will compile and be evaluated in the above pseudocode as `signal_option(["Say something interesting", 4, true])

* `WAIT`

	Halt execution and await input of a given option.

* *Option selection*

	Although not an instruction, selecting an option will need to be done with a couple of requirements to work right:
	
	* When an option is selected, execution should proceed to **the index of the instruction pointer at the associated `OPT` command plus 2**. In the above pseudocode, this means that a theoretical `select_option` method would look like this:

		```
		function select_option(option_index):
			ip = available_options[option_index] + 2
			available_options.clear()
		```

		The reason for this +2 instead of +1 is that the compiler generates a `JMP` command after an `OPT` command so that execution skips the body of the option on the first go-round. When executing an option, we need to skip both the `OPT` call (which'd be +1) and the `JMP` call (+2).
	
	* When an option is selected, all currently available options (pushed using `OPT`) should be cleared.