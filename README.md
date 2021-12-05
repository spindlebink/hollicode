# Hollicode

## Under construction. Not usable yet.

Hollicode is a minimalistic, writer-first syntax for interactive narratives.

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
		[option] Give me one of those apples!
			-> Bought item
		[option] I'll take a pear, please.
			-> Bought item
		[option] Oooh, those grapes look sublime.
			-> Bought item

# Bought item
	Thank you very much!
	-> Conversation beginning
```
