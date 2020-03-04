--------------------------------- swarm state ----------------------------------

mkTaskInfo = function(opts) -- not used yet
	local t = {
		["type"] = opts.type,
		workArea = opts.workArea,
		beginPos = opts.beginPos,
		estCost = opts.estCost,
		requiredTools = opts.requiredTools,
		command = opts.command,
		state = "queueing",
		createdTime = now(),
		beginTime = nil,
		workerId = nil,
	}
	assert(t.type and t.beginPos and t.estCost and t.command, "mkTaskInfo(opts) lack required field")
	return t
end

mkStationInfo = function(opts)
	local s = {
		pos = opts.pos,
		dir = opts.dir,
		limitation = opts.limitation,
		deliverPriority = opts.deliverPriority,
		reservation = opts.reservation,
		restockPriority = opts.restockPriority,
		itemType = opts.itemType,
		stationHosterId = opts.stationHosterId,
		-- states
		itemCount = opts.itemCount or 0,
		isVisiting = default(false)(opts.isVisiting),
		currentQueueLength = default(0)(opts.currentQueueLength),
		maxQueueLength = default(5)(opts.maxQueueLength),
		--latestCheckTime = now() - 100,
	}
	assert(s.pos and ((s.limitation and s.deliverPriority) or (s.reservation and s.restockPriority)), "[mkStationInfo(opts)] lacks required field")
	return s
end

mkWorkerInfo = function(opts) -- not used yet
	local w = {
		id = opts.id,
		latestPos = nil,
		latestReportTime = nil,
		state = "idle", -- or "busy" or "interrapt"
	}
	return w
end

swarm = {
	_state = {
		asFuel = {"minecraft:charcoal"},
		stationPool = {},
		workerPool = {},
		jobPool = {},
	},
}

-------------------------------- telnet service --------------------------------

