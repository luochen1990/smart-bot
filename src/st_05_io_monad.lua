----------------------------------- IO Monad -----------------------------------

-- | mkIO : (a... -> b, a...) -> IO b
mkIO, mkIOfn, isIO = (function()
	local _ioMetatable = {}
	local _mkIO
	_mkIO = function(f, ...)
		local args = {...}
		local io = {
			run = function() return f(unpack(args)) end,
			pipe = function(io1, f2) return _mkIO(function() return f2(io1.run()).run() end) end, -- similar to `bind` or `>>=` in haskell
		}
		setmetatable(io, _ioMetatable)
		return io
	end
	local _mkIOfn = function(f)
		return function(...) return _mkIO(f, ...) end
	end
	_ioMetatable.__len = function(io) return _mkIO(function() local r; repeat r = io.run() until(r); return r end) end -- use `#io` as `rep(io)`, only works on lua5.2+
	_ioMetatable.__call = function(io, ...) return io.run(...) end
	_ioMetatable.__pow = function(io, n) return replicate(n)(io) end -- replicate a few times
	_ioMetatable.__add = function(io1, io2) return _mkIO(function() return io1.run() or io2.run() end) end -- if io1 fail then io2
	_ioMetatable.__mul = function(io1, io2) return _mkIO(function() return io1.run() and io2.run() end) end -- if io1 succ then io2
	_ioMetatable.__div = function(io1, io2) return _mkIO(function() r = io1.run(); io2.run(); return r end) end -- `<*` in haskell
	_ioMetatable.__unm = function(io) return _mkIO(function() return not io.run() end) end -- use `-io` as `fmap not io` in haskell
	local _isIO = function(v)
		return type(v) == "table" and getmetatable(v) == _ioMetatable
	end
	return _mkIO, _mkIOfn, _isIO
end)()

-- | pure : a -> IO a
pure = function(x) return mkIO(function() return x end) end

-- | fmap : (a -> b) -> IO a -> IO b
fmap = function(f)
	return markIOfn("fmap(f)(io)")(mkIOfn(function(io) return f(io()) end))
end

-- | try : IO a -> IO Bool
try = function(io)
	return markIO("try(io)")(mkIO(function() io(); return true end))
end

-- | the internal implementation of retryWithTimeout and retry
_retryWithTimeout = function(iof, totalTimeout, opts)
	local sleepIntervalInit = default(0.1)(opts and opts.sleepIntervalInit)
	local sleepIntervalIncreaseRatio = default(1.01)(opts and opts.sleepIntervalIncreaseRatio)
	local sleepIntervalMax = default(300)(opts and opts.sleepIntervalMax)
	local singleTimeoutInit = default(0.1)(opts and opts.singleTimeoutInit)
	local singleTimeoutIncreaseRatio = default(1.01)(opts and opts.singleTimeoutIncreaseRatio)
	local singleTimeoutMax = default(300)(opts and opts.singleTimeoutMax)

	return mkIO(function()
		local singleTimeout = singleTimeoutInit
		local r = { iof(singleTimeout)() } -- first try
		if r[1] then return unpack(r) end -- direct success
		local sleepInterval = sleepIntervalInit
		--local waitedSeconds = 0.0
		local startTime = os.clock()
		while true do
			local sleepSeconds
			if totalTimeout == nil then -- not inf (i.e. nil)
				sleepSeconds = sleepInterval * math.random()
			else -- totalTimeout ~= nil
				local timeLeft = (startTime + totalTimeout - os.clock())
				if timeLeft <= 0 then break end -- exit while loop
				sleepSeconds = math.min(timeLeft, sleepInterval * math.random())
			end
			sleep(sleepSeconds)
			r = { iof(singleTimeout)() }
			if r[1] then return unpack(r) end
			sleepInterval = math.min(sleepIntervalMax, sleepInterval * sleepIntervalIncreaseRatio)
			singleTimeout = math.min(singleTimeoutMax, singleTimeout * singleTimeoutIncreaseRatio)
		end
		return unpack(r) -- return result of last failed try
	end)
end

-- | retry an action which can specify timeout
-- ,  Usage 1: Seconds -> (Seconds -> IO (Maybe a)) -> IO (Maybe a), e.g. io = retryWithTimeout(totalTimeout)(iof)
-- ,  Usage 2: (Seconds -> IO (Maybe a)) -> IO a
retryWithTimeout = function(arg, opts)
	if type(arg) == "number" then
		return markIOfn("retryWithTimeout(totalTimeout, opts)(iof)")(function(iof)
			return _retryWithTimeout(iof, arg, opts)
		end)
	else -- the `retryWithTimeout(iof)` usage
		return markIO("retryWithTimeout(iof)")(_retryWithTimeout(arg, nil, opts))
	end
end

-- | retry an io which might fail
-- , Usage 1: Seconds -> IO (Maybe a) -> IO (Maybe a)
-- , Usage 2: IO (Maybe a) -> IO a
retry = function(arg, opts)
	if type(arg) == "number" then
		return markIOfn("retry(totalTimeout, opts)(io)")(function(io)
			return _retryWithTimeout(function(t) return io end, arg, opts)
		end)
	else -- the `retry(io)` usage
		return markIO("retry(io)")(_retryWithTimeout(function(t) return arg end, nil, opts))
	end
end

-- | replicate : Int -> IO a -> IO Int
replicate = function(n)
	return function(io)
		return markIO("replicate(n)(io)")(mkIO(function()
			local c = 0
			for i = 1, n do
				local r = io()
				if r then c = c + 1 end
			end
			return c
		end))
	end
end

-- | repeatUntil : (a -> Bool) -> IO a -> IO a
repeatUntil = function(stopCond)
	return markIOfn("repeatUntil(stopCond)(io)")(function(io)
		return mkIO(function() local c = 0; while not stopCond(io()) do c = c + 1 end; return c end)
	end)
end

-- | repeat until fail,  (use `rep(-io)` as repeat until success)
-- , return successfully repeated times
rep = markIOfn("rep(io)")(function(io)
	return mkIO(function() local c = 0; while io() do c = c + 1 end; return c end)
end)

echo = markIOfn("echo(...)")(mkIOfn(function(...)
	for _, expr in ipairs({...}) do
		local ok, res = eval(expr)
		if not ok then error(res.msg) end
		printC(colors.gray)("[echo] "..expr.." ==>", show(unpack(res)))
	end
	return true
end))

