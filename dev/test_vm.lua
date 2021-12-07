local args = {...}
local code = ""
if #args > 0 then
	local inputFile = io.open(args[1], "r")
	if not inputFile then
		print("Error: could not open file '" .. args[1] .. "'.")
		os.exit(1)
	end
	code = inputFile:read("*a")
	inputFile:close()
else
	print("Error: no input file specified.")
	os.exit(1)
end

local run, exec, getVariable, variables
local instructions = {}
local stack = {}
local gotoStack = {}
local options = {}
local ip = 0
local finished = false

variables = {
	variable = false,
	alternate = true,
	set = function(args)
		for i = 1, #args do
			variables[args[i] ] = true
		end
	end
}

function getVariable(variable)
	return variables[variable]
end

function run(code)
	instructions = {}
	-- ensure code ends with a newline so we get all the instructions
	if string.sub(code, #code) ~= "\n" then
		code = code .. "\n"
	end
	for instruction in string.gmatch(code, "([^\n]+)[\n]") do
		table.insert(instructions, instruction)
	end
	ip = 1
	while instructions[ip] and not finished do
		exec(instructions[ip])
	end
end

function exec(instruction)
	local op = instruction:match("[^%s]+")
	local incrementIP = true
	if op == "POP" then
		table.remove(stack)
	elseif op == "BOOL" then
		local boolString = instruction:match("[^%s]+$")
		local value = true
		if boolString == "false" then
			value = false
		end
		table.insert(stack, value)
	elseif op == "STR" then
		local str = instruction:match(op .. "\t(.-)$")
		table.insert(stack, str)
	elseif op == "ECHO" then
		local str = table.remove(stack)
		print(str)
	elseif op == "JMP" then
		incrementIP = false
		ip = ip + tonumber(instruction:match("[^%s]+$"))
	elseif op == "FJMP" then
		local top = stack[#stack]
		if not top then
			incrementIP = false
			ip = ip + tonumber(instruction:match("[^%s]+$"))
		end
	elseif op == "VAR" then
		table.insert(stack, getVariable(instruction:match("[^%s]+$")))
	elseif op == "FUNC" then
		table.insert(stack, getVariable(instruction:match("[^%s]+$")))
	elseif op == "CALL" then
		local num = tonumber(instruction:match("[^%s]+$"))
		local func = table.remove(stack)
		local funcArgs = {}
		for i = 1, num do
			table.insert(funcArgs, 1, table.remove(stack))
		end
		func(funcArgs)
	elseif op == "GOTO" then
		local where = tonumber(instruction:match("[^%s]+$"))
		table.insert(gotoStack, ip)
		ip = where + 1 -- account for Lua's 1-indexed tables
		incrementIP = false
	elseif op == "RET" then
		if #gotoStack > 0 then
			ip = table.remove(gotoStack)
		end
	elseif op == "OPT" then
		local optionName = table.remove(stack)
		local optionGoto = tonumber(instruction:match("[^%s]+$"))
		table.insert(options, {optionName, optionGoto})
	elseif op == "WAIT" then
		for i = 1, #options do
			print("Option #" .. i .. ": " .. options[i][1])
		end
		io.write("Enter an option: ")
		local selectedOption = io.read("*n")
		while not selectedOption or (selectedOption < 0 or selectedOption > #options) do
			print("Invalid option.")
			io.write("Try again: ")
			selectedOption = tonumber(io.read("*n"))
		end
		local o = options[selectedOption]
		table.insert(gotoStack, ip)
		ip = o[2] + 1
		incrementIP = false
	end
	if incrementIP then
		ip = ip + 1
		if ip > #instructions then
			finished = true
		end
	end
end

run(code)