telnetServerCo = function(ignoreDeposit)
	local eventQueue = {}
	local listenCo = function()
		while true do
			--printC(colors.gray)("[telnet] listening")
			local senderId, msg, _ = rednet.receive("telnet")
			--printC(colors.gray)("[telnet] received from " .. senderId .. ": " .. msg)
			local queueTail = #eventQueue + 1
			if ignoreDeposit then queueTail = 1 end
			eventQueue[queueTail] = {senderId, msg}
		end
	end
	local execCo = function()
		local sleepInterval = 1
		while true do
			if #eventQueue == 0 then
				sleepInterval = math.min(0.5, sleepInterval * 1.1)
				--printC(colors.gray)("[telnet] waiting "..sleepInterval)
				sleep(sleepInterval)
			else -- if #eventQueue > 0 then
				--printC(colors.gray)("[telnet] executing "..#eventQueue)
				sleepInterval = 0.02
				local sender, msg = unpack(table.remove(eventQueue, 1))
				printC(colors.gray)("[telnet] exec cmd from " .. sender .. ": " .. msg)
				if msg == "exit" then break end
				func, err = load("return "..msg, "telnet_cmd", "t", _ENV)
				if func then
					ok, res = pcall(func)
					if ok then
						printC(colors.green)(res)
					else
						printC(colors.yellow)(res)
					end
				else
					printC(colors.orange)(err)
				end
			end
		end
	end
	parallel.waitForAny(listenCo, execCo)
end

--------------------------------- swarm service --------------------------------

swarm._startService = _buildServer("swarm", "swarm-service", function(msg)
	return safeEval(msg) --TODO: set proper env
end)

--swarm._startService = function()
--	local eventQueue = {}
--	local listenCo = function()
--		rednet.host("swarm", "server")
--		while true do
--			printC(colors.gray)("[swarm] listening")
--			local senderId, msg, _ = rednet.receive("swarm-service")
--			printC(colors.gray)("[swarm] received from " .. senderId .. ": " .. msg)
--			table.insert(eventQueue, {senderId, msg})
--		end
--	end
--	local execCo = function()
--		local sleepInterval = 1
--		while true do
--			if #eventQueue == 0 then
--				sleepInterval = math.min(0.5, sleepInterval * 1.1)
--				--printC(colors.gray)("[swarm] waiting "..sleepInterval)
--				sleep(sleepInterval)
--			else -- if #eventQueue > 0 then
--				--printC(colors.gray)("[swarm] executing "..#eventQueue)
--				sleepInterval = 0.02
--				local requesterId, msg = unpack(table.remove(eventQueue, 1))
--				printC(colors.gray)("[swarm] exec cmd from " .. requesterId .. "")
--				if msg == "exit" then
--					break
--				end
--				local ok, res = eval(msg)
--				local resp
--				if ok then
--					resp = literal(true, res)
--					printC(colors.green)("[swarm] response to " .. requesterId .. ": " .. resp)
--				else
--					resp = literal(false, res.msg)
--					printC(colors.yellow)("[swarm] response to " .. requesterId .. ": " .. resp)
--				end
--				rednet.send(requesterId, resp, "swarm-response")
--			end
--		end
--	end
--	parallel.waitForAny(listenCo, execCo)
--end

swarm.services = {}

swarm.services.registerStation = function(opts)
	if not opts.pos then
		return false, "station pos is required"
	end
	local station = mkStationInfo(opts)
	local itemTy = opts.itemType
	if not itemTy then
		return false, "station itemType is required"
	end
	swarm._state.stationPool[itemTy] = default({})(swarm._state.stationPool[itemTy])
	swarm._state.stationPool[itemTy][station.pos] = station
	return true, "station registered"
end

swarm.services.updateStation = function(opts)
	if not opts.itemType or not opts.pos then
		return false, "station pos and itemType is required"
	end
	local pool = swarm._state.stationPool[opts.itemType]
	if not pool then
		return false, "station not exist (no such type)"
	end
	local station = pool[opts.pos]
	if not station then
		return false, "station not exist (no such pos)"
	end
	for k, v in pairs(station) do
		station[k] = v
	end
	return true, "station updated"
end

swarm.services.requestStation = function(itemType, itemCount, startPos, fuelLeft)
	local pool = swarm._state.stationPool[itemType]
	if not pool then
		return false, "no such station registered, please register one"
	end
	if type(itemCount) ~= "number" then
		return false, "bad request, please provide itemCount as number"
	end
	if not vec.isVec(startPos) then
		return false, "bad request, please provide startPos as vec"
	end
	if type(fuelLeft) ~= "number" then
		return false, "bad request, please provide fuelLeft as number"
	end
	-- [[
	-- There is three dimention to compare station choices:
	--	1. distance:    |--->
	--	2. item count:   --->|
	--	3. queue time:  |--->#
	--
	-- (Tips about the axis:
	--	 * left to right, worst to best
	--	 * `|` is a basic bar, which means this dimention good enough to this point is required
	--	 * `#` is a significant bar, which means this dimention good enough to this point will make significant difference
	--	 )
	--
	--	the distance dimention has one bar, which means if farer than this distance, then fuelLeft is not enough
	--	the item count dimention has one bar, which means the item count is enough for the request
	--	the queue time dimention has two bar, first means the queue is full, second means the queue is empty
	--
	--	Our strategy is that:
	--	 * if all basic bar can be reached, then we try to reach more (weighted) significant bar;
	--	 * if not, return fail;
	-- ]]
	-- boolean conditions
	local nearer = function(pos1, pos2) return vec.manhat(pos1 - startPos) < vec.manhat(pos2 - startPos) end
	local nearEnough = function(st) return vec.manhat(st.pos - startPos) * 2 <= fuelLeft end
	local itemEnough = function(st) if itemCount >= 0 then return st.itemCount >= itemCount else return st.itemCount < itemCount end end
	local queueNotFull = function(st) return st.currentQueueLength < st.maxQueueLength end
	-- number conditions
	local dist = function(st) return vec.manhat(st.pos - startPos) end
	local queEmpty = function(st) if st.currentQueueLength == 0 and st.isVisiting == false then return 0 else return 1 end end
	local que = function(st) if st.isVisiting == false then return st.currentQueueLength else return st.currentQueueLength + 1 end end
	--
	local comparator = function(...)
		local attrs = {...}
		return function(a, b)
			for i, attr in ipairs(attrs) do
				local aa, ab = attr(a), attr(b)
				if i == #attrs or aa ~= ab then return aa < ab end
			end
		end
	end

	local better = comparator(queEmpty, dist, que)
	local best
	for pos, st in pairs(swarm._state.stationPool[itemType]) do
		if nearEnough(st) and itemEnough(st) and queueNotFull(st) then
			if best == nil or better(st, best) then
				best = st
			end
		end
	end
	if best then
		return true, best
	end
	return false, "no proper station now, please try latter"
end

--------------------------------- swarm client ---------------------------------

---- | build a service, returns an IO to start the service
---- , serviceName is for service lookup
---- , listenProtocol is for request receiving
---- , handler is a function like `function(unwrappedMsg) return ok, res end`
--_buildService = function(serviceName, listenProtocol, handler, logger)
--	handler = default(safeEval)(handler)
--	logger = default({
--		--verb = function(msg) printC(colors.gray)("["..serviceName.."] "..msg) end
--		verb = function(msg) end
--		info = function(msg) printC(colors.gray)("["..serviceName.."] "..msg) end
--		succ = function(msg) printC(colors.green)("["..serviceName.."] "..msg) end
--		fail = function(msg) printC(colors.yellow)("["..serviceName.."] "..msg) end
--		warn = function(msg) printC(colors.orange)("["..serviceName.."] "..msg) end
--	})(logger)
--	local eventQueue = {}
--	local listenCo = function()
--		rednet.host(serviceName, "server")
--		while true do
--			logger.info("listening on "..literal(listenProtocol))
--			local senderId, rawMsg, _ = rednet.receive(listenProtocol)
--			logger.info("received from " .. senderId .. ": " .. rawMsg)
--			table.insert(eventQueue, {senderId, msg})
--		end
--	end
--	local handleCo = function()
--		local sleepInterval = 1
--		while true do
--			if #eventQueue == 0 then
--				sleepInterval = math.min(0.5, sleepInterval * 1.1)
--				logger.verb("waiting "..sleepInterval)
--				sleep(sleepInterval)
--			else -- if #eventQueue > 0 then
--				logger.verb("handling "..#eventQueue)
--				sleepInterval = 0.02
--				local requesterId, msg = unpack(table.remove(eventQueue, 1))
--				logger.info("exec cmd from " .. requesterId .. "")
--
--				local resp
--
--				local ok1, res1 = safeEval(rawMsg)
--				if not ok1 then
--					resp = literal(false, res.msg)
--					logger.fail("response to " .. requesterId .. ": " .. resp)
--				else
--					local responseProtocol, msg = unpack(res1)
--
--					local ok2, res = handler(msg)
--					if not ok2 then
--						resp = literal(false, res.msg)
--						logger.fail("response to " .. requesterId .. ": " .. resp)
--					else
--						resp = literal(true, res)
--						logger.succ("response to " .. requesterId .. ": " .. resp)
--					end
--				end
--				rednet.send(requesterId, resp, responseProtocol)
--			end
--		end
--	end
--	parallel.waitForAny(listenCo, handleCo)
--end

swarm.client = _buildClient("swarm", "swarm-service")

--_request = (function()
--	local _request_counter = 0
--
--	return function(swarmServerId, msg, requestProtocol, timeout)
--		local responseProtocol = requestProtocol .. "_R" .. (_request_counter)
--		_request_counter = (_request_counter + 1) % 1000
--		rednet.send(swarmServerId, literal(responseProtocol, msg), requestProtocol)
--		while true do
--			local responserId, resp = rednet.receive(responseProtocol, timeout) --TODO: reduce timeout in next loop?
--			if responserId == swarmServerId then
--				return true, resp
--			elseif not responserId then
--				return false, "request timeout"
--			else
--				log.warn("[_request] weird, send to "..swarmServerId.." but got response from "..responserId..", are we under attack?")
--			end
--		end
--	end
--end)()

--_requestSwarm = function(cmd, totalTimeout)
--	totalTimeout = default(2)(totalTimeout)
--
--	local _naiveRequestSwarm = function(timeout)
--		return mkIO(function()
--			if not workState.swarmServerId then
--				local serverId = rednet.lookup("swarm", "server")
--				if not serverId then
--					return false, "swarm server not found"
--				end
--				workState.swarmServerId = serverId
--			end
--			-- got workState.swarmServerId
--
--			local reqSucc, resp = _request(workState.swarmServerId, cmd, "swarm-service", timeout)
--			if not reqSucc then -- timeout or network error
--				workState.swarmServerId = nil
--				return false, resp
--			end
--			-- got resp
--
--			local ok, res = eval(resp)
--			if not ok then
--				log.bug("[_requestSwarm] faild to parse response: ", literal({cmd = cmd, response = res}))
--				return false, "faild to parse response"
--			end
--			-- got res
--
--			return unpack(res)
--		end)
--	end
--
--	return retryWithTimeout(totalTimeout)(_naiveRequestSwarm)()
--end

-- | interactive register complex station
registerStation = mkIOfn(function()
end)

unregisterStation = function(st)
end

registerPassiveProvider = mkIO(function()
	reserveOneSlot()
	select(slot.isEmpty)()
	suck(1)()
	local det = turtle.getItemDetail()
	drop(1)()
	if not det then
		log.bug("[registerPassiveProvider] cannot get item detail")
		return false
	end
	local stationDef = {
		pos = workState.pos,
		dir = workState:aimingDir(),
		itemType = det.name,
		limitation = 0,
		deliverPriority = 0, --passive provider
	}
	return swarm.client.request("swarm.services.registerStation("..literal(stationDef)..")")()
end)

--serveAsFuelStation = mkIO(function()
--end)

serveAsProvider = mkIO(function()
	local getAndHold
	if isContainer() then -- suck items from chest
		getAndHold = function(n) return suckHold(n) end
	else -- dig or attack --TODO: check tool
		getAndHold = function(n) return (isContainer * suckHold(n) + -isContainer * (digHold + try(attack) * suckHold(n))) end
	end

	local stationDef = {
		pos = workState.pos - workState:aimingDir(),
		dir = workState:aimingDir(),
		itemType = nil,
		limitation = 0,
		deliverPriority = 0, --passive provider
		stationHosterId = os.getComputerID()
	}

	local registerCo = function()
		printC(colors.gray)("[provider] detecting item")
		local det = retry((select(slot.isNonEmpty) + getAndHold(1)) * details())()
		printC(colors.green)("[provider] got "..det.name)
		stationDef.itemType = det.name
		local _reg = function()
			local ok, res = swarm.client.request("swarm.services.registerStation("..literal(stationDef)..")")()
			if not ok then
				log.cry("[provider] failed to register station (network error): "..literal(res))
				return false
			end
			if not table.remove(res, 1) then
				log.cry("[provider] failed to register station (logic error): "..literal(res))
				return false
			end
			printC(colors.green)("[provider] station registered")
			return true
		end
		retry(_reg)()
	end

	local produceCo = function()
		with({allowInterruption = false})(function()
			while true do
				-- retry to get items
				local det = retry(getAndHold() * details())()
				if det.name == stationDef.itemType then -- got target item
					print("inventory +"..det.count)
				else -- got unconcerned item
					saveDir(turn.lateral * drop())()
				end
				sleep(0.01)
			end
		end)()
	end

	local inventoryCount = {
		isDirty = true,
		lastReport = 0,
	}
	local inventoryCheckCo = function()
		while true do
			local ev = { os.pullEvent("turtle_inventory") } -- no useful information :(
			inventoryCount.isDirty = true
		end
	end
	local updateInventoryCo = function()
		local info = {
			pos = stationDef.pos,
			dir = stationDef.dir,
			itemType = stationDef.itemType,
		}
		while true do
			sleep(5)
			if inventoryCount.isDirty then
				local cnt = slot.count(stationDef.itemType)
				if cnt ~= inventoryCount.lastReport then
					print("current count: "..cnt)
					info.itemCount = cnt
					local ok, res = swarm.client.request("swarm.services.updateStation("..literal(info)..")")()
					if ok then
						inventoryCount.isDirty = false
					else
						log.warn("[provider] failed to report inventory info: "..literal(res))
					end
				end
			end
		end
	end

	registerCo()
	para_(produceCo, inventoryCheckCo, updateInventoryCo)()
end)

serveAsRequester = mkIO(function()
end)

serveAsUnloader = mkIO(function()
	local stationDef = {
		pos = workState.pos - workState:aimingDir(),
		dir = workState:aimingDir(),
		itemType = det.name,
		limitation = 0,
		deliverPriority = 0, --passive provider
	}
	return swarm.client.request("swarm.services.registerStation("..literal(stationDef)..")")()
end)

--registerActiveProvider = mkIO(function()
--	local stationDef = {
--		pos = gpsPos(),
--		limitation = 0,
--		deliverPriority = 98, --passive provider
--	}
--	rednet.send({
--	})
--end)
--
--registerBuffer = mkIO(function()
--	local stationDef = {
--		pos = gpsPos(),
--		reservation = 15,
--		restockPriority = 89,
--	}
--	rednet.send({
--	})
--end)

--registerRequester = mkIO(function()
--	local stationDef = {
--		pos = gpsPos(),
--		reservation = 15,
--		restockPriority = 99,
--	}
--	rednet.send({
--	})
--end)

requestStation = mkIOfn(function(itemName, itemCount, startPos, fuelLeft)
	itemCount = default(0)(itemCount)
	startPos = default(workState.pos)(startPos)
	fuelLeft = default(turtle.getFuelLevel())(fuelLeft)
	return swarm.client.request("swarm.services.requestStation("..literal(itemName, itemCount, startPos, fuelLeft)..")")()
end)

requestFuelStation = mkIOfn(function(nStep)
	for i, name in ipairs(swarm._state.asFuel) do
		local requestSucc, res = requestStation(name, 0)() --TODO: calc fuel number
		if not requestSucc then
			log.warn("[requestFuelStation] request failed: "..res)
		else
			local ok, st = unpack(res)
			if ok then
				return true, st
			end
		end
	end
	return false, "no fuel station available, swarm._state.asFuel = "..literal(swarm._state.asFuel)
end)

requestUnloadStation = mkIOfn(function(spaceCount)
	return O and {pos = O + B + U * 2, dir = B}
end)

-- | a tool to visit station robustly
-- , will unregister bad stations and try to get next
-- , will wait for user help when there is no more station available
-- , will wait for manually move when cannot reach a station
-- , argument: { reqStation, beforeLeave, beforeRetry, beforeWait, waitForUserHelp }
function _robustVisitStation(opts)
	local gotoStation
	gotoStation = function(triedTimes, singleTripCost)
		local ok, station = opts.reqStation(triedTimes, singleTripCost)
		if not ok then
			return false, triedTimes, singleTripCost
		end
		-- got fresh station here
		opts.beforeLeave(triedTimes, singleTripCost, station)
		local leavePos, fuelBeforeLeave = workState.pos, turtle.getFuelLevel()
		with({workArea = false})(visitStation(station))()
		-- arrived station here
		local cost = math.max(0, fuelBeforeLeave - turtle.getFuelLevel())
		local singleTripCost_ = singleTripCost + cost
		if not isStation() then -- the station is not available
			opts.beforeRetry(triedTimes, singleTripCost, station, cost)
			unregisterStation(station)
			return gotoStation(triedTimes + 1, singleTripCost_)
		else
			return true, triedTimes, singleTripCost_
		end
	end
	local succ, triedTimes, singleTripCost = gotoStation(1, 0)
	if not succ then
		opts.beforeWait(triedTimes, singleTripCost, station)
		race_(retry(delay(gotoStation, triedTimes + 1, singleTripCost)), delay(opts.waitForUserHelp, triedTimes, singleTripCost, station))()
		return true
	end
end

