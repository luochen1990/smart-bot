---------------------------------- telnet repl ---------------------------------

_telnet_repl_config = { --this is only a prototype, some fields not filled yet.
	inputHandler = nil,
	readOnlyEnv = _ST,
	abortHandler = nil,
	abortEventListener = nil,
	historyLimit = 100,
	historyFilePath = "/.st_telnet_history",
	style = {
		helloText = "Welcome to Telnet",
		helloColor = colors.lime,
		tipsText = "(This is Telnet, input 'exit' to exit, input 'help' for more help)",
		helpText = [[
		help -- print this help text
		exit -- exit this REPL
		Ctrl+L -- clean screen
		Ctrl+U -- clean current line
		]],
		tipsColor = colors.gray,
		promptText = "telnet> ",
		promptColor = colors.orange,
		commandColor = colors.lightBlue,
		resultColor = colors.white,
		errorStackColor = colors.gray,
		runCommandDefaultColor = colors.lightGray,
	},
}

telnet = function(computerId)
	if not computerId then
		local res = _stComputers.broadcast("os.getComputerLabel()")()
		for _, v in ipairs(res) do
			print(literal(v))
		end
	else
		_telnet_repl_config.style.promptText = "telnet "..computerId.."> "
		_telnet_repl_config.inputHandler = function(cmd, _env)
			local winner, rst = race(_stComputers.send(computerId, cmd), displayLog(computerId))()
			assert(winner == 1, "[telnet] displayLog should not terminate")
			return unpack(rst)
		end
		local repl = replTool.buildRepl(_telnet_repl_config)
		repl.start()
	end
end

