local STATE_COOLDOWN = 1 -- seconds; suppresses same-state repeat fires (e.g. landing bounces)

local TRACKED_STATES = {
	[Enum.HumanoidStateType.Landed]   = "Landed",
	[Enum.HumanoidStateType.Freefall] = "Freefall",
	[Enum.HumanoidStateType.Climbing] = "Climbing",
	[Enum.HumanoidStateType.Swimming] = "Swimming",
	[Enum.HumanoidStateType.Seated]   = "Seated",
}

return function(handler, _services)
	local Players = (_services and _services.Players) or game:GetService("Players")
	local getTime = (_services and _services.getTime) or os.clock

	local function watchCharacter(player: Player, character: Model)
		local humanoid  = character:WaitForChild("Humanoid") :: Humanoid
		local lastFired = {} -- [stateName] = timestamp; resets each character spawn

		humanoid.StateChanged:Connect(function(_old, new)
			local stateName = TRACKED_STATES[new]
			if not stateName then return end

			local now = getTime()
			if lastFired[stateName] and (now - lastFired[stateName]) < STATE_COOLDOWN then return end
			lastFired[stateName] = now

			local root = character:FindFirstChild("HumanoidRootPart")
			handler:addServerEvent(player, {
				tag      = "HumanoidStateChange",
				position = root and root.Position or nil,
				custom   = { state = stateName },
			})
		end)
	end

	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function(character)
			watchCharacter(player, character)
		end)
	end)

	for _, player in Players:GetPlayers() do
		player.CharacterAdded:Connect(function(character)
			watchCharacter(player, character)
		end)
		if player.Character then
			task.spawn(watchCharacter, player, player.Character)
		end
	end
end
