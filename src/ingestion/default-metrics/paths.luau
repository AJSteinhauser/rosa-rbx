local Players    = game:GetService("Players")
local RunService = game:GetService("RunService")

local SAMPLE_RATE         = 0.1
local DISTANCE_THRESHOLD  = 10   -- studs
local TIME_FALLBACK       = 4    -- seconds
local DIRECTION_THRESHOLD = 35   -- degrees

return function(handler, userConfig)
	local tracked = {} -- [Player] = { lastPos, lastDir, lastTime }

	local function beginTracking(player: Player)
		local pos = userConfig.getPosition(player)
		if not pos then return end
		tracked[player] = { lastPos = pos, lastDir = nil, lastTime = os.clock() }
		handler:addServerEvent(player, {
			tag    = "_PathStart",
		})
	end

	RunService.Heartbeat:Connect(function()
		local now = os.clock()
		for player, state in tracked do
			local currentPos = userConfig.getPosition(player)
			if not currentPos then continue end

			local delta    = currentPos - state.lastPos
			local distance = delta.Magnitude

			local directionChanged = false
			if distance > 0.1 and state.lastDir then
				local dot      = math.clamp(state.lastDir:Dot(delta.Unit), -1, 1)
				local angleDeg = math.deg(math.acos(dot))
				directionChanged = angleDeg >= DIRECTION_THRESHOLD
			end

			local elapsed = now - state.lastTime
			if distance >= DISTANCE_THRESHOLD or directionChanged or elapsed >= TIME_FALLBACK then
				handler:addServerEvent(player, { tag = "_PathTag" })
				state.lastPos  = currentPos
				state.lastDir  = distance > 0.1 and delta.Unit or state.lastDir
				state.lastTime = now
			end
		end
	end)

	local function watchPlayer(player: Player)
		if math.random() >= SAMPLE_RATE then return end
		player.CharacterAdded:Connect(function()
			task.wait(1)
			beginTracking(player)
		end)
		if player.Character then
			task.spawn(beginTracking, player)
		end
	end

	Players.PlayerAdded:Connect(watchPlayer)
	Players.PlayerRemoving:Connect(function(player) tracked[player] = nil end)

	for _, player in Players:GetPlayers() do
		watchPlayer(player)
	end
end
