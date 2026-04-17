local Players = game:GetService("Players")

return function(handler)
	local function onCharacterAdded(player: Player, character: Model)
		handler:addServerEvent(player, { tag = "CharacterSpawn" })
		local humanoid = character:WaitForChild("Humanoid") :: Humanoid
		humanoid.Died:Connect(function()
			handler:addServerEvent(player, { tag = "CharacterDeath" })
		end)
	end

	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function(character)
			onCharacterAdded(player, character)
		end)
	end)

	-- Handle players already in-game (e.g. Studio testing with existing characters)
	for _, player in Players:GetPlayers() do
		player.CharacterAdded:Connect(function(character)
			onCharacterAdded(player, character)
		end)
		if player.Character then
			task.spawn(onCharacterAdded, player, player.Character)
		end
	end
end
