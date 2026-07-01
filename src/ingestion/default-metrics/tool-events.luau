local ACTIVATED_COOLDOWN = 1 -- seconds; suppresses rapid-fire repeat activations (e.g. automatic weapons)

return function(handler, _services)
	local Players = (_services and _services.Players) or game:GetService("Players")
	local getTime = (_services and _services.getTime) or os.clock

	local connected = {} -- [Tool] = true, prevents double-connecting when tool moves between backpack/character
	local lastActivated = {} -- [Tool] = timestamp

	local function connectTool(player: Player, tool: Tool)
		if connected[tool] then return end
		connected[tool] = true
		tool.Equipped:Connect(function()
			handler:addServerEvent(player, { tag = "ToolEquipped", custom = { toolName = tool.Name } })
		end)
		tool.Activated:Connect(function()
			local now = getTime()
			if lastActivated[tool] and (now - lastActivated[tool]) < ACTIVATED_COOLDOWN then return end
			lastActivated[tool] = now
			handler:addServerEvent(player, { tag = "ToolActivated", custom = { toolName = tool.Name } })
		end)
		tool.Destroying:Connect(function()
			connected[tool] = nil
			lastActivated[tool] = nil
		end)
	end

	local function scanContainer(player: Player, container: Instance)
		for _, item in container:GetChildren() do
			if item:IsA("Tool") then connectTool(player, item) end
		end
		container.ChildAdded:Connect(function(item)
			if item:IsA("Tool") then connectTool(player, item) end
		end)
	end

	local function watchPlayer(player: Player)
		task.spawn(function()
			local backpack = player:WaitForChild("Backpack")
			if not backpack then return end
			scanContainer(player, backpack)
		end)
		player.CharacterAdded:Connect(function(character)
			scanContainer(player, character)
		end)
		if player.Character then
			scanContainer(player, player.Character)
		end
	end

	Players.PlayerAdded:Connect(watchPlayer)
	for _, player in Players:GetPlayers() do
		watchPlayer(player)
	end
end
