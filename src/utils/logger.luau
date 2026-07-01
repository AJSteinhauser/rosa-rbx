-- Prefixes every message with [Rosa] so log output is identifiable regardless of
-- level. Roblox has no built-in "info" level (just print/warn/error) — info() below
-- is print() under the hood.

local PREFIX = "[Rosa]"

return {
	info = function(message: string)
		print(PREFIX .. " " .. message)
	end,
	warn = function(message: string)
		warn(PREFIX .. " " .. message)
	end,
	error = function(message: string)
		-- level 2: attribute the error to Logger.error's caller, not this line
		error(PREFIX .. " " .. message, 2)
	end,
}
