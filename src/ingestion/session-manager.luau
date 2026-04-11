local HttpService = game:GetService("HttpService")
local Players     = game:GetService("Players")

-- Tracks a unique session UUID per player for the duration of their visit.

local SessionManager = {}
SessionManager.__index = SessionManager

function SessionManager.new()
	local self = setmetatable({}, SessionManager)
	self.sessionStore = {} -- [Player] = string UUID

	Players.PlayerRemoving:Connect(function(player)
		self.sessionStore[player] = nil
	end)

	return self
end

function SessionManager:getSessionId(player: Player): string
	local session = self.sessionStore[player]
	if not session then
		session = HttpService:GenerateGUID(false)
		self.sessionStore[player] = session
	end
	return session
end

return SessionManager
