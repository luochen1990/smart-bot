----------------------------------- fp utils -----------------------------------

-- | identity : a -> a
identity = function(x) return x end

negate = function(x) return -x end

-- | pipe : (a -> b) -> (b -> c) -> a -> c
-- , pipe == flip compose
pipe = function(f, ...)
	local fs = {...}
	if #fs == 0 then return f end
	return function(...) return pipe(unpack(fs))(f(...)) end
end

-- | default : a -> Maybe a -> a
default = function(dft)
	return function(x) if x ~= nil then return x else return dft end end
end

-- | maybe : (b, a -> b) -> Maybe a -> b
maybe = function(dft, wrap)
	return function(x) if x == nil then return dft else return wrap(x) end end
end

-- | apply : a -> (a -> b) -> b
apply = function(...)
	local args = {...}
	return function (f) return f(unpack(args)) end
end

-- | delay : (a -> b, a) -> IO b
delay = function(f, ...)
	local args = {...}
	return function() return f(unpack(args)) end
end

memoize = function(f)
	local mem = {}
	setmetatable(mem, {__mode = "kv"})
	return function(...)
		local r = mem[{...}]
		if r == nil then
			r = f(...)
			mem[{...}] = r
		end
		return r
	end
end

-------------------------------- general utils ---------------------------------

deepcopy = function(obj)
	local lookup_table = {}
	local function _copy(obj)
		if type(obj) ~= "table" then
			return obj
		elseif lookup_table[obj] then
			return lookup_table[obj]
		end
		local new_table = {}
		lookup_table[obj] = new_table
		for index, value in pairs(obj) do
			new_table[_copy(index)] = _copy(value)
		end
		return setmetatable(new_table, getmetatable(obj))
	end
	return _copy(obj)
end

math.randomseed(os.time() * 1000) -- set randomseed for math.random()

-- | eval an expr or a peice of code
eval = function(code, env, readOnlyEnv)
	if readOnlyEnv then setmetatable(env, {__index = readOnlyEnv}) end

	local func = load("return unpack(table.pack(" .. code .. "));", "=lua", "t", env)
	if not func then
		func, compileErr = load(code, "=lua", "t", env)
	end

	if func then
		local old_stack = deepcopy(_callStack)
		local res1 = { pcall( func ) }
		if table.remove(res1, 1) then
			if #res1 == 1 and type(res1[1]) == "table" and type(res1[1].run) == "function" then
				-- directly run a single IO monad
				local res2 = { pcall( res1[1].run ) }
				if table.remove(res2, 1) then
					return true, res2
				else
					local new_stack = _callStack
					_callStack = old_stack
					return false, {msg = res2[1], stack = new_stack}
				end
			else -- trivial case
				return true, res1
			end
		else
			local new_stack = _callStack
			_callStack = old_stack
			return false, {msg = res1[1], stack = new_stack}
		end
	else
		return false, {msg = '[compile error] '..compileErr, stack = nil}
	end
end

-- | execute a piece of code, similar to eval, but print out the result directly
exec = function(code, env, readOnlyEnv)
	if code:sub(1, 7) == "http://" or code:sub(1, 8) == "https://" then
		local h = http.get(code)
		if h then
			code = h.readAll()
		else
			printC(colors.red)("[exec] failed to fetch code from:", code)
			return
		end
	end
	-- got code
	local ok, res = eval(code, env or {}, readOnlyEnv or _ENV)
	if ok then
		if #res > 0 then
			printC(colors.green)(showFields(unpack(res)))
		end
	else
		if res.stack then _printCallStack(10, nil, colors.gray, res.stack) end
		printC(colors.red)(res.msg)
	end
end

-------------------------------- string utils ----------------------------------

-- | convert a value to string for printing
function show(value)
	local ty = type(value)
	if ty == "table" then
		local mt = getmetatable(value)
		if type(mt) == "table" and type(mt.__tostring) == "function" then
			return tostring(value)
		else
			local ok, serialised = pcall(textutils.serialise, value)
			if ok then return serialised else return tostring(value) end
		end
	else
		return tostring(value)
	end
end

-- | convert a list to string for printing
-- , NOTE: `showList({1, nil, 2}, ",")` will print as "1" instead of "1,nil,2"
function showList(ls, spliter, placeholder)
	local s = placeholder or ""
	for i, x in ipairs(ls) do
		if i == 1 then s = show(x) else s = s..(spliter or "\n")..show(x) end
	end
	return s
