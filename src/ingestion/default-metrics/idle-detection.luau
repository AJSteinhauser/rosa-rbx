local MOVEMENT_THRESHOLD   = 2   -- studs; movement above this resets idle timer
local DEFAULT_IDLE_SECONDS = 15

return function(handler, userConfig, _services)
	local Players    = (_services and _services.Players)    or game:GetService("Players")
	local RunService = (_services and _services.RunService) or game:GetService("RunService")
	local getTime    = (_services and _services.getTime)    or os.clock

	local idleThreshold = (
		userConfig.defaultMetrics
		and userConfig.defaultMetrics.idleThresholdSeconds
	) or DEFAULT_IDLE_SECONDS

	local states = {} -- [Player] = { lastPos, idleSince, fired }

	local function beginTracking(player: Player)
		local pos = userConfig.getPosition(player)
		if not pos then return end
		states[player] = { lastPos = pos, idleSince = getTime(), fired = false }
	end

	RunService.Heartbeat:Connect(function()
		local now = getTime()
		for player, state in states do
			local pos = userConfig.getPosition(player)
			if not pos then continue end

			if (pos - state.lastPos).Magnitude >= MOVEMENT_THRESHOLD then
				state.lastPos   = pos
				state.idleSince = now
				state.fired     = false
			elseif not state.fired and (now - state.idleSince) >= idleThreshold then
				state.fired = true
				handler:addServerEvent(player, {
					tag      = "PlayerIdle",
					quantity = math.floor(now - state.idleSince),
				})
			end
		end
	end)

	local function watchPlayer(player: Player)
		player.CharacterAdded:Connect(function()
			task.wait(1)
			beginTracking(player)
		end)
		if player.Character then
			task.spawn(beginTracking, player)
		end
	end

	Players.PlayerAdded:Connect(watchPlayer)
	Players.PlayerRemoving:Connect(function(player) states[player] = nil end)

	for _, player in Players:GetPlayers() do
		watchPlayer(player)
	end
end
