local bytecode = {
	{"PUSHV", "new"},
	{"BRANCH", 3, 1},
	{"TEXT", "Yee yee"},
	{"TEXT", "Anyway"}
}

local ip = 1
local next_ip = 1
local finished = false

local run, evaluate

local been = {}
local stack = {}

local function push(value)
	table.insert(stack, value)
end

local function pop()
	return table.remove(stack)
end

local function peek()
	return stack[#stack]
end

local function goTo(index)
	-- table.insert(been, ip)
	next_ip = index
end

local function getVariable(name)
	if name == "new" then
		return true
	end
end

function run()
	finished = false
	while not finished do
		next_ip = ip + 1
		evaluate(bytecode[ip])
		ip = next_ip
		if ip > #bytecode then
			finished = true
		end
	end
end

function evaluate(op)
	print(op[1])
	if op[1] == "PUSHV" then
		push(getVariable(op[2]))
	elseif op[1] == "BRANCH" then
		local t = pop()
		if t then
			goTo(op[2])
		else
			goTo(op[3])
		end
	elseif op[1] == "TEXT" then
		print(op[2])
	elseif op[1] == "GOTO" then
		goTo(op[2])
	end
end

run()
