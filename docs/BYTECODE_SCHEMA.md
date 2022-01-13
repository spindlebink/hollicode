# Bytecode format schemas (bytecode format 0.1.0)

## Plain text

Plain text bytecode begins with a single JSON-encoded line containing the file header. This header will include:

* `version` - the version of the Hollicode compiler used to generate the file
* `bytecodeVersion` - the version of the bytecode format used in the file. As the language develops, its bytecode instruction set may change, so it's important that any interpreter do a double-check that the bytecode version is correct.

After the header, instructions are separated by new lines (`\n`). Each line will begin with a single word denoting the instruction. If the instruction takes an argument, the instruction name will be followed by a single tab character (`\t`), then the argument stretching to the end of the line.

* For Boolean literals (instruction `BOOL`), the argument will be either "true" or "false"
	
	```
	BOOL	true
	BOOL	false
	```

* For numeric literals (instruction `NUM`), the argument will be a floating point number in base 10

	```
	NUM	10.5
	NUM	35.0
	```

* For string literals (instruction `STR`), the argument will be an **unquoted** sequence of characters stretching to the end of the line. Special characters will be escaped with a backslash.

	```
	STR	Content of a string
	STR	String with "quotes" in it
	STR	String with\na newline\nand\ttabs\t\tgalore
	```

* For instructions taking an integer (`JMP`, `FJMP`, `TJMP`, `CALL`, and `OPT`), the argument will be an integer in base 10

	```
	CALL	2
	JMP	4
	```

A plain text Hollicode bytecode file may or may not end with a blank line.

## JSON

JSON bytecode has the following fields:
* `header` - the file header
	* `version` - the version of the compiler used to generate the file
	* `bytecodeVersion` - the version of the bytecode format used in the file. As the language develops, its bytecode instruction set may change, so it's important that any interpreter do a double-check that the bytecode version is correct.
* `instructions` - an array of instructions. Each instruction will be either A) a string, if the instruction takes no arguments or B) an array containing two items, the instruction name and its argument.

```json
{
	"header": {
		"version": "0.1.0",
		"bytecodeVersion": "0.1.0"
	},
	"instructions": {
		["STR", "Argument to STR instruction"],
		"ECHO"
	}
}
```

## Lua

Lua bytecode exports identically to the JSON format, except it's written as a Lua module instead of JSON notation. All fields are the same.
```lua
return {
	header = {version = "...", bytecodeVersion = "..."},
	instructions = {
		{"STR", "Argument to STR instruction"},
		"ECHO"
	}
}
```
