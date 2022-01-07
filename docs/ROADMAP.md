# Hollicode Development Roadmap

Here are the things I'd like to add to Hollicode. Some of this is in development, it's just that Hollicode develops alongside my primary game dev project right now, and I don't want to fall into the "you either build an engine or build a game" pit.

## Non-trivial example

Complete with user-facing interpreter. The language is in development for a personal project, so I've got my own bytecode interpreter running, but it's unpolished as of yet. This'll probably be done in Lua with LÖVE, since they're direct and (somewhat) idiomatically agnostic.

## `once` keyword

It's common enough in interactive narratives that it deserves to be in the language.

```
> Anchor
[once]
	Hey there! I'm saying this because execution has so far not reached this block.
[else]
	And here we are at the boring old repeated line.

[wait]
-> Anchor
```

The way I'm imagining it, it would require two new bytecode instructions:

* Set tag/increment tag---set or increment a private interpreter variable. We could get by with `true`/`false` flags, but using incrementable tags would lead to increased flexibility later and not any greater commitment now.
* Get tag/increment tag---get the value of an interpreter variable and push to stack.

Then, `once` would compile to a *get tag* instruction, followed by an `if` construct (as compiled to bytecode), and within the body of the block we'd call the `set tag` instruction. It'd be a bytecodeification of:
```lua
if get_internal_variable(specific_hash_for_corresponding_line_in_source) == 0 then
	increment_internal_variable(specific_hash_for_corresponding_line_in_source)
	-- code compiled in the `once` block
end
```

## Think long and hard about variables/function calls

The current workflow, fully directive-based, without any syntax for setting variables or expressions for calling functions, is minimal and reads easily, but I wonder if we could go just a *little* further toward more conventional variable structures. As is, we defer all keeping-track-of-variables stuff to interpreter implementations. I'm not saying it's *wrong*, but it might be worth further thought.

## Think long and hard about options

The current structure is a little convoluted for interpreter implementation. May need a redesign.

## Store anchor locations in bytecode instead of compiling them out

Right now, anchors and go-to commands get compiled out to `JMP` commands. It's a good idea to keep track of anchors so that later on interpreters could provide user-facing methods to go to an anchor programmatically instead of limiting that to in-script go-to commands.

Doing this would require a new instruction which'd go at the top of each compiled script. When compiling, we'd generate a sequence of "the anchor named *Anchor name* goes to line #54". We'd generate bytecode thus:

```
STR	Anchor name
INT	54
ANCH
```

The new instruction would pop the top two items off the stack and store them as an anchor mapping. The interpreter would then provide perhaps a `goto` method that'd look up a stored anchor position and begin execution from there.

## Dedicated `INT` instruction

All numbers are floating-point right now. Internal instructions which take integers provide them in the form of integers, but we don't have an integer instruction. Go figure.
