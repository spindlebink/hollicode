# Hollicode semi-formal specification

## Preamble

Hollicode is a DSL designed for writing interactive narratives. It's capable of expressing anything from simple Twine-style branching narratives to *Disco Elysium*'s systems-heavy dialog.

It's designed to do so with as slim of a language specification as possible. It makes no assumptions about which side of the narrative spectrum your project is on, and as such it leaves the implementation of a lot of methods up to the user, to be determined interpreter-side. Where something like Ren'Py comes with methods for displaying a speaker image, backgrounds, switching scenes, etc., Hollicode provides instead a bytecode whose flexibility lies in its deferring project-specific features to the interpreter's environment. For example, to display a speaker image or background, you'd first write a function to do so in your game engine's code format, then you'd call that function from Hollicode. 

Although this technique offloads work to the game writer, it keeps Hollicode lean and scalable. You can write an interpreter for Hollicode's bytecode in only a couple hundred lines of pretty much any dynamic language. Then, you can design a library of methods Hollicode can call that'll complement your game.

**Hollicode isn't a game engine.** You will need to write code to use this language, and you'll need to be familiar with the engine you're using it in. And, depending on your choice of engine, you'll need to be able to implement a bytecode interpreter in its language of choice. (With that said, the bytecode spec is designed to be easily understood by even those with little familiarity with how bytecode interpreters work, so if you're decently proficient in a programming language, implementing an interpreter is much less work than you might think.)

## Syntax

Hollicode uses white space for indentation. And, just as is the case with any other indentation-based language, **it's a bad idea to mix tabs and spaces in the same file.** Doing so will eventually get promoted up to error status. Just don't.

### Comments

```
~~ Comments begin with `~~` (two tilde symbols) and run to the end of the line.
~~
~~ They're completely ignored by the parser.
```

### Anchor points & go-to statements

Anchor points begin with `#` and run to the end of the line. Go-to statements begin with `->` and run likewise to the end of the line. When execution reaches a go-to statement, it will hop to the associated anchor point and continue from there.

```
# Anchor point

-> Anchor point

~~ Control never reaches here
```

Names for anchor points are **not** case-sensitive, and punctuation is stripped from them during processing. White space is retained after the first character in the anchor point's name.
```
~~ All these refer to the same anchor point, and they're all valid, but please god no.
-> Anchor point
-> anchor point
->            ANCHOR POINT
-> /anc*h))o|r ,p,o,i,n,t,
```

### Lines of text

If a line isn't preceded by `#`, `>`, or `->`, it's interpreted as a line of text and will be pushed as-is to the interpreter. Your narrative's script proper will be written using these statements.

Text lines begin after preceding indentation and continue to the end of the line. You don't need to escape special characters.
```
# Conversation anchor point
A line of text.
A line of text "with quotes" and !@#$% special characters.
```

You can optionally begin a line of text with a single hyphen `-`. If you do so, the line will be interpreted as beginning at the first non-whitespace character after it. You can use this behavior if for example a line needs to begin with `->`, `#`, `[`, or `>`.

```
- A line of text
- -> A line of text which would ordinarily be interpreted as a go-to statement.
- # And one which would be an anchor
```

If a line of text is followed by an indented block of *only* text lines, the indented block will be appended to the line of text as a multiline string. Including anything but text lines in an indented block after a line of text results in a compilation error.

```
A line of text which continues a decently long way and which might benefit from
	being broken up into multiple lines, splitting at the 80-character point
	because that's a nice round number and standard for programming in general.
```

Multiline texts like this are concatenated with spaces in between them.

### Directives

Directives embed function calls, variable evaluation, and control flow into your script. They're prefixed with an `@` symbol.

```
@finger_point_sting
Objection!
```

When the interpreter executes the above example, it'll fetch a variable named `finger_point_sting` from the interpreter and call it as a function, following it with the line "Objection!" sent as a regular text line.

You can pass arguments to directives using formatting similar to that in most scripting languages. They must be separated by commas:

```
@set_speaker "colonel"
This was a vision, fresh and clear as a mountain stream, the mind revealing itself to itself.
@delay 2
@set_expression "bobby", "confused"
```

Directives also accomplish control flow:
```
@if roll_shivers() > 7
	I am a fragment of the world spirit, the genius loci of Revachol.
@else
	~~ failed the check; control falls through below
	~~ `else` here is, of course, optional

~~ Both branches end up here
```

(Note that none of these functions, per the preamble, come built-in in the language--they'd be implemented in the game and hooked into via the interpreter.)

For syntactic sugar, text following a colon will be read to the end of the line, interpreted as a string, and **prepended** to the directive's argument list.

```
~~ Will be evaluated as `delay_with_message "Message to delay with", 4`
@delay_with_message 4: Message to delay with
```

This means that full string options can be easily specified:
```
@option: Sneak around the back
@option: Kick the door down

~~ Equivalent to
@option "Sneak around the back"
@option "Kick the door down"
```

### Options via `option` and `wait`

You can allow for user input using the `option` and `wait` directives. The `option` directive sets aside a block of code to be run when a given option is selected, and the `wait` directive signals to the interpreter that all options have been received and that it's time to yield execution and await user input.

```
What can I do for you?

@option: Can you point me toward the mall?
	Sure; it's that way.

@option: Give me all your money!
	Joke's on you: I don't have any money.

@option: Nothing.
	Stop wasting my time, then.

@wait

~~ Execution falls through here after the option's been selected
```

When input has been received (check the interpreter-specific implementation for more details), execution will proceed from the option's block. If the option block terminates without a `goto` command (`-> anchor point`), execution will jump to the line after the `wait` directive.

### Blocks

Most types of statement can be followed by an indented block. In the case of text lines and anchors, doing so has no effect on control flow, as execution will simply proceed into the block. This means that using a block after these statements serves as an organizational convenience rather than a programmatic feature. Both of these segments evaluate the same, but there's a better sense of structure to the second one:

```
# Conversation beginning
Here is a sentence.
# Anchor point in conversation
Here is another sentence happening after the anchor point.
And here is another that follows it.
# Anchor point past that one
More words here.
# End of conversation
```

```
# Conversation beginning
	Here is a sentence.
	# Anchor point in conversation
		Here is another sentence happening after the anchor point.
		And here is another that follows it.
	# Anchor point past that one
		More words here.
# End of conversation
```

`if` statements and `option` statements behave differently. Their blocks denote code to be executed if an `if` check succeeds or if an option is selected respectively. This shouldn't be too hard to grasp:

```
@if check_result
	Text to display only if `check` evaluates to `true`.
	-> Anchor point #1
@else
	Text to display otherwise.
	-> Anchor point #2
```

As mentioned earlier, block indentations following a line of text are interpreted as block strings and concatenated with spaces.

```
Block of text that can be optionally broken up into multiple lines for readability's sake

Block of text that can be optionally
	broken up into multiple lines for
	readability's sake
```