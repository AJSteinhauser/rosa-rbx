local Players = game:GetService("Players")

return function(handler)
	local joinTimes = {} -- [Player] = os.time() at join

	Players.PlayerAdded:Connect(function(player)
		joinTimes[player] = os.time()
		handler:addServerEvent(player, { tag = "PlayerJoin" })
	end)

	Players.PlayerRemoving:Connect(function(player)
		local duration = joinTimes[player] and (os.time() - joinTimes[player]) or nil
		joinTimes[player] = nil
		handler:addServerEvent(player, {
			tag    = "PlayerLeave",
			custom = { sessionDuration = duration },
		})
	end)
end
