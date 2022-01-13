# Hollicode

Hollicode is a minimalistic, writer-first programming language for interactive narratives.

The compiler outputs domain-specific bytecode that runs off a very slim set of instructions. Its output format is easy to parse and easy to run, and its nature as non-performance-intensive code (you'll be evaluating at most a couple dozen instructions at a time) means an interpreter can be implemented in only a couple hundred lines of a dynamic game engine language like Lua or GDScript.

* [VS Code language package](https://github.com/spindlebink/hollicode-vscode)
* [Lua-based bytecode interpreter](https://github.com/spindlebink/hollicode-lua)

**Two warnings:**
* **Hollicode is in an early state.** Its bytecode format is powerful but still solidifying, and stuff is going to change before version 1.0.
* **I'm working on my own games.** I'll likely respond and help out if you've got questions or issues, but supporting other users in the use of this tool isn't my primary goal right now.

## The project

I've been doing a thing lately where I implement mechanics from games I've enjoyed. I recently played *Disco Elysium,* and I've been thinking about how one might efficiently represent the systems-heavy, branching narratives in it without resorting to regular scripting. The idea of a language tailored around such a use case was intriguing, and I'd never written a compiler before, so I figured it was probably time to learn.

The name derives from a work-in-progress text-heavy RPG called *Hollico.* This programming language is its backbone.

## Use case

Hollicode might be useful if....
* You're writing a game with textual story or dialog
* Your game would benefit from systemic, branching paths in that text
* You don't want to represent writerly content in engine code

## Example

Execution goes from the top down and stops to get user input when it hits a `wait` command.

```
The market's full of vendors, as markets tend to be. Against a wall nearby, an old shopkeeper is polishing a Red Delicious while humming to herself. In front of her is a cart of fruit.

[option] Approach the shopkeeper
	You wander toward the shopkeeper.
	-> Talk to shopkeeper

[option] Leave the market
	Nothing really grabs your interest.
	-> Leave

[wait]

> Talk to shopkeeper

She looks up.
"Hello there," she says. "Can I get you anything?"

[option] Are those apples for sale?
	She hands one to you. "You know what? This one's on me."

[option] No, just looking.
	She goes back to her polishing.

[wait]

> Leave

The shopkeeper nods as you depart.
```

## How does it work?

Hollicode comprises both a syntax and a bytecode instruction specification. The bytecode specification is designed to articulate text-based narratives of arbitrary complexity in a relative handful of instructions (check [the docs page on the bytecode](https://github.com/spindlebink/hollicode/blob/main/docs/BYTECODE.md) for more info). The syntax compiles to that bytecode.

However, where most bytecode-based programming languages provide a virtual machine and compiler in the same package so that you can embed the language directly, Hollicode's implementation has been engineered toward *interpretation* first. The compiler in this repository generates portable bytecode files intended to be interpreted in-game by a language-specific interpreter. The goal was (and is) to design a bytecode spec that could be easily interpreted in a dynamic language rather than a proper scripting language format. Porting Hollicode to a new platform requires only writing an interpreter, and in most higher-level languages, an interpreter only takes a couple hundred lines.

If you're trying to make a line of text display in your game *only if* a check succeeds, you might represent it like this in a theoretical narrative framework:
```lua
conversationParts["Critical part"] = function()
	say("You've reached a critical part in the conversation.")
	say("Shit's going down.")
	if checkCharisma() then
		say("And golly gee, you've brought your A-game.")
		goToConversationPart("A-game brought")
	else
		say("But you're feeling a little nauseated. Looking down, you notice a toothpaste stain on your necktie.")
		goToConversationPart("Alas, no A-game")
	end
end
```

Hollicode defines a set of bytecode instructions which can articulate this sort of thing and a super simple syntax that generates those instructions.

Your workflow when implementing a narrative in Hollicode will be to write in Hollicode's syntax (`.hlc` files), then compile to Hollicode's bytecode (writable in multiple formats like JSON or plain text), then load those compiled files in your game.

## Building

The compiler is written in the (perenially lovely) Crystal programming language. Once you've installed Crystal, compiling Hollicode is as simple as:

```sh
crystal build --release src/hollicode.cr
```

You can then run the generated executable with `--help` to get a rundown on the compiler's features.

For a one-line build and install on Linuxy/Unixy systems:

```sh
sudo crystal build src/hollicode.cr --release -o /usr/local/bin/hollicode
```

## What about....

Ink? Yarnspinner? Ren'Py? Twine? Any number of pet narrative languages? They're mostly great, but each one had one or more foundational issues (for me, at least--your mileage might vary):
* Too little of a DSL, i.e. too programmery. Attempts to contain a full programming language's syntax in a writerly DSL seem to result in languages that require a writer to learn how to program before they can write a branching dialog. **This is unnecessary**--*everyone* understands what a branching narrative is, and we should be able to represent it as simply as possible. A big reason for writing a DSL like this should be offloading programmery stuff to programmers and writerly stuff to writers. Or, if you're doing both, narrative DSLs should lead to a clear separation of the two sides.
* Too much of a DSL. I don't mean syntactically or semantically, but framework-specifically. As far as I can tell, Yarnspinner is a Unity-specific--or at least *heavily* Unity-focused--tool. Ink is a little better, since people have picked it up and written parsers in multiple languages, but it suffers from some other issues in this list. Hollicode is comprised of solutions to two separate design problems:
	
	1. How do we create an imperative, atomic instruction set suitable for complex narratives?
	2. How do we design a syntax to make generating that instruction set easy?

	Hollicode's bytecode instruction set is the real design target here. Once an interpreter's written (and an interpreter takes not more than an afternoon to implement in a suitable dynamic language), the language can be maintained separately from engine or game--maintained by someone other than you, the user. The instruction set can already articulate complex, systemic stories, and further features should change that instruction set as little as possible. This ensures that Hollicode the language stays independent from any single implementation of it.
* Too much of a DSL, and this time I do mean syntactically or semantically. Several languages I looked into provide built-in portrait functionality, group speaking functionality, etc. That's great if you're writing that type of game, but not necessary in a lot of others. Then there's the issue of customization--what if your game needs something qualitatively different from the target project of, say, Ren'Py? Hollicode assumes that the game programmer knows what they're doing and will provide necessary methods for the writer to employ. If that means you get a full range of `set_speaker`/`speaker_enter`/`speaker_leave` methods, then you get them; if it doesn't, those methods you do need can be implemented in a project-specific way, ensuring that your workflow is seamless and bespoke.
* Too limited. We want a straightforward, writer-first syntax, but we also want power and potentially full scripting support. Several alternatives provide hypertext- or choose your own adventure-style branching choices without the programmatic interactions necessary for more complicated systems.
* Visually gross. So many asterisks. So many angle brackets. And some narrative languages require *every line* to begin with a speaker and a colon, or require every line to be quoted. The closer we can get to regular prose, the better.
* Over-engineered. Again: the closer we can get to regular prose, the better. A lot of people work well with branching node editors, but I often feel that they add an unnecessary layer of division between the writer and the writer's skillset--that of *writing*, not wrangling nodes.

If an alternative to Hollicode (the ones I've mentioned are all solid and loved by many) works for you, that's awesome. I'm not trying to start a fight or disparage good work. But if Hollicode's goals align more closely with yours, or you're just interested in the language, you might give Hollicode a shot.

There's a [VS Code language package](https://github.com/spindlebink/hollicode-vscode) available, as well as a [WIP Lua-based interpreter](https://github.com/spindlebink/hollicode-lua) to try out. If you want to implement your own bytecode interpreter, look in `docs/`.

## License

The code in the compiler is licensed under the Affero GPL version 3.0.

This license only applies to integrating with the compiler itself. Generated bytecode is your own. Unless your project uses the Hollicode compiler directly, you can treat your scripts and the generated bytecode as you would any other program generated by a compiler.

The officially-provided interpreters are licensed according to the license info in their repositories.
