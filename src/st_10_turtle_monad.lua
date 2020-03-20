--------- the Turtle Monad ( ReaderT workMode (StateT workState IO) ) ----------

if turtle then

	workMode = {
		verbose = true, -- whether broadcast verb log
		destroy = 1, -- whether auto dig when move blocked: 0:no dig, 1:dig cheap items only, 2:dig all non-protected
		violence = false, -- whether auto attack when move blocked
		detour = true, -- whether to detour when move.to or move.go blocked
		retrySeconds = 2, -- seconds to retry before fail back when move blocked by other turtles
		workArea = false, -- an electric fence
		asFuel = false, -- when false, use every possible thing as fuel
		keepItems = 2, -- 0:always drop, 1:only keep valuable items, 2:keep non-cheap items, 3:keep all
		allowInterruption = true, -- whether allow turtle interrupt current task to refuel or unload or fetch
		pinnedSlot = {}, -- local stations, like {itemType = "minecraft:coal", stackLimit = 64, lowBar = 2, highBar = 64, depot = {pos, dir}}
		--backpackWhiteList = {}, -- not used yet
		--backpackBlackList = {}, -- not used yet
	}

	workState = {
		gpsCorrected = false,
		pos = vec.zero, -- current pos
		facing = const.dir.E, -- current facing direction, const.dir.N/S/W/E
		aiming = 0, -- 0:front, 1:up, -1:down
		fuelStation = false,
		unloadStation = false,
		isRefueling = false,
		isUnloading = false,
		isFetching = false,
		cryingFor = false,
		isRunningSwarmTask = false,
		moveNotCommitted = false,
		back = false, -- save pos, facing and aiming here before interrupt
	}
	O = vec.zero -- pos when process begin, this init value is used before gps corrected

	setmetatable(workState, {__index = {
		aimingDir = function()
			if workState.aiming == 0 then return workState.facing
			else return vec(0, workState.aiming, 0) end
		end,
		lateralDir = function()
			if workState.aiming == 0 then return const.dir.U
			else return workState.facing end
		end,
		preferDirections = function()
			local d0 = workState.facing
			local d1 = leftSide(d0)
			return {U, d0, d1, leftSide(d1), rightSide(d0), D}
		end,
	}})

	-- | run io with specified workMode fields
	-- , NOTE: use `false` as a placeholder for `nil`
	with = function(wm_patch)
		return function(io)
			return mkIO(function()
				local _wm = workMode
				workMode = deepcopy(_wm)
				for k, v in pairs(wm_patch) do
					if workMode[k] ~= nil then
						workMode[k] = v
					else
						error("[with] workMode has no such field: `"..k.."`")
					end
				end
				r = { io() }
				workMode = _wm
				return unpack(r)
			end)
		end
	end

	-- get current pos and posture
	getPosp = mkIO(function()
		return {
			pos = workState.pos,
			facing = workState.facing,
			aiming = workState.aiming,
		}
	end)

end
