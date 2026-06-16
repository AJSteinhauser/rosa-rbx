local Players = game:GetService("Players")

-- Detects and caches each player's platform (PC, Mobile, Console, VR).
--
-- Flow:
--   Server calls getPlatform(player) → yields if platform unknown
--   Server fires "getPlatform" to client via RemoteEvent
--   Client receives it, fires back Enum.Platform
--   Server resumes the waiting coroutine with the result
--
-- NOTE: Client-side listener is set up in EventIngestionHandler.

local PlayerPlatformManager = {}
PlayerPlatformManager.__index = PlayerPlatformManager

function PlayerPlatformManager.new()
	local self = setmetatable({}, PlayerPlatformManager)
	self.platformCache   = {} -- [Player] = Enum.Platform
	self.pendingRequests = {} -- [Player] = coroutine thread

	-- RemoteEvent parented to this module so the client can find it via WaitForChild
	local remote = Instance.new("RemoteEvent")
	remote.Name   = "PlatformManager"
	remote.Parent = script
	self.remoteEvent = remote

	-- When the client responds with their platform
	remote.OnServerEvent:Connect(function(player, platform)
		self.platformCache[player] = platform

		local thread = self.pendingRequests[player]
		if thread then
			self.pendingRequests[player] = nil
			task.spawn(thread, platform)
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		self.platformCache[player] = nil
		local thread = self.pendingRequests[player]
		if thread then
			self.pendingRequests[player] = nil
			task.spawn(thread, "Unknown")
		end
	end)

	return self
end

-- Yields the calling coroutine until the platform is known (max 10 seconds).
function PlayerPlatformManager:getPlatform(player: Player)
	local cached = self.platformCache[player]
	if cached then
		return cached
	end

	local thread = coroutine.running()
	self.pendingRequests[player] = thread

	-- Timeout: if the client doesn't respond within 10s, fall back to "Unknown"
	task.delay(10, function()
		if self.pendingRequests[player] == thread then
			self.pendingRequests[player] = nil
			warn("Platform request timed out for: " .. player.Name .. " — defaulting to Unknown")
			task.spawn(thread, "Unknown")
		end
	end)

	self.remoteEvent:FireClient(player, "getPlatform")

	local platform = coroutine.yield()
	return platform
end

return PlayerPlatformManager
