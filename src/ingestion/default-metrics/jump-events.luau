return function(handler, _services)
	local Players = (_services and _services.Players) or game:GetService("Players")

	local function watchCharacter(player: Player, character: Model)
		local humanoid = character:WaitForChild("Humanoid") :: Humanoid
		humanoid.Jumping:Connect(function(active)
			if active then
				handler:addServerEvent(player, { tag = "PlayerJump" })
			end
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
