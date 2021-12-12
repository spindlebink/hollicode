# Hollicode

Hollicode is a minimalistic, writer-first programming language for interactive narratives.

The compiler outputs domain-specific bytecode that runs off a very slim set of instructions. Its output format is easy to parse and easy to run, and its nature as non-performance-intensive code (you'll be evaluating at most a couple dozen instructions at a time) means an interpreter can be implemented in only a couple hundred lines of a dynamic game engine language like Lua or GDScript.


## The project

I've been doing a thing lately where I implement mechanics from games I've enjoyed. I recently played *Disco Elysium,* and I've been thinking about how one might efficiently represent the systems-heavy, branching narratives in it without resorting to regular scripting. The idea of a language tailored around such a use case was intriguing, and I'd never written a full bytecode compiler before, so I figured it was probably time to learn.

The name, meanwhile, derives from a work-in-progress text-heavy RPG called *Hollico.* This programming language is its backbone.


## Example

```
# Conversation beginning
	[speaker shopkeeper]
	[if new]
		Hello there!
		Don't believe I've seen you round here.
	[else]
		What else can I do for you?

	[option] Got any fresh fruit?
		Do I ever!
		-> Buy fruit
	[option] Where's the nearest ATM?
		ATM? No idea what you're talking about.
		-> Conversation beginning
	[option] Gimme five.
		...five? Five of what?
		-> Conversation beginning
	
	[wait]

# Buy fruit
	[option] Give me one of those apples!
		-> Bought item
	[option] I'll take a pear, please.
		-> Bought item
	[option] Oooh, those grapes look sublime.
		-> Bought item
	
	[wait]

# Bought item
	Thank you very much!
	-> Conversation beginning
```