end

showFields = function(...) return showList({...}, ", ", "nil") end
showWords = function(...) return showList({...}, " ", "") end
showLines = function(...) return showList({...}, "\n", "") end

function literal(val)
	local ty = type(val)
	if ty == "table" then
		local mt = getmetatable(val)
		if type(mt) == "table" then
			if type(mt.__literal) == "function" then
				return mt.__literal(val)
			else
				return nil
			end
		else
			return _literalTable(val)
		end
	elseif ty == "string" then
		return _literalString(val)
	elseif ty == "function" then
		return nil
	else
		return tostring(val)
	end
end

function _literalTable(value)
	local s = "{"
	for i, v in ipairs(value) do
		if i > 1 then s = s .. "," end
		s = s .. literal(v)
	end
	local sp = #value > 0
	for k, v in pairs(value) do
		if type(k) ~= "number" or k > #value then
			if sp then s = s .. "," end
			sp = true
			s = s .. k .. "=" .. literal(v) --TODO: wrap special key with [] and escape
		end
	end
	return s .. "}"
end

function _literalString(val)
	return '"'..val..'"' --TODO: escape special chars
end

------------------------------ coroutine utils ---------------------------------

function race(...)
	local res
	local cos = {}
	for i, io in ipairs({...}) do
		cos[i] = function() res = { io() } end
	end
	local id = parallel.waitForAny(unpack(cos))
	return id, unpack(res)
end

------------------------------ ui event utils ----------------------------------

_waitForKeyPress = function(targetKey)
	while true do
		local ev, keyCode = os.pullEvent("key")
		if ev == "key" and keyCode == targetKey then
			--print("[ev] key("..keys.getName(keyCode)..")")
			return keyCode
		end
	end
end

_waitForKeyCombination = function(targetKey1, targetKey2)
	local st = 0 -- matched length
	repeat
		if st == 0 then
			_waitForKeyPress(targetKey1)
			st = 1
		elseif st == 1 then
			local ev, keyCode = os.pullEvent()
			if ev == "key_up" and keyCode == targetKey1 then
				--print("[ev] key_up("..keys.getName(keyCode)..")")
				st = 0
			elseif ev == "key" and keyCode == targetKey2 then
				--print("[ev] key("..keys.getName(keyCode)..")")
				st = 2
			end
		end
	until (st == 2)
end

---------------------------------- fs utils ------------------------------------

readFile = function(fileHandle)
	local isTempHandle = false
	if type(fileHandle) == "string" then -- file path/name used
		fileHandle = fs.open(fileHandle, 'r')
		isTempHandle = true
	end
	if not fileHandle then return nil end
	local res = fileHandle.readAll()
	if isTempHandle then
		fileHandle.close()
	end
	return res
end

writeFile = function(fileHandle, s, mode)
	local isTempHandle = false
	mode = default('w')(mode)
	if type(fileHandle) == "string" then -- file path/name used
		fileHandle = fs.open(fileHandle, mode)
		isTempHandle = true
	end
	fileHandle.write(s)
	if isTempHandle then
		fileHandle.close()
	else
		fileHandle.flush()
	end
end

readLines = function(fileHandle)
	local isTempHandle = false
	if type(fileHandle) == "string" then -- file path/name used
		fileHandle = fs.open(fileHandle, 'r')
		isTempHandle = true
	end
	if not fileHandle then return nil end
	local res = {}
	local line
	while true do
		line = fileHandle.readLine()
		if not line then break end
		table.insert(res, line)
	end
	if isTempHandle then
		fileHandle.close()
	end
	return res
end

writeLines = function(fileHandle, ls, mode)
	local isTempHandle = false
	mode = default('w')(mode)
	if type(fileHandle) == "string" then -- file path/name used
		fileHandle = fs.open(fileHandle, mode)
		isTempHandle = true
	end
	for _, s in ipairs(ls) do
		fileHandle.writeLine(s)
	end
	if isTempHandle then
		fileHandle.close()
	else
		fileHandle.flush()
	end
end

--------------------------------- rednet utils ---------------------------------

function openWirelessModem()
	for _, mSide in ipairs( peripheral.getNames() ) do
		if peripheral.getType( mSide ) == "modem" then
			local modem = peripheral.wrap( mSide )
			if modem.isWireless() then
				rednet.open(mSide)
				return true
			end
		end
	end
	return false
end

