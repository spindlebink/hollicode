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

local run, exec, getVariable
local instructions = {}
local stack = {}
local ip = 0
local finished = false

local variables = {
	thing1 = "thing 1",
	thing2 = "thing 2",
	["do"] = function(args)
		print("Doing: ", args[1], args[2])
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
		-- print("POP: ", stack[#stack])
		table.remove(stack)
	elseif op == "BOOL" then
		local boolString = instruction:match("[^%s]+$")
		local value = true
		if boolString == "false" then
			value = false
		end
		-- print("BOOL: ", value)
		table.insert(stack, value)
	elseif op == "STR" then
		local str = instruction:match(op .. "\t(.-)$")
		-- print("STR: ", str)
		table.insert(stack, str)
	elseif op == "SAY" then
		local str = table.remove(stack)
		print("SAY: ", str)
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
	elseif op == "CALL" then
		local num = tonumber(instruction:match("[^%s]+$"))
		local func = table.remove(stack)
		local funcArgs = {}
		for i = 1, num do
			table.insert(funcArgs, 1, table.remove(stack))
		end
		func(funcArgs)
	end

	if incrementIP then
		ip = ip + 1
		if ip > #instructions then
			finished = true
		end
	end
end

run(code)
