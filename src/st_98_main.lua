------------------------------- main coroutines --------------------------------

if turtle then

	-- | provide current real pos and facing dir to correct the coordinate system
	_correctCoordinateSystem = markFn("_correctCoordinateSystem(pos, facing)")(function(pos, facing)
		assert(pos and pos.x, "[_correctCoordinateSystem(pos, facing)] pos must be a vector, but got"..tostring(pos))
		assert(facing and facing.y == 0 and vec.manhat(facing) == 1, "[_correctCoordinateSystem(pos, facing)] facing must be a dir, but got "..tostring(facing))
		local old_pos, old_facing = workState.pos, workState.facing
		local offset = pos - old_pos -- use this to correct all locally maintained positions
		local rot = dirRotationBetween(facing, old_facing)
		workState.beginPos = rot(workState.beginPos) + offset
		O = workState.beginPos
		workState.pos = pos
		workState.facing = facing
		F, B, L, R = facing, -facing, leftSide(facing), rightSide(facing)
		for _, d in ipairs({"F", "B", "L", "R"}) do turn[d] = turn.to(_ENV[d]) end
		return true
	end)

	_correctCoordinateSystemWithGps = markFn("_correctCoordinateSystemWithGps")(function()
		local p0 = gpsPos(5)
		if not p0 then
			printC(colors.orange)("[_correctCoordinateSystemWithGps] make sure you have wireless modem and gps station nearby")
			return false
		end
		printC(colors.gray)("turtle pos = "..tostring(p0))
		-- got p0 (i.e. pos) here
		if not refuelFromBackpack(2)() then
			printC(colors.orange)("[_correctCoordinateSystemWithGps] I need some fuel")
			return false
		end
		-- ready to get p1 (i.e. dir) here
		local getFacing = function(go, goBack, calcDir)
			local succ = retry(5)(go)()
			if not succ then
				return nil
			end
			local p1 = gpsPos(5)
			if not p1 then
				repeat turtle.dig(); turtle.attack() until ( goBack() )
				return nil
			end
			repeat turtle.dig(); turtle.attack() until ( goBack() )
			local d = calcDir(p1)
			if vec.manhat(d) ~= 1 then
				printC(colors.gray)("p0 = "..tostring(p0))
				printC(colors.gray)("p1 = "..tostring(p1))
				printC(colors.gray)("p0 - p1 = "..tostring(d))
				printC(colors.orange)("[_correctCoordinateSystemWithGps] weird gps positoin, please check your gps server")
				return nil
			end
			return d
		end
		local d
		if not turtle.detect() then
			d = getFacing(turtle.forward, turtle.back, function(p1) return p1 - p0 end)
		end
		d = d or getFacing(turtle.back, turtle.forward, function(p1) return p0 - p1 end)
		if not d then
			printC(colors.orange)("[_correctCoordinateSystemWithGps] cannot move forward/back and gps locate, please try somewhere else nearby")
			return false
		end
		printC(colors.gray)("turtle facing = "..showDir(d))
		-- got pos and dir here
		return _correctCoordinateSystem(p0, d)
	end)

	_initTurtleState = markFn("_initTurtleState")(function()
		local succ = _correctCoordinateSystemWithGps()
		if not succ then
			printC(colors.yellow)("WARN: failed to get gps pos and dir!")
		end
		workState.fuelStation = default(workState.fuelStation)(requestFuelStation())
		if not workState.fuelStation then
			printC(colors.yellow)("WARN: failed to get fuelStation!")
		end
		workState.unloadStation = default(workState.fuelStation)(requestUnloadStation())
		if not workState.unloadStation then
			printC(colors.yellow)("WARN: failed to get unloadStation!")
		end
		return not not (succ and workState.fuelStation and workState.unloadStation)
	end)

	_initTurtleStateWithChest = function()
		if not (rep(attack) * rep(dig) * use("minecraft:chest"))() then error("[_initTurtleState] please give me a chest") end
		local ok, res = turtle.inspect()
		if not ok then error("[_initTurtleState] failed to get facing direction (inspect failed)") end
		workState.facing = -const.dir[res.state.facing:sub(1,1):upper()]
		F, B, L, R = workState.facing, -workState.facing, leftSide(workState.facing), rightSide(workState.facing)
		for _, d in ipairs({"F", "B", "L", "R"}) do turn[d] = turn.to(_ENV[d]) end
		turtle.dig()
		-- got facing
		workState.pos = gpsPos()
		if workState.pos == nil then error("[_initTurtleState] failed to get gps location!") end
		workState.beginPos = workState.pos
		O = workState.beginPos
		-- got pos
		ok = saveDir(turn.left * try(use("minecraft:chest")) * isChest)()
		if not ok then error("[_initTurtleState] failed to set fuelStation") end
		workState.fuelStation = {pos = workState.pos, dir = L}
		-- got fuelStation
		if DEBUG and math.random() < 0.1 then _test.move() end
	end
end

_printCallStackCo = function()
	while true do
		_waitForKeyCombination(keys.leftCtrl, keys.p)
		_printCallStack(10, nil, colors.blue)
	end
end

_inspectSystemStateCo = function()
	while true do
		_waitForKeyCombination(keys.leftCtrl, keys.i)
		if turtle then
			printC(colors.green)('turtle workMode =', show(workMode))
			printC(colors.green)('turtle workState =', show(workState))
		end
	end
end

_inspectCo = function()
	parallel.waitForAny(_printCallStackCo, _inspectSystemStateCo)
end

_initComputer = function()
	local succ = openWirelessModem()
	if not succ then
		printC(colors.yellow)("WARN: wireless modem not found!")
		return false
	end
	return true
end

_startupMainCo = function()
	local code = readFile("/st_startup.lua")
	if code then eval(code, {}, _ENV) end

	local label = os.getComputerLabel()
	if turtle then
		if string.sub(label, 1, 6) == "guard-" then
			local d = string.sub(label, 7, 7)
			if const.dir[d] then
				if d == "D" then
					followYouCo(D)
				else
					followYouCo(const.dir[d])
				end
			end
		end
	elseif pocket then
		followMeCo()
	end
end

_startupCo = function()
	parallel.waitForAny(_startupMainCo, _inspectCo, delay(_waitForKeyCombination, keys.leftCtrl, keys.c))
end

_replCo = function()
	parallel.waitForAny(_replMainCo, _inspectCo, delay(_waitForKeyCombination, keys.leftCtrl, keys.d))
end

_main = function(...)
	-- init system state
	term.clear(); term.setCursorPos(1,1)
	_initComputer()
	if turtle then _initTurtleState() end
	-- run startup script
	_startupCo()
	-- run repl
	_replCo()
end
