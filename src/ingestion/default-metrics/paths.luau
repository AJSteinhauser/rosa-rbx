local SAMPLE_RATE         = 0.05
local DISTANCE_THRESHOLD  = 25   -- studs
local TELEPORT_THRESHOLD  = 100  -- studs; jump beyond this = new path segment
local DIRECTION_THRESHOLD = 35   -- degrees
local MIN_TAG_INTERVAL    = 0.1  -- seconds between emitted _PathTag events

return function(handler, userConfig, _services)
	local Players     = (_services and _services.Players)     or game:GetService("Players")
	local RunService  = (_services and _services.RunService)  or game:GetService("RunService")
	local HttpService = (_services and _services.HttpService) or game:GetService("HttpService")
	local getTime     = (_services and _services.getTime)     or os.clock
	local random      = (_services and _services.random)      or math.random

	local tracked = {} -- [Player] = { lastPos, lastDir, lastTagTime, segmentId }

	local function beginTracking(player: Player)
		local pos = userConfig.getPosition(player)
		if not pos then return end
		local segmentId = HttpService:GenerateGUID(false)
		tracked[player] = { lastPos = pos, lastDir = nil, lastTagTime = getTime(), segmentId = segmentId }
		handler:addServerEvent(player, { tag = "_PathStart", position = pos, custom = { segmentId = segmentId } })
	end

	RunService.Heartbeat:Connect(function()
		local now = getTime()
		for player, state in tracked do
			local currentPos = userConfig.getPosition(player)
			if not currentPos then continue end

			local delta    = currentPos - state.lastPos
			local distance = delta.Magnitude

			if distance >= TELEPORT_THRESHOLD then
				handler:addServerEvent(player, { tag = "_PathTag", position = state.lastPos, custom = { segmentId = state.segmentId } })
				local segmentId   = HttpService:GenerateGUID(false)
				state.segmentId   = segmentId
				state.lastPos     = currentPos
				state.lastDir     = nil
				state.lastTagTime = now
				handler:addServerEvent(player, { tag = "_PathStart", position = currentPos, custom = { segmentId = segmentId } })
				continue
			end

			local directionChanged = false
			if distance > 0.1 and state.lastDir then
				local dot      = math.clamp(state.lastDir:Dot(delta.Unit), -1, 1)
				local angleDeg = math.deg(math.acos(dot))
				directionChanged = angleDeg >= DIRECTION_THRESHOLD
			end

			if distance >= DISTANCE_THRESHOLD or directionChanged then
				state.lastPos  = currentPos
				state.lastDir  = distance > 0.1 and delta.Unit or state.lastDir
				if now - state.lastTagTime >= MIN_TAG_INTERVAL then
					handler:addServerEvent(player, { tag = "_PathTag", position = currentPos, custom = { segmentId = state.segmentId } })
					state.lastTagTime = now
				end
			end
		end
	end)

	local inStudio = RunService:IsStudio()

	local function watchPlayer(player: Player)
		if not inStudio and random() >= SAMPLE_RATE then return end
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
